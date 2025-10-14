---
title: "Move, Destruct, Leak, and Rust"
date: 2025-10-13T14:33:02-04:00
draft: true
---

This post presents a proposal to extend Rust to support a number of different kinds of destructors. This means we could async drop, but also prevent "forgetting" (leaking) values, enabling async scoped tasks that run in parallel à la rayon/libstd. We'd also be able to have types whose "destructors" require arguments. This proposal -- an evolution of ["must move"] that I'll call "controlled destruction" -- is, I think, needed for Rust to live up to its goal of giving safe versions of critical patterns in systems programming. As such, it is needed to complete the "async dream", in which async Rust and sync Rust work roughly the same.

Nothing this good comes for free. The big catch of the proposal is that it introduces more "core splits" into Rust's types. I believe these splits are well motivated and reasonable -- they reflect *inherent complexity*, in other words, but they are something we'll want to think carefully about nonetheless.

["must move"]: {{< baseurl >}}/blog/2023/03/16/must-move-types.html

## Summary

The TL;DR of the proposal is that we should:

* Introduce a new "default trait bound" `Forget` and an associated trait hierarchy:
    * `trait Forget: Drop`, representing values that can be forgotten
    * `trait Destruct: Move`, representing values with a destructor
    * `trait Move: Pointee`, representing values that can be moved
    * `trait Pointee`, the base trait that represents *any value*
* Use the "opt-in to weaker defaults" scheme proposed for sizedness by [RFC #3729 (Hierarchy of Sized Traits)][3729]
    * So `fn foo<T>(t: T)` defaults to "a `T` that can be forgotten/destructed/moved"
    * And `fn foo<T: Destruct>(t: T)` means "a `T` that can be destructed, but not necessarily forgotten"
    * And `fn foo<T: Move>(t: T)` means "a `T` that can be moved, but not necessarily forgotten"
    * ...and so forth.
* Integrate and enforce the new traits:
    * The bound on `std::mem::forget` will already require `Forget`, so that's good.
    * Borrow check can enforce that any dropped value must implement `Destruct`; in fact, we already do this to enforce `const Destruct` bounds in `const fn`.
    * Borrow check can be extended to require a `Move` bound on any moved value.
* Adjust the trait bound on closures (luckily this works out fairly nicely)

[3729]: https://github.com/rust-lang/rfcs/pull/3729

## Motivation

We wish to extend Rust 
## The "capabilities" of value disposal

Rust today assumes that every `Sized` value can be moved, dropped, and forgotten:

```rust
// Without knowing anything about `T` apart
// from the fact that it's `Sized`, we can...
fn demonstration<T>(a: T, b: T, c: T) {
    // ...drop `a`, running its destructor immediately.
    std::mem::drop(a);

    // ...forget `b`, skipping its destructor
    std::mem::forget(b);

    // ...move `c` into `x`
    let x = c;
} // ...and then have `x` get dropped automatically,
// as exit the block.
```

## Destructors are like "methods that the language calls for you"

I think of Rust's rules like this -- every value has special method, `destruct(self)`, corresponding to what the compiler calls "drop glue":

* The destruct method for a struct...
    * First calls your `Drop` impl, if one exists
    * Then drops all your fields, in order

What makes the `destruct` method special, besides the fact that it is compiler generated, is that the compiler calls it for you when a value goes out of scope. It's a kind of *default method*. But you can *opt out* from that default call by using `std::mem::forget`.

## Problems with the one-size-fits-all destruct

Rust's system of a *destructor that is "hard not to call" (but not impossible)* is pretty useful. But it has some shortcomings:

* Some types are not safe to move -- this is why we have `Pin`.
* Some destructors should really take arguments.
* Some destructors really **must** execute.

This last point is key. Because Rust today allows any value to be "forgotten", the only way to *guarantee* that a destructor will run is to retain ownership of the value. This can be imporant to unsafe code -- APIs that permit scoped threads, for example, need to *guarantee* that those parallel threads will be joined before the function returns. The only way they have to do that is to use a closure which gives `&`-borrowed access to a `scope`:

```rust
scope(|s| ...)
//     -  --- ...which ensures that this
//     |      fn body cannot "forget" it.
//     |  
// This value has type `&Scope`... 
```

Because the API nevers gives up ownership of the scope, it can ensure that it is never "forgotten" and thus that its destructor runs.

## Guaranteed destructors are needed for parallelism

There is one big problem with this scheme, which is that it relies on *synchronous* code. It falls down in the case of *async* code, because async functions don't execute immediately, they return futures -- which are themselves values! And those *futures* can be forgotten.

When you start poking around, you find that *guaranteed* destructors turn up quite a bit in systems programming. Scoped APIs in futures are one example, but DMA (direct memory access) is another. Many embedded devices have a mode where you begin a DMA transfer that causes memory to be written into memory asynchronously. But you need to ensure that this DMA is terminated *before* that memory is freed. If that memory is on your stack, that means you need a destructor that will either cancel or block until the DMA finishes.[^parallel]

[^parallel]: Really the DMA problem is the same as scoped threads. If you think about it, the embedded device writing to memory is basically the same as a parallel thread writing to memory.

## Not all destructors fit the `fn destruct(self)` signature

Another interesting problem with today's destructors is that Rust forces them all to have the exact same signature: `fn destruct(self)`. For many use cases, that signature is too limiting: not all "cleanup" routines can run synchronously, take no arguments, and return `()`. For example, in databases, it's common to have some kind of "transaction" that, once started, needs to be *completed* -- but completing a transaction may return an error or other value. And in async land, it's common to have values that, when dropped, need to perform async operations, which means the synchronous signature isn't good enough.

In other cases, the `fn destruct(self)` signature is too *permissive*. Consider a const fn: if you are going to drop a value in const-.and, you need to know that the destructor for that type is const.

## How to tweak a default

So the situation we have is this:  

## The "opt-in to less than the default" approach

This point about "what if our default bounds were different" comes up a lot. But the approach we are taking to extend `Sized` bounds ([based roughly on this blog post][sized]) offers a path forward. Whereas the "old Rust" was to have a bound like `?Sized`, that "opted out" of a default, the new approach is to have a *positive* bound that identifies the capabilities you *need* -- and which implies that you are opting out of the other default capabilities built on top of that. The way I think of it is that there is a ladder of functionality. By default, you get the whole ladder. But if you explicit say which rung you want, then you just get that rung and below. Of course if you say two rungs, you get the higher of the two.

[sized]: {{< baseurl >}}/blog/2024/04/23/dynsized-unsized.html

## The bound hierarchy for moving and dropping

I think we want to take Rust's "default bound" and break into several tiers:

* `trait Forget: Destruct`, the default, indicates a "leakable" or "forgettable" value.


This approach has two advantages over `?` bounds:

* It's easier to understand what bound you need if you don't want want everything. Instead of 'opting out' from things you don't need, you just say the thing you *do* need.
* It is compatible with adding more layers later. If you have two levels, X and Z, and then you have a function that says it only needs X, that's all it needs. If we later add Y in between, the function will still just get X and below. But if the function had said that 

## 