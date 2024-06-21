---
title: "Claiming, auto and otherwise"
date: 2024-06-21T07:21:21-04:00
---

This blog post proposes adding a third trait, `Claim`, that would live alongside `Copy` and `Clone`. The goal of this trait is to improve Rust's existing split, where types are categorized as either `Copy` (for ["plain old data"][POD][^PDS] that is safe to `memcpy`) and `Clone` (for types that require executing custom code or which have destructors). This split has served Rust fairly well but also has some shortcomings that we've seen over time, including maintenance hazards, performance footguns, and (at times quite significant) ergonomic pain and user confusion.

[POD]: https://en.wikipedia.org/wiki/Passive_data_structure

[^PDS]: I love Wikipedia (of course), but using the name [*passive data structure*][POD] (which I have never heard before) instead of *plain old data* feels very... well, very *Wikipedia*. 

<!--more-->

## TL;DR

The proposal in this blog post has three phases:

1. **Adding a new `Claim` trait** that refines `Clone` to identify "cheap, infallible, and transparent" clones (see below for the definition, but it explicitly excludes allocation). Explicit calls to `x.claim()` are therefore known to be cheap and easily distinguished from calls to `x.clone()`, which may not be. This makes code easier to understand and addresses existing maintenance hazards ([obviously we can bikeshed the name](#How-did-you-come-up-with-the-name-Claim)).
2. **Modifying the borrow checker to insert calls to `claim()` when using a value from a place that will be used later.** So given e.g. a variable `y: Rc<Vec<u32>>`, an assignment like `x = y` would be transformed to `x = y.claim()` if `y` is used again later. This addresses the ergonomic pain and user confusion of reference-counted values in rust today, especially in connection with closures and async blocks.
3. **Finally, disconnect `Copy` from "moves" altogether, first with warnings (in the current edition) and then errors (in Rust 2027).** In short, `x = y` would move `y` unless `y: Claim`. Most `Copy` types would also be `Claim`, so this is largely backwards compatible, but it would let us rule out cases like `y: [u8; 1024]` and also extend `Copy` to types like `Cell<u32>` or iterators without the risk of [introducing subtle bugs](#Some-things-that-should-implement-Copy-do-not).

For some code, automatically calling `Claim` may be undesirable. For example, some data structure definitions track reference count increments closely. **I propose to address this case by creating a "allow-by-default" `automatic-claim` lint that crates or modules can opt-into so that all "claims" can be made explicit**. This is more-or-less the [profile pattern][], although I think it's notable here that the set of crates which would want "auto-claim" do not necessarily fall into neat categories, as I will discuss.

## Step 1: Introducing an explicit `Claim` trait

Quick, reading this code, can you tell me anything about it's performance characteristics?

```rust
tokio::spawn({
    // Clone `map` and store it into another variable
    // named `map`. This new variable shadows the original.
    // We can now write code that uses `map` and then go on
    // using the original afterwards.
    let map = map.clone();
    async move { /* code using map */ }
});

/* more code using map */
```

Short answer: no, you can't, not without knowing the type of `map`. The call to `map.clone()` may just be cloning a large map or incrementing a reference count, you can't tell.

### One-clone-fits-all creates a maintenance hazard

When you're in the midst of writing code, you tend to have a good idea whether a given value is "cheap to clone" or "expensive". But this property can change over the lifetime of the code. Maybe `map` starts out as an `Rc<HashMap<K, V>>` but is later refactored to `HashMap<K, V>`. A call to `map.clone()` will still compile but with very different performance characteristics.

In fact, `clone` can have an effect on the program's *semantics* as well. Imagine you have a variable `c: Rc<Cell<u32>>` and a call `c.clone()`. Currently this creates another handle to the same underlying cell. But if you refactor `c` to `Cell<u32>`, that call to `c.clone()` is now creating an independent cell. Argh. (We'll see this theme, of the importance of distinguishing interior mutability, come up again later.)

### Proposal: an explicit `Claim` trait distinguishing "cheap, infallible, transparent" clones

Now imagine we introduced a new trait `Claim`. This would be a subtrait of `Clone`that indicates that cloning is:

* **Cheap:** Claiming should complete in O(1) time and avoid copying more than a few cache lines (64-256 bytes on current arhictectures).
* **Infallible:** Claim should not encounter failures, even panics or aborts, under any circumstances. **Memory allocation is not allowed**, as it can abort if memory is exhausted. 
* **Transparent:** The old and new value should behave the same with respect to their public API.

The trait itself could be defined like so:[^final]

[^final]: In point of fact, I would prefer if we could define the `claim` method as "final", meaning that it cannot be overridden by implementations, so that we would have a guarantee that `x.claim()` and `x.clone()` are identical. You can do this somewhat awkwardly by defining `claim` in an extension trait, [like so](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=0eef90f677dc2013e73e6af80a2f7b35), but it'd be a bit embarassing to have that in the standard library.

```rust
trait Claim: Clone {
    fn claim(&self) -> Self {
        self.clone()
    }
}
```

Now when I see code calling `map.claim()`, even without knowing what the type of `map` is, I can be reasonably confident that this is a "cheap clone". Moreover, if my code is refactored so that `map` is no longer ref-counted, I will start to get compilation errors, letting me decide whether I want to `clone` here (potentially expensive) or find some other solution.

## Step 2: Claiming values in assignments

In Rust today, values are moved when accessed unless their type implement the `Copy` trait. This means (among other things) that given a ref-counted `map: Rc<HashMap<K, V>>`, using the value `map` will mean that I can't use `map` anymore. So e.g. if I do `some_operation(map)`, then gives my handle to `some_operation`, preventing me from using it again.

### Not all memcopies should be 'quiet'

The intention of this rule is that something as simple as `x = y` should correspond to a simple operation at runtime (a memcpy, specifically) rather than something extensible. That, I think, is laudable. And yet the current rule in practice has some issues:

* First, `x = y` can still result in surprising things happening at runtime. If `y: [u8; 1024]`, for example, then a few simple calls like `process1(y); process2(y);` can easily copy large amounts of data (you probably meant to pass that by reference).
* Second, seeing `x = y.clone()` (or even `x = y.claim()`) is visual clutter, distracting the reader from what's really going on. In most applications, incrementing ref counts is simply not that interesting that it needs to be called out so explicitly.

### Some things that should implement `Copy` do not

There's a more subtle problem: the current rule means adding `Copy` impls can create correctness hazards. For example, many iterator types like `std::ops::Range<u32>` and `std::vec::Iter<u32>` could well be `Copy`, in the sense that they are safe to memcpy. And that would be cool, because you could put them in a `Cell` and then use `get`/`set` to manipulate them. But we don't implement `Copy` for those types because [it would introduce a subtle footgun](https://github.com/rust-lang/rust/issues/18045):

```rust
let mut iter0 = vec.iter();
let mut iter1 = iter0;
iter1.next(); // does not effect `iter0`
```

Whether this is surprising or not depends on how well you know Rust -- but definitely it would be clearer if you had to call `clone` explicitly:

```rust
let mut iter0 = vec.iter();
let mut iter1 = iter0.clone();
iter1.next();
```

Similar considerations are the [reason we have not made `Cell<u32>` implement `Copy`](https://github.com/rust-lang/rust/issues/20813).

### The clone/copy rules interact very poorly with closures

The biggest source of confusion when it comes to clone/copy, however, is not about assignments like `x = y` but rather closures and async blocks. Combining ref-counted values with closures is a big stumbling block for new users. This has been true as long as I can remember. Here for example is a [2014 talk at Strangeloop][sloop] in which the speaker devotes considerable time to the "accidental complexity" (their words, but I agree) they encountered navigating cloning and closures (and, I will note, how the term clone is misleading because it doesn't mean a deep clone). I'm sorry to say that the situation they describe hasn't really improved much since then. And, bear in mind, this speaker is a skilled programmer. Now imagine a novice trying to navigate this. Oh boy.

[sloop]: https://youtu.be/U3upi-y2pCk?si=kFEhRB_O_wdMKysC&t=807

But it's not just beginners who struggle! In fact, there isn't really a *convenient* way to manage the problem of having to clone a copy of a ref-counted item for a closure's use. At the RustNL unconf, [Jonathan Kelley][jkelleyrtp], who heads up the [Dioxus Labs](https://dioxuslabs.com/), described how at CloudFlare codebase they spent significant time trying to find the most ergonomic way to thread context (and these are not Rust novices).

In that setting, they had a master context object `cx` that had a number of subsystems, each of which was ref-counted. Before launching a new task, they would handle out handles to the subsystems that task required (they didn't want every task to hold on to the entire context). They ultimately landed on a setup like this, which is still pretty painful:

[jkelleyrtp]: https://github.com/jkelleyrtp/

```rust
let _io = cx.io.clone():
let _disk = cx.disk.clone():
let _health_check = cx.health_check.clone():
tokio::spawn(async move {
    do_something(_io, _disk, _health_check)
})
```

You can make this (in my opinion) mildly better by leveraging variable shadowing, but even then, it's pretty verbose:

```rust
tokio::spawn({
    let io = cx.io.clone():
    let disk = cx.disk.clone():
    let health_check = cx.health_check.clone():
    async move {
        do_something(io, disk, health_check)
    }
})
```

What you *really* want is to just write something like this, like you would in Swift or Go or most any other modern language:[^novice]

```rust
tokio::spawn(async move {
    do_something(cx.io, cx.disk, cx.health_check)
})
```
[^novice]: Interestingly, when I read that snippet, I had a moment where I thought "maybe it should be `async move { do_something(cx.io.claim(), ...) }`?". But of course that won't work, that would be doing the claim *in* the future, whereas we want to do it *before*. But it really looks like it should work, and it's good evidence for how non-obvious this can be.

### "Autoclaim" to the rescue

What I propose is to modify the borrow checker to automatically invoke `claim` as needed. So e.g. an expression like `x = y` would be automatically converted to `x = y.claim()` if `y` will be used again later. And closures that capture variables in their environment would respect auto-claim as well, so `move || process(y)` would become `{ let y = y.claim(); move || process(y) }` if `y` were used again later.

Autoclaim would not apply to the last use of a variable. So `x = y` only introduces a call to `claim` if it is needed to prevent an error. This avoids unnecessary reference counting.

Naturally, if the type of `y` doesn't implement `Claim`, we would give a suitable error explaining that this is a move and the user should insert a call to `clone` if they want to make a cloned value.

### Support opt-out with an allow-by-default lint

There is definitely some code that benefits from having the distinction between *moving* an existing handle and *claiming* a new one made explicit. For these cases, what I think we should do is add an "allow-by-default" `automatic-claim` lint that triggers whenever the compiler inserts a call to `claim` on a type that is not `Copy`. This is a signal that user-supplied code is running.

To aid in discovery, I would consider a `automatic-operations` lint group for these kind of "almost always useful, but sometimes not" conveniences; effectively adopting the [profile pattern][] I floated at one point, but just by making it a lint group. Crates could then add `automatic-operations = 'deny"` (bikeshed needed) in the `[lints]` section of their `Cargo.toml`.

[profile pattern]: https://smallcultfollowing.com/babysteps/blog/2023/09/30/profiles/

## Step 3. Stop using `Copy` to control moves

Adding "autoclaim" addresses the ergonomic issues around having to call `clone`, but it still means that anything which is `Copy` can be, well, copied. As noted before that implies performance footguns (`[u8;1024]` is probably not something to be copied lightly) and correctness hazards (neither is an iterator). 

The real goal should be to disconnect "can be memcopied" and "can be automatically copied"[^doh]. Once we have "autoclaim", we can do that, thanks to the magic of lints and editions:

* In Rust 2024 and before, we warn when `x = y` copies a value that is `Copy` but not `Claim`.
* In the next Rust edition (Rust 2027, presumably), we make it a hard error so that the rule is just tied to `Claim` trait.

[^doh]: In effect I am proposing to revisit the decision we made in [RFC 936](https://github.com/rust-lang/rfcs/pull/936#issuecomment-78647601), way back when. Actually, I have more thoughts on this, I'll leave them to a FAQ!

At codegen time, I would still expect us to guarantee that `x = y` will memcpy and will not invoke `y.claim()`, since technically the `Clone` impl may not be the same behavior; it'd be nice if we could extend this guarantee to any call to `clone`, but I don't know how to do that, and it's a separate problem. Furthermore, the `automatic_claims` lint would only apply to types that don't implement `Copy`.[^copied]

[^copied]: Oooh, that gives me an idea. It would be nice if in addition to writing `x.claim()` one could write `x.copy()` (similar to [`iter.copied()`](https://doc.rust-lang.org/std/iter/trait.Iterator.html#method.copied)) to explicitly indicate that you are doing a memcpy. Then the compiler rule is basicaly that it will insert either `x.claim()` or `x.copy()` as appropriate for types that implement `Claim`.

## Frequently asked questions

All right, I've laid out the proposal, let me dive into some of the questions that usually come up.

### Are you ??!@$!$! nuts???

I mean, maybe? The Copy/Clone split has been a part of Rust for a long time[^history]. But from what I can see in real codebases and daily life, the impact of this change would be a net-positive all around:

* For most code, they get less clutter and less confusing error messages but the same great Rust taste (i.e., no impact on reliability or performance). 
* Where desired, projects can enable the lint (declaring that they care about performance as a side benefit). Furthermore, they can distinguish calls to `claim` (cheap, infallible, transparent) from calls to `clone` (anything goes).

What's not to like?

[^history]: I've noticed I'm often more willing to revisit long-standing design decisions than others I talk to. I think it comes from having been present when the decisions were made. I know most of them were close calls and often began with "let's try this for a while and see how it feels...". Well, I think it comes from that *and* a certain predilection for recklessness. 🤘

### What kind of code would `#[deny(automatic_claims)]`?

That's actually an interesting question! At first I thought this would correspond to the "high-level, business-logic-oriented code" vs "low-level systems software" distinction, but I am no longer convinced.

For example, I spoke with someone from Rust For Linux who felt that autoclaim would be useful, and it doesn't get more low-level than that! Their basic constraint is that they want to track carefully where memory allocation and other fallible operations occur, and incrementing a reference count is fine.

I think the real answer is "I'm not entirely sure", we have to wait and see! I suspect it will be a fairly small, specialized set of projects. This is part of why I this this is a good idea.

### Well my code *definitely* wants to track when ref-counts are incremented!

I totally get that! And in fact I think this proposal actually **helps** your code:

* By setting `#![deny(automatic_claims)]`, you declare up front the fact that reference counts are something you track carefully. OK, I admit not everything will consider this a pro. Regardless, it's a 1-time setup cost.
* By distinguishing `claim` from `clone`, your project avoids surprising performance footguns (this seems inarguably good).
* In the next edition, when we no longer make `Copy` implicitly copy, you further avoid the footguns associated with that (also inarguably good).

### Is this revisiting [RFC 936][]?

Ooh, deep cut! [RFC 936][] was a proposal to split `Pod` (memcopyable values) from `Copy` (implicitly memcopyable values). At the time, [we decided not to do this](https://github.com/rust-lang/rfcs/pull/936#issuecomment-84036944).[^fcp] I am even the one who [summarized the reasons](https://github.com/rust-lang/rfcs/pull/936#issuecomment-78647601). The short version is that we felt it better to have a single trait and lints.

[^fcp]: This RFC is so old it predates [rfcbot](https://github.com/rust-lang/rfcbot-rs)! Look how informal that comment was. Astounding.

[RFC 936]: https://github.com/rust-lang/rfcs/pull/936

I am definitely offering another alternative aiming at the same problem identified by the RFC. I don't think this means we made the wrong decision at the time. The problem was real, but the proposed solutions were not worth it. This proposal solves the same problems and more, and it has the benefit for ~10 years of experience.[^bestworst] (Also, it's worth pointing out that this RFC came two months before 1.0, and I *definitely* feel to avoid derailing 1.0 with last minute changes -- stability without stagnation!)

[^bestworst]: This seems to reflect the best and worst of Rust decision making. The best because autoclaim represents (to my mind) a nice "third way" in between two extreme alternatives. The worst because the rough design for autoclaim has been clear for years but it sometimes takes a long time for us to actually act on things. Perhaps that's just the nature of the beast, though.

### Doesn't having these "profile lints" split Rust?

A good question. Certainly on a technical level, there is nothing new here. We've had lints since forever, and we've seen that many projects use them in different ways (e.g., customized clippy levels or even -- like the linux kernel -- a [dedicated custom linter](https://github.com/Rust-for-Linux/klint)). An important invariant is that lints define "subsets" of Rust, they don't change it. **Any given piece of code that compiles always means the same thing.**

That said, the [profile pattern][] *does* lower the cost to adding syntactic sugar, and I see a "slippery slope" here. I don't want Rust to fundamentally change its character. We should still be aiming at our core constituency of programs that prioritize performance, reliability, and long-term maintenance.

### How will we judge when an ergonomic change is "worth it"?

I think we should write up some design axioms. But it turns out we already have a first draft! Some years back Aaron Turon wrote an astute analysis in the ["ergonomics initiative" blog post](https://blog.rust-lang.org/2017/03/02/lang-ergonomics.html#how-to-analyze-and-manage-the-reasoning-footprint). He identified three axes to consider:

> * **Applicability**. Where are you allowed to elide implied information? Is there any heads-up that this might be happening?
> * **Power**. What influence does the elided information have? Can it radically change program behavior or its types?
> * **Context-dependence**. How much of do you have to know about the rest of the code to know what is being implied, i.e. how elided details will be filled in? Is there always a clear place to look?

Aaron concluded that *"**implicit features should balance these three dimensions**. If a feature is large in one of the dimensions, it's best to strongly limit it in the other two."* In the case of autoclaim, the applicability is high (could happen a lot with no heads up) and the context dependence is medium-to-large (you have to know the types of things and traits they implement). We should therefore limit power, and this is why we put clear guidelines on who should implement `Claim`. And of course for the cases where that doesn't suffice, the lint can limit the applicability to zero.

I like this analysis. I also want us to consider "who will want to opt-out and why" and see if there are simple steps (e.g., ruling out allocation) we can take which will minimize that while retaining the feature's overall usefulness.

### What about explicit closure autoclaim syntax?

In a recent lang team meeting Josh raised the idea of annotating closures (and presumably async blocks) with some form of syntax that means "they will auto-capture things they capture". I find the concept appealing because I like having an explicit version of automatic syntax; also, projects that deny `automatic_claim` should have a lightweight alternative for cases where they want to be more explicit. However, I've not seen any actual specific *proposal* and I can't think of one myself that seems to carry its weight. So I guess I'd say "sure, I like it, but I would want it in addition to what is in this blog post, not instead of".

### What about explicit closure *capture clauses*?

Ah, good question! It's almost like you read my mind! I was going to add to the previous question that I *do* like the idea of having some syntax for "explicit capture clauses" on closures. 

Today, we just have `|| $body` (which implicitly captures paths in `$body` in some mode) and `move || $body` (which implicitly captures paths in `$body` by value).

Some years ago I wrote a [draft RFC in a hackmd](https://hackmd.io/@nikomatsakis/SyI0eMFXO?type=view) that I still mostly like (I'd want to revisit the details). The idea was to expand `move` to let it be more explicit about what is captured. So `move(a, b) || $body` would capture *only* `a` and `b` by value (and error if `$body` references other variables). But `move(&a, b) || $body` would capture `a = &a`. And `move(a.claim(), b) || $body` would capture `a = a.claim()`.

This is really attacking a different problem, the fact that closure captures have no explicit form, but it also gives a canonical, lighterweight pattern for "claiming" values from the surrounding context. 

### How did you come up with the name `Claim`?

I *thought* [Jonathan Kelley](https://github.com/jkelleyrtp/) suggested it to me, but reviewing my notes I see he suggested `Capture`. Well, that's a good name too. Maybe even a better one! I've already written this whole damn blog post using the name `Claim`, so I'm not going to go change it now. But I'd expect a proper bikeshed before taking any real action.
