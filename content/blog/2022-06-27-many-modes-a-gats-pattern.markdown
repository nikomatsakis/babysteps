---
layout: post
title: 'Many modes: a GATs pattern'
date: 2022-06-27T10:00:00-0400
---

As some of you may know, on May 4th [Jack Huey][jackh726] opened a [PR to stabilize an initial version of generic associated types](https://github.com/rust-lang/rust/pull/96709). The current version is at best an MVP: the compiler support is limited, resulting in unnecessary errors, and the syntax is limited, making code that uses GATs much more verbose than I'd like. Nonetheless, I'm super excited, since GATs unlock a lot of interesting use cases, and we can continue to smooth out the rough edges over time. However, folks on the thread have raised some [strong concerns about GAT stabilization](https://github.com/rust-lang/rust/pull/96709#issuecomment-1129311660), including asking whether GATs are worth including in the language at all. The fear is that they make Rust the language too complex, and that it would be better to just use them as an internal building block for other, more accessible features (like async functions and [return position impl trait in traits][RPITIT]).  In response to this concern, a number of people have posted about how they are using GATs. I recently took some time to deep dive into these comments and to write about some of the patterns that I found there, including a pattern I am calling the "many modes" pattern, which comes from the [chumsky] parser combinator library. I posted about this pattern [on the thread](https://github.com/rust-lang/rust/pull/96709#issuecomment-1167220240), but I thought I would cross-post my write-up here to the blog as well, because I think it's of general interest.

[jackh726]: https://github.com/jackh726/
[chumsky]: https://github.com/zesterer/chumsky/

### General thoughts from reading the examples

I've been going through the (many, many) examples that people have posted where they are relying on GATs and look at them in a bit more detail. A few interesting things jumped out at me as I read through the examples:

* **Many of the use-cases involve GATs with type parameters.** There has been some discussion of stabilizing "lifetime-only" GATs, but I don't think that makes sense from any angle. It's more complex for the implementation and, I think, more confusing for the user. But also, given that the "workaround" for not having GATs tends to be higher-ranked trait bounds (HRTB), and given that those only work for lifetimes, it means we're losing one of the primary benefits of GATs in practice (note that I do expect to get HRTB for types in the near-ish future).
* **GATs allowed libraries to better *hide* details from their clients.** This is precisely because they could make a trait hierarchy that more directly captured the "spirit" of the trait, resulting in bounds like `M: Mode` instead of higher-ranked trait bounds (in some cases, the HRTB would have to be over types, like `for<X> M: Mode<X>`, which isn't even legal in Rust...yet).

As I read, I felt this fit a pattern that I've experienced many times but hadn't given a name to: when traits are being used to describe a situation that they don't quite fit, *the result is an explosion of where-clauses on the clients*. Sometimes you can hide these via supertraits or something, but those complex bounds are still visible in rustdoc, still leak out in error mesages, and don't generally "stay hidden" as well as you'd like. You'll see this come up here when I talk about how you would model this pattern in Rust today, but it's a comon theme across all examples. [Issue #95 on the `RustAudio` crate](https://github.com/RustAudio/rust-lv2/issues/95) for example says, "The first \[solution\] would be to make `PortType` generic over a `'a` lifetime...however, this has a cascading effect, which would force all downstream users of port types to specify their lifetimes". [Pythonesque made a simpler point here](https://github.com/rust-lang/rust/pull/96709#issuecomment-1150127168), "Without GATs, I ended up having to make an Hkt trait that had to be implemented for every type, define its projections, and then make everything heavily parametric and generic over the various conversions."

### The "many modes" pattern (chumsky)

The first example I looked at closely was the [chumsky parsing library](https://github.com/rust-lang/rust/pull/96709#issuecomment-1118409546). This is leveraging a pattern that I would call the "many modes" pattern. The idea is that you have some "core function" but you want to execute this function in many different modes. Ideally, you'd like to define the modes independently from the function, and you'd like to be able to add more modes later without having to change the function at all. (If you're familiar with Haskell, monads are an example of this pattern; the monad specifies the "mode" in which some simple sequential function is executed.)

chumsky is a parser combinator library, so the "core function" is a parse function, defined in the `Parser` trait. Each `Parser` trait impl contains a function that indicates how to parse some particular construct in the grammar. Normally, this parser function builds up a data structure representing the parsed data. But sometimes you don't need the full results of the parse: sometimes you might just like to know if the parse succeeds or fails, without building the parsed version. Thus, the "many modes" pattern: we'd like to be able to define our parser and then execute it against one of two modes, *emit* or *check*. The emit mode will build the data structure, but *check* will just check if the parse succeeds.

In the past, chumsky only had one mode, so they always built the data structure. This could take significant time and memory. Adding the "check" mode let's them skip that, which is a significant performance win. Moreover, the modes are encapsulated within the library traits, and aren't visible to end-users. Nice!

### How did chumsky model modes with GATs?

Chumsky added a [`Mode`] trait, encapsulated as part of their [`internals`] module. Instead of directly constructing the results from parsing, the `Parser` impls invoke methods on [`Mode`] with closures. This allows the mode to decide which parts of the parsing to execute and which to skip. So, in check mode, the [`Mode`] would decide not to execute the closure that builds the output data structure, for example.

[`Mode`]: https://github.com/zesterer/chumsky/blob/6a82f90ae4c1a4564e024eb0f63121fc7b7d3c18/src/zero_copy/mod.rs#L70
[`internals`]: https://github.com/zesterer/chumsky/blob/6a82f90ae4c1a4564e024eb0f63121fc7b7d3c18/src/zero_copy/mod.rs#L67

Using this approach, the [`Parser`](https://github.com/zesterer/chumsky/blob/6a82f90ae4c1a4564e024eb0f63121fc7b7d3c18/src/zero_copy/mod.rs#L137) trait does indeed have several 'entrypoint' methods, but they are all defaulted and just invoke a common implementation method called `go`:

```rust
pub trait Parser<'a, I: Input + ?Sized, E: Error<I::Token> = (), S: 'a = ()> {
    type Output;
    
    fn parse(&self, input: &'a I) -> Result<Self::Output, E> ... {
        self.go::<Emit>(...)
    }

    fn check(&self, input: &'a I) -> Result<(), E> ... {
        self.go::<Check>(...)
    }
    
    #[doc(hidden)]
    fn go<M: Mode>(&self, inp: &mut InputRef<'a, '_, I, E, S>) -> PResult<M, Self::Output, E>
    where
        Self: Sized;
}
```

Implementations of `Parser` *just* specify the `go` method. Note that the impls are, presumably, either contained within `chumsky` or generated by `chumsky` proc-macros, so the `go` method doesn't need to be documented. However, *even if `go` were documented*, the *trait bounds* certainly look quite reasonable. (The type of `inp` is a bit...imposing, admittedly.)

So how is the [`Mode`] trait defined? Just to focus on the GAT, the trait look likes this:

```rust
pub trait Mode {
    type Output<T>;
    ...
}
```

Here, the `T` represents the result type of "some parser parsed in this mode". GATs thus allow us to define a [`Mode`] that is **independent** from any particular `Parser`. There are two impls of [`Mode`] (also internal to chumsky):

* [`Check`](https://github.com/zesterer/chumsky/blob/6a82f90ae4c1a4564e024eb0f63121fc7b7d3c18/src/zero_copy/mod.rs#L115-L117), defined like `struct Check; impl Mode for Check { type Output<T> = (); ... }`. In other words, no matter what parser you use, `Check` just builds a `()` result (success or failure is propagated inepdendently of the mode).
* [`Emit`](https://github.com/zesterer/chumsky/blob/6a82f90ae4c1a4564e024eb0f63121fc7b7d3c18/src/zero_copy/mod.rs#L87-L89), defined like `struct Emit; impl Mode for Emit { type Output<T> = T; ... }`.  In `Emit` mode, the output is exactly what the parser generated.

Note that you could, in theory, produce other modes. For example, a `Count` mode that not only computes success/failure but counts the number of nodes parsed, or perhaps a mode that computes hashes of the resulting parsed value. Moreover, you could add these modes (and the defaulted methods in `Parser`) **without breaking any clients**.

### How could you model this today?

I was trying to think how one might model this problem with traits today. All the options I came up with had significant downsides.

**Multiple functions on the trait, or multiple traits.** One obvious option would be to use multiple functions in the parse trait, or multiple traits:

```rust
// Multiple functions
trait Parser { fn parse(); fn check(); }

// Multiple traits
trait Parser: Checker { fn parse(); }
trait Checker { fn check(); }
```

Both of these approaches mean that defining a new combinator requires writing the same logic twice, once for parse and once for check, but with small variations, which is both annoying and a great opportunity for bugs. It also means that if chumsky ever wanted to define a new mode, they would have to modify every implementation of `Parser` (a breaking change, to boot).

**Mode with a type parameter.** You could try defining a the mode trait with a type parameter, like so...

```rust
trait ModeFor<T> {
    type Output;
    ...
}
```

The `go` function would then look like

```rust
fn go<M: ModeFor<Self::Output>>(&self, inp: &mut InputRef<'a, '_, I, E, S>) -> PResult<M, Self::Output, E>
where
    Self: Sized;
```

In practice, though, this doesn't really work, for a number of reasons. One of them is that the [`Mode`] trait includes methods like [`combine`], which take the output of many parsers, not just one, and combine them together. Good luck writing that constraint with `ModeFor`. But even ignoring that, lacking HRTB, the signature of `go` itself is incomplete. The problem is that, given some impl of `Parser` for some parser type `MyParser`, `MyParser` only knows that `M` is a valid mode for its particular output. But maybe `MyParser` plans to (internally) use some other parser combinators that produce different kinds of results. Will the mode `M` still apply to those? We don't know. We'd have to be able to write a HRTB like `for<O> Mode<O>`, which Rust doesn't support yet:

[`combine`]: https://github.com/zesterer/chumsky/blob/6a82f90ae4c1a4564e024eb0f63121fc7b7d3c18/src/zero_copy/mod.rs#L74-L78

```rust
fn go<M: for<O> Mode<O>>(&self, inp: &mut InputRef<'a, '_, I, E, S>) -> PResult<M, Self::Output, E>
where
    Self: Sized;
```

But even if Rust *did* support it, you can see that the `Mode<T>` trait doesn't capture the user's intent as closely as the [`Mode`] trait from Chumsky did. The [`Mode`] trait was defined independently from all parsers, which is what we wanted. The `Mode<T>` trait is defined relative to some specific parser, and then it falls to the `go` function to say "oh, I want this to be a mode for *all* parsers" using a HRTB.

Using just HRTB (which, again, Rust doesn't have), you could define *another* trait...

```rust
trait Mode: for<O> ModeFor<O> {}

trait ModeFor<O> {}
```

...which would allow us to write `M: Mode` on `go` against, but it's hard to argue this is *simpler* than the original GAT variety. This extra `ModeFor` trait has a "code smell" to it, it's hard to understand why it is there. Whereas before, you implemented the [`Mode`] trait in just the way you think about it, with a single impl that applies to all parsers...

```rust
impl Mode for Check {
    type Output<T> = ();
    ...
}
```

...you now write an impl of `ModeFor`, where one "instance" of the impl applies to only one parser (which has output type `O`). It feels indirect:

```rust
impl<O> ModeFor<O> for Check {
    type Output = ();
    ...
}
```

### How could you model this with RPITIT?

It's also been proposed that we should keep GATs, but only as an implementation detail for things like return position impl Trait in traits (RPITIT) or async functions. This implies that we could model the "many modes" pattern with RPITIT. If you look at the [`Mode`] trait, though, you'll see that this simply doesn't work. Consider the `combine` method, which takes the results from two parsers and combines them to form a new result:

```rust
fn combine<T, U, V, F: FnOnce(T, U) -> V>(
    x: Self::Output<T>,
    y: Self::Output<U>,
    f: F,
) -> Self::Output<V>;
```

How could we write this in terms of a function that returns `impl Trait`?

### Other patterns

In this post, I went through the chumsky pattern in detail. I've not had time to dive quite as deep into other examples, but I've been reading through them and trying to extract out patterns. Here are a few patterns I extracted so far:

* The "generic scopes" pattern ([smithay](https://github.com/rust-lang/rust/pull/96709#issuecomment-1120354039), [playground](https://play.rust-lang.org/?version=nightly&mode=debug&edition=2021&gist=a23b6a846aa1a506c199f7792e1abd3e)):
    * In the Smithay API, if you have some variable `r: R` where `R: Renderer`, you can invoke `r.render(|my_frame| ...)`. This will invoke your callback with some frame `my_frame` that you can then modify. The thing is that the type of `my_frame` depends on the type of renderer that you have; moreover, frames often include thread-local data and so should only be accessible to during that callback.
    * I called this the "generic scopes" pattern because, at least from a types POV, it is kind of a generic version of APIs like [`std::thread::scope`](https://doc.rust-lang.org/std/thread/fn.scope.html). The `scope` function also uses a callback to give limited access to a variable (the "thread scope"), but in the case of `std::thread::scope`, the type of that scope is hard-coded to be [`std::thread::Scope`](https://doc.rust-lang.org/std/thread/struct.Scope.html), whereas here, we want the specific type to depend on the renderer.
    * Thanks to GATs, you can express that pretty cleanly, so that the only bound you need is `R: Renderer`. As with "many modes", if you tried to express it using features today, you can get part of the way there, but the bounds will be complex and involve HRTB.
* The "pointer types" pattern:
    * I didn't dig deep enough into Pythonesque's hypotheticals, but [this comment](https://github.com/rust-lang/rust/pull/96709#issuecomment-1150127168) seemed to be describing a desire to talk about "pointer types" in the abstract, which is definitely a common need; looking at [the comits from Veloren](https://github.com/amethyst/specs/blob/master/src/storage/generic.rs#L114-L150) that pythonesque also cited, this might be a kind of "pointer types" pattern, but I think I might also call it "many modes".
* The "iterable" pattern:
    * In this pattern, you would like a way to say `where C: Iterable`, meaning that `C` is a collection with an `iter` method which fits the signature `fn iter(&self) -> impl Iterator<Item = &T>`. This is distinct from `IntoIterator` because it takes `&self` and thus we can iterate over the same collection many times and concurrently.
    * The most common workaround is to return a `Box<dyn>` (as in [graphene](https://github.com/Emoun/graphene/issues/7)) or a collection ([as in metamolectular](https://github.com/metamolecular/gamma/issues/8)). Neither is zero-cost, which [can be a problem in tight loops, as commented here](https://github.com/rust-lang/rust/pull/96709#issuecomment-1120175346). You can also use HRTB (as [rustc does](https://doc.rust-lang.org/nightly/nightly-rustc/rustc_data_structures/graph/trait.WithSuccessors.html), which is complex and leaky.

### Did I miss something?

Maybe you see a way to express the "many modes" pattern (or one of the other patterns I cited) in Rust today that works well? Let me know by commenting on the thread.

(Since posting this, it occurs to me that one could probably use procedural macros to achieve some similar goals, though I think this approach would also have significant downsides.)
