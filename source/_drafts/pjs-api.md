Lately, I've been thinking about the ParallelJS API that we want to
expose.  In particular, I've been considering offering methods on the
normal array type for basic parallel operations.  I think this opens
up some interesting doors.

*Note:* To give credit where credit is due, I should note that a lot
of the ideas in this post originate with other members of the Parallel
JS team (Shu-yu Guo, Dave Herman, Felix Klock).  But I don't want to
speak for them, since we seem to each have our own opinions on the
best arrangement, so I'm writing the post from the first person
singular ("I") and not a team perspective ("we").  This does not imply
"ownership" of the ideas within.

### The basic idea

The basic idea is to add "unordered" or parallel variants of the
standard higher-order methods to JavaScript arrays as well as to typed
arrays (and [binary data arrays][bd] when those become available).
For example, in addition to `map()` and `reduce()`, we'd offer
`unorderedMap()` and `unorderedReduce()` (in the case of typed arrays,
I think we'd have to add `map()` as well).

The *semantics* of the unordered variants are the same as their
ordered cousins, except that the ordering in which they perform their
iterations is not defined.  However, if you used the unordered
variants, we will attempt parallel execution where possible.

### Why call the methods "unordered"?

I chose the (admittedly somewhat clunky) prefix `unordered` because I
want to emphasize the fundamental contract our parallel execution
engine offers, which is that parallel execution is equivalent to
*some* sequential ordering, but [it doesn't say which one][nondet].
This is a [somewhat controversial design][det], but I still feel it's
the right one.  In any case, it's basically orthgonal to this post.

Note that there is no reason we can't someday try parallel execution
for the ordered `map()` as well.  However, we'd have to be very
careful to avoid introducing overhead in the case that parallelization
fails or would change the semantics of the program.  The use of the
unordered variant effectively serves as a hint that parallelization is
likely to pay off.

### What about immutability?

Some readers will remember that `ParallelArray` objects are immutable
while normal JS arrays are not.  This is true but it's not a big
obstacle.  During any parallel operation, mutations to pre-existing
objects are forbidden and must be detected; in the case of a call like
`array.unorderedMap(func)`, the array `array` that is being mapped is
itself a pre-existing object and thus would be at least temporarily
immutable.

There are of course some good reasons to have immutable data,
particularly if we wind up doing GPU operations, in which case memory
will have to be transferred back and forth, and we may have to worry
about invalidation.  If this ever becomes an issue, we can accommodate
these more advanced use cases either by the existing freezing
interfaces that JS provides or through the multi-dimensional API
described below.

### What are the benefits of this API?

The biggest benefit of this approach, I think, is that it's about the
simplest way to offer parallelism.  You can work with the JS array
types we all know and love (or hate, as you prefer).  Moreover,
integration with existing codebases becomes easier.  If you have some
loops that are performing pure transformations, such as filtering out
records on some criteria, you can change them to execute in parallel
just by changing the name of the method you use.  On other or older
browsers, it's trivial to polyfill `unorderedMap` as equivalent to
`map`.

### What does this mean for ParallelArray?

Right now, the `ParallelArray` API serves two masters.  It tries to be
a very lightweight one-dimensional array but it also tries to be a
fairly powerful multi-dimensional matrix.  If we offer parallel
transformations on normal arrays, that frees up `ParallelArray` so
that it can be targeted at more advanced use cases.  In particular, it
can be (1) always multi-dimensional and (2) type-annotated to permit
efficient storage when you have a matrix of scalar values like bytes
or ints.  I am right now working on another post regarding some ideas
relating to how we can handle the multi-dimensional case; it was
originally part of this post but this post was rapidly becoming too
long.

[bd]: http://wiki.ecmascript.org/doku.php?id=harmony:binary_data
[nondet]: /blog/2013/01/02/deterministic-or-not/
[det]: /blog/2013/01/03/the-case-for-deterministic-results/
