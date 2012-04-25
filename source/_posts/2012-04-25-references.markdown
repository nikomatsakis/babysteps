---
layout: post
title: "References"
date: 2012-04-25 07:53
comments: true
categories: [Rust]
---

I want to do an introduction to the regions system I've been working
on.  This is work-in-progress, so some of the details are likely to
change.  Also, I'm going to try some new terminology on for size:
although it has a long history in the literature, I think the term
"region" is not particularly accurate, so I am going to use the term
"lifetime" or "pointer lifetime" and see how it fits.

In this post I'm just going to show some examples of how the new
features can be used.  In the next post, I'll lift the curtain a bit
and explain how the checks work.

### Introduction

Rust has always (at least, as long as I've been around) had three
sorts of pointers: `@T`, which is a task-local pointer into the heap;
`~T`, a unique pointer into the heap, generally (but not exclusively)
used for sending data between tasks; and reference mode arguments,
used to give a function a temporary pointer.

The goal of this work is to replace reference mode arguments with
something more flexible.  Reference mode arguments work quite well for
many purposes, but they have one primary limitation: they cannot be
stored into data structures.

So, in this branch, we (conceptually at least) remove reference mode
arguments from the Rust Pointer Pantheon and replace them with
reference types, written `&T` (this is actually a shorthand, as we
will see later).  I will refer to a variable of reference type as a
reference.

References are basically generic pointers.  They can point anywhere:
into the stack, into the `@` heap, into the `~` heap, even into the
inside of a record or vector.  They are as flexible as pointers in C;
however, they are free from the many errors that C permits.  The type
checker guarantees that references are always valid, so you can't have
a reference into freed memory, or into a stack frame that has been
popped, and so forth.

We'll get to the full details of how the safety check works later
(probably in a separate post).  First, I want to give some examples of
using references.

### Using references

#### Simple references and borrowing

Let's create a record type `point` for use in our examples:

    type point = { x: uint, y: uint };

Now, imagine that we have a function which wants to compute the slope
of two points.  It doesn't particularly care where those points are
allocated.  You could write it like so:

    fn slope(p1: &point, p2: &point) -> float {
        let y = (p2.y - p1.y) as float;
        let x = (p2.x - p1.x) as float;
        ret y / x;
    }

OK, that was fairly straightforward.  Now let's look at how `slope()`
might be called.  First, assume that we have some routine which takes
a vector of pairs of points allocated on the heap and computes the
maximum slope of any of those pairs.  Why you would want such a
function, I don't know, but this is how you would write it:

    fn max_slope(ps: [(@point, @point)]) -> float {
        ps.max { |(p1, p2)| slope(p1, p2) }
    }

You'll notice that `slope()` is called with `p1` and `p2`, which have
type `@point`, not `&point`.  The type checker happily accepts this,
however, because a reference can point anywhere, including into the
heap.  This process of converting of kind of pointer to another is
called *borrowing*.

The reason it's called borrowing is that, in effect, the callee
(`slope()`) borrows a reference from the caller (`max_slope()`).  It
is the caller's job to ensure that this reference remains valid for
the duration of the callee.  In this case, there is no extra work
required to make that true, but in some cases the compiler may be
required to increment a ref count or maintain a GC root (this is
highly dependent on how the `@` heap is managed, naturally).

You can also borrow `~` pointers.  This basically works the same as
with `@` pointers, except that the unique value cannot be moved away
(for example, sent to another task) while it is borrowed.  The reason
for that is that, for the duration of the borrowing, the unique
pointer is no longer unique.  So if you sent it to another task, for
example, then two tasks would have access to it.  Even within a single
task, if you gave the pointer away, then there would be multiple
copies each claiming to be unique, which would lead to double frees
and other badness.  The key invariant that *borrowing* maintains is
that, while a `~T` may be temporarily aliased, all of the aliases are
references, not other `~T` pointers.  So we can always identify the
true owner once the borrowing expires.

Right now, borrowing can only occur in method calls.  The borrowing
lasts for the duration of the method call.  In the future, borrowing
will also be possible in `alt` expressions and when assigning a local
variable with `let`.  In the former case, the borrowing will last for
the duration of the `alt` expression.  In the latter case, the borrow
will last until the local variable goes out of scope (until the end of
the enclosing block, in other words).

#### Taking the address of local variables

Sometimes we wish to give away pointers into our local stack.  For
example, there is a routine today called `vec::push(x, y)` which has
the effect of appending the value `y` onto the vector `x` (in place).
This can be implemented using references like so:

    fn push<T:copy>(v: &mut [T], elt: T) {
        *v = *v + [T];
    }

Here the argument `&mut [T]` indicates a mutable reference: that is, a
reference which can be used to modify the data it points at.  The
requirement to explicitly declare which pointers may be used for
modification stems from Rust's desire to make mutation explicit, and
is analogous to the existing `@mut T` and `~mut T` types.

To call push, we might write code like this:

    fn accum() {
        let mut v = [1, 2, 3];
        vec::push(&v, 4);
        vec::push(&v, 5);
    }

Here we used the `&` operator to take the address of a local variable
so that we could pass it into the `push()` routine.

*An aside:* I believe that in the current implementation of the
compiler you would have to write `vec::push(&mut v, 4)`---that is, you
would have to declare when taking the address of `v` that you intend
to mutate through this pointer.  I believe there is no reason we can't
lift this restriction, however, and allow the compiler to figure it
out for itself. (I rather prefer the explicit form in theory, because
I like to make it clear when things are being modified, but I suspect
it will be annoying in practice)

#### Copying into the stack

Right now, if you wish to create a record literal on the stack, you
have to manipulate it by value.  So you might write code like:

    fn create_point() {
        let p1 = { x: 3u, y: 4u };
        let p2 = { x: 5u, y: 10u };
        let p3 = if cond {p1} else {p2};
        ...
    }

Here the type of `p{1,2,3}` is `point`.  But often we wish to
manipulate values by pointer.  In this case, that would make `p3` a
cheaper copy, for example.  Using references, we can write something
like this:

    fn create_point() {
        let p1 = &{ x: 3u, y: 4u };
        let p2 = &{ x: 5u, y: 10u };
        let p3 = if cond {p1} else {p2};
        ...
    }

Here we used the same `&` operator, but with an rvalue (an expression
that is not assignable).  This simply allocates space on the stack and
copies the value into it.  The corresponding type of `p{1,2,3}` would then
be `&point`, where `&` is a reference into the stack of
`create_point()`.

#### Placing references into structures

Next let's look at a case where we wish to store a reference into a
structure.  This example comes out of the Rust compiler, but it's a
common pattern in practice.

In the Rust compiler, there is a phase of processing called encode in
which we generate the metadata for a compiled crate.  During this
encoding, we have a struct `encode_ctxt` that stores the various
context which is required.  Because this structure is only needed
during this one phase, it is allocated on the stack, and we pass it
from function to function using references (today, using a reference
mode argument).

The code to create this encode context looks something like the following:

    type encode_ctxt = { /* contents are not important */ };

    fn begin_encoding(...) {
        let ecx = &{ /* allocate an encode context */ };
        for items_to_encode.each { |item|
            encode_item(ecx, item);
        }
    }

Here you see that `begin_encoding()` creates a variable `ecx`,
storing the data onto the stack.  This context is then passed to each
call to `encode_item()`.

What can happen then is that some subpart of the encoding requires
its own context.  For example, in our metadata encoding, we sometimes
have to serialize the AST for an inlinable function.  This requires quite
a bit more state, but it's state that is specific to the inlining itself.
So we can define a type `inline_ctxt` that will include both the encoding
context `ecx` along with some other fields:

    type inline_ctxt/& = {
        ecx: &encode_ctxt,
        ...
    };

What you see here is that the type `inline_ctxt` is declared like any
other record, but it has this `/&` following the name.  This is a
declaration that the type will contain references.  The record
itself then simply embeds the `&encode_ctxt` as any other field.
*Note:* It's possible that the `/&` might become inferred in the
future rather than being explicit.

Now I can write functions that create and use the inlined context as
follows:

     fn encode_inlined_item(ecx: &encode_ctxt, ...) {
         let icx = &{ecx: ecx, ...};
         ...
         some_helper_func(icx, ...);
         ...
     }

     fn some_helper_func(icx: &inline_ctxt, ...) {
         // ... can use icx, icx.ecx, etc ...
     }

#### References in boxes

In the previous example, we create a structure on the stack which
contained a reference to some data living in an activation somewhere
up the stack.  It is also possible to place references into heap
objects.  For example, I could have allocated the `inline_ctxt` on
the heap like so:

     fn encode_inlined_item(ecx: &encode_ctxt, ...) {
         let icx = @{ecx: ecx, ...};
         ...
         some_helper_func(icx, ...);
         ...
     }

     fn some_helper_func(icx: @inline_ctxt, ...) {
         // ... can use icx, icx.ecx, etc ...
     }

In this case, there is not really much reason to do this, as the lifetime
of the `inline_ctxt` is bound to the stack frame that created it.  But
it can be convenient in a number of scenarios:

- a long computation might make use of internal data that can be collected
  before the computation itself completes, and this internal data may
  need to contain references;
- allocating values that you plan to return to your caller is most
  conveniently done with an `@` pointer.

This last point is interesting.  Basically, in most of our examples
we've been allocating things on the stack---but you can't return stuff
that's on your stack up to your caller, clearly (and if you try, in
Rust at least, you'll find that a type error results).

#### Arenas

One very common C trick for speeding up allocation is to make use of
memory pools, also called arenas.  If you happen to have a lot of
allocations which you plan to do but which will all get freed at one
point, then you can allocate a big block of memory and just hand it
out piece by piece.  Once the pass is done, you free the memory all at
once.  The key is that you never track whether an individual
allocation has completed or not, so you avoid a lot of overhead The
problem with arenas is that, as typically implemented, they are
unsafe, because you might free the arena but still hold on to pointers
that point into the arena.  This is where lifetimes come in.

Using a reference, we can allocate memory in arenas and be sure that
the reference will not outlive the arena itself.  For example, this
function will allocate a new point in an arena and return it:

    fn alloc_point(pool: &arena) -> &point {
        ret new (pool) { x: 3u, y: 4u };
    }

In this case, the type checker will assign the allocated point the
same lifetime as the arena itself.  So the point can be used so long
as the arena is valid.

### Lifetimes

At this point, I've shown you a lot of examples of how references can
be used, but I have given basically no intution for how it is that the
compiler can prevent a reference from being used when it is no longer
valid.

The basic idea is that every reference type `&T` is in fact shorthand
for a type written `&a.T`, where `a` is some kind of *lifetime*.  The
lifetime of a reference defines when it is valid.  These lifetimes
correspond to the dynamic execution of some function, block,
expression, whatever.

To make this clearer, let's look at an example.  Suppose I have this
simple function.  I have also shown the various lifetimes (named
`a`...`c`) graphically along the right-hand side.

    fn scoped_lifetimes(x: @uint) { // a
        let y = 3u;                 // |
                                    // |
        if cond {                   // | b
            let z = 4u;             // | |
                                    // | | c
            borrow(x) /* 1 */       // | | |
                                    // | | -
        }                           // | -
    }                               // -

    fn borrow(x: &uint) {...}

There are three distinct lifetimes in the function
`scoped_lifetimes()`, each nested within one another. The outermost
one is `a`, which corresponds to the entire function activation.  The
expression `&y`, which takes the address of the local variable `y`,
would have type `&a.uint`.

The next lifetime is `b`, which corresponds to the "then-block" of the
if statement.  The expression `&z` would have the type `&b.uint`,
because after the if statement concludes the variable `z` is no longer
in scope.

Finally, the lifetime `c` corresponds just to the call to `borrow(x)`.
Here, the variable `x` is coerced into a region pointer with lifetime
`&c.uint`.

Now let's examine `borrow()` a bit more closely.  The definition of borrow
is in fact shorthand for something like the following:

                             //  d
                             //  .
                             //  .
    fn borrow(x: &d.uint) {  //  |
        ...                  //  |
    }                        //  |
                             //  .
                             //  -

In other words, the `&uint` type we saw before in fact expands to a
lifetime with a unique name; we'll call this name `d` (in fact, all
uses of `&` within a function are references to a special region
called the anonymous region---it acts just like a named region, except
that it doesn't have a name).  

The lifetime `d` is a bit different from the other lifetimes we've
seen, as it appears within the function declaration itself: it is in
fact a lifetime parameter.  That is, it corresponds to some lifetime
which the caller will specify---the callee, `borrow()` in this case,
doesn't know precisely how long the lifetime `d` lasts, it only knows
that `d` includes the entire execution of the callee. I've tried to
depict this in my ASCII art diagram using dots to represent the
unknown duration, with the pipes `|` representing what is known for
certain.  In the call to `borrow(x)` which we saw before, the lifetime
parameter `d` would be mapped to the lifetime `c` from
`scoped_lifetimes()`.

#### Detecting errors

The compiler uses these symbolic lifetimes to prevent problems.
Consider something simple like this:

    fn give_away() -> &uint {
        let y = 3u;
        ret &y;
    }

Here there is an error because the function is attempted to return a
pointer into its own stack frame.  To see how the compiler detects
this, consider the lifetimes involved:

                                // a
                                // .
                                // .
    fn give_away() -> &a.uint { // | b
        let y = 3u;             // | |
        ret &y;                 // | |
    }                           // | -
                                // .
                                // -

Here I have called the anonymous lifetime parameter `a`.  The
expression `&y` has type `&b.uint`, which does not match the expected
type `&a.uint`, and so we get a type error.  This type error is
warning us that the lifetime of the pointer we are trying to return
(`b`) is shorter than the lifetime which was declared (`a`).

### Ta ta for now

There's more to tell, but I'll stop here, as this post is already
plenty long.
