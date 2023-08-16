---
date: "2022-03-29T00:00:00Z"
slug: dyn-can-we-make-dyn-sized
title: 'dyn*: can we make dyn sized?'
---

Last Friday, tmandry, cramertj, and I had an exciting conversation. We were talking about the design for combining async functions in traits with `dyn Trait` that tmandry and I had presented to the lang team on Friday. cramertj had an insightful twist to offer on that design, and I want to talk about it here. Keep in mind that this is a piece of "hot off the presses", in-progress design and hence may easily go nowhere -- but at the same time, I'm pretty excited about it. If it works out, it could go a long way towards making `dyn Trait` user-friendly and accessible in Rust, which I think would be a big deal.

### Background: The core problem with dyn

`dyn Trait` is one of Rust’s most frustrating features. On the one hand, `dyn Trait` values are absolutely necessary. You need to be able to build up collections of heterogeneous types that all implement some common interface in order to implement core parts of the system. But working with heterogeneous types is just fundamentally *hard* because you don’t know how big they are. This implies that you have to manipulate them by pointer, and *that* brings up questions of how to manage the memory that these pointers point at. This is where the problems begin.

### Problem: no memory allocator in core

One challenge has to do with how we factor our allocation. The core crate that is required for *all* Rust programs, `libcore`, doesn’t have a concept of a memory allocator. It relies purely on stack allocation. For the most part, this works fine: you can pass ownership of objects around by copying them from one stack frame to another. But it doesn’t work if you don’t know how much stack space they occupy![^alloca]

[^alloca]: But, you are thinking, what about alloca? The answer is that alloca isn’t really a good option. For one thing, it doesn’t work on all targets, but in particular it doesn’t work for async functions, which require a fixed size stack frame. It also doesn't let you return things back *up* the stack, at least not easily.

### Problem: Dyn traits can’t really be substituted for impl Trait

In Rust today, the type `dyn Trait` is guaranteed to implement the trait `Trait`, so long as `Trait` is dyn safe. That seems pretty cool, but in practice it’s not all that useful. Consider a simple function that operates on any kind of `Debug` type:

```rust
fn print_me(x: impl Debug) {
    println!(“{x:?}”);
}
```

Even though the `Debug` trait is dyn-safe, you can’t just change the `impl` above into a `dyn`:

```rust
fn print_me(x: dyn Debug) { .. }
```

The problem here is that stack-allocated parameters need to have a known size, and we don’t know how big `dyn` is. The common solution is to introduce some kind of pointer, e.g. a reference:

```rust
fn print_me(x: &dyn Debug) { … }
```

That works ok for this function, but it has a few downsides. First, we have to change existing callers of `print_me` — maybe we had `print_me(22)` before, but now they have to write `print_me(&22)`. That’s an ergonomic hit. Second, we’ve now hardcoded that we are *borrowing* the `dyn Debug`. There are other functions where this isn’t necessarily what we wanted to do. Maybe we wanted to store that `dyn Debug` into a datastructure and return it — for example, this function `print_me_later` returns a closure that will print `x` when called:

```rust
fn print_me_later(x: &dyn Debug) -> impl FnOnce() + ‘_ {
    move || println!(“{x:?}”)
}
```

Imagine that we wanted to spawn a thread that will invoke `print_me_later`:

```rust
fn spawn_thread(value: usize) {
   let closure = print_me_later(&value);
   std::thread::spawn(move || closure()); // <— Error, ‘static bound not satisfied
}
```

This code will not compile because `closure` references `value` on the stack. But if we had written `print_me_later` with an `impl Debug` parameter, it could take ownership of its argument and everything would work fine.

Of course, we could solve *this* by writing `print_me_later` to use `Box` but that’s hardcoding memory allocation. **This is problematic if we want `print_me_later` to appear in a context, like libcore, that might not even have access to a memory allocator.**

```rust
fn print_me_later(x: Box<dyn Debug>) -> impl FnOnce() + ‘_ {
    move || println!(“{x:?}”)
}
```

**In this specific example, the `Box` is also kind of inefficient.** After all, the value `x` is just a `usize`, and a `Box` is also a `usize`, so in theory we could just copy the integer around (the `usize` methods expect an `&usize`, after all). This is sort of a special case, but it does come up more than you would think at the lower levels of the system, where it may be worth the trouble to try and pack things into a `usize` — there are a number of futures, for example, that don’t really require much state.

### The idea: What if the dyn were the pointer?

In the proposal for “async fns in traits” that tmandry and I put forward, we had introduced the idea of `dynx Trait` types. `dynx Trait` types were not an actual syntax that users would ever type; rather, they were an implementation detail. Effectively a `dynx Future` refers to a *pointer to a type that implements `Future`*. They don’t hardcode that this pointer is a `Box`; instead, the vtable includes a “drop” function that knows how to release the pointer’s referent (for a `Box`, that would free the memory).

### Better idea: What if the dyn were “something of known size”?

After the lang team meeting, tmandry and I met with cramertj, who proceeded to point out to us something very insightful.[^old] The truth is that `dynx Trait` values don’t have to be a *pointer* to something that implemented `Trait` — they just have to be something *pointer-sized*. tmandry and I actually knew *that*, but what we didn’t see was how critically important this was:

* First, a number of futures, in practice, consist of very little state and can be pointer-sized. For example, reading from a file descriptor only needs to store the file descriptor, which is a 32-bit integer, since the kernel stores the other state. Similarly the future for a timer or other builtin runtime primitive often just needs to store an index.
* Second, a `dynx Trait` lets you write code that manipulates values which may be boxed *without directly talking about the box*. This is critical for code that wants to appear in libcore or be reusable across any possible context.
	* As an example of something that would be much easier this way, the `Waker` struct, which lives in libcore, is effectively a *hand-written* `dynx Waker` struct.
* Finally, and we’ll get to this in a bit, a lot of low-level systems code employs clever tricks where they know *something* about the layout of a value. For example, you might have a vector that contains values of various types, but (a) all those types have the same size and (b) they all share a common prefix. In that case, you can manipulate fields in that prefix without knowing what kind of data is contained with, and use a vtable or discriminatory to do the rest.
	* In Rust, this pattern is painful to encode, though you can sometimes do it with a `Vec<S>` where `S` is some struct that contains the prefix fields and an enum. Enums work ok but if you have a more open-ended set of types, you might prefer to have trait objects.

[^old]: Also, cramertj apparently had this idea a long time back but we didn’t really understand it. Ah well, sometimes it goes like that — you have to reinvent something to realize how brilliant the original inventor really was.

### A sketch: The dyn-star type

To give you a sense for how cool “fixed-size dyn types” could be, I’m going to start with a very simple design sketch. Imagine that we introduced a new type `dyn* Trait`, which represents the pair of:

* a pointer-sized value of some type `T` that implements Trait (the `*` is meant to convey “pointer-sized”[^cool])
* a vtable for `T: Trait`; the drop method in the vtable drops the `T` value.

[^cool]: In truth, I also just think “dyn-star” sounds cool. I’ve always been jealous of the A* algorithm and wanted to name something in a similar way. Now’s my chance! Ha ha!

For now, don’t get too hung up on the specific syntax. There’s plenty of time to bikeshed, and I’ll talk a bit about how we might truly phase in something like `dyn*`. For now let’s just talk about what it would be like to use it.

### Creating a dyn*

To coerce a value of type `T` into a `dyn* Trait`, two constraints must be met:

* The type `T` must be pointer-sized or smaller.
* The type `T` must implement `Trait`

### Converting an `impl` to a `dyn*`

Using `dyn*`, we can convert `impl Trait` directly to `dyn* Trait`. This works fine, because `dyn* Trait` is `Sized`. To be truly equivalent to `impl Trait`, you do actually want a lifetime bound, so that the `dyn*` can represent references too:

```rust
// fn print_me(x: impl Debug) {…} becomes
fn print_me(x: dyn* Debug + ‘_) {
    println!(“{x:?}”);
}

fn print_me_later(x: dyn* Debug + ‘_) -> impl FnOnce() + ‘_ {
    move || println!(“{x:?}”)
}
```

These two functions can be directly invoked on a `usize` (e.g., `print_me_later(22)` compiles). What’s more, they work on references (e.g., `print_me_later(&some_type)`) or boxed values `print_me_later(Box::new(some_type))`). 

They are also suitable for inclusion in a no-std project, as they don’t directly reference an allocator. Instead, when the `dyn*` is dropped, we will invoke its destructor from the vtable, which might wind up deallocating memory (but doesn’t have to).

### More things are dyn* safe than dyn safe

Many things that were hard for `dyn Trait` values are trivial for `dyn* Trait` values:

* By-value `self` methods work fine: a `dyn* Trait` value is sized, so you can move ownership of it just by copying its bytes.
* Returning `Self`, as in the `Clone` trait, works fine.
	* Similarly, the fact that `trait Clone: Sized` doesn’t mean that `dyn* Clone` can’t implement `Clone`, although it does imply that `dyn Clone: Clone` cannot hold.
* Function arguments of type `impl ArgTrait` can be converted to `dyn* ArgTrait`, so long as `ArgTrait` is dyn*-safe
* Returning an `impl ArgTrait` can return a `dyn* ArgTrait`.

In short, a large number of the barriers that make traits “not dyn-safe” don’t apply to `dyn*`. Not all, of course. Traits that take parameters of type `Self` won’t work (we don’t know that two `dyn* Trait` types have the same underlying type) and we also can’t support generic methods in many cases (we wouldn’t know how to monomorphize)[^options].

[^options]: Obviously, we would be lifting this partly to accommoate `impl Trait` arguments. I think we could lift this restriction in more cases but it’s going to take a bit more design.

### A catch: `dyn* Foo` requires `Box<impl Foo>: Foo` and friends

There is one catch from this whole setup, but I like to think of it is as an opportunity. In order to create a `dyn* Trait` from a pointer type like `Box<Widget>`, you need to know that `Box<Widget>: Trait`, whereas creating a `Box<dyn Trait>` just requires knowing that `Widget: Trait` (this follows directly from the fact that the `Box` is now part of the hidden type).

At the moment, annoyingly, when you define a trait you don’t automatically get any sort of impls for “pointers to types that implement the trait”. Instead, people often define such traits automatically — for example, the `Iterator` trait has impls like

```rust
impl<I> for &mut I
where
    I: ?Sized + Iterator

impl<I> for Box<I>
where
    I: ?Sized + Iterator
```

Many people forget to define such impls, however, which can be annoying in practice (and not just when using dyn).

I’m not totally sure the best way to fix this, but I view it as an opportunity because if we *can* supply such impls, that would make Rust more ergonomic overall.

One interesting thing: the impls for `Iterator` that you see above include `I: ?Sized`, which makes them applicable to `Box<dyn Iterator>`. But with `dyn* Iterator`, we are starting from a `Box<impl Iterator>` type — in other words, the `?Sized` bound is not *necessary*, because we are creating our “dyn” abstraction around the pointer, which is sized. (The `?Sized` is not harmful, either, of course, and if we auto-generate such impls, we should include it so that they apply to old-style `dyn` as well as slice types like `[u8]`.)

### Another catch: “shared subsets” of traits

One of the cool things about Rust’s `Trait` design is that it allows you to combine “read-only” and “modifier” methods into one trait, as in this example:

```rust
trait WidgetContainer {
    fn num_components(&self);
    fn add_component(&mut self, c: WidgetComponent);
}
```

I can write a function that takes a `&mut dyn WidgetContainer ` and it will be able to invoke both methods. If that function takes `&dyn WidgetContainer ` instead, it can only invoke `num_components`.

If we don’t do anything else, this flexibility is going to be lost with `dyn*`. Imagine that we wish to create a `dyn* WidgetContainer ` from some `&impl WidgetContainer ` type. To do that, we would need an impl of `WidgetContainer ` for `&T`, but we can’t write that code, at least not without panicking:

```rust
impl<W> WidgetContainer for &W
where
    W: WidgetContainer,
{
    fn num_components(&self) {
        W::num_components(self) // OK
    }

    fn add_component(&mut self, c: WidgetComponent) {
        W::add_component(self, c) // Error!
    }
}
```

This problem is not specific to `dyn` — imagine I have some code that just invokes `num_components` but which can be called with a `&W` or with a `Rc<W>` or with other such types. It’s kind of awkward for me to write a function like that now: the easiest way is to hardcode that it takes `&W` and then lean on deref-coercions in the caller. 

One idea that tmandry and I have been kicking around is the idea of having “views” on traits. The idea would be that you could write something like `T: &WidgetContainer ` to mean “the `&self` methods of `WidgetContainer`”. If you had this idea, then you could certainly have

```
impl<W> &WidgetContainer for &W
where
    W: WidgetContainer
```

because you would only need to define `num_components` (though I would hope you don’t have to write such an impl by hand). 

Now, instead of taking a `&dyn WidgetContainer`, you would take a `dyn &WidgetContainer`. Similarly, instead of taking an `&impl WidgetContainer`, you would probably be better off taking a `impl &WidgetContainer` (this has some other benefits too, as it happens).

### A third catch: dyn safety sometimes puts constraints on impls, not just the trait itself

Rust’s current design assumes that you have a single trait definition and we can determine from that trait definition whether or not the trait ought to be dyn safe. But sometimes there are constraints around dyn safety that actually don’t affect the *trait* but only the *impls* of the trait. That kind of situation doesn’t work well with “implicit dyn safety”: if you determine that the trait is dyn-safe, you have to impose those limitations on its impls, but maybe the trait wasn’t *meant* to be dyn-safe. 

I think overall it would be better if traits explicitly declared their intent to be dyn-safe or not. The most obvious way to do that would be with a declaration like `dyn trait`:

```
dyn trait Foo { }
```

As a nice side benefit, a declaration like this could also auto-generate impls like `impl Foo for Box<impl Foo + ?Sized>` and so forth. It would also mean that dyn-safety becomes a semver guarantee.

My main *concern* here is that I suspect *most* traits could and should be dyn-safe. I think I’d prefer if one had to *opt out* from dyn safety instead of *opting in*. I don’t know what the syntax for that would be, of course, and we’d have to deal with backwards compatibility.

### Phasing things in over an edition

If we could start over again, I think I would approach `dyn` like this:

* The syntax `dyn Trait` means a pointer-sized value that implements `Trait`. Typically a `Box` or `&` but sometimes other things.
* The syntax `dyn[T] Trait` means “a value that is layout-compatible with T that implements `Trait`”; `dyn Trait` is thus sugar for `dyn[*const ()] Trait`, which we might write more compactly as `dyn* Trait`.
* The syntax `dyn[T..] Trait` means “a value that starts with a prefix of `T` but has unknown size and implements `Trait`.
* The syntax `dyn[..] Trait` means “some unknown value of a type that implements `Trait`”.

Meanwhile, we would extend the grammar of a trait bound with some new capabilities:

* A bound like `&Trait<P…>` refers to “only the `&self` methods from `Trait`”;
* A bound like `&mut Trait<P…>` refers to “only the `&self` and `&mut self` methods from `Trait`”;
	* Probably this wants to include `Pin<&mut Self>` too? I’ve not thought about that.
* We probably want a way to write a bound like `Rc<Trait<P…>>` to mean `self: Rc<Self>` and friends, but I don’t know what that looks like yet. Those kinds of traits are quite unusual.

I would expect that most people would just learn `dyn Trait`. The use cases for the `dyn[]` notation are far more specialized and would come later. 

Interestingly, we could phase in this syntax in Rust 2024 if we wanted. The idea would be that we move existing uses of `dyn` to the explicit form in prep for the new edition:

* `&dyn Trait`, for example, would become `dyn* Trait + ‘_`
* `Box<dyn Trait>` would become `dyn* Trait` (note that a `’static` bound is implied today; this might be worth reconsidering, but that’s a separate question).
* other uses of `dyn Trait` would become `dyn[…] Trait`

Then, in Rust 2024, we would rewrite `dyn* Trait` to just `dyn Trait` with an “edition idom lint”.

### Conclusion

Whew! This was a long post. Let me summarize what we covered:

* If `dyn Trait` encapsulated *some value of pointer size that implements `Trait`* and not *some value of unknown size*:
	* We could expand the set of things that are dyn safe by quite a lot without needing clever hacks:
		* methods that take by-value self: `fn into_foo(self, …)`
		* methods with parameters of impl Trait type (as long as `Trait` is dyn safe): `fn foo(…, impl Trait, …)`
		* methods that return impl Trait values: `fn iter(&self) -> impl Iterator`
		* methods that return `Self` types: `fn clone(&self) -> Self`
* That would raise some problems we have to deal with, but all of them are things that would be useful anyway:
	* You’d need `dyn &Trait` and things to “select” sets of methods.
	* You’d need a more ergonomic way to ensure that `Box<Trait>: Trait` and so forth.
* We could plausibly transition to this model for Rust 2024 by introducing two syntaxes, `dyn*` (pointer-sized) and `dyn[..]` (unknown size) and then changing what `dyn` means.

There are a number of details to work out, but among the most prominent are:

* Should we declare dyn-safe traits explicitly? (I think yes)
	* What “bridging” impls should we create when we do so? (e.g., to cover `Box<impl Trait>: Trait` etc)
* How exactly do `&Trait` bounds work — do you get impls automatically? Do you have to write them?

### Appendix A: Going even more crazy: `dyn[T]` for arbitrary prefixes

`dyn*` is pretty useful. But we could actually generalize it. You could imagine writing `dyn[T]` to mean “a value whose layout can be read as `T`. What we’ve called `dyn* Trait` would thus be equivalent to `dyn[*const ()] Trait`. This more general version allows us to package up larger values — for example, you could write `dyn[[usize; 2]] Trait` to mean a “two-word value”.

You could even imagine writing `dyn[T]` where the `T` meant that you can safely access the underlying value as a `T` instance. This would give access to common fields that the implementing type must expose or other such things. Systems programming hacks often lean on clever things like this. This would be a bit tricky to reconcile with cases where the `T` is a type like `usize` that is just indicating how many bytes of data there are, since if you are going to allow the `dyn[T]` to be treated like a `&mut T` the user could go crazy overwriting values in ways that are definitely not valid. So we’d have to think hard about this to make it work, that’s why I left it for an Appendix.

### Appendix B: The "other" big problems with dyn

I think that the designs in this post address a number of the big problems with dyn:

* You can't use it like impl
* Lots of useful trait features are not dyn-safe
* You have to write `?Sized` on impls to make them work 

But it leaves a few problems unresolved. One of the biggest to my mind is the interaction with auto traits (and lifetimes, actually). With generic parameters like `T: Debug`, I don't have to talk explicitly about whether `T` is `Send` or not or whether `T` contains lifetimes. I can just write write a generic type like `struct MyWriter<W> where W: Write { w: W, ... }`. Users of `MyWriter` know what `W` is, so they can determine whether or not `MyWriter<Foo>: Send` based on whether `Foo: Send`, and they also can understand that `MyWriter<&'a Foo>` includes references with the lifetime `'a`. In contrast, if we did `struct MyWriter { w: dyn* Write, ... }`, that `dyn* Write` type is *hiding* the underlying data. As Rust currently stands, it implies that `MyWriter` it *not* `Send` and that it does *not* contain references. We don't have a good way for `MyWriter` to declare that it is "send if the writer you gave me is send" *and* use `dyn*`. That's an interesting problem! But orthogonal, I think, from the problems addressed in this blog post.

