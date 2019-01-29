---
layout: post
title: 'Salsa: Incremental recompilation'
categories: [Rust, NLL]
---

So for the last couple of months or so, I've been hacking in my spare
time on this library named
[**salsa**](https://github.com/salsa-rs/salsa), along with a [number
of awesome other
folks](https://github.com/salsa-rs/salsa/graphs/contributors). Salsa
basically extracts the incremental recompilation techniques that we
built for rustc into a general-purpose framework that can be used by
other programs. Salsa is developing quickly: with the publishing of
v0.10.0, we saw a big step up in the overall ergonomics, and I think
the current interface is starting to feel very nice.

Salsa is in use by a number of other projects. For example, matklad's
[rust-analyzer](https://github.com/rust-analyzer/rust-analyzer/), a
nascent Rust IDE, is using salsa, as is the
[Lark](https://github.com/lark-exploration/lark)[^worthy]
compiler. Notably, **rustc does not** -- it still uses its own
incremental engine, which has some pros and cons compared to
salsa.[^port]

If you'd like to learn more about Salsa, you can check out [the [Hello
World
example](https://github.com/salsa-rs/salsa/blob/master/examples/hello_world/main.rs) -- but, even better, you can check out two videos that I just recorded:

- [How Salsa Works](https://youtu.be/_muY4HjSqVw), which gives
  a high-level introduction to the key concepts involved and shows how to use salsa;
- [Salsa In More Depth](https://www.youtube.com/watch?v=i_IhACacPRY), which really digs
  into the incremental algorithm and explains -- at a high-level -- how Salsa is implemented.
  - Thanks to Jonathan Turner for helping me to make this one!
  
If you're interested in salsa, please jump on to our Zulip instance at
[salsa.zulipchat.com](https://salsa.zulipchat.com/). It's a really fun
project to hack on, and we're definitely still looking for people to
help out with the implementation and the design. Over the next few
weeks, I expect to be outlining a "path to 1.0" with a number of
features that we need to push over the finish line.

# Footnotes

[^worthy]: ...worthy of a post of its own, but never mind.

[^port]: I would like to eventually port rustc to salsa, but it's not a direct goal.
