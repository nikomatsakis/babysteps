---
layout: post
title: "Block sugar in expressions"
date: 2011-12-20 15:37
comments: true
categories: [Rust] 
published: false
---
I know it seems like I'm spamming rust-dev today, but I want feedback on some work I just completed.  The goal is to expand the places where block syntactic sugar can be used.  It turns out that this required some (in my opinion) minor changes to how the rust type checker worked, but the changes seem significant enough that I wanted to float this by people for feedback.

#### Summary ####

I allow you to write `expr { || .. }` as part of an expression.  This is syntactic sugar for adding the fn block `{ || ... }` as an additional parameter to the call, if `expr` is a call expression, or for `expr({ || ... })` otherwise.  This entails some minor changes in how we handle expressions in tail position for a function or block: basically, if an expression is in tail position for a function with nil return type or for a statement whose value is ignored, then the result of that expression is ignored.

So this becomes legal:

    fn foo() { 10 }

where before it was illegal.  It is legal now because the function `foo()` has nil return type so the value of its last expression is ignored.  This could be seen as bad, this code is probably wrong.  However, I argue it's benign, because the type checker will catch it when you try to invoke `foo()` and use its return value.  This will cause you to rewrite the `foo()` declaration as:

    fn foo() -> int { 10 }

in which case it is type-checked as we do today.

#### Why make this change? ####

Currently, we support syntactic sugar of the form:

    vec::iter(x) { |e|
        ...
    }

However, this is only supported in a statement and not elsewhere.  Therefore, it is not possible to write things like:

    let task = spawn { |chan| ... };
    let v2 = vec::map(v) { |e| ... };

Instead, one must write:

    let task = spawn({ |chan| ... });
    let v2 = vec::map(v, { |e| ... |);

Not the biggest deal, but I at least find it unsightly. 

#### But why does that mean the type checker has to change? ####

Today we attempt to determine *in the parser* whether an expression may yield a usable value.  In the case of expressions that double as statements, this is generally specified by the presence or absence of a trailing semicolon.  This is recursive, so we can have something like:

    fn foo(...) {
        if expr1 {
              if expr2 { expr3 } else { expr4 }
        } else {
              expr5
        }
    }

This is very different from:

    fn foo(...) {
        if expr1 {
              if expr2 { expr3 } else { expr4 };
        } else {
              expr5
        }
    }

This doesn't work so well with the syntactic sugar, as 
`vec::iter(v) { |e| ... }` and `vec::map(v) { |e| ... }` both look the
same, but the former is a statement where the latter yields a value
that must be used. 

In almost all cases, I can infer what you mean by the position within the block.
If the call with the block sugar occurs as a top-level statement, but
not at the end of the function, as here:

    fn foo(...) {
		bar { |e| 
			...
		}
		
		do_something();
	}

then no semicolon is required and the result of the function call is ignored,
as today.  Meanwhile, if the function call occurs as part of an expression, like here:

    fn foo(...) {
		let v = bar { |e| ... };
	}
	
then a semi-colon is required to terminate the `let`, as normal, and the
result will be significant.	

But if the function call occurs as the last statement in a block:

    fn foo(...) {
		if (...) {
			bar { |e| 
				...
			}
		}
	}
	
Then this is technically an expression position, as it may represent
the result of the block.  But often, as in `foo()` above, the code 
represents a loop or something like that whose result is not significant.
