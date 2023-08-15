---
date: "2022-09-21T00:00:00Z"
slug: dyn-async-traits-part-9-callee-site-selection
title: 'Dyn async traits, part 9: call-site selection'
---

After my last post on dyn async traits, some folks pointed out that I was overlooking a seemingly obvious possibility. Why not have the choice of how to manage the future be made at the call site? It's true, I had largely dismissed that alternative, but it's worth consideration. This post is going to explore what it would take to get call-site-based dispatch working, and what the ergonomics might look like. I think it's actually fairly appealing, though it has some limitations.

## If we added support for unsized return values...

The idea is to build on the mechanisms proposed in [RFC 2884]. With that RFC, you would be able to have functions that returned a `dyn Future`:

```rust
fn return_dyn() -> dyn Future<Output = ()> {
    async move { }
}
```

Normally, when you call a function, we can allocate space on the stack to store the return value. But when you call `return_dyn`, we don't know how much space we need at compile time, so we can't do that[^alloca]. This means you can't just write `let x = return_dyn()`. Instead, you have to choose how to allocate that memory. Using the APIs proposed in [RFC 2884], the most common option would be to store it on the heap. A new method, `Box::new_with`, would be added to `Box`; it acts like `new`, but it takes a closure, and the closure can return values of any type, including `dyn` values:

```rust
let result = Box::new_with(|| return_dyn());
// result has type `Box<dyn Future<Output = ()>>`
```

Invoking `new_with` would be ergonomically unpleasant, so we could also add a `.box` operator. Rust has had an unstable `box` operator since forever, this might finally provide enough motivation to make it worth adding:

```rust
let result = return_dyn().box;
// result has type `Box<dyn Future<Output = ()>>`
```

Of course, you wouldn't *have* to use `Box`. Assuming we have sufficient APIs available, people can write their own methods, such as something to do arena allocation...

```rust
let arena = Arena::new();
let result = arena.new_with(|| return_dyn());
```

...or perhaps a hypothetical `maybe_box`, which would use a buffer if that's big enough, and use box otherwise:

```rust
let mut big_buf = [0; 1024];
let result = maybe_box(&mut big_buf, || return_dyn()).await;
```

If we add [postfix macros], then we might even support something like `return_dyn.maybe_box!(&mut big_buf)`, though I'm not sure if the current proposal would support that or not.

[postfix macros]: https://github.com/rust-lang/rfcs/pull/2442

[^alloca]: I can hear you now: "but what about alloca!" I'll get there.

## What are unsized return values?

This idea of returning `dyn Future` is sometimes called "unsized return values", as functions can now return values of "unsized" type (i.e., types who size is not statically known). They've been proposed in [RFC 2884] by [Olivier Faure], and I believe there were some earlier RFCs as well. The `.box` operator, meanwhile, has been a part of "nightly Rust" since approximately forever, though its currently written in prefix form, i.e., `box foo`[^prefix-box].

[Olivier Faure]: https://github.com/PoignardAzur

The primary motivation for both unsized-return-values and `.box` has historically been efficiency: they permit in-place initialization in cases where it is not possible today. For example, if I write `Box::new([0; 1024])` today, I am technically allocating a `[0; 1024]` buffer on the stack and then copying it into the box: 

```rust
// First evaluate the argument, creating the temporary:
let temp: [u8; 1024] = ...;

// Then invoke `Box::new`, which allocates a Box...
let box: *const T = allocate_memory();

// ...and copies the memory in.
std::ptr::write(box, temp);
```

The optimizer may be able to fix that, but it's not trivial. If you look at the order of operations, it requires making the allocation happen *before* the arguments are allocated. LLVM considers calls to known allocators to be "side-effect free", but promoting them is still risky, since it means that more memory is allocated earlier, which can lead to memory exhaustion. The point isn't so much to look at exactly what optimizations LLVM will do in practice, so much as to say that it is not trivial to optimize away the temporary: it requires some thoughtful heuristics.

[RFC 2884]: https://github.com/rust-lang/rfcs/pull/2884

[^prefix-box]: The `box foo` operator supported by the compiler has no current path to stabilization. There were earlier plans (see [RFC 809](https://github.com/rust-lang/rfcs/pull/809) and [RFC 1228](https://rust-lang.github.io/rfcs/1228-placement-left-arrow.html)), but we ultimately abandoned those efforts. Part of the problem, in fact, was that the precedence of `box foo` made for bad ergonomics: `foo.box` works much better.


## How would unsized return values work?

This merits a blog post of its own, and I won't dive into details. For our purposes here, the key point is that somehow when the callee goes to return its final value, it can use whatever strategy the caller prefers to get a return point, and write the return value directly in there. [RFC 2884] proposes one solution based on generators, but I would want to spend time thinking through all the alternatives before we settled on something.

## Using dynamic return types for async fn in traits

So, the question is, can we use `dyn` return types to help with async function in traits? Continuing with my example from my previous post, if you have an `AsyncIterator` trait...

```rust
trait AsyncIterator {
    type Item;
    
    async fn next(&mut self) -> Option<Self::Item>;
}
```

...the idea is that calling `next` on a `dyn AsyncIterator` type would yield `dyn Future<Output = Option<Self::Item>>`. Therefore, one could write code like this:

```rust
fn use_dyn(di: &mut dyn AsyncIterator) {
    di.next().box.await;
    //       ^^^^
}
```

The expression `di.next()` by itself yields a `dyn Future`. This type is not sized and so it won't compile on its own. Adding `.box` produces a `Box<dyn AsyncIterator>`, which you can then await.[^pin]

[^pin]: If you try to await a `Box<dyn Future>` today, you [get an error that it needs to be pinned](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=b981b7eafee70cc39f70176f6b135023). I think we can solve that by implementing `IntoFuture` for `Box<dyn Future>` and having that convert it to `Pin<Box<dyn Future>>`.

Compared to the `Boxing` adapter I discussed before, this is relatively straightforward to explain. I'm not entirely sure which is more convenient to use in practice: it depends how many `dyn` values you create and how many methods you call on them. Certainly you can work around the problem of having to write `.box` at each call-site via wrapper types or helper methods that do it for you.

## Complication: `dyn AsyncIterator` does not implement `AsyncIterator`

There is one complication. Today in Rust, every `dyn Trait` type also implements `Trait`. But can `dyn AsyncIterator` implement `AsyncIterator`? In fact, it cannot! The problem is that the `AsyncIterator` trait defines `next` as returning `impl Future<..>`, which is actually shorthand for `impl Future<..> + Sized`, but we said that `next` would return `dyn Future<..>`, which is `?Sized`. So the `dyn AsyncIterator` type doesn't meet the bounds the trait requires. Hmm.

## But...does `dyn AsyncIterator` have to implement `AsyncIterator`?

There is no "hard and fixed" reason that `dyn Trait` types have to implement `Trait`, and there are a few good reasons *not* to do it. The alternative to dyn safety is a design like this: you can *always* create a `dyn Trait` value for any `Trait`, but you may not be able to use all of its members. For example, given a `dyn Iterator`, you could call `next`, but you couldn't call generic methods like `map`. In fact, we've kind of got this design in practice, thanks to the [`where Self: Sized` hack](https://rust-lang.github.io/rfcs/0255-object-safety.html#adding-a-where-clause) that lets us exclude methods from being used on `dyn` values.

Why did we adopt object safety in the first place? If you look back at [RFC 255], the primary motivation for this rule was ergonomics: clearer rules and better error messages. Although I argued for [RFC 255] at the time, I don't think these motivations have aged so well. Right now, for example, if you have a trait with a generic method, you get an error when you try to create a `dyn Trait` value, telling you that you cannot create a `dyn Trait` from a trait with a generic method. But it may well be clearer to get an error at the point where you to call that generic method telling you that you cannot call generic methods through `dyn Trait`.

Another motivation for having `dyn Trait` implement `Trait` was that one could write a generic function with `T: Trait` and have it work equally well for object types. That capability *is* useful, but because you have to write `T: ?Sized` to take advantage of it, it only really works if you plan carefully. In practice what I've found works much better is to implement `Trait` to `&dyn Trait`.

[RFC 255]: https://rust-lang.github.io/rfcs/0255-object-safety.html

## What would it mean to remove the rule that `dyn AsyncIterator: AsyncIterator`?

I think the new system would be something like this...

* You can always[^almost] create a `dyn Foo` value. The `dyn Foo` type would define inherent methods based on the trait `Foo` that use dynamic dispatch, but with some changes:
    * Async functions and other methods defined with `-> impl Trait` return `-> dyn Trait` instead.
    * Generic methods, methods referencing `Self`, and other such cases are excluded. These cannot be handled with virtual dispatch.
* If `Foo` is [object safe](https://doc.rust-lang.org/reference/items/traits.html#object-safety) using today's rules, `dyn Foo: Foo` holds. Otherwise, it does not.[^MIR]
    * On a related but orthogonal note, I would like to make a `dyn` keyword required to declare dyn safety.

[^MIR]: Internally in the compiler, this would require modifying the definition of MIR to make "dyn dispatch" more first-class.
[^almost]: Or almost always? I may be overlooking some edge cases.

## Implications of removing that rule

This implies that `dyn AsyncIterator` (or any trait with async functions/RPITIT[^rpitit]) will not implement `AsyncIterator`. So if I write this function...

[^rpitit]: Don't know what RPITIT stands for?! "Return position impl trait in traits!" Get with the program!

```rust
fn use_any<I>(x: &mut I)
where
    I: ?Sized + AsyncIterator,
{
    x.next().await
}
```

...I cannot use it with `I = dyn AsyncIterator`. You can see why: it calls `next` and assumes the result is `Sized` (as promised by the trait), so it doesn't add any kind of `.box` directive (and it shouldn't have to).

What you *can* do is implement a wrapper type that encapsulates the boxing:

```rust
struct BoxingAsyncIterator<'i, I> {
    iter: &'i mut dyn AsyncIterator<Item = I>
}

impl<I> AsyncIterator for BoxingAsyncIterator<'i, I> {
    type Item = I;
    
    async fn next(&mut self) -> Option<Self::Item> {
        self.iter.next().box.await
    }
}
```

...and then you can call `use_any(BoxingAsyncIterator::new(ai))`.[^boxing]

[^boxing]: This is basically what the "magical" `Boxing::new` would have done for you in the older proposal.

## Limitation: what if you wanted to do stack allocation?

One of the goals with the [previous proposal] was to allow you to write code that used `dyn AsyncIterator` which worked equally well in std and no-std environments. I would say that goal was partially achieved. The core idea was that the caller would choose the strategy by which the future got allocated, and so it could opt to use inline allocation (and thus be no-std compatible) or use boxing (and thus be simple). 

[previous proposal]: {{ site.baseurl }}/blog/2022/09/18/dyn-async-traits-part-8-the-soul-of-rust/

In this proposal, the call-site has to choose. You might think then that you could just choose to use stack allocation at the call-site and thus be no-std compatible. But how does one choose stack allocation? It's actually quite tricky! Part of the problem is that async stack frames are stored in structs, and thus we cannot support something like `alloca` (at least not for values that will be live across an await, which includes any future that is awaited[^expl]). In fact, even outside of async, using alloca is quite hard! The problem is that a stack is, well, a stack. Ideally, you would do the allocation just before your callee returns, but that's when you know how much memory you need. But at that time, your callee is still using the stack, so your allocation is on the wrong spot.[^ada] I personally think we should just rule out the idea of using alloca to do stack allocation.

[^expl]: [Brief explanation of why async and alloca don't mix here.](https://internals.rust-lang.org/t/blog-series-dyn-async-in-traits-continues/17403/52?u=nikomatsakis)

[^ada]: I was told Ada compiles will allocate the memory at the top of the stack, copy it over to the start of the function's area, and then pop what's left. Theoretically possible!

If we can't use alloca, what can we do? We have a few choices. In the very beginning, I talked about the idea of a `maybe_box` function that would take a buffer and use it only for really large values. That's kind of nifty, but it still relies on a box fallback, so it doesn't really work for no-std.[^abort] Might be a nice alternative to [stackfuture](https://twitter.com/theinedibleholk/status/1557802452069388288) though![^size]

[^abort]: You could imagine a version that aborted the code if the size is wrong, too, which would make it no-std safe, but not in a realiable way (aborts == yuck).

[^size]: Conceivably you could set the size to `size_of(SomeOtherType)` to automatically determine how much space is needed.

You can also achieve inlining by writing wrapper types ([something tmandry and I prototyped some time back][proto]), but the challenge then is that your callee doesn't accept a `&mut dyn AsyncIterator`, it accepts something like `&mut DynAsyncIter`, where `DynAsyncIter` is a struct that you defined to do the wrapping.

[proto]: https://github.com/nikomatsakis/dyner/blob/8086d4a16f68a2216ddff5c03c8c5b3d94ed93a2/src/dyn_async_iter.rs#L4-L6

**All told, I think the answer in reality would be: If you want to be used in a no-std environment, you don't use `dyn` in your public interfaces. Just use `impl AsyncIterator`. You can use hacks like the wrapper types internally if you really want dynamic dispatch.**

## Question: How much room is there for the compiler to get clever?

One other concern I had in thinking about this proposal was that it seemed like it was *overspecified*. That is, the vast majority of call-sites in this proposal will be written with `.box`, which thus specifies that they should allocate a box to store the result. But what about ideas like caching the box across invocations, or "best effort" stack allocation? Where do they fit in? From what I can tell, those optimizations are still possible, so long as the `Box` which would be allocated doesn't escape the function (which was the same condition we had before). 

The way to think of it: by writing `foo().box.await`, the user told us to use the boxing allocator to box the return value of `foo`. But we can then see that this result is passed to await, which takes ownership and later frees it. We can thus decide to substitute a different allocator, perhaps one that reuses the box across invocations, or tries to use stack memory; this is fine so long as we modifed the freeing code to match. Doing this relies on knowing that the allocated value is immediately returned to us and that it never leaves our control.

## Conclusion

To sum up, I think for most users this design would work like so...

* You can use `dyn` with traits that have async functions, but you have to write `.box` every time you call a method.
* You get to use `.box` in other places too, and we gain at least *some* support for unsized return values.[^limit]
* If you want to write code that is sometimes using dyn and sometimes using static dispatch, you'll have to write some awkward wrapper types.[^fornow]
* If you are writing no-std code, use `impl Trait`, not `dyn Trait`; if you must use `dyn`, it'll require wrapper types.

Initially, I dismissed call-site allocation because it violated `dyn Trait: Trait` and it didn't allow code to be written with `dyn` that could work in both std and no-std. But I think that violating `dyn Trait: Trait` may actually be good, and I'm not sure how important that latter constraint truly is. Furthermore, I think that `Boxing::new` and the various "dyn adapters" are probably going to be pretty confusing for users, but writing `.box` on a call-site is relatively easy to explain ("we don't know what future you need, so you have to box it"). So now it seems a lot more appealing to me, and I'm grateful to [Olivier Faure] for bringing it up again.

[^limit]: I say *at least some* because I suspect many details of the more general case would remain unstable until we gain more experience.

[^fornow]: You have to write awkward wrapper types *for now*, anyway. I'm intrigued by ideas about how we could make that more automatic, but I think it's way out of scope here.

One possible extension would be to permit users to specify the type of each returned future in some way. As I was finishing up this post, I saw that [matthieum posted an intriguing idea](https://internals.rust-lang.org/t/blog-series-dyn-async-in-traits-continues/17403/50?u=nikomatsakis) in this direction on the internals thread. In general, I do see a need for some kind of "trait adapters", such that you can take a base trait like `Iterator` and "adapt" it in various ways, e.g. producing a version that uses async methods, or which is const-safe. This has some pretty heavy overlap with the whole [keyword generics](https://blog.yoshuawuyts.com/announcing-the-keyword-generics-initiative/) initiative too. I think it's a good extension to think about, but it wouldn't be part of the "MVP" that we ship first. 

## Thoughts?

Please leave comments in [this internals thread](https://internals.rust-lang.org/t/blog-series-dyn-async-in-traits-continues/17403/40), thanks!

## Appendix A: the `Output` associated type

Here is an interesting thing! The `FnOnce` trait, implemented by all callable things, defines its associated type [`Output`](https://doc.rust-lang.org/std/ops/trait.FnOnce.html#associatedtype.Output) as `Sized`! We have to change this if we want to allow unsized return values. 

In theory, this could be a big backwards compatibility hazard. Code that writes `F::Output` can assume, based on the trait, that the return value is sized -- so if we remove that bound, the code will no longer build!

Fortunately, I think this is ok. We've deliberately restricted the fn types so you can only use them with the `()` notation, e.g., `where F: FnOnce()` or `where F: FnOnce() -> ()`. Both of these forms expand to something which explicitly specifies `Output`, like `F: FnOnce<(), Output = ()>`. What this means is that even if you really generic code...

```rust=
fn foo<F, R>(f: F)
where
    F: FnOnce<Output = R>
{
    let value: F::Output = f();
    ...
}
```

...when you write `F::Output`, that is actually normalized to `R`, and the type `R` has its own (implicit) `Sized` bound. 

(There's was actually a recent unsoundness related to this bound, [closed by this PR](https://github.com/rust-lang/rust/pull/100096), and we [discussed exactly this forwards compatibility question on Zulip.](https://rust-lang.zulipchat.com/#narrow/stream/326866-t-types.2Fnominated/topic/.23100096.3A.20a.20fn.20pointer.20doesn't.20implement.20.60Fn.60.2F.60FnMut.60.2F.60FnOnc.E2.80.A6/near/297797248))

## Footnotes