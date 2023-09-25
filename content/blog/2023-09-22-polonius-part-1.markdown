---
title: "Polonius revisited, part 1"
date: 2023-09-22T16:32:40-04:00
---

[lqd] has been doing awesome work driving progress on [polonius](https://github.com/rust-lang/polonius/). He's authoring an [update for Inside Rust][update], but the TL;DR is that, with his latest PR, we've reimplemented the traditional Rust borrow checker in a more polonius-like style. We are working to iron out the last few performance hiccups and thinking about replacing the existing borrow checker with this new re-implementation, which is effectively a no-op from a user's perspective (including from a performance perspective). This blog post walks through that work, describing how the new analysis works at a high-level. I plan to write some follow-up posts diving into how we can extend this analysis to be more precise (while hopefully remaining efficient).

[update]: https://github.com/rust-lang/blog.rust-lang.org/pull/1147
[lqd]: https://github.com/lqd/

## What is Polonius?

Polonius is one of those long-running projects that are finally starting to move again. From an end user's perspective, the key goal is that we want to accept functions like so-called [Problem Case #3][pc3], which was originally a goal of NLL but eventually cut from the deliverable. From my perspective, though, I'm most excited about Polonius as a stepping stone towards an analysis that can support internal references and self borrows.

[rbr]: https://www.youtube.com/watch?v=_agDeiWek8w
[slides here]: https://nikomatsakis.github.io/rust-belt-rust-2019/
[pc3]: https://rust-lang.github.io/rfcs/2094-nll.html#problem-case-3-conditional-control-flow-across-functions

Polonius began its life as an [alternative formulation of the borrow checker rules](http://smallcultfollowing.com/babysteps/blog/2018/04/27/an-alias-based-formulation-of-the-borrow-checker/) defined in Datalog. The key idea is to switch the way we do the analysis. Whereas NLL thinks of `'r` as a **lifetime** consisting of a set of program points, in polonius, we call `'r` an **origin** containing a set of **loans**. In other words, rather than tracking the parts of the program where a reference will be used, we track the places that the reference may have come from. For deeper coverage of Polonius, I recommend [my talk at Rust Belt Rust from (egads) 2019][rbr] ([slides here][]).

## Running example

In order to explain the analyses, I'm going to use this running example. One thing you'll note is that the lifetimes/origins in the example are written as numbers, like `'0` and `'1`. This is because, when we start the borrow check, we haven't computed lifetimes/origins yet -- that is the job of the borrow check! So, we first go and create synthetic *inference variables* (just like an algebraic variable) to use as placeholders throughout the computation. Once we're all done, we'll have actual values we could plug in for them -- in the case of polonius, those values are sets of loans (each loan is a `&` expression, more or less, that appears somewhere in the program).

Here is our example. It contains two loans, L0 and L1, of `x` and `y` respectively. There are also four assignments:

```rust
let mut x = 22;
let mut y = 44;
let mut p: &'0 u32 = &x; // Loan L0, borrowing `x`
y += 1;                  // (A) Mutate `y` -- is this ok?
let mut q: &'1 u32 = &y; // Loan L1, borrowing `y`
if something() {
    p = q;               // `p` now points at `y`
    x += 1;              // (B) Mutate `x` -- is this ok?
} else {
    y += 1;              // (C) Mutate `y` -- is this ok?
}
y += 1;                  // (D) Mutate `y` -- is this ok?
read_value(p);           // use `p` again here
```

[Today in Rust](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=8bfd49b522670b37a4e5b0d00bcc6209), we get two errors (C and D). If you were to run this example with [MiniRust](https://github.com/RalfJung/minirust), though, you would find that only D can actually cause Undefined Behavior. At point C, we mutate `y`, but the only variable that references `y` is `q`, and it will never be used again. The borrow checker today reports an error because its overly conservative. Polonius, on the other hand, gets that case correct.

| Location | Existing borrow checker | Polonius | MiniRust |
| -------- | --- | --- | --- |
| A | :heavy_check_mark: | :heavy_check_mark: | OK |
| B | :heavy_check_mark: | :heavy_check_mark: | OK |
| C | :x: | :heavy_check_mark: | OK |
| D | :x: | :x: | Can cause UB, if `true` branch is taken |

## Reformulating the existing borrow check à la polonius

This blog post is going describe the existing borrow checker, but reformulated in a polonius-like style. This will make it easier to see how polonius is different in the next post. The idea of doing this reformulation came about when implementing the borrow checker in [a-mir-formality](https://github.com/rust-lang/a-mir-formality)[^current]. At first, we weren't sure if it was equivalent, but [lqd] verified it experimentally by testing it against the rustc test suite, where it matches the behavior 100% ([lqd] is also going to test against crater). 

[^current]: You won't find this code in the current version of a-mir-formality; it's since been rewritten a few times and the current version hasn't caught up yet.

The borrow check analysis is a combination of three things, which we will cover in turn:

```mermaid
flowchart TD
  ConstructMIR --> LiveVariable
  ConstructMIR --> OutlivesGraph
  LiveVariable --> LiveLoanDataflow
  OutlivesGraph --> LiveLoanDataflow
  ConstructMIR["Construct the MIR"]
  LiveVariable["Compute the live variables"]
  OutlivesGraph["Compute the outlives graph"]
  LiveLoanDataflow["Compute the active loans at a given point"]
```

## Construct the MIR

The borrow checker these days operates on [MIR][][^why]. MIR is basically a very simplified version of Rust where each statement is broken down into rudimentary statements. Our program is already so simple that the MIR basically looks the same as the original program, except for the fact that it's structured into a [control-flow graph][cfg]. The MIR would look roughly like this (simplified):

[^why]: The origin of the MIR is actually an interesting story. As documented in [RFC #1211], 

```mermaid
flowchart TD
  Intro --> BB1
  Intro["let mut x: i32\nlet mut y: i32\nlet mut p: &'0 i32\nlet mut q: &'1 i32"]
  BB1["p = &x;\ny = y + 1;\nq = &y;\nif something goto BB2 else BB3"]
  BB1 --> BB2
  BB1 --> BB3
  BB2["p = q;\nx = x + 1;\n"]
  BB3["y = y + 1;"]
  BB2 --> BB4;
  BB3 --> BB4;
  BB4["y = y + 1;\nread_value(p);\n"]

  classDef default text-align:left,fill-opacity:0;
```

Note that MIR begins with the types for all the variables; control-flow constructs like `if` get transformed into graph nodes called *basic blocks*, where each basic block contains only simple, straightline statements.

[MIR]: https://rustc-dev-guide.rust-lang.org/mir/index.html
[cfg]: https://en.wikipedia.org/wiki/Control-flow_graph
[RFC #1211]: https://rust-lang.github.io/rfcs/1211-mir.html

## Compute the live origins

The first step is to compute the set of *live origins* at each program point. This is precisely the same as [it was described in the NLL RFC](https://rust-lang.github.io/rfcs/2094-nll.html#liveness). This is very similar to the classic liveness computation that is taught in a typical compiler course, but with one key difference. We are not computing live *variables* but rather live *origins* -- the idea is roughly that the *live origins* are equal to the origins that appear in the types of the live *variables*:

```
LiveOrigins(P) = { O | O appears in the type of some variable V live at P }
```

The actual computation is slightly more subtle: when variables go out of scope, we take into account the rules from [RFC #1327][] to figure out precisely which of their origins may be accessed by the `Drop` impl. But I'm going to skip over that in this post.

[the NLL RFC]: https://rust-lang.github.io/rfcs/2094-nll.html
[RFC #1327]: https://rust-lang.github.io/rfcs/1327-dropck-param-eyepatch.html

Going back to our example, I've added comments which origins would be live at various points of interest:

```rust
let mut x = 22;
let mut y = 44;
let mut p: &'0 u32 = &x;
y += 1;
let mut q: &'1 u32 = &y;
// Here both `p` and `q` may be used later,
// and so the origins in their types (`'0` and `'1`)
// are live.
if something() {
    // Here, only the variable `q` is live.
    // `p` is dead because its current value is about
    // to be overwritten. As a result, the only live
    // origin is `'1`, since it appears in `q`'s type.
    p = q;
    x += 1;
} else {
    y += 1;
}
// Here, only the variable `p` is live
// (`q` is never used again),
// and so only the origin `'0` is live.
y += 1;
read_value(p);
```

## Compute the subset graph

The next step in borrow checking is to run a type check across the MIR. MIR is effectively a very simplified form of Rust where statements are heavily desugared and there is a lot less type inference. There is, however, a lot of *lifetime* inference -- basically when NLL starts **every** lifetime is an inference variable. 

For example, consider the `p = q` assignment in our running example:

```rust
...
let mut p: &'0 u32 = &x;
y += 1;
let mut q: &'1 u32 = &y;
if something() {
    p = q; // <-- this assignment
    ...
} else {
    ...
}
...
```

To type check this, we take the type of `q` (`&'1 u32`) and require that it is a subtype of the type of `p` (`&'0 u32`):

```
&'1 u32 <: &'0 u32
```

As described in [the NLL RFC](https://rust-lang.github.io/rfcs/2094-nll.html?highlight=nll#subtyping), this subtyping relation holds if `'1: '0`. In NLL, we called this an *outlives relation*. But in polonius, because `'0` and `'1` are origins representing *sets of loans*, we call it a **subset relation**. In other words, `'1: '0` could be written `'1 ⊆ '0`, and it means that whatever loans `'1` may be referencing, `'0` may reference too. Whatever final values we wind up with for `'0` and `'1` will have to reflect this constraint.

We can view these subset relations as a graph, where `'1: '0` means there is an edge `'1 --⊆--> '0`. In the borrow checker today, this graph is **flow insensitive**, meaning that there is one graph for the entire function. As a result, we are going to get a graph like this:

```mermaid
flowchart LR
  L0 --"⊆"--> Tick0
  L1 --"⊆"--> Tick1
  Tick1 --"⊆"--> Tick0
  
  L0["{L0}"]
  L1["{L1}"]
  Tick0["'0"]
  Tick1["'1"]

  classDef default text-align:left,fill:#ffffff;
```

You can see that `'0`, the origin that appears in `p`, can be reached from both loan `L0` and loan `L1`. That means that it could store a reference to *either* `x` or `y`, in short. In contrast, `'1` (`q`) can only be reached from L1, and hence can only store a reference to `y`.

## Active loans

There is one last piece to complete the borrow checker, which is computing the **active loans**. Active loans determine the errors that get reported. The idea is that, if there is an active loan of a place `a.b.c`, then accessing `a.b.c` may be an error, depending on the kind of loan/access.

Active loans build on the liveness analysis as well as the subset graph. The basic idea is that a loan is active at a point P if there is a path from the borrow that created the loan to P where, for each point along the path...

* there is some live variable that may reference the loan
    * i.e., there is a live origin `O` at `P` where `L ∈ O`. `L ∈ O` means that there is a path in the subset graph from the loan `L` to the origin `O`.
* the place expression that was borrowed (here, `x`) is not reassigned
    * this isn't relevant to the current example, but the idea is that you can borrow the referent of a pointer, e.g., `&mut *tmp`. If you then later change `tmp` to point somewhere else, then the old loan of `*tmp` is no longer relevant, because it's pointing to different data than the current value of `*tmp`.
 
### Implementing using dataflow

In the compiler, we implement the above as a [**dataflow analysis**](https://en.wikipedia.org/wiki/Data-flow_analysis). The value at any given point is the set of active loans. We *gen* a loan (add it to the value) when it is issued, and we *kill* a loan at a point P if either (1) the loan is not a member of the origins of any live variables; (2) the path borrowed by the loan is overwritten.


#### Active loans on entry to the function

Let's walk through our running example. To start, look at the first basic block:

```mermaid
flowchart TD
  Start["..."]
  BB1["<b><i>// Active loans: {}</i></b>
       p = &x; <b><i>// Gen: L0</i></b> -- loan issued
       <b><i>// Active loans: {L0}</i></b>
       y = y + 1;
       q = &y; <b><i>// Gen L1</i></b> -- loan issued
       <b><i>// Active loans {L0, L1}</i></b>
       if something goto BB2 else BB3
  "]
  BB2["..."]
  BB3["..."]
  BB4["..."]

  Start --> BB1
  BB1 --> BB2
  BB1 --> BB3
  BB2 --> BB4
  BB3 --> BB4

  classDef default text-align:left,fill:#ffffff;
  classDef highlight text-align:left,fill:yellow;
  class BB1 highlight
```

This block is the start of the function, so the set of action loans starts out as empty. But then we encounter two `&x` statements, and each of them is the **gen** site for a loan (`L0` and `L1` respectively). By the end of the block, the active loan set is `{L0, L1}`.

#### Active loans on the "true" branch

The next interesting point is the "true" branch of the if:

```mermaid
flowchart TD
  Start["
    ...
    let mut q: &'1 i32;
    ...
  "]
  BB1["..."]
  BB2["
      <b><i>// Kill L0 -- not part of any live origin</i></b>
      <b><i>// Active loans {L1}</i></b>
      p = q;
      x = x + 1;
  "]
  BB3["..."]
  BB4["..."]
 
  Start --> BB1
  BB1 --> BB2
  BB1 --> BB3
  BB2 --> BB4
  BB3 --> BB4
 
  classDef default text-align:left,fill:#ffffff;
  classDef highlight text-align:left,fill:yellow;
  class BB2 highlight
```

The interesting thing here is that, on entering the block, there is a **kill** of L0. This is because the only live reference on entry to the block is `q`, as `p` is about to be overwritten. As the type of `q`  is `&'1 i32`, this means that the live origins on entry to the block are `{'1}`. Looking at the subset graph we saw earlier...

```mermaid
flowchart LR
  L0 --"⊆"--> Tick0
  L1 --"⊆"--> Tick1
  Tick1 --"⊆"--> Tick0
  
  L0["{L0}"]
  L1["{L1}"]
  Tick0["'0"]
  Tick1["'1"]

  class L1 trace
  class Tick1 trace

  classDef default text-align:left,fill:#ffffff;
  classDef trace text-align:left,fill:yellow;
```

...we can trace the transitive predecessors of `'1` to see that it contains only `{L1}` (I've highlighted those predecessors in yellow in the graph). This means that there is no live variable whose origins contains `L0`, so we add a kill for `L0`.

#### No error on `true` branch

Because the only active loan is L1, and L1 borrowed `y`, the `x = x + 1` statement is accepted. This is a really interesting result! It illustrates how the idea of *active loans* restores some flow sensitivity to the borrow check. 

Why is it so interesting? Well, consider this. At this point, the variable `p` is live. The variable `p` contains the origin `'0`, and if we look at the subset graph, `'0` contains both L0 and L1. So, based purely on the subset graph, we would expect modifying `x` to be an error, since it is borrowed by L0. And yet it's not!

This is because the *active loan* analysis noticed that, although in theory `x` may reference `L0`, it definitely doesn't at this point.

#### Active loans on the `false` branch

In contrast, if we look at the "false" branch of the if:

```mermaid
flowchart TD
  Start["
    ...
    let mut p: &'0 i32;
    ...
  "]
  BB1["..."]
  BB2["..."]
  BB3["
      <b><i>// Active loans {L0}, {L1}</i></b>
      y = y + 1;
  "]
  BB4["..."]
 
  Start --> BB1
  BB1 --> BB2
  BB1 --> BB3
  BB2 --> BB4
  BB3 --> BB4
 
  classDef default text-align:left,fill:#ffffff;
  classDef highlight text-align:left,fill:yellow;
  class BB3 highlight
```


#### False error on the `false` branch

This path is also interesting: there is only one live variable, `p`. If you trace the code by hand, you can see that `p` could only refer to L0 (`x`) here. And yet the analysis concludes that we have two active loans: L0 and L1. This is because it is looking at the subset graph to determine what `p` may reference, and that graph is *flow insensitive*. So, since `p` may reference L1 at *some* point in the program, and we haven't yet seen references to L1 go completely dead, we assume that `p` may reference L1 here. This leads to a false error being reported when the user does `y = y + 1`.

#### Active loans on the final block

Now let's look at the final block:

```mermaid
flowchart TD
  Start["
    ...
    let mut p: &'0 i32;
    ...
  "]
  BB1["..."]
  BB2["..."]
  BB3["..."]
  BB4["
        <b><i>// Active loans {L0}, {L1}</i></b>
        y = y + 1;
        read_value(p);
  "]
 
  Start --> BB1
  BB1 --> BB2
  BB1 --> BB3
  BB2 --> BB4
  BB3 --> BB4
 
  classDef default text-align:left,fill:#ffffff;
  classDef highlight text-align:left,fill:yellow;
  class BB4 highlight
```

At this point, there is one live variable (`p`) and hence one live origin (`'0`); the subset graph tells us that `p` may reference both `L0` and `L1`, so the set of active loans is `{L0, L1}`. This is correct: depending on which path we took, `p` may refer to either `L0` or `L1`, and hence we flag a (correct) error when the user attempts to modify `y`.

## Kills for reassignment

Our running example showed one reason that loans get killed when there are no more live references to them. This most commonly happens when you create a short-lived reference and then stop using it. But there is another way to get a kill, which happens from reassignment. Consider this example:

```rust
struct List {
    data: u32,
    next: Option<Box<List>>
}

fn print_all(mut p: &mut List) {
    loop {
        println!("{}", p.data);
        if let Some(n) = &mut p.next {
            p = n;
        } else {
            break;
        }
    }
}
```

I'm not going to walk through how this is borrow checked in detail here, but let me just point out what makes it interesting. In this loop, the code first borrows from `p` and then assigns that result to `p`. This means that, if you just look at the *subset graph*, on the next iteration around the loop, there would be an active loan of `p`. However, [this code compiles](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=076383dd805aa00844ac679b6fc8c2cb) -- how does that work? The answer is that when we do `p = n`, we are mutating `p`, which means that, when we borrow from `p` on the next iteration, we are actually borrowing from a *previous node* than we borrowed from in the first iteration. So everything is fine. The reason the borrow checker is able to conclude this is that it kills the loan of `p.next` when it sees that `p` is assigned to. [This is discussed in the NLL RFC in more detail.](https://rust-lang.github.io/rfcs/2094-nll.htmlborrow-checker-phase-1-computing-loans-in-scope)

## Conclusion

That brings us to the end of part 1! In this post, we covered how you can describe the existing borrow check in a more polonius-like style. We also uncovered an interesting quirk in how the borrow checker is formulated. It uses a *location insensitive* alias analysis (the subset graph) but completely that with a dataflow propagation to track active loans. Together, this makes it more expressive. This wasn't, however, the original plan with NLL. Originally, the subset graph was meant to be flow sensitive. Extending the subset graph to be flow sensitive is basically the heart of polonius. I've got some thoughts on how we might do that and I'll be getting to that in later posts. I do want to say in passing though that doing all of this framing is also making me wonder -- is it really necessary to combine a type check *and* the dataflow check? Can we frame the borrow checker (probably the more precise variants we'll be getting to in future posts) in a more unified way? Not sure yet!
