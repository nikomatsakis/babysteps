---
categories:
- Rust
- Traits
- Chalk
- PL
date: "2017-04-23T00:00:00Z"
subslug: unification-in-chalk-part-2
title: Associated types
slug: unification-in-chalk-part-2
title: Unification in Chalk, part 2
---

In my previous post, I talked over the basics of how
[unification works][pp] and showed how that "mathematical version" winds
up being expressed in chalk. I want to go a bit further now and extend
that base system to cover [associated types]. These turn out to be a
pretty non-trival extension.

[pp]: {{ site.baseurl }}/blog/2017/03/25/unification-in-chalk-part-1/
[associated types]: https://doc.rust-lang.org/nightly/book/second-edition/ch19-03-advanced-traits.html#associated-types

### What is an associated type?

If you're not a Rust programmer, you may not be familiar with the term
"associated type" (although many langages have equivalents). The basic
idea is that traits can have **type members** associated with them.  I
find the most intuitive example to be the `Iterator` trait, which has
an associated type `Item`. This type corresponds to kind of elements
that are produced by the iterator:

```rust
trait Iterator {
    type Item;
    
    fn next(&mut self) -> Option<Self::Item>;
}
```

As you can see in the `next()` method, to reference an associated
type, you use a kind of path -- that is, when you write `Self::Item`,
it means "the kind of `Item` that the iterator type `Self` produces".
I often refer to this as an **associated type projection**, since one
is "projecting out"[^1] the type `Item`.

[^1]: Projection is a very common bit of jargon in PL circles, though it typically refers to accessing a field, not a type. As far as I can tell, no mainstream programmer uses it. Ah well, I'm not aware of a good replacement. 

Let's look at an impl to make this more concrete. Consider
[the type `std::vec::IntoIter<T>`][ii], which is one of the iterators
associated with a vector (specifically, the iterator you get when you
invoke `vec.into_iter()`). In that case, the elements yielded up by
the iterator are of type `T`, so we have an impl like:

[ii]: https://doc.rust-lang.org/std/vec/struct.IntoIter.html

```rust
impl<T> Iterator for IntoIter<T> {
    type Item = T;
    fn next(&mut self) -> Option<T> { ... }
}
```

This means that if we have the type `IntoIter<i32>::Item`, that is
**equivalent** to the type `i32`. We usually call this process of
converting an associated trait projection (`IntoIter<i32>::Item`) into
the type found in the impl **normalizing** the type.

In fact, this `IntoIter<i32>::Item` is a kind of shorthand; in
particular, it didn't explicitly state what trait the type `Item` is
defined in (it's always possible that `IntoIter<i32>` implements more
than one trait that define an associated type called `Item`). To make
things fully explicit, then, one can use a **fully qualified path**
like this:

    <IntoIter<i32> as Iterator>::Item
     ^^^^^^^^^^^^^    ^^^^^^^^   ^^^^
     |                |          |
     |                |          Associated type name
     |                Trait
     Self type

I'll use these fully qualified paths from here on out to avoid confusion.

### Integrating associated types into our type system

In this post, we will extend our notion of types to include associated type projections:

```
T = ?X               // type variables
  | N<T1, ..., Tn>   // "applicative" types
  | P                // "projection" types   (new in this post)
P = <T as Trait>::X
```

Projection types are quite different from the existing "applicative"
types that we saw before. The reason is that they introduce a kind of
"alias" into the equality relationship. With just applicative types,
we could always make progress at each step: that is, no matter what
two types were being equated, we could always break the problem down
into simpler subproblems (or else error out). For example, if we had
`Vec<?T> = Vec<i32>`, we knew that this could **only** be true if `?T
== i32`.

With associated type projections, this is not always true. Sometimes we
just can't make progress. Imagine, for example, this scenario:

    <?X as Iterator>::Item = i32

Here we know that `?X` is some kind of iterator that yields up `i32`
elements: but we have no way of knowing *which* iterator it is, there
are many possibilities. Similarly, imagine this:

    <?X as Iterator>::Item = <T as Iterator>::Item

Here we know that `?X` and `T` are both iterators that yield up the
same sort of items. But this doesn't tell us anything about the
relationship between `?X` and `T`.

### Normalization constraints

To handle associated types, the basic idea is that we will introduce
**normalization constraints**, in addition to just having equality
constraints. A normalization constraint is written like this:

    <IntoIter<i32> as Iterator>::Item ==> ?X   

This constraint says that the associated type projection
`<IntoIter<i32> as Iterator>::Item`, when *normalized*, should be
equal to `?X` (a type variable). As we will see in more detail in a
bit, we're going to then go and solve those normalizations, which
would eventually allow us to conclude that `?X = i32`.

(We could use the Rust syntax `IntoIter<i32>: Iterator<Item=?X>` for
this sort of constraint as well, but I've found it to be more
confusing overall.)

Processing a normalization constraint is very simple to processing a
standard trait constraint. In fact, in chalk, they are literally the
same code. If [you recall from my first Chalk post][first], we can
lower impls into a series of clauses that express the trait that is
being implemented along with the values of its associated types. In
this case, if we look at the impl of `Iterator` for [the `IntoIter` type][IntoIter]:

[IntoIter]: https://doc.rust-lang.org/std/vec/struct.IntoIter.html
[first]: {{ site.baseurl }}/blog/2017/01/26/lowering-rust-traits-to-logic/

```rust
impl<T> Iterator for IntoIter<T> {
    type Item = T;
    fn next(&mut self) -> Option<T> { ... }
}
```

We can translate this impl into a series of clauses sort of like this
(here, I'll use [the notation I was using in my first post][firstat]):

[firstat]: {{ site.baseurl }}/blog/2017/01/26/lowering-rust-traits-to-logic/#associated-types-and-type-equality


```
// Define that `IntoIter<T>` implements `Iterator`,
// if `T` is `Sized` (the sized requirement is
// implicit in Rust syntax.)
Iterator(IntoIter<T>) :- Sized(T).

// Define that the `Item` for `IntoIter<T>`
// is `T` itself (but only if `IntoIter<T>`
// implements `Iterator`).
IteratorItem(IntoIter<T>, T) :- Iterator(IntoIter<T>).
```

So, to solve the normalization constraint `<IntoIter<i32> as
Iterator>::Item ==> ?X`, we translate that into the goal
`IteratorItem(IntoIter<i32>, ?X)`, and we try to prove that goal by
searching the applicable clauses. I sort of sketched out the procedure
[in my first blog post][first], but I'll present it in a bit more detail
here. The first step is to "instantiate" the clause by replacing
the variables (`T`, in this case) with fresh type variables.
This gives us a clause like:

    IteratorItem(IntoIter<?T>, ?T) :- Iterator(IntoIter<?T>).

Then we can unify the arguments of the clause with our goals, leading
to two unification equalities, and combine that with the conditions of the
clause itself, leading to three things we must prove:

    IntoIter<?T> = IntoIter<i32>
    ?T = ?X
    Iterator(IntoIter<?T)
    
Now we can recursively try to prove those things. To prove the
equalities, we apply the unification procedure we've been looking
at. Processing the first equation, we can simplify because we have two
uses of `IntoIter` on both sides, so the type arguments must be equal:

    ?T = i32 // changed this
    ?T = ?X
    Iterator(IntoIter<?T>)
    
From there, we can deduce the value of `?T` and do some substitutions:

    i32 = ?X
    Iterator(IntoIter<i32>)

We can now unify `?X` with i32, leaving us with:

    Iterator(IntoIter<i32>)

We can apply the clause `Iterator(IntoIter<T>) :- Sized(T)` using the same procedure now,
giving us two fresh goals:

    IntoIter<i32> = IntoIter<?T>
    Sized<?T>
    
The first unification will yield (eventually):

    Sized<i32>

And we can prove this because this is a built-in rule for Rust (that is, that `i32` is sized).

### Unification as just another goal to prove

As you can see in the walk through in the previous section, in a lot
of ways, unification is "just another goal to prove". That is, the
basic way that chalk functions is that it has a goal it is trying to
prove and, at each step, it tries to simplify that goal into
subgoals. Often this takes place by consulting the clauses that we
derived from impls (or that are builtin), but in the case of equality
goals, the subgoals are constructed by the builtin unification
algorithm.

In the [previous post][pp], I gave [various pointers][htii] into the
implementation showing how the unification code looks "for real".
I want to extend that explanation now to cover associated types.

[htii]: http://smallcultfollowing.com/babysteps/blog/2017/03/25/unification-in-chalk-part-1/#how-this-is-implemented

The way I presented things in the previous section, unification
flattens its subgoals into the master list of goals. But in fact, for
efficiency, the unification procedure will typically eagerly process
its own subgoals. So e.g. when we transform `IntoIter<i32> =
IntoIter<?T>`, we actually just
[invoke the code to equate their arguments immediately][unifyargs].

[unifyargs]: https://github.com/nikomatsakis/chalk/blob/6a7bb25402987421d93d02bda3f5d79bf878812c/src/solve/infer/unify.rs#L107-L109

The one exception to this is normalization goals. In that case, we
push the goals into
[a separate list that is returned to the caller][goalslist]. The
reason for this is that, sometimes, we can't make progress on one of
those goals immediately (e.g., if it has unresolved type variables, a
situation we've not discussed in detail yet). The caller can throw it
onto a list of pending goals and come back to it later.

[goalslist]: https://github.com/nikomatsakis/chalk/blob/6a7bb25402987421d93d02bda3f5d79bf878812c/src/solve/infer/unify.rs#L41

Here are the various cases of interest that we've covered so far

- [Equating a projection with a non-projection](https://github.com/nikomatsakis/chalk/blob/6a7bb25402987421d93d02bda3f5d79bf878812c/src/solve/infer/unify.rs#L115-L122) will invoke [`unify_projection_ty`](https://github.com/nikomatsakis/chalk/blob/6a7bb25402987421d93d02bda3f5d79bf878812c/src/solve/infer/unify.rs#L161-L166) which just pushes a goal onto the output list. This covers both equating a type variable or an application type with a projection.
- [Equating two projections](https://github.com/nikomatsakis/chalk/blob/6a7bb25402987421d93d02bda3f5d79bf878812c/src/solve/infer/unify.rs#L111-L113) will invoke [`unify_projection_tys`](https://github.com/nikomatsakis/chalk/blob/6a7bb25402987421d93d02bda3f5d79bf878812c/src/solve/infer/unify.rs#L161-L166) which creates the intermediate type variable. The reason for this is discussed shortly.

### Fallback for projection

Thus far we showed how projection proceeds in the "successful" case,
where we manage to normalize a projection type into a simpler type (in
this case, `<IntoIter<i32> as Iterator>::Item` into `i32`). But
sometimes we want to work with generics we *can't* normalize the
projection any further. For example, consider this simple function,
which extracts the first item from a non-empty iterator (it panics if
the iterator *is* empty):

```rust
fn first<I: Iterator>(iter: I) -> I::Item {
    iter.next().expect("iterator should not be empty")
}
```

What's interesting here is that we don't know what `I::Item` is. So imagine
we are given a normalization constraint like this one:

    <I as Iterator>::Item ==> ?X

What type should we use for `?X` here? What chalk opts to do in cases
like this is to construct a sort a special "applicative" type
representing the associated item projection. I will write it as
`<Iterator::Item><I>`, for now, but there is no real Rust syntax for
this.  It basically represents "a projection that we could not
normalize further". You could consider it as a separate item in the
grammar for types, except that it's not really semantically different
from a projection; it's just a way for us to guide the chalk solver.

The way I think of it, there are two rules for proving that a
projection type is equal. The first one is that we can prove it via
normalization, as we've already seen:

    IteratorItem(T, X)
    -------------------------
    <T as Iterator>::Item = X

The second is that we can prove it just by having all the *inputs* be equal:

    T = U
    ---------------------------------------------
    <T as Iterator>::Item = <U as Iterator>::Item

We'd prefer to use the normalization route, because it is more
flexible (i.e., it's sufficient for `T` and `U` to be equal, but not
necessary). But if we can definitively show that the normalization
route is impossible (i.e., we have no clauses that we can use to
normalize), then we we opt for this more restrictive route. The
special "applicative" type is a way for chalk to record (internally)
that for this projection, it opted for the more restrictive route,
because the first one was impossible.

(In general, we're starting to touch on Chalk's proof search strategy,
which is rather different from Prolog, but beyond the scope of this
particular blog post.)

### Some examples of the fallback in action

In the `first()` function we saw before, we will wind up computing
the result type of `next()` as `<I as Iterator>::Item`. This will be
returned, so at some point we will want to prove that this type
is equal to the return type of the function (actually, we want to prove
subtyping, but for this particular type those are the same thing, so I'll
gloss over that for now). This corresponds to a goal like the following
(here I am using [the notation I discussed in my first post for universal
quantification etc][bhc]):

[bhc]: http://smallcultfollowing.com/babysteps/blog/2017/01/26/lowering-rust-traits-to-logic/#type-checking-generic-functions-beyond-horn-clauses

    forall<I> {
        if (Iterator(I)) {
            <I as Iterator>::Item = <I as Iterator>::Item
        }
    }

Per the rules we gave earlier, we will process this constraint by introducing
a fresh type variable and normalizing both sides to the same thing:

    forall<I> {
        if (Iterator(I)) {
            exists<?T> {
                <I as Iterator>::Item ==> ?T,
                <I as Iterator>::Item ==> ?T,
            }
        }
    }
    
In this case, both constraints will wind up resulting in `?T` being
the special applicative type `<Iterator::Item><I>`, so everything
works out successfully.

Let's briefly look at an illegal function and see what happens here.
In this case, we have two iterator types (`I` and `J`) and we've
used the wrong one in the return type:

```rust
fn first<I: Iterator, J: Iterator>(iter_i: I, iter_j: J) -> J::Item {
    iter_i.next().expect("iterator should not be empty")
}
```

This will result in a goal like:

    forall<I, J> {
        if (Iterator(I), Iterator(J)) {
            <I as Iterator>::Item = <J as Iterator>::Item
        }
    }

Which will again be normalized and transformed as follows:

    forall<I, J> {
        if (Iterator(I), Iterator(J)) {
            exists<?T> {
                <I as Iterator>::Item ==> ?T,
                <J as Iterator>::Item ==> ?T,
            }
        }
    }

Here, the difference is that normalizing `<I as Iterator>::Item` results in
`<Iterator::Item><I>`, but normalizing `<J as Iterator>::Item` results in
`<Iterator::Item><J>`. Since both of those are equated with `?T`, we will
ultimately wind up with a unification problem like:

    forall<I, J> {
        if (Iterator(I), Iterator(J)) {
            <Iterator::Item><I> = <Iterator::Item><J>
        }
    }

Following our usual rules, we can handle the equality of two
applicative types by equating their arguments, so after that we get
`forall<I, J> I = J` -- and this clearly cannot be proven. So we get
an error.

### Termination, after a fashion

One final note, on termination. We do not, in general, guarantee
termination of the unification process once associated types are
involved. [Rust's trait matching is turing complete][tc], after all.
However, we *do* wish to ensure that our own unification algorithms
don't introduce problems of their own! 

[tc]: https://sdleffler.github.io/RustTypeSystemTuringComplete/

The non-projection parts of unification have a pretty clear argument
for termination: each time we remove a constraint, we replace it with
(at most) simpler constraints that were all embedded in the original
constraint.  So types keep getting smaller, and since they are not
infinite, we must stop sometime.

This argument is not sufficient for projections. After all, we replace
a constraint like `<T as Iterator>::Item = U` with an equivalent
normalization constraint, where all the types are the same:

    <T as Iterator>::Item ==> U

The argument for termination then is that normalization, if it
terminates, will unify `U` with an applicative type. Moreover, we only
instantiate type variables with normalized types. Now, these
applicative types might be the special applicative types that Chalk
uses internally (e.g., `<IteratorItem><T>`), but it's an applicative
type nontheless. When that *applicative* type is processed later, it
will therefore be broken down into smaller pieces (per the prior
argument). That's the rough idea, anyway.

### Contrast with rustc

I tend to call the normalization scheme that chalk uses **lazy**
normalization.  This is because we don't normalize until we are
actually equating a projection with some other type. In constrast,
rustc uses an **eager** strategy, where we normalize types as soon as
we "instantiate" them (e.g., when we took a clause and replaced its
type parameters with fresh type variables).

The eager strategy has a number of downsides, not the least of which
that it is very easy to forget to normalize something when you were
supposed to (and sometimes you wind up with a mix of normalized and
unnormalized things).

In rustc, we only have one way to represent projections (i.e., we
don't distinguish the "projection" and "applicative" version of
`<Iterator::Item><T>`). The distinction between an unnormalized `<T as
Iterator>::Item` and one that we failed to normalize further is made
simply by knowing (in the code) whether we've tried to normalize the
type in question or not -- the unification routines, in particular,
always assume that a projection type implies that normalization
wouldn't succeed.

### A note on terminology

I'm not especially happy with the "projection" and "applicative"
terminology I've been using. Its's what Chalk uses, but it's kind of
nonsense -- for example, both `<T as Iterator>::Item` and `Vec<T>` are
"applications" of a type function, from a certain perspective. I'm not
sure what's a better choice though. Perhaps just "unnormalized" and
"normalized" (with types like `Vec<T>` always being immediately
considered normalized). Suggestions welcome.

### Conclusion

I've sketched out how associated type normalization works in chalk and
how it compares to rustc. I'd like to change rustc over to this
strategy, and plan to open up an issue soon describing a
strategy. I'll post a link to it in the [internals comment thread]
once I do.

There are other interesting directions we could go with associated
type equality. For example, I was pursuing for some time a strategy
based on congruence closure, and even implemented (in [ena])
[an extended version of the algorithm described here][cc]. However,
I've not been able to figure out how to combine congruence closure
with things like implication goals -- it seems to get quite
complicated. I understand that there are papers tackling this topic
(e.g, [Selsam and de Moura][lean]), but haven't yet had time to read
it.

[cc]: http://www.alice.virginia.edu/~weimer/2011-6610/reading/nelson-oppen-congruence.pdf
[ena]: https://crates.io/crates/ena
[lean]: https://arxiv.org/pdf/1701.04391.pdf

### Comments?

I'll be monitoring [the internals thread] for comments and discussion. =)

[the internals thread]: https://internals.rust-lang.org/t/blog-series-lowering-rust-traits-to-logic/4673

### Footnotes

