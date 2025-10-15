---
title: "More thoughts on claiming"
date: 2024-06-26T08:20:43-04:00
series:
- "Claim"
- "Ergonomic RC"
---

This is the first of what I think will be several follow-up posts to ["Claiming, auto and otherwise"][cao]. This post is focused on clarifying and tweaking the design I laid out previously in response to some of the feedback I've gotten. In future posts I want to lay out some of the alternative designs I've heard.

[cao]: {{< baseurl >}}/blog/2024/06/21/claim-auto-and-otherwise/

## TL;DR: People like it

If there's any one thing I can take away from what I've heard, is that people really like the idea of making working with reference counted or cheaply cloneable data more ergonomic than it is today. A lot of people have expressed a lot of excitement.

If you read only one additional thing from the post&mdash;well, don't do that, but if you *must*&mdash;read the [Conclusion](#conclusion). It attempts to restate what I was proposing to help make it clear.

## Clarifying the relationship of the traits

I got a few questions about the relationship of the Copy/Clone/Claim traits to one another. I think the best way to show it is with a venn diagram:

{{< embed "content/blog/2024-06-26-venn-diagram.svg" >}}

* The `Clone` trait is the most general, representing any way of duplicating the value. There are two important subtraits:
    * `Copy` represents values that can be cloned via memcpy and which lack destructors ("plain old data").
    * `Claim` represents values whose clones are cheap, infallible, and transparent; on the basis of these properties, claims are inserted automatically by the compiler.

`Copy` and `Claim` overlap but do not have a strict hierarchical relationship. Some `Claim` types (like `Rc` and `Arc`) are not "plain old data". And while all `Copy` operations are infallible, some of them fail to meet claim's other conditions:

* Copying a large type like `[u8; 1024]` is not cheap.
* Copying a type with interior mutability like `Cell<u8>` is not transparent.

## On heuristics

One challenge with the `Claim` trait is that the choice to implement it involves some heuristics:

* What exactly is *cheap?* I tried to be specific by saying "O(1) and doesn't copy more than a few cache lines", but clearly it will be hard to draw a strict line.
* What exactly is *infallible?* It was pointed out to me that `Arc` will abort if the ref count overflows (which is one reason why the Rust-for-Linux project [rolled their own alternative](https://rust-for-linux.com/arc-in-the-linux-kernel)). And besides, any Rust code can abort on stack overflow. So clearly we need to have some reasonable compromise.
* What exactly is *transparent?* Again, I tried to specify it, but iterator types are an example of types that are *technically* transparent to copy but where it is nontheless very confusing to claim them.

An aversion to heuristics is the reason we have the current copy/clone split. We couldn't figure out where to draw the line ("how much data is too much?") so we decided to simply make it "memcpy or custom code". This was a reasonable starting point, but we've seen that it is imperfect, leading to uncomfortable compromises.

The thing about "cheap, infallible, and transparent" is that I think it represents **exactly** the criteria that we really want to represent when something can be automatically claimed. And it seems inherent that those criteria are a bit squishy.

One implication of this is that `Claim` should rarely if ever appear as a bound on a function. Writing `fn foo<T: Claim>(t: T)` doesn't really feel like it adds a lot of value to me, since, given the heuristical nature of claim, it's going to rule out some uses that may make sense. [eternaleye](https://github.com/eternaleye) proposed an [interesting twist](https://github.com/nikomatsakis/babysteps/issues/43) on the original proposal, suggesting we introducing stricter versions of `Claim` for, say, O(1) `Clone`, although I don't yet see what code would want to use that as a bound either.

## "Infallible" ought to be "does not unwind" (and we ought to abort if it does)

I originally laid out the conditions for claim as "cheap, infallible, and transparent", where "infallible" means "cannot panic or abort". But it was pointed out to me that `Arc` and `Rc` in the standard library will indeed abort if the ref-count exceeds `std::usize::MAX`! This obviously can't work, since reference counted values are the prime candidate to implement `Claim`.

Therefore, I think infallible ought to say that "Claim operations should never panic". This almost doesn't need to be said, since panics are **already** meant to represent impossible or extraordinarily unlikely conditions, but it seems worth reiterating since it is particularly important in this case.

In fact, I think we should go further and have the compiler insert an abort if an automatic `claim` operation does unwind.[^universal] My reasoning here is the same as I gave in my [post on unwinding][uw][^follow-up]: 

* Reasoning about unwinding is already very hard, it becomes nigh impossible if the sources of unwinding are hidden.
* It would make for more efficient codegen if the compiler doesn't have to account for unwinding, which would make code using `claim()` (automatically or explicitly) mildly more efficient than code using `clone()`.

[RFC #3288]: https://github.com/rust-lang/rfcs/pull/3288

[uw]: {{< baseurl >}}/blog/2024/05/02/unwind-considered-harmful/

[^follow-up]: Another blog post for which I ought to post a follow-up!

[^universal]: In fact, I wonder if we could extend [RFC #3288][] to apply this retroactively to all operations invoked automatically by the compiler, like `Deref`, `DerefMut`, and `Drop`. Obviously this is technically backwards incompatible, but the benefits here could well be worth it in my view, and the code impacted seems very small (who intentionally panics in `Deref`?). 

I was originally thinking of the Rust For Linux project when I wrote the wording on infallible, but their requirements around aborting are really orthogonal and much broader than `Claim` itself. They already don't use the Rust standard library, or most dependencies, because they want to limit themselves to code that treats abort as an absolute last resort. Rather than abort on overflow, their version of reference counting opts simply to leak, for example, and their memory allocators return a `Result` to account for OOM conditions. I think the `Claim` trait will work just fine for them whatever we say on this point, as they'll already have to screen for code that meets their more stringent criteria.

## Clarifying `claim` codegen

In my post, I noted almost in passing that I would expect the compiler to still use memcpy at monomorphization time when it knew that the type being claimed implements `Copy`. One interesting bit of feedback I got was anecdotal evidence that this will indeed be cricital for performance.

To model the semantics I want for `claim` we would need specialization[^vaporware]. I'm going to use a variant of specialized that [lcnr](https://github.com/lcnr) first proposed to me; the idea is to have an `if impl` expression that, at monomorphization time, either takes the `true` path (if the type implements `Foo` via [always applicable](https://smallcultfollowing.com/babysteps/blog/2018/02/09/maximally-minimal-specialization-always-applicable-impls/) impls) or the `false` path (otherwise). This is a cleaner formulation for specialization when the main thing you want to do is provide more optimized or alternative implementations.

[^vaporware]: Specialization has definitely acquired that "vaporware" reputation and for good reason&mdash;but I still think we can add it! That said, my thinking on the topic has evolved quite a bit. It'd be worth another post sometime. /me adds it to the queue.

Using that, we could write a function `use_claim_value` that defines the code the compiler should insert:

```rust
fn use_claim_value<T: Claim>(t: &T) -> T {
    std::panic::catch_unwind(|| {
        if impl T: Copy {
            // Copy T if we can
            *t
        } else {
            // Otherwise clone
            t.clone()
        }
    }).unwrap_or_else(|| {
        // Do not allow unwinding
        abort();
    })
}
```

This has three important properties:

* No unwinding, for easier reasoning and better codegen.
* Copies if it can.
* Always calls `clone` otherwise.

## Conclusion

### What I really proposed

Effectively I proposed to change what it means to "use something by value" in Rust. This has always been a kind of awkward concept in Rust without a proper name, but I'm talking about what happens to the value `x` in any of these scenarios:

```rust
let x: SomeType;

// Scenario A: passing as an argument
fn consume(x: SomeType) {}
consume(x);

// Scenario B: assigning to a new place
let y = x;

// Scenario C: captured by a "move" closure
let c = move || x.operation();

// Scenario D: used in a non-move closure
// in a way that requires ownership
let d = || consume(x);
```

No matter which way you do it, the rules today are the same:

* If `SomeType: Copy`, then `x` is *copied*, and you can go on using it later.
* Else, `x` is *moved*, and you cannot.

I am proposing that, modulo the staging required for backwards compatibility, we change those rules to the following:

* If `SomeType: Claim`, then `x` is *claimed*, and you can go on using it later.
* Else, `x` is *moved*, and you cannot.

To a first approximation, "claiming" something means calling `x.claim()` (which is the same as `x.clone()`). But in reality we can be more efficient, and the definition I would use is as follows:

* If the compiler sees `x` is "live" (may be used again later), it transforms the use of `x` to `use_claimed_value(&x)` ([as defined earlier](#clarifying-claim-codegen)).
* If `x` is dead, then it is just moved.

### Why I proposed it

There's a reason I proposed this change in the way that I did. I really value the way Rust handles "by value consumption" in a consistent way across all those contexts. It fits with Rust's ethos of orthogonal, consistent rules that fit together to make a harmonious, usable whole.

My goal is to retain Rust's consistency while also improving the gaps in the current rule, which neither highlights the things I want to pay attention to (large copies), hides the things I (almost always) don't (reference count increments), nor covers all the patterns I sometimes want (e.g., being able to `get` and `set` a `Cell<Range<u32>>`, which doesn't work today because making `Range<u32>: Copy` would introduce footguns). My *hope* is that we can do this in a way that it benefits most every Rust program, whether it be low-level or high-level in nature.


