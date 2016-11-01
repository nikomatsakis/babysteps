---
layout: post
title: "Reducing DST Annotation"
date: 2013-06-06 06:16
comments: true
categories: [Rust]
---

So Ben Blum has doing [some investigation][bblum] into the full
implications of the `Sized` bound that I proposed as part of the
[dynamically sized types][dst] post. It's clear that, if we change
nothing else, the impact of `Sized` will be somewhat greater than I
thought. He estimates somewhere around 40% of the files in libstd need
at least one `Sized` bound; the actual number may wind up being
somewhat higher.

It is not entirely clear to me if this is a problem. I imagine that
the number of `Sized` bounds will be highest in container and other
library code. But it is worse than I hoped. So I wanted to briefly
explore some of the alternatives, assuming that the `Sized` annotation
burden is too high.

### No dynamically sized types

One option of course is to keep the status quo. I feel that the
current scheme where `&[T]` is a type but is not an instance of `&T`
is a "wart in the making". It's a pain to write generic impls for
universal traits like `Eq` etc.  It's annoying to me that I can't borrow
a `~[T]` by writing `&*v`. The compiler is full of all kinds of
special case code paths to accommodate this situation.

Patrick Walton's thoughts about improving language integration for
smart pointers work out more smoothly with DST, since it means that one
can write `Gc<[T]>`, `Rc<str>`, and so forth.  Admittedly, it is also
plausible to only support `Gc<~[T]>`---certainly `@mut ~[T]` is a
common type in Rust today, since it permits appending and growing the
length.

Some elements of my original proposal don't work out like I thought,
though. For example, pcwalton and I realized that it's better to have
the "non-borrowed" forms of `[T]` and so forth use a different layout
than the borrowed forms.

It turns out that function types just don't fit well as DSTs, leading
to alternative proposals, like the [fn vs thunk][ft] post or
[bblum's proposal][bblum] which changes `[&|@|~]fn` to `fn[&|@|~]`,
and makes clever use of bounds.

### Option 1: Different defaults

This may be a case where the defaults are just wrong. pcwalton
proposed having all type parameters implicitly have a `Sized` bound
unless you prefix it with `unsized`. So you'd write `<unsized T>` to
get the widest possible type parameter. This seems like it might work
quite well, and it's quite simple to explain. However, I was thinking
about other possible approaches.

### Option 2: A limited form of inference

One thought I had was that most of these `Sized` bounds are really
quite redundant. As a simple example, consider the function `push`:

    fn push<T>(vec: &mut ~[T], value: T) { ... }
    
We already know that whenever you call a function, all of the values
you supply as arguments must be sized. Moreover, we know that you
can't have a vector type `~[T]` unless `T` is `Sized`. So in a lot of
ways the sized bound is quite redundant: even without looking at the
fn body, we can deduce that it would only be possible to invoke `push`
with a `T` that is sized.

Therefore, we could have the type checker take advantage of this when
checking the body of `push`. Essentially it would augment the declared
bounds of `T` with `Sized` if it can deduce from the types of the
parameters that the function could only be called with a sized type.

My feeling is that this rule would basically eliminate `Sized` bounds
from all fns in practice, though they might still appear on type
declarations (currently, we don't allow bounds at all in type
declarations, but I think we have to permit at least builtin bounds
for smoother integration with deriving and also for destructors, more
below).

I am somewhat concerned the rule is perhaps overly clever. It's a bit
subtle and hard to explain, particularly compared to pcwalton's simple
defaulting proposal. Also, we don't as a rule do any inference around
function signatures: the rule I propose here is not in fact a
violation of this principle, since the function signature of `push`
would not change, but it *feels* like a violation in spirit. We are
essentially inferring, based on the types of the parameters, that
`push` can only be called with sized types bound to `T`.

### An aside, bounds in type declarations

Currently we do not allow bounds in generic type declarations. As
bblum points out, though, it is hard to
[properly support deriving][deriving] this way. You might think that
deriving could just add `Sized` bounds to all the type parameters, but
that is not valid for a type like `Foo` where `T` could legally be
unsized:

    pub struct Foo<T> {
        v: @T
    }
    
There is another, unrelated, use case for such bounds, which is
destructors. Currently we only permit destructors to be defined on
`Owned` types. But suppose I have a generic type like `ArrayMessage`
that is only used with owned values:

    pub struct ArrayMessage<T> {
        data: ~[T]
    }
    pub type U8Message = ArrayMessage<u8>
    pub type U16Message = ArrayMessage<u6>

If I were to define a destructor for `ArrayMessage`, I would need to
ensure that `T` is owned:

    impl<T:Owned> Drop for ArrayMessage<T> { ... }
    
But the compiler gives me an error here, because we don't permit types
to "sometimes" have destructors. In other words, would this impl imply
that `ArrayMessage` has no destructor if instantiated with a non-owned
type? Of course, *we* know that in practice `ArrayMessage` is only
used with `Owned` arguments, but we currently have no way to tell the
*compiler* that.

So I think we can just allow bounds in type declarations, though I am
inclined to limit it to the builtin traits (what we sometimes call
"kinds"). We would validate that the type of every expression meets
whatever bounds are defined. If we decided to opt for my inference
suggestion, then we would not want to validate arbitrary types that
appear in e.g. fn parameter lists. Instead, we would leverage the fact
that we know that this type cannot be instantiated without a bound to
aid the inference scheme (in other words, if I have an argument of
type `ArrayMessage<T>`, that would imply to the compiler that `T` must
be `Owned`).

I am inclined to limit the bounds to builtin traits for two reasons.
First, it ensures that the validation that a type meets its defined
bounds is cheap: we don't want to be doing trait resolution on every
expression, even if we made more progress on memoization. Second, I
think the inference scheme I discussed is only feasible for simple,
builtin traits, and I don't want to consider what would happen if we
applied it more widely.

### So what to do?

I'd be happy with either defaults or this inference scheme. I might
prefer defaults, actually: easier to explain. And I feel like it's ok
to have "unsized" type parameters be declared differently, they will
not be used as widely as normal ones. There is the potential issue
that sometimes people will use a normal type parameter when an unsized
type parameter could have worked, but I suspect that unsized type
parameters will not be widely used, but rather will appear in
particular patterns:

- Smart pointers, and
- Impls for "universal" traits like `Eq` and so forth.

In those case, the library author will quickly find out that it can't
be applied to `[T]`.

[bblum]: https://github.com/mozilla/rust/issues/6308#issuecomment-18880575
[deriving]: https://github.com/mozilla/rust/issues/6308#issuecomment-18866391
[dst]: {{ site.baseurl }}/blog/2013/04/30/dynamically-sized-types/
[ft]: {{ site.baseurl }}/blog/2013/06/03/more-on-fns/
