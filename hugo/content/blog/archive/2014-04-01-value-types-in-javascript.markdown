---
categories:
- JS
comments: true
date: "2014-04-01T00:00:00Z"
slug: value-types-in-javascript
title: Value types in JavaScript
---

Here is the current state of my thinking with respect to value types
and value objects. Some of you may have seen
[Brendan's slides][slides] where he discusses value objects. This post
is about the same topic, but it is focused on just the initial part of
the work -- what it means to be a value object and how we could define
value types and integrate them into the standard. I am not going to
discuss new syntax or operators yet. I have thoughts on those too but
I wanted to start by laying out the foundations.

### The need for extensible value types

JavaScript has long had a division between *primitive values* and
*objects*. These two things are fundamentally rather different.
Primitive values have no identity and no prototype. They are not
*allocated*, just used. They are also immutable. Consider an integer
like `var x = 1` -- if I write `x += 1`, I haven't *incremented* the
number 1 itself, I've just changed the variable `x` to have a new
value, 2.

Objects are rather different. When I create an object, it has
*identity*. If I execute the same expression twice, I get two
*different objects*. This is why `{} === {}` evaluates to false
(unlike, say, `1 === 1`). In turn, objects have mutable contents, so I
write `foo.x += 1` and mutate the contents of `foo`.

There is nothing wrong with the division between values and objects in
and of itself. Both have their place and are useful in certain
circumstances. What *is* unfortunate is that JavaScript makes the set
of value types inextensible. That is, the only value types I can have
are the primitives that the spec itself provides: booleans, numbers,
strings, and (in ES6) symbols. (I've probably forgotten one, but it
doesn't matter.)

In this post, I'll lay out a preliminary design for allowing users to
define and use their own value types. These types offer the same
advantages as the built-in types: they are immutable and have no
identity apart from their value. When used appropriately -- i.e., in
places where a *value* is fundamentally what you want and not an
*object* -- this makes programs easier to read and write and also
easier to optimize. Everybody wins!

<!--more-->

### Value types are just both tasty and nutritious

Suppose that I have a type representing colors:

```js
function Color(r, g, b, a) {
    this.r = r;
    this.g = g;
    this.b = b;
    this.a = a;
}
```
    
Now I can create a color by doing `new Color(22, 44, 66, 88)`. This
conceptually represents a color. I will argue here that colors are an
example of a type that really *wants* to be a value. The fact that JS
forces us to represent colors as mutable objects is really wrong and
makes code harder and less convenient to write. Later on, we'll see
how we could define `Color` as a value type, which would not only make
it more convenient but help to make our generated code more efficient
as well.

#### Comparisons

Now what I want to tell if the color of two rectangles is the same?
You'd hope I could just write `rect1.color === rect2.color`, but of
course I cannot, at least not reliably. The problem is that colors are
*objects* and thus when we compare with `===` we are comparing
for *object identity* rather than representing the *same color*.

To compare if two colors represent the same color, we have to write
some kind of equals function:

```js
Color.prototype.equals(c) {
    return this.r === c.r && this.g === c.g &&
           this.b === c.b && this.a === c.a;
         
} 
```

Now I have to remember to write code like
`rect1.color.equals(rect2.color)`. This is not as pretty and of course
if I forget somewhere I'll just get the wrong behavior. Too bad.

#### Mutation and aliasing

Another problem with using objects for colors is that they are
mutable. For something like colors, this is probably not what we
want. In particular, I'd like to be able to write code like:

```js
rect2.color = rect1.color;
```
    
The problem is that if I do this, I have now linked `rect1` and
`rect2` to the *same color object*. So now if some other piece of code
tries to modify the color of `rect1`:

```js
rect1.color.r += 3;
```
    
This change will also affect the color of `rect2`! That is almost
certainly not what we wanted to happen. Yuck.

#### Hard to optimize

The presence of pointer identity, aliasing, and mutability also
inhibit a wide variety optimizations. For example, imagine I had a
loop like:

```js
for (...) {
    ...
    doSomething("foo" + "bar");
    ...
}
```

Any JIT engine could, if it choose, safely lift that expression
`"foo"+"bar"` out of the loop and evaluate it exactly once, rather
than evaluating it on every iteration through the loop. But if I write
some similar code that constructs a `Color` instance, it will be much
harder to optimize:

```js
for (...) {
    ...
    doSomething(new Color(255,0,0,0));
    ...
}
```

We'd like to optimize this to create just one `Color` instead of one
per loop iteration. But we have to be very careful if we do so.  After
all, what if `doSomething` mutated the fields of the color, like so:

```js
function doSomething(c) {
    ...
    c.r += 1;
    ...
}
```

Now if we don't create a new color on every iteration, we'll just keep
modifying the same object. That's no good.

### Primitive types do not generalize to user-defined value types

OK, so I hope I've convinced you that it'd be nice to have
user-defined value types. You might think that it would be best to
model these user-defined value types after the existing primitive
types. I'd like to convince you that this is the wrong path.

The reason that modeling user-defined value types after primitives
is tempting is that primitives have a lot of the behavior we want:

1. Primitives are *immutable*. You can't rewrite the contents of
   a string, for example, you have to generate a new one.
1. Primitives do not have *identity*. `===` compares the *value*, not
   the *pointer*.  Two strings, for example, are equal if they contain
   the same *characters*, regardless of where those characters are
   stored.
   
However, primitives also come with a lot of other behavior that is
different from objects, and this behavior doesn't really scale well
when you allow the set of primitives to be extended by the user:

1. `typeof primitive` yields a unique string, like `"number"` (whereas
   all objects, regardless of their prototype, just get `"object"`)
1. Primitives do not have *prototypes*, so if you evaluate
   `primitive.member`, what happens is that the primitive is
   automatically wrapped in a class like `Number` or `String` to yield
   an object.
   - In particular, if you access a primitive value from another realm
     (i.e., from an iframe), you copy just the primitive value. If you
     try to invoke a method on it, it will get wrapped in the *local
     wrapper* for the current realm, and not the wrapper from the
     realm in which it originated.
  
These kinds of rules work fine for a fixed, well-known set of
primitive types. They do not scale well once we start introducing
arbitrary, user-defined primitive types.

To see why, consider `typeof`. If we allow user types to define what
string is returned from `typeof`, then this string is no longer
particularly unique. What do we do if two user-defined types claim the
same `typeof` string? What about if they try to forge an existing
string, like `number`?

The lack of prototypes is a bit of a problem as well. For each
primitive type, there is an implicit link to a well-known wrapper
type. But if users define their own primitive types, we'll have to
link them to a (user-defined) wrapper type as well, so that we can add
methods to those types.

This link gets very thorny in a cross-realm scenario: in that case, if
we want to act like primitives, we need to find a corresponding
wrapper function between the two realms. But there is no guarantee
that the two realms will define the same set of types and no
particularly good way to link those types up even if both realms did
so. So what do we do?

I think the answer is simply that we should not try to model value
types on primitives. After all, the set of classes is already
extensible and has already addressed these problems:

- Objects use their prototype to link to their constructor function.
- Objects always yield `"object"` for `typeof` checks.
- Cross-realm objects carry a link (via their prototype) back to their
  original realm, side-stepping the need to synchronize class
  definitions between realms.

### Generalizing typed objects to support user-defined value types

Therefore, I think we should focus on value *objects*. A value object
is an object whose contents are immutable and which has no
identity. Value objects are based on typed objects -- to create one,
users first define a custom *value struct type* or *value array type*
and then instantiate it.

The plan can be summarized as follows:

0. All "primitive types" today are also "value types" (e.g., ints,
   uints, objects, etc). (To be clear, when I say "value type", I mean
   "a type whose instances have no individual identity", so this includes
   primitives but also value objects.)
1. A user-defined struct or array can be made into a value type via a
   "valueType()" transformer like `var Point = new StructType({x:
   uint8, y: uint8}).valueType();`
   - For this to be legal, all of its fields must be of value
     type as well. (see appendix A)
   - All value types are also opaque types.
2. Instances of a value type (called "value objects") are equivalent to normal
   typed objects except for three differences:
   1. You cannot assign to their properties (naturally).
   2. They are compared for equality by comparing the values of each field for
      equality recursively.
3. If you have a non-value-type with a property `p` of value type,
   and you reference `p`, the data is copied out into a new value
   object. This is basically just an extension of the existing rule
   for ints etc.

### Explanation through examples

Let me give some examples to show you how it all works. So if I write
something like this, this is a value type:

```js
var Point = new StructType({x: uint8, y: uint8}).valueType();
```

Now instances of Point are immutable:

```js
var point = Point();
point.x = 1;               // No effect, see appendix B.
assertEq(point.x, 0);
```

I can also create an aggregate value type structure:

```js
var Line = new StructType({from: Point, to: Point}).valueType();
var line = Line();

line.from.x = 1; // No effect
assertEq(x, 0);
```

I can also put `Point` instances into something that is NOT a value
object, in this case an array:

```js
var points = Point.array(200);
points[0] = Point({x: 1, y: 2});
points[1] = Point({x: 3, y: 4});
```

Now this raises a question of mutability. Since the points are stored
inline in the array (i.e., this is NOT an array of pointers-to-points
but just point structs), what happens if I reassign one of its
elements:

```js
var p = points[0];
points[0] = Point({x: 5, y: 6});
```

In particular, did the values of `p` change? If so, that's weird,
because `p` is a `Point` and hence supposed to be immutable.

This is addressed by rule 2c which says that a read of a value type
creates a *copy* (if the owner is not a value type). Hence `p` is not
a pointer into `points` but rather its own object. Thus mutating
`points[0]` has no effect on `p`.

Now there was one last point, which has to do with equality.  Points
are value types, so we want it to be true that if I create two points
with identical fields, they should be equal:

```js
var p = Point({x: 1, y: 1});
var q = Point({x: 1, y: 1});
assertEq(p, q); // p === q holds
```

For ordinary typed objects, this would not be the case: they would
have distinct buffers. But for value objects, it should hold, and it
does, thanks to rule 2.2 which redefines `===` for value types.

Rule 2.2 also has another important implication. *Without* rule 2.2,
the "copy out" semantics (rule 2.3) would be very visible.  In other
words, while it normally holds that `array[0] === array[0]`, this
would not hold for an array like `points`, because accessing an
element of points copies it out.

Hence, without rule 2.2, `points[0] !== points[0]`. But that's no good
-- we want it to be *invisible* when copies occur, at least if there
are no mutations going on.  But because value objects compare for
equality by comparing their fields, there is no problem. `points[0] === points[0]`
even though each time we evaluate `points[0]` we get (at least if we don't
optimize) a fresh object with a fresh buffer.

One little quirk of these rules, though it's not inconsistent in some
sense, is that if you try to mutate a field of a value type embedded
within an array, it doesn't work, even though you could overwrite the
value type as a whole. In other words:

```js
print(points[0].x); // 0 to start
points[0].x = 1;
print(points[0].x); // still 0
points[0] = {x: 1, y: 2};
print(points[0].x); // now 1
```

The reason for this is that `points[0].x` first evaluates `points[0]`,
which yields a fresh `Point` `temp`, and then does `temp.x`. But
assigning to a field of a value object like `temp` has no effect, and
hence the assignment is lost.

### Frozen arrays

One can easily define a frozen array type of a fixed length:

```js
var A = T.arrayType(N).valueType();
```

One can then instantiate this type using an example instance:

```js
var a = new A([...]);
```
    
Or perhaps with some sort of `build` method that is yet to be
specified (though the current PJS strawman incorporates this sort of
thing):

```js
var a = A.build(i => /* create value for index `i` */);
```
    
In general, though, we don't encourage the creation of array types.
Instead, we prefer that people create arrays directly when possible:

```js
var mutableArray = T.array(N);
```
    
So perhaps we want a similar accessor for creating a frozen array:

```js
var mutableArray = T.valueArray(N, [...]);
```
    
It's not clear how `build` fits into this scenario. Perhaps the
initializer can also be a function. I don't know, there's some
bikeshedding to be done here.

### A side note: Integration with Map and Set

ES6 is adding some very useful types called `Map` and `Set`.  These
are more powerful data structures for storing objects. One problem
with them, however, is that they are always keyed on *object
identity*.  This means that if you wanted to have, say, a map keyed by
`Color`, and you defined a `Color` class, your lookup is not going to
have the semantics you expect, because two distinct `Color` instances
that both represent "red" will nonetheless be considered unequal.

Using value types addresses this problem in a simple way without
requiring user-defined comparators and the like. Since the identity
semantics of value objects are based on their fields, if you used a
value type for `Color` you will get the lookup you expect. Horray!

(Sorry if this is unclear; this post is long enough as it is and I
don't want to draw out the examples, but I thought this was an
interesting and not entirely obvious interaction.)

### Appendices

#### Appendix A. Embedding non-value-types within value types.

We could permit non-value types to be embedded within value types.
This would imply that value-ness, like opacity, is not necessarily
tied to the *type* but rather to the instance. I have avoided this
design for two reasons:

1. I think the semantics of embedding a non-value-type into a
   value-type are non-obvious. It has to mean that the embedded
   non-value-type becomes immutable or else valueness has little
   meaning, but this is potentially confusing and I'd rather just
   avoid the question altogether.
2. It interferes with optimization to have mutability be per-instance
   rather than something that is uniquely determined by the type. Not
   that it can't be overcome, but why bother if it's not a feature we
   particularly *want*.

#### Appendix B. The semantics of assignments to properties of value types.

I've been assuming we want assignments to frozen fields to be dropped
for consistency with frozen fields. Of course I'd prefer they throw an
exception.  That doesn't really affect much else in the rules here. (I
also don't remember the semantics of assignments to frozen fields in
strict mode -- perhaps it should just behave exactly like strict mode
does.)

[slides]: http://www.slideshare.net/BrendanEich/value-objects
