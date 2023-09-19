---
layout: post
title: Lowering Rust traits to logic
categories: [Rust, Traits, PL, Chalk]
---

Over the last year or two (man, it's scary how time flies), I've been
doing quite a lot of thinking about Rust's trait system. I've been
looking for a way to correct a number of flaws and shortcomings in the
current implementation, not the least of which is that it's
performance is not that great. But also, I've been wanting to get a
relatively clear, normative definition of how the trait system works,
so that we can better judge possible extensions. After a number of
false starts, I think I'm finally getting somewhere, so I wanted to
start writing about it.

In this first post, I'm just going to try and define a basic mapping
between Rust traits and an underlying logic. In follow-up posts, I'll
start talking about how to apply these ideas into an improved, more
capable trait implementation.

### Rust traits and logic

One of the first observations is that the Rust trait system is
basically a kind of logic. As such, we can map our struct, trait, and
impl declarations into logical inference rules. For the most part,
these are basically Horn clauses, though we'll see that to capture the
full richness of Rust -- and in particular to support generic
programming -- we have to go a bit further than standard Horn clauses.

If you've never heard of Horn clauses, think Prolog. If you've never
worked with Prolog, shame on you! Ok, I'm just kidding, I've just been
quite obsessed with Prolog lately so now I have to advocate studying
it to everyone (that and Smalltalk -- well, and Rust of course
:wink:). More seriously, if you've never worked with Prolog, don't
worry, I'll try to explain some as we go. But you may want to keep the
wikipedia page loaded up. =)

Anyway, so, the mapping between traits and logic is pretty straightforward.
Imagine we declare a trait and a few impls, like so:

```rust
trait Clone { }
impl Clone for usize { }
impl<T> Clone for Vec<T> where T: Clone { }
```

We could map these declarations to some Horn clauses, written in a
Prolog-like notation, as follows:

```
Clone(usize).
Clone(Vec<?T>) :- Clone(?T).
```

In Prolog terms, we might say that `Clone(Foo)` -- where `Foo` is some
Rust type -- is a *predicate* that represents the idea that the type
`Foo` implements `Clone`. These rules are *program clauses* that state
the conditions under which that predicate can be proven (i.e.,
considered true). So the first rule just says "Clone is implemented
for `usize`". The next rule says "for any type `?T`, Clone is
implemented for `Vec<?T>` if clone is implemented for `?T`". So
e.g. if we wanted to prove that `Clone(Vec<Vec<usize>>)`, we would do
so by applying the rules recursively:

- `Clone(Vec<Vec<usize>>)` is provable if:
  - `Clone(Vec<usize>)` is provable if:
    - `Clone(usize)` is provable. (Which is is, so we're all good.)
    
But now suppose we tried to prove that `Clone(Vec<Bar>)`. This would
fail (after all, I didn't give an impl of `Clone` for `Bar`):

- `Clone(Vec<Bar>)` is provable if:
  - `Clone(Bar)` is provable. (But it is not, as there are no applicable rules.)
    
We can easily extend the example above to cover generic traits with
more than one input type. So imagine the `Eq<T>` trait, which declares
that `Self` is equatable with a value of type `T`:

```rust
trait Eq<T> { ... }
impl Eq<usize> for usize { }
impl<T: Eq<U>> Eq<Vec<U>> for Vec<T> { }
```

That could be mapped as follows:

```
Eq(usize, usize).
Eq(Vec<?T>, Vec<?U>) :- Eq(?T, ?U).
```

So far so good. However, as we'll see, things get a bit more
interesting when we start adding in notions like associated types,
higher-ranked trait bounds, struct/trait where clauses, coherence,
lifetimes, and so forth. =) I won't get to all of those items in this
post, but hopefully I'll cover them in follow-on posts.

### Associated types and type equality

Let's start with associated types. Let's extend our example trait
to include an associated type or two:

```rust
trait Iterator {
    type Item;
}

impl<A> Iterator for IntoIter<A> {
    type Item = A;
}

impl<T: Iterator> Iterator for Enumerate<T> {
    type Item = (usize, T::Item);
}
```

We would map these into our pseudo-Prolog as follows:

```
// This is what we saw before:
Iterator(IntoIter<?A>).
Iterator(Enumerate<?A>) :- Iterator(?A).

// These clauses cover normalizing the associated type.
IteratorItem(IntoIter<?A>, ?A).
IteratorItem(Enumerate<?T>, (usize, <?U as Iterator>::Item)).
                                //  ^^^^^^^^^^^^^^^^^^^^^^
                                //  fully explicit reference to an associated type
```

You can see that we now have two kinds of clauses. `Iterator(T)` tells
us if `Iterator` is implemented for `T`. `IteratorItem(T, U)` tells us
that `T::Item` is equivalent to `U`.

And this brings us to an important point: we need to think about what
*equality* means in this logic. You can see that I've been writing
Prolog-like notation but using Rust types; this might have seemed like
a notational convenience (and it is), but it actually masks something
deeper. The notion of equality for a Rust type is sigificantly richer
than Prolog's notion of equality, which is a very simple syntactic
unification.

In particular, imagine that I wanted to combine the `Clone` rules we
saw earlier with the `Iterator` definition we just saw, and I wanted
to prove something like `Clone(<IntoIter<usize> as Iterator>::Item)`.
Intuitively, this should hold, because `<IntoIter<usize> as
Iterator>::Item` is defined to be `usize`, and we know that
`Clone(usize)` is provable. But if were using a standard Prolog
engine, it wouldn't know anything about how to handle associated types
when it does proof search, and hence it could not use the clause
`Clone(usize)` to prove the goal `Clone(<IntoIter<usize> as
Iterator>::Item)`.

#### One approach: rewrite predicates to be based on syntactic equality

One approach to solving this problem would be to define all of our
logic rules strictly in terms of syntactic equality. This approach is
sort of appealing because it means we could (in principle, anyway) run
the resulting rules on a standard Prolog engine. Ultimately, though, I
don't think it's the right way to think about things, but it is a
helpful building block for explaining the better way.

If we are using only a syntactic notion of equality, we can't just use
the same variable twice in order to equate types as we have been
doing. Instead, we have to systematically rewrite the rules we've been
giving to use an auxiliary predicate `TypeEqual(T, U)`. This predicate
tells us when two Rust types are equal. This is what the rules that
result from the impl of `Iterator` for `IntoIter` might look like
written in this style:

```rust
Iterator(?A) :-
    TypeEqual(?A, IntoIter<?B>).
IteratorItem(?A, ?B) :-
    TypeEqual(?A, IntoIter<?B>).
```

Looking at the first rule, we say that `Iterator(?A)` is true for any
type `?A` that is equal to `IntoIter<?B>`. You can see that we avoided
directly equating `?A` and `IntoIter<?B>`.

The second rule is a bit more interesting: remember, intuitively, we
want to say that that `IteratorItem(IntoIter<?B>, ?B)` -- that is, we
want to "pull out" the type argument `?X` to `IntoIter` and repeat it.
But since we can't directly equate things, we accept any type `?A`
that can be found to be equal to `IntoIter<?B>`.

So let's look at how this `TypeEqual` thing would work. I'll just show
one way it could be defined, where you have a separate rule for each
kind of type:

```
// Rules for syntactic equality. If we JUST had these rules,
// then `TypeEqual` would be equivalent to standard
// Prolog unification.

TypeEqual(usize, usize).

TypeEqual(IntoIter<?A>, IntoIter<?B>) :-
    TypeEqual(?A, ?B).

TypeEqual(<?A as Iterator>::Item, <?B as Iterator>::Item) :-
    TypeEqual(?A, ?B).

// Normalization based rules. This is the rule that lets you
// rewrite an associated type to the type from the impl.

TypeEqual(<?A as Iterator>::Item, ?B) :-
    IteratorItem(?A, ?B).

TypeEqual(?B, <?A as Iterator>::Item) :-
    IteratorItem(?A, ?B).
```

The most interesting rules are the last two, which allow us to
normalize an associated type on either side. Now that we've done this
rewriting, we can return to our original goal of proving
`Clone(<IntoIter<usize> as Iterator>::Item)`, and we will find that it
is possible. The key difference is that the program clause `Clone(usize)`
would now be written `Clone(?A) :- TypeEqual(?A, usize)`. This means
that we are able to find a (rather convoluted) proof like so:

- `Clone(<IntoIter<usize> as Iterator>::Item)` is provable if:
  - `TypeEqual(<IntoIter<usize> as Iterator>::Item, usize)` is provable if:
    - `IteratorItem(IntoIter<usize>, usize)` is provable if:
      - `TypeEqual(IntoIter<usize>, IntoIter<usize>)` is provable if:
        - `TypeEqual(usize, usize)` is provable. (Which it is, so we're all good.)

So, we can see that this approach at least sort of works, but it has a
number of downsides. One problem is that we've kind of inserted a
"compilation" step -- the logic rules that we get from a trait/impl
now have to be transformed in this non-obvious way that makes them
look quite different from the source. One of the goals of this logic
translation is to help us understand and evaluate new additions to the
trait system; the further it strays from the Rust source, the less
helpful it will be for that purpose.

The other thing is that the whole reason to use syntactic equality
only was to get something a normal Prolog engine would understand, but
we don't really want to use a regular Prolog engine in the compiler
anyway, for a variety of reasons. And these rules in particular, at
least the way I wrote them here, cause a lot of problems for a regular
Prolog engine, because it introduces ambiguity into the proof
search. You could rewrite them in more complex ways, but then we're
straying even further from the simple logic we were looking for.

#### Another approach: just change what equality means!

Ultimately, a better approach is just to say that equality in our
logic includes a notion of normalization. That is, we can basically
take the same rules for type equality that we defined as `TypeEqual(A,
B)` but move it into the *trait-solving engine itself* (or, depending
on your POV, into the metatheory of our logic). So now our trait
solver is defined in terms of the original, straight-forward rules
that we've been writing, but it's understood that when we equate
`usize` with `<IntoIter<usize> as Iterator>::Item`, that succeeds only
if we can recursively prove the predicate
`IteratorItem(IntoIter<usize>, usize)`. This ultimately is the
approach that I've taken in my prototype: the trait solver itself has
a built-in notion of normalization and it always uses it when it is
doing unification. (The scheme I have implemented is what we have
sometimes called "lazy normalization" in the past.)

It may seem like this was always the obvious route to take. And I
suppose in a way it is. But part of why I resisted it for some time
was that I was searching out what is the *simplest* and most minimal
way to define the trait solver; so every notion that we can trivially
"export" into the logic rules is a win in that respect. But equality
is a bridge too far.

#### An aside: call for citations

As an aside, I'd be curious to know if anyone has suggestions for
related work around this area of "customizable equality". In
particular, I'm not aware of logic languages that have to prove goals
to prove equality (though I got some leads at POPL last week that I
have yet to track down).

Along a similar vein, I've also been interested in strengthening the
notion of equality even further, so that we go beyond mere
normalization and include the ability to have arbitrary equality
constraints (e.g., `fn foo<A>() where A = i32``). The key to doing
this is solving a problem called "congruence closure" -- and indeed
there exist good algorithms for doing that, and I've implemented
[one of them][cc] in the [ena] crate that I'm using to do
unification. However, combining this algorithm with the proof search
rules for trait solving, particularly with inference and higher-ranked
trait bounds, is non-trivial, and I haven't found a satisfying
solution to it yet. I would assume that more full-featured theorem
provers like Coq, Lean, Isabelle and so forth have some clever tricks
for tackling these sorts of problems, but I haven't graduated to
reading into those techniques yet, so citations here would be nice too
(though it may be some time before I follow up).

[cc]: http://www.alice.virginia.edu/~weimer/2011-6610/reading/nelson-oppen-congruence.pdf
[ena]: http://github.com/nikomatsakis/ena

### Type-checking normal functions

OK, now that we have defined some logical rules that are able to
express when traits are implemented and to handle associated types,
let's turn our focus a bit towards *type-checking*. Type-checking is
interesting because it is what gives us the goals that we need to
prove. That is, everything we've seen so far has been about how we
derive the rules by which we can prove goals from the traits and impls
in the program; but we are also interesting in how derive the goals
that we need to prove, and those come from type-checking.

Consider type-checking the function `foo()` here:

```rust
fn foo() { bar::<usize>() }
fn bar<U: Eq>() { }
```

This function is very simple, of course: all it does is to call
`bar::<usize>()`. Now, looking at the definition of `bar()`, we can see
that it has one where-clause `U: Eq`. So, that means that `foo()` will
have to prove that `usize: Eq` in order to show that it can call `bar()`
with `usize` as the type argument.

If we wanted, we could write a prolog predicate that defines the
conditions under which `bar()` can be called. We'll say that those
conditions are called being "well-formed":

```
barWellFormed(?U) :- Eq(?U).
```

Then we can say that `foo()` type-checks if the reference to
`bar::<usize>` (that is, `bar()` applied to the type `usize`) is
well-formed:

```
fooTypeChecks :- barWellFormed(usize).
```

If we try to prove the goal `fooTypeChecks`, it will succeed:

- `fooTypeChecks` is provable if:
  - `barWellFormed(usize)`, which is provable if:
    - `Eq(usize)`, which is provable because of an impl.
    
Ok, so far so good. Let's move on to type-checking a more complex function.

### Type-checking generic functions: beyond Horn clauses

In the last section, we used standard Prolog horn-clauses (augmented with Rust's
notion of type equality) to type-check some simple Rust functions. But that only
works when we are type-checking non-generic functions. If we want to type-check
a generic function, it turns out we need a stronger notion of goal than Prolog
can be provide. To see what I'm talking about, let's revamp our previous
example to make `foo` generic:

```rust
fn foo<T: Eq>() { bar::<T>() }
fn bar<U: Eq>() { }
```

To type-check the body of `foo`, we need to be able to hold the type
`T` "abstract".  That is, we need to check that the body of `foo` is
type-safe *for all types `T`*, not just for some specific type. We might express
this like so:

```
fooTypeChecks :-
  // for all types T...
  forall<T> {
    // ...if we assume that Eq(T) is provable...
    if (Eq(T)) {
      // ...then we can prove that `barWellFormed(T)` holds.
      barWellFormed(T)
    }
  }.
```

This notation I'm using here is the notation I've been using in my
prototype implementation; it's similar to standard mathematical
notation but a bit Rustified. Anyway, the problem is that standard
Horn clauses don't allow universal quantification (`forall`) or
implication (`if`) in goals (though many Prolog engines do support
them, as an extension). For this reason, we need to accept something
called "first-order hereditary harrop" (FOHH) clauses -- this long
name basically means "standard Horn clauses with `forall` and `if` in
the body". But it's nice to know the proper name, because there is a
lot of work describing how to efficiently handle FOHH clauses. I was
particularly influenced by Gopalan Nadathur's excellent
["A Proof Procedure for the Logic of Hereditary Harrop Formulas"][FOHH].

[FOHH]: http://dl.acm.org/citation.cfm?id=868380

Anyway, I won't go into the details in this post, but suffice to say
that supporting FOHH is not really all that hard. And once we are able
to do that, we can easily describe the type-checking rule for generic
functions like `foo` in our logic.

### Conclusion and future vision

So, I'm pretty excited about this work. I'll be posting plenty of
follow-up posts that dig into the details in the days to come, but I
want to take a moment in this post to lay out the long-term vision
that I'm shooting for in a bit more depth.

Ultimately, what I am trying to develop is a kind of "middle layer"
for the Rust type system. That is, we can think of modeling Rust
semantics in three layers:

- Pure Rust syntax (the traits, impls, etc that you type)
- Inference rules (the "lowered" form I've been talking about in this
  post)
- Proof search engine (the trait solver in the compiler)

Essentially, what makes the current compiler's trait solver complex is
that it omits the middle layer. This is exactly analogous to the way
that trans in the old compiler was complex because it tried to map
directly from the AST to LLVM's IR, instead of having an intermediate
step (what we now call MIR).

The goal of this work is then to puzzle out what piece of each
structure belongs at each layer such that each individual layer
remains quite simple, but the system still does what we expect. We saw
a bit of that in this post, where I sketched out why it is best to
include type equality in the layer of the "proof search engine" --
i.e., as part of how the inference rules are themselves interpreted --
rather than modeling it in the inference rules themselves. I think
I've made a lot of progress here, as I'll try to lay out in follow-up
posts, but in some areas -- particularly coherence! -- I'm not yet
sure of the right division.

For the moment, I've been implementing things in Rust. You can view my
prototype solver in the [chalk] repository. The code consists of a
[parser] for a [subset of Rust syntax]. It then [lowers this syntax]
into an [internal IR] that maps fairly cleanly to the things I've been
showing you here. What I would like is for chalk to become the
**normative implementation** of the trait system: that is, chalk
basically would describe how the trait system is *supposed* to
behave. To this end, we would prioritize clean and simple code over
efficiency.

[chalk]: http://github.com/nikomatsakis/chalk
[parser]: https://github.com/nikomatsakis/chalk/blob/master/chalk-rust-parse/src/parser.lalrpop
[subset of Rust syntax]: https://github.com/nikomatsakis/chalk/blob/master/chalk-rust-parse/src/ast.rs
[lowers this syntax]: https://github.com/nikomatsakis/chalk/blob/master/chalk-rust/src/lower/mod.rs
[internal IR]: https://github.com/nikomatsakis/chalk/blob/master/chalk-rust/src/ir/mod.rs

Once we have a normative implementation, that means that we could
evaluate the complexity of RFCs that aim to extend the trait system by
implementing them in the normative codebase *first*, so that we can
uncover any complications. As a proof of concept of that approach,
I've implemented withoutboat's
[associated type constructor RFC][RFC1598], which I will describe in a
future post (preview: it's very easy to do and works out beautifully;
in fact, it doesn't add *anything at all* to the logic, once you
consider the fact that we already support generic methods).

[RFC1598]: https://github.com/rust-lang/rfcs/pull/1598

Separately, I'd like to rewrite the trait system in the compiler to
use the same overall strategy as chalk is pioneering, but with a
more optimized implementation. I will say more in follow-up posts, but
I think that this strategy has a good chance of significantly
improving compile-times: it is much more amenable to caching and does
far less redundant work than the current codebase. Moreover, this
approach just seems much cleaner and more capable overall, so I would
expect we would be able to to close out a number of open bugs related
to normalization as well as completing various advanced features, like
specialization. Win-win overall.

Once we have two implementations, I would like to check them against
one another. Basically the compiler would have a special mode in which
it forwards every goal that it tries to prove over to the normative
implementation, as well as solving the goal itself using the efficient
implementation. These two should yield the same results: if they fail
to do so, that's a bug somewhere (probably the compiler, but you never
know).

Finally, I think it should be possible to extract a more formal
description of the trait system from chalk, along the lines of what
I've been sketching here. This would allow us to prove various
properties about the trait system as well as our proof search
algorithm (e.g., it'd be nice to prove that the proof search strategy
we are using is sound and complete -- meaning that it always finds
valid proofs, and that if there is a proof to be found, it will find
it).

This is way too much work to do on my own of course. I intend to focus
my efforts primarily on the compiler implementation, because I would
love to know if indeed I am correct and this is a massive improvement
to compilation time. But along the way I also plan to write-up as many
mentoring bugs as I can, both in chalk and in the compiler itself. I
think this would be a really fun way to get into rustc hacking, and we
can always use more people who know their way around the trait system!

### Comments?

I started a [thread on internals][] to discuss this post and other
(forthcoming) posts in the series.

[thread on internals]: https://internals.rust-lang.org/t/blog-series-lowering-rust-traits-to-logic/4673
