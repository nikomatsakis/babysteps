---
layout: post
title: Giving, lending, and async closures
date: 2023-05-09 11:13 -0400
---

In [a previous post on async closures][pp], I [concluded][] that the best way to support async closures was with an `async` trait combinator. I've had a few conversations since the post and I want to share some additional thoughts. In particular, this post dives into what it would take to make async functions matchable with a type like `impl FnMut() -> impl Future<Output = bool>`. This takes us down some interesting roads, in particular the distinction between giving and lending traits; it turns out that the closure traits specifically are a bit of a special case in turns of what we can do backwards compatibly, due to their special syntax. on!

[pp]: https://smallcultfollowing.com/babysteps/blog/2023/03/29/thoughts-on-async-closures/

[concluded]: https://smallcultfollowing.com/babysteps/blog/2023/03/29/thoughts-on-async-closures/#conclusion

## Goal

Let me cut to the chase. This article lays out a way that we *could* support a notation like this:

```rust
fn take_closure(x: impl FnMut() -> impl Future<Output = bool>) { }
```

It requires some changes to the `FnMut` trait which, somewhat surprisingly, are backwards compatible I believe. It also requires us to change how we interpret `-> impl Trait` when in a trait bound (and likely in the value of an associated type); this could be done (over an Edition if necessary) but it introduces some further questions without clear answers.

This blog post itself isn't a real proposal, but it's a useful ingredient to use when discussing the right shape for async clsoures.

## Giving traits

The split between `Fn` and `async Fn` turns out to be one instance of a general pattern, which I call "giving" vs "lending" traits. In a *giving* trait, when you invoke its methods, you get back a value that is independent from `self`.

Let's see an example. The current `Iterator` trait is a *giving* trait:

```rust
trait Iterator {
    type Item;
    fn next(&mut self) -> Option<Self::Item>;
    //      ^ the lifetime of this reference
    //        does not appear in the return type;
    //        hence "giving"
}
```


In `Iterator`, each time you invoke `next`, you get ownership of a `Self::Item` value (or `None`). This value is not borrowed from the iterator.[^coll] As a consumer, a giving trait is convenient, because it permits you to invoke `next` multiple times and keep using the return value afterwards. For example, this function compiles and works for any iterator ([playground](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=baf23fe5cc1c5182acb3c9760b85ed33)):

```rust
fn take_two_v1<T: Iterator>(t: &mut T) -> Option<(T::Item, T::Item)> {
    let Some(i) = t.next() else { return None };
    let Some(j) = t.next() else { return None };
    // *Key point:* `i` is still live here, even though we called `next`
    // again to get `j`.
    Some((i, j))
}
```

[^coll]: There is a subtle point here. If you are iterating over, say, a `&[T]` value, then the `Item` you get back is an `&T` and hence borrowed. It may seem strange for me to say that you get ownership of the `&T`. The key point here is that the `&T` is borrowed *from the collection you are iterating over* and not *from the iterator itself*. In other words, from the point of view of the *Iterator*, it is copying out a `&T` reference and handing ownership of the reference to you. Owning the reference does not give you ownership of the data it refers to.

## Lending traits

Whereas a *giving* trait gives you ownership of the return value, a *lending* trait is one that returns a value borrowed from `self`. This pattern is less common, but it certainly appears from time to time. Consider the [`AsMut`][] trait:

[`AsMut`]: https://doc.rust-lang.org/std/convert/trait.AsMut.html

```rust
trait AsMut<T: ?Sized> {
    fn as_mut(&mut self) -> &mut T;
    //        -             -
    // Returns a reference borrowed from `self`.
}
```

`AsMut` takes an `&mut self` and (thanks to Rust's [elision rules]) returns an `&mut T` borrowed from it. As a caller, this means that so long as you use the return value, the `self` is considered borrowed. Unlike with `Iterator`, therefore, you can't invoke `as_mut` twice and keep using both return values ([playground](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=dc6b05db0d60fea3a6bab9ae622b6350)):

[elision rules]: https://doc.rust-lang.org/book/ch10-03-lifetime-syntax.html#lifetime-elision

```rust
fn as_mut_two<T: AsMut<String>>(t: &mut T) {
    let i = t.as_mut(); // Borrows `t` mutably
    
    let j = t.as_mut(); // Error: second mutable borrow
                        // while the first is still live
    
    i.len();            // Use result from first borrow
}
```

## Lending iterators

Of course, `AsMut` is kind of a "trivial" lending trait. A more interesting one is lending *iterators*[^stream]. A lending iterator is an iterator that returns references into the iterator self. Typically this is because the iterator has some kind of internal buffer that it uses. Until recently, there was no lending iterator trait because it wasn't even possible to express it in Rust. But with generic associated types (GATs), that changed. It's now possible to express the trait, although there are [borrow checker limitations][] that block it from being practical[^MVP]:

```rust
trait LendingIterator {
    type Item<'this>
    where
        Self: 'this;
    
    fn next(&mut self) -> Option<Self::Item<'_>>;
    //      ^                        ^^
    // Unlike `Iterator`, returns a value
    // potentially borrowed from `self`.
}
```

[borrow checker limitations]: https://github.com/rust-lang/rust/issues/92985

[^MVP]: Not to mention that GATs remain in an "MVP" state that is rather unergonomic to use; we're working on it!

[^stream]: Sometimes called "streaming" iterators.

As the name suggests, when you use a lending iterator, it is *lending* values to you; you have to "give them back" (stop using them) before you can invoke `next` again. This gives more freedom to the iterator: it has the ability to use an internal mutable buffer, for example. But it takes some flexibility from you as the consumer. For example, the `take_two` function we saw earlier will not compile with `LendingIterator` ([playground](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=3b6c02ae459ccb917a994f8025a45496)):

```rust
fn take_two_v2<T: LendingIterator>(
    t: &mut T,
) -> Option<(T::Item<'_>, T::Item<'_>)> {
    let Some(i) = t.next() else { return None };
    let Some(j) = t.next() else { return None };
    // *Key point:* `i` is still live here, even though we called `next`
    // again to get `j`.
    Some((i, j))
}
```

## An aside: Inherent or accidental complexity?

It seems kind of annoying that `Iterator` and `LendingIterator` are two distinct traits. In a GC'd language, they wouldn't be. This is a good example of what makes using Rust more complex. On the other hand, it's worth asking, is this *inherent* or *accidental* complexity? The answer, I think, is "it depends".

For example, I could certainly write an `Iterator` in Java that makes use of an internal buffer:

```java
class Compute
    implements Iterator<ByteBuffer>
{
    ByteBuffer shared = new ByteBuffer(256);
    
    ByteBuffer next() {
        if (mutateSharedBuffer()) {
            return shared.asReadOnlyBufer();
        }
        return null;
    }
    
    /// Mutates `shared` and return true if there is a new value.
    private boolean mutateSharedBuffer() {
        // ...
    }
}
```

Despite the fact that Java has no way to express the concept, this is most definitely a *lending iterator*. If I try to write a function that invokes `next` twice, the first value will simply not exist anymore:

```java
Compute c = new Compute();
ByteBuffer a = c.next();
ByteBuffer b = c.next();
byte a0 = a.get(); // a has been overwritten with b..
byte b0 = b.get(); // ..so `a0 == b0` is always true.
```

In a case like this, Rust's distinctions are expressing **inherent complexity**[^cure]. If you want to have a shared buffer that you reuse between calls, Java makes it easy to make mistakes. Rust's ownership rules force you to copy out data that you want to keep using, preventing bugs like the one above. Eventually people learn to adopt functional patterns or to clone data instead of sharing access to mutable state. But that requires time and experience, and the compiler and language isn't helping you do so (unless you use, say, Haskell or O'Caml or some purely functional language). These kinds of patterns are a good example of why Rust code winds up having that "if it compiles, it works" feeling, and how the same machinery that guarantees memory safety also prevents logical bugs.

[^cure]: Of course, Rust's notations for expressing these distinctions involve some "accidental complexity" of their own, and you might argue that the cure is worse than the disease. Fair enough.

## `Iterator` as a special case of `LendingIterator`

OK, so we saw that the `Iterator` and `LendingIterator` trait, while clearly related, express an important tradeoff. The `Iterator` trait declares up front that each `Item` is independent from the iterator, but the `LendingIterator` declares that the `Item<'_>` values returned may be borrowed from the iterator. This affects what fully generic code (like our `take_two` function) can do.

But note a careful hedge: I said that the `LendingIterator` trait declares that `Item<'_>` calues **may** be borrowed from the iterator. They don't **have** to be. In fact, every `Iterator` can be viewed as a `LendingIterator` (as you can see in this [playground](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=733200eccf9d8d221a589a7db6f3bc85)), much like every `FnMut` (which takes an `&mut self`) can be viewed as a `Fn` (which takes an `&self`). Essentially an `Iterator` is "just" a `LendingIterator` that doesn't happen to make use of the `'a` argument when defining its `Item<'a>`.

It's also possible to write a version of `take_two` that uses `LendingIterator` but compiles ([playground](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=359a2c2dab5e9e8c277af73c046bd1f3))[^gah]:

[^gah]: This example, by the way, demonstrates how the unergonomic state of GAT support. I don't love writing `for<'a>` all the time.

```rust
fn take_two_v3<T, U>(t: &mut T) -> Option<(U, U)> 
where
    T: for<'a> LendingIterator<Item<'a> = U>
    // ^^^^^^                             ^
    // No matter which `'a` is used, result is always `U`,
    // which cannot reference `'a` (after all, `'a` is not
    // in scope when `U` is declared).
{
    let Some(i) = t.next() else { return None };
    let Some(j) = t.next() else { return None };
    Some((i, j))
}
```

The key here is the where-clause. It says that `T::Item<'a>` is always equal to `U`, no matter what `'a` is. **In other words, the item that is produced by this iterator is *never* borrowed from `self`** -- if it were, then its type would include `'a` somewhere, as that is the lifetime of the reference to the iterator. As a result, `take_two` compiles successfully. Of course, it also can't be used with `LendingIterator` values that actually make use of the flexibility the trait is offering them.

## Can we "unify" `Iterator` and `LendingIterator`?

The fact that every iterator is just a special case of lending iterator begs the question, can they be unified? Jack Huey, in the runup to GATs, spend a while exploring this question, and concluded that it doesn't work. To see why, imagine that we changed `Iterator` so that it had `type Item<'a>`, instead of just `type Item`. It's easy enough to imagine that existing code that says `T: Iterator<Item = u32>` could be reinterpreted as `for<'a> T: Iterator<Item<'a> = u32>`, and then it ought to continue compiling. But the scheme doesn't quite work precisely because of examples like `take_two_v1`:

```rust=
fn take_two_v1<T: Iterator>(t: &mut T) -> Option<(T::Item, T::Item)> {...}
```

This signature just says that it takes an `Iterator`; it doesn't put any additional constraints on it. If we've modified `Iterator` to be a lending iterator, then you can't take two items independently. So we would have to have **some** way to say "any giving iterator" vs "any lending iterator" -- and if we're going to say those two things, why not make it two distinct traits?

## `FnMut` is a giving trait

I started off this post talking about async closures, but so far I've just talked about iterators. What's the connection? Well, for starters, the distinction between sync and async closures is precisely the difference between *giving* and *lending* closures.

**Sync** closures (at least as defined now) are **giving** traits. Consider a (simplified) view of the `FnMut` trait as an example:

```rust
trait FnMut<A> {
    type Output;
    fn call(&mut self, args: A) -> Self::Output;
    //      ^                      ^^^^^^^^^^^^
    // The `self` reference is independent from the
    // return type.
}
```

`FnMut` returns a `Self::Output`, just like the giving `Iterator` returns `Self::Item`. 

## `FnMut` has special syntax

You may not be accustomed to seeing the `FnMut` trait as a regular trait. In fact, on stable Rust, we require you to use special syntax with `FnMut`. For example, you write `impl FnMut(u32) -> bool` as a shorthand for `FnMut<(u32,), Output = bool>`. This is not just for convenience, it's also because we have planned for some time to make changes to the `FnMut` trait (e.g., to make it variadic, rather than having it take a tuple of argument types), and the special syntax is meant to leave room for that. **Pay attention here:** this special syntax turns out to have an important role.

## Async closures are a lending pattern

**Async** closures are closures that return a future. But that future has to capture `self`. So that makes them a kind of **lending** trait. Imagine we had a `LendingFnMut`:

```rust
trait LendingFnMut<A> {
    type Output<'this>
    where
        Self: 'this;
    
    fn call(&mut self, args: A) -> Self::Output<'_>;
    //      ^                                  ^^^^
    // Lends data from `self` as part of return value.
}
```

Now we could (not saying we *should*) express an async closure as a kind of *bound* on `Output`:

```rust
// Imagine we want something like this...
async fn foo(x: async FnMut() -> bool) {...}

// ...that is kind of this:
async fn foo<F>(f: F)
where
    F: LendingFnMut<()>,
    for<'a> F::Output<'a>: Future<Output = bool>
{
    ...
}
```

What is going on here? We saying first that `f` is a *lending* closure that takes no arguments `F: LendingFnMut<()>`. Note that we are **not** using the special `FnMut` sugar here, so this constraint says nothing about the value of `Output`. Then, in the next where-clause, we are specifying that `Output` implements `Future<Output = bool>`. Importantly, we never say what `F::Output` *is*. Just that it will implement `Future`. This means that it **could** include references to `self` (but it doesn't have to).

**Note what just happened**. This is effectively a "third option" for how to desugar some kind of async closures. In my [previous post], I talked about using HKT and about transforming the `FnMut` trait into an async variant (`async FnMut`). But here we see that we could also have a *lending* variant of the trait and then bound the `Output` of that to implement `Future`.

## Closure syntax gives us more room to maneuver

So, to recap things we have seen:

* Giving vs lending traits is a fundamental pattern:
    * A giving trait has a return value that **never** borrows from `self`
    * A lending trait has a return value that **may** borrow from `self`
* Giving traits are *subtraits* of lending traits; i.e., you can view a giving trait as a lending trait that happens not to lend.
* We can't convert `Iterator` to a *lending* trait "in place", because functions that are generic over `T: Iterator` rely on it being the *giving* pattern.
* Async closures are expressible using a *lending* variant of `FnMut`, but not the current trait, which is the *giving* version.

Given the last two points, it might seem logical that we also can't convert `FnMut` "in place" to the lending version, and that therefore we have to add some kind of separate trait. In fact, though, this is not true, and the reason is because of the forced closure syntax. In particular, it's not possible to write a function today that is generic over `F: FnMut<A>` but doesn't specify a specific value for the `Output` generic type. When you write `F: FnMut(u32)`, you are actually specifying `F: FnMut<(u32,), Output = ()>`. It *is* possible to write generic code that talks about `F::Output`, but that will always be normalizable to something else, because adding the `FnMut` bound always includes a value for `Output`.

In principle, then, we could redefine the `Output` associated type to take a lifetime parameter and change the desugaring for `F: FnMut() -> R` to be `for<'a> F: FnMut<(), Output<'a> = R>`. We would also have to make `F::Output` be legal even without specifying a value for its lifetime parameter; there are a few ways we could do that.

## How to interpret impl Trait in the value of an associated type

Let's imagine that we changed the `Fn*` to be lending traits, then. That's still not enough to support our original goal:

```rust
fn take_closure(x: impl FnMut() -> impl Future<Output = bool>) { }
//                                 ^^^^
// Impl trait is not supported here.
```

The problem is that we also have to decide how to desugar `impl Trait` in this position. The interpretation that we want is not entirely obvious. We could choose to desugar `-> impl Future` as a bound on the `Output` type, i.e., to this:

```rust
fn take_closure<F>(x: F) 
where
    F: FnMut<()>,
    for<'a> <F as FnMut<()>>::Output<'a>: Future<Output = bool>.
{ }
```

If we did this, then the `Output` value is permitted to capture `'a`, and hence we are taking advantage of `FnMut` being a lending closure. This means that, when we call the closure, we have to await the resulting future before we can call again, just like we wanted.

### Complications

Interpreting `impl Trait` this way is a bit tricky. For one thing, it seems inconsistent with how we interpret `impl Trait` in a parameter like `impl Iterator<Item = impl Debug>`. Today, that desugars to two fresh parameters `<F, G>` where `F: Iterator<Item = G>, G: Debug`. We could probably change that without breaking real world code, since if the associated type is not a GAT I don't think it matters, but we also permit things like `impl Iterator<Item = (impl Debug, impl Debug)>` that cannot be expressed as bounds. [RFC #2289][] proposed a new syntax for these sorts of bounds, such that one would write `F: Iterator<Item: Debug>` to express the same thing. By analogy, one could imagine writing `F: FnMut(): Future<Output = bool>`, but that's not consistent with the `-> impl Future` that we see elsewhere. It feels like there's a bit of a tangle of string to sort out here if we try to go down this road, and I worry about winding up with something that is very confusing for end-users (too many subtle variations).

[RFC #2289]: https://github.com/rust-lang/rust/issues/52662

## Conclusion

To recap all the points made in this post:

* Giving vs lending traits is a fundamental pattern:
    * A giving trait has a return value that **never** borrows from `self`
    * A lending trait has a return value that **may** borrow from `self`
* Giving traits are *subtraits* of lending traits; i.e., you can view a giving trait as a lending trait that happens not to lend.
* We can't convert `Iterator` to a *lending* trait "in place", because functions that are generic over `T: Iterator` rely on it being the *giving* pattern.
* Async closures are expressible using a *lending* variant of `FnMut`, but not the current trait, which is the *giving* version.
* It is possible to modify the `Fn*` traits to be "lending" by changing how we desugar `F: Fn`, but we have to make it possible to write `F::Output` even when `Output` has a lifetime parameter (perhaps only if that parameter is statically known not to be used).
* We'd also have to interpret `FnMut() -> impl Future` as being a bound on a possibly lent return type, which would be somewhat inconsistent with how `Foo<Bar = impl Trait>` is interpreted now (which is as a fresh type).

## Hat tip

Tip of the hat to Tyler Mandry -- this post is basically a summary of a conversation we had.

## Footnotes