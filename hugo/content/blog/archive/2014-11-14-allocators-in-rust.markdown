---
categories:
- Rust
comments: true
date: "2014-11-14T21:13:52Z"
slug: allocators-in-rust
title: Allocators in Rust
---

There has been a lot of discussion lately about Rust's allocator
story, and in particular our relationship to jemalloc. I've been
trying to catch up, and I wanted to try and summarize my understanding
and explain for others what is going on. I am trying to be as
factually precise in this post as possible. If you see a factual
error, please do not hesitate to let me know.

<!--more-->

### The core tradeoff

The story begins, like all interesting design questions, with a
trade-off. The problem with trade-offs is that neither side is 100%
right. In this case, the trade-off has to do with two partial truths:

1. **It is better to have one global allocator than two.** Allocators like
   [jemalloc], [dlmalloc], and so forth are all designed to be the
   only allocator in the system. Of necessity they permit a certain
   amount of "slop", allocating more memory than they need so that
   they can respond to requests faster, or amortizing the cost of
   metadata over many allocations. If you use two different
   allocators, you are paying those costs twice. Moreover, the
   allocator tends to be a hot path, and you wind up with two copies
   of it, which leaves less room in the instruction cache for your
   actual code.
2. **Some allocators are more efficient than others.** In particular,
   the default allocators shipped with libc on most systems tend not
   to be very good, though there are exceptions. One particularly good
   allocator is jemalloc. In comparison to the default glibc or
   windows allocator, jemalloc can be noticeably more efficient both
   in performance and memory use. Moreover, jemalloc offers an
   extended interface that Rust can take advantage of to gain even
   more efficiency (for example, by specifying the sizes of a memory
   block when it is freed, or by asking to reallocate memory in place
   when possible).
   
Clearly, the best thing is to use just one allocator that is also
efficient. So, to be concrete, whenever we produce a Rust executable,
everyone would prefer if that Rust executable -- along with any C code
that it uses -- would just use jemalloc everywhere (or whatever
allocator we decide is 'efficient' tomorrow).

However, in some cases we can't control what allocator other code will
use. For example, if a Rust library is linked into a larger C
program. In this case, we can opt to continue using jemalloc from
within that Rust code, but the C program may simply use the normal
allocator. And then we wind up with two allocators in use. This is
where the trade-off comes into play. Is it better to have Rust use
jemalloc even when the C program within which Rust is embedded does
not? In that case, the Rust allocations are more efficient, but at the
cost of having more than one global allocator, with the associated
inefficiencies. I think this is the core question.

### Two extreme designs

Depending on whether you want to prioritize using a single allocator
or using an efficient allocator, there are two extreme designs one
might advocate for the Rust standard library:

1. When Rust needs to allocate memory, just call `malloc` and friends.
2. Compile Rust code to invoke jemalloc directly. This is what we
   currently do. There are many variations on how to do
   this. Regardless of which approach you take, this has the downside
   that when Rust code is linked into C code, there is the possibility
   that the C code will use one allocator, and Rust code another.
   
It's important to clarify that what we're discussing here is really
the *default* behavior, to some extent. The Rust standard library
already isolates the definition of the global allocator into a
particular crate. End users can opt to change the definition of that
crate. However, it would require recompiling Rust itself to do so,
which is at least a mild pain.

#### Calling malloc

If we opted to default to just calling `malloc`, this does not mean
that end users are locked into the libc allocator or anything like
that. There are existing mechanisms for changing what allocator is
used at a global level (though I understand this is relatively hard on
Windows). Presumably when we produce an actual Rust executables, we
would default to using jemalloc.

Calling malloc has the advantage that if a Rust library is linked into
a C program, both of them will be using the same global allocator,
whatever it is (unless of course that C program itself doesn't call
`malloc`).

However, one downside of this is that we are not able to take
advantage of the more advanced jemalloc APIs for sized deallocation
and reallocation. This has a measureable effect in micro-benchmarks.
I am not aware of any measurements on larger scale Rust applications,
but there are definitely scenarios where the advanced APIs are useful.

Another potential downside of this approach is that `malloc` is called
via indirection (because it is part of libc; I'm a bit hazy on the
details of this point, and would appreciate clarification). This
implies a somewhat higher overhead for calls to malloc/free than if we
fixed the allocator ahead of time. It's worth noting that this is the
*normal setup* that all C programs use by default, so relative to a
typical C program, this setup carries no overhead.

(When compiling a statically linked executables, rustc could opt to
redirect `malloc` and friends to jemalloc at this point, which would
eliminate the indirection overhead but not take advantage of the
specialized jemalloc APIs.  This would be a simplified variant of the
hybrid scheme I eventually describe below.)

#### Calling jemalloc directly

If we opt to hardcode Rust's default allocator to be jemalloc, we gain
several advantages. The performance of Rust code, at least, is not
subject to the whims of whatever global allocator the platform or
end-user provides. We are able to take full advantage of the
specialized jemalloc APIs. Finally, as the allocator is fixed to
jemalloc ahead of time, static linking scenarios do not carry the
additional overhead that calling `malloc` implies (though, as I noted,
one can remove that overhead also when using `malloc` via a simple
hybrid scheme).

Having Rust code unilatelly call jemalloc also carries downsides. For
example, if Rust code is embedded as a library, it will not adopt the
global allocator of the code that it is embedded within. This carries
the performance downsides of multiple allocators but also a certain
amount of risk, because a pointer allocated on one side cannot be
freed on the other (some argue this is bad practice; this is certainly
true if you do not know that the two sides are using the same
allocator, but is otherwise legitimate, see the section below for more
details).

The same problem can also occur in reverse, when C code is used from
within Rust. This happens today with rustc: due to the specifics of
our setup, LLVM uses the system allocator, not the jemalloc allocator
that Rust is using. This causes extra fragmentation and memory
consumption. It's also not great because jemalloc is better than the
system allocator in many cases.

#### To prefix or not to prefix

One specific aspect of calling jemalloc directly concerns how it is
built. Today, we build jemalloc using name prefixes, effectively
"namespacing" it so that it does not interfere with the system
allocator. This is what causes LLVM to use a different allocator in
rustc. This has the advantage of clarity and side-stepping certain
footguns around dynamic linking that could otherwise occur, but at the
cost of forking the allocators.

A [recent PR][18678] aimed to remove the prefix. It was rejected
because in a dynamic linking scenario, this creates a fragile
situation. Basically, the dynamic library ("client") defines `malloc`
to be jemalloc. The host process also has a definition for `malloc`
(the system allocator). The precise result will depend on the flags
and platform that you're running on, but there are basically two
possible outcomes, and both can cause perfectly legitimate code to
crash:

1. The host process wins, `malloc` means the same thing
   everywhere (this occurs on [linux by default][m]). 
2. `malloc` means different things in the host and the client
   (this occurs [on mac by default][m], and [on linux][o] with the
   `DEEPBIND` flag).

In the first case, crashes can arise if the client code should try to
intermingle usage of the nonstandard jemalloc API (which maps to
jemalloc) with the standard malloc API (which the client believes to
also be jemalloc, but which has been remapped to the system allocator
by the host). The [jemalloc documentation][jeman] isn't 100% explicit
on the matter, but I believe it is legal for code to (e.g.) call
`mallocx` and then call `free` on the result. Hence if Rust should
link some C code that did that, it would crash under the first
scenario.

In the second case, crashes can arise if the host/client attempt to
transfer ownership of memory. Some claim that this is not a legitimate
thing to do, but that is untrue: it is (usually) perfectly legal for
client code to (e.g.) call `strdup` and then pass the result back to
the host, expecting the host to free it. (Granted, it is best to be
cautious when transfering ownership across boundaries like this, and
one should never call `free` on a pointer unless you can be sure of
the allocator that was used to allocate that pointer in the first
place. But if you *are* sure, then it should be possible.)

**UPDATE:** I've been told that on Windows, freeing across DLL
boundaries is something you can never do. On Reddit,
[Mr_Alert writes][r]: "In Windows, allocating memory in one DLL and
freeing it in another is very much illegitimate. Different compiler
versions have different C runtimes and therefore different
allocators. Even with the same compiler version, if the EXE or DLLs
have the C runtime statically linked, they'll have different copies of
the allocator. So, it would probably be best to link rust_alloc to
jemalloc unconditionally on Windows." Given the number of differences
between platforms, it seems likely that the best behavior will
ultimately be platform dependent.

Fundamentally, the problems here are due to the fact that the client
is attempting to redefine the allocator on behalf of the host. Forcing
this kind of name conflict to occur intentionally seems like a bad
idea if we can avoid it.

### A hybrid scheme

There is also the possibility of various hybrid schemes. One such
option that Alex Crichton and I put together, summarized in
[this gist][hs], would be to have Rust call neither the standard
`malloc` nor the jemalloc symbols, but rather an intermediate set of
APIs (let's call them `rust_alloc`). When compiling Rust libraries
("rlibs"), these APIs would be unresolved. These rust allocator APIs
would take all the information they need to take full advantage of
extended jemalloc APIs, if they are available, but could also be
"polyfilled" using the standard system malloc interface.

So long as Rust libraries are being compiled into "rlibs", these
`rust_alloc` dependencies would remain unresolved. An `rlib` is
basically a statically linked library that can be linked into another
Rust program. At some point, however, a final artifact is produced, at
which point the `rust_alloc` dependency must be fulfilled. The way we
fulfill this dependency will ultimately depend on what kind of
artifact is produced:

- Static library for use in a C program: link `rust_alloc` to `malloc`
- Dynamic library (for use in C or Rust): link `rust_alloc` to `malloc`
- Executable: resolve `rust_alloc` to jemalloc, and override the
  system malloc with jemalloc as well.

This seems to offer the best of both worlds. Standalone, statically
linked Rust executables (the recommended, default route) get the full
benefit of jemalloc. Code that is linked into C or dynamically loaded
uses the standard allocator by default. Any C code used from within
Rust executables will also call into jemalloc as well.

However, there is one major caveat. While it seems that this scheme
would work well on linux, the behavior on other platforms is
different, and it's not yet clear if the same scheme can be made to
work as well on Mac and Windows.

Naturally, even if we sort out the cross-platform challenges, this
hybrid approach too is not without its downsides. It means that Rust
code built for libraries will not take full advantage of what jemalloc
has to offer, and in the case of dynamic libraries there may be more
overhead per `malloc` invocation than if jemalloc were statically
linked. However, by the same token, Rust libraries will avoid the
overhead of using two allocators and they will also be acting more
like normal C code. And of course the embedding program may opt, in
its linking phase, to redirect `malloc` (globally) to jemalloc.

[hs]: https://gist.github.com/alexcrichton/41c6aad500e56f49abda

### So what should we do?

The decision about what to do has a couple of facets. In the immediate
term, however, we need to take steps to improve rustc's memory
usage. It seems to me that, at minimum, we ought to accept
[strcat's PR #18915][18915], which ensures that Rust executables can
use jemalloc for everything, at least on linux. Everyone agrees that
this is a desirable goal.

Longer term, it is somewhat less clear. The reason that this decision
is difficult is that there is no choice that is "correct" for all
cases. The most performant choice will depend on the specifics of the
case:

- Is the Rust code embedded?
- How much allocation takes place in Rust vs in the other language?
- What allocator is the other language using?

(As an example, the performance and memory use of `rustc` improved
when we adopted jemalloc, even partially, but other applications will
fare differently.)

At this point I favor the general principle that Rust code, when
compiled as a library for use within C code, should more-or-less
behave like C code would behave. This seems to suggest that, when
building libraries for C consumption, Rust should just call `malloc`,
and people can use the normal mechanisms to inject jemalloc if they so
choose. However, when compiling Rust executables, it seems
advantageous for us to default to a better allocator and to get the
maximum efficiency we can from that allocator. The hybrid scheme aims
to achieve both of these goals but there may be a better way to go
about it, particularly around the area of dynamic linking.

I'd like to see more measurement regarding the performance impact of
foregoing the specialized jemalloc APIs and using weak linking. I've
seen plenty of numbers suggesting jemalloc is better than other
allocators on the whole, and plenty of numbers saying that using
specialized APIs helps in microbenchmarks. But it is unclear what the
impact of such APIs (or weak linking) is on the performance of larger
applications.

I'd also like to get the input from more people who have experience in
this area. I've talked things over with [strcat][thestinger] a fair
amount, who generally favors using jemalloc even if it means two
allocators. We've also reached out to Jason Evans, the author of
jemalloc, who stressed the fact that multiple global allocators is
generally a poor choice. I've tried to reflect their points in this
post.

Note though that whatever we decide we can evolve it as we go. There
is time to experiment and measure. One thing that *is* clear to me is
that we do not want Rust to "depend on" jemalloc in any hard
sense. That is, it should always be possible to switch from jemalloc
to another allocator. This is both because jemalloc, good as it is,
can't meet everyone's needs all the time, and because it's just not a
necessary dependency for Rust to take. Establishing an abstraction
boundary around the "Rust global allocator" seems clearly like the
right thing to do, however we choose to fulfill it.

[18915]: https://github.com/rust-lang/rust/pull/18915
[thestinger]: https://github.com/thestinger
[o]: https://gist.github.com/alexcrichton/781eb2f958150a890dd3
[jeman]: http://www.canonware.com/download/jemalloc/jemalloc-latest/doc/jemalloc.html
[m]: https://gist.github.com/alexcrichton/8638ac35a79834adcc57
[18678]: https://github.com/rust-lang/rust/pull/18678
[jemalloc]: http://www.canonware.com/jemalloc/
[dlmalloc]: http://g.oswego.edu/dl/html/malloc.html
[r]: http://www.reddit.com/r/rust/comments/2mcew2/allocators_in_rust_from_nmatsakiss_blog/cm35d8f
