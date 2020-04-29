---
layout: post
title: 'Async interviews: my take thus far'
categories: [Rust, Async]
---

The point of the [async interview] series, in the end, was to help
figure out what we should be doing next when it comes to Async I/O. I
thought it would be good then to step back and, rather than
interviewing someone else, give my opinion on some of the immediate
next steps, and a bit about the medium to longer term. I'm also going
to talk a bit about what I see as some of the practical challenges.

https://zulip-archive.rust-lang.org/187312wgasyncfoundations/81944meeting20200428.html#195596002

### Focus for the immediate term: interoperability and polish

At the highest level, I think we should be focusing on two things in
the "short to medium" term: **enabling interoperability** and
**polish**.

By **interoperability**, I mean the ability to write libraries and
frameworks that can be used with many different executors/runtimes.
Adding the `Future` trait was a big step in this direction, but
there's plenty more to go.

By **polish**, I mean "small things that go a long way to improving
quality of life for users". These are the kinds of things that are
easy to overlook, because no individual item is a big milestone. We've
been focusing on diagnostics, and we should continue that, but I also
think we want to broaden the scope a bit. On Zulip, for example,
[LucioFranco suggested][LF] that we could add a lint to warn about
things that should not be live across yields (e.g., lock guards).

[LF]: https://zulip-archive.rust-lang.org/187312wgasyncfoundations/81944meeting20200428.html#195598667

### Polish in the standard library

When it comes to polish, I think we can extend that focus beyond the
compiler, to the standard library and the language. I'd like to see
the stdlib include building blocks like async-aware mutexes and
channels, for example, as well as smaller utilities like
`task::block_on`. YoshuaWuyts recently proposed adding some simple
constructors, like [`future::{pending,
ready}`](https://github.com/rust-lang/rust/pull/70834) which I think
could fit in this category.

### Polish in the language

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
`Stream` that support attached iterator. Perhaps these variants will
deprecate the existing traits, or perhaps they will live alongside
them (or maybe we can even find a way to extend the existing traits in
place). I don't know, but we'll figure it out, and we'll do it for
both sync and async applications, well, synchronously[^resist].

[^resist]: I couldn't resist.

### Supporting interoperability: adding async read and write traits

I also think we should add [`AsyncRead`] and [`AsyncWrite`] to the
standard library, also in roughly the form they have today in
futures. In contrast to [`Stream`], I do expect this to be
controversial, for a few reasons. But much like [`Stream`], I still
think it's the right thing to do, and actually for much the same reasons.

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
on them.

### Real artists ship

You may have noticed a theme here, but I think it's worth stating it
explicitly: Real artists ship! Actually, I am just now reading the
story on [folklore.org] about this, and it seems like the quote was
meant to endorse super stressful all nighters. That's not what I think
about when I hear it. I think about how there are always "new and
better" things on the horizon, but at some point you have to stop
improving, and start building.

[folklore.org]: https://www.folklore.org/StoryView.py?story=Real_Artists_Ship.txt

Moreover, once you do so, there is always room to come back and make
improvements, release a 2.0 release, and so forth. The only reason
that a 2.0 release would be difficult is because so many people have
been building and shipping successful systems on the thing you made,
and they don't want to change -- and that's not so bad, is it?

Anyway, there's obviously some give and take here, but it seems to me
that when it comes to both `Stream` and `AsyncRead` and `AsyncWrite`,
it's time for us to move forward.

### Some things I think we should not do

There are a few things I think we should *not* do

### An interesting wildcard: generator syntax


### XXXX

Some passing thoughts:

There are some themes and principles.

There is a slogan here, "cross that bridge when we come to it", or
perhaps "true artists ship", that we should be establishing as a
guiding principle?

The need for 
