---
layout: post
title: Announcing the Async Interviews
categories: [Rust, AsyncInterviews]
---

Hello all! I'm going to be trying something new, which I call the
**"Async Interviews"**. These interviews are going to be a series of
recorded video calls with various "luminaries" from Rust's Async I/O
effort. In each one, I'm going to be asking roughly the same question:
**Now that the async-await MVP is stable, what should we be doing
next?** After each call, I'll post the recording from the interview,
along with a blog post that leaves a brief summary.

My intention in these interviews is to really get into details. That
is, I want to talk about what our big picture goals should be, but
also what the *specific concerns* are around stabilizing particular
traits or macros. What sorts of libraries do they enable? And so
forth. (You can view my rough [interview script], but I plan to tailor
the meetings as I go.)

[interview script]: https://gist.github.com/nikomatsakis/ae2ede32c4c7d49cbda088a1539724d9

I view these interviews as serving a few purposes:

* Help to survey what different folks are thinking and transmit that
  thinking out to the community.
* Help me to understand better what some of the tradeoffs are,
  especially around discussions that occurred before I was following
  closely.
* Experiment with a new form of Rust discussion, where we substitute
  1-on-1 exploration and discussion for bigger discussion threads.

### First video: Rust and WebAssembly

The first video in this series, which I expect to post next week, will
be me chatting with **Alex Crichton** and **Nick Fitzgerald** about
**Async I/O and WebAssembly**. This video is a bit different from the
others, since it's still early days in that area -- as a result, we
talked more about what role Async I/O (and Rust!) might eventually
play, and less about immediate priorities for Rust. Along with the
video, I'll post a blog post summarizing the main points that came up
in the conversation, so you don't necessarily have to watch the video
itself.

### What videos will come after that?

My plan is to be posting a fresh async interview roughly once a week.
I'm not sure how long I'll keep doing this -- I guess as long as it
seems like I'm still learning things. I'll announce the people I plan
to speak to as I go, but I'm also very open to suggestions!

I'd like to talk to folks who are working on projects at all levels of
the "async stack", such as runtimes, web frameworks, protocols, and
consumers thereof. If you can think of a project or a person that you
think would provide a useful perspective, I'd love to hear about
it. Drop me a line via e-mail or on Zulip or Discord.

### Creating design notes

One thing that I have found in trying to get up to speed on the design
of Async I/O is that the discussions are often quite distributed,
spread amongst issues, RFCs, and the like. I'd like to do a better job
of organizing this information.

Therefore, as part of this effort to talk to folks, one of the things
I plan to be doing is to collect and catalog the concerns, issues, and
unknowns that are being brought up. **I'd love to find people to help
in this effort!** If that is something that interests you, come join
the [#wg-async-foundations stream] on [the rust-lang Zulip] and say
hi!

[#wg-async-foundations stream]: https://rust-lang.zulipchat.com/#narrow/stream/187312-wg-async-foundations
[the rust-lang Zulip]: https://rust-lang.zulipchat.com

### So what *are* the things we might do now that async-await is stable?

If you take a look at my rough [interview script], you'll see a long
list of possibilities. But I think they break down into two big
categories:

* improving interoperability
* extending expressive power, convenience, and ergonomics

Let's look a bit more at those choices.

### Improving interoperability

A long time back, Rust actually had a built-in green-threading
library.  It was removed in [RFC #230], and a big part of the
motivation was that we knew we were unlikely to find a *single runtime
design* that was useful for all tasks. And, even if we could, we
certainly knew we hadn't found it *yet*. Therefore, we opted to pare
back the stdlib to just expose the primitives that the O/S had to
offer.

[RFC #230]: https://gist.github.com/nikomatsakis/ef21d903717ef20b8bbf4ae5c1c03ba0

Learning from this, our current design is intentionally much more
"open-ended" and permits runtimes to be added as simple crates on
crates.io. Right now, to my knowledge, we have at least five distinct
async runtimes for Rust, and I wouldn't be surprised if I've forgotten
a few:

* [fuschia's runtime], used for the Fuschia work at Google;
* [tokio], a venerable, efficient runtime with a rich feature set;
* [async-std], a newer contender which aims to couple libstd-like APIs
  with highly efficient primitives;
* [bastion], exploring a resilient, Erlang-like model[^woohoo];
* [embrio-rs], exploring the embedded space.

[^woohoo]: Woohoo! I just want to say that I've been hoping to see something like OTP for Rust for...quite some time.

[fuschia's runtime]: https://fuchsia.googlesource.com/
[tokio]: https://tokio.rs/
[async-std]: https://async.rs/
[bastion]: https://bastion.rs/
[actix]: https://actix.rs/
[embrio-rs]: https://github.com/Nemo157/embrio-rs

I think this is great: I love to see people experimenting with
different tradeoffs and priorities. Not only do I think we'll wind up
with better APIs and more efficient implementations, this also means
we can target 'exotic' environments like the Fuschia operating system
or smaller embedded platforms. Very cool stuff.

However, that flexibility does come with some real risks. Most
notably, I want us to be sure that it is possible to "mix and match"
libraries from the ecosystem. No matter what base runtime you are
using, it should be possible to take a protocol implementation like
[quinn], combine it with "middleware" crates like [async-compression],
and starting sending payloads.

[async-compression]: https://github.com/Nemo157/async-compression
[quinn]: https://github.com/djc/quinn

In my mind, the best way to ensure interoperability is to ensure that
we offer standard traits that define the interfaces between
libraries. Adding the `std::Future` trait was a huge step in this
direction -- it means that you can create all kinds of combinators and
things that are fully portable between runtimes. But what are the
*next* steps we can take to help improve things further?

One obvious set of things we can do improve interop is to try and
stabilize additional traits. Currently, the futures crate contains a
number of interfaces that have been evolving over time, such as
[`Stream`], [`AsyncRead`], and [`AsyncWrite`]. Maybe some of these
traits are good candidates to be moved to the standard library next?

Here are some of the main things I'd like to discuss around interop:

* As a meta-point, should we be moving the crates to the standard
  library, or should we move try to promote the futures crate (or,
  more likely, some of its subcrates, such as
  [futures-io](https://docs.rs/futures-io/0.3.1/futures_io/)) as the
  standard for interop? I've found from talking to folks that there is
  a fair amount of confusion on "how standard" the futures crates are
  and what the plan is there.
* Regardless of how we signal stability, I also want to talk about the
  specific traits or other things we might stabilizing. For each such item,
  there are two things I'd like to drill into:
    * What kinds of interop would be enabled by stabilizing this
      item? What are some examples of the sorts of libraries that
      could now exist independently of a runtime because of the
      existence of this item?
    * What are the specific concerns that remain about the design of
      this item? The [`AsyncRead`] and [`AsyncWrite`] traits, for
      example, presently align quite closely with their synchronous
      counterparts [`Read`] and [`Write`]. However, this interface
      does require that the buffer used to store data must be
      zeroed. The [tokio] crate is [considering altering its own local
      definition of `AsyncRead`][tokio#1744] for this reason, is that
      something we should consider as well? If so, how?
* On a broader note, what are the sorts of things crates need to truly
  operate that are *not* covered by the existing traits? For example,
  the [global executors] that boats recently proposed would give
  people the ability to "spawn tasks" into some ambient context... is
  that a capability that would enable more interop? Perhaps access to
  task-local data? Inquiring minds want to know.

[tokio]: https://tokio.rs/
[tokio#1744]: https://github.com/tokio-rs/tokio/pull/1744
[futures]: https://github.com/rust-lang-nursery/futures-rs/
[`AsyncRead`]: https://docs.rs/futures/0.3.1/futures/io/trait.AsyncRead.html
[`AsyncWrite`]: https://docs.rs/futures/0.3.1/futures/io/trait.AsyncWrite.html
[`Read`]: https://doc.rust-lang.org/std/io/trait.Read.html
[`Write`]: https://doc.rust-lang.org/std/io/trait.Write.html
[`Stream`]: https://docs.rs/futures/0.3.1/futures/stream/trait.Stream.html
[global executors]: https://boats.gitlab.io/blog/post/global-executors/

### Improving expressive power, convenience, and ergonomics

Interoperability isn't the only thing that we might try to improve.
We might also focus on language extensions that either grow our
expressive power or add convenience and ergonomics. Something like
supporting async fn in traits or async closures, for example, could be
a huge enabler, even if there are some real difficulties to making
them work.

Here are some of the specific features we might discuss:

* **Async destructors.** As boats described [in this blog post][adr],
  there is sometimes a need to "await" things when running
  destructors, and our current system can't support that.
* **Async fn in traits.** We support `async fn` in free functions and
  inherent methods, but not in traits. As I explained in [this blog
  post][atr], there are a lot of challenges to support async fn in
  traits properly (but consider using [the `async-trait` crate]).
* **Async closures.** Currently, we support async *blocks* (`async
  move { .. }`), which evaluate to a future, and async *functions*
  (`async fn foo()`), which are a function that returns a future. But,
  at least on stable, we have no way to make a *closure* that returns
  a future. Presumably this would be something like `async || {
  ... }`. (In fact, on nightly, we do have support for async
  closures, but there are some issues in the design that we need to
  work out.)
* **Combinator methods like [`map`], or macros like [`join!`] and
  [`select!`].** The futures crate offers a number of useful combinators
  and macros. Maybe we should move some of those to the standard
  library?

[adr]: https://boats.gitlab.io/blog/post/poll-drop/
[atr]: http://smallcultfollowing.com/babysteps/blog/2019/10/26/async-fn-in-traits-are-hard/
[the `async-trait` crate]: https://crates.io/crates/async-trait
[`map`]: https://docs.rs/futures/0.3.1/futures/future/trait.FutureExt.html#method.map
[`join!`]: https://docs.rs/futures/0.3.1/futures/macro.join.html
[`select!`]: https://docs.rs/futures/0.3.1/futures/macro.select.html

### Conclusion

I think these interviews are going to be a lot of fun, and I expect to
learn a lot. Stay tuned for the first blog post, coming next week,
about **Async I/O and WebAssembly**.

### Footnotes
