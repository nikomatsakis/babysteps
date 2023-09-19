---
layout: post
title: "Restrict pointers"
date: 2012-10-24 21:15
comments: true
categories: [Rust]
---

I am considering whether we should add a way to borrow something but
retain uniqueness.  This would address a shortcoming of the borrowing
system that has been bothering me for some time, and it would enable a
few patterns that are difficult or awkward today.

<!-- more -->

### The Problem

I described the problem in [this paper review I wrote][pr], but I will
repeat it here, because it's relevant, and perhaps people don't read
and remember every single word that I write.  In our system, a `~T`
type is always owned.  So if you write:

    fn foo(bar: ~Map<K,V>) {
        bar.insert(k, v);
        for bar.each |k, v| {
            ...                 // (bar is immutable here)
        }
    }

This is a function which takes in a map, modifies it some, iterates
over it, and then (implicitly) frees it.  The same function could, if
it wanted to, continue by sending `bar` to another task, or doing
whatever.  But, of course, it doesn't here, and perhaps what I really
wanted was just to do some work on behalf of the caller `foo()`.

Typically, the way that one expresses the idea that you want to take
a `Map` but not consume it is to use a borrowed pointer:

    fn foo(bar: &Map<K,V>) {
        bar.insert(k, v);            // (Error)
        for bar.each |k, v| {
            ...                 // (bar is immutable here)
        }
    }
    
Unfortunately, as indicated in the comments, this code will not
compile.  This is because when you borrow a freezable data structure
like a map, you must select if it is immutable (`&Map<K,V>`) or
mutable (`&mut Map<K,V>`).  But this example uses `insert()`, which
requires mutability, and iteration, which requires immutability
(modifying the map while iterating is a no-no).

The only static way to solve this problem is to move the map into the
function `foo()` and then return it back to the caller when `foo()`
has finished:

    fn foo(mut bar: ~Map<K,V>) -> ~Map<K,V> {
        bar.insert(k, v);
        for bar.each |k, v| {
            ...                 // (bar is immutable here)
        }
        return map;
    }
    
This is a bit annoying, but it works.  It's similar to other affine
systems like [Alms][alms].

### A solution

Currently borrowed pointers have the form `& mq` where `mq` is a
mutability qualifier, like `mut` or `const` (the default is
immutable).  I would propose to add a fourth qualifier, called
`restrict` (the keyword is [borrowed from C99][c99]).  An `&restrict` pointer
is still a borrowed pointer, so it does not convey ownership, but it
is *unique*, meaning that it is the only (live) pointer that points at
that particular memory.  It would also imply that this memory is
mutable.  Unlike other `&` pointers, `&restrict` pointers cannot be
copied (they are affine), though they can be re-borrowed temporarily,
just like owned pointers.

Note the distinction between `&~T` and `&restrict T`. The former is a
borrowed pointer to an owned pointer to a `T` (double indirection).
The latter is a borrowed pointer to a `T` (single indirection) that is
guaranteed to be unique.

So, we could rewrite our troublesome function `foo()` as follows:

    fn foo(bar: &restrict Map<K,V>) {
        bar.insert(k, v);
        for bar.each |k, v| {
            ...
        }
    }

Now it is perfectly legal to insert into the map and iterate over it.
The borrow checker knows that there are no aliases of `bar`, so it
will permit it to be treated as both mutable and immutable, as long as
those regions do not overlap.  You would call `foo` like this
`foo(&restrict map)`.

The reason that `restrict` implies mutability is that, if the memory
is *immutable*, you might as well just do an `&T` pointer.  There is
no need to have a unique pointer to immutable memory, since aliases
cannot interfere with one another.  We could force you to say
`&restrict mut` but that seems rather verbose!

### How can you enforce this?

The existing borrow checker mechanisms can easily be enhanced to
support a restricted borrow.  The main difference between this and
other borrows is that a restricted borrow is not compatible with any
other borrows; moreover, a restricted borrow prohibts reads, writes,
and moves.

### Neat.  What else can you do with it?

A lot of parallel algorithms require dividing up an array and
processing each of its parts in parallel.  For this to be safe, you
want to know that you have the only copy of the array.  I was thinking
that one could write a function like:

    fn subdivide<T>(values: &restrict [T]) -> ~[&restrict [T]]
    
`subdivide()` would take a unique slice and divide it up into a set of
other slices, each of which are guaranteed to be disjoint from one
another (and thus safe to process in parallel tasks).  You could
imagine a similar function:

     fn partition<T>(values: &restrict [T], mid: uint) -> (&restrict [T], &restrict [T])
     
This would divide an array about some mid point, which is common in
divide-and-conquer algorithms.

There would still be plenty of work to be done before you could make
good use of these functions though.  For example, we'd need to build
up some parallel constructs that fork and join together.  Such
functions would be permitted access to `&` pointers, so long as they
did not mutate them (as discussed in this post on [purity][purity];
the current Rust `pure` keyword would be a good match here, but maybe
we can find other nice solutions too).

[purity]: {{< baseurl >}}/blog/2012/10/12/extending-the-definition-of-purity-in-rust/

### What's weird here?

One odd thing is that, as I am envisioning it, passing an `&restrict`
to another function consumes the original `&restrict`, just as with
any other affine value.  That's necessary for `subdivide()` and so
forth to work.  Unfortunately, that means that you may have to
re-borrow an `&restrict` pointer to make use of a helper.

So, to make this more concrete, two functions like
this would not compile:

    fn foo(x: &restrict Map<K, V>, ...) {
        bar(x, ...);
        ...
        x.insert(...); // Error: x was given away!
    }

    fn bar(x: &restrict Map<K, V>, ...) {
        ...
    }

The problem is that calling `bar()` gave away the
`x` pointer.  You'd have to write `foo()` like so:

    fn foo(x: &restrict Map<K, V>, ...) {
        bar(&restrict *x, ...);
        ...
        x.insert(...); // OK!
    }
    
Basically this just "re-borrowed" `x`.

### Can you compare this to fractional permissions?

Ok, so you probably didn't ask for this comparison really.  But for
those of you who *are* familiar with fractional permissions, I think a
useful metaphor to explain borrowing goes something like this: first,
before a value is borrowed, it has a permission of 1.0.  When the
value is borrowed with a non-restrict pointer, its permission drops to
something between 0 and 1 exclusive.  When the value is borrwed with a
*restrict* pointer, the permission drops to 0.

The analogy is not exact.  Our borrowing system does not track and
account for permissions but rather simply remembers the largest
dynamic extent of any borrowed pointer and assumes that 1.0 is
returned at the end of that.  This is less flexible in theory---you
can't stash a permission into a heap structure, for example---but it's
often more flexible in practice, since most of the actual fractional
permissions since I've seen paper over fractional permissions with a
borrowing-like system, and they usually don't have the full power of
regions.

Another difference is that our permissions can't actually be
summarized as number between 0 and 1.  In a traditional fractional
permission system, mutability and moves are both tied to having the
full 1.0 permission, but having less than 1.0 means you are limited to
reads and cannot move.  But for us there is the possibility that you
borrow with `&mut`, which permits writes but not move.

[pr]: {{< baseurl >}}/blog/2012/09/26/type-system-for-borrowing-permissions/
[alms]: http://www.eecs.harvard.edu/~tov/pubs/alms/
[c99]: http://en.wikipedia.org/wiki/Restrict
