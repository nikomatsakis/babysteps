---
categories:
- Rust
- AsyncInterviews
date: "2019-12-23T00:00:00Z"
slug: async-interview-3-carl-lerche
title: 'Async Interview #3: Carl Lerche'
---

Hello! For the latest [async interview], I spoke with Carl Lerche
([carllerche]). Among many other crates[^loom], Carl is perhaps best
known as one of the key authors behind [tokio] and [mio]. These two
crates are quite widely used through the async ecosystem. Carl and I
spoke on December 3rd.

[async interview]: http://smallcultfollowing.com/babysteps/blog/2019/12/09/async-interview-2-cramertj/
[tokio]: https://github.com/tokio-rs/tokio 
[mio]: https://github.com/tokio-rs/mio
[carllerche]: https://github.com/carllerche/

[^loom]: I think [loom] looks particularly cool.
[loom]: https://crates.io/crates/loom

### Video

You can watch the [video] on YouTube. I've also embedded a copy here
for your convenience:

[video]: https://youtu.be/xpk0y8tfszE

<center><iframe width="560" height="315" src="https://www.youtube.com/embed/xpk0y8tfszE" frameborder="0" allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe></center>

## Background: the mio crate

One of the first things we talked about was a kind of overview of the
layers of the "tokio-based async stack".

We started with the [mio] crate. [mio] is meant to be the "lightest
possible" non-blocking I/O layer for Rust. It basically exposes the
"epoll" interface that is widely used on linux. Windows uses a
fundamentally different model, so in that case there is a kind of
compatibility layer, and hence the performance isn't quite as good,
but it's still pretty decent. mio "does the best it can", as Carl put
it.

The [tokio] crate builds on [mio]. It wraps the epoll interface and
exposes it via the [`Future`] abstraction from `std`. It also offers
other things that people commonly need, such as timers.

[`Future`]: https://doc.rust-lang.org/std/future/trait.Future.html

Finally, bulding atop tokio you find [tower], which exposes a
"request-response" abstraction called [`Service`]. [tower] is similar
to things like [finagle] or [rack]. This is then used by libraries
like [hyper] and [tonic], which implement protocol servers (http for
[hyper], gRPC for [tonic]). These protocol servers internally use the
[tower] abstractions as well, so you can tell hyper to execute any
[`Service`].

[tower]: https://crates.io/crates/tower
[hyper]: https://crates.io/crates/hyper
[tonic]: https://crates.io/crates/tonic
[finagle]: https://twitter.github.io/finagle/
[rack]: https://rack.github.io/
[`Service`]: https://docs.rs/tower/0.3.0/tower/trait.Service.html

One challenge is that it is not yet clear how to adapt tower's
[`Service`] trait to `std::Future`. It would really benefit from
support of async functions in traits, in particular, which [is
difficult for a lot of reasons][aft]. The current plan is to adopt
[`Pin`] and to require boxing and `dyn Future` values if you wish to
use the `async fn` sugar. (Which seems like a good starting place,
-ed.)

[aft]: http://smallcultfollowing.com/babysteps/blog/2019/10/26/async-fn-in-traits-are-hard/
[`Pin`]: https://doc.rust-lang.org/std/pin/struct.Pin.html

Returning to the overall async stack, atop protocol servers like
hyper, you find web frameworks, such as [warp] -- and (finally) within
those you have middleware and the actual applications.

[warp]: https://crates.io/crates/warp

## How independent are these various layers?

I was curious to understand how "interconnected" these various crates
were. After all, while tokio is widely used, there are a number of
different executors out there, both targeting different platforms
(e.g., [Fuchsia]) as well as different trade-offs (e.g., [async-std]).
I'm really interested to get a better understanding of what we can do
to help the various layers described above operate independently, so
that people can mix-and-match.

[Fuchsia]: https://fuchsia.googlesource.com/
[async-std]: https://async.rs/

To that end, I asked Carl what it would take to use (say) Warp on
Fuchsia. The answer was that "in principle" the point of Tower is to
create just such a decoupling, but in practice it might not be so
easy.

One of the big changes in the upcoming tokio 0.2 crate, in fact, has
been to combine and merge a lot of tokio into one crate. Previously,
the components were more decoupled, but people rarely took advantage
of that. Therefore, tokio 0.2 combined a lot of components and made
the experience of using them together more streamlined, although it is
still possible to use components in a more "standalone" fashion.

In general, to make tokio work, you need some form of "driver thread".
Typically this is done by spawning a background thread, you can skip
that and run the driver yourself. 

The original tokio design had a static global that contained this
driver information, but this had a number of issues in practice: the
driver sometimes started unexpectedly, it could be hard to configure,
and it didn't work great for embedded environments. Therefore, the new
system has switched to an explicitly launch, though there are
procedural macros `#[tokio::main]` or `#[tokio::test]` that provide
sugar if you prefer.

## What should we do next? Stabilize stream.

Next we discussed which concrete actions made sense next. Carl felt
that an obvious next step would be to stabilize the `Stream` trait.
As you may recall, cramertj and I [discussed the `Stream` trait][c2]
in quite a lot of detail -- in short, the existing design for `Stream`
is "detached", meaning that it must yield up ownership of each item it
produces, much like an `Iterator`. It would be nice to figure out the
story for "attached" streams that can re-use internal buffers, which
are a very common use case, especially before we create syntactic
sugar.

[c2]: http://smallcultfollowing.com/babysteps/blog/2019/12/10/async-interview-2-cramertj-part-2/

Carl's motivation for a stable [`Stream`] is in part that he would like
to issue a stable tokio release, ideally in Q3 of 2020, and [`Stream`]
would be a part of that. If there is no [`Stream`] trait in the standard
libary, that complicates things.

One thing we *didn't* discuss, but which I personally would like to
understand better, is what sort of libraries and infrastructure might
benefit from a stabilized [`Stream`]. For example, "data libraries" like
hyper mostly want a trait like [`AsyncRead`] to be stabilized.

[`Stream`]: https://docs.rs/futures/0.3.1/futures/stream/trait.Stream.html
[`AsyncRead`]: https://docs.rs/futures/0.3.1/futures/io/trait.AsyncRead.html

## About async read

Next we discussed the [`AsyncRead`] trait a little, though not in great
depth. If you've been following the latest discussion, you'll have seen
that there is a [tokio proposal](https://github.com/tokio-rs/tokio/pull/1744)
to modify the `AsyncRead` traits used within tokio. There are two main goals here:

* to make it safe to pass an uninitialized memory buffer to `read`
* to better support vectorizing writes

However, there isn't a clear consensus on the thread (at least not the
last time I checked) on the best alternative design. The PR itself
proposes changing from a `&mut [u8]` buffer (for writing the output
into) to a `dyn` trait value, but there are other options. Carl for
example [proposed] using a concrete wrapper struct instead, and adding
methods to test for vectorization support (since outer layers may wish
to adopt different strategies based on whether vectorization works).

[proposed]: https://github.com/tokio-rs/tokio/pull/1744#issuecomment-553575438

One of the arguments in favor of the current design from the futures
crate is that it maps very cleanly to the `Read` trait from the stdlib
([cramertj advanced this argument][c3], for example). Carl felt that
the trait is already quite different (e.g., notably, it uses `Pin`)
and that these more "analogous" interfaces could be made with
defaulted helper methods instead. Further, he felt that async
applications tend to prize performance more highly than synchronous
ones, so the importance and overhead of uninitialized memory may be
higher.

[c2]: http://smallcultfollowing.com/babysteps/blog/2019/12/10/async-interview-2-cramertj-part-2/

## About async destructors and other utilities

We discussed async destructors. Carl felt that they would be a
valuable thing to add for sure. He felt that the ["general design"
proposed by boats](https://boats.gitlab.io/blog/post/poll-drop/) would
be reasonable, although he thought there might be a bit of a
duplication issue if you have both a async drop and a sync drop. A
possible solution would be to have a `prepare_to_drop` async method
that gives the object time to do async preparations, and then to
always run the sync drop afterwards.

We also discussed a few utility methods like `select!`, and Carl
mentioned that a lot of the ecosystem is currently using things like
[proc-macro-hack] to support these, so perhaps a good thing to focus
on would be improving procedural macro support so that it can handle
expression level macros more cleanly.
  
## Comments?

There is a [thread on the Rust users forum](https://users.rust-lang.org/t/async-interviews/35167/) for this series.

## Footnotes

[proc-macro-hack]: https://crates.io/crates/proc-macro-hack
