---
layout: post
title: "Mutability idea retracted"
date: 2012-05-30 18:47
comments: true
categories: [Rust]
---

I have been thinking a bit more about the
[approach to mutability I recently discussed][mut].  It seemed a bit
too good to be true (too clean) and I think I've realized a problem.

[mut]: blog/2012/05/28/moving-mutability-into-the-type/

The problem derives from my definition of types:

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

The interesting case is that of a type variable, denoted as `X`.  I
grouped type variables under the heading of "unqualified types".  But
this is of course incorrect, they are not unqualified types.  They can
map to a qualified type (in fact, that's the whole point of this
exercise).  So really the hierarchy ought to be:

    T = Q U
      | X
    Q = mut | const | imm
    U = [T]
      | @T
      | &T
      | { (f : T)* }
      | int
      | uint
      | ...
      
Now, the problem with this is that the meaning of a function
definition like this is unclear:

    fn set<A>(x: [mut A], i: uint, y: A) { x[i] = y; }
    
In fact, this definition does not fit the type grammar I gave.  This
is because `A` is a `T` but in the type `[mut A]` it appears where a
`U` is expected.  The same scenario kind of crops up with local
variables.  But I think we would like to be able to write a function
like `set()` (although an alternative might be to make a `mut` kind
and write `<A:mut>`).  It's not obvious to me if the situation can be
salvaged.
