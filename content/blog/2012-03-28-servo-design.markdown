---
layout: post
title: "Servo design"
date: 2012-03-28T08:30:00Z
comments: true
categories: [Servo]
---

Yesterday we had a hackathon/meeting to discuss the overarching design
of Servo, the project to build a next-generation rendering engine.  We
didn't ultimately do much hacking (though we did a little), but mostly
we tried to hammer out the big picture so that we can actually get to
writing code.  I wanted to try and write up what I understood as the
consensus (for the moment, anyway).

### The big picture

There will be (at least) three large components.  Each is basically
operating in independent tasks and the various stages are therefore
largely isolated from one another and able to execute independently
(with certain exceptions, as we shall see):

- JS
- Layout
- Painting

There are several data structures that will be maintained by these
different stages:

- The DOM
- The "Layout Tree" (CSS boxes corresponding to each DOM element)
- The "Display Tree" (what to draw at each location)
- Various other structures:
  - backing store(s) for canvas etc.

I'll go over each in turn.  
 
### The DOM and Layout Tree

The most interesting---and complex---part of the design centers around
the representation of the DOM.  We want the ability for layout to
execute in parallel with the JS itself.  However, both layout and JS
require access to the DOM; and, of course, the JS may choose to modify
the DOM at any time, and those changes should eventually be reflected
in the layout. Initially the plan was to overcome this by having two
DOMs: the main DOM, accessible to JS, and the shadow DOM, accessible
to layout. The shadow DOM would be kept up-to-date by messages from
the JS.  The problem with this plan is simply overhead: based on our
own experiments as well as feedback from [Ben Lerner][blerner], we
decided this is not the best approach.

[blerner]: http://www.cs.brown.edu/~blerner/

An alternative that we are considering instead is what we call the RCU
approach.  The name derives from the [read-copy-update][rcu] pattern
used extensively in the Linux kernel.  The idea itself was also
inspired by the work on [Concurrent Revisions][rev] by Burckhardt et
al. at MSR.

[rcu]: http://en.wikipedia.org/wiki/Read-copy-update
[rev]: http://research.microsoft.com/apps/pubs/default.aspx?id=132619

In a nutshell, the idea of the RCU plan is that when the JS node kicks
off a layout task, it will preserve the version of the DOM that the
layout is reading.  So any changes that occur while layout is active
must take place on a copy of the DOM.  Of course, it would be too
expensive to do a deep copy of the DOM when layout activates, and
[traditional persistent data structures][pds] like maps and vectors
are are not much help either.

[pds]: http://en.wikipedia.org/wiki/Persistent_data_structure

One key ingredient for any RCU-like plan is that it must be possible to
know when readers are active.  It turns out that we should be able to
track this for layout and JS.  Basically, the JS task is the "driver":
it decides when to start layout and may, in some cases, have to block
waiting for layout to terminate.

You can think of the main JS task as operating in a loop something
like this:

    layout_active = false;
    dirty_nodes = NULL;
    loop {
       execute_JS();

       if (dirty_nodes) {
           if (layout_active) {
               join_layout();
           }
           spawn_layout();
           layout_active = true;
       }
    }

It can also happen that the JS requests the computed style information
or layout.  In this case, then JS must first join the layout task 
(and, if the tree is dirty, it may have to spawn the task too!).

Our plan instead is to replace each pointer to a DOM node (`node*`)
with a handle (`rcu<node>*`).  This handle will be a structure like
the following:

    struct rcu<T> {
        T *wr_ptr;
        T *rd_ptr;
        rcu<T> *next_dirty;
    };

The `wr_ptr` points at the current version of the node, whereas the
`rd_ptr` points at the version of the node that layout is operating
on.  At the moment when a layout task is spawned, `rd_ptr` and
`wr_ptr` are always the same.  Whenever JS wishes to make
modifications and layout is active, it follow an algorithm something
like this:

    void dirty(rcu<T> *handle) {
        if (handle->wr_ptr != handle->rd_ptr)
            return; // already dirty
        if (!layout_active)
            return; // doesn't matter
            
        handle->wr_ptr = new T(*handle->rd_ptr); // copy rd data
        handle->next_dirty = dirty_nodes;
        dirty_nodes = handle;
        
        return;
    }
    
After this, it is safe for the code to make changes to the contents of
`handle->wr_ptr`.

The final step is to reset the `rd_ptr` to the `wr_ptr`.  This occurs
once layout is completed.  For example, we might implement the 
`join_layout()` routine like so:

    void join_layout() {
        layout_task->join();
        
        // Reset read and write pointers:
        rcu<T> *p = dirty_nodes, *pn;
        while (p != NULL) {
            pn = p->next_dirty;
            p->rd_ptr = p->wr_ptr;
            p->next_dirty = NULL;
            p = pn;
        }
        dirty_nodes = NULL;
    }
    
Note: the small details of this implementation will probably
change. For example, it might be better to store the `dirty_nodes` in
a vector instead of a linked list, or at least pull the `next` field
out somewhere else (this would for example make sense if the
proportion of dirty to clean nodes is small, as expected).  But you
get the idea (I hope, anyway).

So now that we've explained the basics, let's look at a few variations.

#### Separating layout into phases

I described layout as one monolithic entity.  But in fact it can be
useful to separate it into multiple parts.  For example, some JS calls
require that style computation be completed, but do not require that
the actual layout boxes be computed nor that the geometry is complete.
Therefore, we can break the layout task into multiple tasks, allowing
the JS to join just the phase that it requires (as well as allowing it
to spawn a task which will only perform the style computation and so
forth.

#### Triggering layout at other times

For things like CSS animations, we would like to be able to trigger an
animation even while the JS is active.  We can do this without great
difficulty thanks to the periodic callback which the JS makes every N
operations or so.  Basically, when the animation is ready to begin the
next layout step, it will asynchronously set a flag
(`animation_requires_layout`).  During the JS callback, if layout is
inactive but `animation_requires_layout` is true, then it will spawn
off a layout task.  Any writes which occur after that point will have
to be RCU'd.

One issue with this which I can see: the layout task will see whatever
DOM modifications had occurred up until the point of the interrupt.
This doesn't seem immediately desirable to me.  It could be
circumvented by tracking dirty nodes even when layout is inactive, and
just resetting the `rd_ptr`s every turn of the JS event loop.

#### Other stuff

We have to be careful around the backing buffers for Canvas layers and
other such data structures.  This doesn't seem especially hard but
we'll want to think about it.  Most likely Canvas will need to be
double-buffered and we'll just swap the buffers at the same point we
adjust the `rd_ptr` (when you think about, the RCU scheme is basically
double-buffering for the DOM).

#### Memory management

Writing this up has brought some questions to mind.  Primarily my
concerns center around memory management.  Garbage collection
operating in the JS task while layout is active will have to be quite
careful.  It can safely trace through both the rd and wr ptrs for DOM
nodes, but if there are links from the DOM nodes to the computed style
and layout information (which we had thought to have), then it is not
safe for the GC in the JS task to look at those.  The layout may be
concurrently modifying them after all.  There is also the matter of managing
the memory for the layout data structures.

One solution is for GC to simply join the layout task before it begins
execution.  Or, similarly, to distinguish small collections---in which
we ignore layout data structures---from large collections, in which
case layout must be joined.  This is probably good enough.

### Painting

When layout finishes, it can perform a paint by building up what is
now called a display tree---basically a list of rectangles to draw and
their contents---and send this off to the display task.  The display
task is then charged with walking this tree, rasterizing its contents,
and blitting the data to the screen.  This process can be done in a
very parallel way using rather simple techniques (blit any
non-overlapping rectangles in parallel, etc).  It can also use simple
caching to avoid expensive rasterizations, as Gecko does today. In
short, it seems fairly straightforward.

### The plan

We hope to quickly build up a fairly rudimentary form of Servo based
on this architecture.  The layout algorithms themselves will probably
be initially implemented in a sequential fashion.  We can still get
quite a lot of simple parallelism from various pieces of low-hanging
fruit: selector matching, painting, etc.  And we get quite a bit of
pipeline parallelism and responsiveness by separating the various
tasks.  But eventually of course we hope to parallelize the layout pipeline
itself.  

One important point which bz raised is that sometimes the raw
performance of layout is not terribly important---but it is important
that the browser stay responsive.  The fact that Gecko must do layout
on the main thread harms responsiveness, something which we should be
able to avoid.

### A final note

One disappointing aspect of this plan is that the existing static
data-race verification techniques are so inadequate to the problem.
Actor-based solutions require total separation of the DOM trees,
leading to unacceptable overhead.  Simple parallelism like that
offered by painting will likely never be analyzable by any simple
static regimen: it would have to be able to reason about the fact that
painting two rectangles which do not overlap is a commutative
operation.  The RCU-like plan would of course be very hard to
statically analyze, though if you build something like that into your
language as a base abstraction---as with the
[Concurrent Revisions][rev] work---that might work out well.

In general though I believe that a balanced approach to race detection
is best: statically verify where you can, accept the limited use of
dynamic schemes otherwise.  And we should be able to statically verify
simpler subproblems, for example, ensuring that layout only reads data
that is reachable via the `rd_ptr` and that JS only writes to data
reachable via the `wr_ptr` (this can be solved by a simple ADT which
only grants access via one pointer or the other).
