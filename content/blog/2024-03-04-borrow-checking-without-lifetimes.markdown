---
title: "Borrow checking without lifetimes"
date: 2024-03-04T13:29:34-05:00
---

This blog post explores an alternative formulation of Rust's type system that esches *lifetimes* in favor of *places*. The TL;DR is that instead of having `'a` represent a *lifetime* in the code, it can represent a set of *loans*, like `shared(a.b.c)` or `mut(x)`. If this sounds familiar, it should, it's the basis for [polonius](https://smallcultfollowing.com/babysteps/blog/2023/09/22/polonius-part-1/), but reformulated as a type system instead of a static analysis. This blog post is just going to give the high-level ideas. In follow-up posts I'll dig into how we can use this to support interior references and other advanced borrowing patterns. In terms of implementation, I've mocked this up a bit, but I intend to start extending [a-mir-formality][] to include this analysis.

[a-mir-formality]: https://github.com/rust-lang/a-mir-formality

<!--more-->

## Why would you want to replace lifetimes?

Lifetimes are the best and worst part of Rust. The best in that they let you express very cool patterns, like returning a pointer into some data in the middle of your data structure. But they've got some serious issues. For one, the idea of what a lifetime is rather abstract, and hard for people to grasp ("what does `'a` actually represent?"). But also Rust is not able to express some important patterns, most notably interior references, where one field of a struct refers to data owned by another field.

## So what *is* a lifetime exactly?

Here is the definition of a lifetime from the RFC on non-lexical lifetimes:

> Whenever you create a borrow, the compiler assigns the resulting reference a lifetime. This lifetime corresponds to the span of the code where the reference may be used. The compiler will infer this lifetime to be the smallest lifetime that it can have that still encompasses all the uses of the reference.

[Read the RFC for more details.](https://rust-lang.github.io/rfcs/2094-nll.html#what-is-a-lifetime)

## Replacing a *lifetime* with an *origin*

Under this formulation, `'a` no longer represents a *lifetime* but rather an **origin** -- i.e., it explains where the reference may have come from. We define an origin as a **set of loans**. Each loan captures some **place expression** (e.g. `a` or `a.b.c`), that has been borrowed along with the mode in which it was borrowed (`shared` or `mut`).

```
Origin = { Loan }

Loan = shared(Place)
     | mut(Place)

Place = variable(.field)*  // e.g., a.b.c
```

## Defining types

Using origins, we can define Rust types roughly like this (obviously I'm ignoring a bunch of complexity here...):

```
Type = TypeName < Generic* >
     | & Origin Type
     | & Origin mut Type
     
TypeName = u32 (for now I'll ignore the rest of the scalars)
         | ()  (unit type, don't worry about tuples)
         | StructName
         | EnumName
         | UnionName

Generic = Type | Origin
```

Here is the first interesting thing to note: there is no `'a` notation here! This is because I've not introduced generics yet. Unlike Rust proper, this formulation of the type system has a concrete syntax (`Origin`) for what `'a` represents.

## Explicit types for a simple program

Having a fully explicit type system also means we can easily write out example programs where all types are fully specified. This used to be rather challenging because we had no notation for lifetimes. Let's look at a simple example, a program that ought to get an error:

```rust
let mut counter: u32 = 22_u32;
let p: &{shared(counter)} u32 = &counter;
counter += 1; // Error: cannot mutate `counter` while `p` is live
println!("{p}");
```

Apart from the type of `p`, this is valid Rust. Of course, it won't compile, because we can't modify `counter` while there is a live shared reference `p` ([playground][]). As we continue, you will see how the new type system formulation arrives at the same conclusion.

[playground]: https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=1a05f0a4aad12c33345ca4adc1cd9bb2

## Basic typing judgments

Typing judgments are the standard way to describe a type system. We're going to phase in the typing judgments for our system iteratively. We'll start with a simple, fairly standard formulation that doesn't include borrow checking, and then show how we introduce borrow checking. For this first version, the typing judgment we are defining has the form

```
Env |- Expr : Type
```

This says, "in the environment `Env`, the expression `Expr` is legal and has the type `Type`". The *environment* `Env` here defines the local variables in scope. The Rust expressions we are looking at for our [sample program][playground] are pretty simple:

```
Expr = integer literal (e.g., 22_u32)
     | & Place
     | Expr + Expr
     | Place (read the value of a place)
     | Place = Expr (overwrite the value of a place)
     | ...
```

Since we only support one scalar type (`u32`), the typing judgment for `Expr + Expr` is as simple as:

```
Env |- Expr1 : u32
Env |- Expr2 : u32
----------------------------------------- addition
Env |- Expr1 + Expr2 : u32
```

The rule for `Place = Expr` assignments is based on subtyping:

```
Env |- Expr : Type1
Env |- Place : Type2
Env |- Type1 <: Type2
----------------------------------------- shared references
Env |- Place = Expr : ()
```

The rule for `&Place` is somewhat more interesting:

```
Env |- Place : Type
----------------------------------------- shared references
Env |- & Place : & {shared(Place)} Type
```

The rule just says that we figure out the type of the place `Place` being borrowed (here, the place is `counter` and its type will be `u32`) and then we have a resulting reference to that type. The origin of that reference will be `{shared(Place)}`, indicating that the reference came from `Place`:

```
&{shared(Place)} Type
```

## Computing liveness

To introduce borrow checking, we need to phase in the idea of **liveness**.[^obvious] If you're not familiar with the concept, the NLL RFC has a [nice introduction](https://rust-lang.github.io/rfcs/2094-nll.html#liveness):

[^obvious]: If this is not obvious to you, don't worry, it wasn't obvious to me either. It turns out that using liveness in the rules is the key to making them simple. I'll try to write a follow-up about the alternatives I explored and why they don't work later on.

> The term “liveness” derives from compiler analysis, but it’s fairly intuitive. We say that a variable is live if the current value that it holds may be used later.

Unlike with NLL, where we just computed live **variables**, we're going to compute **live places**:

```
LivePlaces = { Place }
```

To compute the set of live places, we'll introduce a helper function `LiveBefore(Env, LivePlaces, Expr): LivePlaces`. `LiveBefore()` returns the set of places that are live before `Expr` is evaluated, given the environment `Env` and the set of places live after expression. I won't define this function in detail, but it looks roughly like this:

```
// `&Place` reads `Place`, so add it to `LivePlaces`
LiveBefore(Env, LivePlaces, &Place) =
    LivePlaces ∪ {Place}

// `Place = Expr` overwrites `Place`, so remove it from `LivePlaces`
LiveBefore(Env, LivePlaces, Place = Expr) =
    LiveBefore(Env, (LivePlaces - {Place}), Expr)

// `Expr1` is evaluated first, then `Expr2`, so the set of places
// live after expr1 is the set that are live *before* expr2
LiveBefore(Env, LivePlaces, Expr1 + Expr2) =
    LiveBefore(Env, LiveBefore(Env, LivePlaces, Expr2), Expr1)
    
... etc ...
```

## Integrating liveness into our typing judgments

To detect borrow check errors, we need to adjust our typing judgment to include liveness. The result will be as follows:

```
(Env, LivePlaces) |- Expr : Type
```

This judgment says, "in the environment `Env`, and given that the function will access `LivePlaces` in the future, `Expr` is valid and has type `Type`". Integrating liveness in this way gives us some idea of what accesses will happen in the future.

For compound expressions, like `Expr1 + Expr2`, we have to adjust the set of live places to reflect control flow:

```
LiveAfter1 = LiveBefore(Env, LiveAfter2, Expr2)
(Env, LiveAfter1) |- Expr1 : u32
(Env, LiveAfter2) |- Expr2 : u32
----------------------------------------- addition
(Env, LiveAfter2) |- Expr1 + Expr2 : u32
```

We start out with `LiveAfter2`, i.e., the places that are live after the entire expression. These are also the same as the places live after expression 2 is evaluated, since this expression doesn't itself reference or overwrite any places. We then compute `LiveAfter1` -- i.e., the places live after `Expr1` is evaluated -- by looking at the places that are live *before* `Expr2`. This is a bit mind-bending and took me a bit of time to see. The tricky bit here is that liveness is computed *backwards*, but most of our typing rules (and intution) tends to flow *forwards*. If it helps, think of the "fully desugared" version of `+`:

```
let tmp0 = <Expr1>
    // <-- the set LiveAfter1 is live here (ignoring tmp90, tmp1)
let tmp1 = <Expr2>
    // <-- the set LiveAfter2 is live here (ignoring tmp0, tmp1)
tmp0 + tmp1
    // <-- the set LiveAfter2 is live here
```

## Borrow checking with liveness

Now that we know liveness information, we can use it to do borrow checking. We'll introduce a "permits" judgment:

```
(Env, LiveAfter) permits Loan
```

that indicates that "taking the loan Loan would be allowed given the environment and the live places". Here is the rule for assignments, modified to include liveness and the new "permits" judgment:

```
(Env, LiveAfter - {Place}) |- Expr : Type1
(Env, LiveAfter) |- Place : Type2
(Env, LiveAfter) |- Type1 <: Type2
(Env, LiveAfter) permits mut(Place)
----------------------------------------- assignment
(Env, LiveAfter) |- Place = Expr : ()
```

Before I dive into how we define "permits", let's go back to our example and get an intution for what is going on here. We want to declare an error on this assigment:

```rust
let mut counter: u32 = 22_u32;
let p: &{shared(counter)} u32 = &counter;
counter += 1; // <-- Error
println!("{p}"); // <-- p is live
```

Note that, because of the `println!` on the next line, `p` will be in our `LiveAfter` set. Looking at the type of `p`, we see that it includes the loan `shared(counter)`. The idea then is that mutating counter is illegal because there is a live loan `shared(counter)`, which implies that `counter` must be immutable.

Restating that intution:

> A set `Live` of live places *permits* a loan `Loan1` if, for every live place `Place` in `Live`, the loans in the type of `Place` are compatible with `Loan1`.

Written more formally:

```
∀ Place ∈ Live {
    (Env, Live) |- Place : Type
    ∀ Loan2 ∈ Loans(Type) { Compatible(Loan1, Loan2) }
}
-----------------------------------------
(Env, Live) permits Loan1
```

This definition makes use of two helper functions:

* `Loans(Type)` -- the set of loans that appear in the type
* `Compatible(Loan1, Loan2)` -- defines if two loans are compatible. Two shared loans are always compatible. A mutable loan is only compatible with another loan if the places are disjoint.

## Conclusion

The goal of this post was to give a high-level intution. I wrote it from memory, so I've probably overlooked a thing or two. In follow-up posts though I want to go deeper into how the system I've been playing with works and what new things it can support. Some high-level examples:

* How to define subtyping, and in particular the role of liveness in subtyping
* Important borrow patterns that we use today and how they work in the new system
* Interior references that point at data owned by other struct fields and how it can be supported


