---
layout: post
title: "Why case classes are better than variant types"
date: 2011-12-02 06:57
comments: true
categories: [PL]
---

One of the better features from functional programming languages are
variant types (a.k.a. algebraic data types).  Basically they are a way
of enumerating a small set of possibilities and then making sure that
you handle every possible case.  However, in real world use variant
types tend to run into a few annoying problems.  While working on the
[Harmonic compiler](http://www.harmonic-lang.org), I found that
Scala's case classes addressed some of these shortcomings.  

My goal in writing Scala code was to *never* have an `assert false` to
cover situations I knew could not occur.  I did not quite succeed, but
I got really close, much closer than I ever got in any other language.
Mostly where I failed I knew that I could refactor the types but I did
not want to spend the time to do it.  In this post I want to explain
how and why the case class approach seems to work better than
traditional variant types.  In later posts I'll cover some of the
other tricks that I ended up using, particularly the approach I used
to having an AST whose shape changed over time.

In O'Caml, you have something like this (I forget the precise syntax):

    type expr =
    |    bin_op of (op, expr, expr)
    |    un_op of (op, expr)
    |    tuple of (expr list)
    |    ...
    ;

This seems great at first, but you often run into two situations.  The
first, which is *very* common, is that you want to have some helper
routine which handles a subset of expressions.  For example:

    let lower_bin_op op left right = ...
    let lower_un_op op expr = ...
    let lower_expr expr = 
        case expr of
        |    bin_op(x, y, z) -> lower_bin_op x y z
        |    un_op(op, x) -> lower_un_op op x
        |    tuple(exprs) -> L.map lower_expr exprs
        |    ...

But now you can see that we duplicated the contents of `bin_op` and
`un_op` in the arguments to `lower_bin_op` and `lower_un_op`.  This is
annoying.  So we end up doing this:

    type bin_op = { op: op, left: expr, right: expr };
    type un_op = { op: op, expr: expr };
    type expr = bin_op of bin_op | un_op of un_op | tuple of expr list

OK, so far, kind of annoying, but no big problem.  But what about the
situation where you want a helper function that handles two or three
related cases?  You have no choice but to write code like:

    let get_op expr = 
        case expr of 
        |    bin_op(op, _, _) -> op
        |    un_op(op, _) -> op
        |    _ -> fail "impossible: not an operator expr!"

This seems to happen a lot: sometimes the language does not allow the
full set of expressions in all contexts; sometimes you have lowered
your AST; sometimes you have a series of functions which handle
certain cases and fall through to other functions for the remaining
cases.  Or sometimes you just want a nice helper that extracts some
common piece of data that appears in multiple cases, like the one
above.

Now what happens in Scala?  In Scala, when you defined your expression
type, you would write:

    sealed abstract trait Expr
    sealed abstract trait OpExpr extends Expr {
           def op: Op
    }
    case class UnOp(op: Op, expr: Expr) extends OpExpr
    case class BinOp(op: Op, left: Expr, right: Expr) extends OpExpr
    case class Tuple(exprs: List[Expr]) extends Expr

Now I can write our first example as:

    def lowerBinOp(expr: BinOp) = {...}
    def lowerUnOp(expr: UnOp) = {...}
    def lowerExpr(expr: Expr) = {
        expr match {
             case expr: BinOp => lowerBinOp(expr)
             case expr: UnOp => lowerUnOp(expr)
             case Tuple(exprs) => exprs.foreach(lowerExpr)
        }
    }

The key here is that `BinOp` and `UnOp` are *automatically* types of
their own, unlike in O'Caml, where variants are not a type.  What I
did in the match expression is to define a second variable `expr` that
shadows the original `expr` but has a more refined type.  I found
myself doing this a lot when I wrote Scala.

OK, so far so good.  What about the second example, where we extracted
the operator from any operator expression?  Turns out that was already
defined: note that `UnOp` and `BinOp` both extended `OpExpr`, which
defined a virtual op property.  So I can write `expr.op` and so long
as the expression is a binary operator or a unary operator everything
is good.  If you wanted to write something like the O'Caml, that is
of course possible too:

    def getOp(expr: OpExpr) = {
        expr match {
            case BinOp(op, _, _) => op
            case UnOp(op, _) => op
        }
    }

Only now there is no need for the explicit fail case.  So basically
using inheritance and subtyping you got a very flexible categorization
scheme.  Since traits support multiple inheritance you are not limited
to trees, but can have arbitrary DAGs, which is very helpful.
