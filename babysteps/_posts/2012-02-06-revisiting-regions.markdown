---
layout: post
title: "Revisiting regions"
date: 2012-02-06 09:25
comments: true
published: false
categories: [Rust, PL]
---

There seems to be some renewed interest in intergrating regions into
Rust.  Well, my interest has never waned, but perhaps now the time is
ripe.  The goals, basically, are to create a more flexible language
without adding significant complexity.  Therefore, I wanted to revise
my original proposal from some time back.  I thought I'd sketch out
the outline here before trying to write it up in more detail.

# High-level ideas

- A new pointer type `R&[mut] T`, which is a pointer to a type `T` in the
  region `R`.  But, most of the time, you need only write `&T`,
  because the region `R` can be inferred or defaulted.
- No modes: where you used to do `&x: T` or `&&x: T` you now do `x:
  &mut T` or `x: &T`, respectively.
- You can take the address of variables and fields using the `&` operator.
- Borrowing as an alternative to alias analysis.
- Explicit memory pools to eliminate GC overhead.
- Types can be parameterized by regions: 

      type T<R&> = {
          foo: R& T2;
      };

# Layers

I separate the proposal into layers.  These are basically ideas that
can be implemented (and discussed) in stages.

- 
