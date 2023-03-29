---
layout: post
title: Must move types
date: 2023-03-16 18:32 -0400
---

Rust has lots of mechanisms that prevent you from doing something bad. But, right now, it has NO mechanisms that force you  to do something *good*[^mu]. I’ve been thinking lately about what it would mean to add “must move” types to the language. This is an idea that I’ve long resisted, because it represents a fundamental increase to complexity. But lately I’m seeing more and more problems that it would help to address, so I wanted to try and think what it might look like, so we can better decide if it's a good idea.

[^mu]: Well, apart from the "must use" lint.

## Must move?

The term ‘must move’ type is not standard. I made it up. The more usual name in PL circles is a “linear” type, which means a value that must be used exactly once. The idea of a *must move* type `T` is that, if some function `f` has a value `t` of type `T`, then `f` *must move* `t` before it returns (modulo panic, which I discuss below). Moving `t` can mean either calling some other function that takes ownership of `t`, returning it, or — as we’ll see later — destructuring it via pattern matching.

Here are some examples of functions that *move* the value `t`. You can return it…

```rust
fn return_it<T>(t: T) {
    t
}
```

…call a function that takes ownership of it…

```rust
fn send_it<T>(t: T) {
    channel.send(t); // takes ownership of `t`
}
```

…or maybe call a constructor function that takes ownership of it (which would usually mean you must “recursively” move the result)…

```rust
fn return_opt<T>(t: T) -> Option<T> {
    Some(t) // moves t into the option
}
```

## Doesn’t Rust have “linear types” already?

You may have heard that Rust’s ownership and borrowing is a form of “linear types”. That’s not really true. Rust has *affine types*, which means a value that can be moved *at most* once. But we have nothing that forces you to move a value. For example, I can write the `consume` function in Rust today:

```rust
fn consume<T>(t: T) {
    /* look ma, no .. nothin' */
}
```

This function takes a value `t` of (almost, see below) any type `T` and…does nothing with it. This is not possible with linear types. If `T` were *linear*, we would have to do *something* with `t` — e.g., move it somewhere. This is why I call linear types *must move*.

## What about the destructor?

“Hold up!”, you’re thinking, “`consume` doesn’t actually do *nothing* with `t`. It drops `t`, executing its destructor!” Good point. That’s true. But `consume` isn’t actually required to execute the destructor; you can always use `forget` to avoid it[^rc]:

[^rc]: Or create a Rc-cycle, if that’s more your speed.

```rust
fn consume<T>(t: T) {
    std::mem::forget(t();
}
```

If weren’t possible to “forget” values, destructors would mean that Rust had a linear system, but even then, it would only be in a technical sense. In particular, destructors would be a required action, but of a limited form — they can’t, for example, take arguments. Nor can they be async.

## What about `Sized`?

There is one other detail about the `consume` type worth mentioning. When I write `fn consume<T>(t: T)`, that is actually *shorthand* for saying “any type `T` that is `Sized`”. In other words, the fully elaborated “do nothing with a value” function looks like this:

```rust
fn consume<T: Sized>(t: T) {
    std::mem::forget(t();
}
```

If you don’t want this default `Sized` bound, you write `T: ?Sized`. The leading `?` means “maybe Sized” — i.e., now `T` can any type, whether it be sized (e.g., `u32`) or unsized (e.g., `[u32]`). 

**This is important:** a where-clause like `T: Foo` *narrows* the set of types that `T` can be, since now it *must* be a type that implements `Foo`. The “maybe” where-clause `T: ?Sized` (we don’t accept other traits here) *broadens* the set of types that `T` can be, by removing default bounds.

## So how would “must move” work?

You might imagine that we could encode “must move” types via a new kind of bound, e.g., `T: MustMove`. But that’s actually backwards. The problem is that “must move” types are actually a superset of ordinary types — after all, if you have an ordinary type, it’s still ok to write a function that always moves it. But it’s *also* ok to have a function that drops it or forgets it. In contrast, with a “must move” type, the only option is to move it. **This implies that what we want is a `?` bound, not a normal bound.**

The notation I propose is `?Drop`. The idea is that, by default, every type parameter `D` is assumed to be *droppable*, meaning that you can always choose to drop it at any point. But a `M: ?Drop` parameter is *not necessarily droppable*. You must ensure that a value of type `M` is moved somewhere else.

Let’s see a few examples to get the idea of it. To start, the `identity` function, which just returns its argument, could be declared with `?Drop`:

```rust
fn identity<M: ?Drop>(m: M) -> M {
    m // OK — moving `m` to the caller
}
```

But the `consume` function could not:

```rust
fn consume<M: ?Drop>(m: M) -> M {
    // ERROR: `M` is not moved.
}
```

You might think that the version of `consume` which calls `mem::forget` is sound — after all, `forget` is declared like so

```rust
fn forget<T>(t: T) {
    /* compiler magic to avoid dropping */
}
```

Therefore, if  `consume` were to call `forget(m)`, wouldn’t that count as a move? The answer is yes, it would, but we *still* get an error. This is because `forget` is not declared with `?Drop`, and therefore there is an implicit `T: Drop` where-clause:

```rust
fn consume<M: ?Drop>(m: M) -> M {
    forget(m); // ERROR: `forget` requires `M: Drop`, which isn’t known to hold.
}
```

## Declaring types to be `?Drop`

Under this scheme, all structs and types you declare would be droppable by default. If you don’t implement `Drop` explicitly, the compiler adds an automatic `Drop` impl for you that just recursively drops your fields. But you could explicitly declare your type to be `?Drop` by using a [negative impl][ni]:

[ni]: https://github.com/rust-lang/rust/issues/68318

```rust
pub struct Guard {
    value: u32
}

impl !Drop for Guard { }
```

When you do this, the type becomes “must move” and any function which has a value of type `Guard` must either move it somewhere else. You might wonder then how you ever terminate — the answer is that one way to “move” the value is to unpack it with a pattern. For example, `Guard` might declare a `log` method:

```rust
impl Guard {
    pub fn log(self, message: &str) {
        let Guard { value } = self; // moves “self”
        println!(“{value} = {message}”);
    }
}
```

This plays nicely with privacy: if your type have private fields, only functions within that module will be able to destruct it, everyone else must (eventually) discharge their obligation to move by invoking some function within your module.

## Interactions between “must move” and control-flow

Must move values interact with control-flow like `?`. Consider the `Guard` type from the previous section, and imagine I have a function like this one…

```rust
fn execute(t: Guard) -> Result<(), std::io::Error> {
    let s: String = read_file(“message.txt”)?;  // ERROR: `t` is not moved on error
    t.log(&s);
    Ok(())
}
```

This code would not compile. The problem is that the `?` in `read_file` may return with an `Err` result, in which case the call to `t.log` would not execute! This is a good error, in the sense that it is helping us ensure that the `log` call to `Guard` is invoked, but you can imagine that it’s going to interact with other things. To fix the error, you should do something like this…

```rust
fn execute(t: Guard) -> Result<(), std::io::Error> {
    match read_file(“message.txt”) {
        Ok(s) => {
		t.log(&s);
		Ok(())
        }
        Err(e) => {
            t.log(“error”); // now `t` is moved
            Err(e)
        }
    }
}
```

Of course, you could also opt to pass back the `t` value to the caller, making it their problem.

## Conditional “must move” types

Talking about types like `Option` and `Result` — it’s clear that we are going to want to be able to have types that are *conditionally* must move —  i.e., must move only if their type parameter is “must move”. That’s easy enough to do:

```rust
enum Option<T: ?Drop> {
    Some(T),
    None,
}
```

Some of the methods on `Option` work just fine:

```rust
impl<T: ?Drop> Option<T> {
    pub fn map<U: ?Drop>(self, op: impl FnOnce(T) -> U) -> Option<U> {
        match self {
            Some(t) => Some(op(t)),
            None => None,
        }
    }
}
```

Other methods would require a `Drop` bound, such as `unwrap_or`:

```rust
impl<T: ?Drop> Option<T> {
    pub fn unwrap_or(self, default:T) -> T
    where
        T: Drop,
    {
        match self {
            // OK
            None => default,

            // Without the `T: Drop` bound, we are not allowed to drop `default` here.
            Some(v) => v,
       }
    }
}
```

## “Must move” and panic

One very interesting question is what to do in the case of panic. This is tricky! Ordinarily, a `panic` will unwind all stack frames, executing destructors. But what should we do for a `?Drop` type that doesn’t *have* a destructor?

I see a few options:

* Force an abort. Seems bad.
* Deprecate and remove unwinding, limit to panic=abort. A more honest version of the previous one. Still seems bad, though dang would it make life easier.
* Provide some kind of fallback option.

The last one is most appealing, but I’m not 100% sure how it works. It may mean that we don’t want to have the “must move” opt-in be to `impl !Drop` but rather to `impl MustMove`, or something like that, which would provide a method that is invoked on the case of panic (this method could, of course, choose to abort). The idea of fallback might also be used to permit cancellation with the `?` operator or other control-flow drops (though I think we definitely want types that don’t permit cancellation in those cases).

## “Must move” and trait objects

What do we do with `dyn`? I think the answer is that `dyn Foo` defaults to `dyn Foo + Drop`, and hence requires that the type be droppable. To create a “must move” dyn, we could permit `dyn Foo + ?Drop`. To make that really work out, we’d have to have `self` methods to consume the dyn (though today you can do that via `self: Box<Self>` methods).

## Uses for “must move”

Contra to best practices, I suppose, I’ve purposefully kept this blog post focused on the mechanism of must move and not talked much about the motivation. This is because I’m not really trying to sell anyone on the idea, at least not yet, I just wanted to sketch some thoughts about how we might achieve it. That said, let me indicate why I am interested in “must move” types.

First, async drop: right now, you cannot have destructors in async code that perform awaits. But this means that async code is not able to manage cleanup in the same way that sync code does. Take a look at the [status quo story about dropping database handles][sq] to get an idea of the kinds of problems that arise. Adding async drop itself isn’t that hard, but what’s really hard is guaranteeing that types with async drop are not dropped in sync code, as documented at length in [Sabrina Jewson's blog post][ad]. This is precisely because we currently assume that *all* types are droppable. The simplest way to achieve “async drop” then would to define a trait `trait AsyncDrop { async fn async_drop(self); }` and then make the type “must move”. This will force callers to eventually invoke `async_drop(x).await`. We might want some syntactic sugar to handle `?` more easily, but that could come later.

[sq]: https://rust-lang.github.io/wg-async/vision/submitted_stories/status_quo/alan_finds_database_drops_hard.html

[ad]: https://sabrinajewson.org/blog/async-drop

Second, parallel structured concurrency. As Tyler Mandry [elegant documented][tm], if we want to mix parallel scopes and async, we need some way to have futures that cannot be forgotten. The way I think of it is like this: in *sync* code, when you create a local variable `x` on your stack, you have a guarantee from the language that it’s destructor will eventually run, unless you move it. In async code, you have no such guarantee, as your entire future could just be forgotten by a caller. “Must move” types solve this problem (with some kind of callback for panic) give us a tool to solve this problem, by having the future type be `?Drop` — this is effectively a principled way to integrate completion-style futures that must be fully polled.

[tm]: https://tmandry.gitlab.io/blog/posts/2023-03-01-scoped-tasks/

Finally, “liveness conditions writ large”. As I noted in the beginning, Rust’s type system today is pretty good at letting you guarantee “safety” properties (“nothing bad happens”), but it’s much less useful for *liveness* properties (“something good eventually happens”). Destructors let you get close, but they can be circumvented. And yet I see liveness properties cropping up all over the place, often in the form of guards or cleanup that really ought to happen. Any time you’ve ever wanted to have a destructor that takes an argument, that applies. This comes up a lot in unsafe code, in particular. Being able to “log” those obligations via “must move” types feels like a really powerful tool that will be used in many different ways.

## Parting thoughts

This post sketches out one way to get “true linear” types in Rust, which I’ve dubbed as “must move” types. I think I would call this the `?Drop` approach, because the basic idea is to allow types to “opt out” from being “droppable” (in which case they must be moved). This is not the only approach we could use. One of my goals with this blog post is to start collecting ideas for different ways to add linear capabilities, so that we can compare them with one another.

I should also address the obvious “elephant in the room”. The Rust type system is already complex, and adding “must move” types will unquestionably make it more complex. I’m not sure yet whether the tradeoff is worth it: it’s hard to judge without trying the system out. I think there’s a good chance that “must move” types live “on the edges” of the type system, through things like guards and so forth that are rarely abstracted over. I think that when you are dealing with concrete types, like the `Guard` example, must move types won’t feel particularly complicated. It will just be a helpful lint saying “oh, by the way, you are supposed to clean this up properly”. But where pain will arise is when you are trying to build up generic functions — and of course just in the sense of making the Rust language that much bigger. Things like `?Sized` definitely make the language feel more complex, even if you never have to interact with them directly. 

On the other hand, “must move” types definitely add value in the form of preventing very real failure modes. I continue to feel that Rust’s goal, above all else, is “productive reliability”, and that we should double down on that strength. Put another way, I think that the complexity that comes from reasoning about “must move” types is, in large part, *inherent complexity*, and I feel ok about extending the language with new tools for that. We saw this with the interaction with the `?` operator — no doubt it’s annoying to have to account for moves and cleanup when an error occurs, but it’s also a a key part of building a robust system, and destructors don’t always cut it.