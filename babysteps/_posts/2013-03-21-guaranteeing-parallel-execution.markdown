---
layout: post
title: "Guaranteeing parallel execution"
date: 2013-03-21 10:38
comments: true
categories: [PJs, JS]
---

One common criticism of the work on ParallelJS is that the API itself
does not guarantee parallel execution.  Instead, our approach has been
to offer methods whose definition makes parallel execution *possible*,
but we have left it up to the engines to define the exact set of
JavaScript that will be safe for parallel execution.

Now, I definitely think it is a good idea to clearly define the subset
of JavaScript that our engine will be able to execute in parallel.  As
I wrote in my [preivous post][pp], I want to do this both via
documentation and via developer tools that provide live feedback.  In
some cases, I think, the rules will probably depend on type inference
or other dynamic analysis techniques that are subtle and hard to
explain, but live feedback should be helpful in detecting and
resolving those cases.

Nonetheless, I do not think that the *formal specification* of
ParallelJS should include these sorts of details.  In my view, this
would be similar to having the ECMAScript committee define what
patterns in JavaScript will be efficiently JITted and which will not.
This is ultimately going to vary depending on the implementation.

In particular, the JavaScript subset that will be acceptable is going
to vary substantially depending on what techniques are used to
implement the parallelization.  On the extreme end, if we had an
implementation based on transactional memory, you could imagine that
the *full JavaScript language* might be accepted.  If you think that's
science fiction, consider that
[newer Intel chips will have hardware support for a limited form of transactional memory][htm].
On the other extreme, engines that utilize the GPU will only support a
very limited subset, one that most likely excludes memory allocation.

I find the precedent of [asm.js][asmjs] to be a more promising
approach.  The formal specification should only state what the the
parallel methods are.  Preferably, this specification should be loose
enough to accommodate as many different parallel execution techniques
as possible, but strict enough to prevent wide divergence between
engines.  I have argued in the past for
["equivalent to some sequential execution"][equiv], and I still think
that's the right standard, but there's room for discussion on this
point.

Meanwhile, there are can be several independent specifications that
provide guidance as to what subset of JavaScript should be supported
to parallelize in different ways.  Writing such a specification now is
probably immature, I think it would be better to have multiple
JavaScript engines involved so that the specification is not tailored
to SpiderMonkey.  

It will be challenging, I think, to come up with a specification that
offers the very strong guarantees that "asm.js" can offer (no
recompilation, no bailouts, etc).  This is because "asm.js" is a
*very* narrow slice of JS intended to be output by compilers, not by
humans.  It excludes, for example, all normal JavaScript objects.
Now, a specification like this might be useful in a parallel context
as well; it could serve as the backend for other languages.  But I
would hope that we have some broader specifications that define code
that humans can write.

It is also important to point out that "asm.js" builds upon a lot of
precedent.  Smart folk working on projects like [Emscripten][e] and
[Mandreel][m] have already done a lot of the leg work to define the
idioms that "asm.js" codifies.  I hope that as ParallelJS evolves
we'll also evolve a common set of idioms and "ways of doing things"
that we can then formalize.

[pp]: /blog/2013/03/20/parallel-js-lands/
[asmjs]: http://asmjs.org/
[htm]: http://en.wikipedia.org/wiki/Transactional_Synchronization_Extensions
[equiv]: /blog/2013/01/02/deterministic-or-not/ 
[m]: http://www.mandreel.com/
[e]: https://github.com/kripken/emscripten
