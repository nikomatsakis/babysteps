---
layout: post
title: why async fn in traits are hard
categories: [Rust, AsyncAwait]
---

After reading [boat's excellent post on asynchronous destructors][b],
I thought it might be a good idea to write some about `async fn` in
traits. Support for `async fn` in traits is probably the single most
common feature request that I hear about. It's also one of the more
complex topics. So I thought it'd be nice to do a blog post kind of
giving the "lay of the land" on that feature -- what makes it
complicated?  What questions remain open?

[b]: https://boats.gitlab.io/blog/post/poll-drop/

I'm not making any concrete proposals in this post, just laying out
the problems. But do not lose hope! In a future post, I'll lay out a
specific roadmap for how I think we can make incremental progress
towards supporting async fn in traits in a useful way. And, in the
meantime, you can use the [`async-trait`] crate (but I get ahead of
myself...).

## The goal

In some sense, the goal is simple. We would like to enable you to
write traits that include `async fn`. For example, imagine we have
some `Database` trait that lets you do various operations against a
database, asynchronously:

```rust
trait Database {
    async fn get_user(
        &self, 
    ) -> User;
}
```

## Today, you should use async-trait

Today, of course, the answer is that you should dtolnay's
excellent [`async-trait`] crate. This allows you to write
almost what we wanted:

[`async-trait`]: https://crates.io/crates/async-trait

```rust
#[async_trait]
trait Database {
    async fn get_user(&self) -> User;
}
```

But what is really happening under the hood? As the [crate's
documentation explains][ate], this declaration is getting transformed to
the following. Notice the return type.

[ate]: https://github.com/dtolnay/async-trait#explanation

```rust
trait Database {
    fn get_user(&self) -> Pin<Box<dyn Future<Output = User> + Send + '_>>;
}
```

So basically you are returning a boxed `dyn Future` -- a future
object, in other words. This desugaring is rather different from what
happens with `async fn` in other contexts -- but why is that? The rest
of this post is going to explain some of the problems that `async fn`
in traits is trying to solve, which may help explain why we have a
need for the [`async-trait`] crate to begin with!

## Async fn normally returns an impl Future

We saw that the [`async-trait`] crate converts an `async fn` to something
that returns a `dyn Future`. This is contrast to the `async fn` desugaring
that the Rust compiler uses, which produces an `impl Future`. For example,
imagine that we have an inherent method `async fn get_user()` defined on
some particular service type:

```rust
impl MyDatabase {
    async fn get_user(&self) -> User {
        ...
    }
}
```

This would get desugared to something similar to:

```rust
impl MyDatabase {
    fn get_user(&self) -> impl Future<Output = User> + '_ {
        ... 
    }
}
```

So why does `async-trait` do something different? Well, it's
because of "Complication #1"...

## Complication #1: returning `impl Trait` in traits is not supported

Currently, we don't support `-> impl Trait` return types in traits.
Logically, though, we basically know what the semantics of such a
construct should be: it is equivalent to a kind of associated type.
That is, the trait is promising that invoking `get_user` will return
*some* kind of future, but the precise type will be determined by the
details of the impl (and perhaps inferred by the compiler). So, if
know *logically* how `impl Trait` in traits should behave, what stops
us from implementing it? Well, let's see...

### Complication #1a. `impl Trait` in traits requires GATs

Let's return to our `Database` example. Imagine that we permitted
`async fn` in traits. We would therefore desugar 

```rust
trait Database {
    async fn get_user(&self) -> User;
}
```

into something that returns an `impl Future`:

```rust
trait Database {
    fn get_user(&self) -> impl Future<Output = User> + '_;
}
```

and then we would in turn desugar *that* into something that uses
an associated type:

```rust
trait Database {
    type GetUser<'s>: Future<Output = User> + 's;
    fn get_user(&self) -> Self::GetUser<'_>;
}
```

Hmm, did you notice that I wrote `type GetUser<'s>`, and not `type
GetUser`?  Yes, that's right, this is not just an associated type,
it's actually a [**generic** associated type][gat]. The reason for
this is that `async fn` always capture all of their arguments -- so
whatever type we return will include the `&self` as part of it, and
therefore it has to include the lifetime `'s`. So, that's one
complication, we have to figure out generic associated types.

[gat]: https://github.com/rust-lang/rfcs/blob/master/text/1598-generic_associated_types.md

Now, in some sense that's not so bad. Conceptually, GATs are fairly
simple. Implementation wise, though, we're still working on how to
support them in rustc -- this may require porting rustc to use
[chalk], though that's not entirely clear. In any case, this work is
definitely underway, but it's going to take more time. 

[chalk]: https://github.com/rust-lang/chalk

Unfortunately for us, GATs are only the beginning of the complications
around `async fn` (and `impl Trait`) in traits!

## Complication #2: send bounds (and other bounds)

Right now, when you write an `async fn`, the resulting future may or
may not implement `Send` -- the result depends on what state it
captures. The compiler infers this automatically, basically, in
typical auto trait fashion.

But if you are writing generic code, you may well want to need to
require that the resulting future is `Send`. For example, imagine we
are writing a `finagle_database` thing that, as part of its inner
working, happens to spawn off a parallel thread to get the current
user. Since we're going to be spawning a thread with the result from
`d.get_user()`, that result is going to have to be `Send`, which means
we're going to want to write a function that looks *something* like
this[^scoped]:

[^scoped]: Astute readers might note that I'm eliding a further challenge, which is that you need a scoping mechanism here to handle the lifetimes. Let's assume we have something like [Rayon's scope] or [crossbeam's scope] available.

[Rayon's scope]: https://docs.rs/rayon/1.2.0/rayon/fn.scope.html
[crossbeam's scope]: https://docs.rs/crossbeam/0.7.2/crossbeam/thread/struct.Scope.html

```rust
fn finagle_database<D: Database>(d: &D)
where
    for<'s> D::GetUser<'s>: Send,
{
    ...
    spawn(d.get_user());
    ...
}
```

This example seems "ok", but there are four complications

* First, we wrote the name `GetUser`, but that is something we
  introduced as part of "manually" desugaring `async fn
  get_user`. What name would the user *actually* use?
* Second, writing `for<'s> D::GetUser<'s>` is kind of grody, we're obviously
  going to want more compact syntax (this is really an issue around generic
  associated types in general).
* Third, our example `Database` trait has only one async fn, but
  obviously there might be many more. Probably we will want to make
  *all* of them `Send` or `None` -- so you can expand a lot more
  grody bounds in a real function!
* Finally, forcing the user to specify which exact async fns have to
  return `Send` futures is a semver hazard.

Let me dig into those a bit.

### Complication #2a. How to name the associated type?

So we saw that, in a trait, returning an `impl Trait` value is
equivalent to introducing a (possibly generic) associated type. But
how should we *name* this associated type? In my example, I introduced
a `GetUser` associated type as the result of the `get_user`
function. Certainly, you could imagine a rule like "take the name of
the function and convert it to camel case", but it feels a bit hokey
(although I suspect that, in practice, it would work out just
fine). There have been other proposals too, such as `typeof`
expressions and the like.

### Complication #2b. Grody, complex bounds, especially around GATs.

In my example, I used the strawman syntax `for<'s> D::GetUser<'s>:
Send`.  In real life, unfortunately, the bounds you need may well get
more complex still. Consider the case where an `async fn` has generic
parameters itself:

```rust
trait Foo {
    async fn bar<A, B>(a: A, b: B);
}
```

Here, the future that results `bar` is only going to be `Send` if `A:
Send` and `B: Send`. This suggests a bound like

```rust
where
    for<A: Send, B: Send> { S::bar<A, B>: Send }
```

From a conceptual point-of-view, bounds like these are no problem.
Chalk can handle them just fine, for example. But I think this is
pretty clearly a problem and not something that ordinary users are
going to want to write on a regular basis.

### Complication #2c. Listing specific associated types reveals implementation details

If we require functions to specify the *exact* futures that are
`Send`, that is not only tedious, it could be a semver
hazard. Consider our `finagle_database` function -- from its where
clause, we can see that it spawns out `get_user` into a scoped
thread. But what if we wanted to modify it in the future to spawn off
more database operations? That would require us to modify the
where-clauses, which might in turn break our callers. Seems like a
problem, and it suggests that we might want some way to say "all
possible futures are send".

### Conclusion: We might want a new syntax for propagating auto traits to async fns

All of this suggests that we might want some way to propagate auto
traits through to the results of async fns explicitly. For example,
you could imagine supporting `async` bounds, so that we might write
`async Send` instead of just `Send`:

```rust
pub fn finagle_database<DB>(t: DB)
where
    DB: Database + async Send,
{
}
```

This syntax would be some kind of "default" that expands to explicit
`Send` bounds both `DB` and all the futures potentially returned by
`DB`.

Or perhaps we'd even want to avoid *any* syntax, and somehow
"rejigger" how `Send` works when applied to traits that contain async
fns? I'm not sure about how that would work.

It's worth pointing out this same problem can occur with `impl Trait`
in return position[^iteratorx], or indeed any associaed
types. Therefore, we might prefer a syntax that is more general and
not tied to `async`.

[^iteratorx]: Still, consider a trait `IteratorX` that is like `Iterator`, where the adapters return `impl Trait`. In such a case, you probably want a way to say not only "I take a `T: IteratorX + Send`" but also that the `IteratorX` values returned by calls to `map` and the like are `Send`. Presently you would have to list out the specific associated types you want, which also winds up revealing implementation details. 

## Complication #3: supporting dyn traits that have async fns

Now imagine that had our `trait Database`, containing an `async fn
get_user`. We might like to write functions that operate over `dyn Database`
values. There are many reasons to prefer `dyn Database` values:

* We don't want to generate many copies of the same function, one per database type;
* We want to have collections of different sorts of databases, such as a
  `Vec<Box<dyn Database>>` or something like that.

In practice, a desire to support `dyn Trait` comes up in a lot of examples
where you would want to use `async fn` in traits. 

### Complication #3a: `dyn Trait` have to specify their associated type values

We've seen that `async fn` in traits effectively desugars to a
(generic) associated type. And, under the current Rust rules, when you
have a `dyn Trait` value, the type must specify the values for all
associated types.  If we consider our desugared `Database` trait, then,
it would have to be written `dyn Database<GetUser<'s> = XXX>`. This is
obviously no good, for two reasons:

1. It would require us to write out the full type for the `GetUser`,
   which might be super complicated.
2. And anyway, each `dyn Database` is going to have a *distinct*
   `GetUser` type. If we have to specify `GetUser`, then, that kind of
   defeats the point of using `dyn Database` in the first place, as
   the type is going to be specific to some particular service, rather
   than being a single type that applies to all services.

### Complication #3b: no "right choice" for `X` in `dyn Database<GetUser<'s> = X>`

When we're using `dyn Database`, what we actually want is a type where
`GetUser` is **not specified**. In other words, we just want to write
`dyn Database`, full stop, and we want that to be expanded to
something that is perhaps "morally equivalent" to this:

```rust
dyn Database<GetUser<'s> = dyn Future<..> + 's>
```

In other words, all the caller really wants to know when it calls
`get_user` is that it gets back *some* future which it can poll. It
doesn't want to know exactly which one.

Unfortunately, actually using `dyn Future<..>` as the type there is
not a viable choice. We probably want a `Sized` type, so that the
future can be stored, moved into a box, etc. We could imagine then
that `dyn Database` defaults its "futures" to `Box<dyn Future<..>>`
instead -- well, actually, `Pin<Box<dyn Future>>` would be a more
ergonomic choice -- but there are a few concerns with *that*.

First, using `Box` seems rather arbitrary. We don't usually make `Box`
this "special" in other parts of the language.

Second, where would this box get allocated? The actual trait impl for
our service isn't using a box, it's creating a future type and
returning it inline. So we'd need to generate some kind of "shim impl"
that applies whenever something is used as a `dyn Database` -- this
shim impl would invoke the main function, box the result, and return
*that*.

Third, because a `dyn Future` type hides the underlying
future (that is, indeed, its entire purpose), it also blocks the auto
trait mechanism from figuring out if the result is `Send`. Therefore,
when we make e.g. a `dyn Database` type, we need to specify not only
the allocation mechanism we'll use to manipulate the future (i.e., do
we use `Box`?) but also whether the future is `Send` or not.

## Now you see why async-trait desugars the way it does

After reviewing all these problems, we now start to see where the
design of the [`async-trait`] crate comes from:

* To avoid Complications #1 and #2, [`async-trait`] desugars `async fn`
  to return a `dyn Future` instead of an `impl Future`.
* To avoid Complication #3, [`async-trait`] chooses for you to use
  a `Pin<Box<dyn Future + Send>>` (you can [opt-out] from the `Send` part).
  This is almost always the correct default.

[opt-out]: https://github.com/dtolnay/async-trait#non-threadsafe-futures

All in all, it's a very nice solution.

The only real drawback here is that there is some performance hit from
boxing the futures -- but I suspect it is negligible in almost all
applications. I don't think this would be true if we boxed the results
of **all** async fns; there are many cases where async fns are used to
create small combinators, and there the boxing costs *might* start to
add up.  But only boxing async fns that go through trait boundaries is
very different.  And of course it's worth highlighting that most
languages box all their futures, all of the time. =)

## Summary

So to sum it all up, here are some of the observations from this article:

* `async fn` desugars to a fn returning `impl Trait`, so if we want to
  support `async fn` in traits, we should also support fns that
  return `impl Trait` in traits.
    * It's worth pointing out also that sometimes you have to manually
      desugar an `async fn` to a `fn` that returns `impl Future` to avoid
      capturing all your arguments, so the two go hand in hand.
* Returning `impl Trait` in a trait is equivalent to an 
  associated type in the trait.
    * This associated type does need to be nameable, but what name
      should we give this associated type?
    * Also, this associated type often has to be generic, especially
      for `async fn`.
* Applying `Send` bounds to the futures that can be generated is
  tedious, grody, and reveals semver details. We probably some way to
  make that more ergonomic.
    * This quite likely applies to the general `impl Trait` case too,
      but it may come up somewhat less frequently.
* We do want the ability to have `dyn Trait` versions of traits that contain associated
  functions and/or `impl Trait` return types.
    * But currently we have no way to have a `dyn Trait` without fully specifying
      all of its associated types; in our case, those associated types have a 1-to-1
      relationship with the `Self` type, so that defeats the whole point of `dyn Trait`.
    * Therefore, in the case of `dyn Trait`, we would want to have the
      `async fn` within returning *some* form of `dyn Future`. But we would have to effectively
      "hardcode" two choices:
        * What form of pointer to use (e.g., `Box`)
        * Is the resulting future `Send`, `Sync`, etc
    * This applies to the general `impl Trait` case too.

The goal of this post was just to lay out **the problems**. I hope to
write some follow-up posts digging a bit into the solutions -- though
for the time being, the solution is clear: use the [`async-trait`]
crate.

## Footnotes
