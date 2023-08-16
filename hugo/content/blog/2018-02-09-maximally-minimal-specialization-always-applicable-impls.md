---
categories:
- Rust
- Specialization
date: "2018-02-09T00:00:00Z"
slug: maximally-minimal-specialization-always-applicable-impls
title: 'Maximally minimal specialization: always applicable impls'
---

So
[aturon wrote this beautiful post about what a good week it has been][week].
In there, they wrote:

> **Breakthrough #2**: @nikomatsakis had a eureka moment and figured out a
> path to make specialization sound, while still supporting its most
> important use cases (blog post forthcoming!). Again, this suddenly
> puts specialization on the map for Rust Epoch 2018.

Sheesh I wish they hadn't written that! Now the pressure is on. Well,
here goes nothing =).

*Anyway*, I've been thinking about the upcoming Rust Epoch. We've been
iterating over the final list of features to be included and I think
it seems pretty exciting.  But there is one "fancy type system"
feature that's been languishing for some time:
**specialization**. Accepted to much fanfare as [RFC 1210][], we've
been kind of stuck since then trying to figure out how to solve an
underlying soundness challenge.

As aturon wrote, I **think** (and emphasis on think!) I may have a
solution. I call it the **always applicable** rule, but you might also
call it **maximally minimal specialization**[^early].

[RFC 1210]: https://github.com/rust-lang/rfcs/blob/master/text/1210-impl-specialization.md
[aturon-sos]: https://aturon.github.io/blog/2017/07/08/lifetime-dispatch/ 
[week]: http://aturon.github.io/2018/02/09/amazing-week/

[^early]: We don't say it so much anymore, but in the olden days of Rust, the phrase "max min" was very "en vogue"; I think we picked it up from some ES6 proposals about the class syntax.

Let's be clear: **this proposal does not support all the
specialization use cases originally envisioned**. As the phrase
*maximally minimal* suggests, it works by focusing on a core set of
impls and accepting those. But that's better than most of its
competitors! =) Better still, it leaves a route for future expansion.

### The soundness problem

I'll just cover the soundness problem very briefly; Aaron wrote an
[excellent blog post][aturon-sos] that covers the details. The crux of
the problem is that code generation wants to erase regions, but the
type checker doesn't. This means that we can write specialization
impls that depend on details of lifetimes, but we have no way to test
at code generation time if those more specialized impls apply. A very
simple example would be something like this:

```rust
impl<T> Trait for T { }
impl Trait for &'static str { }
```

At code generation time, all we know is that we have a `&str` -- for
**some lifetime**. We don't know if it's a static lifetime or not. The
type checker is supposed to have assured us that **we don't have to
know** -- that this lifetime is "big enough" to cover all the uses of
the string.

My proposal would reject the specializing impl above. I basically aim
to solve this problem by guaranteeing that, just as today, code
generation **doesn't have to care** about specific lifetimes, because
it knows that -- whatever they are -- if there is a potentially
specializing impl, it will be applicable.

### The "always applicable" test

The core idea is to change the rule for when overlap is allowed. In
[RFC 1210][] the rule is something like this:

- Distinct impls A and B are allowed to overlap if one of them
  *specializes* the other.
  
We have long intended to extend this via the idea of [intersection impls],
giving rise to a rule like:

[intersection impls]: http://smallcultfollowing.com/babysteps/blog/2016/09/24/intersection-impls/

- Two distinct impls A and B are allowed to overlap if, for all
  types in their intersection:
  - there exists an applicable impl C and C *specializes* both A and B.[^reflexive]
  
[^reflexive]: Note: an impl is said to *specialize* itself.
    
My proposal is to extend that intersection rule with the *always
applicable* test. I'm actually going to start with a simple version,
and then I'll discuss an important extension that makes it much more
expressive.

- Two distinct impls A and B are allowed to overlap if, for all
  types in their intersection:
  - there exists an applicable impl C and C *specializes* both A and B,
  - **and** that impl C is *always applicable*.
    
(We will see, by the way, that the precise definition of the
*specializes* predicate doesn't matter much for the purposes of my
proposal here -- any partial order will do.)

### When is an impl *always applicable*?

Intuitively, an impl is *always applicable* if it does not impose any
additional conditions on its input types beyond that they be
well-formed -- and in particular it doesn't impose any equality
constraints between parts of its input types. It also has to be fully
generic with respect to the lifetimes involved.

Actually, I think the best way to explain it is in terms of the
**implied bounds** proposal[^scalexm] ([RFC][ibrfc], [blog post][ibpost]). The
idea is roughly this: an impl is *always applicable* if it meets three
conditions:

- it relies **only** on implied bounds,
- it is fully generic with respect to lifetimes,
- it doesn't repeat generic type parameters.

[ibrfc]: https://github.com/rust-lang/rfcs/blob/master/text/2089-implied-bounds.md
[ibpost]: {{ site.baseurl }}/blog/2014/07/06/implied-bounds/
[ibpr]: https://github.com/rust-lang-nursery/chalk/pull/82
[^scalexm]: Let me give a shout out here to scalexm, who recently [emerged with an elegant solution for how to model implied bounds in Chalk][ibpr].

Let's look at those three conditions. 

#### Condition 1: Relies only on implied bounds.

Here is an example of an *always applicable* impl (which could
therefore be used to specialize another impl):

```rust
struct Foo<T: Clone> { }

impl<T> SomeTrait for Foo<T> { 
  // code in here can assume that `T: Clone` because of implied bounds
}
```

Here the impl works fine, because it adds no additional bounds beyond
the `T: Clone` that is implied by the struct declaration.

If the `impl` adds new bounds that are not part of the struct,
however, then it is **not always applicable**:

```rust
struct Foo<T: Clone> { }

impl<T: Copy> SomeTrait for Foo<T> { 
  // ^^^^^^^ new bound not declared on `Foo`,
  //         hence *not* always applicable
}
```

#### Condition 2: Fully generic with respect to lifetimes.

Each lifetime used in the impl header must be a lifetime parameter,
and each lifetime parameter can only be used once. So an impl like
this is **always applicable**:

```rust
impl<'a, 'b> SomeTrait for &'a &'b u32 {
  // implied bounds let us assume that `'b: 'a`, as well
}
```

But the following impls are **not** always applicable:

```rust
impl<'a> SomeTrait for &'a &'a u32 {
                   //  ^^^^^^^ same lifetime used twice
}

impl SomeTrait for &'static str {
                //  ^^^^^^^ not a lifetime parmeter
}
```

#### Condition 3: Each type parameter can only be used once.

Using a type parameter more than once imposes "hidden" equality constraints
between parts of the input types which in turn can lead to equality constraints
between lifetimes. Therefore, an *always applicable* impl must use each
type parameter only once, like this:

```rust
impl<T, U> SomeTrait for (T, U) {
}
```

Repeating, as here, means the impl cannot be used to specialize:

```rust
impl<T> SomeTrait for (T, T) {
  //                   ^^^^
  // `T` used twice: not always applicable
}
```

#### How can we think about this formally?

For each impl, we can create a Chalk goal that is provable if it is
always applicable. I'll define this here "by example". Let's consider
a variant of the first example we saw:

```rust
struct Foo<T: Clone> { }

impl<T: Clone> SomeTrait for Foo<T> { 
}
```

As we saw before, this impl is *always applicable*, because the `T:
Clone` where clause on the impl follows from the implied bounds of
`Foo<T>`. 

The recipe to transform this into a predicate is that we want to
replace each *use* of a type/region parameter in the input types with
a universally quantified type/region (note that the two uses of the
same type parameter would be replaced with two distinct types). This
yields a "skolemized" set of input types T. When check if the impl
could be applied to T.

In the case of our example, that means we would be trying to prove
something like this:

```
// For each *use* of a type parameter or region in
// the input types, we add a 'forall' variable here.
// In this example, the only spot is `Foo<_>`, so we
// have one:
forall<A> {
  // We can assume that each of the input types (using those
  // forall variables) are well-formed:
  if (WellFormed(Foo<A>)) {
    // Now we have to see if the impl matches. To start,
    // we create existential variables for each of the
    // impl's generic parameters:
    exists<T> {
      // The types in the impl header must be equal...
      Foo<T> = Foo<A>,
      // ...and the where clauses on the impl must be provable.
      T: Clone,
    }
  }
} 
```

Clearly, this is provable: we infer that `T = A`, and then we can
prove that `A: Clone` because it follows from
`WellFormed(Foo<A>)`. Now if we look at the second example, which
added `T: Copy` to the impl, we can see why we get an error. Here was
the example:

```rust
struct Foo<T: Clone> { }

impl<T: Copy> SomeTrait for Foo<T> { 
  // ^^^^^^^ new bound not declared on `Foo`,
  //         hence *not* always applicable
}
```

That example results in a query like:

```
forall<A> {
  if (WellFormed(Foo<A>)) {
    exists<T> {
      Foo<T> = Foo<A>,
      T: Copy, // <-- Not provable! 
    }
  }
} 
```

In this case, we fail to prove `T: Copy`, because it does not follow
from `WellFormed(Foo<A>)`.

As one last example, let's look at the impl that repeats a type parameter:

```rust
impl<T> SomeTrait for (T, T) {
  // Not always applicable
}
```

The query that will result follows; what is interesting here is that
the type `(T, T)` results in *two* forall variables, because it has
two distinct *uses* of a type parameter (it just happens to be one
parameter used twice):

```
forall<A, B> {
  if (WellFormed((A, B))) {
    exists<T> {
      (T, T) = (A, B) // <-- cannot be proven
    }
  }
} 
```

### What is accepted?

What this rule primarily does it allow you to specialize blanket impls
with concrete types. For example, we currently have a `From` impl
that says any type `T` can be converted to itself:

```rust
impl<T> From<T> for T { .. }
```

It would be nice to be able to define an impl that allows a value of
the never type `!` to be converted into *any* type (since such a value
cannot exist in practice:

```rust
impl<T> From<!> for T { .. }
```

However, this impl overlaps with the reflexive impl. Therefore, we'd
like to be able to provide an intersection impl defining what happens
when you convert `!` to `!` specifically:

```rust
impl From<!> for ! { .. }
```

All of these impls would be legal in this proposal.

### Extension: Refining *always applicable* impls to consider the base impl

While it accepts some things, the *always applicable* rule can also be
quite restrictive. For example, consider this pair of impls:

```rust
// Base impl:
impl<T> SomeTrait for T where T: 'static { }
// Specializing impl:
impl SomeTrait for &'static str { }
```

Here, the second impl wants to specialize the first, but it is not
*always applicable*, because it specifies the `'static` lifetime. *And
yet,* it feels like this should be ok, since the base impl only
applies to `'static` things.

We can make this notion more formal by expanding the property to say
that the specializing impl C must be *always applicable* **with
respect to the base impls**. In this extended version of the
predicate, the impl C is allowed to rely not only on the *implied
bounds*, but on the *bounds that appear in the base impl(s)*.

So, the impls above might result in a Chalk predicate like:

```
// One use of a lifetime in the specializing impl (`'static`),
// so we introduce one 'forall' lifetime:
forall<'a> {
  // Assuming the base impl applies:
  if (exists<T> { T = &'a str, T: 'static }) {
      // We have to prove that the
      // specialized impls type's can unify:
      &'a str = &'static str
    }
  }
} 
```

As it happens, the compiler today has logic that would let us deduce
that, because we know that `&'a str: 'static`, then we know that `'a =
'static`, and hence we could solve this clause successfully.

This rule also allows us to accept some cases where type parameters
are repeated, though we'd have to upgrade chalk's capability to let it
prove those predicates fully. Consider this pair of impls from
[RFC 1210][]:

```rust
// Base impl:
impl<E, T> Extend<E, T> for Vec<E> where T: IntoIterator<Item=E> {..}
// Specializing impl:
impl<'a, E> Extend<E, &'a [E]> for Vec<E> {..}
               //  ^       ^           ^ E repeated three times!
```

Here the specializing impl repeats the type parameter `E` three times!
However, looking at the base impl, we can see that all of those
repeats follow from the conditions on the base impl. The resulting
chalk predicate would be:

```
// The fully general form of specializing impl is
// > impl<A,'b,C,D> Extend<A, &'b [C]> for Vec<D>
forall<A, 'b, C, D> {
  // Assuming the base impl applies:
  if (exists<E, T> { E = A, T = &'b [B], Vec<D> = Vec<E>, T: IntoIterator<Item=E> }) {
    // Can we prove the specializing impl unifications?
    exists<'a, E> {
      E = A,
      &'a [E] = &'b [C],
      Vec<E> = Vec<D>,
    }
  }
} 
```

This predicate should be provable -- but there is a definite catch.
At the moment, these kinds of predicates fall outside the "Hereditary
Harrop" (HH) predicates that Chalk can handle. HH predicates do not
permit existential quantification and equality predicates as
hypotheses (i.e., in an `if (C) { ... }`). I can however imagine some
quick-n-dirty extensions that would cover these particular cases, and
of course there are more powerful proving techniques out there that we
could tinker with (though I might prefer to avoid that).

### Extension: Reverse implied bounds rules

While the previous examples ought to be provable, there are some other
cases that won't work out without some further extension to Rust.
Consider this pair of impls:

```rust
impl<T> Foo for T where T: Clone { }
impl<T> Foo for Vec<T> where T: Clone { }
```

Can we consider this second impl to be always applicable relative to
the first? Effectively this boils down to asking whether knowing
`Vec<T>: Clone` allows us to deduce that `T: Clone` -- and right now, we can't
know that. The problem is that the impls we have only go one way. 
That is, given the following impl:

```rust
impl<T> Clone for Vec<T> where T: Clone { .. }
```

we get a program clause like  

```
forall<T> {
  (Vec<T>: Clone) :- (T: Clone)
}
```

but we *need* the reverse:

```
forall<T> {
  (T: Clone) :- (Vec<T>: Clone)
}
```

This is basically an extension of implied bounds; but we'd have to be careful.
If we just create those reverse rules for every impl, then it would mean that
removing a bound from an impl is a breaking change, and that'd be a shame.

We could address this in a few ways. The most obvious is that we might
permit people to annotate impls indicating that they represent minimal
conditions (i.e., that removing a bound is a breaking
change).

Alternatively, I feel like there is some sort of feature "waiting" out
there that lets us make richer promises about what sorts of trait
impls we might write in the future: this would be helpful also to
coherence, since knowing what impls will *not* be written lets us
permit more things in downstream crates.  (For example, it'd be useful
to know that `Vec<T>` will *never* be `Copy`.)

### Extension: Designating traits as "specialization predicates"

However, even when we consider the base impl, and even if we have some
solution to reverse rules, we *still* can't cover the use case of
having "overlapping blanket impls", like these two:

```rust
impl<T> Skip for T where T: Read { .. }
impl<T> Skip for T where T: Read + Seek { .. }
```

Here we have a trait `Skip` that (presumably) lets us skip forward in
a file.  We can supply one default implementation that works for any
reader, but it's inefficient: it would just read and discard N
bytes. It'd be nice if we could provide a more efficient version for
those readers that implement `Seek`. Unfortunately, this second impl
is not *always applicable with respect to* the first impl -- it adds a
new requirement, `T: Seek`, that does not follow from the bounds on
the first impl nor the implied bounds.

You might wonder why this is problematic in the first place. The danger is
that some other crate might have an impl for `Seek` that places lifetime constraints,
such as:

```rust
impl Seek for &'static Foo { }
```

Now at code generation time, we won't be able to tell if that impl
applies, since we'll have erased the precise region.

However, what we *could* do is allow the `Seek` trait to be designated
as a **specialization predicate** (perhaps with an attribute like
`#[specialization_predicate]`). Traits marked as specialization
predicates would be limited so that every one of their impls must be
*always applicable* (our original predicate). This basically means
that, e.g., a "reader" cannot *conditionally* implement `Seek` -- it
has to be always seekable, or never. When determining whether an impl
is *always applicable*, we can ignore where clauses that pertain to
`#[specialization_predicate]` traits.

Adding a `#[specialization_predicate]` attribute to an existing trait
would be a breaking change; removing it would be one too. However, it
would be possible to take existing traits and add "specialization
predicate" subtraits. For example, if the `Seek` trait already existed,
we might do this:

```rust
impl<T> Skip for T where T: Read { .. }
impl<T> Skip for T where T: Read + SeekPredicate { .. }

#[specialization_predicate]
trait UnconditionalSeek: Seek {
  fn seek_predicate(&self, n: usize) {
    self.seek(n);
  }
}
```

Now streams that implement seek unconditionally (probably all of them)
can add `impl UnconditionalSeek for MyStream { }` and get the
optimization.  Not as automatic as we might like, but could be worse.

### Default impls need not be *always applicable*

This last example illustrates an interesting point. RFC 1210 described not
only specialization but also a more flexible form of defaults that go beyond
default methods in trait definitions. The idea was that you can define lots of defaults
using a `default impl`. So the `UnconditionalSeek` trait at the end of the last section
might also have been expressed:

```rust
#[specialization_predicate]
trait UnconditionalSeek: Seek {
}

default impl<T: Seek> UnconditionalSeek for T {
  fn seek_predicate(&self, n: usize) {
    self.seek(n);
  }
}
```

The interesting thing about default impls is that they are not (yet) a
full impl.  They only represent default methods that *real* impls can
draw upon, but users still have to write a real impl somewhere. This
means that they can be exempt from the rules about being *always
applicable* -- those rules will be enforced at the real impl point.
Note for example that the default impl above is not always available,
as it depends on `Seek`, which is not an implied bound anywhere.

### Conclusion

I've presented a refinement of specialization in which we impose one
extra condition on the specializing impl: not only must it be a subset
of the base impl(s) that it specializes, it must be *always
applicable*, which means basically that if we are given a set of types T where we know:

- the base impl was proven by the type checker to apply to T
- the types T were proven by the type checker to be well-formed
- and the specialized impl unifies with the lifetime-erased versions of T

then we know that the specialized impl applies.

The beauty of this approach compared with past approaches is that it
preserves the existing role of the type checker and the code
generator. As today in Rust, the type checker always knows the full
region details, but the code generator can just ignore them, and still
be assured that all region data will be valid when it is accessed.

This implies for example that we don't need to impose the restrictions
that [aturon discussed in their blog post][aturon-sos]: we can allow specialized
associated types to be resolved in full by the type checker as long as they are not marked
default, because there is no danger that the type checker and trans will come to different
conclusions.

### Thoughts?

I've opened
[an internals thread on this post](https://internals.rust-lang.org/t/blog-post-maximally-minimal-specialization-always-applicable-impls/6739). I'd
love to hear whether you see a problem with this approach. I'd also
like to hear about use cases that you have for specialization that you
think may not fit into this approach.

### Footnotes
