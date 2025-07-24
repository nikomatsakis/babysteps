---
layout: post
title: "The case FOR deterministic results"
date: 2013-01-03T19:05:00Z
comments: true
categories: [PJs, JS]
---

In my last post, I made the case against having a deterministic
semantics.  I've gotten a fair amount of feedback saying that, for a
Web API, introducing nondeterminism is a very risky idea.  Certainly
the arguments are strong.  Therefore, I want to take a moment and make
the case *for* determinism.

<!-- more -->

### Why determinism?

All things being equal, it's clear that deterministic execution
semantics are preferable.  They're easier to debug and they avoid the
question of browser incompatibilities.  

One interesting observation (most recently pointed out by
[Roc in this comment][roc]) is that while the intention of a
nondeterministic ordering is to free up the implementor, what
sometimes happens is that all people wind up relying on the behavior
of one implementation, and then the others follow suit.

That said, there seem to be numerous examples of nondeterministic
portions of JavaScript: the iteration order for properties, for
example, or the order of callbacks to the comparator in `Array.sort`.
But then there are plenty of examples of implementations being
constrained by arbitrary behavior inherited from legacy interpreters.
In any case, I am not an expert in these kind of nitty gritty
cross-browser compatibility details.

If we did opt for nondeterministic semantics, it might be plausible to
use a cheap PRNG like [Xorshift][xor] in the sequential fallback so as
to make it more likely that unwanted dependencies on execution
ordering would be seen during testing (though, of course, this adds
overhead too!).

### What about performance?

It is true that nondeterministic semantics give maximum efficiency,
but the magnitude of these performance gains is not entirely clear.
In my previous post, for example, I stressed the behavior around
bailouts.  It is true that guaranteeing deterministic semantics will
result in wasted work and in general make bailouts less efficient.
*However,* it is also true that bailouts are the exceptional case: if
things are working properly, they should only occur at the beginning
of execution.  Once sufficient type information has been gathered,
parallel execution without bailouts should be the norm---unless of
course it turns out the code is not parallelizable, either because it
is impure or because it uses some unsupported language features, in
which case we will simply use the sequential fallback from the start
and not even *attempt* parallelism.

So, at least in the case of functions like `map()`, efficiency in the
*steady state* should not be negatively impacted by deterministic
semantics, presuming that the kernel function is pure.

### But what about reduce, scan, and scatter?

As I wrote in the previous post, the current semantics of
`ParallelArray` are inconsistent.  They give deterministic results for
`map()` but not for `reduce()`, `scan()`, or `scatter()`.  The core
problem here is that the standard sequential ordering for `reduce()`
(i.e., left-to-right) is inherently sequential---and the most
efficient ordering will depend on the precise implementation strategy
(how many worker threads are involved, etc). But, at the cost of some
efficiency, we *can* choose a deterministic ordering that still
permits parallel execution.

For reduce, a good ordering might be to evaluate in a tree-like
fashion.  So we would first reduce indices 0 and 1, then 2 and 3, 4
and 5, and so on, resulting in an array with length `N/2`.  We can
then repeat the reduction until the result has length 1.  If at any
step we get an array with an odd length, we can reduce the final
element in with the final pair.  A similar ordering can be used for
scan, though the need to preserve intermediate results creates
complications.

The scatter operation, at least when a conflict function is provided,
is much more difficult to parallelize.  I think that the only way it
is possible is to make each thread walk the entire list of targets but
only process writes to a specific subset of the array.  If no conflict
function is provided, or if the conflict function is one that is known
to be associative and commutative (such as integer addition---though
not floating point, sadly), then parallelization of scatter is also
relatively straightforward.

### So what's the right thing to do?

At this point, the answer is probably "measure" or perhaps "wait and
see".  I am somewhat concerned though about basing too many decisions
on the performance of our current implementation, both because it has
not been heavily optimized and because it is only one model of
execution (parallel worker threads).  But we've got to go on
something.

If the API were designed for *me personally* to use, I would want it
to have nondeterministic semantics.  This gives maximum flexibility to
the implementation without opening the door to data races.  However, I
am certainly appreciative of the concerns regarding
debugability---performance is not everything!

[roc]: http://smallcultfollowing.com/babysteps/blog/2013/01/02/deterministic-or-not/#comment-753987533
[xor]: http://en.wikipedia.org/wiki/Xorshift
