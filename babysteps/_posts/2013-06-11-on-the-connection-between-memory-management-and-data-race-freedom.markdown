---
layout: post
title: "On the connection between memory management and data-race freedom"
date: 2013-06-11 16:01
comments: true
categories: [Rust]
---

As I alluded in the [previous post][pp], I have noticed an interesting
connection between *memory management* and *data-race freedom*. I want
to take a moment to elaborate on this, becaause the connection was not
obvious to me at first, but it ultimately drives a lot of the Rust
design decisions.

First, I believe that if you want to guarantee data-race freedom, and
you want to support the cheap transfer of mutable state between tasks,
then you must have a garbage-collector-free subset of your
language. To see what I mean by "cheap transfer of mutable state",
consider something like double-buffering: you have one drawing and one
display task exchanging buffers (so there are only two buffers in
total).  While the drawing task is preparing the next frame, the
display task is busy displaying the current one. At the end, they
exchange buffers.  In order to prevent data races in a scenario like
this, it is vital that we be able to guarantee that when the buffers
are exchanged, neither task has any remaining references. Otherwise,
the display task would be able to read or write from the buffer that
the drawing task is currently writing on.

Interestingly, if we wanted to *free* one of those buffers, rather
than send it to another task, the necessary safety guaranty would be
precisely the same: we must be able to guarantee that there are no
existing aliases. Therefore, if you plan to support a scenario like
double buffering *and guarantee data-race freedom*, then you have
exactly the same set of problems to solve that you would have if you
wanted to make GC optional. Of course, you could still use a GC to
*actually free* the memory, but there is no reason to, you're just
giving up performance. Most languages opt to give up on data-race
freedom at this point. Rust does not.

But there is a deeper connection than this. I've often thought that
while data-races in a technical sense can only occur in a parallel
system, problems that *feel* a lot like data races crop up all the
time in sequential systems. One example would be what C++ folk call
*iterator invalidation*---basically, if you are iterating over a
hashtable and you try to modify the hashtable during that iteration,
you get undefined behavior. Sometimes your iteration skips keys or
values, sometimes it shows you the new key, sometimes it doesn't, etc.
In C++, this leads to crashes. In Java, this (hopefully) leads to an
exception.

But whatever the outcome, iterator invalidation feels very similar to
a data race. The problem often arises because you have one piece of
code iterating over a hashtable and then calling a subroutine defined
over in some other module. This other module then writes to the same
hashtable.  Both modules look fine on their own, it's only the
combination of the two that causes the issue. And because of the
undefined nature of the result, it often happens that the code works
fine for a long time---until it doesn't.

Rust's type system prevents iterator invalidation. Often this can be
done statically. But if you use `@mut` types, that is, mutable managed
data, we do the detection dynamically. Even in the dynamic case, the
guarantee that you get is much stronger than what Java gives with
fail-fast iteration: Rust guarantees failure, and in fact it even
points at the two pieces of code that are conflicting (though if you
build optimized, we can only provide you with one of those locations,
since tracking the other causes runtime overhead right now).

One reason that we are so intolerant towards iterator invalidation is
because we wish to guarantee memory safety, and we wish to do so
without the use of universal garbage collection (since, as I just
argued before, it is basically unnecessary if you also guarantee
data-race freedom). Without a garbage collector, iterator invalidation
can lead to dangling pointers or other similar problems. But even
*with* a garbage collector, iterator invalidation leads to undefined
behavior, which can in turn imply that your browser can be compromised
by code that can exploit that behavior. So it's an all-around bad
thing.

Therefore, I think it is no accident that the same type-system tools
that combat iterator invalidation wind up being
[useful to fight data-races][pp]. Essentially I believe these are two
manifestations of the same problem---unexpected aliasing---in one
case, expressed in a parallel setting, and in the other, in a
sequential setting. The sequential case is mildly simpler, in that in
a sequential setting you at least have a happens-before relationship
between any two pairs of accesses, which does not hold in a parallel
setting.  This is why we tolerate `&const` and `&mut` aliases in
sequential code, but forbid them with closure bounds in parallel code.

In some way this observation is sort of banal. Of course mutating
without knowledge of possible aliases gets you into trouble. But I
think it's also profound, in a way, because it suggests that these two
seemingly unrelated issues, memory management and data races, cannot
be truly separated (except by sacrificing mutability).

Most languages make no effort to control aliasing; if anything, they
use universal garbage collection to prevent the end user from having
to reason about when aliasing might exist to a given piece of
data. This works well for guaranteeing memory is not freed, but as
I've suggested, it can lead to a variety of incorrect behaviors if
mutation is permitted.

This observation has motivated a lot of the research into ownership
types and linear types, research which Rust draws on. Of other recent
non-research languages, the only other that I know which takes the
approach of controlling aliasing is [Parasail][parasail]. Not
coincidentally, I would argue, both Rust and Parasail guarantee
data-race freedom, while most langauges do not.

[pp]: {{ site.baseurl }}/blog/2013/06/11/data-parallelism-in-rust/
[parasail]: http://parasail-programming-language.blogspot.com/
