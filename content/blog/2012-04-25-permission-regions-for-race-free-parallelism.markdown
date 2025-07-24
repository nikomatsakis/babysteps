---
layout: post
title: "Permission regions for race-free parallelism"
date: 2012-04-25T17:50:00Z
comments: true
categories: [Papers]
---

I've been making a point of reading academic papers on the train as I
ride home.  It's so easy to get behind with the sheer quantity of work
that is being produced.  Anyway, it occurred to me that I ought to try
and summarize the papers I read on this blog so that I can I remember
my reactions to them.

I'll start with "Permission Regions for Race-Free Parallelism", by
Westbrook, Zhao, Budimilic, and Sarkar.  The basic idea builds off of
Habanero Java, which is a kind of fork of the X10 language that Sarkar
and his group work on.  The basic idea of the paper is to add a
language construct `permit` which looks like:

    permit read(x1,...,xn) write(y1,...,yn) {
        /* this code may read fields of x1...xn and write
           fields of y1...yn */
    }

For example, imagine a method `pop()` that removes an item from the
front of a linked list:

    Node pop() {
        Node tmp = this.next;
        if (tmp != null)
            this.next = tmp.next;
        return tmp;
    }
    
This would be annotated like so:

    Node pop() {
        permit write(this) {
            Node tmp = this.next;
            if (tmp != null)
                permit read(tmp)
                    next = tmp.next;
            return tmp;
        }
    }
    
A dynamic monitoring system will then guarantee check for races at the
granularity of the `permit` blocks.  An effect system also allows a
method to be called under the stipulation that reads/writes are
permitted of its parameters. Permission regions are not required for
final fields, naturally.

Finally, they support a view construct for arrays which allows you to declare
permission to access a portion of an array:

    region r = ...;
    int[.] subA = A.subView(r);
    permit write(subA) { ... }
    
This is reminiscent of my own `divide()` method in PJs.

Interestingly, they allow the local variables within a permit section
to be modified.  Presumably each such assignment will lead to a new
dynamic conflict check.

To reduce the annotation burden, the compiler will automatically
insert permission regions.  Basically they find the highest point in
the AST that includes all accesses within a given method, but they do
not cross `async` or `isolated` (the HJ keywords for spawning tasks
and for creating transactions).  They find this is usually right.

The whole point of this exercise is to reduce the overhead and (I
believe) improve the accuracy of dynamic checks.  Naturally, the
slowdown for monitoring for data races varied dramatically, but it was
generally around 1.5 to 2x.  There are some exceptions, such as
raytracer, which went as high as 22x.  

### My reaction: 

Summary: interested but mildly skeptical.

Their performance numbers seem pretty decent for dynamic monitoring,
but I'm not sure it meets their goal of "always on".  HJ's target
audience after all is scientific computing, and 2x slowdown in that
field seems like a big deal to me.  Still, a lot of people are using R
and Python etc so maybe it is "fast enough".  And of course they can
optimize further, I'm sure.

The actual semantics of their race check are sort of interesting.  A
narrow focus on data-races over other kinds of races can lead to
programs that do the wrong thing even though they never have any races.
The classic example is Java code like this:

    void addIfEmpty(/*shared*/ Vector v, Object o) {
        if (v.isEmpty()) v.add(o);
    }
    
These two statements were presumably intended to be atomic, but of
course they may not execute atomically.  Nonetheless, since `Vector`
in Java is a fully synchronized class, there will be no data races
under the technical definition of data races.

In any case, declaring permission regions seems to suggest a
sensitivity to this issue, however the use of compiler inference kind
of works against this intutition, since the compiler may not know the
proper places to insert the checks.  (Here, for example, if fully
automated the compiler would still insert the permission regions
within the vector calls themselves)

But I think, in the end, races vs data races is besides the point.
That is, the permission regions are not intended as a kind of
"declaration of things that go together" but rather as a practical
means of reducing overhead and controlling the granularity of checks
for detecting data races.  Basically---I gather that they assume the
system will be always on and, generally, ignored by programmers.  But
if they come up against an issue where performance is a problem, they
will start using the effect system and explicit permission regions to
push these checks to a higher-level.

I'm not sure how effective this will be, however.  A lot of the
overhead seems to derive from the array view checks, which cannot be
automated.  Furthermore, when the number of items to be accessed is
unbounded, such as when walking a linked list, you cannot push the
permission regions out any bigger.  It would be nice to see numbers
that compare the overhead before they tweaked it and after to get an
idea of how much reduction is possible.

It brings to mind my own efforts with PJs etc: I am excited to see
that bear fruit, because I think the overhead of such dynamic checks
can be made *extremely* low.  Of course my system would not be nearly
as flexible as theirs, which is why the checks are so cheap.  But
basically I like the idea of dynamic checking for races, but I think
it is not necessary something you want to just layer on top of a
rather broken "everything shared and mutable all the time" system,
because the overheads are just too high.  Rather, you start with a
sane foundation, and you should be able to monitor for violations
relatively cheaply and locally.

