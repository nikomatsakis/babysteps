---
layout: post
title: "Type inference in Spidermonkey"
date: 2012-07-30 08:21
comments: true
categories: [PL, Spidermonkey, Rivertrail]
---

I've been slowly learning how [type inference][ti] works in
SpiderMonkey.  As I understand it, SpiderMonkey's type inference
scheme is the brain child of one Brian "Hack-it", coder
extraordinaire.  You may have seen a [recent PLDI publication][pldi]
on the topic. You may, like me, have read that publication.  You may,
also like me, have walked away thinking, "um, I don't really
understand how that works."  In that case, dear reader, this blog post
is for you.  Well, actually, it's for me, to try and document what I
gleaned from a conversation or two.  It may or may not be accurate
(almost certainly not) and it may or may not be helpful.

<!-- more -->

[ti]: https://wiki.mozilla.org/TypeInference
[pldi]: http://dl.acm.org/citation.cfm?id=2254094

The key distinction of SM's Type Inferencer (hereafter, just TI) is
that it is optimistic, not conservative.  It is also dynamic, meaning
that it adjusts during the execution of your program.  Basically, as
new types are observed, TI will adjust its estimate of what types are
likely to appear at each point.

### Type objects and type sets

In a traditional static type inference scheme, the inferencer will
create a fixed number of summary objects to represent the objects that
will exist at runtime.  Each runtime object will be associated with a
summary object; usually the summary objects are mapped to new
statements in the source code, so each runtime object is associated
with the summary object corresponding to the line where it was
instantiated.

TI has a similar concept called *type objects*.  Each JavaScript
object is associated with a type object, usually corresponding (again)
to the line where it was allocated.  Each function also has its own
type object and so forth. The type object will summarize the types for
a (potentially infinite) group of objects at runtime.

Each Type Object contains a mapping from properties to *type sets*.  A
type set is a set of possible types that this property might have;
these can be either the primitive types or other type objects.  So,
if you have some code like this:

    var a = {f:3};
    var b = {g:a};

then the type object for `b` will have a property `f` with a type set
containing the type object for `a`.  In general, I will use the
convention that objects are named with lower-case letters and their
corresponding type objects are named with upper-case letters.  So,
here, `a`/`b` are the objects and `A`/`B` are the corresponding type
objects.  Therefore, we can say that `B.g` includes `A`.

Graphically, this can be depicted like so:

     +-----+                 +-----+
     | "A" |                 | "B" |
     +-----+     /-------\   +-----+     /-----\
     | "f" |---->| "int" |   | "g" |---->|     |
     +-----+     \-------/   +-----+     \-----/
        ^                                   |
        |                                   |
        +-----------------------------------+


Here, the square-edged (`+`) boxes depict type objects, and the
rounded-edged (`/`) boxes depict type sets.  Each type object has a
list of properties and each property has an associated type set.  The
edge from the type set for `b.g` leads to the type object for `a`.

Type sets are also use to summarize the set of types at various
program points.  For example, each function has a type set for each of
its parameters as well as its return type.  When analyzing a function,
there will be typesets also for intermediate variables.

### Type barriers

During execution, type sets generally only record the values which
have actually been observed.  What this means is that merely *storing*
a value into a property is not enough to affect its type set.  So, for
example, suppose that there is a sequence of code like this:

    a = b.c
    d.e = a
    
Now, support that before this code runs, the type set `D.e` associated
with `d.e` only contains integers.  Further suppose that the value `a`
is a string. You might think that after this code executed the type
set `D.e` would contain both integers and strings.  You'd be wrong.

In fact, the type set is unaffected.  Instead, when the store
executes, the engine observes that a string has been added to this
property, but it prefers to take an optimistic approach and assume
that the string will never actually be *read out*.  But of course we
can't ignore the string type completely. So instead of modifying the
type set, the engine adds a *type barrier*.  This is basically a note
on the type set saying, "Hey, I've seen a string go in here, but I've
never seen it come out."

To understand the practical impact of a type barrier, consider a snippet
of code like the following:

    next = d.e + 1
    
Here the value `d.e` is being read, where `d` is the same object that
was stored into before (or actually any object associated with the
type object `D`).  Before the type barrier was added to the type set,
the JIT would have assumed that `d.e` was an integer, and hence
generated specialized code that simply read the value out of the
property, casted it to an integer, and added 1 to it.  But then the
store to `d.e` occurred with a string value.  Now, the type set still
contains only `int`, so the JIT will *still* assume that `d.e` is an
integer; but because of the type barrier, it will also add a check to
see whether in fact the value which was read is a string (if there was
existing JIT code, adding a type barrier might entail throwing it out
or performing on-stack replacement).

Now so long as that string is never actually read, the type set `D.e`
continues to store only an integer, but every access to the property
will check for a string.  Once a string is actually *observed*, the
type set updates itself.  This triggers a certain amount of
propagation based on a constraint graph generated from the code.  I
don't *fully* understand the constraint graph in detail yet, but my
high-level understanding is that the TI analysis code constructs a
constraint graph based on the JS source.  When new values appear in a
type set, these will sometimes be propagated into other type sets, or
they may trigger new barriers.  Basically there are various heuristics
that determine whether a value is eagerly propagated from one type set
to another or whether the propagation merely triggers a new type
barrier.

### Conclusion

The key idea of the TI system is to be *optimistic*.  As much as
possible, it resists changing type sets until it is forced to by
actually observing new values.  However, via barriers, it always
retains a summary of what kinds of values might be in each type set
which it is currently ignoring.

As usual, writing up and explaining something is a good way to find
the limits of your understanding.  I think I have a feeling for how
this propagation works, but it's not quite as crystal clear as I'd
like it to be.  In particular I don't understand the particulars of
the constraint graph and I don't quite understand when constraints are
active.
