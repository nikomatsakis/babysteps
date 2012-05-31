---
layout: post
title: "Mutability"
date: 2012-05-31 10:32
comments: true
categories: [Rust]
---

OK, I've been thinking more about the mutability issue and I think
I have found a formulation that I am happy with.  The basic idea is
that we refactor types like so:

    T = M T
      | X
      | @T
      | ~T
      | [T]
      | {(f:T)*}
      | int
      | uint
      | ...
    M = mut | const | imm
    
This no doubt looks similar to some of my other permutations.  The key
difference is that before I separated qualified and unqualified types.
This was intended to aid with inference, but in fact it was getting me
into trouble.  I realize now there is a different way to solve the
inference problem.  But first let me back and explain what inference
problem I am concerned about.

### Inferring in the face of mutability

One of the annoying parts about moving mutability into the type
is that if you have a piece of code like this:

    fn foo(v: [mut int]) {
        let x = v[0];
        ...
    }
    
then a naive inference algorithm would assign `x` the type of the
contents of `v`, `mut int`.  But this is not what we want.  We want
just `int` (i.e., immutable int).  The problem is that, in general,
making these kinds of imperative-sounding decisions ("if there is a
mut qualifier, remove it") within the inference engine is nigh
impossible, because we may not know what types we are dealing with.
One or both types can be type variables that will only be fully
resolved later.

Before I intended to sidestep this by saying that the type of `x` was
composed of a mutability qualifier, which we know up front, and the
unqualified part of the type, which we take from the right-hand-side.
This unqualified part might be an unresolved type variable.  But this
doesn't work out.

Now I realize an alternate route.  Let `R` be the type of the
right-hand side in an assignment (`mut int`, in this case).  Then the
type of the variable on the left-hand-side is just `imm R`.  Now, if
we expect that out, we get `imm mut int`.  The meaning of this is that
the outermost qualifier overrides the others, so this is equivalent to
`imm int`.

Of course all this business with multiple qualifiers and so forth is
transparent to the end user of the language.  That's just how the type
checker internally deals with things.

### "But wait, multiple qualifiers?  Isn't that... wrong?"

Well, I papered over it before, but it will always be necessary at
some level to allow outer qualifiers to override the contents of inner
qualifiers.  Imagine a generic function, for example:

    fn fold<X,Y>(v: [X], y: Y, f: fn(Y, X) -> Y) {
        let mut y = y;
        for v.each { |e|
            y = f(y, e);
        }
        ret y;
    }
    
Here the type of `y` is `mut Y`---when `Y` is expanded to a full type,
it may have mutability qualifiers of its own.  This would require us
to override them with the outer mutability.

This is akin to the way that immutable fields in a record are not, in
fact, immutable if the record itself is embedded in a mutable
location:

    let mut x = {f: 3};
    let y = &const f.x;
    assert *y == 3; // value starts as 3...
    x = {f: 4};     // ...and is overwritten to be 4.
    assert *y == 4; // same address, different value
    
(You can see that the compiler is aware that `f.x` is mutable; that's
why I had to write `&const f.x` and not just `&f.x`.  In fact, the
compiler will allow us to write `x.f = 4` directly.)

### "To be honest, I'm not comfortable with `mut int` as type."

In comments, gasche has [pointed out][g] that `mut int` is not especially
meaningful as a type. He is not wrong in this: if you think of types
as describing values, then mutability has no part in it.  However, I
think that even the type system as we desribe it today carries this
contradiction in it.  The type `{mut f: int}` also describes a value.
The `mut` qualifier on the field `f` is only meaningful when the value
is stored into a location in memory: as I pointed out in a previous
post, it is in fact useful to allow the mut qualifier to be
disregarded and to "freeze" the record.

[g]: http://smallcultfollowing.com/babysteps/blog/2012/05/28/moving-mutability-into-the-type/#comment-540838367

I think it is more useful to think of types in Rust (and any
imperative language) as describing the types and qualities of
*memory*.  So `mut int` is "an integer stored in mutable memory".
Mutability qualifiers are thus not particularly interesting in the
return type of a function (except with pointers, of course).

### Doesn't this system allow for type aliases?

The big change in my mind from previous incarnations is the presence
of `imm int` as a type.  I had always thought of the types `mut T` and
`const T`, but just assumed immutability would be indicated by the
absence of any qualifier.  But I think it's useful to make it possible
to specify immutability explicitly so that you can override other
qualifiers.

This will complicate the unification algorithm, naturally.  I am not
sure precisely how much, to be honest.  I have to tinker with it to
see.

But it seems like, inference aside, this scheme allows for the holy
grail of dealing uniformly with mutability without introducing
functions that are parameterized by mutability qualifiers.

### Maybe we should just introduce mutability qualifiers?

It is an option.  It doesn't even have to be that bad.  We could
probably replace `const` altogether with a parametric mutability
qualifier `mut?` (or some such thing).  Then you could write:

    fn each<A>(v: [mut? A], f: fn(&mut? A) -> bool)
    
Here, all uses of `mut?` imply the same parametric mutability.  That
is, if the vector is mutable, then the function type expects a mutable
pointer.  Javari's experiments used a system like this (`@PolyRead`)
and they found that one such qualifier was sufficient.  But a signature
like that certainly feels a lot more complex than this one:

    fn each<A>(v: [A], f: fn(&A) -> bool)
    
which I think is what everybody writes at first before realizing that,
today, it doesn't cover all the cases (e.g., mutable vectors).

### Maybe we should just do nothing?

If we leave things as they are, then effectively all higher-order
functions over vectors will only operate on immutable vectors.  With
some minor tweaks (which we should perhaps do anyhow), we could also
allow them to be used with mutable vectors if those vectors are in a
local variable (borrow check would guarantee that the vector is not
mutated during the call).  If you really want a mutable vector *and*
you want to use it with higher-order functions, you can always "fake"
a mutable vector by using a record with a single mutable field
`[{mut f: int}]` in place of `[mut int]`.
