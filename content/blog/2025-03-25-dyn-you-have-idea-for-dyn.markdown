---
title: "Dyn you have idea for `dyn`?"
date: 2025-03-25T17:19:17Z
series:
- "Dyn async traits"
---

Knock, knock. Who's there? Dyn. Dyn who? Dyn you have ideas for `dyn`? I am generally dissatisfied with how `dyn Trait` in Rust works and, based on conversations I've had, I am pretty sure I'm not alone. And yet I'm also not entirely sure the best fix. Building on my last post, I wanted to spend a bit of time exploring my understanding of the problem. I'm curious to see if others agree with the observations here or have others to add.

## Why do we have `dyn Trait`?

It's worth stepping back and asking why we have `dyn Trait` in the first place. To my mind, there are two good reasons.

### Because sometimes you want to talk about "some value that implements `Trait`"

The most important one is that it is sometimes strictly necessary. If you are, say, building a multithreaded runtime like `rayon` or `tokio`, you are going to need a list of active tasks somewhere, each of which is associated with some closure from user code. You can't build it with an enum because you can't enumerate the set of closures in any one place. You need something like a `Vec<Box<dyn ActiveTask>>`.

### Because sometimes you don't need to so much code

The second reason is to help with compilation time. Rust land tends to lean really heavily on generic types and `impl Trait`. There are good reasons for that: they allow the compiler to generate very efficient code. But the flip side is that they force the compiler to generate a lot of (very efficient) code. Judicious use of `dyn Trait` can collapse a whole set of "almost identical" structs and functions into one.

### These two goals are distinct 

Right now, both of these goals are expressed in Rust via `dyn Trait`, but actually they are quite distinct. For the first, you really want to be able to talk about having a `dyn Trait`. For the second, you might prefer to write the code with generics but compile in a different mode where the specifics of the type involved are erased, much like how the Haskell and Swift compilers work.

## What does "better" look like when you really want a `dyn`?

Now that we have the two goals, let's talk about some of the specific issues I see around `dyn Trait` and what it might mean for `dyn Trait` to be "better". We'll start with the cases where you really *want* a `dyn` value. 

### Observation: you know it's a `dyn`

One interesting thing about this scenario is that, by definition, you are storing a `dyn Trait` explicitly. That is, you are not working with a `T: ?Sized + Trait` where `T` just happens to be `dyn Trait`. This is important because it opens up the design space. We talked about this some in the previous blog post: it means that  You don't need working with this `dyn Trait` to be exactly the same as working with any other `T` that implements `Trait` (in the previous post, we took advantage of this by saying that calling an async function on a `dyn` trait had to be done in a `.box` context).

### Able to avoid the `Box`

For this pattern today you are almost certainly representing your task a `Box<dyn Task>` or (less often) an `Arc<dyn Task>`. Both of these are "wide pointers", consisting of a data pointer and a vtable pointer. The data pointer goes into the heap somewhere.

In practice people often want a "flattened" representation, one that combines a vtable with a fixed amount of space that might, or might not, be a pointer. This is particularly useful to allow the equivalent of `Vec<dyn Task>`. Today implementing this requires unsafe code (the `anyhow::Anyhow` type is an example).

### Able to inline the vtable

Another way to reduce the size of a `Box<dyn Task>` is to store the vtable 'inline' at the front of the value so that a `Box<dyn Task>` is a single pointer. This is what C++ and Java compilers typically do, at least for single inheritance. We didn't take this approach in Rust because Rust allows implementing local traits for foreign types, so it's not possible to enumerate all the methods that belong to a type up-front and put them into a single vtable. Instead, we create custom vtables for each (type, trait) pair.

### Able to work with `self` methods

Right now `dyn` traits cannot have `self` methods. This means for example you cannot have a `Box<dyn FnOnce()>` closure. You can workaround this by using a `Box<Self>` method, but it's annoying:

```rust
trait Thunk {
    fn call(self: Box<Self>);
}

impl<F> Thunk for F
where
    F: FnOnce(),
{
    fn call(self: Box<Self>) {
        (*self)()
    }
}

fn make_thunk(f: impl FnOnce()) -> Box<dyn Thunk> {
    Box::new(f)
}
```

### Able to call `Clone`

One specific thing that hits me fairly often is that I want the ability to *clone* a `dyn` value:

```rust
trait Task: Clone {
    //      ----- Error: not dyn compatible
    fn method(&self);
}

fn clone_task(task: &Box<dyn Task>) {
    task.clone()
}
```

This is a hard one to fix because the `Clone` trait can only be implemented for `Sized` types. But dang it would be nice.

### Able to work with (at least some) generic functions

Building on the above, I would like to have `dyn` traits that have methods with generic parameters. I'm not sure how flexible this can be, but anything I can get would be nice. The simplest starting point I can see is allowing the use of `impl Trait` in argument position:

```rust
trait Log {
    fn log_to(&self, logger: impl Logger); // <-- not dyn safe today
}
```

Today this method is not dyn compatible because we have to know the type of the `logger` parameter to generate a monomorphized copy, so we cannot know what to put in the vtable. Conceivably, *if* the `Logger` trait were dyn compatible, we could generate a copy that takes (effectively) a `dyn Logger` -- except that this wouldn't quite work, because `impl Logger` is short for `impl Logger + Sized`, and `dyn Logger` is not `Sized`. But maybe we could finesse it.

If we support `impl Logger` in argument position, it would be nice to support it in return position. This of course is approximately the problem we are looking to solve to support dyn async trait:

```rust
trait Signal {
    fn signal(&self) -> impl Future<Output = ()>;
}
```

Beyond this, well, I'm not sure how far we can stretch, but it'd be *nice* to be able to support other patterns too.

### Able to work with partial traits or traits without some associated types unspecified

One last point is that *sometimes* in this scenario I don't need to be able to access all the methods in the trait. Sometimes I only have a few specific operations that I am performing via `dyn`. Right now though all methods have to be dyn compatible for me to use them with `dyn`. Moreover, I have to specify the values of all associated types, lest they appear in some method signature. You can workaround this by factoring out methods into a supertrait, but that assumes that the trait is under your control, and anyway it's annoying. It'd be nice if you could have a partial view onto the trait.

## What does "better" look like when you really want less code?

So what about the case where generics are fine, good even, but you just want to avoid generating quite so much code? You might also want that to be under the control of your user.

I'm going to walk through a code example for this section, showing what you can do today, and what kind of problems you run into. Suppose I am writing a custom iterator method, `alternate`, which returns an iterator that alternates between items from the original iterator and the result of calling a function. I might have a struct like this:

```rust
struct Alternate<I: Iterator, F: Fn() -> I::Item> {
    base: I,
    func: F,
    call_func: bool,
}

pub fn alternate<I, F>(
    base: I,
    func: F,
) -> Alternate<I, F>
where
    I: Iterator,
    F: Fn() -> I::Item,
{
    Alternate { base, func, call_func: false }
}
```

The `Iterator` impl itself might look like this:

```rust
impl<I, F> Iterator for Alternate<I, F>
where
    I: Iterator,
    F: Fn() -> I::Item,
{
    type Item = I::Item;
    fn next(&mut self) -> Option<I::Item> {
        if !self.call_func {
            self.call_func = true;
            self.base.next()
        } else {
            self.call_func = false;
            Some((self.func)())
        }
    }
}
```

Now an `Alternate` iterator will be `Send` if the base iterator and the closure are `Send` but not otherwise. The iterator and closure will be able to use of references found on the stack, too, so long as the `Alternate` itself does not escape the stack frame. Great!

But suppose I am trying to keep my life simple and so I would like to write this using `dyn` traits:

```rust
struct Alternate<Item> { // variant 2, with dyn
    base: Box<dyn Iterator<Item = Item>>,
    func: Box<dyn Fn() -> Item>,
    call_func: bool,
}
```

You'll notice that this definition is somewhat simpler. It looks more like what you might expect from `Java`. The `alternate` function and the `impl` are also simpler:

```rust
pub fn alternate<Item>(
    base: impl Iterator<Item = Item>,
    func: impl Fn() -> Item,
) -> Alternate<Item> {
    Alternate {
        base: Box::new(base),
        func: Box::new(func),
        call_func: false
    }
}

impl<Item> Iterator for Alternate<Item> {
    type Item = Item;
    fn next(&mut self) -> Option<Item> {
        // ...same as above...
    }
}
```

### Confusing lifetime bounds

There a problem, though: this code won't compile! If you try, you'll find you get an error in this function:

```rust
pub fn alternate<Item>(
    base: impl Iterator<Item = Item>,
    func: impl Fn() -> Item,
) -> Alternate<Item> {...}
```

The reason is that `dyn` traits have a default lifetime bound. In the case of a `Box<dyn Foo>`, the default is `'static`. So e.g. the `base` field has type `Box<dyn Iterator + 'static>`. This means the closure and iterators can't capture references to things. To fix *that* we have to add a somewhat odd lifetime bound:

```rust
struct Alternate<'a, Item> { // variant 3
	 base: Box<dyn Iterator<Item = Item> + 'a>,
    func: Box<dyn Fn() -> Item + 'a>,
    call_func: bool,
}

pub fn alternate<'a, Item>(
    base: impl Iterator<Item = Item> + 'a,
    func: impl Fn() -> Item + 'a,
) -> Alternate<'a, Item> {...}
```

### No longer generic over `Send`

OK, this looks weird, but it will work fine, and we'll only have one copy of the iterator code per output `Item` type instead of one for every (base iterator, closure) pair. Except there is *another* problem: the `Alternate` iterator is never considered `Send`. To make it `Send`, you would have to write `dyn Iterator + Send` and `dyn Fn() -> Item + Send`, but then you couldn't support *non*-Send things anymore. That stinks and there isn't really a good workaround.

Ordinary generics work really well with Rust's auto trait mechanism. The type parameters `I` and `F` capture the full details of the base iterator plus the closure that will be used. The compiler can thus analyze a `Alternate<I, F>` to decide whether it is `Send` or not. Unfortunately `dyn Trait` really throws a wrench into the works -- because we are no longer tracking the precise type, we also have to choose which parts to keep (e.g., its lifetime bound) and which to forget (e.g., whether the type is `Send`).

### Able to partially monomorphize ("polymorphize")

This gets at another point. Even ignoring the `Send` issue, the `Alternate<'a, Item>` type is not ideal. It will make fewer copies, but we still get one copy per item type, even though the code for many item types will be the same. For example, the compiler will generate effectively the same code for `Alternate<'_, i32>` as `Alternate<'_, u32>` or even `Alternate<'_, [u8; 4]>`. It'd be cool if we could have the compiler go further and coallesce code that is identical.[^llvm] Even better if it can coallesce code that is "almost" identical but pass in a parameter: for example, maybe the compiler can coallesce multiple copies of `Alternate` by passing the size of the `Item` type in as an integer variable.

[^llvm]: If the code is byte-for-byte identical, In fact LLVM and the linker will sometimes do this today, but it doesn't work reliably across compilation units as far as I know. And anyway there are often small differences.

### Able to change from `impl Trait` without disturbing callers

I really like using `impl Trait` in argument position. I find code like this pretty easy to read:

```rust
fn for_each_item<Item>(
    base: impl Iterator<Item = Item>,
    mut op: impl FnMut(Item),
) {
    for item in base {
        op(item);
    }
}
```

But if I were going to change this to use `dyn` I can't just change from `impl` to `dyn`, I have to add some kind of pointer type:

```rust
fn for_each_item<Item>(
    base: &mut dyn Iterator<Item = Item>,
    op: &mut dyn Fn(Item),
) {
    for item in base {
        op(item);
    }
}
```

This then disturbs callers, who can no longer write:

```rust
for_each_item(some_iter, |item| process(item));
```

but now must write this

```rust
for_each_item(&mut some_iter, &mut |item| process(item));
```

You can work around this by writing some code like this...

```rust
fn for_each_item<Item>(
    base: impl Iterator<Item = Item>,
    mut op: impl FnMut(Item),
) {
    for_each_item_dyn(&mut base, &mut op)
}

fn for_each_item_dyn<Item>(
    base: &mut dyn Iterator<Item = Item>,
    op: &mut dyn FnMut(Item),
) {
    for item in base {
        op(item);
    }
}
```

but to me that just begs the question, why can't the *compiler* do this for me dang it?

### Async functions can make send/sync issues crop up in functions

In the iterator example I was looking at a struct definition, but with `async fn` (and in the future with `gen`) these same issues arise quickly from functions. Consider this async function:

```rust
async fn for_each_item<Item>(
    base: impl Iterator<Item = Item>,
    op: impl AsyncFnMut(Item),
) {
    for item in base {
        op(item).await;
    }
}
```

If you rewrite this function to use `dyn`, though, you'll find the resulting future is never send nor sync anymore:

```rust
async fn for_each_item<Item>(
    base: &mut dyn Iterator<Item = Item>,
    op: &mut dyn AsyncFnMut(Item),
) {
    for item in base {
        op(item).box.await; // <-- assuming we fixed this
    }
}
```

## Conclusions and questions

This has been a useful mental dump, I found it helpful to structure my thoughts. 

One thing I noticed is that there is kind of a "third reason" to use `dyn` -- to make your life a bit simpler. The versions of `Alternate` that used `dyn Iterator` and `dyn Fn` felt simpler to me than the fully parameteric versions. That might be best addressed though by simplifying generic notation or adopting things like implied bounds.

Some other questions I have:

* Where else does the `Send` and `Sync` problem come up? Does it combine with the first use case (e.g., wanting to write a vector of heterogeneous tasks each of which are generic over whether they are send/sync)?
* Maybe we can categorize real-life code examples and link them to these patterns.
* Are there other reasons to use dyn trait that I didn't cover? Other ergonomic issues or pain points we'd want to address as we go?
