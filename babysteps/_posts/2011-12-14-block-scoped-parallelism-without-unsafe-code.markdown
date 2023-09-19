---
layout: post
title: "Block-scoped parallelism without unsafe code"
date: 2011-12-14 15:32
comments: true
categories: [Rust, PL]
published: false
---

I've been discussing my [evolving][bsp1] [ideas][bsp2] for a simple mechanism for
block-scoped parallelism.  Till now, I've been assuming that the implementations of
the parallel patterns themselves are trusted and unsafe.  I'm actually quite comfortable
with this, but pcwalton isn't, and it'd be nice if it weren't necessary, at least not
for simple cases.  Anyway, last night it occurred to me that one could generalize the
mechanism using a fork-join mechanism similar to Doug Lea's [Fork-Join 
Framework][fjf] that would be at once very flexible and data-race free.

The idea builds on the [par blocks][bsp1] I've been proposing.  For review,
a par block is essentially a block that can only access upvars through `const`-ified
types; in addition, the argument types of a par block must be sendable, meaning that
the only pointers which may be contained are unique pointers (this restriction
is new and was born out of discussions with pcwalton). This guarantees that
multiple par blocks may run in parallel with one another, as the only shared state which
they can both access (the upvars) are read-only.  They may still have exclusive and mutable
access to data which is given them through parameters or which they create 
during their own execution. Like all blocks, they may return values as well.


[bsp1]: {{ site.baseurl }}/blog/2011/12/09/pure-blocks/
[bsp2]: {{ site.baseurl }}/blog/2011/12/13/const-vs-mutable/
[fjf]: http://docs.oracle.com/javase/tutorial/essential/concurrency/forkjoin.html