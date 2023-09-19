---
layout: post
title: "Typed object handles"
date: 2013-10-18 15:39
comments: true
categories: [PJs, JS]
---
Yesterday [Dmitry Lomov][dl] and I had a discussion about the typed objects
API. Much of the discussion revolved around the specific issue of
*handles*. In this post I will summarize the issues we discussed and
review the various design options.

I'll begin with a summary of what handles are and how they are used in
current APIs; if this is familiar to you (*cough* [Dave Herman][lc] *cough*)
you may want to skip ahead to the section "Subtle points".

<!-- more -->

### An introduction to handles

#### Handles point into other typed objects

As envisioned in the current strawman, handles are a kind
of *movable pointer* that can be used to point into arbitrary data
structures. For example, imagine that we created an object
representing a line:

```js
var PointType = new StructType({x: float32, y: float32});
var LineType = new StructType({from: PointType, to: PointType});
var aLine = new LineType({from: {x: 1, y: 2},
                          to: {x: 3, y: 4}});
```

Now we could create a handle that points at the `from` coordinate:

```js
var handle = PointType.handle(aLine, "from");
print(handle.x, handle.y); // prints 1, 2
handle.x += 1;
print(handle.x, handle.y); // prints 2, 2
```

You can see that a handle is created by invoking the method `handle`
on a type object; the handle can then only be used to point at data of
the given type. You specify where the handle points by giving a base
object and a path: in this case, `aLine` is the base object, and the
path is the property `"from"`. We will see later that a path can
consist of any number of property names and element indices.

*Note:* the [wiki][wiki] specifies that handles are created using `new
 Handle(PointType, aLine, "from")` instead of `PointType.handle(aLine,
 "from")`; my branch differs from this, the distinction is unimportant
 and will be reconciled eventually.

#### Handles can be moved

In the simple example we just saw, a handle is not really different
from any other typed object. After all, we could have rewritten the
previous snippet not to use a handle and had the same effect:

```js
var from = aLine.from; // not a handle
print(from.x, from.y); // prints 1, 2
from.x += 1;
print(from.x, from.y); // prints 2, 2
```

However, using a handle gives us additional capabilities. For example,
we can *move* a handle to point somewhere else, such as the `to`
coordinate:

```js
Handle.move(handle, aLine, "to");
print(handle.x, handle.y); // prints 3, 4
```

#### Handles allow you to avoid allocation

Moving handles makes it possible to write a loop that iterates through
data without allocating values. For example, the following function
`visitPoints` invokes a callback `func` on every point (both `from`
and `to`) that appears in a list of lines:

```js
var LinesArray = new ArrayType(LineType);

function visitPoints(linesArray, func) {
    var handle = Point.handle();
    for (var i = 0; i < linesArray.length; i++) {
        // Make handle point at linesArray[i].from:
        Handle.move(handle, linesArray, i, "from");
        func(handle);
        
        // Make handle point at linesArray[i].to:
        Handle.move(handle, linesArray, i, "to");
        func(handle);
    }
}
```

If we were not using a handle here, then each iteration of the loop
would require the allocation of two objects.

#### Handles as "out pointers"

One of the primary uses for handles is to serve as an *out pointer* --
you may recall the idea from this
[previous post about integrating typed objects with PJS][out], but in
case you do not let me summarize again.

Imagine that we wished to add an API `build` to all array types.  The
idea of `build` is to both allocate and initialize an array in one
step. For example, if I wanted to have an array of points spaced
evenly along the `y=0` line, like
`[{x: 0, y: 0}, {x: 1, y: 0}, {x: 2, y: 0}]`, I could write:

```
var PointsArray = new ArrayType(Point);
var points = PointsArray.build(3, i => new Point({x: i, y: 0}));
```

We might implement `build` like so:

```js
ArrayType.prototype.build = function build(length, func) {
    var result = new this(length);
    for (var i = 0; i < length; i++) {
        // invoke callback
        result[i] = func(i);
    }
    return result;
};
```

All the code we have written thus far is quite reasonable and will
work fine, but it is somewhat inefficient. For example, in every
iteration of the build loop, we will invoke the callback `func` which
will allocate a new point object. This new point object will then be
copied into the final result array. At that point, the new point
object is garbage and will eventually be collected.

A more efficient way to handle this same scenario would be to have the
`build` API provide an *out pointer* -- that is, a pointer into the
result array -- where `func` can directly write its result. This
avoids the need for a copy altogether. Using this style of API would
mean that a call to write might look like:

```
var PointsArray = new ArrayType(Point);
var points = PointsArray.build(3, (i, out) => {
    out.x = i;
    out.y = 0;
});
```

Now the callback does not return a point object but rather
writes directly into `out`. It is also possible to use the
`Handle.set` method to combine both writes into one statement:

```
var PointsArray = new ArrayType(Point);
var points = PointsArray.build(3, (i, out) => {
    Handle.set(out, {x: i, y: 0});
});
```

*Side note on optimization:* You might object that writing the
function using `Handle.set` *still* allocates a temporary object (the
literal `{x:i, y:0}`) which was what we were trying to avoid in the
first place. This is of course true. However, two points to keep in
mind: (1) the original code also allocated the same temporary, so in
fact the functional style allocated two objects per iteration, not
just one; (2) I fully expect that in both cases any decent JIT would
be able to optimize away this temporary object. The latter is a
relatively simple local optimization. In contrast, converting a
function that returns its value into one that uses an out pointer is a
relatively subtle optimization that can only be performed in limited
circumstances.

To implement the new build API, you might write:

```js
ArrayType.prototype.build = function build(length, func) {
    var result = new this(length);
    var handle = this.element.handle();
    for (var i = 0; i < length; i++) {
        // point `handle` at `result[i]`
        Handle.move(handle, result, i);
        
        // invoke callback
        func(i, handle);
    }
    return result;
};
```

This is *almost* the definition we've arrived at with PJS. The one
difference is that we found that in some cases, in particular when you
have an array of *scalar data*, using an out pointer is awkward.
For example, imagine I wanted to create an array of even numbers like
`[0, 2, 4, 6]`. Using an out pointer, I would have to write:

```js
Uint32Array.build(4, (i, out) => {
    Handle.set(out, i * 2);
});
```

This is siginficantly less nice than writing in the functional style,
which would simply be `Uint32Array.build(4, i => i * 2)`.

To accommodate both use cases, in PJS we opted to make use of the out
pointer *optional*. The idea is that we examine the return value from
the callback function; if the function returned `undefined`, we assume
that it used the out pointer to write its result. Otherwise, we copy
the value that was returned into the array. So that means that `build`
looks like this:

```js
ArrayType.prototype.build = function build(length, func) {
    var result = new this(length);
    var handle = this.element.handle();
    for (var i = 0; i < length; i++) {
        // point `handle` at `result[i]`
        Handle.move(handle, result, i);

        // invoke callback
        var r = func(i, handle);
        
        // NEW: optionally copy result from callback
        if (r !== undefined)
            result[i] = r;
    }
    return result;
};
```

### Subtle points

OK, I've introduced the basic idea of handles and shown how we expect
them to be used. Until this point I've only looked at how handles let
users write programs that are more efficient -- or at least could be
more efficient, depending on the kinds of optimizations that the
engine performs. I want to look now at some of the more subtle design
constraints and goals of handles.

In the previous section I mentioned that handles can make functions
like `build` more efficient (1) they can be moved, allowing you to
create one object and then use it throughout the loop and (2) they can
be used as out pointers, which serves to avoid both allocation and
copying overhead. If you didn't care about allocation costs, you might
think that you could use normal typed objects instead of handles
would be sufficient. In that case, the `build` function might look like:

```js
ArrayType.prototype.build = function build(length, func) {
    var result = new this(length);
    var handle = this.element.handle();
    for (var i = 0; i < length; i++) {
        // Look ma, no handles!
        var r = func(i, result[i]);
        if (r !== undefined)
            result[i] = r;
    }
    return result;
};
```

This definition will *almost* work, but there are two important
differences that I want to elaborate on.

#### Handles permit uniform treatment of scalar values

The version of `build` which does not use handles will work ok if you
are constructed a complex type:

```
var PointsArray = new ArrayType(Point);
var points = PointsArray.build(3, (i, out) => {
    out.x = i;
    out.y = 0;
});
```

The reason for this is that when we call the callback, we supply
`result[i]`. Since the result is an array of points, which are
structs, this will create a new typed object pointing into the
`result` array.  Modifying the fields of this typed object also
modifies the underlying result array.

However, the same is not true if you are constructing an array of
integers. In that case, `result[i]` would yield an integer value,
rather than a pointer into the array, and hence the user would not be
able to use the out pointer form if the result is a scalar type.

This may not seem like a big deal, because as I wrote before the out
pointer is kind of awkward when constructing scalar arrays.  However,
I believe it is nonetheless a downside, because using handles permits
me to write generic, uniform code that works *no matter what type of
array is being built*.

*Note:* The fact that handles behave differently from typed objects
with respect to scalars is a plus, but also a minus, in that its
different and asymmetric. More in the section on "controversial
points" below. I am ultimately not sure how important it is to be able
to always use out pointers no matter what type you are producing. As
long as you are careful to permit the option of using return value
*or* an out pointer, everything probably works out, and you can still
write generic code that simply retains that pattern.

#### Handles as capabilities

The other interesting point about handles is that they can never be
used to access any part of memory outside of the memory that they
immediately point at. Let me elaborate. When the `build` function
calls the `func` callback, it provides an out pointer pointing at the
`i`th element in the array. We want to ensure that providing this out
pointer *only allows* the `func` callback access to the memory for the
`i`th element, and not other elements.

This guarantee is crucial for PJS, because we will be executing
different iterations of `build` in parallel, and we want to be sure
that if one thread is writing into array index `100`, it can't use the
out pointer to gain access to array index `0` and read or mutate that.
This would induce data races.

If I use a typed object -- at least as they are currently designed --
there is no such guarantee. This is because a typed object can be used
to gain access to the underlying array buffer. And unfortunately there
is no way to hand out of a "subset" of an array buffer -- instead, you
access the entire thing, which means that even if I am only given a
pointer to element `22`, I *actually* have access to the entire array.
This design choice is somewhat forced upon us because we must be
backwards compatible with typed arrays.

### Controversial points

Let me dive now into some of the more controversial points of handles.

#### Handles are "nullable"

Unlike normal typed objects, handles can be "null", meaning that they
can be in a state where they do not point anywhere. Currently, this
can only occur when handles are first created, if no initial path is
supplied. For example, the common way to use a handle in a loop would
be something like the following:

```js
var handle = elementType.handle(); // handle is NULL here
for (var i = 0; i < array.length; i++) {
    Handle.move(handle, array, i);
    // handle is no longer null
}
```

Here, a handle `handle` is first created in a NULL state and then, on
each iteration of the loop, re-pointed.

Nullable handles means that (1) users can encounter errors by using a
handle that doesn't point anywhere and (2) the compiler must insert
null checks, which decreases performance.

You might think that you could easily eliminate null handles by simply
disallowing handles that are created without pointing at anything.
This is true, but it would make working with handles in loops quite
awkward. The code above would have to look something like:

```js
if (array.length > 0) {
  var handle = elementType.handle(array, 0); // handle is not null
  for (var i = 0; i < array.length; i++) {
    Handle.move(handle, array, i);
    ...
  }
}
```

In this case, we gave an initial assignment for the `handle` but we
never used it. This avoids null errors but also doesn't contain a way
to represent a handle in this invalid state where it is not yet
intended to be used, so it's debatable if this decreases user error.

*Note:* I will argue later that in the *subtle points* section that
nullable handles are not necessarily bad and in fact provide
potentially important capabilities.

#### Anybody can move a handle

One non-obvious fact is that, in the current API, handles can be moved
by *anyone*, including the callback. This can be potentially
problematic.  For example, here is a slight variation on the final
version of `build` routine that I gave you earlier. As you may recall,
this version `build()` supplies an out pointer but also checks for a
return value and potentially copies that return value into the result.
I changed one line from the previous definition, higlighted with a
comment.

```js
ArrayType.prototype.build = function build(length, func) {
    var result = new this(length);
    var handle = this.element.handle();
    for (var i = 0; i < length; i++) {
        Handle.move(handle, result, i); // 1
        var r = func(i, handle);
        if (r !== undefined)
            Handle.set(handle, r); // 2 -- Changed
    }
    return result;
};
```

As you can see, I changed the line marked `2` from `result[i] = r` to
`Handle.set(handle, r)`. Since we just moved `handle` to point at
`result[i]` in the line marked `1`, you might think that these two
bits of code are equivalent. You would be wrong. The reason is that it
is possible that, after calling `func`, the handle `handle` has been
moved and no longer points into the result array. This is potentially
a dangerous footgun.

#### Handles and typed objects are similar but different

I could imagine that handles and typed objects are simultaneously
too different and too similar. That is, they behave similarly *enough*
that you could almost ignore the differences, except for various
edge cases. This can cause trouble for people learning the API.

Examples of edge cases where they differ:

1. Handles can be moved or null.
2. Handles can point at scalar values like floats or ints.
3. Handles do not permit access to the underlying buffer (see section below).

### Design alternatives

So, what should we do with handles? I am going to present three
different possible designs. Each of them preserves the basic memory
encapsulation capability that I can give you a handle into a typed
object without giving you full access to the entire typed object.

#### (1) Keep handles, embrace nullability

We can keep handles more-or-less as they are, meaning that they remove
movable and nullable. It remains true that handles can be moved by
anyone and you just have to live with that.

In this case, I would argue for adding an API to make handles return
to a null state (e.g., `Handle.move(handle)` makes `handle` null). The
reason for this is that it lets handles serve as *revocable*
capabilities. This means that if I have a typed object I know is
unaliased, I can give out a handle to it and then revoke that handle
and still be sure that my typed object is unaliased.

One example use case for this that [dherman][lc] and I have tossed
around is the idea of initialized data that will be sent to another
worker. The vague idea is that you can allocate memory directly in
another worker's memory space and then be given a handle to that
memory you can write into. Afterwards, the handle is made null (of
course this might be achievable with array buffer transfer instead).

#### (2) Keep handles, reject movability and nullability

We can keep handles, but disallow them from being moved.  This implies
that when you create a handle you always specify an object path.  In
this case, handles never help to reduce allocation, they only serve as
a means of granting limited access to a buffer.

#### (3) Drop handles, add opaque typed object views

If handles aren't helping us with reduced memory requirements, maybe
we can drop them altogether. Instead we would allow you to create a
new typed object relative to an original one and somehow specify that
this new typed object will be created *opaque*, meaning that it does
not grant access to the underlying buffer. This has the advantage of
no longer having two concepts (handles, typed objects) but the
possible disadvantage that it cannot work uniformly with scalars.

### My preference

When I started writing this post, I was vacillating between options 2
and 3, but in the course of writing the post I think I have persuaded
myself that I prefer option 1: keep handles and embrace nullability.

My arguments are:

**Nullability is not so bad.** It is already a thing in JS and we will
never change that. It's a minor point for optimization.  Accesses to
typed objects (as distinct from handles) still do not require null
checks, so by avoiding handles users can avoid the price of null
checks.

**Nullable handles provide for better ocap.** It is useful to be able
to hand out access to a limited memory region without giving out the
entire buffer. It is also useful to be able to *take it away again*.
Being able to null a handle out later means that if you have a buffer
that you know is unaliased, you can invoke a function with a handle
into that buffer and then later null the handle out. You can now be
sure that your original buffer is unaliased.

**Avoiding allocation *is* important.** It is tempting to say that
allocation can be made free. After all, we're all using highly
optimized generational collectors, right? (ok, almost;
[go, terrence and jonco, go!][ggc]). But I think this is ultimately
false. First, no allocation is always cheaper than some allocation,
even when the allocator is hyper optimized. Second, this is
particularly true in a parallel setting (read on).

In the parallel case, the way that one handles allocation in a
scalable way is to have each parallel thread equipped with its own set
of independent memory pools, whether you call those nurseries or
arenas or whatever. Allocating and setting up these independent memory
pools is not super expensive, but it's also not super cheap; it
requires some amount of synchronization and is ultimately pure
overhead. What I would like to do is to allocate those memory pools
*lazilly*, meaning on first allocation. If we make handles
relocatable, it is possible to avoid all allocation within the loop
itself. This means that if your callback avoids allocating objects,
which in many cases is very possible, we can avoid setting up memory
pools altogether. This should help to lower the overhead of entering
and exiting the parallel section which is [crucial to enabling
better parallel speedups][amdahl].

[wiki]: http://wiki.ecmascript.org/doku.php?id=harmony:typed_objects
[out]: {{< baseurl >}}/blog/2013/05/29/integrating-binary-data-and-pjs
[ggc]: https://bugzilla.mozilla.org/show_bug.cgi?id=764882
[amdahl]: http://en.wikipedia.org/wiki/Amdahl%27s_law
[lc]: https://twitter.com/littlecalculist
[dl]: https://twitter.com/mulambda
