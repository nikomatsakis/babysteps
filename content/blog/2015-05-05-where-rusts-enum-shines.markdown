---
layout: post
title: "Virtual Structs Part 1: Where Rust's enum shines"
date: 2015-05-05T06:15:26-0400
comments: true
categories: [Rust]
---

One priority for Rust after 1.0 is going to be incorporating some
kind of support for
["efficient inheritance" or "virtual structs"][349]. In order to
motivate and explain this design, I am writing a series of blog posts
examining how Rust's current abstractions compare with those found in
other languages.

The way I see it, the topic of "virtual structs" has always had two
somewhat orthogonal components to it. The first component is a
question of how we can generalize and extend Rust enums to cover more
scenarios. The second component is integrating virtual dispatch into
this picture.

I am going to start the series by focusing on the question of
extending enums. This first post will cover some of the strengths of
the current Rust `enum` design; the next post, which I'll publish
later this week, will describe some of the advantages of a more
"class-based" approach. Then I'll discuss how we can bring those two
worlds together. After that, I will turn to virtual dispatch, impls,
and matching, and show how they interact.

[349]: https://github.com/rust-lang/rfcs/issues/349

<!-- more -->

### The Rust enum

I don't know about you, but when I work with C++, I find that the
first thing that I miss is the Rust `enum`. Usually what happens is
that I start out with some innocent-looking C++ enum, like
`ErrorCode`:

```cpp
enum ErrorCode {
    FileNotFound,
    UnexpectedChar
};

ErrorCode parse_file(String file_name);
```

As I evolve the code, I find that, in some error cases, I want to
return some additional information. For example, when I return
`UnexpectedChar`, maybe I want to indicate what character I saw, and
what characters I expected. Because this data isn't the same for all
errors, now I'm kind of stuck. I can make a struct, but it has these
extra fields that are only sometimes relevant, which is awkward:

```cpp
struct Error {
    ErrorCode code;
    
    // only relevant if UnexpectedChar:
    Vector<char> expected; // possible expected characters
    char found;
};
```

This solution is annoying since I have to come up with values for all
these fields, even when they're not relevant. In this case, for
example, I have to create an empty vector and so forth.  And of course
I have to make sure not to read those fields without checking what
kind of error I have first. And it's wasteful of memory to boot. (I
could use a `union`, but that is kind of a mess of its own.) All in
all, not very good.

One more structured solution is to go to a full-blown class hierarchy:

```cpp
enum ErrorCode {
    FileNotFound,
    UnexpectedChar
};

class Error {
  public:
    Error(ErrorCode ec) : errorCode(ec) { }
    const ErrorCode errorCode;
};

class FileNotFoundError : public Error {    
  public:
    FileNotFound() : Error(FileNotFound);
};

class UnexpectedChar : public ErrorCode {
  public:
    UnexpectedChar(char expected, char found)
      : Error(UnexpectedChar),
        expected(expected),
        found(found)
    { }
    
    const char expected;
    const char found;
};
```

In many ways, this is pretty nice, but there is a problem (besides the
verbosity, I mean). I can't just pass around `Error` instances by
value, because the size of the `Error` will vary depending on what
kind of error it is. So I need dynamic allocation. So I can change my
`parse_file` routine to something like:

```cpp
unique_ptr<Error> parse_file(...);
```

Of course, now I've wound up with a lot more code, and mandatory
memory allocation, for something that doesn't really seem all that
complicated.

### Rust to the rescue

Of course, Rust enums make this sort of thing easy. I can start out
with a simple enum as before:

```rust
enum ErrorCode {
    FileNotFound,
    UnexpectedChar
}

fn parse_file(file_name: String) -> ErrorCode;
```

Then I can simply modify it so that the variants carry data:

```rust
enum ErrorCode {
    FileNotFound,
    UnexpectedChar { expected: Vec<String>, found: char }
}

fn parse_file(file_name: String) -> ErrorCode;
```

And nothing really has to change. I only have to supply values for
those fields when I construct an instance of `UnexpectedChar`, and I
only read the values when I match a given error. But most importantly,
I don't have to do dummy allocations: the size of `ErrorCode` is
automatically the size of the largest variant, so I get the benefits
of the a `union` in C but without the mess and risk.

### What makes Rust and C++ behave differently?

So why does this example work so much more smoothly with a Rust enum
than a C++ class hierarchy? The most obvious difference is that Rust's
enum syntax allows us to compactly declare all the variants in one
place, and of course we enjoy the benefits of match syntax. Such
"creature comforts" are very nice, but that is not what I'm really
talking about in this post.  (For example, Scala is an example of a
language that offers [great syntactic support][scala] for using
"classes as variants"; but that doesn't change the fundamental
tradeoffs involved.)

[scala]: http://docs.scala-lang.org/tutorials/tour/case-classes.html

To me, the key difference between Rust and C++ is the size of the
`ErrorCode` types. In Rust, the size of an `ErrorCode` instance is
equal to **the maximum of its variants**, which means that we can pass
errors around by value and know that we have enough space to store any
kind of error. In contrast, when using classes in C++, the size of an
`ErrorCode` instance will vary, **depending on what specific variance
it is**. This is why I must pass around errors using a pointer, since
I don't know how much space I need up front. (Well, actually, C++
doesn't *require* you to pass around values by pointer: but if you
don't, you wind up with [object slicing], which can be a particularly
surprising sort of error. In Rust, we have the notion of [DST] to
address this problem.)

[object slicing]: http://stackoverflow.com/questions/274626/what-is-object-slicing
[DST]: http://smallcultfollowing.com/babysteps/blog/2014/01/05/dst-take-5/

**Rust really relies deeply on the flat, uniform layout for
enums**. For example, every time you make a nullable pointer like
`Option<&T>`, you are taking advantage of the fact that options are
laid out flat in memory, whether they are `None` or `Some`. (In Scala,
for example, creating a `Some` variant requires allocating an object.)

### Preview of the next few posts

OK, now that I spent a lot of time telling you why enums are great and
subclassing is terrible, my next post is going to tell you why I think
suclassing is sometimes fantastic and enums kind of annoying.

### Caveat

I'm well aware I'm picking on C++ a bit unfairly. For example, perhaps
instead of writing up my own little class hierarchy, I should be using
`boost::any` or something like that. Because C++ is such an extensible
language, you can definitely construct a class hierarchy that gives
you similar advantages to what Rust enums offer. Heck, you could just
write a carefully constructed wrapper around a C `union` to get what
you want. But I'm really focused here on contrasting the kind of "core
abstractions" that the language offers for handling variants with
data, which in Rust's case is (currently) enums, and in C++'s case is
subtyping and classes.
