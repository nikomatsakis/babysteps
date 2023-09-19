---
layout: post
title: Never patterns, exhaustive matching, and uninhabited types (oh my!)
categories: [Rust]
---

One of the long-standing issues that we've been wrestling with in Rust
is how to integrate the concept of an "uninhabited type" -- that is, a
type which has no values at all. Uninhabited types are useful to
represent the "result" of some computation you know will never execute
-- for example, if you have to define an error type for some
computation, but this particular computation can never fail, you might
use an uninhabited type.

[RFC 1216](https://github.com/rust-lang/rfcs/pull/1216) introduced `!`
as the sort of "canonical" uninhabited type in Rust, but actually one
can readily make an uninhabited type of your very own just by declared
an enum with no variants (e.g., `enum Void { }`). Since such an enum
can never be instantiated, the type cannot have any values. Done.

However, ever since the introduction of `!`, we've wrestled with some
of its implications, particularly around *exhaustiveness checking* --
that is, the checks the compiler does to ensure that when you write a
`match`, you have covered every possibility. As we'll see a bit later,
there are some annoying tensions -- particularly between the needs of
"safe" and "unsafe" code -- that are tricky to resolve. 

Recently, though, Ralf Jung and I were having a chat and we came up
with an interesting idea I wanted to write about. This idea offers a
possibility for a "third way" that lets us resolve some of these
tensions, I believe.

### The idea: `!` patterns

Traditionally, when one has an uninhabited type, one "matches against
it" by not writing any patterns at all. So, for example, consider the
`enum Void { }` case I had talked about. Today in Rust [you can match
against such an enum with an empty match
statement](https://play.rust-lang.org/?gist=a9d9a47db5496de43ccc4b8bea225413&version=stable&mode=debug&edition=2015):

```rust
enum Void { }
fn foo(v: Void) {
  match v { }
}
```

In effect, this match serves as a kind of assertion. You are saying
"because `v` can never be instantiated, `foo` could never actually be
called, and therefore -- when I match against it -- this `match` must
be dead code".  Since the match is dead code, you don't need to give
any match arms: there is nowhere for execution to flow.

The funny thing is that you made this assertion -- that the match is
dead code -- by **not writing anything at all**. We'll see later that
this can be problematic around unsafe code. The idea that Ralf and I
had was to introduce a new kind of pattern, a `!` pattern (pronounced
a "never" pattern). **This `!` pattern matches against any enum with
no variants** -- it is an explicit way to talk about impossible cases.
Note that the `!` pattern *can* be used with the `!` type, but it can
also be used with other types, like `Void`.

Now we can consider the `match v { }` above as a kind of shorthand for
a use of the `!` pattern:

```rust
fn foo(v: Void) {
  match v {
    !
  }
}
```

Note that since `!` explicitly represents an unreachable pattern, we
don't need to give a "body" to the match arm either.

We can use `!` to cover more complex cases as well. Consider something
like a `Result` that uses `Void` as the error case. If we want, we can
use the `!` pattern to explicitly say that the `Err` case is
impossible:

```rust
fn foo(v: Result<String, Void>) {
  match v {
    Ok(s) => ...,
    Err(!),
  }
}
```

Same for matching a "reference to nothing":

```rust
fn foo(v: &!) {
  match v {
    &!,
  }
}
```

### Auto-never transformation

As I noted initially, the Rust compiler currently accepts "empty
match" statements when dealing with uninhabited types. So clearly the
use of the `!` pattern cannot be mandatory -- and anyway that would be
unergonomic. The idea is that before we check exhaustiveness and so
forth we have an "auto-never" step that automatically adds `!`
patterns into your match as needed.

There are two ways you can be missing cases:

- If you are matching against an `enum`, you might cover *some* of the enum variants
  but not all. e.g., `match foo { Ok(_) => ... }`  is missing the `Err` case.
- If you are matching against other kinds of values, you might be missing an arm
  altogether. This occurs most often with an empty match like `match v { }`.
  
The idea is that -- when you omit a case -- the compiler will attempt
to insert `!` patterns to cover that case. In effect, to try and prove
on your behalf that this case is impossible. If that fails, you'll get
an error.

The auto-never rules that I would initially propose are as
follows. The idea is that we define the auto-never rules based on the
*type* that is being matched:

- When matching a tuple of struct (a "product type"), we will "auto-never" 
  *all* of the fields.
  - So e.g. if matching a `(!, !)` tuple, we would auto-never a `(!, !`) pattern.
  - But if matching a `(u32, !)` tuple, auto-never would fail. You would have
    to explicit write `(_, !)` as a pattern -- we'll cover this case when we
    talk about unsafe code below.
- When matching a reference is uninhabited, we will generate a `&` pattern
  and auto-never the referent.
  - So e.g. if matching a `&!`, we would generate a `&!` pattern.
  - **But** there will be a lint for this case that fires "around unsafe code",
    as we discuss below.
- When matching an enum, then the "auto-never" would add all missing variants
  to that enum and then recursively auto-never those variants' arguments.
  - e.g., if you write `match x { None => .. .}` where `x:
    Option<T>`, then we will attempt to insert `Some(P)` where the
    pattern `P` is the result of "auto-nevering" the type `T`.

Note that these rules compose. So for example if you are matching a
value of type `&(&!, &&Void)`, we would "auto-never" a pattern like
`&(&!, &&!)`.

### Implications for safe code

One of the main use cases for uninhabited types like `!` is to be able
to write generic code that works with `Result` but have that `Result`
be optimized away when errors are impossible. So the generic code
might have a `Result<String, E>`, but when `E` happens to be `!`, that
is represented in memory the same as `String` -- *and* the compiler
can see that anything working with `Err` variants must be dead-code.

Similarly, when you get a result from such a generic function and you
know that `E` is `!`, you should be able to painlessly 'unwrap' the
result.  So if I have a value `result` of type `Result<String, !>`, I
would like to be able to use a `let` to extract the `String`:

```rust
let result: Result<String, !> = ...;
let Ok(value) = result;
```

and extract the `Ok` value `v`. Similarly, I might like to extract
a reference to the inner value as well, doing something like this:

```rust
let result: Result<String, !> = ...;
let Ok(value) = &result;
// Here, `value: &String`.
```

or -- equivalently -- by using the `as_ref` method

```rust
let result: Result<String, !> = ...;
let Ok(value) = result.as_ref();
// Here, `value: &String`.
```

All of these cases should work out just fine under this proposal. The
auto-never transformation would effectively add `Err(!)` or `Err(&!)`
patterns -- so the final example would be equivalent to:

```rust
let value = match result.as_ref() {
  Ok(v) => v,
  Err(&!),
};
```

### Unsafe code and access-based models

Around safe code, the idea of `!` patterns and auto-never don't seem
that useful: it's maybe just an interesting way to make it a bit more
explicit what is happening. Where they really start to shine, however,
is when you start thinking carefully about *unsafe* code -- and in
particular when we think about how matches interact with access-based
models of undefined behavior.

#### What data does a match "access"?

While the details of our model around unsafe code are still being
worked out (in part by this post!), there is a general consensus that
we want an "access-based" model. For more background on this, see
Ralf's lovely recent blog post on [Stacked Borrows][sb], and in
particular the first section of it. In general, in an access-based
model, the user asserts that data is valid by accessing it -- and in
particular, they need not access **all** of it.

[sb]: https://www.ralfj.de/blog/2018/08/07/stacked-borrows.html

So how do access-based models relate to matches? The Rust match is a
very powerful construct that can do a lot of things! For example, it
can extract fields from structs and tuples:

```rust
let x = (22, 44);
match x {
  (v, _) => ..., // reads the `x.0` field
  (_, w) => ..., // reads the `x.1` field
}
```

It can test which enum variant you have:

```rust
let x = Some(22);
match x {
  Some(_) => ...,
  None => ...,
}
```

And it can dereference a reference and read the data
that it points at:

```rust
let x = &22;
match x {
  &w => ..., // Equivalent to `let w = *x;`
}
```

**So how do we decide which data a match looks at?** The idea is that
you should be able to figure that out by looking at the patterns in
the match arms and seeing what data they touch:

- If you have a pattern with an enum variant like `Some(_)`, then it
  must access the discriminant of the enum being matched.
- If you have a `&`-pattern, then it must dereference the reference
  being matched.
- If you have a binding, then it must copy out the data that is
  bound (e.g., the `v` in `(v, _)`).
  
This seems obvious enough. But what about when dealing with an
uninhabited type? If I have `match x { }`, there are no arms at all,
so what data does *that* access?

The key here is to think about the matches **after** the auto-never
transformation has been done. In that case, we will never have an
"empty match", but rather a `!` pattern -- possibly wrapped in some
other patterns.  Just like any other enum pattern, this `!` pattern is
logically a kind of "discriminant read" -- but in this case we are
reading from a discriminant that cannot exist (and hence we can
conclude the code is dead).

So, for example, we had a "reference-to-never" situation, like so:

```rust
let x: &! = ...;
match x { }
```

then this would be desugared into

```rust
let x: &! = ...;
match x { &! }
```

Looking at this elaborated form, the presence of the `&` pattern makes
it clear that the match will access `*x`, and hence that the reference
`x` must be valid (or else we have UB) -- and since no valid reference
to `!` can exist, we can conclude that this match is dead code.

### Devil is in the details

Now that we've introduced the idea of unsafe code and so forth, there
are two particular interactions between the auto-never rules and unsafe
code that I want to revisit:

- **Uninitialized memory**, which explains why -- when we auto-never a tuple type --
  we require *all* fields of the tuple to have uninhabited type, instead
  of just one.
- **References**, which require some special care. In the auto-never
  rules as I proposed them earlier, we used a lint to try and thread
  the needle here.

#### Auto-never of tuple types and uninitialized memory

In the auto-never rules, I wrote the following:

> - When matching a tuple of struct (a "product type"), we will "auto-never" 
>   *all* of the fields.
>   - So e.g. if matching a `(!, !)` tuple, we would auto-never a `(!, !`) pattern.
>   - But if matching a `(u32, !)` tuple, auto-never would fail. You would have
>     to explicit write `(_, !)` as a pattern -- we'll cover this case when we
>     talk about unsafe code below.

You might think that this is stricter than necessary. After all, you
can't possibly construct an instance of a tuple type like `(u32, !)`,
since you can't produce a `!` value for the second half. So why
require that *all* fields by uninhabited?

The answer is that, using unsafe code, it is possible to *partially*
initialize a value like `(u32, !)`. In other words, you could create
code that just uses the first field, and ignores the second one. In
fact, this is even quite reasonable!  To see what I mean, consider a
type like `Uninit`, which allows one to manipulate values that are
possibly uninitialized (similar to the one introduced in [RFC 1892]):

```rust
union Uninit<T> {
  value: T,
  uninit: (),
}
```

[RFC 1892]: https://github.com/rust-lang/rfcs/pull/1892

Note that the contents of a `union` are generally only known to be
valid when the fields are actually accessed (in general, unions may
have fields of more than one type, and the compiler doesn't known
which one is the correct type at any given time -- hopefully the
programmer does).

Now let's consider a function `foo` that uses `Uninit`. `foo` is
generic over some type `T`; this type gets constructed by invoking the
closure `op`:

```rust
fn foo<T>(op: impl FnOnce() -> T) {
  unsafe {
    let x: Uninit<(u32, T)> = Uninit { uninit: () };
    x.value.0 = 22; // initialize first part of the tuple
    ...
    match x.value {
      (v, _) => {
        // access only first part of the tuple
      }
    }
    ...
    x.value.1 = op(); // initialize the rest of the tuple
    ...
  }
}
```

For some reason, in this code, we need to combine the result
of this closure (of type `T`) with a `u32`, and we need to 
manipulate that `u32` before we have invoked the closure (but probably
after too). So we create an **uninitialized** `(u32, T)` value,
using `Uninit`:

```rust
    let x: Uninit<(u32, T)> = Uninit { uninit: () };
```

Then we initialize *just* the `x.value.0` part of the tuple:

```rust
    x.value.0 = 22; // initialize first part of the tuple
```  

Finally, we can use operations like `match` (or just direct
field access) to pull out parts of that tuple. In so doing, we are
careful to ignore (using `_`) the parts that are not yet initialized:

```rust
    match x.value {
      (v, _) => {
        // access only first part of the tuple
      }
    }
```

Now, everything here is hunky-dory, right? Well, now what happens if I
invoke `foo` with a closure `op` that never returns? That closure
might have the return value `!` -- and now `x` has the type
`Uninit<(u32, !)>`. This tuple `(u32, !)` is supposed to be
uninhabited, and yet here we are initializing it (well, the first
half) and accessing it (well, the first half). Is that ok?

In fact, when we first enabled full exhaustivness checking and so
forth, [we hit code doing **exactly** patterns like this][thread0].
(Ony that code wasn't yet using a `union` like `Uninit` -- it was
using `mem::uninitialized`, which creates problems of its own.)

[thread0]: https://internals.rust-lang.org/t/recent-change-to-make-exhaustiveness-and-uninhabited-types-play-nicer-together/4602

In general, a goal for the auto-never rules was that they would only
apply when there is **no matchable data** accessable from the value.
In the case of a type like `(u32, !)`, it may be (as we have seen)
that there is usable data (the `u32`); so if we accepted `match x { }`
that would mean that one could still add a pattern like `(x, _)` which
would (a) extract data and (b) not by dead code and (c) not be
UB. Seems bad.

#### Reference patterns and linting

Now that we are armed with this idea of `!` and the auto-never
transformation, we can examine the problem of reference types, which
turns out to be the primary case where the needs of safe and unsafe
code come into conflict.

Throughout this post, I've been assuming that we want to treat values
of types like `&!` as effectively "uninhabited" -- this follows from
the fact that we want `Result<String, !>` to be something that you can
work with ergonomically in safe code. Since a common thing to do is to
use `as_ref()` to transform a `&Result<String, !>` into a
`Result<&String, &!>`, I think we would still want the compiler to
understand that the `Err` variant ought to be treated as *impossible*
in such a type.

Unfortunately, when it comes to unsafe code, there is a general desire
to treat any reference `&T` "with suspicion". Specifically, we don't
want to make the assumption that this is a reference to valid,
initialized memory **unless we see an explicit dereference by the
user**. This is really the heart of the "access-based" philosophy.

But that implies that a value of type `&!` ought not be considered
uninhabited -- it might be a reference to uninitialized memory, for
example, that is never intended to be used.

If we indeed permit you to treat `&!` values as uninhabited, then we
are making it so that match statements can "invisibily" insert
dereferences for you that you might not expect. That seems worrisome.

Auto-never patterns gives us a way to resolve this impasse. For
example, when matching on a `&!` value, we can insert the `&!` pattern
automatically -- but lint if that occurs in an `unsafe` function or a
function that contains an unsafe block (or perhaps a function that
manipulates raw pointers). Users can then silence the lint by writing
out a `&!` pattern explicitly. Effectively, the lint would enforce the
rule that "in and around unsafe code, you should write out `&!` patterns
explicitly, but in safe code, you don't have to".

Alternatively, we could limit the auto-never transformation so that
`&T` types do not "auto-never" -- but that imposes an ergonomic tax on
safe code.

### Conclusion

This post describes the idea of a "never pattern" (written `!`) that
matches against the `!` type or any other "empty enum" type. It also
describes an auto-never transformation that inserts such patterns into
matches. As a result -- in the desugared case, at least -- we no
longer use the **absence** of a match arm to designate matches against
uninhabited types.

Explicit `!` patterns make it easier to define what data a match will
access. They also give us a way to use lints to help bridge the needs
of safe and unsafe code: we can encourage unsafe code to write
explicit `!` patterns where they might help document subtle points of
the semantics, without imposing that burden on safe code.

