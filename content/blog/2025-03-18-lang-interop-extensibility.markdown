---
title: "Rust in 2025: Language interop and the extensible compiler"
date: 2025-03-18T15:34:25Z
series:
- "Rust in 2025"
---

For many years, C has effectively been the "lingua franca" of the computing world. It's pretty hard to combine code from two different programming languages in the same process--unless one of them is C. The same could theoretically be true for Rust, but in practice there are a number of obstacles that make that harder than it needs to be. Building out **silky smooth language interop** should be a core goal of helping Rust to target [foundational applications][fa]. I think the right way to do this is not by extending rustc with knowledge of other programming languages but rather by building on Rust's core premise of being an extensible language. By investing in building out an **"extensible compiler"** we can allow crate authors to create a plethora of ergonomic, efficient bridges between Rust and other languages.

[fa]: {{< baseurl >}}/blog/2025/03/10/rust-2025-intro/

## We'll know we've succeeded when...

When it comes to interop...

* It is easy to create a Rust crate that can be invoked from other languages and across multiple environments (desktop, Android, iOS, etc). Rust tooling covers the full story from writing the code to publishing your library.
* It is easy[^asitcanbe] to carve out parts of an existing codebase and replace them with Rust. It is *particularly* easy to integrate Rust into C/C++ codebases.

[^asitcanbe]: Well, as easy as it can be.

When it comes to extensibility...

* Rust is host to wide variety of extensions ranging from custom lints and diagnostics ("clippy as a regular library") to integration and interop (ORMs, languages) to static analysis and automated reasoning^[math].

[^math]: Mathematically prove my unsafe code is safe? Yes please!

## Lang interop: the *least common denominator* use case

In my head, I divide language interop into two core use cases. The first is what I call **Least Common Denominator** (LCD), where people would like to write one piece of code and then use it in a wide variety of environments. This might mean authoring a core SDK that can be invoked from many languages but it also covers writing a codebase that can be used from both Kotlin (Android) and Swift (iOS) or having a single piece of code usable for everything from servers to embedded systems. It might also be creating [WebAssembly components][c] for use in browsers or on edge providers.

[c]: https://bytecodealliance.org/

[uniffi]: https://mozilla.github.io/uniffi-rs/latest/

[diplomat]: https://rust-diplomat.github.io/book/

What distinguishes the LCD use-case is two things. First, it is primarily unidirectional---calls mostly go *from* the other language *to* Rust. Second, you don't have to handle all of Rust. You really want to expose an API that is "simple enough" that it can be expressed reasonably idiomatically from many other languages. Examples of libraries supporting this use case today are [uniffi][] and [diplomat][]. This problem is not new, it's the same basic use case that [WebAssembly components](https://component-model.bytecodealliance.org/) are targeting as well as old school things like [COM](https://en.wikipedia.org/wiki/Component_Object_Model) and [CORBA](https://en.wikipedia.org/wiki/Common_Object_Request_Broker_Architecture) (in my view, though, each of those solutions is a bit too narrow for what we need).

When you dig in, the requirements for LCD get a bit more complicated. You want to start with simple types, yes, but quickly get people asking for the ability to make the generated wrapper from a given language more idiomatic. And you want to focus on calls *into* Rust, but you also need to support callbacks. In fact, to really integrate with other systems, you need generic facilities for things like logs, metrics, and I/O that can be mapped in different ways. For example, in a mobile environment, you don't necessarily want to use tokio to do an outgoing networking request. It is better to use the system libraries since they have special cases to account for the quirks of radio-based communication.

To really crack the LCD problem, you also have to solve a few other problems too:

* It needs to be easy to package up Rust code and upload it into the appropriate package managers for other languages. Think of a tool like [maturin](https://github.com/PyO3/maturin), which lets you bundle up Rust binaries as Python packages.
* For some use cases, **download size** is a very important constraint. Optimizing for size right now is hard to start. What's worse, your binary has to include code from the standard library, since we can't expect to find it on the device---and even if we could, we couldn't be sure it was ABI compatible with the one you built your code with.

## Needed: the "serde" of language interop

Obviously, there's enough here to keep us going for a long time. I think the place to start is building out something akin to the "serde" of language interop: the [serde](https://crates.io/crates/serde) package itself just defines the core trait for serialization and a derive. All of the format-specific details are factored out into other crates defined by a variety of people.

I'd like to see a universal set of conventions for defining the "generic API" that your Rust code follows and then a tool that extracts these conventions and hands them off to a backend to do the actual language specific work. It's not essential, but I think this core dispatching tool should live in the rust-lang org. All the language-specific details, on the other hand, would live in crates.io as crates that can be created by anyone.

## Lang interop: the "deep interop" use case

The second use case is what I call the **deep interop** problem. For this use case, people want to be able to go deep in a particular language. Often this is because their Rust program needs to invoke APIs implemented in that other language, but it can also be that they want to stub out some part of that other program and replace it with Rust. One common example that requires deep interop is embedded developers looking to invoke gnarly C/C++ header files supplied by vendors. Deep interop also arises when you have an older codebase, such as the Rust for Linux project attempting to integrate Rust into their kernel or companies looking to integrate Rust into their existing codebases, most commonly C++ or Java.

Some of the existing deep interop crates focus specifically on the use case of invoking APIs from the other language (e.g., [bindgen][] and [duchess][]) but most wind up supporting bidirectional interaction (e.g., [pyo3][], [npapi-rs][], and [neon][]). One interesting example is [cxx][], which supports bidirectional Rust-C++ interop, but does so in a rather opinionated way, encouraging you to make use of a subset of C++'s features that can be readily mapped (in this way, it's a bit of a hybrid of LCD and deep interop).

[bindgen]: https://github.com/rust-lang/rust-bindgen

[duchess]: https://duchess-rs.github.io/duchess/

[cxx]: https://cxx.rs

[pyo3]: https://pyo3.rs/v0.23.5/

[npapi]: https://napi.rs

[neon]: https://neon-rs.dev

## Interop with all languages is important. C and C++ are just more so.

I want to see smooth interop with all languages, but C and C++ are particularly important. This is because they have historically been the language of choice for foundational applications, and hence there is a lot of code that we need to integrate with. Integration with C today in Rust is, in my view, "ok" -- most of what you need is there, but it's not as nicely integrated into the compiler or as accessible as it should be. Integration with C++ is a huge problem. I'm happy to see the Foundation's [Rust-C++ Interoperability Initiative](https://rustfoundation.org/interop-initiative/) as well a projects like Google's [crubit](https://github.com/google/crubit) and of course the venerable [cxx](https://github.com/dtolnay/cxx).

## Needed: "the extensible compiler"

The traditional way to enable seamless interop with another language is to "bake it in" i.e., Kotlin has very smooth support for invoking Java code and Swift/Zig can natively build C and C++. I would prefer for Rust to take a different path, one I call **the extensible compiler**. The idea is to enable interop via, effectively, supercharged procedural macros that can integrate with the compiler to supply type information, generate shims and glue code, and generally manage the details of making Rust "play nicely" with another language.

In some sense, this is the same thing we do today. All the crates I mentioned above leverage procedural macros and custom derives to do their job. But procedural macrods today are the "simplest thing that could possibly work": tokens in, tokens out. Considering how simplistic they are, they've gotten us remarkably, but they also have distinct limitations. Error messages generated by the compiler are not expressed in terms of the macro input but rather the Rust code that gets generated, which can be really confusing; macros are not able to access type information or communicate information between macro invocations; macros cannot generate code on demand, as it is needed, which means that we spend time compiling code we might not need but also that we cannot integrate with monomorphization. And so forth.

I think we should integrate procedural macros more deeply into the compiler.[^incremental] I'd like macros that can inspect types, that can generate code in response to monomorphization, that can influence diagnostics[^yay] and lints, and maybe even customize things like method dispatch rules. That will allow all people to author crates that provide awesome interop with all those languages, but it will also help people write crates for all kinds of other things. To get a sense for what I'm talking about, check out [F#'s type providers](https://learn.microsoft.com/en-us/dotnet/fsharp/tutorials/type-providers/) and what they can do.

[^yay]: Stuff like the [`diagnostics` tool attribute namespace](https://doc.rust-lang.org/reference/attributes/diagnostics.html#the-diagnostic-tool-attribute-namespace) is super cool! More of this!

The challenge here will be figuring out how to keep the stabilization surface area as small as possible. Whenever possible I would look for ways to have macros communicate by generating ordinary Rust code, perhaps with some small tweaks. Imagine macros that generate things like a "virtual function", that has an ordinary Rust signature but where the body for a particular instance is constructed by a callback into the procedural macro during monomorphization. And what format should that body take? Ideally, it'd just be Rust code, so as to avoid introducing any new surface area.

[^incremental]: Rust's incremental compilation system is pretty well suited to this vision. It works by executing an arbitrary function and then recording what bits of the program state that function looks at. The next time we run the compiler, we can see if those bits of state have changed to avoid re-running the function. The interesting thing is that this function could as well be part of a procedural macro, it doesn't have to be built-in to the compiler.

## Not needed: the Rust Evangelism Task Force

So, it turns out I'm a big fan of Rust. And, I ain't gonna lie, when I see a prominent project pick some other language, at least in a scenario where Rust would've done equally well, it makes me sad. And yet I also know that if *every* project were written in Rust, that would be **so sad**. I mean, who would we steal good ideas from?

I really like the idea of focusing our attention on *making Rust work well with other languages*, not on convincing people Rust is better [^rustvsgo]. The easier it is to add Rust to a project, the more people will try it -- and if Rust is truly a better fit for them, they'll use it more and more.

[^rustvsgo]: I've always been fond of this article [Rust vs Go, "Why they're better together"](https://thenewstack.io/rust-vs-go-why-theyre-better-together/).

## Conclusion: next steps

This post pitched out a north star where

* a single Rust library can be easily used across many languages and environments;
* Rust code can easily call and be called by functions in other languages;
* this is all implemented atop a rich procedural macro mechanism that lets plugins inspect type information, generate code on demand, and so forth.

How do we get there? I think there's some concrete next steps:

* Build out, adopt, or extend an easy system for producing "least common denominator" components that can be embedded in many contexts.
* Support the C++ interop initiatives at the Foundation and elsewhere. The wheels are turning: tmandry is the point-of-contact for [project goal](https://rust-lang.github.io/rust-project-goals/2025h1/seamless-rust-cpp.html) for that, and we recently held our [first lang-team design meeting on the topic](https://hackmd.io/@rust-lang-team/rJvv36hq1e) (this document is a great read, highly recommended!).
* Look for ways to extend proc macro capabilities and explore what it would take to invoke them from other phases of the compiler besides just the very beginning.
	* An aside: I also think we should extend rustc to support compiling proc macros to web-assembly and use that by default. That would allow for strong sandboxing and deterministic execution and also easier caching to support faster build times.