For the second async interview, I spoke with Taylor Cramer -- or
cramertj, as I'll refer to him. cramertj is a member of the compiler
and lang teams and was -- until recently -- working on Fuschia at
Google. They've been a key player in Rust's Async I/O design and in
the discussions around it. They were also responsible for a lot of the
implementation work to make `async fn` a reality.

### On Fuschia

We kicked off the discussion talking a bit about the particulars of
the Fuschia project. Fuschia is a microkernel architecture and thus a
lot of the services one finds in a typical kernel are implemented as
independent Fuschia processes. These processes are implemented in Rust
and use Async I/O. This means that, in Fuschia, two things

### Fuschia uses its own unique executor and runtime

Because Fuschia is not a unix system, it doesn't have concepts like
epoll or unix sockets. Fuschia therefore uses its own custom executor
and runtime, rather than building on a separate stack like tokio or
async-std.

### Fuschia benefits from interoperability

Even though Fuschia uses its own executor, it is able to reuse a lot
of libraries from the ecosystem. For example, Fuschia uses Hyper for
its HTTP parsing. This is possible because Hyper offers a generic
interface based on traits that Fuschia can implement.

In general, cramertj feels that the best way to achieve interop is to
offer trait-based interfaces. There are other projects, for example,
that offer feature flags (e.g., to enable "tokio" compatibilty etc),
but this tends to be a suboptimal way of managing things, at least for
libraries. 

For one thing, offer features means that support for systems like fuschia
must be "upstreamed" into the project, whereas offering traits means that
downsteam systems can implement the traits themselves.

In addition, using features to choose between alternatives can cause
problems across larger dependency graphs. Features are always meant to
be "additive" -- i.e,. you can add any number of them -- but features
that choose between backends tend to be exclusive -- i.e., you must
choose at most one. This is a problem because cargo likes to take the
union of all features across a dependency graph, and so having
exclusive features can lead to miscompilations when things are
combined.

### Background topic: futures crate

cramertj and I next talked some about the futures crate. Before going
much further into that, I want to give a bit of background on the
futures crate itself and how its setup.

The futures crate has been very carefully setup to permit its
components to evolve with minimal breakage and incompatibility across
the ecosystem.  However, my experience from talking to people has been
that there is a lot of confusion as to how the futures crate is setup
and why, and just how much they can rely on things not to change. So I
want to spend a bit of time documenting *my* understanding the setup
and its motivations.

Historically, the [`futures`] crate has served as a kind of
experimental "proving ground" for various aspects of the future
design, including the `Future` trait itself (which is now in std).

Currently, the futures crate is at version 0.3, and it offers a number of
different categories of functionality:

[`futures`]: https://github.com/rust-lang-nursery/futures-rs/

* key traits like `Stream`, `AsyncRead`, and `AsyncWrite`
* key primitives like ["async-aware" locks]
    * traditional locks
* "extension" traits like [`FutureExt`], [`StreamExt`], [`AsyncReadExt`], and so forth
    * these traits offer convenient combinator methods like `map` that
      are not part of the corresponding base traits
* useful macros like [`join!`] or [`select!`]
* useful bits of code such as a [`ThreadPool`] for "off-loading" heavy computations

[`FutureExt`]: https://docs.rs/futures/0.3.1/futures/future/trait.FutureExt.html
[`StreamExt`]: https://docs.rs/futures/0.3.1/futures/stream/trait.StreamExt.html
[`AsyncReadExt`]: https://docs.rs/futures/0.3.1/futures/io/trait.AsyncReadExt.html
[`join!`]: https://docs.rs/futures/0.3.1/futures/macro.join.html
[`select!`]: https://docs.rs/futures/0.3.1/futures/macro.select.html
[locks]: https://docs.rs/futures/0.3.1/futures/lock/index.html
[`ThreadPool`]: https://docs.rs/futures/0.3.1/futures/executor/struct.ThreadPool.html

In fact, the first item in that list ("key traits") is quite distinct
from the remaining items. In particular, if you are writing a library,
those key traits are things that you might well like to have in your
public interface. For example, if you are writing a parser that
operates on a stream of data, it might take a [`AsyncRead`] as its
data source (just as a synchronous parser would take a [`Read`]).

The remaining items on the list fall *generally* into the category of
"implementation details". They ought to be "private" dependencies of
your crate.  For example, you may use methods from [`FutureExt`]
internally, but you don't require other crates to use them; similarly
you may [`join!`] futures internally, but that is not something that
would show up in a function signature.

### the futures crate is really a facade

One thing you'll notice if you look more closely at the [`futures`]
crate is that it is in fact composed of a number of smaller crates.
The [`futures`] crate itself simply 're-exports' items from these
other crates:

* `futures-core` -- defines the [`Stream`] trait (also the `Future`
  trait, but that is an alias for std)
* `futures-io` -- defines the [`AsyncRead`] and [`AsyncWrite`] traits
* `futures-util` -- defines extension traits like [`FutureExt`]
* ...

The goal of this facade is to permit things to evolve without forcing
semver-incompatible changes. For example, if the [`AsyncRead`] trait
should evolve, we might be forced to issue a new major version of
`futures-io` and thus ultimately issue a new `futures` release (say,
0.4). However, the version number of `futures-core` remains
unchanged. This means that if your crate only depends on the `Stream`
trait, it will be interoperable across both `futures` 0.3 and 0.4,
since both of those versions are in fact re-exporting the same
`Stream` trait (from `futures-core`, whose version has not changed).

In fact, if you are a library crate, it probably behooves you to avoid
depending on the [`futures`] crate at all, and instead to declare
finer-grained dependencies; this will make it very clear whe you need
to declare a new semver release yourself.

### cramertj: the best place for "standard" traits is in std

So, background aside, let me return to my discussion with
cramertj. One of the points that cramertj is that the only "truly
standard" place for a trait to live is libstd. Therefore, cramertj
feels like the next logical step for traits like `Stream` or
`AsyncRead` is to start moving them into the standard library.  Once
they are there, this would be the strongest possible signal that
people can rely on them not to change.

### we can move to libstd without breakage

You may be wondering what it would mean if we moved one of the traits
from the [`futures`] crate into libstd -- would things in the
ecosystem that are currently using [`futures`] have to update? The
answer is no, not necessarily.

Presuming that some trait from [`futures`] is moved wholesale into
libstd (i.e., without *any* modification), then it is possible for us
to simply issue a new *minor version* of the [`futures`] crate (and
the appropriate subcrate). This new minor version would change from
defining a trait (say, `Stream`) to re-exporting the version from std.

As a concrete example, if we moved [`AsyncRead`] from [`futures-io`]
to libstd (as cramertj advocates for later on), then we would issue a
`0.3.2` release of [`futures-io`]. This release would replace `trait
AsyncRead` with a `pub use` that re-exports `AsyncRead` from std. Now,
any crate in the ecosystem that previously depended on `0.3.1` can be
transparently upgraded to `0.3.2` (it's a semver-compatibly change,
after all)[^unifying-minor-version], and suddenly all references to
`AsyncRead` would be referencing the version from std. (This is, in
fact, exactly what happened with the futures trait; in 0.3.1., it is
simply [re-exported from libcore].)

[re-exported from libcore]: https://docs.rs/futures-core/0.3.1/src/futures_core/future.rs.html#7

[^unifying-minor-version]: This change relies on the fact that cargo will generally not compile two distinct minor versions of a crate; so all crates that depend on `0.3.1` would be compiled against `0.3.2`.

[`futures-io`]: https://crates.io/crates/futures-io

### The stream trait maybe should be streaming

Next, cramertj and I turned to discussing some of the specific traits
from the futures crate. One of the traits that we covered was stream.

The [current `Stream`
trait](https://docs.rs/futures-core/0.3.1/src/futures_core/stream.rs.html#27-93)
found in [`futures-core`] is very similar to the [`Iterator`] trait, but
asynchronous. In (slightly) simplified form, it is as follows:

[`Iterator`]: https://doc.rust-lang.org/std/iter/trait.Iterator.html

```rust
pub trait Stream {
    type Item;
    fn poll_next(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
    ) -> Poll<Option<Self::Item>>;
}
```

The main concern that cramertj raised with this trait is that, like
`Iterator`, it always gives ownership of each item back to its
caller. This falls out from its structure, which requires the
implementor to specify an `Item` type, and that `Item` type cannot
borrow from the `self` reference given to `poll_next`.

In practice, many stream implementors might like to have some internal
storage that they re-use over and over. For example, they might have
an internal buffer, and when `poll_next` is called, they would give
back (upon completion) a **reference** to that buffer. The idea would
be that once `poll_next` is called again, they would start to re-use
the same buffer.

In fact, the same thing would be useful for standard synchronous
iterators.  It is sometimes called a "streaming iterator". Hence, one
might wish to have a "streaming stream". Obviously this terminology is
sub-optimal. I'm not sure what the best terminology is. 

In the call, I mentioned the term "detached", which I sometimes use to
refer to the current `Iterator`/`Stream`.  The idea is that `Item`
that gets returned by `Stream` is "detached" from `self`, which means
that it can be stored and moved about independently from `self`. In
contrast, in a "streaming stream" design, the return value may be
borrowed from `self`, and hence is "attached" -- it can only be used
so long as the `self` reference remains live.

In truth, I sort of prefer "borrowing/owned iterator" to
"attached/detached iterator", because it seems to introduce fewer
terms. However, I fear that these terms will be confused for the
distinction between `vec.into_iter()` and `vec.iter()`. Both of these
methods exist today, of course, and they both yield "detached"
iterators; however, the former takes ownership of `vec` and the latter
borrows from it. The key point is that `vec.iter()` is giving back
borrowed values, but they are borrowed *from the vector*, not from the
*iterator*.

### The natural way to write "attached" streams is with GATs

In any case, the challenge here is that, without generic associated
types, there is no nice way to write the "attached" (or "streaming")
version of `Stream`. You really want to be able to write a definition
like:

```rust
trait AttachedStream {
    type Item<'s> where Self: 's;
    //       ^^^^ ^^^^^^^^^^^^^^ (we likely need an annotation like this
    //       |                    too, for reasons I'll cover in an appendix)
    //       note the `'s` here!

    fn poll_next<'s>(
        self: Pin<&'s mut Self>,
        cx: &mut Context<'_>,
    ) -> Poll<Option<Self::Item<'s>>>;
    //                         ^^^^
    // `'s` is the lifetime of the `self` reference.
    // Thus, the `Item` that gets returned may
    // borrow from `self`.
}
```

### "Attached" streams would be used differently than the current ones

There are real implications to adopting an "attached" definition of
stream or iterator.  In short, particularly in a generic context where
you don't know all the types involved, you wouldn't be able to get
back two values from an "attached" stream/iterator at the same time,
whereas you can with the "detached" streams and iterators we have
today.

For the most common use case of iterating over each element in turn,
this doesn't matter, but it's easy to define functions that rely on
it. Let me illustrate with `Iterator` since it's easier. Today, this
code compiles:

```rust
/// Returns the next two elements in the iterator.
/// Panics if the iterator doesn't have at least two elements.
fn first_two<I>(iterator: I) -> (I::Item, I::Item) 
where 
    I: Iterator,
{
    let first_item = iterator.next().unwrap();
    let second_item = iterator.next().unwrap();
    (first_item, second_item) 
}
```

However, given an "attached" iterator design, the first call to `next`
would "borrow" `iterator`, and hence you could not call `next()` again
so long as `first_item` is still in use.

### Concerns with blocking the streaming trait

If I may editorialize a bit, in re-watching the video, I had a few thoughts:

First, I don't want to block a stable `Stream` on generic associated
types. I do think we should prioritize shipping GATs and I would
expect to see progress nex year, but I think we need *some* form of
`Stream` sooner than that.

Second, the existing `Stream` is very analogous to
`Iterator`. Moreover, there has been a long-standing desire for
attached iterators. Therefore, it seems reasonable to move forward
with stabilizing stream today, and then expect to revisit both traits
in a consistent fashion once generic associated types are available.

### "Detached" streams can be converted into "attached" ones

Let's assume then that we choose to stabilize `Stream` as it exists
today. Then we may want to add an `AttachedStream` later on.  In
principle, it should then be possible to add a "conversion" trait such
that anything which implements `Steam` also implements
`AttachedStream`:

```
impl<S> AttachedStream for S
where
    S: Stream,
{
    type Item<'_> = S::Item;
    
    fn poll_next<'s>(
        self: Pin<&'s mut Self>,
        cx: &mut Context<'_>,
    ) -> Poll<Option<Self::Item<'s>>> {
        Stream::poll_next(self, cx)
    }
}
```

The idea here is that the `AttachedStream` trait gives the
*possibility* of returning values that borrow from `self`, but it
doesn't *require* that the returned values do so.

As far as I know, the above scheme above would work. In general,
interconversion traits like these sometimes are tricky around
coherence, but you can typically get away with "one" such impl. It
would mean that types can implement `AttachedStream` if they need to
re-use an internal buffer and `Stream` if they do not, which is a
reasonable design. (I'd be curious to know if there are fatal flaws
here.)

### Things that consume streams would typically want `AttachedStream`

One downside of adding `Stream` now and `AttachedStream` later is that
functions which *consume* streams would at first all be written to work with `Stream`,
when in fact they probably would later want to be rewritten to take `AttachedStream`.
In other words, given some code like:

```rust
fn consume_stream(s: impl Stream) { .. }
```

it is quite likely that the signature should be `impl
AttachedStream`. The idea is that you only want to "consume" a stream
if you need to have two items from the stream existing at the same
time. Otherwise, if you're jus going to iterate over the stream one
element at a time, attached stream is the more general variant.

### Syntactic support for streams and iterators

cramertj and I didn't talk *too* much about it directly, but there
have been discussion about adding two forms of syntactic support for
streams/iterators. The first would be to extend the for loop so that
it works over streams as well, as boats covers in their blog post on
[for await loops][].

The second would be to add a new form of "generator", as found in many
other languages. The idea would be to introduce a new form of
function, written `gen fn` in synchronous code and `async gen fn` in
asynchronous code, that can contain `yield` statements. Calling such a
function would yield an `impl Iterator` or `impl Stream`, for sync and
async respectively.

[for await loops]: https://boats.gitlab.io/blog/post/for-await-i/

One point that cramertj made is that we should hold off on adding
syntactic support until we have some form of "attached" stream trait
-- or at least until we have a fairly clear idea what its design will
be. The idea is that we would likely want (e.g.) a for-await sugar to
operate over both detached and attached streams, and similarly we may
want `gen fn` to generate attached streams, or to have the ability to
do so.

### The `AsyncRead` and `AsyncWrite` traits

Next cramertj and I discussed the [`AsyncRead`] and [`AsyncWrite`]
traits.  As currently defined in [`futures-io`], these traits are the
"async analog" of the corresponding synchronous traits [`Read`] and
[`Write`]. For example, somewhat simplified, [`AsyncRead`] looks like:

```rust
trait AsyncRead {
    fn poll_read(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut [u8],
    ) -> Poll<Result<usize, Error>>;
}
```

These have been a topic of recent discussion because the tokio crate
has been [considering adopting a new definition of
`AsyncRead`/`AsyncWrite`][tokio#1744]. The primary concern has to do
with the `buf: &mut [u8]` method. This method is supplying a buffer
where the data should be written. Therefore, typically, it doesn't
really matter what the contents of that buffer when the function is
called, as it will simply be overwritten with the data
generated. *However,* it is of course *possible* to write a
`AsyncRead` implementation that does read from that buffer. This means
that you can't supply a buffer of uninitialized bytes, since reading
from uninitialized memory is undefined behavior and can cause LLVM to
perform mis-optimizations.

[tokio#1744]: https://github.com/tokio-rs/tokio/pull/1744

cramertj and I didn't go too far into discussing the alternatives here
so I won't either (this blog post is already *way* too long). I hope
to dig into it in future interviews. The main point that cramertj made
is that the same issue effects the standard `Read` trait, and indeed
there have been attempts to modify the trait to deal with (e.g., the
[`initializer`][sync-init] method, which also has an [analogue in the
`AsyncRead` trait][async-init]). cramertj felt that it makes sense for
the sync and async I/O traits to be consistent in their handling of
uninitialized memory.

[sync-init]: https://doc.rust-lang.org/std/io/trait.Read.html#method.initializer
[async-init]: https://docs.rs/futures/0.3.1/futures/io/trait.AsyncRead.html#method.initializer


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

The only thing you can write is a closure that returns an async block:

```rust
let foo = || async move { ... };
```



