---
layout: post
title: "Deterministic or not?"
date: 2013-01-02 12:30
comments: true
categories: [PJs, JS]
---

One of the interesting questions with respect to Parallel JS is what
the semantics ought to be if you attempt a parallel operation with a
kernel function that has side-effects.  There are basically three
reasonable options:

1. *Deterministic results where possible:* The function behaves "as
   if" it executed sequentially, executing the kernel from 0 to n,
   just like `Array.map`.
2. *Error:* An exception is thrown.
3. *Non-determinstic results:* The function behaves "as if" it
   executed sequentially, but the items were mapped in an unspecified
   order.

The [branch][branch] currently implements option 3: I believe it is
the most consistent and will yield the best performance.  However,
reasonable people can differ on this point, so I want to make my case.

<!-- more -->   

### Why not ensure deterministic results?

At first glance, at least, it seems like having deterministic results
would be the most convenient option.  After all, `ParallelArray.map()`
could then be used as a drop-in equivalent to `Array.map()`.  However,
there are two reasons that I am concerned about this option:

1. Deterministic results are not possible for all operations.
2. Deterministic ordering can hamper efficient parallel execution.

#### Deterministic results are not possible for all operations.

If you examine [the specification for `ParallelArray.reduce()`][reduce],
you will see that it permits `reduce()` to reduce the items in the array
in any order:

<blockquote>
Reduce is free to group calls to the elemental function and reorder
the calls. For an elemental function that is associative and
commutative the final result will be the same as reducing from left to
right...reduce is only required to return a result consistent with
some call ordering and is not required to chose the same call ordering
on subsequent calls.
</blockquote>

This means that the result of `reduce()` is only deterministic if the
kernel function is associative and commutative.  Without this
requirement, implementations would be severely limited in how they
could perform parallel reduction, and in some cases parallel execution
would be too expensive to be worthwhile (interestingly, the sequential
fallback would be more expensive too, because the best sequential
ordering for reduction is not parallelizable at all).

For this reason, I am wary of telling users that `ParallelArray`
methods have equivalent semantics to `Array` methods.  This is only
partially true and it can never be fully true.  In general, I think
users will want the *best parallel performance they can get*, and they
will accept whatever restrictions are required to get it.

### Deterministic ordering can hamper efficient parallel execution.

We just saw that, in the case of `reduce()`, any deterministic
ordering either prevents efficient parallel execution or it prevents
efficient sequential execution.  To a lesser degree, the same is true
of `map()`.  Unlike `reduce()`, though, the problems with `map()` are
somewhat subtle.

You may recall that when we perform parallel execution, there is
always the possibility of *bailout*.  A bailout can occur because we
detect that a write would cause a visible side-effect, but it can also
occur for arbitrary, internal reasons.  Bailouts often occur because
there is some portion of the code that has not yet been executed in
the warmup runs, and hence the type information that we gathered was
inaccurate.

The question is, when a bailout occurs, what do we do with the results
that were successfully computed by the previous parallel iterations?
It would be very nice if we were able to make use of those results.
If we do guarantee deterministic results, however, this is somewhat
tricky.

Imagine for a moment there are just two threads processing a
1000-element array.  In our current system, each worker will be
responsible for mapping half of the array.  So imagine that the first
worker has processed indices 0 to 22 when it encounters a bailout due
to insufficient type information.  To gather type information, we need
to execute iteration 23 sequentially in the interpreter.  In fact,
while we're in the interpreter, it's probably best if we do a chunk of
iterations---say, 23 to 32 or so, just to gather up more
data. Meanwhile, let's say that the second worker has processed
entries 500 to 600 before it notices that the first worker bailed out
and follows suit.

Unfortunately, if we are guaranteeting deterministic results, it is
very difficult for us to make use of the results for entries 500 to
600 that were already computed.  It's possible, after all, that when
we re-run iterations 23 to 32 in the interpreter, they will modify
shared state, and that could affect the computations that already
occurred. In effect, all parallel iterations are inherently
*speculative*.

As annoying as it is to have to throw away indices 500 to 600, it is
equally annoying if the bailout should occur in the second worker
(say, while processing index 601).  In that case, we have a problem:
we'd like to run index 601 in the interpreter, but it's possible that
this too will cause side-effects.  That means that we must ensure that
all indices prior to 601 are fully processed (which, at the time of
bailout, they are not).  Given enough bookkeeping, we can manage this
too: we could perhaps re-spawn parallel workers to process from 23 to
600, for example, and then re-spawn to process from 600 to 1000.

### What if we don't guarantee deterministic ordering?

If, however, we choose *not* to guarantee deterministic results, these
problems become much simpler.  When a bailout occurs, we can simply
have each worker execute sequentially from wherever it left off.  So
to continue with our example, worker 0 would run from indices 23 to 30
or so, and perhaps worker 1 would run from 601 to 632.  This way they
can both gather a bit more data.  Then we resume parallel execution.

This is in fact more-or-less exactly what
[our current code does][branch].  Each worker tracks its current
position.  Whenever the kernel function is invoked, it processes the
next data it has to proccess, and it updates its current position as
it goes.  If a bailout occurs, then the current position is not
updated, so when the kernel function is invoked next (which will be
from the interpreter), it will pick up where it left off and process
for a while.  I can dive into the intimate details of this in a
separate post.

#### What about reporting an error?

Prohibiting impure operations altogether does enable the same
optimizations as nondeterministic ordering, but (as I
[argued in a previous post][purity]) it does so by imposing a
significant and unnecessary implementation and performance burden on
the sequential fallback code.  So I am not a fan of this approach.

### The take-away

My feeling is this.  Deterministic ordering sounds like it makes
things easier for the end-user, but the story is actually more
complex, as only some operations are deterministic.  Moreover it
imposes performance burdens on the implementation, so even the "good
guys" who stick to pure operations will pay the price, at least until
optimizations become more highly tuned to cover all kinds of corner
cases.

In general, I think people will turn to `ParallelArray` when they have
pure operations to perform: for pure operations, deterministic
ordering simply imposes a performance burden. If you have an impure
operation for which ordering is significant, it seems to me you would
be better off just using normal arrays or coding the operation in a
sequential fashion.

Clearly this is an area where reasonable people can differ, though,
and I would not be surprised if we ultimately decide to guarantee
determinism where possible (i.e., `map()` and `filter()`).

[purity]: /blog/2012/10/24/purity-in-parallel-javascript/
[pp]: /blog/2012/12/06/improving-our-parallel-intrinsic/
[branch]: https://github.com/syg/iontrail
[rope]: http://en.wikipedia.org/wiki/Rope_%28data_structure%29
[reduce]: http://wiki.ecmascript.org/doku.php?id=strawman:data_parallelism#reduce
