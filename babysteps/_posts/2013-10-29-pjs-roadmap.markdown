---
layout: post
title: "PJS Roadmap"
date: 2013-10-29 17:51
comments: true
categories: [PJs, JS]
---
I think someone reading this blog would be forgiven for thinking that
I must spend most of my energy thinking about Rust. In fact I spend a
good part of my working hours hammering on PJS. I thought I'd try to
write up a bit of a preview of the things we are working on.

### Parallel methods on arrays

Right now, on Nightly Firefox builds, you can use the parallel methods
`mapPar`, `filterPar`, and `reducePar` on normal JS arrays. These work
basically like their sequential equivalents except that they execute
in an undefined order (for `reducePar`, that can be a more significant
difference, since both the left and right operand might be the result
of a reduction). That means you can write code like:

    var x = [...];
    x.mapPar(function(e) { return ...; })
    
We don't expect major changes to these methods, except that things
will continue to work faster and with a broader range of functions.
The major change I expect, which is backwards compatible, is that
`mapPar` and `filterPar` will change from having an undefined
execution order to having a defined order that is the same as `map`
and `filter` (in other words, they will become "drop-in" replacements
for `map` and `filter`). But we're not ready yet to commit that things
won't change, and hence these methods will stay confined to Nightly
builds only for the time being.

Besides improving the runtime itself, the two major areas of development
for these methods are:

1. Developer feedback: We'd like to improve the feedback that
   one gets from the JIT in general, and particularly with respect to
   parallel execution, to make it easier to track down why you may
   be getting parallel execution.
   
2. Supporting a wider set of JS features: there are a few common
   constructs that block parallel execution right now. Prime among
   them is regular expressions. It'd be great to fix those.
   
### Typed objects

My main focus has been on implementing the typed objects API and
integrating it into our existing parallel support. Typed objects on
Nightly are in a transitional state: they partially conform to the
final API, but a lot of work has not yet landed. I hope to land the
remainder over this week and next.

Two big pieces of functionality are still missing. The first is the
ability to create a typed object that is layered atop an array buffer.
The second is to be able to extract an array buffer from a typed
object.  In both cases, the *best* way to handle this would be to
merge typed arrays and typed objects completely, but since the
performance of typed arrays is so crucial, I expect to first create
bridges between the two types and then finally remove the bridge
altogether. The latter is a long-term goal.

I implemented the the basic optimization strategy
[that I described before][pp], but it is still necessary to extend
that code to handle array elements (that is, we will currently
optimize an expression like `foo.x` or `bar.x = 22`, but not `foo[1]`
or `bar[3] = 22` (where `foo` and `bar` are typed objects or handles).

The other big piece of work is that we need to optimize typed object
creation. I would like idiomatic code like the following:

    var point = new PointType({x: 22, y: 44});

to compile efficiently, without creating any intermediate objects. The
same optimizations I have in mind will also make large assignments
like the following more efficient:

    line.from = {x: 22, y: 44}; // where line.from is a PointType
   
### Integrating the two

Once typed objects are fully working, we need to ensure that parallel
higher-order methods like `mapPar` etc work and work efficiently.  We
have currently built a [prollyfill] implementing roughly the desired
API. The prollyfill works but only on [my branch] at the moment. It'll
work on Nightly once the typed object patches are fully
landed. However, the prollyfill is pretty slow right now due to the
absence of good optimization for typed objects and the absence of
parallel execution.

There are two main work items here, one high and one low priority.
The high priority item is that we'll have to adjust the write guard
code to understand [out pointers][outp].

The low priority item is that we'll need to implement fallback paths
that ensure that even when the JIT cannot fully optimize typed
objects, we can still stay in parallel execution. I am not quite sure
how this will look. Most likely it will mean extending the ICs to
support typed objects (a good idea that will benefit sequential code
too); I've also made a point to [self-host] the typed objects
implementation where possible, which should help with parallelization.

### Timeline

The current goal is to have efficient parallel execution for typed
objects by January. I still think this can be achieved. If we can have
the optimized variations on typed objects working by November, that
gives two months to integrate which seems reasonable, though not
generous.

[pp]: http://smallcultfollowing.com/babysteps/blog/2013/07/19/integrating-binary-data-and-type-inference-in-spidermonkey/
[prollyfill]: https://github.com/nikomatsakis/pjs-polyfill
[self-host]: https://bugzilla.mozilla.org/show_bug.cgi?id=898362
