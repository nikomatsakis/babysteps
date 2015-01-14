---
layout: post
title: "Purging proc"
date: 2014-11-26 16:58:56 -0500
comments: true
categories: [Rust]
---

The so-called "unboxed closure" implementation in Rust has reached the
point where it is time to start using it in the standard library.  As
a starting point, I have a
[pull request that removes `proc` from the language][19338]. I started
on this because I thought it'd be easier than replacing closures, but
it turns out that there are a few subtle points to this transition.

I am writing this blog post to explain what changes are in store and
give guidance on how people can port existing code to stop using
`proc`. This post is basically targeted Rust devs who want to adapt
existing code, though it also covers the closure design in general.

To some extent, the advice in this post is a snapshot of the current
Rust master. Some of it is specifically targeting temporary
limitations in the compiler that we aim to lift by 1.0 or shortly
thereafter. I have tried to mention when that is the case.

[19338]: https://github.com/rust-lang/rust/pull/19338

<!-- more -->

### The new closure design in a nutshell

For those who haven't been following, Rust is moving to a powerful new
closure design (sometimes called *unboxed closures*). This part of the
post covers the highlight of the new design. If you're already
familiar, you may wish to skip ahead to the "Transitioning away from
proc" section.

The basic idea of the new design is to unify closures and traits. The
first part of the design is that function calls become an overloadable
operator. There are three possible traits that one can use to overload
`()`:

```rust
trait Fn<A,R> { fn call(&self, args: A) -> R };
trait FnMut<A,R> { fn call_mut(&mut self, args: A) -> R };
trait FnOnce<A,R> { fn call_once(self, args: A) -> R };
```

As you can see, these traits differ only in their "self" parameter.
In fact, they correspond directly to the three "modes" of Rust
operation:

- The `Fn` trait is analogous to a "shared reference" -- it means that
  the closure can be aliased and called freely, but in turn the
  closure cannot mutate its environment.
- The `FnMut` trait is analogous to a "mutable reference" -- it means
  that the closure cannot be aliased, but in turn the closure is
  permitted to mutate its environment. This is how `||` closures work
  in the language today.
- The `FnOnce` trait is analogous to "ownership" -- it means that the
  closure can only be called once. This allows the closure to move out
  of its environment. This is how `proc` closures work today.

#### Enabling static dispatch

One downside of the older Rust closure design is that closures and
procs always implied virtual dispatch. In the case of procs, there was
also an implied allocation. By using traits, the newer design allows
the user to choose between static and virtual dispatch. Generic types
use static dispatch but require monomorphization, and object types use
dynamic dispatch and hence avoid monomorphization and grant somewhat
more flexibility.

As an example, whereas before I might write a function that takes a
closure argument as follows:

```rust
fn foo(hashfn: |&String| -> uint) {
    let x = format!("Foo");
    let hash = hashfn(&x);
    ...
}
```

I can now choose to write that function in one of two ways. I can use
a generic type parameter to avoid virtual dispatch:

```rust
fn foo<F>(hashfn: F)
    where F : FnMut(&String) -> uint
{
    let x = format!("Foo");
    let hash = hashfn(&x);
    ...
}
```

Note that we write the type parameters to `FnMut` using parentheses
syntax (`FnMut(&String) -> uint`). This is a convenient syntactic
sugar that winds up mapping to a traditional trait reference
(currently, `for<'a> FnMut<(&'a String,), uint>`). At the moment,
though, you are *required* to use the parentheses form, because we
wish to retain the liberty to change precisely how the `Fn` trait type
parameters work.

A caller of `foo()` might write:

```rust
let some_salt: String = ...;
foo(|str| myhashfn(str.as_slice(), &some_salt))
```
    
You can see that the `||` expression still denotes a closure. In fact,
the best way to think of it is that a `||` expression generates a
fresh structure that has one field for each of the variables it
touches. It is as if the user wrote:

```rust
let some_salt: String = ...;
let closure = ClosureEnvironment { some_salt: &some_salt };
foo(closure);
```

where `ClosureEnvironment` is a struct like the following:
   
```rust
struct ClosureEnvironment<'env> {
    some_salt: &'env String
}

impl<'env,'arg> FnMut(&'arg String) -> uint for ClosureEnvironment<'env> {
    fn call_mut(&mut self, (str,): (&'arg String,)) -> uint {
        myhashfn(str.as_slice(), &self.some_salt)
    }
}
```
    
Obviously the `||` form is quite a bit shorter.

#### Using object types to get virtual dispatch

The downside of using generic type parameters for closures is that you
will get a distinct copy of the fn being called *for every
callsite*. This is a great boon to inlining (at least sometimes), but
it can also lead to a lot of code bloat.  It's also often just not
practical: many times we want to combine different kinds of closures
together into a single vector. None of these concerns are specific to
closures. The same things arise when using traits in general. The nice
thing about the new closure design is that it lets us use the same
tool -- object types -- in both cases.

If I wanted to write my `foo()` function to avoid monomorphization,
I might change it from:

```rust
fn foo<F>(hashfn: F)
    where F : FnMut(&String) -> uint
{...}
```

to:

```rust
fn foo(hashfn: &mut FnMut(&String) -> uint) {
{...}
```

Note that the argument is now a `&mut FnMut(&String) -> uint`, rather
than being of some type `F` where `F : FnMut(&String) -> uint`.

One downside of changing the signature of `foo()` as I showed is that
the caller has to change as well. Instead of writing:

```rust
foo(|str| ...)
```
    
the caller must now write:

```rust
foo(&mut |str| ...)
```
    
Therefore, what I expect to be a very common pattern is to have a
"wrapper" that is generic which calls into a non-generic inner function:

```rust
fn foo<F>(hashfn: F)
    where F : FnMut(&String) -> uint
{
    foo_obj(&mut hashfn)
}

fn foo_obj(hashfn: &mut FnMut(&String) -> uint)
{...}
```

This way, the caller does not have to change, and only this outer
wrapper is monomorphized, and it will likely be inlined away, and the
"guts" of the function remain using virtual dispatch.

In the future, I'd like to make it possible to pass object types (and other
"unsized" types) by value, so that one could write a function that just
takes a `FnMut()` and not a `&mut FnMut()`:

```rust
fn foo(hashfn: FnMut(&String) -> uint) {
{...}
```

Among other things, this makes it possible to transition simply
between static and virtual dispatch without altering callers and
without creating a wrapper fn. However, it would compile down to
roughly the same thing as the wrapper fn in the end, though with
guaranteed inlining. This change requires somewhat more design and
will almost surely not occur by 1.0, however.

#### Specifying the closure type explicitly

We just said that every closure expression like `|| expr` generates a
fresh type that implements one of the three traits (`Fn`, `FnMut`, or
`FnOnce`). But how does the compiler decide which of the three traits
to use?

Currently, the compiler is able to do this inference based on the
surrouding *context* -- basically, the closure was an argument to a
function, and that function requested a specific kind of closure, so
the compiler assumes that's the one you want. (In our example, the
function `foo()` required an argument of type `F` where `F` implements
`FnMut`.) In the future, I hope to improve the inference to a more
general scheme.

Because the current inference scheme is limited, you will sometimes
need to specify which of the three fn traits you want
explicitly. (Some people also just prefer to do that.) The current
syntax is to use a leading `&:`, `&mut:`, or `:`, kind of like an
"anonymous parameter":

```rust
// Explicitly create a `Fn` closure which cannot mutate its
// environment. Even though `foo()` requested `FnMut`, this closure
// can still be used, because a `Fn` closure is more general
// than `FnMut`.
foo(|&:| { ... })

// Explicitly create a `FnMut` closure. This is what the
// inference would select anyway.
foo(|&mut:| { ... })

// Explicitly create a `FnOnce` closure. This would yield an
// error, because `foo` requires a closure it can call multiple
// times in a row, but it is being given a closure that can be
// called exactly once.
foo(|:| { ... }) // (ERROR)
```

The main time you need to use an explicit `fn` type annotation is when
there is no context. For example, if you were just to create a closure
and assign it to a local variable, then a `fn` type annotation is
required:

```rust
let c = |&mut:| { ... };
```
    
*Caveat:* It is still possible we'll change the `&:`/`&mut:`/`:`
syntax before 1.0; if we can improve inference enough, we might even
get rid of it altogether.

#### Moving vs non-moving closures

There is one final aspect of closures that is worth covering. We gave the
example of a closure `|str| myhashfn(str.as_slice(), &some_salt)`
that expands to something like:
   
```rust
struct ClosureEnvironment<'env> {
    some_salt: &'env String
}
```
    
Note that the variable `some_salt` that is used from the surrounding
environment is *borrowed* (that is, the struct stores a reference to
the string, not the string itself). This is frequently what you want,
because it means that the closure just references things from the
enclosing stack frame. This also allows closures to modify local
variables in place.

However, capturing upvars by reference has the downside that the
closure is tied to the stack frame that created it. This is a problem
if you would like to return the closure, or use it to spawn another
thread, etc.

For this reason, closures can also take ownership of the things that
they close over. This is indicated by using the `move` keyword before
the closure itself (because the closure "moves" things out of the
surrounding environment and into the closure). Hence if we change
that same closure expression we saw before to use `move`:

```rust
move |str| myhashfn(str.as_slice(), &some_salt)
```

then it would generate a closure type where the `some_salt` variable
is owned, rather than being a reference:

```rust
struct ClosureEnvironment {
    some_salt: String
}
```

This is the same behavior that `proc` has. Hence, whenever we replace
a `proc` expression, we generally want a moving closure.

Currently we never infer whether a closure should be `move` or not.
In the future, we may be able to infer the `move` keyword in some
cases, but it will never be 100% (specifically, it should be possible
to infer that the closure passed to `spawn` should always take
ownership of its environment, since it must meet the `'static` bound,
which is not possible any other way).

### Transitioning away from proc

This section covers what you need to do to modify code that was using
`proc` so that it works once `proc` is removed.

#### Transitioning away from proc for library users

For users of the standard library, the transition away from `proc` is
fairly straightforward. Mostly it means that code which used to write
`proc() { ... }` to create a "procedure" should now use `move|| {
... }`, to create a "moving closure". The idea of a *moving closure*
is that it is a closure which takes ownership of the variables in its
environment. (Eventually, we expect to be able to infer whether or not
a closure must be moving in many, though not all, cases, but for now
you must write it explicitly.)

Hence converting calls to libstd APIs is mostly a matter of
search-and-replace:

```rust
Thread::spawn(proc() { ... }) // becomes:
Thread::spawn(move|| { ... })

task::try(proc() { ... }) // becomes:
task::try(move|| { ... })
```

One non-obvious case is when you are creating a "free-standing" proc:

```rust
let x = proc() { ... };
```

In that case, if you simply write `move||`, you will get some strange errors:

```rust
let x = move|| { ... };
```

The problem is that, as discussed before, the compiler needs context
to determine what sort of closure you want (that is, `Fn` vs `FnMut`
vs `FnOnce`). Therefore it is necessary to explicitly declare the sort
of closure using the `:` syntax:

```rust
let x = proc() { ... }; // becomes:
let x = move|:| { ... };
```

Note also that it is precisely when there is no context that you must
also specify the types of any parameters. Hence something like:

```rust
let x = proc(x:int) foo(x * 2, y);
//      ~~~~ ~~~~~
//       |     |
//       |     |
//       |     |
//       |   No context, specify type of parameters.
//       |
//      proc always owns variables it touches (e.g., `y`)
```

might become:

```rust
let x = move|: x:int| foo(x * 2, y);
//      ~~~~ ^ ~~~~~
//       |   |   |
//       |   |  No context, specify type of parameters.
//       |   |
//       |   No context, also specify FnOnce.
//       |
//     `move` keyword means that closure owns `y`
```

#### Transitioning away from proc for library authors

The transition story for a library author is somewhat more
complicated. The complication is that the equivalent of a type like
`proc():Send` ought to be `Box<FnOnce() + Send>` -- that is, a boxed
`FnOnce` object that is also sendable. However, we don't currently
have support for invoking `fn(self)` methods through an object, which
means that if you have a `Box<FnOnce()>` object, you can't call it's
`call_once` method (put another way, the `FnOnce` trait is not object
safe). We plan to fix this -- possibly by 1.0, but possibly shortly
thereafter -- but in the interim, there are workarounds you can use.

In the standard library, we use a trait called `Invoke` (and, for
convenience, a type called `Thunk`). You'll note that although these
two types are publicly available (under `std::thunk`), these types do
not appear in the public interface any other stable APIs. That is,
`Thunk` and `Invoke` are essentially *implementation details* that end
users do not have to know about. We recommend you follow the same
practice. This is for two reasons:

1. It generally makes for a better API. People would rather write
   `Thread::spawn(move|| ...)` and not
   `Thread::spawn(Thunk::new(move|| ...))` (etc).
2. Eventually, once `Box<FnOnce()>` works properly, `Thunk` and
   `Invoke` may be come deprecated. If this were to happen, your
   public API would be unaffected.

Basically, the idea is to follow the "thin wrapper" pattern that I
showed earlier for hiding virtual dispatch. If you recall, I gave the
example of a function `foo` that wished to use virtual dispatch
internally but to hide that fact from its clients. It did do by creating
a thin wrapper API that just called into another API, performing the
object coercion:

```rust
fn foo<F>(hashfn: F)
    where F : FnMut(&String) -> uint
{
    foo_obj(&mut hashfn)
}

fn foo_obj(hashfn: &mut FnMut(&String) -> uint)
{...}
```

The idea with `Invoke` is similar. The public APIs are generic APIs
that accept any `FnOnce` value. These just turnaround and wrap that
value up into an object. Here the problem is that while we would
probably prefer to use a `Box<FnOnce()>` object, we can't because
`FnOnce` is not (currently) object-safe. Therefore, we use the trait
`Invoke` (I'll show you how `Invoke` is defined shortly, just let me
finish this example):

```rust
pub fn spawn<F>(taskbody: F)
    where F : FnOnce(), F : Send
{
    spawn_inner(box taskbody)
}

fn spawn_inner(taskbody: Box<Invoke+Send>)
{
    ...
}
```

The `Invoke` trait in the standard library is defined as:

```rust
trait Invoke<A=(),R=()> {
    fn invoke(self: Box<Self>, arg: A) -> R;
}
```
    
This is basically the same as `FnOnce`, except that the `self` type is
`Box<Self>`, and not `Self`. This means that `Invoke` requires
allocation to use; it is really tailed for object types, unlike
`FnOnce`.

Finally, we can provide a bridge impl for the `Invoke` trait as
follows:

```rust
impl<A,R,F> Invoke<A,R> for F
    where F : FnOnce(A) -> R
{
    fn invoke(self: Box<F>, arg: A) -> R {
        let f = *self;
        f(arg)
    }
}
```

This impl allows any type that implements `FnOnce` to use the `Invoke`
trait.

### High-level summary

Here are the points I want you to take away from this post:

1. As a library consumer, the latest changes mostly just mean
   replacing `proc()` with `move||` (sometimes `move|:|` if there
   is no surrounding context).
2. As a library author, your public interface should be generic
   with respect to one of the `Fn` traits. You can then convert
   to an object internally to use virtual dispatch.
3. Because `Box<FnOnce()>` doesn't currently work, library authors may
   want to use another trait internally, such as `std::thunk::Invoke`.

I also want to emphasize that a lot of the nitty gritty details in this
post are transitionary. Eventually, I believe we can reach a point where:

1. It is never (or virtually never) necessary to explicitly declare
   `Fn` vs `FnMut` vs `FnOnce` explicitly.
2. We can frequently (though not always) infer the keyword `move`.
3. `Box<FnOnce()>` works, so `Invoke` and friends are not needed.
4. The choice between static and virtual dispatch can be changed without
   affecting users and without requiring wrapper functions.

I expect the improvements in inference before 1.0. Fixing the final
two points is harder and so we will have to see where it falls on the
schedule, but if it cannot be done for 1.0 then I would expect to see
those changes shortly thereafter.
