---
layout: post
title: "An experimental new type inference scheme for Rust"
date: 2014-07-09T10:08:00Z
comments: true
categories: [Rust]
---

While on vacation, I've been working on an alternate type inference
scheme for rustc. (Actually, I got it 99% working on the plane, and
have been slowly poking at it ever since.) This scheme simplifies the
code of the type inferencer dramatically and (I think) helps to meet
our intutions (as I will explain). It is however somewhat less
flexible than the existing inference scheme, though all of rustc and
all the libraries compile without any changes. The scheme will (I
believe) make it much simpler to implement to proper one-way matching
for traits (explained later).

*Note:* Changing the type inference scheme doesn't really mean much to
end users. Roughly the same set of Rust code still compiles. So this
post is really mostly of interest to rustc implementors.

### The new scheme in a nutshell

The new scheme is fairly simple. It is based on the observation that
most subtyping in Rust arises from lifetimes (though the scheme is
extensible to other possible kinds of subtyping, e.g. virtual
structs). It abandons unification and the H-M infrastructure and takes
a different approach: when a type variable `V` is first related to
some type `T`, we don't set the value of `V` to `T` directly. Instead,
we say that `V` is equal to some type `U` where `U` is derived by
replacing all lifetimes in `T` with lifetime variables. We then relate
`T` and `U` appropriately.

Let me give an example. Here are two variables whose type must be
inferred:

    'a: { // 'a --> name of block's lifetime
        let x = 3;
        let y = &x;
        ...
    }

Let's say that the type of `x` is `$X` and the type of `y` is `$Y`,
where `$X` and `$Y` are both inference variables. In that case, the
first assignment generates the constraint that `int <: $X` and the
second generates the constraint that `&'a $X <: $Y`. To resolve the
first constraint, we would set `$X` directly to `int`. This is because
there are no lifetimes in the type `int`. To resolve the second
constraint, we would set `$Y` to `&'0 int` -- here `'0` represents a
fresh lifetime variable. We would then say that `&'a int <: &'0 int`,
which in turn implies that `'0 <= 'a`. After lifetime inference is
complete, the types of `x` and `y` would be `int` and `&'a int` as
expected.

Without unification, you might wonder what happens when two type
variables are related that have not yet been associated with any
concrete type. This is actually somewhat challenging to engineer, but
it certainly does happen. For example, there might be some code like:

    let mut x;        // type: $X
    let mut y = None; // type: Option<$0>
    
    loop {
        if y.is_some() {
            x = y.unwrap();
            ...
        }
        ...
    }

Here, at the point where we process `x = y.unwrap()`, we do not yet
know the values of either `$X` or `$0`. We can say that the type of
`y.unwrap()` will be `$0` but we must now process the constrint that
`$0 <: $X`. We do this by simply keeping a list of outstanding
constraints. So neither `$0` nor `$X` would (yet) be assigned a
specific type, but we'd remember that they were related. Then, later,
when either `$0` or `$X` *is* set to some specific type `T`, we can go
ahead and instantiate the other with `U`, where `U` is again derived
from `T` by replacing all lifetimes with lifetime variables. Then we
can relate `T` and `U` appropriately.

If we wanted to extend the scheme to handle more kinds of inference
beyond lifetimes, it can be done by adding new kinds of inference
variables. For example, if we wanted to support subtyping between
structs, we might add struct variables.

<!-- more -->

### What advantages does this scheme have to offer?

The primary advantage of this scheme is that it is easier to think
about for us compiler engineers. Every type variable is either *set*
-- in which case its type is known precisely -- or *unset* -- in which
case its type is not known at all. In the current scheme, we track a
lower- and upper-bound over time. This makes it hard to know just how
much is really known about a type. Certainly I know that when I think
about inference I still think of the state of a variable as a binary
thing, even though I know that really it's something which evolves.

What prompted me to consider this redesign was the need to support
*one-way matching* as part of trait resolution. One-way matching is
basically a way of saying: is there any substitution `S` such that `T
<: S(U)` (whereas normal matching searches for a substitution applied
to both sides, like `S(T) <: S(U)`).

One-way matching is very complicated to support in the current
inference scheme: after all, if there are type variables that appear
in `T` or `U` which are partially constrained, we only know *bounds*
on their eventual type. In practice, these bounds actually tell us a
lot: for example, if a type variable has a lower bound of `int`, it
actually tells us that the type variable *is* `int`, since in Rust's
type system there are no super- of sub-types of `int`. However,
encoding this sort of knowledge is rather complex -- and ultimately
amounts to precisely the same thing as this *new* inference scheme.

Another advantage is that there are various places in the Rust's type
checker whether we query the current state of a type variable and make
decisions as a result. For example, when processing `*x`, if the type
of `x` is a type variable `T`, we would want to know the current state
of `T` -- is `T` known to be something inherent derefable (like `&U`
or `&mut U`) or a struct that must implement the `Deref` trait? The
current APIs for doing this bother me because they expose the bounds
of `U` -- but those bounds can change over time. This seems "risky" to
me, since it's only sound for us to examine those bounds if we either
(a) freeze the type of `T` or (b) are certain that we examine
properties of the bound that will not change. This problem does not
exist in the new inference scheme: anything that might change over
time is abstracted into a new inference variable of its own.

### What are the disadvantages?

One form of subtyping that exists in Rust is not amenable to this
inference. It has to do with universal quantification and function
types. Function types that are "more polymorphic" can be subtypes of
functions that are "less polymorphic". For example, if I have a
function type like `<'a> fn(&'a T) -> &'a uint`, this indicates a
function that takes a reference to `T` with any lifetime `'a` and
returns a reference to a uint with that same lifetime. This is a
*subtype* of the function type `fn(&'b T) -> &'b uint`. While these
two function types look similar, they are quite different: the former
accepts a reference with *any* lifetime but the latter accepts only a
reference with the specific lifetime `'b`.

What this means is that today if you have a variable that is assigned
many times from functions with varying amounts of polymorphism,
we will generally infer its type correctly:

    fn example<'b>(..) {
        let foo: <'a> |&'a T| -> &'a int = ...;
        let bar: |&'b T| -> &'b int = ...;
        
        let mut v;
        v = foo;
        v = bar;
        // type of v is inferred to be |&'b T| -> &'b int
    }
    
However, this will not work in the newer scheme. Type ascription of
some form would be required. As you can imagine, this is not a very
.common problem, and it did not arise in any existing code.

(I believe that there are situations which the newer scheme infers
correct types and the older scheme will fail to compile; however, I
was unable to come up with a good example.)

### How does it perform?

I haven't done extensive measurements. The newer scheme creates a lot
of region variables. It seems to perform roughly the same as the older
scheme, perhaps a bit slower -- optimizing region inference may be
able to help.



