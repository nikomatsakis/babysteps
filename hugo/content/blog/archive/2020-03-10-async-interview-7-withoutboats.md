---
categories:
- Rust
- AsyncInterviews
date: "2020-03-10T00:00:00Z"
slug: async-interview-7-withoutboats
title: 'Async Interview #7: Withoutboats'
---

Hello everyone! I'm happy to be posting a transcript of my [async
interview] with withoutboats. This particularly interview took place
way back on January 14th, but the intervening months have been a bit
crazy and I didn't get around to writing it up till now.

[async interview]: http://smallcultfollowing.com/babysteps/blog/2019/11/22/announcing-the-async-interviews/

### Video

You can watch the [video] on YouTube. I've also embedded a copy here
for your convenience:

[video]: https://youtu.be/a-kZhPMqXRs

<center><iframe width="560" height="315" src="https://www.youtube.com/embed/a-kZhPMqXRs" frameborder="0" allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe></center>

## Next steps for async

Before I go into boats' interview, I want to talk a bit about the
state of async-await in Rust and what I see as the obvious next steps.
I may still do a few more async interviews after this -- there are
tons of interesting folks I never got to speak to! -- but I think it's
also past time to try and come to a consensus of the "async roadmap"
for the rest of the year (and maybe some of 2021, too). The good news
is that I feel like the async interviews highlighted a number of
relatively clear next steps. Sometime after this post, I hope to post
a blog post laying out a "rough draft" of what such a roadmap might
look like.

## History

withoutboats is a member of the Rust lang team. Starting around the
beginning on 2018, they started looking into async-await for
Rust. Everybody knew that we wanted to have some way to write a
function that could suspend (`await`) as needed. But we were stuck on
a rather fundamental problem which boats explained in the blog post
["self-referential structs"][aai]. This blog post was the first in a
series of posts that ultimately documented the design that became the
[`Pin`] type, which describes a pointer to a value that can never be
moved to another location in memory. `Pin` became the foundation for
async functions in Rust. (If you've not read the blog post series,
it's highly recommended.) If you'd like to learn more about pin, boats
posted a [recorded stream on YouTube][pin] that explores its design in
detail.

[`Pin`]: https://doc.rust-lang.org/std/pin/struct.Pin.html
[aai]: https://boats.gitlab.io/blog/post/2018-01-25-async-i-self-referential-structs/
[pin]: https://www.youtube.com/watch?v=shtfSMTwKRw

## Vision for async

All along, boats has been motivated by a relatively clear vision: we
should make async Rust "just as nice to use" as Rust with blocking
I/O. In short, you should be able to write code much like you ever
did, but adding making functions which perform I/O into `async` and
then adding `await` here or there as needed. 

Since 2018, we've made great progress towards the goal of "async I/O
that is as easy as sync" -- most notably by landing and [stabilizing
the async-await MVP][mvp] -- but we're not there yet. There remain a
number of practical obstacles that make writing code using async I/O
more difficult than sync I/O. So the mission for the next few years is
to identify those obstacles and dismantle them, one by one.

[mvp]: https://blog.rust-lang.org/2019/11/07/Async-await-stable.html

## Next step: async destructors

One of the first obstacles that boats mentioned was extending Rust's
[`Drop`] trait to work better for async code. The [`Drop`] trait, for
those who don't know Rust, is a special trait in Rust that types can
implement in order to declare a destructor (code which should run when
a value goes out of scope). boats wrote a [blog
post](https://boats.gitlab.io/blog/post/poll-drop/) that discusses the
problem in more detail and proposes a solution. Since that blog post,
they've refined the proposal in response to some feedback, though the
overall shape remains the same. The basic idea is to extend the `Drop`
trait with an optional `poll_drop_ready` method:

[`Drop`]: https://doc.rust-lang.org/std/ops/trait.Drop.html

```rust
trait Drop {
    fn drop(&mut self);
    fn poll_drop_ready(
        self: Pin<&mut Self>, 
        ctx: &mut Context<'_>,
    ) -> Poll<()> {
        Poll::Ready(())
    }
}
```

When executing an async fn, and a value goes out of scope, we will
first invoke `poll_drop_ready`, and "await" if it returns anything
other than `Poll::Ready`. This gives the value a chance to do async
operations that may block, in preparation for the final drop.  Once
`Poll::Ready` is returned, the ordinary `drop` method is invoked.

This async-drop trait came up in early async interviews, and I raised
[Eliza's use case] with boats. Specifically, she wanted some way to
offer values that are live on the stack a callback when a yield occurs
and when the function is resumed, so that they can (e.g.) interact
with thread-local state correctly in an async context. While distinct
from async destructors, the issues are related because destructors are
often used to manage thread-local values in a scoped fashion.

[Eliza's use case]: http://smallcultfollowing.com/babysteps/blog/2020/02/11/async-interview-6-eliza-weisman/#raii-and-async-fn-doesnt-always-play-well

Adding async drop requires not only modifying the compiler but also
modifying futures combinators to properly handle the new
`poll_drop_ready` method (combinators need to propagate this
`poll_drop_ready` to the sub-futures they contain).

Note that we wouldn't offer any 'guarantee' that `poll_drop_ready`
will run. For example, it would not run if a future is dropped without
being resumed, because then there is no "async context" that can
handle the awaits. However, like `Drop`, it would ultimately be
something that types can "usually" expect to execute under ordinary
circumstances.

Some of the use cases for async-drop include writers that buffer data
and wish to ensure that the data is flushed out when the writer is
dropped, transactional APIs, or anything that might do I/O when
dropped.

## `block_on` in the std library

One very small addition that boats proposed is adding `block_on` to
the standard library. Invoking `block_on(future)` would block the
current thread until `future` has been fully executed (and then return
the resulting value). This is actually something that most async I/O
code would *never* want to do -- if you want to get the value from a
future, after all, you should do `future.await`. So why is `block_on` useful?

Well, `block_on` is basically the most minimal executor. It allows you
to take async code and run it in a synchronous context with minimal
fuss. It's really convenient in examples and documentation. I would
personally like it to permit writing stand-alone test cases. Those
reasons alone are probably good enough justification to add it, but
boats has another use in mind as well.

## async fn main

Every Rust program ultimately begins with a `main` somewhere. Because
`main` is invoked by the surrounding C library to start the program,
it also tends to be a place where a certain amount of "boilerplate
code" can accumulate in order to "setup" the environment for the rest
of the program. This "boilerplate setup" can be particularly annoying
when you're just getting started with Rust, as the `main` function is
often the first one you write, and it winds up working differently
than the others. A similar program effects smaller code examples.

In Rust 2018, we extended `main` so that it supports `Result` return
values. This meant that you could now write `main` functions that use
the `?` operator, without having to add some kind of intermediate
wrapper:

```rust
fn main() -> Result<(), std::io::Error> {
    let file = std::fs::File::create("output.txt")?;
}
```

Unfortunately, async code today suffers from a similar papercut.  If
you're writing an async project, most of your code is going to be
async in nature: but the `main` function is always synchronous, which
means you need to bridge the two somehow. Sometimes, especially for
larger projects, this isn't that big a deal, as you likely need to do
some setup or configuration anyway. But for smaller examples, it's
quite a pain.

So boats would like to allow people to write an "async" main. This
would then permit you to directly "await" futures from within the
`main` function:

```rust
async fn main() {
    let x = load_data(22).await;
}

async fn load_data(port: usize) -> Data { ... }
```

Of course, this raises the question: since the program will ultimately
run synchronized, how do we bridge from the `async fn main` to a
synchronous main? This is where `block_on` comes in: at least to
start, we can simply declare that the future generated by `async fn
main` will be executed using `block_on`, which means it will block the
main thread until `main` completes (exactly what we want). For simple
programs and examples, this will be exactly what you want.

But most real programs will ultimately want to start some other
executor to get more features. In fact, [following the lead of the
runtime crate][rc], many executors already offer a procedural macro
that lets you write an async main. So, for example, [tokio] and
[async-std] offer attributes called [`#[tokio::main]`][tma] and
[`#[async_std::main]`][ama] respectively, which means that if you have an
`async fn main` program you can pick an executor just by adding the
appropriate attribute:

```rust
#[tokio::main] // or #[async_std::main], etc
async fn main() {
    ..
}
```

[rc]: https://github.com/rustasync/runtime#attributes

I imagine that other executors offer a similar procedural macro -- or
if they don't yet, they could add one. =)

(In fact, since async-std's runtime starts implicitly in a background
thread when you start using it, you could use async-std libraries
without any additional setup as well.)

[tokio]: https://tokio.rs/
[async-std]: https://async.rs/
[tma]: https://book.async.rs/tutorial/accept_loop.html
[ama]: https://docs.rs/async-std/1.5.0/async_std/#examples

Overall, this seems pretty nice to me. Basically, when you write
`async fn main`, you get Rust's "default executor", which presently is
a *very* bare-bones executor suitable only for simple examples. To
switch to a more full-featured executor, you simply add a
`#[foo::main]` attribute and you're off to the races!

[tokio]: https://tokio.rs/
[async-std]: https://async.rs/

(Side note #1: This isn't something that boats and I talked about, but
I wonder about adding a more general attribute, like
`#[async_runtime(foo)]` that just desugars to a call like
`foo::main_wrapper(...)`, which is expected to do whatever setup is
appropriate for the crate `foo`.)

(Side note #2: This *also* isn't something that boats and I talked
about, but I imagine that having a "native" concept of `async fn main`
might help for some platforms where there is already a native
executor. I'm thinking of things like [GStreamer] or perhaps iOS with
Grand Central Dispatch. In short, I imagine there are environments
where the notion of a "main function" isn't really a great fit anyhow,
although it's possible I have no idea what I'm talking about.)
 
[GStreamer]: https://gstreamer.freedesktop.org/

## async-await in an embedded context

One thing we've not talked about very much in the interviews so far is
using async-await in an embedded context. When we shipped the
async-await MVP, we definitely cut a few corners, and one of those had
to do with the use of thread-local storage (TLS). Currently, when you
use `async fn`, the desugaring winds up using a private TLS variable
to carry the [`Context`] about the current async task down through the
stack. This isn't necessary, it was just a quick and convenient hack
that sidestepped some questions about how to pass in arguments when
resuming a suspended function. For most programs, TLS works just fine,
but some embedded environments don't support it. Therefore, it makes
sense to fix this bug and permit `async fn` to pass around its state
without the use of TLS. (In fact, since boats and I talked,
[jonas-schievink] opened PR [#69033] which does exactly this, though
it's not yet landed.)

[jonas-schievink]: https://github.com/rust-lang/rust/pull/69033
[#69033]: https://github.com/rust-lang/rust/pull/69033
[`Context`]: https://doc.rust-lang.org/std/task/struct.Context.html

## Async fn are implemented using a more general generator mechanism

You might be surprised when I say that we've already started fixing
the TLS problem. After all, **the reason we used TLS in the first
place is that there were unresolved questions about how to pass in
data when waking up a suspended function -- and we haven't resolved
those problems**. So why are we able to go ahead and use them to
support TLS?

The answer is that, while the `async fn` feature is implemented atop a
more general mechanism of suspendable functions[^gen], the full power
of that mechanism is not exposed to end-users. So, for example,
suspendable functions in the compiler permit yielding arbitrary
values, but async functions always yield up `()`, since they only need
to signal that they are blocked waiting on I/O, not transmit
values. Similarly, the compiler's internal mechanism will allow us to
pass in a new [`Context`] when we wake up from a yield, and we can use
that mechanism to pass in the [`Context`] argument from the future
API. But this is hidden from the end-user, since that [`Context`] is
never directly exposed or accessed.

[^gen]: In the compiler, we call these "suspendable functions" generators, but I'm avoiding that terminology for a reason.

[`Poll::Pending`]: https://doc.rust-lang.org/std/task/enum.Poll.html#variant.Pending

In short, the suspended functions supported by the compiler are not a
language feature: they are an implementation detail that is
(currently) only used for async-await. This is really useful because
it means we can change how they work, and it also means that we don't
have to make them support all possible use cases one might want. In
this particular case, it means we don't have to resolve some of the
thorny questions about to pass in data after a yield, because we only
need to use them in a very specific way.

## Supporting generators (iterators) and async generators (streams)

One observation that boats raised is that people who write Async I/O
code are interacting with `Pin` much more directly than was expected.
The primary reason for this is that people are having to manually
implement the [`Stream`] trait, which is basically the async version
of an iterator. (We've talked about `Stream` in a number of previous
async interviews.) I have also found that, in my conversations with
*users* of async, streams come up very, very often. At the moment,
*consuming* streams is generally fairly easy, but *creating* them is
quite difficult. For that matter, even in synchronous Rust, manually
implementing the `Iterator` traits is kind of annoying (although
significantly easier than streams).

[`Stream`]: https://docs.rs/futures/0.3.1/futures/stream/trait.Stream.html

So, it would be nice if we had some way to make it easier to write
iterators and streams. And, indeed, this design space has been carved
out in other languages: the basic mechanism is to add a
**generator**[^gen2], which is some sort of function that can yield up
a series of values before terminating. Obviously, if you've read up to
this point, you can see that the "suspendable functions" we used to
implement async await can also be used to support some form of
generator abstractions, so a lot of the hard implementation work has
been done here.

[^gen2]: This is why I was avoiding using the term "generator" earlier -- I want to say "suspendable functions" when referring to the implementation mechanism, and "generator" when referring to the user-exposed feature.

That said, support generator functions has been something that we've
been shying away from. And why is that, if a lot of the implementation
work is done? The answer is primarily that the design space is
**huge**. I alluded to this earlier in talking about some of the
questions around how to pass data in when resuming a suspended
function.

## Full generality considered too dang difficult

boats however contends that we are making our lives harder than they
need to be. In short, **if we narrow our focus from "create the
perfect, flexible abstraction for suspended functions and coroutines"
to "create something that lets you write iterators and streams", then
a lot of the thorny design problems go away**. Now, under the covers,
we still want to have some kind of unified form of suspended functions
that can support async-await and generators, but that is a much
simpler task.

In short, we would want to permit writing a `gen fn` (and `async gen
fn`), which would be some function that is able to `yield` values and
which eventually returns. Since the iterator's `next` method doesn't
take any arguments, we wouldn't need to support passing data in after
yields (in the case of streams, we *would* pass in data, but only the
[`Context`] values that are not directly exposed to users). Similarly,
iterators and streams don't produce a "final value" when they're done,
so these functions would always just return unit.

Adopting a more narrow focus wouldn't close the door to exposing our
internal mechanism as a first-class language feature at some point,
but it would help us to solve urgent problems sooner, and it would
also give us more experience to use when looking again at the more
general task. It also means that we are adding features that makes
writing iterators and streams *as easy as we can make it*, which is a
good thing[^precludes]. (In case you can't tell, I was sympathetic to
boats' argument.)

[^precludes]: though not one that a fully general mechanism necessarily
precludes

## Extending the stdlib with some key traits

boats is in favor of adding the "big three" traits to the standard library
(if you've been reading these interviews, these traits will be quite
familiar to you by now):

* `AsyncRead`
* `AsyncWrite`
* `Stream`

## Stick to the core vision: Async and sync should be analogous 

One important point: boats believes (and I agree) that we should try
to maintain the principle that the async and synchronous versions of
the traits should align as closely as possible. This matches the
overarching design vision of minimizing the differences between "async
Rust" and "sync Rust". It also argues in favor of the proposal that
[sfackler proposed in their interview][sfackler], where we address the
questions of how to handle uninitialized memory in an analogous way
for both `Read` and `AsyncRead`.

[sfackler]: http://smallcultfollowing.com/babysteps/blog/2020/01/20/async-interview-5-steven-fackler/

We talked a bit about the finer details of that principle. For
example, if we were to extend the `Read` trait with some kind of `read_buf` method (which can support an uninitialized output buffer), then this
new method would have to have a default, for backwards compatibility reasons:

```rust
trait Read {
    fn read(&mut self, ...);
    fn read_buf(&mut self, buf: &mut BufMut<..>) { }
}
```

This is a bit unfortunate, as ideally you would only implement
`read_buf`.  For `AsyncRead`, since the trait doesn't exist yet, we
could switch the defaults. But boats pointed out that this carries
costs too: we would forever have to explain why the two traits are
different, for example. (Another option is to have both methods
default to one another, so that you can implement either one, which --
combined with a lint -- might be the best of both worlds.)

## Generic interface for spawning

Some time back, boats wrote a post proposing [global executors].  This
would basically be a way to add a function to the stdlib to spawn a
task, which would then delegate (somehow) to whatever executor you are
using. Based on the response to the post, boats now feels this is
probably not a good short-term goal. 

For one thing, there were a lot of unresolved questions about just
what features this global executor should support. But for another,
the main goal here is to enable libraries to write "executor
independent" code, but it's not clear how many libraries spawn tasks
**anyway** -- that's usually done more at the application
level. Libraries tend to instead return a future and let the
application do the spawning (interestingly, one place this doesn't
work is in destructors, since they can't return futures; supporting
async drop, as discussed earlier, would help here.)

[global executors]: https://boats.gitlab.io/blog/post/global-executors/

So it'd probably be better to revisit this question once we have more
experience, particularly once we have the async I/O and stream traits
available.

## The futures crate

We discussed other possible additions to the standard library.
There are a lot of "building blocks" currently in the futures library
that are independent from executors and which could do well in the standard
library. Some of the things that we talked about:

* async-aware mutexes, clearly a useful building block
* channels
    * though std channels are not the most loved, crossbeam's are genreally preferred
    * interstingly, channel types *do* show up in public APIs from time to time, as a way to receive data, so having them in std could be particularly useful

In general, where things get more complex is whenever you have bits of
code that either have to spawn tasks or which do the "core I/O". These
are the points where you need a more full-fledged reactor or
runtime. But there are lots of utilities that don't need that and
which could profitably level in the std library.

## Where to put async things in the stdlib? 

One theme that boats and I did not discuss, but which has come up when
I've raised this question with others, is *where* to put async-aware
traits in the std hierarchy, particularly when there are sync
versions. For example, should we have `std::io::Read` and
`std::io::AsyncRead`? Or would it be better to have `std::io::Read`
and something like `std::async::io::Read` (obviously, async is a
keyword, so this precise path may not be an option). In other words,
should we combine sync/async traits into the same space, but with
different names, or should we carve out a space for "async-enabled"
traits and use the same names? An interesting question, and I don't
have an opinion yet.

## Conclusion and some of my thoughts

I always enjoy talking with boats, and this time was no exception.  I
think boats raised a number of small, practical ideas that hadn't come
up before. I do think it's important that, in addition to stabilizing
fundamental building blocks like `AsyncRead`, we also consider
improvements to the ergonomic experience with smaller changes like
`async fn main`, and I agree with the guiding principle that boats
raised of keeping async and sync code as "analogous" as possible.

### Comments?

There is a [thread on the Rust users forum](https://users.rust-lang.org/t/async-interviews/35167/) for this series.

### Footnotes
