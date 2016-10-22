---
layout: post
title: "Observational equivalence and unsafe code"
date: 2016-10-02 07:06:23 -0400
comments: false
categories: [Rust, Unsafe]
---

I spent a really interesting day last week at Northeastern University.
First, I saw a fun talk by Philip Haller covering [LaCasa], which is a
set of extensions to Scala that enable it to track ownership. Many of
the techniques reminded me very much of Rust (e.g., the use of
"spores", which are closures that can limit the types of things they
close over); if I have time, I'll try to write up a more detailed
comparison in some later post.

Next, I met with [Amal Ahmed] and her group to discuss the process of
crafting unsafe code guidelines for Rust. This is one very impressive
group. It's this last meeting that I wanted to write about now. The
conversation helped me quite a bit to more cleanly separate two
distinct concepts in my mind.

The TL;DR of this post is that I think we can limit the capabilities
of unsafe code to be "things you could have written using the safe
code plus a core set of unsafe abstractions" (ignoring the fact that
the safe implementation would be unusably slow or consume ridiculous
amounts of memory). This is a helpful and important thing to be able
to nail down.

[LaCasa]: http://2016.splashcon.org/event/splash-2016-oopsla-lacasa-lightweight-affinity-and-object-capabilities-in-scala
[Amal Ahmed]: http://www.ccs.neu.edu/home/amal/

<!-- more -->

### Background: observational equivalence

One of the things that we talked about was **observational
equivalence** and how it relates to the unsafe code guidelines. The
notion of observational equivalence is really pretty simple: basically
it means "two bits of code do the same thing, as far as you can tell".
I think it's easiest to think of it in terms of an API. So, for
example, consider the `HashMap` and `BTreeMap` types in the Rust
standard library. Imagine I have some code using a `HashMap<i32, T>`
that only invokes the basic map operations -- e.g., `new`, `get`, and
`insert`. I would expect to be able to change that code to use a
`BTreeMap<i32, T>` and have it keep working. This is because `HashMap`
and `BTreeMap`, at least with respect to `i32` keys and
`new`/`get`/`insert`, are **observationally equivalent**.

If I expand the set of API routines that I use, however, this
equivalence goes away. For example, if I iterate over the map, then a
`BTreeMap` gives me an ordering guarantee, whereas `HashMap` doesn't.

Note that the speed and memory use will definitely change as I shift
from one to the other, but I still consider them observationally
equivalent. This is because I consider such changes "unobservable", at
least in this setting (crypto code might beg to differ).

### Composing unsafe abstractions

One thing that I've been kind of wrestling with in the unsafe code
guidelines is how to break it up. A lot of the attention has gone into
thinking about some very low-level decisions: for example, if I make a
`*mut` pointer and an `&mut` reference, when can they legally alias?
But there are some bigger picture questions that are also equally
interesting: what kinds of things can unsafe code **even do** in the
first place, whatever types it uses?

One example that I often give has to do with the infamous
`setjmp`/`longjmp` in C. These are some routines that let you
implement a poor man's exception handling. You call `setjmp` at one
stack frame and then, down the stack, you call `longjmp`. This will
cause all the intermediate stack frames to be popped (with no
unwinding or other cleanup) and control to resume from the point where
you called `setjmp`.  You can use this to model exceptions (a la
Objective C),
[build coroutines](http://fanf.livejournal.com/105413.html), and of
course -- this *is* C -- to shoot yourself in the foot (for example,
by invoking `longjmp` when the stack frame that called `setjmp` has
already returned).

So you can imagine someone writing a Rust wrapper for
`setjmp`/`longjmp`. You could easily guarantee that people use the API
in a correct way: e.g., that you when you call `longjmp`, the `setjmp`
frame is still on the stack, but does that make it **safe**?

One concern is that `setjmp`/`longjmp` do not do any form of
unwinding. This means that all of the intermediate stack frames are
going to be popped and none of the destructors for their local
variables will run. This certainly means that memory will leak, but it
[can have much worse effects if you try to combine it with other unsafe abstractions][reddit]. Imagine
for example that you are using [Rayon][]: Rayon relies on running
destructors in order to join its worker threads. So if a user of the
`setjmp`/`longjmp` API wrote something like this, that would be very
bad:

[reddit]: https://www.reddit.com/r/rust/comments/508pkb/unleakable_crate_safetysanityrefocus/d72703d
[Rayon]: https://github.com/nikomatsakis/rayon/

```rust
setjmp(|j| {
    rayon::join(
        || { /* original thread */; j.longjmp(); },
        || { /* other thread */ });
});
```

What is happening here is that we are first calling `setjmp` using our
"safe" wrapper. I'm imagining that this takes a closure and supplies
it some handle `j` that can be used to "longjmp" back to the `setjmp`
call (basically like `break` on steroids). Now we call `rayon::join`
to (potentially) spin off another thread. The way that `join` works is
that the first closure executes on the current thread, but the second
closure may get stolen and execute on another thread -- in that case,
the other thread will be joined before `join` returns. But here we are
calling `j.longjmp()` in the first closure. This will skip right over
the destructor that would have been used to join the second thread.
So now potentially we have some other thread executing, accessing
stack data and raising all kinds of mischief.

(Note: the current signature of `join` would probably prohibit this,
since it does not reflect the fact that the first closure is known to
execute in the original thread, and hence requires that it close over
only sendable data, but I've contemplated changing that.)

So what went wrong here? We tried to combine two things that
independently seemed *safe* but wound up with a broken system. How did
that happen? The problem is that when you write unsafe code, you are
not only thinking about what your code **does**, you're thinking about
what the outside world **can do**. And in particular you are modeling
the potential actions of the outside world using the limits of **safe
code**.

In this case, Rayon was making the assumption that when we call a closure,
that closure will do one of four things:

- loop infinitely;
- abort the process and all its threads;
- unwind;
- return normally.

This is true of all safe code -- unless that safe code has access to
`setjmp`/`longjmp`.

This illustrates the power of unsafe abstractions. They can extend the
very vocabulary with which safe code speaks. (Sorry, I know that was
ludicrously flowery, but I can't bring myself to delete it.) Unsafe
abstractions can extend the **capabilities** of safe code. This is
very cool, but also -- as we see here -- potentially
dangerous. **Clearly, we need some guidelines to decide what kinds of
capabilities it is ok to add and which are not.** 

### Comparing setjmp/longjmp and rayon

But how can we decide what capabilities to permit and which to deny?
This is where we get back to this notion of *observational
equivalence*. After all, both Rayon and setjmp/longjmp give the user
some new powers:

- Rayon lets you run code in different threads.
- Setjmp/longjmp lets you pop stack frames without returning or unwinding.

But these two capabilities are qualitiatively different. For the most
part, Rayon's superpower is **observationally equivalent** to safe
Rust. That is, I could implement Rayon without using threads at all
and you as a safe code author couldn't tell the difference, except for
the fact that your code runs slower (this is a slight simplification;
I'll elaborate below). **In contrast, I cannot implement
setjmp/longjmp using safe code.**

**"But wait", you say, "Just what do you mean by 'safe code'?"** OK,
That last paragraph was really sloppy. I keep saying things like "you
could do this in safe Rust", but of course we've already seen that the
very notion of what "safe Rust" can do is something that **unsafe code
can extend**. So let me try to make this more precise. Instead of
talking about *Safe Rust* as it was a monolithic entity, we'll
gradually build up more expressive versions of Rust by taking a safe
code and adding unsafe capabilities. Then we can talk more precisely
about things.

### Rust0 -- the safe code

Let's start with Rust0, which corresponds to what you can do without
using **any unsafe code at all, anywhere**. Rust0 is a remarkably
incapable language. The most obvious limitation is that you have no
access to the heap (`Box` and `Vec` are unsafely implemented
libraries), so you are limited to local variables. You can still do
quite a lot of interesting things: you have arrays and slices,
closures, enums, and so forth. But everything must live on the stack
and hence ultimately follow a stack discipline. Essentially, you can
never return anything from a function whose size is not statically
known. We can't even use static variables to stash stuff, since those
are inherently shared and hence immutable unless you have some unsafe
code in the mix (e.g., `Mutex`).

### Rust1 -- the heap (`Vec`)

So now let's consider Rust1, which is Rust0 but with access to `Vec`.
We don't have to worry about how `Vec` is implemented. Instead, we can
just think of `Vec` as if it were part of Rust itself (much like how
`~[T]` used to be, in the bad old days). Suddenly our capabilities are
much increased!

For example, one thing we can do is to implement the `Box` type
(`Box<T>` is basically a `Vec<T>` whose length is always 1, after
all). We can also implement something that acts identically to
`HashMap` and `BTreeMap` in pure safe code (obviously the performance
characteristics will be different).

(At first, I thought that giving access to `Box` would be enough, but
you can't really simulate `Vec` just by using `Box`. Go ahead and try
and you'll see what I mean.)

### Rust2 -- sharing (`Rc`, `Arc`)

This is sort of an interesting one. Even if you have `Vec`, you still
cannot implement `Rc` or `Arc` in Rust1. At first, I thought perhaps we could
fake it by cloning data -- so, for example, if you want a `Rc<T>`, you
could (behind the scenes) make a `Box<T>`. Then when you clone the
`Rc<T>` you just clone the box. Since we don't yet have `Cell` or
`RefCell`, I reasoned, you wouldn't be ablle to tell that the data had
been cloned. But of course that won't work, because you can use a
`Rc<T>` for **any** `T`, not just `T` that implement `Clone`.

### Rust3 -- non-atomic mutation

That brings us to another fundamental capability. `Cell` and `RefCell`
permit mutation when data is shared. This can't be modeled with just
`Rc`, `Box`, or `Vec`, all of which maintain the invariant that
mutable data is uniquely reachable.

### Rust4 -- asynchronous threading

This is an interesting level. Here we add the ability to spawn a
thread, as described in `std::thread` (note that this thread runs
asynchronously and cannot access data on the parent's stack frame). At
first, I thought that threading didn't add "expressive power" since we
lacked the ability to share **mutable** data across threads (we can
share immutable data with `Arc`).

After all, you could implement `std::thread` in safe code by having it
queue up the closure to run and then, when the current thread
finishes, have it execute. This isn't **really** correct for a number
of reasons (what is this scheduler that overarches the safe code?
Where do you queue up the data?), but it seems *almost* true.

But there is another way that adding `std::thread` is important. It
means that safe code can **observe** memory in an asynchronous thread,
which affects the kinds of **unsafe code** that we might write. After
all, the whole purpose of this exercise is to figure out the limits of
what safe code can do, so that unsafe code knows what it has to be
wary of. So long as safe code did not have access to `std::thread`,
one could **imagine** writing an unsafe function like this:

```rust
fn foo(x: &Arc<i32>) {
    let p: *const i32 = &*x;
    let q: *mut i32 = p as *mut i32;
    *q += 1;
    *q -= 1;
}
```

This function takes a shared `i32` and **temporarily** increments and
then decrements it. The important point here is that the invariant
that the `Arc<i32>` is immutable is broken, but it is restored before
`foo` returns. Without threads, safe code can't tell the difference
between `foo(&my_arc)` and a no-op. But with threads, `foo()` might
trigger a data-race. (This is all leaving aside the question of
compiler optimization and aliasing rules, of course.)

(Hat tip to Alan Jeffreys for pointing this out to me.)

### Rust5 -- communication between threads and processes

The next level I think are abstractions that enable threads to
communiate with one another. This includes both within a process
(e.g., `AtomicU32`) and across processes (e.g., I/O).

This is an interesting level to me because **I think** it represents
the point where the effects of a library like rayon becomes observable
to safe code. Until this point, the only data that could be shared
across Rayon threads was immutable, and hence I think the precise
interleavings could also be simulated. But once you throws atomics
into the mix, and in particular the fact that atomics give you control
over the memory model (i.e., they do not require sequential
consistency), then you can definitely observe whether threading is
truly in use. The same is true for I/O and so forth.

So this is the level that shows that what I wrote earlier, that
"Rayon's superpower is observationally equivalent to safe Rust" is
actually false. I think it **is** observationally equivalent to "safe
Rust4", but not Rust5. Basically Rayon serves as a kind of "Rust6", in
which we grow Rust5 by adding scoped threads, that allow sharing data
on stack frames.

### And so on

We can keep going with this exercise, which I actually think is quite
valuable, but I'll stop here for now. What I'd like to do
asynchronously is to go over the standard library and interesting
third-party packages and try to nail down the "core unsafe
abstractions" that you need to build Rust, as well as the
"dependencies" between them.

But I want to bring this back to the core point: the focus in the
unsafe code guidelines has been on exploring what unsafe code can do
"in the small".  Basically, what types it ought to use to achieve
certain kinds of aliasing and so forth. **But I think it's also very
important to nail down what unsafe code can do "in the large".** How
do we know whether (say)
[abomonation](https://github.com/frankmcsherry/abomonation),
[deque](https://crates.io/crates/deque), and so forth represent legal
libraries?

As I left the meeting with Amal's group, she posed this question to
me. Is there something where all three of these things are true:

- you cannot simulate using the standard library;
- you **can** do with unsafe code;
- and it's a "reasonable" thing to do.

Whenever the answer is yes, that's a candidate for growing another
Rust level. We already saw one "yes" answer in this blog post, right
at the end: scoped threads, which enable threading with access to
stack contents. Beyond that, most of the potential answers I've come
up with are access to various kernel capabilities:

- dynamic linking;
- shared memory across processes;
- processes themselves. =)

What's a bit interesting about these is that they seem to be mostly
about the operating system itself. They don't feel "fundamental" in
the same way as scoped threads: in other words, you could imagine
simulating the O/S itself in safe code, and then you could build these
things. Not quite how to think about *that* yet.

In any case, I'd be interested to hear about other "fundamental
abstractions" that you can think of.

### Coda: Picking and choosing your language levels

Oh, one last thing. It might seem like defining all these language
levels is a bit academic. But it can be very useful to pick them
apart. For example, imagine you are targeting a processor that has no
preemption and always uses cooperative multithreading. In that case,
the concerns I talked about in Rust4 may not apply, and you may be
able to do more aggressive things in your unsafe code.

### Comments

Please leave comments in
[this thread on the Rust internals forum](https://internals.rust-lang.org/t/blog-post-observatonal-equivalence-and-unsafe-code/4148/1).


