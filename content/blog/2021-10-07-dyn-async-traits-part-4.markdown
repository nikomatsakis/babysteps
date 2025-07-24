---
layout: post
title: Dyn async traits, part 4
date: 2021-10-07T12:33:00-0400
series:
- "Dyn async traits"
---

In the previous post, I talked about how we could write our own `impl Iterator for dyn Iterator` by adding a few primitives. In this post, I want to look at what it would take to extend that to an async iterator trait. As before, I am interested in exploring the “core capabilities” that would be needed to make everything work.

## Start somewhere: Just assume we want Box

In the [first post of this series][post1], we talked about how invoking an async fn through a dyn trait should to have the return type of that async fn be a `Box<dyn Future>` — but only when calling it through a dyn type, not all the time.

[post1]: {{< baseurl >}}/blog/2021/09/30/dyn-async-traits-part-1/#conclusion-ideally-we-want-box-when-using-dyn-but-not-otherwise

Actually, that’s a slight simplification: `Box<dyn Future>` is certainly one type we could use, but there are other types you might want:

* `Box<dyn Future + Send>`, to indicate that the future is sendable across threads;
* Some other wrapper type besides `Box`.

To keep things simple, I’m just going to look at `Box<dyn Future>` in this post. We’ll come back to some of those extensions later.

## Background: Running example

Let’s start by recalling the `AsyncIter` trait:

```rust
trait AsyncIter {
    type Item;

    async fn next(&mut self) -> Option<Self::Item>;
}
```

Remember that when we “desugared” this `async fn`, we introduced a new (generic) associated type for the future returned by `next`, called `Next` here:

```rust
trait AsyncIter {
    type Item;

    type Next<'me>: Future<Output = Self::Item> + 'me;
    fn next(&mut self) -> Self::Next<'_>;
}
```

We were working with a struct `SleepyRange` that implements `AsyncIter`:

```rust
struct SleepyRange { … }
impl AsyncIter for SleepyRange {
    type Item = u32;
    …
}
```

## Background: Associated types in a static vs dyn context

Using an associated type is great in a static context, because it means that when you call `sleepy_range.next()`, we are able to resolve the returned future type precisely. This helps us to allocate exactly as much stack as is needed and so forth.

But in a dynamic context, i.e. if you have `some_iter: Box<dyn AsyncIter>` and you invoke `some_iter.next()`, that’s a liability. The whole point of using `dyn` is that we don’t know exactly what implementation of `AsyncIter::next` we are invoking, so we can’t know exactly what future type is returned. Really, we just want to get back a `Box<dyn Future<Output = Option<u32>>>` — or something very similar.

## How could we have a trait that boxes futures, but only when using dyn?

If we want the trait to only box futures when using `dyn`, there are two things we need.

**First, we need to change the `impl AsyncIter for dyn AsyncIter`.** In the compiler today, it generates an impl which is generic over the value of every associated type. But we want an impl that is generic over the value of the `Item` type, but which *specifies* the value of the `Next` type to be `Box<dyn Future>`. This way, we are effectively saying that “when you call the `next` method on a `dyn AsyncIter`, you always get a `Box<dyn Future>` back” (but when you call the `next` method on a specific type, such as a `SleepyRange`, you would get back a different type — the actual future type, not a boxed version). If we were to write that dyn impl in Rust code, it might look something like this:

```rust
impl<I> AsyncIter for dyn AsyncIter<Item = I> {
    type Item = I;

    type Next<'me> = Box<dyn Future<Output = Option<I>> + ‘me>;
    fn next(&mut self) -> Self::Next<'_> {
        /* see below */
    }
}
```

The body of the `next` function is code that extracts the function pointer from the vtable and calls it. Something like this, relying on the APIs from [RFC 2580] along with the function `associated_fn` that I sketched in the previous post:

```rust
fn next(&mut self) -> Self::Next<‘_> {
    type RuntimeType = ();
    let data_pointer: *mut RuntimeType = self as *mut ();
    let vtable: DynMetadata = ptr::metadata(self);
    let fn_pointer: fn(*mut RuntimeType) -> Box<dyn Future<Output = Option<I>> + ‘_> =
        associated_fn::<AsyncIter::next>();
    fn_pointer(data)
}
```

This is still the code we want. However, there is a slight wrinkle.

## Constructing the vtable: Async functions need a shim to return a `Box`

In the `next` method above, the type of the function pointer that we extracted from the vtable was the following:

```rust
fn(*mut RuntimeType) -> Box<dyn Future<Output = Option<I>> + ‘_>
```

However, the signature of the function in the impl is different! It doesn’t return a `Box`, it returns an `impl Future`! Somehow we have to bridge this gap. What we need is a kind of “shim function”, something like this:

```rust
fn next_box_shim<T: AsyncIter>(this: &mut T) -> Box<dyn Future<Output = Option<I>> + ‘_> {
    let future: impl Future<Output = Option<I>> = AsyncIter::next(this);
    Box::new(future)
}
```

Now the vtable for `SleepyRange` can store `next_box_shim::<SleepyRange>` instead of storing `<SleepyRange as AsyncIter>::next` directly.

## Extending the `AssociatedFn` trait

In my previous post, I sketched out the idea of an `AssociatedFn` trait that had an associated type `FnPtr`. If we wanted to make the construction of this sort of shim automated, we would want to change that from an associated type into its own trait. I’m imagining something like this:

```rust
trait AssociatedFn { }
trait Reify<F>: AssociatedFn {
    fn reify(self) -> F; 
}
```

where `A: Reify<F>` indicates that the associated function `A` can be “reified” (made into a function pointer) for a function type `F`. The compiler could implement this trait for the direct mapping where possible, but also for various kinds of shims and ABI transformations. For example, the `AsyncIter::next` method might implement`Reify<fn(*mut ()) -> Box<dyn Future<..>>>` to allow a “boxing shim” to be constructed and so forth.

## Other sorts of shims

There are other sorts of limitations around dyn traits that could be overcome with judicious use of shims and tweaked vtables, at least in some cases. As an example, consider this trait:

```rust
pub trait Append {
    fn append(&mut self, values: impl Iterator<Item = u32>);
}
```

This trait is not traditionally dyn-safe because the `append` function is generic and requires monomorphization for each kind of iterator — therefore, we don’t know which version to put in the vtable for `Append`, since we don’t yet know the types of iterators it will be applied to! But what if we just put *one* version, the case where the iterator type is `&mut dyn Iterator<Item = u32>`? We could then tweak the `impl Append for dyn Append` to create this `&mut dyn Iterator` and call the function from the vtable:

```rust
impl Append for dyn Append {
    fn append(&mut self, values: impl Iterator<Item = u32>) {
        let values_dyn: &mut dyn Iterator<Item = u32> = &values;
        type RuntimeType = ();
        let data_pointer: *mut RuntimeType = self as *mut ();
        let vtable: DynMetadata = ptr::metadata(self);
        let f = associated_fn::<Append::append>(vtable);
        f(data_pointer, values_dyn);
    }
}
```

## Conclusion

So where does this leave us? The core building blocks for “dyn async traits” seem to be:

* The ability to customize the contents of the vtable that gets generated for a trait. 
	* For example, async fns need shim functions that box the output.
* The ability to customize the dispatch logic (`impl Foo for dyn Foo`).
* The ability to customize associated types like `Next` to be a `Box<dyn>`:
	* This requires the ability to extract the vtable, as given by [RFC 2580].
	* It also requires the ability to extract functions from the vtable (not presently supported).

I said at the outset that I was going to assume, for the purposes of this post, that we wanted to return a `Box<dyn>`, and I have.  It seems possible to extend these core capabilities to other sorts of return types (such as other smart pointers), but it’s not entirely trivial; we’d have to define what kinds of shims the compiler can generate. 

I haven’t really thought very hard about how we might allow users to specify each of those building blocks, though I sketched out some possibilities. At this point, I’m mostly trying to explore the possibilities of what kinds of capabilities may be useful or necessary to expose. 

