---
layout: post
title: "Challengines implementing unique closures"
date: 2011-12-12 21:25
comments: true
categories: [Rust]
---

**Update:** See the recent post addressing
[the solution to this problem][po].

I have been trying to implement unique closures---or sendable
functions, as I prefer to call them---but I realized that there is
a fundamental problem that I hadn't thought of before.   The problem
stems from two contradictory design goals:

- Sendable functions should be movable to another task without copying
- The various function types should have a subtyping relationship

The first requirement really demands that the sendable function's
environment be stored with a unique pointer.  Otherwise multiple
threads could share access to the same mutable state. Uncool.

The second requirement, however, demands that sendable functions
should have the same representation as our other closure types---that
is, they should be represented as the pair of a function pointer and a
boxed environment.

Clearly something has to give.  I see various options.

#### Copy when sending to another task

When sending a sendable function elsewhere, we could do a deep copy of
the closure contents. However, we would want to allocate this copy in
the target task's heap.  brson pointed out that there is a potential
race condition of sorts, in that the target task might die before the
message is constructed and sent. And in any case it just feels weird
to have one task allocate in another task's heap. The proper way to do
this kind of thing is to use the exchange heap, as we do with unique
pointers, but we can't do that and preserve the subtyping
relationship. There is also the fact that I think it should *always*
be possible to send without copies, if you are willing to use unique
pointers.

#### Remove the subtyping relationship

If `fn[send]` was not a subtype of `fn`, then a lot of our problems go
away.  But if we down *that* route, then we end up with a lot of
different kinds of functions; we can no longer unify bare functions
and sendable functions, since bare functions *must* be usable as
closures.  I have a personal goal of keeping the number of function
types to three or less, analogous with `~`, `@`, and `&`.

#### Coroutines or procedures

This is basically what I half-proposed in
[my previous post about procedures/coroutines][coro].  I like this
idea but it's a bit of a departure from what we have; if we did it, I
would probably want to go "whole hog" and support coroutines, though I
think for 0.1 starting with one-shot procedures would be more
realistic.  One thing I like about it is that we can reduce down to
two function types: `fn(T)->U` and `block(T)->U`.  `fn(T)->U` would be
used for (what are today) bare functions and lambdas. `block(T)->U`
would be used for blocks and would also be compatible with `fn(T)->U`.

#### Move the bound into the pointer type

Using coroutines, we can get ourselves down to two function types.
But there is a way to get down to one. Currently, a function type is
actually a pair of the function pointer and the environment.  Another
option would be to make a closure be a single pointer to the
environment, and then to embed the function pointer into the
environment.  Thus the type for *all* closures would be `fn(T)->U`.
This would be a [dynamically sized type][nic] and hence subject to
various limitations; in particular, it could only be referenced by
pointer.  We could then use the type of the pointer to also encode the
bound:

- A unique function pointer `~fn(T)->U` can only close over sendable state.
- A shared function pointer `@fn(T)->U` can close over task-local state.
- A by-ref function pointer `&fn(T)->U` can close over arbitrary state.

Furthermore, the borrowing and aliasing rules would naturally allow
`~fn(T)->U` and `@fn(T)->U` to be used as `&fn(T)->U`, but only for a
limited time, etc.  

I personally think the system that results from this is easy to
explain.  However, it has some downsides:

- it relies on the [no implicit copies (NIC) proposal][nic] and
  [regions][reg], neither of which have been accepted, much less
  implemented;
- it means that calling a closure requires first loading the function pointer
  out of the environment and then calling indirectly, which is slower;
- it merges the function bound and the kind of pointer used to access
  the function.  I see this as a positive (one less concept to
  explain) but others may disagree.  I do not believe any
  expressiveness is lost by this approach, in any case.
  
In any case, the fact that it relies on proposals that have not been
implemented and will not be implemented for 0.1 make it not a viable
option.

#### None of the above

The route I am currently looking into is much more conservative.  We
basically do not support unique closures or any other alternative for
0.1.  Instead, we address the particular pain point that started this
quest: generic bare functions.  Right now, generic functions take
implicit arguments called type descriptors, which are basically a form
of reflection. These type descriptors are always local to a thread.  I
am going to see how difficult it is to make them global. This would
allow generic bare functions to be bound to specific types but remain
bare functions. (If we do decide to "monomorphize", as is under
discussion, then this becomes a non-issue, as type descriptors are no
longer needed.)

#### And what of the future?

Assuming we take the none of the above option, what about the next
version of Rust? Hard to say. Personally speaking, I find the first
two options to be non-starters for the reasons stated previously.  The
third option (coroutines) seems good to me if we can make them fast
enough to use for iterators (which I think we can).  The fourth option
(pointer type is bound) appeals to me as well because it brings us
down to *one type of function* (`fn(T)->U`) without any loss of
expressiveness.  We would probably want to see what performance impact
it has and if there are ways to mitigate it.  In any case, there is a
long road between here and the fourth option, since we have to
implement the [NIC proposal][nic] and fully spec out and implement
[region support][reg].  However, the third and fourth options are not
incompatible, so maybe we will see both someday.

[nic]: {{< baseurl >}}/rust/no-implicit-copies#dynamically-sized-types
[reg]: https://github.com/graydon/rust/wiki/Proposal-for-regions
[coro]: {{< baseurl >}}/blog/2011/12/06/coroutines-for-rust/
[po]: {{< baseurl >}}/blog/2011/12/13/partially-ordered-unique-closures/
