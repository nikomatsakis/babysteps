---
layout: post
title: "Dynamically sized types, revisited"
date: 2013-04-30T20:06:00Z
comments: true
categories: [Rust]
---
Recently, separate discussions with pnkfelix and graydon have prompted
me to think a bit about "dynamically sized types" once again. Those
who know Rust well know all about the sometimes annoying discrepancy
between a type like `~T` (owned pointer to `T`) and `~[S]` (owned
vector of `S` instances)---in particular, despite the visual
similarity, there is no type `[S]`, so `~[S]` is not an instance of
`~T` for any `T`. This design was the outcome of a lot of
back-and-forth and I think it has generally served us well, but I've
always had this nagging feeling that we can do better. Recently it
occurred to me how we could, though it's not without its price.

In the spirit of "no stone left unturned", I thought I'd write out
this idea. At first I thought this was a rather futile exercise, since
any large changes to Rust have to pass a pretty high bar at this
point, but now that I've thought the idea through, I think it has a
lot of merit and is worth considering.

<!-- more -->

### A change to representation

For the purposes of simplicity, I will focus on vector types in this
blog post, though I think that many of the same considerations apply
to other types like closure and trait types (as well as strings, but
those are really just newtyped vectors to the compiler).

In the compiler today, both a `~[T]` and an `@[T]` are represented as
a `Box<Vector<T>>*` where the `Box` and `Vector` types are defined as
follows (here `N` is the length of the vector, which naturally is not
known until runtime):

    template<class T>
    struct Box {
        type_descriptor_t *type_desc;
        ...
        T payload;
    }
    
    template<class T>
    struct Vector {
        unsigned length;
        T[N] elements;
    }

(The fact that `~[T]` uses a box is not actually necessary, it was
done as part of the early work on tracing GC and will eventually be
undone, at least for those cases where the type `T` does not itself
include managed pointers)

However, today, a slice `&[T]` is represented quite differently. It is
in fact a `Slice<T>` type, where `Slice` is defined as follows:

    template<class T>
    struct Slice {
        T* elements;
        unsigned length;
    }
    
The reason for this is that we wish a slice to be a subset of another
vector, which is enabled by this two-word representation.

What I'd like to do is to use two words for all vectors. Therefore,
the layout for `~[T]` and `@[T]` will be:

    template<class T>
    struct Vector {
        Box<Elements<T>>* elements;
        unsigned length;
    }

    template<class T>
    struct Elements {
        T[N] elements;
    }

### What does this new representation buy us?

Notice that, apart from the box header, this means that a `~[T]` or a
`@[T]` is in fact a valid slice. This is exactly like any other `~T`
or `@T` pointer, which has the same format as a `&T` pointer but for
the box. This is actually quite similar to how we handle object types
(`@Trait` vs `&Trait`) and closure types (`@fn()`, `&fn()`).

This means that we can define our Rust type hierarchy as follows:

    T = S            // sized types
      | U            // unsized types
    S = &'r T        // region ptr
      | @T           // managed ptr
      | ~T           // unique ptr
      | [S, ..N]     // fixed-length array
      | uint         // scalars
      | ...
    U = [S]          // vectors
      | str          // string
      | Trait        // existential ("exists S:Trait.S")
      | fn(S*) -> S

Note that I have divided the types into two groups. *Sized* types
indicate values whose size is known to the compiler. *Unsized* types
represent values whose size is *not* known the compiler (this
terminology is somewhat imprecise; unsized values do in fact have a
size, but it is not known until runtime). Note that unsized types are
generally only legal behind a pointer; that is, you can't have a type
like `~[[int]]`, which would be an array of arrays, where each
subarray could have a different size. You could have `~[~[int]]`---an
array of pointers to arrays---or `~[[int, ..4]]`, an array of
fixed-length arrays of size 4.

Pointers to values of unsized type (e.g., `@U`, `&U`) are "fat"
pointers, meaning that at runtime they are represented by a pair
(`(pointer, meta)`).  The first word is a pointer to the data, and the
second word (`meta`) is some kind of descriptor that indicates what
size the data has. The exact nature of this descriptor will change
depending on the type `U`, but there is always something there (for
vectors, the meta value is just a length; for objects, it's a vtable;
etc). Standard pointer operations (notably borrowing) are applied to
the `pointer` portion of this pair but leave the `meta` portion
intact.

### Writing generic code in the face of unsized types

Using this definition of types means that we can write and compose
generic impls that operate over types like `@T`, `~T`, and `[T]`,
instead of writing impls, like the following:

    impl<T:ToStr> ToStr for @T {
        fn to_str(&self) -> ~str {
            let @ref v = *self;
            fmt!("@%s", v.to_str())
        }
    }

    impl<T:ToStr> ToStr for ~T {
        fn to_str(&self) -> ~str {
            let ~ref v = *self;
            fmt!("~%s", v.to_str())
        }
    }

    impl<T:ToStr+Sized> ToStr for [T] {
        fn to_str(&self) -> ~str {
            let mut result = ~"";
            let mut prefix = "";
            result.push_char('[');
            for self.each |v: &T| {
                result.push_str(prefix);
                result.push_str(v.to_str());
                prefix = ",";
            }
            result.push_char(']');
        }
    }

This replaces the impls we must write today, which would be over `~T`,
`@T`, `~[T]`, `@[T]` (and `&T` and `&[T]`, typically, but I didn't
include those in the above example).

However, there is a catch. The compiler must ensure that unsized types
do not appear in illegal locations. For example, we cannot have a
local variable of unsized type, because that would require an unknown
amount of stack space. Similarly, we cannot have a vector whose
elements are unsized. In fact, this is visible in the previous code
snippet: if you look carefully at the impl for `[T]`, you will see
that the type `T` is declared with a bound `Sized`:

    impl<T:ToStr+Sized> ToStr for [T] { ... }

This indicates that the type `T` must be a sized type.

In practice, I suspect we wouldn't have to write the `Sized` bound very
often. This is because the traits `Copy` and `Clone` must extend
`Sized`, since they return a new instance of the receiver, and you
can't return an unsized type (note that functions must take sized
arguments and return sized values). Today, most generic functions fall
into two categories: those that copy values around, and those that
manipulate them solely by reference. The former would require a
`Sized` bound, but then they also require a `Copy` bound, which
implies `Sized`. The latter do not require `Sized` at all.

### In summary

In summary, I think we can have our cake and eat it too. If we change
the representation of vectors and slices, we can have composable types
*and* all the efficiency and flexibility of the current system. The
price is that we must distinguish "sized" from "unsized" type
parameters. I argue that this is likely to be a minor cost, since most
of the time parameters that would require a `Sized` bound will already
have a `Copy` or `Clone` bound anyhow. I think that's pretty exciting,
since the non-composability of vector types has always seemed like a
language wart in the making.
