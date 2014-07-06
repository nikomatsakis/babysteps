---
layout: post
title: "Parallel JS lands"
date: 2013-03-20 09:56
comments: true
categories: [PJs, JS]
---

The [first version of our work on ParallelJS][bug829602] has just been
promoted to mozilla-central and thus will soon be appearing in a
Nightly Firefox build near you.  I find this pretty exciting.  In
honor of the occassion, I wanted to take a moment to step back and
look both at what has landed now, what we expect to land soon, and the
overall trajectory we are aiming for.

[bug829602]: https://bugzilla.mozilla.org/show_bug.cgi?id=829602

<!-- more -->

### What is available now

Once Nightly builds are available, users will be able to run what is
essentially a "first draft" of Parallel JS.  The code that will be
landing first is not really ready for general use yet.  It supports a
limited set of JavaScript and there is no good feedback mechanism to
tell you whether you got parallel execution and, if not, why not.
Moreover, it is not heavily optimized, and the performance can be
uneven.  Sometimes we see linear speedups and zero overhead, but in
other cases the overhead can be substantial, meaning that it takes
several cores to gain from parallelism.  Nonetheless, it is pretty
exciting to see multithreaded execution landing in a JavaScript
engine.  As far as I know, this is the first time that something like
this has been available (WebWorkers, with their Share Nothing, Copy
Everything architecture, do not count).

**UPDATE:** It has been pointed out to me that WebWorkers were
recently extended to support *moving* typed arrays from place to
place, though there is still no way for multiple workers to *share* a
read-only view on a typed array.

We have already written several patches that we hope to land in the
near future.  These patches expand the set of JavaScript functions
that can run in parallel.  They also help to reduce compilation
overheads and generally improve performance, as well as making the
code less vulnerable to disruptions from garbage collection.

### Where we are going in the medium term

Looking at the medium term, the main focus is on ensuring that there
is a large, usable subset of JavaScript that can be reliably
parallelized.  Moreover, there should be a good feedback mechanism to
tell you when you are not getting parallel execution and why not.

I think that we can achieve a state where if you write a pure function
(meaning one that does not mutate shared state) in "plain vanilla" JS,
it will basically work.  "Plain vanilla" is of course a highly
technical industry term meaning "no weird stuff".  Intuitively, I mean
code that uses only JS objects (i.e., no DOM objects) and avoids some
of the more advanced JS features like proxies. A more rigorous
definition of what I mean by "plain vanilla" is a big piece of this
medium-term work.

Supporting "plain vanilla" JS is mostly a matter of going through
individual code paths in SpiderMonkey and refactoring them so that
they can cleanly support parallel execution.  It is difficult to do
this and keep the code relatively DRY.  We are currently exploring the
best techniques for this.  I think there is no magic bullet here,
though; the code was written to assume single-threaded execution and
is riddled with various bits of cleverness that unfortunately make it
hard to parallelize.

The other part of the story is providing feedback that informs users
when parallelization has failed and why.  Once we support a large
enough portion of JS, I think good feedback is probably even more
important than expanding the subset we support.

Finally, there will always be ongoing work on lowering overhead and
improving performance.  Some of that can come from more advanced
optimization techniques (like vectorized compilation or GPU support),
but to some extent this also arises just from looking over the
relevant code paths and tuning them repeatedly.

### Where we are going in the long term

I am basically obsessed with the idea of making parallelism easy and
omnipresent wherever I can.  The code we are landing now is a very
significant step in that direction, though there is a long road ahead.

I want to see a day where there are a variety of parallel APIs for a
variety of situations.  I want to see a day where you can write
arbitrary JS and know that it will parallelize and run efficiently
across all browsers.

I expect the final APIs with which we expose parallel execution will
evolve over time.  There will be debate, some of which is already
visible on this blog.  For example, should we just offer a
`ParallelArray` type or instead [attach methods to Array][split]?  How
*should* we specify the [semantics][semantics1] of parallel execution,
[precisely][semantics2]?  I expect that once we have good prototypes
available, this dialog will grow, paricularly as the JS community and
ECMAScript committee gets involved (neither group is exactly known for
a shortage of opinions, and rightly so).

I also want to add better support for task parallelism via something
like the [PJs][pjs] API I have talked about before.  Part of the goal
with the current work has been to lay the foundations to make it
possible to iterate on APIs and introduce new ones.

[pjs]: http://smallcultfollowing.com/babysteps/blog/2012/01/09/parallel-javascript/
[split]: /blog/2013/02/26/splitting-the-pjs-api/
[semantics1]: http://smallcultfollowing.com/babysteps/blog/2013/01/02/deterministic-or-not/ 
[semantics2]: http://smallcultfollowing.com/babysteps/blog/2013/01/03/the-case-for-deterministic-results/
