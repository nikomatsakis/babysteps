---
categories:
- Rust
comments: true
date: "2013-05-14T00:00:00Z"
slug: procedures
title: Procedures, continued
---

So, I didn't actually *mean* to post that previous post, I had
intended to think more on the idea. But oh well, cat's out of the
bag. In any case, I've been thinking about the "closures" vs
"procedures" idea that I jotted down there and decided to try and
elaborate on it a bit more, since I find it has a lot of appeal. In
particular I think that the current collection of closure types is
addressing too many distinct use cases and the result is confusing.

*UPDATE 2013.05.14 10:30am:* Edited to tweak various errors and to
add some variations at the end that I prefer.

### Today: by-reference vs copying closures

Today we offer three different kinds of closures (`&fn`, `@fn`, and
`~fn`), but these closures can really be divided into two basic
categories: by-reference and copying closures. A by-reference closure
is the usual kind: it is allocated on the stack and has full access to
the variables in the creating stack frame. It can read them, write
them, and borrow them. These are used with for loops and the like.

Copying closures, on the other hand, are somewhat different. They are
not tied to any particular stack frame. Instead, they *copy* the
current values of the variables which they close over into their
environment (like all the default Rust copies, this is a shallow copy,
so if the value being closed over contains `~` pointers, it will no
longer be accessible from the creator). These closures are used
primarily as task bodies and for futures. There are some scattered
uses of `@fn` closures in the compiler but as far as I can tell they
are all legacy code that should eventually be purged and rewritten to
use traits (i.e., the visitor, the AST folder).

Loosely speaking, a `&fn` closure is by-reference and `@fn` and `~fn`
closures are copying closures. But this is not strictly true. In fact,
an the `&fn` type can be either a by-reference closure *or* a copying
closure, because you are permitted to borrow a `@fn` or `~fn` to a
`&fn`.  So the type in isolation does not tell you whether a closure
is by-reference or not. In fact, there is no explicit indication at
all---instead, when you create a closure today (i.e., with a `|x, y|
...`) expression, the compiler infers based on the expected types
whether this should be a by-reference closure or a copying
closure. Because the semantics of these two vary greatly, I find this
potentially quite confusing and unfortunate.

### Tomorrow (perhaps): closures and procedures

In general, I would prefer to draw a starker line between copying and
by-reference closures. I propose to use the term *closure* to refer
only to by-reference, stack-allocated closures. We could then use
another term, perhaps *procedure*, to refer to the copying
closures. This would mean that our type hierarchy would look like:

    T = S               // sized types
      | U               // unsized types
    S = fn(S*) -> S     // closures (*)
      | &'r T           // region ptr
      | @T              // managed ptr
      | ~T              // unique ptr
      | [S, ..N]        // fixed-length array
      | uint            // scalars
      | ...
    U = [S]             // vectors
      | str             // string
      | Trait           // existential ("exists S:Trait.S")
      | proc(S*) -> S   // procedures (*)

This chart is basically the same as the one you will find in the
[dynamically sized types][dst] post from before with one crucial
difference: closure types have been split from procedures, and closure
types have moved into the category of *sized types*, meaning that you
no longer write an explicit sigil when you use one. This is because
the representation of a closure would always be a pair of a borrowed
pointer into the stack and a function pointer: the type has a fixed
size (two words) and requires no memory allocation.

I have chosen to leave procedures as unsized, since a procedure must
allocate memory on the heap, and this allows the user to select which
heap is used; in earlier drafts of this idea, I had modified
procedures to implicit use the exchange heap, meaning that a type like
`proc()` always represented an exchange heap allocation. But I think
it's more consistent to have that type be written `~proc`, and it
maintains the general Rust invariant "you don't have allocation unless
you see a sigil".

*UPDATE:* bstrie on IRC asked about fn items, which never have any
environment. As today, these would continue to be coercable to either
a closure or a procedure.

### Closure and procedure expressions

Closures would still be created with the form `|x, y|
expr`. Procedures would be created using the keyword `proc`: `proc(x,
y) expr`. If desired, we could integrate procedures into `do` using
some syntax like one of the following, depending on whether we wish
to make the sigil explicit:

    do spawn proc { ... }   // sigil inferred
    
    do spawn ~proc { ... }  // sigil explicit
    
### Closure and procedure types in more detail

The full function or procedure type would look something like this
(`[]` indicates optional content):

     [once] (fn|proc) [:['r] [Bounds]] <'a...> (S*) -> S
     ^~~~~^           ^~~~~~~~~~~~~~~^ ^~~~~~^ ^~~^    ^
       |                     |            |     |      |
       |                     |            |     |  Return type
       |                     |            |    Argument types
       |                     |          Bound lifetime names
       |               Lifetime and trait bounds
    Onceness

Here the "onceness" indicates whether the closure/procedure can be
called more than once. The "lifetime and trait bounds" indicate
constraints on the environment. The lifetime bound `'r` indicates the
minimum lifetime of the variables that the closure/procedure closes
over, and the "bounds" (if any) would give bounds on the types of
those variables. Finally, you have the argument and return types.

If omitted, the default bounds for a closure would be a fresh lifetime
and no type bounds. The default bounds for a procedure would be the
static lifetime and `Owned`.

### Use cases

Let's look briefly at the use cases I listed before.

#### Higher-order and once functions

Typical uses for higher-order and once functions look much the same as
before, but minus a sigil.

    impl<T:Sized> for [T] {
        pub fn map<U:Sized>(f: fn(&T) -> U) -> ~[U] { ... }
                            // ^~~~~~~~~~~
    }

    impl<T:Sized> for Option<T> {
        // `each` on an option type can only execute at most once:
        pub fn each(f: once fn(&T) -> bool) -> bool { ... }
                    // ^~~~~~~~~~~~~~~~~~~
        }
    }

For contrast, these are `&fn(&T) -> U` and `&once fn(&T) -> bool` today.

#### Sendable functions and sendable once functions

Here is an example of a sendable once function:

    fn spawn(f: ~once proc()) {...}
             // ^~~~~~~~~~
             
As we saw before, one would write one of the following to call this
function:

    do spawn proc { ... }
    spawn(proc { ... })

Creating a future would look like `future(proc expr)` (vs `future(||
expr)` today).

#### Const closures

One could still use const closures to achieve lightweight parallelism:

    impl<T:Sized> for [T] {
        pub fn par_map<U:Sized>(f: fn:Const(&T) -> U) -> bool { ... }
                                // ^~~~~~~~~~~~~~~~~
    }

However, I have been thinking that we'll have to be careful here, we
need some way to guarantee that the closure does not move from its
environment and then replace the moved value. Today this is illegal,
but if we can prevent closures from recursing (which we must do
anyhow) then we could make such moves legal, and it would be useful
sometimes. On simple solution is to stay that if the closure type has
a `Const` bound, moves are illegal, but it's a bit...ad-hoc, since the
bounds are only supposed to be constraining the *types* of the
variables that are closed over. Still, it might be good enough.

#### Sendable const functions and combinators

As I argued before, I think these are not important use cases, but
with procedures they actually work out fine (though not with
variations 2 and 3 below). A sendable const function can be expressed
with the type `~proc:Owned+Const()`, which is complex, but then it
*is* a complex idea. Combinator types would likely look like `@proc`
or `@proc:'r`, in the case where the combinator closes over borrowed
data.

### Variation #1: Leaving procedures out of the core language

In fact, I think `proc` types need not be built into the language, you
could model them with traits, though you'd probably want a macro like
`proc!(...)` for defining the proc body. This would also mean the
procedures can't be used with `do` form.

### Variation #2: Limit procedures to execute once

I don't know of any (good) uses cases for non-once procedures.  I
think they should just always be `once`. This would mean that the only
closure types that are commonly needed would be:

1. `fn(T)` -- normal higher-order functions
2. `once fn(T)` -- higher-order functions that execute at most once
3. `~proc(T)` -- procedures

Because procedures can always be desugared into a struct and a trait,
this would not lose no expressiveness.

### Variation #3: Limit procedures to execute once and use exchange heap

For maximum streamlining, we could make `proc` implicitly use `~`,
in which case it would be written:

1. `fn(T)` -- normal higher-order functions
2. `once fn(T)` -- higher-order functions that execute at most once
3. `proc(T)` -- procedures

These types read pretty well, I think.

### Summary

I have long been unsatisfied with the implicit and confusing divide
between "by reference" and "copying" closures. Splitting them into two
concepts seems to address a lot of issues and be an overall win to me.

[dst]: {{ site.baseurl }}/blog/2013/04/30/dynamically-sized-types/
