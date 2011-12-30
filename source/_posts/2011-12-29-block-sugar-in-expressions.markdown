---
layout: post
title: "Block sugar in expressions"
date: 2011-12-29 07:30
comments: true
categories: [Rust]
---

**UPDATE:** I found some more complications.  Updates inline.

I have been working on and off on allowing block sugar to appear in
Rust expressions and not only statements.  For those who do not know
what I am talking about, let me give a bit of context.  At the moment,
one can write the following in Rust:

    vec::iter(v) { |e| 
       ...
    }
    
which is sugar for the function call:

    vec::iter(v, { |e| 
       ...
    })
    
Objectively, there isn't much difference between the two, but somehow
pulling the `{||}` out of the parentheses feels much lighter to me.

However, today, this sugar is only allowed in statements.  That is,
the result of the call to `vec::iter()` is ignored.  For
`vec::iter()`, this makes sense, since the result is unit.  But it
might also be nice to be able to write:

    let foo = vec::map(v) { |e|
        ...
    };
    
or:

    let child = task::spawn { ||
        ...
    };

In implementing this, however, I've run into a few dark corners of the
syntax.  I'm trying to find the best way to support such sugar with
minimal changes to the language.

#### The problem

Today we attempt to determine *in the parser* whether an expression
may yield a usable value.  In the case of expressions that double as
statements, this is generally specified by the presence or absence of
a trailing semicolon.  In the case of blocks and other compound
statements, the presence or absence of a semicolon in the final
expression within the block is significant.  Therefore, we can have
something like:

    fn foo(...) -> T {
        if expr1 {
              if expr2 { expr3 } else { expr4 }
        } else {
              expr5
        }
    }

This is a function which returns a value.  This is very different from
the same code with semicolons:

    fn foo(...) {
        if expr1 {
              if expr2 { expr3; } else { expr4; };
        } else {
              expr5;
        }
    }
    
This is code that executes but the result values are ignored.

This system doesn't work so well with the syntactic sugar, as
`vec::iter(v) { |e| ... }` and `vec::map(v) { |e| ... }` both look the
same, but the latter produces a value.  Therefore, the parser is
unable to distinguish between them to decide whether the expression
produces a value or not.

This ambiguity only becomes significant if the sugared expression
appears at the top-level of a block (e.g., where it can be interpreted
as a statement).  Here we can distinguish between two cases:

##### Case 1: In the middle of a block

Consider a block like:

    {
        foo {|| ... }
        -10
    }
    
How do I interpret this?  Based on the whitespace, it appears to
have been intended this way:

    { foo({|| ... }); -10 }
    
But it could also be parsed this way:

    { foo({|| ... }) - 10 }
    
I solved this with a simple rule: in a top-level expression, the
block sugar cannot be followed by binary operators, calls, fields,
etc.  Therefore, we would parse this block as two statements.  I and
others that I have asked find the other alternative (`foo {|| ...} -
10` as an expression) visually hard to parse.  If you want this, use
explicit parentheses.

##### Case 2: Tail position in a block

Does a block like `{ foo {|| ...} }` produce a value or not?  This is
trickier than the other option.

#### Solutions

I see four possible solutions to the "tail position" problem,
and I summarize them as follows:

- **Yes, it does produce a value.**
- **No, it does not produce a value.**
- **It depends on where the block appears.**
- **The parser shouldn't be doing this anyway.**

Let me spell out these possible solutions in more detail.

#### "Yes, it does produce a value."

This creates a distinction between loops like `while {...}` and loops
like `func(v) {...}`; while loops *always* have unit type but
`func(v) {...}` may not.  Today, however, that produces an error for a
snippet like this:

    while cond {
        vec::iter(v) { ... }
    }

This is because the parser requires that while loop blocks do not have
an expression in tail position, and `vec::iter()` counts as such a
block.  We would therefore require a semicolon in such cases.  This
feels weird to me.

We can solve this by modifying the parser.  There are a few options,
but I think the most consistent overall is to permit expressions in
while loop bodies and elsewhere, but require them to have unit type.
This means that the above example would work, but a call to
`vec::any()` would not (it produces a boolean value) and neither would
a tail expression like `10` (it produces an int value).  Those would
require a trailing semicolon.

**UPDATE:** This solution can lead to some complications.  Consider
code like the following:

    fn foo() {
        if cond {
            vec::iter(v) { ... }
        } else {
            vec::iter(v) { ... }
        }
        
        bar();
    }
    
The first `if/else` now looks like an expression, because both blocks
produce a value (albeit a value of type unit).  In other words, the
`if/else` is classified the same as an `if/else` like `if cond { 10 }
else { 20 }` by the parser.  These "value-bearing" if/else expressions
require semicolons.  Therefore, the example doesn't parse.  To solve
this, we say that `if/else`, `alt`, `do/while`, and standalone blocks
never require semicolons when used at top-level.  

I find this more consistent anyhow.  Basically there is a category of
"dual-purpose" (statement and expression) forms.  These include
"keyword" expressions (`if`, `alt`, `while`, etc), standalone blocks,
and syntactic sugar calls.  If these dual-purpose expressions appear
at top-level, they are a statement.  Otherwise, they are an
expression.
  
#### "No, it does not produce a value."

We could also say that a top-level expression never produces a value.
This feels consistent with the rule for top-level expressions that
appear in the middle of a block.  However, this solution disallows a
statement like:

    let w =
      if true { vec::any(abs_v) { |e| float::nonnegative(e) } }
      else { false };

Here, the call to `vec::any()` is clearly intended to be used an
expression, but the parser interprets it as a statement, and so we get
a type error `expected () but found bool`.  The problem here is
insufficient context: the *block itself* appears in an expression
position, so it seems reasonable that the tail position of such a
block be treated as an expression!  This leads us to our next
solution.

#### "It depends on where the block appears."

We can distinguish in the parser between blocks that appear in an
expression position and those that do not.  The key problem here
becomes function items themselves.  For example:

    fn foo() -> bool {
        ...
        vec::any(abs_v) { |e| float::nonnegative(e) }
    }
    
Is this call to `vec::any()` an expression?  The block here appears as
the body of a function, so it's a bit hard to say.  I would like the
answer to be yes.  We could achieve this by examining the return type
of the function being parsed: if it is unit (or unspecified, which
defaults to unit) then we can parse the function body as a block in
statement position.  This means that `foo()` above would parse (and
type check).  In `bar()`:
 
This works well for functions, but the parser doesn't always have
enough context to make this decision:

    fn foo() {
        vec::iter(v) { |e|
            vec::any(abs_v) { |e| float::nonnegative(e) }
        }
    }

Is this call to `vec::any()` intended as an expression?  As it
happens, `vec::iter()` expects a block argument with unit result type;
so to follow our context-sensitive rules, `vec::any()` must be a
statement, but of course the parser doesn't know that, and so the user
would have to put a semicolon. This leads us to our *next* solution.

#### "The parser shouldn't be doing this anyway."

We can have the parser say that the last expression in a block is
always an expression and not a statement, and just have the type
checker perform the context-dependent reasoning: any time that a block
is checked in a context where a unit result is expected, the type of
the tail expression is ignored.  This makes all of our examples
work but is mildly more permissive than the language today.  For example,
this code would type check:

    fn foo() {
        10
    }

This is because `foo()` has a unit result type, so the type of the
tail expression (`int`) is ignored.  Most likely the result type of
`foo()` was accidentally omitted.  I think this is acceptable, though,
because the user will notice that the return type of `foo()` is missing
when they try to call it elsewhere in the code.

**UPDATE:** This also requires distinguishing "dual-purpose"
statements as described in the first solution ("yes, it does produce a
value").  In fact, both the first and fourth solution are kind of the
same, but the fourth involves a bit more work in the type checker to
allow users to omit semicolons somewhat more often.

#### So what should I do?

I don't know but I am leaning towards the first or final solutions, as
they seem the most consistent.  To be honest I am most concerned with
finding a rule that's easy enough to explain and understand.  I don't
want people to feel that the parsing rules are too confusing.

