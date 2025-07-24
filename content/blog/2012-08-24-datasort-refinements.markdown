---
layout: post
title: "Datasort refinements"
date: 2012-08-24T10:24:00Z
comments: true
categories: [Rust, PL]
---

One of the things that is sometimes frustrating in Rust is the
inability to define a type that indicates some subset of enum
variants.  For example, it is very common to have a pattern like this:

    match an_expr {
        expr_call(*) => process_call(an_expr)
        ...
    }

    fn process_call(a_call_expr: @ast::expr) { ... }

But as you can see, the type of `a_call_expr` does not reflect the
fact that this expression is a call.  This is frustrating.

## Earlier thoughts

Patrick and I had earlier sketched out designs to rectify this loosely
following Scala's design for case classes.  Graydon had an alternate
design.  There was a bit of back-and-forth in
<https://github.com/mozilla/rust/issues/1679>, though it doesn't
contain the latest details.

The idea consisted of two basic parts, one of which is "reused" in
this new proposal and hence worth discussing in detail.  This first
part is that we "unify" the way that structs and enum variants are
written, so that you can declare structs that wrap a tuple (like a
variant) or variants with a field.  Both have their place.  So that
means you could write a struct like this:

    struct NodeId(uint)
    
which is effectively a newtype'd (in the Haskell sense) wrapper around
a `uint` (this replaces the current, rather unintuitive, shorthand of
`enum foo = uint`).  Or you could build an enum variant like this:

    enum VarKind {
        LocalVar { id: uint, name: ~str }
    }
    
This addresses a common problem with variants: once they get beyond 1 or
2 parameters, it's hard to know what's what, and you end up with code like
this:

    def_upvar(node_id /* id of closed over var */,
              @def    /* closed over def */,
              node_id /* expr node that creates the closure */,
              node_id /* id for the block/body of the closure expr */),
              
This would be much nicer if the fields could be labeled (of course,
you could define a struct type and wrap it in the `def_upvar`, but
that's annoying in practice and rarely done).

The second part of the plan was to make each variant a type, and to
permit the introduction of nested enums.  This allowed for a simple
tree-like scheme of refinements.  We also intended to allow one to
declare a set of common fields that are inherited by all variants.
I'm not diving into much detail on this second patt of the plan
because it is not important to my alternate proposal; however, suffice
to say that while it was expressive, it carried some syntactic
complications that we had never satisfactorily resolved.

## An alternate approach

Anyway, after some discussion with Ben Blum, I've been thinking about
another approach.  It's pretty close to what Graydon originally
proposed (maybe even identical?) though with an added component from
Patrick.  Interestingly, they are both ideas that I didn't like on
first hearing them, but together they seem to appeal to me more.

Today an enum type is written `Id<T*>`.  Under the new proposal, a
full enum type would be written `Id<T*>[VariantName*]`.  The meaning
of this is "an instance of the enum `Id<T*>` which has the type of one
of the variants listed".  There is a natural subtyping
relationship:`V1 <= V2 => Id[V1] <: Id[V2]` (that is, if you have a
more narrow type, you can use it where a wider type is expected).

To make this more concrete, here are some examples:

    Option<int>               --> as today
    Option<int>[Some,None]    --> equivalent to the above
    Option<int>[Some]         --> always Some
    @ast::Expr[Call]          --> an expression that must be a call

I would expect user's to define type aliases for common patterns.  For
example:

    type Some<T> = Option<T>[Some];
    type Lvalue = @ast::Expr[Call, ...];

When the variants are defined in a struct-like fashion, using named
fields, users can access any field which appears as part of the common
prefix to all variants (alternatively, we could support the access to
any common field at all, but it would potentially be inefficient at
runtime and I'd rather make that cost obvious to the user).  So, if we
define our expressions like so:

    struct ExprBase { id: uint }
    struct BinaryArgs { lhs: @Expr, rhs: @Expr }
    
    enum Expr {
        Literal {base: ExprBase, value: uint},
        Variable {base: ExprBase, name: ~str},
        Plus {base: ExprBase, args: BinaryArgs},
        Minus {base: ExprBase, args: BinaryArgs},
    }
    
    type ExprBinop = Expr[Plus, Minus]
    
Then, given any expression, one could write `expr.base.id`.  Given
any `ExprBinop`, one could write `expr.args.lhs`.  And so forth.

Although I was initially opposed to the common fields idea when
Patrick proposed it, because it requires you to repeat yourself a bit
more than I'd like, it overcomes some of the more annoying syntactic
questions that plagued our earlier ideas.  Moreover, I remember that
in Scala, in practice I often ended up repeating common fields as
part of the constructor:

    sealed trait Expr(val id: Int)
    case class Literal(override val id: Int, value: Int) extends Expr(id)
    ...

This just formalizes the practice.

One important property of this proposal is that the narrowing of
variants is achieved through a structural type and not a nominal type.
That is, there is no nominal type corresponding to a "binop
expression"; rather, it is defined through a type alias.  This ensures
that the Least Upper Bound and Greatest Lower Bound operations are
easily defined, which is important for the type inferencer.

## In conclusion...

The proposal is relatively easy to implement and doesn't involve deep
changes to any particular part of the language.  It would give us a
very expressive system for statically ruling out variants when
possible that supports arbitrary subsets.


