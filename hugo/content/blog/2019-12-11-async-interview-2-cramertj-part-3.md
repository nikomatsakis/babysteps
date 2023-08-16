---
categories:
- Rust
- AsyncInterviews
date: "2019-12-11T00:00:00Z"
slug: async-interview-2-cramertj-part-3
title: 'Async Interview #2: cramertj, part 3'
---

This blog post is continuing [my conversation with
cramertj][first post]. This
will be the last post.

In the [first post], I covered what we said about Fuchsia,
interoperability, and the organization of the futures crate. 

In the [second post], I covered cramertj's take on the [`Stream`],
[`AsyncRead`], and [`AsyncWrite`] traits. We also discused the idea of
[attached] streams and the imporance of GATs for modeling those.

[`Stream`]: https://docs.rs/futures-core/0.3.1/futures_core/stream/trait.Stream.html
[`AsyncRead`]: https://docs.rs/futures/0.3.1/futures/io/trait.AsyncRead.html
[`AsyncWrite`]: https://docs.rs/futures/0.3.1/futures/io/trait.AsyncWrite.html
[attached]: http://smallcultfollowing.com/babysteps/blog/2019/12/10/async-interview-2-cramertj-part-2/#terminology-note-detachedattached-instead-of-streaming

In this post, we'll talk about async closures.

You can watch the [video] on YouTube.

[first post]: http://smallcultfollowing.com/babysteps/blog/2019/12/09/async-interview-2-cramertj/
[second post]: http://smallcultfollowing.com/babysteps/blog/2019/12/10/async-interview-2-cramertj-part-2/
[video]: https://youtu.be/NF_qyiypnOs

### Async closures

Next we discussed async closures. You may have noticed that while you
can write an `async fn`:

```rust
async fn foo() {
    ...
}
```

you cannot write the analogous syntax with closures:

```rust
let foo = async || ...;
```

Such a thing would often be useful, especially when writing the
combinators on futures and streams that one might expect (like `map`
and so forth). Unfortunately, async closures turn out to be somewhat
more complex than their synchronous counterparts -- to get the
behavior we probably want, it turns out that they too would require
some support for generic associated types (GAT), because they sort of
want to be "[attached] closures".

### An example using iterator

To see the problem, let's start with a synchronous example using
`Iterator`. Here is some code that uses `for_each` to process each
datum in the iterator and -- along the way -- it increments a counter
found on the stack:

```rust
fn process_count(iterator: impl Iterator<Item = Datum>) {
    let mut counter = 0;
    iterator.for_each(|data| {
        counter += 1
        process_datum(datum);
    });
    use(counter);
}
```

So what is actually happening when we compile this? The closure expression
actually compiles to a struct that implements the `FnMut` trait. This struct
will hold a reference to the `counter` variable. So in practice the desugared
form might look like:

```rust
fn process_count(iterator: impl Iterator<Item = Datum>) {
    let mut counter = 0;
    iterator.for_each(ClosureStruct { counter: &mut counter |})
    use(counter);
}
```

The line `counter += 1` is compiled then to the equivalent of `*self.counter += 1`:

```rust
impl FnMut<Datum> for ClosureStruct {
    type Output = ();

    fn call(&mut self, datum: Datum) {
        *self.counter += 1;
        process_datum(datum);
    }
}
```

### Converting the example to use stream

So what would happen if we were using an async closure? The
`ClosureStruct` would still be constructed, presumably, in the same
way. But the closure trait no longer directly performs the
action. Instead, when you call the closure, you get back a *future*
the performs the action; that *future* is going to need to have a
reference to `counter` too, and that comes from `self`. So that means
that the type of this future is going to have to hold a reference to
`self`, which means that the impl would have to look something like
this:

```rust
impl AsyncFnMut<Datum> for ClosureStruct {
    type Future<'s> = ClosureFuture<'s>;
    
    fn call<'s>(&'s mut self, datum: Datum) -> ClosureFuture<'s> {
        ClosureFuture::new(&mut self.counter, datum)
    }
}
```

As you can see, modeling this properly requires GATs. In fact, async
closures are basically ["attached"] closures which return a value that
borrows from `self`. (And, just as attached iterators might sometimes
be useful, I've found that sometimes I have need of an attached
closure in synchronous code as well.)

["attached"]: http://smallcultfollowing.com/babysteps/blog/2019/12/10/async-interview-2-cramertj-part-2/#terminology-note-detachedattached-instead-of-streaming

### What you can write today

The only thing you can write today is a closure that returns an async
block:

```rust
let foo = || async move { ... };
```

But this has rather different semantics. In this case, for example, we
would be copying the current value of `counter` into the future, and
not holding a reference to the `counter` (and if you tried to hold a
reference, you'll get an error).

### Conclusion

This wraps up my 3-part summary of my conversation with cramertj.
Looking back, I think the main take-aways are:

* We could stabilize [`AsyncRead`] and [`AsyncWrite`] and resolve the
  questions of uninitialized memory (and presumably vectorized writes,
  which we didn't discuss explicitly) in some analogous way with the
  sync version of the traits.
* [`Stream`] and async closures would benefit from being "attached",
  which requires us to make progress on GATs.
    * In particular, we would not want to add generator syntax until
      we have a convincing and complete story.
* Similarly, until the async closures story is more complete, we
  probably want to hold off on adding too many utility functions in
  the stdlib. Auxiliary libraries like [`futures`] allow us to
  introduce such functions and later make changes.
* The `select!` macro is cool and everybody should read the
  [async book chapter] to learn why. =)
  
## Comments?

There is a [thread on the Rust users forum](https://users.rust-lang.org/t/async-interviews/35167/) for this series.
  
[`futures`]: https://github.com/rust-lang-nursery/futures-rs/
[async book chapter]: https://rust-lang.github.io/async-book/06_multiple_futures/03_select.html
