---
layout: post
title: Polonius and the case of the hereditary harrop predicate
categories: [Rust, NLL]
---

In my [previous post][pp] about Polonius and subregion obligations, I
mentioned that there needs to be a follow-up to deal with
higher-ranked subregions. This post digs a bit more into what the
*problem* is in the first place and sketches out the general solution
I have in mind, but doesn't give any concrete algorithms for it.

[pp]: {{< baseurl >}}/blog/2019/01/17/polonius-and-region-errors/

### The subset relation in Polonius is not enough

In my original post on Polonius, I assumed that when we computed a
subtype relation `T1 <: T2` between two types, the result was either a
hard error or a set of `subset` relations between various regions.
So, for example, if we had a subtype relation between two references:

```
&'a u32 <: &'b u32
```

the result would be a `subset` relation `'a: 'b` (or, "`'a` contains a
subset of the loans in `'b`").

For a more complex case, consider the relationship of two fn types:

```
fn(&'a u32) <: fn(&'b u32)
// ^^^^^^^     ^^^^^^^^^^
// |           A fn expecting a `&'b u32` as argument.
// |
// A fn expecting a `&'a u32` as argument.
```

If we imagine that we have some variable `f` of type `fn(&'a u32)` --
that is, a fn that can be called with a `'a` reference -- then this
subtype relation is saying that `f` can be given the type `fn(&'b
u32)` -- that is, a fn that can be called with a `'b` reference.  That
is fine so long as that `'b` reference can be used as a `'a`
reference: that is, `&'b u32 <: &'a u32`. So, we can say that the two
fn types are subtypes so long as `'b: 'a` (note that the order is
reversed from the first example; this is because fn types are
*contravariant* in their argument type).

Unfortunately, this structure isn't flexible enough to accommodate a
subtyping question involving higher-ranked types. Consider a subtype
relation like this:

```
fn(&'a u32) <: for<'b> fn(&'b u32)
//             ^^^^^^^
//             Unlike before, the supertype
//             expects a reference with *any*
//             lifetime as argument.
```

What subtype relation should come from this? We can't say `'b: 'a` as
before, because the lifetime `'b` isn't some specific region --
rather, the supertype says that the function has to accept a reference
with *any* lifetime `'b`. In fact, this subtyping relation should
ultimately yield an error.

### Richer constraints

To express the constraints that arise from higher-ranked subtyping
(and trait matching), we need a richer set of constraints than just
subset. In fact, if you tease it all out, we need something more like
this:

```
Constraint = Subset
           | Constraint, Constraint // and
           | forall<R1> { Constraint }
           | exists<R1> { Constraint }

Subset = R1: R2  
```

Now we can say that

```
fn(&'a u32) <: for<'b> fn(&'b u32)
```

holds if the constraint `forall<'b> { 'b: 'a }` holds, which implies
that `'a` has to contain all possible loans. This isn't possible, and
so we would treat this as an error.

Interestingly, if we reverse the order of the two types:

```
for<'b> fn(&'b u32) <: fn(&'a u32)
```

we get the constraint `exists<'b> { 'a: 'b }` (`for` binders on the
*subtype* side are instantiated with "there exists", not "for
all"). That is, the region `'a` must be a subset of some possible set
of loans `'b`. This constraint is trivially solveable: `'b` could
always be exactly `'a` itself.

### The role of free vs bound regions

As one final example, consider what happens here, where we added a
return type and another region (`'c`):

```
for<'b> fn(&'b u32) -> &'b u32
           <:
        fn(&'a u32) -> &'c u32
```

This gives rise to the following constraint:

```
exists<'b> {
  'a: 'b, // from relating the parameter types
  'b: 'c, // from relating the return types
}
```

Here, the constraint is solveable, but only if `'a: 'c`. Therefore, if
we think back to Polonius with its simple "subset" relations, we can
effective *reduce* this "rich" constraint to the subset relation `'a:
'c`.

To do this reduction, we draw a distinction between the *bound* and
the *free* regions. *Bound* regions are those that are bound within a
`forall` and `exists` quantifiers (e.g., `'b`), and *free* regions
those that are not. When we are reducing, we only care about two things:

- **Do we have something *unsatisfiable* about the constraint?** This
  often happens when a bound "forall" region is on the right-hand
  side.
  - We saw this with `forall<'b> { 'b: 'a }`.
  - Another example is `forall<'x, 'y> { 'x: 'y }`.
  - Reducing something unsatisfiable is obviously an error.
- **What are the effects on the free regions?** Othertimes, bound
  regions effectively as a "go-between", creating subset relations
  between the free regions.
  - We saw this with `exists<'b> { 'a: 'b, 'b: 'c }`.
  - Another, stranger example might be `forall<'b> { 'a: 'b }`: here,
    this is satisfiable, but only if `'a: 'static`. This is true
    because `'static: 'b` is implicitly true (`'static: R` is true for
    any region R).
    - In Polonius terms, `'static` represents an "empty set" of loans,
      so this effectively means that `'a` can be a subset of any
      region `'b` by being the empty set.

### Wait, those "richer" constraints look familiar...

The "richer" constraints I mentioned in the previous section basically
arise from taking a base predicate (`R1: R2`) and "adding in" richer
constraint forms like "for all" and "there exists". This may sound
familiar -- if you recall [my very first Chalk post][chalk1], I talked
about the [need to go beyond Prolog's core "Horn clauses" and to
support "Hereditary Harrop" (HH) predicates][hh]. The basic idea was
to extend simple Horn clauses with "for all" and "there exists", along
with a few other things.

In fact, "hereditary harrop predicates" are a kind of generic
structure that we can apply to any base set of predicates. So, if we
wanted, we might say that the region constraints we are creating can
be extended to the full hereditary harrop form, which would look like
so:

[chalk1]: {{< baseurl >}}/blog/2017/01/26/lowering-rust-traits-to-logic/#type-checking-generic-functions-beyond-horn-clauses
[hh]: {{< baseurl >}}/blog/2017/01/26/lowering-rust-traits-to-logic/#type-checking-generic-functions-beyond-horn-clauses

```
Constraint = Subset
           | Constraint, Constraint // and
           | Constraint; Constraint // or
           | forall<R1> { Constraint }
           | exists<R1> { Constraint }
           | if (Assumption) { Constraint }
           
Assumption = Subset
           | forall<R1> { Assumption }
           | if (Constraint) { Assumption }

Subset = R1: R2  
```

Here we support not only "for all" and "there exists" but also
"implication" and even "or". rustc doesn't use constraints this rich
today, but for various reasons I think we will want to eventually.

Why is it useful to talk about HH predicates? Well, HH predicates have
the nice property that we can use basic Prolog-style search to find
and enumerate all possible solutions to them. Besides, "hereditary
harrop" is really fun to say.

### Conclusion

So now we have this problem. To encode the "solutions" to
higher-ranked subtyping and trait matching, we need to use this richer
notion of constraints that include `forall` and `exists`
quantifiers. Once we add those, we are basically talking about
"hereditary harrop region constraints". We've also talked about the
idea of mapping these complex constraints down to the simple subset
relation that Polonius uses, but here I only gave examples and didn't
really give any sort of *algorithm*. I've done some experiments here,
and I may try to write them up in a future post, but I'm also curious
to know if somebody else has already solved this problem. I definitely
have that "reinventing the wheel" feeling here.

One really *nice* aspect of this general direction, though, is that it
means that Polonius effectively doesn't care about these "richer"
constraints. The idea is that our subtyping and trait matching
algorithms can produce hereditary harrop region constraints (or some
subset thereof). These can be reduced to simpler subset constraints,
which are then passed to Polonius to do the final reasoning. (And, of
course, any of these steps may also produce an error.)

Comments, as usual, are requested in the [internals thread for this
blog post series][internals].

[internals]: https://internals.rust-lang.org/t/blog-post-an-alias-based-formulation-of-the-borrow-checker/7411
