---
layout: post
title: "Moving mutability into the type"
date: 2012-05-28 15:17
comments: true
categories: [Rust, PL, Mutability]
---

I am dissatisfied with how mutability is treated in the Rust type
system.  The current system is that a *type* is not prefixed mutable;
rather, lvalues are.  That is, a type `T` is defined like so:

    T = [M T]
      | @ M T
      | & M T
      | { (M f : T)* }
      | int
      | uint
      | ...
    M = mut | const | (imm)

Note that there is no type `mut int` (a mutable integer).  This is
logical enough; such a type has little inherent meaning: an integer is
a value, it is not mutable or immutable.

Mutability only appears whenever there is an lvalue: that is, a
location in memory that might potentially be overwritten.  So you have
a type like `@int`, which means a "pointer to immutable,
garbage-collected memory that contains an integer" (immutable is the
default).  Similarly, `@mut int` is a pointer to mutable, gc'd memory
that contains an integer.

This system is logical but it has several shortcomings in practice.  I
think I have a proposal that addresses them in a reasonable way.  I'll
first go over the shortcomings I hope to address and then discuss my
solution.

### Shortcoming #1: Parameterizing over mutability is not possible

Because mutability is not part of the type, if I write a generic
function like this:

    fn each<A>(v: [A], f: fn(&A) -> bool) { ... }
    
I am in fact defining a function that allows iteration only over
*immutable arrays*.  The type `[A]` basically means "an array of
immutable instances of the type `A`".  But this is probably not what I
want; I would like to allow iteration over any array, regardless of
whether it is mutable or not.

Of course I could write two functions (`each` and `each_mut`).  But I
could also use the `const` type.  The `const` qualifier, borrowed from
C++, effectively means "read-only": that is, it may be used with
either mutable or immutable memory.  So, to be safe, you can only use
a `const` pointer for reading, but you can never rule out the
possibility that the memory that is pointed at might be modified by
somebody else.

`const` types sound good but in practice they are insufficient.  They
are particularly insufficient when we start combining vectors with
references.  To see why, let's look at how one might implement the
`each()` function with `const`:

    fn each<A>(v: [const A], f: fn(&A) -> bool) {
        let l = len(v);
        let mut i = 0u;
        while i < l {
            if !f(&v[i]) { ret; }
            i += 1u;
        }
    }
    
This function invokes the function `f()` with a reference to each
element of the vector in turn.  We use references to elements (that
is, the type `&A`) rather than passing the element itself because it
avoids the need to copy the element; in a language like Java, where
everything is passed by pointer and garbage collection is ubiquitous,
copies are no problem, but in Rust one tries to avoid
them---particularly when operating over generic types, where the cost
of the copy is unknown (copying a unique pointer, for example, could
involve an deep clone and hence an arbitrary number of allocations).

This function looks simple, but it would be in fact be rejected by the
Rust type checker.  The reason is that the type `&A` in fact indicates
that the memory is immutable: but we don't know that, we only know
that it is `const`.  To be correct, we have to write the following:

    fn each<A>(v: [const A], f: fn(&const A) -> bool) {
        // the rest is the same, basically
    }
    
Note that the function `f()` now expects a `&const A` pointer: that
is, a pointer to `const` memory.  Now, this might not seem like a big
problem, but in fact a `&const A` pointer is significantly less useful
than an `&A` pointer.

This is because there are many operations that are only legal on immutable
memory.  For example, if we have an `&option<int>`, we can write code
like:

    let x: &option<int> = ...;
    alt *x {
        none { ... }
        some(y) { ... }
    }

This is not especially safe with a `const` pointer.  The reason is
that the `alt` construct in Rust does not copy data out of `x`, as it
would in ML, but rather `y` is a pointer directly into the interior of
`x`.  This is very efficient, but for a `const` or `mut` pointer it is
unsafe, because someone might overwrite `*x` with `none`, and then
this pointer is invalid.  So, to `alt` over mutable memory you need
to use copies:

    let x: &const option<int> = ...;
    alt copy *x {
        none { ... }
        some(y) { ... }
    }
    
Similar concerns apply to unique pointers, which are freed as soon as
they are overwritten.

So, what we would like, is a way to write a function that uses an
immutable reference for an immutable vector, a mutable reference for
a mutable vector, a const reference for a const vector.  

### Shortcoming #2: There is no way to convert mutability

One of Rust's more powerful features is unique pointers.  Unique
pointers are useful for sending things betwen tasks, but there is more
we could do with them.  For example, if you have a `~mut int`, there
is no reason it could not be converted to a `~int`: after all, there
is only pointer to the memory in question, so we can change whether
the memory is mutable or not at will.  We already use this for
vectors, which are currently unique, in that we have `vec::from_mut()`
and `vec::to_mut()`.  But we could make this a more general
transformation.

For example, the following program ought to be legal:

    type rec = {mut f: int, mut g: int};
    type rec_frozen = {f: int, g: int};
    fn freeze(r: ~rec) -> ~rec_frozen { r }
    
In fact, this program could be legal even without the unique pointer,
if the record is passed by value:

    fn freeze(r: rec) -> rec_frozen { r }

### Proposal

I think we ought to move the mutability qualifiers away from lvalues
and into the types.  This means that internally the structure of our
types would be like this:

    T = Q U
    Q = mut | const | imm
    U = [T]
      | @T
      | &T
      | { (f : T)* }
      | X
      | int
      | uint
      | ...
      
Here, every type `T` consists of one or more mutability qualifiers `Q`
and an unqualified type `U`.  Although qualifiers are made mandatory,
in the syntax that users enter, an unqualified type without a
qualifier would of course be shorthand for an immutable version, as
today.

### Assigning vs subtyping

One of the tricky aspects of mutability/immutability is that clearly
there is no subtyping relation between `mut int` and `imm int`.  And
yet you would like code like the following to work:

    let vec: [mut int] = [mut 1, 2, 3];
    let t: int = vec[0];
    
In the new scheme, after all, the type of `vec[0]` is `mut int`, but
the type of the variable `t` is `int`.  So why is this assignment
legal?

The reason is that we distinguish between two types being *assignable*
and *subtyping*.  This is already necessary for handling region
pointers.  Basically, *assignability* would ignore interior and unique
mutability.  This means that `mut int` is assignable to `int` and
vice-versa.  But it also means that `{f: mut int, g: mut int}` is
assignable to to `{f: int, g: int}` and `~[mut int]` is assignable to
`~[int]` (and vice versa).  `@mut int` would not, however, be
assignable to `@int`.  This addresses shortcoming #2.

### Generic operations

Under this scheme, generic operations like those for vectors
"just work":

    fn each<A>(v: [A], f: fn(&A) -> bool) {
        let l = len(v);
        let mut i = 0u;
        while i < l {
            if !f(&v[i]) { ret; }
            i += 1u;
        }
    }

The mutability is no longer part of the vector but rather part of the
generic type `A`, so this same routine works for mutable, const, or
immutable vectors.

### Inference

The one tricky part to this scheme is inference.  Consider code
like the following:

    fn deref(x: [mut int]) -> int {
        let y = x[0];
        ret y;
    }

What type does `y` have?  Today it would have the type `int`, and this
is what we would like it to have; but if we are not careful, it will
end up the type `mut int`.  After all, that is the type of the rvalue,
and the type of a variable is generally unified with the type of its
initializer.  Basically, the assignability checks and unification
don't mix so well, because they require knowing the type of the rvalue
being assigned and the type of the lvalue being assigned to, and one
or both of those may be unknown.

I think we can solve this in a reasonable, best-effort way, much like
we approach inference in the face of subtyping.  We define the check
to operate over unqualified types `U`.  That is, we completely ignore
the mutability qualifier of the local variable and the rvalue.  If the
types are specified, we'll apply the full assignability relation, but
if there are type variables, we'll fall back to requiring subtyping.

Here is a case where this would fail:

    fn takes_mut_rec(x: {f: mut int}) {
        let y = x;
        wants_imm_rec(&y);
    }

    fn wants_imm_rec(x: &{f: int}) { ... }

Here, we will infer the type of `y` to `{f: mut int}`.  This will then
generate an error because `&{f: mut int}` is not assignable to the
type `&{f: int}` expects by `wants_imm_rec()`---that is, a pointer to
a record with mutable fields is not usable as a pointer to a record
with immutable fields. 

This is a failure of type inference because the following program,
which is the same except for an explicit type annotation, would be
perfectly legal:

    fn takes_mut_rec(x: {f: mut int}) {
        let y: {f: int} = x;
        wants_imm_rec(&y);
    }
    
(The assignment is legal because we copying `x` into the local
variable `y`, so we can declare the mutability of this new memory to
be whatever we like.)

I think this is acceptable, though. Inference need not be perfect in all
cases (indeed, it cannot be).
