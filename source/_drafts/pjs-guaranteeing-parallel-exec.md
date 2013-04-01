---
layout: post
title: "Guaranteeing parallel execution"
date: 2013-03-20 10:04
comments: true
categories: [PJS]
---

One common criticism of the work on ParallelJS is that the API itself
does not guarantee parallel execution.  Instead, our approach has been
to offer methods whose definition makes parallel execution *possible*,
but we have left it up to the engines to define the exact set of
JavaScript that will be safe for parallel execution.

As you can see from my [previous post][pp], I do not think that this
means that we should make no effort to define what subset of
JavaScript can be expected to run in parallel.  I just think that we
should avoid making this part of the formal specification.  In my
view, this would be similar to having the ECMAScript committee define
what patterns in JavaScript will be efficiently JITted and which will
not.  These kind of implementation-dependent details do not belong in
a formal spec, to my mind.

I would rather see a separate document similar to [asm.js][asmjs] that
defines a subset of JavaScript that users can rely upon to be
parallelized (let's call this "par.js" for now).  Browsers can then
aim to implement and build upon this specification.  Now, whereas
asm.js is intended to be output by compilers, I would hope that
"par.js" would be broader, so that it covers code humans would
naturally write.

In fact, I imagine there will be a need for multiple "par.js"
specifications.  For example, not everything that can be parallelized
using a multithreaded implementation will be vectorizable or able to
run on the GPU.

I see the task of building such a specification as an important
mid-term goal.  But it will also be an evolving document; as
implementations become more advanced, we can grow the set of
constructs that are legal and safe.  In addition, other browsers will
hopefully start to add support for these APIs and features.

[pp]: /blog/2013/03/20/parallel-js-lands/
[asmjs]: http://asmjs.org/
