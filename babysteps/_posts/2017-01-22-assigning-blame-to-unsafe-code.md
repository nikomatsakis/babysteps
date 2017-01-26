---
layout: post
title: Assigning blame to unsafe code
categories: [Rust, Unsafe]
---

While I was at POPL the last few days, I was reminded of an idea
regarding how to bring more struture to the unsafe code guidelines
process that I've been kicking around lately, but which I have yet to
write about publicly. The idea is fresh on my mind because while at
POPL I realized that there is an interesting opportunity to leverage
the "blame" calculation techniques from gradual typing research. But
before I get to blame, let me back up and give some context.

### The guidelines should be executable 

I've been thinking for some time that, whatever guidelines we choose,
we need to adopt the principle that they should be **automatically
testable**. By this I mean that we should be able to compile your
program in a special mode ("sanitizer mode") which adds in extra
assertions and checks. These checks would dynamically monitor what
your program does to see if it invokes undefined behavior: if they
detect UB, then they will abort your program with an error message.

Plenty of sanitizers or sanitizer-like things exist for C, of course.
My personal favorite is [valgrind], but there are a number of
[other examples](https://github.com/google/sanitizers) (the
[data-race detector for Go](https://golang.org/doc/articles/race_detector.html)
also falls in a similar category). However, as far as I know, none of
the C sanitizers is able to detect the full range of undefined
behavior. Partly this is because C UB includes untestable (and, in my
opinion, overly aggressive) rules like "every loop should do I/O or
terminate". I think we should strive for a **sound and complete**
sanitizer, meaning that we guarantee that if there is undefined
behavior, we will find it, and that we have no false positives.  We'll
see if that's possible. =)

The really cool thing about having the rules be executable (and
hopefully *efficiently* executable) is that, in the (paraphrased)
words of [John Regehr](http://www.cs.utah.edu/~regehr/), it changes
the problem of verifying safety from a formal one into a matter of
test coverage, and the latter is much better understood. My ultimate
goal is that, if you are the developer of an unsafe library, all you
have to do is to run `cargo test --unsafe` (or some such thing), and
all of the normal tests of your library will run but in a special
sanitizer mode where any undefined behavior will be caught and flagged
for you.

But I think there is one other important side-effect. I have been (and
remain) very concerned about the problem of programmers not
understanding (or even being aware of) the rules regarding correct
unsafe code. This is why I originally wanted a system like the Tootsie
Pop rules, where programmers have to learn as few things as possible.
But having an easy and effective way of testing for violations changes
the calculus here dramatically: **I think we can likely get away with
much more aggressive rules if we can test for violations**. To play on
John Regehr's words, this changes the problem from being one of having
to learn a bunch of rules to having to interpret error messages. **But
for this to work well, of course, the error messages have to be
good.** And that's where this idea comes in.

### Proof of concept: miri

As it happens, there is an existing project that is already doing a
limited form of the kind of checks I have in mind: [miri], the MIR
interpreter created by [Scott Olson] and now with
[significant contributions] by [Oliver Schneider]. If you haven't seen
or tried miri, I encourage you to do so. It is very cool and
surprisingly capable -- in particular, miri can not only execute safe
Rust, but also **unsafe** Rust (e.g., it is able to interpret the
definition of `Vec`).

[miri]: https://github.com/solson/miri
[Scott Olson]: https://github.com/solson/
[Oliver Schneider]: https://github.com/oli-obk
[significant contributions]: https://github.com/solson/miri/graphs/contributors

The way it does this is to simulate the machine at a reasonably
low-level. So, for example, when you allocate memory, it stores that
as a kind of blob of bytes of a certain size. But it doesn't *only*
store bytes; rather, it tracks additional metadata about what has been
stored into various spots. For example, it knows whether memory has
been initialized or not, and it knows which bits are pointers (which
are stored opaquely, not with an actual address). This allows is to
interpret a lot of unsafe code, but it also allows it to detect
various kinds of errors.

### An example

Let's start with a simple example of some bogus unsafe code.

```rust
fn main() {
    let mut b = Box::new(22);
    innocent_looking_fn(&b);
    *b += 1;
}

fn innocent_looking_fn(b: &Box<usize>) {
    // This wicked little bit of code will take a borrowed
    // `Box` and free it.
    unsafe {
        let p: *const usize = &**b;
        let q: Box<usize> = Box::from_raw(p as *mut usize);
    }
}
```

The problem here is that this "innocent looking function" claims to
borrow the box `b` but it actually frees it. So now when `main()`
comes along to execute `*b += 1`, the box `b` has been freed. This
situation is often called a "dangling pointer" in C land. We might expect
then that when you execute this program, something dramatic will happen,
but that is not (necessarily) the case:

```
> rustc tests/dealloc.rs
> ./dealloc
```

As you can see, I got no error or any other indication that something
went awry. This is because, internally, freeing the box just throws
its address on a list for later re-use. Therefore when I later make
use of that address, it's entirely possible that the memory is still
sitting there, waiting for me to use it, even if I'm not supposed to.
This is part of what makes tracking down a "use after free" bug
incredibly frustrating: oftentimes, nothing goes wrong! (Until it
does.) It's also why we need some kind of **sanitizer** mode that will
do additional checks beyond what really happens at runtime.

### Detecting errors with miri

But what happens when I run this through miri?

```
> cargo run tests/dealloc.rs
    Finished dev [unoptimized + debuginfo] target(s) in 0.2 secs
     Running `target/debug/miri tests/dealloc.rs`
error: dangling pointer was dereferenced
 --> tests/dealloc.rs:8:5
  |
8 |     *b += 1;
  |     ^^^^^^^
  |
note: inside call to main
 --> tests/dealloc.rs:5:1
  |
5 |   fn main() {
  |  _^ starting here...
6 | |     let mut b = Box::new(22);
7 | |     evil(&b);
8 | |     *b += 1;
9 | | }
  | |_^ ...ending here

error: aborting due to previous error
```

(First, before going further, let's just take a minute to be impressed
by the fact that miri bothered to give us a nice stack trace here. I
had heard good things about miri, but before I started poking at it
for this blog post, I expected something a lot less polished. I'm
impressed.)

You can see that, unlike the real computer, miri detected that `*b`
was freed when we tried to access it. It was able to do this because
when miri is interpreting your code, it does so with respect to a more
abstract model of how a computer works. In particular, when memory is
freed in miri, miri remembers that the address was freed, and if there
is a later attempt to access it, an error is thrown. (This is very
similar to what tools like [valgrind] and [electric fence] do as well.)

[valgrind]: http://valgrind.org/
[electric fence]: http://elinux.org/Electric_Fence

So even just using miri out of the box, we see that we are starting to
get a certain amount of sanitizer rules. Whatever the unsafe code
guidelines turn out to be, one can be sure that they will declare it
illegal to access freed memory. As this example demonstrates, running
your code through miri could help you detect a violation.

### Blame

This example also illustrates another interesting point about a
sanitizer tool. The point where the error is **detected** is not
necessarily telling you which bit of code is **at fault**. In this
case, the error occurs in the safe code, but it seems clear that the
fault lies in the unsafe block in `innocent_looking_fn()`. That
function was supposed to present a safe interface, but it failed to do
so. Unfortunately, for us to figure that out, we have to trawl through
the code, executing backwards and trying to figure out how this freed
pointer got into the variable `b`. Speaking as someone who has spent
years of his life doing exactly that, I can tell you it is not fun.
Anything we can do to get a more precise notion of what code is at
fault would be tremendously helpful.

It turns out that there is a large body of academic work that I think
could be quite helpful here. For some time, people have been exploring
[**gradual typing** systems](https://en.wikipedia.org/wiki/Gradual_typing). This
is usually aimed at the software development process: people want to
be able to start out with a dynamically typed bit of software, and
then add types gradually. But it turns out when you do this, you have
a similar problem: your statically typed code is guaranteed to be
internally consistent, but the dynamically typed code might well feed
it values of the wrong types. To address this, **blame systems**
attempt to track where you crossed between the static and dynamic
typing worlds so that, when an error occurs, the system can tell you
which bit of code is at fault.

**UPDATE:** It turns out that I got the history of blame wrong. While
blame is used in gradual typing work, it actually originates in the
more general setting of contract enforcement, specifically with
[Robby Findler's thesis on Behavioral Software Contracts][rf]. That's
what I get for writing on the plane without internet. =)

[rf]: https://www.eecs.northwestern.edu/~robby/pubs/papers/behavioral-software-contracts.pdf

Traditionally this blame tracking has been done using proxies and
other dynamic mechanisms, particularly around closures. For example,
Jesse Tov's [Alms language][alms] allocated stateful proxies to allow
for owned types to flow into a language that didn't understand
ownership (this is sort of roughly analogous to dynamically wrapping a
value in a `RefCell`). Unfortunately, introducing proxies doesn't seem
like it would really work so well for a "no runtime" language like
Rust. We could probably get away with it in miri, but it would never
scale to running arbitrary C code.

Interestingly, at this year's POPL, I saw a paper that seemed to
present a solution to this problem. In
[*Big types in little runtime*][btlr], Michael Vitousek, Cameron
Swords (ex-Rust intern!), and Jeremy Siek describe a system for doing
gradual typing in Python that works even without modifying the Python
runtime -- this rules out proxies, because the runtime would have to
know about them. Instead, the statically typed code keeps a log "on
the side" which tracks transitions to and from the unsafe code and
other important events. When a fault occurs, they can read this log
and reconstruct which bit of code is at fault. This seems eminently
applicable to this setting: we have control over the *safe Rust* code
(which we are compiling in a special mode), but we don't have to
modify the unsafe code (which might be in Rust, but might also be in
C). Exciting!

[btlr]: http://dl.acm.org/citation.cfm?id=3009849
[alms]: http://users.eecs.northwestern.edu/~jesse/pubs/dissertation/

### Conclusion

This post has two purposes, in a way. First, I want to advocate for
the idea that we should define the unsafe code guidelines in an
*executable* way. Specifically, I think we should specify predicates
that must hold at various points in the execution. In this post we saw
a simple example: when you dereference a pointer, it must point to
memory that has been allocated and not yet freed. (Note that this
particular rule only applies to the moment at which the pointer is
dereferenced; at other times, the pointer can have any value you want,
though it may wind up being restricted by other rules.) It's much more
interesting to think about assertions that could be used to enforce
Rust's aliasing rules, but that's a good topic for another post.

Probably the best way for us to do this is to start out with a minimal
"operational semantics" for a representative subset of MIR (bascally a
mathematical description of what MIR does) and then specify rules by
adding side-clauses and conditions into that semantics. I have been
talking to some people who might be interested in doing that, so I
hope to see progress here.

That said, it may be that we can instead do this exploratory work by
editing miri. The codebase seems pretty clean and capable, and a lot of the
base work is done.

In the long term, I expect we will want to instead target a platform
like [valgrind], which would allow us to apply these rules even around
to unsafe C code. I'm not sure if that's really feasible, but it seems
like the ideal.

The second purpose of the post is to note the connection with gradual
typing and the opportunity to apply blame research to the problem. I
am very excited about this, because I've always felt that guidelines
based simply on undefined behavior were going to be difficult for
people to use, since errors are are often detected in code that is
quite disconnected from the origin of the problem.

