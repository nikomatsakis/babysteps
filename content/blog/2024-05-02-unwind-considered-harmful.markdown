---
title: "Unwind considered harmful?"
date: 2024-05-02 12:39 -0400
---

I’ve been thinking a wild thought lately: we should deprecate `panic=unwind`. Most production users I know either already run with `panic=abort` or use unwinding in a very limited fashion, basically just to run to *cleanup*, not to truly *recover*. Removing unwinding from most case meanwhile has a number of benefits, allowing us to extend the type system in interesting and potentially very impactful ways. It also removes a common source of subtle bugs. Note that I am not saying we should remove unwinding entirely: that’s not an option, both because of stability and because of Rust’s mission to “deeply integrate” with all kinds of languages and systems.

## Unwinding means all code must be able to stop at every point

Unwinding puts a “non-local burden” on the language. The fundamental premise of unwinding is that it should be possible for all code to just **stop** execution at any point (or at least at any function call) and then be restarted. **But this is not always possible**. Sometimes code disturbs invariants which must be restored before execution can continue in a reasonable way.

## The impact of unwinding was supposed to be contained

In Graydon’s initial sketches for Rust’s design, he was very suspicious of unwinding.[^signal] Unwinding introduces implicit control flow that is difficult to reason about. Worse, this control flow doesn’t surface during “normal execution”, it only shows up when things go wrong — this can tend to pile up, making a bad situation worse.

[^signal]: For a time, we were exploring an alternative approach to panics called *signals* that didn't use unwinding at all -- the idea was that, for each error condition, you would expose a hook point (a "signal") that users could customize to control what to do in the case of error. This proved a bit too unfamiliar and kind of a pain in practice, and we wound up backing away from it. Today's [panic hook](https://doc.rust-lang.org/std/panic/fn.set_hook.html) is sort of a simpler version of that (it doesn't support in-place recovery, but it does enable in-place cleanup).

The initial idea was that unwinding would be allowed, but it would always unwinding the entire active thread. Moreover, since in very early Rust threads couldn’t share state at all (it was more like Erlang), that limited the damage that a thread could do. It was reasonable to assume that programs could recover.

## But it escaped its bounds

Over time, both of the invariants that limited unwinding’s scope proved untenable. Most importantly, we added shared-mutability with types like `Mutex`. This was necessary to cover the full range of use cases Rust aims to cover, but it meant that it was now possible for threads to leave data in a disturbed state. We added “lock poisoning” to account for that, but it’s an ergonomic annoyance and an imperfect solution, and so libraries like `parking_lot` have simply removed it. 

We also added `catch_unwind`, allowing recovery within a thread. This was meant to be used in libraries like `rayon` that were simulating many logical threads with one OS thread, but it of course opened the door to “catching” exceptions in other scenarios. We added the idea of `UnwindSafe` to try and discourage abuse, but (in a familiar theme) it’s an ergonomic annoyance and an imperfect solution, and so many folks would prefer to just remove it.

## Unwinding increases binary size and reduces optimization potential

Unwinding is supposed to be a “zero-cost abstraction”, but it’s not really. To start, it requires inserting “landing pads” — basically, the code that will execute when unwinding occurs — which can take up quite a large amount of space in your binary. Folks like Fuchsia have measured binary size improvements of up to 10% by removing unwinding. Second, the need to account for unwinding limits optimizations, because the compiler has to account for more control-flow paths. I don’t have a number for how high of an impact this is, but it’s clearly not zero.

## Unwinding puts limits on the borrow checker

Accounting for unwinding also requires the borrow checker to be more conservative. Consider for example the function `std::mem::swap`. It’d be nice if one could write this in safe code:

```rust
fn swap<T>(
    a: &mut T,
    b: &mut T,
) {
    let tmp = *a;
    *a = *b;
    *b = tmp;
}
```

This code won’t compile today, because `let tmp = *a` requires moving out of `*a`, and `a` is an `&mut` reference. That would leave the reference in an “incomplete” state, so we don’t allow it. But is that constraint truly needed? After all, the reference is going to be restored a few lines below…?

The reason the borrow checker does not accept code like the above is due to unwinding. In general, if you move out of an `&mut`, you leave a hole behind that **MUST** be filled before the function returns. In the function above, it is in fact guaranteed that the hole will be filled before `swap` returns. But in general there is a very narrow range of code that can safely execute, since any function call (and many other operations besides) can initiate a `panic!`. And if unwinding occurred, then the code that restores the `&mut` value would never execute. For this reason, we deemed it not worth the complexity to support moving out of `&mut` references.

## Unwinding prevents code from running to completion

If the only cost of unwinding was moving out of `&mut`and inflated binary sizes, I would think that it’s probably worth it to keep it. But over time it’s become clear to me that this is just one special case of a more general challenge with unwinding, which is that functions simply cannot rely on running to completion. This creates challenges in a number of areas.

### Unwinding makes unsafe code really hard to write

If you are writing unsafe code, you have to be very careful to account for possible unwinding. And it can occur in a lot of places! Some of them are obvious, such as when the user gives you a closure and you call it. Others are less obvious, such as when you call a trait method like `x.clone()` where `x` has some unknown type `T: Clone`. Others are downright obscure, such as when you execute `vec[i] = new_value` and `vec` is a `Vec<T>` for some unknown type `T` — that last one will run the destructor on `vec[i]` , which can panic, and hence can unwind (at least until [RFC #3288] is accepted). When developing Rayon, I found I could not feasibly track all the places that unwinding could occur, and thus gave up and just added [code to abort if unwinding occurs when I don’t expect it][abort].

[abort]: https://github.com/rayon-rs/rayon/blob/0e8d45dd3e5b62a9ef86fdc754a9b9e3b4f048a8/rayon-core/src/unwind.rs#L24

[RFC #3288]: https://github.com/rust-lang/rfcs/pull/3288

### Unwinding makes [Must Move types][] untenable

In a previous blog post I wrote about the idea of [must move types][]. I am not sure if this idea is worth it on balance (although I think it might be, it addresses an awful lot of scenarios) but I think it will not be workable with unwinding. And the reason is the same as everything else: the point of a “must move” type is that it must be moved before the fn ends. This effectively means there is some kind of action you must take. But unwinding assumes you can stop the function at any point, so you can never guarantee that this action gets taken (at least, not in a practical sense, in principle you could setup destructors to take the action, but it would be unworkable I think).

[Must Move types]:  https://smallcultfollowing.com/babysteps/blog/2023/03/16/must-move-types/

## Unwinding is of course useful

I’ve been dunking on unwinding, but it is of course useful (although I *suspect* less broadly than is commonly believed). The most obvious use case is recovering in an “event-driven” sort of process, like a webserver or perhaps a GUI. We’ve all been to websites that dump a stack trace on our screen. Unwinding is one way that you could implement this sort of recovery in Rust. It’s not, however, the *only* way. We could look into constructs that leverage process-based recovery, for example. And of course unwinding-based recovery is a bit risky, if there is shared state. Plus, in practice, a good many things that become exceptions in Java are `Result`-return values in Rust.

For me, the key thing here is that virtually every network service I know of ships either with panic=abort or without really leveraging unwinding to *recover*, just to take cleanup actions and then exit. This could be done with panic=abort and exit handlers.

One other place that uses unwinding is the salsa framework, which uses it to abort cancelled operations in IDEs. It’s useful there because all the code is side-effect free, so we really can unwinding without any impact. But we could always find another solution to the problem.

## Unwinding is in fact required…but only in narrow places

I don’t really think Rust should remove support for unwinding, of course. For one thing, there is backwards compatibility to consider. But for another, I think that Rust ought to have the goal that it ultimately supports any low-level thing you might want to do. There are C++ systems that use exceptions, and Rust ought to interoperate with them. But I don’t think that means the default across all of Rust should be unwinding: it’s more like “something you need in a narrow part of your codebase so you can convert to `Result`”.

## Conclusion

I think the argument for deprecating unwinding boils down to this: unwinding purports to make cheap recovery tenable, but it’s not really reliable in the face of shared state. Meanwhile, it puts limits on what we can do in the language, ultimately decreasing reliability (because we can’t guarantee cleanup is done) and ease of use (borrow checker is stricter, APIs that would require cleanup can’t be written). 

How could we deprecate it, though? It would basically become part of the ABI, much like C vs C-unwind. It’d be possible to opt-in on a finer-grained basis. In functions that are guaranteed not to have unwinding, the borrow checker could be more permissive, and must-move types could be supported. 

I’m definitely tempted to sketch out what deprecating unwinding might look like in more detail. I’d be curious to hear from folks that rely on unwinding to better understand where it is useful— and if we can find alternatives that meet the need in a more narrowly tailored way!
