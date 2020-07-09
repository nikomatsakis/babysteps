---
layout: post
title: 'Async Interview #8: Stjepan Glavina'
categories: [Rust, AsyncInterviews]
---

Several months ago, on May 1st, I spoke to Stjepan Glavina about his
(at the time) new crate, [smol]. Stjepan is, or ought to be, a pretty
well-known figure in the Rust universe. He is one of the primary
authors of the various [crossbeam] crates, which provide core parallel
building blocks that are both efficient and very ergonomic to use. He
was one of the initial designers for the [async-std] runtime. And so
when I read stjepang's [blog post] describing a new async runtime
[smol] that he was toying with, I knew I wanted to learn more about
it. After all, what could make stjepang say:

> It feels like this is finally it - it’s the big leap I was longing for the whole time! As a writer of async runtimes, I’m excited because this runtime may finally make my job obsolete and allow me to move onto whatever comes next.

[crossbeam]: https://crates.io/crates/crossbeam
[smol]: https://crates.io/crates/smol
[blog post]: https://stjepang.github.io/2020/04/03/why-im-building-a-new-async-runtime.html

If you'd like to find out, then read on!

### Video

You can watch the [video] on YouTube. I've also embedded a copy here
for your convenience:

[video]: https://youtu.be/vYEnc5lVMvs

<center><iframe width="560" height="315" src="https://www.youtube.com/embed/vYEnc5lVMvs" frameborder="0" allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe></center>

### What is smol?

[smol] is an async runtime, similar to [tokio] or [async-std], but
with a distinctly different philosophy. It aims to be much simpler and
smaller. Whereas [async-std] offers a kind of "mirror" of the libstd
API surface, but made asynchronous, [smol] tries to get asynchrony by
**wrapping and adapting** synchronous components. There are two main
ways to do this:

* One option is to **delegate to a thread-pool**. As we'll see, stjepang
  argues that this option is can be much more efficient than people realize,
  and that it makes sense for things like accesses to the local file system.
  [smol] offers the [`blocking!`] macro as well as adapters like the
  [`reader`] function, which converts `impl Read` values into
  [`impl AsyncRead`] values.
* The other option is to use the [`Async<T>`] wrapper to **convert
  blocking I/O sockets into non-blocking ones**. This works for any I/O
  type `T` that is compatible with `epoll` (or its equivalent; on Mac,
  smol uses `kqueue`, and on Windows, smol uses [`wepoll`]).
  
[`epoll`]: https://en.wikipedia.org/wiki/Epoll
[`kqueue`]: https://en.wikipedia.org/wiki/Kqueue
[`wepoll`]: https://github.com/piscisaureus/wepoll
[tokio]: https://tokio.rs/
[async-std]: https://async.rs/
[`Async`]: https://docs.rs/smol/0.1.18/smol/struct.Async.html
[`impl AsyncRead`]: https://docs.rs/futures-io/0.3.5/futures_io/trait.AsyncRead.html

### Delegation to a thread pool

One of the debates that has been going back and forth when it comes to
asynchronous coding is how to accommodate things that need to block.
Async I/O is traditionally based on a "cooperative" paradigm, which
means that if you thread is going to do blocking I/O -- or perhaps
even just execute a really long loop -- you ought to use an explicit
operation like `spawn_blocking` that tells the scheduler what's going
on. 

Earlier, in the context of async-std, stjepang introduced a [new
async-std scheduler, inspired by Go]. This scheduler would
automatically determine when tasks were taking too long and try to
spin up more threads to compensate. This was simpler to use, but it
also had some downsides: it could be too pessimistic at times,
creating spikes in the number of threads.

[new async-std scheduler, inspired by Go]: https://async.rs/blog/stop-worrying-about-blocking-the-new-async-std-runtime/

Therefore, in smol, stjepang returned to the approach of explicitly
labeling your blocking sections, this time via the [`blocking!`]
macro. This macro will move the "blocking code" out from the
cooperative thread pool to one where the O/S manages the scheduling.

[`blocking!`]: https://docs.rs/smol/0.1.18/smol/macro.blocking.html

### Explicit blocking is often just fine

In fact, you might say that the core argument of `smol` is that some
mechanism like [`blocking!`] is often "good enough". Rather than reproducing
or cloning the libstd API surface to make it asynchronous, it is often
just fine to use the existing API but with a [`blocking!`] adapter
wrapped around it.

In particular, when interacting with the *file system* or with
stdin/stdout, smol's approach is based on blocking. It offers
[`reader`] and [`writer`] adapters that move that processing to
another thread.

[`reader`]: https://docs.rs/smol/0.1.18/smol/fn.reader.html
[`writer`]: https://docs.rs/smol/0.1.18/smol/fn.writer.html

### The Async wrapper

But of course if you were spawning threads for **all** of your I/O,
this would defeat the purpose of using an async runtime in the first
place.  Therefore, smol offers another approach, the [`Async<T>`]
wrapper.

[`Async<T>`]: https://docs.rs/smol/0.1.18/smol/struct.Async.html
[`TcpStream`]: https://doc.rust-lang.org/std/net/struct.TcpStream.html

The idea of [`Async<T>`] is that you can take a blocking abstraction,
like the [`TcpStream`] found in the standard library, and convert it
to be asynchronous by creating a `Async<TcpStream>`. This works for
any type that supports the [`AsRawFd`] trait, which gives access to
the underlying file descriptor. We'll explain that in a bit.

[`AsRawFd`]: https://doc.rust-lang.org/nightly/std/os/unix/io/trait.AsRawFd.html

So what can you do with an `Async<TcpStream>`? The core operations
that [`Async<T>`] offers are the async functions [`read_with`] and
[`write_with`]. They allow you to wrap blocking operations and have
them run asynchronously. For example, given a `socket` of type
`Async<UdpSocket>`, you might write the following to send data
asynchronously:

```rust
let len = socket.write_with(|s| s.send(msg)).await?;
```

[`read_with`]: https://docs.rs/smol/0.1.18/smol/struct.Async.html#method.read_with
[`write_with`]: https://docs.rs/smol/0.1.18/smol/struct.Async.html#method.write_with

### How the wrappers work: epoll

So how do these wrappers work under the hood? The idea is quite
simple, and it's connected to how epoll works. The idea with a
traditional Unix non-blocking socket is that it offers the same
interface as a blocking one: i.e., you still invoke functions like
`send`. However, if the kernel would have had to block, and the socket
is in non-blocking mode, then it simply returns an error code instead.
Now the user's code knows that the operation wasn't completed and it
can try again later (in Rust, this is
[`io::ErrorKind::WouldBlock`][WB]). But how does it know when to try
again? The answer is that it can invoke [`epoll`] to find out when the
socket is ready to accept data.

[WB]: https://doc.rust-lang.org/nightly/std/io/enum.ErrorKind.html#WouldBlock.v

The `read_with` and `write_with` methods build on this
idea. Basically, they execute your underlying operation just like
normal. But if that operation returns [`WouldBlock`][WB], then the
function will register the underlying file descriptor (which was
obtained via [`AsRawFd`]) with smol's runtime and yield the current
task. smol's reactor will invoke epoll and when epoll indicates that
the file descriptor is ready, it will start up your task, which will
run your closure again. Hopefully this time it succeeds.

If this seems familiar, it should. [`Async<T>`] is basically the same
as the core [`Future`] interface, but "specialized" to the case of
pollable file descriptors that return [`WouldBlock`][WB] instead of 
[`Poll::Pending`]. And of course the core [`Future`] interface
was very much built with interfaces like [`epoll`] in mind.

[`Future`]: https://doc.rust-lang.org/std/future/trait.Future.html
[`Poll::Pending`]: https://doc.rust-lang.org/std/task/enum.Poll.html#variant.Pending

### Ergonomic wrappers

The [`read_with`] and [`write_with`] wrappers are very general but
not the most convenient to use. Therefore, smol offers some "convenience impls"
that basically wrap existing methods for you. So, for example, 
given my `socket: Async<UdpStream>`, earlier we saw that I can send data
with `write_with`:

```rust
let len = socket.write_with(|s| s.send(msg)).await?;
```

but I can also invoke [`socket.send`][send] directly:

```rust
let len = socket.send(msg).await;
```

[send]: https://docs.rs/smol/0.1.18/smol/struct.Async.html#method.send

[Under the hood], this just delegates to a call to [`write_with`].

[Under the hood]: https://docs.rs/smol/0.1.18/src/smol/async_io.rs.html#939-941

### Bridging the sync vs sync worlds

stjepang argues that based the runtime around this idea of "bridging"
the sync vs async worlds not only makes for a smaller runtime, but
also has the potential to help bridge the gap between the "sync" and
"async" worlds.  Basically, user's today have to choose: do they base
their work around the synchronous I/O interfaces, like [`Read`] and
[`Write`], or the asynchronous ones?  The former are more mature and
there are a lot of libraries available that build on them, but the
latter seem to be the future.

[`Read`]: https://doc.rust-lang.org/std/io/trait.Read.html
[`Write`]: https://doc.rust-lang.org/std/io/trait.Write.html

[smol] presents another option. Rather than converting all libraries to
async, you can just adapt the synchronous libraries into the async
world, either through [`Async<T>`], where that applies, or through the
blocking adapters like [`reader`] or [`writer`].

We walked through the example of the [`inotify`] crate. This is an
existing library that wraps the
[inotify](https://en.wikipedia.org/wiki/Inotify) interface in the
linux kernel in idiomatic Rust. It is written in a sychronous style,
however, and so you might think that if you are writing async code,
you can't use it. However, its core type [implements
`AsRawFd`](https://docs.rs/inotify/0.8.3/inotify/struct.Inotify.html#method.as_raw_fd). That
means that you can create an `Async<Inotify>` instance and invoke all
its methods by using the [`read_with`] or [`write_with`] methods (or
create ergonomic wrappers of your own).

[`inotify`]: https://crates.io/crates/inotify

### Digging into the runtime

In the video, we spent a fair amount of time digging into the guts of
how smol is implemented. For example, smol never starts threads on its
own: instead, users start their own threads and invoke functions from
smol that put those threads to work.  We also looked at the details of
its thread scheduler, and compaerd it to some of the recent work
towards a [new Rayon scheduler] that is still pending. (Side note,
there's a [recorded deep dive] on YouTube that digs into how the Rayon
scheduler works, if that's your bag). In any case, we kind of got into
the weeds here, so I'll spare you the details. You can watch the
video. =)

[new Rayon scheduler]: https://github.com/rayon-rs/rayon/pull/746
[recorded deep dive]: https://youtu.be/HvmQsE5M4cY

### The importance of auditing and customizing

One interesting theme that we came to later is the importance of being
able to audit unsafe code. stjepang mentioned that he has often heard
people say that they would be happy to have a runtime that doesn't
achieve peak performance, if it makes use of less unsafe code.

In fact, I think one of the things that stjepang would really like to
see is people taking smol and, rather than using it directly, adapting
it to their own codebases. Basically using it as a starting point
to build your own runtime for your own needs.

### Towards a generic runtime interface?

It's not a short-term thing, but one of the things that I personally
am very interested in is getting a better handle on what a "generic
runtime interface" looks like. I'd love to see a future where async
runtimes are like allocators: there is a default one that works
"pretty well" that you can use a lot of the time, but it's also really
use to change that default and port your application over to more
specialized allocators that work better for you.

I've often imagined this as a kind of trait that encapsulates the
"core functions" a runtime would provide, kind of like the
[`GlobalAlloc`] trait for allocators. But stjepang pointed out that
[smol] suggests a different possibility, one where the std library
offers a kind of "mini reactor". This reactor would offer functions to
"register" sockets, associate them with wakers, and a function that
periodically identifies things that can make progress and pushes them
along. This wouldn't in and of itself be a runtime, but it would be a
building block that other runtimes can use.

[`GlobalAlloc`]: https://doc.rust-lang.org/core/alloc/trait.GlobalAlloc.html

Anyway, as I said above, I don't think we're at the point where we
know what a generic runtime interface should look like. I'm
particularly a bit nervous about something that is overly tied to
epoll, given all the interesting work going on around adapting
io-uring (e.g., withoutboat's [Ringbahn]) and so forth. But I think
it's an interesting thing to think about, and I definitely think smol
stakes out an interesting point in this space.

[Ringbahn]: https://without.boats/blog/ringbahn-ii/

### Conclusion

My main takeaways from this conversation were:

* The "core code" you need for a runtime is really very little.
* Adapters like [`Async<T>`] and offloading work onto thread pools can be a
  helpful and practical way to unify the question of sync vs async.
* In particular, while I knew that Future's were conceptually quite
  close to epoll, I hadn't realized how far you could get with a
  generic adapter like [`Async<T>`], which maps between the I/O
  [`WouldBlock`][WB] error and the [`Poll::Pending`] future result.
* In thinking about the space of possible runtimes, we should be
  considering not only things like efficiency and ergonomics, but also
  the total amount of code and our ability to audit and understand it.

### Comments?

There is a [thread on the Rust users forum](https://users.rust-lang.org/t/async-interviews/35167/) for this series.
