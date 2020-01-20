---
layout: post
title: 'Async Interview #5: Steven Fackler'
---

Hello! For the latest [async interview], I spoke with Steven Fackler
([sfackler]). sfackler has been involved in Rust for a long time and
is a member of the Rust libs team. He is also the author of [a lot of
crates], most notably [tokio-postgres].

[sfackler]: https://github.com/sfackler/
[a lot of crates]: https://crates.io/users/sfackler
[tokio-postgres]: https://crates.io/crates/tokio-postgres
[async interview]: http://smallcultfollowing.com/babysteps/blog/2019/11/22/announcing-the-async-interviews/

I particularly wanted to talk to sfackler about the `AsyncRead` and
`AsyncWrite` traits. These traits are on everybody's list of
"important things to stabilize", particularly if we want to create
more interop between different executors and runtimes. On the other
hand, in [tokio-rs/tokio#1744], the tokio project is considering
adopting its own variant traits that diverge significantly from those
in the futures crate, precisely because they have concerns over the
design of the traits as is. This seems like an important area to dig
into!

[tokio-rs/tokio#17144]: https://github.com/tokio-rs/tokio/pull/1744

### Video

You can watch the [video] on YouTube. I've also embedded a copy here
for your convenience:

[video]: https://youtu.be/nerrc3L9qrM

<center><iframe width="560" height="315" src="https://www.youtube.com/embed/nerrc3L9qrM" frameborder="0" allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe></center>

One note: something about our setup meant that I was hearing a lot of
echo. I think you can sometimes hear it in the recording, but not
nearly as bad as it was live. So if I seem a bit spacey, or take very
long pauses, you might know the reason why!
## Background: concerns on the async-read trait

So what are the concerns that are motivating [tokio-rs/tokio#17144]?
There are two of them:

* the current traits do not permit using uninitialized memory as the
  backing buffer;
* there is no way to test presently whether a given reader supports
  vectorized operations.

## This blog post will focus on uninitialized memory

sfackler and I spent most of our time talking about uninitialized
memory. We did also discuss vectorized writes, and I'll include some
notes on that at the end, but by and large sfackler felt that the
solutions there are much more straightforward.

## Important: The same issues arise with the sync `Read` trait

Interestingly, neither of these issues is specific to `AsyncRead`.  As
defined today, the `AsyncRead` trait is basically just the async
version of [`Read`] from `std`, and both of these concerns apply there
as well. In fact, part of why I wanted to talk to sfackler
specifically is that he is the author of an [excellent paper
document][doc] that covers the problem of using uninitialized memory
in great depth. A lot of what we talked about on this call is also
present in that document.  Definitely give it a read.

[doc]: https://paper.dropbox.com/doc/MvytTgjIOTNpJAS6Mvw38
[`Read`]: https://doc.rust-lang.org/std/io/trait.Read.html

## Read interface doesn't support uninitialized memory

The heart of the `Read` trait is the `read` method:

```rust
fn read(&mut self, buf: &mut [u8]) -> io::Result<usize>
```

This method reads data and writes it into `buf` and then -- assuming
no error -- returns `Ok(n)` with the number `n` of bytes written.

Ideally, we would like it if `buf` could be an uninitialized buffer.
After all, the `Read` trait is not supposed to be *reading* from
`buf`, it's just supposed to be *writing* into it -- so it shouldn't
matter what data is in there.

## Problem 1: The impl might read from the buf, even if it shouldn't

However, in practice, there are two problems with using uninitialized
memory for `buf`. The first one is relatively obvious: although it
isn't *supposed* to, the `Read` impl can trivially read from `buf` without
using any unsafe code:

```rust
impl Read for MyReader {
  fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
    let x = buf[0];
    ...
  }
}
```

Reading from an uninitialized buffer is Undefined Behavior and could
cause crashes, segfaults, or worse.

## Problem 2: The impl might not really initialize the buffer

There is also a second problem that is often overlooked: when the
`Read` impl returns, it returns a value `n` indicating how many bytes
of the buffer were written. In principle, if `buf` was uninitialized
to start, then the first `n` bytes should be written now -- but *are*
they? Consider a `Read` impl like this one:

```rust
impl Read for MyReader {
  fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
    Ok(buf.len())
  }
}
```

This impl has no unsafe code. It *claims* that it has initialized the
entire buffer, but it hasn't done any writes into `buf` at all! Now if
the caller tries to read from `buf`, it will be reading uninitialized
memory, and causing UB.

One subtle point here. The problem isn't that the read impl could
return a false value about how many bytes it has written. **The
problem is that it can lie without ever using any unsafe code at
all.** So if you are auditing your code for unsafe blocks, you would
overlook this.

## Constraints and solutions

There have been a lot of solutions proposed to this problem. sfackler
and I talked about all of them, I think, but I'm going to skip over
most of the details. You can find them either in the video or in [in
sfackler's paper document][doc], which covers much of the same
material.

In this post, I'll just cover what we said about three of the options:

* First, adding a `freeze` operation.
  * This is in some ways the simplest, as it requires no change to
    `Read` at all.
  * Unfortunately, it has a number of limitations and downsides.
* Second, adding a second `read` method that takes a `&mut dyn BufMut` dyn value.
  * This is the solution initially proposed in [tokio-rs/tokio#1744].
  * It has much to recommend it, but requires virtual calls in a core API, although
    initial benchmarks suggest such calls are not a performance problem.
* Finally, creating a struct `BufMuf` in the stdlib for dealing with partially initialized
  buffers, and adding a `read` method for *that*.
  * This overcomes some of the downsides of using a trait, but at the
    cost of flexibility.

## Digression: how to think about uninitialized memory

Before we go further, let me digress a bit. I think the common
understanding of uninitialized memory is that "it contains whatever
values happen to be in there at the moment". In other words, you might
imagine that when you first allocate some memory, it contains *some*
value -- but you can't predict what that is.

This intuition turns out to be incorrect. This is true for a number of
reasons. Compiler optimizations are part of it. In LLVM, for example,
an uninitialized variable is not assigned to a fixed stack slot or
anything like that. It is instead a kind of "free floating"
"uninitialized" value, and -- whenever needed -- it is mapped to
whatever register or stack slot happens to be convenient at the time
for most optimal code. What this means in practice is that each time
you try to read from it, the compiler will substitute *some* value,
but it won't necessarily be the *same* value every time. This behavior
is justified by the C standard, which states that reading
uninitialized memory is "undefined behavior".

This can cause code to go quite awry. The canonical example in my mind
is the case of a bounds check. You might imagine, for example, that code
like this would suffice for legally accessing an array:

```rust
let index = compute_index();
if index < length {
  return &array[index];
} else {
  panic!("out of bounds");
}
```

However, if the value returned by `compute_index` is uninitialized,
this is incorrect. Because in that case, `index` will also be "the
uninitialized value", and hence each access to it conceptually yields
different values.  So the value that we compare against `length` might
not be the same value that we use to index into the array one line
later. Woah.

But, as sfackler and I discussed, there are actually other layers that
rely on uninitialized memory never being read even below the
kernel. For example, in the linux kernel, the virtual memory system
has a flag called `MADV_FREE`. This flag is used to mark virtual
memory pages that are considered uninitialized.  For each such virtual
page, khe kernel is free to change the physical memory page at will --
*until* the virtual page is written to. At that point, the memory is
potentially initialized, and so the virtual page is pinned. What this
means in practice is that when you get memory back from your
allocator, each read from that memory may yield different values,
unless you've written to it first.

For all these reasons, it is best to think of uninitialized memory not
as having "some random value" but rather as having the value
"uninitialized".  This is special value that can, sometimes, be
converted to a random value when it is forced to (but, if accessed
multiple times, it may yield different values each time).

If you'd like a deeper treatment, I recommend [Ralf's blog post].

[Ralf's blog post]: https://www.ralfj.de/blog/2019/07/14/uninit.html

## Possible solution to read: Freeze operation

So, given the above, what is the freeze operation, and how could it
help with handling uninitialized memory in the `read` API?

The general idea is that we could have a primitive called `freeze`
that, given some (potentially) uninitialized value, converts any
uninititalized bits into "some random value". We could use this to
fix our indexing, for example, by "freezing" the index before we compare
against the length:

```rust
let index = freeze(compute_index());
if index < length {
  return &array[index];
} else {
  panic!("out of bounds");
}
```

In a similar way, if we have a reference to an uninitialized buffer,
we could conceivably "freeze" that reference to convert it to a reference
of random bytes, and then we can safely use that to invoke `read`.
The idea would be that callers do something like this:

```rust
let uninitialized_buffer = ...;
let buffer = freeze(uninitialized_buffer);
let n = reader.read(&mut buffer)?;
...
```

If we could do this, it would be great, because the existing `read`
interface wouldn't have to change at all!

There are a few complications though. First off, there is no such
`freeze` operation in LLVM today. There is talk of adding one, but
that operation wouldn't quite do what we need. For one thing, it
freezes the value it is applied to, but it doesn't apply through a
reference. So you could use it to fix our array bounds length checking
example, but you can't use it to fix `read` -- we don't need to freeze
the `&mut [u8]` *reference*, we need to fix the memory it *refers to*.

Secondly, that primitive would only apply to compiler optimizations.
It wouldn't protect against kernel optimizations like `MADV_FREE`. To
handle that, we have to do something extra, such as writing one byte
per memory page. That's conceivable, of course, but there are some
downsides:

* It feels fragile. What if linux adds some new optimizations in the
  future, how will we work around those?
* It feels disappointing. After all, `MADV_FREE` was presumably added
  because it allows this to be faster -- and we all agree that given a
  "well-behaved" `Read` implementation, it should be reasonable.
* It can be expensive. sfackler pointed out that it is sometimes
  common to "over-provision" your read buffers, such as creating a
  16MB buffer, so as to avoid blocking. This is fairly cheap in
  practice, but only thanks to optimizations (like `MADV_FREE`) that
  allow that memory to be lazilly allocated and so forth. If we start
  writing a byte into every page of a 16MB buffer, you're going to
  notice the difference.
  
For these reasons, sfackler felt like `freeze` isn't the right answer
here. It might be a useful primitive for things like array bounds
checking, but it would be better if we could modify the `Read` trait
in such a way that we permit the use of "unfrozen" uninitialized
memory.

Incidentally, this is a topic we've hit on in previous async
interviews.  [cramertj and I talked about it][ctj2], for example. My
own opinion has shifted -- at first, I thought a freeze primitive was
obviously a good idea, but I've come to agree with sfackler that it's
not the right solution here.

[ctj]: http://smallcultfollowing.com/babysteps/blog/2019/12/10/async-interview-2-cramertj-part-2/#the-asyncread-and-asyncwrite-traits

## Fallback and efficient interoperability

If we don't take the approach of adding a `freeze` primitive, then
this implies that we are going to have to extend the `Read` trait with
some of second method. Let's call it `read2` for short. And this
raises an interesting question: how are we going to handle backwards
compatibility?

In particular, `read2` is going to have a default, so that existing
impls of `Read` are not invalidated. And this default is going to have
to fallback to calling `read`, since that is the only method that we
can guarantee to exist. Since `read` requires a fully initialized
buffer, this will mean that `read2` will have to zero its buffer if it
may be uninitialized. This by itself is ok -- it's no worse than today.

The problem is that some of the solutions discussed in [sfackler's
doc][doc] can wind up having to zero the buffer multiple times,
depending on how things play out. And this could be a big performance
cost. That is definitely to be avoided.

## Possible solution to read: Take a trait object, and not a buffer

Another proposed solution, in fact the one described in [tokio-rs/tokio#1744],
is to modify `read` so it takes a trait object (in the case of the `Read` trait,
we'd have to add a new, defaulted method):

```rust
fn read_buf(&mut self, buf: &mut dyn BufMut) -> io::Result<()>
```

The idea here is that `BufMut` is a trait that lets you safely
access a potentially uninitialized set of buffers:

```rust
pub trait BufMut {
    fn remaining_mut(&self) -> usize;
    unsafe fn advance_mut(&mut self, cnt: usize);
    unsafe fn bytes_mut(&mut self) -> &mut [u8];
    ...
}
```

You might wonder why the definition takes a `&mut dyn BufMut`, rather
than a `&mut impl BufMut`. Taking `impl BufMut` would mean that the
code is specialized to the particular sort of buffer you are using, so
that would potentially be quite a bit faster. However, it would also
make `Read` not "dyn-safe"[^object-safe], and that's a non-starter.

[^object-safe]: Most folks say "object-safe" here, but I'm trying to shift our terminology to talk more about the dyn keyword.

There are some nifty aspects to this proposal. One of them is that the
same trait can to some extent "paper over" vectorized writes, by
distributing the data written across buffers in a chain.

But there are some downsides. Perhaps most important is that requiring
virtual calls to write into the buffer could be a significant
performance hazard. Thus far, measurements don't suggest that, but it
seems like a cost that can only be recovered by heroic compiler
optimizations, and that's the kind of thing we prefer to avoid.

Moreover, the ability to be generic over vectorized writes may not be
as useful as you might think. Often, the caller wants to know whether
the underlying `Read` supports vectorized writes, and it would operate
quite differently in that case. Therefore, it doesn't really hurt to
have two `read` methods, one for normal and one for vectorized writes.

## Variant: use a struct, instead of a trait

The variant that sfackler prefers is to replace the `BufMut` trait
with a struct.[^carl] The API of this struct would be fairly similar
to the trait above, except that it wouldn't make much attempt to unify
vectorized and non-vectorized writes.

[^carl]: Carl Lerche proposed something similar on the tokio thread [here](https://github.com/tokio-rs/tokio/pull/1744#issuecomment-553575438).

Basically, we'd have a struct that encapsulates a "partially
initialized slice of bytes". You could create such a struct from a
standard slice, in which case all things are initialized, or you can
create it from a slice of "maybe initialized" bytes (e.g., `&mut
[MaybeUninit<u8>]`. There can also be convenience methods to create a
`BufMut` that refers to the uninitialized tail of bytes from a `Vec`
(i.e., pointing into the vector's internal buffer).

The safe methods of the `BufMut` API would permit

* writing to the buffer, which will track the bytes that were initialized;
* getting access to a slice, but only one that is guaranteed to be initialized.

There would be unsafe methods for getting access to memory that may be
uninitialized, or for asserting that you have initialized a big swath
of bytes (e.g., by handing the buffer off to the kernel to get written
to).

The buffer has state: it can track what has been initialized. This
means that any given part of the buffer will get zeroed at most
once. This ensures that fallback from the new `read2` method to the
old `read` method is reasonably efficient.

## Sync vs async, how to proceed

So, given the above thoughts, how should we proceed with `AsyncRead`?
sfackler felt that the question of how to handle uninitialized output
buffers was basically "orthogonal" from the question of whether and
when to add `AsyncRead`. In others, sfackler felt that the `AsyncRead`
and `Read` traits should mirror one another, which means that we could
add `AsyncRead` now, and then add a solution for uninitialized memory
later -- or we could do the reverse order.

One minor question has to do with defaults. Currently the `Read` trait
requires an implementation of `read` -- any new method (`read_uninit`
or whatever) will therefore have to have a default implementation that
invokes `read`.  But this is sort of the wrong incentive: we'd prefer
if users implemented `read_uninit`, and implemented `read` in terms of
the new method. We could conceivably reverse the defaults for the
`AsyncRead` trait to this preferred style. Alternatively, sfackler
noted that we could make *both* `read` and `read_uninit` have a
default implementation, one implementing in terms of the other. In
this case, users would have to implement one or the other
(implementing *neither* would lead to an infinite loop, and we would
likely want a lint for that case).

We also discussed what it would mean it tokio adopted its own
`AsyncRead` trait that diverged from std. While not ideal, sfackler
felt like it wouldn't be that big a deal either way, since it ought to
be possible to efficiently interconvert between the two. The main
constraint is having some kind of stateful entity that can remember
the amount of uninitialized data, thus preventing the inefficient
fallover behavior.

## Is the ability to use uninitialized memory even a problem?

We spent a bit of time at the end discussing how one could gain data
on this problem. There are two things that would be nice to know.

First, how big is the performance impact from zeroing? Second, how
ergonomic is the proposed API to use in practice?

Regarding the performance impact, I asked the same question on
[tokio-rs/tokio#17144], and I did get back some interesting results,
[which I summarized in this hackmd at the time][tokio-hackmd]. In
short, hyper's benchmarks show a fairly sizable impact, with
uninitialized data getting speedups[^speedup] of 1.3-1.5x. Other
benchmarks though are much more mixed, showing either no diference or
small differences on the order of 2%. Within the stdlib, we found
about a [7% impact on microbenchmarks][#26950].

[^speedup]: I am defining a "speedup" here as the ratio of `U/Z`, where `U/Z` are the throughput with uninitialized/zeroed buffers respectively.
[tokio-hackmd]: https://hackmd.io/ukeyehx7Ta-6KhaVRFi2mg#Measuring-the-impact
[#26950]: https://github.com/rust-lang/rust/pull/26950

Still, sfackler raised another interesting data point (both [on the
thread] and in our call). He was pointing out [#23820], a PR which
rewrote [`read_to_end`] in the stdlib. The older implementation was
simple and obvious, but suffered from massive performance cliffs
related to the need to zero buffers. The newer implementation is fast,
but much more complex. Using one of the APIs described above would
permit us to avoid this complexity.

[`read_to_end`]: https://doc.rust-lang.org/std/io/trait.Read.html#method.read_to_end
[#23820]: https://github.com/rust-lang/rust/pull/23820
[on the thread]: https://github.com/tokio-rs/tokio/pull/1744#issuecomment-553179399

Regarding ergonomics, as ever, that's a tricky thing to judge. It's
hard to do better than prototyping as well as offering the API on
nightly for a time, so that people can try it out and give feedback.

Having the API on nightly would also help us to make branches of
frameworks like tokio and async-std so we can do bigger measurements.

## Higher levels of interoperability

sfackler and I talked a bit about what the priorities should be beyond
`AsyncRead`. One of the things we talked about is whether there is a
need for higher-level traits or libraries that expose more custom
information beyond "here is how to read data". One example that has
come up from time to time is the need to know, for example, the URL or
other information associated with a request.

Another example might be the role of crates like `http`, which aims to
define Rust types for things like HTTP header codes that are fairly
standard. These would be useful types to share across all HTTP
implementations and libraries, but will we be able to achieve that
sort of sharing without offering the crate as part of the stdlib (or
at last part of the Rust org)? I don't think we had a definitive
answer here.

## Priorities beyond async read

We next discussed what other priorities the Rust org might have
around Async I/O. For sfackler, the top items would be

* better support for GATs and async fn in traits;
* some kind of generator or syntactic support for streams;
* improved diagnostics, particularly around send/sync.

## Conclusion

sfackler and I focused quite heavily on the `AsyncRead` trait
and how to manage uninitialized memory. I think that it would be
fair to summarize the main points of our conversation as:

* we should add `AsyncRead` to the stdlib and have it mirror `Read`;
* in general, it makes sense for the synchronous and asynchronous
  versions of the traits to be analogous;
* we should extend both traits with a method that takes a `BufMut`
  struct to manage uninitialized output buffers, as the other options
  all have a crippling downside;
* we should extend both traits with a "do you support vectorized output?"
  callback as well;
* beyond that, the Rust org should focus heavily on diagnostics for
  async/await, but streams and async fns in traits would be great
  too. =)
  
## Comments?

There is a [thread on the Rust users forum](https://users.rust-lang.org/t/async-interviews/35167/) for this series.

## Appendix: Vectorized reads and writes

There is one minor subthread that I've skipped over -- vectorized
reads and writes. I skipped it in the blog post because this problem
is somewhat simpler. The standard `read` interface takes a single
buffer to write the data into. But a *vectorized* interface takes a
series of buffers -- if there is more data than will fit in the first
one, then the data will be written into the second one, and so on
until we run out of data or buffers. Vectorized reads and writes can
be much more efficient in some cases.

Unfortunately, not all readers support vectorized reads. For that
reason, the "vectorized read" method has a fallback: by default, it
just calls the normal read method using the first non-empty buffer in
the list. This is theoretically equal, but obviously it could be a lot
less efficient -- imagine that I have supplied one buffer of size 1K
and one buffer of size 16K. The default vectorized read method will
just always use that single 1K buffer, which isn't great -- but still,
not much to be done about it. Some readers just cannot support
vectorized reads.

The problem here then is that it would be nice if there were some way
to *detect* when a reader supports vectorized reads. This would allow
the caller to choose between a "vectorized" call path, where it tries
to supply many buffers, or a single-buffer call path, where it just
allocates a big buffer.

Apparently hyper will do this today, but using a heuristic: if a call
to the vectorized read method returns *just enough* data to fit in the
first buffer, hyper guesses that in fact vectorized reads are not
supported, and switches dynamically to the "one big buffer" strategy.
(Neat.)

There is perhaps a second, more ergonomic issue: since the vectorized
read method has a default implementation, it is easy to forget to
implement it, even if you would have been able to do so.

In any case, this problem is relatively easy to solve: we basically
need to add a new method like

```rust
fn supports_vectorized_reads(&self) -> bool
```

to the trait.

The matter of decided whether or not to supply a default is a bit
trickier.  If you don't supply a default, then everybody has to
implement it, even if they just want the default behavior. But if you
*do*, people who wished to implement the method may forget to do so --
this is particularly unfortunate for reads that are wrapping another
reader, which is a pretty common case.

## Footnotes
