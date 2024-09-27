---
layout: post
title: Trait transformers (send bounds, part 3)
date: 2023-03-03 09:39 -0500
series:
- "Send bound problem"
---

I previously introduced [the "send bound" problem][sb], which refers to the need to add a `Send` bound to the future returned by an async function. This post continues my tour over the various solutions that are available. This post covers "Trait Transformers". This proposal arose from a joint conversation with myself, Eric Holk, Yoshua Wuyts, Oli Scherer, and Tyler Mandry. It's a variant of Eric Holk's [inferred async send bounds][iasb] proposal as well as the work that Yosh/Oli have been doing in the [keyword generics][kg] group. Those posts are worth reading as well, lots of good ideas there.[^plan]

[^plan]: I originally planned to have part 3 of this series simply summarize those posts, in fact, but I consider Trait Transformers an evolution of those ideas, and close enough that I'm not sure separate posts are needed.

[kg]: https://blog.rust-lang.org/inside-rust/2023/02/23/keyword-generics-progress-report-feb-2023.html
[iasb]: https://blog.theincredibleholk.org/blog/2023/02/13/inferred-async-send-bounds/
[sb]: {{< baseurl >}}/blog/2023/02/01/async-trait-send-bounds-part-1-intro/

## Core idea: the trait transformer

A *transformer* is a way for a single trait definition to define multiple variants of that trait. For example, where `T: Iterator` means that `T` implements the `Iterator` trait we know and love, `T: async Iterator` means that `T` implements the *async version* of `Iterator`. Similarly, `T: Send Iterator` means that `T` implements the *sendable version* of `Iterator` (we'll define both the "sendable version" and "async version" more precisely, don't worry).

Transformers can be combined, so you can write `T: async Send Iterator` to mean "the async, sendable version". They can also be distributed, so you can write `T: async Send (Iterator + Factory)` to mean the "async, sendable" version of both `Iterator` and `Factory`.

There are 3 proposed transformers:

* async
* const
* any auto trait

The set of transformers is defined by the language and is not user extensible. This could change in the future, as transformers can be seen as a kind of trait alias.

## The async transformer

The async transformer is used to choose whether functions are sync or async. It can only be applied to traits that opt-in by specifying which methods should be made into sync or async. Traits can opt-in either by declaring the async transformer to be mandatory, as follows...

```rust
async trait Fetch {
    async fn fetch(&mut self, url: Url) -> Data;
}
```

...or by making it optional, in which case we call it a "maybe-async" trait...

```rust
#[maybe(async)]
trait Iterator {
    type Item;
    
    #[maybe(async)]
    fn next(&mut self) -> Self::Item;
    
    fn size_hint(&self) -> Option<(usize, usize)>;
}
```

Here, the trait `Iterator` is the same `Iterator` we've always had, but `async Iterator` refers to the "async version" of `Iterator`, which means that it has an async `next` method (but still has a sync method `size_hint`).

(For the time being, maybe-async traits cannot have default methods, which avoids the need to deal with "maybe-async" code. This can change in the future.)

### Trait transformer as macros

You can think of a trait transformer as being like a fancy kind of macro. When you write a maybe-async trait like `Iterator` above, you are effectively defining a *template* from which the compiler can derive a family of traits. You could think of the `#[maybe(async)]` annotation as a macro that derives two related traits, so that...

```rust
#[maybe(async)]
trait Iterator {
    type Item;
    
    #[maybe(async)]
    fn next(&mut self) -> Self::Item;
    
    fn size_hint(&self) -> Option<(usize, usize)>;
}
```

...would effectively expand into two traits, one with a sync `next` method and one with an `async` version...

```rust
trait Iterator { fn next(&mut self ) -> Self::Item; ... }
trait AsyncIterator { async fn next(&mut self) -> Self::Item; ... }
```

...when you have a where-clause like `T: async Iterator`, then, the compiler would be transforming that to `T: AsyncIterator`. In fact, Oli and Yosh implemented a procedural macro crate that does more-or-less *exactly* this.

The idea with trait transformers though is not to literally do expansions like the ones above, but rather to build those mechanisms into the compiler. This makes them more efficient, and also paves the way for us to have code that is generic over whether or not it is async, or expand the list of modifiers. But the "macro view" is useful to have in mind.

### Always async traits

When a trait is declared like `async trait Fetch`, it only defines an async version, and it is an error to request the sync version like `T: Fetch`, you must write `T: async Fetch`.

Defining an async method without being always-async or maybe-async is disallowed:


```rust
trait Fetch {
    async fn fetch(&mut self, url: Url) -> Data; // ERROR
}
```

Forbidding traits of this kind means that traits can move from "always async" to "maybe async" without a breaking change. See the frequently asked questions for more details.

## The const transformer

The const transformer works similarly to `async`. One can write

```rust!
#[maybe(const)]
trait Compute {
    #[maybe(const)]
    fn a(&mut self);
    
    fn b(&mut self);
}
```

and then if you write `T: const Compute` it means that `a` must be a `const fn` but `b` need not be. Similarly one could write `const trait Compute` to indicate that the `const` transformer is mandatory.

## The auto-trait transformer

Auto-traits can be used as a transformer. This is permitted on any (maybe) async trait or on traits that explicitly opt-in by defining `#[maybe(Send)]` variants. The default behavior of `T: Send Foo` for some trait `Foo` is that...

* `T` must be `Send`
* the future returned by any async method in `Foo` must be `Send`
* the value returned by any RPITIT method must be `Send`[^unclear]

[^unclear]: It's unclear if `Send Foo` should always convert [RPITIT] return values to be `Send`, but it *is* clear that we want some way to permit one to write `-> impl Future` in a trait and have that be `Send` iff async methods are `Send`.

[RPITIT]: https://rust-lang.github.io/impl-trait-initiative/RFCs/rpit-in-traits.html

Per these rules, given:

```rust
#[maybe(async)]
trait Iterator {
    type Item;

    #[maybe(async)]
    fn next(&mut self) -> Self::Item;
}
```

writing `T: async Send Iterator` would be equivalent to:

* `T: async Iterator<next(): Send> + Send`

using the [return type notation][rtn].

[rtn]: https://smallcultfollowing.com/babysteps/blog/2023/02/13/return-type-notation-send-bounds-part-2/

The `#[maybe(Send)]` annotation can be applied to associated types or functions...

```rust
#[maybe(Send)]
trait IntoIterator {
    #[maybe(Send)]
    type IntoIter;
    
    type Item;
}
```

...in which case writing `T: Send IntoIterator` would expand to `T: IntoIterator<IntoIter: Send> + Send`.

## Frequently asked questions

### How is this different from eholk's [Inferred Async Send Bounds][iasb]?

Eric's proposal was similar in that it permitted `T: async(Send) Foo` as a similar sort of "macro" to get a bound that included `Send` bounds on the resulting futures. In that proposal, though the "send bounds" were tied to the use of async sugar, which means that you could no longer consider `async fn` to be sugar for a function returning an `-> impl Future`. That seemed like a bad thing, particularly since explicitly `-> impl Future` syntax is the only way to write an async fn that doesn't capture all of its arguments.

### How is this different from the [keyword generics][kg] post?

Yosh and Oli posted a [keyword generics update][kg] that included notation for "maybe async" traits (they wrote `?async`) along with some other things. The ideas in this post are very similar to those, the main difference is treating `Send` as an independent transformer, similar to the previous question.

### Should the auto-trait transformer be specific to each auto-trait, or generic?

As written, the auto-trait transformer is specific to a particular auto-trait, but it might be useful to be able to be generic over multiple (e.g., if you are maybe Send, you likely want to be maybe Send-Sync too, right?). You could imagine writing `#[maybe(auto)]` instead of `#[maybe(Send)]`, but that's kind of confusing, because an "always-auto" trait (i.e., an auto trait like Send) is quite a different thing from a "maybe-auto" trait (i.e., a trait that has a "sendable version"). OTOH users can't define their own auto traits and likely will never be able to. Unclear.

### Why make auto-trait transformer be opt-in?

You can imagine letting `T: Send Foo` mean `T: Foo + Send` for all traits `Foo`, without requiring `Foo` to be declared as `maybe(Send)`. The problem is that this would mean that customizing the `Send` version of a trait for the first time is a semver breaking change, and so must be done at the same time the trait is introduced. This implies that no existing trait in the ecosystem could customize its `Send` version. Seems bad.

### Will you permit `async` methods without the async transformer? Why or why not?

No. The following trait...

```rust
trait Http {
    async fn fetch(&mut self); // ERROR
}
```

...would get an error like "cannot use `async` in a trait unless it is declared as `async` or `#[maybe(async)]`. Ensuring that people write `T: async Http` and not just `T: Http` means that the trait can become "maybe async" later without breaking those clients. It also means that people would have to remember (when writing async code) whether a trait is "maybe async" or "always async" so they know whether to write `T: async Http` (for maybe-async traits) or `T: Http` (for always-async). This way, if the trait has async methods, you write `async`.

### Why did you label methods in a `#[maybe(async)]` trait as `#[maybe(async)]` instead of `async`?

In the examples, I wrote maybe(async) traits like so:

```rust
#[maybe(async)]
trait Iterator {
    type Item;

    #[maybe(async)]
    fn next(&mut self) -> Self::Item;
}
```

Personally, I rather prefer the idea that inside a `#[maybe(async)]` block, you define the trait as it were *always* async...

```rust
#[maybe(async)]
trait Iterator {
    type Item;

    async fn next(&mut self) -> Self::Item;
}
```

...but then the async gets removed when used in a sync context. However, I changed it because I couldn't figure out the right way to permit `#[maybe(Send)]` in this scenario. I can also imagine that it's a bit confusing to write `async fn` when you maybe "maybe async".

### Why use an annotation (`#[..]`) like `#[maybe(async)]` instead of a keyword?

I don't know, because `?async` is hard to read, and we've got enough keywords? I'm open to bikeshedding here.

### Do we still want [return type notation][rtn]?

Yes, [RTN][] is useful for giving more precise specification of which methods should return send-futures (you may not want to require that *all* async methods are send, for example). It's also needed internally by the compiler anyway as the "desugaring target" for the `Send` transformer.

### Can we allow `#[maybe]` on types/functions?

Maybe![^see] That's basically full-on keyword generics. This proposal is meant as a stepping stone. It doesn't permit code or types to be generic whether they are async/send/whatever, but it does permit us to define multiple versions of trait. To the language, it's effectively a kind of *macro*, so that (i.e.) a single trait definition `#[maybe(async)] trait Iterator` effectively defines two traits, `Iterator` and `AsyncIterator`, and the `T: async Iterator` notation is being used to select the second one. (This is only an example, I don't mean that users would literally be able to reference a `AsyncIterator` trait.)

[^see]: See what I did there?

### What order are transformers applied?

Transformers must be written according to this grammar

```
Trait := async? const? Path* Path
```

where `x?` means optional `x`, `x*` means zero or more `x`, and the traits named in `Path*` must be auto-traits. The transformers (if present) are applied in order, so first things are made async, then const, then sendable. (I'm not sure if both async and const make any sense?)

### Can auto-trait transformers let us genearlize over rc/arc?

Yosh at some point suggested that we could think of "send" or "not send" as another application of [keyword generics][kg], and that got me very excited. It's a known problem that people have to define two versions of their structs (see e.g. the [im] and [im-rc] crates). Maybe we could permit something like

```rust
#[maybe(Send)]
struct Shared<T> {
    /* either Rc<T> or Arc<T>, depending */
}
```

and then permit variables of type `Shared<u32>` or `Send Shared<u32>`. The [keywosrd generics][kg] proposals already are exploring the idea of structs whose types vary depending on whether they are async or not, so this fits in.

[im]: https://crates.io/crates/im
[im-rc]: https://crates.io/crates/im-rc

## Conclusion

This post covered "trait transformers" as a possible solution the ["send bounds"][sb] problem. Trait transformers are not exactly an *alternative* to the [return type notation][rtn] proposed earlier; they are more like a complement, in that they make the "easy easy", but effectively provide a convenient desugaring to uses of [return type notation][rtn].

The full set of solutions thus far are...

* [Return type notation (RTN)][rtn]
    * *Example:* `T: Fetch<fetch(): Send>`
    * *Pros:* flexible and expressive
    * *Cons:* verbose
* eholk's [inferred async send bounds][iasb]
    * *Example:* `T: async(Send) Fetch`
    * *Pros:* concise
    * *Cons:* specific to async notation, doesn't support `-> impl Future` functions; requires RTN for completeness
* trait transformers (this post)
    * *Example:* `T: async Send Fetch`
    * *Pros:* concise
    * *Cons:* requires RTN for completeness

