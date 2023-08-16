---
categories:
- PJs
- JS
comments: true
date: "2013-11-04T00:00:00Z"
slug: optimizing-complex-typed-object-assignments
title: Optimizing complex typed object assignments
---

I want to optimize assignments to struct-typed fields in typed
objects. This post is an effort to work through my optimization plan.

<!--more-->

### The goal

Imagine some code like this:

    var PointType = new StructType({x: int32, y: int32});
    var LineType = new StructType({from: PointType,
                                   to: PointType});
    var line = new LineType();
    line.to = {x: 22, y: 44};
    
The last line in particular is the one I am interested in.  Today we
execute this in the most naive way. The code which ion generates looks
something like:

    var tmp = {x: 22, y: 44};
    SetProperty(line, "to", tmp) // a C++ helper

This means that a fresh temporary object `tmp` is allocated. There is
no special optimization for setting properties whose types are complex
types like `PointType`, so `line.to` results in a call into the
interpreter, which eventually calls the [self-hosted function][cct]
`ConvertAndCopyTo`. This function will reflectively walk `tmp`,
essentially doing the equivalent of:

    var tmp = {x: 22, y: 44};
    line.to.x = int32(tmp.x);
    line.to.y = int32(tmp.y);

There are many sources of inefficiency here:

1. Constructing the temporary object `tmp`.
2. Going into C++ code from JS then back to self-hosted JS.
3. The reflective walk done by `ConvertAndCopyTo`.

The pending patch in [bug 933289][933289] eliminates point 2.
Basically all the patch does is to convert the generic `SetProperty`
call, which goes into C++ and then into self-hosted code, so that it
directly invokes the self-hosted code. Therefore the generated code
now looks like:

    var tmp = {x: 22, y: 44};
    ConvertAndCopyTo(Point, line, 8, tmp)

This is a slight optimization in that we've baked in the offset of the
`to` field (8 bytes) and we avoid the JS to C++ to JS transition, but
we are still allocating a temporary and we're still using a reflective
walk to read out and copy the properties. What I'm looking at now is
how we can eliminate those two parts.

### Optimizing in stages

My plan is to add two optimizations. The first would expand calls to
`ConvertAndCopyTo` into a series of assignments in the case where we
know the type of the value being assigned. Therefore, a call like
`ConvertAndCopyTo(Point, line, 8, tmp)` would be expanded in place to
something like:

    var tmp = {x: 22, y: 44};
    line.to.x = int32(tmp.x)
    line.to.y = int32(tmp.y)
    
Next, a second optimization would detect reads like `tmp.x` where
we can statically determine the result and propagate the value. This
means that the code above would be optimized to:

    var tmp = {x: 22, y: 44};
    line.to.x = int32(22);
    line.to.y = int32(44);
    
Finally, dead-code elimination should be able to remove the temporary.

This approach has the advantage that the second half can benefit
general code. For example, a common pattern in some of the PJS code
I've looked is to use constant vectors like so:

    var constantFactors = [3.14159, 2.71828, 6.67384];
    var x = constantFactors[0] * vector[0];
    var y = constantFactors[1] * vector[1];
    var z = constantFactors[2] * vector[2];
    
The same optimization would constant propagate those uses. (I don't
believe we optimize this kind of code today; of course, if we do,
that's great, less work for me.)

### One tricky case

However, after some discussion with jandem on IRC, I realized that
this strategy was overly ambitious. In particular, the first step
which expands calls to `ConvertAndCopyTo` provides no way to recover
in case the JIT code should be invalidated. In the running example,
this isn't an issue, but in general a read like `tmp.x` or `tmp.y`
could in fact access a getter and have arbitrary side-effects. That
means that we must be able to bailout of the jitted code and resume
execution in the interpreter.

For example, imagine some code like:

    line.to = evilObject;
    
this line would be optimized to:

    ConvertAndCopyTo(Point, line, 8, evilObject)
    
and that call would in turn be expanded to:

    line.to.x = int32(evilObject.x);
    line.to.y = int32(evilObject.y);

Now imagine that `evilObject.x` is in fact a getter that modifies some
global variables, and `evilObject.y` is a getter that throws an
exception. Since throwing exceptions boots us out of jitted code, that
means that we have to bailout to the interpreter while reading
`evilObject.y`. The problem is that the interpreter only has a single
bytecode for the entire assignment; it doesn't have a way to represent
having partially progressed through the assignment. And, since
accessing `evilObject.x` actually mutates a global variable, we can't
just re-do the entire assignment.

To avoid this scenario, we can lean on TI so as to ensure that we only
expand `ConvertAndCopyTo` calls when we can ensure that the source
value properties are normal data properties and hence accessing them
will not produce globally visible side-effects. This means that even
if we do have to throw or revert, we can always bail out and repeat
the entire assignment without ill effects.

At least that's my plan! I hope to hack some on this tonight /
tomorrow, so we'll see if I encounter any surprises.

[cct]: http://dxr.mozilla.org/mozilla-central/source/js/src/builtin/TypedObject.js#l349
[933289]: https://bugzilla.mozilla.org/show_bug.cgi?id=933289
