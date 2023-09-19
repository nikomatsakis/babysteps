---
layout: post
title: "In favor of types of unknown size"
date: 2012-04-27 09:55
comments: true
categories: [Rust]
---

I'm still thinking about vector and string types in Rust and I think
I've decided what I feel is the best approach.  I thought I'd
summarize it here and make the case for it.  If you don't know what
I'm talking about, see [this post][bg] for more background.  I'll
forward this to the mailing list as well; I'm sorry if it seems like
I'm harping on this issue.  I just think vectors and strings are kind
of central data structures so we want them to be as nice as possible,
both in terms of what you can do with them and in terms of the
notations we use to work with them.

[bg]: {{< baseurl >}}/blog/2012/04/23/vectors-strings-and-slices

## Summary

First, The Grand ASCII Art Table, summarizing everything (sad fact:
`M-x picture-mode` is way more convenient than making an HTML table).
Blank spaces indicate things that are inexpressible in one proposal or
the other (for better or worse).

```
+---------------------++---------------------+
| This proposal:      || Original proposal:  |
|--------+------------||-------+-------------|
| Type   | Literal    || Type  | Literal     |
|--------+------------||-------+-------------|
| [:]T   |            || [T]   | [1, 2, 3]   |
| []T    | [1, 2, 3]  ||       |             |
| &[]T   | &[1, 2, 3] ||       |             |
| @[]T   | @[1, 2, 3] || [T]/@ | [1, 2, 3]/@ |
| ~[]T   | ~[1, 2, 3] || [T]/~ | [1, 2, 3]/~ |
| [3]T   | [|1, 2, 3] || [T]/3 | [1, 2, 3]/_ |
|        |            ||       |             |
| substr |            || str   | "abc"       |
| str    | "abc"      ||       |             |
| &str   | &"abc"     ||       |             |
| @str   | @"abc"     || str/@ | "abc"/@     |
| ~str   | ~"abc"     || str/~ | "abc"/~     |
|        |            || str/3 | "abc"/_     |
+---------------------++---------------------+
```

The types `[]T` and `str` would represent vectors and strings,
respectively.  These types have the C representation `rust_vec<T>` and
`rust_vec<char>`.  They are of *dynamic size*, meaning that their size
depends on their length.  The literal form for vectors and strings are
`[a, b, c]` and `"foo"`, just as normal.

The types `[:]T` and `substr` represent slices of vectors and strings.
Their representation is the pair of a pointer and a length.  They are
each associated with a [lifetime][ref] that specifies how long the
slice is valid, and thus can be more fully notated as `[:]/&r T` and
`substr/&r`, but users will not have to write this very often, if
ever.

Vectors, strings, and fixed-length vectors are implicitly coercable to
slices just as today.  Furthermore, one can explicitly take a slice
using a Python like slice notation: `v[3:-5]` or `v[:]` to take a
slice of the entire vector.  It is also allowed to take a slice of a
slice.  This is where the `:` in the slice type comes from: it's
supposed to echo this syntactic form.

[ref]: {{< baseurl >}}/blog/2012/04/25/references

Fixed-length vectors are written `[N]T`.  They are represented just
like a C vector `T[N]`.  The literal form is `[| v1, ..., vN]`. The
leading `|` serves to distinguish a fixed-length vector.  It is random
but whatever, this is a specialized use case for C compatibility.  The
length of the literal form is always derived from the number of items.
I opted not to include a way to represent fixed-length strings for the
[same reasons I previously stated][bg].

## Advantages

The big advantage is that everything is written the way that seems to
me to be most natural.  For example, a vector on the stack is
`&[1, 2, 3]`.  A task-local vector is written: `@[1, 2, 3]`.  unique
vector is written `~[1, 2, 3]`.  Same with strings.  

I also like the indication of where memory is allocated is orthogonal
to what is stored in the memory. The type and unary operators `&`, `@`
and `~` tell you where the memory is allocated, and the types which
follow tell you what you will find at that memory.  If we have types
like `[1, 2, 3]/@`, they combine where the memory is allocated with
what you will find there (to be clear, that is by design, so as to
avoid the disadvantages in the next section).

There is no need for a literal form for slices.  If you create a
vector and then use it where a slice is expected, the type will be
coercable, so no error will result.

## Disadvantages

The primary disadvantage is that the types `[]T` and `str` are of
dynamic length.  This implies a kind distinction that does not exist
today.  I'd be inlined to just make a rule that types of dynamic
length cannot be used as the types of local variables, fields, vector
contents, nor the values of generic type parameters (and maybe a few
other places).  Later we could add an explicit kind if that seems
necessary.  It basically means you would get an error message like
"the type `[T]` has unknown size cannot be used as the type of a local
variable, use a pointer like `@[T]` or `&[T]`".

Having types of unknown size are a complication, to be sure, but I
feel it is a lesser complication than having special types, expression
forms, and rules for vectors and strings.  Furthermore, this same case
(types of unknown size) has come up from time to time when thinking
about other possible future designs, so I am not sure that it can be
avoided.

A second, more subtle point is that slices are no longer the shortest
type in terms of how they are written, although they are probably the
most common thing you will want to use.  I am not too worried about
this either: `[:]T` is still fairly short and we will use it
ubiquitously.  One thing I don't like is that I find `[:]` somewhat
hard to type.  Maybe that will get easier, or maybe something else
(e.g, `[.]` and a slice notation of `v[1..3]`)  would be better.

## Other kinds of variably sized types...?

Records of dynamic size are common in C, and we may ultimately have to
be able to model that (though we could admittedly use the C trick,
where it pretends all types have fixed size when in fact the memory
allocated may be greater, combined with unsafe pointers). Still, there
is a legitimate use case for allocating a variably-sized vector
interior to a record even in Rust code, and we could support that
(it's the same trick that we in fact use to implement vectors
themselves---if it's important enough for us, maybe it's important
enough for our users).

Another example would be base types.  We may sometime want to allow
records or classes that can be extended with subtypes.  In that case,
we could say that the base types have variable size, since the number
of fields they possess are unknown---this would mean that you only
refer to them by pointer, preventing the common C++ problems of
[slicing][slice] and unsafe array arithmetic.

I'm not sure where else this comes up.  Perhaps that's it.

[slice]: http://stackoverflow.com/questions/274626/what-is-the-slicing-problem-in-c
