---
layout: post
title: "Borrowing errors"
date: 2012-05-05 05:37
comments: true
categories: [Rust]
---

I implemented a simple, non-flow-sensitive version of the reference
checker which I described in [my previous post][pp].  Of course it
does not accept the Rust codebase; however, the lack of
flow-sensitivity is not the problem, but rather our extensive use of
unique vectors.  I thought I'd write a post first showing the problem
that you run into and then the various options for solving it.

## Errors

The single most common error involves `vec:len()`.  There are many
variations, but mostly it boils down to code code like this, taken
from the `io` package:

    type mem_buffer = @{mut buf: [mut u8],
                        mut pos: uint};

    impl of writer for mem_buffer {
        fn write(v: [const u8]/&) {
            if self.pos == vec::len(self.buf) { ... }
            ...
        }
    }
    
The problem lies in `vec::len(self.buf)`.  This is considered illegal
because the vector `self.buf` resides in a mutable field of a
task-local box.  Therefore, the algorithm assumes that `vec::len()`
may have access to it and could, potentially, mutate it, which would
cause the vector to be freed.  Bad.  This call would be fine if the
field `buf` were not mutable.  In that case, even if `vec::len()` had
access to the `mem_buffer`, it could not be able to overwrite the
field.

In fact, *all* of the errors I see right now (about 46 of them across
the standard library and `rustc`) are calls to `vec::len()` or
`vec::each()` with the vector in question living in mutable, aliasable
memory.  It is, currently, the only way to accumulate items in a
vector, after all.  However, I haven't implemented the full check---in
particular, I didn't implement the check that pattern matching a
variant or through a box requires immutable memory, and so I imagine
there will be some more errors related to that once I do that.

## Solution #1: Swapping

Of course, this problem is not really a surprise.  The solution I had
in mind for handling unique data that is located in mutable, aliasable
memory is to swap that unique data into your stack frame, where the
compiler can track it (inspired by
[Haller and Odersky's work on uniqueness][hocap], though I'm sure the
technique predates them).  So the code from the `io` package could be
rewritten as:

    type mem_buffer = @{mut buf: [mut u8],
                        mut pos: uint};

    impl of writer for mem_buffer {
        fn write(v: [const u8]/&) {
            let mut buf = [];
            buf <-> self.buf;
            if self.pos == vec::len(buf) { ... }
            ...
            self.buf <- buf;
        }
    }

This makes use of the little known swap (`<->`) and move (`<-`)
assignment forms.  Now the buffer being passed to `vec::len()` is in
the local variable `buf`, not the contents of some `@` box; this means
that `vec::len()` could not possily reassign it because there are no
aliases to the local variable `buf`.

It's a bit of a pain to write this swapping code each time.  It could
of course be packaged up in a library (here, I've included various
mode declarations, though these would be unnecessary in a purely
region-ified world, as ownership would be done by default):

    type swappable<T> = {mut val: option<T>};
    impl methods<T> for swappable<T> {
        fn swap(f: fn(+T) -> T) {
            let mut v = none;
            v <-> self.buf;
            if v.is_none() { fail "already swapped"; }
            self.val <- some(f(option::unwrap(v)));
        }
    }
    
Swappable could then be used to build up a dynamically growable
vector library:

    type dvec<T> = {buf: swappable<T>};
    impl methods<T> for dvec<T> {
        fn add(+e: T) {
            self.buf.swap { |v| v + [e] }
        }

        fn add_all(v2: [T]) {
            self.buf.swap { |v| v + v2 }
        }
        
        fn each(f: fn(T) -> bool) {
            self.buf.swap { |v| vec::each(v, f); v }
        }
    }
    
Attempts to add to a vector that is being iterated over would fail
dynamically (basically a more reliable version of Java's
["fail-fast iterators"][ffe]).
    
## Solution #2: Pure functions...?

Still, it'd be nice if one could invoke `vec::len()` and `vec::each()`
even when the data is in a mutable location.  After all, neither of
those functions make any changes, and we know that.  One solution I
considered was that we could make use of the `pure` annotation in a
kind of lightweight effect system.

The basic idea would be that `pure` functions are functions which do
not modify any aliasable state (today pure functions disallow mutation
of *any* state, including data interior to the stack frame; we should
[fix this regardless][1422]). However, drawing on
[more work by the Scala folks][lpe], we can actually generalize pure
functions somewhat farther: we could allow them to invoke closures so
long as those closures are given in the arguments.  The idea is
basically that a pure function is one which does not make any
modifications to aliasable state *except possibly through closures
which the caller itself provided*.

These changes would allow us to declare `vec::len()` and `vec::each()`
as pure.  In the case of `vec::len()`, that would be sufficient to
ensure safety without any form of alias check.  Horray!

But don't get too excited: even if `vec::each()` is declared pure, we
still cannot accept calls like the ones we saw before:

    vec::each(self.buf) { |e|
        ...
    }

The reason is that `buf` is still stored in aliasable, mutable state,
and so we have to be sure that the loop body is safe.  This can be
achieved when the vector is stored in a local variable, as we can
monitor for writes to that variable.  But if the vector is in an `@`
box, we have to consider any possible alias of that box.  And this
leads us to our next possible solution, alias analysis.

## Solution #3: Alias analysis

As I said in my [previous post][pp], I am not 100% sure of what analysis
we are doing today.  But if I were to design an alias-based analysis to
address this shortcoming, I imagine if would work something like this:

- Each callee is guaranteed that every reference is stable (points at
  memory which will not be freed) no matter what actions is takes.
  This means that the callee is free to call any functions it likes,
  including closures, because the caller has guaranteed that all
  functions which the callee has access to are harmless.
  
In particular, `vec::each(v, f)` could safely invoke the `f()` on each
item in `v` without fear of `v` being freed.  It's up to the caller to
guarantee that `f` will not have any harmful effects.

But how can the caller do this?  There are two basic techniques.  The
first is to rely on the guarantees it gets from the outside.  So, if
you have a function like:

    fn map<T,U>(v: [T]/&, m: fn(T) -> U) -> [U] {
        let mut r = [];
        for vec::each(v) { |e|
            r += m(e);
        }
        ret r;
    }

Here, the call to `m()` is known to be safe because both `v` and `m`
were given as parameters, so it actually the job of the caller of
`map()` to ensure that they do not conflict.  

If we can't rely on a guarantee from the outside, then, we have to look
at the types.  For example, going back to our example of the buffer, if
we had a loop like:

    for self.buf.each { |e|
        some_ptr.buf = [];
    }
    
Here the assignment to `some_ptr.buf` would be disallowed if
`some_ptr` had the same type as `self`: after all, maybe it is an
alias of `self`.

We can apply similar reasoning to functions that are invoked:

    for self.buf.each { |e|
        clear_buf(some_ptr);
    }

Without knowing what `set_buf()` does, we'd have to reject this
because it has access to data of the same type as `self` (and hence,
potentially to `self` itself).

The cool thing about an analysis like this is that it would allow most
of the examples in the standard library to compile mostly as is.  But
there are some downsides.

First, it's not clear to me that an analysis like this "scales well".
By scales well I do not mean performance but rather that, while
library code tends to pass, I am not sure that uses of library code
will pass.  For example, suppose I have a shared, growable vector that
encapsulates a unique pointer, rather like Java's `ArrayBuffer`.  And
now I have some library code that does:

     my_vec.each { |e| do_some_processing(e); }
     
where `my_vec` is one of these array buffers.  Using an alias check,
it is possible to define the `ArrayBuffer.each()` method, but that
essentially pushes the requirement to the caller to validate that the
body of the `each()` loop will not modify `my_vec`.  Since `my_vec` is
aliasable, this means that `do_some_processing()` must not use any
array buffers of its own.

Admittedly, we haven't run into these scaling problems so much, but I
am not sure how much to draw from that.  For one thing, the analysis
is buggy today, so it may be that we should be seeing more errors than
we are.  For another, all vectors are unique now, but this is causing
us scaling problems, and we are starting to move away from that.
  
A second concern about the analysis is that it is anti-encapsulation.
It requires the compiler to have full details about the types of all
data that may be accessed.  When you have types like closures or
interfaces types, this information is not available, and so the more
we use these abstractions, the worse the analysis performs.
Furthermore, it becomes impossible for modules to "hide" the
implementation of a type---whenever any type definition anywhere
changes, all downstream code must be recompiled or else the memory
safety can no longer be guaranteed.  Admittedly, due to Rust's support
for interior types (not everything is a pointer) and inlining, this is
already often the case, but it should still be possible to define
modules that make use of opaque pointer types in the future, allowing
for changes to the implementation where no recompile is necessary.

**UPDATE:** A further thought on this matter.  This is a bit different
from requiring recompilation as a matter of course (e.g., because the
size of a record changed)---that is, there is no guarantee that the
downstream compilation will succeed.  Now, if I add a use of some
vector library in the upstream code, downstream code may fail to
compile, even if the use of the vector library is purely internal and
not exposed through the interface.

## Summary

I am still leaning towards solution #1, though I appreciate our alias
analysis more and more.  Actually, the fact that I only encountered 46
errors seems pretty decent, especially since most of them are
clustered together.  However, I do expect more such errors when I
implement the pattern matching safety checks, but there we can make
better use of fine-grained copies and so I expect that to be less of a
problem.

Oh, and a final note regarding flow sensitivity: I think I will
implement a flow-sensitive variant of the checker (it's a small change
from what I have today), but since we never take the address of locals
today, it's a moot point anyhow.

[hocap]: http://lampwww.epfl.ch/~phaller/capabilities.html
[lpe]: http://infoscience.epfl.ch/record/175240/files/ecoop_1.pdf
[ffe]: http://stackoverflow.com/questions/4479554/why-vector-methods-iterator-and-listiterator-are-fail-fast
[1422]: https://github.com/mozilla/rust/issues/1422
[pp]: /blog/2012/05/01/borrowing
