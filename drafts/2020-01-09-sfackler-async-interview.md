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

## Background: concerns on the async-read trait

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

So what are the concerns that are motivating [tokio-rs/tokio#17144]?
There are two of them:

* the current traits do not permit using uninitialized memory as the
  backing buffer;
* there is no way to test presently whether a given reader supports
  vectorized operations.
  
## The same issues arise with the sync `Read` trait

Interestingly, neither of these issues is specific to `AsyncRead`.  As
defined today, the `AsyncRead` trait is basically just the async
version of [`Read`] from `std`, and both of these concerns apply there
as well. In fact, part of why I wanted to talk to sfackler
specifically is that he is the author of an [excellent paper
document][doc] that
covers the problem of using uninitialized memory in great depth. A lot
of what we talked about on this call is also present in that document.
Definitely give it a read.

[doc]: https://paper.dropbox.com/doc/MvytTgjIOTNpJAS6Mvw38
[`Read`]: https://doc.rust-lang.org/std/io/trait.Read.html

## Uninitialized memory

The heart of the problem here lies in the signature of `read`:

```rust
fn read(&mut self, buf: &mut [u8]) -> io::Result<usize>
```

The *expectation* here is that the `read` impl is going to write into `buf`
but not read from it. But nothing actually *stops* them from reading from `buf`,
which means we can't supply uninitialized memory without safe code being
able to read it (which would be UB).

There is another problem too: `read` is going to return the number of
bytes written. If the caller supplies an uninitialized buffer, then it
will want to trust this return value and go ahead and read from those
next N bytes (which should now be initialized). But there is no
guarantee that the callee actually initiaized the .

## Vectorized reads and writes

This problem is somewhat simpler. The standard `read` interface takes
a single buffer to write the data into. But a *vectorized* interface
takes a series of buffers -- if there is more data than will fit in
the first one, then the data will be written into the second one, and
so on until we run out of data or buffers. Vectorized reads and writes
can be much more efficient in some cases.

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

## Focus on uninitialized buffers: lots of wrong ways to fix it

Since the vectorized read case is relatively simple, I'm going to
focus on uninitialized buffers. A lot of our discussion was spent
discussing the downsides of the various proposed solutions thus far.
I'm going to skip most of that in this blog post and just focus on two of
the ideas:

* a "freeze" operation
* taking a `&mut dyn BufMut` trait argment instead of `&mut [u8]`

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
That's the idea, anyway.

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
per memory page. That's conceivable, of course, but there are some downsides:

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

## Fallback and interop

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
    unsafe fn bytes_vec_mut<'a>(
        &'a mut self, 
        dst: &mut [IoSliceMut<'a>]
    ) -> usize { ... }
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

Another variant is to replace the `BufMut` trait with a struct. (Carl
Lerche proposed something similar on the tokio thread
[here](https://github.com/tokio-rs/tokio/pull/1744#issuecomment-553575438).)
The API of this struct would be fairly similar to the trait above,
except that it wouldn't make much attempt to unify vectorized and
non-vectorized writes.

Basically we'd have a struct that encapsulates a "partially
initialized slice of bytes". You could create such a struct from a
standard slice, in which case all things are initialized, or you can
create it from a slice of "maybe initialized" bytes (e.g., `&mut
[MaybeUninit<u8>]`. There can also be convenience methods to create a
`BufMut` that refers to the uninitialized tail of bytes from a `Vec`
(i.e., pointing into the vector's internal buffer).

The BufMut API would generally only permit writing to the buffer, at
least safely.  This avoids the safety problem of a `read`
implementation reading uninitialized data.

If you needed to fallback to the old `read` API, you would be able to
ask the `BufMut` for a standard `&mut [u8]`. In this case, it can zero
the uninitialized parts of the buffer before it gives it to you -- but
it can also record that those parts are now initialized. This avoids
the "zeroing more than once" performance cliff.

Finally, to address the other half of unsafety in which the caller of
`read` must trust the `callee` to correctly report how many bytes they
read, we can have an `unsafe` method where the callee asserts how much
data was written into the buffer. This would be useful when handing a
buffer to a syscall, for example. (Alternatively, the callee can write
data using more limited APIs that guarantees safety).

## How can we go about
