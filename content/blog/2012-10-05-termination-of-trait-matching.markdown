---
layout: post
title: "Termination of trait matching"
date: 2012-10-05T10:55:00Z
comments: true
categories: [Rust, Traits]
---

So, the condition that was supposed to ensure termination in my
previous post is most certainly wrong.  The idea was to prevent
tautological impls like the following:

    impl<A: Foo> A: Foo { ... }
    
Such impls, given a naive algorithm, would loop infinitely trying to
decide if a type `T` implemented `Foo`.  You can imagine: it would
ask, "does `T` implement `Foo`? Well, if I map `A` to `T` then this
impl applies, but only if `T` implements `Foo`. Hmm.  That puts me
back where I started from.  Oh well, better try it again!" Obviously a
less naive algorithm could keep a stack and then fail to execute, but
it was precisely the logic of this stack that I was trying to capture
in that restriction.

Just as obviously, the restriction I proposed is insufficient.  One
could write:

    impl<A: Bar> A: Foo { ... }
    impl<A: Foo> A: Bar { ... }
    
This leads to the same scenario but violates no restriction.

Anyway, there are no conclusions in this post.  Just some intermediate
thoughts along the way I wanted to jot down.

<!-- more -->

### What is the algorithm, anyway?

In its full gory detail, the naive algorithm is something like this:

- `fn Implements(Tr, N, Tn*) -> bool`:
  - "Does the type `Tr` implement `N<Tn*>`?  If so, here is the impl that proves it"
  - Here I am ignoring type parameters and trait instances
  - Is `Tr <: N<Tn*>`?
    - Then `Tr` is a trait instance
    - Does `N` refer to the `self` type in a method parameter or return type?
      - No: return true
        -> Note: in the future, we could allow it in the case where it appears only in
           return types by wrapping the return value
  - Is `Tr` a bounded parameter type?
    - Is `N<Tn*>` (or a subtype of `N<Tn*>`) among the bounds?
      - Yes: return true
  - For each impl `Impl = impl<VD*> Ts: M<Tm*>`:
    - Is there a substitution `S` for the variables declared in `VD*` such that
      `Tr <: S Ts` and `N<Tn*> <: M<S Tm*>`?
      - For each variable declaration `VD = X: M<...>*`:
        - Let `Ta = S X` be the type inferred for this variable
        - For each of the bounds `M<Tb*>` in `VD`:
          - `Implements(Ta, M, S Tb*)`?
            - No: return false
        - return true

You can more or less ignore the first two cases and force on the final
one.  Also, here I am assuming another requirement that I forgot to
write down in my previous post: all instance variables declared on an
impl must appear in either the self type, the trait type, or both.
That ensures that we can use inference to find the substitution `S`.

Clearly the dangerous case for termination is the recursive call to
`Implements()` that occurs when checking the bounds.  We must somehow
guarantee that this call will not itself generate an infinite number
of subcalls.

### Simple technique for termination

One simple condition that guarantees termination is to require that
the variables declared on the impl appear *within* the self type (not
*as the self type*, as in these examples).  That means that these impls
would be fine:

```
impl<X: ...> Foo<X>: N<...> { ... }
impl<X: ...> ~[X]: N<...> { ... }
impl<X: ...> @X: N<...> { ... }
```
    
But the following impls are illegal because the type variable `X` is
not a part of the self type:

```
// Here X *is* the self type, not a *part* of it:
impl<X: N<...>> X: N<...> { ... }
// Here X *is* just unrelated to the type `int`:
impl<X: N<...>> int: N<...> { ... }
```

Given this requirement, one can make an inductive argument based on
the depth of the receiver type `Tr`.  If `Tr` has depth 1 (such as
with the type `int`), then the impl can take no type parameters, so
there are no recursive calls.  In every other case, the recursive call
occurs on the value of some type variable, the depth of the type bound
to each type variable is always less than the self type, hence they
hold by the inductive hypothesis.
    
This is in fact very similar to
[the requirement that is used in Haskell 98][haskell], which requires
that all variables in the "instance assertion" must appear in the
"instance head".  GHC now supports a flag `-XFlexibleContexts` to
loosen this rule.  It then imposes some, well, different constraints.

[haskell]: http://www.haskell.org/ghc/docs/7.0.1/html/users_guide/type-class-extensions.html#instance-decls

### Haskell's rules

Given the `-XFlexibleContexts` flag, Haskell imposes what it calls the
Paterson Conditions (there is one other set of conditions as well that
have to do with functional dependencies):

- For each assertion in the context
  - No type variable has more occurrences in the assertion than in the head
  - The assertion has fewer constructors and variables (taken together and counting repetitions) than the head
  
I can vaguely imagine the inductive hypothesis that these conditions
are enforcing, but I don't yet have a real understanding of these
rules, and certainly not any sort of intuitive feeling.  I'll write
another post once I've grokked this better.  I think I've exceeded my
quota for thinking about this at the moment.
