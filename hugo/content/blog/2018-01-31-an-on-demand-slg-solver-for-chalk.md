---
categories:
- Rust
- Traits
- Chalk
- PL
date: "2018-01-31T00:00:00Z"
slug: an-on-demand-slg-solver-for-chalk
title: An on-demand SLG solver for chalk
---

In my last Chalk post, I talked about an experimental, SLG-based
solver that I wrote for Chalk. That particular design was based very
closely on the excellent paper
["Efficient top-down computation of queries under the well-founded semantics", by W. Chen, T. Swift, and D. Warren][ews]. It
followed a traditional Prolog execution model: this has a lot of
strengths, but it probably wasn't really suitable for use in rustc.
The single biggest reason for this was that it didn't really know when
to stop: given a query like `exists<T> { T: Sized }`, it would happily
try to enumerate all sized types in the system. It was also pretty
non-obvious to me how to extend that system with things like
co-inductive predicates (needed for auto traits) and a few other
peculiarities of Rust.

[ews]: http://www.sciencedirect.com/science/article/pii/0743106694000285

In the last few days, I've implemented a second SLG-based solver for
Chalk. This one follows a rather different design. It's kind of a
hybrid of Chalk's traditional "recursive" solver and the SLG-based
one, with a lot of influence from [MiniKanren][]. I think it's getting
a lot closer to the sort of solver we could use in Rustc.

[MiniKanren]: http://minikanren.org/

One key aspect of its design is that it is "on-demand" -- that is, it
tries to only do as much as work as it needs to produce the next
answer, and then stops. This means that we can generally stop it from
doing silly things like iterating over every type in the
system[^caveat].

[^caveat]: The existing implementation could do better here, but the ingredients are there.

It also works in a "breadth-first fashion". This means that, for
example, it would rather produce a series of answers like
`[Vec<?T>, Rc<?T>, Box<?T>, ...]` that to go deep and give answers
like `[Vec<?T>, Vec<Vec<?T>>, Vec<Vec<Vec<?T>>>, ...]`. This is
particularly useful when combined with on-demand solving, since it
helps us to quickly see ambiguity and stop enumerating answers.

### Details of how it works

As part of the [PR][], I wrote up a [README][] that tries to walk
through how query solving works in the new solver. I thought I'd paste
that here into this blog post.

The basis of the solver is the `Forest`
type. A *forest* stores a collection of *tables* as well as a
*stack*. Each *table* represents the stored results of a particular
query that is being performed, as well as the various *strands*, which
are basically suspended computations that may be used to find more
answers. Tables are interdependent: solving one query may require
solving others.

[PR]: https://github.com/rust-lang-nursery/chalk/pull/76
[README]: https://github.com/nikomatsakis/chalk-ndm/blob/64964db637c1ea63ecb0234326f9b57b3a9e55cb/src/solve/slg/on_demand/README.md

Perhaps the easiest way to explain how the solver works is to walk
through an example. Let's imagine that we have the following program:

```rust
trait Debug { }

struct u32 { }
impl Debug for u32 { }

struct Rc<T> { }
impl<T: Debug> Debug for Rc<T> { }

struct Vec<T> { }
impl<T: Debug> Debug for Vec<T> { }
```

Now imagine that we want to find answers for the query `exists<T> {
Rc<T>: Debug }`. The first step would be to u-canonicalize this query; this
is the act of giving canonical names to all the unbound inference variables based on the 
order of their left-most appearance, as well as canonicalizing the universes of any
universally bound names (e.g., the `T` in `forall<T> { ... }`). In this case, there are no
universally bound names, but the canonical form Q of the query might look something like:

    Rc<?0>: Debug
    
where `?0` is a variable in the root universe U0. We would then go and
look for a table with this as the key: since the forest is empty, this
lookup will fail, and we will create a new table T0, corresponding to
the u-canonical goal Q.

**Creating a table.** When we first create a table, we also initialize
it with a set of *initial strands*. A "strand" is kind of like a
"thread" for the solver: it contains a particular way to produce an
answer. The initial set of strands for a goal like `Rc<?0>: Debug`
(i.e., a "domain goal") is determined by looking for *clauses* in the
environment. In Rust, these clauses derive from impls, but also from
where-clauses that are in scope. In the case of our example, there
would be three clauses, each coming from the program. Using a
Prolog-like notation, these look like:

```
(u32: Debug).
(Rc<T>: Debug) :- (T: Debug).
(Vec<T>: Debug) :- (T: Debug).
```

To create our initial strands, then, we will try to apply each of
these clauses to our goal of `Rc<?0>: Debug`. The first and third
clauses are inapplicable because `u32` and `Vec<?0>` cannot be unified
with `Rc<?0>`. The second clause, however, will work.

**What is a strand?** Let's talk a bit more about what a strand *is*. In the code, a strand
is the combination of an inference table, an X-clause, and (possibly)
a selected subgoal from that X-clause. But what is an X-clause
(`ExClause`, in the code)? An X-clause pulls together a few things:

- The current state of the goal we are trying to prove;
- A set of subgoals that have yet to be proven;
- A set of delayed literals that we will have to revisit later;
  - (I'll ignore these for now; they are only needed to handle loops between negative goals.)
- A set of region constraints accumulated thus far.
  - (I'll ignore these too for now; we'll cover regions later on.)

The general form of an X-clause is written much like a Prolog clause,
but with somewhat different semantics:

    G :- D | L
    
where G is a goal, D is a set of delayed literals, and L is the set of
literals that must be proven (in the general case, these can be both a
goal like G but also a negated goal like `not { G }`). The idea is
that -- if we are able to prove L and D -- then the goal G can be
considered true.

In the case of our example, we would wind up creating one strand, with
an X-clause like so:

    (Rc<?T>: Debug) :- (?T: Debug)

Here, the `?T` refers to one of the inference variables created in the
inference table that accompanies the strand. (I'll use named variables
to refer to inference variables, and numbered variables like `?0` to
refer to variables in a canonicalized goal; in the code, however, they
are both represented with an index.)

For each strand, we also optionally store a *selected subgoal*. This
is the literal after the turnstile (`:-`) that we are currently trying
to prove in this strand. Initally, when a strand is first created,
there is no selected subgoal.

**Activating a strand.** Now that we have created the table T0 and
initialized it with strands, we have to actually try and produce an
answer. We do this by invoking the `ensure_answer` operation on the
table: specifically, we say `ensure_answer(T0, A0)`, meaning "ensure
that there is a 0th answer".

Remember that tables store not only strands, but also a vector of
cached answers. The first thing that `ensure_answer` does is to check
whether answer 0 is in this vector. If so, we can just return
immediately.  In this case, the vector will be empty, and hence that
does not apply (this becomes important for cyclic checks later on).

When there is no cached answer, `ensure_answer` will try to produce
one.  It does this by selecting a strand from the set of active
strands -- the strands are stored in a `VecDeque` and hence processed
in a round-robin fashion. Right now, we have only one strand, storing
the following X-clause with no selected subgoal:

    (Rc<?T>: Debug) :- (?T: Debug)

When we activate the strand, we see that we have no selected subgoal,
and so we first pick one of the subgoals to process. Here, there is only
one (`?T: Debug`), so that becomes the selected subgoal, changing
the state of the strand to:

    (Rc<?T>: Debug) :- selected(?T: Debug, A0)
    
Here, we write `selected(L, An)` to indicate that (a) the literal `L`
is the selected subgoal and (b) which answer `An` we are looking for. We
start out looking for `A0`.

**Processing the selected subgoal.** Next, we have to try and find an
answer to this selected goal. To do that, we will u-canonicalize it
and try to find an associated table. In this case, the u-canonical
form of the subgoal is `?0: Debug`: we don't have a table yet for
that, so we can create a new one, T1. As before, we'll initialize T1
with strands. In this case, there will be three strands, because all
the program clauses are potentially applicable. Those three strands
will be:

- `(u32: Debug) :-`, derived from the program clause `(u32: Debug).`.
  - Note: This strand has no subgoals.
- `(Vec<?U>: Debug) :- (?U: Debug)`, derived from the `Vec` impl.
- `(Rc<?U>: Debug) :- (?U: Debug)`, derived from the `Rc` impl.

We can thus summarize the state of the whole forest at this point as
follows:

```
Table T0 [Rc<?0>: Debug]
  Strands:
    (Rc<?T>: Debug) :- selected(?T: Debug, A0)
  
Table T1 [?0: Debug]
  Strands:
    (u32: Debug) :-
    (Vec<?U>: Debug) :- (?U: Debug)
    (Rc<?V>: Debug) :- (?V: Debug)
```
    
**Delegation between tables.** Now that the active strand from T0 has
created the table T1, it can try to extract an answer. It does this
via that same `ensure_answer` operation we saw before. In this case,
the strand would invoke `ensure_answer(T1, A0)`, since we will start
with the first answer. This will cause T1 to activate its first
strand, `u32: Debug :-`.

This strand is somewhat special: it has no subgoals at all. This means
that the goal is proven. We can therefore add `u32: Debug` to the set
of *answers* for our table, calling it answer A0 (it is the first
answer). The strand is then removed from the list of strands.

The state of table T1 is therefore:

```
Table T1 [?0: Debug]
  Answers:
    A0 = [?0 = u32]
  Strand:
    (Vec<?U>: Debug) :- (?U: Debug)
    (Rc<?V>: Debug) :- (?V: Debug)
```

Note that I am writing out the answer A0 as a substitution that can be
applied to the table goal; actually, in the code, the goals for each
X-clause are also represented as substitutions, but in this exposition
I've chosen to write them as full goals, following NFTD.
   
Since we now have an answer, `ensure_answer(T1, A0)` will return `Ok`
to the table T0, indicating that answer A0 is available. T0 now has
the job of incorporating that result into its active strand. It does
this in two ways. First, it creates a new strand that is looking for
the next possible answer of T1. Next, it incorpoates the answer from
A0 and removes the subgoal. The resulting state of table T0 is:

```
Table T0 [Rc<?0>: Debug]
  Strands:
    (Rc<?T>: Debug) :- selected(?T: Debug, A1)
    (Rc<u32>: Debug) :-
```

We then immediately activate the strand that incorporated the answer
(the `Rc<u32>: Debug` one). In this case, that strand has no further
subgoals, so it becomes an answer to the table T0. This answer can
then be returned up to our caller, and the whole forest goes quiescent
at this point (remember, we only do enough work to generate *one*
answer). The ending state of the forest at this point will be:

```
Table T0 [Rc<?0>: Debug]
  Answer:
    A0 = [?0 = u32]
  Strands:
    (Rc<?T>: Debug) :- selected(?T: Debug, A1)

Table T1 [?0: Debug]
  Answers:
    A0 = [?0 = u32]
  Strand:
    (Vec<?U>: Debug) :- (?U: Debug)
    (Rc<?V>: Debug) :- (?V: Debug)
```

Here you can see how the forest captures both the answers we have
created thus far *and* the strands that will let us try to produce
more answers later on.

### Conclusions

Well, the README stops the story a bit short -- it doesn't explain,
for example, what happens when there are cycles in the graph and so
forth. Maybe you can piece it together, though.

The biggest question is: is this a suitable architecture for use in
rustc? About this, I'm not sure yet. I feel like this route is quite
promising, however, and it's been an interesting journey for me in any
case thus far.

One of the tricky things that I don't yet know how to resolve: under
the current setup, if our root query is generated a diverse set of
answers, we can quite easily stop asking for more (e.g., to handle
`exists<T> { T: Sized }`). I think this is by far the more common
scenario in Rust. However, it's also possible to have a query which
*internally* has to go through quite a few answers in order to produce
any results at the root level. I'm imagining something like this:

```
impl<T> Foo for T
   where T: Bar, T: Baz,
```

Under the setup described here, one of these queries -- let's say `T:
Bar` -- gets chosen somewhat arbitrary to begin producing answers
first. It might produce a very large number of answers, which will
then get "fed" to the `Baz` trait, which will effectively filter them
out. But maybe `T: Baz` is only implemented for a very few types, so
if we had chosen the other order things would have been far more
efficient. I can imagine some heuristics helping here -- for example,
we might take traits like `Sized` or `Debug`, or which have very
open-ended impls -- and prefer not to select them first. I *suspect* a few
simple heuristics would get us quite far.

Currently, my biggest concern with this design is the "runaway
internal query" aspect I just described. But I'm curious if there are
other things I'm overlooking! As ever,
[I've created an internals thread][thread], please leave comments
there if you have thoughts (also suggestions for things I should go
and read).

[thread]: https://internals.rust-lang.org/t/blog-post-an-on-demand-slg-solver-for-chalk/6676

### Footnotes
