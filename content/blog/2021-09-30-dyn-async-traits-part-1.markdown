---
layout: post
title: Dyn async traits, part 1
date: 2021-09-30 10:50 -0400
series:
- "Dyn async traits"
---
Over the last few weeks, [Tyler Mandry] and I have been digging hard into what it will take to implement async fn in traits. Per the [new lang team initiative process](https://lang-team.rust-lang.org/initiatives.html), we are collecting our design thoughts in an ever-evolving website, the [async fundamentals initiative](https://rust-lang.github.io/async-fundamentals-initiative/). If you're interested in the area, you should definitely poke around; you may be interested to read about the [MVP](https://rust-lang.github.io/async-fundamentals-initiative/roadmap/mvp.html) that we hope to stabilize first, or the (very much WIP) [evaluation doc](https://rust-lang.github.io/async-fundamentals-initiative/evaluation.html) which covers some of the challenges we are still working out. I am going to be writing a series of blog posts focusing on one particular thing that we have been talking through: the [problem of `dyn` and `async fn`](https://rust-lang.github.io/async-fundamentals-initiative/evaluation/challenges/dyn_traits.html). This first post introduces the problem and the general goal that we are shooting for (but don't yet know the best way to reach).

[Tyler Mandry]: https://github.com/tmandry/

### What we're shooting for

What we want is simple. Imagine this trait, for "async iterators":

```rust
trait AsyncIter {
    type Item;
    async fn next(&mut self) -> Option<Self::Item>;
}
```

We would like you to be able to write a trait like that, and to implement it in the obvious way:

```rust
struct SleepyRange {
    start: u32,
    stop: u32,
}

impl AsyncIter for SleepyRange {
    type Item = u32;
    
    async fn next(&mut self) -> Option<Self::Item> {
        tokio::sleep(1000).await; // just to await something :)
        let s = self.start;
        if s < self.stop {
            self.start = s + 1;
            Some(s)
        } else {
            None
        }
    }
}
```

You should then be able to have a `Box<dyn AsyncIter<Item = u32>>` and use that in exactly the way you would use a `Box<dyn Iterator<Item = u32>>` (but with an `await` after each call to `next`, of course):

```rust
let b: Box<dyn AsyncIter<Item = u32>> = ...;
let i = b.next().await;
```

### Desugaring to an associated type

Consider this running example:

```rust
trait AsyncIter {
    type Item;
    async fn next(&mut self) -> Option<Self::Item>;
}
```

Here, the `next` method will desugar to a fn that returns *some* kind of future; you can think of it like a generic associated type:

```rust
trait AsyncIter {
    type Item;

    type Next<'me>: Future<Output = Self::Item> + 'me;
    fn next(&mut self) -> Self::Next<'_>;
}
```

The corresponding desugaring for the impl would use [type alias impl trait][tait]:


[tait]: https://rust-lang.github.io/impl-trait-initiative/

```rust
struct SleepyRange {
    start: u32,
    stop: u32,
}

// Type alias impl trait:
type SleepyRangeNext<'me> = impl Future<Output = u32> + 'me;

impl AsyncIter for InfinityAndBeyond {
    type Item = u32;
    
    type Next<'me> = SleepyRangeNext<'me>;
    fn next(&mut self) -> SleepyRangeNext<'me> {
        async move {
            tokio::sleep(1000).await;
            let s = self.start;
            ... // as above
        }
    }
}
```

This desugaring works quite well for standard generics (or `impl Trait`). Consider this function:

```rust
async fn process<T>(t: &mut T) -> u32
where
    T: AsyncIter<Item = u32>,
{
    let mut sum = 0;
    while let Some(x) = t.next().await {
        sum += x;
        if sum > 22 {
            break;
        }
    }
    sum
}
```

This code will work quite nicely. For example, when you call `t.next()`, the resulting future will be of type `T::Next`. After monomorphization, the compiler will be able to resolve `<SleepyRange as AsyncIter>::Next` to the `SleepyRangeNext` type, so that the future is known exactly. In fact, crates like [embassy](https://github.com/akiles/embassy) already use this desugaring, albeit manually and only on nightly.

### Associated types don't work for dyn

Unfortunately, this desugaring causes problems when you try to use `dyn` values. Today, when you have `dyn AsyncIter`, you must specify the values for *all* associated types defined in `AsyncIter`. So that means that instead of `dyn AsyncIter<Item = u32>`, you would have to write something like

```rust
for<'me> dyn AsyncIter<
    Item = u32, 
    Next<'me> = SleepyRangeNext<'me>,
>
```

This is clearly a non-starter from an ergonomic perspective, but is has an even more pernicious problem. The whole point of a `dyn` trait is to have a value where we don't know what the underlying type is. But specifying the value of `Next<'me>` as `SleepyRangeNext` means that there is *exactly one impl* that could be in use here. This `dyn` value *must* be a `SleepyRange`, since no other impl has that same future. 

**Conclusion:** For `dyn AsyncIter` to work, the future returned by `next()` must be *independent of the actual impl*. Furthermore, it must have a fixed size. In other words, it needs to be something like `Box<dyn Future<Output = u32>>`.

### How the `async-trait` crate solves this problem

You may have used the [`async-trait`] crate. It resolves this problem by not using an associated type, but instead desugaring to `Box<dyn Future>` types:

[`async-trait`]: https://crates.io/crates/async-trait

```rust=
trait AsyncIter {
    type Item;

    fn next(&mut self) -> Box<dyn Future<Output = Self::Item> + Send + 'me>;
}
```

This has a few disadvantages:

* It forces a `Box` all the time, even when you are using `AsyncIter` with static dispatch.
* The type as given above says that the resulting future *must* be `Send`. For other async fn, we use auto traits to analyze automatically whether the resulting future is send (it is `Send` it if it can be, in other words; we don't declare up front whether it *must* be).

### Conclusion: Ideally we want `Box` when using `dyn`, but not otherwise

So far we've seen:

* If we desugar async fn to an associated type, it works well for generic cases, because we can resolve the future to precisely the right type.
* But it doesn't work for doesn't work well for `dyn` trait, because the rules of Rust require that we specify the value of the associated type exactly. For `dyn` traits, we really want the returned future to be something like `Box<dyn Future>`.
    * Using `Box` does mean a slight performance penalty relative to static dispatch, because we must allocate the future dynamically.

What we would *ideally* want is to only pay the price of `Box` when using `dyn`:

* When you use `AsyncIter` in generic types, you get the desugaring shown above, with no boxing and static dispatch.
* But when you create a `dyn AsyncIter`, the future type becomes `Box<dyn Future<Output = u32>>`.
    * (And perhaps you can choose another "smart pointer" type besides `Box`, but I'll ignore that for now and come back to it later.)

In upcoming posts, I will dig into some of the ways that we might achieve this.
