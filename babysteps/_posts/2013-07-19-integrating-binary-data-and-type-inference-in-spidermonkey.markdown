---
layout: post
title: "Integrating binary data and type inference in SpiderMonkey"
date: 2013-07-19 06:42
comments: true
categories: [PJs, JS]
---
Since the new version of PJS is going to be based on binary data, we
are going to need to have a well-optimized binary data implementation.
Nikhil Marathe has prepared an [initial implementation][578700], but
it is limited to the interpreter. I am looking now at how to integrate
binary data into the JIT. The goal is to have accesses get compiled to
very efficient generated code. In this blog post, I specifically want
to cover the plan for integrating our type inference with binary data.

<!-- more -->

### Metatypes, descriptors, instances

Let's cover some terminology. In binary data, users create *type
descriptors* as follows:

```javascript
var PointType = new StructType({x: float64, y: float64});
var LineType = new StructType({start: PointType, end: PointType});
```

The built-ins for scalars (e.g., `float64`) are also type
descriptors. In contrast, the built-ins `StructType` and `ArrayType`
are called *metatypes* because they do not themselves represent types
but rather the means to define a type.

It is also possible to create types that include non-scalar data.  For
example, here is a struct that might be used for a binary tree:

```javascript
var TreeType = new StructType({value: Any,
                               left: Object,
                               right: Object});
```

Once you have a type descriptor, you can create instances of that
type descriptor using the `new` operator:

```javascript
var origin = new PointType({x: 0, y: 0});
var unit = new PointType({x: 1, y: 1});
var line = new LineType({start: origin, end: unit});
```

You can access the properties of these instances just as you would
expect:

```javascript
var length = Math.sqrt(Math.pow(line.end.x - line.start.x, 2) +
                       Math.pow(line.end.y - line.start.y, 2));
```                           

The aim of this work is to optimize an expression like `line.end.y` so
that it can be compiled into a simple load of the relevant data.

### Canonical type representations

Each time that a new type descriptor is created, we will create an
internal, canonical representation of the type it defines. So,
for example, if I created types like so:

```javascript
var FloatPointType1 = new StructType({x: float64, y: float64});
var FloatPointType2 = new StructType({x: float64, y: float64});
var IntPointType = new StructType({x: uint32, y: uint32});
```

There would be two canonical type representations created, one for
both `FloatPointType1` and `FloatPointType2` (which both describe the
same type) and one for `IntPointType`. These objects are never exposed
to the user. We could either reference count them or make them
collectable by the GC; in the latter case, it might be easiest to make
them be actual JS objects, albeit ones used in a very specialized way.

### Links from type objects to type representations

Next we will augment the TI type objects for descriptors and instances
to contain a pointer to one of these canonical type representations.
This means that when the JIT compiler encounters an expression like
`point.x`, it can examine the type set for the object `point` to
find out both that `line` is a binary data instance and its
representation.

#### Scalar property access

The simple case is when are accessing a scalar property. For example,
imagine something like `point.x` where `point` is an instance of the
following type descriptor:

```javascript
var PointType = new StructType({x: float64, y: float64});
```

In this case, the JIT compiler can extract from the type object for
`point` that the property `x` is a `float64` and that it is at offset
0. It can then compile a direct access to load a float from that
memory location. Presumably this will require a few extra MIR, such as
`MLoadFloat(x, 0)` which extracts a float out of the binary data
instance `x` at offset 0.

#### Any and object properties

As mentioned earlier, type descriptors can also include
`any` and `object` properties, such as this binary tree example;

```javascript
var TreeType = new StructType({value: Any,
                               left: Object,
                               right: Object});
```

We can handle these properties in one of two ways. The first option is
to always add barriers on every access to an object or any
property. This effectively doesn't make any use of TI information.

The second option is to treat any/object properties the same way that
we treat properties on normal objects. We can record a type set for
each object property in the instance type object, and then add
barriers as we normally would. In some cases, this will allow us to
drop type barriers in the jitted code, but it shouldn't make a large
difference in the performance otherwise. Still, if it's easy to do, it
seems worth it to record type sets for object properties.

#### Chained property access

Remember though that our goal is to enable something like
`line.end.y`. This is a bit more complex, because the property `end`
is a property of complex (non-scalar) type. to us, `line.end.y` looks
like one compound property access, but in the JS interpreter, it is
actually *two* property accesses, one after the other.  In other
words, an expression like `var y = line.end.y` is equivalent to a bit
of code like this:

```javascript
var tmp = line.end;
var y = tmp.y;
```

Here, the first access, `line.end`, returns a new, *derived instance*
for the point `end`. This derived instance aliases the original
line. So, at runtime, you could depict the objects and the runtime
memory as follows:

        line
          |
          +--->  +--------+
                 | .start |
        tmp      |  .x    |
          |      |  .y    |
          +--->  | .end   |
                 |  .x    |
                 |  .y    |
                 +--------+

Of course, we'd like the JIT to convert these two distinct property
accesses into one load, assuming it has adequate type information.
The next few paragraphs lay out my plan for making this happen. I
assume a certain amount of familiarity with IonMonkey, or at least
compilers and SSA representations.

When the JIT processes the first property access, `var tmp =
line.end`, it will observe from the type set of `line` that `end` is a
fetch of a complex property, causing it to generate a special MIR
opcode, distinct from a normal get property. Let's denote this as
`MDerivedStruct(line, PointRepr, 16)`, meaning that it will create a
derived struct instance with the type representation `PointRepr` at
offset 8. Here by `PointRepr` I am referring to this internal
representation of the type descriptor that is contained in the type
object. The effect of this MIR is the same as the typical
`MGetProperty(line, "end")`, except that it provides more information
about what kind of kind of property will be fetched (such opcodes are
also known not to have side effects, unlike general property
accesses).

When the JIT then processes the next property access, `tmp.y`, it will
observe the MIR opcode that defines `tmp`. If this MIR opcode is
a `MDerivedStruct`, we can match the property `x` against `PointRepr`
and generate the appropriate direct load of the scalar value.

That means that the JIT will generate the following MIR:

```javascript
var tmp = line.end    >>      tmp = MDerivedStruct(line, PointRepr, 16);
var y = tmp.y         >>      x = MLoadFloat(line, 24)
```

Note that the value `tmp` is not used anywhere; the definition of `x`
bypassed the temporary and loaded the scalar value directly from
`line`. The definition of `tmp` can then be removed by dead code
elimination.

In the case where the access to the complex property *is* the end
goal, such as an expression like `foo = line.end`, then the
`MDerivedStruct` will simply remain in the program. The generated code
can then call directly into the runtime functions for creating derived
structs (it could even just use the unoptimized, normal path in the
interpreter, but that's suboptimal).

##### The methods `get` and `set`

One implication of the design for accesses like `line.end.y` is that
if the type information is not precise, we will generate an
intermediate object, even if it seems unnecessary. For example, this
could occur if `line` is *sometimes* a normal JS object and
*sometimes* a binary data instance, or if it may be one of many kinds
of binary data instances that have distinct types.

Optimizing these cases is more difficult and doesn't seem particularly
important; the former is particularly hard, as it may be that the
intermediate value is necessary. To optimize that would either require
generalizing our inline caching mechanism to handle multiple property
accesses (yuck) or generating a kind of "if-else" in the generated
code. Either way, more work than I think is necessary for what seems
to be a corner case.

However, there is also an alternate means to avoid
allocation. Programmers can instead use the `get` method that all
binary data instances offer.  So, `line.end.y` could be rewritten
`line.get("end", "y")`. Naturally, the JIT will observe calls to `get`
and, if it can determine that `line` is a binary data object, and the
arguments are constants, it will optimize `line.get("end", "y")` to
produce a simple load. But even if it's information is lacking, the
runtime fallback for `get` can avoid allocating. Of course, this may
or may not be faster, depending on how optimized the alloction
pathways in the engine are.

### Type object canonicalization

Normally, whenever there is some code like `new Foo`, we will produce
one type object per value of `Foo` (since `Foo` is typically a global
function definition, this means one type object). In the case of
binary data, it is plausible that the user defines multiple equivalent
type descriptors (e.g., `FloatPointType1` and `FloatPointType2` from
my earlier examples). In such cases, we could canonicalize the type
objects so that there is exactly one type object per unique type
representation. Similarly, we could canonicalize the type objects for
the instances, since having multiple type objects isn't particularly
useful.

### Adding handles

For simplicity, I didn't discuss *handles*, which are effectively
binary data pointers. A handle lets you get a pointer to a subpiece of
another binary data object. This is *similar* to the derived objects I
mentioned earlier, except that (1) handles can be used to get a
pointer into a field or array element of any type, not just a complex
type like a struct; (2) handles can be reused and made to point at
other locations. Handles are mostly intended to be used in APIs that
wish to hand out a pointer to some subportion of a data structure.
For example, the [plan for PJS][pjs] is to use handles when
constructing arrays of structs or compound types in parallel to allow
the callback to mutate the data in place rather than returning it
(which would necessitate a superfluous copy and allocation). Anyway,
integrating handles into this scheme is straightforward: like
instances and descriptors, type objects for handles would be
associated with the type representation of what they point at.

### Grungy implementation detail: saving bytes

This section will probably not be of interest to you unless you are a
SpiderMonkey developer, and perhaps not even then.  It turns out that
we generate a lot of type objects and it is important not to add
fields to them willy nilly. Therefore, simply adding a new field to
all type objects that represents the link from a descriptor/instance
type object to the canonical type representation is overly wasteful,
since that field is inapplicable to the vast majority of type objects.

In an ideal world, I would make a subtype of `TypeObject`
(`BinaryDataTypeObject` or some such) to contain the extra
field. However, as type objects are GC things, doing that would
require adding a new finalizer kind, which would result in distinct
arenas for storing binary data type objects vs other type objects. Not
good.

So, what we can do is to reuse a technique that Shu uncovered.
Basically we can overload the `newScript` field. This field currently
stores a pointer to the constructor function for objects associated
with this type object; it is only relevant to code like `new Foo`
where `Foo` is a user-defined function.  This means that it is
inapplicable to the type objects for descriptors and instances.

**UPDATE 2013.07.19: Tweaked some paragraphs for clarity.**

[578700]: https://bugzilla.mozilla.org/show_bug.cgi?id=578700&sourceid=Mozilla-search
[pjs]: /blog/2013/05/29/integrating-binary-data-and-pjs/
