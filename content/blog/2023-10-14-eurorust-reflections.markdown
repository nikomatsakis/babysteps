---
title: "Eurorust reflections"
date: 2023-10-14T12:47:05-04:00
---

I’m on the plane back to the US from Belgium now and feeling grateful for having had the chance to speak at the [EuroRust conference][er][^slides]. EuroRust was the first Rust-focused conference that I’ve attended since COVID (though not the first conference overall). It was also the first Rust-focused conference that I’ve attended in Europe since…ever, from what I recall.[^rf] Since many of us were going to be in attendance, the types team also organized an in-person meetup which took place for 3 days before the conference itself[^agenda]. Both the meetup and the conference were great in many ways, and sparked a lot of ideas. I think I’ll be writing blog posts about them for weeks to come, but I thought that to start, I’d write up something general about the conference itself, and some of my takeaways from the experience

[er]: https://eurorust.eu

[^slides]: As I usually do, I’ve [put my slides online](https://github.com/nikomatsakis/eurorust-2023). If you’re curious, take a look! If you see a typo, maybe open a PR. The speaker notes have some of the “soundrack”, though not all of it.

[^rf]: Somehow, I never made it to a RustFest. 

[^agenda]: You can find the [agenda][] here. It contains links to the briefing documents that we prepared in advance, along with loose notes that we took during the discussions. I expect we’ll author a blog post covering the key developments on the Inside Rust blog.

[agenda]: https://hackmd.io/cO1NJWTHTVihbE0UCWyRfg

### It’s great to talk to people **using** Rust

When I started on Rust, I figured the project was never going to go anywhere — I mean, come on, we were making a new programming language. What are the odds it’ll be a success? But it still seemed like fun. So I set myself a simple benchmark: I will consider the project a success the first time I see an announcement where somebody built something cool with it, and I didn’t know them beforehand. In those days, everybody using Rust was also hanging out on IRC or on the mailing list.

Well, that turned out to be a touch on the conservative side. These days, Rust has gotten big enough that the core project itself is just a small piece of the action. It’s just amazing to hear all the things people are using Rust for. Just looking at the conference sponsors alone, I loved meeting the [Shuttle] and [Tauri]/[CrabNebula] teams and I got excited about playing with both of them. I had a great time [talking to the RustRover team](https://twitter.com/rustrover/status/1712461642666320369) about the possibilities for building custom diagnostics and the ways we could leverage their custom GUI to finally get past the limitations of the terminal when we present error messages. But one of my favorite parts happened on the tram ride home, when I randomly met the maintainer of [PyO3]. Such a cool project, and definite inspiration for work I’ve been doing lately, like [duchess].

[PyO3]: https://pyo3.rs
[Shuttle]: https://www.shuttle.rs/
[Tauri]: https://tauri.app
[CrabNebula]: https://crabnebula.dev/
[duchess]: https://duchess-rs.github.io/duchess

### Rust teachers everywhere

Speaking of [Shuttle][] and [Tauri][], both of them are interesting in a particular way: they are empowerment efforts in their own right, and so they attract people whose primary interest is not Rust itself, but rather achieving some other goal (e.g., cloud development, or building a GUI application). It's cool to see Rust empowering people to build other empowerment apps, but it's *also* a fascinating source of data. Both of those projects have started embarking on efforts to teach Rust precisely because that will help grow their userbase. The Shuttle blog has all kinds of interesting articles[^oauth]; the Tauri folks told me about their efforts to build Rust articles specifically targeting JavaScript and TypeScript programmers, which required careful choice of terminology and concepts.

[^oauth]: Including one I can't *wait* to read about [OAuth](https://www.shuttle.rs/blog/2023/08/30/using-oauth-with-axum) -- I tried to understand Github's docs on OAuth and just got completely lost.

### The whole RustFest idea seems to have really worked

At some point, RustFest morphed from a particular conference into a kind of ‘meta conference’ organization, helping others to organize and run their own events. Looking over the calendar of Rust events in Europe, I have to say, that looks like it’s worked out pretty dang well. Hats off to y’all on that. Between [EuroRust](https://eurorust.eu), [RustLab in Italy](https://rustlab.it/), [Rust Nation](https://www.rustnationuk.com/) in the UK, and probably a bunch more that I’m not aware of.

I should also say that meeting the conference *organizers* at this conference was very nice. Both the EuroRust organizers (Marcus and Sarah, from MainMatter) were great to talk to, and I finally got to meet [Ernest](https://github.com/ernestkissiedu) (now organizing Rust Nation in the UK), whom I’ve talked to on and off over the years but never met in person. 

I do still miss the cozy chats at [Rust Belt Rust](https://www.rust-belt-rust.com/) (RIP), but this new generation of Rust conferences (and their organizers) is pretty rad too. Plus I get to eat good cheese and drink beer outdoors, two things that for reasons unbeknownst to me are all too rare in the United States.

### The kids are all right

One of my favorite things about being involved in the Rust project has been watching it sustain and reinvent itself over the years. This year at the conference I got to see the “new generation” of Rust maintainers and contributors — some of them, like @davidtwco, I had met before, but who have gone from “wanna be” Rust contributor to driving core initiatives like the [diagnostic translation effort](https://blog.rust-lang.org/inside-rust/2022/08/16/diagnostic-effort.html). Others — like @bjorn3, @WaffleLapkin, @Nilstrieb, and even @MaraBos — I had never had a chance to meet before. I love that working on Rust lets you interact with people from all other the world, but there’s nothing like putting a name to a face, and getting to give someone a hug or shake their hand. 

### But yeah, there’s that thing

So, let me say up front, due to scheduling conflicts, I wasn’t able to attend RustConf this year (or last year, as it happens). But I read [Adam Chalmer's blog post](https://blog.adamchalmers.com/rustconf-2023-recap/) that many people were talking about, and I saw this paragraph…

> **Rustconf definitely felt sadder and downbeat than my previous visit.** Rustconf 2019 felt jubilant. The opening keynote celebrated the many exciting things that had happened over the last year. Non-lexical lifetimes had just shipped, which removed a ton of confusing borrow checker edge cases. Async/await was just a few short months away from being stabilized, unleashing a lot of high-performance, massively-scalable software. Eliza Weisman was presenting a new async tracing library which soon took over the Rust ecosystem. Lin Clark presented about how you could actually compile Rust into this niche thing called WebAssembly and get Rust to run on the frontend -- awesome! **It felt like Rust had a clear vision and was rapidly achieving its goals. I was super excited to be part of this revolution in software engineering.**

…and it made me feel really sad.[^lots] Rust’s mission has always been empowerment. I’ve always loved the “can do” spirit of Rust, the way we aim high and try to push boundaries in every way we can. **To me, the open source org has always been an important part of how we empower.**

[^lots]: Side note, but I think Rust 2024 is shaping up to be another hugely impactful edition. There's a very good chance we'll have [async functions in traits](https://blog.rust-lang.org/inside-rust/2023/05/03/stabilizing-async-fn-in-trait.html), [type alias impl trait](https://rust-lang.github.io/impl-trait-initiative/explainer/tait.html), and [polonius](https://blog.rust-lang.org/inside-rust/2023/10/06/polonius-update.html), each of which is a massive usability and expressiveness win. I'm hoping we'll also get [improved temporary lifetimes](https://smallcultfollowing.com/babysteps/blog/2023/03/15/temporary-lifetimes/) in the new edition, eliminating the "blocking bugs" [identified as among the most common in real-world Rust programs](https://cseweb.ucsd.edu/~yiying/RustStudy-PLDI20.pdf). And of course the last few years have already seen let-else, scoped threads, cargo add, and a variety of other cahnges. Gonna be great!

Developing a programming language, especially a compiled one, is often viewed as the work of “wizards”, just like systems programming. I think Rust proves that this “wizard-like” reputation has more to do with the limitations of the tools we were using than the task itself. But just like Rust has the goal of making systems programming more practical and accessible, I like to think *the Rust org* helps to open up language development to a wider audience. I’ve seen so many people come to Rust, full of enthusiasm but not so much experience, and use it to launch a new career.

But, if I’m honest, I’ve also seen a lot of people come into Rust full of enthusiasm and wind up burned out and frustrated. And sometimes I think that’s precisely *because* of our “sky’s the limit” attitude — sometimes we can get so ambitious, we set ourselves up to crash and burn.

### Sometimes “thinking big” means getting nowhere

Everybody wants to “think big”. And Rust has always prided itself on taking a “holistic view” of problems — we’ve tried to pay attention to the whole project, not just generating good code, but targeting the whole experience with quality diagnostics, a build system, an easy way to manage which Rust version you want, a package ecosystem, etc. But when we look at all the stuff we’ve built, it’s easy to forget how we got there: incrementally and painfully.

I mean, in Ye Olde Days of Rust, we didn’t even have a borrow checker. Soundness was an aspiration, not a reality. And once we got one, it sucked to use, because the design was still stuck in some ‘old style’ thinking. And even once we had INHTWAMA[^phrase], the error messages were pretty confounding. And once we [invented the idea of multiline errors][err], it wasn’t until late 2018 that we had [NLL], which changed the game again. And that’s just the compiler! The story is pretty much the same for every other detail of the language. You used to have to build the compiler with a Makefile that was so complex, I wouldn’t be surprised if were self-aware.[^makefns]

[err]: https://blog.rust-lang.org/2016/08/10/Shape-of-errors-to-come.html

[NLL]: https://blog.rust-lang.org/2018/12/06/Rust-1.31-and-rust-2018.html#non-lexical-lifetimes

[^phrase]: INHTWAMA was the rather awkward (and inaccurate) acronym that we gave to the idea of “aliasing xor mutation” — i.e., the key principle underlying Rust’s borrow checker. The name comes from a blog post I wrote called [“Imagine never hearing the phrase aliasable, mutable again”][inhtwama], which @pcwalton incorrectly remembered as “Imagine never hearing the *words* aliasable, mutable again”, and hence shortened to INHTWAMA. I notice now though that this acronym was also frequently mutated to I*M*HTWAMA which just makes no sense at all. 

[inhtwama]: https://smallcultfollowing.com/babysteps/blog/2012/11/18/imagine-never-hearing-the-phrase-aliasable/

[^makefns]: I learned a lot from reading Rust’s `Makefile` in the early days. I had no idea you could model function calls in `make` with macros. Brilliant. I’ve always deeply admired Graydon’s `Makefile` wizardry there, though it ocucrs to me now that I never checked the git logs.

**When I feel burned out, one of the biggest reasons is that I've fallen into the trap of thinking too big, doing too much, and as a result I am spread too thin and everything seems impossible.** Just look back three years ago: the async working group was driving this crazy project, [the Async Vision Doc][avd], and it seemed like we were on top of the world. We recorded all these stories of how async Rust was hard, and we were thinking about how we could solve it. Not surprisingly, we found that these stories were sometimes language problems, but just as often they were library limitations, or gaps in the tooling, or the docs. And so we set out an [expansive vision, spawning out a ton of subprojects][prj]. And all the time, there was a voice in my head saying, “is this really going to work?”

[avd]: https://blog.rust-lang.org/2021/03/18/async-vision-doc.html

[prj]: https://rust-lang.github.io/wg-async/vision/roadmap.html

Well, I’d say the answer is “no”. I mean, we made a lot of progress. We are going to stabilize async functions in traits this year, and that is **awesome**. We made a bunch of improvements to async usability, most notably cjgillot’s fantastic PR that improves the accuracy of send bounds and futures, preventing a whole ton of false errors (though that work wasn’t really done in coordination with the async wg effort per se, it’s just because cjgillot is out there silently making huge refactors[^wrong]).

[^wrong]: Side note, but more often than not, I think cjgillot’s approaches are not going to work. And so far I’m 0 for 2 on this, he’s always been right. To [paraphrase Brendan Eich](https://twitter.com/BrendanEich/status/1456758350419480580), “always bet on cjgillot”.

And yet, there’s a lot we didn’t do. We don’t have generators. We didn’t yet find a way to make futures smaller. We didn’t really drive to ground the conversation on structured concurrency. We also took a lot *longer* to do stuff than I hoped. I thought async functions in traits would ship in 2021 — it’s shipping now, but it’s 2023. 

### Focus, focus, focus; iterate, iterate, iterate

One lesson I take away from the async wg experience is focus, focus, focus and iterate, iterate, iterate. **You can (almost) never start too small.** I think we were absolutely right that “doing async right” demands addressing all of those concerns, but I think that we overestimated our ability to coordinate them up front, and as a result, things like shipping async fn in traits took longer than they needed to. We *are* going to get the async shiny future, but we’re going to get it one step at a time.

### Also: we’re a lot bigger than we used to

Still, sometimes I find that when I float ideas, I encounter a reflexive bit of pushback: *“sounds great, who’s going to do it”*. One the one hand, that’s the voice of experience, coming back from one too many Think Big plans that didn’t work out. But on the other, sometimes it feels a bit like “old school” thinking to me.  Rust is not the dinky little project it used to be, where we all knew everybody. Rust is used by [millions of developers](https://www.slashdata.co/blog/state-of-the-developer-nation-23rd-edition-the-fall-of-web-frameworks-coding-languages-blockchain-and-more/) and is one of [the fastest growing language today](https://www.oreilly.com/radar/technology-trends-for-2023/); it [powers](https://www.theregister.com/2022/09/20/rust_microsoft_c/) [the cloud](https://aws.amazon.com/blogs/opensource/why-aws-loves-rust-and-how-wed-like-to-help/) and it’s quite possibly in [your](https://github.com/Rust-for-Linux) [kernel](https://www.bleepingcomputer.com/news/microsoft/new-windows-11-build-ships-with-more-rust-based-kernel-features/). In many ways, this growth hasn’t caught up with the open source org: I’d still like to see more companies hiring dedicated Rust teams of Rust developers, or giving their employees paid time to work on Rust[^ideas]. But I think that growth is coming, especially if we work harder at harnessing it, and I am very excited about what that can mean.

[^ideas]: And I have some thoughts on how we can do better at encouraging them! More on that in some later posts.

### Nothing succeeds like success

Now I know that when we talk about burnout, we’re also talking about other kinds of drama. Maybe you think that things like ‘working iteratively’ and having more people or resources are not going to help when the problem is conflicts between people or organizations. And you’re not wrong, it’s not going to solve all conflict. But I also think that an awful lot of conflict ultimately comes out of zero-sum, scarcity-oriented thinking, or from feeling disempowered to achieve the goals you set out to do. To help with burnout, we need to do better at a number of things, including I think helping each other to [practice empathy] and manage conflict more productively[^lesson], but I think we also need to do better at shipping product.

[practice empathy]: https://smallcultfollowing.com/babysteps/blog/2023/09/27/empathy-in-open-source/

[^lesson]: One of the biggest lessons for me in my personal life has been realizing that not telling people when I feel upset is not necessarily being kind to them and certainly not kind to myself. It seems like avoiding conflict, but it can actually lead to much larger conflicts down the line.

### Don’t be afraid to fail — you got this

One of my favorite conversations from the whole conference happened after the conference itself. I was in the midst of pitching Jack Huey on some of the organizational ideas that I’m really excited about right now, which I think can help bring the Rust project closer to being the empowering, inclusive open-source project it aspires to be. Jack wasn’t sure if they were going to work. “But”, he said, “what the heck, let’s try it! I mean, what have we got to lose? If it doesn’t work, we’ll learn something, and do something else.”[^paraphrase] Hell yes.

[^paraphrase]: Full confession, this quote is made up out of thin air. I have no memory of what words he used. But this is what he meant!


