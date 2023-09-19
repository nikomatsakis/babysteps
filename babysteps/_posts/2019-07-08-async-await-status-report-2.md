---
layout: post
title: 'Async-await status report #2'
categories: [Rust, AsyncAwait]
---

I wanted to give an update on the status of the "async-await
foundations" working group. This post aims to cover three things:

- the "async await MVP" that we are currently targeting;
- how that fits into the bigger picture;
- and how you can help, if you're so inclined;

## Current target: async-await MVP

We are currently working on stabilizing what we call the **async-await
MVP** -- as in, "minimal viable product". As the name suggests, the
work we're doing now is basically the minimum that is needed to
"unlock" async-await. After this work is done, it will be easier to
build async I/O based applications in Rust, though a number of rough
edges remain.

The MVP consists of the following pieces:

- the [`Future`] trait, which defines the core future protocol (stabilized in [1.36.0]!);
- basic async-await syntax;
- a "first edition" of [the "async Rust" book][a-b].

[`Future`]: https://doc.rust-lang.org/std/future/trait.Future.html
[1.36.0]: https://blog.rust-lang.org/2019/07/04/Rust-1.36.0.html

### The future trait

The first of these bullets, the future trait, was stabilized in the
[1.36.0] release. This is important because the [`Future`] trait is the
core building block for the whole Async I/O ecosystem. Having a stable
future trait means that we can begin the process of consolidating the
ecosystem around it.

### Basic async-await syntax

Now that the future trait is stable, the next step is to stabilize the
basic "async-await" syntax. We are presently shooting to stabilize
this in 1.38. We've finished the largest work items, but there are
still a number of things left to get done before that date -- if
you're interested in helping out, see the "how you can help" section
at the end of this post!

The current support we are aiming to stabilize permits `async fn`, but
only outside of traits and trait implementations. This means that you
can write free functions like this one:[^highlight]

[^highlight]: Sadly, it seems like [rouge] hasn't been updated yet to highlight the async or await keywords. Or maybe I just don't understand how to upgrade it. =)
[rouge]: https://github.com/rouge-ruby/rouge

```rust
// When invoked, returns a future that (once awaited) will yield back a result:
async fn process(data: TcpStream) -> Result<(), Box<dyn Error>> {
    let mut buf = vec![0u8; 1024];
    
    // Await data from the stream:
    let len = reader.read(&mut buf).await?;
    ...
}
```

or inherent methods:

```rust
impl MyType {
    // Same as above, but defined as a method on `MyType`:
    async fn process(data: TcpStream) -> Result<(), Box<dyn Error>> { .. }
}
```

You can also write async blocks, which generate a future "in place"
without defining a separate function. These are particularly useful to
pass as arguments to helpers like [`runtime::spawn`][spawn]:

[spawn]: https://docs.rs/runtime/0.3.0-alpha.5/runtime/fn.spawn.html

```rust
let data: TcpStream;
runtime::spawn(async move {
    let mut buf = vec![0u8; 1024];
    let len = reader.read(&mut buf).await?;
    ...
})
```

Eventually, we plan to permit `async fn` in other places, but there
are some complications to be resolved first, as will be discussed
shortly.

### The async book

One of the goals of this stabilization is that, once async-await
syntax becomes available, there should be **really strong
documentation to help people get started**. To that end, we're
rejuvenating [the "async Rust" book][a-b]. This book covers the nuts
and bolts of Async I/O in Rust, ranging from simple examples with
`async fn` all the way down to the details of how the future trait
works, writing your own executors, and so forth. Take a look!

[a-b]: https://rust-lang.github.io/async-book/index.html

(Eventually, I expect some of this material may make its way into more
standard books like [The Rust Programming Language][trpl], but in the
meantime we're evolving it separately.)

[trpl]: https://doc.rust-lang.org/book/

## Future work: the bigger picture

The current stabilization push, as I mentioned above, is aimed at
getting an MVP stabilized -- just enough to enable people to run off
and start to build things. So you're probably wondering, what are some
of the things that come next? Here is a (incomplete) list of possible
future work:

- **A core set of async traits and combinators.** Basically a 1.0
  version of the [futures-rs repository][fr], offering key interfaces
  like `AsyncRead`.
- **Better stream support.** The [futures-rs repository][fr] contains
  a `Stream` trait, but there remains some "support work" to make it
  better supported. This may include [some form of for-await
  syntax][for-await] (although that is not a given).
- **Generators and async generators.** The same core compiler
  transform that enables async await should enable us to support
  Python- or JS-like generators as a way to write iterators. Those
  same generators can then be made asynchronous to produce streams of
  data.
- **Async fn in traits and trait impls.** Writing generic crates and
  interfaces that work with `async fn` is possible in the MVP, but not
  as clean or elegant as it could be. Supporting `async fn` in traits
  is an obvious extension to make that nicer, though we have to figure
  out all of the interactions with the rest of the trait system.
- **Async closures.** We would like to support the obvious `async ||`
  syntax that would generate a closure. This may require tinkering
  with the `Fn` trait hierarchy.

[for-await]: https://boats.gitlab.io/blog/post/for-await-i/
[fr]: https://github.com/rust-lang-nursery/futures-rs

## How you can get involved

There's been a lot of great work on the `async fn` implementation
since my first post -- we've closed over [40 blocker issues]!  I want
to give a special shout out to the folks who worked on those
issues:[^forgot]

[40 blocker issues]: https://github.com/rust-lang/rust/issues?q=is%3Aissue+label%3AAsyncAwait-Blocking+is%3Aclosed
[^forgot]: I culled this list by browsing the closed issues and who they were assigned to. I'm sorry if I forgot someone or minimized your role! Let me know and I'll edit the post. <3

- **davidtwco** reworked the desugaring so that the drop order for
  parameters in an `async fn` and `fn` is analagous, and then
  heroically fixed a number of minor bugs that were filed as fallout
  from this change.
- **tmandry** dramatically reduced the size of futures at runtime.
- **gilescope** improved a number of error messages and helped to reduce
  errors.
- **matthewjasper** reworked some details of the compiler transform to
  solve a large number of ICEs.
- **doctorn** fixed an ICE when `await` was used in inappropriate places.
- **centril** has been helping to enumerate tests and generally work on
  triage work.
- **cramertj** implemented the `await` syntax, wrote a bunch of tests,
  and, of course, did all of the initial implementation work.
- and hey, I extended the region inferencer to support multiple
  lifetime parameters. I guess I get some credit too. =)

If you'd like to help push `async fn` over the finish line, take a
look at our [list of blocking issues][blocking]. Anything that is not
assigned is fair game! Just find an issue you like that is not
assigned and use [`@rustbot claim`][claim] to claim it. You can find
out more about how our working group works on [the async-await working
group page][wg]. In particular, that page includes a link to the
[calendar event][cal] for our weekly meeting, which takes place in the
[the `#wg-async-foundations` channel on the rust-lang Zulip][Zulip] --
the next meeting is tomorrow (Tuesday)!. But feel free to drop in any
time with questions.

## Footnotes

[claim]: https://github.com/rust-lang/triagebot/wiki/Assignment
[wg]: https://github.com/rust-lang/compiler-team/tree/master/working-groups/async-await
[cal]: https://calendar.google.com/calendar/r/eventedit/copy/NjQzdWExaDF2OGlqM3QwN2hncWI5Y2o1dm5fMjAxOTA2MTFUMTcwMDAwWiA2dTVycnRjZTZscnR2MDdwZmkzZGFtZ2p1c0Bn/bmlrb21hdHNha2lzQGdtYWlsLmNvbQ?scp=ALL&pli=1&sf=true
[Zulip]: https://rust-lang.zulipchat.com/#narrow/stream/187312-wg-async-foundations
[blocking]: https://github.com/rust-lang/rust/labels/AsyncAwait-Blocking
[E-mentor]: https://github.com/rust-lang/rust/issues?q=is%3Aopen+label%3AAsyncAwait-Blocking+label%3AE-mentor
