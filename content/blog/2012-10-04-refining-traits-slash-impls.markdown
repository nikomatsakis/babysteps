---
layout: post
title: "Refining traits and impls"
date: 2012-10-04T09:32:00Z
comments: true
categories: [Rust, Traits]
---

Currently, the Rust compiler accepts all manner of trait, impl, and
bound declarations.  In fact, it accepts plenty of declarations that
later phases of the compiler are not sophisticated enough to handle.
In other words, the syntax is writing checks the semantics can't cash.
(*An aside:* I just love saying that phrase for some perverse reason.
I really wish however that checks, like rotary dial telephones, were
something that younger people vaguely understood but which no longer
had relevance in the modern era.  The [Swiss Einzahlungschein][se] truly
opened my eyes! Anyhow.)

[se]: https://www.postfinance.ch/en/biz/prod/pay/debsolution/inpay/apply.html

I would like to solve this.  In particular, I would very much like to
have rules with the following properties:

- *Coherent and unambiguous:* There is at most one impl of a given trait for a given type.
- *Safe linking:* Linking in a new crate cannot cause a static error
  nor violate any of the above properties.
- *Overloading- and backtracking-free:* Given an expression
  `a.m(...)`, the choice of which method `m` to invoke should be based
  only on the type of `a`.  More generally, given a type `T` and a
  trait `N`, we should be able to decide whether `T` implements `N`
  without considering other types or other traits.
- *Termination:* Compilation always terminates.

What follows is a justifiation of those principles and a description
of how to achieve them.  If you don't want to read it, here is the summary:

*Aside from the coherence requirement, the main restriction is that a
given type can only implement or extend a given trait once (and hence
with one set of type parameters).*

<!-- more -->
    
### Why these principles?  
  
None of these principles is strictly necessary.  Haskell for example
maintains coherence but does not (necessarily) guarantee safe linking;
you can have modules that do not link together due to incompatible
typeclass declarations (actually, given the right configuration
settings, Haskell can either violate coherence or guarantee
safe-linking, so I guess what I mean is "based on my folklore idea of
which specific settings are commonly used").  Scala does not guarantee
coherence, though they can use inheritance to do so when it is
important.  Haskell's multiparameter type classes are not
overloading-free in general, though they can be made overloading-free
through the use of functional dependencies or type functions.

I won't bother to justify coherence nor monotonicity, but I do want to
discuss overloading freedom a bit.  It has several nice implications.
For one, the implementation never needs to backtrack: that is, it can
consider whether a type implements a trait simply by searching through
the impls for a trait, rather than having to consider whether a set of
types implement a trait.  This simplifies the implementation; it also
fits better with the object-oriented flavor of our traits/impls: when
you write `<A: N<B, C, D>>`, it is the type `A` which decides which
impl of `N` will be used, not the types `B`, `C`, or `D`.  Another
nice property is that it is consistent with the rest of the language,
which doesn't support overloading (except through the trait
mechanism).

Interestingly, in the paper
["Type classes: an exploration of the design space"][tc], Jones et
al. discuss several uses for multiparameter type classes which they
find compelling.  If I am not mistaken, *all of those examples* are
compatible with the requirements I propose here, with the exception of
overloading for mathematical operations, and I describe a workaround
for that case below.

[tc]: http://research.microsoft.com/en-us/um/people/simonpj/papers/type-class-design-space/

### What restrictions are necessary?

Aside from the coherence requirement, the main restriction is that a
given type can only implement or extend a given trait once (and hence
with one set of type parameters).

More formally phrased, the full set of restrictions on traits and
impls are:

1. You can only provide one implementation of any particular trait for
   a given type.  In other words, for any two impls with the same trait name:
   
       impl<...> T1: N<...> {...}
       impl<...> T2: N<...> {...}
       
   the self types `T1` and `T2` must not have a common subtype for any
   substitutions of the various impl parameters. Note in particular that it
   does not matter what type parameters are provided to the trait `N`.
   In other words, the following set of impls *would be illegal*:
   
        impl ~str: Iterable<~str> {...} // by word
        impl ~str: Iterable<char> {...} // by character
        
   These are illegal because both implement the `Iterable` trait but with the
   same type.
2. There are no "orphan" implementations.  This means that for every `impl<...> T: N<...>`
   defined in the current crate, at least one of the following two conditions holds:
   - the trait `N` is declared in the current crate;
   - the self type `T` is either a nominal type declared in the current
     crate or an arity-1 type constructor whose argument (transitively)
     is declared in the current crate (e.g., `Foo`, `@Foo`, `~[Foo]`,
     or---for that matter---`~[@Foo]`, where `Foo` is declared in the
     current crate).
3. If the self type of an impl for trait `N<...>` is a type parameter `T`,
   `T` must not be bounded (directly or indirectly) by the trait `N`.
4. Trait inheritance must form a tree and no trait `N` may inherit
   from another trait `M` more than once with multiple values for
   `M`'s type parameters.
   
Restriction 1 is concerned with ensuring freedom from both ambiguity
and overloading.  Restriction 2 guarantees safe linking. Restriction 3
is required to ensure that compilation always terminates, I believe.
Otherwise you might have some impl like `impl<T: Eq> T: Eq` and we
could wind up searching forever trying to find out whether `T`
implements `Eq` (though I imagine one could write an algorithm that
knows to terminate, sort of like subtyping for recursive structural
types, I just don't care to, since an impl like this has no purpose in
practice).

It is interesting to compare this to Haskell.  The situation is
loosely similar to a multiparameter type class specified
as follows:

     class C self a ... z | self -> a ... z where ...
     
I have a "read-only" relationship with Haskell, so there's probably a
mistake in the syntax somewhere, but basically I mean that the first
type parameter to the type class (`self`) determines the values for
the other type parameters (`a...z`).  However, the analogy is not
exact.  With functional dependencies, knowing `self` would tell you `a...z`
precisely.  In our system it's not quite that simple:

1. The `self` type in our system in general can bound the later type
   parameters `a...z` but due to variance does not strictly determine
   them.
2. The rules I gave permit an impl such as `impl<A> Foo: Bar<A>`.  In
   this case, the self type (`Foo`) does not even bound th type variable
   `A`.  I don't *think* this has any ill effects, but it does make me
   nervous, so we could add another restriction that every type variable
   appearing in the trait type must appear in the self type.
   
One interesting distinction between multiparameter typeclasses in
Haskell and the rules I propose is that we support an impl like
`impl<A: Foo> A: Bar`: that is, an impl that allows you to implement a
trait `Bar` given an instance of the trait `Foo`.  This pattern of
impl is useful in some cases as I discuss below, though it can also be
abused (also discussed below).  One must be cautious here to ensure
termination.  I believe that restriction #3 is sufficient, though it
seems somewhat less restrictive than Haskell's rules (but we are not
trying to infer as much as Haskell is).  I probably ought to read
[these papers][these-papers] to be sure, since they apparently discuss
the matter in more detail.

[these-papers]: http://research.microsoft.com/en-us/um/people/simonpj/papers/fd-chr/

**UPDATE**: I discuss this analogy to Haskell further in the [next post][postscript].

**UPDATE**: I am pretty sure that the termination condition is insufficient.  More to come.

[postscript]: {{< baseurl >}}/blog/2012/10/04/a-postscript-on-traits-and-impls/

### What if I *want* overloading?

Despite the fact that I want to prevent it, overloading can sometimes
be very useful.  For example, consider the trait `Add` that is used to
define the meaning of the `+` operator:

```
trait Add<R,S> {
    pure fn add(&self, rhs: &R) -> S;
}
```

As you can see, this trait is parameterized by the type of the
right-hand side (`R`) and the type of the sum (`S`).

Now, imagine that we wished to permit the addition of ints with ints
but also ints with floats (a classic example of overloading).  We
might have the following implementations of `Add`:

```
impl int: Add<int, int> { ... }
impl int: Add<float, float> { ... }
```

We have effectively overloaded the `add()` method now.  I can add ints
to ints or ints to floats.  So if I write `x + y` (which is basically
shorthand for `(&x).add(&y)`), the compiler must use both the type of
`x` and `y` to decide which impl will be invoked.

Interestingly, it is possible to encode something very much like
overloading by making use of double-dispatch in a style somewhat
similar to the visitor pattern:

```
trait IntRhs<S> {
    pure fn add_to_int(lhs: int) -> S;
}
impl<S, R: IntRhs<S>> int: Add<R, S> {
    pure fn add(&self, rhs: &R) -> S {
        rhs.add_to_int(*self)
    }
}
impl int: IntRhs<int> {...}
impl float: IntRhs<float> {...}
```

Although this pattern is wordier, it is also more flexible: it is now
possible for other types to implement `IntRhs` and hence be usable as
the right-hand-side of an addition with an integer.  In other words,
this pattern is probably how you should be doing it anyhow.

### When should I use an impl whose self type is a type parameter?

I spent some time looking through the impls that appear in our standard
library.  Most are fairly straightforward.  There is one pattern
though that stands out as unusal.  You can have an impl which 
has the form:

    impl<A: Foo> A: Bar { ... }
    
This impl implements the trait `Bar` for any type `A` that implements
the trait `Foo`.  This kind of impl is supported under the rules I
propose; however, it is only permitted if (1) `Bar` is defined in the
current crate and (2) there are *no other impls of the trait `Bar`*.

The reason that there can be no other impls is that if there were
another impl, no matter what self type it had, it would violate
restriction #1 from my list, since you could substitute that type for
`A`.  Note that restriction #1 did not require that the substituted
type meet the bounds placed on the type variable---in other words, it
is a violation to implement the trait `Bar` for any other type `T`,
even if `T` does not implement `Foo`!  This is an intentional
limitation: it helps ensure that the implementation does not need to
backtrack.  It also has other nice properties: for example, adding an
implementation for the trait `Foo` can never cause ambiguity errors
with respect to implementations of the trait `Bar`.

It turns out that we use this impl in two distinct pattern.  The first
of those patterns *is* compatible with restriction #1 and the second
is not.  However, there is a better way to express the second pattern.

#### Pattern #1: Extension traits

Sometimes we simply wish to extend an interface with "convenience"
methods:

```
trait Hash {
    pure fn hash_keyed(k0: u64, k1: u64) -> u64;
}
trait HashUtil {
    pure fn hash() -> u64;
}
impl<A: Hash> A: HashUtil {
    pure fn hash() -> u64 { self.hash_keyed(0,0) }
}
```

In this particular case, a default method implementation would likely
be a better choice.  However, this pattern can still be useful if the
trait you are extending is outside of your control.

The key point here is that there will never be another implementor of
this trait.  That is, you could just as well have written this impl as
a standalone function (but then you couldn't use dot notation):

```
fn hash<A: Hash>(a: &A) -> u64 {
    a.hash_keyed(0, 0)
}
```

#### Pattern #2: Simulating inheritance

We have one impl which says that everything which can be converted
into a stream of bytes is also hashable:

```
impl<A: IterBytes> A: Hash {
    pure fn hash_keyed(k0: u64, k1: u64) -> u64 {
        /* apply a super awesome cryptographic hashing algorithm
           that goes way over my head */
    }
}
```

Technically speaking, this example is precisely the same as the
previous section, but it's purpose is very different.  I believe that
the intention was to define a kind of "default" method that says: for
every type that is byte-iterable, it can be hashed as follows, if no
better way is provided."

There are two problems with this solution.  The first is that it
raises interesting ambiguity questions if there is a type that implies
`Hash` and also `IterBytes`---which version of `Hash` should we
prefer?  The explicit one or the "default-y" one based on `IterBytes`?

Even if we assume that all types will either implement `Hash` OR
`IterBytes`, impls like this make resolution difficult.  Imagine we
have some type `Foo` that implements `Hash` and not `IterBytes`.  When
we are searching for implementations of `Hash` that apply to `Foo`, we
might chance upon the impl above (written in terms of `IterBytes`)
first.  In that case, we would see that if we instantiate the type
variable `A` to be the type `Foo`, then it matches the receiver
type---but we would also inherit the additional obligation of finding
an implementation of `IterBytes` for `Foo`.  Of course this search
would fail, and then we would (presumably) have to keep searching for
another impl that matches `Foo`.  This is what I mean by
backtracking---even though unification succeeded, we don't *know* that
the impl applies.

In general I am not interesting in supporting this use-case.  A better
way to implement this pattern would be to model the relationship using
inheritance and default methods.  For example, the definition of the
`IterBytes` trait would be:

```
trait IterBytes : Hash {
    pure fn hash_keyed(k0: u64, k1: u64) -> u64 {
        ...
    }
}
```

### What else can we crib from Haskell?

Browsing through the
[list of type class extensions in the Haskell's user manual][tce], I
have some thoughts about enabling something equivalent to "Class
method types".  That'll have to wait for another blog post.  We
already support many of the "relaxed rules" that are listed there
(such as "relaxed rules for the instance head" and "relaxed rules for
the instance contexts").  We will never support overlapping or
incoherent impls, I believe.

[tce]: http://www.haskell.org/ghc/docs/7.0.1/html/users_guide/type-class-extensions.html

### Appendix: Some implementation details

Here are some incomplete thoughts on how each algorithm will work.
These are intended more as notes for myself than anything else.  I
wanted to think out some of the issues in detail to be sure I wasn't
missing anything.

### Checking coherence, non-ambiguity, and overloading-freedom

The coherence check consists of two parts.  The first check ensures
that there are no cases of overlapping or overloadded impls.  To do
this, we iterate over all pairs of impls that target the same trait
`N` (regardless of the type parameters).  We replace all variables
bound on each impl with fresh type/region variables and try to unify
them.  Put more formally, if `T1` and `T2` are the self types of the
two impls, the check fails if there exists a substitution `S` such
that `S(T1) <: S(T2)` or `S(T2) <: S(T1)`.

Note that we must be careful about about trait inheritance.  It
is possible to have an impl for trait `N` where `N` extends `M`
that conflicts with an impl for trait `M`.

The second part of the coherence check ensures that there are no
"orphan" impls, to use Haskell-speak.  The orphan check reports an
error for any impl that does not meet (at least) one of the two
following criteria:

- the trait `N` is declared in the current crate;
- the self type `T` is either a nominal type declared in the current
  crate or an arity-1 type constructor whose argument (transitively)
  is declared in the current crate (e.g., `Foo`, `@Foo`, `~[Foo]`,
  or---for that matter---`~[@Foo]`, where `Foo` is declared in the
  current crate).

### Checking a bounded type parameter

When a type variable `X: N<U1...Un>` is bound to a type `T`, we must
ensure that `T` implements the trait `N<U1...Un>`.  To do so we
iterate through all implementations associated with the trait `N`,
instantiate their bound variables, and attempt to unify their self
type `Ts` with `T`.  If this unification is successful (formally, if
there exists a substitution `S` where `T <: S Ts`), then we must check
that:

1. the trait type `N<V1...Vn>` associated with the impl is a subtype
   of `N<U1...Un>` (formally, that `N<S V1...S Vn> <: N<U1...Un>`).
2. the bounds associated with the bound variables on the impl are
   themselves satisfied.

Note that the non-ambiguity check guarantees us that at most one trait
will have a self type that is unifiable with `T`.  Therefore, we do
not need to consider backtracking should property (2) above not hold.

### Checking a method call

Checking a call to a trait method is much like checking a bounded type
parameter.  If we find a call `a.m(...)`, and `m()` is defined on an
in-scope trait `T`, then we can find all implementations of `T`.  For
each implementation, we instantiate the bound variables to yield a
self-type.  The procedure is basically identical.

### Notes on F-bounds

I would like to support F-bounded polymorphism, meaning that the bound
of a type parameter `X` may refer to `X`.  For example, something like
`X: ComparableTo<X>` is legal.  In Rust, F-bounds are not needed as
frequently as you might think due to the special `self` type available
in every trait, but they can still play a role.  Today I think our
implementation does not support F-bounds but that is a shortcoming we
should correct.  As it happens, I do not believe this adds an
particular difficulty; you can implement it in the "usual way".

Just to spell out one particular such case for reference, imagine a
trait and impl pair such as:

    trait Foo<A: Foo<A>> { ... }
    impl int: Foo<int> { ... }
    
In this case, while sanity checking the `impl` declaration we would
see that `int` is used as the value for `Foo`'s type parameter, and
hence need to validate that, yes, `int` does implement the trait
`Foo<int>`.  We do this simply by searching through the impls in
scope; we will find the impl `int: Foo<int>`.  But now we are not
checking the impl but rather using it and hence we can trust it to be
true to its word (coinduction FTW!), therefore we know that `int`
implements `Foo<int>` (presuming the whole program typechecks).
