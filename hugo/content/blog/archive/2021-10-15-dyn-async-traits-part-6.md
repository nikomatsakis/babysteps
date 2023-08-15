---
date: "2021-10-15T00:00:00Z"
slug: dyn-async-traits-part-6
title: Dyn async traits, part 6
---

A quick update to my last post: first, a better way to do what I was trying to do, and second, a sketch of the crate I'd like to see for experimental purposes.

## An easier way to roll our own boxed dyn traits

In the previous post I covered how you could create vtables and pair the up with a data pointer to kind of "roll your own dyn". After I published the post, though, dtolnay sent me [this Rust playground link](https://play.rust-lang.org/?version=nightly&mode=debug&edition=2018&gist=adba43d6e056337cd8a297624a296219) to show me a much better approach, one based on the [erased-serde] crate. The idea is that instead of make a "vtable struct" with a bunch of fn pointers, we create a "shadow trait" that reflects the contents of that vtable:

[erased-serde]: https://crates.io/crates/erased-serde

```rust
// erased trait:
trait ErasedAsyncIter {
    type Item;
    fn next<'me>(&'me mut self) -> Pin<Box<dyn Future<Output = Option<Self::Item>> + 'me>>;
}
```

Then the `DynAsyncIter` struct can just be a boxed form of this trait:

```rust
pub struct DynAsyncIter<'data, Item> {
    pointer: Box<dyn ErasedAsyncIter<Item = Item> + 'data>,
}
```

We define the "shim functions" by implementing `ErasedAsyncIter` for all `T: AsyncIter`:

```rust
impl<T> ErasedAsyncIter for T
where
    T: AsyncIter,
{
    type Item = T::Item;
    fn next<'me>(&'me mut self) -> Pin<Box<dyn Future<Output = Option<Self::Item>> + 'me>> {
        // This code allocates a box for the result
        // and coerces into a dyn:
        Box::pin(AsyncIter::next(self))
    }
}
```

And finally we can implement the `AsyncIter` trait for the dynamic type:

```rust
impl<'data, Item> AsyncIter for DynAsyncIter<'data, Item> {
    type Item = Item;

    type Next<'me>
    where
        Item: 'me,
        'data: 'me,
    = Pin<Box<dyn Future<Output = Option<Item>> + 'me>>;

    fn next(&mut self) -> Self::Next<'_> {
        self.pointer.next()
    }
}
```

Yay, it all works, and without *any* unsafe code!

## What I'd like to see

This "convert to dyn" approach isn't really specific to async (as erased-serde shows). I'd like to see a decorator that applies it to any trait. I imagine something like:

```rust
// Generates the `DynAsyncIter` type shown above:
#[derive_dyn(DynAsyncIter)]
trait AsyncIter {
    type Item;
    async fn next(&mut self) -> Option<Self::Item>;
}
```

But this ought to work with any `-> impl Trait` return type, too, so long as `Trait` is dyn safe and implemented for `Box<T>`. So something like this:

```rust
// Generates the `DynAsyncIter` type shown above:
#[derive_dyn(DynSillyIterTools)]
trait SillyIterTools: Iterator {
    // Iterate over the iter in pairs of two items.
    fn pair_up(&mut self) -> impl Iterator<(Self::Item, Self::Item)>;
}
```

would generate an erased trait that returns a `Box<dyn Iterator<(...)>>`. Similarly, you could do a trick with taking any `impl Foo` and passing in a `Box<dyn Foo>`, so you can support impl Trait in argument position.

Even without impl trait, `derive_dyn` would create a more ergonomic dyn to play with.

I don't really see this as a "long term solution", but I would be interested to play with it.

## Comments?

I've created a [thread on internals](https://internals.rust-lang.org/t/blog-series-dyn-async-in-traits/15449) if you'd like to comment on this post, or others in this series.