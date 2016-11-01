---
layout: post
title: "Attribute and macro syntax"
date: 2014-09-11 07:33
comments: true
categories: [Rust]
---

A few weeks back pcwalton introduced a [PR][pr] that aimed to move the
attribute and macro syntax to use a leading `@` sigil. This means that
one would write macros like:

    @format("SomeString: {}", 22)
    
or

    @vec[1, 2, 3]
    
One would write attributes in the same way:

    @deriving(Eq)
    struct SomeStruct {
    }
    
    @inline
    fn foo() { ... }

This proposal was controversial. This debate has been sitting for a
week or so. I spent some time last week reading every single comment
and I wanted to lay out my current thoughts.

### Why change it?

There were basically two motivations for introducing the change.

**Free the bang.** The first was to "free up" the `!` sign. The
initial motivation was aturon's error-handling RFC, but I think that
even if we decide not to act on that specific proposal, it's still
worth trying to reserve `!` and `?` for *something* related to
error-handling. We are very limited in the set of characters we can
realistically use for syntactic sugar, and `!` and `?` are valuable
"ASCII real-estate".

Part of the reason for this is that `!` has a long history of being
the sigil one uses to indicate something dangerous or
surprising. Basically, something you should pay extra attention
to. This is partly why we chose it for macros, but in truth macros are
not *dangerous*. They can be mildly surprising, in that they don't
necessarily act like regular syntax, but having a distinguished macro
invocation syntax already serves the job of alerting you to that
possibility. Once you know what a macro does, it ought to just fade
into the background.

**Decorators and macros.** Another strong motivation for me is that I
think attributes and macros are two sides of the same coin and thus
should use similar syntax. Perhaps the most popular attribute --
`deriving` -- is literally nothing more than a macro. The only
difference is that its "input" is the type definition to which it is
attached (there are some differences in the implementation side
presently -- e.g., deriving is based off the AST -- but as I discuss
below I'd like to erase that distiction eventually). That said, right
now attributes and macros live in rather distinct worlds, so I think a
lot of people view this claim with skepticism. So allow me to expand
on what I mean.

### How attributes and macros ought to move closer together

Right now attributes and macros are quite distinct, but looking
forward I see them moving much closer together over time. Here are
some of the various ways.
    
**Attributes taking token trees.** Right now attribute syntax is kind
of specialized. Eventually I think we'll want to generalize it so that
attributes can take arbitrary token trees as arguments, much like
macros operate on token trees (if you're not familiar with token
trees, see the appendix). Using token trees would allow more complex
arguments to deriving and other decorators. For example, it'd be great
to be able to say:

    @deriving(Encodable(EncoderTypeName<foo>))
    
where `EncoderTypeName<foo>` is the name of the specific encoder that
you wish to derive an impl for, vs today, where deriving always
creates an encodabe impl that works for all encoders. (See
[Issue #3740][3740] for more details.) Token trees seem like the
obvious syntax to permit here.

**Macros in decorator position.** Eventually, I'd like it to be possible
for any macro to be attached to an item definition as a decorator. The
basic idea is that `@foo(abc) struct Bar { ... }` would be syntactic
sugar for (something like) `@foo((abc), (struct Bar { ... }))`
(presuming `foo` is a macro).

*An aside:* it occurs to me that to make this possible before 1.0 as I
envisioned it, we'll need to at least reserve macro names so they
cannot be used as attributes. It might also be better to have macros
declare whether or not they want to be usable as decorators, just so
we can give better error messages. This has some bearing on the
"disadvantages" of the `@` syntax discussed below, as well.

Using macros in decorator position would be useful for those cases
where the macro is conceptually "modifying" a base fn
definition. There are numerous examples: memoization, some kind of
generator expansion, more complex variations on deriving or
pretty-printing, and so on. A specific example from the past was the
`externfn!` wrapper that would both declare an `extern "C"` function
and some sort of Rust wrapper (I don't recall precisely why). It was
used roughly like so:

    externfn! {
        fn foo(...) { ... }
    }

Clearly, this would be nicer if one wrote it as:

    @extern
    fn foo(...) { ... }
    
**Token trees as the interface to rule them all.** Although the idea
of permitting macros to appear in attribute position seems to largely
erase the distinction between today's "decorators", "syntax
extensions", and "macros", there remains the niggly detail of the
implementation.  Let's just look at `deriving` as an example: today,
`deriving` is a transform from one AST node to some number of AST
nodes. Basically it takes the AST node for a type definition and emits
that same node back along with various nodes for auto-generated impls.
This is completely different from a macro-rules macro, which operates
only on token trees. The plan has always been to remove deriving out
of the compiler proper and make it "just another" syntax extension
that happens to be defined in the standard library (the same applies
to other standard macros like `format` and so on).

In order to move `deriving` out of the compiler, though, the interface
will have to change from ASTs to token trees. There are two reasons
for this. The first is that we are simply not prepared to standardize
the Rust compiler's AST in any public way (and have no near term plans
to do so). The second is that ASTs are insufficiently general.  We
have syntax extensions to accept all kinds of inputs, not just Rust
ASTs.
    
Note that syntax extensions, like deriving, that wish to accept Rust
ASTs can easily use a Rust parser to parse the token tree they are
given as input. This could be a cleaned up version of the `libsyntax`
library that `rustc` itself uses, or a third-party parser module
(think Esprima for JS). Using separate libraries is advantageous for
many reasons. For one thing, it allows other styles of parser
libraries to be created (including, for example, versions that support
an extensible grammar). It also allows syntax extensions to pin to an
older version of the library if necessary, allowing for more
independent evolution of all the components involved.

### What are the objections?

There were two big objections to the proposal:

1. Macros using `!` feels very lightweight, whereas `@` feels more
   intrusive.
2. There is an inherent ambiguity since `@id()` can serve as both an
   attribute and a macro.
   
The first point seems to be a matter of taste. I don't find `@`
particularly heavyweight, and I think that choosing a suitable color
for the emacs/vim modes will probably help quite a bit in making it
unobtrusive. In constrast, I think that `!` has a strong connotation
of "dangerous" which seems inappropriate for most macros. But neither
syntax seems particularly egregious: I think we'll quickly get used to
either one.

The second point regarding potential ambiguities is more
interesting. The ambiguities are easy to resolve from a technical
perpsective, but that does not mean that they won't be confusing to
users.

#### Parenthesized macro invocations

The first ambiguity is that `@foo()` can be interpreted as either an
attribute or a macro invocation. The observation is that `@foo()` as a
macro invocation should behave like existing syntax, which means that
either it should behave like a method call (in a fn body) or a tuple
struct (at the top-level). In both cases, it would have to be followed
by a "terminator" token: either a `;` or a closing delimeter (`)`,
`]`, and `}`). Therefore, we can simply peek at the next token to
decide how to interpret `@foo()` when we see it.

I believe that, using this disambiguation rule, almost all existing
code would continue to parse correctly if it were mass-converted to
use `@foo` in place of the older syntax. The one exception is
top-level macro invocations. Today it is common to write something
like:

    declaremethods!(foo, bar)
    
    struct SomeUnrelatedStruct { ... }

where `declaremethods!` expands out to a set of method declarations or
something similar.

If you just transliterate this to `@`, then the macro would be parsed
as a decorator:

    @declaremethods(foo, bar)
    
    struct SomeUnrelatedStruct { ... }

Hence a semicolon would be required, or else `{}`:

    @declaremethods(foo, bar);
    struct SomeUnrelatedStruct { ... }

    @declaremethods { foo, bar }
    struct SomeUnrelatedStruct { ... }

Note that both of these are more consistent with our syntax in
general: tuple structs, for example, are always followed by a `;` to
terminate them.  (If you replace `@declaremethods(foo, bar)` with
`struct Struct1(foo, bar)`, then you can see what I mean.) However,
today if you fail to include the semicolon, you get a parser error,
whereas here you might get a surprising misapplication of the macro.

#### Macro invocations with braces, square or curly

Until recently, attributes could only be applied to items. However,
recent RFCs have proposed extending attributes so that they can be
applied to blocks and expressions. These RFCs introduce additional
ambiguities for macro invocations based on `[]` and `{}`:

- `@foo{...}` could be a macro invocation or an annotation `@foo`
  applied to the block `{...}`,
- `@foo[...]` could be a macro invocation or an annotation `@foo`
  applied to the expression `[...]`.
    
These ambiguities can be resolved by requiring inner attributes for
blocks and expressions. Hence, rather than `@cold x + y`, one would
write `(@!cold x) + y`.  I actually prefer this in general, because it
makes the precedence clear.

### OK, so what are the options?

Using `@` for attributes is popular. It is the use with macros that is
controversial. Therefore, how I see it, there are three things on the
table:

1. Use `@foo` for attributes, keep `foo!` for macros (status quo-ish).
2. Use `@foo` for both attributes and macros (the proposal).
3. Use `@[foo]` for attributes and `@foo` for macros (a compromise).

Option 1 is roughly the status quo, but moving from `#[foo]` to `@foo`
for attributes (this seemed to be universally popular). The obvious
downside is that we lose `!` forever and we also miss an opportunity
to unify attribute and macro syntax. We can still adopt the model
where decorators and macros are interoperable, but it will be a little
more strange, since they look very different.

The advantages of Option 2 are what I've been talking about this whole
time. The most significant disadvantage is that adding a semicolon can
change the interpretation of `@foo()` in a surprising way,
particularly at the top-level.

Option 3 offers most of the advantages of Option 2, while retaining a
clear syntactic distinction between attributes and macro usage. The
main downside is that `@deriving(Eq)` and `@inline` follow the
precedent of other languages more closely and arguably look cleaner
than `@[deriving(Eq)]` and `@[inline]`.

### What to do?

Currently I personally lean towards options 2 or 3. I am not happy
with Option 1 both because I think we should reserve `!` and because I
think we should move attributes and macros closer together, both in
syntax and in deeper semantics.

Choosing between options 2 and 3 is difficult. It seems to boil down
to whether you feel the potential ambiguities of `@foo()` outweigh the
attractiveness of `@inline` vs `@[inline]`. I don't personally have a
strong feeling on this particular question. It's hard to say how
confusing the ambiguities will be in practice. I would be happier if
placing or failing to place a semicolon at the right spot yielded a
hard error.

So I guess I would summarize my current feeling as being happy with
either Option 2, but with the proviso that it is an error to use a
macro in decorator position unless it explicitly opts in, or Option 3,
without that proviso. This seems to retain all the upsides and avoid
the confusing ambiguities.

### Appendix: A brief explanation of token trees

Token trees are the basis for our macro-rules macros. They are a
variation on token streams in which tokens are basically uninterpreted
except that matching delimeters (`()`, `[]`, `{}`) are paired up. A
macro-rules macro is then "just" a translation from a token tree to
another token. This output token tree is then parsed as
normal. Similarly, our parser is actually not defined over a *stream*
of tokens but rather a *token tree*.

Our current implementation deviates from this ideal model in some
respects.  For one thing, macros take as input token trees with
embedded asts, and the parser parses a stream of tokens with embedded
token trees, rather than token trees themselves, but these details are
not particularly relevant to this post. I also suspect we ought to
move the implementation closer to the ideal model over time, but
that's the subject of another post.


[pr]: https://github.com/pcwalton/rfcs/blob/unify-attributes-and-macros/active/0000-unify-attributes-and-macros.md
[3740]: https://github.com/rust-lang/rust/issues/3740
