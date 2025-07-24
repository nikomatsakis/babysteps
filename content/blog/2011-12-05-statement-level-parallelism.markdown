---
layout: post
title: "Statement-level parallelism"
date: 2011-12-05T09:25:00Z
comments: true
categories: [Rust]
---

The primary means of parallel programming in Rust is tasks.  Our task
support is good: as good or better than any other language I've seen
(good support for unique types and unique closures) but we have
virtually no support for intra-task parallelism.  The classic example
is iterating over an array and processing each element in parallel.
To be fair, this is a hard problem.

For my PhD, I worked on a language called
[Harmonic](http://harmonic-lang.org).  Harmonic had a lot of ideas
which I---naturally enough---really like, but most of them are
probably not appropriate for Rust, as they leaned heavily on a
complex, dependent type system.  Some of them, however, might apply.
In fact, thanks to unique pointers and interior types, it might be
possible to make the Rust version even more expressive than the
original.

The key idea that I want to lift from Harmonic is
[*parallel blocks*][parblk], which are blocks (in the Smalltalk and
Ruby sense) that may execute in parallel with each other *and with the
function that created them*.  This is a slight twist on the typical
fork-join setup: in fork-join, parallel control paths fork off and are
eventually joined.  However, after the path forks off, the parent
continues execution.  In Harmonic, however, the parent can fork off a
number of paths in parallel but the parent is always suspended until
they have terminated.  This allows the parallel paths to access all of
the parent's state, albeit in a read-only fashion.

I found this idea fairly expressive but there were some gaps in
Harmonic.  In particular, it often happens that you have an array of
data and you want to give each piece out to a worker which then *owns*
that piece of data and can make arbitrary changes to it.  The aliasing
challenges in Harmonic made this impossible.  This can be achieved in
Rust with unique arrays of unique pointers or value types.

The basic syntax would look something like this:

    fn process(x: ~[mut T]) {
        x.par_map_in_place { y -> 
            // x is borrowed here (and hence inaccessible).
            // y has type &T and is a pointer into x.
        }
    }

There are some type-system improvements needed here (for example, we
need a way for a method like `par_map_in_place()` to require that its
receiver is a borrowed, unique pointer).  We also need to play with
the set of methods required.  Overloading support might help keep the
names short; in Harmonic, I planned to make use of overloading or
reflection to allow parallel blocks (which were written `{| x ->
... |}` instead of `{ x-> ... }`) to simply execute in parallel.

This will also lean on regions and the notion of a constructor
expression from the no copies proposal: regions and explicit memory
pools would allow us to allocate *mutable* data on the stack in the
parallel block and no for sure that it is thread-local.  All upvars
that give access to shared state (`@` keyword), meanwhile, would be
transformed into read-only references.

Anyway, this is a long way from a concrete proposal, but I think it
has a lot of promise.

[parblk]: http://harmonic-lang.org/tutorial-2/4-parallel-control-flow-usi.html
