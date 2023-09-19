---
layout: post
title: 'Associated type constructors, part 4: Unifying ATC and HKT'
categories: [Rust, ATC, HKT, Traits]
---

This post is a continuation of my posts discussing the topic of
associated type constructors (ATC) and higher-kinded types (HKT):

1. [The first post][post-a] focused on introducing the basic idea of
   ATC, as well as introducing some background material.
2. [The second post][post-b] showed how we can use ATC to model HKT,
   via the "family" pattern.
3. [The third post][post-c] did some exploration into what it would
   mean to support HKT directly in the language, instead of modeling
   them via the family pattern.
4. This post considers what it might mean if we had both ATC *and* HKT
   in the language: in particular, whether those two concepts can be
   unified, and at what cost.
   
<!-- more -->

### Unifying HKT and ATC

So far we have seen "associated-type constructors" and "higher-kinded
types" as two distinct concepts. The question is, would it make sense
to try and *unify* these two, and what would that even mean?

Consider this trait definition:

```rust
trait Iterable {
    type Iter<'a>: Iterator<Item=Self::Item>;
    type Item;
    
    fn iter<'a>(&'a self) -> Self::Iter<'a>;
}
```

In the ATC world-view, this trait definition would mean that you can
now specify a type like the following

```
<T as Iterable>::Iter<'a>
```

Depending on what the type `T` and lifetime `'a` are, this might get
"normalized". Normalization basically means to expand an associated
type reference using the types given in the appropriate impl. For
example, we might have an impl like the following:

```rust
impl<A> Iterable for Vec<A> {
    type Item = A;
    type Iter<'a> = std::vec::Iter<'a, A>;

    fn iter<'a>(&'a self) -> Self::Iter<'a> {
        self.clone()
    }
}
```

In that case, `<Vec<Foo> as Iterable>::Iter<'x>` could be *normalized*
to `std::vec::Iter<'x, Foo>`. This is basically exactly the same way
that associated type normalization works now, except that we have
additional type/lifetime parameters that are placed on the associated
item itself, rather than having all the parameters come from the trait
reference.

#### Associated type constructors as functions

Another way to view an ATC is as a kind of function, where the
normalization process plays the role of evaluating the function when
applied to various arguments. In that light, `<Vec<Foo> as
Iterable>::Iter` could be viewed as a "type function" with a signature
like `lifetime -> type`; that is, a function which, given a type and a
lifetime, produces a type:

```
<Vec<Foo> as Iterable>::Iter<'x>
^^^^^^^^^^^^^^^^^^^^^^^^^^^^ ^^
function                     argument
```

When I write it this way, it's natural to ask how such a function is
related to a *higher-kinded type*. After all, `lifetime -> type` could
also be a *kind*, right? So perhaps we should think of `<Vec<Foo> as
Iterable>::Iter` as a type of kind `lifetime -> type`? What would that mean?

### Limitations on what can be used in an ATC declaration

Well, in the last post, we saw that, in order to ensure that inference
is tractable, HKT in Haskell comes with pretty strict limitations on
the kinds of "type functions" we can support. Whatever we chose to
adopt in Rust, it would imply that we need similar limitations on ATC
values that can be treated as higher-kinded.

That wouldn't affect the impl of `Iterable` for `Vec<A>` that we saw
earlier. But imagine that we wanted `Range<i32>`, which is the type
produced by `0..22`, to act as an `Iterable`. Now, ranges like `0..22`
are *already* iterable -- so the type of an iterator could just be
`Self`, and `iter()` can effectively just be `clone()`. So you might
think you could just write:

```rust
impl<u32> Iterable for Range<u32>
    type Item = u32;
    type Iter<'a> = Range<u32>;
    //              ^^^^ doesn't use `'a'` at all
    
    fn iter(&self) -> Range<u32> {
        *self
    }
}
```

However, this impl would be illegal, because `Range<u32>` doesn't use
the parameter `'a`. Presuming we adopted the rule I suggested in the
previous post, every value for `Iter<'a>` would have to use the `'a`
exactly once, as the first lifetime argument.  So `Foo<'a, u32>` would
be ok, as would `&'a Bar`, but `Baz<'static, 'a>` would not.

### Working around this limitation with newtypes

You could work around this limitation above by introducing a newtype.
Something like this:

```rust
struct RangeIter<'a> {
    range: Range<u32>,
    dummy: PhantomData<&'a ()>,
    //                  ^^ need to use `'a` somewhere
}
```

We can then implement `Iterator` for `RangeIter<'a>` and just proxy
`next()` on to `self.range.next()`. But this is kind of a drag.

### An alternative: give users the choice

For a long time, I had assumed that if we were going to introduce HKT,
we would do so by letting users define the kinds more explicitly. So,
for example, if we wanted the member `Iter` to be of kind `lifetime ->
type`, we might declare that explicitly.  Using the `<_>` and `<'_>`
notation I was using in earlier posts, that might look like this:

```
trait Iterable {
    type Iter<'_>;
}
```   

Now the trait has declared that impls must supply a valid, partially
applied struct/enum name as the value for `Iter`. 

I've somewhat soured on this idea, for a variety of reasons. One big
one is that we are forcing trait users to mak this choice up front,
when it may not be obvious whether a HKT or an ATC is the better fit.
And of course it's a complexity cost: now there are two things to
understand.

Finally, now that I realize that HKT is going to require bounds, not
having names for things means it's hard to see how we're going to
declare those bounds. In fact, even the `Iterable` trait probably has
some bounds; you can't just use **any old** lifetime for the
iterator. So really the trait probably includes a condition that
`Self: 'iter`, meaning that the iterable thing must outlive the
duration of the iteration:

```rust
trait Iterable {
    type Iter<'iter>: Iterator<Item=Self::Item>
        where Self: 'iter; // <-- bound I was missing before
    type Item;
    
    fn iter<'iter>(&'iter self) -> Self::Iter<'iter>;
}
```

### Why focus on associated items?

You might wonder why I said that we should consider `<T as
Iterable>::Iter` to have type `lifetime -> type` rather than saying
that `Iterable::Iter` would be something of kind `type -> lifetime ->
type`. In other words, what about the input types to the trait itself?

It turns out that this idea doesn't really make sense. First off, it
would naturally affect existing associated types. So `Iterator::Item`,
for example, would be something of kind `type -> type`, where the
argument is the type of the iterator. `<Range<u32> as Iterator>::Item`
would be the syntax for *applying* `Iterator::Item` to `Range<u32>`.
Since we can write generic functions with higher-kinded parameters
like `fn foo<I<_>>()`, that means that `I` here might be
`Iterator::Item`, and hence `I<Range<u32>>` would be equivalent to
`<Range<u32> as Iterator>::Item`.

But remember that, to make inference tractable, we want to know that
`?X<Foo> = ?Y<Foo>` if and only if `?X = ?Y`. That means that we could
not allow `<Range<u32> as Iterator>::Item` to normalize to the same
thing as `<Range<u32> as SomeOtherTrait>::Foo`. You can see that this
doesn't even remotely resemble associated types as we know them, which
are just plain one-way functions.

### Conclusions

This is kind of the "capstone" post for the series that I set out to
write.  I've tried to give an overview of
[what associated type constructors are][post-a]; the
[ways that they can model higher-kinded patterns][post-b];
[what higher-kinded types are][post-c]; and now what it might mean if
we tried to combine the two ideas.

I hope to continue this series a bit further, though, and in
particular to try and explore some case studies and further
thoughts. If you're interested in the topic, I strongly encourage you
to
[hop over to the internals thread][internals]
and take a look. There have been a lot of insightful comments there.

That said, currently my thinking is this:

- Associated type constructors are a natural extension to the
  language. They "fit right in" syntactically with associated types.
- Despite that, ATC would represent a huge step up in expressiveness,
  and open the door to richer traits. This could be particularly important
  for many libraries, such as futures.
  - I know that Rayon had to bend over backwards in some places because we lack
    any way to express an "iterable-like" pattern.
- Higher-kinded types as expressed in Haskell are not very suitable for Rust:
  - they don't cover bounds, which we need;
  - the limitation to "partially applied" struct/enum names is not a natural fit,
    even if we loosen it somewhat.
- Moreover, adding HKT to the language would be a big complexity jump:
  - to use Rust, you already have to understand associated types, and ATC is not much more;
  - but adding to that rules and associated syntax for HKT feels like
    a lot to ask.
    
**So currently I lean towards accepting ATC with no restrictions and
modeling HKT using families.** That said, I agree that the potential
to feel like a lot of "boilerplate".  I sort of suspect that, in
practice, HKT would require a fair amount of its own boilerplate (i.e,
to abstract away bounds and so forth), and/or not be suitable for
Rust, but perhaps further exploration of example use-cases will be
instructive in this regard.

### Comments

Please leave comments on [this internals thread][internals].

[post-a]: {{ site.baseurl }}/blog/2016/11/02/associated-type-constructors-part-1-basic-concepts-and-introduction/
[post-b]: {{ site.baseurl }}/blog/2016/11/03/associated-type-constructors-part-2-family-traits/
[post-c]: {{ site.baseurl }}/blog/2016/11/04/associated-type-constructors-part-3-what-higher-kinded-types-might-look-like/
[internals]: https://internals.rust-lang.org/t/blog-post-series-alternative-type-constructors-and-hkt/4300/
