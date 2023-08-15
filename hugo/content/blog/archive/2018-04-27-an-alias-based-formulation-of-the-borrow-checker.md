---
categories:
- Rust
- NLL
date: "2018-04-27T00:00:00Z"
slug: an-alias-based-formulation-of-the-borrow-checker
title: An alias-based formulation of the borrow checker
---

Ever since the Rust All Hands, I've been experimenting with an
alternative formulation of the Rust borrow checker. The goal is to
find a formulation that overcomes some shortcomings of the current
proposal while hopefully also being faster to compute. I have
implemented a prototype for this analysis. It passes the full NLL test
suite and also handles a few cases -- such as [#47680] -- that the
current NLL analysis cannot handle. However, the performance has a
long way to go (it is currently slower than existing analysis). That
said, I haven't even begun to optimize yet, and I know I am doing some
naive and inefficient things that can definitely be done better; so I
am still optimistic we'll be able to make big strides there.

[#47680]: https://github.com/rust-lang/rust/issues/47680#issuecomment-363131420

Also, it was pointed out to me that yesterday, April 26, is the sixth
"birthday" of the borrow check -- it's fun to look at [my commit from
that time][bday], gives a good picture of what Rust was like then.[^alt][^macro]

[bday]: https://github.com/rust-lang/rust/commit/50a3dd40ae8ae6494e55d5cfc29eafdb4172af52

[^alt]: We were still using [the `alt` and `ret` keywords][kw], and not yet using `=>` for match arms! Neat. And still kind of inscrutable to me.

[^macro]: And [macros were like `#foo[..]` instead of `foo!(..)`][spider]. I remember pcwalton used to complain about "squashed spiders" all over the code.

[kw]: https://github.com/rust-lang/rust/commit/50a3dd40ae8ae6494e55d5cfc29eafdb4172af52#diff-26be476d05bea7e3cd4e452d6104482dR1758

[spider]: https://github.com/rust-lang/rust/commit/50a3dd40ae8ae6494e55d5cfc29eafdb4172af52#diff-20cc6d854aa3f056ddd3c36b7c257765R332

### End-users don't have to care

The first thing to note is that this proposal **makes no difference
from the point of view of an end-user of Rust**. That is, the borrow
checker ought to work the same as it would have under the NLL
proposal, more or less.

However, there are some subtle shifts in this proposal in terms of how
the compiler thinks about your program, and that could potentially
affect future language features.

### Our first example

The analysis works on MIR, but I'm going to explain it in terms of
simple Rust examples. Here is the first example, which I will call
example A. The example should not compile, as you can see:

```rust
fn main() {
  let mut x: i32 = 22;
  let mut v: Vec<&i32> = vec![];
  let r: &mut Vec<&i32> = &mut v;
  let p: &i32 = &x; // 1. `x` is borrowed here to create `p`
  r.push(p);        // 2. `p` is stored into `v`, but through `r`
  x += 1;           // <-- Error! can't mutate `x` while borrowed
  take(v);          // 3. the reference to `x` is later used here
}

fn take<T>(p: T) { .. }
```

### Regions are sets of loans

The biggest shift in this new approach is that when you have a type
like `&'a i32`, the meaning of `'a` changes:

- In the system described in the NLL RFC, `'a` -- called a lifetime --
  ultimately corresponded to some portion of the source program or
  control-flow graph.
- Under *this* proposal, `'a` -- which I will be calling a region[^name] --
  instead corresponds to a set of **loans** -- that is, a set of
  borrow expressions, like `&x` or `&mut v` in Example A. The idea is
  that if a reference `r` has type `&'a i32` then invalidating the **terms
  of any of the loans** in `'a` would invalidate `r`.

[^name]: Region is the standard term from academia, so I am adopting it by default, but it doesn't necessarily carry the right "intuitions" here. We should maybe fish about for a better term.

Invalidating the **terms of a loan** means to perform an illegal
access of the path borrowed by the loan. So for example if you have a
mutable loan like `r = &mut v`, then you can only access the value `v`
through the reference `r`. Accessing `v` directly in any way -- read,
write, or move -- would invalidate the loan. For a shared loan like `p
= &x`, reading through `x` (or `p`) is allowed, but writing or
mutating `x` would invalidate the terms of the loan (and writing
through `p` is also not possible).

The subtyping rules for references work a bit differently now that a
region is a set of loans and not program points. Whereas with points,
you can approximate a reference by shortening the lifetime, with sets
of loans you can approximate by enlarging the set. In other words:

```
'a ⊆ 'b
------------------
&'a u32 <: &'b u32
```

In Rust syntax, `'a ⊆ 'b` corresponds to the notation `'a: 'b`, and
that is what I will use for the rest of the post. We have
traditionally called this an *outlives relationship*, but I am going
to call it a *subset relationship* instead, as befits the new meaning
of regions[^covariant].

[^covariant]: Interestingly, this means that the type `&'a u32` is *covariant* with respect to `'a`, whereas before it was most naturally defined as *contravariant* -- that is, *subtypes* correspond to *smaller sets* (but *larger lifetimes*). Again, not a thing that really matters to Rust users, but a nice property for those delving into the type system.

To gain a better intuition for the idea of regions as sets of loans, consider
this program:

```rust
let x = vec![1, 2];

let p: &'a i32 = if random() {
  &x[0] // Loan L0
} else {
  &x[1] // Loan L1
};
```

Here, the region `'a` would correspond to the set `{L0, L1}`, since it
may refer to data produced by the loan L0, but it may also refer to
data from the loan L1.

### Datalog

Throughout this post, I'm going to be defining the analysis by using
[Datalog] rules. Datalog is -- in some sense -- a subset of Prolog
designed for efficient execution. It basically corresponds to rules
like this (using the syntax from the [Souffle] project):

[Datalog]: https://en.wikipedia.org/wiki/Datalog
[Souffle]: https://github.com/oracle/souffle/wiki

```
.decl cfg_edge(P:point, Q:point)
.input cfg_edge

.decl reachable(P:point, Q:point)
reachable(P, Q) :- cfg_edge(P, Q).
reachable(P, R) :- reachable(P, Q), cfg_edge(Q, R).
```

As you can see here, Datalog programs define relations between things;
here those relations are declared with `.decl`[^dot]. Some relations
are **inputs**, declared with `.input`, which means that their values
are given up-front by the user (these are also called facts). In this
program, that is `cfg_edge`. Other relations, like `reachable`, are
defined via rules which synthesize new things from those facts. As in
Prolog, upper-case identifiers are variables, and whenever a variable
appears twice, it must have the same value.

[^dot]: These `.foo` directives are specific to souffle, as far as I know.

Note that, because it is a subset, Datalog avoids a lot of Prolog's
more 'programming language'-like properties. For example, Datalog
programs always terminate when executed on a finite set of facts (even
when they recurse, like the one above). Also, it is fine to use
negative reasoning in a Datalog program, as it disallows negative
cycles -- there are no subtle concerns about the distinction between
"logical not" and "negation as failure".[^neg]

[^neg]: We employ negation in these rules, but only in a particularly trivial way -- negated inputs.

To implement these rules, I've been using Frank McSherry's awesome
[differential-dataflow] crate. This has been a pretty great
experience: once you get the hang of it, you can translate Datalog
rules in a very straightforward way, which means that I've been able
to rapidly prototype new designs in just an hour or two. Moreover, the
resulting execution is quite fast (though I've not measured
performance too much on the latest design).

[differential-dataflow]: https://crates.io/crates/differential-dataflow

### Region variables

Now that we've described regions as sets of loans, I want you to throw
all of that away. The analysis as I've defined it doesn't directly
manipulate those sets, at least not initially. Instead, it uses
"region variables" to represent all the regions in the program. I'll
denote these as "numbered" regions like `'0`, `'1`, etc.

If we rewrite our program then to use these abstract regions
(basically, to have a numbered region everywhere that MIR would have
one), it looks like the following:

```rust
fn main() {
  let mut x: i32 = 22;
  let mut v: Vec<&'0 i32> = vec![];
  let r: &'1 mut Vec<&'2 i32> = &'3 mut v;
  let p: &'5 i32 = &'4 x;
  r.push(p);
  x += 1;
  take::<Vec<&'6 i32>>(v);
}

fn take<T>(p: T) { .. }
```

These abstract regions will appear through our datalog rules; I'll
denote them with `R` for "region".

### Relations between regions

The abstract regions we saw before don't have any meaning just
yet. What happens next is that we walk through and apply the type
system rules in the standard way. This will result in "subset"
relationships between regions, as we saw before. So for example
consider the following line from Example A:

```rust
let p: &'5 i32 = &'4 x;
```

Here, the expression `&'4 x` produces a value of type `&'4 i32`. This
type must be a subtype of the type of `p`, `&'5 i32`, so we get:

    &'4 i32 <: &'5 i32
    
which in turn requires `'4: '5`. If we look at the program, we'll see
a number of subtype relationships emerge. I'll write down each one
along with the resulting subset relationships.

```rust
fn main() {
  let mut x: i32 = 22;

  let mut v: Vec<&'0 i32> = vec![];
  
  let r: &'1 mut Vec<&'2 i32> = &'3 mut v;
  // requires: &'3 mut Vec<&'0 i32> <: &'1 mut Vec<&'2 i32>
  //        => '3: '1, '0: '2, '2: '0

  let p: &'5 i32 = &'4 x;
  // requires: &'4 i32 <: &'5 i32
  //        => '4: '5

  r.push(p);
  // requires: &'5 i32 <: &'2 i32
  //        => '5: '2
  
  x += 1;

  take::<Vec<&'6 i32>>(v);
  // requires: Vec<&'0 i32> <: Vec<&'6 i32>
  //        => '0: '6
}

fn take<T>(p: T) { .. }
```

Ultimately, these subset relationships become input facts into the
system. For reasons that will become clear later on, I call these the
"base subset" relations:

```
.decl base_subset(R1:region, R2:region, P:point)
.input base_subset
```

In other words, `base_subset(R1, R2, P)` means `R1: R2` was required
to be true at the point `P`.

We'll see in a second that this `base_subset` input is only the
starting point -- it tells you which relations were directly required
to begin with, but it doesn't tell you the full set of relations at
any point; this is because the subset relations "accumulate" as you
iterate, so you must ensure both the older relations *and* the newer
ones. We're going to define a more complete `subset` relation that
includes both, but before we can get there, we have to look at how we
define the control-flow graph.

### Points in the control-flow graph

The control-flow graph used by this analysis is defined based on the
MIR. We define the points in the flow-graph as follows:

```
Point = Start(Statement) | Mid(Statement)
Statement = BBi '/' j
```

Here, the `Statement` identifies a particular statement (the `j`th
statement from the `i`th basic block). We then distinguish the **start
point** of a statement from the **mid point**. The start point is
basically "before it has done anything", and the "mid point" is the
place where the statement is executing. As such, all the base-subset
relationships from the previous section are defined to occur at the
mid-point of their corresponding statements.

We define the flow in the graph using a `cfg_edge` input:

```
.decl cfg_edge(P:point, Q:point)
.input cfg_edge
```

Naturally, every start point has an edge to its corresponding mid
point.  Mid points have an edge to the start of the next statement or,
in the case of a terminator, to the start of the basic blocks that
follow.

(For the most part, you can ignore mid-points for now, but they become
very important later on as we integrate notions of liveness.)

### Tracking subset relationships across the graph

Now we come to the most interesting part of the analysis: computing
the subset relations. In the interest of building intuitions, I'm
going to start by presenting a simpler form of this than the final
analysis; then we'll come back and make it a bit more complex.

The key idea here is that the analysis doesn't directly compute the
values of each region variable. Instead, it computes the **subset
relationships** that have to hold between them at each point in the
control-flow graph. These relationships are introduced by the "base
subset" relationships that result from the type-check, but they are
then propagated across control-flow edges, according to the following
rule:

- Once a base subset relationship is introduced between two regions `'a:
  'b`, it must remain true.

We can define this in datalog like so. We start with a relation `subset`:

```
.decl subset(R1:region, R2:region, P:point)
```

The idea is that if `subset(R1, R2, P)` is defined, then `R1: R2` must
hold at the point `P`. We can start with the "base subset" relations
that are supplied by the type checker:

```
// Rule subset1
subset(R1, R2, P) :- base_subset(R1, R2, P).
```

Subset is transitive, so we can define that too:

```
// Rule subset2
subset(R1, R3, P) :- subset(R1, R2, P), subset(R2, R3, P).
```

Finally, we define a rule that propagates subset relationships across
the control-flow graph edges:[^refine]

[^refine]: This subset propagation rule is the rule that we are going to refine later.

```
// Rule subset3 (version 1)
subset(R1, R2, Q) :- subset(R1, R2, P), cfg_edge(P, Q).
```

Easy peezy, lemon squeezy, as my daughter likes to say. If we apply
these rules to our Example A, we wind up with the following subset
relationships in between each statement (I'm only showing the
relationships at each "start" point here, and I'm not showing the full
transitive closure). Note that they just keep growing:

```rust
fn main() {
  let mut x: i32 = 22;
  
  // (none)

  let mut v: Vec<&'0 i32> = vec![];
  
  // (none)

  let r: &'1 mut Vec<&'2 i32> = &'3 mut v;

  // '3: '1, '0: '2, '2: '0

  let p: &'5 i32 = &'4 x;

  // '3: '1, '0: '2, '2: '0, '4: '5

  r.push(p);

  // '3: '1, '0: '2, '2: '0, '4: '5,
  // '5: '2,
  
  x += 1;

  // '3: '1, '0: '2, '2: '0, '4: '5,
  // '5: '2,

  take::<Vec<&'6 i32>>(v);

  // '3: '1, '0: '2, '2: '0, '4: '5,
  // '5: '2, '0: '6
}

fn take<T>(p: T) { .. }
```

Consider the final set of relationships. Based on this, we can see
some interesting stuff. For example, we can see a relationship between
the region `'4` (that is, the region from the borrow of `x`) and the
region `'0` (that is, the region for the data in the vector `v`):

    '4: '5: '2: '0

This is basically reflecting the flow of data in your program. If you
think of each region as representing a "set of loans", then this is
saying that `'0` (that is, the vector) may hold references that
derived from that `&x` statement. This leads to our next piece of the
analysis.

### Borrow regions

So far, we introduced the *subset* relation that shows the
relationships between region variables and showed how that can be
extended to the control-flow graph. We're going to do the same now for
tracking which regions depend on which loans.

First off, we introduce a new input, called `borrow_region`:

```
.decl borrow_region(R:region, L:loan, P:point)
.input borrow_region
```

This input is defined for each borrow expression (e.g., `&x` or `&mut v`)
in the program. It relates the region from the borrow to the abstract
loan that is created. Here is Example A, annotated with the borrow-regions
that are created at each point:

```rust
fn main() {
  let mut x: i32 = 22;
  let mut v: Vec<&'0 i32> = vec![];
  let r: &'1 mut Vec<&'2 i32> = &'3 mut v;
  // borrow_region('3, L0)
  let p: &'5 i32 = &'4 x;
  // borrow_region('4, L1)
  r.push(p);
  x += 1;
  take::<Vec<&'6 i32>>(v);
}

fn take<T>(p: T) { .. }
```

Like the `base_subset` relations, `borrow_region` are created at the
mid-point of the corresponding borrow statement.

### Live regions and loans

In normal compiler parlance, a variable X is **live** at some point P
in the control-flow graph if **its current value may be used later**
(more formally, if there is some path from P to Q, where Q uses X, and
X is not assigned along that path).

We can make an analogous definition for regions: a region `'a` is
**live** at some point `P` if some reference with type `&'a i32` may be
dereferenced later. For the most part, this just means that there is a
live variable `X` and that `'a` appears in the type of `X`. There is
however some subtleness about drops, since we try to be clever and
understand which regions a destructor might use and which it will not
(e.g., we know that a value of type `Vec<&'a u32>` will not access
`'a` when it is dropped). I'm not going into the details of how that
works here, it's the same as it was defined in the [NLL RFC].

[NLL RFC]: https://rust-lang.github.io/rfcs/2094-nll.html

In terms of the Datalog, we can define an input `region_live_at` like so:

```
.decl region_live_at(R:region, P:point)
.input region_live_at
```

The initial values here are computed just as in the NLL RFC.

### The "requires" relation

Now we can extend the `borrow_region` relation across the control-flow
graph.  As before, we introduce a new relation, called `requires`:

```
.decl requires(R:region, L:loan, P:point)
```

This can be read as

> The region R requires the terms of the loan L to be enforced at the point P.

Or, to put another way:

> If the terms of the loan L are violated at the point P, then the region R is invalidated.

(I don't love the name "requires", but I haven't thought of a better one yet.)

The first rule says that the region for a borrow is always dependent on its
corresponding loan:

```
// Rule requires1
requires(R, L, P) :- borrow_region(R, L, P).
```

The next rule says that if `R1: R2`, then `R2` depends on any loans that `R1` depends on: 

```
// Rule requires2
requires(R2, L, P) :- requires(R1, L, P), subset(R1, R2, P).
```

Finally, we can propagate these requirements across control-flow
edges, just as with subsets. But here, there is a twist:

```
// Rule requires3 (version 1)
requires(R, L, Q) :-
  requires(R, L, P),
  !killed(L, P),
  cfg_edge(P, Q).
```

This rule says that if the region `R` requires the loan `L` at `P`,
then it also requires `L` at the successor `Q` -- *so long as `L` is
not "killed" at `P`*. So what is this `!killed(L, P)` rule? The killed
input relation is defined as follows:

```
.decl killed(L:loan, P:point)
.input killed
```

`killed(L, P)` is defined when the point `P` is an assignment that
overwrites one of the references whose referent was borrowed in the
loan `L`. Imagine you have something like this:

```rust
let p = 22;
let q = 44;
let x: &mut i32 = &mut p; // `x` points at `p`
let y = &mut *x; // Loan L0, `y` points at `p` too
// ...
x = &mut q; // `x` points at `q`; kills L0
```

Here, `x` initially referenced `p`, and that is copied into `y`. At
this point (where we see `...`), accessing `*x` is illegal, because
`y` has borrowed it. But then `x` is reassigned to point at `q`
instead -- now accessing `*x` doesn't alias `*y` anymore. This is
reflected by *killing* the loan L0, thus indicating that `y` would no
longer be invalidated by accessing `*x`.

We can now annotate Example A to include both the `subset` relations
and the `requires` relations at each point. As before, I'm not going
to show the full transitive closure of possibilities, but rather just
the "base facts". You can see that they continue to accumulate as we
move through the program:

```rust
fn main() {
  let mut x: i32 = 22;
  
  // (none)

  let mut v: Vec<&'0 i32> = vec![];
  
  // (none)

  // Loan L0
  let r: &'1 mut Vec<&'2 i32> = &'3 mut v;

  // '3: '1, '0: '2, '2: '0
  // requires('3, L0)

  // Loan L1
  let p: &'5 i32 = &'4 x;

  // '3: '1, '0: '2, '2: '0, '4: '5
  // requires('3, L0)
  // requires('4, L1)

  r.push(p);

  // '3: '1, '0: '2, '2: '0, '4: '5,
  // '5: '2,
  // requires('3, L0)
  // requires('4, L1)
  
  x += 1;

  // '3: '1, '0: '2, '2: '0, '4: '5,
  // '5: '2,
  // requires('3, L0)
  // requires('4, L1)

  take::<Vec<&'6 i32>>(v);

  // '3: '1, '0: '2, '2: '0, '4: '5,
  // '5: '2, '0: '6
  // requires('3, L0)
  // requires('4, L1)
}

fn take<T>(p: T) { .. }
```

In particular, consider the set of facts that hold on entry to the `x += 1`
statement:

```
// '3: '1, '0: '2, '2: '0, '4: '5,
// '5: '2,
// requires('3, L0)
// requires('4, L1)
```

Note that the loan L1 is a shared borrow of `x`, and `'4` requires
`L1`. Moreover, the variable `v` holds references of type `&'0
i32`, and we can see that `'4` is a subset of `'0`:

    '4: '5: '2: '0
    
This implies that the references in the vector `v` would be
invalidated by mutating `x`, since that would invalidate the terms of
L1. Seeing as `v` is going to be used on the next line, that's a
problem -- and that leads us to the final part of our rules, the
definition of an error.

### Defining an "error"

And now finally we can define what a borrow check error is. We define
an input `invalidates(P, L)`, which indicates that some access or
action at the point P invalidates the terms of the loan L:

```
.decl invalidates(P:point, L:loan)
.input invalidates
```

Next, we extend the notion of liveness from regions to **loans**. A
loan L is live at the point P if some live region R requires it:

```
.decl loan_live_at(R:region, P:point)

// Rule loan_live_at1
loan_live_at(L, P) :-
  region_live_at(R, P),
  requires(R, L, P).
```

Finally, it is an error if a point P invalidates a loan L while the
loan L is live:

```
.decl error(P:point)

// Rule error1
error(P) :-
  invalidates(P, L),
  loan_live_at(L, P).
```  

### Refining constraint propagation with liveness

This is *almost* the analysis that I implemented, except for one
point. We can refine the constraint propagation slightly by taking
liveness into account, which allows us to accept a lot more programs.
Consider this example, annotated with the key facts introduced at each
point (remember, these facts propagate forward through control flow):

```rust
let x = 22;
let y = 44;
let mut p: &'0 i32 = &'1 x; // Loan L0
  // '1: '0
  // requires('1, L0)
p = &'3 y; // Loan L1
  // '3: '0
  // requires('3, L1)
x += 1;
  // invalidates(L0)
print(*p);
```

It would be nice if we could accept this program: although `p`
initially refers to `x`, it is later re-assigned to refer to `y`, so
by the time we execute `x += 1` the loan could be released. However,
under the rules I've given thus far, we would reject it, because we
are steadily accumulating information. Therefore, at the point where
we do `x += 1`, we can derive that `requires('0, L0)` quite trivially.

The problem arises because we *re-assigned* an existing variable `p`
rather than declaring a new one. This re-uses the same region `'0`.
We *could* therefore solve this by modifying the program to use a
fresh variable:

```rust
let x = 22;
let y = 44;
let p: &'0 i32 = &'1 x;
let q: &'4 i32 = &'3 y;
x += 1;
print(*q);
```

But that's not a very satisfying answer. Another possibility would be
to rewrite using something like SSA form, which would basically
automate that transformation above. That remains an option, but it's
not what I chose to do -- among other things, variables in MIR are
"places", and using SSA form kind of complicates that. (That is,
variables can be borrowed and assigned indirectly and so forth.)

What I did instead is to modify the rules that propagate subset and
requires relations between points. Previously, those rules were
defined to propagate indiscriminately. Now we modify them to only
propagate relations for regions that are live at the successor point:

```
// Rule subset3 (version 2)
subset(R1, R2, Q) :-
  subset(R1, R2, P),
  cfg_edge(P, Q),
  region_live_at(R1, Q), // new 
  region_live_at(R2, Q). // new

// Rule requires3 (version 2)
requires(R, L, Q) :-
  requires(R, L, P),
  !killed(L, P),
  cfg_edge(P, Q),
  region_live_at(R, Q). // new
```

Using these rules, our original program is accepted. The key point is
that on entry to the line `p = &y`, the variable `p` is dead (its
value is about to be overwritten), and hence its region `'0` is also
dead. Therefore, the `requires` (and `subset`) constraints that affect
it do not propagate forward.

This improvement is also crucial to accepting the example from [#47680],
which is rejected by the current NLL analysis:

```rust
struct Thing;

impl Thing {
  fn maybe_next(&mut self) -> Option<&mut Self> {
    ..
  }
}
    
fn main() {
  let mut temp = &mut Thing;
          
  loop {
    match temp.maybe_next() {
      Some(v) => { temp = v; }
      None => { }
    }
  }
}
```

Here, the problem is that `temp.maybe_next()` borrows `*temp`. This
borrow is returned -- sometimes -- through the variable `v`, and then
stored back into `temp` (replacing the value of `temp`). This means,
if you trace it out, that indeed the borrow is live around the
loop. You might think it would be "killed" because we reassigned temp
(and indeed it *should* be), but with the current rules it was not,
because when `None` was returned, `temp` was not reassigned. Basically
the analysis was getting tripped up with the loop.

Under the new rules, however, we can see that -- along the `Some` path
-- the loan gets killed, because `temp` is reassigned. Meanwhile --
along the `None` path -- the `requires` relation is dropped, because
it is only associated with dead regions at that point. So the program
is accepted.

### Top-down vs bottom-up and causal computation

Of course, in a real compiler, knowing whether or not there are errors
is not enough. We also need to be able to report the error nicely to
the user.  The NLL RFC proposed a technique for reporting errors that
I called [three-point form]:

[three-point form]: https://rust-lang.github.io/rfcs/2094-nll.html#leveraging-intuition-framing-errors-in-terms-of-points

> To the extent possible, we will try to explain all errors in terms of three points:
>
> - The point where the borrow occurred (B).
> - The point where the resulting reference is used (U).
> - An intervening point that might have invalidated the reference (A).

One of the intriguing byproducts of framing the analysis as a series
of Datalog rules is that we can extract these three points by looking
at the way we derived each error. That is, consider the error in
Example A, where we had an illegal `x += 1`. If that increment
occurred at the point `P`, we might have found the error by querying
`error(P)`. If we were using Prolog, which executes "top-down" (i.e.,
starting from the goal we trying to prove), then we might encounter a
proof tree like this:

```
error(P) :-
  invalidates(P, L1),        // input fact
  loan_live_at(L1, P) :-     // rule loan_live_at1
    region_live_at('0, P),   // input fact
    requires('0, L1, P) :-   // rule requires2
      requires('4, L1, P) :- // rule requires3
        ...
      subset('4, '0, P) :-   // rule subset3
        ...
```

If you look over this tree, everything you need to know is in
there. There is an error at point P because (a) P invalidates L1 and
(b) L1 is live. L1 is live because `'0` is live and `'0` requires
L1. `'0` requires L1 because of `'4`...  and so on. We just need to
write some heuristics to decide what to extract out.

Traditionally, however, Datalog executes bottom-up -- that is, it
computes all the base facts, then the facts derived from those, and so
on. This can be more efficient, but it can be wasteful if all those
facts are not ultimately needed. There are techniques for combining
top-down and bottom-up propagation (e.g., [magic sets]); there are
also techniques for getting "explanations" out of Datalog --
basically, a minimal set of facts that are needed to derive a given
tuple (like `error(P)`). [One such technique][t] was even
[implemented][expl] and defined using [differential-dataflow], which
is great.

[magic sets]: https://www.sciencedirect.com/science/article/pii/S0004370212000562
[t]: http://www.vldb.org/pvldb/vol9/p1137-chothia.pdf
[expl]: https://github.com/frankmcsherry/explanation

I've not really done much in this direction yet -- I'm still trying to ensure
this is the analysis we want -- but it seems clear that if we go this
way we should be able to get good error information out.

### Questions?

I've opened an [thread on the Rust internals board][thread] for discussion.

[thread]: https://internals.rust-lang.org/t/blog-post-an-alias-based-formulation-of-the-borrow-checker/7411

### Thanks

I want to take a moment to say thanks to a few people and projects who
influenced this idea. First off, Frank McSherry's awesome
[differential-dataflow] crate really did enable me to iterate a lot
faster. Very good stuff.

Second, I have been wondering for some time why the compiler's type
system seemed to operate quite differently from a traditional alias
analysis. Some time ago I had a very interesting conversation with
Lionel Parreaux about an interesting alternative approach to Rust's
borrow checking, where regions were regular expressions over program
paths; then later I was talking with Vytautas Astrauskas and Federico
Poli at the Rust All Hands about their efforts to integrate Rust with
the [Viper static verifier][viper], which required them to re-engineer
alias relationships quite similar to the subset relation described
here. Pondering these efforts, I re-read a number of the latest papers
on alias analysis on large C programs. This, combined with a lot of
experimentation and iteration, led me here. So thanks all!

[viper]: http://www.pm.inf.ethz.ch/research/viper.html

### Footnotes
