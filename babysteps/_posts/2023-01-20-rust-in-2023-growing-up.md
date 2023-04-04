---
layout: post
title: 'Rust in 2023: Growing up'
date: 2023-01-20 08:08 -0500
---

When I started working on Rust in 2011, my daughter was about three months old. She’s now in sixth grade, and she’s started growing rapidly. Sometimes we wake up to find that her clothes don’t quite fit anymore: the sleeves might be a little too short, or the legs come up to her ankles. Rust is experiencing something similar. We’ve been growing tremendously fast over the last few years, and any time you experience growth like that, there are bound to be a few rough patches. Things that don’t work as well as they used to. This holds both in a technical sense — there are parts of the language that don’t seem to scale up to Rust’s current size — and in a social one — some aspects of how the projects runs need to change if we’re going to keep growing the way I think we should. As we head into 2023, with two years to go until the Rust 2024 edition, this is the theme I see for Rust: **maturation and scaling**.

## TL;DR

In summary, these are (some of) the things I think are most important for Rust in 2023:

* Implementing **[“the year of everywhere”][tye]** so that you can make any function async, write `impl Trait` just about anywhere, and fully utilize generic associated types; planning for the Rust 2024 edition.
* Beginning work on a **Rust specification** and integrating it into our processes. 
* Defining rules for **unsafe code** and smooth tooling to check whether you’re following them.
* Supporting efforts to **teach Rust** in universities and elsewhere.
* Improving our **product planning** and **user feedback** processes.
* Refining our **governance structure** with specialized teams for dedicated areas, more scalable structure for broad oversight, and more intensional onboarding.

[tye]: https://smallcultfollowing.com/babysteps/blog/2022/09/22/rust-2024-the-year-of-everywhere/

## “The year of everywhere” and the 2024 edition

What do async-await, impl Trait, and generic parameters have in common? They’re all essential parts of modern Rust, that’s one thing. They’re also all, in my opinion, in a “minimum viable product” state. Each of them has some key limitations that make them less useful and more confusing than they have to be. As I wrote in [“Rust 2024: The Year of Everywhere”][tye], there are currently a lot of folks working hard to lift those limitations through a number of extensions:

* Generic associated types ([stabilized in October](https://blog.rust-lang.org/2022/10/28/gats-stabilization.html), now undergoing various improvements!)
* Type alias impl trait ([proposed for stabilization](https://github.com/rust-lang/rust/issues/63063#issuecomment-1354392317))
* Async functions in traits and “return position impl Trait in traits” ([static dispatch available on nightly](https://blog.rust-lang.org/inside-rust/2022/11/17/async-fn-in-trait-nightly.html), but more work is needed)
* Polonius (under active discussion)

None of these features are “new”. They just take something that exists in Rust and let you use it more broadly. Nonetheless, I think they’re going to have a big impact, on experienced and new users alike. Experienced users can express more patterns more easily and avoid awkward workarounds. New users never have to experience the confusion that comes from typing something that feels like it *should* work, but doesn’t.

One other important point: **Rust 2024 is just around the corner!** Our goal is to get any edition changes landed on master this year, so that we can spend the next year doing finishing touches. This means we need to put in some effort to thinking ahead and planning what we can achieve.

## Towards a Rust specification

As Rust grows, there is increasing need for a specification. Mara had a [recent blog post][marastd] outlining some of the considerations — and especially the distinction between a *specification* and *standardization*. I don’t see the need for Rust to get involved in any standards bodies — our existing RFC and open-source process works well. But I do think that for us to continue growing out the set of people working on Rust, we need a central definition of what Rust should do, and that we need to integrate that definition into our processes more thoroughly. 

In addition to long-standing docs like the [Rust Reference][rr], the last year has seen a number of notable efforts towards a Rust specification. The [Ferrocene language specification][spec] is the most comprehensive, covering the grammar, name resolution, and overall functioning of the compiler. Separately, I’ve been working on a project called [a-mir-formality][], which aims to be a “formal model” of Rust’s type system, including the borrow checker. And Ralf Jung has [MiniRust][], which is targeting the rules for unsafe code.

So what would an official Rust specification look like? Mara opened [RFC 3355][], which lays out some basic parameters. I think there are still a lot of questions to work out. Most obviously, how can we combine the existing efforts and documents? Each of them has a different focus and — as a result — a somewhat different structure. I’m hopeful that we can create a complementary whole.

Another important question is how to integrate the specification into our project processes. We’ve already got a rule that new language features can’t be stabilized until the reference is updated, but we’ve not always followed it, and the [lang docs team][] is always in need of support. There are hopeful signs here: both the Foundation and Ferrocene are interested in supporting this effort.

[marastd]: https://blog.m-ou.se/rust-standard/

[RFC 3355]: https://github.com/rust-lang/rfcs/pull/3355

[rr]: https://doc.rust-lang.org/reference/

[Lang docs team]: https://www.rust-lang.org/governance/teams/lang#lang-docs%20team

[Ferrocene project]: https://ferrous-systems.com/ferrocene/

[spec]: https://spec.ferrocene.dev/

[a-mir-formality]: https://github.com/nikomatsakis/a-mir-formality

[MiniRust]: https://www.ralfj.de/blog/2022/08/08/minirust.html

## Unsafe code

In my experience, most production users of Rust don’t touch unsafe code, which is as it should be. But almost every user of Rust relies on dependencies that do, and those dependencies are often the most critical systems. 

At first, the idea of unsafe code seems simple. By writing `unsafe`, you gain access to new capabilities, but you take responsibility for using them correctly. But the more you look at unsafe code, the more questions come up. [What does it mean to use those capabilities *correctly*?][nomicon] These questions are not just academic, they have a real impact on optimizations performed by the Rust compiler, LLVM, and even the hardware.

Eventually, we want to get to a place where those who author unsafe code have clear rules to follow, as well as simple tooling to test if their code violates those rules (think `cargo test —unsafe`). Authors who want more assurance than dynamic testing can provide should have access to static verifiers that can prove their crate is safe — and we should start by proving the standard library is safe.

We’ve been trying for some years to build that world but it’s been ridiculously hard. Lately, though, there have been some breakthroughs. Gankra’s [experiments with  `strict_provenance` APIs][95228] have given some hope that we can define a relatively simple [provenance model][pm] that will support both arbitrary unsafe code trickery and aggressive optimization, and Ralf Jung’s aforementioned [MiniRust][] shows how a Rust operational semantics could look. More and more crates test with [miri][] to check their unsafe code, and for those who wish to go further, the [kani][] verifier can check unsafe code for UB ([more formal methods tooling][fmtools] here).

[nomicon]: https://doc.rust-lang.org/nomicon/

[bolero]: https://camshaft.github.io/bolero/

[95228]: https://github.com/rust-lang/rust/issues/95228

[pm]: https://www.ralfj.de/blog/2022/04/11/provenance-exposed.html

[miri]: https://www.ralfj.de/blog/2022/07/02/miri.html

I think we need a renewed focus on unsafe code in 2023. The first step is already underway: we are **creating the [opsem team][3346]**. Led by [Ralf Jung][] and [Jakob Degen][], the opsem team has the job of defining “the rules governing unsafe code in Rust”. It’s been clear for some time that this area requires dedicated focus, and I am hopeful that the opsem team will help to provide that.

[Ralf Jung]: https://github.com/RalfJung

[Jakob Degen]: https://github.com/JakobDegen

I would like to see progress on **dynamic verification**. In particular, I think we need a tool that can handle arbitrary binaries. [miri][] is great, but it can’t be used to test programs that call into C code. I’d like to see something more like [valgrind][] or [ubsan][], where you can test your Rust project for UB even if it’s calling into other languages through FFI.

[valgrind]: https://valgrind.org/

[ubsan]: https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html

Dynamic verification is great, but it is limited by the scope of your tests. To get true reliability, we need a way for unsafe code authors to do static verification. Building static verification tools today is possible but extremely painful. The compiler’s APIs are unstable and a moving target. **The [stable MIR][] project proposes to change that by providing a stable set of APIs that tool authors can build on**. 

[stable MIR]: https://github.com/rust-lang/project-stable-mir

Finally, the best unsafe code is the unsafe code you don’t have to write. Unsafe code provides infinite power, but people often have simpler needs that could be made safe with enough effort. Projects like [cxx][] demonstrate the power of this approach. For Rust the language, [safe transmute][] is the most promising such effort, and I’d like to see more of that.

[cxx]: https://cxx.rs/

[safe transmute]: https://rust-lang.github.io/rfcs/2835-project-safe-transmute.html

[fmtools]: https://rust-formal-methods.github.io/tools.html

[kani]: https://model-checking.github.io/kani/

[ucg]: https://rust-lang.github.io/unsafe-code-guidelines/

## Teaching Rust in universities

More and more universities are offering classes that make use of Rust, and recently many of these educators have come together in the [Rust Edu initiative][re] to form shared teaching materials. I think this is great, and a trend we should encourage. It’s helpful for the Rust community, of course, since it means more Rust programmers. I think it’s also helpful for the students: much like learning a functional programming language, learning Rust requires incorporating different patterns and structure than other languages. I find my programs tend to be broken into smaller pieces, and the borrow checker forces me to be more thoughtful about which bits of context each function will need. Even if you wind up building your code in other languages, those new patterns will influence the way you work. 

[re]: https://rust-edu.org

Stronger connections to teacher can also be a great source of data for improving Rust. If we understand better how people learn Rust and what they find difficult, we can use that to guide our priorities and look for ways to make it better. This might mean changing the language, but it might also mean changing the tooling or error messages. I’d like to see us setup some mechanism to feed insights from Rust educators, both in universities but also trainers at companies like [Ferrous Systems][] or [Integer32][], into the Rust teams.

One particularly exciting effort here is the research being done at Brown University[^disclosure] by Will Crichton and Shriram Krisnamurthi. Will and Shriram have published an [interactive version of the Rust book][rb] that includes quizzes. As a reader, these quizzes help you check that you understood the section. But they also provide feedback to the book authors on which sections are effective. And they allow for “A/B testing”, where you change the content of the book and see whether the quiz scores improve. Will and Shriram are also looking at other ways to deepen our understanding of how people learn Rust.

[Ferrous Systems]: https://ferrous-systems.com/

[Integer32]: https://www.integer32.com/

[rb]: https://rust-book.cs.brown.edu/

[^disclosure]: In disclosure, AWS is a sponsor of this work.

## More insight and data into the user experience

As Rust has grown, we no longer have the obvious gaps in our user experience that there used to be (e.g., “no IDE support”). At the same time, it’s clear that the experience of Rust developers could be a lot smoother. There are a lot of great ideas of changes to make, but it’s hard to know which ones would be most effective. **I would like to see a more coordinated effort to gather data on the user experience and transform it into actionable insights.** Currently, the largest source of data that we have is the annual Rust survey. This is a great resource, but it only gives a very broad picture of what’s going on.

A few years back, the async working group collected “status quo” stories as part of its vision doc effort. These stories were immensely helpful in understanding the “async Rust user experience”, and they are still helping to shape the priorities of the async working group today. At the same time, that was a one-time effort, and it was focused on async specifically. I think that kind of effort could be useful in a number of areas.

I’ve already mentioned that teachers can provide one source of data. Another is simply going out and having conversations with Rust users. But I think we also need fine-grained data about the user experience. In the compiler team’s [mid-year report][], they noted (emphasis mine):

> One more thing I want to point out: five of the ambitions checked the box in the survey that said "some of our work has reached Rust programmers, but **we do not know if it has improved Rust for them.”** 

Right now, it’s really hard to know even basic things, like how many users are encountering compiler bugs in the wild. We have to judge that by how many comments people leave on a Github issue. Meanwhile, [Esteban][] personally scours twitter to find out which error messages are confusing to people.[^always] We should look into better ways to gather data here. I’m a fan of (opt-in, privacy preserving) telemetry, but I think there’s a discussion to be had here about the best approach. All I know is that there has to be a better way.

[^always]: To be honest, Esteban will probably always do that, whatever we do.

[Esteban]: https://github.com/estebank

[racket]: https://cs.brown.edu/~sk/Publications/Papers/Published/mfk-mind-lang-novice-inter-error-msg/paper.pdf

[mid-year report]: https://blog.rust-lang.org/inside-rust/2022/08/08/compiler-team-2022-midyear-report.html#compiler-team-operations-aspirations-%EF%B8%8F

## Maturing our governance

In 2015, shortly after 1.0, [RFC 1068][] introduced the original Rust teams: libs, lang, compiler, infra, and moderation. Each team is an independent, decision-making entity, owning one particular aspect of Rust, and operating by consensus. The “Rust core team” was given the role of knitting them together and providing a unifying vision. This structure has been a great success, but as we’ve grown, it has started to hit some limits.

[RFC 1068]: https://rust-lang.github.io/rfcs/1068-rust-governance.html?highlight=team#

The first limiting point has been bringing the teams together. The original vision was that team leads—along with others—would be part of a *core team* that would provide a unifying technical vision and tend to the health of the project. It’s become clear over time though that there are really different jobs. Over this year, the various Rust teams, project directors, and existing core team have come together to define a new model for project-wide governance. This effort is being driven by a [dedicated working group][gov-update] and I am looking forward to seeing that effort come to fruition this year.

The second limiting point has been the need for more specialized teams. One example near and dear to my heart is the new [types team][3254], which is focused on type and trait system. This team has the job of diving into the nitty gritty on proposals like Generic Associated Types or impl Trait, and then surfacing up the key details for broader-based teams like lang or compiler where necessary. The aforementioned [opsem team][3346] is another example of this sort of team. I suspect we’ll be seeing more teams like this. 

[3254]: https://github.com/rust-lang/rfcs/pull/3254

[3346]: https://github.com/rust-lang/rfcs/pull/3346

There continues to be a need for us to grow teams that do [more than coding][mtc]. The compiler team prioritization effort, under the leadership of [apiraino][], is a great example of a vital role that allows Rust to function but doesn’t involve landing PRs. I think there are a number of other “multiplier”-type efforts that we could use. One example would be “reporters”, i.e., people to help publish blog posts about the many things going on and spread information around the project. I am hopeful that as we get a new structure for top-level governance we can see some renewed focus and experimentation here.

[apiraino]: https://github.com/apiraino

[mtc]: https://smallcultfollowing.com/babysteps/blog/2019/04/15/more-than-coders/

[gov-update]: https://blog.rust-lang.org/inside-rust/2022/10/06/governance-update.html

## Conclusion

Seven years since Rust 1.0 and we are still going strong. As Rust usage spreads, our focus is changing. Where once we had gaping holes to close, it’s now more a question of iterating to build on our success. But the more things change, the more they stay the same. Rust is still working to empower people to build reliable, performant programs. We still believe that building a supportive, productive tool for systems programming — one that brings more people into the “systems programming” tent — is also the best way to help the existing C and C++ programmers “hack without fear” and build the kind of systems they always wanted to build. So, what are you waiting for? Let’s get building!
