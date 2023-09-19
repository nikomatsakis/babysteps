---
layout: post
title: Non-lexical lifetimes using liveness and location
categories: [Rust, NLL]
---

At the recent compiler design sprint,
[we spent some time discussing **non-lexical lifetimes**][etherpad],
the plan to make Rust's lifetime system significantly more advanced. I
want to write-up those plans here, and give some examples of the kinds
of programs that would now type-check, along with some that still will
not (for better or worse).

If you were at the sprint, then the system I am going to describe in
this blog post will actually sound quite a bit different than what we
were talking about. However, I believe it is equivalent to that
system. I am choosing to describe it differently because this version,
I believe, would be significantly more efficient to implement (if
implemented naively). I also find it rather easier to understand.

I have a [prototype implementation][nll] of this system. The example
used in this post, along with the ones from previous posts, have all
been tested in this prototype and work as expected.

[nll]: https://github.com/nikomatsakis/nll
[etherpad]: https://public.etherpad-mozilla.org/p/rust-compiler-design-sprint-paris-2017-nll

### Yet another example

I'll start by giving an example that illustrates the system pretty
well, I think. This section also aims to give an intution for how the
system works and what set of programs will be accepted without going
into any of the details. Somewhat oddly, I'm going to number this
example as "Example 4". This is because my [previous post][nll0]
introduced examples 1, 2, and 3. If you've not read that post, you may
want to, but don't feel you have to. The presentation in this post is
intended to be independent.

[nll0]: http://smallcultfollowing.com/babysteps/blog/2016/04/27/non-lexical-lifetimes-introduction/
[nll1]: http://smallcultfollowing.com/babysteps/blog/2016/05/04/non-lexical-lifetimes-based-on-liveness/
[nll2]: http://smallcultfollowing.com/babysteps/blog/2016/05/09/non-lexical-lifetimes-adding-the-outlives-relation/

#### Example 4: Redefined variables and liveness

I think the key ingredient to understanding how NLL should work is
understanding **liveness**. The term "liveness" derives from compiler
analysis, but it's fairly intuitive. We say that **a variable is live
if the current value that it holds may be used later**. This is very
important to Example 4:

```rust
let mut foo, bar;
let p = &foo;
// `p` is live here: its value may be used on the next line.
if condition {
    // `p` is live here: its value will be used on the next line.
    print(*p);
    // `p` is DEAD here: its value will not be used.
    p = &bar;
    // `p` is live here: its value will be used later.
}
// `p` is live here: its value may be used on the next line.
print(*p);
// `p` is DEAD here: its value will not be used.
```

Here you see a variable `p` that is assigned in the beginning of the
program, and then maybe re-assigned during the `if`. The key point is
that `p` becomes **dead** (not live) in the span before it is
reassigned.  This is true even though the variable `p` will be used
again, because the **value** that is in `p` will not be used.

So how does liveness relate to non-lexical lifetimes? The key rule is
this: **Whenever a variable is live, all references that it may
contain are live.** This is actually a finer-grained notion than just
the liveness of a variable, as we will see. For example, the first
assignment to `p` is `&foo` -- we want `foo` to be borrowed everywhere
that this assignment may later be accessed. This includes both
`print()` calls, but excludes the period after `p = &bar`. Even though
the variable `p` is live there, it now holds a different reference:

```rust
let foo, bar;
let p = &foo;
// `foo` is borrowed here, but `bar` is not
if condition {
    print(*p);
    // neither `foo` nor `bar` are borrowed here
    p = &bar;   // assignment 1
    // `foo` is not borrowed here, but `bar` is
}
// both `foo` and `bar` are borrowed here
print(*p);
// neither `foo` nor `bar` are borrowed here,
// as `p` is dead
```

Our analysis will begin with the liveness of a variable (the
coarser-grained notion I introduced first). However, it will use
reachability to refine that notion of liveness to obtain the liveness
of individual **values**.

#### Control-flow graphs and point notation

Recall that in NLL-land, all reasoning about lifetimes and borrowing
will take place in the context of [MIR][], in which programs are represented
as a control-flow graph. This is what Example 4 looks like as a control-flow graph:

[MIR]: https://blog.rust-lang.org/2016/04/19/MIR.html

```
// let mut foo: i32;
// let mut bar: i32;
// let p: &i32;

A
[ p = &foo     ]
[ if condition ] ----\ (true)
       |             |
       |     B       v
       |     [ print(*p)     ]
       |     [ ...           ]
       |     [ p = &bar      ]
       |     [ ...           ]
       |     [ goto C        ]
       |             |
       +-------------/
       |
C      v
[ print(*p)    ]
[ return       ]
```

As a reminder, I will use a notation like `Block/Index` to refer to a
specific point (statement) in the control-flow graph. So `A/0` and
`B/2` refer to `p = &foo` and `p = &bar`, respectively. Note that
there is also a point for the goto/return terminators of each block
(i.e., A/1, B/4, and C/1).

Using this notation, we can say that we want `foo` to be borrowed
during the points A/1, B/0, and C/0. We want `bar` to be borrowed
during the points B/3, B/4, and C/0.

### Defining the NLL analysis

Now that we have our two examples, let's work on defining how the NLL
analysis will work.

#### Step 0: What is a lifetime?

The lifetime of a reference is defined in our system to be a **region
of the control-flow graph**. We will represent such regions as a set
of points.

A note on terminology: For the remainder of this post, I will often
use the term **region** in place of "lifetime". Mostly this is because
it's the standard academic term and it's often the one I fall back to
when thinking more formally about the system, but it also feels like a
good way to differentiate the lifetime of the **reference** (the
region where it is in use) with the lifetime of the **referent** (the
span of time before the underlying resource is freed).

#### Step 1: Instantiate erased regions

The plan for adopting NLL is to do type-checking in two phases.  The
first phase, which is performed on the HIR, I would call **type
elaboration**. This is basically the "traditional type-system"
phase. It infers the types of all variables and other things, figures
out where autoref goes, and so forth; the result of this is the MIR.

The key change from today is that I want to do all of this type
elaboration using erased regions. That is, until we build the MIR, we
won't have any regions at all. We'll just keep a placeholder (which
I'll write as `'erased`). So if you have something like `&i32`, the
elaborated, internal form would just be `&'erased i32`. This is quite
different from today, where the elaborated form includes a specific
region. (However, this erased form is precisely what we want for
generating code, and indeed MIR today goes through a "region erasure"
step; this step would be unnecessary in the new plan, since MIR as
produced by type check would always have fully erased regions.)

Once we have built MIR, then, the idea is roughly to go and replace
all of these erased regions with inference variables. This means we'll
have region inference variables in the types of all local variables;
it also means that for each borrow expression like `&foo`, we'll have
a region representing the lifetime of the resulting reference. I'll
write the expression together with this region like so: `&'0 foo`.

Here is what the CFG for Example 4 looks like with regions
instantiated.  You can see I used the variable `'0` to represent the
region in the type of `p`, and `'1` and `'2` for the regions of the
two borrows:

```
// let mut foo: i32;
// let mut bar: i32;
// let p: &'0 i32;

A
[ p = &'1 foo  ]
[ if condition ] ----\ (true)
       |             |
       |     B       v
       |     [ print(*p)     ]
       |     [ ...           ]
       |     [ p = &'2 bar   ]
       |     [ ...           ]
       |     [ goto C        ]
       |             |
       +-------------/
       |
C      v
[ print(*p)    ]
[ return       ]
```

#### Step 2: Introduce region constraints

Now that we have our region variables, we have to introduce
constraints.  These constriants will come in two kinds:

- liveness constraints; and,
- subtyping constraints.

Let's look at each in turn.

#### Liveness constraints.

The basic rule is this: **if a variable is live on entry to a point P,
then all regions in its type must include P**.

Let's continue with Example 4. There, we have just one variable, `p`.
It's type has one region (`'0`) and it is live on entry to A/1, B/0,
B/3, B/4, and C/0. So we wind up with a constraint like this:

    {A/1, B/0, B/3, B/4, C/0} <= '0
    
We also include a rule that for each borrow expression like `&'1 foo`,
`'1` must include the point of borrow. This gives rise to two further
constraints in Example 4:

    {A/0} <= '1
    {B/2} <= '2

#### Location-aware subtyping constraints

The next thing we do is to go through the MIR and establish the normal
subtyping constraints. However, we are going to do this with a slight
twist, which is that we are going to take the current location into
account. That is, instead of writing `T1 <: T2` (`T1` is required to
be a subtype of `T2`) we will write `(T1 <: T2) @ P` (`T1` is required
to be a subtype of `T2` at the point P). This in turn will translate
to region constraints like `(R2 <= R1) @ P`.

Continuing with Example 4, there are a number of places where
subtyping constraints arise. For example, at point A/0, we have `p =
&'1 foo`. Here, the type of `&'1 foo` is `&'1 i32`, and the type of
`p` is `&'0 i32`, so we have a (location-aware) subtyping constraint:

    (&'1 i32 <: &'0 i32) @ A/1
    
which in turn implies    

    ('0 <= '1) @ A/1 // Note the order is reversed.

Note that the point here is A/1, not A/0. This is because A/1 is **the
first point in the CFG where this constraint must hold on entry**.

The meaning of a region constraint like `('0 <= '1) @ P` is that,
starting from the point P, the region `'1` must include all points
that are reachable without leaving the region `'0`. The implementation
basically does a depth-first search starting from P; the search stops
if we exit the region `'0`. Otherwise, for each point we find, we add
it to `'1`.

Jumping back to example 4, we wind up with two constraints in total.
Combining those with the liveness constraint, we get this:

    ('0 <= '1) @ A/1
    ('0 <= '2) @ B/3
    {A/1, B/0, B/3, B/4, C/0} <= '0
    {A/0} <= '1
    {B/2} <= '2
    
We can now try to find the smallest values for `'0`, `'1`, and `'2`
that will make this true. The result is:

    '0 = {A/1, B/0, B/3, B/4, C/0}
    '1 = {A/0, A/1, B/0, C/0}
    '2 = {B/3, B/4, C/0}

**These results are exactly what we wanted.** The variable `foo` is
borrowed for the region `'1`, which does not include B/3 and B/4.
This is true even though the `'0` includes those points; this is
because you cannot reach B/3 and B/4 from A/1 without going through
B/1, and `'0` does not include B/1 (because `p` is not live at
B/1). Similarly, `bar` is borrowed for the region `'2`, which begins
at B/4 and extends to C/0 (and need not include earlier points, which
are not reachable).

You may wonder why we do not have to include **all** points in `'0` in
`'1`. Intuitively, the reasoning here is based on liveness: `'1` must
ultimately include all points where the reference may be accessed. In
this case, the subregion constraint arises because we are copying a
reference (with region `'1`) into a variable (let's call it `x`) whose
type includes the region `'0`, so we need reads of `'0` to also be
counted as reads of `'1` -- **but, crucially, only those reads that
may observe this write**. Because of the liveness constraints we saw
earlier, if `x` will later be read, then `x` must be live along the
path from this copy to that read (by the definition of liveness,
essentially). Therefore, because the variable is live, `'0` will
include that entire path. Hence, by including the points in `'0` that
are reachable from the copy (without leaving `'0`), we include all
potential reads of interest.

### Conclusion

This post presents a system for computing non-lexical lifetimes. It
assumes that all regions are erased when MIR is created. It uses only
simple compiler concepts, notably liveness, but extends the subtyping
relation to take into account **where** the subtyping must hold. This
allows it to disregard unreachable portions of the control-flow.

I feel pretty good about this iteration. Among other things, it seems
so simple I can't believe it took me this long to come up with
it. This either means that is it the right thing or I am making some
grave error. If it's the latter people will hopefully point it out to
me. =) It also seems to be efficiently implementable.

I want to emphasize that this system is the result of a lot of
iteration with a lot people, including (but not limited to) Cameron
Zwarich, Ariel Ben-Yehuda, Felix Klock, Ralf Jung, and James Miller.

It's interesting to compare this with various earlier attempts:

- Our earliest thoughts assumed continuous regions (e.g., [RFC 396]).
  The idea was that the region for a reference ought to correspond to
  some continuous bit of control-flow, rather than having "holes" in
  the middle.
  - The example in this post shows the limitation of this,
    however. Note that the region for the variable `p` 
    includes B/0 and B/4 but excludes B/1.
  - This is why we lean on **liveness requirements** instead, so as to
    ensure that the region contains all paths from where a reference is
    created to where it is eventually dereferenced.
- An alternative solution might be to consider continuous regions but apply
  an SSA or SSI transform.
  - This allows the example in this post to type, but it falls down on
    more advanced examples, such as [vec-push-ref][vpr] (hat tip,
    Cameron Zwarich). In particular, it's possible for subregion
    relations to arise without a variable being redefined.
  - You can go farther, and give variables a distinct type at
    each point in the program, as in Ericson2314's
    [stateful MIR for Rust][smr]. But even then you must contend with
    invariance or you have the same sort of problems.
  - Exploring this led to the development of the "localized" subregion
    relationship constraint `(r1 <= r2) @ P`, which I had in mind
    [in my original series][outlives] but which we elaborated more fully at the
    rustc design sprint.
  - The change in this post versus what we said at the sprint is that
    I am using one type per variable instead of one type per variable
    per statement; I am also explicitly using the results of an
    earlier liveness analysis to construct the constraints, whereas in
    the sprint we incorporated the liveness into the region inference
    itself (by reasoning about which values were live across each
    individual statement and thus creating many more inequalities).
  
There are some things I've left out of this post. Hopefully I will get
to them in future posts, but they all seem like relatively minor
twists on this base model.

- I'd like to talk about how to incorporate lifetime parameters on fns
  (I think we can do that in a fairly simple way by modeling them as
  regions in an expanded control-flow graph,
  [as illustrated by this example in my prototype][gd]).
- There are various options for modeling the
  ["deferred borrows" needed to accept `vec.push(vec.len())`][mutself].
- We might consider a finer-grained notion of liveness that operates
  not on variables but rather on the "fragments" (paths) that we use
  when doing move-checking. This would help to make `let (p, q) =
  (&foo, &bar)` and `let pair = (&foo, &bar)` entirely equivalent (in
  the system as I described it, they are not, because whenever `pair`
  is live, both `foo` and `bar` would be borrowed, even if only
  `pair.0` is ever used).  But even if we do this there will still be
  cases where storing pointers into an aggregate (e.g., a struct) can
  lose precision versus using variables on the stack, so I'm not sure
  it's worth worrying about.
  
Comments? [Let's use this old internals thread.][internals]

[gd]: https://github.com/nikomatsakis/nll/blob/master/test/get-default.nll
[mutself]: https://internals.rust-lang.org/t/accepting-nested-method-calls-with-an-mut-self-receiver/4588
[RFC 396]: https://github.com/rust-lang/rfcs/pull/396
[smr]: https://github.com/Ericson2314/a-stateful-mir-for-rust
[internals]: https://internals.rust-lang.org/t/non-lexical-lifetimes-based-on-liveness/3428
[outlives]: http://smallcultfollowing.com/babysteps/blog/2016/05/09/non-lexical-lifetimes-adding-the-outlives-relation/
[vpr]: https://github.com/nikomatsakis/nll/blob/a6609ab17fd483f8d47ef919af3838bf214954e5/test/vec-push-ref.nll
