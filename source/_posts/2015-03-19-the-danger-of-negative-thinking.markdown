---
layout: post
title: "The danger of negative thinking"
date: 2015-03-19 17:59:39 -0400
comments: true
categories: [Rust]
---

There has been a lot of talk about integrating *negative reasoning*
into the trait system. The most obvious example is this (very well
reasoned) RFC covering [negative trait bounds][586]. However, what's
perhaps less widely recognized is that the trait system as currently
implemented already has some amount of negative reasoning, in the form
of the coherence system. Recently, [I realized][23086] that *any* form
of negative reasoning carries real risks for forwards compatibility --
including coherence as it exists today. Fortunately, there seem to be
some potential solutions on the horizon.

This blog post covers why negative reasoning can be problematic, with
a focus on the pitfalls in the current coherence system. This post
only covers the problem. The next post will cover one possible
solution I have been working on based on specialization. This solution
*seems* to be very promising.

<!-- more -->

### A goal

Let me start out with an implicit premise of this post. I think it's
important that implementing an existing trait for an existing type
does not cause code to stop compiling (and hence does not require a
"major version bump"). Let me give you a concrete example. libstd
defines the `Range<T>` type. Right now, this type is not `Copy` for
various [good reasons][18045]. However, we might like to make it
`Copy` in the future when we have a suitable lint. It feels like that
should be legal. However, as I'll show you below, this could in fact
cause existing code not to compile. I think this is a problem.

Put another way, I think we'd like adding impls to be `monotonic`,
meaning that it cannot cause compilation failures. Ideally, we'd also
have the guarantee that if a new impl is added to an ancestor crate,
then downstream crates continue to use the same impls that they did
before, regardless of the new impl that was added (presuming the
downstream crate doesn't change as well).

### Negative reasoning in coherence today, the simple case

"Coherence" refers to a set of rules that Rust uses to enforce the
idea that there is at most one impl of any trait for any given set of
input types. Let me introduce an example crate hierarchy that I'm going
to be coming back to throughout the post:

```
libstd
  |
  +-> lib1 --+
  |          |
  +-> lib2 --+
             |
             v
            app
```

This diagram shows that four crates: `libstd`, two libraries
(creatively titled `lib1` and `lib2`), and an application `app`. `app`
uses both of the libraries (and, transitively, libstd). The libraries
are otherwise defined independently from one another., We say that
`libstd` is a parent of the other crates, and that `lib[12]` are
cousins.

OK, so, imagine that `lib1` defines a type `Carton` but doesn't
implement any traits for it. This is a kind of smart pointer, like
`Box`.

```rust
// In lib1
struct Carton<T> { }
```

Now imagine that the `app` crate defines a type `AppType` that uses
the `Debug` trait.

```rust
// In app
struct AppType { }
impl Debug for AppType { }
```

At some point, `app` has a `Carton<AppType>` that it is passing around,
and it tries to use the `Debug` trait on that:

```rust
// In app
fn foo(c: Carton<AppType>) {
    println!("foo({:?})", c); // Error
    ...
}
```

Uh oh, now we encounter a problem because there is no impl of `Debug`
for `Carton<AppType>`. But `app` can solve this by adding such an
impl:

```rust
// In app
impl Debug for Carton<AppType> { ... }
```

You might expect this to be illegal per the orphan rules, but in fact
it is not, and this is no accident. We *want* people to be able to
define impls on *references* to their types. That is, since `Carton`
is a smart pointer, we want impls like the one above to work, just
like you should be able to do an impl on `&AppType` or `Box<AppType>`.

OK, so, what's the problem? The problem is that now maybe `lib1` notices
that `Carton` should define `Debug`, and it adds a blanket impl for all
types:

```rust
// In lib1
impl<T:Debug> Debug for Carton<T> { }
```

This seems like a harmless change, but now if `app` tries to
recompile, it will encounter a **coherence violation**.

What went wrong? Well, if you think about it, even a simple impl like

```rust
impl Debug for Carton<AppType> { }
```

contains an implicit negative assertion that no ancestor crate defines
an impl that could apply to `Carton<AppType>`. This is fine at any
given moment in time, but as the ancestor crates evolve, they may add
impls that violate this negative assertion.

### Negative reasoning in coherence today, the more complex case

The previous example was relatively simple in that it only involved a
single trarit (`Debug`). But the current coherence rules also allow us
to concoct examples that employ multiple traits. For example, suppose
that `app` decided to workaround the absence of `Debug` by defining
it's own debug protocol. This uses `Debug` when available, but allows
`app` to add new impls if needed.

```rust
// In app, before `lib1` added an impl of `Debug` for `Carton`
trait AppDebug { ... }
impl<T:Debug> AppDebug for T { }
impl<T:AppDebug> AppDebug for Carton<T> { }
```

This is perfectly legal (actually, I realized later that this is only
legal due to [a bug][23516]; but I'm leaving the example as is because
I think the larger point still holds and besides if I don't stop
revising this blog post I'll never get anything else done today!). But
now if `lib1` should add the impl of `Debug` for `Carton<T>` that it
added before, we get a conflict again:

```rust
// In lib1
impl<T:Debug> Debug for Carton<T> { }
```

In this case though the conflict isn't that there are two impls of
`Debug`. Instead, adding an impl of `Debug` caused there to be two
impls of `AppDebug` that are applicable to (say) `Carton<AppType>`,
whereas before there was only one.

### Negative reasoning from OIBIT and RFC 586

The conflicts I showed before have one thing in common: the problem is
that when we add an impl in the supercrate, they cause there to be
*too many* impls in downstream crates. This is an important
observation, because it can potentially be solved by specialization or
some other form conflict resolution -- basically a way to decide
between those duplicate impls (see below for details).

I don't believe it is possible *today* to have the problem where
adding an impl in one crate causes there to be *too few* impls in
downstream crates, at least not without enabling some feature-gates.
However, you can achieve this easily with [OIBIT][oibit] and
[RFC 586][586]. **This suggests to me that we want to tweak the design
of OIBIT -- which has been accepted, but is still feature-gated -- and
we do not want to accept RFC 586.**

I'll start by showing what I mean using [RFC 586][586], because it's
more obvious. Consider this example of a trait `Release` that is
implemented for all types that do not implement `Debug`:

```rust
// In app
trait Release { }
impl<T:!Debug> Release for T { }
```

Clearly, if `lib1` adds an impl of `Debug` for `Carton`, we have a
problem in `app`, because whereas before `Carton<i32>` implemented
`Release`, it now does not.

Unfortunately, we can create this same scenario using OIBIT:

```rust
trait Release for .. { }
impl<T:Debug> !Release for T { }`
```

In practice, these sorts of impls are both feature-gated and buggy
(e.g. [#23072][23072]), and there's a good reason for that. When I
looked into fixing the bugs, I realized that this would entail
implementing essentially the full version of negative bounds, which
made me nervous. **It turns out we don't need *conditional negative*
impls for most of the uses of OIBIT that we have in mind, and I think
that we should forbid them before we remove the feature-gate.**

### Orphan rules for negative reasoning

One thing I tried in researching this post is to apply a sort of
orphan condition to negative reasoning. To see what I tried, let me
walk you through how the overlap check works today. Consider the
following impls:

```rust
trait AppDebug { ... }
impl<T:Debug> AppDebug for T { }
impl<U:AppDebug> AppDebug for Carton<U> { }
```

(Assume that there is no impl of `Debug` for `Carton`.) The overlap
checker would check these impls as follows. First, it would create
fresh type variables for `T` and `U` and unify, so that `T=Carton<$U>`
for some fresh variable `$U`. It would then add in all the constraints
that must hold for both impls to simultaneously apply:

    $U: AppDebug
    Carton<$U>: Debug
    
It iterates over this list and tries to find out whether any of them
are known *not* to be true. In this case, the second condition might
or might not be true, it's impossible to say without knowing what type
`$U` is. But the overlap checker believes it say for sure `Carton<$U>:
Debug` doesn't hold, because we don't see any impls that apply to
`Carton`. (NB: In writing this post, I actually realized that this
itself is a separate bug (now filed as [#23516][23516]), but for now
let's ignore that. I don't think it really affects most of this post.)

In any case, this is an example of a negative bound -- the coherence
checker is relying on `Carton<$U>: Debug` not being true. So I
modified the checker so that it could only rely on negative bounds if
either the trait is local or else the type is a struct/enum defined
locally. The idea being that the current crate is in full control of
the set of impls for either of those two cases. This turns out to work
somewhat OK, but it breaks a few patterns we use in the standard
library. The most notable is `IntoIterator`:

```rust
// libcore
trait IntoIterator { }
impl<T:Iterator> for IntoIterator { }

// libcollections
impl<'a,T> IntoIterator for &'a Vec<T> { }
```

In particular, the final impl there is illegal, because it relies on
the fact that `&Vec<T>: Iterator`, and the type `&Vec` is not a struct
defined in the local crate (it's a *reference* to a struct). In
particular, the coherence checker here is pointing out that in
principle we could add an impl like `impl<T:Something> Iterator for
&T`, which would (maybe) conflict. This pattern is one we definitely
want to support, so we'd have to find some way to allow this. (See
below for some further thoughts.)

### What should we do?

Here I'll sketch out some things we can do to help ourselves here.

#### Limiting OIBIT

First, and independently from everything else, we should add the
constraint that negative OIBIT impls cannot add additional
where-clauses beyond those implied by the types involved. (There isn't
much urgency on this because negative impls are feature-gated.)
Therefore, one cannot write an impl like this one, because it would be
adding a constraint `T:Debug`:

```rust
trait Release for .. { }
impl<T:Debug> !Release for T { }`
```

However, this would be legal:

```rust
struct Foo<T:Debug> { }
trait Release for .. { }
impl<T:Debug> !Release for Foo<T> { }`
```

The reason that this is ok is because the type `Foo<T>` isn't even
valid if `T:Debug` doesn't hold. We could also just skip such
"well-formedness" checking in negative impls and then say that there
should be no where-clauses at all.

Either way, the important point is that when checking a negative impl,
the only thing we have to do is try and unify the types. We could even
go farther, and have negative impls use a distinct syntax of some
kind.

### Still to come.

OK, so this post laid out the problem. I have another post or two in
the works exploring possible solutions that I see. I am currently
doing a bit of prototyping that should inform the next post. Stay
tuned.
   
[23516]: https://github.com/rust-lang/rust/issues/23516
[19032]: https://github.com/rust-lang/rust/issues/19032
[586]: https://github.com/rust-lang/rfcs/pull/586
[23086]: https://github.com/rust-lang/rust/issues/23086
[18045]: https://github.com/rust-lang/rust/issues/18045
[oibit]: https://github.com/rust-lang/rfcs/blob/master/text/0019-opt-in-builtin-traits.md
[23072]: https://github.com/rust-lang/rust/issues/23072


