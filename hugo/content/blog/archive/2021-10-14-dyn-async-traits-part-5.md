---
date: "2021-10-14T00:00:00Z"
slug: dyn-async-traits-part-5
title: Dyn async traits, part 5
---

If you’re willing to use nightly, you can already model async functions in traits by using GATs and impl Trait — this is what the [Embassy] async runtime does, and it’s also what the [real-async-trait] crate does. One shortcoming, though, is that your trait doesn’t support dynamic dispatch. In the previous posts of this series, I have been exploring some of the reasons for that limitation, and what kind of primitive capabilities need to be exposed in the language to overcome it. My thought was that we could try to stabilize those primitive capabilities with the plan of enabling experimentation. I am still in favor of this plan, but I realized something yesterday: **using procedural macros, you can ALMOST do this experimentation today!** Unfortunately, it doesn't quite work owing to some relatively obscure rules in the Rust type system (perhaps some clever readers will find a workaround; that said, these are rules I have wanted to change for a while).

[Embassy]: https://github.com/embassy-rs/embassy
[real-async-trait]: https://crates.io/crates/real-async-trait

**Just to be crystal clear:** Nothing in this post is intended to describe an “ideal end state” for async functions in traits. I still want to get to the point where one can write `async fn` in a trait without any further annotation and have the trait be “fully capable” (support both static dispatch and dyn mode while adhering to the tenets of zero-cost abstractions[^zca]). But there are some significant questions there, and to find the best answers for those questions, we need to enable more exploration, which is the point of this post.

[^zca]: In the words of Bjarne Stroustroup, “What you don’t use, you don’t pay for. And further: What you do use, you couldn’t hand code any better.”

### Code is on github

The code covered in this blog post has been prototyped and is [available on github](https://github.com/nikomatsakis/ergo-dyn/blob/main/examples/async-iter-manual-desugar.rs). See the caveat at the end of the post, though!

### Design goal

To see what I mean, let’s return to my favorite trait, `AsyncIter`:

```rust
trait AsyncIter {
    type Item;
    async fn next(&mut self) -> Option<Self::Item>;
}
```

The post is going to lay out how we can transform a trait declaration like the one above into a series of declarations that achieve the following:

* We can use it as a generic bound (`fn foo<T: AsyncIter>()`), in which case we get static dispatch, full auto trait support, and all the other goodies that normally come with generic bounds in Rust.
* Given a `T: AsyncIter`, we can coerce it into some form of `DynAsyncIter` that uses virtual dispatch. In this case, the type doesn’t reveal the specific `T` or the specific types of the futures.
	* I wrote `DynAsyncIter`, and not `dyn AsyncIter` on purpose — we are going to create our own type that acts *like* a `dyn` type, but which manages the adaptations needed for async.
	* For simplicity, let’s assume we want to box the resulting futures. Part of the point of this design though is that it leaves room for us to generate whatever sort of wrapping types we want.

You could write the code I’m showing here by hand, but the better route would be to package it up as a kind of decorator (e.g., `#[async_trait_v2]`[^name]).

[^name]: Egads, I need a snazzier name than that!

### The basics: trait with a GAT

The first step is to transform the trait to have a GAT and a regular `fn`, in the way that we’ve seen many times:

```rust
trait AsyncIter {
    type Item;

    type Next<‘me>: Future<Output = Option<Self::Item>>
    where
        Self: ‘me;

    fn next(&mut self) -> Self::Next<‘_>;
}
```

### Next: define a “DynAsyncIter” struct

The next step is to manage the virtual dispatch (dyn) version of the trait. To do this, we are going to “roll our own” object by creating a struct `DynAsyncIter`. This struct plays the role of a `Box<dyn AsyncIter>` trait object. Instances of the struct can be created by calling `DynAsyncIter::from` with some specific iterator type; the `DynAsyncIter` type implements the `AsyncIter` trait, so once you have one you can just call `next` as usual:

```rust
let the_iter: DynAsyncIter<u32> = DynAsyncIter::from(some_iterator);
process_items(&mut the_iter);

async fn sum_items(iter: &mut impl AsyncIter<Item = u32>) -> u32 {
    let mut s = 0;
    while let Some(v) = the_iter.next().await {
        s += v;
    }
    s
}
```

### Struct definition

Let’s look at how this `DynAsyncIter` struct is defined. First, we are going to “roll our own” object by creating a struct `DynAsyncIter`. This struct is going to model a `Box<dyn AsyncIter>` trait object; it will have one generic parameter for every ordinary associated type declared in the trait (not including the GATs we introduced for async fn return types). The struct itself has two fields, the data pointer (a box, but in raw form) and a vtable. We don’t know the type of the underlying value, so we’ll use `ErasedData` for that:

```rust
type ErasedData = ();

pub struct DynAsyncIter<Item> {
    data: *mut ErasedData,
    vtable: &’static DynAsyncIterVtable<Item>,
}
```

For the vtable, we will make a struct that contains a `fn` for each of the methods in the trait. Unlike the builtin vtables, we will modify the return type of these functions to be a boxed future:

```rust
struct DynAsyncIterVtable<Item> {
    drop_fn: unsafe fn(*mut ErasedData),
    next_fn: unsafe fn(&mut *mut ErasedData) -> Box<dyn Future<Output = Option<Item>> + ‘_>,
}
```

### Implementing the AsyncIter trait

Next, we can implement the `AsyncIter` trait for the `DynAsyncIter` type. For each of the new GATs we introduced, we simply use a boxed future type. For the method bodies, we extract the function pointer from the vtable and call it:

```rust
impl<Item> AsyncIter for DynAsyncIter<Item> {
    type Item = Item;

    type Next<‘me> = Box<dyn Future<Output = Option<Item>> + ‘me>;

    fn next(&mut self) -> Self::Next<‘_> {
        let next_fn = self.vtable.next_fn;
        unsafe { next_fn(&mut self.data) }
   }
}
```

The unsafe keyword here is asserting that the safety conditions of `next_fn` are met. We’ll cover that in more detail later, but in short those conditions are:

* The vtable corresponds to some erased type `T: AsyncIter`…
* …and each instance of `*mut ErasedData` points to a valid `Box<T>` for that type.

### Dropping the object

Speaking of Drop, we do need to implement that as well. It too will call through the vtable:

```rust
impl Drop for DynAsyncIter {
    fn drop(&mut self) {
        let drop_fn = self.vtable.drop_fn;
        unsafe { drop_fn(self.data); }
    }
}
```

We need to call through the vtable because we don’t know what kind of data we have, so we can’t know how to drop it correctly.

### Creating an instance of `DynAsyncIter`

To create one of these `DynAsyncIter` objects, we can implement the `From` trait. This allocates a box, coerces it into a raw pointer, and then combines that with the vtable:

```rust
impl<Item, T> From<T> for DynAsyncIter<Item>
where
    T: AsyncIter<Item = Item>,
{
    fn from(value: T) -> DynAsyncIter {
        let boxed_value = Box::new(value);
        DynAsyncIter {
            data: Box::into_raw(boxed_value) as *mut (),
            vtable: dyn_async_iter_vtable::<T>(), // we’ll cover this fn later
        }
    }
}
```

### Creating the vtable shims

Now we come to the most interesting part: how do we create the vtable for one of these objects? Recall that our vtable was a struct like so:

```rust
struct DynAsyncIterVtable<Item> {
    drop_fn: unsafe fn(*mut ErasedData),
    next_fn: unsafe fn(&mut *mut ErasedData) -> Box<dyn Future<Output = Option<Item>> + ‘_>,
}
```

We are going to need to create the values for each of those fields. In an ordinary `dyn`, these would be pointers directly to the methods from the `impl`, but for us they are “wrapper functions” around the core trait functions. The role of these wrappers is to introduce some minor coercions, such as allocating a box for the resulting future, as well as to adapt from the “erased data” to the true type:

```rust
// Safety conditions:
//
// The `*mut ErasedData` is actually the raw form of a `Box<T>` 
// that is valid for ‘a.
unsafe fn next_wrapper<‘a, T>(
    this: &’a mut *mut ErasedData,
) -> Box<dyn Future<Output = Option<T::Item>> + ‘a
where
    T: AsyncIter,
{
    let unerased_this: &mut Box<T> = unsafe { &mut *(this as *mut Box<T>) };
    let future: T::Next<‘_> = <T as AsyncIter>::next(unerased_this);
    Box::new(future)
}
```

We’ll also need a “drop” wrapper:

```rust
// Safety conditions:
//
// The `*mut ErasedData` is actually the raw form of a `Box<T>` 
// and this function is being given ownership of it.
fn drop_wrapper<T>(
    this: *mut ErasedData,
)
where
    T: AsyncIter,
{
    let unerased_this = Box::from_raw(this as *mut T);
    drop(unerased_this); // Execute destructor as normal
}
```

### Constructing the vtable

Now that we’ve defined the wrappers, we can construct the vtable itself. Recall that the `From` impl called a function `dyn_async_iter_vtable::<T>`. That function looks like this:

```rust
fn dyn_async_iter_vtable<T>() -> &’static DynAsyncIterVtable<T::Item>
where
    T: AsyncIter,
{
    const {
        &DynAsyncIterVtable {
            drop_fn: drop_wrapper::<T>,
            next_fn: next_wrapper::<T>,
        }
    }
}
```

This constructs a struct with the two function pointers: this struct only contains static data, so we are allowed to return a `&’static` reference to it.

Done!

### And now the caveat, and a plea for help

Unfortunately, this setup doesn't work quite how I described it. There are two problems:

* `const` functions and expressions stil lhave a lot of limitations, especially around generics like `T`, and I couldn't get them to work;
* Because of the rules introduced by [RFC 1214], the `&’static DynAsyncIterVtable<T::Item>` type requires that `T::Item: 'static`, which may not be true here. This condition perhaps shouldn't be necessary, but the compiler currently enforces it.

[RFC 1214]: https://rust-lang.github.io/rfcs/1214-projections-lifetimes-and-wf.html

I wound up hacking something terrible that erased the `T::Item` type into uses and used `Box::leak` to get a `&'static` reference, just to prove out the concept. I'm almost embarassed to [show the code](https://github.com/nikomatsakis/ergo-dyn/blob/3503770e08177a6d59e202f88cb7227863331685/examples/async-iter-manual-desugar.rs#L107-L118), but there it is. 

Anyway, I know people have done some pretty clever tricks, so I'd be curious to know if I'm missing something and there *is* a way to build this vtable on Rust today. Regardless, it seems like extending `const` and a few other things to support this case is a relatively light lift, if we wanted to do that.

### Conclusion

This blog post presented a way to implement the dyn dispatch ideas I've been talking using only features that currently exist and are generally en route to stabilization. That's exiting to me, because it means that we can start to do measurements and experimentation. For example, I would really like to know the performance impact of transitiong from `async-trait` to a scheme that uses a combination of static dispatch and boxed dynamic dispatch as described here. I would also like to explore whether there are other ways to wrap futures (e.g., with task-local allocators or other smart pointers) that might perform better. This would help inform what kind of capabilities we ultimately need.

Looking beyond async, I'm interested in tinkering with different models for `dyn` in general. As an obvious example, the "always boxed" version I implemented here has some runtime cost (an allocation!) and isn't applicable in all environments, but it would be far more ergonomic. Trait objects would be Sized and would transparently work in far more contexts. We can also prototype different kinds of vtable adaptation.