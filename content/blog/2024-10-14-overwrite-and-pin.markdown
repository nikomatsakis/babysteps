---
title: "The `Overwrite` trait and `Pin`"
date: 2024-10-14T15:12:38Z
series:
- "Overwrite trait"
---

In July, boats presented a compelling vision in their post [pinned places][]. With the `Overwrite` trait that I introduced in my previous post, however, I think we can get somewhere even *more* compelling, albeit at the cost of a tricky transition. As I will argue in this post, the `Overwrite`  trait effectively becomes a better version of the existing `Unpin` trait, one that effects not only pinned references but also regular `&mut` references. Through this it's able to make `Pin` fit much more seamlessly with the rest of Rust.

[pinned places]: https://without.boats/blog/pinned-places/

## Just show me the dang code

Before I dive into the details, let's start by reviewing a few examples to show you what we are aiming at (you can also skip to the [TL;DR](#sotheres-a-lot-here-whats-the-key-takeaways), in the FAQ).

I'm assuming a few changes here:

* Adding an `Overwrite` trait and changing most types to be `!Overwrite` by default.
    * The `Option<T>` (and maybe others) would opt-in to `Overwrite`, permitting `x.take()`.
* Integrating pin into the borrow checker, extending auto-ref to also "auto-pin" and produce a `Pin<&mut T>`. The borrow checker only permits you to pin values that you own. Once a place has been pinned, you are not permitted to move out from it anymore (unless the value is overwritten).

The first change is "mildly" backwards incompatible. I'm not going to worry about that in this post, but I'll cover the ways I think we can make the transition in a follow up post.

<a name="example-1" />

### Example 1: Converting a generator into an iterator

We would really like to add a *generator* syntax that lets you write an iterator more conveniently.[^details] For example, given some slice `strings: &[String]`, we should be able to define a generator that iterates over the string lengths like so:

[^details]: The precise design of generators is of course an ongoing topic of some controversy. I am not trying to flesh out a true design here or take a position. Mostly I want to show that we can create ergonomic bridges between "must pin" types like generators and "non pin" interfaces like `Iterator` in an ergonomic way without explicit mentioning of pinning.

```rust
fn do_computation() -> usize {
    let hashes = gen {
        let strings: Vec<String> = compute_input_strings();
        for string in &strings {
            yield compute_hash(&string);
        }
    };
    
    // ...
}
```

But there is a catch here! To permit the borrow of `strings`, which is owned by the generator, the generator will have to be pinned.[^yagni] That means that generators cannot directly implement `Iterator`, because generators need a `Pin<&mut Self>` signature for their `next` methods. It *is* possible, however, to implement `Iterator` for `Pin<&mut G>` where `G` is a generator.[^anyptr]

[^yagni]: Boats has argued that, since no existing iterator can support borrows over a yield point, generators might not need to do so either. I don't agree. I think supporting borrows over yield points is necessary for ergonomics [just as it was in futures](https://aturon.github.io/tech/2018/04/24/async-borrowing/).

[^anyptr]: Actually for `Pin<impl DerefMut<Target: Generator>>`.

In today's Rust, that means that using a generator as an iterator would require explicit pinning:

```rust
fn do_computation() -> usize {
    let hashes = gen {....};
    let hashes = pin!(hashes); // <-- explicit pin
    if let Some(h) = hashes.next() {
        // process first hash
    };
    // ...
}
```

With [pinned places][], this feels more builtin, but it still requires users to actively think about pinning for even the most basic use case:

```rust
fn do_computation() -> usize {
    let hashes = gen {....};
    let pinned mut hashes = hashes;
    if let Some(h) = hashes.next() {
        // process first hash
    };
    // ...
}
```

Under this proposal, users would simply be able to ignore pinning altogether:

```rust
fn do_computation() -> usize {
    let mut hashes = gen {....};
    if let Some(h) = hashes.next() {
        // process first hash
    };
    // ...
}
```

Pinning is still happening: once a user has called `next`, they would not be able to move `hashes` after that point. If they tried to do so, the borrow checker (which now understands pinning natively) would give an error like:

```rust
error[E0596]: cannot borrow `hashes` as mutable, as it is not declared as mutable
 --> src/lib.rs:4:22
  |
4 |     if let Some(h) = hashes.next() {
  |                      ------ value in `hashes` was pinned here
  |     ...
7 |     move_somewhere_else(hashes);
  |                         ^^^^^^ cannot move a pinned value
help: if you want to move `hashes`, consider using `Box::pin` to allocate a pinned box
  |
3 |     let mut hashes = Box::pin(gen { .... });
  |                      +++++++++            +
```

As noted, it is possible to move `hashes` after pinning, but only if you pin it into a heap-allocated box. So we can advise users how to do that.

<a name="example-2" />

### Example 2: Implementing the `MaybeDone` future

The [pinned places][] post included an example future called `MaybeDone`. I'm going to implement that same future in the system I describe here. There are some comments in the example comparing it to the [version from the pinned places post](https://without.boats/blog/pinned-places/#bringing-it-together).

```rust
enum MaybeDone<F: Future> {
    //         ---------
    //         I'm assuming we are in Rust.Next, and so the default
    //         bounds for `F` do not include `Overwrite`.
    //         In other words, `F: ?Overwrite` is the default
    //         (just as it is with every other trait besides `Sized`).
    
    Polling(F),
    //      -
    //      We don't need to declare `pinned F`.
    
    Done(Option<F::Output>),
}

impl<F: Future> MaybeDone<F> {
    fn maybe_poll(self: Pin<&mut Self>, cx: &mut Context<'_>) {
        //        --------------------
        //        I'm not bothering with the `&pinned mut self`
        //        sugar here, though certainly we could still
        //        add it.
        if let MaybeDone::Polling(fut) = self {
            //                    ---
            //       Just as in the original example,
            //       we are able to project from `Pin<&mut Self>`
            //       to a `Pin<&mut F>`.
            //
            //       The key is that we can safely project
            //       from an owner of type `Pin<&mut Self>`
            //       to its field of type `Pin<&mut F>`
            //       so long as the owner type `Self: !Overwrite`
            //       (which is the default for structs in Rust.Next).
            if let Poll::Ready(res) = fut.poll(cx) {
                *self = MaybeDone::Done(Some(res));
            }
        }
    }

    fn is_done(&self) -> bool {
        matches!(self, &MaybeDone::Done(_))
    }

    fn take_output(&mut self) -> Option<F::Output> {
        //         ---------
        //   In pinned places, this method had to be
        //   `&pinned mut self`, but under this design,
        //   it can be a regular `&mut self`.
        //   
        //   That's because `Pin<&mut Self>` becomes
        //   a subtype of `&mut Self`.
        if let MaybeDone::Done(res) = self {
            res.take()
        } else {
            None
        }
    }
}
```

<a name="example-3" />

### Example 3: Implementing the `Join` combinator

Let's complete the journey by implementing a `Join` future:

```rust
struct Join<F1: Future, F2: Future> {
    // These fields do not have to be declared `pinned`:
    fut1: MaybeDone<F1>,
    fut2: MaybeDone<F2>,
}

impl<F1, F2> Future for Join<F1, F2>
where
    F1: Future,
    F2: Future,
{
    type Output = (F1::Output, F2::Output);

    fn poll(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Self::Output> {
        //  --------------------
        // Again, I've dropped the sugar here.
        
        // This looks just the same as in the
        // "Pinned Places" example. This again
        // leans on the ability to project
        // from a `Pin<&mut Self>` owner so long as
        // `Self: !Overwrite` (the default for structs
        // in Rust.Next).
        self.fut1.maybe_poll(cx);
        self.fut2.maybe_poll(cx);
        
        if self.fut1.is_done() && self.fut2.is_done() {
            // This code looks the same as it did with pinned places,
            // but there is an important difference. `take_output`
            // is now an `&mut self` method, not a `Pin<&mut Self>`
            // method. This demonstrates that we can also get
            // a regular `&mut` reference to our fields.
            let res1 = self.fut1.take_output().unwrap();
            let res2 = self.fut2.take_output().unwrap();
            Poll::Ready((res1, res2))
        } else {
            Poll::Pending
        }
    }
}
```

## How I think about pin

OK, now that I've lured you in with code examples, let me drive you away by diving into the details of `Pin`. I'm going to cover the way that I think about `Pin`. It is similar to but different from how `Pin` is presented in the [pinned places][] post -- in particular, I prefer to think about *places that pin their values* and not *pinned places*. In any case, `Pin` is surprisingly subtle, and I recommend that if you want to go deeper, you read boat's [history of `Pin` post][pinhistory] and/or [the stdlib documentation for `Pin`][`Pin`].

[pinhistory]: https://without.boats/blog/pin/
[`Pin`]: https://doc.rust-lang.org/std/pin/struct.Pin.html

### The `Pin<P>`  type is a modifier on the pointer `P`

The `Pin<P>` type is unusual in Rust. It **looks** similar to a "smart pointer" type, like `Arc<T>`, but it functions differently. `Pin<P>` is not a pointer, it is a **modifier** on another pointer, so

* a `Pin<&T>` represents a **pinned reference,**
* a `Pin<&mut T>` represents a **pinned mutable reference,**
* a `Pin<Box<T>>` represents a **pinned box,**

and so forth.

You can think of a `Pin<P>` type as being a pointer of type `P` that refers to a **place** (Rust jargon for a location in memory that stores a value) **whose value `v` has been pinned**. A pinned value `v` can never be moved to another place in memory. Moreover, `v` must be dropped before its place can be reassigned to another value.

### Pinning is part of the "lifecycle" of a place

The way I think about, every place in memory has a lifecycle:

```mermaid
flowchart TD
Uninitialized 
Initialized
Pinned

Uninitialized --
    p = v where v: T
--> Initialized

Initialized -- 
    move out, drop, or forget
--> Uninitialized

Initialized --
    pin value v in p
    (only possible when T is !Unpin)
--> Pinned

Pinned --
    drop value
--> Uninitialized

Pinned --
    move out or forget
--> UB

Uninitialized --
    free the place
--> Freed

UB[💥 Undefined behavior 💥]
```

When first allocated, a place `p` is **uninitialized** -- that is, `p` has no value at all.

An uninitialized place can be **freed**. This corresponds to e.g. popping a stack frame or invoking `free`.

`p` may at some point become **initialized** by an assignment like `p = v`. At that point, there are three ways to transition back to uninitialized:

* The value `v` could be moved somewhere else, e.g. by moving it somewhere else, like `let p2 = p`. At that point, `p` goes back to being uninitialized.
* The value `v` can be *forgotten*, with `std::mem::forget(p)`. At this point, no destructor runs, but `p` goes back to being considered uninitialized.
* The value `v` can be *dropped*, which occurs when the place `p` goes out of scope. At this point, the destructor runs, and `p` goes back to being considered uninitialized.

Alternatively, the value `v` can be **pinned in place**:

* At this point, `v` cannot be moved again, and the only way for `p` to be reused is for `v` to be dropped. 

Once a value is pinned, moving or forgetting the value is **not** allowed. These actions are "undefined behavior", and safe Rust must not permit them to occur.

#### A digression on forgetting vs other ways to leak

As most folks know, Rust does not guarantee that destructors run. If you have a value `v` whose destructor never runs, we say that value is *leaked*. There are however two ways to leak a value, and they are quite different in their impact:

* Option A: Forgetting. Using `std::mem::forget`, you can *forget* the value `v`. The place `p` that was storing that value will go from *initialized* to *uninitialized*, at which point the place `p` can be freed.
    * Forgetting a value is **undefined behavior** if that value has been pinned, however!
* Option B: Leak the place. When you leak a place, it just stays in the initialized or pinned state forever, so its value is never dropped. This can happen, for example, with a ref-count cycle.
    * This is safe even if the value is pinned!

In retrospect, I wish that Option A did not exist -- I wish that we had not added `std::mem::forget`. We did so as part of working through the impact of ref-count cycles. It seemed equivalent at the time ("the dtor doesn't run anyway, why not make it easy to do") but I think this diagram shows why it adding forget made things permanently more complicated for relatively little gain.[^useful] Oh well! Can't win 'em all.

[^useful]: I will say, I use `std::mem::forget` quite regularly, but mostly to make up for a shortcoming in `Drop`. I would like it if `Drop` had a separate method, `fn drop_on_unwind(&mut self)`, and we invoked that method when unwinding. Most of the time, it would be the same as regular drop, but in some cases it's useful to have cleanup logic that only runs in the case of unwinding.

### Values of types implementing `Unpin` cannot be pinned

There is one subtle aspect here: not all values can be pinned. If a type `T` implements `Unpin`, then values of type `T` cannot be pinned. When you have a pinned reference to them, they can still squirm out from under you via `swap` or other techniques. Another way to say the same thing is to say that *values can only be pinned if their type is `!Unpin`* ("does not implement `Unpin`").

Types that are `!Unpin` can be called *address sensitive*, meaning that once they pinned, there can be pointers to the internals of that value that will be invalidated if the address changes. Types that implement `Unpin` would therefore be *address insensitive*. Traditionally, all Rust types have been address insensitive, and therefore `Unpin` is an auto trait, implemented by most types by default.

### `Pin<&mut T>` is really a "maybe pinned" reference

Looking at the state machine as I describe it here, we can see that possessing a `Pin<&mut T>` isn't really a *pinned* mutable reference, in the sense that it doesn't always refer to a place that is pinning its value. If `T: Unpin`, then it's just a regular reference. But if `T: !Unpin`, then a pinned reference guarantees that the value it refers to is pinned in place.

This fits with the name `Unpin`, which I believe was meant to convey that idea that, even if you have a pinned reference to a value of type `T: Unpin`, that value can become unpinned. I've heard the metaphor of "if `T: Unpin`, you can left out the pin, swap in a different value, and put the pin back".

## Pin picked a peck of pickled pain

Everyone agrees that `Pin` is confusing and a pain to use. But what makes it such a pain? 

If you are attempting to **author** a Pin-based API, there are two primary problems:

1. `Pin<&mut Self>` methods can't make use of regular `&mut self` methods.
2. `Pin<&mut Self>` methods can't access fields by default. Crates like [pin-project-lite][] make this easier but still require learning obscure concepts like [structural pinning][sp].

[pin-project-lite]: https://crates.io/crates/pin-project-lite
[sp]: https://doc.rust-lang.org/std/pin/index.html#projections-and-structural-pinning

If you attempting to **consume** a Pin-based API, the primary annoyance is that getting a pinned reference is hard. You can't just call `Pin<&mut Self>` methods normally, you have to remember to use `Box::pin` or `pin!` first. (We saw this in [Example 1](#example-1) from this post.)

## My proposal in a nutshell

This post is focused on a proposal with two parts:

1. Making `Pin`-based APIs easier to *author* by replacing the `Unpin` trait with `Overwrite`.
2. Making `Pin`-based APIs easier to *call* by integrating pinning into the borrow checker.

I'm going to walk through those in turn.


## Making `Pin`-based APIs easier to author

### `Overwrite` as the better `Unpin`

The first part of my proposalis a change I call `s/Unpin/Overwrite/`. The idea is to introduce `Overwrite` and then change the "place lifecycle" to reference `Overwrite` instead of `Unpin`:


```mermaid
flowchart TD
Uninitialized 
Initialized
Pinned

Uninitialized --
    p = v where v: T
--> Initialized

Initialized -- 
    move out, drop, or forget
--> Uninitialized

Initialized --
    pin value v in p
    (only possible when<br>T is 👉<b><i>!Overwrite</i></b>👈)
--> Pinned

Pinned --
    drop value
--> Uninitialized

Pinned --
    move out or forget
--> UB

Uninitialized --
    free the place
--> Freed

UB[💥 Undefined behavior 💥]
```

For `s/Unpin/Overwrite/` to work well, we have to make all `!Unpin` types also be `!Overwrite`. This is not, strictly speaking, backwards compatible, since today `!Unpin` types (like all types) can be overwritten and swapped. I think eventually we want *every* type to be `!Overwrite` by default, but I don't think we can change that default in a general way without an edition. But for `!Unpin` types *in particular* I suspect we can get away with it, because `!Unpin` types are pretty rare, and the simplification we get from doing so is pretty large. (And, as I argued in the previous post, [there is no loss of expressiveness](https://smallcultfollowing.com/babysteps/blog/2024/09/26/overwrite-trait/#subtle-overwrite-is-not-infectious); code today that overwrites or swaps `!Unpin` values can be locally rewritten.)

### Why swaps are bad without `s/Unpin/Overwrite/`

Today, `Pin<&mut T>` cannot be converted into an `&mut T` reference unless `T: Unpin`.[^SharedRef] This because it would allow safe Rust code to create Undefined Behavior by swapping the referent of the `&mut T` reference and hence moving the pinned value. By requiring that `T: Unpin`, the `DerefMut` impl is effectively limiting itself to references that are not, in fact, in the "pinned" state, but just in the "initialized" state.

[^SharedRef]: In contrast, a `Pin<&mut T>` reference can be safely converted into an `&T` reference, as evidenced by [Pin's `Deref` impl](https://doc.rust-lang.org/std/pin/struct.Pin.html#impl-Deref-for-Pin%3CPtr%3E). This is because, even if `T: !Unpin`, a `&T` reference cannot do anything that is invalid for a pinned value. You can't swap the underlying value or read from it.

#### As a result, `Pin<&mut T>` and `&mut T` methods don't interoperate today

This leads directly to our first two pain points. To start, from a `Pin<&mut Self>` method, you can only invoke `&self` methods (via the `Deref` impl) or other `Pin<&mut Self>` methods. This schism separates out the "regular" methods of a type from its pinned methods; it also means that methods doing field assignments don't compile:

```rust
fn increment_field(self: Pin<&mut Self>) {
    self.field = self.field + 1;
}
```

This errors because compiling a field assignment requires a `DerefMut` impl and `Pin<&mut Self>` doesn't have one.

#### With `s/Unpin/Overwrite/`, `Pin<&mut Self>` is a subtype of `&mut self`

`s/Unpin/Overwrite/` allows us to implement `DerefMut` for *all* pinned types. This is because, unlike `Unpin`, `Overwrite` affects how `&mut` works, and hence `&mut T` would preserve the pinned state for the place it references. Consider the two possibilities for the value of type `T` referred to by the `&mut T`:

* If `T: Overwrite`, then the value is not pinnable, and so the place cannot be in the pinned state.
* If `T: !Overwrite`, the value could be pinned, but we also cannot overwrite or swap it, and so pinning is preserved.

This implies that `Pin<&mut T>` is in fact a generalized version of `&mut T`. Every `&'a mut T` keeps the value pinned for the duration of its lifetime `'a`, but a `Pin<&mut T>` ensures the value stays pinned for the lifetime of the underlying storage.

If we have a `DerefMut` impl, then `Pin<&mut Self>` methods can freely call `&mut self` methods. Big win!

#### Today you must categorize fields as "structurally pinned" or not

The other pain point today with `Pin` is that we have no native support for "pin projection"[^projection]. That is, you cannot safely go from a `Pin<&mut Self>` reference to a `Pin<&mut F>` method that referring to some field `self.f` without relying on unsafe code. 

[^projection]: Projection is the wonky PL term for "accessing a field". It's never made much sense to me, but I don't have a better term to use, so I'm sticking with it.

The most common practice today is to use a custom crate like [pin-project-lite][]. Even then, you also have to make a choice for each field between whether you want to be able to get a `Pin<&mut F>` reference or a normal `&mut F` reference. Fields for which you can get a pinned reference are called [structurally pinned][sp] and the criteria for which one you should use is rather subtle. Ultimately this choice is required because `Pin<&mut F>` and `&mut F` don't play nicely together.

#### Pin projection is safe from any `!Overwrite` type

With `s/Unpin/Overwrite/`, we can scrap the idea of structural pinning. Instead, if we have a field owner `self: Pin<&mut Self>`, pinned projection is allowed so long as `Self: !Overwrite`. That is, if `Self: !Overwrite`, then I can *always* get a `Pin<&mut F>` reference to some field `self.f` of type `F`. How is that possible?

Actually, the full explanation relies on borrow checker extensions I haven't introduced yet. But let's see how far we get without them, so that we can see the gap that the borrow checker has to close.

Assume we are creating a `Pin<&'a mut F>` reference `r` to some field `self.f`, where `self: Pin<&mut Self>`:

* We are creating a `Pin<&'a mut F>` reference to the value in `self.f`:
    * If `F: Overwrite`, then the value is not pinnable, so this is equivalent to an ordinary `&mut F` and we have nothing to prove.
    * Else, if `F: !Overwrite`, then we have to show that the value in `self.f` will not move for the remainder of its lifetime.
        * Pin projection from ``*self` is only valid if `Self: !Overwrite` and `self: Pin<&'b mut Self>`, so we know that the value in `*self` is pinned for the remainder of its lifetime by induction.
        * We have to show then that the value `v_f` in `self.f` will never be moved until the end of its lifetime.

There are three ways to move a value out of `self.f`:

* You can assign a new value to `self.f`, like `self.f = ...`.
    * This will run the destructor, ending the lifetime of the value `v_f`.
* You can create a mutable reference `r = &mut self.f` and then...
    * assign a new value to `*r`: but that will be an error because `F: !Overwrite`.
    * swap the value in `*r` with another: but that will be an error because `F: !Overwrite`.

QED. =)

## Making `Pin`-based APIs easier to call

Today, getting a `Pin<&mut>` requires using the `pin!` macro, going through `Box::pin`, or some similar explicit action. This adds "syntactic salt" to calling a `Pin<&mut Self>` some other abstraction rooted in unsafe (e.g., `Box::pin`). There is no built-in way to safely create a pinned reference. This is fine but introduces ergonomic hurdles

We want to make calling a `Pin<&mut Self>` method as easy as calling an `&mut self` method. To do this, we need to extra the compiler's notion of "auto-ref" to include the option of "auto-pin-ref":

```rust
// Instead of this:
let future: Pin<&mut impl Future> = pin!(async { ... });
future.poll(cx);

// We would do this:
let mut future: impl Future = async { ... };
future.poll(cx); // <-- Wowee!
```

Just as a typical method call like `vec.len()` expands to `Vec::len(&vec)`, the compiler would be expanding `future.poll(cx)` to something like so:

```rust
Future::poll(&pinned mut future, cx)
//           ^^^^^^^^^^^ but what, what's this?
```

This expansion though includes a new piece of syntax that doesn't exist today, the `&pinned mut` operation. (I'm lifting this syntax from boats' [pinned places](https://without.boats/blog/pinned-places/) proposal.)

Whereas `&mut var` results in an `&mut T` reference (assuming `var: T`), `&pinned mut var` borrow would result in a `Pin<&mut T>`. It would also make the borrow checker consider the value in `future` to be *pinned*. That means that it is illegal to move out from `var`. The pinned state continues indefinitely until `var` goes out of scope or is overwritten by an assignment like `var = ...` (which drops the heretofore pinned value). This is a fairly straightforward extension to the borrow checker's existing logic.

### New syntax not strictly required

It's worth noting that we don't actually **need** the `&pinned mut` syntax (which means we don't need the `pinned` keyword). We could make it so that the only way to get the compiler to do a pinned borrow is via auto-ref. We could even add a silly trait to make it explicit, like so:

```rust
trait Pinned {
    fn pinned(self: Pin<&mut Self>) -> Pin<&mut Self>;
}

impl<T: ?Sized> Pinned for T {
    fn pinned(self: Pin<&mut T>) -> Pin<&mut T> {
        self
    }
}
```

Now you can write `var.pinned()`, which the compiler would desugar to `Pinned::pinned(&rustc#pinned mut var)`. Here I am using `rustc#pinned` to denote an "internal keyword" that users can't type.[^khash]

[^khash]: We have a syntax `k#foo` for explicitly referred to a keyword `foo`. It is meant to be used only for keywords that will be added in future Rust editions. However, I sometimes think it'd be neat to internal-ish keywords (like `k#pinned`) that are used in desugaring but rarely need to be typed explicitly; you would still be *able* to write `k#pinned` if for whatever reason you *wanted* to. And of course we could later opt to stabilize it as `pinned` (no prefix required) in a future edition.

## Frequently asked questions

### So...there's a lot here. What's the key takeaways?

The shortest version of this post I can manage is[^llm]

* Pinning fits smoothly into Rust if we make two changes:
    * Limit the ability to swap types by default, making `Pin<&mut T>` a subtype of `&mut T` and enabling uniform pin projection.
    * Integrate pinning in the auto-ref rules and the borrow checker.

[^llm]: I tried asking ChatGPT to summarize the post but, when I pasted in my post, it replied, "The message you submitted was too long, please reload the conversation and submit something shorter." Dang ChatGPT, that's rude! Gemini at least [gave it the old college try](https://g.co/gemini/share/bdc1e35d4805). Score one for Google. Plus, it called my post "thought-provoking!" Aww, I'm blushing!

### Why do you only mention swaps? Doesn't `Overwrite` affect other things?

Indeed the `Overwrite` trait as I defined it is overkill for pinning. The more precise, we might imagine two special traits that affect what we can do with the referent an `&mut` reference:

```rust
trait DropWhileBorrowed { }
trait SwapWhileBorrowed: DropWhileBorrowed { }
```

Given a reference `r: &mut T`:

* Overwriting its referent `*r` with a new value would require `T: DropWhileBorrowed`;
* Swapping the referent `*r` with another value would require `T: SwapWhileBorrowed`.

Today, every type is `SwapWhileBorrowed`. What I argued in the previous post is that we should make the default be that user-defined types implement **neither** of these two traits (over an ediiton, etc etc). Instead, you could opt-in to both of them at once by implementing `Overwrite`.

But we could get all the pin benefits by making a weaker change. Instead of having types opt out from both traits by default, they could only opt out of `SwapWhileBorrowed`, but continue to implement `DropWhileBorrowed`. This is enough to make pinning work smoothly. To see why, recall the [pinning state diagram](#pinning-is-part-of-the-lifecycle-of-a-place): dropping the value in `*r` (permitted by `DropWhileBorrowed`) will exit the "pinned" state and return to the "uninitialized" state. This is valid. Swapping, in contrast, is UB.

### Why then did you propose opting out from both overwrites *and* swaps?

Opting out of overwrites (i.e., making the default be *neither* `DropWhileBorrowed` *nor* `SwapWhileBorrowed`) gives us the additional benefit of truly immutable fields. This will make cross-function borrows less of an issue, as I described in my previous post, and make some other things (e.g., variance) less relevant. Moreover, I don't think overwriting an entire reference like `*r` is that common, versus accessing individual fields. And in the cases where people *do* do it, it is [easy to make a dummy struct with a single field, and then overwrite `r.value` instead of `*r`](https://smallcultfollowing.com/babysteps/blog/2024/09/26/overwrite-trait/#subtle-overwrite-is-not-infectious). To me, therefore, distinguishing between `DropWhileBorrowed` and `SwapWhileBorrowed` doesn't obviously carry its weight.

### Can you come up with a more *semantic* name for `Overwrite`?

All the trait names I've given so far (`Overwrite`, `DropWhileBorrowed`, `SwapWhileBorrowed`) answer the question of "what operation does this trait allow". That's pretty common for traits (e.g., `Clone` or, for that matter, `Unpin`) but it is sometimes useful to think instead about "what kinds of types should implement this trait" (or not implement it, as the case may be).

My current favorite "semantic style name" is `Mobile`, which corresponds to implementing `SwapWhileBorrowed`. A *mobile* type is one that, while borrowed, can move to a new place. This name doesn't convey that it's also ok to *drop* the value, but that follows, since if you can swap the value to a new place, you can presumably drop that new place.

I don't have a "semantic" name for `DropWhileBorrowed`. As I said, I'm hard pressed to characterize the type that would want to implement `DropWhileBorrowed` but not `SwapWhileBorrowed`.

### What do `DropWhileBorrowed` and `SwapWhileBorrowed` have in common?

Together these traits guarantee that, as the owner of some local variable `let mut lv`, if I create a mutable reference `r = &mut v` that refers to the current value in `lv`, then once `r` is no longer in use, the variable `lv` will still have the same value. When you think about it, that's actually a pretty reasonable guarantee, and one that holds on for almost every method.

Let's use an analogy. Suppose I own a house and I lease it out to someone else to use. I expect that they will make changes on the inside, such as hanging up a new picture. But I don't expect them to tear down the house and build a new one on the same lot. I also don't expect them to drive up a flatbed truck, load my house onto it, and move it somewhere else (while proving me with a new one in return). In Rust today, a reference `r: &mut T` reference allows all of these things:

* Mutating a field like `r.count += 1` corresponds to *hanging up a picture*. The values inside `r` change, but `r` still refers to the same conceptual value.
* Overwriting `*r = t` with a new value `t` is like tearing down the house and building a new one. The original value that was in `r` no longer exists.
* Swapping `*r` with some other reference `*r2` is like moving my house somewhere else and putting a new house in its place.

### There's a lot of subtle reasoning in this post. Are you sure this is correct?

I am pretty sure! But not 100%. I'm definitely scared that people will point out some obvious flaw in my reasoning. But of course, if there's a flaw I want to know. To help people analyze, let me recap the two subtle arguments that I made in this post and recap the reasoning.

**Lemma.** Given some local variable `lv: T` where `T: !Overwrite` mutably borrowed by a reference `r: &'a mut T`, the value in `lv` cannot be dropped, moved, or forgotten for the lifetime `'a`.

During `'a`, the variable `lv` cannot be accessed directly (per the borrow checker's usual rules). Therefore, any drops/moves/forgets must take place to `*r`:

* Because `T: !Overwrite`, it is not possible to overwrite or swap `*r` with a new value; it is only legal to mutate individual fields. Therefore the value cannot be dropped or moved.
* Forgetting a value (via `std::mem::forget`) requires ownership and is not accesible while `lv` is borrowed.

**Theorem A.** If we replace `T: Unpin` and `T: Overwrite`, then `Pin<&mut T>` is a safe subtype of `&mut T`.

The argument proceeds by cases:

* If `T: Overwrite`, then `Pin<&mut T>` does not refer to a pinned value, and hence it is semantically equivalent to `&mut T`.
* If `T: !Overwrite`, then `Pin<&mut T>` does refer to a pinned value, so we must show that the pinning guarantee cannot be disturbed by the `&mut T`. By our lemma, the `&mut T` cannot move or forget the pinned value, which is the only way to disturb the pinning guarantee.

**Theorem B.** Given some field owner `o: O` where `O: !Overwrite` with a field `f: F`, it is safe to pin-project from `Pin<&mut O>` to a `Pin<&mut F>` reference referring to `o.f`.

The argument proceeds by cases:

* If `F: Overwrite`, then `Pin<&mut F>` is equivalent to `&mut F`. We showed in Theorem A that `Pin<&mut O>` could be upcast to `&mut O` and it is possible to create an `&mut F` from `&mut O`, so this must be safe.
* If `F: !Overwrite`, then `Pin<&mut F>` refers to a pinned value found in `o.f`. The lemma tells us that the value in `o.f` will not be disturbed for the duration of the borrow.

### What part of this post are you most proud of?

Geez, I'm *so* glad you asked! Such a thoughtful question. To be honest, the part of this post that I am happiest with is the state diagram for places, which I've found very useful in helping me to understand `Pin`:

```mermaid
flowchart TD
Uninitialized 
Initialized
Pinned

Uninitialized --
    `p = v` where `v: T`
--> Initialized

Initialized -- 
    move out, drop, or forget
--> Uninitialized

Initialized --
    pin value `v` in `p`
    (only possible when `T` is `!Unpin`)
--> Pinned

Pinned --
    drop value
--> Uninitialized

Pinned --
    move out or forget
--> UB

Uninitialized --
    free the place
--> Freed

UB[💥 Undefined behavior 💥]
```

Obviously this question was just an excuse to reproduce it again. Some of the key insights that it helped me to crystallize:

* A value that is `Unpin` cannot be pinned:
    * And hence `Pin<&mut Self>` really means "reference to a maybe-pinned value" (a value that is *pinned if it can be*).
* Forgetting a value is very different from leaking the place that value is stored:
    * In both cases, the value's `Drop` never runs, but only one of them can lead to a "freed place".

In thinking through the stuff I wrote in this post, I've found it very useful to go back to this diagram and trace through it with my finger.

### Is this backwards compatible?

Maybe? The question does not have a simple answer. I will address in a future blog post in this series. Let me say a few points here though:

First, the `s/Unpin/Overwrite/` proposal is not backwards compatible as I described. It would mean for example that all futures returned by `async fn` are no longer `Overwrite`. It is quite possible we simply can't get away with it.

That's not fatal, but it makes things more annoying. It would mean there exist types that are `!Unpin` but which can be overwritten. This in turn means that `Pin<&mut Self>` is not a subtype of `&mut Self` for *all* types. Pinned mutable references would be a subtype for *almost* all types, but not those that are `!Unpin && Overwrite`.

Second, a naive, conservative transition would definitely be rough. My current thinking is that, in older editions, we add `T: Overwrite` bounds by default on type parameters `T` and, when you have a `T: SomeTrait` bound, we would expand that to include a `Overwrite` bound on associated types in `SomeTrait`, like `T: SomeTrait<AssocType: Overwrite>`. When you move to a newer edition I think we would just **not** add those bounds. This is kind of a mess, though, because if you call code from an older edition, you are still going to need those bounds to be present.

That all sounds painful enough that I think we might have to do something smarter, where we don't *always* add `Overwrite` bounds, but instead use some kind of inference in older editions to avoid it most of the time.

# Conclusion

My takeaway from authoring this post is that something like `Overwrite` has the potential to turn `Pin` from wizard level Rust into mere "advanced Rust", somewhat akin to knowing the borrow checker really well. If we had no backwards compatibility constraints to work with, it seems clear that this would be a better design than `Unpin` as it is today.

Of course, we *do* have backwards compatibility constraints, so the real question is how we can make the transition. I don't know the answer yet! I'm planning on thinking more deeply about it (and talking to folks) once this post is out. My hope was first to make the case for the value of `Overwrite` (and to be sure my reasoning is sound) before I invest too much into thinking how we can make the transition.

Assuming we can make the transition, I'm wondering two things. First, is `Overwrite` the right name? Second, should we take the time to re-evaluate the default bounds on generic types in a more complete way? For example, to truly have a nice async story, and for myraid other reasons, I think we need [must move types](https://smallcultfollowing.com/babysteps/blog/2023/03/16/must-move-types/). How does that fit in?
