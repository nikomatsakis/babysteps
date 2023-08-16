---
categories:
- Rust
- AsyncInterviews
date: "2019-12-10T00:00:00Z"
slug: async-interview-2-cramertj-part-2
title: 'Async Interview #2: cramertj, part 2'
---

This blog post is continuing [my conversation with cramertj](http://smallcultfollowing.com/babysteps/blog/2019/12/09/async-interview-2-cramertj/).

In the first post, I covered what we said about Fuchsia,
interoperability, and the organization of the futures crate.  This
post covers cramertj's take on the [`Stream`] trait as well as the
[`AsyncRead`] and [`AsyncWrite`] traits.

You can watch the [video] on YouTube.

[video]: https://youtu.be/NF_qyiypnOs

### The need for "streaming" streams and iterators

Next, cramertj and I turned to discussing some of the specific traits
from the futures crate. One of the traits that we covered was
[`Stream`]. The [`Stream`] trait is basically the asynchronous version
of the [`Iterator`] trait. In (slightly) simplified form, it is as
follows:

[`AsyncRead`]: https://docs.rs/futures/0.3.1/futures/io/trait.AsyncRead.html
[`AsyncWrite`]: https://docs.rs/futures/0.3.1/futures/io/trait.AsyncWrite.html
[`Stream`]: https://docs.rs/futures-core/0.3.1/futures_core/stream/trait.Stream.html
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

In practice, many stream/iterator implementations would be more
efficient if they could have some internal storage that they re-use
over and over. For example, they might have an internal buffer, and
when `poll_next` is called, they would give back (upon completion) a
**reference** to that buffer. The idea would be that once `poll_next`
is called again, they would start to re-use the same buffer.

### Terminology note: Detached/attached instead of "streaming"

The idea of having an iterator that re-uses an internal buffer has
come up before. In that context, it was often called a "streaming
iterator", which I guess means that we want a "streaming stream".
This is pretty clearly a suboptimal term.

In the call, I mentioned the term "detached", which I sometimes use to
refer to the current `Iterator`/`Stream`.  The idea is that `Item`
that gets returned by `Stream` is "detached" from `self`, which means
that it can be stored and moved about independently from `self`. In
contrast, in a "streaming stream" design, the return value may be
borrowed from `self`, and hence is "attached" -- it can only be used
so long as the `self` reference remains live.

I'm not really sure that I care for this terminology. I sort of prefer
"owned/borrowing iterator", where the idea is in an owned iterator,
the iterator transfers ownership of the data to you, and in borrowing
iterator, the data you get back is borrowed from the iterator
itself. However, I fear that these terms will be confused for the
distinction between `vec.into_iter()` and `vec.iter()`. Both of these
methods exist today, of course, and they both yield "detached"
iterators; however, the former takes ownership of `vec` and the latter
borrows from it. The key point is that `vec.iter()` is giving back
borrowed values, but they are borrowed *from the vector*, not from the
*iterator*.

(One final note is that this same concept of 'attached' vs 'detached'
will come up when discussing async closures again, which further
argues for using terminology other than "streaming".)

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

### Things that consume streams would typically want an attached stream

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

In fact, generators give a nice way to get an intuitive understanding
of the difference between "attached" and "detached" streams: given
attached streams, a generator yield could return references to local
variables.  But if we only have detached streams, as today, then you
could only yield things that you own or things that were borrowed from
your caller (i.e., references derived from other references that you
got as parameters). In other words, yield would have the same
limitations as return does today.

### The `AsyncRead` and `AsyncWrite` traits

Next cramertj and I discussed the [`AsyncRead`] and [`AsyncWrite`]
traits.  As currently defined in [`futures-io`], these traits are the
"async analog" of the corresponding synchronous traits [`Read`] and
[`Write`]. For example, somewhat simplified, [`AsyncRead`] looks like:

[`futures-io`]: https://crates.io/crates/futures-io
[`Read`]: https://doc.rust-lang.org/std/io/trait.Read.html
[`Write`]: https://doc.rust-lang.org/std/io/trait.Write.html

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
so I won't either (this blog post is already long enough). I hope to
dig into it in future interviews. The main point that cramertj made is
that the same issue affects the standard `Read` trait and that it
would make sense to address the design in the same way in both traits.
(Indeed, there have been attempts to modify the trait to deal with
(e.g., the [`initializer`][sync-init] method, which also has an
[analogue in the `AsyncRead` trait][async-init]).)

[sync-init]: https://doc.rust-lang.org/std/io/trait.Read.html#method.initializer
[async-init]: https://docs.rs/futures/0.3.1/futures/io/trait.AsyncRead.html#method.initializer

cramertj's preferred solution to the problem would be to have some
"freeze" function that can take uninitialized memory and "bless" it
such that it can be accessed without UB, though it would contain
"random" bytes (this is basically what people intuitively expected
from uninitialized memory, though in fact it is [not an accurate
model][uninit]). Unfortunately, figuring out how to implement such a
thing in LLVM is a pretty open question, and there are also other
problems (such as linux's `MADV_FREE` feature) that may make this
infeasible.

[uninit]: https://www.ralfj.de/blog/2019/07/14/uninit.html

**EDIT:** An earlier draft of this post mistakely said that we would
want some "poison" function, but really the proper term is "freeze".
In other words, some function that -- given a bit of uninitialized
data -- makes it initialized but with some arbitrary value.

### Conclusion

This was part two of my conversation with cramertj. Stay tuned for
part 3, where we talk about async closures!
  
## Comments?

There is a [thread on the Rust users forum](https://users.rust-lang.org/t/async-interviews/35167/) for this series.
