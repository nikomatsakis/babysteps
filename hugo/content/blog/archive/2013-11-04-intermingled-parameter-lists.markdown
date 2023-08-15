---
categories:
- Rust
comments: true
date: "2013-11-04T00:00:00Z"
slug: intermingled-parameter-lists
title: Intermingled parameter lists, take 2
---

I got a lot of feedback on my post about
[intermingled parameter lists][ipl] -- most of it negative -- and I've
been thinking about the issue over the weekend. Truth is, I wasn't
terribly fond of the proposal myself -- making the position in the
list significant feels wrong -- but I felt it was the least bad of the
various options. However, I've had a change of heart, and thus have a
new "least bad" proposal.

The high-level summary of the plan is as follows:

- Parameters lists are not intermingled, instead we begin with some
  number of lifetime parameters and then some number of type
  parameters, as today.
- Lifetime parameters on fn items are considered late bound unless
  they appear within a type bound.
- When referencing a fn item (or any generic path), users would have
  the option of either (1) supplying values for no parameters at all;
  (2) only supplying values for type parameters; or (3) supplying
  values for both lifetime and type parameters.
- Users may always use `_` to have the compiler select a suitable
  default for the value of some type or type/lifetime parameter. This
  is equivalent to not supplying a value at all.
  
This plan is fully backwards compatible (all existing code retains its
existing meaning).

*Aside #1:* Some [good][c1] [arguments][c2] were advanced in favor of
making *all* lifetime parameters late bound and relying instead on
[higher-kinded types (HKT)][hkt] or some kind of explicit universal
quantification syntax instead. While both things -- and in particular,
HKT -- might be nice to have, I don't think that they fully eliminate
the need for early/late binding, as I will explain later.

*Aside #2:* I'd like to find a better name for early and late
binding. If there is a standard term for this sort of distinction, I
am not aware of it. I suspect this is because most languages whcih
feature universally quantified types support quantification over other
types -- it is much cleaner from a pure type system point-of-view --
and thus they do not have to discriminate between early and late
binding. The situation is also related to let polymorphism and the
distinction between *type schemes* and *types* in ML or Haskell, so
perhaps there is a related term I can borrow from there. It occurs to
me that it's also worth digging into the literature about type
erasure, as this distinction arises at least partly due to our use of
monomorphization as an implementation scheme. Anyway, suggestions for
better names or else other reading material welcome.

<!--more-->

### Prelude: How much is this likely to impact people?

I want to point out that the distinction between early and late bound
lifetime parameters won't matter so much in regular usage. In
particular, the only time that the sort of binding comes into play is
when functions are used as values.

### Example 1: A late-bound lifetime parameter

Let's begin with the `get_index` early from my [earlier post][ipl]:

    fn get_index<'l, T>(v: &'l [T], index: uint) -> &'l T {
        &v[index]
    }

In this case, the lifetime `'l` would be late-bound, because it does
not appear in any type bounds (in fact, there are no type bounds at
all).

As today, when users take the value of `get_index`, there is no need
to specify explicit values for any of the parameters. This simply
means that the compiler will use inference to find the values it
needs.

    let a = get_index; // use inference for everything
    a([3]);

In this case, we would infer that the type `T` should be `int`, and
hence that the type of `a` is `<'l> fn(&'l [int], uint) -> &'l int`.
Note that the type of `a` is generic with respect to the lifetime
`'l`. That is, we could call `a` many times, supply slices with
different lifetimes, and each time the return value would have the
same lifetime as the input.

The proposal also adds the `_` specification for types/lifetimes,
which makes it possible to make the defaults explicit:

    let a = get_index;         // implicitly use inference for everything
    let c = get_index::<_>;    // explicitly use inference for types,
                               // implicitly use inference for lifetimes
    let b = get_index::<_, _>; // explicitly use inference for everything

As you can see, users can choose between supplying values for all
parameters (`b`) or just for type parameters (`c`). The compiler uses
the number of values provided to determine the distinction.

Thanks to `_`, it is also possible to specify values for *just some*
of the parameters. If we did not want to rely on inference to
determine that `T` was `int` but instead wanted to specify it
manually, we might write:
        
    let d = get_index::<_, int>; // just specify types
    let e = get_index::<int>; // equivalent to above
    
In all of these previous cases, no concrete value was given for the
lifetime parameter `'l`. Because `'l` is late-bound, this results in a
final fn type that is generic with respect to `'l`. If we wish,
though, we could specify a specific lifetime as well:
    
    let f = get_index::<'static, int>; // specify all values manually

`f` would have the type `fn(&'static [int], uint) -> &'static int`.
Unlike the other examples, `f` could only be used with slices of
static lifetime.

*An aside:* the subtyping rules for universally quantified functions
also specify that a generic type like `<'a> fn(&'a int)` is a subtype
of a precise type `fn(&'static int)`, exactly because we could
transform the former into the latter by substituting `'static` for
`'a`. Simon Peyton-Jones et al. have written a
[wonderfully readable, but rather long, paper][spj] on this topic if
you'd like to read more.

### Example 2: An early-bound lifetime parameter

I'm going to use a slightly different example of an early-bound
lifetime parameter than I gave last time, so that I can explain things
a bit more clearly. Let's turn to a familiar friend, the `Iterator`
trait (amazing how iteration manages to be simultaneously the most
pedestrian topic imaginable but also so rich with respect to exposing
weaknesses in type systems):

    trait Iterator<A> {
        fn next(&mut self) -> Option<A>;
    }

Now, imagine I want to write a function that iterates over some
values and pulls out the first meeting some criteria or other:

    fn first<'a, I:Iterator<&'a Value>>(i: I) -> Option<&'a Value> {
        for f in i {
            if some_condition_or_other_holds(f) {
                return Some(f);
            }
        }
        return None;
    }

Unlike the previous case, the lifetime parameter `'a` appears within
the type bound for `I`, which means that it is *early bound*. In case
you forgot from my previous post, this means that we cannot wait until
the fn is called to decide what lifetime to use for `'a`, but
rather must choose one immediately.

*Review:* The reason for this is that, because we don't support types
that are universally quantified over other types, we must select
concrete values for all type parameters in order to create the type
for (some specific reference to) `first`. We will then need to check
that the value we chose for `I` meets the bound `Iterator<&'a Value>`,
which implies that we must know a specific value for `'a`. (Some
commentors argued that [HKT][c1] or [skolemization][c2] provides an
alternative; I disagree, as I'll explain below.)

In any case, all this machinery is mostly invisible when you are using
Rust because the compiler provides defaults. Under this proposal,
all of these different ways of referring to `first` would be equivalent:

    let a = first;         // all implicit
    let b = first::<_>;    // types explicit, lifetimes implicit
    let c = first::<_,_>;  // all explicit

The catch though is that, because `'a` is early bound, the type of
first is not going to be universally quantified over `'a`, but rather
it'll refer to some concrete lifetime. In this case, the type would be
`fn(Foo) -> Option<&'Bar>` where `Foo` and `'Bar` are the values we
infer for `I` and `'a` respectively.

As before, it is also an option to partially specify either the lifetime
or the types. For example, I could do:

    let d = first::<'static, _>; // Don't specify iterator type, just lifetime
    let e = first::<_, Foo>;     // Just specify iterator type

### Can we avoid distinguishing early- and late-bound lifetime parameters at all?

It was proposed that we could use HKT to avoid the need for
early-bound lifetime parameters at all. Unfortunately, I don't think
this works. The basic idea would be to replace any type parameter that
uses a lifetime with a higher-kinded type parameter instead, so that
we don't have to reference the lifetime parameter from within the type
bound. This is easier to explain by example. The function `first` that
I showed before was defined like:

    fn first<'a, I:Iterator<&'a Value>>(i: I)
                                        -> Option<&'a Value> {...}
    
Under this HKT-based approach, it would instead be defined as follows
(I've highlighted the key differences):

    fn first<'a, I<'b>:Iterator<&'b Value>>(i: I<'a>)
              /* ^~~~~                         ^~~~~ */
                                            -> Option<&'a Value> {...}

You can see that by making `I` take a lifetime parameter, I've severed
the inherent connection between the bound of `I` and `'a`. Instead,
that connection is recreated in the parameter list with `I<'a>`.

I've done a lot of hand-waving in this example. I think that Haskell's
notion of HKT's is significantly more restrictive than this, in that
it is sensitive to ordering, and one would be expected to provide
bounds for `I` that are of kind `LT -> *` (note that `Iterator` alone
is of kind `* -> *`, so I guess you'd need an adapter). There are good
reasons for these restrictions, it makes inference and type class
matching much more tractable. But let's leave all that aside for the
moment (besides, I need to inform myself more deeply on this topic,
it's quite possible that I am out of date) and assume the example
worked as written, as there is a more fundamental problem.

The fundamental problem is that for this approach to work, the
`Iterator` protocol *must* be implemented in a way that is completely
generic with respect to the lifetime. But this may not apply to all
types. This is because we must validate `I` against `Iterator` without
knowing what lifetimes it may be applied to. For example, imagine I
had a type `Alphabet` that permitted iteration over some pre-defined,
static set of values:

    struct Alphabet { index: uint }
    
    static v0: Value = ...;
    static v1: Value = ...;
    
    impl Iterator<&'static Value> for Alphabet {
        fn next(&mut self) -> Option<&'static value> {
            let i = self.index;
            self.index += 1;
            match i {
                0 => Some(&v0),
                1 => Some(&v1),
                _ => None,
            }
        }
    }
    
This is an example of an impl that is not defined generally with
respect to all lifetimes. Rather, it is defined with respect to *one
specific lifetime*. For this reason, `Alphabet` would not
(necessarily, anyhow) be usable as a binding for the type parameter
`I` in our example. This is a special case of the phenomenon that
Simon Peyton-Jones and Mark Jones describe in section 2.2
("Overloading with constrained parameters") of their paper covering
the design space for [multi-parameter type classes][mptc]. In short,
higher-kinded types are only applicable for a type-class when you can
be sure that every instance of the type-class will be applicable to
any type (resp. lifetime).

That said, in this specific case, as the data is `'static`, and
`'static` exceeds all other lifetimes, we could have created an impl
that is generic with respect to any impl. This would not always be the
case, though. For example, imagine a trait like:

    trait<'a> PipelineSink {
        fn consume(x: Data<'a>);
    }
    
One example of a `PipelineSink` might be one that sends messages to
another task. Such messages would have to include only `'static` data
to be sendable.

    struct TaskSender { chan: Channel<Data<'static>> }
    
    impl PipelineSink<'static> for TaskSender {
        fn consume(x: Data<'static>) {
            self.chan.send(x);
        }
    }
    
In this case, it would not be possible to create a generic `impl`.

### Detailed rules

The more detailed rules for my proposal are as follows:

- Parameter lists consists of some number of lifetimes and some
  number of types (i.e., the two are *not* intermingled, for now anyway).
- Lifetime parameters on fns or methods that appear within a type
  bound are considered *early bound*. Those that do not are considered
  *late bound*.
- Whenever a type- or lifetime-parameterized path is referenced, users
  have the option of either:
  - supplying values for *all* parameters, both lifetime and type; or,
  - supplying values for *only* the type parameters, in which case
    defaults/inference will be used for the lifetimes; or,
  - supplying no values at all, in which case defaults/inference will be used
    for all parameteters.
- Defaults, whether explicit or implicit, are only permitted in the
  following contexts:
  - In a function signature, values for lifetimes parameters may be
    defaulted.  All such lifetimes will occur in types or trait
    references, and hence are early bound. They are replaced by
    anonymous bound lifetime parameters as today.
    - If these missing values appear in the list of arguments, the resulting
      parameters will be late bound. If the missing values appear in within
      a type bound, the resulting parameters will be early bound.
  - In a function body, values for types may be defaulted. They will be
    replaced with fresh type variable.
  - In a function body, values for lifetimes may be defaulted.
    - If the lifetime parameter is early bound, a fresh lifetime
      variable is substituted.
    - If the lifetime parameter is late bound, then it must appear as
      a parameter to a fn item, and results in a bound parameter
      scoped to the resulting fn type.
      
[ipl]: {{ site.baseurl }}/blog/2013/10/29/intermingled-parameter-lists/
[c1]: {{ site.baseurl }}/blog/2013/10/29/intermingled-parameter-lists/#comment-1103218392
[c2]: {{ site.baseurl }}/blog/2013/10/29/intermingled-parameter-lists/#comment-1103344213
[spj]: http://research.microsoft.com/en-us/um/people/simonpj/papers/higher-rank/
[hkt]: http://en.wikipedia.org/wiki/Kind_%28type_theory%29
[skol]: http://demonstrations.wolfram.com/Skolemization/
[atc]: http://research.microsoft.com/apps/pubs/default.aspx?id=67485
[mptc]: http://research.microsoft.com/en-us/um/people/simonpj/papers/type-class-design-space/
