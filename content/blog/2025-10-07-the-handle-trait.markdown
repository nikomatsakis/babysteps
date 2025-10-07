---
title: "The Handle trait"
date: 2025-10-07T10:04:55-04:00
series:
- "Ergonomic RC"
---

There's been a lot of discussion lately around ergonomic ref-counting. We had a lang-team design meeting and then a quite impactful discussion at the RustConf Unconf. I've been working for weeks on a follow-up post but today I realized what should've been obvious from the start -- that if I'm taking that long to write a post, it means the post is too damned long. So I'm going to work through a series of smaller posts focused on individual takeaways and thoughts. And for the first one, I want to (a) bring back some of the context and (b) talk about an interesting question, **what should we call the trait**. My proposal, as the title suggests, is `Handle` -- but I get ahead of myself.

## The story thus far

For those of you who haven't been following, there's been an ongoing discussion about how best to have ergonomic ref counting:

* It began with the first Rust Project Goals program in 2024H2, where Jonathan Kelley from Dioxus wrote a [thoughtful blog post about a path to high-level Rust](https://dioxus.notion.site/Dioxus-Labs-High-level-Rust-5fe1f1c9c8334815ad488410d948f05e) that eventually became a 2024H2 [project goal towards ergonomic ref-counting](https://rust-lang.github.io/rust-project-goals/2024h2/ergonomic-rc.html).
* I wrote a [series of blog posts about a trait I called `Claim`](https://smallcultfollowing.com/babysteps/series/claim/).
* Josh and I talked and Josh opened [RFC #3680][], which proposed a `use` keyword and `use ||` closures. Reception, I would say, was mixed; yes, this is tackling a real problem, but there were lots of concerns on the approach. [I summarized the key points here](https://github.com/rust-lang/rfcs/pull/3680#issuecomment-2625526944).
* Santiago implemented experimental support for (a variant of) [RFC #3680][] as part of the [2025H1 project goal](https://rust-lang.github.io/rust-project-goals/2025h1/ergonomic-rc.html).
* I authored a [2025H2 project goal proposing that we create an alternative RFC focused on higher-level use-cases](https://rust-lang.github.io/rust-project-goals/2025h2/ergonomic-rc.html) which prompted Josh and I have to have a long and fruitful conversation in which he convinced me that this was not the right approach.
* We had a lang-team design meeting on 2025-08-27 in which I presented this [survey and summary of the work done thus far](https://hackmd.io/@rust-lang-team/B12TpGhKle).
* And then at the [RustConf 2025 Unconf](https://2025.rustweek.org/unconf/) we had a big group discussion on the topic that I found very fruitful, as well as various follow-up conversations with smaller groups.

[RFC #3680]: https://github.com/rust-lang/rfcs/pull/3680

## This blog post is about "the trait"

The focus of this blog post is on one particular question: what should we call "The Trait". In virtually every design, there has been *some kind* of trait that is meant to identify *something*. But it's been hard to get a handle[^foreshadowing] on what precisely that *something* is. What is this trait for and what types should implement it? Some things are clear: whatever The Trait is, `Rc<T>` and `Arc<T>` should implement it, for example, but that's about it.

[^foreshadowing]: That. my friends,  is *foreshadowing*. Damn I'm good.

My original proposal was for a trait named [`Claim`][] that was meant to convey a "lightweight clone" -- but really the trait was [meant to replace `Copy` as the definition of which clones ought to be explicit][wirp][^heavycopy]. Jonathan Kelley had a similar proposal but called it `Capture`. In [RFC #3680] the proposal was to call the trait `Use`.

[`Claim`]: https://smallcultfollowing.com/babysteps/blog/2024/06/21/claim-auto-and-otherwise/

[wirp]: https://smallcultfollowing.com/babysteps/blog/2024/06/26/claim-followup-1/#what-i-really-proposed

[^heavycopy]: I described `Claim` as a kind of "lightweight clone" but in the Unconf someone pointed out that "heavyweight copy" was probably a better description of what I was going for.

The details and intent varied, but all of these attempts had one thing in common: they were very *operational*. That is, the trait was always being defined in terms of *what* it does (or doesn't do) but not *why* it does it. And that I think will always be a weak grounding for a trait like this, prone to confusion and different interpretations. For example, what is a "lightweight" clone? Is it O(1)? But what about things that are O(1) with very high probability? And of course, O(1) doesn't mean *cheap* -- it might copy 22GB of data every call. That's O(1).

What you want is a trait where it's fairly clear when it should and should not be implemented and not based on taste or subjective criteria. And `Claim` and friends did not meet the bar: in the Unconf, several new Rust users spoke up and said they found it very hard, based on my explanations, to judge whether their types ought to implement The Trait (whatever we call it). That has also been a persitent theme from the RFC and elsewhere.

## "Shouldn't we call it *share*?" (hat tip: Jack Huey)

But really there *is* a semantic underpinning here, and it was Jack Huey who first suggested it. Consider this question. What are the differences between cloning a `Mutex<Vec<u32>>` and a `Arc<Mutex<Vec<u32>>>`?

One difference, of course, is cost. Cloning the `Mutex<Vec<u32>>` will deep-clone the vector, cloning the `Arc` will just increment a referece count. 

But the more important difference is what I call *"entanglement"*. When you clone the `Arc`, you don't get a new value -- you get back a *second handle to the same value*.

[^fp]: and functional programming...

## Entanglement changes the meaning of the program

Knowing which values are "entangled" is key to understanding what your program does. A big part of how the borrow checker[^fp] achieves reliability is by reducing "entaglement", since it becomes a relative pain to work with in Rust.

Consider the following code. What will be the value of `l_before` and `l_after`?

```rust
let l_before = v1.len();
let v2 = v1.clone();
v2.push(new_value);
let l_after = v1.len();
```

The answer, of course, is "depends on the type of `v1`". If `v1` is a `Vec`, then `l_after == l_before`. But if `v1` is, say, a struct like this one:

```rust
struct SharedVec<T> {
    data: Arc<Mutex<Vec<T>>>
}

impl<T> SharedVec<T> {
    pub fn push(&self, value: T) {
        self.data.lock().unwrap().push(value);
    }

    pub fn len(&self) -> usize {
        self.data.lock().unwrap().len()
    }
}
```

then `l_after == l_before + 1`.

There are many types that act like a `SharedVec`: it's true for `Rc` and `Arc`, of course, but also for things like [`Bytes`](https://docs.rs/bytes/latest/bytes/struct.Bytes.html) and channel endpoints like [`Sender`](https://doc.rust-lang.org/std/sync/mpsc/struct.Sender.html). All of these are examples of "handles" to underlying values and, when you clone them, you get back a second handle that is indistinguishable from the first one.

## We have a name for this concept already: handles

Jack's insight was that we should focus on the *semantic concept* (sharing) and not on the operational details (how it's implemented). This makes it clear when the trait ought to be implemented. I liked this idea a lot, although I eventually decided I didn't like the name `Share`. The word isn't specific enough, I felt, and users might not realize it referred to a specific concept: "shareable types" doesn't really sound right. But n fact there *is* a name already in common use for this concept: handles (see e.g. [`tokio::runtime::Handle`](https://docs.rs/tokio/latest/tokio/runtime/struct.Handle.html)).

This is how I arrived at my proposed name and definition for The Trait, which is `Handle`:[^final]

```rust
/// Indicates that this type is a *handle* to some
/// underlying resource. The `handle` method is
/// used to get a fresh handle.
trait Handle: Clone {
    final fn handle(&self) -> Self {
        Clone::clone(self)
    }
}
```

[^final]: The "final" keyword was proposed by Josh Triplett in RFC 3678. It means that impls cannot change the definition of `Handle::handle`. There's been some back-and-forth on whether it ought to be renamed or made more general or what have you; all I know is, I find it an incredibly useful concept for cases like this, where you want users to be able to opt-in to a method being *available* but *not* be able to change what it does. You can do this in other ways, they're just weirder.

## We would lint and advice people to call `handle`

The `Handle` trait includes a method `handle` which is *always* equivalent to `clone`. The purpose of this method is to signal to the reader that the result is a second handle to the same underlying value.

Once the `Handle` trait exists, we should lint on calls to `clone` when the receiver is known to implement `Handle` and encourage folks to call `handle` instead:

```rust
impl DataStore {
    fn store_map(&mut self, map: &Arc<HashMap<...>>) {
        self.stored_map = map.clone();
        //                    -----
        //
        // Lint: convert `clone` to `handle` for
        // greater clarity.
    }
}
```

Compare the above to the version that the lint suggests, using `handle`, and I think you will get an idea for how `handle` increases clarity of what is happening:

```rust
impl DataStore {
    fn store_map(&mut self, map: &Arc<HashMap<...>>) {
        self.stored_map = map.handle();
    }
}
```

## What it means to be a *handle*

The defining characteristic of a *handle* is that it, when cloned, results in a second value that accesses the same underlying value. This means that the two handles are "entangled", with interior mutation that affects one handle showing up in the other. Reflecting this, most handles have APIs that consist exclusively or almost exclusively of `&self` methods, since having unique access to the *handle* does not necessarily give you unique access to the *value*.

Handles are generally only significant, semantically, when interior mutability is involved. There's nothing *wrong* with having two handles to an immutable value, but it's not generally distinguishable from two copies of the same value. This makes persistent collections an interesting grey area: I would probably implement `Handle` for something like `im::Vec<T>`, particularly since something like a `im::Vec<Cell<u32>>` *would* make entaglement visible, but I think there's an argument against it.

## Handles in the stdlib

In the stdlib, handle would be implemented for exactly one `Copy` type (the others are values):

```rust
// Shared references, when cloned (or copied),
// create a second reference:
impl<T: ?Sized> Handle for &T {}
```


It would be implemented for ref-counted pointers (but not `Box`):

```rust
// Ref-counted pointers, when cloned,
// create a second reference:
impl<T: ?Sized> Handle for Rc<T> {}
impl<T: ?Sized> Handle for Arc<T> {}
```

And it would be implemented for types like channel endpoints, that are implemented with a ref-counted value under the hood:

```rust
// mpsc "senders", when cloned, create a
// second sender to the same underlying channel:
impl<T: ?Sized> Handle for mpsc::Sender {}
```

## Conclusion: let's call The Trait `Handle`

OK, I'm going to stop there with this "byte-sized" blog post. More to come!