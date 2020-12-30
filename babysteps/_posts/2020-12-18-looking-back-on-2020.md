---
layout: post
title: Looking back on 2020
categories: [Rust]
---

I wanted to write a post that looks back over 2020 from a personal perspective. My goal here is to look at the various initiatives that I've been involved in and try to get a sense for how they went, what worked and what didn't, and also what that means for next year. This post is a backdrop for a #niko2021 post that I plan to post sometime before 2021 actually starts, talking about what I expect to be doing in 2021.

I want to emphasize the 'personal' bit. **This is not meant as a general retrospective of what has happened in the Rust universe.** I also don't mean to claim credit for all (or most) of the ideas on this list. Some of them are things I was at best tangentially involved in, but which I think are inspiring, and would inform events of next year.

### The backdrop: total hellscape

It goes without saying that it was quite a year. It's impossible to ignore the pandemic, the killings of George Floyd, Breonna Taylor, Ahmaud Arbery, China's actions in Hong Kong, massive financial disruption, what can only be described as an attempt to steal the US election, and all the other things that are going on around us. Many of the [biggest events in Rust][foundation] were shaped by this global backdrop. If nothing else, it added to a general ambient stress level that made 2020 a very difficult year for me personally. Not to provide free advertising for anyone, but [this match.com commercial really did capture it](https://www.youtube.com/watch?v=qmb5ENInqVk). Here's to a better 2021. 🥂

[foundation]: https://blog.rust-lang.org/2020/08/18/laying-the-foundation-for-rusts-future.html

### Still, a lot of good stuff happened

Despite all of that, I am pretty proud of a number of developments around Rust that I have been involved in. I think we done a number of important things, and we have a number of really promising initiatives in flight as well that I think will come to fruition in 2021. I'd like to talk about some of those.

Once I started compiling a list I realized there's an awful lot, so here is a kind of TL;DR where you can click for more details:

* Process and governance
    * [The Major Change Process helped compiler team spend more time on design](#mcp)
    * [Lang Team Project Proposals show promise, but are a WIP](#pp)
    * [The Lang Team's Backlog Bonanza was great, and should continue](#bb)
    * [The Foundation Conversation was an interesting model I think we can apply elsewhere](#fc)
    * [The Foundation is very exciting](#f)
* Technical work
    * [The group working on RFC 2229 ("disjoint closure captures") is awesome](#rfc2229)
    * [The MVP for const generics is great, and we should do more](#mvp)
    * [Sprints for Polonius are a great model, we need more sprints](#sprint)
    * [Chalk and designs for a shared type library](#chalk)
    * [Progress on ffi-unwind](#ffi-unwind)
    * [Progress on never type stabilization](#never)
    * [Progress on Async Rust](#async)

<a name="mcp"></a>

### The Major Change Process helped compiler team spend more time on design

One of the things I am most happy with is the compiler team's [Major Change Process](https://forge.rust-lang.org/compiler/mcp.html). For those not familiar with it, the idea is simple: if you would like to make a Major Change to the compiler (defined loosely as "something that would change documentation in the [rustc-dev-guide]"), then you first open an issue (called a Major Change Proposal, or MCP) on the compiler-team repository. In that issue, you describe roughly the idea. This also automatically opens a Zulip thread in [#t-compiler/major changes](https://zulip-archive.rust-lang.org/233931tcompilermajorchanges/index.html) for discussion. If somebody on the compiler team likes the idea, they "second" the proposal. This automatically starts off a Final Comment Period of 10 days. At the end of that, the MCP is approved.

[rustc-dev-guide]: https://github.com/rust-lang/rustc-dev-guide

The goal of MCPs is two-fold. The first, and most important, goal is to encourage more design discussion. It would sometimes happen that we have large PRs opened with little or not indication of the greater design that they were shooting for, which made it really hard to review. We can now tell the authors of such PRs "please write an MCP describing the design you have in mind here". The second goal is to give us a lightweight way to make decisions. It would sometimes happen that PRs kind of get stuck without a clear "decision" having been made.

The MCP process is not without its problems. We recently did a [retrospective](https://rust-lang.github.io/compiler-team/minutes/design-meeting/2020-09-18-mcp-retrospective/) and while I think the first goal ("design feedback") has been a big success, the second goal ("clearer decisions") is a mixed bag. We've definitely had problems where MCPs were approved but people didn't feel their objections had been heard. I think we'll wind up tweaking the process to better account for that.

<a name="pp"></a>

### Lang Team Project Proposals show promise, but are a WIP

In the lang team, we have been experimenting on a change to our process we call ["project proposals"][bb]. The idea is that, before writing an RFC, you can write a more lightweight proposal to take the temperature of the lang team. We will take a look and decide whether what we think, which might be one of a few things:

[bb]: https://blog.rust-lang.org/inside-rust/2020/10/16/Backlog-Bonanza.html

* **Suggest implementing:** The idea is good and it is small enough that we think you can just go straight to implementation.
* **Needs an RFC:** The idea is good but it ought to have an RFC. We'll assign a liaison to work with you towards fleshing it out.
* **Close:** We don't feel this idea is a good fit right now.

I had a lot of goals in mind for project proposals. First, to help us avoid RFC limbo and [unbounded queues]. I want to get to the point where the only open RFCs on the repository are ones that are generally backed by the lang team, so that the team is able to keep up with the traffic on them and keep the process moving. But I want to do this without cutting off the potential for people to bring up interesting ideas that weren't on the team radar.

[unbounded queues]: http://smallcultfollowing.com/babysteps/blog/2019/07/10/aic-unbounded-queues-and-lang-design/

Another goal is to **support RFC authors better**. One bit of feedback I've received over the years numerous times is that people are intimidated to author RFCs, or consider it too much of a hassle. The idea of assigning a liaison is that they can help on the RFC and give guidance, while also keeping the broader team in the loop. 

Finally, I hope that liaisons can serve as part of a clearer [**path to lang-team membership**][pm]. The idea is that serving as the liaison for a project can be a way for us to see how people would be as a member of the lang-team and possibly recruit new members.

[pm]: https://blog.rust-lang.org/inside-rust/2020/07/09/lang-team-path-to-membership.html

I would say that the "project" system has been a mixed success. We've had a number of successful project groups, but we've also had some that are slow to start. We've not done a great job of recruiting fresh liaisons and I think the role could use more definition. Finally, we need to have much clearer messaging, and a more finalized "decision" around the RFC process -- I'm also concerned if the RFC process starts to diverge too much between teams. I think it's quite confusing for people right now to know how they're supposed to "pitch" an idea (and people are often unclear which team is the best fit for an idea). 

Josh and I have been iterating on a more complete "staged RFC" proposal that aims to address a number of those points (it's a refinement and iteration on the [older staged RFC idea] that I wrote about years ago). This is one of the things I'd really like to focus on next year, along with improving and defining the lang team liaison process.

[older staged RFC idea]: http://smallcultfollowing.com/babysteps/blog/2018/06/20/proposal-for-a-staged-rfc-process/

<a name="bb"></a>

### The Lang Team's Backlog Bonanza was great, and should continue

This year the lang team did a series of sync meetings that we called the ["Backlog Bonanza"][bb], where we went through every pending RFC and tried to figure out what to do with it. This was great not only because we were able to give feedback on every open RFC and (mostly) determine what to do with it[^feedback], but also as a 'team bonding' exercise (at least I thought so). It helped us to sharpen what kinds of things we think are important.

[^feedback]: In some cases, we still need to complete the follow-up work, I think, of actually closing and commenting on those RFCs. 

Next year I hope to extend the Backlog Bonanza towards triaging open tracking issues and features. I'd like this to fit in with the work towards tracking projects. Ideally we'd get to the point where you can very easily tell "what are the projects that are likely to be stabilized soon", "what are the projects that could use my help", and "what are the projects that are stalled out" (along with other similar questions).

<a name="fc"></a>

### The Foundation Conversation was an interesting model I think we can apply elsewhere

One of the things that's been on my mind this year is that we need to be looking for new ways to get "beyond the comment thread" when it comes to engaging with Rust users and getting design feedback. Comment threads are flexible and sometimes fantastic but prone to all kinds of problems, particularly on controversial or complex topics. Last year I wrote about [Collaborative Summary Documents][csd] as an alternative to comment threads. This year we tried out the [Foundation Conversation][tfc][^tip], and I thought it worked out quite well. I particularly enjoyed the Github Q&A aspect of it.[^tweet] It seemed like a good way to take questions and share information.

[csd]: http://smallcultfollowing.com/babysteps/blog/2019/04/22/aic-collaborative-summary-documents/
[tfc]: https://blog.rust-lang.org/2020/12/07/the-foundation-conversation.html
[^tweet]: Well, that and the [crude digital editing](https://twitter.com/nikomatsakis/status/1337715789852532736).
[^tip]: Hat tip to [Ashley Williams][ag_dubs] for proposing this communication plan.
[ag_dubs]: https://twitter.com/ag_dubs

The way we ran it, for future reference, was as follows:

* Open a github repo for a period of time to take questions.
* We had a zoom call going with the team all present.
* When new issues were opened, we would briefly discuss and assign someone to write a response. After some period of time, we'd review the response and suggest edits (or someone else might take over). This repeated until consensus was reached.
* At the end of the day, we collected the answers into a [FAQ].

[FAQ]: https://github.com/rust-lang/foundation-faq-2020/blob/main/FAQ.md

I feel like this might be an interesting model to use or adapt for other purposes. It might have been a nice way to take feedback on async-await syntax, for example, or other extremely controversial topics. In these cases there is often a lot of context that the team has acquired but it is difficult to "share it".

(One thing I've always wanted to do is to collect feedback via google forms or e-mails. We would then read and think about the feedback, maybe contact the authors, and produce a new design in response; we would also publish the feedback we got and our thoughts.)

<a name="f"></a>

### The Foundation is very exciting

A large part of my life this year has been spent learning and working towards the creation of a Rust Foundation, and I'm very excited that it's finally [taking shape](https://blog.rust-lang.org/2020/12/14/Next-steps-for-the-foundation-conversation.html). I think that the Foundation's mission of **empowering Rust maintainers to joyfully do their best work** is tremendously important, and I think it will provide a venue for us to do things on Rust that would be hard to do otherwise. If you want to learn more about it, check out the Foundation [FAQ] or our [live] [broadcasts].

While I'm on the topic, I want to say that I think Mozilla deserves a lot of credit here. It's not every company that would embark on a project like Rust, much less launch it out into an independent foundation. Huzzah!

[live]: https://twitter.com/rustlang/status/1336807743974481920
[broadcasts]: https://twitter.com/rustlang/status/1337505108599386112

<a name="rfc2229"></a>
### The group working on RFC 2229 ("disjoint closure captures") is awesome

[RFC 2229] proposed a change to how closure capture works. Consider a closure like `|| some_func(&a.b.c)`. Today, that closure will capture the entire variable `a`. Under [RFC 2229], it would capture `a.b.c`, which can avoid a number of unnecessary borrow checker conflicts. 

[RFC 2229] was approved in 2018 but implementation was stalled while we worked on NLL and other details. Recently though an [excellent group of folks](https://www.rust-lang.org/governance/teams/compiler#wg-rfc-2229) decided to take on the implementation work. Over the past year, I've been working with them on the design and implementation, and we've been making steady progress. The feature is now at the point where it "basically works" and we are working on migration (enabling this feature will require a Rust edition, as it would otherwise change the semantics of existing programs). A particular shout out to [arora-aman](https://github.com/arora-aman), who has been the "point person" for the group, helping to collect questions, relay answers, and generally keep things organized.

[RFC 2229]: https://rust-lang.github.io/rfcs/2229-capture-disjoint-fields.html

Given the great progress we've been making, I am quite hopeful that we'll see this feature land as part of a 2021 Rust Edition. The only caveat is that doing the implementation work has raised some questions about the best behavior for `move` closures and the like, so we may need to do a bit more design iteration before we are fully satisfied.

<a name="mvp"></a>
### The MVP for const generics is great, and we should do more

Const generics has been one of those 'long awaited' features whose fate often felt very uncertain. In July, boats [proposed](https://without.boats/blog/shipping-const-generics/) a kind of "MVP" for const generics -- a simple subset that enables a number of important use cases and sidesteps some of the areas where the implementation work isn't done yet. We now have a [stabilization PR for that subset in FCP][79135], thanks to a lot of tireless work by [lcnr](https://github.com/lcnr/), [varkor](github.com/varkor), and others.

[79135]: https://github.com/rust-lang/rust/pull/79135

I'm very excited about this for two reasons. First, I think the MVP will be really useful to library authors. But secondly, I think this "MVP" strategy that we should be deploying more often. For example, oli, matthewjasper and I recently outlined a kind of "MVP" for "named impl trait", though we have yet to describe or fully propose it. =)

This idea of pushing an MVP to conclusion is something we've done a number of times in Rust in the past, but it's one of those strategies that are easy to forget about it when you're in the thick of trying to work through some problem. I'm hopeful that in 2021 we can make progress on some of our longer running initiatives in this way.

<a name="sprint"></a>
### Sprints for Polonius are a great model, we need more sprints

Polonius is another project that has been making slow progress, mostly because other things keep taking higher priority. This year we tried a new approach to working on it, which was to schedule a "sprint week". The idea was that the entire group would reserve time in their schedules and spend about 4 hours a day over the course of one week to *just focus on polonius* (some people spent more). For projects like polonius, this kind of concentrated attention is really useful, because there is a lot of context you have to build up in your head in order to make progress.

In a [recent compiler team meeting](https://zulip-archive.rust-lang.org/238009tcompilermeetings/99285steeringmeeting20201204PerformanceGoalsfor2020.html), we discussed the idea of using these "sprints" more generally. For example, we considered having a bi-monthly compiler team sprint, where we would encourage the team (and new contributors!) to clear space in their schedules to help push progress on a particular goal. 

I've heard from many part-time contributors that this kind of sprint approach can be really useful, as it's easier to get support for a "week of concentrated work" than for a "steady drip" of tasks. (In the latter case, it's easy for those tasks to always be pre-empted by higher priorities work items.) It also can create a nice sense of community.

<a name="chalk"></a>
### Chalk and designs for a shared type library

Speaking of community, the Chalk project continues to advance, although with the work on the Foundation I at least have not been able to pay as much attention as I would like. Chalk's integration with rustc has made great progress, and it's still being used by rust-analyzer as the main trait engine. Lately our focus has been the shared type library that I [first proposed in March](https://rust-lang.github.io/compiler-team/minutes/design-meeting/2020-03-12-shared-library-for-types/). A huge shoutout to [jackh726](https://github.com/jackh726/), who has not only been writing a lot of great PRs, but also doing a lot of the organizational work. I expect this to be a continued area of focus in 2021.

<a name="ffi-unwind"></a>
### Progress on ffi-unwind

Unwinding across FFI boundaries has been a persistent annoying pain point for years. We generally wanted it to be UB, but there are some use cases that demand it. Plus, understanding unwinding is really complex and involves lots of grungy platform details. This is a perfect recipe for inaction. This year the ffi-unwind project group finally took the time to dive into the options and make a proposal, resulting in [RFC 2945] (which now has a [pending implementation PR](https://github.com/rust-lang/rust/pull/76570)). Hat tip to [Amanieu], [BatmanAoD], and [katie-martin-fastly] for their work on this.

[katie-martin-fastly]: https://github.com/katie-martin-fastly
[RFC 2945]: https://github.com/rust-lang/rfcs/pull/2945
[Amanieu]: https://github.com/Amanieu
[BatmanAoD]: https://github.com/BatmanAoD

<a name="never"></a>
### Progress on never-type

Stabilizing the never type (`!`) is another of those long-standing endeavors that keeps getting blocked by one problem or another. Over the last few months I spent some time working with [blitzerr](https://github.com/blitzerr/) to create a [lint for tainted fallback](https://github.com/rust-lang/rust/issues/66173). We succeeded in writing the lint, but found it opened up some new issues, which gave rise to a fresh idea for how to approach fallback which I implemented in [#79366]. I haven't had time to revisit this since we did a crater run to assess impact, but I'm hopeful that we'll be able to finally stabilize the never type in 2021.

[#79366]: https://github.com/rust-lang/rust/pull/79366

<a name="async"></a>
### Progress on Async Rust

tmandry has been leading the "async foundations working group" for some time. The group has been slowly expanding its focus from polish and fixing bugs towards new RFCs and efforts:

* nellshamrell opened an RFC [stabilizing the `Stream` trait](https://github.com/rust-lang/rfcs/pull/2996), currently in "pre-FCP", and yoshuawuyts opened a [PR with an unstable implementation](https://github.com/rust-lang/rust/pull/79023)
* blgBV and LucioFranco opened an [RFC for a "must not await" lint](https://github.com/rust-lang/rfcs/pull/3014) to help catch values that are live across an await, but should not be
* while this is not an "async"-specific effort, sfackler landed an RFC for [reading into uninitialized buffers](https://github.com/rust-lang/rfcs/pull/2930), which potentially unlocks progress on `AsyncRead`, as [he and I discussed in our async interview](https://smallcultfollowing.com/babysteps/blog/2020/01/20/async-interview-5-steven-fackler/)
* continued smaller stabilizations of useful bits of functionality, like [`core::future::ready`](https://github.com/rust-lang/rust/pull/74328)

In general, I thought the [Async Interviews](https://smallcultfollowing.com/babysteps/blog/2019/11/22/announcing-the-async-interviews/) were a good experience, and I'd like to do more things like that as a way to dig into technical questions. (I actually have one interview that I never got around to publishing -- oops. I should do that!)

### Conclusion and some personal thoughts

Well, the end of 2020 is coming up quick. We did it. I want to wish all of you a happy end of the year, and encourage everyone to relax and take it easy on yourselves. Despite all odds, I think it's been a pretty good year for Rust. People who know me know that I have a hard time feeling "satisfied"[^working]. I don't like to count chickens, and I tend to think things will go wrong[^todo]. Well, as of this year, even **I** can plainly see that "Rust has made it". Every day I am learning about new uses for Rust. This isn't to say we're done, there's still plenty to do, but I think we can really take pride in having achieved what initially seemed impossible: launching a new systems programming language into widespread use.

[^working]: Working on it.
[^todo]: The major exception is when I am preparing my To Do list. In that case, I seem to think that nothing unexpected ever happens and there are 72 hours in the day.

### Footnotes
