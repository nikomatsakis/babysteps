---
categories:
- PJs
- JS
comments: true
date: "2012-12-05T00:00:00Z"
slug: self-hosted-parallel-js
title: Self-hosted Parallel JS
---

The blog has been silent for a while.  The reason is that I've been
hard at work on [Parallel JS][pjs].  It's come a long way: in fact,
the goal is to land an initial version in the next couple weeks!

One of the very exciting developments has been that we switched to a
*self-hosting* implementation.  Self-hosting is a very cool new
direction for the SpiderMonkey engine being introduced by
[Till Schneidereit][till].  The idea is to implement large parts of
the engine itself in JavaScript, similar to projects like
[Squeak][sq], [Jikes RVM][jp], [Maxine][max], [PyPy][pypy] and numerous
others.  As an example, imagine the standard JavaScript function
`Array.map`.  In SM, this is currently implemented with approximately
[80 lines of C++ code][amap].  This function must handle all sorts of
annoying conditions, such as [ensuring that objects are rooted][root],
[checking for interrupts][interrupt], and using an
[optimized call sequence to make it faster to invoke the JS code][fig].
If the implementation were written in JS, however, all of these issues
would be handled automatically by the engine itself, just as they are
for any other JS function.

Besides complexity, another downside to the C++ implementation of
`Array.map` is that it is *slow*.  This may seem surprising.  Isn't
C++ supposed to be faster than JS?  Well, the answer is that yes, C++
programs can be faster than JS, but only if they're operating on C++
data structures, which are significantly different than their JS
equivalents.  A C++ array, for example, is just a continuous series of
memory locations, so an array store like `a[i] = v` can be compiled
with just a few assembly instructions.  In JavaScript, though, arrays
are much more flexible: they can be sparse, for example, and they can
be dynamically grown and shrunk.  All of this means that that same
array store in JavaScript *can be* a significant more complex
operation.  Therefore, the C++ equivalent is a
[call to the JS VM function `SetArrayElement()`][setarrayelemcall].
This function is very general and can handle all of the various
possibilities that come up.

Using a helper function is unfortunate because, in the common case, a
JS array is actually represented in the engine using a simple C++
array, meaning that the store `a[i] = v` could (normally) be compiled
into a simple store, just like in C++.  And in fact, if the loop were
written in JS, the JIT would do just that; it would only resort to
something as general as `SetArrayElement()` if it proved to be
necessary during execution.

There are other reasons that the C++ code is slower than JS code would
be.  The interfacing to the GC is more awkward, for example, since the
compiler cannot generate a stack map to tell us where pointers are
located.  The transition between C++ and JS code requires a bit of
adaptation since the IonMonkey compiler uses a calling convention that
is specialized to the needs of JS.  And so on.

#### Intrinsics

Of course, replacing C++ with JavaScript is not all rainbows and
sunshine.  There are complications.  For one thing, the C++ code is
able to do special things that normal JavaScript is not capable of; it
is also involved with some internal details that JavaScript functions
do not normally need to be concerned with.  To help with these cases,
self-hosting introduces the idea of *intrinsic function*.  An
intrinsic function is a special JS function, implemented in C++, that
is only available to the self-hosted code.  Intrinsics can be used to
expose extra capabilities to the self-hosted code, which is really
internal to the engine, without exposing them to all JavaScript code.

To set them apart, intrinsic functions are currently given a name that
starts with a `%` sign (e.g., `%Foo()`). The plan as I understand it,
though, is to replace these names with normal JS identifiers.

In Parallel JS, we use intrinsics to expose a single, underlying
parallel operation.  This operation is then used to implement the
other higher-level parallel ops (`map()`, `filter()`, `reduce()`,
`scan()`, and `scatter()`).  Unlike the higher-level ops, the
intrinsic parallel operation is not safe.  It can induce data races.
It will also fail if the function it is applied to cannot be compiled
for parallel execution for whatever reason, unlike the higher-level
ops.

[pjs]: {{ site.baseurl }}/blog/categories/pjs
[till]: http://www.tillschneidereit.de
[sq]: http://www.squeak.org/
[jp]: http://www.research.ibm.com/jalapeno/publication.html
[max]: http://labs.oracle.com/projects/maxine/
[pypy]: http://pypy.org/
[amap]: https://github.com/mozilla/mozilla-central/blob/7ca138ebf9ab8f0f1e981af486b9af6206fd0d15/js/src/jsarray.cpp#L2943
[root]: https://github.com/mozilla/mozilla-central/blob/7ca138ebf9ab8f0f1e981af486b9af6206fd0d15/js/src/jsarray.cpp#L2948
[interrupt]: https://github.com/mozilla/mozilla-central/blob/7ca138ebf9ab8f0f1e981af486b9af6206fd0d15/js/src/jsarray.cpp#L2986
[fig]: https://github.com/mozilla/mozilla-central/blob/7ca138ebf9ab8f0f1e981af486b9af6206fd0d15/js/src/jsarray.cpp#L2983
[setarrayelemcall]: https://github.com/mozilla/mozilla-central/blob/7ca138ebf9ab8f0f1e981af486b9af6206fd0d15/js/src/jsarray.cpp#L3006
