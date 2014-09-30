---
layout: post
title: "Multi- and conditional dispatch in traits"
date: 2014-09-30 09:45:47 -0400
comments: true
categories: [Rust]
---

I've been working on a branch that implements both *multidispatch*
(selecting the impl for a trait based on more than one input type) and
*conditional dispatch* (selecting the impl for a trait based on where
clauses). I wound up taking a direction that is slightly different
from what is described in the [trait reform RFC][traitreform], and I
wanted to take a chance to explain what I did and why. The main
difference is that in the branch we move away from the crate
concatenability property in exchange for better inference and less
complexity.

<!-- more -->

### The various kinds of dispatch

The first thing to explain is what the difference is between these
various kinds of dispatch.

**Single dispatch.** Let's imagine that we have a conversion trait:

```rust
trait Convert<Target> {
    fn convert(&self) -> Target;
}
```
    
This trait just has one method. It's about as simple as it gets. It
converts from the (implicit) `Self` type to the `Target` type. If we
wanted to permit conversion between `int` and `uint`, we might
implement `Convert` like so:

```rust
impl Convert<uint> for int { ... } // int -> uint
impl Convert<int> for uint { ... } // uint -> uint
```

Now, in the background here, Rust has this check we call
*coherence*. The idea is (at least as implemented in the `master`
branch at the moment) to guarantee that, for any given `Self` type,
there is at most one impl that applies. In the case of these two
impls, that's satisfied. The first impl has a `Self` of `int`, and the
second has a `Self` of `uint`. So whether we have a `Self` of `int` or
`uint`, there is at most one impl we can use (and if we don't have a
`Self` of `int` or `uint`, there are zero impls, that's fine too).

**Multidispatch.** Now imagine we wanted to go further and allow `int`
to be converted to some other type `MyInt`. We might try writing an
`impl` like this:

```rust
struct MyInt { i: int }
impl Convert<MyInt> for int { ... } // int -> MyInt
```

Unfortunately, now we have a problem. If `Self` is `int`, we now have
two applicable conversions: one to `uint` and one to `MyInt`. In a
purely single dispatch world, this is a coherence violation.

The idea of multidispatch is to say that it's ok to have multiple
impls with the same `Self` type as long as at least one of their
*other* type parameters are different. So this second impl is ok,
because the `Target` type parameter is `MyInt` and not `uint`.

**Conditional dispatch.** So far we have dealt only in concrete types
like `int` and `MyInt`. But sometimes we want to have impls that apply
to a category of types. For example, we might want to have a
conversion from any type `T` into a `uint`, as long as that type
supports a `MyGet` trait:

```rust
trait MyGet {
    fn get(&self) -> MyInt;
}

impl<T> Convert<MyInt> for T
    where T:Hash
{
    fn convert(&self) -> MyInt {
        self.hash()
    }
}
```

We call impls like this, which apply to a broad group of types,
*blanket impls*. So how do blanket impls interact with the coherence
rules? In particular, does the conversion from `T` to `MyInt` conflict
with the impl we saw before that converted from `int` to `MyInt`? In
my branch, the answer is "only if `int` implements the `MyGet` trait".
This seems obvious but turns out to have a surprising amount of
subtlety to it.

### Crate concatenability and inference

In the trait reform RFC, I mentioned a desire to support *crate
concatenability*, which basically means that you could take two crates
(Rust compilation units), concatenate them into one crate, and
everything would keep building. It turns out that the coherence rules
already basically guarantee this without any further thought --
*except* when it comes to inference. That's where things get
interesting.

To see what I mean, let's look at a small example. Here we'll use the
same `Convert` trait as we saw before, but with just the original set
of impls that convert between `int` and `uint`. Now imagine that I
have some code which starts with a `int` and tries to call `convert()`
on it:

```rust
trait Convert<T> { fn convert(&self) -> T; }
impl Convert<uint> for int { ... }
impl Convert<int> for uint { ... }
...
let x: int = ...;
let y = x.convert();
```

What can we say about the type of `y` here? Clearly the user did not
specify it and hence the compiler must infer it. If we look at the set
of impls, you might think that we can infer that `y` is of type
`uint`, since the only thing you can convert a `int` into is a `uint`.
And that is true -- at least as far as this particular crate goes.

However, if we consider beyond a single crate, then it is possible
that some other crate comes along and adds more impls. For example,
perhaps another crate adds the conversion to the `MyInt` type that we
saw before:

```rust
struct MyInt { i: int }
impl Convert<MyInt> for int { ... } // int -> MyInt
```

Now, if we were to concatenate those two crates together, then this
type inference step wouldn't work anymore, because `int` can now be
converted to *either* `uint` or `MyInt`. This means that the snippet
of code we saw before would probably require a type annotation to clarify
what the user wanted:

```
let x: int = ...;
let y: uint = x.convert();
```

### Crate concatenation and conditional impls

I just showed that the crate concatenability principle interferes with
inference in the case of multidispatch, but that is not necessarily
bad. It may not seem so harmful to clarify both the type you are
converting from and the type you are converting to, even if there is
only one type you could legally choose. Also, multidispatch is fairly
rare; most traits has a single type that decides on the `impl` and
then all other types are uniquely determined. Moreover, with the
[associated types RFC][assoctypes], there is even a syntactic way to
express this. Still, aturon and I have encountered cases where
multidispatch was technically needed but rarely utilized, and hence
where usability would be improved by having inference also for input
type parameters.

However, when you start trying to implement *conditional dispatch*
that is, dispatch predicated on where clauses, crate concatenability
becomes a real problem. To see why, let's look at a different trait
called `Push`. The purpose of the `Push` trait is to describe
collection types that can be appended to. It has one associated type
`Elem` that describes the element types of the collection:

```rust
trait Push {
    type Elem;
    
    fn push(&mut self, elem: Elem);
}
```
    
We might implement `Push` for a vector like so:

```rust
impl<T> Push for Vec<T> {
    type Elem = T;
    
    fn push(&mut self, elem: T) { ... }
}
```

(This is not how the actual standard library works, since `push` is an
inherent method, but the principles are all the same and I didn't want
to go into inherent methods at the moment.) OK, now imagine I have
some code that is trying to construct a vector of `char`:

```rust
let mut v = Vec::new();
v.push('a');
v.push('b');
v.push('c');
```

The question is, can the compiler resolve the calls to `push()` here?
That is, can it figure out which impl is being invoked? (At least in
the current system, we must be able to resolve a method call to a
specific impl or type bound at the point of the call -- this is a
consequence of having type-based dispatch.) Somewhat surprisingly, if
we're strict about crate concatenability, the answer is *no*.

The reason has to do with DST. The impl for `Push` that we saw before
in fact has an implicit `where` clause:

```rust
impl<T> Push for Vec<T>
    where T : Sized
{ ... }
```

This implies that some other crate could come along and implement `Push` for
an unsized type:

```rust
impl<T> Push for Vec<[T]> { ... }
```

Now, when we consider a call like `v.push('a')`, the compiler must
pick the impl based solely on the type of the receiver `v`. At the
point of calling `push`, all we know is that is the type of `v` is a
vector, but we don't know what it's a vector *of* -- to infer the
element type, we must first resolve the very call to `push` that we
are looking at right now.

Clearly, not being able to call `push` without specifying the type of
elements in the vector is very limiting. There are a couple of ways to
resolve this problem. I'm not going to go into detail on these solutions,
because they are not what I ultimately opted to do. But briefly:

- We could introduce some new syntax for distinguishing *conditional
  dispatch* vs other where clauses (basically the input/output
  distinction that we use for type parameters vs associated types).
  Perhaps a `when` clause, used to select the impl, versus a `where`
  clause, used to indicate conditions that must hold once the impl is
  selected, but which are not checked beforehand. Hard to understand
  the difference? Yeah, I know, I know.
- We could use an ad-hoc rule to distinguish the input/output clauses.
  For example, all predicates applied to type parameters that are
  directly used as an input type. Limiting, though, and non-obvious.
- We could create a much more involved reasoning system (e.g., in this
  case, `Vec::new()` in fact yields a vector whose types are known to
  be sized, but we don't take this into account when resolving the
  call to `push()`). Very complicated, unclear how well it will work
  and what the surprising edge cases will be.

Or... we could just abandon crate concatenability. But wait, you ask,
isn't it important?

### Limits of crate concatenability

So we've seen that crate concatenability conflicts with inference and
it also interacts negatively with conditional dispatch. I now want to
call into question just how valuable it is in the first place. Another
way to phrase crate concatenability is to say that it allows you to
always add new impls without disturbing existing code using that
trait. This is actually a fairly limited guarantee. It is still
possible for adding impls to break downstream code across two
*different* traits, for example. Consider the following example:

```rust
struct Player { ... }
trait Cowboy {
    // draw your gun!
    fn draw(&self);
}
impl Cowboy for Player { ...}

struct Polygon { ... }
trait Image {
    // draw yourself (onto a canvas...?)
    fn draw(&self);
}
impl Image for Polygon { ... }
```

Here you have two traits with the same method name (`draw`). However,
the first trait is implemented only on `Player` and the other on
`Polygon`. So the two never actually come into conflict.  In
particular, if I have a player `player` and I write `player.draw()`, it could
only be referring to the `draw` method of the `Cowboy` trait.

But what happens if I add another impl for `Image`?

```rust
impl Image for Player { ... }
```

Now suddenly a call to `player.draw()` is ambiguous, and we need to
use so-called "UFCS" notation to disambiguate (e.g.,
`Player::draw(&player)`).

(Incidentally, this ability to have type-based dispatch is a great
strength of the Rust design, in my opinion. It's useful to be able to
define method names that overlap and where the meaning is determined
by the type of the receiver.)

### Conclusion: drop crate concatenability

So I've been turning these problems over for a while. After some
discussions with others, aturon in particular, I feel the best fix is
to abandon crate concatenability. This means that the algorithm for
picking an impl can be summarized as:

1. Search the impls in scope and determine those whose types can be
   unified with the current types in question and hence could possibly
   apply.
2. If there is more than one impl in that set, start evaluating where clauses to
   narrow it down.

This is different from the current `master` in two ways. First of all,
to decide whether an impl is applicable, we use simple unification
rather than a one-way match. Basically this means that we allow impl
matching to affect inference, so if there is at most one impl that can
match the types, it's ok for the compiler to take that into account.
This covers the `let y = x.convert()` case. Second, we don't consider
the where clauses unless they are needed to remove ambiguity.

I feel pretty good about this design. It is somewhat less pure, in
that it blends the role of inputs and outputs in the impl selection
process, but it seems very *usable*. Basically it is guided only by
the ambiguities that really exist, not those that could theoretically
exist in the future, when selecting types. This avoids forcing the
user to classify everything, and in particular avoids the
classification of where clauses according to when they are evaluated
in the impl selection process. Moreover I don't believe it introduces
any significant compatbility hazards that were not already present in
some form or another.

[traitreform]: https://github.com/rust-lang/rfcs/blob/master/active/0024-traits.md
[assoctypes]: https://github.com/rust-lang/rfcs/blob/master/active/0059-associated-items.md
