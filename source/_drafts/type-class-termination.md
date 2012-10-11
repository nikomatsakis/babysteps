Talking with Dave Herman, I realized there was a bug in my earlier blog post.
The requirement intended to guarantee termination was not strong enough.
I believe the correct requirement is this:

- For every type variable `X` declared on the impl, either `X` must
  appear as an argument to the self type (note: not the self type
  itself) or the bounds of `X` may not refer (directly or indirectly)
  to the trait being implemented.

Put less formally, all of the following impls are fine because
the type variable `X` appears as part of the self type:

```
impl<X: ...> Foo<X>: N<...> { ... }
impl<X: ...> ~[X]: N<...> { ... }
impl<X: ...> @X: N<...> { ... }
```
    
However, the following impls are illegal because the type
variable `X` is not a part of the self type *and* its bounds
refer to the trait `N` that being implemented:

```
// Here X *is* the self type, not a *part* of it:
impl<X: N<...>> X: N<...> { ... }
impl<X: N<...>> int: N<...> { ... }
```

What follows is a semi-formal description of the algorithm and an
argument that it does indeed terminate.

<!-- more -->

### The algorithm

First, the ground definitions. Impls have the form:

    Impl = impl<VD*> Ts: N<...> { ... }
    
Here, `Ts` is the self type, `N` is a trait name, and `VD*` is zero or
more variable declarations of the form:

    VD = X: M<...>*
    
Here, `X` is the variable name and `M<...>*` indicates zero or more
trait references.

Now, the function we are defining is `Applies(Impl, Tr, Ta*) -> bool`.
Given an impl, the type `Tr` of the receiver, and types `Ta*`
corresponding to the bound type variables `VD*`, the function returns
true if the impl applies to the given receiver `Tr`?

*An aside:* You might expect that given the "overloading-free"
property I was talking about, we would not need to be given the types
`Ta*` in order to answer this question.  This is not correct, because
we must validate that each of the type arguments meets its declared
bounds.  Overloading-free does however allow us to answer a slightly
different question, which is something like "Given an impl and the
type `Tr` of the receiver, could any other impl apply to the receiver
besides the given impl?" This implies that we don't need to think
about backtracking.

The algorithm is something like this:

- Check whether `Tr <: [X* -> Ta*] Ts`.  If no, the answer is no.
- For each corresponding variable declaration `VD = X: M<...>*` and type argument `Ta`:
  - For each of the bounds `M<Tb*>` in `VD`:
    - Check that there exists an impl `Impl` of `M` such that 
      `Applies(Impl, Ta, [X* -> Ta*] Tb*)`.

So, why do I believe this terminates.  The argument is based on
induction (that being about the thing I remember from [6.046][6046]).
Basically we must show that in the recursive invocation of `Applies()`
some "quantity" is getting "smaller". Ok, here comes some hand-waving.
If `Ta` is a subpart of the self type `Ts` (and hence `Tr`), then the
receiver type is getting smaller.  Otherwise, 

[6046]: http://ocw.mit.edu/courses/electrical-engineering-and-computer-science/6-046j-introduction-to-algorithms-sma-5503-fall-2005/

