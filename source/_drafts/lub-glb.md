One of the more challenging parts of the region type system is coping
with bound lifetimes in function types, particularly as they relate to
least-upper-bound and greatest-lower-bound computations during
inference.  I believe I have worked out the correct algorithm, but it
is decidedly non-trivial.  I am sure that this has been worked out
before, but I haven't found any paper describing it.  Tips in that
direction would be nice. Without further adieu, here is the algorithm.

A warning: this post is not likely to be of general interest.

<!-- more -->

### Background

Briefly, the issue is that we want to compute the least-upper-bound of
function types and they may include bound lifetimes.  Here I will use
the contention that upper-case lifetime names are free and lower-case
are bound.  For example, the LUB (closest mutual supertype) of
`fn(&a/T)` and `fn(&A/T)` is `fn(&A/T)`, because the bound lifetime
`a` can be instantiated to the free lifetime `A` but not vice versa.
Similarly, the GLB of those two types is `fn(&a/T)`, for the same
reason.

Here are some trickier examples and the results.  A `--` indicates
that there is no upper bound:

```
Type 1         Type 2         LUB            GLB
fn(&a)         fn(&X)         fn(&X)         fn(&a)
fn(&A)         fn(&X)         --             fn(&a)
fn(&a, &b)     fn(&x, &x)     fn(&a, &a)     fn(&a, &b)
fn(&a, &b, &a) fn(&x, &y, &y) fn(&a, &a, &a) fn(&a, &b, &c)
```

Notice the last two examples in particular.

For deeper background, you may want to read [my comment][mc] in the
Rust source that explains the general issues and in particular covers
how to implement the subtyping algorithm.  This [old blog post][obp]
is also relevant.

### LUB

The LUB algorithm proceeds in three steps:

1. Replace all bound regions (on both sides) with fresh region
   inference variables.
2. Compute the LUB "as normal", meaning compute the GLB of each
   pair of argument types and the LUB of the return types and
   so forth.  Combine those to a new function type F.
3. Map the regions appearing in `F` using the procedure described below.

For each region `R` that appears in `F`, we may need to replace it
with a bound region.  Let `V` be the set of fresh variables created as
part of the LUB procedure (either in step 1 or step 2).  You may be
wondering how variables can be created in step 2.  The answer is that
when we are asked to compute the LUB or GLB of two region variables,
we do so by producing a new region variable that is related to those
two variables.  i.e., The LUB of two variables `$x` and `$y` is a
fresh variable `$z` that is constrained such that `$x <= $z` and `$y
<= $z`.

To decide how to replace a region `R`, we must examine `Tainted(R)`.
This function searches through the constraints which were generated
when computing the bounds of all the argument and return types and
produces a list of all regions to which `R` is related, directly or
indirectly.

If `R` is not in `V` or `Tainted(R)` contains any region that is not
in `V`, then `R` is not replaced (that is, `R` is mapped to itself).
Otherwise, if `Tainted(R)` is a subset of `V`, then we select the
earliest variable in `Tainted(R)` that originates from the left-hand
side and replace `R` with a bound version of that variable.

So, let's work through the simplest example: `fn(&A)` and `fn(&a)`.
In this case, `&a` will be replaced with `$a` (the $ indicates an
inference variable) which will be linked to the free region `&A`, and
hence `V = { $a }` and `Tainted($a) = { &A }`.  Since `$a` is not a
member of `V`, we leave `$a` as is.  When region inference happens,
`$a` will be resolved to `&A`, as we wanted.

So, let's work through the simplest example: `fn(&A)` and `fn(&a)`.
In this case, `&a` will be replaced with `$a` (the $ indicates an
inference variable) which will be linked to the free region `&A`, and
hence `V = { $a }` and `Tainted($a) = { $a, &A }`.  Since `&A` is not a
member of `V`, we leave `$a` as is.  When region inference happens,
`$a` will be resolved to `&A`, as we wanted.

Let's look at a more complex one: `fn(&a, &b)` and `fn(&x, &x)`.
In this case, we'll end up with a graph that looks like:

```
     $a        $b     *--$x
       \        \    /  /
        \        $h-*  /
         $g-----------*
```

Here `$g` and `$h` are fresh variables that are created to represent
the LUB/GLB of things requiring inference.  This means that `V` and
`Tainted` will look like:

```
V = {$a, $b, $x}
Tainted($g) = Tainted($h) = { $a, $b, $h, $x }
```

Therefore we replace both `$g` and `$h` with `$a`, and end up
with the type `fn(&a, &a)`.

### GLB

The procedure for computing the GLB is similar.  The difference lies
in computing the replacements for the various variables. For each
region `R` that appears in the type `F`, we again compute `Tainted(R)`
and examine the results:

1. If `Tainted(R) = {R}` is a singleton set, replace `R` with itself.
2. Else, if `Tainted(R)` contains only variables in `V`, and it
   contains exactly one variable from the LHS and one variable from
   the RHS, then `R` can be mapped to the bound version of the
   variable from the LHS.
3. Else, `R` is mapped to a fresh bound variable.

These rules are pretty complex.  Let's look at some examples to see
how they play out.

Out first example was `fn(&a)` and `fn(&X)`---in
this case, the LUB will be a variable `$g`, and `Tainted($g) =
{$g,$a,$x}`.  By these rules, we'll replace `$g` with a fresh bound
variable, so the result is `fn(&z)`, which is fine.

The next example is `fn(&A)` and `fn(&Z)`. XXX

The next example is `fn(&a, &b)` and `fn(&x, &x)`. In this case, as
before, we'll end up with `F=fn(&g, &h)` where `Tainted($g) =
Tainted($h) = {$g, $a, $b, $x}`.  This means that we'll select fresh
bound varibales `g` and `h` and wind up with `fn(&g, &h)`.

For the last example, let's consider what may seem trivial, but is
not: `fn(&a, &a)` and `fn(&x, &x)`.  In this case, we'll get `F=fn(&g,
&h)` where `Tainted($g) = {$g, $a, $x}` and `Tainted($h) = {$h, $a,
$x}`.  Both of these sets contain exactly one bound variable from each
side, so we'll map them both to `&a`, resulting in `fn(&a, &a)`.
Horray!

### Why is this correct?

You may be wondering whether this algorithm is correct.  So am I.  But
I believe it is.  There are various properties that it should fulfill:

1. *Valid:* If `LUB(T1, T2)` (resp. GLB) yields `T3`, then
   `T1 <: T3` and `T2 <: T3` (resp. `T3 <: T1`, `T3 <: T2`).
2. *Complete:* If `LUB(T1, T2)` (resp. GLB) results in an error,
   then there is no upper bound (resp. lower bound).
3. *Maximal:* There is no tighter, valid bound.

Actually I would be willing to sacrifice maximality, to some extent,
as that would affect completness of the (already incomplete) inference
algorithm but not soundness.  But as it happens I believe these
algorithms are maximal.

Let me try to rephrase the algorithms above in a more theoretical
fashion. Basically what's happening is that we are 

<!-- Footnotes -->

[mc]: https://github.com/mozilla/rust/blob/1a3a70760b4dfe03e135f28b5456d61752d3e677/src/rustc/middle/typeck/infer/region_inference.rs#L127
[obp]: /blog/2012/04/23/on-types-and-type-schemes/
