---
layout: post
title: 'Async Interview #2: cramertj, part 3'
categories: [Rust, AsyncInterviews]
---

This blog post is continuing [my conversation with
cramertj][first post]. This
will be the last post.

In the [first post], I covered what we said about Fuchsia,
interoperability, and the organization of the futures crate. 

In the [second post], I covered cramertj's take on the [`Stream`]
trait, and discussed the various kinds of 

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

[attached]: http://smallcultfollowing.com/babysteps/blog/2019/12/10/async-interview-2-cramertj-part-2/#terminology-note-detachedattached-instead-of-streaming

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

