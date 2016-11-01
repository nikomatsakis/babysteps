---
layout: post
title: "On reference-counting and leaks"
date: 2015-04-29 12:39:10 -0700
comments: true
categories: [Rust]
---

What's a 1.0 release without a little drama? Recently, we discovered
that there was an oversight in one of the standard library APIs that we
had intended to stabilize. In particular, we recently added an API for
scoped threads -- that is, child threads which have access to the
stack frame of their parent thread.

The flaw came about because, when designing the scoped threads API, we
failed to consider the impact of resource leaks. Rust's ownership
model makes it somewhat hard to leak data, but not impossible. In
particular, using reference-counted data, you can construct a cycle in
the heap, in which case the components of that cycle may never be
freed.

Some commenters online have taken this problem with the scoped threads
API to mean that Rust's type system was fundamentally flawed. This is
not the case: Rust's guarantee that safe code is memory safe is as
true as it ever was. The problem was really specific to the scoped
threads API, which was making flawed assumptions; this API has been
marked unstable, and there is an [RFC][1084] proposing a safe
alternative.

That said, there is an interesting, more fundamental question at play
here. We long ago decided that, to make reference-counting practical,
we had to accept resource leaks as a possibility. But some
[recent][1085] [proposals][1094] have suggested that we should place
limits on the `Rc` type to avoid some kinds of reference leaks. These
limits would make the original scoped threads API safe. **However,
these changes come at a pretty steep price in composability: they
effectively force a deep distinction between "leakable" and
"non-leakable" data,** which winds up affecting all levels of the
system.

This post is my attempt to digest the situation and lay out my current
thinking. For those of you don't want to read this entire post (and I
can't blame you, it's long), let me just copy the most salient
paragraph from my conclusion:

> This is certainly a subtle issue, and one where reasonable folk can
  disagree. In the process of drafting (and redrafting...) this post,
  my own opinion has shifted back and forth as well. But ultimately I
  have landed where I started: **the danger and pain of bifurcating
  the space of types far outweighs the loss of this particular RAII
  idiom.**

All right, for those of you who want to continue, this post is divided
into three sections:

1. Section 1 explains the problem and gives some historical background.
2. Section 2 explains the "status quo".
3. Section 3 covers the proposed changes to the reference-counted type
   and discusses the tradeoffs involved there.

<!-- more -->

### Section 1. The problem in a nutshell

Let me start by summarizing the problem that was uncovered in more
detail. The root of the problem is an interaction between the
reference-counting and threading APIs in the standard library. So
let's look at each in turn. If you're familiar with the problem, you
can skip ahead to section 2.

#### Reference-counting as the poor man's GC

Rust's standard library includes the `Rc` and `Arc` types which are
used for reference-counted data. These are widely used, because they
are the most convenient way to create data whose ownership is shared
amongst many references rather than being tied to a particular stack
frame.

Like all reference-counting systems, `Rc` and `Arc` are vulnerable to
reference-count cycles. That is, if you create a reference-counted box
that contains a reference to itself, then it will never be
collected. **To put it another way, Rust gives you a lot of safety
guarantees, but it doesn't protect you from memory leaks (or
deadlocks, which turns out to be a very similar problem).**

The fact that we don't protect against leaks is not an accident. This
was a deliberate design decision that we made while transitioning from
garbage-collected types (`@T` and `@mut T`) to user-defined reference
counting. The reason is that preventing leaks requires either a
runtime with a cycle collector or complex type-system tricks. The
option of a mandatory runtime was out, and the type-system tricks we
explored were either too restrictive or too complex. So we decided to
make a pragmatic compromise: to document the possibility of leaks
(see, for example, [this section of the Rust reference manual][rrm])
and move on.

In practice, the possibility of leaks is mostly an interesting
technical caveat: I've not found it to be a big issue in practice.
Perhaps because problems arose so rarely in practice, some
things---like leaks---that should not have been forgotten
were... partially forgotten. History became legend. Legend became
myth. And for a few years, the question of leaks seemed to be a
distant, settled issue, without much relevance to daily life.

#### Thread and shared scopes

With that background on `Rc` in place, let's turn to threads.
Traditionally, Rust threads were founded on a "zero-sharing"
principle, much like Erlang. However, as Rust's type system evolved,
we realized we could [do much better][dp] -- **the
[same type system rules][conn] that ensured memory safe in sequential
code could be used to permit sharing in parallel code as well**,
particularly once we adopted [RFC 458][458] (a brilliant insight by
[pythonesque][py]).

The basic idea is to start a child thread that is tied to a particular
scope in the code. We want to guarantee that before we exit that
scope, the thread will be joined. If we can do this, then we can
safely permit that child thread access to stack-allocated data, so
long as that data outlives the scope; this is safe because Rust's
type-system rules already ensure that any data shared between multiple
threads must be immutable (more or less, anyway).

So the question then is how can we designate the scope of the children
threads, and how can we ensure that the children will be joined when
that scope exits. The original proposal was based on closures, but in
the time since it was written, the language has shifted to using more
RAII, and hence the `scoped` API is based on RAII. The idea is pretty
simple.  You write a call like the following:

```rust
fn foo(data: &[i32]) {
  ...
  let guard = thread::scoped(|| /* body of the child thread */);
  ...
}
```

The `scoped` function takes a closure which will be the body of the
child thread. It returns to you a guard value: running the destructor
of this guard will cause the thread to be joined. This guard is always
tied to a particular scope in the code. Let's call the scope `'a`. The
closure is then permitted access to all data that outlives `'a`.  For
example, in the code snippet above, `'a` might be the body of the
function `foo`. This means that the closure could safely access the
input `data`, because that must outlive the fn body. The type system
ensures that no reference to the guard exists outside of `'a`, and
hence we can be sure that guard will go out of scope sometime before
the end of `'a` and thus trigger the thread to be joined. At least
that was the idea.

#### The conflict

By now perhaps you have seen the problem. The scoped API is only
safe if we can guarantee that the guard's destructor runs, so that the
thread will be joined; but, using `Rc`, we can leak values, which
means that their destructors never run. So, by combining `Rc` and
`scoped`, we can cause a thread to be launched that will never be
joined.  This means that this thread could run at any time and try to
access data from its parents stack frame -- even if that parent has
already completed, and thus the stack frame is garbage. Not good!

So where does the fault lie? From the point of view of *history*, it
is pretty clear: the `scoped` API was ill designed, given that `Rc`
already existed. As I wrote, we had long ago decided that the most
practical option was to accept that leaks could occur. This implies
that if the memory safety of an API depends on a destructor running,
you can't relinquish ownership of the value that carries that
destructor (because the end-user might leak it).

It is totally possible to fix the `scoped` API, and in fact there is
already [an RFC showing how this can be done][1084] (I'll summarize it
in section 2, below). However, some people feel that the decision we
made to permit leaks was the wrong one, and that we ought to have some
limits on the RC API to prevent leaks, or at least prevent *some*
leaks. I'll dig into those proposals in section 3.

### Section 2. What is the impact of leaks on the status quo?

So, if we continue with the status quo, and accept that resource leaks
can occur with `Rc` and `Arc`, what is the impact of that?  At first
glance, it might seem that the possibility of resource leaks is a huge
blow to RAII. After all, if you can't be sure that the destructor will
run, how can you rely on the destructor to do cleanup?  But when you
look closer, it turns out that the problem is a lot more narrow.

#### "Average Rust User"

I think it's helpful to come at this problem from two difference
perspectives. The first is: what do resource leaks mean for the
average Rust user? I think the right way to look at this is that the
user of the `Rc` API has an obligation to avoid cycle leaks or break
cycles. Failing to do so will lead to bugs -- these could be resource
leaks, deadlocks, or other things. **But leaks cannot lead to memory
unsafety.** (Barring invalid unsafe code, of course.)

It's worth pointing out that even if you are using `Rc`, you don't
have to worry about memory leaks due to forgetting to decrement a
reference or anything like that. The problem really boils down to
ensuring that you have a clear strategy for avoiding cycles, which
usually boils to an "ownership DAG" of strong references (though in
some cases, breaking cycles explicitly may also be an option).

#### "Author of unsafe code"

The other perspective to consider is the person who is writing unsafe
code. Unsafe code frequently relies on destructors to do cleanup.  I
think the right perspective here is to view a destructor as akin to
any other user-facing function: in particular, it is the user's
responsibility to call it, and they may accidentally fail to do
so. Just as you have to write your API to be defensive about users
invoking functions in the wrong order, you must be defensive about
them failing to invoke destructors due to a resource leak.

It turns out that the majority of RAII idioms are actually perfectly
memory safe even if the destructors don't run. For example, if we
examine the Rust standard library, it turns out that *all* of the
destructors therein are either optional or can be made optional:

1. Straight-forward destructors like `Box` or `Vec` leak memory if
   they are not freed; clearly no worse than the original leak.
2. Leaking a [mutex guard][mg] means that the mutex will never be released.
   This is likely to cause deadlock, but not memory unsafety.
3. Leaking a [`RefCell` guard][rg] means that the `RefCell` will remain
   in a borrowed state. This is likely to cause thread panic, but not memory
   unsafety.
4. Even fancy iterator APIs like `drain`, which was initially thought
   to be problematic, can be implemented in
   [such a way that they cause leaks to occur if they are leaked][poop],
   but not memory unsafety.

In all of these cases, there is a guard value that mediates access to
some underlying value. The type system already guarantees that the
original value cannot be accessed while the guard is in scope. But how
can we ensure safety outside of that scope in the case where the guard
is leaked? If you look at the the cases above, I think they can be
grouped into two patterns:

1. *Ownership:* Things like `Box` and `Vec` simply own the values they are
   protecting. This means that if they are leaked, those values are also
   leaked, and hence there is no way for the user to access it.
2. *Pre-poisoning:* Other guards, like `MutexGuard`, put the value
   they are protecting into a poisoned state that will lead to dynamic
   errors (but not memory unsafety) if the value is accessed without
   having run the destructor.  In the case of `MutexGuard`, the
   "poisoned" state is that the mutex is locked, which means a later
   attempt to lock it will simply deadlock unless the `MutexGuard` has
   been dropped.

#### What makes scoped threads different?

So if most RAII patterns continue to work fine, what makes scoped
different? I think there is a fundamental difference between scoped
and these other APIs; this difference was [well articulated][proxy] by
Kevin Ballard:

> `thread::scoped` is special because it's using the RAII guard as a
> proxy to represent values on the stack, but this proxy is not
> actually used to access those values.

If you recall, I mentioned above that all the guards serve to mediate
access to some value. In the case of `scoped`, the guard is mediating
access to the result of a computation -- the data that is being
protected is "everything that the closure may touch". The guard, in
other words, doesn't really know the specific set of affected data,
and it thus cannot hope to either own or pre-poison the data.

In fact, I would take this a step farther, and say that I think that
in this kind of scenario, where the guard doesn't have a connection to
the data being protected, RAII tends to be a poor fit. This is
because, generally, the guard doesn't have to be used, so it's easy
for the user to accidentally drop the guard on the floor, causing the
side-effects of the guard (in this case, joining the thread) to occur
too early. I'll spell this out a bit more in the section below.

**Put more generally, accepting resource leaks does mean that there is
a Rust idiom that does not work.** In particular, it is not possible
to create a borrowed reference that can be guaranteed to execute
arbitrary code just before it goes out of scope. What we've seen
though is that, frequently, it is not necessary to *guarantee* that
the code will execute -- but in the case of scoped, because there is
no direct connection to the data being protected, joining the thread
is the only solution.

#### Using closures to guarantee code execution when exiting a scope

If we can't use an RAII-based API to ensure that a thread is joined,
what can we do? It turns out that there is a good alternative, laid
out in [RFC 1084][1084]. The basic idea is to restructure the API so
that you create a "thread scope" and spawn threads into that scope (in
fact, the RFC lays out a more general version that can be used not
only for threads but for any bit of code that needs guaranteed
execution on exit from a scope). This thread scope is delinated using
a closure. In practical terms, this means that started a scoped thread
look something like this:

```rust
fn foo(data: &[i32]) {
  ...
  thread::scope(|scope| {
    let future = scope.spawn(|| /* body of the child thread */);
    ...
  });
}
```

As you can see, whereas before calling `thread::scoped` started a new
thread immediately, it now just creates a thread scope -- it doesn't
itself start any threads. A borrowed reference to the thread scope is
passed to a closure (here it is the argument `scope`). The thread
scope offers a method `spawn` that can be used to start a new thread
tied to a specific scope. This thread will be joined when the closure
returns; as such, it has access to any data that outlives the body of
the closure. Note that the `spawn` method still returns a future to
the result of the spawned thread; this future is similar to the old
join guard, because it can be used to join the thread early. But this
future doesn't have a destructor. If the thread is not joined through
the future, it will still be automatically joined when the closure
returns.

In the case of this particular API, I think closures are a better fit
than RAII. In particular, the closure serves to make the scope where
the threads are active clear and explicit; this in turn avoids certain
footguns that were possible with the older, RAII-based API. To see an
example of what I mean, consider this code that uses the old API to do
a parallel [quicksort][qs]:

```rust
fn quicksort(data: &mut [i32]) {
  if data.len() <= 1 { return; }
  let pivot = data.len() / 2;
  let index = partition(data, pivot);
  let (left, right) = data.split_at_mut(data, index);
  let _guard1 = thread::scoped(|| quicksort(left));
  let _guard2 = thread::scoped(|| quicksort(right));
}
```

I want to draw attention to one snippet of code at the end:

```rust
  let (left, right) = data.split_at_mut(data, index);
  let _guard1 = thread::scoped(|| quicksort(left));
  let _guard2 = thread::scoped(|| quicksort(right));
```

Notice that we have to make dummy variables like `_guard1` and
`_guard2`. If we left those variables off, then the thread would be
immediately joined, which means we wouldn't get any actual
parallelism. What's worse, the code would still work, it would just
run sequentially. The need for these dummy variables, and the
resulting lack of clarity about just when parallel threads will be
joined, is a direct result of using RAII here.

Compare that code above to using a closure-based API:

```rust
  thread::scope(|scope| {
    let (left, right) = data.split_at_mut(data, index);
    scope.spawn(|| quicksort(left));
    scope.spawn(|| quicksort(right));
  });
```

I think it's much clearer. Moreover, the closure-based API opens the
door to other methods that could be used with `scope`, like
convenience methods to do parallel maps and so forth.

### Section 3. Can we prevent (some) resource leaks?

Ok, so in the previous two sections, I summarized the problem and
discussed the impact of resource leaks on Rust. But what if we could
avoid resource leaks in the first place? There have been two RFCs on
this topic: [RFC 1085][1085] and [RFC 1094][1094].

The two RFCs are quite different in the details, but share a common
theme. The idea is not to avoid all resource leaks altogether; I think
everyone recognizes that this is not practical. Instead, the goal is
to try and divide types into two groups: those that can be safely
leaked, and those that cannot. You then limit the `Rc` and `Arc` types
so that they can only be used with types that can safely be leaked.

This approach seems simple but it has deep ramifications. It means
that `Rc` and `Arc` are no longer fully general container
types. Generic code that wishes to operate on data of all types
(meaning both types that can and cannot leak) can't use `Rc` or `Arc`
internally, at least not without some hard choices.

Rust already has a lot of precedent for categorizing types. For
example, we use a trait `Send` to designate "types that can safely be
transferred to other threads". In some sense, dividing types into
leak-safe and not-leak-safe is analogous. But my experience has been
that every time we draw a fundamental distinction like that, it
carries a high price. This distinction "bubbles up" through APIs and
affects decisions at all levels. In fact, we've been talking about one
case of this rippling effect through this post -- the fact that we
have two reference-counting types, one atomic (`Arc`) and one not
(`Rc`), is precisely because we want to distinguish thread-safe and
non-thread-safe operations, so that we can get better performance when
thread safety is not needed.

**What this says to me is that we should be very careful when
introducing blanket type distinctions.** The places where we use this
mechanism today -- thread-safety, copyability -- are fundamental to
the language, and very important concepts, and I think they carry
their weight. Ultimately, I don't think resource leaks quite fit the
bill. But let me dive into the RFCs in question and try to explain
why.

#### RFC 1085 -- the Leak trait

The first of the two RFCs is [RFC 1085][1085]. This RFC introduces a
trait called `Leak`, which operates exactly like the existing `Send`
trait. It indicates "leak-safe" data. Like `Send`, it is implemented
by default.  If you wish to make leaks impossible for a type, you can
explicitly opt out with a negative impl like `impl !Leak for MyType`.
When you create a `Rc<T>` or `Arc<T>`, either `T: Leak` must hold, or
else you must use an unsafe constructor to certify that you will not
create a reference cycle.

The fact that `Leak` is automatically implemented promises to make it
mostly invisible. Indeed, in the prototype that [Jonathan Reem][reem]
implemented, he found relatively little fallout in the standard
library and compiler. While encouraging, I still think we're going to
encounter problems of composability over time.

There are a couple of scenarios where the `Leak` trait will, well,
leak into APIs where it doesn't seem to belong. One of the most
obvious is trait objects. Imagine I am writing a serialization
library, and I have a `Serializer` type that combines an output stream
(a `Box<Writer>`) along with some serialization state:

```rust
struct Serializer {
  output_stream: Box<Writer>,
  serialization_state: u32,
  ...
}
```

So far so good. Now someone else comes along and would like to use my
library. They want to put this `Serializer` into a reference counted
box that is shared amongst many users, so they try to make a
`Rc<Serializer>`. Unfortunately, this won't work. This seems somewhat
surprising, since weren't all types were supposed to be `Leak` by
default?

The problem lies in the `Box<Writer>` object -- an object is designed
to hide the precise type of `Writer` that we are working with. That
means that we don't know whether this particular `Writer` implements
`Leak` or not. For this client to be able to place `Serializer` into
an `Rc`, there are two choices. The client can use `unsafe` code, or
I, the library author, can modify my `Serializer` definition as
follows:

```rust
struct Serializer {
  output_stream: Box<Writer+Leak>,
  serialization_state: u32,
  ...
}
```

This is what I mean by `Leak` "bubbling up". It's already the case
that I, as a library author, want to think about whether my types can
be used across threads and try to enable that. Under this proposal, I
also have to think about whether my types should be usable in `Rc`,
and so forth.

Now, if you avoid trait objects, the problem is smaller. One advantage
of generics is that they don't encapsulate what type of writer you are
using and so forth, which means that the compiler can analyze the type
to see whether it is thread-safe or leak-safe or whatever. Until now
we've found that many libraries avoid trait objects partly for this
reason, and I think that's good practice in simple cases. But as things scale up,
encapsulation is a really useful mechanism for simplifying type annotations and
making programs concise and easy to work with.

There is one other point. [RFC 1085][1085] also includes an unsafe
constructor for `Rc`, which in principle allows you to continue using
`Rc` with any type, so long as you are in a position to assert that no
cycles exist. But I feel like this puts the burden of unsafety into
the wrong place. I think you should be able to construct
reference-counted boxes, and truly generic abstractions built on
reference-counted boxes, without writing unsafe code.

My allergic reaction to requiring `unsafe` to create `Rc` boxes stems
from a very practical concern: if we push the boundaries of unsafety
too far out, such that it is common to use an unsafe keyword here and
there, we vastly weaken the safety guarantees of Rust *in
practice*. I'd rather that we increase the power of safe APIs at the
cost of more restrictions on unsafe code. Obviously, there is a
tradeoff in the other direction, because if the requirements on unsafe
code become too subtle, people are bound to make mistakes there too,
but my feeling is that requiring people to consider leaks doesn't
cross that line yet.

#### RFC 1094 -- avoiding reference leaks

[RFC 1094][1094] takes a different tack. Rather than dividing types
arbitrarily into leak-safe and not-leak-safe, it uses an existing
distinction, and says that any type which is associated with a scope
cannot leak.

The goal of [RFC 1094][1094] is to enable a particular "mental model"
about what lifetimes mean. Specifically, the RFC aims to ensure that
if a value is limited to a particular scope `'a`, then the value will
be destroyed before the program exits the scope `'a`. This is very
similar to what Rust currently guarantees, but stronger: in current
Rust, there is no guarantee that your value will be destroyed, there
is only a guarantee that it will not be accessed outside that
scope. Concretely, if you leak an `Rc` into the heap today, that `Rc`
may contain borrowed references, and those references could be invalid
-- but it doesn't matter, because Rust guarantees that you could never
use them.

In order to guarantee that borrowed data is never leaked,
[RFC 1094][1094] requires that to construct a `Rc<T>` (or `Arc<T>`),
the condition `T: 'static` must hold. In other words, the payload of a
reference-counted box cannot contain borrowed data. This by itself is
very limiting: lots of code, including the rust compiler, puts
borrowed pointers into reference-counted structures. To help with
this, the RFC includes a second type of reference-counted box,
`ScopedRc`. To use a `ScopedRc`, you must first create a
reference-counting scope `s`. You can then create new `ScopedRc`
instances associated with `s`. These `ScopedRc` instances carry their
own reference count, and so they will be freed normally as soon as
that count drops to zero. But if they should get placed into a cycle,
then when the scope `s` is dropped, it will go along and "cycle
collect", meaning that it runs the destructor for any `ScopedRc`
instances that haven't already been freed. (Interestingly, this is
very similar to the closure-based scoped thread API, but instead of
joining threads, exiting the scope reaps cycles.)

I originally found this RFC appealing. It felt to me that it avoided
adding a new distinction (`Leak`) to the type system and instead
piggybacked on an existing one (borrowed vs non-borrowed). This seems
to help with some of my concerns about "ripple effects" on users.

**However, even though it piggybacks on an existing distinction
(borrowed vs static), the RFC now gives that distinction additional
semantics it didn't have before.** Today, those two categories can be
considered on a single continuum: for all types, there is some
bounding scope (which may be `'static`), and the compiler ensures that
all accesses to that data occur within that scope. Under RFC 1094,
there is a discontinuity. Data which is bounded by `'static` is
different, because it may leak.

This discontinuity is precisely why we have to split the type `Rc`
into two types, `Rc` and `ScopedRc`. In fact, the RFC doesn't really
mention `Arc` much, but presumably there will have to be both
`ScopedRc` and a `ScopedArc` types. So now where we had only two
types, we have four, to account for this new axis:

```
|-----------------++--------+----------|
|                 || Static | Borrowed |
|-----------------++--------+----------|
| Thread-safe     || Rc     | RcScoped |
| Not-thread-safe || Arc    | ArcScope |
|-----------------++--------+----------|
```

And, in fact, the distinction doesn't end here. There are
abstractions, such as channels, that built on `Arc`. So this means
that this same categorization will bubble up through those
abstractions, and we will (presumably) wind up with `Channel` and
`ChannelScoped` (otherwise, channels cannot be used to send borrowed
data to scoped threads, which is a severe limitation).

### Section 4. Conclusion.

This concludes my deep dive into the question of resource leaks. It
seems to me that the tradeoffs here are not simple. The status quo,
where resource leaks are permitted, helps to ensure composability by
allowing `Rc` and `Arc` to be used uniformly on all types. I think
this is very important as these types are vital building blocks.

On a historical note, I am particularly sensitive to concerns of
composability. Early versions of Rust, and in particular the borrow
checker before we adopted the current semantics, were rife with
composability problems. This made writing code very annoying -- you
were frequently refactoring APIs in small ways to account for this.

However, this composability does come at the cost of a useful RAII
pattern. Without leaks, you'd be able to use RAII to build references
that reliably execute code when they are dropped, which in turn allows
RAII-like techniques to be used more uniformly across all safe APIs.

This is certainly a subtle issue, and one where reasonable folk can
disagree. In the process of drafting (and redrafting...) this post, my
own opinion has shifted back and forth as well. But ultimately I have
landed where I started: **the danger and pain of bifurcating the space
of types far outweighs the loss of this particular RAII idiom.**

Here are the two most salient points to me:

1. The vast majority of RAII-based APIs are either safe or can be made
   safe with small changes. The remainder can be expressed with
   closures.
   - With regard to RAII, the scoped threads API represents something
     of a "worst case" scenario, since the guard object is completely
     divorced from the data that the thread will access.
   - In cases like this, where there is often no *need* to retain the
     guard, but dropping it has important side-effects, RAII can be a
     footgun and hence is arguably a poor fit anyhow.
2. The cost of introducing a new fundamental distinction ("leak-safe"
   vs "non-leak-safe") into our type system is very high and will be
   felt up and down the stack.  This cannot be completely hidden or
   abstracted away.
   - This is similar to thread safety, but leak-safety is far less fundamental.
   
Bottom line: the cure is worse than the disease.   

[reem]: https://github.com/reem/
[raii]: http://en.wikipedia.org/wiki/Resource_Acquisition_Is_Initialization
[rrm]: http://doc.rust-lang.org/reference.html#behavior-not-considered-unsafe
[dp]: http://smallcultfollowing.com/babysteps/blog/2013/06/11/data-parallelism-in-rust/
[conn]: http://smallcultfollowing.com/babysteps/blog/2013/06/11/on-the-connection-between-memory-management-and-data-race-freedom/
[py]: https://github.com/pythonesque
[mg]: http://doc.rust-lang.org/std/sync/struct.MutexGuard.html
[rg]: http://doc.rust-lang.org/std/cell/struct.Ref.html
[poop]: http://cglab.ca/~abeinges/blah/everyone-poops/
[proxy]: https://github.com/rust-lang/rfcs/pull/1084#issuecomment-96875651
[qs]: http://en.wikipedia.org/wiki/Quicksort
[458]: https://github.com/rust-lang/rfcs/blob/master/text/0458-send-improvements.md
[1084]: https://github.com/rust-lang/rfcs/pull/1084
[1085]: https://github.com/rust-lang/rfcs/pull/1085
[1094]: https://github.com/rust-lang/rfcs/pull/1094
[WAMA]: http://smallcultfollowing.com/babysteps/blog/2012/11/18/imagine-never-hearing-the-phrase-aliasable/
