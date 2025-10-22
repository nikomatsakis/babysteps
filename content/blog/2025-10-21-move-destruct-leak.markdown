---
title: "Move, Destruct, Leak, and Rust"
date: 2025-10-21T21:45:02-04:00
series:
- "Must move"
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

In a [talk I gave some years back at Rust LATAM in Uruguay](https://nikomatsakis.github.io/rust-latam-2019/#1)[^great], I [said this](https://nikomatsakis.github.io/rust-latam-2019/#81):

[^great]: That was a great conference. Also, interestingly, this is one of my favorite of all my talks, but for some reason, I rarely reuse this material. I should change that.

* It's easy to **expose** a high-performance API.
* But it's hard to **help users control it** -- and this is what Rust's type system does.

<img src="{{< baseurl >}}/assets/2025-movedestructleak/firespell.gif" alt="Person casting a firespell and burning themselves"/>

Rust currently does a pretty good job with preventing parts of your program from interfering with one another, but we don't do as good a job when it comes to guaranteeing that cleaup happens[^safety]. We have destructors, of course, but they have two critical limitations:

[^safety]: Academics distinguish "safety" from "liveness properties", where safety means "bad things don't happen" and "liveness" means "good things eventually happen". Another way of saying this is that Rust's type system helps with a lot of safety properties but struggles with liveness properties.

* All destructors must meet the same signature, `fn drop(&mut self)`, which isn't always adequate. 
* There is no way to guarantee a destructor once you give up ownership of a value.

### Making it concrete.

That motivation was fairly abstract, so let me give some concrete examples of things that tie back to this limitation:

* The ability to have `async` or `const` drop, both of which require a distinct drop signature.
* The ability to have a "drop" operation that takes arguments, such as e.g. a message that must be sent, or a result code that must be provided before the program terminates.
* The ability to have async scopes that can access the stack, which requires a way to guarantee that a parallel thread will be joined even in an async context.
* The ability to integrate at maximum efficiency with WebAssembly async tasks, which require guaranteed cleanup.[^citation]

[^citation]: Uh, citation needed. I know this is true but I can't find the relevant WebAssembly issue where it is discussed. Help, internet!

The goal of this post is to outline an approach that could solve all of the above problems and which is backwards compatible with Rust today.

### The "capabilities" of value disposal

The core problem is that Rust today assumes that every `Sized` value can be moved, dropped, and forgotten:

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

### Destructors are like "opt-out methods"

The way I see, most methods are "opt-in" -- they don't execute unless you call them. But destructors are different. They are effectively a method that runs by default -- unless you opt-out, e.g., by calling `forget`. But the ability to opt-out means that they don't fundamentally add any power over regular methods, they just make for a more ergonomic API.

The implication is that the only way in Rust today to *guarantee* that a destructor will run is to retain ownership of the value. This can be important to unsafe code -- APIs that permit scoped threads, for example, need to *guarantee* that those parallel threads will be joined before the function returns. The only way they have to do that is to use a closure which gives `&`-borrowed access to a `scope`:

```rust
scope(|s| ...)
//     -  --- ...which ensures that this
//     |      fn body cannot "forget" it.
//     |  
// This value has type `&Scope`... 
```

Because the API nevers gives up ownership of the scope, it can ensure that it is never "forgotten" and thus that its destructor runs.

The scoped thread approach works for sync code, but it doesn't work for async code. The problem is that async functions return a future, which is a value. Users can therefore decide to "forget" this value, just like any other value, and thus the destructor may never run.

### Guaranteed cleanup is common in systems programming

When you start poking around, you find that *guaranteed* destructors turn up quite a bit in systems programming. Scoped APIs in futures are one example, but DMA (direct memory access) is another. Many embedded devices have a mode where you begin a DMA transfer that causes memory to be written into memory asynchronously. But you need to ensure that this DMA is terminated *before* that memory is freed. If that memory is on your stack, that means you need a destructor that will either cancel or block until the DMA finishes.[^parallel]

[^parallel]: Really the DMA problem is the same as scoped threads. If you think about it, the embedded device writing to memory is basically the same as a parallel thread writing to memory.

## So what can we do about it?

This situation is very analogous to the challenge of revisiting the default `Sized` bound, and I think the same basic approach that I outlined in [this blog post][sized] will work.

The core of the idea is simple: have a "special" set of traits arranged in a hierarchy:

```rust
trait Forget: Destruct {} // Can be "forgotten"
trait Destruct: Move {}   // Can be "destructed" (dropped)
trait Move: Pointee {}    // Can be "moved"
trait Pointee {}          // Can be referenced by pointer
```

 By default, generic parameters get a `Forget` bound, so `fn foo<T>()` is equivalent to `fn foo<T: Forget>()`. But if the parameter *opts in* to a weaker bound, then the default is suppressed, so `fn bar<T: Destruct>()` means that `T` is assumed by "destructible" but *not* forgettable. And `fn baz<T: Move>()` indicates that `T` can *only* be moved.

 ## Impact of these bounds

 Let me explain briefly how these bounds would work.

### The default can forget, drop, move etc

Given a default type `T`, or one that writes `Forget` explicitly, the function can do anything that is possible today:


```rust
fn just_forget<T: Forget>(a: T, b: T, c: T) {
    //         --------- this bound is the default
    std::mem::drop(a);   // OK
    std::mem::forget(b); // OK
    let x = c;           // OK
}
```

### The forget function requires `T: Forget`

The `std::mem::forget` function would require `T: Forget` as well:

```rust
pub fn forget<T: Forget>(value: T) { /* magic intrinsic */ }
```

This means that if you have only `Destruct`, the function can only drop or move, it can't "forget":

```rust
fn just_destruct<T: Destruct>(a: T, b: T, c: T) {
    //           -----------
    // This function only requests "Destruct" capability.

    std::mem::drop(a);   // OK
    std::mem::forget(b); // ERROR: `T: Forget` required
    let x = c;           // OK
}
```

### The borrow checker would require "dropped" values implement `Destruct`

We would modify the `drop` function to require only `T: Destruct`:

```rust
fn drop<T: Destruct>(t: T) {}
```

We would also extend the borrow checker so that when it sees a value being dropped (i.e., because it went out of scope), it would require the `Destruct` bound.

That means that if you have a value whose type is only `Move`, you cannot "drop" it:

```rust
fn just_move<T: Move>(a: T, b: T, c: T) {
    //           -----------
    // This function only requests "Move" capability.

    std::mem::drop(a);   // ERROR: `T: Destruct` required
    std::mem::forget(b); // ERROR: `T: Forget` required
    let x = c;           // OK
}                        // ERROR: `x` is being dropped, but `T: Destruct`
```

This means that if you have only a `Move` bound, you *must* move anything you own if you want to return from the function. For example:

```rust
fn return_ok<T: Move>(a: T) -> T {
    a // OK
}
```

If you have a function that does not move, you'll get an error:

```rust
fn return_err<T: Move>(a: T) -> T {
} // ERROR: `a` does not implement `Destruct`
```

It's worth pointing out that this will be annoying as all get out in the face of panics:

```rust
fn return_err<T: Move>(a: T) -> T {
    // ERROR: If a panic occurs, `a` would be dropped, but `T` not implement `Destruct`
    forbid_env_var();

    a
} 

fn forbid_env_var() {
    if std::env::var("BAD").is_ok() {
        panic!("Uh oh: BAD cannot be set");
    }
}
```

I'm ok with this, but it is going to put pressure on better ways to rule out panics statically.

### Const (and later async) variants of `Destruct`

In fact, we are already doing something much like this destruct check for const functions. Right now if you have a const fn and you try to drop a value, you get an error:

```rust
const fn test<T>(t: T) {
} // ERROR!
```

Compiling that gives you the error:

```
error[E0493]: destructor of `T` cannot be evaluated at compile-time
 --> src/lib.rs:1:18
  |
1 | const fn test<T>(t: T) { }
  |                  ^       - value is dropped here
  |                  |
  |                  the destructor for this type cannot be evaluated in constant functions
```

This check is not presently taking place in borrow check but it could be.

### The borrow checker would require "moved" values implement `Move`

The final part of the check would be requiring that "moved" values implement `Move`:

```rust
fn return_err<T: Pointee>(a: T) -> T {
    a // ERROR: `a` does not implement `Move`
}
```

You might think that having types that are `!Move` would replace the need for pin, but this is not the case. A *pinned* value is one that can *never move again*, whereas a value that is not `Move` can never be moved in the first place -- at least once it is stored into a place.

I'm not sure if this part of the proposal makes sense, we could start by just having all types be `Move`, `Destruct`, or (the default) `Forget`.

### Opting out from forget etc

The other part of the proposal is that you should be able to explicit "opt out" from being forgettable, e.g. by doing

```rust
struct MyType {}
impl Destruct for MyType {}
```

Doing this will limit the generics that can accept your type, of course.

### Associated type bounds

The tough part with these "default bound" proposals is always associated type bounds. For backwards compatibility, we'd have to default to `Forget` but a lot of associated types that exist in the wild today shouldn't really *require* `Forget`. For example a trait like `Add` should *really* just require `Move` for its return type:

```rust
trait Add<Rhs = Self> {
    type Output /* : Move */;
}
```

I am basically not too worried about this. It's possible that we can weaken these bounds over time or through editions. Or, perhaps, add in some kind of edition-specific "alias" like

```rust
trait Add2025<Rhs = Self> {
    type Output: Move;
}
```

where `Add2025` is implemented for everything that implements `Add`.

I am not sure exactly how to manage it, but we'll figure it out -- and in the meantime, most of the types that should not be forgettable are really just "guard" types that don't have to flow through quite so many places.

#### Associated type bounds in closures

The one place that I think it is *really imporatnt* that we weaken the associated type bounds is with closures-- and, fortunately, that's a place we can get away with due to the way our "closure trait bound" syntax works. I feel like I wrote a post on this before, but I can't find it now, but the short version is that, today, when you write `F: Fn()`, that means that the closure must return `()`. If you write `F: Fn() -> T`, then this type `T` must have been declared somewhere else, and so `T` will (independently from the associated type of the `Fn` trait) get a default `Forget` bound. So since the `Fn` associated type is not independently nameable in stable Rust, we can change its bounds, and code like this would continue to work unchanged:

```rust
fn foo<T, F>()
where
    F: Fn() -> T,
    //         - `T: Forget` still holds by default
{}
```

## Frequently asked questions

### How does this relate to the recent thread on internals?

Recently I was pointed at [this internals thread](https://internals.rust-lang.org/t/pre-rfc-substructural-type-system/23614) for a "substructural type system" which likely has very similar capabilities. To be totally honest, though, I haven't had time to read and digest it yet! I had this blog post like 95% done though so I figured I'd post it first and then go try and compare.

### What would it mean for a struct to opt out of `Move` (e.g., by being only `Pointee`)?

So, the system as I described *would* allow for 'unmoveable' types (i.e., a struct that opts out from everything and only permits `Pointee`), but such a struct would only really be something you could store in a static memory location. You couldn't put it on the stack because the stack must eventually get popped. And you couldn't move it from place to place because, well, it's immobile.

This seems like something that could be useful -- e.g., to model "video RAM" or something that lives in a specific location in memory and cannot live anywhere else -- but it's not a widespread need.

### How would you handle destructors with arguments?

I imagine something like this:

```rust
struct Transaction {
    data: Vec<u8>
}

/// Opt out from destruct
impl Move for Transaction { }

impl Transaction {
    // This is effectively a "destructor"
    pub fn complete(
        self, 
        connection: Connection,
    ) {
        let Transaction { data } = self;
    }
}
```

With this setup, any function that owns a `Transaction` must eventually invoke `transaction.complete()`. This is because no values of this type can be dropped, so they must be moved.

### How does this relate to async drop?

This setup provides attacks a key problem that has blocked async drop in my mind, which is that types that are "async drop" do not have to implement "sync drop". This gives the type system the ability to prevent them from being dropped in sync code, then, and it would mean that they can only be dropped in async drop. But there's still lots of design work to be done there.

### Why is the trait `Destruct` and not `Drop`?

This comes from the const generifs work. I don't love it. But there is a logic to it. Right now, when you drop a struct or other value, that actually does a whole sequence of things, only one of which is running any `Drop` impl -- it also (for example) drops all the fields in the struct recursively, etc. The idea is that "destruct" refers to this whole sequence.

### How hard would this to be to prototype?

I...don't actually think it would be very hard. I've thought somewhat about it and all of the changes seem pretty straightforward. I would be keen to support a [lang-team experiment](https://lang-team.rust-lang.org/how_to/experiment.html) on this.

### Does this mean we should have had leak?

The whole topic of destructors and leaks and so forth datesback to approximately Rust 1.0, when we discovered that, in fact, our abstraction for threads was unsound when combined with cyclic ref-counted boxes. Before that we hadn't fully internalized that destructors are "opt-out methods". You can read [this blog post I wrote at the time][rcleak]. At the time, the primary idea was to have some kind of `?Leak` bounds and it was tied to the idea of references (so that all `'static` data was assumed to be "leakable", and hence something you could put into an `Rc`). I... mostly think we made the right call at the time. I think it's good that most of the ecosystem is interoperable and that `Rc` doesn't require `static` bounds, and certainly I think it's good that we moved to 1.0 with minimal disruption. In any case, though, I rather prefer this design to the ones that were under discussion at the time, in part because it also addresses the need for different kinds of destructors and for destructors with many arguments and so forth, which wasn't something we thought about then.

[rcleak]: {{< baseurl >}}/blog/2015/04/29/on-reference-counting-and-leaks/

### Isn't it confusing to have these "magic" traits that "opt out" from default bounds?

I think that specifying the *bounds you want* is inherently better than today's `?` design, both because it's easier to understand and because it allows us to backwards compatibly add traits in between in ways that are not possible with the `?` design.

However, I do see that having `T: Move` mean that `T: Destruct` does not hold is subtle. I wonder if we should adopt some kind of sigil or convention on these traits, like `T: @Move` or something. I don't know! Something to consider.