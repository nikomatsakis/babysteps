---
layout: post
title: "Intersection Impls"
date: 2016-09-24 06:07:31 -0400
comments: false
categories: [Rust, Specialization, Traits]
---

As some of you are probably aware, on the nightly Rust builds, we
currently offer a feature called **specialization**, which was defined
in [RFC 1210][1210]. The idea of specialization is to improve Rust's
existing coherence rules to allow for overlap between impls, so long
as one of the overlapping impls can be considered *more
specific*. Specialization is hotly desired because it can enable
powerful optimizations, but also because it is an important component
for [modeling object-oriented designs][OO].

[OO]: http://aturon.github.io/blog/2015/09/18/reuse/
[1210]: https://github.com/rust-lang/rfcs/pull/1210

The current specialization design, while powerful, is also limited in
a few ways. I am going to work on a series of articles that explore
some of those limitations as well as possible solutions.

This particular posts serves two purposes: it describes the running
example I want to consder, and it describes one possible solution:
**intersection impls** (more commonly called "lattice impls"). We'll
see that intersection impls are a powerful feature, but they don't
completely solve the problem I am aiming to solve and they also
intoduce other complications. My conclusion is that they may be a part
of the final solution, but are not sufficient on their own.

<!-- more -->

### Running example: interconverting between `Copy` and `Clone`

I'm going to structure my posts around a detailed look at the `Copy`
and `Clone` traits, and in particular about how we could use
specialization to bridge between the two. These two traits are used in
Rust to define how values can be duplicated. The idea is roughly like
this:

- A type is `Copy` if it can be copied from one place to another just
  by copying bytes (i.e., with `memcpy`). This is basically types that
  consist purely of scalar values (e.g., `u32`, `[u32; 4]`, etc).
- The `Clone` trait expands upon `Copy` to include all types that can
  be copied at all, even if requires executing custom code or allocating
  memory (for example, a `String` or `Vec<u32>`).

These two traits are clearly *related*. In fact, `Clone` is a
*supertrait* of `Copy`, which means that every type that is copyable
must also be cloneable.

For better or worse, supertraits in Rust work a bit differently than
*superclasses* from OO languages. In particular, the two traits are
still independent from one another. This means that if you want to
declare a type to be `Copy`, you must also supply a `Clone` impl.
Most of the time, we do that with a `#[derive]` annotation, which
auto-generates the impls for you:

```rust
#[derive(Copy, Clone, ...)]
struct Point {
    x: u32,
    y: u32,
}
```

That `derive` annotation will expand out to two impls looking
roughly like this:

```rust
struct Point {
    x: u32,
    y: u32,
}

impl Copy for Point {
    // Copy has no methods; it can also be seen as a "marker"
    // that indicates that a cloneable type can also be
    // memcopy'd.
}

impl Clone for Point {
    fn clone(&self) -> Point {
        *self // this will just do a memcpy
    }
}
```

The second impl (the one implementing the `Clone` trait) seems a bit
odd. After all, that impl is written for `Point`, but in principle it
could be used *any* `Copy` type. It would be nice if we could add a
blanket impl that converts from `Copy` to `Clone` that applies to all
`Copy` types:

```rust
// Hypothetical addition to the standard library:
impl<T:Copy> Clone for T {
    fn clone(&self) -> Point {
        *self
    }
}
```

If we had such an impl, then there would be no need for `Point` above
to implement `Clone` explicitly, since it implements `Copy`, and the
blanket impl can be used to supkply the `Clone` impl. (In other words,
you could just write `#[derive(Copy)]`.) As you have probably
surmised, though, it's not that simple. Adding a blanket impl like
this has a few complications we'd have to overcome first. This is
still true with the specialization system described in [RFC 1210][].

There are a number of examples where these kinds of blanket impls
might be useful. Some examples: implementing `PartialOrd` in terms of
`Ord`, implementing `PartialEq` in terms of `Eq`, and implementing
`Debug` in terms of `Display`.

### Coherence and backwards compatibility

<img src="/images/Troymcclure.png" style="float:left; height:285px;"></img>

*Hi! I'm the language feature coherence! You may remember me from
previous essays like [Little Orphan Impls][LOI] or [RFC 1023][].*

Let's take a step back and just think about the language as it is now,
without specialization. With today's Rust, adding a blanket
`impl<T:Copy> Clone for T` would be massively backwards incompatible.
This is because of the coherence rules, which aim to prevent there
from being more than one trait applicable to any type (or, for generic
traits, set of types).

<div style="clear:both"></div>

So, if we tried to add the blanket impl now, without specialization,
it would mean that every type annotated with `#[derive(Copy, Clone)]`
would stop compiling, because we would now have two clone impls: one
from derive and the blanket impl we are adding. Obviously not
feasible.

[LOI]: http://smallcultfollowing.com/babysteps/blog/2015/01/14/little-orphan-impls/
[RFC 1023]: https://github.com/rust-lang/rfcs/pull/1023

### Why didn't we add this blanket impl already then?

You might then wonder why we didn't add this blanket impl converting from
`Copy` to `Clone` in the "wild west" days, when we broke every
existing Rust crate on a regular basis. We certainly considered
it. The answer is that, if you have such an impl, the coherence rules
mean that it would not work well with generic types.

To see what problems arise, consider the type `Option`:

```rust
#[derive(Copy, Clone)]
enum Option<T> {
    Some(T),
    None,
}
```

You can see that `Option<T>` derives `Copy` and `Clone`. But because
`Option` is generic for `T`, those impls have a slightly different
look to them once we expand them out:

```rust
impl<T:Copy> Copy for Option<T> { }

impl<T:Clone> Clone for Option<T> {
    fn clone(&self) -> Option<T> {
        match *self {
            Some(ref v) => Some(v.clone()),
            None => None,
        }
    }
}
```

Before, the `Clone` impl for `Point` was just `*self`. But for
`Option<T>`, we have to do something more complicated, which actually
calls `clone` on the contained value (in the case of a `Some`). To see
why, imagine a type like `Option<Rc<u32>>` -- this is clearly
cloneable, but it is not `Copy`.  So the impl is rewritten so that it
only assumes that `T: Clone`, not `T: Copy`.

The problem is that types like `Option<T>` are *sometimes* `Copy` and
sometimes not. So if we had the blanket impl that converts all `Copy`
types to `Clone`, and we have the impl above that impl `Clone` for
`Option<T>` if `T: Clone`, then we can easily wind up in a situation
where there are two applicable impls. For example, consider
`Option<u32>`: it is `Copy`, and hence we could use the blanket impl
that just returns `*self`. But it is also fits the `Clone`-based impl
I showed above. This is a **coherence violation**, because now the
compiler has to pick which impl to use. Obviously, in the case of the
trait `Clone`, it shouldn't matter too much which one it chooses,
since they both have the same effect, but the compiler doesn't know
that.

### Enter specialization

OK, all of that prior discussion was assuming the Rust of today.  So
what if we adopted the existing [specialization RFC][1210]?  After
all, its whole purpose is to improve coherence so that it is possible
to have multiple impls of a trait for the same type, so long as one of
those implementations is *more specific*. Maybe that applies here?

In fact, the RFC as written today **does not**. The reason is that the
RFC defines rules that say an impl A is more specific than another
impl B if impl A applies to a **strict subset** of the types which
impl B applies to. Let's consider some arbitrary trait `Foo`.  Imagine
that we have an impl of `Foo` that applies to any `Option<T>`:

```rust
impl<T> Foo for Option<T> { .. }
```

The "more specific" rule would then allow a second impl for
`Option<i32>`; this impl would specialize the more generic one:

```rust
impl Foo for Option<i32> { .. }
```

Here, the second impl is more specific than the first, because while
the first impl can be used for `Option<i32>`, it can also be used for
lots of other types, like `Option<u32>`, `Option<i64>`, etc. So that
means that these two impls would be **accepted** under
[RFC #1210][1210]. If the compiler ever had to choose between them, it
would prefer the impl that is specific to `Option<i32>` over the
generic one that works for all `T`.

But if we try to apply that rule to our two `Clone` impls, we run into
a problem. First, we have the blanket impl:

```rust
impl<T:Copy> Clone for T { .. }
```

and then we have an impl tailored to `Option<T>` where `T: Clone`:

```rust
impl<T:Clone> Clone for Option<T> { .. }
```

Now, you might think that the second impl is more specific than the
blanket impl. After all, it can be used for any type, whereas the
second impl can only be used `Option<T>`.  Unfortunately, this isn't
quite right. After all, the blanket impl cannot be used for *any* type
`T`: it can only be used for `Copy` types. And we already saw that
there are lots of types for which the second impl can be used where
the first impl is inapplicable. In other words, neither impl is a
subset of one another -- rather, they both cover two distinct, but
overlapping, sets of types.

To see what I mean, let's look at some examples:

```
| Type              | Blanket impl | `Option` impl |
| ----              | ------------ | ------------- |
| i32               | APPLIES      | inapplicable  |
| Box<i32>          | inapplicable | inapplicable  |
| Option<i32>       | APPLIES      | APPLIES       |
| Option<Box<i32>>  | inapplicable | APPLIES       |
```

Note in particular the first and fourth rows. The first row shows that
the blanket impl is not a subset of the `Option` impl.  The last row
shows that the `Option` impl is not a subset of the blanket impl
either. That means that these two impls would be **rejected** by
[RFC #1210][1210] and hence adding a blanket impl now would *still* be
a breaking change. Boo!

To see the problem from another angle, consider this Venn digram,
which indicates, for every impl, the sets of types that it matches.
As you can see, there is overlap between our two impls, but neither is
a strict subset of one another:

```
+-----------------------------------------+
|[impl<T:Copy> Clone for T]               |
|                                         |
| Example: i32                            |
| +---------------------------------------+-----+
| |                                       |     |
| | Example: Option<i32>                  |     |
| |                                       |     |
+-+---------------------------------------+     |
  |                                             |
  |   Example: Option<Box<i32>>                 |
  |                                             |
  |          [impl<T:Clone> Clone for Option<T>]|
  +---------------------------------------------+
```

### Enter intersection impls

One of the first ideas proposed for solving this is the so-called
"lattice" specialization rule, which I will call "intersection" impls,
since I think that captures the spirit better. The intuition is pretty
simple: if you have two impls that have a partial intersection, but
which don't strictly subset one another, then you can add a third impl
that covers *precisely* that intersection, and hence which subsets
both of them. So now, for any type, there is always a "most specific"
impl to choose. To get the idea, it may help to consider this "ASCII
Art" Venn diagram. Note the difference from above: there is now an
impl (indicating with `=` lines and `.` shading) covering precisely
the intersection of the other two.

```
+-----------------------------------------+
|[impl<T:Copy> Clone for T]               |
|                                         |
| Example: i32                            |
| +=======================================+-----+
| |[impl<T:Copy> Clone for Option<T>].....|     |
| |.......................................|     |
| |.Example: Option<i32>..................|     |
| |.......................................|     |
+-+=======================================+     |
  |                                             |
  |   Example: Option<Box<i32>>                 |
  |                                             |
  |          [impl<T:Clone> Clone for Option<T>]|
  +---------------------------------------------+
```

Intersection impls have some nice properties. For one thing, it's a
kind of minimal extension of the existing rule. In particular, if you
are just looking at any two impls, the rules for deciding which is
more specific are unchanged: the only difference when adding in
intersection impls is that coherence permits overlap when it otherwise
wouldn't.

They also give us a good opportunity to recover some
optimization. Consider the two impls in this case: the "blanket" impl
that applies to any `T: Copy` simply copies some bytes around, which
is very fast. The impl that is tailed to `Option<T>`, however, does
more work: it matches the impl and then recursively calls
`clone`. This work is necessary if `T: Copy` does not hold, but
otherwise it's wasted work.  With an intersection impl, we can recover
the full performance:

```rust
// intersection impl:
impl<T:Copy> Clone for Option<T> {
    fn clone(&self) -> Option<T> {
        *self // since T: Copy, we can do this here
    }
}
```

### A note on compiler messages

I'm about to pivot and discuss the shortcomings of intersection
impls. But before I do so, I want to talk a bit about the compiler
messages here. I think that the core idea of specialization -- that
you want to pick the impl that applies to the **most specific** set of
types -- is fairly intuitive. But working it out in practice can be
kind of confusing, especially at first. So whenever we propose any
extension, we have to think carefully about the error messages that
might result.

In this particular case, I think that we could give a rather nice error
message. Imagine that the user had written these two impls:

```rust
impl<T: Copy> Clone for T { // impl A
    fn clone(&self) -> T { ... }
}    

impl<T: Clone> Clone for Option<T> { // impl B
    fn clone(&self) -> Option<T> { ... }
}    
```

As we've seen, these two impls overlap but neither specializes the
other. One might imagine an error message that says as much, and
which also suggests the intersection impl that must be added:

```
error: two impls overlap, but neither specializes the other
  |
2 | impl<T: Copy> Clone for T {...}
  | ----
  |
4 | impl<T: Clone> Clone for Option<T> {...}
  |
  | note: both impls apply to a type like `Option<T>` where `T: Copy`;
  |       to specify the behavior in this case, add the following intersection impl:
  |       `impl<T: Copy> Clone for Option<T>`
```

Note the message at the end. The wording could no doubt be improved,
but the key point is that we should be to actually tell you **exactly
what impl is still needed**.

### Intersection impls do not solve the cross-crate problem

Unfortunately, intersection impls don't give us the backwards
compatibility that we want, at least not by themselves. The problem
is, if we add the blanket impl, we *also* have to add the intersection
impl. **Within the same crate, this might be ok. But if this means that
downstream crates have to add an intersection impl too, that's a big
problem.**

### Intersection impls may force you to predict the future

There is one other problem with intersection impls that arises in
cross-crate situations, which
[nrc described on the tracking issue][nrc]: sometimes there is a
*theoretical* intersection between impls, but that intersection is
empty in practice, and hence you may not be able to write the code you
wanted to write. Let me give you an example. This problem doesn't show
up with the `Copy`/`Clone` trait, so we'll switch briefly to another
example.

[nrc]: https://github.com/rust-lang/rust/issues/31844#issuecomment-247867693

Imagine that we are adding a `RichDisplay` trait to our project. This
is much like the existing [`Display`][display] trait, except that it
can support richer formatting like ANSI codes or a GUI. For
convenience, we want any type that implements `Display` to also
implement `RichDisplay` (but without any fancy formatting). So we add
a trait and blanket impl like this one (let's call it impl A):

[display]: https://doc.rust-lang.org/std/fmt/trait.Display.html

```rust
trait RichDisplay { /* elided */ }
impl<D: Display> RichDisplay for D { /* elided */ } // impl A
```

Now, imagine that we are also using some other crate `widget` that
contains various types, including `Widget<T>`. This `Widget<T>` type
does not implement `Display`. But we would like to be able to render a
widget, so we implement `RichDisplay` for this `Widget<T>` type. Even
though we didn't define `Widget<T>`, we can implement a trait for it
because we defined the trait:

```rust
impl<T: RichDisplay> RichDisplay for Widget<T> { ... } // impl B
```

Well, now we have a problem! You see, according to the rules from
[RFC 1023][], impls A and B are considered to *potentially* overlap,
and hence we will get an error. This might surprise you: after all,
impl A only applies to types that implement `Display`, and we said
that `Widget<T>` does not. The problem has to do with semver: because
`Widget<T>` was defined in another crate, it is outside of our
control. In this case, the other crate is allowed to implement
`Display` for `Widget<T>` at some later time, and that should not be a
breaking change. But imagine that this other crate added an impl like
this one (which we can call impl C):

```rust
impl<T: Display> Display for Widget<T> { ... } // impl C
```

Such an impl would cause impls A and B to overlap. Therefore,
coherence considers these to be overlapping -- however, specialization
does not consider impl B to be a specialization of impl A, because, at
the moment, there is no subset relationship between them. **So there
is a kind of catch-22 here: because the impl may exist in the future,
we can't consider the two impls disjoint, but because it doesn't exist
right now, we can't consider them to be specializations.**

Clearly, intersection impls don't help to address this issue, as the
set of intersecting types is empty. You might imagine having some
alternative extension to coherence that permits impl B on the logic of
"if impl C were added in the future, that'd be fine, because impl B
would be a specialization of impl A".

This logic is pretty dubious, though! For example, impl C might have
been written another way (we'll call this alternative version of impl C "impl C2"):

```rust
impl<T: WidgetDisplay> Display for Widget<T> { ... } // impl C2
//   ^^^^^^^^^^^^^^^^ changed this bound
```

Note that instead of working for any `T: Display`, there is now some
other trait `T: WidgetDisplay` in use. Let's say it's only implemented
for optional 32-bit integers right now (for some reason or another):

```rust
trait WidgetDisplay { ... }
impl WidgetDisplay for Option<i32> { ... }
```

So now if we had impls A, B, and C2, we would have a different
problem. Now impls A and B would overlap for `Widget<Option<i32>>`,
but they would not overlap for `Widget<String>`. The reason here is
that `Option<i32>: WidgetDisplay`, and hence impl A applies. But
`String: RichDisplay` (because `String: Display`) and hence impl B
applies. Now we are back in the territory where intersection impls
come into play. So, again, **if we had impls A, B, and C2**, one could
imagine writing an intersection impl to cover this situation:

```rust
impl<T: RichDisplay + WidgetDisplay> RichDisplay for Widget<T> { ... } // impl D
```

But, of course, **impl C2 has yet to be written**, so we can't really
write this intersection impl **now**, in advance. We have to wait
until the conflict arises before we can write it.

You may have noticed that I was careful to specify that both the
`Display` trait and `Widget` type were defined outside of the current
crate. This is because [RFC 1023][] permits the use of "negative
reasoning" **if either the trait or the type is under local
control**. That is, if the `RichDisplay` and the `Widget` type were
defined in the *same* crate, then impls A and B could co-exist,
because we are allowed to rely on the fact that `Widget` does not
implement `Display`. The idea here is that the only way that `Widget`
could implement `Display` is if I modify the crate where `Widget` is
defined, and once I am modifying things, I can also make any other
repairs (such as adding an intersection impl) that are necessary.

### Conclusion

Today we looked at a particular potential use for specialization:
adding a blanket impl that implements `Clone` for any `Copy` type. We
saw that the current "subset-only" logic for specialization isn't
enough to permit adding such an impl. We then looked at one proposed
fix for this, intersection impls (often called lattice
impls).

Intersection impls are appealing because they increase expressiveness
while keeping the general feel of the "subset-only" logic. They also
have an "explicit" nature that appeals to me, at least in
principle. That is, if you have two impls that partially overlap, the
compiler doesn't select which one should win: instead, you write an
impl to cover precisely that intersection, and hence specify it
yourself. Of course, that explicit nature can also be verbose and
irritating sometimes, particularly since you will often want the
"intersection impl" to behave the same as one of the other two (rather
than doing some third, different thing).

Moreover, the explicit nature of interseciton impls causes problems
across crates:

- they don't allow you to add a blanket impl in a backwards compatible
  fashion;
- they interact poorly with semver, and specifically the limitations
  on negative logic imposed by [RFC 1023][].

My conclusion then is that intersection impls may well be *part* of
the solution we want, but we will need additional mechanisms. Stay
tuned for additional posts.

### A note on comments

As is my wont, I am going to close this post for comments. If you
would like to leave a comment, please go to this
[thread on Rust's internals forum][thread] instead.

[thread]: https://internals.rust-lang.org/t/blog-post-intersection-impls/4129

