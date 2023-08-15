---
categories:
- Rust
comments: true
date: "2011-12-21T00:00:00Z"
slug: tone-and-criticism
title: Tone and criticism
---
So, I worry that my various posts about Rust give the impression that
I'm dissatisfied with the language.  It's true that there are several
things I'd like to change---and those are what I've focused on---but I
want to clarify that I quite like Rust the way it is and I find the
overall feel of the language to be very good.  When it comes to the
big decisions, I think Rust gets it right:

- Low-level control over how data is laid out in memory, but
  high-level, expressive types like vectors, tuples, variadic types,
  lightweight closures
- Ability to use the stack, but safely:
  - Locals can be allocated on the stack
  - Blocks that directly reference the stack that created them
    but do not leak
- Unique pointers for messaging (and possibly other things)
- Immutable by default but mutable when desired
- Static bindings for most calls
- Lightweight tasks with cheap, growable stacks
- A focus on type safety, and particularly on using types to achieve
  goals beyond detecting typos, such as data-race freedom or
  exhaustiveness checking

None of these features are unique to Rust, but the *combination* is
new, and it's powerful.  There are also plenty of small decisions I
think are fantastic:

- Crate files (an idea whose time had come) and the generally
  simple command lines to invoke the compiler
- Syntax: at first I thought `fn` and `ret` were overly terse,
  but after working with them writing out `return` just seems so ponderous.
  Similarly, parentheses-free syntax for `if` is surprisingly pleasant.
- Unsigned types without implicit conversions

I could go on but I guess that's enough.  Anyway I think my point is
that I think Rust has the big picture down pat.  I would like to tweak
how it achieves some of those goals but even if my ideas never make it
or turn out to be flawed (as some of them no doubt are), Rust'll be a
very nice language to use.
