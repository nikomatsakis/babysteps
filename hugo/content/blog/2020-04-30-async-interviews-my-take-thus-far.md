---
categories:
- Rust
- Async
date: "2020-04-30T00:00:00Z"
slug: async-interviews-my-take-thus-far
title: 'Async interviews: my take thus far'
---

The point of the [async interview] series, in the end, was to help
figure out what we should be doing next when it comes to Async I/O. I
thought it would be good then to step back and, rather than
interviewing someone else, give my opinion on some of the immediate
next steps, and a bit about the medium to longer term. I'm also going
to talk a bit about what I see as some of the practical challenges.

[async interview]: {{ site.baseurl }}/blog/2019/11/22/announcing-the-async-interviews/

### Focus for the immediate term: interoperability and polish

At the highest level, I think we should be focusing on two things in
the "short to medium" term: **enabling interoperability** and
**polish**.

By **interoperability**, I mean the ability to write libraries and
frameworks that can be used with many different executors/runtimes.
Adding the `Future` trait was a big step in this direction, but
there's plenty more to go. 

My dream is that eventually people are able to write portable async
apps, frameworks, and libraries that can be moved easily between async
executors. We won't get there right away, but we can get closer.

By **polish**, I mean "small things that go a long way to improving
quality of life for users". These are the kinds of things that are
easy to overlook, because no individual item is a big milestone.

### Polish in the compiler: diagnostics, lints, smarter analyses

Most of the focus of [wg-async-foundations] recently has been on
polish work on the compiler, and we've made quite a lot of
progress. Diagnostics have [notably] [improved], and we've been
working on [inserting] [helpful] [suggestions], [fixing compiler
bugs], and [improving efficiency]. One thing I'm especially excited
about is that we [no longer rely on thread-local storage in the `async
fn` transformation][tls], which means that async-await is now
compatible with `#[no_std]` environments and hence embedded
development.

I want to give a 👏 "shout-out" 👏 to 👏 [tmandry] 👏 for leading this
polish effort, and to point out that if you're interested in
contributing to the compiler, this is a great place to start! Here are
some [tips for how to get involved][g-i].

[g-i]: https://github.com/rust-lang/wg-async-foundations#getting-involved
[wg-async-foundations]: https://github.com/rust-lang/wg-async-foundations
[tmandry]: https://github.com/tmandry
[notably]: https://github.com/rust-lang/rust/pull/64895
[improved]: https://github.com/rust-lang/rust/pull/65345
[inserting]: https://github.com/rust-lang/rust/pull/70906
[helpful]: https://github.com/rust-lang/rust/pull/68212
[suggestions]: https://github.com/rust-lang/rust/pull/71174
[fixing compiler bugs]: https://github.com/rust-lang/rust/pull/68884
[improving efficiency]: https://github.com/rust-lang/rust/pull/69837
[tls]: https://github.com/rust-lang/rust/pull/69033



I think it's also a good idea to be looking a bit more broadly.  On
Zulip, for example, [LucioFranco suggested][LF] that we could add a
lint to warn about things that should not be live across yields (e.g.,
lock guards), and I think that's a great idea (there is a [clippy
lint] already, though it's specific to `MutexGuard`; maybe this should
just be promoted to the compiler and generalized).

[LF]: https://zulip-archive.rust-lang.org/187312wgasyncfoundations/81944meeting20200428.html#195598667
[clippy lint]: https://github.com/rust-lang/rust-clippy/issues/4226

Another, more challenging area is improving the precision of the
async-await transformation and analysis. Right now, for example, the
compiler "overapproximates" what values are live across a yield, which
sometimes yields spurious errors about whether a future needs to be
`Send` or not. Fixing this is, um, "non-trivial", but it would be a
major quality of life improvement.

### Polish in the standard library: adding utilities

When it comes to polish, I think we can extend that focus beyond the
compiler, to the standard library and the language. I'd like to see
the stdlib include building blocks like async-aware mutexes and
channels, for example, as well as smaller utilities like
[`task::block_on`]. YoshuaWuyts recently proposed adding some simple
constructors, like [`future::{pending, ready}`] which I think could
fit in this category. A key constraint here is that these should be
libraries and APIs that are portable across all executors and
runtimes.

[`future::{pending, ready}`]: https://github.com/rust-lang/rust/pull/70834
[`task::block_on`]: http://smallcultfollowing.com/babysteps/blog/2020/03/10/async-interview-7-withoutboats/#block_on-in-the-std-library

### Polish in the language: async main, async drop

Polish extends to the language, as well. The idea here is to find
small, contained changes that fix specific pain points or limitations.
Adding `async fn main`, as [boats proposed], might be such an example
(and I rather like the idea of `#[test]` that [XAMPRocky proposed on
internals]).

[boats proposed]: http://smallcultfollowing.com/babysteps/blog/2020/03/10/async-interview-7-withoutboats/#async-fn-main
[XAMPRocky proposed on internals]: https://users.rust-lang.org/t/async-interviews/35167/17?u=nikomatsakis

Another change I think makes sense is to support [async destructors],
and I would go further and adopt find some solution to the concerns
about RAII and async that [Eliza Weisman raised]. In particular, I
think we need some kind of (optional) callback for values that reside
on a stack frame that is being suspended.

[async destructors]: http://smallcultfollowing.com/babysteps/blog/2020/03/10/async-interview-7-withoutboats/#next-step-async-destructors
[Eliza Weisman raised]: http://smallcultfollowing.com/babysteps/blog/2020/02/11/async-interview-6-eliza-weisman/#raii-and-async-fn-doesnt-always-play-well

### Supporting interoperability: the stream trait

Let me talk a bit about what we can do to support interoperability.
The first step, I think, is to do [as Carl Lerche proposed] and add
the [`Stream`] trait into the standard library. Ideally, it would be
added in *exactly* the form that it takes in futures 0.3.4, so that we
can release a (minor) version of futures that simply re-exports the
stream trait from the stdlib.

[as Carl Lerche proposed]: http://smallcultfollowing.com/babysteps/blog/2019/12/23/async-interview-3-carl-lerche/#what-should-we-do-next-stabilize-stream
[`Stream`]: https://docs.rs/futures/0.3.4/futures/stream/trait.Stream.html

Adding stream enables interoperability in the same way that adding
`Future` did: one can now define libraries that produce streams, or
which operate on streams, in a completely neutral fashion.

### But what about "attached streams"?

I said that I did not think adding `Stream` to the standard library
would be controversial. This does not mean there aren't any concerns.
cramertj, in particular, [raised a concern] about the desire for
"attached streams" (or "streaming streams"), as they are sometimes
called.

[raised a concern]: http://smallcultfollowing.com/babysteps/blog/2019/12/10/async-interview-2-cramertj-part-2/

To review, today's `Stream` trait is basically the exact async analog
of `Iterator`. It has a [`poll_next`] method that tries to fetch the
next item. If the item is ready, then the caller of `poll_next` gets
ownership of the item that was produced. This means in particular that
the item cannot be a reference into the stream itself. The same is
true of iterators today: iterators cannot yield references into
themselves (though they *can* yield references into the collection
that one is iterating over). This is both useful (it means that
generic callers can discard the iterator but keep the items that were
produced) and a limitation (it means that iterators/streams cannot
reuse some internal buffer between iterations).

[`poll_next`]: https://docs.rs/futures/0.3.4/futures/stream/trait.Stream.html#tymethod.poll_next

### We should not block progress on streams on GATs

I hear the concern about attached streams, but I don't think it should
block us from moving forward. There are a few reasons for this. The
first is pragmatic: fully resolving the design details around attached
streams will require not only [GATs], but experience with GATs. This
is going to take time and I don't think we should wait. Just as
iterators are used everywhere in their current form, there are plenty
of streaming appplications for which the current stream trait is a
good fit.

[GATs]: http://smallcultfollowing.com/babysteps/blog/2019/12/10/async-interview-2-cramertj-part-2/#the-natural-way-to-write-attached-streams-is-with-gats

### Symmetry between sync and async is a valuable principle

There is another reason I don't think we should block progress on
attached streams. I think there is a lot of value to having symmetric
sync/async versions of things in the standard library. I think boats
had it right when they said that the [guiding vision] for Async I/O in
Rust should be that one can take sync code and make it async by adding
in `async` and `await` as necessary.

[guiding vision]: http://smallcultfollowing.com/babysteps/blog/2020/03/10/async-interview-7-withoutboats/#vision-for-async

This isn't to say that everything between sync and async must be the
same. There will likely be things that only make sense in one setting
or another.  But I think that in cases where we see *orthogonal
problems* -- problems that are not really related to being synchronous
or asynchronous -- we should try to solve them in a uniform way.

In this case, the problem of "attached" vs "detached" is orthogonal
from being async or sync. We want attached iterators just as much as
we want attached streams -- and we are making progress on the
foundational features that will enable us to have them.

Once we have those features, we can design variants of `Iterator` and
`Stream` that support attached iterators/streams. Perhaps these
variants will deprecate the existing traits, or perhaps they will live
alongside them (or maybe we can even find a way to extend the existing
traits in place). I don't know, but we'll figure it out, and we'll do
it for both sync and async applications, well, synchronously[^resist].

[^resist]: I couldn't resist.

### Supporting interoperability: adding async read and write traits

I also think we should add [`AsyncRead`] and [`AsyncWrite`] to the
standard library, also in roughly the form they have today in
futures. In short, stable, interoperable traits for reading and writing enables
a whole lot of libraries and middleware. After all, the main reason
people are using async is to do I/O.

In contrast to [`Stream`], I do expect this to be controversial, for a
few reasons. But much like [`Stream`], I still think it's the right
thing to do, and actually for much the same reasons.

[`AsyncRead`]: https://docs.rs/futures/0.3.4/futures/io/trait.AsyncRead.html
[`AsyncWrite`]: https://docs.rs/futures/0.3.4/futures/io/trait.AsyncWrite.html

### First concern about async read: uninitialized memory

I know of two major concerns about adding `AsyncRead` and
`AsyncWrite`.  The first is around **uninitialized memory**. Just like
its synchronous counterpart [`Read`], the [`AsyncRead`] trait must be
given a buffer where the data will be written. And, just like
[`Read`], the trait currently requires that this buffer must be zeroed
or otherwise initialized. 

You will probably recognize that this is another case of an
"orthogonal problem". Both the synchronous and asynchronous traits
have the same issue, and I think the best approach is to try and solve
it in an analogous way. Fortunately, [sfackler has done just
that][sfackler]. The idea that we discussed in our async interview is
slowly making its way into RFC form.

[`Read`]: https://doc.rust-lang.org/std/io/trait.Read.html
[sfackler]: http://smallcultfollowing.com/babysteps/blog/2020/01/20/async-interview-5-steven-fackler/

So, in short, I think uninitialized memory is a "solved problem", and
moreover I think it was solved in the right way. Happy days.

### Second concern about async read: io_uring

This is a relatively new thing, but a new concern about `AsyncRead`
and `AsyncWrite` is that, fundamentally, they were designed around
[`epoll`]-like interfaces. In these interfaces, you get a callback
when data is ready and then you can go and write that data into a
buffer. But in Linux 5.1 added a new interface, called `io_uring`, and
it works differently. I won't go into the details here, but boats
gives a [good intro] in their blog post introducing the [`iou`]
library.

[`epoll`]: https://en.wikipedia.org/wiki/Epoll
[good intro]: https://boats.gitlab.io/blog/post/iou/
[`iou`]: https://github.com/withoutboats/iou

My take here is somewhat similar to my take on why we should not block
streams on GATs: `io_uring` is super promising, but it's also super
new. We have very little experience trying to build futures atop
`io_uring`. I think it's great that people are experimenting, and I
think that we should encourage and spread those experiments. After
some time, I expect that "best practices" will start to emerge, and at
that time, we should try to codify those best practices into traits
that we can add to the standard library.

In the meantime, though, epoll is not going anywhere. There will
always be systems based on epoll that we will want to support, and we
know exactly how to do that, because we've spend years tinkering with
and experimenting with the [`AsyncRead`] and [`AsyncWrite`]. It's time
to standardize them and to allow people to build I/O libraries based
on them. Once we know how best to handle `io_uring`, we'll integrate
that too.

All of that said, I would really like to learn more about `io_uring`
and what it might mean, since I've not dug that deeply here. Maybe a
good topic for a future async interview!

### Looking further out

Looking further out, I think there are some bigger goals that we
should be thinking about. The largest is probably adding some form of
**generator syntax**. Anecdotally, I definitely hear about a fair
number of folks working with streams and encountering difficulties
doing so. As [boats said], writing `Stream` implementations is a
common reason that people have to interact directly with `Pin`, and
that's something we want to minimize. Further, in a synchronous
setting, generator syntax would also give us syntactic support for
writing iterators, which would benefit Rust overall. **Enabling
support for async functions in traits** would also be high on my list,
along with **async closures**. (The latter in particular would enable
us to bring in a lot more utility methods and combinators for futures
and streams, which would be great.)

[boats said]: http://smallcultfollowing.com/babysteps/blog/2020/03/10/async-interview-7-withoutboats/#supporting-generators-iterators-and-async-generators-streams

I think though that it's worth waiting a bit before we pursue these, for
several reasons.

* Generator syntax would build on a `Stream` trait anyhow, so having
  that in the standard libary is an obvious first step.
* There is ongoing work on GATs and chalk integration in the context
  of wg-traits, and we're making quite rapid progress there. The above
  items all potentially interact with GATs in some way, and it'd be
  nice if we had more of an implementation available before we started
  in on them (though it may not be a hard requirement).
* Quite frankly, we don't have the bandwidth. We need to work on
  building up an effective wg-async-foundations group before we can
  take on these sorts of projects. More on this point later.

### Related and supporting efforts

There are a few pending features in the language team that I think may be pretty
useful for async applications. I won't go into detail here, but briefly:

* `impl Trait` everywhere -- finishing up the `impl Trait` saga will
  enable us to encode some cases where async fn in traits might be
  nice, such as Tower's [`Service`] trait;
* GATs, obviously -- GATs arise around a number of advanced features.
* procedural macros -- we've been making slow and steady progress on
  stabilizing bits and pieces of the procedural macro story, and I
  think it's a crucial enabler for async-related applications (and
  many others). Things like the `#[runtime::main]` and `async-trait`
  crate are only possible because of the procedural macro
  support. Both Carl and Eliza brought up the importance of offering
  procedural macros in expression position without requiring things
  like `proc_macro_hack`.

[`Service`]: https://docs.rs/tower/0.3.0/tower/trait.Service.html

I'll write more about these points in other posts, though.

### Summing up: the list

To summarize, here is my list of what I think we should be doing in
"async land" as our next steps:

* Continued polish and improvements to the core compiler implementation.
* Lints for common "gotchas", like `#[must_use]` to help identify "not yield safe" types.
* Extend the stdlib with mutexes, channels, [`task::block_on`], and other small utilities.
* Extend the `Drop` trait with "lifecycle" methods ("async drop").
* Add `Stream`, `AsyncRead`, and `AsyncWrite` traits to the standard library.

To be clear, this is a **proposal**, and I am very much interested in
feedback on it, and I wouldn't surprised to add or remove a thing or
two. However, it's not an arbitrary proposal: It's a proposal that
I've given a fair amount of thought to, and I feel reasonably certain
about it.

There are a few things I'd be particularly interested to [get feedback][ait] on:

* If you maintain a library, what are some of the challenges you've
  encountered in making it operate generically across executors? What
  could help there?
* Do you have ideas for useful bits of polish? Are there small changes or stdlib
  additions that would make everyday life that much easier?

### A challenge: growing an effective working group

I want to close with a few comments on organization. One of the things
we've been trying to figure out is how best to organize ourselves and
create a sustainable working group.

Thus far, [tmandry] has been doing a great job at organizing the
polish work that has been our focus, and I think we've been making
good progress there, although there's always a need for more folks to
help out. (Shameless plug: [Here are some tips for how to get
involved][g-i]!)

**If we want to go beyond polish and get back to adding things to the
standard library, especially things like the `Stream` or `AsyncRead`
trait, we're going to have to up our game.** The same is true for some
of the more diverse tasks that fall under our umbrella, such as
maintaining the [async book].

[async book]: https://rust-lang.github.io/async-book/index.html

To do those tasks, we're going to need [more than coders]. We need to
take the time to draft designs, incorporate feedback, write the RFCs,
and push things through to stabilization.

[more than coders]: http://smallcultfollowing.com/babysteps/blog/2019/04/15/more-than-coders/

To be honest, I'm not entirely sure where that work is going to come
from -- but I believe we can do it! If this is something you're
interested in, definitely drop in the `#wg-async-foundations` stream
on Zulip and say hello, and monitor the [Inside Rust], as I expect
we'll be posting updates there from time to time.

[Inside Rust]: https://blog.rust-lang.org/inside-rust/

### Comments?

As always, please leave comments in the [async interviews thread][ait]
on `users.rust-lang.org`.

[ait]: https://users.rust-lang.org/t/async-interviews/35167/

### Footnotes
