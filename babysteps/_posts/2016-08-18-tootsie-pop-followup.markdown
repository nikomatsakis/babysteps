---
layout: post
title: "'Tootsie Pop' Followup"
date: 2016-08-18 09:17:46 -0400
comments: false
categories: [Rust, Unsafe]
---

A little while back, I wrote up a tentative proposal I called the
["Tootsie Pop" model for unsafe code][tpm]. It's safe to say that this
model was not universally popular. =) There was quite a
[long and fruitful discussion][d] on discuss. I wanted to write a
quick post summarizing my main take-away from that discussion and to
talk a bit about the plans to push the unsafe discussion forward.

<!-- more --> 

### The importance of the unchecked-get use case

For me, the most important lesson was the importance of the "unchecked
get" use case. Here the idea is that you have some (safe) code which
is indexing into a vector:

```rust
fn foo() {
    let vec: Vec<i32> = vec![...];
    ...
    vec[i]
    ...
}    
```

You have found (by profiling, but of course) that this code is kind of
slow, and you have determined that the bounds-check caused by indexing
is a contributing factor. You can't rewrite the code to use iterators,
and you are quite confident that the index will always be in-bounds,
so you decide to dip your tie into `unsafe` by calling
`get_unchecked`:

```rust
fn foo() {
    let vec: Vec<i32> = vec![...];
    ...
    unsafe { vec.get_unchecked(i) }
    ...
}    
```

Now, under the precise model that I proposed, this means that the
entire containing module is considered to be within an unsafe
abstraction boundary, and hence the compiler will be more conservative
when optimizing, and as a result the function may actually run
**slower** when you skip the bounds check than faster. (A very similar
example is invoking
[`str::from_utf8_unchecked`](https://doc.rust-lang.org/std/str/fn.from_utf8_unchecked.html),
which skips over the utf-8 validation check.)

Many people were not happy about this side-effect, and I can totally
understand why. After all, this code isn't mucking about with funny
pointers or screwy aliasing -- the unsafe block is a kind of drop-in
replacement for what was there before, so it seems odd for it to have
this effect.

### Where to go from here

Since posting the last blog post, we've started a
[longer-term process][p] for settling and exploring a lot of these
interesting questions about the proper use of unsafe. At this point,
we're still in the "data gathering" phase. The idea here is to collect
and categorize interesting examples of unsafe code. I'd prefer at this
point not to be making decisions per se about what is legal or not --
although in some cases someting may be quite unambiguous -- but rather
just try to get a good corpus with which we can evaluate different
proposals.

While I haven't given up on the "Tootsie Pop" model, I'm also not
convinced it's the best approach. But whatever we do, I still believe
we should strive for something that is **safe and predictable by
default** -- something where the rules can be summarized on a
postcard, at least if you don't care about getting every last bit of
optimization. But, as the unchecked-get example makes clear, it is
important that we also enable people to obtain full optimization,
possibly with some amount of opt-in. I'm just not yet sure what's the
right setup to balance the various factors.

As I wrote in my last post, I think that we have to expect that
whatever guidelines we establish, they will have only a limited effect
on the kind of code that people write. So if we want Rust code to be
reliable **in practice**, we have to strive for rules that permit the
things that people actually do: and the best model we have for that is
the extant code. This is not to say we have to achieve total backwards
compatibility with any piece of unsafe code we find in the wild, but
if we find we are invalidating a common pattern, it can be a warning
sign.

[tpm]: http://smallcultfollowing.com/babysteps/blog/2016/05/27/the-tootsie-pop-model-for-unsafe-code/
[d]: http://internals.rust-lang.org/t/tootsie-pop-model-for-unsafe-code/3522/
[arielb1]: https://github.com/rust-lang/rfcs/pull/1578#issuecomment-222530225
[RFC 1643]: https://github.com/rust-lang/rfcs/pull/1643
[rmm]: https://github.com/nikomatsakis/rust-memory-model
[p]: https://internals.rust-lang.org/t/next-steps-for-unsafe-code-guidelines/3864
