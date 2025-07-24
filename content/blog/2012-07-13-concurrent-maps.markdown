---
layout: post
title: "Concurrent maps"
date: 2012-07-13T10:30:00Z
comments: true
categories: [PL, Rust, Actors]
---

I had a very interesting discussion with Sriram and Terrence (of
[Kilim][kilim] and [ANTLR][antlr] fame, respectively---two smart
dudes) yesterday. One of the things we talked about was adapting
shared-memory data structures like concurrent hash maps into
an actor setting.

[kilim]: http://www.malhar.net/sriram/kilim/
[antlr]: http://www.antlr.org/

One thing we've found when working on Servo is that the temptation to
cheat is enormous.  Most of the papers you read about things like
parallel layout just assume a shared memory setting and blithely make
use of data strutures like concurrent hash maps.  There is nothing
*wrong* with such data structures, but if we can avoid shared, mutable
memory it will go a long way towards avoiding bugs I think---as well
as keeping things secure.  Even if the bug is mostly correct, data
races and similar subtle errors can open holes for exploitation.

Sriram as it happens did his thesis on this topic and has a lot of
deep ideas.  We discussed some ways to convert concurrent hashmaps
into distributed hashmaps.  I thought I'd write some of them down
for future reference.

The basic idea of any "distributed" data structure is to have a task
(or multiple tasks) which govern that structure.  They act like
traditional [monitors][monitor].  

[monitor]: http://en.wikipedia.org/wiki/Monitor_%28synchronization%29

In the case of a hashmap, the simplest design stripes the data across
a number of tasks---likely we just want to have about one task per
core, or perhaps two or three tasks per core, something constant
factor like that. Each task would be responsible for some stripe of
the hashes.  When you want to get or insert, you first hash, then
select the appropriate task, and fire it a message.  There are some
obvious improvements one can make on this: for example, if a task's
buckets become overloaded, it can split itself into two tasks to do
dynamic rebalancing, or start employing a secondary hash.  It can then
forward information about this backwards so that the "directory of
hashes" can be updated (there will probably be more than one copy of
this directory, however, so the task must be able to forward requests
received from out-of-date copies).  Similarly, you can have more
complex operations than get/insert: the sender can fire along a unique
closure that will perform maps or other more complex manipulations and
just send back the result.

But there are other interesting designs you can pursue as well.  For
example, to do distributed CSS matching, it might be possible to spin
up N tasks all with the same tree.  Each will build up (and own) one
portion of the final table.  Each of these N tasks walks over the tree
but only processes nodes whose hash belongs in their slice.  Once they
are done, they simply wait around for get requests that query the
results they built up.  The main difference here is that you don't
have "builder" tasks that use the hashtable---the hashtable kind of
builds itself and then awaits queries.

Another thing that Sriram had actually built and experimented with was
a concurrent B-tree where each node was an actor.  He found the design
was radically simplified from the traditional design, because all
locking was basically transparent and trivial.  He wasn't able to
spend enough time tuning to get informative performance results,
though.

This whole idea has got me quite excited.  Until coming to Rust, I was
mostly focused on shared memory designs, so I didn't invest too much
effort into thinking about actor-based solutions.  I imagine there is
a lot of related work in the Erlang communities, not to mention
traditional distributed systems (and cluster-based parallelism as
well).  I'd like to start experimenting in Rust with prototyping these
designs, maybe soon.  It always amazes me how much there is to learn,
even within a relatively narrow area like parallel processing!



