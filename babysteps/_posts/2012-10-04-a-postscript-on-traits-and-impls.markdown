---
layout: post
title: "A postscript on traits and impls"
date: 2012-10-04 16:45
comments: true
categories: [Rust, Traits]
---

I was thinking more about type classes as I walked down the street.
In my [prior post][pp] I wrote that the rules I proposed resulted
in a system where traits loosely fit the following Haskell template:

     class C self a ... z | self -> a ... z where ...

However, I gave two caveats.  The first was that due to subtyping we
cannot say that one type precisely determines another, but only that
it puts a bound.  The second was that, in any given impl, the value of
`a ... z` may be a type parameter which does not appear in the `self`
type.  I think I understated the importance of this second caveat.
For example, consider the example I gave for simulating overloading:

```
trait Add<R,S>  { pure fn add(&self, rhs: &R) -> S;  }
trait IntRhs<S> { pure fn add_to_int(&self, lhs: int) -> S; }
impl<S, R: IntRhs<S>> int: Add<R, S> { ... }
```

This impl declaration essentially says "when `self` is `int`, the type
parameter `R` may be any type which implements `IntRhs`".  Moreover,
in this case, the `self` type does not constrain the parameter `S` at
all---that constraint is derived purely from `R`.

In other words, while overloading-freedom does mean that the impl
which will be used is purely determined by `self`, it does not mean
that `self` alone determines the value of all the other trait
parameters, as my Haskell analogy implied.  It's more accurate to say
that the `self` type determines a (possibly empty) set of bounds that
will be imposed on the other type parameters.  These bounds can take
the form of subtyping bounds (lower- or upper-bounds, or both) or
trait bounds.  

[pp]: {{ site.baseurl }}/blog/2012/10/04/refining-traits-slash-impls/
