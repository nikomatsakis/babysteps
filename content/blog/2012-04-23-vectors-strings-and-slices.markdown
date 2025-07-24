---
layout: post
title: "Vectors, strings, and slices"
date: 2012-04-23T14:31:00Z
comments: true
categories: [Rust]
---

We've been discussing a lot about how to manage vectors and strings in
Rust.  Graydon sent out an excellent proposal which allows for a great
number of use cases to be elegant handled.  However, I find the syntax
somewhat misleading.  I've proposed one alternative on the mailing
list, but I now find I don't like it, so I thought I'd brainstorm a
bit and try to find something better.

There are really three use cases:

- vectors and strings, which are either allocated on the task heap
  (`@`) or exchange heap (`~`);
- slices, which are a cheap, stack-bound way to represent subvecs and
  substrings;
- fixed-length vectors, which are mainly for C compatibility.

In this post I'm going to focus on the first two cases. The last use
case (fixed-length vectors) is, I think, quite distinct from the first
two, and we should separate it out.  I have also omitted one use case
which Graydon's proposal included: fixed-length strings.  I don't
think that the type `str/10` is of much use, as it refers to a
by-value string that is *always* 10 characters long.  This is not like
a fixed-length buffer that can hold strings *up to* 10 characters
long.  Rather, as I understand it, it can *only* store strings of
exactly 10 characters.  How often are we likely to want that?

### Representation

The representation of a vector or string is something like:

    struct rust_vec<T> {
        int fill;    // How many bytes are used
        int alloc;   // How many bytes are allocated
        T   data[0]; // Inline data
    };
    
Note in particular that this structure does not have a fixed size.
Rather, it will vary depending on how many items are present.  This
indirection is efficient but causes us a bit of trouble.

The representation of a slice which Graydon proposed is something
like this:

    struct slice<T> {
        T *data;
        int length;
    };
    
Basically, the pair of a pointer and a length of memory.  

As an aside, Fixed-length vectors, have yet a third representation:
`T[N]`.  In other words, just a C-like vector.  So you can see that
slices, "vectors as a whole", and fixed-length vectors are quite
different things to the compiler.

### Proposal the first

One idea might be something like this:

    Proposed   Graydon   Representation
    [T]        [T]       slice<T>
    vec<T>               rust_vec<T>
    @vec<T>    [T]/@     rust_box<rust_vec<T>>*
    ~vec<T>    [T]/~     rust_vec<T>*
    
    substr     str       slice<char>
    str                  rust_vec<char>
    @str       str/@     rust_box<rust_vec<char>>*
    ~str       str/~     rust_vec<char>*

The literal forms would basically stay the same as they are today.  So
`[x1, x2]` has the type `vec<T>` and `"foo"` has the type `str`.

I have intentionally drawn a big distinction between the type of a
slice (`[T]`) and the type of a vector (`vec<T>`).  I think these
things are similar but different and people might be easily confused
if the notation is too similar.

There are two types here that cannot be expressed in the original
system: `vec<T>` and `str`.  There is a good reason that these types
are inexpressible: they do not have a fixed size.  So, allowing them
as types introduces a certain danger.  For example, a function like
the following could not be compiled:

     fn foo(x: @vec<T>) {
         let y = *x;
         ...
     }
     
After all, the size of the stack frame could not be correctly
calculated, it would depend on how much data was in `x`.  It is particularly
annoying to deal with this situation due to the possibility of writing
generic functions like

     fn gen_foo<U>(x: @U) {
         let y = *x;
         ...
     }
     
There are two solutions to this, which are really the same solution in
different guises.  The simplest solution is to say that type variables
cannot be bound to the types `vec<T>` and `str`.  This would prevent
us from calling `gen_foo()` with a vector or a string.  We'd also have
some kind of special treatment around assignments so that `let x =
[1, 2, 3]` ends up with a slice, I guess.  Have to think a bit about
that.

Alternatively, one could have a bound that indicates data of a known
size.  This kind would be required to manipulate instances of `T` by
value.  But this could rapidly become annoying.  You might prefer to
have the default be that types *do* have a known type and you have to
say when the type variable might *not*.  This is also ok although
generally type bounds *enable* operators, not *disable* them.

Both solutions are somewhat annoying and I know that Graydon was
trying to avoid them in his design.

### Proposal the second

If we wanted to avoid the possibility of types whose size is not
known, then we have to take a different tack.  We can't have the `@`
be a prefix anymore.  I'd still rather it come near the *front* of the
type, and not tacked on the end.  So far, my preferred notation for
*this* is something like the following:

    Proposed   Graydon   Representation
    []T        [T]       slice<T>
    [@]T       [T]/@     rust_box<rust_vec<T>>*
    [~]T       [T]/~     rust_vec<T>*
    
    ""         str       slice<char>
    "@"        str/@     rust_box<rust_vec<char>>*
    "~"        str/~     rust_vec<char>*

Yes, that's right, I just proposed using `""` as the way to write the
type for strings.  Pretty wacky, I know.  But it seems like we need a
type name that has two parts, a begin and an end, so that we can stick
the `@` and `~` inside of them.  An alternative might be to use more
words (`str` vs `tstr` vs `ustr` or something).

The literal forms for vectors could be something like `[@|...]` and
`[~|...]`.  I don't know about strings.

## What about fixed-length vectors?

I don't know.  We could do `[N]T`, but then it kind of looks like a
slice.  I personally lean towards something like `T * N`.  We also
need an expression form.  To be honest, I don't care about this *that*
much, it seems like macros could solve it too.

## Summary...

None of these ideas seem perfect.  I'm mostly tossing them out there
to ensure we keep talking about it.

p.s., I just realized as I read over the post that I forgot about
mutability.  Something like `[mut T]` cannot be written as `vec<mut
T>`, at least not today.  Sigh.  Well, I'll post this blog post
anyway.  As I said, nothing here is perfect, just wanted to capture
some of the things I've been thinking about.

