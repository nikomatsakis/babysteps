---
layout: post
title: "Proposed JS parallelism vs actors"
date: 2012-01-11 10:38
comments: true
categories: [PL, PJs]
---

In one of the comments on yesterday's post,
[Tushar Pokle asked][comment] why I would champion my model over an
Erlang model of strict data separation.  There are several answers to
this question.  The simplest answer is that Web Workers already
provide an actors model, though they do not make tasks particularly
cheap (it's possible to work around this by creating a fixed number of
workers and sending tasks for them to execute).

[comment]: http://smallcultfollowing.com/babysteps/blog/2012/01/09/parallel-javascript/#comment-407714243

The better answer is that I don't think that Erlang's actor model and
the model I propose are that far apart.  I see this model as a kind of
"delimited actor".  Why would I say that, since it does not seem to
resemble actors at a superficial level?  The reason is that, in my
model, each child is quite isolated from one another.  In a typical
"shared memory" model, processes communicate by modifying common data
structures.  This turns out to be highly unreliable.

In the model I propose (which needs a name), processes may share data
structures, but they cannot communicate this way, as those structures
are immutable.  In fact, the only way that sibling processes can
communicate with one another is by joining each other.  This allows
them to recieve the other processes result.  This is effectively a
one-shot message from one task to another.

So, in a way my model is a simplification of actors: it allows you to
spawn a set of actors.  The parent data which they share is
effectively an initial message from the parent to each child.  The
child's result is then a one time message from each child to the
parent (or to other siblings in a [DAG][dag]-like fashion).

[dag]: http://en.wikipedia.org/wiki/Directed_acyclic_graph

I don't actually think my model is a good choice as the *only* model
for parallelism in your language, but I think it *complements* actors
quite well.  Consider what you would do in Erlang if you want to
process the members of a list in parallel: you would create a task for
each member of the list and send it whatever context is requires.  You
would then receive back the new values and construct the new list.  In
other words, you would implement precisely the messaging pattern that
this model defines.

Of course, as often happens, supporting only a limited model for
messaging lets you optimize things in the implementation. Because we
know that the child processes are only of limited duration, we don't
have to copy the parent's data but can instead allow them to reference
it (readonly) directly.  Similarly, because we know that each child is
dead when its result is received, we don't have to copy the result
into the parent's address space, but can again reuse the values
directly.  Finally, the garbage collector does not have to consider
the case of cross-process garbage collection: the parent's data is
immutable, so whatever is live will remain live.  The data accessible
to each child is disjoint, so we can collect data owned by each child
independently without looking at the others.

I am tempted to call my model "delimited actors", but I think it looks
sufficiently different from actors that this name might be misleading.
But, as I just argued, I think it is closer to actors than to the
"shared memory" model that has caused so many problems and
difficulties.
