---
layout: post
title: 'Associated type constructors, part 2: family traits'
categories: [Rust, ATC, HKT, Traits]
---

Hello. This post is a continuation of my posts discussing the topic of
associated type constructors (ATC) and higher-kinded types (HKT):

1. [The first post][post-a] focused on introducing the basic idea of
   ATC, as well as introducing some background material.
2. This post talks about some apparent limitations of associated type
   constructors, and shows how we can overcome them by making use of a
   design pattern that I call "family traits". Along the way, we
   introduce the term **higher-kinded type** for the first time, and
   show (informally) that family traits are equally general.
   
[post-a]: {{ site.baseurl }}/blog/2016/11/02/associated-type-constructors-part-1-basic-concepts-and-introduction/

<!-- more -->

### The limits of associated type constructors

OK, so in the last post we saw how we can use ATC to define a
`Collection` trait, and how to implement that trait for our sample
collection `List<T>`.  In particular, ATC let us express the return
type of the `iterator()` method as `Self::Iter<'iter>`, so that we can
incorporate the lifetime `'iter` of each particular iterator.

What I'd like to do now is to go one step further -- what if I wanted
to write a function that converts a collection of integers into a
collection of floats. Something like this:

```rust
fn floatify<I, F>(ints: &I) -> F
    where I: Collection<i32>, F: Collection<f32>
{
    let mut floats = F::empty();
    for &f in c.iterate() {
        floats.add(f as f32);
    }
    floats
}
```

This code would work just fine, but it has some interesting properties
that we may not have expected. In particular, `floatify()` can convert
any collection of integers into *any* collection of floats, but those
collections can be of **totally different types**. For example, I
could convert from a `List<i32>` to a `Vec<f32>` like so:

```rust
fn foo(x: &List<i32>) -> f32 {
    let y: Vec<f32> = floatify(x);
    //     ^^^^^^^^ notice the type annotation
    y.iterate().sum()
}
```

This is more flexible, which is good, but also has some downsides.
For example, that same flexibility can make type inference harder. To
see what I mean, imagine that I wanted to remove the `Vec<f32>` type
annotation from the variable `y`, like so:

```rust
fn foo(x: &List<i32>) -> f32 {
    let y = floatify(x);
    //  ^ error: type not constrained!
    y.iterate().sum()
}
```

This would not compile, because we don't have enough information to
figure out the type of `y`! In particular, we know that `y` is a
"collection of `f32` values", but we don't know what *kind* of
collection. It is a `Vec<f32>` or `List<f32>`? Obviously it makes a
difference to the semantics of our code, since vectors add items onto
the end, and lists add things onto the beginning, so the order of
iterator is going to be different (and, since these are floats and
hence `+` is not actually commutative, that implies the `sum` may well
be different). So the compiler doesn't want to just *guess*.

So maybe we'd like to say that `floatify` takes and returns a
collection of the same type. It turns out we can't do that with just
the `Collection` trait we've seen so far. Essentially, the signature
that we would *want* is maybe something like this (ignoring the where
clauses for now):

```rust
fn floatify_hkt<I>(ints: &I<i32>) -> I<f32>
//                        ^^^^^^ wait up, what is `I` here?
```

But woah, what is this `I` thing here? It's not a type parameter in
the normal sense, since it doesn't represent a type like `Vec<i32>` or
`List<i32>`. Instead it represents a kind of "partial type", like
`Vec` or `List`, where the the element type is not yet specified. Or,
as type theorists like to call it, a "higher-kinded type" (HKT). I'll
get into why it's called that, and more about how such a thing might
work, in the next post. For this post, I want to focus on an
alternative solution, one that doesn't require HKT at all.

### Introducing type families

So let's assume that type parameters still just represent plain old
types -- in that case, is it possible to write a version of
`floatify()` that returns a collection of the same "sort" as its
input?

It turns out you can do it, but you need an extra trait. We already
saw the `Collection` trait before; we'd want to add a second trait,
let's call it `CollectionFamily`, that lets us go from a "collection
family" (e.g., `Vec`) to a specific collection (e.g., `Vec<T>`):

```rust
trait CollectionFamily {
    type Member<T>: Collection<T>;
}
```

A "collection family" corresponds to a 'family' of collections, like 
`Vec` or `List`. We're also going to need then some dummy types to use for implementing
this trait:

```rust
struct VecFamily;

impl CollectionFamily for VecFamily {
    type Member<T> = Vec<T>;
}

struct ListFamily;

impl CollectionFamily for ListFamily {
    type Member<T> = List<T>;
}
```

*Note:* While writing this post I realized that Haskell also has a
feature called "associated type families". Those are certainly related
to the things I am talking about here, but I am not trying to model
that Haskell feature, and my use of the term "family" is independent.

### Families and inference

OK, so now we have the idea of a "collection family". You might think
then that we can now rewrite `floatify` like so:

```rust
fn floatify_family<F>(ints: &F::Collection<i32>) -> F::Collection<f32>
    where F: CollectionFamily
{
    let mut floats = F::Coll::empty();
    for &f in c.iterate() {
        floats.add(f as f32);
    }
    floats
}
```

Whereas before the type parameters represented specific collection
types, now we take a type parameter `F` that represents an entire
*family* of collection types. Then we can can use `F::Collection<i32>` to
name "the collection in the family `F` whose item type is `i32`".

This type signature for `floatify_family()` works, but let's see what
happens now for our caller:

```rust
fn foo(x: &List<i32>) -> f32 {
    let y = floatify_family::<ListFamily>(x);
    //                        ^^^^^^^^^^ wait, what?
    y.iterate().sum()
}
```

It turns out that there is good and bad news. The good news is that,
once we know the family, we can indeed infer the type of `y`. The bad
news is that, at least with the setup we have so far, we can't
actually infer the type of the family! That is, the
`floatify_family::<ListFamily>` annotation turns out to be required!
To see why, let's look again at the signature of `floatify_family()`

```rust
fn floatify_family<F>(ints: &F::Collection<i32>) -> F::Collection<f32>
    where F: CollectionFamily
```

As before, to infer the type of `F`, we going to replace `F` with an
inference variable `?F`, and then do some unification. So we can see
that the type of the `ints` argument will be something like this (here
I am using the fully qualified notation to make everything explicit):

    <?F as CollectionFamily>::Collection<i32>
    
We have to unify this with `List<i32>`. But this presents a bit of a
problem! Knowing the *value* of an associated type (`?F::Collection<i32>`)
doesn't really let us figure out what impl that associated type came
from (i.e., what `?F` is). After all, there could be other impls that
specify the same `Coll`.

### Linking collections and families

To make inference work, then, we really need a "backlink" from
`Collection` to `CollectionFamily`. This lets us go from a specific
collection type to its family:

```rust
trait Collection<T> {
    // Backlink to `Family`.
    type Family: CollectionFamily;
    
    // as before:
    fn empty() -> Self;
    fn add(&mut self, value: Item);
    fn iterate(&self) -> Self::Iter;
    type Iter: Iterator<Item=Item>;
}

trait CollectionFamily {
    type Member<T>: Collection<T, Family = Self>;
}
```

Now we could rewrite `floatify_family` like so:

```rust
fn floatify_family<C>(ints: &C) -> C::Family::Member<f32>
    where C: Collection<i32> //    ^^^^^^^^^^^^^^^^^ another collection, in same family
{
    ...
}    
```

This change will mean that we can write the call without any type
annotations:

```rust
fn foo(x: &List<i32>) -> f32 {
    let y = floatify_family(x);
    //      ^^^^^^^^^^^^^^^ look ma, no annotations
    y.iterate().sum()
}
```

What will happen is that, at the call site, the inferencer will create
two type variables, `?C` and `?F`. From the argument types, we can
deduce that `?C = List<i32>`. Next, solving the constraint `?C:
Collection<i32, Family=?F>` will allow us to deduce that `?F =
ListFamily`. And hence we are all set.

### Side-note: extending higher-ranked trait bounds

There's one part of [RFC 1598][] that I haven't covered so far. I just
want to mention it in passing; it'll become a bit more prominent in
later articles in this series. The RFC includes a generalization of
Rust's *higher-ranked trait bounds* to support generalization over
types. This actually occurs quite implicitly and naturally. To see
what I mean, consider the `CollectionFamily` trait:

```rust
trait CollectionFamily {
    type Member<T>: Collection<T>;
    //              ^^^^^^^^^^^^^ what does this bound apply to?
}
```

In particular, consider the bound `Collection<T>` -- this bound
applies to the type `Self::Member<T>`, but what is `T` here? The answer
is that `T` is a stand-in for "any type" (or, almost).

Currently, we have a notation for writing trait bounds that apply to
*any* lifetime. For example, `for<'a> T: Foo<'a>` means "for any
lifetime `'a`, `T` implements `Foo<'a>`"; you could also write `T:
for<'a> Foo<'a>`, which is equivalent. This `'a` lifetime can also
appear as part of the type, so one might write `for<'a> &'a T:
Foo<'a>` (in this case, you can't move the `for<'a>` around, since it
brings the `'a` into scope).

(There are actually lots of interesting implementation questions
raised by HRTB, some of which we haven't fully worked through. I've
got another series of blog posts on those, but I'm going to leave that
aside for now.)

Anyway, this `for<>` notation is just what we need to handle our `Member<T>`
type, except that we need it to apply to types. Basically we want a
bound like this:

```rust
for<T> Self::Member<T>: Collection<T>
```

Meaning in English, "for any type `T`, `Self::Member<T>` implements the
trait `Collection<T>`". Or, more naturally, "`Member<T>` is always a collection,
no matter what `T` is".

(This is a simplification. Really, `T` must meet *some* requirements
-- for example, it likely must be `Sized`. This is precisely the stuff
I want to get into in a later post, since our current implementation
doesn't handle these kinds of requirements as gracefully as it
should/could.)

### Families vs HKT

It should be clear that the "collection families" I introduced in the
last section basically correspond to higher-kinded types, but made
more explicit. This shows that associated type constructors are indeed
a quite general tool. I am pretty sure that one can convert any
program using HKT to use associated type constructors, but of course
one must follow this family pattern.

One could view this as a problem: one could also view it a plus.
After all, associated type constructors are a tiny delta on the
language we have today, and yet we gain the full power of
HKT. Basically, teaching ATC isn't much harder than teaching Rust
today, and then we can just add the "design pattern" of families on
top -- this may well be less intimidating than teaching "HKT" itself.
Maybe.

One nice part about avoiding "true HKT" is that we get to sidestep
some of the thorny questions that it raises. In particular, the
challenges that full HKT poses for inference. We'll come back to
those: it turns out that they are highly related to the problems we
had in families that prompted us to add a `Family` member to
`Collection`.

One big question, I think, is how often we would want to define these
sorts of "family" traits, and how it would *really* feel to use them
"at scale". I can think of several places that families might make
sense. Let me just give a few examples of possible families.

#### Parameterizing over smart pointers and thread safety

One thing I think people want to do from time to time is to
parameterize over `Rc` vs `Arc`. You might imagine having a
family like this for choosing between them:

```rust
trait RefCountedFamily {
    type Ptr<T>: RefCounted<T, Family = Self>;
    
    fn new<T>(value: T) -> Self::Ptr<T>;
}

trait RefCounted<T>: Deref<Target=T> + Clone {
    type Family: RefCountedFamily;
}
```

An example that could benefit from this is persistent collections like
[mw's hamt-rs](https://github.com/michaelwoerister/hamt-rs) library,
which currently encodes `Arc`.

More generally, you might want to be able to map between patterns
types like `Rc<Cell<usize>>` or `Rc<RefCell<T>>` vs `Arc<AtomicUsize>`
or `Arc<Rwlock<T>>`; these are mostly equivalent, except that the
latter is thread-safe but more expensive.

#### Parameterizing over mutability

Another common thing is the need to be parameterized over `&'a T` vs
`&'a mut T`. Interestingly, I don't think that associated type
constructors (*or* HKT) really gives us that! The problem is that
borrow expressions operate on *paths*, and we have no way to reify
that distinction right now. Basically you can't make methods that
model the `&` operator; interestingly, this problem is also a
limitation for modeling garbage collection in Rust. I'll try to get
into this in one of the later posts in the series, but it's an
interesting shortcoming I hadn't realized till trying to write out
this post.

### Conclusions

OK, in this post we covered a design pattern I call "family traits",
that uses ATC to model HKT:

- Our original `Collection` trait let you iterate over existing collections,
  but it didn't let you convert between types of collections;
  - in other words, if I have a type like `C: Collection<i32>`,
    I couldn't get a type `D` where `D: Collection<u32>` that is guaranteed
    to be the same "sort" of collection.
- "Higher-kinded types" are basically a way to make this notion more
  formal, and refer to an "unapplied generic" like `Vec` or `List`.
- We can model this relationship with ATC by defining a type like `VecFamily` or
  `ListFamily` that is also unapplied, and then definiting a trait `CollectionFamily`.
  - For type inference reasons, we also need to be able to go from a
    specific `Collection` type like `C` to its family (`C::Family`).

The next post will dig deeper into what higher-kinded types might look
like in Rust, and in particular we want to see if there's a way to
make them "play nice" with the `Collection<T>` trait we've been
looking at.

### Comments

Please leave comments on
[this internals thread](https://internals.rust-lang.org/t/blog-post-series-alternative-type-constructors-and-hkt/4300).


[RFC 1598]: https://github.com/rust-lang/rfcs/pull/1598
