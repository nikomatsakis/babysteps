---
categories:
- Rust
comments: true
date: "2015-01-14T14:03:45Z"
slug: little-orphan-impls
title: Little Orphan Impls
---

We've recently been doing a lot of work on Rust's *orphan rules*,
which are an important part of our system for guaranteeing *trait
coherence*. The idea of trait coherence is that, given a trait and
some set of types for its type parameters, there should be exactly one
impl that applies. So if we think of the trait `Show`, we want to
guarantee that if we have a trait reference like `MyType : Show`, we
can uniquely identify a particular impl. (The alternative to coherence
is to have some way for users to identify which impls are in scope at
any time.  It has [its own complications][hp]; if you're curious for
more background on why we use coherence, you might find this
[rust-dev thread][thread] from a while back to be interesting
reading.)

The role of the *orphan rules* in particular is basically to prevent
you from implementing *external traits for external types*. So
continuing our simple example of `Show`, if you are defining your own
library, you could not implement `Show` for `Vec<T>`, because both
`Show` and `Vec` are defined in the standard library. But you *can*
implement `Show` for `MyType`, because you defined `MyType`. However,
if you define your own trait `MyTrait`, then you can implement
`MyTrait` for any type you like, including external types like
`Vec<T>`. To this end, the orphan rule intuitively says "either the
trait must be local or the self-type must be local".

More precisely, the orphan rules are targeting the case of two
"cousin" crates. By cousins I mean that the crates share a common
ancestor (i.e., they link to a common library crate). This would be
libstd, if nothing else. That ancestor defines some trait. Both of the
crates are implementing this common trait using their own local types
(and possibly types from ancestor crates, which may or may not be in
common). But neither crate is an ancestor of the other: if they were,
the problem is much easier, because the descendant crate can see the
impls from the ancestor crate.

When we extended the trait system to [support][md1]
[multidispatch][md2], I confess that I originally didn't give the
orphan rules much thought. It seemed like it would be straightforward
to adapt them. Boy was I wrong! (And, I think, our original rules were
kind of unsound to begin with.)

The purpose of this post is to lay out the current state of my
thinking on these rules. It sketches out a number of variations and
possible rules and tries to elaborate on the limitations of each
one. It is intended to serve as the seed for a discussion in the
[Rust discusstion forums][d].

<!--more-->

### The first, totally wrong, attempt

The first attempt at the orphan rules was just to say that an impl is
legal if a local type appears somewhere. So, for example, suppose that I
define a type `MyBigInt` and I want to make it addable to integers:

```rust
impl Add<i32> for MyBigInt { ... }
impl Add<MyBigInt> for i32 { ... }
```

Under these rules, these two impls are perfectly legal, because
`MyBigInt` is local to the current crate. However, the rules also
permit an impl like this one:

```rust
impl<T> Add<T> for MyBigInt { ... }
```

Now the problems arise because those same rules *also* permit an impl
like this one (in another crate):

```rust
impl<T> Add<YourBigInt> for T { ... }
```

Now we have a problem because both impls are applicable to
`Add<YourBigInt> for MyBigInt`.

In fact, we don't need multidispatch to have this problem. The same
situation can arise with `Show` and tuples:

```rust
impl<T> Show for (T, MyBigInt) { ... } // Crate A
impl<T> Show for (YourBigInt, T) { ... } // Crate B
```

(In fact, multidispatch is really nothing than a compiler-supported
version of implementing a trait for a tuple.)

The root of the problem here lies in our definition of "local", which
completely ignored type parameters. Because type parameters can be
instantiated to arbitrary types, they are obviously special, and must
be considered carefully.

### The ordered rule

This problem was first brought to our attention by [arielb1][ab1], who
filed [Issue 19470][19470]. To resolve it, he proposed a rule that I
will call the *ordered rule*. The ordered rule goes like this:

1. Write out all the type parameters to the trait, starting with `Self`.
2. The name of some local struct or enum must appear on that line before the first
   type parameter.
   - *More formally:* When visiting the types in pre-order, a local type must be visited
     before any type parameter.

In terms of the examples I gave above, this rule permits the following impls:

```rust
impl Add<i32> for MyBigInt { ... }
impl Add<MyBigInt> for i32 { ... }
impl<T> Add<T> for MyBigInt { ... }
```

However, it avoids the quandry we saw before because it rejects this impl:

```rust
impl<T> Add<YourBigInt> for T { ... }
```

This is because, if we wrote out the type parameters in a list, we would get:

```rust
T, YourBigInt
```

and, as you can see, `T` comes first.

This rule is actually pretty good. It meets most of the requirements
I'm going to unearth.  But it has some problems. The first is that it
feels strange; it feels like you should be able to reorder the type
parameters on a trait without breaking everything (we will see that
this is not, in fact, obviously true, but it was certainly my first
reaction).

Another problem is that the rule is kind of fragile. It can easily
reject impls that don't seem particularly different from impls that it
accepts. For example, consider the case of the [`Modifier` trait][rm]
that is used in hyper and iron. As you can see in [this issue][20974],
iron wants to be able to define a `Modifier` impl like the following:

```rust
struct Response;
...
impl Modifier<Response> for Vec<u8> { .. }
```

This impl is accepted by the ordered rule (thre are no type parameters at all,
in fact). However, the following impl, which seems very similar and equally
likely (in the abstract), would *not* be accepted:

```rust
struct Response;
...
impl<T> Modifier<Response> for Vec<T> { .. }
```

This is because the type parameter `T` appears before the local type
(`Response`). Hmm. It doesn't really matter if `T` appears in the local type,
either; the following would also be rejected:

```rust
struct MyHeader<T> { .. }
...
impl<T> Modifier<MyHeader<T>> for Vec<T> { .. }
```

Another trait that couldn't be handled properly is the `BorrowFrom` trait
in the standard library. There a number of impls like this one:

```rust
impl<T> BorrowFrom<Rc<T>> for T
```

This impl fails the ordered check because `T` comes first. We can make
it pass by switching the order of the parameters, so that the
`BorrowFrom` trait becomes `Borrow`.

A final "near-miss" occurred in the standard library with the `Cow`
type.  Here is an impl from `libcollections` of `FromIterator` for a
copy-on-write vector:

```rust
impl<'a, T> FromIterator<T> for Cow<'a, Vec<T>, [T]>
```

Note that `Vec` is a local type here. This impl obeys the ordered
rule, but somewhat by accident. If the type parameters of the `Cow`
trait were in a different order, it would not, because then `[T]`
would precede `Vec<T>`.

### The covered rule

In response to these shortcomings, I proposed an alternative rule that
I'll call the *covered* rule. The idea of the covered rule was to say
that (1) the impl must have a local type somewhere and (2) a type
parameter can only appear in the impl if the type parameter is
*covered* by a local type. Covered means that it appears "inside" the
type: so `T` is covered by `MyVec` in the type `MyVec<T>` or
`MyBox<Box<T>>`, but not in `(T, MyVec<int>)`. This rule has the
advantage of having nothing to do with ordering and it has a certain
intution to it; any type parameters that appear in your impls have to
be tied to something local.

This rule
[turns out to give us the required orphan rule guarantees][proof]. To
see why, consider this example:

```rust
impl<T> Foo<T> for A<T> // Crate A
impl<U> Foo<B<U>> for U // Crate B
```

If you tried to make these two impls apply to the same type, you wind
up with infinite types. After all, `T = B<U>`, but `U=A<T>`, and hence
you get `T = B<A<T>>`.

Unlike the previous rule, this rule happily accepts the `BorrowFrom`
trait impls:

```rust
impl<T> BorrowFrom<Rc<T>> for T
```

The reason is that the type parameter `T` here is covered by the
(local) type `Rc`.

However, after implementing this rule, we found out that it actually
prohibits a lot of other useful patterns. The most important of them is
the so-called *auxiliary* pattern, in which a trait takes a type parameter
that is a kind of "configuration" and is basically orthogonal to the types
that the trait is implemented for. An example is the `Hash` trait:

```rust
impl<H> Hash<H> for MyStruct
```

The type `H` here represents the hashing function that is being used. As you can imagine,
for most types, they will work with *any* hashing function. Sadly, this impl is rejected,
because `H` is not covered by any local type. You could make it work by adding a parameter
`H` to `MyStruct`:

```rust
impl<H> Hash<H> for MyStruct<H>
```

But that is very weird, because now when we create our struct we are
also deciding which hash functions can be used with it. You can also
make it work by moving the hash function parameter `H` to the `hash`
method itself, but then *that* is limiting.  It makes the `Hash` trait
not object safe, for one thing, and it also prohibits us from writing
types that *are* specialized to particular hash functions.

Another similar example is indexing. Many people want to make types indexable
by any integer-like thing, for example:

```rust
impl<I:Int, T> Index<I> for Vec<T> {
    type Output = T;
}
```

Here the type parameter `I` is also uncovered.

### Ordered vs Covered

By now I've probably lost you in the ins and outs, so let's see a
summary.  Here's a table of all the examples I've covered so far. I've
tweaked the names so that, in all cases, any type that begins with
`My` is considered local to the current crate:

```
+----------------------------------------------------------+---+---+
| Impl Header                                              | O | C |
+----------------------------------------------------------+---+---+
| impl Add<i32> for MyBigInt                               | X | X |
| impl Add<MyBigInt> for i32                               | X | X |
| impl<T> Add<T> for MyBigInt                              | X |   |
| impl<U> Add<MyBigInt> for U                              |   |   |
| impl<T> Modifier<MyType> for Vec<u8>                     | X | X |
| impl<T> Modifier<MyType> for Vec<T>                      |   |   |
| impl<'a, T> FromIterator<T> for Cow<'a, MyVec<T>, [T]>   | X | X |
| impl<'a, T> FromIterator<T> for Cow<'a, [T], MyVec<T>>   |   | X |
| impl<T> BorrowFrom<Rc<T>> for T                          |   | X |
| impl<T> Borrow<T> for Rc<T>                              | X | X |
| impl<H> Hash<H> for MyStruct                             | X |   |
| impl<I:Int,T> Index<I> for MyVec<T>                      | X |   |
+----------------------------------------------------------+---+---+
```

As you can see, both of these have their advantages. However, the
ordered rule comes out somewhat ahead. In particular, the places where
it fails can often be worked around by reordering parameters, but
there is *no* answer that permits the covered rule to handle the
`Hash` example (and there are a number of other traits that fit that
pattern in the standard library).

### Hybrid approach #1: Covered self

You might be wondering -- if neither rule is perfect, is there a way
to combine them? In fact, the rule that is current implemented is such
a hybrid.  It imposes the covered rules, but only on the `Self`
parameter. That means that there must be a local type somewhere in
`Self`, and any type parameters appearing in `Self` must be covered by
a local type. Let's call this hybrid `CS`, for "covered apply to
`Self`".

```
+----------------------------------------------------------+---+---+---+
| Impl Header                                              | O | C | S |
+----------------------------------------------------------+---+---+---|
| impl Add<i32> for MyBigInt                               | X | X | X |
| impl Add<MyBigInt> for i32                               | X | X |   |
| impl<T> Add<T> for MyBigInt                              | X |   | X |
| impl<U> Add<MyBigInt> for U                              |   |   |   |
| impl<T> Modifier<MyType> for Vec<u8>                     | X | X |   |
| impl<T> Modifier<MyType> for Vec<T>                      |   |   |   |
| impl<'a, T> FromIterator<T> for Cow<'a, MyVec<T>, [T]>   | X | X | X |
| impl<'a, T> FromIterator<T> for Cow<'a, [T], MyVec<T>>   |   | X | X |
| impl<T> BorrowFrom<Rc<T>> for T                          |   | X |   |
| impl<T> Borrow<T> for Rc<T>                              | X | X | X |
| impl<H> Hash<H> for MyStruct                             | X |   | X |
| impl<I:Int,T> Index<I> for MyVec<T>                      | X |   | X |
+----------------------------------------------------------+---+---+---+
O - Ordered / C - Covered / S - Covered Self
```

As you can see, the CS hybrid turns out to miss some important cases that the
pure ordered full achieves. Notably, it prohibits:

- `impl Add<MyBigInt> for i32`
- `impl Modifier<MyType> for Vec<u8>`

This is not really good enough.

### Hybrid approach #2: Covered First

We can improve the covered self approach by saying that some type
parameter of the trait must meet the rules (some local type; impl type
params covered by a local type), but not necessarily `Self`. Any type parameters
which precede this covered parameter must consist exclusively of remote types (no impl
type parameters, in particular).

```
+----------------------------------------------------------+---+---+---+---+
| Impl Header                                              | O | C | S | F |
+----------------------------------------------------------+---+---+---|---|
| impl Add<i32> for MyBigInt                               | X | X | X | X |
| impl Add<MyBigInt> for i32                               | X | X |   | X |
| impl<T> Add<T> for MyBigInt                              | X |   | X | X |
| impl<U> Add<MyBigInt> for U                              |   |   |   |   |
| impl<T> Modifier<MyType> for Vec<u8>                     | X | X |   | X |
| impl<T> Modifier<MyType> for Vec<T>                      |   |   |   |   |
| impl<'a, T> FromIterator<T> for Cow<'a, MyVec<T>, [T]>   | X | X | X | X |
| impl<'a, T> FromIterator<T> for Cow<'a, [T], MyVec<T>>   |   | X | X | X |
| impl<T> BorrowFrom<Rc<T>> for T                          |   | X |   |   |
| impl<T> Borrow<T> for Rc<T>                              | X | X | X | X |
| impl<H> Hash<H> for MyStruct                             | X |   | X | X |
| impl<I:Int,T> Index<I> for MyVec<T>                      | X |   | X | X |
+----------------------------------------------------------+---+---+---+---+
O - Ordered / C - Covered / S - Covered Self / F - Covered First
```

As you can see, this is a strict improvement over the other
appraoches. The only thing it can't handle that the other rules can is
the `BorrowFrom` rule.

### An alternative approach: distinguishing "self-like" vs "auxiliary" parameters

One disappointment about the hybrid rules I presented thus far is that
they are inherently ordered. It runs somewhat against my intuition,
which is that the order of the trait type parameters shouldn't matter
that much. In particular it feels that, for a commutative trait like
`Add`, the role of the left-hand-side type (`Self`) and
right-hand-side type should be interchangable (below, I will argue
that in fact some kind of order may well be essential to the notion of
coherence as a whole, but for now let's assume we want `Add` to treat
the left- and right-hand-side as equivalent).

However, there are definitely other traits where the parameters are
not equivalent. Consider the `Hash` trait example we saw before. In
the case of `Hash`, the type parameter `H` refers to the hashing
algorithm and thus is inherently *not* going to be covered by the type
of the value being hashed. It is in some sense completely orthogonal
to the `Self` type. For this reason, we'd like to define impls that
apply to any hasher, like this one:

```rust
impl<H> Hash<H> for MyType { ... }
```

The problem is, if we permit this impl, then we can't allow another
crate to define an impl with the same parameters, but in a different
order:

```rust
impl<H> Hash<MyType> for H { ... }
```

One way to permit the first impl and not the second without invoking
ordering is to classify type parameters as *self-like* and *auxiliary*.

The orphan rule would require that at least one self-like parameter
references a local type and that all impl type parameters appearing in
self-like types would be covered. The `Self` type is always self-like,
but other types would be auxiliary unless declared to be self-like (or
perhaps the default would be the opposite).

Here is a table showing how this new "explicit" rule would work,
presuming that the type parameters on `Add` and `Modifier` were
declared as self-like. The `Hash` and `Index` parameters would be
declared as auxiliary.

```
+----------------------------------------------------------+---+---+---+---+---+
| Impl Header                                              | O | C | S | F | E |
+----------------------------------------------------------+---+---+---|---|---+
| impl Add<i32> for MyBigInt                               | X | X | X | X | X |
| impl Add<MyBigInt> for i32                               | X | X |   | X | X |
| impl<T> Add<T> for MyBigInt                              | X |   | X | X |   |
| impl<U> Add<MyBigInt> for U                              |   |   |   |   |   |
| impl<T> Modifier<MyType> for Vec<u8>                     | X | X |   | X | X |
| impl<T> Modifier<MyType> for Vec<T>                      |   |   |   |   |   |
| impl<'a, T> FromIterator<T> for Cow<'a, MyVec<T>, [T]>   | X | X | X | X | X |
| impl<'a, T> FromIterator<T> for Cow<'a, [T], MyVec<T>>   |   | X | X | X | X |
| impl<T> BorrowFrom<Rc<T>> for T                          |   | X |   |   | X |
| impl<T> Borrow<T> for Rc<T>                              | X | X | X | X | X |
| impl<H> Hash<H> for MyStruct                             | X |   | X | X | X |
| impl<I:Int,T> Index<I> for MyVec<T>                      | X |   | X | X | X |
+----------------------------------------------------------+---+---+---+---+---+
O - Ordered / C - Covered / S - Covered Self / F - Covered First
E - Explicit Declarations
```

You can see that it's quite expressive, though it is very restrictive
about generic impls for `Add`. However, it would push quite a bit of
complexity onto the users, because now when you create a trait, you
must classify its type parameter as self.

### In defense of ordering

Whereas at first I felt that having the rules take ordering into
account was unnatural, I have come to feel that ordering is, to some
extent, inherent in coherence. To see what I mean, let's consider an
example of a new vector type, `MyVec<T>`. It might be reasonable to
permit `MyVec<T>` to be addable to anything can converted into an
iterator over `T` elements.  Naturally, since we're overloading `+`,
we'd prefer for it to be commutative:

```rust
impl<T,I> Add<I> for MyVec<T> where I : IntoIterator<Output=T> {
    type Output = MyVec<T>;
    ...
}   
impl<T,I> Add<MyVec<T>> for I where I : IntoIterator<Output=T> {
    type Output = MyVec<T>;
    ...
}   
```

Now, given that `MyVec<T>` is a vector, it should be iterable as well:

```rust
impl<T> IntoIterator for MyVec<T> {
    type Output = T;
    ...
}
```

The problem is that these three impls are inherently
overlapping. After all, if I try to add two `MyVec` instances, which
impl do I get?

Now, this isn't a problem for any of the rules I proposed in this
thread, because all of them reject that pair of impls. In fact, both
the "Covered" and "Explicit Declarations" rules go farther: they
reject *both impls*. This is because the type parameter `I` is
uncovered; since the rules don't consider ordering, they can't allow
an uncovered iterator `I` on either the left- or the right-hand-side.

The other variations ("Ordered", "Covered Self", and "Covered First"),
on the other hand, allow only one of those impls: the one where
`MyVec<T>` appears on the left. This seems pretty reasonable. After
all, if we allow you to define an overloaded `+` that applies to an
open-ended set of types (those that are iterable), there is the
possibility that others will do the same. And if I try to add a
`MyVec<int>` and a `YourVec<int>`, both of which are iterable, who
wins? The ordered rules give a clear answer: the left-hand-side wins.

There are other blanket cases that also get prohibited which might on their
face seem to be reasonable. For example, if I have a `BigInt` type, the ordered
rules allow me to write impls that permit `BigInt` to be added to any concrete
int type, no matter which side that concrete type appears on:

```rust
impl Add<BigInt> for i8 { type Output = BigInt; ... } 
impl Add<i8> for BigInt { type Output = BigInt; ... }
...
impl Add<BigInt> for i64 { type Output = BigInt; ... } 
impl Add<i64> for BigInt { type Output = BigInt; ... }
```

It might be nice, if I could just write the following two impls:

```rust
impl<R:Int> Add<BigInt> for R { type Output = BigInt; ... } 
impl<L:Int> Add<L> for BigInt { type Output = BigInt; ... }
```

Now, this makes some measure of sense because `Int` is a trait that is
only intended to be implemented for the primitive integers. In
principle all bigints could use these same rules without conflict, so
long as none of them implement `Int`. But in fact, nothing prevents
them from implementing `Int`.  Moreover, it's not hard to imagine
other crates creating comparable impls that would overlap with the
ones above:

```rust
struct PrintedInt(i32);
impl Int for PrintedInt;
impl<R:Show> Add<PrintedInt> for R { type Output = BigInt; ... } 
impl<L:Show> Add<L> for PrintedInt { type Output = BigInt; ... }
```

Assuming that `BigInt` implements `Show`, we now have a problem!

In the future, it may be interesting to provide a way to use traits to
create "strata" so that we can say things like "it's ok to use an
`Int`-bounded type parameter on the LHS so long as the RHS is bounded
by `Foo`, which is incompatible with `Int`", but it's a subtle and
tricky issue (as the `Show` example demonstrates).

So ordering basically means that when you define your traits, you
should put the "principal" type as `Self`, and then order the other
type parameters such that those which define the more "principal"
behavior come afterwards in order.

### The problem with ordering

Currently I lean towards the "Covered First" rule, but it bothers me
that it allows something like

```rust
impl Modifier<MyType> for Vec<u8>
```

but not

```rust
impl<T> Modifier<MyType> for Vec<T>
```

However, this limitation seems to be pretty inherent to any rules that
do not explicitly identify "auxiliary" type parameters. The reason is
that the ordering variations all use the first occurrence of a local
type as a "signal" that auxiliary type parameters should be permitted
afterwards. This implies that another crate will be able to do
something like:

```rust
impl<U> Modifier<U> for Vec<YourType>
```

In that case, both impls apply to `Modifier<MyType> for Vec<YourType>`.

### Conclusion

This is a long post, and it covers a lot of ground. As I wrote in the
introduction, the orphan rules turn out to be hiding quite a lot of
complexity. Much more than I imagined at first. My goal here is mostly
to lay out all the things that aturon and I have been talking about in
a comprehensive way.

I feel like this all comes down to a key question: how do we identify
the "auxiliary" input type parameters? Ordering-based rules identify
this for each impl based on where the first "local" type
appears. Coverage-based rules seem to require some sort of explicit
declaration on the trait.

I am deeply concerned about asking people to understand this
"auxiliary" vs "self-like" distinction when declaring a trait. On the
other hand, there is no silver bullet: under ordering-based rules,
they will be required to sometimes reorder their type parameters just
to pacify the seemingly random ordering rule. (But I have the feeling
that people intuitively put the most "primary" type first, as `Self`,
and the auxiliary type parameters later.)

[rm]: https://github.com/reem/rust-modifier
[reem]: https://github.com/reem
[19470]: https://github.com/rust-lang/rust/issues/19470
[20974]: https://github.com/rust-lang/rust/issues/20974
[ab1]: https://github.com/arielb1
[md1]: http://smallcultfollowing.com/babysteps/blog/2014/09/30/multi-and-conditional-dispatch-in-traits/
[md2]: https://github.com/rust-lang/rfcs/blob/master/text/0195-associated-items.md
[d]: http://discuss.rust-lang.org/t/orphan-rules/1322
[hp]: https://mail.mozilla.org/pipermail/rust-dev/2011-December/001036.html
[thread]: https://mail.mozilla.org/pipermail/rust-dev/2011-December/thread.html#1036
[proof]: https://github.com/rust-lang/rust/issues/19470#issuecomment-66846120
