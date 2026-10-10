---
title: "Why 'externalized' proofs of cyclic trait impls does not work"
date: 2026-10-10T08:23:35-07:00
series:
- "Cyclic trait impls"
---

For this post, I wanted to talk about two different approaches to handling supertraits. I'm calling them *modular* proofs vs *external* proofs. The key idea of this post is that, if we want to have cyclic trait impls, we really need to use a *modular* proof strategy, where the impl establishes all supertraits hold. Previously we had considered an *external* strategy, where the piece of code *using* the impl has the obligation to prove the supertraits hold. Modular proofs always seemed better but I did not think they were workable in the past. But I have become convinced that external proofs are incompatible with Rust as designed, and hence modular proofs are really the only option[^ralfj]. This post dives into that reasoning, and also gives a bit of explanation of what I mean by proofs in the first place.

[^ralfj]: I think this was obvious to Ralf Jung from the start. But it took me a bit.

## Traits and supertraits

So what do I mean by *modular* vs *external* proofs? Well, it all comes down to **who is responsible for proving that supertrait obligations hold**. Consider a trait like `Magic`:

```rust
trait Magic: Copy { }
```

The supertrait declaration means that, whenever `X: Magic` for some type `X`, it should be true that `X: Copy`. We make use of this in generic functions:

```rust
fn is_copy<T: Copy>() {
}

fn is_magic<T: Magic>() {
    // Legal, because `T: Magic` implies `T: Copy`
    is_copy::<T>();
}
```

The trick is that the compiler has to make sure that this implication holds -- i.e., for every type `X` that implements `Magic`, `X` also implements `Copy`. So how does it do it? 

## Modular proofs: the impl must show supertraits hold

The obvious answer is to make proving supertraits part of deciding whether an impl is valid. For any impl of `Magic`, we can require that the `Copy` supertrait holds. So an impl like this would be illegal:

```rust
// In a modular system, this impl is *illegal*
impl Magic for String { }
```

This impl is illegal because it would require that `String: Copy`, and that does not hold. Seems good.

## Modular proofs are a bit tricky

I am calling these proofs *modular* because the idea is that we can prove an entire program is valid by proving each part of it separately. In "programming language" theory, this is typically called a "modular" check, as it works by breaking up the entire program into modules that can be independently checked.

The idea with a *modular proof* is that we can *trust impls to show that the supertrait relationships hold*, we don't have to go and re-prove them over and over. If the impl is wrong, the impl will be invalid, but our code is fine. So if we have `impl Magic for String`, that implies the rest of the program can prove that `String: Magic`:

```rust
fn string_is_magic() {
    // Legal, because there is an impl for `String: Magic`:
    is_magic::<String>();
}
```

In fact, since we know that `Magic` implies `Copy`, the rest of the program can even rely on `impl Magic for String` to conclude that `String: Copy`:

```rust
fn string_is_copy() {
    // Legal, because there is an impl for `String: Magic`,
    // and `Magic` implies `Copy`:
    is_copy::<String>();
}
```

So long as `impl Magic for String` is invalid, none of this poses a problem to soundness, since the program overall doesn't type-check.

## Comparison with functions

An easy way to understand the idea of modular checks is to think of functions. Imagine you have a function like this one:

```rust
fn compute_sum(a: i32, b: i32) -> i32 {
	format!("{a} + {b}") // <-- Error
}
```

Clearly, this function is not legal. It takes two integers and promises to return a third integer, but in fact it returns a `String`. So the function is illegal. But if you have a call to that function from elsewhere, we consider that other call to be legal:

```rust
fn use_sum() {
    let c: i32 = compute_sum(2, 20); // OK
}
```

Here, `use_sum` is relying on `compute_sum` to obey its contract. It's not the job of `use_sum` to check that, it can just assume it is true.

## The catch: how do we decide the impl is invalid

There is a bit of a catch though. How do we decide if the impl is invalid? The basic idea was that `impl Magic for String` would have to prove that `String: Copy`. But we just saw that it could, in fact, do that *by using itself*. In other words, if we aren't careful, we can provide a proof that `String: Copy` like...

* `String: Copy` because `Magic` implies `Copy` and
	* `String: Magic` because `impl Magic for String` exists

and then we would (incorrectly) conclude that the impl is valid. So clearly we need to do something to rule that out. **We need a rule that says, when we are proving that an impl is valid, that proof cannot recursively rely on the impl itself.**[^termination] I'll come back in a future post to ways we might do that, but for now, I want to explore another alternative.

## External proofs: the user of the impl must show supertraits hold

When we first looked at this problem, way back in 2018 or so, we thought of another approach. What if we said that an `impl` is *not* responsible for proving supertraits. Instead, the idea would be that `impl Magic for String` is not enough to say that `String: Magic`. It only says that `Shallow(String: Magic)` -- i.e., `String` implements `Magic` in a *shallow* way, but not in a *deep* way that includes the full supertraits. **To prove 
that `String: Magic`, we have to show that `Shallow(String: Magic)` *and* `Shallow(String: Copy)`:**[^inf]

```
Shallow(String: Magic)
Shallow(String: Copy)
---------------------------- Magic fully implemented
String: Magic
```

[^inf]: This notation is called an *inference rule*. The conditions above the line are the *premises* and the bottom line is the *conclusion*. It says that, if you know the premises are true, you can infer that the conclusion holds.

This has the somewhat counterintuitive implication that `impl Magic for String` is actually *legal* in an "external proof" approach:

```rust
// In an external system, this impl is LEGAL
// (but unusable)
impl Magic for String { }
```

The saving grace is that, while this impl is legal, you can't actually **use** it. This function for example does not compile:

```rust
fn string_is_magic() {
    // NOT legal in an external system:
    // * We can prove that `Shallow(String: Magic)`
    // * We CANNOT prove that `Shallow(String: Copy)`.
    is_magic::<String>();
}
```

Here, `String: Magic` doesn't hold even though there is an `impl` of `Magic` for `String`, because the caller *also* has to check that `String: Copy` is implemented, and it is not. Huh, interesting.

## Comparison to functions: external is awkward

the "external proof" approach for impls is clearly a bit awkward. If we make the comparison to functions, it's as if the caller has to double check that the callee's body matches its return type, it can't actually *trust* the declared signature. But, awkward or not, it does resolve our problem: given `impl Magic for String`, we cannot prove `String: Copy`, and hence we cannot prove that `String: Magic`. We can only prove that `Shallow(Magic: String)`, which doesn't imply that the supertraits hold.

## But external doesn't work with unsafe traits

Based on the above, for a long time, I was working with the assumption that, weird as they are, we would go with the "external proof" approach. However, as Ralf Jung and lcnr pointed out to me recently, this is very challenging to reconcile with unsafe traits. Consider an unsafe trait like `Nullable`: 

```rust
// A type that can be safely transmuted from `0_usize`.
unsafe trait NullWord { }
```

The way that Rust works, when we write an `unsafe impl`, it is the job of that impl to prove that the unsafe conditions hold. Other parts of the program get to trust the impl. So if I write a function like this one, it should be considered safe:[^willnotcompile]

[^willnotcompile]: In point of fact, I believe this will not compile because of special rules about unsafe, but that's not relevant to the point I'm trying to make.

```rust
fn foo<T: NullWord>() -> T {
   std::mem::transmute(0_usize)
}
```

Now imagine that I wrote an invalid impl like this one:

```rust
// INVALID: We are asserting that `Box` can be null,
// which is not true!
unsafe impl<T> Nullable for Box<T> { }
```

Given this program I could clearly call `foo::<Box<u32>>()`, but that would "go wrong" (cause "undefined behavior"). I think we would all agree that the fault lies in the impl. **And yet, that is inconsistent: we say that the impl alone cannot be trusted to figure out if the supertraits are implemented, but it can be trusted to figure out if the unsafe impl is valid?**

## Conclusion

I definitely believe that we want to treat the "extra conditions indicated by unsafe" as a more general version of the other obligations that an impl has to establish to show that the trait holds-- and therefore that we must have modular proofs. That's kind of a relief, because something always felt *wrong* about external proofs, but it was hard to put my finger on a concrete problem. In the next post in this series (whenever that may be...), I expect to cover the approach to coinductive modular proofs that I landed on. Then I expect to talk about an alternative that was proposed to me that I find quite appealing.
