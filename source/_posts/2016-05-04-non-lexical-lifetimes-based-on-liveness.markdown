---
layout: post
title: "Non-lexical lifetimes based on liveness"
date: 2016-05-04 05:19:04 -0400
comments: false
categories: [Rust]
---
In my [previous post][nllintro] I outlined several cases that we would like
to improve with Rust's current borrow checker. This post discusses one
possible scheme for solving those. The heart of the post is two key ideas:

1. Define a **lifetime** as a **set of points in the control-flow
   graph**, where a **point** here refers to some particular statement
   in the control-flow graph (i.e., not a [basic block][cfg], but some
   statement within a basic block).
2. Use **liveness** as the basis for deciding where a variable's type
   must be valid.

The rest of this post expounds on these two ideas and shows how they
affect the various examples from the previous post.

<!-- more -->

### Problem case #1: references assigned into a variable

To see better what these two ideas mean -- and why we need both of
them -- let's look at the initial example from [my previous post][nllintro].
Here we are storing a reference to `&mut data[..]` into the variable
`slice`:

```rust
fn bar() {
    let mut data = vec!['a', 'b', 'c'];
    let slice = &mut data[..]; // <-+ lifetime today
    capitalize(slice);         //   |
    data.push('d'); // ERROR!  //   |
    data.push('e'); // ERROR!  //   |
    data.push('f'); // ERROR!  //   |
} // <------------------------------+
```

As shown, the lifetime of this reference today winds up being the
subset of the block that starts at the `let` and stretches until the
ending `}`. This results in compilation errors when we attempt to push
to `data`.  The reason is that a borrow like `&mut data[..]`
effectively "locks" the `data[..]` for the lifetime of the borrow,
meaning that `data` becomes off limits and can't be used (this
"locking" is just a metaphor for the type system rules; there is of
course nothing happening at runtime).

What we would like is to observe that `slice` is *dead* -- which is
[compiler-speak][lv] for "it won't ever be used again" -- after the call to
`capitalize`. Therefore, if we had a more flexible lifetime system, we
might compute the lifetime of the `slice` reference to something that
ends right after the call to `capitalize`, like so:

```rust
fn bar() {
    let mut data = vec!['a', 'b', 'c'];
    let slice = &mut data[..]; // <-+ lifetime under this proposal
    capitalize(slice);         //   |
    // <----------------------------+
    data.push('d'); // OK
    data.push('e'); // OK
    data.push('f'); // OK
}
```

If we had this shorter lifetime, then the calls to `data.push` would
be legal, since the "lock" is effectively released early.

At first it might seem like all we have to do to achieve this result
is to adjust the definition of what a lifetime can be to make it more
flexible. In particular, today, once a lifetime must extend beyond the
boundaries of a single statement (e.g., beyond the `let` statement
here), it must extend all the way till the end of the enclosing block.
So, by adopting a definition of lifetimes that is just "a set of
points in the control-flow graph", we lift this constraint, and we can
now express the idea of a lifetime that starts at the `&mut data[..]`
borrow and ends after the call to `capitalize`, which we couldn't even
express before.

But it turns out that is not quite enough. There is another rule in
the type system today that causes us a problem. This rule states that
the type of a variable must outlive the variable's scope. In other
words, if a variable contains a reference, that reference must be
valid for the entire scope of the variable. So, in our example above,
the reference created by the `&mut data[..]` borrow winds up being
stored in the variable `slice`. This means that the lifetime of that
reference must include the scope of `slice` -- which stretches from
the `let` until the closing `}`. In other words, even if we adopt more
flexible lifetimes, if we change nothing else, we wind up with the
same lifetime as before.

You might think we could just remove the rule altogether, and say that
the lifetime of a reference must include all the points where the
lifetime is used, with no special treatment for references stored into
variables. In this particular example we've been looking at, that
would do the right thing: the lifetime of `slice` would only have to
outlive the call to `capitalize`. But it starts to go wrong if the
control-flow gets more complicated:

```rust
fn baz() {
    let mut data = vec!['a', 'b', 'c'];
    let slice = &mut data[..]; // <-+ lifetime if we ignored
    loop {                     //   | variables altogether
        capitalize(slice);     //   |
        // <------------------------+
        data.push('d'); // Should be error, but would not be.
    }
    data.push('e'); // OK
    data.push('f'); // OK
}
```

Here again the reference `slice` is *still* only be required to live
until after the call to `capitalize`, since that is the only place it
is used. However, in this variation, that is not the correct behavior:
the reference `slice` is in fact still [live][lv] after the call to
capitalize, since it will be used again in the next iteration of the
loop. **The problem here is that we are entering the lifetime (after
the call to `capitalize`) and then re-entering it (on the loop
backedge) but without reinitializing `slice`.**

One way to address this problem would be to modify the definition of a
lifetime. The definition I gave earlier was very flexible and allowed
any set of points in the control-flow to be included. Perhaps we want
some special rules around backedges? This is the approach that
[RFC 396][] took, for example. I initially explored this approach but
found that it caused problems with more advanced cases, such as a
variation on problem case 3 we will examine in a later post.

Instead, I have opted to weaken -- but not entirely remove -- the
original rule.  The original rule was something like this (expressed
as an [inference rule][]):

    scope(x) = 's
    T: 's
    ------------------
    let x: T OK

In other words, it's ok to declare a variable `x` with type `T`, as
long as `T` outlive the scope `'s` of that variable. My new version is more like
this:

    live-range(x) = 's
    T: 's
    ------------------
    let x: T OK

Here I have substituted *live-range* for *scope*. By [live-range][lv]
I mean "the set of points in the CFG where `x` may be later used",
effectively. If we apply this to our two variations, we will see that,
in the first example, the variable `slice` is *dead* after the call to
capitalize: it will never be used again. But in the second variation,
the one with a loop, `slice` is *live*, because it may be used in the
next iteration. This accounts for the different behavior:

```rust
// Variation #1: `slice` is dead after call to capitalize,
// so the lifetime ends
fn bar() {
    let mut data = vec!['a', 'b', 'c'];
    let slice = &mut data[..]; // <-+ lifetime under this proposal
    capitalize(slice);         //   |
    // <----------------------------+
    data.push('d'); // OK
    data.push('e'); // OK
    data.push('f'); // OK
}

// Variation #2: `slice` is live after call to capitalize,
// so the lifetime encloses the entire loop.
fn baz() {
    let mut data = vec!['a', 'b', 'c'];
    let slice = &mut data[..]; // <---------------------------+
    loop {                                               //   |
        capitalize(slice);                               //   |
        data.push('d'); // ERROR!                        //   |
    }                                                    //   |
    // <------------------------------------------------------+
    
    // But note that `slice` is dead here, so the lifetime ends:
    data.push('e'); // OK
    data.push('f'); // OK
}
```

### Refining the proposal using fragments

One problem with the analysis as I presented it thus far is that it is
based on liveness of individual variables. This implies that we lose
precision when references are moved into structs or tuples. So, for
example, while this bit of code *will* type-check:

```rust
let mut data1 = vec![];
let mut data2 = vec![];
let x = &mut data1[..]; // <--+ data1 is "locked" here
let y = &mut data2[..]; // <----+ data2 is "locked" here
use(x);                 //    | |
// <--------------------------+ |
data1.push(1);          //      |
use(y);                 //      |
// <----------------------------+
data2.push(1);
```

It would cause errors if we move those two references into a tuple:

```rust
let mut data1 = vec![];
let mut data2 = vec![];
let tuple = (&mut data1[..], &mut data2[..]); // <--+ data1 and data2
use(tuple.0);                                 //    | are locked here
data1.push(1);                                //    |
use(tuple.1);                                 //    |
// <------------------------------------------------+
data2.push(1);
```

This is because the variable `tuple` is live until after the last
field access. *However,* the [dynamic drop][RFC 320] analysis is
already computing a set of *fragments*, which are basically minimal
paths that it needs to retain full resolution around which subparts of
a struct or tuple have been moved. We could probably use similar logic
to determine that we ought to compute the liveness of `tuple.0` and
`tuple.1` independently, which would make this example type-check.
(If we did so, then any use of `tuple` would be considered a "gen" of
both `tuple.0` and `tuple.1`, and any write to `tuple` would be
considered a "kill" of both.) This would probably subsume and be
compatible with the fragment logic used for [dynamic drop][RFC 320], so it
could be a net simplification.

### Destructors

One further wrinkle that I did not discuss is that any struct with a
destructor encounters special rules. This is because the destructor
may access the references in the struct. These rules were specified in
[RFC 1238][dropck] but are colloquially called
["dropck"][dropck]. They basically state that when we create some
variable `x` whose type `T` has a destructor, then `T` must outlive
the *parent* scope of `x`. That is, the references in `x` don't have
to just be valid for the scope of `x`, they have to be valid for
*longer* than the scope of `x`.

In some sense, the dropck rules remains unchanged by all I've
discussed here. But in another sense dropck may stop being a special
case. The reason is that, in [MIR][], all drops are made explicit in
the [control-flow graph][CFG], and hence if a variable `x` has a
destructor, that should show us as "just another use" of `x`, and thus
cause the lifetime of any references within to be naturally extended
to cover that destructor. I admit I haven't had time to dig into a lot
of examples here: destructors are historically a very subtle case.

### Implementation ramifications

Those of you familiar with the compiler will realize that there is a
bit of a chicken-and-egg problem with what I have presented
here. Today, the compiler computes the lifetimes of all references in
the `typeck` pass, which is basically the main type-checking pass that
computes the types of all expressions. We then use the output of this
pass to construct MIR. But in this proposal I am defining lifetimes as
a set of points in the MIR control-flow-graph. What gives?

To make this work, we have to change how the compiler works
internally.  The rough idea is that the `typeck` pass will no longer
concern itself with regions: it will erase all regions, just as trans
does. This has a number of ancillary benefits, though it also carries
a few complications we have to resolve (maybe a good topic for another
blog post!). We'll then build MIR from this, and hence the initially
constructed MIR will also have no lifetime information (just erased
lifetimes).

Then, looking at each function in the program in turn, we'll do a
safety analysis. We'll start by computing lifetimes -- at this point,
we have the MIR CFG in hand, so we can easily base them on the
CFG. We'll then run the borrowck.  When we are done, we can just
forget about the lifetimes entirely, since all later passes are just
doing optimization and code generation, and they don't care about
lifetimes.

Another interesting question is how to represent lifetimes in the
compiler. The most obvious representation is just to use a bit-set,
but since these lifetimes would require one bit for every statement
within a function, they could grow quite big. There are a number of
ways we could optimize the representation: for example, we could track
the mutual dominator, even promoting it "upwards" to the innermost
enclosing loop, and only store bits for that subportion of the
graph. This would require fewer bits but it'd be a lot more
accounting. I'm sure there are other far more clever options as well.
The first step I think would be to gather some statistics about the
size of functions, the number of inference variables per fn, and so
forth.

In any case, a key observation is that, since we only need to store
lifetimes for one function at a time, and only until the end of
borrowck, the precise size is not nearly as important as it would be
today.

### Conclusion

Here I presented the key ideas of my current thoughts around
non-lexical lifetimes: using flexible lifetimes coupled with
liveness. I motivated this by examining problem case \#1 from
[my introduction][nllintro]. I also covered some of the implementation
complications. In future posts, I plan to examine problem cases \#2
and \#3 -- and in particular to describe how to extend the system to
cover named lifetime parameters, which I've completely ignored
here. (Spoiler alert: problem cases \#2 and \#3 are also no longer
problems under this system.)

I also do want to emphasize that this plan is a
"work-in-progress". Part of my hope in posting it is that people will
point out flaws or opportunities for improvement. So I wouldn't be
surprised if the final system we wind up with winds up looking quite
different.

(As is my wont lately, I am disabling comments on this post. If you'd
like to discuss the ideas in here, please do so in
[this internals thread][thread] instead.)

[lv]: https://en.wikipedia.org/wiki/Live_variable_analysis
[nllintro]: http://smallcultfollowing.com/babysteps/blog/2016/04/27/non-lexical-lifetimes-introduction/
[mir]: http://blog.rust-lang.org/2016/04/19/MIR.html
[cfg]: https://en.wikipedia.org/wiki/Control_flow_graph
[RFC 396]: https://github.com/rust-lang/rfcs/pull/396
[RFC 320]: https://github.com/rust-lang/rfcs/blob/master/text/0320-nonzeroing-dynamic-drop.md
[inference rule]: https://en.wikipedia.org/wiki/Rule_of_inference
[dropck]: https://github.com/rust-lang/rfcs/blob/master/text/1238-nonparametric-dropck.md
[thread]: http://internals.rust-lang.org/t/non-lexical-lifetimes-based-on-liveness/3428
