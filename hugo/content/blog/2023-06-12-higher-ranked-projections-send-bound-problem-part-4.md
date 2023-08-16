---
date: "2023-06-12T00:00:00Z"
slug: higher-ranked-projections-send-bound-problem-part-4
title: Higher-ranked projections (send bound problem, part 4)
---

I recently [posted a draft of an RFC][z] about [Return Type Notation][RTN] to the async working group Zulip stream. In response, Josh Triplett reached out to me to raise some concerns. Talking to him gave rise to a 3rd idea for how to resolve the send bound problem. I still prefer RTN, but I think this idea is interesting and worth elaborating. I call it *higher-ranked projections*.

[z]: https://rust-lang.zulipchat.com/#narrow/stream/187312-wg-async/topic/associated.20return.20types.20draft.20RFC

[RTN]: https://smallcultfollowing.com/babysteps/blog/2023/02/13/return-type-notation-send-bounds-part-2/

## Idea part 1: Define `T::Foo` when `T` has higher-ranked bounds

Consider a trait like this…

```rust
trait Transform<In> {
    type Output;

    fn apply(&self, in: In) -> Self::Output;
}
```

Today, given a trait bound like `T: Transform<Vec<u32>>`, when you write `T::Output`, the compiler expands that to a fully qualified associated type `<T as Transform<Vec<u32>>>::Output`. This took a bit of work — the self type (`T`) of the trait is specified by the user, but the compiler looked at the bounds to select `Vec<u32>` as the value for `In`.

But suppose you have a higher-ranked trait bound like `T: for<‘a> Transform<&’a [u32]>`. Then what should the compiler do for `T::Output`? The compiler would have to  something like `<T as Transform<&’b str>>::Output` where we pick a specific lifetime `’b`. Instead of doing that, the compiler currently gives an error.

But we don’t always *need* to expand `T::Output` to a specific type. If `T::Output` is appearing in a *where-clause*, we could expand it to a random of types. For example, consider this function, which today will not compile:

```rust
fn process<T>()
where
    T: for<‘a> Transform<&’a str>>,
    T::Output: Send, // ERROR: `T::Output` is not allowed
{ /* … */ }
```

We could interpret `T::Output: Send` as a higher-ranked bound, for example:

```rust
fn process<T>()
where
    T: for<‘a> Transform<&’a str>>,
    for<‘a> <T as Transform<&’a str>>::Output: Send, // Desugared?
{ /* … */ }
```

## Idea part 2: Fix the bugs on associated type chains

Right now, if have an iterator that yields other items, the compiler won’t let you write things like `T::Item::Item`…

```rust
fn foo<T: Iterator>
where
    T::Item: Iterator,
    T::Item::Item: Send, // <— ERROR
{ /* … */ }
```

…instead you have to write something horrible like `<<T as Iterator>::Item as Iterator>::Item`. There’s no particularly good reason for this. We should make it work better. One thing that would be useful is if we examined the bounds declared in the trait, so that e.g. if we have a trait like…

```rust
trait Factory {
    type Iterator: Iterator;
}
```

…and a `F: Factory`, then `F::Iterator::Item` should work.

## Idea part 3: Associated type for every method in a trait

As the final step, for every method in a trait, we could add an associated type that binds to the “zero-sized function type” associated with that method. So in the `Iterator` trait…

```rust
trait Iterator {
    type Item;
    fn next(&mut self) -> Option<Self::Item>;
}
```

…there’d be two associated types, `Item` and `next`. Given `T: Iterator`, `T::next` would map to a function type that implements `for<‘a> Fn(&’a mut T) -> Option<T::Item>`.

## Putting it all together

If we put this all together, we can start to put bounds in the return types of async functions. Consider our usual trait:

```rust
trait HealthCheck {
    async fn check(&mut self);
}
```

and then a function like

```rust
fn spawn_health_check<HC>(hc: &mut HC)
where
    HC: HealthCheck,
    HC::check::Output: Send,
{
    /* … */
}
```

what does `HC::check::Output: Send` mean? Note that the `Output` here is the return type of the *function* trait, so it refers to the future that you get when you call the async function.

Regardless, by combining ideas part 1, 2, and 3, `HC::check::Output` can then be expanded to the following:

```rust
fn spawn_health_check<HC>(hc: &mut HC)
where
    HC: HealthCheck,
    // `HC::check::Output: Send` becomes…
    for<‘a> <HC::check as Fn<(&’a mut HC,)>>::Output: Send,
{
    /* … */
}
```

which, if you really like complex where clauses, you could further expand to this to a where-clause like this:

```rust
for<‘a> <
    <HC as HealthCheck>::check 
    as 
    Fn<(&’a mut HC,)>
>::Output: Send
```

## Comparing this approach and RTN

In many ways, this idea is very similar to RTN. Compare this example…

```rust
fn spawn_health_check<HC>(hc: &mut HC)
where
    HC: HealthCheck,
    HC::check::Output: Send,
{
    /* … */
}
```

…to the RTN-based approach…

```rust
fn spawn_health_check<HC>(hc: &mut HC)
where
    HC: HealthCheck,
    HC::check(): Send,
{
    /* … */
}
```

In fact, `()` could be a shorthand for `::Output`.

## Associated type bounds

Another part of RTN, and in fact the only part that we’ve implemented so far, is the ability to put bounds on function returns “inline”:

```rust
fn spawn_health_check<HC>(hc: &mut HC)
where
    HC: HealthCheck<check(): Send>,
    //             ———
{
    /* … */
}
```

We could in principle do the same thing with `::Output` notation:

```rust
fn spawn_health_check<HC>(hc: &mut HC)
where
    HC: HealthCheck<check::Output: Send>,
    //             ———
{
    /* … */
}
```

## Pro: simpler building blocks

What I really like about this idea is that it doesn’t introduce new concepts or notation, but rather refines and extends ones that exist. We already have `T::Output` — all this is doing is making it work in contexts where it didn’t work before, and in a fairly logical way. We already have zero-sized function types representing every method, but now we would have a way to name them.

## Con: Rust has two namespaces, and this is at odds with that 

I said that we can add an associated type for every method in the trait — but what do we do if there is an associated type and a method with the same name? Something like this…

```rust
trait Foo {
    type process;
    fn process(&mut self);
}
```

…that would be weird, but it can certainly happen (in fact, I’ve written proc macros that generate code like this because I was too lazy to transform the name of the associated type). 

We have some options here. We could say that we only add associated types for a method if there isn’t an explicit associated type. We can make this shadowing illegal in Rust 2024 (but not earlier Rust editions). We can only add methods for async functions and RPITIT functions, which are not currently possible, and then forbid shadowing in those cases. 

Still, fundamentally, this approach is of making a method into an associated type is at odds with Rust’s primary two namespaces (types, values), whereas the RTN approach is working *with* those two namespaces.

## Con: omg so verbose; and so. many. colons.

The obvious downside of the `::Output` notation is that it is significantly more verbose to read and write when compared to RTN, and it puts `::` and `:` in close proximity (admittedly an existing problem with Rust syntax). Consider:

```rust
where HC::check(): Send
// vs
where HC::check::Output: Send
```

RTN also works really well in associated type bound position, but `::Output` works less well:

```rust
where HC: HealthCheck<check(): Send>
// vs
where HC: HealthCheck<check::Output: Send>
```

### but…

…although it must be said that, in practice, `check(): Send` isn’t the only thing you have to write. For example, this example only says that the future returned by `check()` is `Send`, but in practice you actually need `HC` to be `Send + ‘static` too. So you would have to write something like…

```rust
HC: HealthCheck<check(): Send> + Send + ‘static
```

…and, of course, many traits in practice have a lot more than one method. Consider something like this trait…

```rust
trait Resource {
    async fn get(&mut self);
    async fn put(&mut self);
}
```

…then you would need to write…

```rust
R: Resource<get(): Send, put(): Send> + Send + ‘static
```

…and that quickly gets tedious. We encountered this in the case studies that we did, which is why the Google folks created a crate that lets you define a trait alias like `SendResource`, so that `R: SendResource` says all the above.

## Con: confusion between `Output`

One interesting point that Yosh raised in our lang team design meeting is that people already have the potential to be confused about whether the `Send` bound applies to the *future returned by the async function* or the *value you get from awaiting the future*; the fact that both `FnOnce` and `Future` have an `Output` associated type could well play into that confusion.

One thing we discussed is how one would place bounds on the *value returned from a future* (versus the future itself). Under the higher-ranked projections proposal described in this blog post, this is fairly clear, you just do `...::Output::Output`:

```rust
where 
    T::method::Output::Output: Send
    //         ------  ------
    //           |       |
    //           |     Describes value produced by future
    //         Describes the future itself.
```

For RTN, there are multiple options. One is to use `::Output`:

```rust
where 
    T::method()::Output: Send,
    //       --  ------
    //       |    |
    //       |  Describes value produced by future
    //       Describes the future itself.
```

Another is to "double down" on the "pseudo-expression" syntax:

```rust
where 
    T::method().await: Send,
    //       -- -----
    //       |    |
    //       |  Describes value produced by future
    //       Describes the future itself.
```

We don't have to settle this today, but it's interesting to think about.

## Pro: Building blocks first?

I’m torn on this point. Lately I’ve been into the idea of “stabilize the building blocks”. For a mature language like Rust, it is important to work piece by piece. Moreover, thanks to custom derive and procedural macros, people can build really powerful abstractions if they have the buildings blocks to work with. And it’s sometimes a lot easier to get consensus around the building blocks than the nice syntax on top[^not_always]. All of this argues to me for the `::Output` approach, which feels to me like more of a general purpose building block.

[^not_always]: Although not always! I think that `-> impl Trait` is a good example of where stabilizing the syntax first, and working through the semantics and core primitives over time, has paid off.

### but…

On the other hand, the `()` syntax is itself a building block. But it’s a building block that’s actually nice enough to use in simple cases. We’ve often been reluctant to add new bits of syntax to Rust, and I think that’s generally good, but sometimes I look with envy at other languages that are willing to take bold steps to build designs that are *aggressively awesome*. I’d like us as a language community to [dare to ask for more][]. It’s hard to argue that the `::Output` syntax is aggressively awesome. The `()` syntax may not be *aggressively* awesome (that's probably [trait transformers][]), but it's at least mildly awesome.

[dare to ask for more]: http://smallcultfollowing.com/babysteps/blog/2022/02/09/dare-to-ask-for-more-rust2024/

[trait transformers]: http://smallcultfollowing.com/babysteps/blog/2023/03/03/trait-transformers-send-bounds-part-3/

## Implementation notes

Right now, the only form of RTN that we have *implemented* is the “associated type bound” notation, e.g., `HealthCheck<check(): Send>`. If we add RTN, I think we should also support use in where clauses (e.g., `HC::check(): Send`) and as a type for local variables (e.g., `let x: HC::check() = hc.check(…)`), persuant to the [“year of everywhere”] philosophy, where we try to make Rust notations as uniformly applicable as possible[^TC]. That said, implementing it in those other places is significantly more complicated in the compiler.

[“year of everywhere”]: http://smallcultfollowing.com/babysteps/blog/2022/09/22/rust-2024-the-year-of-everywhere/

[^TC]: Hat tip to TC for bringing up this slogan in the lang team meeting.

The `::Output` notation, in contrast, doesn’t read especially well as an associated type bound (`HealthCheck<check::Output: Send>` is kind of O_O to me). I think it works better as a standalone where clause like `HC::check::Output: Send`. It’s not clear how quickly we can implement that. It should be possible, imo, but it requires more investigation.

## Conclusion

There isn’t one yet. My sense is that both the `::Output` and the RTN approach would work. The `::Output` approach feels a bit more “primitive”. It can be used with any higher-ranked trait bound, which means it covers slightly more options, although I don't have a compelling example of where you would want it right now. In contrast, RTN feels easier to explain and more accessible to newcomers, and it respects Rust’s “two namespaces” approach. Neither feels like a one-way door: we can start with RTN and then add `::Output` (in which case, `()` is a kind of sugar for `::Output`), and we can start with `::Output` and then add `()` as a sugar for it later.


