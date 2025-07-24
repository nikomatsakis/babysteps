---
layout: post
title: "Unifying patterns in alts and lets"
date: 2012-06-10T05:41:00Z
comments: true
categories: [Rust]
---

This is a proposal to unify the mechanics of `alt` and destructuring
assignment.  It was born out of discussion between erickt, pcwalton,
and I amidst various bugs in the bug tracker but I wanted to float it
around to a larger audience.  I'd like to discuss this on Tuesday,
because one of the logical next steps for the regions work is to begin
deciding precisely what to do about the types of identifiers in alts.

## Today

Currently, `alt` always creates implicit references into the structure
you are alting over.  For example, in this code:

    let p = {x:1, y:2};
    alt p {
        {x: x, y: y} {
           ...
        }
    }
    
the bound variables `x` and `y` are actually pointers to the interior
of `p`.

In addition, one can use let to match infallible patterns:

    let p = {x: 3, y: 4};
    let {x: x, y: y} = p;
    
Here, however, the values are actually not pointers to the interior of
`p` but rather are copied out of `p`.

## Shortcomings

Sometimes it is useful to get a pointer to the interior of a pattern
in a `let` and sometimes it is useful to copy out in an `alt`, but
the current system does not let you choose.  In addition, it is often
very useful to *move* out of the discriminant in an `alt`, but that is
not currently an option.

The matter of copying out of an `alt` is somewhat more important under
the new borrowck rules.  This is because the older system would
implicitly copy out of the discriminant when it appeared that the
value being matched was residing in mutable memory or that it might be
invalidated in some way.  This is no longer the case, which means that
more explicit copies are required in order to match against the
contents of an enum or unique pointer that lives in mutable memory (I
am actively working on a blog post / tutorial about the details of
this new check).

## The proposal

The proposal is to distinguish between *copying bindings* and
*reference bindings*.  A copying binding, indicating by either a
variable name alone (`x`) copies/moves the value out of the
discriminant.  A reference binding, indicated using `*x` (see some
notes on syntax below), takes the address of the value within the
discriminant.  For types that are not implicitly copyable, copying
bindings must be preceded by a `copy` keyword (`copy x`).  

Here is an example of creating references into the interior:

    let p = {x:1, y:2};
    alt p {
        {x: *x, y: *y} {
           ...
        }
    }

And the same example using `let`:

    let p = {x:1, y:2};
    let {x: *x, y: *y} = p;

Here is an example of copying the values out:

    let p = {x:1, y:2};
    alt p {
        {x: x, y: y} {
           ...
        }
    }
    let {x: x, y: y} = p;
    
And finally an example that requires an explicit `copy` keyword:

    let p = {x: ~1, y: ~2};
    alt p {
        {x: copy x, y: copy y} {
            ....
        }
    }
    let {x: copy x, y: copy y} = p;
    
Here, a pattern like `{x: x, y: y}` would result in a warning because
a unique value is being copied (which requires memory allocation and
is a performance red-flag).
    
## Moves

As a bonus, this idea transparently permits data to be *moved* as part
of an `alt` (hat tip to pcwalton for this observation).  For example,
the function called `option::unwrap()` could be written as follows
(here I am assuming a unary move operator; something generally agreed
to but not yet implemened):

    fn unwrap<T>(-opt: option<T>) -> T {
        alt move opt {
            some(v) { ret v; }
            none { fail; }
        }
    }

Basically, if the discriminant is *moved* into the alt then its pieces
can be carved up and moved into the bindings.  This is equivalent to
lets like the following (which is legal today):

    let (x, y) = move v;

For symmetry, the `move` keyword could be permitted on copying
bindings (`move x`).  It seems though that this would always be
superfluous except in the case of last use, where it could serve as
useful documentation:

    fn unwrap<T>(-opt: option<T>) -> T {
        alt opt {
            some(move v) { ret v; }
            none { fail; }
        }
    }

## Syntax

I borrowed the `*identifier` syntax from Cyclone.  However, I would
personally prefer `&identifier`, as it is more reminiscent of the
"take the address of" operator.  However, I presume that `&P` will
eventually become a pattern, like `@P` and `~P` today (currently,
there is no pattern to match against an `&T` type).  There was some
talk at various points of making unsafe pointers be a special kind of
lifetime, like `static`, so that one would write `*unsafe T` in which
case `*r.T` could replace `&r.T` as the type of safe references.  That
would in turn permit switching the role of `&` and `*` in patterns.
    

