---
layout: post
title: 'Dyn async traits, part 8: the soul of Rust'
date: 2022-09-18 13:49 -0400
---

In the last few months, Tyler Mandry and I have been circulating a [“User’s Guide from the Future”][UMF] that describes our current proposed design for async functions in traits. In this blog post, I want to deep dive on one aspect of that proposal: how to handle dynamic dispatch. My goal here is to explore the space a bit and also to address one particularly tricky topic: how explicit do we have to be about the possibility of allocation? This is a tricky topic, and one that gets at that core question: what is the soul of Rust?

[UMF]: https://hackmd.io/@nikomatsakis/SJ2-az7sc

### The running example trait

Throughout this blog post, I am going to focus exclusively on this example trait, `AsyncIterator`:

```rust
trait AsyncIterator {
    type Item;
    async fn next(&mut self) -> Option<Self::Item>;
}
```

And we’re particularly focused on the scenario where we are invoking `next` via dynamic dispatch:

```rust
fn make_dyn<AI: AsyncIterator>(ai: AI) {
    use_dyn(&mut ai); // <— coercion from `&mut AI` to `&mut dyn AsyncIterator`
}

fn use_dyn(di: &mut dyn AsyncIterator) {
    di.next().await; // <— this call right here!
}
```

Even though I’m focusing the blog post on this particular snippet of code, everything I’m talking about is applicable to any trait with methods that return `impl Trait` (async functions themselves being a shorthand for a function that returns `impl Future`).

The basic challenge that we have to face is this:

* The caller function, `use_dyn`, doesn’t know what impl is behind the `dyn`, so it needs to allocate a fixed amount of space that works for everybody. It also needs some kind of vtable so it knows what `poll` method to call.
* The callee, `AI::next`, needs to be able to package up the future for its `next` function in some way to fit the caller’s expectations.

The [first blog post in this series][part1][^2020] explains the problem in more detail.

[part1]: https://smallcultfollowing.com/babysteps/blog/2021/09/30/dyn-async-traits-part-1/

[^2020]: Written in Sep 2020, egads!

### A brief tour through the options

One of the challenges here is that there are many, many ways to make this work, and none of them is “obviously best”. What follows is, I think, an exhaustive list of the various ways one might handle the situation. If anybody has an idea that doesn’t fit into this list, I’d love to hear it.

**Box it.** The most obvious strategy is to have the callee box the future type, effectively returning a `Box<dyn Future>`, and have the caller invoke the `poll` method via virtual dispatch. This is what the [`async-trait`] crate does (although it also boxes for static dispatch, which we don’t have to do).

[`async-trait`]: https://crates.io/crates/async-trait

**Box it with some custom allocator.** You might want to box the future with a custom allocator.

**Box it and cache box in the caller.** For most applications, boxing itself is not a performance problem, unless it occurs repeatedly in a tight loop. Mathias Einwag pointed out if you have some code that is repeatedly calling `next` on the same object, you could have that caller cache the box in between calls, and have the callee reuse it. This way you only have to actually allocate once.

**Inline it into the iterator.** Another option is to store all the state needed by the function in the `AsyncIter` type itself. This is actually what the existing `Stream` trait does, if you think about it: instead of returning a future, it offers a `poll_next` method, so that the implementor of `Stream` effectively *is* the future, and the caller doesn’t have to store any state. Tyler and I worked out a more general way to do inlining that doesn’t require user intervention, where you basically wrap the `AsyncIterator` type in another type `W` that has a field big enough to store the `next` future. When you call `next`, this wrapper `W` stores the future into that field and then returns a pointer to the field, so that the caller only has to poll that pointer. **One problem with inlining things into the iterator is that it only works well for `&mut self` methods**, since in that case there can be at most one active future at a time. With `&self` methods, you could have any number of active futures.

**Box it and cache box in the callee.** Instead of inlining the entire future into the `AsyncIterator` type, you could inline just one pointer-word slot, so that you can cache and reuse the `Box` that `next` returns. The upside of this strategy is that the cached box moves with the iterator and can potentially be reused across callers. The downside is that once the caller has finished, the cached box lives on until the object itself is destroyed.

**Have caller allocate maximal space.** Another strategy is to have the caller allocate a big chunk of space on the stack, one that should be big enough for every callee. If you know the callees your code will have to handle, and the futures for those callees are close enough in size, this strategy works well. Eric Holk recently released the [stackfuture crate] that can help automate it. **One problem with this strategy is that the caller has to know the size of all its callees.**

[stackfuture]: https://github.com/microsoft/stackfuture

**Have caller allocate some space, and fall back to boxing for large callees.** If you don’t know the sizes of all your callees, or those sizes have a wide distribution, another strategy might be to have the caller allocate some amount of stack space (say, 128 bytes) and then have the callee invoke `Box` if that space is not enough.

**Alloca on the caller side.** You might think you can store the size of the future to be returned in the vtable and then have the caller “alloca” that space — i.e., bump the stack pointer by some dynamic amount. Interestingly, this doesn’t work with Rust’s async model. Async tasks require that the size of the stack frame is known up front. 

**Side stack.** Similar to the previous suggestion, you could imagine having the async runtimes provide some kind of “dynamic side stack” for each task.[^ada] We could then allocate the right amount of space on this stack. This is probably the most efficient option, but it assumes that the runtime is able to provide a dynamic stack. Runtimes like [embassy] wouldn’t be able to do this. Moreover, we don’t have any sort of protocol for this sort of thing right now. Introducing a side-stack also starts to “eat away” at some of the appeal of Rust’s async model, which is [designed to allocate the “perfect size stack” up front][ss] and avoid the need to allocate a “big stack per task”.[^heap]

[ss]: https://without.boats/blog/futures-and-segmented-stacks/

[embassy]: https://github.com/embassy-rs/embassy

[^heap]: Of course, without a side stack, we are left using mechanisms like `Box::new` to cover cases like dynamic dispatch or recursive functions. This becomes a kind of pessimistically sized segmented stack, where we allocate for each little piece of extra state that we need. A side stack might be an appealing middle ground, but because of cases like `embassy`, it can’t be the only option.

[^ada]: I was intrigued to learn that this is what Ada does, and that Ada features like returning dynamically sized types are built on this model. I’m not sure how [SPARK] and other Ada subsets that target embedded spaces manage that, I’d like to learn more about it.

[SPARK]: https://www.adacore.com/about-spark

### Can async functions used with dyn be “normal”?

One of my initial goals for async functions in traits was that they should feel “as natural as possible”. In particular, I wanted you to be able to use them with dynamic dispatch in just the same way as you would a synchronous function. In other words, I wanted this code to compile, and I would want it to work even if `use_dyn` were put into another crate (and therefore were compiled with no idea of who is calling it):

```rust
fn make_dyn<AI: AsyncIterator>(ai: AI) {
    use_dyn(&mut ai);
}

fn use_dyn(di: &mut dyn AsyncIterator) {
    di.next().await;
}
```

My hope was that we could make this code work *just as it is* by selecting some kind of default strategy that works most of the time, and then provide ways for you to pick other strategies for those code where the default strategy is not a good fit. The problem though is that there is no single default strategy that seems “obvious and right almost all of the time”…

| Strategy | Downside |
| --- | --- |
| Box it (with default allocator) | requires allocation, not especially efficient |
| Box it with cache on caller side | requires allocation |
| Inline it into the iterator | adds space to `AI`, doesn’t work for `&self` |
| Box it with cache on callee side | requires allocation, adds space to `AI`, doesn’t work for `&self` |
| Allocate maximal space | can’t necessarily use that across crates, requires extensive interprocedural analysis |
| Allocate some space, fallback | uses allocator, requires extensive interprocedural analysis or else random guesswork |
| Alloca on the caller side | incompatible with async Rust |
| Side-stack | requires cooperation from runtime and allocation |

### The soul of Rust

This is where we get to the “soul of Rust”. Looking at the above table, the strategy that seems the closest to “obviously correct” is “box it”. It works fine with separate compilation, fits great with Rust’s async model, and it matches what people are doing today in practice. I’ve spoken with a fair number of people who use async Rust in production, and virtually all of them agreed that “box by default, but let me control it” would work great in practice.

And yet, when we floated the idea of using this as the default, Josh Triplett objected strenuously, and I think for good reason. Josh’s core concern was that this would be crossing a line for Rust. Until now, there is no way to allocate heap memory without some kind of explicit operation (though that operation could be a function call). But if we wanted make “box it” the default strategy, then you’d be able to write “innocent looking” Rust code that nonetheless *is* invoking `Box::new`. In particular, it would be invoking `Box::new` each time that `next` is called, to box up the future. But that is very unclear from reading over `make_dyn` and `use_dyn`.

As an example of where this might matter, it might be that you are writing some sensitive systems code where allocation is something you always do with great care. It doesn’t mean the code is no-std, it may have access to an allocator, but you still would like to know exactly where you will be doing allocations. Today, you can audit the code by hand, scanning for “obvious” allocation points like `Box::new` or `vec![]`. Under this proposal, while it would still be *possible*, the presence of an allocation in the code is much less obvious. The allocation is “injected” as part of the vtable construction process. To figure out that this will happen, you have to know Rust’s rules quite well, and you also have to know the signature of the callee (because in this case, the vtable is built as part of an implicit coercion). In short, scanning for allocation went from being relatively obvious to requiring a PhD in Rustology. Hmm.

On the other hand, if scanning for allocations is what is important, we could address that in many ways. We could add an “allow by default” lint to flag the points where the “default vtable” is constructed, and you could enable it in your project. This way the compiler would warn you about the possible future allocation. In fact, even today, scanning for allocations is actually much harder than I made it ought to be: you can easily see if your function allocates, but you can’t easily see what its callees do. You have to read deeply into all of your dependencies and, if there are function pointers or `dyn Trait` values, figure out what code is potentially being called. With compiler/language support, we could make that whole process much more first-class and better.

In a way, though, the technical arguments are besides the point. “Rust makes allocations explicit” is widely seen as a key attribute of Rust’s design. In making this change, we would be tweaking that rule to be something like ”Rust makes allocations explicit *most of the time*”. This would be harder for users to understand, and it would introduce doubt as whether Rust *really* intends to be the kind of language that can replace C and C++[^coro].

[^coro]: Ironically, C++ itself inserts implicit heap allocations to help with coroutines!

### Looking to the Rustacean design principles for guidance

Some time back, Josh and I drew up a draft set of design principles for Rust. It’s interesting to look back on them and see what they have to say about this question:

* ⚙️ Reliable: "if it compiles, it works"
* 🐎 Performant: "idiomatic code runs efficiently"
* 🥰 Supportive: "the language, tools, and community are here to help"
* 🧩 Productive: "a little effort does a lot of work"
* 🔧 Transparent: "you can predict and control low-level details"
* 🤸 Versatile: "you can do anything with Rust"

Boxing by default, to my mind, scores as follows:

* **🐎 Performant: meh.** The real goal with performant is that the cleanest code also runs the *fastest*. Boxing on every dynamic call doesn’t meet this goal, but something like “boxing with caller-side caching” or “have caller allocate space and fall back to boxing” very well might.
* **🧩 Productive: yes!** Virtually every production user of async Rust that I’ve talked to has agreed that having code box by default would (but giving the option to do something else for tight loops) would be a great sweet spot for Rust.
* **🔧 Transparent: no.** As I wrote before, understanding when a call may box now requires a PhD in Rustology, so this definitely fails on transparency.

(The other principles are not affected in any notable way, I don't think.)

### What the “user’s guide from the future” suggests

These considerations led Tyler and I to a different design. In the [“User’s Guide From the Future”][UMF] document from before, you’ll see that it does not accept the running example just as is. Instead, if you were to compile the example code we’ve been using thus far, you’d get an error:


```
error[E0277]: the type `AI` cannot be converted to a
              `dyn AsyncIterator` without an adapter
 --> src/lib.rs:3:23
  |
3 |     use_dyn(&mut ai);
  |                  ^^ adapter required to convert to `dyn AsyncIterator`
  |
  = help: consider introducing the `Boxing` adapter,
    which will box the futures returned by each async fn
3 |     use_dyn(&mut Boxing::new(ai));
                     ++++++++++++  +
```


As the error suggests, in order to get the boxing behavior, you have to opt-in via a type that we called `Boxing`[^bikeshed]:

[^bikeshed]: Suggestions for a better name very welcome.

```rust
fn make_dyn<AI: AsyncIterator>(ai: AI) {
    use_dyn(&mut Boxing::new(ai));
    //          ^^^^^^^^^^^
}

fn use_dyn(di: &mut dyn AsyncIterator) {
    di.next().await;
}
```

Under this design, you can only create a `&mut dyn AsyncIterator` when the caller can verify that the `next` method returns a type from which a `dyn*` can be constructed. If that’s not the case, and it’s usually not, you can use the `Boxing::new` adapter to create a `Boxing<AI>`. Via some kind of compiler magic that *ahem* we haven’t fully worked out yet[^pay-no-attention], you could coerce a `Boxing<AI>` into a `dyn AsyncIterator`.

[^pay-no-attention]: Pay no attention to the compiler author behind the curtain. 🪄 🌈 Avert your eyes!

**The details of the `Boxing` type need more work[^UMFchange], but the basic idea remains the same: require users to make *some* explicit opt-in to the default vtable strategy, which may indeed perform allocation.**

[^UMFchange]: e.g., if you look closely at the [User's Guide from the Future][UMF], you'll see that it writes `Boxing::new(&mut ai)`, and not `&mut Boxing::new(ai)`. I go back and forth on this one.

### How does `Boxing` rank on the design principles?

To my mind, adding the `Boxing` adapter ranks as follows…

* **🐎 Performant: meh.** This is roughly the same as before. We’ll come back to this.
* **🥰 Supportive: yes!** The error message guides you to exactly what you need to do, and hopefully links to a well-written explanation that can help you learn about why this is required.
* **🧩 Productive: meh.** Having to add `Boxing::new` call each time you create a `dyn AsyncIterator` is not great, but also on-par with other Rust papercuts.
* **🔧 Transparent: yes!** It is easy to see that boxing may occur in the future now.

This design is now transparent. It’s also less productive than before, but we’ve tried to make up for it with supportiveness. “Rust isn’t always easy, but it’s always helpful.”

### Improving performance with a more complex ABI

One thing that bugs me about the “box by default” strategy is that the performance is only “meh”. I like stories like `Iterator`, where you write nice code and you get tight loops. It bothers me that writing “nice” async code yields a naive, middling efficiency story.

That said, I think this is something we could fix in the future, and I think we could fix it backwards compatibly. The idea would be to extend our ABI when doing virtual calls so that the caller has the *option* to provide some “scratch space” for the callee. For example, we could then do things like analyze the binary to get a good guess as to how much stack space is needed (either by doing dataflow or just by looking at all implementations of `AsyncIterator`). We could then have the caller reserve stack space for the future and pass a pointer into the callee — the callee would still have the *option* of allocating, if for example, there wasn’t enough stack space, but it could make use of the space in the common case.

Interestingly, I think that if we did this, we would also be putting some pressure on Rust’s “transparency” story again. While Rust’s leans heavily on optimizations to get performance, we’ve generally restricted ourselves to simple, local ones like inlining; we don’t require interprocedural dataflow in particular, although of course it helps (and LLVM does it). But getting a good estimate of how much stack space to reserve for potential calleees would violate that rule (we’d also need some simple escape analysis, as I describe in [Appendix A]). All of this adds up to a bit of ‘performance unpredictability’. Still, I don’t see this as a big problem, particularly since the fallback is just to use `Box::new`, and as we’ve said, for most users that is perfectly adequate.

### Picking another strategy, such as inlining

Of course, maybe you don’t want to use `Boxing`. It would also be possible to construct other kinds of adapters, and they would work in a similar fashion. For example, an inlining adapter might look like:

```rust
fn make_dyn<AI: AsyncIterator>(ai: AI) {
    use_dyn(&mut InlineAsyncIterator::new(ai));
    //           ^^^^^^^^^^^^^^^^^^^^^^^^
}
```

The `InlineAsyncIterator<AI>` type would add the extra space to store the future, so that when the `next` method is called, it writes the future into its own fields and then returns it to the caller. Similarly, a cached box adapter might be `&mut CachedAsyncIterator::new(ai)`, only it would use a field to cache the resulting `Box`.

You may have noticed that the inline/cached adapters include the name of the trait. That’s because they aren’t relying on compiler magic like Boxing, but are instead intended to be authored by end-users, and we don’t yet have a way to be generic over any trait definition. (The proposal as we wrote it uses macros to generate an adapter type for any trait you wish to adapt.) This is something I’d love to address in the future. [You can read more about how adapters work here.][iai]

[iai]: https://rust-lang.github.io/async-fundamentals-initiative/explainer/inline_async_iter_adapter.html

### Conclusion

OK, so let’s put it all together into a coherent design proposal:

* You cannot coerce from an arbitrary type `AI` into a `dyn AsyncIterator`. Instead, you must select an adaptor:
	* Typically you want `Boxing`, which has a decent performance profile and “just works”.
	* But users can write their own adapters to implement other strategies, such as `InlineAsyncIterator` or `CachingAsyncIterator`.
* From an implementation perspective:
	* When invoked via dynamic dispatch, async functions return a `dyn* Future`. The caller can invoke `poll` via virtual dispatch and invoke the (virtual) drop function when it’s ready to dispose of the future.
	* The vtable created for `Boxing<AI>` will allocate a box to store the future `AI::next()` and use that to create the `dyn* Future`.
	* The vtable for other adapters can use whatever strategy they want. `InlineAsyncIterator<AI>`, for example, stores the `AI::next()` future into a field in the wrapper, takes a raw pointer to that field, and creates a `dyn* Future` from this raw pointer.
* As a backwards compatible improvement for better performance:[^tmandry]
	* We modify the ABI for async trait functions (or any trait function using return-position impl trait) to allow the caller to optionally provide stack space. The `Boxing` adapter, if such stack space is available, will use it to avoid boxing when it can. This would have to be coupled with some compiler analysis to figure out how much to stack space to pre-allocate.

[^tmandry]: I should clarify that, while Tyler and I have discussed this, I don't know how he feels about it. I wouldn't call it 'part of the proposal' exactly, more like an extension I am interested in.

This lets us express virtually any pattern. Its even *possible* to express side-stacks, if the runtime provides a suitable adapter (e.g., `TokioSideStackAdapter::new(ai)`), though if side-stacks become popular I would rather consider a more standard means to expose them.

The main downsides to this proposal are:

* Users have to write `Boxing::new`, which is a productivity and learnability hit, but it avoids a big hit to transparency. Is that the right call? I’m still not entirely sure, though my heart increasingly says yes. It’s also something we could revisit in the future (e.g., and add a default adapter).
* If we opt to modify the ABI, we’re adding some complexity there, but in exchange for potentially quite a lot of performance. I would expect us not to do this initially, but to explore it as an extension in the future once we have more data about how important it is. 

There is one pattern that we can’t express: “have caller allocate maximal space”. This pattern *guarantees* that heap allocation is not needed; the best we can do is a heuristic that *tries* to avoid heap allocation, since we have to consider public functions on crate boundaries and the like. To offer a guarantee, the argument type needs to change from `&mut dyn AsyncIterator` (which accepts any async iterator) to something narrower. This would also support futures that escape the stack frame (see [Appendix A] below). It seems likely that these details don’t matter, and that either inline futures or heuristics would suffice, but if not, a crate like [stackfuture] remains an option.

[Appendix A]: #Appendix-A-futures-that-escape-the-stack-frame

### Comments?

Please leave comments in [this internals thread](https://internals.rust-lang.org/t/blog-series-dyn-async-in-traits-continues/17403). Thanks!

### Appendix A: futures that escape the stack frame

In all of this discussion, I’ve been assuming that the async call was followed closely by an await. But what happens if the future is not awaited, but instead is moved into the heap or other locations?

```rust
fn foo(x: &mut dyn AsyncIterator<Item = u32>) -> impl Future<Output = Option<u32>> + ‘_ {
    x.next()
}
```

For boxing, this kind of code doesn’t pose any problem at all. But if we had allocated space on the stack to store the future, examples like this would be a problem. So long as the scratch space is optional, with a fallback to boxing, this is no problem. We can do an escape analysis and avoid the use of scratch space for examples like this.

### Footnotes