---
layout: post
title: 'Dare to ask for more #rust2024'
date: 2022-02-09T14:52:00-0500
---

Last year, we shipped [Rust 2021] and I have found the changes to be a real improvement in usability. Even though the actual changes themselves were quite modest, the combination of [precise capture closure] and [simpler formatting strings] (`println!("{x:?}")` instead of `println!("{:?}", x)`) is making a real difference in my "day to day" life.[^coding] Just like [NLL] and the [new module system] from [Rust 2018], I've quickly adapted to these new conventions. When I go back to older code, with its clunky borrow checker workarounds and format strings, I die a little inside.[^die]

[Rust 2021]: https://blog.rust-lang.org/2021/10/21/Rust-1.56.0.html
[Rust 2018]: https://doc.rust-lang.org/edition-guide/rust-2018/index.html
[NLL]: http://blog.pnkfx.org/blog/2019/06/26/breaking-news-non-lexical-lifetimes-arrives-for-everyone/
[new module system]: https://doc.rust-lang.org/nightly/edition-guide/rust-2018/path-changes.html
[precise capture closure]: https://doc.rust-lang.org/edition-guide/rust-2021/disjoint-capture-in-closures.html
[simpler formatting strings]: https://doc.rust-lang.org/edition-guide/rust-2021/panic-macro-consistency.html

As we enter 2022, I am finding my thoughts turning more and more to the next Rust edition. What do I want from Rust, and the Rust community, over the next few years? To me, the theme that keeps coming to mind is **dare to ask for more**. Rust has gotten quite a bit nicer to use over the last few years, but I am not satisfied. I believe that there is room for Rust to be 22x more productive[^precisely] and easy to use than it is today, and I think we can do it without meaningfully sacrificing [reliability], [performance], or [versatility]. 

[reliability]: https://rustacean-principles.netlify.app/how_rust_empowers/reliable.html
[performance]: https://rustacean-principles.netlify.app/how_rust_empowers/performant.html
[versatility]: https://rustacean-principles.netlify.app/how_rust_empowers/versatile.html

## Daring to ask for a more ergonomic, expressive Rust

As Rust usage continues to grow, I have been able to talk to quite a number of Rust users with a wide variety of backgrounds and experience. One of the themes I like to ask about is their experience of learning Rust. In many ways, the story here is much better than I had anticipated. Most people are able to learn Rust and feel productive in 3-6 months. Moreover, once they get used to it, most people seem to really enjoy it, and they talk about how learning ownership rules influences the code they write in other languages too (for the better). They also talk about experiencing far fewer bugs in Rust than in other languages -- this is true for C++[^cppbugs], but it's also true for things written in Java or other languages[^concurrency].

[^cppbugs]: I talked to a team that developed some low-level Rust code (what would've been writte in C++) and they reported experienced **one** crash in 3+ years, which originated in an FFI to a C library. That's just amazing.

[^concurrency]: Most commonly, if Rust has an edge of a language like Java, it is because of our stronger concurrency guarantees. But it's not only that. It's also that meeting the required performance bar in other languages often requires one to write code that is "rather clever". Rust's higher performance means that one can write simpler code instead, which then has correspondingly fewer bugs.

That said, it's also quite clear that using Rust has a significant [cognitive overhead]. Few Rust users feel like true experts[^survey]. There are a few topics -- "where clauses", "lifetimes" -- that people mention over and over as being confusing. The more I talk to people, the more I get the sense that the problem isn't any *one* thing, it's *all* the things. It's having to juggle a lot of concerns all at once, and having to get everything lined up before one can even see your code run.

[cognitive overhead]: https://blog.thegovlab.org/post/a-new-vocabulary-for-the-21st-century-cognitive-overhead

[^survey]: The survey consistenly has a peak of around 7 out of 10 in terms of how people self-identify their expertise.

These interviews really validate the work we did on the [ergonomics initiative] and also in Rust 2021. One person I spoke to said the following:

[ergonomics initiative]: https://blog.rust-lang.org/2017/03/02/lang-ergonomics.html

> Looking backwards, NLL and match ergonomics were major improvements in getting people to learn Rust. A lot of people suddenly found stuff way easier. NLL made a lot of things with regard to mutability much simpler. One remaining thing coming up is disjoint capture of fields in closures. That’s another example where people just didn’t understand, "why is this compiler yelling at me? This should work?"

As happy as I am with those results, I don't think we're done. I would like to see progress in two different dimensions:

**Fundamental simplifications:** These are changes like NLL or disjoint-closure-capture that just change the game in terms of what the compiler can accept. Even though these kinds of changes often make the analysis more complex, they ultimately make the language *feel* simpler: more of the programs that *should* work actually *do* work. Simplifications like this tend not to be particularly controversial, but they are difficult to design and implement. Often they require an edition because of small changes to language semantics in various edge cases.

One of the simplest improvements here would be landing polonius, which would fix [#47680](https://github.com/rust-lang/rust/issues/47680), a pattern that I see happening with some regularity. I think that there are also language extensions, like [scoped contexts], some kind of [view types](https://smallcultfollowing.com/babysteps//blog/2021/11/05/view-types/), specialization, or some way to manage self-referential structs, that could fit in this category. That's a bit trickier. The language grows, which is not a simplification, but it can make common patterns so much simpler than it's a net win.

**Sanding rough edges.** These are changes that just make writing Rust code *easier*. There are fewer "i's to dot" or "t's to cross". Good examples are lifetime elision. You know you are hitting a rough edge when you find yourself blindly following compiler suggestions, or randomly adding an `&` or a `*` here or there to see if it will make the compiler happy. 

While sanding rough edges can benefit everyone, the impact is largest for newcomers. Experienced folks have a bit of "survival bias". They tend to know the tricks and apply them automatically. Newcomers don't have that benefit and can waste quite a lot of time (or just give up entirely) trying to fix some simple compilation errors.

[Match ergonomics] was a recent change in this category: while I believe it was an improvement, it also gave rise to a number of rough edges, particularly around references to copy types (see [#44619] for more discussion). I'd like to see us fix those, and also fix "rough edges" in other areas, like [implied bounds].

[#44619]: https://github.com/rust-lang/rust/issues/44619
[scoped contexts]: https://tmandry.gitlab.io/blog/posts/2021-12-21-context-capabilities/
[view types]: https://smallcultfollowing.com/babysteps//blog/2021/11/05/view-types/
[match ergonomics]: https://rust-lang.github.io/rfcs/2005-match-ergonomics.html
[implied bounds]: https://rust-lang.github.io/rfcs/2089-implied-bounds.html

## Daring to ask for a more ergonomic, expressive *async* Rust

Going along with the previous bullet, I think we still have quite a bit of work to do before using Async Rust feels natural. Tyler Mandry and I recently wrote a post on the "Inside Rust" blog, [Async Rust in 2022], that sketched both the way we want async Rust to feel ("just add async") and the plan to get there. 

It seems clear that highly concurrent applications are a key area where Rust shines, so it makes sense for us to continue investing heavily in this area. What's more, those investments benefit more than just async Rust users. Many of them are fundamental extensions to Rust, like [generic associated types][][^Jack] or [type alias impl trait][][^oli], which ultimately benefit everyone.

[^Jack]: Shout out to Jack Huey, tirelessly driving that work forward!

[^oli]: Shout out to Oliver Scherer, tirelessly driving *that* work forward!

[generic associated types]: https://blog.rust-lang.org/2021/08/03/GATs-stabilization-push.html
[type alias impl trait]: https://rust-lang.github.io/impl-trait-initiative/explainer/tait.html

[Async Rust in 2022]: https://blog.rust-lang.org/inside-rust/2022/02/03/async-in-2022.html

Having a truly great async Rust experience, however, is going to require more than language extensions. It's also going to require better tooling, like [tokio console], and more efforts at standardization, like the [portability and interoperability effort](https://www.ncameron.org/blog/portable-and-interoperable-async-rust/) led by nrc.

[tokio console]: https://tokio.rs/blog/2021-12-announcing-tokio-console

## Daring to ask for a more ergonomic, expressive *unsafe* Rust

Strange as it sounds, part of what makes Rust as *safe* as it is is the fact that Rust supports *unsafe* code. Unsafe code allows Rust programmers to gain access access to the full range of machine capabilities, which is what allows Rust to be [versatile]. Rust programmers can then use ownership/borrowing to encapsulate those raw capabilities in a safe interface, so that clients of that library can [rely][reliability] on things working correctly.

There are some flies in the unsafe ointment, though. The reality is that writing *correct* unsafe Rust code can be quite difficult.[^toohard] In fact, because we've never truly defined the set of rules that unsafe code authors have to follow, you could even say it is *literally* impossible, since there is no way to know if you are doing it correctly if nobody has defined what correct *is*.

[^toohard]: Armin wrote a recent article, [Unsafe Rust is Too Hard], that gives some real-life examples of the kinds of challenges you can encounter.

[Unsafe Rust is Too Hard]: https://lucumr.pocoo.org/2022/1/30/unsafe-rust/

To be clear, we do have a lot of promising work here! [Stacked borrows](https://plv.mpi-sws.org/rustbelt/stacked-borrows/), for example, looks to be awfully close to a viable approach for the aliasing rules. The rules are implemented in [miri] and a lot of folks are [using that](https://pramode.in/2020/11/08/miri-detect-ub-rust/) to check their unsafe code. Finally, the [unsafe code guidelines](https://rust-lang.github.io/unsafe-code-guidelines/) effort made good progress on documenting layout guarantees and other aspects of unsafe code, though that work was never RFC'd or made normative. (The issues on that repo also contain a lot of great discussion.)

[miri]: https://github.com/rust-lang/miri

I think it's time we paid good attention to the full experience of writing unsafe code. We need to be sure that people can write unsafe Rust abstractions that are correct. This means, yes, that we need to invest in defining the rules they have to follow. I think we also need to invest time in making correct unsafe Rust code more *ergonomic* to write. Unsafe Rust today often involves a lot of annotations and casts that don't necessarily add much to the code[^boilerplate]. There are also some core features, like method dispatch with a raw pointer, that don't work, as well as features (like [unsafe fields]) that would help in ensuring unsafe guarantees are met.

[unsafe fields]: https://github.com/rust-lang/rfcs/issues/381

[^boilerplate]: ...besides boilerplate.

[versatile]: https://rustacean-principles.netlify.app/how_rust_empowers/versatile.html

## Daring to ask for a richer, more interactive experience from Rust's tooling

Tooling has a huge impact on the experience of using Rust, both as a learner and as a power user. I maintain that the the hassle-free experience of [rustup] and [cargo] has done as much for Rust's adoption as our safety guarantees -- maybe more. The quality of the compiler's error messages comes up in virtually every single conversation I have, and I've lost count of how many people cite [clippy] and [rustfmt] as a key part of their onboarding process for new developers. Furthermore, after many years of ridiculously hard work, Rust's IDE support is starting to be *really, really good*. Major kudos to both the [rust-analyzer] and [IntelliJ Rust] teams.

[rustup]: https://rustup.rs/
[cargo]: https://doc.rust-lang.org/cargo/
[clippy]: https://github.com/rust-lang/rust-clippy
[rustfmt]: https://rust-lang.github.io/rustfmt/?version=v1.4.38&search=
[rust-analyzer]: https://rust-analyzer.github.io/
[IntelliJ Rust]: https://www.jetbrains.com/rust/

**And yet, because I'm greedy, I want more. I want Rust to continue its tradition of "groundbreakingly good" tooling.** I want you to be able to write `cargo test --debug` and have your test failures show up automatically in an omniscient debugger that lets you easily determine what happened[^pco]. I want profilers that serve up an approachable analysis of where you are burning CPU or allocating memory. I want it to be trivial to "up your game" when it comes to reliability by applying best practices like analyzing and improving code coverage or using a fuzzer to produce inputs.

[^pco]: [Watch the recording](https://www.youtube.com/watch?v=uTc7KCBbVFI) [pernos.co](https://pernos.co/) demo that Felix did for the Rustc Reading Club to get a sense for what is possible here!

[insta]: https://insta.rs/

I'm especially interested in tooling that changes the "fundamental relationship" between the Rust programmer and their programs. The difference between fixing compilation bugs in a modern Rust IDE and using `rustc` is a good illustration of this. In an IDE, you have the freedom to pick and choose which errors to fix and in which order, and the IDEs are getting good enough these days that this works quite well. Feedback is swift. This can be a big win.

I think we can do more like this. I would like to see people learning how the borrow checker works by "stepping through" code that doesn't pass the borrow check, seeing the kinds of memory safety errors that can occur if that code were to execute. Or perhaps "debugging" trait resolution failures or other complex errors in a more interactive fashion. [The sky's the limit.](https://github.com/rust-lang/rust-artwork/blob/master/2017-RustConf/Rust_Lucy%20Art_A.svg)

## Daring to ask for richer tooling *for unsafe Rust*

One area where improved tooling could be particularly important is around "unsafe" Rust. If we really want people to write unsafe Rust code that is correct in practice -- and I do! -- they are going to need help. Just as with all Rust tooling, I think we need to cover the basics, but I also think we can go beyond that. We definitely need sanitizers, for example, but rather than just detecting errors, we can connect those sanitizers to debuggers and use that error as an opportunity to *teach people how stacked borrows works*. We can build better testing frameworks that make things like fuzzing and property-based testing easy. And we can offer strong support for [formal methods](https://github.com/rust-formal-methods/wg), to support libraries that want to invest the time can give higher levels of assurance (the standard library seems like a good candidate, for example).

## Conclusion: we got this

As Rust sees more success, it becomes harder and harder to make changes. There's more and more Rust code out there and continuity and stability can sometimes be more important than fixing something that's broken. And even when you do decide to make a change, everybody has opinions about how you should be doing it differently -- worse yet, sometimes they're right.[^wrong] It can sometimes be very tempting to say, "Rust is good enough, you don't want one language for everything anyway" and leave it at that.

For Rust 2024, I don't want us to do that. I think Rust is awesome. But I think Rust could be *awesomer*. We definitely shouldn't go about making changes "just because", we have to respect the work we've done before, and we have to be realistic about the price of churn. But we should be planning and dreaming as though the current crop of Rust programmers is just the beginning -- as though the vast majority of Rust programs are yet to be written (which they are). 

My hope is that for RustConf 2024, people will be bragging to each other about the hardships they endured back in the day. "Oh yeah," they'll say, "I was writing async Rust back in the old days. You had to grab a random crate from crates.io for every little thing you want to do. You want to use an async fn in a trait? Get a crate. You want to write an iterator that can await? Get a crate. People would come to standup after 5 days of hacking and be like 'I finally got the code to compile!' And we walked to work uphill in the snow! Both ways! In the summer!"[^carried-away]

[^carried-away]: I may have gotten a little carried away there.

So yeah, for Rust 2024, let's dare to ask for more.[^poet]

[^poet]: Hey, that rhymes! I'm a poet, and I didn't even know it!


[^wrong]: It's so much easier when everybody else is wrong.

## Footnotes

[^coding]: One interesting change: I've been writing more and more code again. This itself is making a big difference in my state of mind, too!

[^die]: Die, I tell you! DIE!

[^precisely]: Because it's 2022, get it?
