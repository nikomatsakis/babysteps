---
layout: post
title: "Parallel Javascript"
date: 2012-01-09T16:55:00Z
comments: true
categories: [PL, PJs, JS]
---

Lately the ideas for a parallel, shared memory JavaScript have begun
to take shape.  I've been discussing with [various][dherman]
[Java][luke][Script][alon] [luminaries][fzzzy] and it seems like a
design is starting to emerge.  This post serves as a documentation of
the basic ideas; I'm sure the details will change as we go along.

### User Model

The model is that a JavaScript worker (the "parent") may spawn a
number of child tasks (the "children").  The parent is suspended while
the children execute, meaning that it will not process events or take
other actions.  Once the children have completed the parent will be
re-awoken.

Each object in JavaScript is owned by the task which created it.
Children may access all of the objects of their parent, but only in a
read-only fashion.  This is enforced dynamically.  When a task
completes, its objects become owned by the parent.  Therefore, the
child tasks may create data and operate on it in a mutable fashion;
when they finish they can return some of this data to the parent as
their result.  When the parent resumes, they are now the owner of the
data (as the child has finished) and so they may freely manipulate it.

One nice feature of this model is that the data which a given piece of
code has access to is precisely the same set as the data which it is
allowed to read.  So reads can proceed with no overhead at all (well,
in theory; see the implementation section below).  Writes require an
extra check to guarantee that the object is owned by the task doing
the writing (again, in theory; see the implementation section below).

Parallel children will only be usable from web workers.  The reason is
that the model is inherently blocking (the parent must not execute
while the children are executing or we would have dataraces), and we
do not want to permit the main UI thread to be blocked.

One last piece of the puzzle concerns arrays and array buffers.  I
want the option to divide up large arrays and array buffers amongst
workers in such a way that each gets a disjoint view into the buffer.
Each worker could then read/write into their disjoint view in
parallel.  Access to the original array or array buffer would yield an
exception until all children have completed.  The user would select
how the view buffer should be divided up (tiled, striped,
checkerboard, etc).  This will probably be deferred until later though.

### API

I would like to expose the API in two levels.  The first would be the
more primitive, building blocks API which permits child tasks to be
forked and joined.  The second would be a higher level API that
operates over entire arrays or array buffers.  The higher level API
would be more than just convenience: it would be needed for creating
the disjoint views discussed at the end of the previous section.

#### Creating and querying tasks

To execute in parallel, you begin by creating a scheduler:

    let sched = scheduler();

Each scheduler is bound to a parent task, which is always
the task which created it.  You can use the scheduler to create
child tasks which will execute while the scheduler is active.
Child tasks can be created in two ways:

    let task1 = sched.fork(function() {...});
    let task2 = sched.forkN(n, function(idx) {...});

The first, `fork()`, simply creates a task that will execute the given
function.  The result `task1` is a task object, which supports the
method `get()` (more on that later).  The `forkN()` variant creates a
task which will process `n` items: he function provided as argument
will be invoked once per item, with `idx` ranging from `0` to `n-1`.
The individual invocations of this function may themselves occur in
parallel.  

Executing the tasks can be done using the execute method of the scheduler:

    sched.execute()

This will cause a block parallel phase in which all forked tasks associated
with the scheduler execute.

Finally, each task produces a result.  For a `fork()` task, the result
is simply the return value of the function.  For a `forkN()` task, the
result is an array containing all the results (so
`[func(0), ..., func(n-1)]`).  

Whichever way it is created, the result of a task can be accessed using
the `get()` method.  If executed within the parent, the `get()` method
must be called after the `sched.execute()` call or else an error occurs.
If executed within a child, the `get()` method will effectively join the
other task and read its result.  The result will then be read-only within
the child.

#### Dividing arrays and buffers

Building on this low-level API, there is a higher-level API for processing
arrays and buffers.  I am not precisely sure how this should look, but I
think it will be something like:

    array.update_in_parallel(strategy, function(ctx, view) {
        ... array is inaccessible in here; each child task gets
            a disjoint view which is a read/write slice of the array ...
    });
    
Here the parameter `strategy` would specify how the array should be
divided into views.  I think the best thing is probably to look at the
X10 and Chapel languages (as well as their predecessors) and see how
they handle the dividing of arrays across distributed processors.  We
probably want something similar but (hopefully) simpler.  In an ideal
world, strategy would be some sort of functions so that users could
specify how the array is divided, though this opens the door to races
if the function is invalid.  Another simpler alternative is to allow
various strings like "tiled", "striped", etc.

### Implementation

A plan for a working prototype based on Spidermonkey has begun to
emerge.  First, the idea would be to have a pool of worker threads
that will execute the parallel tasks by drawing on a shared queue (or
possibly using work stealing, this is not so important).

The tricky part is how to manage the shared data from the parent task.
We need to make that data available to the children in such a way that
it can (a) be safely read in parallel and (b) not be modified.  You
may think that (a) should come for free, but in fact it does not.
This is because Spidermonkey optimizes reads, which in JavaScript can
be quite complex, by making use of caching and other techinques which
do in fact modify the representation of the object being read.  

The technique that we plan to use is similar to what is used to
protect domains from one another.  Each task will have its own
[compartment][compartments].  This effect creates a partitioned heap
where each task has a separate heap.  Then, for each upvar of the
parent that must be used from the child, a proxy object (not a JS
proxy, but a Spidermonkey proxy, which is a lower level tool) will be
created.  Reads to this parent object will therefore always go through
a proxy: this proxy is responsible for taking a naive read path that
does not modify the parent object.  This means that reads of parent
objects during parallel code will be somewhat slower.  However, as a
benefit, this proxy can trivially prevent writes to parent objects, so
it is easy to ensure that the siblings do not step on each other.

Once a task ends, the data in its compartment can be given to the
parent.  Basically a compartment contains a number of arena pages.
Those arena pages can simply be moved from the child task's
compartment into the parent task's compartment.  The only thing left
to do is to replace any references to the proxied parent objects with
the actual objects themselves.  Note that because the parent objects
are immutable, it will not be possible to have references from the
parent objects to the child objects, only the other way around.  We
could also run the garbage collector if we wanted, which would cause
all child data not reachable from the child's result to be collected.

One big advantage of this proxy-and-compartment-based design is that
it should not require modifying the JIT or the interpreter.  Both of
those systems are already aware of proxies and would treat them specially.

[compartments]: http://andreasgal.com/2010/10/13/compartments/
[dherman]: http://calculist.org/
[fzzzy]: http://donovanpreston.blogspot.com/
[alon]: http://mozakai.blogspot.com/
[luke]: http://blog.mozilla.com/luke/
