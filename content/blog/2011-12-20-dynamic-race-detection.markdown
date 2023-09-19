---
layout: post
title: "Dynamic race detection"
date: 2011-12-20 11:19
comments: true
categories: [PL]
published: true
---

In the context of thinking about parallelism for Rust, I have been reminded
of an older idea I had for a lightweight, predictable dynamic race 
detection monitoring system based around block-scoped parallelism. I should 
think this would be suitable for (an extended version of) a dynamic
language like Python, JavaScript, or Lua.  I will write in a Python-like
syntax since I know it best, but I am debating about exploring this
for JavaScript.

#### Block-scoped parallelism

The basic parallel model would be block-scoped parallelism as I've been
referring to in the various Rust posts.  To make this concrete, here is a
low-level example of how it might work; this is a dynamic version of
something like the `finally/async` blocks of X10. There are two basic concepts,
a *parallel region* and a set of *parallel tasks*.  Each task is created within
some parallel region; when the parallel region is *executed*, all of
the tasks begin exeution.  They may continue to create new tasks.  Meanwhile,
the task which executed the parallel region blocks until it completes.

    def divide_and_conquer(...):
		if "small enough to do sequentially":
			process(list)
		else:
		    p = parallel_region()
			task1 = p.new_task(lambda: divide_and_conquer(...))
			task2 = p.new_task(lambda: divide_and_conquer(...))
			p.execute()
			task1.get_result() # yields an error unless p.execute() has run

I will leave aside for the moment the question of deciding which problems
are small enough to do sequentially and so forth.  This task and
parallel region API is intended to be low-level.  Higher-level libraries
would build on it to make those sorts of decisions.

Anyway the API is somewhat orthogonal.  We could dicker about the
precise design, I am more interested in the data-race freedom
part.  The key properties that the API must maintain are:

- Tasks are always created within a parallel region.
- The parent task which executes the parallel region is always suspended
  while its child tasks execute.

#### Monitoring for data races

Now, the key idea: I want to say that each object is *owned* by the
task which creates it.  The data is then mutable only by its owner and
any parent task of the owner.  The data is *readable* by the owner and
any child task of the owner.  These constraints---assuming no
global data---suffice to guarantee that a given object cannot leak to 
siblings of its owner.  Only the owner, ancesors of the owner, and
children of the owner can have access to the object.

This leaking property is important, so let's take a second to see why 
it's true: the idea is that two sibling tasks can only communicate via
shared memory.  This memory must have existed when the tasks were
created, so it must be owned by a common parent of the sibling tasks.  
This common memory is therefore immutable: only the common parent could
modify it, and the comment parent is suspended while its children
execute.

Based on this, we can say that whenever we modify a field of an object,
we must check that we are either the owner or a parent of the owner.
If we are a parent, then the owner must have terminated (else the 
parent could be not be active), so we can adjust the owner of the object
to be ourselves. Thus the check for "do I have write access?" is kind of a 
variant of Tarjan's union set algorithm with chain compression.

Interestingly, no dynamic check at all is needed to do a read: either we
own the object, in which case we can read it, or it is owned by a parent
or extinct child.  In all of those cases reads are permitted.

I've phrased this write check as a per-object check, but I think that in
an actual implementation, I would really do it on groups of objects;
this would be implemented almost exactly like a write barrier in
a garbage collected environment, except that we have to not only write
out the dirty bit but read it first to check that we have write access.
Obviously this will be slower, but not that much slower I should
think, particularly as we are likely to be writing to recently
created objects, and hence have the dirty bit in cache.

#### Ownership

But sometimes we want to be able to pass mutable data to our children.
My idea for this is to use a kind of dynamic version of unique pointers.
In JavaScript, I would implement this with proxies: basically, you create
an object and when you create it, you say it is *mobile*.  What you get
back is a proxy to the real object, which is locked within the proxy and
never divulged.  Now you can use it like any object, but eventually you 
can give it to a child. Your existing proxy is then set to some broken 
state and a new proxy created which has the object. This proxy is handed by the 
runtime to your newly spawned task. The task can always give it back to you by
returning it.  

#### What about other models?

I showed this for a simple fork-join model.  I think you can rephrase it
in terms of futures or something like Dot Net's parallel tasks as well.