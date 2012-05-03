---
layout: post
title: "Borrowing"
date: 2012-05-01 19:53
comments: true
categories: [Rust]
---

I've been working for the last few days on the proper safety
conditions for borrowing.  I am coming into a situation where I am not
sure what would be the best approach.  The question boils down to how
coarse-grained and approximate our algorithm ought to be: in
particular, ought it to be flow sensitive?  But let me back up a bit, first,
and provide a bit of background.

## Background

Rust bucks the "new language" trend by not having a purely
garbage-collected model.  We feature things like interior and unique
types which can be eagerly overwritten.  This means that we have to be
very careful when we create temporary references to those kinds of
values that these references remain valid.

Here is an example of unsafe code:

    fn main() {
        let mut v = [1, 2, 3];
        for vec::each(v) { |i|
            v = [];
        }
    }
    
What is happening here is that we are iterating over the vector `v`
but, during the iteration, setting the local variable to be the empty
vector.  Because vectors are unique, this will cause the original
vector to be immediately freed---while the iteration is occurring!

Now, Rust today has an alias checker which is supposed to prevent
these sorts of errors.  However, it has some flaws: for one thing, it
admits that erroneous program I just showed you (that's just a
bug). For another, the check is rather complex.  Sufficiently complex
that I don't really understand the conditions that it is enforcing.
The core is a type-based alias analysis that tries to figure out what
kinds of data a function could possibly reach. But when it finds
potentially dangerous aliasing going on, the algorithm will sometimes
silently copy the data in question, if that seems harmless enough, or
other times issue warnings or report errors.

In defense of the current algorithm, however, the fact is that if you
want to remain flexible and not force programmers into too many
contortions, it's hard to come up with a simple set of rules.  We'll
see that as I go on.

### An alternative

I have been working on a simpler alternative which is based more on
types and less on alias analysis.  The original idea was to base this
analysis purely on the declared mutability of local variables, fields,
and so forth.  We would then conservatively reject programs where
memory safety relied on a potentially mutable location not being
mutated.

I think, however, that I've decided this is so conservative as to be
unusable.  Consider this harmless program, for example:

    let mut v = [1, 2, 3];
    let l = vec::len(v)
    
Under the rules I just gave you, this program would in fact be
illegal.  The reason is that vectors and unique and `vec::len()` is
created a transient reference to the vector it takes as argument.  The
safety analysis however sees that the local variable `v` is declared
as mutable, and thus consider this unsafe to be unsafe: what if `v`
were somehow changed by `vec::len()`?

Of course, we know that this is impossible.  `vec::len()` cannot just
gin up a pointer into the caller's stack frame (well, not without an
`unsafe` block, anyway).  In this case, that's pretty obvious: we
never even took the address of `v`.  The question is where you draw
the line.  How intelligent should the compiler get?  In general,
smarter seems better, but there are two countervailing forces: (1) if
the analysis is too complex, it's hard to tell why it's giving you an
error; (2) the more complex the analysis, the greater the chance of
bugs in the safety checker itself.  Let me tell you, it's not fun to
spend a day tracking down a memory bug that the language supposedly
guarantees to be impossible.

I've been working on a compromise analysis which does not attempt to
do alias analysis but which *does* track which parts of the stack
frame are aliased or may be borrowed.  The analysis makes very
conservative assumptions about what a function can reach: it assumes
that if a non-unique pointer exists to a given memory location, the
function can access it.  Using this analysis, we can allow functions
to borrow data that is stored in mutable variables that are not
modified, so long as the address of those mutable variables was not
taken.

Under these rules, the `vec::len()` example is fine.  An example like this
is also fine:

    let mut v = [1, 2, 3];
    for vec::each(v) { |i|
        io::print(#fmt("%d", i));
    }
    v = [];

Here, we iterate over the vector `v` and then, after the iteration,
clear `v` to the empty vector.  This mutation is fine because the
reference to the vector created in `vec::each()` only had a lifetime
equal to the for loop itself.

The example we saw before, where the vector is assigned not after the
loop but rather in the middle, would of course still fail to compile:

    let mut v = [1, 2, 3];
    for vec::each(v) { |_|
        v = [];
    }
    
Specifically, the analysis would report that the assignment to `v`
inside the loop conflicts with the borrow of `v` on the line before.
In effect, although the variable `v` is declared as mutable, it
becomes *temporarily immutable* during the loop.

### The algorithm at a high-level

The key ideas that the algorithm tries to enforce is this:

- borrowing an `@T` pointer is safe regardless of where it is stored,
  because we can just temporarily increase the ref count of the pointer
  for the duration of the loan;
- borrowing a `~T` pointer (or a unique vector) is safe if it is
  stored in a location that can be considerd immutable for the
  duration of the loan.
  
We can consider a location be immutable under two conditions:

- the type system guarantees it to be immutable.  For example, the
  contents of a box of type `@T` are immutable, as is the value of a
  local variable that is not declared as mutable (with one exception,
  see below);
- the location is uniquely tied to the stack frame itself and the compiler
  does not observe any assignments to that location, nor are there any
  mutable aliases in scope.
  
The first case is the simple set of rules I wanted to enforce earlier.
The second case is the more complex set I described later, where can
say that a local variable is "temporarily immutable".  In fact, we can
go a bit further than just local variables, and also talk about the
contents of records stored in the stack, or the contents of unique
pointers found in the stack, or sequences of such things.  All of
those cases share the property that, unless the user takes their
address with the `&` operator, they cannot be aliased outside the
function itself.
  
That means that we would accept any of the following equivalent programs:

    let mut v = [1, 2, 3];
    for vec::each(v) { |i|
        io::print(#fmt("%d", i));
    }
    v = [];

    let r = {mut v: [1, 2, 3]};
    for vec::each(r.v) { |i|
        io::print(#fmt("%d", i));
    }
    r.v = [];

    let u = ~mut [1, 2, 3];
    for vec::each(*u) { |i|
        io::print(#fmt("%d", i));
    }
    *u = [];

However, we would reject this similar-looking program:

    let b = @mut [1, 2, 3];
    for vec::each(*b) { |i|
        io::print(#fmt("%d", i));
    }
    
The reason that this program is rejected is that we assume that
`vec::each()` has access to every `@T` value (to put it another way,
we assume that every [aliasable value escapes][ea]).  So that means we
cannot prove that `vec::each()` will not overwrite the contents of
`*b` (a more involved analysis might be able to see that `b` itself is
never leaked out of the stack frame).

[ea]: http://en.wikipedia.org/wiki/Escape_analysis

If you want to have unique pointers within mutable boxes, you have to
bring them into your stack frame to work with them, generally making
use of the little known swap operator `<->`.  For example, the prior
program might be written:

    let b = @mut [1, 2, 3];
    let v = [];
    *b <-> v; // bring [1, 2, 3] into our stack frame
    for vec::each(v) { |i|
        io::print(#fmt("%d", i));
    }
    *b <-> v; // replace it
    
This limitation is basically the same as that taken by other unique
pointer systems.

This is one corner case I haven't discussed yet.  Even immutable local
variables can be *moved* (sent, for example, to another thread).  So
we have to remember which immutable local variables are in use and
prevent moves from occurring.

## And now... the question I have been leading up to. 

Until now I haven't talked at all about the `&` operator.  One of the
nice features enabled by the work on references and pointer lifetimes
is to allow the user to take the address of a variable on the stack
(previously, this could only be done implicitly through reference-mode
arguments).  This feature *is* handy, and I'm a big fan of making
modifications to the local stack frame explicit, but it also
introduces complications.  Consider this variant of our usual example:

    let mut v = [1, 2, 3];
    let w = &mut v;
    for vec::each(v) { |i| ... }

My check would actually reject this program.  The reason is that it
assumes `vec::each()` has access to all aliased data---including `w`.
Therefore, as in the case of `@mut T` types, we cannot prevent
`vec::each()` from overwriting `v` indirectly by modifying `*w`.  Here
you would get an error which points out that the existence of an
in-scope alias for `v` means that it cannot be borrowed by
`vec::each()`.  This seems reasonable to me.

But how smart is the compiler?  For example, is this program allowed?

    let mut v = [1, 2, 3];
    let mut x = [4, 5, 6];
    let mut w = &mut x;
    for vec::each(v) { |i|
        w = &mut v;
    }

Now, on the first iteration of the loop, `v` is unaliased, but it
becomes aliased during the loop.  Under our normal assumptions, then,
this program must be rejected, for fear of `vec::each()` assigning to
`*w` sometime after the first iteration.

Ok, what about this program:

    let mut v = [1, 2, 3];
    for vec::each(v) { |i| ... }
    let mut w = &mut v;
    
Here I have moved the alias so it comes after `vec::each()`.  This
should presumably be ok.

But there is one wrinkle.  Sometimes it is hard to say when code will
execute, particularly around closures.  For example:

    let mut x = [4, 5, 6];
    let mut v = [1, 2, 3];
    let mut w = &x;
    debug::indent({||
        for vec::each(v) { |i| ... }
        w = &mut v;
    })
    
Here, the function `debug::indent` presumably does something like
cause all debug messages that occur during its argument to be
indented.  So it probably only runs the argument closure once.  But we
don't know that.  So we'd have to reject this program, just in case 
`debug::indent()` called its closure argument twice.

A similar problem crops up if we allow stack closures (as opposed to
the various kinds of copying closures) to be assigned to variables.
This is currently illegal but which I wouldn't mind making it legal
someday.  But then a flow-sensitive analysis would have to understand
(and reject, in this case) code like this:

    let mut x = [4, 5, 6];
    let mut v = [1, 2, 3];
    let mut w = &x;
    let foo = fn&() {
        for vec::each(v) { |i| ... }
        w = &mut v;
    };
    foo();
    foo();

Now on the second call to `foo()` it's possible that `vec::each()`
might have access to `w`.

## So the options:

So here are various options from dumb to smart:

1. the compiler does a flow-insensitive analysis with respect to which
   references exist.  *All* of the examples in the previous section
   are illegal.  To make them safe, you have to explicitly introduce a block,
   like:
  
        let mut v = [1, 2, 3];
        for vec::each(v) { |i|
            ...
        }
        
        {
            let w = &mut v; // limit the scope of `&`
        }

2. the flow-sensitive analysis rules I described in the previous
   section are ok, when things are unclear just do your best;
3. this whole analysis is too dumb.  It should try to determine which
   references actually escape the stack frame and track what they point
   at and so forth.  Anything it can possibly figure out it should
   figure out.

I am torn at the moment.  I started with #2 but I am tempted to try #1
and just see how painful it really is.
