---
layout: post
title: "Parallelizable JavaScript Subset"
date: 2013-04-30 11:30
comments: true
categories: [PJs, JS]
---
I want to look at an interesting topic: what subset of JavaScript do
we intend to support for parallel execution, and how long will it take
to get that working? As my dear and loyal readers already know, our
current engine supports a simple subset of JavaScript but we will want
to expand it and make the result more predictable.

From my point of view, the subset below includes basically all the
JavaScript syntax that I ever use. There are two primary limitations
that I think people will encounter in practice:

1. *The fact that mutating shared state boots you out of parallel
   mode.* This restriction is (I think) easy to understand, but it
   will often take some restructuring to obey it.
2. *The fact that strings and many native objects (regular
   expressions, DOM objects, etc) are currently not supported.* I
   expect we'll improve the support for strings in the near term and
   also for some native objects, but for others---notably DOM---it
   will be *very* challenging to make things work in parallel, due to
   the many complex implementation details.

OK, let's get to the details. In the list that follows, we often refer
to a *plain old JavaScript object* (POJO), which means an object
defined in JavaScript, not a built-in object. It should be created
either with a literal (`{...}`, `[...]`) or a `new C` expression where
`C` is a user-defined function. I've also written *bug* for cases
where the current implementation is more limited than it should be.

- `a`: Variable access
  - You should be able to access any variable in scope, so long as you
    do not use `with` or `eval`. I think this all works fine today,
    though there may be errors in the implementation today relating to
    infrequently used access patterns, such as `"use strict"`.
- `a.b`: Property access
  - If `a` is a POJO and `b` is a data property
    - no getters (should work someday)
- `a[e]`: Element access
  - If `a` is a POJO or a TypedArray
- `a + b`, `a - b`, etc: Binary operators
  - for any primitive values (someday we should be able to support all objects)
  - *bug:* today, only works if `a` and `b` are both numbers or bools
     (in any combination)
- `a === b`, `a !== b`: Strict equality and unequality
  - always works
- `a == b`, `a > b`, etc: Loose relational operators
  - works if `a` and `b` are both numbers or bools (in any combination)
- `a[i] = b`: Numeric property assignment
  - if `a` is a POJO or TypedArray owned by current task, and `i <=
    a.length` (no holes---*not yet, anyway*)
  - *bug:* today, we must successfully predict that `a` will be an array
    or typed array. In practice, this preciction is reasonably successful,
    but problems arise when the same function is called many times from
    different contexts.
- `a.e = b` or `a["e"] = b`: String property assignment
  - if `a` is a POJO owned by the current task
  - *bug:* today, we must successfully predict the offset of `e` within `a`.
    In practice, this prediction often fails, as the code must be written
    very, very carefully for it to work.
- `{...}`, `[...]`, `new C(...)`: object literals and creation
  - for `new C(...)`, C must be a JavaScript function
- `f()` and `a.m(...)`: Function and method calls
  - If the function being called is a user-implemented function, or
    one of the functions in the following list:
    - higher-order functions like `map`, `reduce`, etc
    - parallel higher-order functions like `pmap`, `preduce`, etc
    - `Array.push` (presuming the receiver is writable)
      - *bug:* today only `a[a.length] = e` works, not `a.push(e)`
    - `Math.*`
      - *bug:* today, most but not all `Math` functions work, and only
        if we predict the function that will be called and are able to
        inline it. In practice, this prediction is almost always
        successful.
    - (more to come)
- `function(a, b) { ... }` or `(a, b) => { ... }`: closure creation
  - this should basically always work, I think
  - *bug:* the `=>` syntax doesn't work yet in parallel execution, I
     don't believe
- `if`, `while`, etc
  - works fine

One caveat I should point out in the current implementation: even if
you stick to the above subset, it is possible that *some* parallel
iterations will abort, generally because of mispredicted types or
other transient errors. But I consider a parallel abort to be ok if
the engine will eventually stabilize and all subsequent runs will be
successful. This is the same as what happens with JIT engines, which
often generate code that is later invalidated and recompiled.
