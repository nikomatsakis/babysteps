---
categories:
- Rust
comments: true
date: "2015-03-19T17:59:39Z"
published: false
slug: the-danger-of-negative-thinking
title: The danger of negative thinking
---

One of the aspects of language design that I find the most interesting
is trying to take *time* into account. That is, when designing a type
system in particular, we tend to think of the program as a fixed,
immutable artifact. But of course real programs evolve over time, and
when designing a language it's important to consider what impact the
type rules will have on the ability of people to change their
programs. Naturally as we approach the 1.0 release of Rust this is
very much on my mind, since we'll be making firmer commitments to
compatibility than we ever have before.

Anyway, with that introduction, I recently realized that our current
trait system contains a [forward compatibility hazard][23086]
concerned with *negative reasoning*. Negative reasoning is basically
the ability to decide if a trait is *not* implemented for a given
type. The most obvious example of negative reasoning are
[negative trait bounds][586], which have been proposed in a rather
nicely written RFC. However, what's perhaps less widely recognized is
that the trait system as currently implemented already has some amount
of negative reasoning, in the form of the coherence system.

This blog post covers why negative reasoning can be problematic, with
a focus on the pitfalls in the current coherence system. This post
only covers the problem. I've been working on prototyping possible
solutions and I'll be covering those in the next few blog posts.

<!--more-->

### A goal

Let me start out with an implicit premise of this post. I think it's
important that we be able to add impls of existing traits to existing
types without breaking downstream code (that is, causing it to stop
compiling, or causing it to radically different things). Let me give
you a concrete example. libstd defines the `Range<T>` type. Right now,
this type is not `Copy` for various [good reasons][18045]. However, we
might like to make it `Copy` in the future. It feels like that should
be legal. However, as I'll show you below, this could in fact cause
existing code not to compile. I think this is a problem.

(In the next few posts when I start covering solutions, we'll see that
it may be that one cannot *always* add impls of any kind for *all
traits* to *all types*.  If so, I can live with it, but I think we
should try to make it possible to add as many kinds of impls as
possible.)

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
struct Carton<T> { ... }
```

Now imagine that the `app` crate defines a type `AppType` that uses
the `Debug` trait.

```rust
// In app
struct AppType { ... }
impl Debug for AppType { ... }
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
define impls on *references* and *boxes* to their types. That is,
since `Carton` is a smart pointer, we want impls like the one above to
work, just like you should be able to do an impl on `&AppType` or
`Box<AppType>`.

OK, so, what's the problem? The problem is that now maybe `lib1` notices
that `Carton` should define `Debug`, and it adds a blanket impl for all
types:

```rust
// In lib1
impl<T:Debug> Debug for Carton<T> { ... }
```

This seems like a harmless change, but now if `app` tries to
recompile, it will encounter a **coherence violation**.

What went wrong? Well, if you think about it, even a simple impl like

```rust
impl Debug for Carton<AppType> { ... }
```

contains an implicit negative assertion that no ancestor crate defines
an impl that could apply to `Carton<AppType>`. This is fine at any
given moment in time, but as the ancestor crates evolve, they may add
impls that violate this negative assertion.

### Negative reasoning in coherence today, the more complex case

The previous example was relatively simple in that it only involved a
single trait (`Debug`). But the current coherence rules also allow us
to concoct examples that employ multiple traits. For example, suppose
that `app` decided to workaround the absence of `Debug` by defining
it's own debug protocol. This uses `Debug` when available, but allows
`app` to add new impls if needed.

```rust
// In lib1 (note: no `Debug` impl yet)
struct Carton<T> { ... }

// In app, before `lib1` added an impl of `Debug` for `Carton`
trait AppDebug { ... }
impl<T:Debug> AppDebug for T { ... } // Impl A

struct AppType { ... }
impl Debug for AppType { ... }
impl AppDebug for Carton<AppType> { ... } // Impl B
```

This is all perfectly legal. In particular, implementing `AppDebug`
for `Carton<AppType>` is legal because there is no impl of `Debug` for
`Carton`, and hence impls A and B are not in conflict. But now if
`lib1` should add the impl of `Debug` for `Carton<T>` that it added
before, we get a conflict again:

```rust
// Added to lib1
impl<T:Debug> Debug for Carton<T> { ... }
```

In this case though the conflict isn't that there are two impls of
`Debug`. Instead, adding an impl of `Debug` caused there to be two
impls of `AppDebug` that are applicable to `Carton<AppType>`, whereas
before there was only one.

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
[RFC 586][586]. This suggests to me that we want to tweak the design
of OIBIT -- which has been accepted, but is still feature-gated -- and
we do not want to accept RFC 586 (at least not without further
thought).

I'll start by showing what I mean using [RFC 586][586], because it's
more obvious. Consider this example of a trait `Release` that is
implemented for all types that do not implement `Debug`:

```rust
// In app
trait Release { ... }
impl<T:!Debug> Release for T { ... }
```

Clearly, if `lib1` adds an impl of `Debug` for `Carton`, we have a
problem in `app`, because whereas before `Carton<i32>` implemented
`Release`, it now does not.

Unfortunately, we can create this same scenario using OIBIT:

```rust
trait Release for .. { ... }
impl<T:Debug> !Release for T { ... }`
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
impl<T:Debug> AppDebug for T { ... }
impl AppDebug for Carton<AppType> { ... }
```

(Assume that there is no impl of `Debug` for `Carton`.) The overlap
checker would check these impls as follows. First, it would create
fresh type variables for `T` and unify, so that `T=Carton<AppType>`.
Because `T:Debug` must hold for the first impl to be applicable, and
`T=Carton<AppType>`, that implies that if both impls are to be
applicable, then `Carton<AppType>: Debug` must hold. But by searching
the impls in scope, we can see that it does not hold -- and thanks to
the coherence orphan rules, we know that nobody else can make it hold
either. So we conclude that the impls do not overlap.

It's true that `Carton<AppType>: Debug` doesn't hold *now* -- but this
reasoning doesn't take into account *time*. Because `Carton` is
defined in the `lib1` crate, and not the `app` crate, it's not under
"local control". It's plausible that `lib1` can add an impl of `Debug`
for `Carton<T>` for all `T` or something like that. This is the central
hazard I've been talking about.

To avoid this hazard, I modified the checker so that it could only
rely on negative bounds if either the trait is local or else the type
is a struct/enum defined locally. The idea being that the current
crate is in full control of the set of impls for either of those two
cases. This turns out to work somewhat OK, but it breaks a few
patterns we use in the standard library. The most notable is
`IntoIterator`:

```rust
// libcore
trait IntoIterator { ... }
impl<T:Iterator> for IntoIterator { ... }

// libcollections
impl<'a,T> IntoIterator for &'a Vec<T> { ... }
```

In particular, the final impl there is illegal, because it relies on
the fact that `&Vec<T>: Iterator`, and the type `&Vec` is not a struct
defined in the local crate (it's a *reference* to a struct). In
particular, the coherence checker here is pointing out that in
principle we could add an impl like `impl<T:Something> Iterator for
&T`, which would (maybe) conflict. This pattern is one we definitely
want to support, so we'd have to find some way to allow this.

#### Limiting OIBIT

As an aside, I mentioned that OIBIT as specified today is equivalent
to negative bounds. To fix this, we should add the constraint that
negative OIBIT impls cannot add additional where-clauses beyond those
implied by the types involved. (There isn't much urgency on this
because negative impls are feature-gated.)  Therefore, one cannot
write an impl like this one, because it would be adding a constraint
`T:Debug`:

```rust
trait Release for .. { ... }
impl<T:Debug> !Release for T { ... }`
```

However, this would be legal:

```rust
struct Foo<T:Debug> { ... }
trait Release for .. { ... }
impl<T:Debug> !Release for Foo<T> { ... }`
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


