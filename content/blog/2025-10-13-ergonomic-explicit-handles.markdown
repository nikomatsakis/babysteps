---
title: "We need (at least) ergonomic, explicit handles"
date: 2025-10-13T07:39:16-04:00
series:
- "Ergonomic RC"
---

Continuing my discussion on Ergonomic RC, I want to focus on the core question: **should users have to explicitly invoke handle/clone, or not?** This whole "Ergonomic RC" work was originally proposed by [Dioxus][] and their answer is simple: **definitely not**. For the kind of high-level GUI applications they are building, having to call `cx.handle()` to clone a ref-counted value is pure noise. For that matter, for a lot of Rust apps, even cloning a string or a vector is no big deal. On the other hand, for a lot of applications, the answer is **definitely yes** -- knowing where handles are created can impact performance, memory usage, and even correctness (don't worry, I'll give examples later in the post). So how do we reconcile this?

**This blog argues that we should make it ergonomic to be explicit**. This wasn't always my position, but after an impactful conversation with Josh Triplett, I've come around. I think it aligns with what I once called the [soul of Rust][sor]: we want to be ergonomic, yes, but we want to be **ergonomic while giving control**[^axiom]. I also like Tyler Mandry's [*Clarity of purpose*][cop] contruction, *"Great code brings only the important characteristics of your application to your attention"*. The key point is that *there is great code in which cloning and handles are important characteristics*, so we need to make that code possible to express nicely. This is particularly true since Rust is one of the very few languages that really targets that kind of low-level, foundational code. 

[sor]: https://smallcultfollowing.com/babysteps//blog/2022/09/18/dyn-async-traits-part-8-the-soul-of-rust/

[^axiom]: I see a potential candidate for a design axiom... *rubs hands with an evil-sounding cackle and a look of glee*

**This does not mean we cannot (later) support automatic clones and handles.** It's inarguable that this would benefit clarity of purpose for a lot of Rust code. But I think we should focus *first* on the harder case, the case where explicitness is needed, and **get that as nice as we can**; then we can circle back and decide whether to also support something automatic. One of the questions for me, in fact, is whether we can get "fully explicit" to be *nice enough* that we don't really need the automatic version. There are benefits from having "one Rust", where all code follows roughly the same patterns, where those patterns are perfect some of the time, and don't suck too bad[^industry] when they're overkill.    

[cop]: https://tmandry.gitlab.io/blog/posts/the-main-thing/

[^industry]: [It's an industry term](https://youtu.be/JMFS9lrVd64?si=BdaDNm7rIueS0Jlx&t=71).

## "Rust should not surprise you." (hat tip: Josh Triplett)

I mentioned this blog post resulted from a long conversation with Josh Triplett[^actually]. The key phrase that stuck with me from that conversation was: *Rust should not surprise you*. The way I think of it is like this. Every programmer knows what its like to have a marathon debugging session -- to sit and state at code for days and think, *but... how is this even POSSIBLE?* Those kind of bug hunts can end in a few different ways. Occasionally you uncover a deeply satisfying, subtle bug in your logic. More often, you find that you wrote `if foo` and not `if !foo`. And *occasionally* you find out that your language was doing something that you didn't expect. That some simple-looking code concealed a subltle, complex interaction. People often call this kind of a *footgun*.

[^actually]: Actually, by the standards of the conversations Josh and I often have, it was't really all that long -- an hour at most.

Overall, Rust is *remarkably* good at avoiding footguns[^sync]. And part of how we've achieved that is by making sure that things you might need to know are visible -- like, explicit in the source. Every time you see a Rust match, you don't have to ask yourself "what cases might be missing here" -- the compiler guarantees you they are all there. And when you see a call to a Rust function, you don't have to ask yourself if it is fallible -- you'll see a `?` if it is.[^panics]

[^sync]: Well, at least *sync* Rust is. I think async Rust has more than its share, particularly around cancellation, but that's a topic for another blog post.

[^panics]: Modulo panics, of course -- and no surprise that accounting for panics is a major pain point for some Rust users.

### Creating a handle can definitely "surprise" you

So I guess the question is: *would you ever have to know about a ref-count increment*? The trick part is that the answer here is application dependent. For some low-level applications, definitely yes: an atomic reference count is a measurable cost. To be honest, I would wager that the set of applications where this is true are vanishly small. And even in those applications, Rust already improves on the state of the art by giving you the ability to choose between `Rc` and `Arc` *and then proving that you don't mess it up*.

But there are other reasons you might want to track reference counts, and those are less easy to dismiss. One of them is memory leaks. Rust, unlike GC'd languages, has *deterministic destruction*. This is cool, because it means that you can leverage destructors to manage all kinds of resources, as Yehuda wrote about long ago in his classic ode-to-[RAII][] entitled ["Rust means never having to close a socket"][RMNCS]. But although the points where handles are created and destroyed is deterministic, the nature of reference-counting can make it much harder to predict when the underlying resource will actually get freed. And if those increments are not visible in your code, it is that much harder to track them down. Just recently, I was debugging [Symposium](), which is written in Swift. Somehow I had two `IPCManager` instances when I only expected one, and each of them was responding to every IPC message, wreaking havoc. Poking around I found stray references floating around in some surprising places, which was causing the problem. Would this bug have still occurred if I had to write `.handle()` explicitly to increment the ref count? Definitely, yes. Would it have been easier to find after the fact? Also yes.[^tbqh]

[^tbqh]: In this particular case, it was fairly easy for me to find regardless, but this application is very simple. I can definitely imagine ripgrep'ing around a codebase to find all increments being useful, and that would be much harder to do without an explicit signal they are occurring.

[RAII]: https://en.wikipedia.org/wiki/Resource_acquisition_is_initialization
[RNCFS]: https://blog.skylight.io/rust-means-never-having-to-close-a-socket/

Josh gave me a similar example from the "bytes" crate. A `Bytes` type is a handle to a slice of some underlying memory buffer. When you clone that handle, it will keep the entire backing buffer around. Sometimes you might prefer to copy your slice out into a separate buffer so that the underlying buffer can be freed. It's not that hard for me to imagine trying to hunt down an errant handle that is keeping some large buffer alive and being very frustrated that I can't see explicitly in the where those handles are created.

A similar case occurs with APIs like like `Arc::get_mut`[^make_mut]. `get_mut` takes an `&mut Arc<T>` and, if the ref-count is 1, returns an `&mut T`. This lets you take a *shareable* handle that *you* know is not actually *being* shared and recover uniqueness. This kind of API is not frequently used -- but when you need it, it's so nice it's there.

[^make_mut]: Or `Arc::make_mut`, which is one of my favorite APIs. It takes an `Arc<_>` and gives you back mutable (i.e., unique) access to the internals, always! How is that possible, given that the ref count may not be 1? Answer: if the ref-count is not 1, then it clones it. This is perfect for copy-on-write-style code. So beautiful. 😍

## "What I love about Rust is its versatility: low to high in one language" (hat tip: Alex Crichton)

Entering the conversation with Josh, I was leaning towards a design where you had some form of automated cloning of handles and an allow-by-default lint that would let crates which *don't* want that turn it off. But Josh convinced me that there is a significant class of applications that want handle creation to be ergonomic AND visible (i.e., explicit in the source). Low-level network services and even things like Rust For Linux likely fit this description, but any Rust application that uses `get_mut` or `make_mut` might also.

And this reminded me of something Alex Crichton once said to me. Unlike the other quotes here, it wasn't in the context of ergonomic ref-counting, but rather when I was working on my first attempt at the ["Rustacean Principles"][rp]. Alex was saying that he loved how Rust was great for low-level code but also worked well high-level stuff like CLI tools and simple scripts. I feel like you can interpret this quote in two ways, depending on what you choose to emphasize. You could hear it as, "It's important that Rust is good for high-level use cases". That is true, and it is what leads us to ask whether we should even make handles visible at all.

But you can also read Alex's quote as, "It's important that there's one language that works well enough for *both*" -- and I think that's true too. The "true Rust gestalt" is when we manage to *simultaneously* give you the low-level control that grungy code needs but wrapped in a high-level package. This is the promise of zero-cost abstractions, of course, and Rust (in its best moments) delivers.

[rp]: https://smallcultfollowing.com/babysteps/blog/2021/09/08/rustacean-principles/

### The "soul of Rust": low-level enough for a kernel, usable enough for a GUI

Let's be honest. High-level GUI programming is not Rust's bread-and-butter, and it never will be; users will never confuse Rust for TypeScript. But then, TypeScript will never be in the Linux kernel. The goal of Rust is to be a single language that can, by and large, be "good enough" for *both* extremes. **The goal is make enough low-level details visible for kernel hackers but do so in a way that is usable enough for a GUI.** It ain't easy, but it's the job.

This isn't the first time that Josh has pulled me back to this realization. The last time was in the context of async fn in dyn traits, and it led to a blog post talking about the ["soul of Rust"](https://smallcultfollowing.com/babysteps/blog/2022/09/18/dyn-async-traits-part-8-the-soul-of-rust/) and a [followup going into greater detail](https://smallcultfollowing.com/babysteps/blog/2022/09/19/what-i-meant-by-the-soul-of-rust/). I think the catchphrase "low-level enough for a Kernel, usable enough for a GUI" kind of captures it.

### Conclusion: Explicit handles should be the first step, but it doesn't have to be the final step

There is a slight caveat I want to add. I think another part of Rust's soul is *preferring nuance to artificial simplicity* ("as simple as they can be, but no simpler", as they say). And I think the reality is that there's a huge set of applications that make new handles left-and-right (particularly but not exclusively in async land[^oof]) and where explicitly creating new handles is noise, not signal. This is why e.g. Swift[^gobig] makes ref-count increments invisible -- and they get a big lift out of that![^erg] I'd wager most Swift users don't even realize that Swift is not garbage-collected[^doh].

[^oof]: My experience is that, due to language limitations we really should fix, many async constructs force you into `'static` bounds which in turn force you into `Rc` and `Arc` where you'd otherwise have been able to use `&`.

[^gobig]: I've been writing more Swift and digging it. I have to say, I love how they are not afraid to "go big". I admire the ambition I see in designs like SwiftUI and their approach to async. I don't think they bat 100, but it's cool they're swinging for the stands. I want Rust to [dare to ask for more][dtam]!

[^erg]: Well, not *only* that. They also allow class fields to be assigned when aliased which, to avoid stale references and iterator invalidation, means you have to move everything into ref-counted boxes and adopt persistent collections, which in turn comes at a performance cost and makes Swift a harder sell for lower-level foundational systems (though by no means a non-starter, in my opinion).

[^doh]: Though I'd also wager that many eventually find themselves scratching their heads about a ref-count cycle. I've not dug into how Swift handles those, but I see references to "weak handles" flying around, so I assume they've not (yet?) adopted a cycle collector. To be clear, you can get a ref-count cycle in Rust too! It's harder to do since we discourage interior mutability, but not that hard.

But the key thing here is that even if we do add some way to make handle creation automatic, we ALSO want a mode where it is explicit and visible. So we might as well do that one first.

OK, I think I've made this point 3 ways from Sunday now, so I'll stop. The new next few blog posts in the series will dive into (at least) two options for how we might make handle creation and closures more ergonomic while retaining explicitness.

