---
layout: post
title: To async trait or just to trait
date: 2023-03-12T19:33:00-0400
series:
- "Dyn async traits"
---

One interesting question about async fn in traits is whether or not we should label the *trait itself* as async. Until recently, I didn’t see any need for that. But as we discussed the question of how to enable “maybe async” code, we realized that there would be some advantages to distinguishing “async traits” (which could contain async functions) from sync traits (which could not). However, as I’ve thought about the idea more, I’m more and more of the mind that we should not take this step — at least not now. I wanted to write a blog post divin g into the considerations as I see them now.

## What is being proposed?

The specific proposal I am discussing is to require that traits which include async functions are declared as async traits…

```rust
// The "async trait" (vs just "trait") would be required
// to have an "async fn" (vs just a "fn").
async trait HttpEngine {
    async fn fetch(&mut self, url: Url) -> Vec<u8>;
}
```

…and when you reference them, you use the `async` keyword as well…

```rust
fn load_data<H>(h: &mut impl async HttpEngine, urls: &[Url]) {
    //                       ----- just writing `impl HttpEngine`
    //                             would be an error
    …
}
```

This would be a change from the support implemented in nightly today, where any trait can have async functions.

## Why have “async traits” vs “normal” traits?

When authoring an async application, you’re going to define traits like `HttpEngine` that inherently involve async operations. In that case, having to write `async trait` seems like pure overhead. So why would we ever want it? 

The answer is that not all traits are like `HttpEngine`. We can call `HttpEngine` an “always async” trait — it will always involve an async operation. **But a lot of traits are “maybe async” — they sometimes involve async operations and sometimes not.** In fact, we can probably break these down further: you have traits like `Read`, which involve I/O but have a sync and async equivalent, and then you have traits like `Iterator`, which are orthogonal from I/O.

Particularly for traits like `Iterator`, the current trajectory will result in two nearly identical traits in the stdlib: `Iterator` and `AsyncIterator`. These will be mostly the same apart from `AsyncIterator` have an async `next` function, and perhaps some more combinators. It’s not the end of the world, but it’s also not ideal, particularly when you consider that we likely want more “modes”, like a `const` Iterator, a “sendable” iterator, perhaps a fallible iterator (one that returns results), etc. This is of course the problem often referred to as the “color problem”, from Bob Nystron's well-known [“What color is your function?”][wcf] blog post, and it’s precisely what the [“keyword generics” initiative][kg] is looking to solve.

[wcf]: https://journal.stuffwithstuff.com/2015/02/01/what-color-is-your-function/
[kg]: https://blog.rust-lang.org/inside-rust/2022/07/27/keyword-generics.html

## Requiring an async keyword ensures consistency between “maybe” and “always” async traits…

It’s not really clear what a full solution to the “color problem” looks like. But whatever it is, it’s going to involve having traits with multiple modes. So instead of `Iterator` and `AsyncIterator`, we’ll have the base definition of `Iterator` and then a way to derive an async version, `async Iterator`. We can then call an `Iterator` a “maybe async” trait, because it might be sync but it might be async. We might declare a “maybe async” trait using an attribute, like this[^eg]:

[^eg]: I can feel you fixating on the `#[maybe(async)]` syntax. Resist the urge! There is no concrete proposal yet.

```rust
#[maybe(async)]
trait Iterator {
    type Item;

    // Because of the #[maybe(async)] attribute,
    // the async keyword on this function means “if
    // this trait is in async mode, then this is an
    // async function”:
    async fn next(&mut self) -> Option<Self::Item>;
}
```

Now imagine I have a function that reads urls from some kind of input stream. This might be an `async fn` that takes an `impl async Iterator` as argument:

```rust
async fn read_urls(urls: impl async Iterator<Item = Url>) {
    //                        --——- specify async mode
    while let Some(u) = urls.next().await {
        //                          -———- needed because this is an async iterator
        …
    }
}
```

But now let’s say I want to combine this (async) iterator of urls and use an `HttpEngine` (our “always async” trait) to fetch them:

```rust
async fn fetch_urls(
    urls: impl async Iterator<Item = Url>,
    engine: impl HttpEngine,
) {
   while let Some(u) = urls.next().await {
       let data = engine.fetch(u).await;
       …
   }
}
```

There’s nothing wrong with this code, but it might be a bit surprising that I have to write `impl async Iterator` but I just write `impl HttpEngine`, even though both traits involve async functions. I can imagine that it would sometimes be hard to remember which traits are “always async” versus which ones are only “maybe async”.

## …which also means traits can go from “always” to “maybe” async without a major version bump.

There is another tricky bit: imagine that I am authoring a library and I create a “always async” `HttpEngine` trait to start:

```rust
trait HttpEngine {
    async fn fetch(&mut self, url: Url) -> Vec<u8>;
}
```

but then later I want to issue a new version that offers a sync *and* an async version of `HttpEngine`. I can’t add a `#[maybe(async)]` to the trait declaration because, if I do so, then code using `impl HttpEngine` would suddenly be getting the *sync* version of the trait, whereas before they were getting the *async* version.

In other words, unless we force people to declare async traits up front, then changing a trait from “always async” to “maybe async” is a breaking change.

## But writing `async Trait` for traits that are *always* async is annoying…

The points above are solid. But there are some flaws. The most obvious is that having to write `async` for every trait that uses an async function is likely to be pretty tedious. I can easily imagine that people writing async applications are going to use a lot of “always async” traits and I imagine that, each time they write `impl async HttpEngine`, they will think to themselves, “How many times do I have to tell the compiler this is async already?! We get it, we get it!!”

Put another way, the consistency argument (“how will I remember which traits need to be declared async?”) may not hold water in practice. I can imagine that for many applications the only “maybe async” traits are the core abstractions coming from libraries, like `Iterator`, and most of the other code is just “always async”. So actually it’s not that hard to remember which is which.

## …and it’s not clear that traits will go from “always” to “maybe” async anyway…

But what about semver violations? Well, if my thesis above is correct, then it’s also true that there will be relatively few traits that need to go from “always async” to “maybe async”. Moreover, I imagine most libraries will know up front whether they expect to be sync or not. So maybe it’s not a big deal that this is a breaking change,

## …and trait aliases would give a workaround for “always -> maybe” transitions anyway…

So, maybe it won’t happen in practice, but let’s imagine that we did define an always async `HttpEngine` and then later want to make the trait “maybe async”. Do we absolutely need a new major version of the crate? Not really, there is a workaround. We can define a new “maybe async” trait — let’s call it `HttpFetch` and then redefine `HttpEngine` in terms of `HttpFetch`:

```rust
// This is a trait alias. It’s an unstable feature that I would like to stabilize.
// Even without a trait alias, though, you could do this with a blanket impl.
trait HttpEngine = async HttpFetch;

#[maybe(async)]
trait HttpFetch { … }
```

This obviously isn’t ideal: you wind up with two names for the same underlying trait. Maybe you deprecate the old one. But it’s not the end of the world.

## …and requiring async composes poorly with supertraits and trait aliases…

Actually, that last example brings up an interesting point. To truly ensure consistency, it’s not enough to say that “traits with async functions must be declared async”. We also need to be careful what we permit in trait aliases and supertraits. For example, imagine we have a trait `UrlIterator` that has an `async Iterator` as a supertrait…

```rust
trait UrlIterator: async Iterator<Item = Url> { }
```

…now people could write functions that take a `impl UrlIterator`, but it will still require `await` when you invoke its methods. So we didn’t really achieve *consistency* after all. The same thing would apply with a trait alias like `trait UrlIterator = async Iterator<Item = Url>`. 

It’s possible to imagine a requirement like “to have a supertrait that is async, the trait must be async”, but — to me — that feels non-compositional. I’d like to be able to declare a trait alias `trait A = …` and have the `…` be able to be any sort of trait bounds, whether they’re async or not. It feels funny to have the async propagate out of the `...` and onto the trait alias `A`.

## …and, while this decision is hard to reverse, it can be reversed.

So, let’s say that we were to stabilize the ability to add async functions to any trait. And then later we find that we actually want to have maybe async traits and that we wish we had required people to write `async` explicitly all the time, because consistency and semver. Are we stuck?

Well, not really. There are options here. For example, we might might make it *possible* to write `async` (but not required) and then lint and warn when people don’t. Perhaps in another edition, we would make it mandatory. This is basically what we did with the `dyn` keyword. Then we could declare that making a trait always-async to maybe-async is not considered worthy of a major version, because people’s code that follows the lints and warnings will not be affected. If we had transitioned so that all code in the new edition required an `async` keyword even for “always async” traits, we could let people declare a trait to be “maybe async but only in the new edition”, which would avoid all breakage entirely.

In any case, I don’t really want to do those things. It’d be embarassing and confusing to stabilize SAFIT and then decide that “oh, no, you have to declare traits to be async”. I’d rather we just think through the arguments now and make a call. But it’s always good to know that, just in case you’re wrong, you have options.

## My (current) conclusion: YAGNI

So which way to go? I think the question hinges a lot on how common we expect “maybe async” code to be. My expectation is that, even if we do support it, “maybe async” will be fairly limited. It will mostly apply to (a) code like `Iterator` that is orthogonal from I/O and (b) core I/O primitives like the `Read` trait or the `File` type. If we’re especially successful, then crates like `reqwest` (which currently offers both a sync and async interface) would be able to unify those into one. But application code I expect to largely be written to be either sync or async.

I also think that it’ll be relatively unusual to go from “always async” to “maybe async”. Not impossible, but unusual *enough* that either making a new major version or using the “renaming” trick will be fine.

**For this reason, I lean towards NOT requiring `async trait`, and instead allowing `async fn` to be added to any trait.** I am still hopeful we’ll add “maybe async” traits as well, but I think there won’t be a big problem of “always async” traits needing to change to maybe async. (Clearly we are going to want to go from “never async” to “maybe async”, since there are lots of traits like `Iterator` in the stdlib, but that’s a non-issue.)

The other argument in favor is that it’s closer to what we do today. There are lots of people using `#[async_trait]` and I’ve never heard anyone say “it’s so weird that you can write `T: HttpEngine` and don’t have to write `T: async HttpEngine`”. **At minimum, if we were going to change to requiring the “async” keyword, I would want to give that change some time to bake on nightly before we stabilized it. This could well delay stabilization significantly.**

If, in contrast, you believed that lots of code was going to be “maybe async”, then I think you would probably want the async keyword to be mandatory on traits. After all, since most traits are maybe async anyway, you’re going to need to write it a lot of the time.
