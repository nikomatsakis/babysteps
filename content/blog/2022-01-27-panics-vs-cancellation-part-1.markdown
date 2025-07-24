---
layout: post
title: Panics vs cancellation, part 1
date: 2022-01-27T15:55:00-0500
---

One of the things people often complain about when doing Async Rust is cancellation. This has always been a bit confusing to me, because it seems to me that async cancellation should feel a lot like panics in practice, and people don't complain about panics very often (though they do sometimes). This post is the start of a short series comparing panics and cancellation, seeking after the answer to the question "Why is async cancellation a pain point and what should we do about it?" This post focuses on explaining Rust's *panic philosophy* and explaining why I see panics and cancellation as being quite analogous to one another.

## Why panics are discouraged in Rust

Let's go back to some pre-history. The Rust design has always included panics, but it *hasn't* always included the [`catch_unwind`] function. In fact, adding that function was quite controversial. Why?

[`catch_unwind`]: https://doc.rust-lang.org/std/panic/fn.catch_unwind.html

The reason is that long experience with exceptions has shown that exceptions work really well for propagating errors out, but they don't work well for recovering from errors or handling them in a structured way. The problem is that exceptions make errors invisible, which means that programmers don't think about them.

The only time when exceptions work well for recovery is when that recovery is done at a very coarse-grained level. If you have a "main loop" of your application and you can kind of catch the exception and restart that main loop, that can be very useful. You see this insight popping up all over the place; I think Erlang did it best, with their ["let it crash" philosophy](https://medium.com/@vamsimokari/erlang-let-it-crash-philosophy-53486d2a6da). 

## Why exceptions are bad at fine-grained recovery

The reason that exceptions are bad at fine-grained recovery is simple. In most programs, you have some kind of invariants that you are maintaining to ensure your data is in a valid state. It's relatively straightforward to ensure that these invariants hold at the beginning of every operation and that they hold by the end of every operation. It's **really, really hard** to ensure that those invariants hold **all the time**. Very often, you have some code that wants to make some mutations, put your data in an inconsistent state, and then fix that inconsistency.

Unfortunately, with widespread use of exceptions, what you have is that any piece of code, at any time, might suddenly just abort. So if that function is doing mutation, it could leave the program in an inconsistent state.

Consider this simple pseudocode (inspired by [tomaka's blog post][tomaka]). The idea of this function is that it is going to read from some file, parse the data it reads, and then send that data over a socket:

[tomaka]: https://tomaka.medium.com/a-look-back-at-asynchronous-rust-d54d63934a1c

```rust
fn copy_data(from_file: &File, to_socket: &Socket) {
    let buffer = from_file.read();
    let parsed_items = parse(buffer);
    parsed_items.send(to_socket);
}
``` 

You might think that since this function doesn't do any explicit mutation, it would be fine to stop it any point and re-execute it. But that's not true: there is some implicit state, which is the cursor in the `from_file`. If the `parse` function or the `send` function were to throw an exception, whatever data had just been read (and maybe parsed) would be lost. The next time the function is invoked, it's not going to go back and re-read that data, it's just going to proceed from where it left off, and some data is lost.

## Rust's compromise

The initial design of Rust included the idea that panic recovery was only possible at the thread boundary. The idea was that threads own all of their state, so if a thread panicked, you would take down the thread, and with it all of the potentially corrupted state. In this way, recovery could be done with some reasonable assurance of success. There are some limits to this idea. For one thing, threads can share state. The most obvious way for that to happen is with a `Mutex`, but -- as the `copy_data` example shows -- you can also have problems when you are communicating (reading from a file, sending messages over a channel, etc).  We have extra mechanisms to help with those cases, such as [lock posioning](https://doc.rust-lang.org/nomicon/poisoning.html), but the jury is out on how well they work.[^lp]

[^lp]: My take is that the concept behind lock poisoning still seems good to me, but the ergonomics of how we implemented it are bad, and make people not like it. That said, I'd like to dig more into this: I've been hearing from various people that -- even in their limited form -- panics are one of the weaker points in Rust's reliability story, and I'm not yet sure what to think.

## Why `?` is good 

All of this discussion of course begs the question, how *is* one supposed to handle error recovery in Rust? The answer, of course, is [the `?` operator](https://doc.rust-lang.org/book/ch09-02-recoverable-errors-with-result.html). This operator desugars into a pattern match, but it has the effect of "propagating" the error to the caller of the function. If we look at the `copy_data` one more time, but imagine that any potential errors were propagated using results, it would look like:

```rust
fn copy_data(from_file: &File, to_socket: &Socket) -> eyre::Result<()> {
    let buffer = from_file.read()?;
    let parsed_items = parse(buffer);
    parsed_items.send(to_socket)?;
}
``` 

The nice thing about this code is that one can easily see and audit potential errors: for example, I can see that `send` may result in an error, and a sharp-eyed reviewer might see the potential data loss.[^auditpostfacto] Even better, I can do some sort of recovery in the case of error by opting not to forward the error but matching instead. (Note that the `send` methods [typically pass back the message in the event of an error](https://doc.rust-lang.org/std/sync/mpsc/struct.Sender.html#method.send).)

```rust
fn copy_data(from_file: &File, to_socket: &Socket) -> eyre::Result<()> {
    let buffer = from_file.read()?;
    let parsed_items = parse(buffer);
    match parsed_items.send(to_socket) {
        Ok(()) => (),
        Err(SendError(parsed_items)) => recover_from_error(parsed_items),
    }
}
``` 

[^auditpostfacto]: My experience is that these bugs are hard to spot in review, but that the `?` operator is invaluable when debugging -- in that case, you are asking the question, "how could this function possibly return early?", and having the `?` operator really helps you find the answer.

## How does this connect to async cancellation?

I said that, from a user's perspective, it seems to me that async cancellation and Rust panics should feel very similar. Let me explain.

It sometimes happen that you have spawned a future whose result is no longer needed. For example, you may be running a server that is doing work on behalf of a client, but that client may drop its connection, in which case you'd like to cancel that work. 

In Rust, our cancellation story is centered around dropping. The idea is that to cancel a future, you drop it. Whenever you drop any kind of value in Rust, the value's destructor runs which has the job of disposing of whatever resources that value owns. In the case of a *future*, the values that it owns are the suspended variables from the stack frame. Consider that same `copy_data` function we saw earlier, but ported to async Rust:


```rust
async fn copy_data(from_file: &File, to_socket: &Socket) {
    let buffer = from_file.read().await;
    let parsed_items = parse(buffer);
    parsed_items.send(to_socket).await;
}
``` 

Suppose that, at some point, we pause the program at the final line, `parsed_items.send(...).await`. In that case, the future would be storing the value of `buffer` and `parsed_items`. So when the future is dropped, those values will be dropped. 

In effect, if you look at things from the "inside view" of the async fn, cancellation looks like the `await` call panicking -- it unwinds the stack, running the destructors for all values. The analogy, of course, only goes so far: you can't, for example, "catch" the unwinding from a cancellation. Also, panics arise from code that the thread executed, but cancellations are injected from the outside when the async fn's result is no longer needed.[^deprecate]

[^deprecate]: This could be a crucial difference: I think, for example, it's the reason that Java deprecated its [Thread.stop](https://docs.oracle.com/javase/8/docs/api/java/lang/Thread.html#stop--) method.

## Next time

In the next post I plan to start looking at examples of async cancellation and practice, trying to pinpoint how it is used and why it seems to cause more problems than panic.

## Thanks

Thanks to Aaron Turon, Yoshua Wuyts, Yehuda Katz, and others with whom I've deep dived on this topic over the years, and to tomaka for their [blog post][tomaka].

## Footnotes
