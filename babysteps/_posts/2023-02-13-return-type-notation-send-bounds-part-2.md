---
layout: post
title: Return type notation (send bounds, part 2)
date: 2023-02-13 11:14 -0500
---
In the [previous post][pp], I introduced the “send bound” problem, which refers to the need to add a `Send` bound to the future returned by an async function. I want to start talking about some of the ideas that have been floating around for how to solve this problem. I consider this a bit of an open problem, in that I think we know a lot of the ingredients, but there is a bit of a “delicate balance” to finding the right syntax and so forth. To start with, though, I want to introduce Return Type Notation, which is an idea that Tyler Mandry and I came up with for referring to the type returned by a trait method.  

[pp]: {{ site.baseurl }}/blog/2023/02/01/async-trait-send-bounds-part-1-intro/

### Recap of the problem

If we have a trait `HealthCheck` that has an async function `check`…

```rust
trait HealthCheck {
    async fn check(&mut self, server: Server);
}
```

…and then a function that is going to call that method `check` but in a parallel task…

```rust
fn start_health_check<H>(health_check: H, server: Server)
where
    H: HealthCheck + Send + 'static,
{ 
    …
}
```

…we don’t currently have a way to say that the future returned by calling `H::check()` is send. The where clause `H: HealthCheck + Send` says that the type `H` must be send, but it says nothing about the future that gets returned from calling `check`.

### Core idea: A way to name “the type returned by a function”

The core idea of return-type notation is to let you write where-clauses that apply to `<H as HealthCheck>::check(..)`, which means “any return type you can get by calling `check` as defined in the impl of `HealthCheck` for `H`”. This notation is meant to be reminiscent of the fully qualified notation for associated types, e.g. `<T as Iterator>::Item`. Just as we usually abbreviate associated types to `T::Item`, you would also typically abbreviate return type notation to `H::check(..)`. The trait name is only needed when there is ambiguity.

Here is an example of how `start_health_check` would look using this notation:

```rust
fn start_health_check<H>(health_check: H, server: Server)
where
    H: HealthCheck + Send + 'static,
    H::check(..): Send, // <— return type notation
```

Here the where clause `H::check(..): Send` means “the type(s) returned when you call `H::check` must be `Send`. Since async functions return a future, this means that future must implement `Send`.

## More compact notation

Although it has not yet been stabilized, [RFC #2289][] proposed a shorthand way to write bounds on associated types; something like `T: Iterator<Item: Send>` means “`T` implements `Iterator` and its associated type `Item` implements `Send`”. We can apply that same sugar to return-type notations:

[RFC #2289]: https://rust-lang.github.io/rfcs/2289-associated-type-bounds.html?highlight=associated#

```rust
fn start_health_check<H>(health_check: H, server: Server)
where
    H: HealthCheck<check(..): Send> + Send + 'static,
    //             ^^^^^^^^^
```

This is more concise, though also clearly kind of repetitive. (When I read it, I think “how many dang times do I have to write `Send`?” But for now we’re just trying to explore the idea, not evaluate its downsides, so let’s hold on that thought.)

## Futures capture their arguments

Note that the where clause we wrote was

```rust
H::check(..): Send
```

and not 

```rust
H::check(..): Send + ‘static
```

Moreover, if we were to add a `'static` bound, the program would not compile. Why is that? The reason is that async functions in Rust desugar to returning a future that captures all of the function’s arguments:

```rust
trait HealthCheck {
    // async fn check(&mut self, server: Server);
    fn check<‘s>(&’s mut self, server: Server) -> impl Future<Output = ()> + ‘s;
    //           ^^^^^^^^^^^^                                                ^^
    //         The future captures `self`, so it requires the lifetime bound `'s` 
}
```

Because the future being returned captures `self`, and `self` has type `&’s mut Self`, the `Future` returned must capture `’s`. Therefore, it is not `’static`, and so the where-clause `H::check(..): Send + ‘static` doesn’t hold for all possible calls to `check`, since you are not required to give an argument of type `&’static mut Self`.

## RTN with specific parameter types

Most of the time, you would use RTN to bound all possible return values from the function. But sometimes you might want to be more specific, and talk just about the return value for some specific argument types. As a silly example, we could have a function like

```rust
fn call_check_with_static<H>(h: &’static mut H)
where
   H: HealthCheck + ‘static,
   H::check(&’static mut H, Server): ‘static,
```

This function has a generic parameter `H` that is `’static` and it gets a `&’static mut H` as argument. The where clause `H::check(&’static mut H, Server): ‘static` then says: if I call `check` with the argument `&’static mut H`, it will return a `‘static` future. In contrast to the previous section, where we were talking about any possible return value from `check`, this where-clause is true and valid.

## Desugaring RTN to associated types

To understand what RTN does, it’s best to think of the desugaring from async functions to associated types. This desugaring is exactly how Rust works internally, but we are not proposing to expose it to users directly, for reasons I’ll elaborate in a bit. 

We saw earlier how an `async fn` desugars to a function that returns `impl Future`. Well, in a trait, returning `impl Future` can itself be desugared to a trait with a(generic) associated type:

```rust
trait HealthCheck {
    // async fn check(&mut self, server: Server);
    type Check<‘t>: Future<Output = ()> + ‘t;
    fn check<‘s>(&’s mut self, server: Server) -> Self::Check<‘s>;
}
```

When we write a where-clause like `H::check(..): Send`, that is then effectively a bound on this hidden associated type `Check`:

```rust
fn start_health_check<H>(health_check: H, server: Server)
where
    H: HealthCheck + Send + 'static,
    for<‘a> H::Check<‘a>: Send, // <— equivalent to `H::check(..): Send`
```

## Generic methods

It is also possible to have generic async functions in traits. Imagine that instead of `HealthCheck` taking a specific `Server` type, we wanted to accept any type that implements the trait `ServerTrait`:

```rust
trait HealthCheckGeneric {
    async fn check_gen<S: ServerTrait>(&mut self, server: S);
}
```

We can still think of this trait as desugaring to a trait with an associated type:

```rust
trait HealthCheckGeneric {
    // async fn check<S>(&mut self, server: S) where S: ServerTrait,
    type CheckGen<‘t, S: ServerTrait>: Future<Output = ()> + ‘t;
   fn check_gen <‘s, S: ServerTrait>(&’s mut self, server: Server) -> Self::CheckGen<‘s, S>;
}
```

But if we want to write a where-clause like `H::check_gen(..): Send`, this would require us to support higher-ranked trait bounds over *types* and not just lifetimes:

```rust
fn start_health_check<H>(health_check: H, server: Server)
where
    H: HealthCheckGeneric + Send + 'static,
    for<‘a, S> H::CheckGen<‘a, S>: Send, // <—
    //     ^ for all types S…
```

As it happens, this sort of where-clause is something the [types team][tt] is working on in our new solver design. I’m going to skip over the details, as it’s kind of orthogonal to the topic of how to write `Send` bounds.

[tt]: https://blog.rust-lang.org/2023/01/20/types-announcement.html

One final note: just as you can specify a particular value for the argument types, you should be able to use turbofish to specify the value for generic parameters. So something like `H::check_gen::<MyServer>(..): Send` would mean “whenever you call `check_gen` on `H` with `S = MyServer`, the return type is `Send`”.

## Using RTN outside of where-clauses

So far, all the examples I’ve shown you for RTN involved a where-clause. That is the most important context, but it should be possible to write RTN types any place you write a type. For the most part, this is just fine, but using the `..` notation outside of a where-clause introduces some additional complications. Think of `H::check` — the precise type that is returned will depend on the lifetime of the first argument. So we could have one type `H::check(&’a mut H, Server)` and the return value would reference the lifetime `’a`, but we could also have `H::check(&’b mut H, Server)`, and the return value would reference the lifetime `’b`. The `..` notation really names a *range* of types. For the time being, I think we would simply say that `..` is not allowed outside of a where-clause, but there are ways that you could make it make sense (e.g., it might be valid only when the return type doesn’t depend on the types of the parameters).

## “Frequently asked questions”

That sums up our tour of the “return-type-notation” idea. In short:

* You can write bounds like `<T as Trait>::method(..): Send` in a where-clause to mean “the method `method` from the impl of `Trait` for `T` returns a value that is `Send`, no matter what parameters I give it”.
* Like an associated type, this would more commonly be written `T::method(..)`, with the trait automatically determined.
* You could also specify precise types for the parameters and/or generic types, like `T::method(U, V)`.

Let’s dive into some of the common questions about this idea.

### Why not just expose the desugared associated type directly?

Earlier I explained how `H::check(..)` would work by desugaring it to an associated type. So, why not just have users talk about that associated type directly, instead of adding a new notation for “the type returned by `check`”? The main reason is that it would require us to expose details about this desugaring that we don’t necessarily want to expose. 

The most obvious detail is “what is the name of the associated type” — I think the only clear choice is to have it have the same name as the method itself, which is slightly backwards incompatible (since one can have a trait with an associated type and a method that has the same name), but easy enough to do over an edition. 

We would also have to expose what generic parameters this associated type has. This is not always so simple. For example, consider this trait:

```rust
trait Dump {
   async fn dump(&mut self, data: &impl Debug);
}
```

If we want to desugar this to an associated type, what generics should that type have?

```rust
trait Dump {
    type Dump<…>: Future<Output = ()> + …;
    //        ^^^ how many generics go here?
    fn dump(&mut self, data: &impl Debug) -> Self::Dump<…>;
}
```

This function has two sources of “implicit” generic parameters: elided lifetimes and the `impl Trait` argument. One desugaring would be:

```rust
trait Dump {
    type Dump<‘a, ‘b, D: Debug>: Future<Output = ()> + ‘a + ‘b;
   fn dump<‘a, ‘b, D: Debug>(&’a mut self, data: &’b D) -> Self::Dump<‘a, ‘b, D>;
}
```

But, in this case, we could also have a simpler desugaring that uses just one lifetime parameter (this isn’t always the case):

```rust
trait Dump {
    type Dump<‘a, D: Debug>: Future<Output = ()> + ‘a;
   fn dump<‘a, D: Debug>(&’a mut self, data: &’a D) -> Self::Dump<‘a, D>;
}
```

Regardless of how we expose the lifetimes, the `impl Trait` argument also raises interesting questions. In ordinary functions, the lang-team generally favors not including `impl Trait` arguments in the list of generics (i.e., they can’t be specified by turbofish, their values are inferred from the argument types), although we’ve not reached a final decision there. That seems inconsistent with exposing the type parameter `D`.

All in all, the appeal of the RTN is that it skips over these questions, leaving the compiler room to desugar in any of the various equivalent ways. It also means users don’t have to understand the desugaring, and can just think about the “return value of check”.

### Should `H::check(..): Send` mean that the *future* is `Send`, or the result of the future? 

Some folks have pointed out that `H::check(..): Send` seems like it refers to the value you get from *awaiting* `check`, and not the future itself. This is particularly true since our async function notation doesn’t write the future explicitly, unlike (say) C# or TypeScript (in those languages, an `async fn` must return a task or promise type). This seems true, it *will* likely be a source of confusion — but it’s also consistent with how async functions work. For example:

```rust
trait Get {
    async fn get(&mut self) -> u32;
}

async fn bar<G: Get>(g: &mut G) {
    let f: impl Future<Output = u32> = g.get();
}
```

In this code, even though `g.get()` is declared to return `u32`, `f` is a future, not an integer. Writing `G::get(..): Send` thus talks about the *future*, not the integer.

### Isn’t RTN kind of verbose?

Interesting fact: when I talk to people about what is confusing in Rust, the trait system ranks as high or higher than the borrow checker. If we take another look at our motivation example, I think we can start to see why:

```rust
fn start_health_check<H>(health_check: H, server: Server)
where
    H: HealthCheck<check(..): Send> + Send + 'static,
```

That where-clause basically just says “`H` is safe to use from other threads”, but it requires a pretty dense bit of notation! (And, of course, also demonstrates that the borrow checker and the trait system are not independent things, since `’static` can be seen as a part of both, and is certainly a common source of confusion.) Wouldn’t it be nice if we had a more compact way to say that?

Now imagine you have a trait with a lot of methods:

```rust
trait AsyncOps {
    async fn op1(self);
    async fn op2(self);
    async fn op3(self);
}
```

Under the current proposal, to create an `AsyncOps` that can be (fully) used across threads, one would write:

```rust
fn do_async_ops<A>(health_check: H, server: Server)
where
    A: AsyncOps<op1(..): Send, op2(..): Send, op3(..): Send> + Send + 'static,
```

You could use a trait alias (if we stabilized them) to help here, but still, this seems like a problem! 

### But maybe that verbosity is useful?

Indeed! RTN is a very flexible notation. To continue with the `AsyncOps` example, we could write a function that says "the future returned by `op1` must be send, but not the others", which would be useful for a function like so:

```rust
async fn do_op1_in_parallel(a: impl AsyncOps<op1(..): Send + 'static>) {
    //                                       ^^^^^^^^^^^^^^^^^^^^^^^
    //                                       Return value of `op1` must be Send, static
    tokio::spawn(a.op1()).await;
}
```

### Is RTN limited to async fn in traits?

All my examples have focused on async fn in traits, but we can use RTN to name the return types of any function anywhere. For example, given a function like `get`:

```rust
fn get() -> impl FnOnce() -> u32 {
    move || 22
}
```

we could allow you to write `get()` to name name the closure type that is returned:

```rust
fn foo() {
    let c: get() = get();
    let d: u32 = c();
}
```

This seems like it would be useful for things like iterator combinators, so that you can say things like “the iterator returned by calling `map` is `Send`”.

### Why do we have to write `..`?

OK, nobody asks this, but I do sometimes feel that writing `..` just seems silly. We could say that you just write `H::check(): Send` to mean "for all parameters". (In the case where the method has no parameters, then "for all parameters" is satisfied trivially.) That doesn’t change anything fundamental about the proposal but it lightens the “line noise” aspect a tad:

```rust
fn start_health_check<H>(health_check: H, server: Server)
where
    H: HealthCheck<check(): Send> + Send + 'static,
```

It does introduce some ambiguity. Did the user mean “for all parameters” or did they forget that `check()` has parameters? I’m not sure how this confusion is harmful, though. The main way I can see it coming about is something like this:

* `check()` initially has zero parameters, and the user writes `check(): Send`.
* In a later version of the program, a parameter is added, and now the meaning of `check` changes to “for all parameters” (although, as we noted before, that was arguably the meaning before).

There is a shift happening here, but what harm can it do? If the check still passes, then `check(T): Send` is true for any `T`. If it doesn’t, the user gets an error has to add an explicit type for this new parameter.

### Can we really handle this in our trait solver?

As we saw when discussing generic methods, handling this feature in its full generality is a bit much for our trait solver today. But we could begin with a subset -- for example, the notation can only be used in where-clauses and only for methods that are generic over lifetime parameters and not types. Tyler and I worked out a subset we believe would be readily implementable.

## Conclusion

This post introduced return-type notation, an extension to the type grammar that allows you to refer to the return type of a trait method, and covered some of the pros/cons. Here is a rundown:

**Pros:**

* Extremely flexible notation that lets us say precisely which methods must return `Send` types, and even lets us go into detail about which argument types they will be called with.
* Avoids having to specify a desugaring to associated types precisely. For example, we don’t have to decide how to name that type, nor do we have to decide how many lifetime parameters it has, or whether `impl Trait` arguments become type parameters.
* Can be used to refer to return values of things beyond async functions.

**Cons:**

* New concept for users to learn — now they have associated types as well as associated return types.
* Verbose even for common cases; doesn’t scale up to traits with many methods.
