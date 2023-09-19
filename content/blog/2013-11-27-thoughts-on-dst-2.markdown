---
layout: post
title: "Thoughts on DST, Part 2"
date: 2013-11-27 06:36
comments: true
categories: [Rust]
---
In the [previous post][pp] I elaborated a bit on DSTs and how they could be
created and used. I want to look a bit now at an alternate way to
support the combination of vector types and smart pointers (e.g.,
`RC<[uint]>`). This approach avoids the use of DSTs. We'll see that it
also addresses some of the rough patches of DST, but doesn't work
quite as well for object types.

This is part 2 of a series:

1. [Examining DST.][pp]
2. Examining an alternative formulation of the current system.
3. [...and then a twist.][part3]
4. [Further complications.][part4]

<!-- more -->

### Existential types, take 2

Previously I showed how a type like `[T]` could be interpreted as an
existential type like `exists N. [T, ..N]`. In this post, I explore
the idea that we most the `exists` qualifier to a different level.  So
`~[T]`, for example, would be interpreted as `exists N. ~[T, ..N]`
rather than `~(exists N. [T, ..N])`. Naturally the same existential
treatment can be applied to objects.  So `&Trait` is formalized as
`exists T:Trait. &T`.

This is in a way very similar to what we have today. In particular,
there are no dynamically sized types: `[T]` is not a type on its own,
but rather a kind of shorthand that "globs onto" the enclosing pointer
type. However, as we proceed I'll outline a couple of points where we
can generalize and improve upon on what we have today; this is
because, today, a `~[T]` value is considered a type all its own that
is totally distinct from a `~[T, ..N]`, rather than being an
existential variant. This has implications for how we build vectors
and for our ability to smoothly support user-defined pointer types.

Now, when I say *shorthand*, does that imply that users could write
out a full existential type? Not necessarily, and probably not in the
initial versions. Perhaps in the future. I am thinking of more of a
mental shorthand, as instruction for how to think about a type like
`&Trait` or `&[T]`.

### Representing existentials

Moving the existential qualifier *outside* of the pointer simplifies
the story about representation and coercion. An existential type like
is always represented as two words:

    repr(exists N. U) == (repr(U), uint)
    repr(exists T:Trait. U) == (repr(U), vtable)
    
So, for example, in the type `~[T] == exists N. ~[T, ..N]`, the
representation would be `(pointer, length)`, where `pointer` is a
pointer to a `[T, ..N]`. Of course, we don't know what `N` is, but
that doesn't matter, because it doesn't affect the pointer. We can
therefore adjust our definition `repr` slightly to codify the fact
that we don't know -- nor care -- about the precise values of `N` or
`T`:

    repr(exists N. U) == (repr(U[N => 0]), uint)
    repr(exists T:Trait. U) == (repr(U[T => ()]), vtable)

Here I just substituted `0` for `N` and `()` for `T`. This makes sense
since the compiler doesn't really know what those values are at
compilation time. It also implies that we cannot create an existential
unless it's safe to ignore `N` and `T` -- e.g., `exists N. [T, ..N]`
would be illegal, since there is no pointer indirection, and hence
knowing `N` is crucial to knowing the representation of `[T, ..N]`.

This definition probably looks pretty similar to what I had before but
it's different in a crucial way. In particular, there are no more fat
pointers -- rather there are existential types that abstract over
pointers. The length or vtable are part of the representation of *the
existential type*, not the pointer. Let me explain the implications of
this by example. Imagine our `RC` type that we had before:

    struct RC<T> {
        priv data: *T,
        priv ref_count: uint,
    }

If we have a `RC<[int, ..3]>` instance, its representation will be
`(pointer, ref_count)`. But if we coerce it to `RC<[int]>`, its
representation will be `((pointer, ref_count), length)`. Note that
`RC` pointer itself is unchanged: it's just embedded in a tuple.

Embedding the `RC` value in a tuple is naturally simpler than what we
had before, which had to kind of rewrite the `RC` value to insert the
length in the middle. But it's also just plain more expressive. For
example, consider the example of a custom allocator smart pointer that
includes some headers on the allocation before the data itself (I
introduced this type in [part 1][pp]):

    struct Header1<T> {
        header1: uint,
        header2: uint,
        payload: T
    }
    
    struct MyAlloc1<T> {
        data: *Header1<T>
    }

With DST, a type like `MyAlloc1<[int]>` is not even expressible
because the type parameter `T` is not found behind a pointer sigil and
thus `T` couldn't be bound to an unsized type. Even if we could
overcome that, we could not have coerced a `MyAlloc1<[int,..3]>` to a
`MyAlloc<[int]>` because we couldn't "convert" the representation of
`MyAlloc1` to make `data.payload` fat pointer. But all of this poses
no problem under the existential scheme: if we represent
`MyAlloc1<[int, ..3]>` as `(pointer)`, the representation of
`MyAlloc1<[int]>` is just `((pointer), length)`. This in turn implies
that it should be possible to support the C-like inline arrays that I
described before, though some future extensions will be required.

### What does this scheme mean in practice?

For users, this scheme will feel pretty similar to what we have today,
except that some odd discrepancies like `~[1, 2, 3]` vs `~([1, 2, 3])`
go away.

In general, the only legal operation we would permit on an existential
type like `RC<[int]>` or `~[int]` is to dereference it. The compiler
automatically propagates the existential-ness over to the result of
the dereference. That means that `*rc` where `rc` has type `RC<[int]>`
would have type `&[int]` -- or, more explicitly, `exists
N. RC<[int, ..N]>` is dereferenced to `exists N. &[int, ..N]`. In
formal terms, this is a combined pack-and-unpack operation. I'll
discuss this in part 3 of this series. The special case would be
`&[T]`, for which we can define indexing -- and this would also
perform the bounds check. Object types (`&Trait`, `RC<Trait>`) would
be similar except that they would only permit dereferencing and method
calls.

For people implementing smart pointers, this scheme has a
straightforward story. No special work is required to make a smart
pointer compatible with vector or trait types: after all, at the time
that a smart pointer instance is created, we always have *full
knowledge* of the type being allocated. So if the user writes `new(RC)
[1, 2, 3]` (employing the overloadable `new` operator we are
discussing), that corresponds to creating an instance of
`RC<[int, ..3]>`. `[int, ..3]` is just a normal type with a known
size, like any other.

#### "Case study": Ref-counted pointers

Really, the only thing that distinguish a "smart pointer" from any
other type is that it overloads `*` (and possibly integrates with
`new`). I've got another post planned on the details of these
mechanisms, but let's look at overloading `*` a bit here to see how it
interacts with existential types. The deref operator traits would look
something like this:

    trait Deref<T> {
        // Equivalent of `&*self` operation
        fn deref<'a>(&'a self) -> &'a T;
    }
    
    trait MutDeref<T> {
        // Equivalent of `&mut *self` operation
        fn mut_deref<'a>(&'a mut self) -> &'a mut T;
    }

Here is how we might implement define an `RC` type and implement the
`Deref` trait:

    struct RC<T> {
        priv data: *T,
        priv ref_count: uint,
    }
    
    impl<T> Deref<T> for RC<T> {
        fn deref<'a>(&'a self) -> &'a T {
            &*self.data
        }
    }

Note that `RC` doesn't implement the `MutDeref` trait. This is because
`RC` pointers can't make any kind of uniqueness guarantees. If you
want a ref-counted pointer to mutable data you can compose one using
the newly created `Cell` and `RefCell` types, which offer dynamic
soundness checks (e.g., `RC<Cell<int>>` would be a ref-counted mutable
integer). In any case, I don't have the space to delve into more
detail on mutability control in the face of aliasing here -- it would
make a good topic for a future post as we've been working on a design
there that offers a better balance than today's `@mut` and is
smart-pointer friendly.

As I said before, the `RC` implementation does not make any mention
whatsoever of vectors or arrays or anything similar. It's defined over
all types `T`, and that includes `[int, ..3]`. Nothing to see here
folks, move along.

The compiler will invoke the user-defined deref operator both for
explicit derefs (the `*` operator) and auto-derefs (field access,
method call, indexing). Consider the following example:

    fn sum(rc: RC<[int]>) -> int {
        let mut sum = 0;
        let l = rc.len();           // (1)
        for i in range(0, l) {
            sum += rc[i];           // (2)
        }
    }

Here, autoderef will be employed at two points. First, in the call
`rc.len()`, the pointer `rc` will be autoderef'd to a `&[int]` while
searching for a `len()` method (see the type rules below for how this
works). `len()` is defined for a `&[int]` type, and so the call
succeeds. Similarly in the access `rc[i]`, the indexing operator will
autoderef `rc` to `&[int]` in its search for something
indexable. Since `&[int]` is indexable, the call succeeds. The
important point here is that the `RC` type itself only supports deref;
the indexing operations etc come for free because `&[int]` is
indexable.

**UPDATE:** Thinking on this a bit more I realized an obvious
complication. Without knowing the value of `N`, we can't actually
know which monomorphized variant of `deref` to invoke. This matters if
the value of `N` affects the layout of fields and so on. There are
various solutions to this -- for example, only permitting existential
construction when the types are laid out such that the value of `N` is
immaterial for anything besides bounds checking, or perhaps including
a vtable rather than a length -- but it is definitely a crimp in the
plan. Seems obvious in retrospect. Well, more thought is
warranted.

### Comparing DST to this approach

I currently favor this approach -- which clearly needs a confusing
acronym! -- over DST. It seems simpler overall and the ability to
coerce from arbitrary pointer types into existential types is very
appealing. It is a shame that it doesn't address the issues with
object types that I mentioned [in the previous post][pp] but there are
workarounds there (better factoring for traits intended to be used as
objects, essentially).

This will not address the new user confusion that `&[T]` is valid
syntax even though `[T]` is not a type, but I think it does offer a
new way to better explain that discrepancy: `&[T]` is short for
`&[T, ..N]` for an unknown `N`, and thus `[T, ..N]` is the memory's
actual type.

[pp]: {{< baseurl >}}/blog/2013/11/26/thoughts-on-dst-1/
[part3]: {{< baseurl >}}/blog/2013/11/26/thoughts-on-dst-3/
[part4]: {{< baseurl >}}/blog/2013/12/02/thoughts-on-dst-4/
