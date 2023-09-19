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
gleaned from a conversation or two.  It it is almost certainly not
*entirely* accurate and it may or may not be helpful.

**UPDATED 2012/07/31**: I made some substantial edits based on
feedback from `djvj` which clarified the interaction between property
type sets and the type sets associated with each load.  This actually
makes much more sense to me now than it did before, maybe to you too.

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

then the type object for `b` will have a property `g` with a type set
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
there will be typesets also for intermediate variables and also for
bytecodes.  So if I have an instruction like:

    next = d.e + 1
    
then the read from `d.e` will have an associated type set recording
*what types it saw at this particular property load*.  This is an
important point, because the type set `D.e` that summarizes all types
that may be in the property `d.e` may be larger than the set of types
that actually get read at this particular spot in the code.  In other
words, if there are two kinds of `d` objects, some with integers and
some with strings, then `D.e` will contain both integers and strings.
Due to the imprecision of the analysis, both types of objects are
being lumped together into the same type object.  But perhaps this
particular load only ever sees the objects that contain integers.  As
we'll see in a bit, type inference handles this case elegantly,
allowing us to continue generating code that assumes `d.e` is an
integer, while recovering if that should prove false.

### Type barriers

During execution, type sets generally only record the values which
have actually been observed.  What this means is that merely *storing*
a value into a property is not enough to affect its type set.  So, for
example, suppose that there is a sequence of code like this:

    a = b.c
    d.e = a

Now, support that before this code runs, the type set `D.e` associated
with `d.e` only contains integers.  Further suppose that the value `a`
is a string. The state of the system might then look something like
this:

     +-----+                 +-----+
     | "B" |                 | "D" |
     +-----+     /-------\   +-----+     /-------\
     | "c" |---->| "str" |   | "e" |---->| "int" |
     +-----+     \-------/   +-----+     \-------/
     
Here you see that the type set `B.c` has strings in it, and the
type set for `D.e` has integers in it.  

If this were a standard type inference algorithm, the above state
would not be possible.  This is because a value is being copied from
`b.c` into `d.e`, and hence the type set `D.e` ought to be a superset
of the typeset `B.c`.  But this is not so.  "Ok", you might think,
"perhaps the algorithm waits until the assignment *occurs* to do the
propagation".  In that case, after the code executed, the type set
`D.e` would contain both `int` and `str`.  In fact that is what happens,
but there is a twist.

While it's true that the type set for `D.e` is updated, it's not true
that the type sets for *loads of the property e* are updated.  When
the store executes, the engine observes that a string has been added
to `D.e`, but it prefers to take an optimistic approach and assume
that those places which read `d.e` will continue to only see integers
and not observe this string value.  But of course we can't ignore the
string type completely. So instead of modifying the type set for each
load, the engine adds a *type barrier*.  This is basically a note on
the load saying, "Hey, some of the objects you are loading from may
contain strings, but I've never actually seen one come out."

To understand the practical impact of a type barrier, consider a snippet
of code like the following:

    next = d.e + 1

Here the value `d.e` is being read, where `d` is the same object that
was stored into before (or actually any object associated with the
type object `D`).  Remember that there will be a type set for `D.e`,
indicating all values that may possible be read, and a separate type
set (let's call it `L`) for the load itself.  Before the `str` is
added to `D.e`, these two type sets are the same, and hence the JIT
will assume that `d.e` will produce an integer and generate
specialized code that simply reads the value out of the property,
casts it to an integer, and adds 1 to it.  But once the store to `d.e`
occurs with a string value, `D.e` will contain an `int` and a `str`.
This does not (yet) modify `L`, however, so the JIT will *still*
assume that `d.e` is an integer. But it does cause a type barrier to
be added to `L`, so the JIT will add additional code to check and make
sure that it saw an integer and not a string (if there was existing
JIT code, adding a type barrier might entail throwing it out or
performing on-stack replacement).

Now so long as that string is never actually read, the type set `L`
continues to contain only an integer, but every access to the property
will check for a string.  Once a string is actually *observed*, the
type set `L` will be updated. This can trigger additional code
invalidation for those places which relied upon reading only an
integer.

Updates to type sets also triggers a certain amount of propagation
based on a traditional static constraint graph generated from the
code.  I don't *fully* understand the constraint graph in detail yet.
One thing I do know is that, unlike a static constraint graph, it
contains two sorts of edges (in reality, probably more).  One edge is
a traditional subset edge that ensures that one type set is a subset
of the other.  The second edge is a barrier edge which says "if this
type set A is bigger than B, it is possible that values from A have
been stored into B, so add a type barrier to watch for them".  This is
the same mechanism that we just discussed.  Basically it's more
efficient and accurate to use traditional constraint edges, but they
can lead to a loss of overall precision, so there are some heuristics
that guide the decision about which kind of edge to use in order to
get the best overall results.

### Conclusion

The key idea of the TI system is to be *optimistic*.  As much as
possible, it resists changing type sets until it is forced to by
actually observing new values.  However, via barriers, it always
retains a summary of what kinds of values might be in each type set
which it is currently ignoring.

By associating type sets not only with the heap objects but with the
loads of properties themselves, TI is also able to shape specialized
paths and to overcome some of the inherent imprecision in the type
analysis itself.

As usual, writing up and explaining something is a good way to find
the limits of your understanding.  I think I have a feeling for how
this propagation works, but it's not quite as crystal clear as I'd
like it to be.  In particular I don't understand the particulars of
the constraint graph and I don't quite understand when constraints are
active.
