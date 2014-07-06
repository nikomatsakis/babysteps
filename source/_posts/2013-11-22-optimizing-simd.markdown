---
layout: post
title: "Optimizing SIMD, part 2"
date: 2013-11-22 15:50
comments: true
categories: [PJs, JS]
---
A quick follow-up to my previous post. The approach I suggested
("generate boxing instructions but bypass them when possible") is in
some sense pessimistic: we generate the instructions we need for the
worst case and then cleanup. Like many problems in computer science,
it has an optimistic dual. We could generate unboxed data and then
insert boxes where needed. In fact, we have an existing mechanism for
doing that, called the *type policies*. Basically, there is a phase
where each MIR opcode goes through and examines the types of its
inputs, attempting to reconcile those types with what it needs, either
by boxing or unboxing as needed.

In a [comment on my original post][c], Haitao suggested using the more
optimistic approach. It is also something I had discussed briefly with
Luke in the past. I agree it is a good way to go; the main reason I
held off on suggesting it is that I thought using the pessimistic
approach (particularly to start) would be a faster way of getting
going. Also, I wasn't sure if having objects (the float32x4 wrappers)
be represented by unpacked values during the IonBuilder phase would
violate some invariants.

The reason that I think it'll be easier to get started if we create
the wrapped instructions to begin with is that they can be used in the
bailouts. This means that we'll be able to implement and test the
required changes to the register allocator and code generator first.
Of course, performance will be lackluster since we'll still be
allocating temporaries.

The pessimistic approach is also easier to implement. It requires only
a few lines of code, basically just a helper for unboxing float32x4
values which first checks "is this a boxed float32x4? let me just pull
out the input and return that directly rather than generating a load
instruction". However, it won't yield as good results, since it
doesn't handle phis as well. Until Haitao suggested it, I hadn't
thought about using the optimistic approach to address phis.

In any case, either technique seems like a good choice to me. In the
interest of making changes as small as possible, what I'd prefer is to
start with the pessimistic approach and then move to the optimistic
approach once things work.

If we take this approach (pessimistic first, optimistic later), then
this is the high-level set of tasks. I used indentation to convey
dependencies.

- Add the `simd` module, either in C++ code or (preferably) ported to
  self-hosting. We have to be careful to get the float32 addition
  semantics here, but thanks to `Math.fround` that's not too hard.
- Add MIR types and operations, using pessimistic optimization to start
  - Augment register allocator and LIR to handle vector types
  - Augment bailout code to accept unboxed vectors and box them
    - Implement changes to type policy and generate unboxed data by
      default ("optimistic approach")
- Eventually, correct the value type semantics -- right now we are
  representing `float32x4` values as objects. The correct strategy for
  permitting new kinds of values (in the sense of a distinct `typeof`)
  is being discussed actively in [bug 654416][654416], and we will
  eventually latch onto whatever that strategy becomes.

[654416]: https://bugzilla.mozilla.org/show_bug.cgi?id=645416
