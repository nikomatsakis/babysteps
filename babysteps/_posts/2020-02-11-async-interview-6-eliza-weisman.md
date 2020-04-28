---
layout: post
title: 'Async Interview #6: Eliza Weisman'
categories: [Rust, AsyncInterviews]
---

Hello! For the latest [async interview], I spoke with Eliza Weisman
([hawkw], [mycoliza on twitter]). Eliza first came to my attention as the author of the
[tracing] crate, which is a nifty crate for doing application level
tracing. However, she is also a core maintainer of tokio, and she
works at Buoyant on the [linkerd] system. [linkerd] is one of a small
set of large applications that were build using 0.1 futures -- i.e.,
before async-await. This range of experience gives Eliza an interesting
"overview" perspective on async-await and Rust more generally.

[mycoliza on twitter]: https://twitter.com/mycoliza
[linkerd]: https://linkerd.io/
[hawkw]: https://github.com/hawkw/
[async interview]: http://smallcultfollowing.com/babysteps/blog/2019/11/22/announcing-the-async-interviews/
[tracing]: https://crates.io/crates/tracing

### Video

You can watch the [video] on YouTube. I've also embedded a copy here
for your convenience:

[video]: https://youtu.be/bCf9K28TqVQ

<center><iframe width="560" height="315" src="https://www.youtube.com/embed/bCf9K28TqVQ" frameborder="0" allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe></center>

### The days before question mark

Since I didn't know Eliza as well, we started out talking a bit about
her background. She has been using Rust for 5 years, and I was amused
by how she characterized the state of Rust when she got started:
pre-"question mark" Rust. Indeed, the introduction of the `?` operator
does feel one of those "turning points" in the history of Rust, and
I'm quite sure that `async`-`await` will feel similarly (at least for
some applications).

One interesting observation that Eliza made is that it feels like Rust
has reached the point where there is nothing *critically missing*.
This isn't to say there aren't things that need to be improved, but
that the number of "rough edges" has dramatically decreased. I think
this is true, and we should be proud of it -- though we also shouldn't
relax too much. =) Getting to learn Rust is still a significant hurdle
and there are still a number of things that are much harder than they
need to be.

One interesting corrolary of this is that a number of the things that
most affect Eliza when writing Async I/O code are **not specific to
async I/O**.  Rather, they are more general features or requirements
that apply to a lot of different things.

### Tokio's needs

We talked some about what [tokio] needs from async Rust. As Eliza
said, many of the main points already came up in [my conversation with
Carl][carl]:

* async functions in traits would be great, but [they're hard][async-fn-in-traits]
* stabilizing streams, async read, and async write would be great

[tokio]: https://tokio.rs/
[carl]: http://smallcultfollowing.com/babysteps/blog/2019/12/23/async-interview-3-carl-lerche/
[async-fn-in-traits]: http://smallcultfollowing.com/babysteps/blog/2019/10/26/async-fn-in-traits-are-hard/

### Communicating stability

One thing we spent a fair while discusing is how to best
**communicate** our stability story. This goes beyond "semver".
semver tells you *when a breaking change has been made*, of course,
but it doesn't tell *whether a breaking change will be made in the
future* -- or how long we plan to do backports, and the like.

The easiest way for us to communicate stability is to move things
to the std library. That is a clear signal that breaking changes
will **never** be made.

But there is room for us to set "intermediate" levels of stability.
One thing that might help is to make a **public stability policy** for
crates like `futures`. For example, we could declare that the futures
crate will maintain compatibility with the current `Stream` crate for
the next year, or two ears.

These kind of timelines would be helpful: for example, tokio plans to
[maintain a stable interface for the next 5 years][policy], and so if
they want to expose traits from the `futures` crate, they would want a
guarantee that those traits would be supported during that period (and
ideally that futures would not release a semver-incompatible version
of those traits).

[policy]: https://tokio.rs/blog/2019-11-tokio-0-2/#tokio-1-0-in-q3-2020-with-lts-support

### Depending on community crates

When we talk about interoperability, we are often talking about core
traits like `Future`, `Stream`, and `AsyncRead`. But as we move up the
stack, there are other things where having a defined standard could be
really useful. My go to example for this is the [http] crate, which
defines a number of types for things like HTTP error codes. The types
are important because they are likely to find their way in the "public
interface" of libraries like hyper, as well as frameworks and things.
I would like to see a world where web frameworks can easily be
converted between frameworks or across HTTP implementations, but that
would be made easier if there is an agreed upon standard for
representing the details of a HTTP request. Maybe the [http] crate is
that already, or can become that -- in any case, I'm not sure if the
stdlib is the right place for such a thing, or at least not for some
time. It's something to think about. (I do suspect that it might be
useful to move such crates to the Rust org? But we'd have to have a
good story around maintainance.) Anyway, I'm getting beyond what was
in the interview I think.

[http]: https://crates.io/crates/http

### Tracing

We talked a fair amount about the [tracing] library. Tracing is one of
those libraries that can do a large number of things, so it's kind of
hard to concisely summarize what it does. In short, it is a set of
crates for collecting *scoped, structured, and contextual diagnostic
information* in Rust programs. One of the simplest use cases is to
collect logging information, but it can also be used for things like
profiling and any number of other tasks.

I myself started to become interesting in tracing as a possible tool
to help for debugging and analyzing programs like rustc and chalk,
where the "chain" that leads to a bug can often be quite complex and
involve numerous parts of the compiler. Right now I tend to just dump
gigabytes of logs into files and traverse them with grep. In so doing,
I lose all kinds of information (like hierarchical information about
what happens during what) that would make my life easier. I'd love a
tool that let me, for example, track "all the logs that pertain to a
particular function" while also making it easy to find the context in
which a particular log occurred.

The [tracing] library got its start as a structured replacement for
various hacky layers atop the `log` crate that were in use for
debugging [linkerd]. Like many async applications, debugging a
[linkerd] session involves correlating a lot of events that may be
taking place at distinct times -- or even distinct *machines* -- but
are still part of one conceptual "thread" of control.

[tracing] is actually a "front-end" built atop the "tracing-core"
crate. tracing-core is a minimal crate that just stores a thread-local
containing the current "event subscriber" (which processes the tracing
events in some way). You don't interact with tracing-core directly,
but it's important to the overall design, as we'll see in a bit.

The tracing front-end contains a bunch of macros, rather like the
`debug!` and `info!` you may be used to from the log crate (and indeed
there are crates that let you use those `debug!` logs directly).  The
major one is the `span!` macro, which lets you declare that a task is
happening.  It works by putting a "placeholder" on the stack: when
that placeholder is dropped, the task is done:

```rust
let s: Span = span!(...); // create a span `s`
let _guard = s.enter(); // enter `s`, so that subsequent events take place "in" `s`
let t: Span = span!(...); // create a *subspan* of `s` called `t`
...
```

Under the hood, all of these macros forward to the "subscripber" we
were talking about later. So they might receive events like "we
entered this span" or "this log was generated". 

The idea is that events that happen inside of a span inherit the
context of that span. So, to jump back to my compiler example, I might
use a span to indicate which function is currently being type-checked,
which would then be associated with any events that took place.

There are many different possible kinds of subscribers. A subscriber
might, for example, dump things out in real time, or it might just
collectevents and log them later.  Crates like [tracing-timing] record
inter-event timing and make histograms and flamegraphs.

[tracing-timing]: https://crates.io/crates/tracing-timing

### Integrating tracing with other libraries

It seems clear that tracing would work best if it is integrated with
other libaries. I believe it is already integrated into tokio, but one
could also imagine integrating tracing with rayon, which distributes
tasks across worker threads to run in parallel. The goal there would
be that we "link" the tasks so that events which occur in a parallel
task inherit the context/span information from the task which spawned
them, even though they're running on another thread.

The idea here is not only that Rayon can link up your application
events, but that Rayon can add its own debugging information using
tracing in a non-obtrusive way. In the 'bad old days', tokio used to
have a bunch of `debug!` logs that would let you monitor what was
going on -- but these logs were often confusing and really targeting
internal tokio developers.

With the tracing crate, the goal is that libraries can *enrich* the
user's diagnostics. For example, the hyper library might add metadata
about the set of headers in a request, and tokio might add information
about which thread-pool is in use. This information is all "attached"
to your actual application logs, which have to do with your business
logic. Ideally, you can ignore them most of the time, but if that sort
of data becomes relevant -- e.g., maybe you are confused about why a
header doesn't seem to be being detected by your appserver -- you can
dig in and get the full details.

### Integrating tracing with other logging systems

Eliza emphasized that she would really like to see more
interoperability amongst tracing libraries. The current tracing crate,
for example, can be easily made to emit log records, making it
interoperable with the [log] crate (there is also a "logger" that
implements the tracing interface).

[log]: https://crates.io/crates/log

Having a distinct tracing-core crate means that it possible for there
to be multiple facades that build on tracing, potentially operating in
quite different ways, which all share the same underlying "subscriber"
infrastructure. (rayon uses the same trick; the [rayon-core] crate
defines the underlying scheduler, so that multiple versions of the
rayon `ParallelIterator` traits can co-exist without having multiple
global schedulers.) Eliza mentioned that -- in her ideal world --
there'd be some alternative front-end that is so good it can replaces
the `tracing` crate altogether, so she no longer has to maintain the
macros. =)

[rayon-core]: https://crates.io/crates/rayon-core

### RAII and async fn doesn't always play well

There is one feature request for async-await that arises from the
tracing library. I mentioned that tracing uses a guard to track the
"current span":

```rust
let s: Span = span!(...); // create a span `s`
let _guard = s.enter(); // enter `s`, so that subsequent events take place "in" `s`
...
```

The way this works is that the guard returned by `s.enter()` adds some
info into the thread-local state and, when it is dropped, that info is
withdrawn. Any logs that occur while the `_guard` is still live are
then decorated with this extra span information. **The problem is that
this mechanism doesn't work with async-await.**

As [explained in the tracing README][ex], the problem is that if an
async await function yields during an `await`, then it is removed from
the current thread and suspended. It will later be resumed, but
potentially on another thread altogether. However, the `_guard`
variable is not notified of these events, so (a) the thread-local info
remains set on the original thread, where it may not longer belong and
(b) the destructor which goes to remove the info will run on the wrong
thread.

[ex]: https://github.com/tokio-rs/tracing#in-asynchronous-code

One way to solve this would be to have some sort of callback that
`_guard` can receive to indicate that it is being yielded, along with
another callback for when an async fn resumes. This would probably
wind up being optional methods of the `Drop` trait. This is basically
another feature request to making RAII work well in an async
environment (in addition to the [existing problems with async drop that boats
described here][ad]).

[ad]: https://boats.gitlab.io/blog/post/poll-drop/

### Priorities as a linkerd hacker

I asked Eliza to think for a second about what priorities she would
set for the Rust org while wearing her "linkerd hacker" hat -- in
other words, when acting not as a library designer, but as the author
of an that relies on Async I/O. Most of the feedback here though had
more to do with general Rust features than async-await specifically.

Eliza pointed out that linkerd hasn't yet fully upgraded to use
async-await, and that the vast majority of pain points she's
encountered thus far stem from having to use the older futures model,
which [didn't integrate well with rust borrows][aturon].

[aturon]: http://aturon.github.io/tech/2018/04/24/async-borrowing/

The other main pain point is the compilation time costs imposes by the
deep trait hierarchies created by tower's service and layer
traits. She mentioned hitting a type error that was so long it
actually crashed her terminal. I've heard of others hitting similar
problems with this sort of setup. I'm not sure yet how this is best
addressed.

Another major feature request would be to put more work into
procedural macros, especially in expression position. Right now
`proc-macro-hack` is the tool of choice but -- as the name suggests --
it doesn't seem ideal.

The other major point is that support for cargo feature flags in
tooling is pretty minimal. It's very easy to have code with feature
flags that "accidentally" works -- i.e., I depend on feature flag X,
but I don't specify it; it just gets enabled via some other dependency
of mine. This also makes testing of feature flags hard. rustdoc
integration could be better. All true, all challenging. =)

### Comments?

There is a [thread on the Rust users forum](https://users.rust-lang.org/t/async-interviews/35167/) for this series.




