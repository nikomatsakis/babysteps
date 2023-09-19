---
layout: post
title: 'Associated type constructors, part 3: What higher-kinded types might look
  like'
categories: [Rust, ATC, HKT, Traits]
---
This post is a continuation of my posts discussing the topic of
associated type constructors (ATC) and higher-kinded types (HKT):

1. [The first post][post-a] focused on introducing the basic idea of
   ATC, as well as introducing some background material.
2. [The second post][post-b] showed how we can use ATC to model HKT,
   via the "family" pattern.
3. This post dives into what it would mean to support HKT directly
   in the language, instead of modeling them via the family pattern.

<!-- more -->

### The story thus far (a quick recap)

In the previous posts, we had introduced a basic `Collection` trait
that used ATC to support an `iterate()` method:

```rust
trait Collection<Item> {
    fn empty() -> Self;
    fn add(&mut self, value: Item);
    fn iterate<'iter>(&'iter self) -> Self::Iter<'iter>;
    type Iter<'iter>: Iterable<Item=&'iter Item>;
}
```

And then we were discussing this function `floatify`, which converts a
collection of integers to a collection of floats. We started with a
basic version using ATC:

```rust
fn floatify<I, F>(ints: &I) -> F
    where I: Collection<i32>, F: Collection<f32>
```

However, this version does not constrain the inputs and outputs to be
the same "sort" of collection. For example, it can be used to convert
a `Vec<i32>` to a `List<f32>`. Sometimes that is desirable, but maybe
not. To compensate, we augmented `Collection` with an associated
"family" trait, so that if we have (say) a `Foo<i32>`, we can convert
to a `Foo<f32>`:

```rust
trait Collection<Item> {
    ... // as before
    type Family: CollectionFamily;
}

trait CollectionFamily {
    type Coll<Item>: Collection<Item>;
}
```

This let us write a `floatify_family` like so, which does enforce that
the input and output collections belong to the same "family":

```rust
fn floatify_family<C>(ints: &C) -> C::Family::Member<f32>
    where C: Collection<i32> //    ^^^^^^^^^^^^^^^^^ another collection,
{                            //                      in same family
    ...
}    
```

A common question in response to the previous post was whether the
`CollectionFamily` trait was actually *necessary*. The answer is that
it is not, one could also have augmented the `Collection` trait to
just have a `Sibling` member:

```rust
trait Collection<Item> {
    ...
    type Sibling<AnotherItem>: Collection<AnotherItem>;
}
```

And then we could write `floatify_sibling` as follows:

```rust
fn floatify_sibling<C>(ints: &C) -> C::Sibling<f32>
    where C: Collection<i32> //     ^^^^^^^^^^^^^^^ another collection,
{                            //                     in same family
    ...
}    
```

For some more thoughts on that, see [my comment on internals].

In any case, where I want to go today is to start exploring what it
might mean to encode this family pattern directly into the language
itself. This is what people typically mean when they talk about
*higher-kinded types*.

### Supporting families directly in the language via HKT

The family trait idea is very powerful, but in a way it's a bit
indirect. Now for each collection type (e.g., `List<T>`), we wind up
adding another "family type" (`ListFamily`) that effectively
corresponds to the `List` part without the `<T>`:

```rust
struct List<T> { ... }
impl Collection for List<T> { type Family = ListFamily; ... }
struct ListFamily;
impl CollectionFamily for ListFamily { ... }
```

The idea of HKT is that can make it possible to just refer to `List`
(without proving a `<T>`), instead of introducing a "family type".
So for example we might write `floatify_hkt()` like so:

```rust
fn floatify_hkt<I<_>>(ints: &I<i32>) -> I<f32>
//              ^^^^ the notation `I<_>` signals that `I` is
//                   not a complete type
```

Here you see that we declared a different kind of parameter `I` --
normally `I` would represent a complete type, like `List<i32>`. But
because we wrote `I<_>` (I'm pilfering a bit from
[Scala's syntax][scala] here), we have declared that `I` represents a
*type constructor*, meaning something like `List`. To be a bit more
explicit, I'm going to write `List<_>`, where the `_` indicates an
"unspecified" type parameter.

So this signature is effectively saying that it takes as input a
`I<i32>` (for some `I`) and returns an `I<f32>` -- the intention is to
mean that it takes a collection of integers and returns the same sort
of collection, but applied to floats (so, e.g., `I` might be mapped to
`List<_>` or `Vec<_>`, yielding `List<i32>/List<f32>` or
`Vec<i32>/Vec<f32>` respectively). But is that what it really says?
It turns out that this question is bit more subtle than you might
think; let's dig in.

### Trait bounds, higher-ranked and otherwise

The first thing to notice is that `floatify_hkt()` is missing some
where-clauses. In particular, nowhere do we declare that `I<i32>` is
supposed to be a collection. To do that, we would need something like
this:

```rust
fn floatify_hkt<I<_>>(ints: &I<i32>) -> I<f32>
    where for<T> I<T>: Collection<T>
    //    ^^^^^^^^^^^^^^^^^^^^^^^^^^ "higher-ranked trait bound"
```

Here I am using the "higher-ranked trait bounds (HRTB) applied to types"
introduced by [RFC 1598][], and discussed in
[the previous post][post-b]. Basically we are saying that `I<T>` is
always a `Collection`, regardless of what `T` is.

So we just saw that we need HRTB to declare that any type `I<T>` is a
collection (otherwise, we just know it is some type). But (as far as I
know) Haskell doesn't have anything like HRTB -- in Haskell, trait
bounds cannot be higher-ranked, so you could only write a declaration
that uses explicit types, like so:

```rust
fn floatify_hkt<I<_>>(ints: &I<i32>) -> I<f32>
    where I<i32>: Collection<i32>,
          I<f32>: Collection<f32>,
```

In this case, that's a perfectly adequate declaration. But in some
cases, being forced to write out explicit types like this can cause
you to expose information in your interface you might otherwise prefer
to keep secret. Consider this function `process()`[^fc], which takes a
collection of inputs (of type `Input`) and returns a collection of
outputs (of type -- wait for it -- `Output`). The interesting thing
about this function is that, internally, it creates a temporary
collection of some intermediate type called `MyType`:

[^fc]: I was not able to find an even-mildly-convincing variant on `floatify` for this. =)

```rust
fn process<I<_>>(inputs: &I<Input>) -> I<Output>
    where I<Input>: Collection<Input>, I<Output>: Collection<Output>,
{
    struct MyType { ... }
    
    // create an intermediate collection for some reason or other
    let mut shapes: I<MyType> = points.iter().map(|p| ...).collect();
    //              ^^^^^^^^ wait, how do I know I<MyType> is a collection?

    ...
}
```

Now you can see the problem! We know that `I<Input>` is a collection,
and we know that `I<Output>` is a collection, but without some form of
HRTB, we can't declare that `I<MyType>` is a collection without moving
`MyType` outside of the fn body[^mod]. So being able to say something like
"`I<T>` is a collection no matter what `T` is" is actually crucial to
our ability to encapsulate the internal processing that we are doing.

[^mod]: This problem is not specific to types declared in fn bodies;
        one can easily construct similar examples where it would be
        necessary to make private structs public.
        
So, if Haskell lacks HRTB, how do they handle a case like this anyway?

### Higher-kinded self types

If you have higher-kinded types at your disposal, you can use them to
achieve something very similar to higher-ranked trait bounds, but we
would have to change how we defined our `Collection` trait. Currently,
we have a trait `Collection<T>` which is defined for some collection
type `C`; the type `C` is then considered a collection of items of
type `T`. So for example `C` might be `List<Foo>` (in which case `T`
would be `Foo`). The new idea would be to redefine `Collection` to be
defined over *collection type constructors* (like `List<_>`). So we
might write something like this:

```rust
trait HkCollection for Self<_> {
//    ^^               ^^^^^^^ declare that `Self` is a type constructor
//    stands for "higher-kinded"

    fn empty<T>() -> Self<T>;
    fn add<T>(self: &mut Self<T>, value: T);
    //    ^^^ the `T` effectively moved from the trait to the methods
    ...
}
```

Now I might implement this not for `List<T>` but rather for `List<_>`:

```rust
impl HkCollection for List<_> {
    fn empty<T>() -> List<T> {
        List::new()
    }
    ...
}
```

And, finally, instead of writing `where for<T> I<T>: Collection<T>`,
we can write `where I: HkCollection`. Note that here I bounded `I`,
not `I<_>`, since I am applying this trait not to any particular
*type*, but rather to the type *constructor*.

At first it may appear that these two setups are analogous, but **it
turns out that the "higher-kinded self types" approach has some pretty
big limitations**. Perhaps the most obvious is that it rules out
collections like `BitSet`, which can only store values of one particular
type:

```rust
impl HkCollection for BitSet { ... }
//                    ^^^^^^ not a type constructor
```

Note that with the older, non-higher-kinded collection trait, we could
easily do something like this:

```rust
impl Collection<usize> for BitSet { ... }
```

The same problem also confronts collections like `HashSet` or
`BTreeSet` that require bounds -- that is, even though these are
generic types, you can't actually make a `HashSet` of just any old
type `T`. It must be a `T: Hash`. In other words, when I write
something like `Self<_>`, I am actually leaving out some important
information about what kinds of types the `_` can be:

```rust
trait HkCollection for HashSet<_>
//                     ^^^^^^^ how can we restrict `_` to `Hash` types?
```

In Haskell, at least, if I have a HKT, that means I can apply this
type constructor to **any** type and get a result. But all collections
in Rust tend to apply *some* bounds on that. For example, `Vec<T>` and
`List<T>` both (implicitly) require that `T: Sized`. Or, if you have
`HashMap<K,V>`, you might consider it to be a collection of pairs `(K,
V)`, except that it only works if `K: Hash + Eq + Sized` and `V:
Sized`.

So, really, if we did want to support a syntax like `Foo<_>`, we would
actually need some way of constraining this `_`.

### SPJ's "Type Classes: Exploring the Design Space"

Naturally, Haskell has encountered all of these problems as well.  One
of my favorite papers is
["Type Classes: Exploring the Design Space" by Jones et al.][tcds],
published way back in 1997. They motivate "multiparameter type
classes" (which in Rust would be "generic traits" like
`Collection<T>`) by reviewing the various shortcomings of traits
defined with a higher-kinded `Self` type (like `HkCollection`):

- Section 2.1, "Overloading with coupled parameters" basically talks
  about the idea that impls might not always apply to *all* types.  So
  something like `impl Collection<usize> for BitSet` is a simple
  example -- if you choose the "collection family" to be `BitSet`, you
  can then forced to pick `usize` as your element type.
  - In these situations, it is often (but not always) the case that
    the "second" parameter could (and perhaps should) be an associated
    type. For example, we might have changed `trait Collection<Item> {
    ... }` to `trait Collection { type Item; ... }`. This would have
    meant that, for any given collection type, there is a fixed `Item`
    type.
    - So, for example, the `BitSet` imply that applied to any integral
      type would be illegal, because the type `BitSet` alone does not
      define the item type `T`:
      - `impl<T: Integer> Collection for BitSet { type Item = T; ... }`
    - I talked some about this tradeoff in the "Things I learned"
      section from [my post on Rayon][rayon]; the rule of thumb I
      describe there seems to suggest `Collection<T>` would be better,
      though I think you could argue it the other way. We'll have to
      experiment.
- Section 2.2, "Overloading with constrained parameters" covers the
  problem of wanting constraints like `T: Sized` or `T: Hash`. In
  Haskell, the `Sized` bound isn't necessary, but certainly things
  like `HashSet<T>` wanting `T: Hash` still applies.

Obviously this paper is pretty old (1997!), and a lot of new things in
Haskell have been developed since then (e.g., I think the paper
predates associated types in Haskell). I think this core tradeoff is
still relevant, however. Let me know though if you think I'm out of
date and I need to read up on feature X which tries to address this
trade-off. (For example, is there any treatment of higher-kinded types
5Bthat adds the ability to constrain parameters in some way?)

### Time to get a bit more formal

OK, I want to get a bit more formal in terms of how I am talking about
HKT. In particular, I want to talk more about what a *kind* is and why
we could call a type constructor like `List<_>` *higher*-kinded. The
idea is that just like types tell us what sort of value we have (e.g.,
`i32` vs `f32`), kinds tell us what sort of *generic parameter* we have.

In fact, Rust already has two kinds: lifetimes and types. Consider the
item `ListIter` that we saw earlier:

```rust
struct ListIter<'iter, T> { ... }`
```

Here we see that there are two parameters, `'iter` and `T`, and the
first one represents a lifetime and the second a type. Let's say that
`'iter` has the kind `lifetime` and `T` has the kind `type` (in
Haskell, people would write `type` as `*`) .

Now what is the kind of `ListIter<'foo, i32>`? This is also a `type`.

So what is the kind of a type constructor like `ListIter<'foo, _>`?
This is something which, if you give it a type, you get a type. That
sounds like a function, right? Well, the idea is to write that kind as
`type -> type`.

And so higher-kinded type parameters *are* kind of like functions,
except that instead of calling them at runtime (`foo(22)`), you
*apply* them to types (`Foo<i32>`). In general, when we can talk about
something "callable", we tend to call it "higher-", so in this case we
say "higher-kinded".

You can also imagine higher-kinded type parameters that abstract over
lifetimes. We might write this like `ListIter<'_, i32>`, which would
correspond to the kind `lifetime -> type`. If you had a parameter
`I<'_>`, then you could apply it like `I<'foo>`, and -- assuming `I =
ListIter<'_, i32>` -- you would get `ListIter<'foo, i32>`.

Speaking more generally, we can say that the *kind* `K` of a type
parameter can fit this grammar:

```
K = type | lifetime | K -> K
```

Note that this supports all kinds of crazy kinds, like `I<_<_>>`,
which would be `(type -> type) -> type`. This is like a `Foo` that is
not parameterized by another type, but rather by a type *constructor*,
so one would not write `Foo<i32>`, but rather `Foo<Vec<_>>`. Wow,
meta.

Note that everything here assumes that if you have a type constructor
`I` of kind `type -> type`, we can apply `I` to any type. There's no
way to say "types that are hashable". In later posts, I hope to dig
into this a bit more, and show that HRTB (and traits) can provide us a
means to express things like that.

### Decidability and inference

So you may have noticed that, in the previous paragraph, I was making
all kinds of analogies to higher-kinded types being like
functions. And certainly you can imagine defining "general type
lambdas", so that if you have a type parameter of kind `type -> type`,
you could supply *any* kind of function which, given one type, yields
another. But it turns out this is likely not what we want, for a
couple of reasons:

1. It doesn't actually express what we wanted.
2. It makes inference imposssible.

To get some intuition here, Let's go back to our first example:

```rust
fn floatify_hkt<I<_>>(ints: &I<i32>) -> I<f32>
```

Here, `I` is declared a parameter of kind `type -> type`. Now remember
that our intention was to say that these two parameters were the same
"sort" of collection (e.g., we take/return a `Vec<i32>/Vec<f32>` or a
`List<i32>/List<f32>`, but not a `Vec<i32>/List<f32>`). If however `I`
can be *any* "type lambda", then `I` could be a lambda that returns
`Vec<i32>` if given an `i32`, and `List<f32>` is given an `f32`. We
might imagine pseudo-code that uses `if` and talks about types, like
this:

```
type I<T> = if T == i32 { Vec<i32> } else { List<f32> };
```

At this point, if you've been carefully reading along, this should be
striking a memory. This sounds a lot like our first attempt at family
traits from the [previous post][post-b]! Let's go back in time to that
first take on `floatify_family()`:

```rust
fn floatify_family<F>(ints: &F::Collection<i32>) -> F::Collection<f32>
    where F: CollectionFamily
```

Basically here the `F` is playing *exactly* this "type lambda" role.
`F::Collection<T>` is the same as `I<T>`. Moreover, using impls and
traits, we can write arbitrary, [turing-complete] functions on types!

(Note: it sounds like being turing-complete is hard; it's not. It's
actually hard to *avoid* once you start adding in any reasonably
expressive system. You essentially have to add some special-cases and
limitations to do it.)

This implies that if we permit higher-kinded type parameters like `I`
to be mapped to just any old kind of "type lambda", our inference is
going to get stuck. So whenever you called `floatify_hkt()`, you would
need to explicitly annotate the "type lambda" `I`. Note that this is
worse than something like `collect()`, where all we need to know is
what the return type is, and we can figure everything out. Here, even
if we know the argument/return types, we can't figure out the
*function* that maps between them, at least not uniquely.

As an analogy, it'd be like if I told you "ok, so `f(1) = 2` and `f(2)
= 3`, what is the function `f`?". Naturally there is no unique
answer. You might think that the answer is `f(x) = 1 + x`, and that
does fit the data, but of course that's not the only answer. It could
also be `f(x) = min(x + 1, 10)`, and so forth.

### Limiting higher-kinded types via currying, like Haskell

The way that Haskell solves this problem is by **limiting**
higher-kinded types. In particular, they say that a higher-kinded type
has to be (the equivalent of) a `struct` or `enum` name with some
*suffix* of parameters left blank.

So that means that if you have a kind like `type -> type`, it could be
satisfied with `Vec<_>` or `Result<i32, _>`, but not `Result<_, i32>`
and certainly not some more complex function. It also means that if
you have aliases (like `type PairVec<T> = Vec<(T, T)>` in Rust), you
can't make an HKT from `PairVec<_>`.

This scheme has a lot of advantages! In particular, let's go back to
our type inference problem. As you recall, the fundamental kind of
constraint we end up with is type equalities. In that case, we wind up
knowing the "inputs" to a HKT and the "output". So I might have
something like:

    ?1<?2> = Result<i32, u32>
    
Since `?1` can't be just any function, I can uniquely determine that
`?1 = Result<i32, _>` and `?2 = u32`. There is just nothing else it
could be!

(This scheme is called *currying* in Haskell and it's actually really
quite elegant, at least in terms of how it fits into the whole
abstract language. It's basically a universal principle in Haskell
that any sort of "function" can be converted into a lambda by leaving
off a suffix of its parameters. I won't say more because (a)
converting the examples into Rust syntax doesn't really give you as
good a feeling for its elegance and (b) this post is long enough
without explaining Haskell too!)

In fact, we can go even futher. Imagine that we have an equality like
this, where we don't really know much at all about either side:

    ?1<?2> = ?3<?4>
    
Even here, we can make progress, because we can infer that `?1 = ?3`
and `?2 = ?4`. This is a pretty strong and useful property.

### Problems with currying for Rust

So there are a couple of reasons that a currying approach wouldn't
really be a good fit for Rust. For one thing, it wouldn't fit the `&`
"type constructor" very well. If you think of types like `&'a T`, you
effectively have a type of kind `lifetime -> type -> type` (well, not
exactly; the type `T` must outlive `'a`, giving rise to the same
matter of constrained types I raised earlier, but this problem is not
unique to `&` and applies to most any generic Rust type). Essentially,
give me a lifetime (`'a`) and a type (`T`) and I will give you a new
combined type `&'a T`. OK, so far so good, but if we follow a
currying-based approach, then this means that you can partially apply
`&` to a particular lifetime (`'a`), yielding a HKT like `type ->
type`. This is good for those cases where you wish to treat `&'a T`
interchangeably with other pointer-like types, such as `Rc<T>`.

But then there are times like `Iterable`, where you might like to be
able to take a base type like `&'a T` and plugin other lifetimes to
get `&'b T`. In other words, you might want `lifetime -> type`. But
using a Haskell-like currying approach you basically have to pick one
or the other.

Another problem with currying is that you always have to leave a
*suffix* of type parameters unapplied, and that is just (in practice)
unlikely to be a good choice in Rust. Imagine we wanted to use a
map-like type parameter `M<_,_>`, so that (say) we could take in a
`M<i32, T>` and convert it to a map `M<f32, T>` of the same basic
kind. Now consider the definition of `HashMap`, which actually has
three parameters (one of which is defaulted):

```rust
pub struct HashMap<K, V, S = RandomState>
```

We would have wanted `M = HashMap<_, _, S>`, but we can't do that,
because that's a *prefix* of the types we need, not a *suffix*.

One strategy that might work ok in practice is to say, in Rust, you
can name a HKT by putting an `_` on some *prefix* of the parameters
*for any given kind*. So e.g. we can do the following:

- `&'a T` yielding `type`
- `&'_ T` yielding `lifetime -> type`
- `&'a _` yielding `type -> type`
- `Ref<'_, T>` yielding `lifetime -> type`
- `Ref<'a, _>` yielding `type -> type`
- `HashMap<_, i32, S>` yielding `type -> type` (where the first `type` is the key)
- `HashMap<_, _, S>` yielding `type -> type -> type`
- `Result<_, Err>` yielding `type -> type`

but we could not do any of these, because in each case the `_` is not a prefix:

- `Foo<'a, '_, i32>`
- `HashMap<i32, _, S>`

Obviously it's unfortunate that the `_` would have to be a prefix, but
that's basically a necessary limitation to support type inference. If
you permitted `_` to appear anywhere, then only the most basic
constraints become solveable -- essentially in **practice** you wind
up with a scenario where **all type parameters** must become `_`, and
partial application never works. To see what I mean, consider some
examples:

- `?T<?U> = Rc<i32>`, solvable:
    - could be `?T = Rc<_>, ?U = i32`
    - but not that this only works because *all* type parameters of `Rc` were made into `_`
- `?T<?U> = Result<i32, u32>`, unsolvable:
    - could be `?T = Result<_, u32>, ?U = i32`
    - could be `?T = Result<i32, _>, ?U = u32`
- `?T<?U, ?V> = Result<i32, u32>`, solvable if we assume that ordering must be respected:
    - could be `?T = Result<_, _>, ?U = i32, ?V = u32`
    - again, this only works because *all* type parameters of `Result` were made into `_`

So, essentially, choosing a prefix (or suffix) is actually *more*
expressive in practice than allowing `_` to go anywhere, since the
latter would cripple inference and require manual type annotation.

So, what do you do if you'd like to be able to put the `_` anywhere?
Say, because you want the choice of `Result<_, E>` or `Result<T, _>`? The answer is that 
you build "wrapper types", like:

```rust
struct Unresult<E, T> {
    result: Result<T, E>
}
```

(Note that this won't work with a plain type alias, as you can't
partially apply a type alias.  This is precisely because `Unresult<X,
Y>` is a *distinct type* from `Result<Y, X>`, which is not the case
with a type alias.) 

I find this kind of interesting because it starts to resemble the
"dummy" types that we made for families. But this is not really a
"win" for ATC or family traits in particular. After all, you only need
said dummy types when the default order isn't working for you; and, if
you wanted to make one collection type (like `List<T>`) participate in
two different collection families, you'd need a wrapper there too.

### Side note: Alternatives to currying

I am not sure of the full space of alternatives here.

For example, it may be possible to permit higher-kinded types to be
assigned to more complex functions, but only if the user provides
explicit type hints in those cases. This would be perhaps analogous to
higher-ranked types in Haskell, which sometimes require a certain
amount of type annotation since they can't be fully inferred in
general.

Another fruitful area to explore is the branch of logic programming,
where this sort of inference is referred to as **higher-order
unification** -- basically, solving unification problems where you
have variables that are functions. Unsurprisingly, unrestricted
higher-order unification is a pretty thorny problem, lacking most of
the nice properties of first-order unification. For example, there can
be an infinite number of solutions, none of which is more general than
the other; in fact, in general, it's not even decidable whether there
*is* a solution or not!

Now, none of this means that there don't exist algorithms for solving
higher-order unification. In particular, there is a core solution
called Huet's algorithm; it's just that it is not guaranteed to
terminate and may generate an infinite number of
solutions. Nonetheless, in some settings it can work quite well.

There is also a *subset* of the higher-order unification called
**higher-order pattern matching**. In this subset, if I understand
correctly, we can solve unification constraints with higher-kinded
variables, but only if they look like this:

    for<T> (?1<T> = U<T>)
    
The idea here is that we are constraining `?1<T>` to be equal to
`U<T>` **no matter what `T` is**. In this case, clearly, `?1` must be
equal to `U`.  Apparently, this subset appears often in higher-order
logic programming languages like Lambda Prolog, but sadly it doesn't
seem that relevant to Rust.

### Conclusions

This concludes our first little tour of what HKT is, and what it might
mean for Rust. Here is a little summary of the some of the highlights:

- Higher-kinded types let you use a *type constructor* as a parameter;
  so you might have a parameter declared like `I<_>` whose value is `Vec<_>`;
  that is, the `Vec` type without specifying a particular kind of element.
- Higher-ranked trait bounds (which Haskell doesn't offer, but which
  are part of the [ATC RFC][RFC 1598]) permit functions to declare
  something like "`I<T>` is a collection of `T` elements, regardless
  of what `T` is".
  - Otherwise, you have to have a series of constraints like `I<i32>: Collection<i32>`,
    `I<f32>: Collection<f32>`.
  - This can reveal implementation details you might prefer to hide.
- What Haskell *does* offer as an alternative is traits whose `Self` type is higher-kinded.
  - However, because HKT in Haskell do not permit where-clauses or conditions,
    such a trait would not be usable for collections that impose limitations on
    their element types (i.e., basically all collections):
    - `BitSet` might require that the element is a `usize`;
    - `HashSet<T>` requires `T: Hash`;
    - `BTreeSet<T>` requires `T: Ord`;
    - heck, even `Vec<T>` requires `T: Sized` in Rust!
  - Thus, a tradeoff is born between multi-parameter type classes, which permit such
    conditions, and type classes based around higher-kinded types.
  - To be usable in Rust, we would have to extend the concept of HKT to include where clauses,
    since almost **all** Rust types include some condition, even if only `T: Sized`.
  - Note that *collection families* naturally permit one to apply where conditions and side clauses.
- Higher-kinded types in Haskell are limited to a "curried type declaration":
  - This makes type inference tractable and feels natural in Haskell.
  - Exporting this scheme to Rust feels awkward.
  - One thing that might work is that one can omit a *prefix* of the type parameters 
    of any given kind.
    
OK, that's enough for one post! In the next post, I plan to tackle the
following question:

- What is the difference between an "associated type constructor" and
  an "associated HKT"?
  - **What might it mean to unify those two worlds?**
  

### Comments

Please leave comments on
[this internals thread](https://internals.rust-lang.org/t/blog-post-series-alternative-type-constructors-and-hkt/4300).

#### Footnotes  

[post-a]: {{ site.baseurl }}/blog/2016/11/02/associated-type-constructors-part-1-basic-concepts-and-introduction/
[post-b]: {{ site.baseurl }}/blog/2016/11/03/associated-type-constructors-part-2-family-traits/
[RFC 1598]: https://github.com/rust-lang/rfcs/pull/1598
[rayon]: http://smallcultfollowing.com/babysteps/blog/2016/02/25/parallel-iterators-part-2-producers/
[uq]: https://en.wikipedia.org/wiki/Universal_quantification
[turing-complete]: https://www.reddit.com/r/rust/comments/2o6yp8/brainfck_in_rusts_type_system_aka_type_system_is/
[my comment on internals]: https://internals.rust-lang.org/t/blog-post-series-alternative-type-constructors-and-hkt/4300/28?u=nikomatsakis
[scala]: http://blogs.atlassian.com/2013/09/scala-types-of-a-higher-kind/
[tcds]: http://research.microsoft.com/en-us/um/people/simonpj/Papers/type-class-design-space/


