---
layout: post
title: "The Case of the Recurring Closure"
date: 2013-04-30 10:51
comments: true
categories: [Rust]
---
Yesterday I realized that you can violate Rust's memory safety
guarantees by using "stack closures", meaning closures that are
allocated on the stack which have can refer to and manipulate the
local variables of the enclosing stack frame. Such closures are
ubiquitous in Rust, since every `for` loop makes use of them (and
virtually every higher-order function). Luckily, this hole can be
fixed with (I think) very little pain---in fact, I think fixing it
can also help us make other analyses a little less strict.

The problem stems from the fact that, if you are clever, you can get a
stack closure to recurse (that is, to call itself again with the same
environment). This would mean that while the stack closure has a new
set of local variables, the variables *it inherits from its
environment* are the same. When the borrow checker was first written,
this was not true, but it is now, since closures were generalized in
the meantime.

### Executive Summary

My proposed fix is a change that will guarantee statically that stack
closures cannot recurse (that is, cannot call themselves with the same
environment).  I'll go into the details of the problem and my proposed
fix in the post, but I wanted to start by briefly summarizing what the
effects would be on end-users.

- Almost all if not all existing higher-order functions would still
  work fine. In particular, you can call `&fn` closures normally and
  pass them as a parameter to another function and so on. What would
  be a little more subtle is storing `&fn` closures into data
  structures; it'd still be supported, but some patterns that would be
  legal today would become illegal.
- The "liveness" pass, which checks that all variables are
  initialized, can be generalized to permit closures to move out from
  local variables so long as they move a new value back in. This means
  that `foldl` can be implemented without copies:
  
      function foldl<A,B,I:Iterable<B>>(a0: A,
                                        iter: &I,
                                        op: &fn(A,&B) -> A) -> A {
          let mut result = a0;
          
          // Here I am deliberately desugaring the `for` syntax,
          // because I want to emphasize that this is a closure:
          iter.each(|b| {
              // Note: A is not copyable, therefore this call
              // *moves* from result into `op()` and then restores
              // it. This did not used to be legal because we are
              // executing in a closure, and we were afraid
              // that `op` might in fact somehow recurse, in which
              // case it would find that `result` is uninitialized.
              result = op(result, b);
              true
          })
      }

What would not work would be:

- Passing the same `&fn` closure as a parameter more than once,
  or calling a `&fn` closure with itself as an argument (no Y combinators).
- Making a struct `S` that contains `&fn` closures and then calling those
  closures via an `@S` or
  `&S` pointer, like so:
  
      struct S {f: &fn()}
      fn foo(s: &S) { s.f() } // would be illegal
  
  You could write this code using an `&mut S` pointer, though:

      struct S {f: &fn()}
      fn foo(s: &mut S) { s.f() } // would be illegal
      
  The reason for this is that `&mut` pointers are non-aliasable.
  Similar rules arise in the revised borrow checker I've been working
  on for various corner cases where aliasing is a concern. I'll have a
  post on that at some point too.
  
<!-- more -->  
  
### What is the problem, anyway?

Here is an example of an unsound function:

    struct R<'self> {
        // This struct is needed to create the
        // otherwise infinite type of a fn that
        // accepts itself as argument:
        c: &'self fn(&R)
    }
    
    fn innocent_looking_victim() {
        let mut vec = ~[1, 2, 3];
        conspirator(|f| {
            if vec.len() < 100 {
                vec.push(4);
                for vec.each |i| {
                    f.c(&f)
                }
            }
        })
    }
    
    fn conspirator(f: &fn(&R)) {
        let r = R {c: f};
        f(&r)
    }

What happens when you run this function is that the vector `vec` is
pushed to while it is also being iterated over, which is supposed to
be impossible. The root cause of this problem is that the borrow
checker generally assumes that `&fn` closures do not recurse (which,
when it was first written, was true). Because of this, the closure `f`
which is passed to `conspirator` is permitted to freeze `vec`, because
it looks to the borrow checker like it can track all the possible
aliases of `vec` and it sees that this action is ok. But the borrow
checker is of course mistaken here, since the closure `f` is passed to
itself as an argument, and thus there *is* an alias of `vec`, capured
in the closure environment.

The problem lies in the `&fn` closures, which effectively create
implicit references to the data they capture. I tried to make up an
example showing what that function looks like if state is passed
explicitly, but due to the problem of recursive types it is quite
tedious, so I'm going to, um, leave it as an exercise to the reader.

Anyhow, my solution has two parts:

1. Modify the borrow checker to treat these implicit references just
   like any other reference in the borrow checker. Basically the model
   should be that when a stack closure with lifetime `'a` is created,
   its contents are opaque to the creator, except that any data which
   it references is considered borrowed for the lifetime `'a`. The
   type of borrow will depend on how the variable is used (for
   example, is it read? mutated?  borrowed from within the
   closure?). In the case above, the variable `vec` would be borrowed
   mutably, since it is pushed to.
2. Guarantee that closures cannot recurse, because otherwise we'd have
   to treat every upvar as potentially aliased, which would make most
   programs illegal.
   
Let's look at those changes in more detail.   

### Modifications to the borrow checker

The basic idea would be to examine the body of each closure as we are
conducting the borrow check to examine what free variables it
references and how.  This is fairly straightforward to do: the borrow
checker conducts a walk of the AST already to find all the functions
it must check, so basically what we would do is to analyze functions
on the way up the tree. So we would analyze each closure first,
assuming it has total access to the upvars of the parent. We would
then compute a list of the upvars that the closure borrowed and what
level of access it required.  In the parent fn, when we find a closure
expression, we would not examine the body of the closure but rather
just treat it as taking out loans that persist for the lifetime of the
closure. This is very similar to what we have to
do for `once` fns and also what we do for moves (I guess that's
another post, though).

### Guaranteeing closures cannot recurse

The idea here would be to make all `&fn` closures
non-copyable. Basically this would mean the only copyable closure type
would be an `@fn`:

- `~fn` is non-copyable
- `~once fn` is non-copyable
- `&fn` *will become* non-copyable
- `&once fn` is non-copyable
- `@fn` is copyable
- `@once fn` is non-copyable

At first I thought that `@once fn` was not necessary, but in fact it
is potentially useful for combinator libraries and the like, as it
allows you to return a fn that can move out of its environment.

For fun, let's review the [full closure type specification][cts] from
a previous blog post, modernized somewhat and taking these changes
into account.

    (&'r|~|@'r) [unsafe] [once] fn [:K] (S) -> T
    ^~~~~~~~~~^ ^~~~~~~^ ^~~~~^    ^~~^ ^~^    ^
       |          |        |        |    |     |
       |          |        |        |    |   Return type
       |          |        |        |  Argument types
       |          |        |    Environment bounds
       |          |     Once-ness (a.k.a., affine)
       |        Effect
    Allocation type and lifetime bound
    
One part I had hoped to remove was the environment bounds, but I think
they are still necessary. The only real use case for this is `:Const`,
which would be a way of saying that the closure only closes over
deeply immutable data. This enables parallelism in various ways
(putting closures in ARCs, fork-join parallelism a la PJS, etc).
Conceivably we could also support `:Clone`, which would permit
closures to be cloned, but we'd need some magic support in trans (code
which, admittedly, mostly exists) to make that work.

[cts]: {{ site.baseurl }}/blog/2012/10/23/function-and-object-types/

### Some musings on orthogonality or lack thereof

It annoys me that the rules for closures feel... one-off. I considered
briefly if we were not categorizing things correctly. To some extent,
the answer is clearly yes: there are many partly orthogonal
characteristics of closures (once-ness, type of pointer used to
reference its data, kinds of loans it requires, etc). Ultimately, we
are trying to boil this down into a relatively small set of types that
covers all important use cases.

A similar phenomena occurs with `&` and `&mut`: there are really two
characteristics, aliasability and mutability, and we have joined them
together, such that `&` references are immutable and aliasable and
`&mut` are mutable and unaliasable. This is typically what you want,
but there are rare occasions where you must use `&mut` solely for its
non-aliasable nature and not because of mutability. In particular, if
you want access to other non-aliasable things, such as other `&mut`
pointers or (per this post) `&fn` closures.

In the beginning of the post I wrote that the following example will
not work:

      struct S {f: &fn()}
      fn foo(s: &S) { s.f() } // would be illegal
      
The reason for this has to do precisely with the fact that `&S`
pointers are always aliasable. Hence we could not permit `s.f` to be
called because we can't guarantee that there are no aliases to `s`
lurking around, and thus creating aliases to `s.f`. You could fix this
program by using `&mut`:

      struct S {f: &fn()}
      fn foo(s: &mut S) { s.f() } // legal

In this case, we don't care about mutability, we do care about
uniqueness.

I was debating for a time whether to suggest adding more facets to the
various types. For example, one could imagine `&`, `&alias`, `&mut`,
and `&mut alias`. But I think that ultimately, this is a bad idea.
For one thing, the correct aliasability default varies, so you'd
*probably* want something like `&`, `&noalias`, `&mut`, `&mut
alias`. The type system ultimately feels more complex, with many
branches (case in point: see the full closure type specification
above!).
