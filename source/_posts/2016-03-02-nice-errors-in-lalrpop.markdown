---
layout: post
title: "Nice errors in LALRPOP"
date: 2016-03-02 12:58:49 -0500
comments: false
categories: [Rust]
---

For the last couple of weeks, my mornings have been occupied with a
pretty serious revamping of [LALRPOP's][lalrpop] error message output. I will
probably wind up doing a series of blog posts about the internal
details of how it works, but I wanted to write a little post to
advertise this work.

Typically when you use an LR(1) parser generator, error messages tend
to be written in terms of the LR(1) state generation algorithm.  They
use phrases like "shift/reduce conflict" and talk about LR(1)
items. Ultimately, you have to do some clever thinking to relate the
error to your grammar, and then a bit more clever thinking to figure
out how you should adjust your grammar to make the problem go away.
While working on [adapting the Rust grammar to LALRPOP][rustypop], I
found I was wasting a lot of time trying to decrypt the error
messages, and I wanted to do something about it. This work
is the result.

**An aside:** It's definitely worth citing [Menhir] as an inspiration,
which is an awesome parser generator for OCaml. Menhir offers a lot of
the same features that LALRPOP does, and in particular generates
errors very similar to those I am talking about here.

[Menhir]: http://gallium.inria.fr/~fpottier/menhir/

What I've tried to do now in LALRPOP is to do that clever thinking for
you, and instead present the error message in terms of your
grammar. Perhaps even more importantly, I've also tried to **identify
common beginner problems and suggest solutions**. Naturally this is a
work-in-progress, but I'm already pretty excited with the current
status, so I wanted to write up some examples of it in action.

<!-- more -->

### Diagnosing ambiguous grammars

Let's start with an example of a truly ambiguous grammar. Imagine that
I have this grammar for a simple calculator (in LALRPOP syntax, which
I hope will be mostly self explanatory):

```rust
use std::str::FromStr;
grammar;
pub Expr: i32 = {
    <n:r"[0-9]+"> => i32::from_str(n).unwrap(),
    <l:Expr> "+" <r:Expr> => l + r,
    <l:Expr> "-" <r:Expr> => l - r,
    <l:Expr> "*" <r:Expr> => l * r,
    <l:Expr> "/" <r:Expr> => l / r,
};
```

This grammar evaluates expressions like `1 + 2 * 3` and yields a
32-bit integer as the result. The problem is that this grammar is
quite ambiguous: it does not encode the precedence of the various
operators in any particular way. The older versions of LALRPOP gave
you a rather opaque error concerning shift/reduce conflicts. As of version
0.10, though, you get this (the actual output even [uses ANSI colors][screenshot],
if available):

```text
calc.lalrpop:6:5: 6:34: Ambiguous grammar detected

  The following symbols can be reduced in two ways:
    Expr "*" Expr "*" Expr

  They could be reduced like so:
    Expr "*" Expr "*" Expr
    ├─Expr──────┘        │
    └─Expr───────────────┘

  Alternatively, they could be reduced like so:
    Expr "*" Expr "*" Expr
    │        └─Expr──────┤
    └─Expr───────────────┘

  Hint: This looks like a precedence error related to `Expr`. See the LALRPOP
  manual for advice on encoding precedence.
```

Much clearer, I'd say! And note, if you look at the last sentence,
that LALRPOP is even able to diagnose that this an ambiguity specifically
about **precedence** and refer you to the manual -- now, if only I'd
**written** the LALRPOP manual, we'd be all set.

I should mention that LALRPOP also reports several other errors, all
of which are related to the precedence. For example, it will also
report:

```text
/Users/nmatsakis/tmp/prec-calc.lalrpop:6:5: 6:34: Ambiguous grammar detected

  The following symbols can be reduced in two ways:
    Expr "*" Expr "+" Expr

  They could be reduced like so:
    Expr "*" Expr "+" Expr
    ├─Expr──────┘        │
    └─Expr───────────────┘

  Alternatively, they could be reduced like so:
    Expr "*" Expr "+" Expr
    │        └─Expr──────┤
    └─Expr───────────────┘

  LALRPOP does not yet support ambiguous grammars. See the LALRPOP manual for
  advice on making your grammar unambiguous.
```

The code for detecting precedence errors however doesn't consider
errors between two distinct tokens (here, `*` and `+`), so you don't
get a specific message, just a general note about ambiguity. This
seems like an area that would be nice to improve.

### Diagnosing LR(1) limitations and suggesting inlining

That last example was a case where the grammar was fundamentally
ambiguous. But sometimes there are problems that have to do with how
LR(1) parsing works; diagnosing these nicely is even more important,
because they are less intuitive to the end user. Also, LALRPOP has
several tools that can help make dealing with these problems easier,
so where possible we'd really like to suggest these tools to users.

Let's start with a grammar for parsing Java import declarations.
Java's import declarations have this form:

```java
import java.util.*;
import java.lang.String;
```

A first attempt at writing a grammar for them might look like this (in
this grammar, I gave all of the nonterminals the type `()`, so there
is no need for action code; this means that this grammar does not
build a parse tree, and so it can only be used to decide if the input
is legal Java or not):

```rust
grammar;

pub ImportDecl: () = {
    "import" Path ";",
    "import" Path "." "*" ";",
};

Path: () = Ident ("." Ident)*;

Ident = r#"[a-zA-Z][a-zA-Z0-9]*"#;
```

Now, unlike before, this grammar is unambiguous. Nonetheless, if we
try to run it through LALRPOP, we will get the following error:

```text
java.lalrpop:8:12: 8:29: Local ambiguity detected

  The problem arises after having observed the following symbols in the input:
    "import" Ident
  At that point, if the next token is a `"."`, then the parser can proceed in
  two different ways.

  First, the parser could execute the production at java.lalrpop:8:12: 8:29,
  which would consume the top 1 token(s) from the stack and produce a `Path`.
  This might then yield a parse tree like
    "import" Ident  ╷ "." "*" ";"
    │        └─Path─┘           │
    └─ImportDecl────────────────┘

  Alternatively, the parser could shift the `"."` token and later use it to
  construct a `("." Ident)+`. This might then yield a parse tree like
    Ident "."        Ident
    │     └─("." Ident)+─┤
    └─Path───────────────┘

  Hint: It appears you could resolve this problem by adding the annotation
  `#[inline]` to the definition of `Path`. For more information, see the section
  on inlining in the LALROP manual.
```

What's interesting is that, in this case, the grammar is not actually
ambiguous. For any given string, there is only one possible parse. The
problem though is that the grammar **as it is written** requires more
than one token of lookahead. To understand why, you have to think like
an LR(1) parser -- which really isn't as complicated as it sounds. As
usually happens with computers, the hard part is not understanding how
**wicked smart** the LR(1) algorithm is, it's understanding just how
**plain dumb** it is.

Basically, the way an LR(1) parser works is that it takes one token at
a time from your input and tries to match up what it has seen so far
against the productions in your grammar. If it finds a match, it can
**reduce**, which basically means that it can "recognize" the last few
tokens as something larger. But, and this is the key point, it can
only do a reduction when it is at exactly the right point in the
input. So, for example, consider the definition of `ImportDecl`:

```
pub ImportDecl: () = {
    "import" Path ";",
    "import" Path "." "*" ";",
};
```

Imagine that we are parsing an input like:

```java
import foo.bar.*;
```

The first thing that would happen then is that we would see an
`"import"` token. An `"import"` is the *start* of an `ImportDecl`, but
it alone is not enough to say for sure if we have a valid `ImportDecl`
yet. So we would push it on the stack. The next token is an identifier
(`"foo"`). We don't see any identifiers listed in the definition of `ImportDecl`,
but we *do* see a `Path`, and a `Path` is defined like so:

```rust
Path: () = Ident ("." Ident)*;
```

So maybe this identifier is the start of a `Path`. Still, too early to
say for sure. We would then push the identifier onto the stack and
look at the next token. The next token will be a `"."`. This is
promising, since to make a `Path`, we have to first see an identifier
(which we did) and then zero or more `("." Ident)` pairs. So this
`"."` could be the start of such a pair. So we might imagine that we should
push it on the stack and keep going, expecting to see a `Path`. Then
we'd have a stack like:

```text
"import" Ident "." 
```

Now, for the input `import foo.bar.*`, in fact, pushing the `.` onto
the stack *would* be the right thing to do. But for other inputs, it
would not be. Imagine that our input was `import foo.*;`. If we pushed
the `.` onto the stack, then we would eventually wind up with a stack
that looks like this:

```text
"import" Ident "." "*" ";"
```

Now we have a real problem. To a human, this is clearly an `ImportDecl`;
in particular, it matches this production:

```text
ImportDecl = "import" Path "." "*" ";"
```

But to the computer, this is not a match at all. The second thing
listed after `"import"` should be a *path* not an *identifier*. Now of
course there is a rule that lets us convert an `ident` to a path, but
it's too late to use it. We can only do a conversion when the thing we
are converting is the last thing we have seen. In particular here we'd
need to ignore the last three tokens (`"." "*" ";"`) and just convert
the `Path` that lies above them. The LR(1) parser is not smart enough
to do that (which is why it can parse in linear time).

The way I described things, this conflict arises at parse time -- but
in fact the LR(1) generation algorithm can detect ahead of time that
this could happen, which is why you are getting an error.

So how can we solve this? The answer is that we can rearrange our
grammar.  What's kind of surprising about LR(1) is that seemingly
"no-op" rearrangements can make a big difference. **This is precisely
beacuse in order for the parser to recognize a nonterminal, it must do
so at the very moment when those symbols are seen -- it can't do it
after the fact.** This has some significance to the semantics of a
grammar.  That is, normally, you can rely on the fact that your action
code will execute **precisely** when the tokens that you list are
seen, no later and no earlier. This may matter if your action code has
side-effects. (In the case of this grammar, we have no action code, so
there are clearly no side-effects.)

This also means that we can solve LR(1) conflicts by rearranging
things so that the parser doesn't have to make a decision as soon. So
imagine that we transformed our grammar by "inlining" the `Path`
nonterminal into the `ImportDecl`, and be further converting the `("." Ident)*`
entries into `("." Ident)+` (as well as another option where there are no pairs at all).
Then we would have:

```rust
grammar;

pub ImportDecl: () = {
    "import" Ident ";",
    "import" Ident "." "*" ";", // (*)
    "import" Ident ("." Ident)+ ";",
    "import" Ident ("." Ident)+ "." "*" ";",
};

Ident = r#"[a-zA-Z][a-zA-Z0-9]*"#;
```

Now, this version is equivalent to what we had before, in that it
parses the same inputs. But to the parser, it looks very different. In
particular, we no longer have to first recognize that an identifier is
a `Path` to produce an `ImportDecl`. As you can see in the second
production (indicated with a `(*)` comment) we can now directly
recognize `"import" Ident "." "*" ";"` as an `ImportDecl`.  In other
words, the parse which got stuck before now works just fine.

This technique of inlining one nonterminal into another is very common
and very effective for making grammars compatible with
LR(1). Therefore, it's actually automated in LALRPOP. All you have to
do is annotate a nonterminal with `#[inline]` and the preprocessor
will handle it for you (moreover, the preprocessor automatically
converts `Foo*` into two options, one without `Foo` at all, and one
with `Foo+`).

In fact, if we go back to the original error report,
we can see that LALRPOP recognized what was happening and even advised
us that we may want to add a `#[inline]` attribute:

```text
  Hint: It appears you could resolve this problem by adding the annotation
  `#[inline]` to the definition of `Path`. For more information, see the section
  on inlining in the LALROP manual.
```

You may be wondering why LALRPOP doesn't just inline
automatically. There are a couple of reasons:

1. It's hard to tell for sure when inlining will help. I have some
   heuristics to detect some situations, but I can't detect them all,
   and sometimes the suggestion may be inappropriate.
2. Inlining makes your grammar bigger.
3. Inlining changes when you action code runs, so it effectively alters
   your program semantics.
4. Even if we could detect when to inline, it would happen relatively late
   in the cycle, and so we would have to start from the beginning. By having
   the user add an attribute, we know from the beginning when to inline,
   and so subsequent LALRPOP instantiations are faster.

Finally, inlining may just not be the best fix. For example, the
change I would *actually* make to that grammar would probably be to
convert it as follows:

```rust
grammar;

pub ImportDecl: () = {
    "import" Path ";",
    "import" Path "." "*" ";",
};

Path: () = {
    Ident,
    Path "." Ident,
};    

Ident = r#"[a-zA-Z][a-zA-Z0-9]*"#;
```

If you work it through, you will find that this grammar IS `LR(1)`,
and it doesn't use any inlining at all. That means it will have fewer
states.  I also find it more readable. But YMMV.

### Where to from here?

First off, I really want to rework the phrasings of those error
messages. They should not (I think) talk about "popping states" and so
forth. But I've got to spend some time thinking about how best to
explain the LR(1) algorithm. This blog post is kind of a first stab,
but it proved much harder than I expected, and I think I could
certainly make it much clearer than what I've achieved thus far! :)
There are also a host of other smaller improvements that can be made.

All of that said, I am currently hard at work on exploring the
[lane table] generation algorithm and other variations on LR(1). This
may lead to some insights into how to present errors, I'm not sure.
This may also lead to some ideas for how to automate inlining further,
or other scenarios where I can make tailored suggestions.  We'll just
have to see!

I've got a few parsing related blog posts I hope to read over the
next few weeks:

- the "ascii art" library that I wrote to format the error messages
  is itself kind of interesting;
- how the error report generation works under the hood;
- an explanation of the [lane table][] algorithm, which is rather
  underdocumented (but I'm still figuring it out myself);
- [rustypop][], my Rust grammar in LALRPOP, is coming along, and I want
  to use it as a springboard to talk about some of LALRPOP's macro features.

So, if parsing interests you, then stay tuned.

[lane table]: http://cssauh.com/xc/pub/LaneTable_APPLC12.pdf
[rustypop]: https://github.com/nikomatsakis/rustypop
[lalrpop]: http://smallcultfollowing.com/babysteps/blog/2015/09/14/lalrpop/
[screenshot]: http://imgur.com/nHdMXt5
