---
layout: post
title: "Lifetime notation"
date: 2012-12-30 16:33
comments: true
categories: [Rust]
---

I've been thinking for a while that our lifetime notation has too many
defaults which can be more confusing than helpful.  A recent spate of
e-mails on rust-dev brought this back to my mind.  I've been wanting
to take a look at these defaults for a while, so I thought I'd write
up a quick exploration of the "syntactic space".  A warning: this is
not really an exciting post to read.  I hope to have a few of those
coming up very soon.  This one is mostly just a list of syntactic
options I wanted to document for future reference and to serve as a
starting point for discussion.

<!-- more -->

### Problematic cases

The area that most people find confusing is when you have a borrowed
pointer inside of a struct.  A recent example was this `StringReader`
struct:

    struct StringReader {
        value: &str,
        count: uint
    }
     
Here, the `StringReader` contains a borrowed pointer.  This means that
an instance of `StringReader` is only valid for as long as its `value`
field is valid.  So, every instance of the `StringReader` must have a
lifetime, and that lifetime is the same as the `value` field within.

The compiler in fact infers which structs contain (directly or
indirectly) borrowed pointers and thus must have an associated
lifetime.  It's all very automatic.  If we were to require a more
explicit notation, the declaration of `StructReader` might look
something like this:

    struct StringReader/&self {
        value: &self/str,
        count: uint
    }
     
Here, the trailing `/&self` that appears after `StringReader`
indicates that instances of the `StringReader` type are associated
with a lifetime "self".  Moreover, the `value: &self/str` states that
the value field is a string with this same lifetime.

What is in fact happening here in terms of the formalism is that the
`StringReader` type has a *lifetime parameter* named `self`.  In other
words, `StringReader/&self` is a generic type, just like `Option<T>`,
except that it is not generic over a type `T` but rather over the
lifetime `self`.  It is of course possible to have a type like
`Foo/&self<T>`, which is generic over both a lifetime `self` *and* a
type `T`.

One thing which would sometimes be useful (but which is currently
unsupported) is the ability to have more than one lifetime parameter
on a struct.  There are no theoretical reasons for this limitation,
it's simply that the syntax and defaults we've adopted didn't seem to
scale up to multiple parameters.

### Options

There are a fair number of possibilities.  I thought rather than write
a lot of words, I'll just enumerate the various options I see.  To
begin with, here is a program written with the current syntax that
demonstrates the various bits of shorthand.

    struct StringReader { // Lifetime parameter &self is not declared
        value: &str,      // & in a type decl defaults to self
        count: uint
    }
    
    impl StringReader {
        fn new(value: &self/str) -> StringReader/&self {
            StringReader { value: value, count: 0 }
        }
    }
    
    fn remaining(s: &StringReader) -> uint {
                 // ^~~~~~~~~~~~~ & in a fn is a fresh lifetime, so this
                 // is shorthand for &x/StringReader.  Moreover,
                 // &x/StringReader is short for &x/(StringReader/&x).
        return s.value.len() - s.count;
    }
    
    fn value(s: &v/StringReader) -> &v/str {
             // ^~~~~~~~~~~~~~~ &v/StringReader is short
             //                 for &v/(StringReader/&v).
        return s.value;
    }
    
Option 2: Fully explicit type declarations but not uses.

    struct StringReader/&self { // Note explicit decl here
        value: &self/str,       // And explicit reference here
        count: uint
    }
    
    impl StringReader {
        fn new(value: &self/str) -> StringReader/&self {
            StringReader { value: value, count: 0 }
        }
    }
    
    fn remaining(s: &StringReader) -> uint {     // As in Option 1
        return s.value.len() - s.count;
    }
    
    fn value(s: &v/StringReader) -> &v/str {     // As in Option 1
        return s.value;
    }

Option 3: Like Option 2, but infer the presence `self` lifetime
parameter on a type decl.

    struct StringReader {     // No explicit decl
        value: &self/str,     // But explicit reference
        count: uint
    }
    
    impl StringReader {
        fn new(value: &self/str) -> StringReader/&self {
            StringReader { value: value, count: 0 }
        }
    }
    
    fn remaining(s: &StringReader) -> uint {     // As in Option 1
        return s.value.len() - s.count;
    }
    
    fn value(s: &v/StringReader) -> &v/str {     // As in Option 1
        return s.value;
    }

Option 4: Fully explicit type declarations and uses.

    struct StringReader/&self {      // As in Option 3
        value: &self/str,            // As in Option 3
        count: uint
    }
    
    impl StringReader {
        fn new(value: &self/str) -> StringReader/&self {
            StringReader { value: value, count: 0 }
        }
    }
    
    fn remaining(s: &StringReader/&) -> uint {
                 // ^~~~~~~~~~~~~~~ Here we require that the
                 // lifetime parameter on StringReader be
                 // "acknowledged" by the trailing `/&`.  Interestingly,
                 // this "&" could either refer to a fresh lifetime
                 // (making this equivalent to &x/(StringReader/&y)) or,
                 // more usefully, refer to the enclosing lifetime
                 // &x/(StringReader/&x).  The latter is closer to how
                 // things work today.
        return s.value.len() - s.count;
    }
    
    fn value(s: &v/StringReader/&v) -> &v/str {
             // ^~~~~~~~~~~~~~~~~~ Fully explicit.
        return s.value;
    }

Option 5. Like Option 4, but with alternate syntax that tries to unify
lifetime parameters and type parameters.  Here the lifetime name goes
*before* the `&`, as we originally had it.  This is required to make
parsing unambiguous.

    struct StringReader<self&> {
        value: self& str,
            // ^~~~~~~~~ self& in place of &self/
        count: uint
    }
    
    impl StringReader {
        fn new(value: self& str) -> StringReader<self&> {
            StringReader { value: value, count: 0 }
        }
    }
    
    fn remaining(s: &StringReader<&> -> uint {
                 // ^~~~~~~~~~~~~~~~ as in Option 4, we must select
                 // which of the two possible meanings.
        return s.value.len() - s.count;
    }
    
    fn value(s: v& StringReader<v&>) -> &:v str {
        return s.value;
    }

Option 6. Another alternate syntax for Option 4, where the lifetime
names are preceded by a `:`.

    struct StringReader<:self> {
        value: &:self str,
        count: uint
    }
    
    impl StringReader {
        fn new(value: &:self str) -> StringReader<:self> {
            StringReader { value: value, count: 0 }
        }
    }
    
    fn remaining(s: &StringReader<:>) -> uint {
        return s.value.len() - s.count;
    }
    
    fn value(s: &:v StringReader<:v>) -> &:v str {
        return s.value;
    }

Option 7. Another alternate syntax for Option 4, where region
parameters appear in `{}`.

    struct StringReader{self} {
        value: &{self} str,
        count: uint
    }
    
    impl StringReader {
        fn new(value: &{self} str) -> StringReader{self} {
                                  //  ^~~~~~~~~~~~~~~~~~ I opted
                                  //  not to include an extra `&`.
            StringReader { value: value, count: 0 }
        }
    }
    
    fn remaining(s: &StringReader{}) -> uint {
                 // ^~~~~~~~~~~~~~~ The trailing `{}` indicate we should
                 // use a default lifetime.  Again we must decide precisely
                 // what this means.  I think the best semantics would be
                 // to take the lifetime of any enclosing `&`.  If there
                 // is no enclosing `&`, it could be an error, or else a
                 // fresh lifetime.
        return s.value.len() - s.count;
    }
    
    fn value(s: &{v} StringReader{v}) -> &{v} str {
        return s.value;
    }

Option 8. Like Option 7, but allow the list of region parameters
to be omitted on reference to a type if you just want the defaults.

    struct StringReader{self} {
        value: &{self} str,
        count: uint
    }
    
    impl StringReader {
        fn new(value: &{self} str) -> StringReader{self} {
            StringReader { value: value, count: 0 }
        }
    }
    
    fn remaining(s: &StringReader) -> uint {
                 // ^~~~~~~~~~~~~ Trailing `{}` not required as we will
                 // use defaults.
        return s.value.len() - s.count;
    }
    
    fn value(s: &{v} StringReader) -> &{v} str {
                 // ^~~~~~~~~~~~~ As above.
        return s.value;
    }

### Conclusion

I am currently leaning towards option 8.  I like using a system of
matching delimeters as it allows for multiple parameters very easily
(e.g., `Context{a, b}`).  Re-using `<>` for both the lifetime
parameters and the type parameters is also appealing to me, but I
can't quite find a way to do it that is unambiguously parsable.
Option 5 is perhaps tolerable.

