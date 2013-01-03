---
layout: post
title: "Purity in Parallel JavaScript"
date: 2012-10-24 13:54
comments: true
categories: [PJs]
---

I can't believe I'm saying this, but I've started to think that
Parallel JS (nee Rivertrail) should not demand pure callbacks to
functions like `map()` and so forth.  Rather it should just accept
arbitrary functions.  Previously, I thought that it was important that
`ParallelArray` methods should only accept functions which, at least
in a perfect world, would be safely parallelizable.  But I am no
longer so sure why that is an important goal.  Here is my reasoning.

First, we always retain the right to execute sequentially.  If we're
executing sequentially, it's actively *harder* to enforce purity than
it is to permit mutation---we will have to put in place some kind of
proxying or write monitoring.  I would really like it if using
`ParallelArray` methods was never slower than writing an equivalent
for loop in JavaScript.  That is, writing `parallel_array.map(f)`
should not be slower than `normal_array.map(f)`.  But if we have to
impose write monitoring, it *will* almost certainly be slower, in the
event that we cannot parallelize.  It will also be less general.

Second, it's not clear to me what negative side effect (no pun
intended) comes of permitting mutation in the callbacks.  In cases
where we can tell at compile time that the function is safe, we can
permit it to execute in parallel.  In cases where we cannot, we can
speculatively run in parallel and then monitor the suspicious writes
(as indeed we do today).  If we detect a violation, it just means we
fallback to sequential (just as we do today).  It's not like telling
users they are not supposed to write to shared data means that they
will not; ultimately, we must always be ready to enforce this contract
dynamically, so the only question is what happens when we detect a
violation.
