---
layout: post
title: Polonius and region errors
categories: [Rust, NLL]
---

Now that NLL has been shipped, I've been doing some work revisiting
[the Polonius project][gh]. Polonius is the project that implements
[the "alias-based formulation" described in my older
blogpost][pp]. Polonius has come a long way since that post; it's now
quite fast and also experimentally integrated into rustc, where it
passes the full test suite.

[pp]: {{ site.baseurl }}/blog/2018/04/27/an-alias-based-formulation-of-the-borrow-checker/

[gh]: https://github.com/rust-lang-nursery/polonius/

However, polonius as described is not complete. It describes the core
"borrow check" analysis, but there are a number of other checks that
the current implementation checks which polonius ignores:

- Polonius does not account for **moves and initialization**.
- Polonius does not check for **relations between named lifetimes**.

This blog post is focused on the second of those bullet points. It
covers the simple cases; hopefully I will soon post a follow-up that
targets some of the more complex cases that can arise (specifically,
dealing with higher-ranked things).

### Brief Polonius review

If you've never read the [the original Polonius post][pp], you should probably
do so now. But if you have, let me briefly review some of the key details
that are relevant to this post:

- Instead of interpreting the `'a` notation as the *lifetime* of a
  reference (i.e., a set of points), we interpret `'a` as a *set of
  **loans***. We refer to `'a` as a "region"[^academic] in order to
  emphasize this distinction.
- We call `'a: 'b` a **subset** relation; it means that the loans in
  `'a` must be a subset of the loans in `'b`. We track the required
  subset relations at each point in the program.
- A **loan** comes from some borrow expression like `&foo`. A loan L0
  is "live" if some live variable contains a region `'a` whose value
  includes L0. When a loan is live, the "terms of the loan" must be
  respected: for a shared borrow like `&foo`, that means the path that
  was borrowed (`foo`) cannot be mutated. For a mutable borrow, it
  means that the path that was borrowed cannot be accessed at all.
  - If an access occurs that violates the terms of a loan, that is an
    error.

[^academic]: The term "region" is not an especially good fit, but it's common in academia.

### Running Example 1

Let's give a quick example of some code that should result in an
error, but which would not if we only considered the errors that
polonius reports today:

```rust
fn foo<'a, 'b>(x: &'a [u32], y: &'b [u32]) -> &'a u32 {
    &y[0]
}
```

Here, we declared that we are returning a `&u32` with lifetime `'a`
(i.e., borrowed from `x`) but in fact we are returning data with
lifetime `'b` (i.e., borrowed from `y`).

Slightly simplified, the MIR for this function looks something like
this.

```
fn foo(_1: &'a [u32], _2: &'b [u32]) -> &'a [u32] {
  _0 = &'X (*_2)[const 0usize]; // S0
  return;                       // S1
}  
```

As you can see, there's only really one interesting statement; it
borrows from `_2` and stores the result into `_0`, which is the
special "return slot" in MIR.

In the case of the parameters `_1` and `_2`, the regions come directly
from the method signature. For regions appearing in the function body,
we create fresh region variables -- in this case, only one, `'X`. `'X`
represents the region assigned to the borrow.

The relevant polonius facts for this function are as follows:

- `base_subset('b, 'X, mid(S0))` -- as [described in the NLL
  RFC][reborrow], "re-borrowing" the referent of a reference (i.e.,
  `*_2`) creates a subset relation between the region of the region
  (here, `'b`) and the region of the borrow (here, `'X`). Written in
  the notation of the [NLL RFC], this would be the relation `'X: 'b @
  mid(S0)`.
- `base_subset('X, 'a, mid(S0))` -- the borrow expression in S0
  produces a result of type `&'X u32`. This is then assigned to `_0`,
  which has the type `&'a [u32]`.  The [subtyping rules][subtyping]
  require that `'X: 'a`.

[reborrow]: https://rust-lang.github.io/rfcs/2094-nll.html#reborrow-constraints
[subtyping]: https://rust-lang.github.io/rfcs/2094-nll.html#subtyping

Combining the two `base_subset` relations allows us to conclude that
the full subset relation includes `subset('b, 'a, mid(S0))` -- that
is, for the function to be valid, the region `'b` must be a subset of
the region `'a`. This is an error because the regions `'a` and `'b`
are actually parameters to `foo`; in other words, `foo` must be valid
for *any* set of regions `'a` and `'b`, and hence we cannot know if
there is a subset relationship between them. **This is a different
sort of error than the "illegal access" errors that Polonius reported
in the past:** there is no access at all, in fact, simply subset
relations.

### Placeholder regions

There is an important distinction between named regions like `'a` and
`'b` and the region `'X` we created for a borrow. The definition of
`foo` has to be true **for all** regions `'a` and `'b`, but for a
region like `'X` there only has to be *some* valid value. This
difference is often called being *universally quantified* (true for
all regions) versus *existentially quantified* (true for *some*
region).

In this post, I will call universally quantified regions like `'a` and
`'b` **"placeholder" regions**. This is because they don't really
represent a known quantity of loans, but rather a kind of
"placeholder" for some unknown set of loans.

We will include a base fact that helps us to identify placeholder regions:

```
.decl placeholder_region(R1: region)
.input placeholder_region
```

This fact is true for any placeholder region. So in our example we might have

```
placeholder_region('a).
placeholder_region('b).
```

Note that the actual polonius impl already includes a relation like
this[^universal], because we need to account for the fact that
placeholder regions are "live" at all points in the control-flow
graph, as we always assume there may be future uses of them that we
cannot see.

[^universal]: Currently called `universal_region`, though I plan to rename it.

### Representing known relations

Even placeholder regions are not *totally* unknown though. The
function signature will often include where clauses (or implied
bounds) that indicate some known relationships between placeholder
regions. For example, if `foo` included a where clause like `where 'b:
'a`, then it would be perfectly legal.

We can represent the known relationships using an input:

```
.decl known_base_subset(R1: region, R2: region)
.input known_base_subset
```

Naturally these known relations are transitive, so we can define a
`known_subset` rule to encode that:

```
.decl known_subset(R1: region, R2: region)

known_subset(R1, R2) :- known_base_subset(R1, R2).
known_subset(R1, R3) :- known_base_subset(R1, R2), known_subset(R2, R3).
```

In our example of `foo`, there are no where clauses nor implied
bounds, so these relations are empty. If there were a where clause
like `where 'b: 'a`, however, then we would have a
`known_base_subset('b, 'a)` fact. Similarly, per out implied bounds
rules, such an input fact might be derived from an argument with a
type like `&'a &'b u32`, where there are 'nested' regions.

### Detecting illegal subset relations

We can now extend the polonius rules to report errors for cases like
our running example. The basic idea is this: if the function requires
a subset relationship `'r1: 'r2` between two placeholder regions `'r1`
and `'r2`, then it must be a "known subset", or else we have an error.
We can encode this like so:

```
.decl subset_error(R1: region, R2: region, P:point)

subset_error(R1, R2, P) :-
  subset(R1, R2, P),      // `R1: R2` required at `P`
  placeholder_region(R1), // `R1` is a placeholder
  placeholder_region(R2), // `R2` is also a placeholder
  !known_subset(R1, R2).  // `R1: R2` is not a "known subset" relation.
```

In our example program, we can clearly derive `subset_error('b, 'a, mid(S0))`,
and hence we have an error:

- we saw earlier that `subset('a, 'b, mid(S0))` holds
- as `'a` is a placeholder region, `placeholder_region('a)` will
  appear in the input (same for `'b`)
- finally, the `known_base_subset` (and hence `known_subset`) relation
  in our example is empty

**Sidenote on negative reasoning and stratification.** This rule makes
use of negative reasoning in the form of the `!known_subset(R1, R2)`
predicate. Negative reasoning is fine in datalog so long as the
program is "stratified" -- in particular, we must be able to compute
the entire `known_subset` relation without having to compute
`subset_error`. In this case, the program is trivialy stratified --
`known_subset` depends only on the input relation
`known_base_subset`.)

### Observation about borrowing local data

It is interesting to walk through a different example. This is another
case where we expect an error, but in this case the error arises
because we are returning a reference to the stack:

```rust
fn bar<'a>(x: &'a [u32]) -> &'a u32 {
    let stack_slot = x[0];
    &stack_slot
}
```

Polonius will report an error for this case, but not because of the
mechanisms in this blog post. What happens instead is that we create a
loan for the borrow expression `&stack_slot`, we'll call it `L0`. When
the borrow is returned, this loan `L0` winds up being a member of the
`'a` region.  It is therefore "live" when the storage for `stack_slot`
is popped from the stack, which is an error: you can't pop the storage
for a stack slot where there are live loans that have reference it.

### Conclusion

This post describes a simple extension to the polonius rules that
covers errors arising from subset relations. Unlike the prior rules,
these errors are not triggered by any "access", but rather simply the
creation of a (transitive) subset relation between two placeholder
regions.

Unfortunately, this is not the complete story around region checking
errors. In particular, this post ignored subset relations that can
arise from "higher-ranked" types like `for<'a> fn(&'a u32)`. Handling
these properly requires us to introduce a bit more logic and will be
covered in a follow-up.

Comments, if any, should be posted in [the internals thread dedicated to my previous
polonius post][internals]

[internals]: https://internals.rust-lang.org/t/blog-post-an-alias-based-formulation-of-the-borrow-checker/7411

### Appendix: A (potentially) more efficient formulation

The `subset_error` formulation above relied on the transitive `subset`
relation to work, because we wanted to report errors any time that one
placeholder wound up being forced to be a subset of another. In the
more optimized polonius implementations, we don't compute the full
transitive relation, so it might be useful to create a new relation
`subset_placeholder` that is specific to placeholder regions:

```
.decl subset_placeholder(R1: region, R2: region, P:point)
```

The idea is that `subset_placeholder(R1, R2, P)` means that, at the
point P, we know that `R1: R2` must hold, where `R1` is a placeholder.
You can express this via a "base" rule:

```
subset_placeholder(R1, R2, P) :-
  subset(R1, R2, P),      // `R1: R2` required at `P`
  placeholder_region(R1). // `R1` is a placeholder
```

and a transitive rule:

```
subset_placeholder(R1, R3, P) :-
  subset_placeholder(R1, R2, P), // `R1: R2` at P where `R1` is a placeholder
  subset(R2, R3, P).      // `R2: R3` required at `P`
```

Then we reformulate the `subset_error` rule to be based on `subset_placeholder`:

```
.decl subset_error(R1: region, R2: region, P:point)

subset_error(R1, R2, P) :-
  subset_placeholder(R1, R2, P), // `R1: R2` required at `P`
  placeholder_region(R2), // `R2` is also a placeholder
  !known_subset(R1, R2).  // `R1: R2` is not a "known subset" relation.
```

### Footnotes
