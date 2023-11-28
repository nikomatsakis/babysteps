---
title: "Project Goals"
date: 2023-11-28T10:43:59-05:00
---

Lately I've been iterating on an idea I call **project goals**. **Project goals** are a new kind of RFC that defines a specific goal that a specific group of people hope to achieve in a specific amount of time -- for example, _"Rusty Spoon Corp proposes to fund 2 engineers full time to stabilize collections that support custom memory allocations by the end of 2023"_.

Project goals would also include asks from various teams that are needed to complete the goal. For example, _"Achieving this goal requires a dedicated reviewer from the compiler team along with an agreement from the language design team to respond to RFCs or nominated issues within 2 weeks."_ The decision of whether to accept a goal would be up to those teams who are being asked to support it. If those teams approve the RFC, it means they agree with the goal, and also that they agree to commit those resources.

**My belief is that project goals become a kind of incremental, rolling roadmap, declaring our intent to fix specific problems and then tracking our follow-through (or lack thereof).** As I'll explain in the post, I believe that a mechanism like project goals will help our morale and help us to get shit done, but I also think it'll help with a bunch of other ancillary problems, such as providing a clearer path to get involved in Rust as well as getting more paid maintainers and contributors.

At the moment, project goals are just an idea. My plan is to author some sample goals to iron out the process and then an RFC to make it official.

<!--more-->

## Driving a goal in the Rust project is an uncertain process

Rust today has a lot of half-finished features waiting for people to invest time into them. But figuring out how to do so can be quite intimidating. You may have to trawl through github or Zulip threads to figure out what's going on. Once you've done that, you'll likely have to work through some competing constraints to find a proposed solution. But that stuff isn't the real problem. The real problem is that, once you've invested that time and done that work, **you don't really know whether anyone will care enough about your work to approve it**. There's a good chance you'll author an RFC, or a PR, and nobody will even respond to it.

Rust teams today often operate in a fairly reactive mode, without clear priorities. The official Rust procedures are almost exclusively 'push', and often based on evaluating *artifacts*, not intentions -- people decide a problem they would like to see solved, and write an RFC or a PR to drive it forward; the teams decide whether to accept that work. But there is no established way to get feedback from the team on whether this is a problem -- or an approach the problem -- that would be welcome. Or, even if the team does theoretically want the work, there is no real promise from the team that they'll respond or accountability when they do not.

We do try to be proactive and talk about our goals. Teams sometimes post lists of aspirations or roadmaps to to Inside Rust, for example, and we used to publish annual roadmaps as a project. But these documents have never seemed very successful to me. **There is a fundamental tension that is peculiar to open source: the teams are not the ones doing the work.** Teams review and provide feedback. Contributors do the work, and ultimately they decide what they will work on (or if they will do work at all). It's hard to plan for the kinds of things you will do when you don't know what resources you have. A more reliable barometer of the Rust project's priorities has been to read the personal blogs doing the work, where people are talking about the goals they personally plan to drive.

## This uncertainty holds back investment

The uncertainty involved in trying to push an idea forward in Rust is a major deterrent for companies thinking about investing in Rust. I hear about this gap from virtually every angle:

* Imagine you're a a developer who wants to use paid time to work on open source. How do you convince your manager it makes sense? Right now, the best you can do is I think I can make progress, and besides, it's the right thing to do!"
* Imagine you're a contractor who wants to deliver for a client. They want to pay you to help drive a feature over the finish line -- but you can't be sure if you're going to be able to deliver, since it will require consensus from a Rust team, and it's unclear whether it meets their priorities.
* Imagine you're a CTO considering whether to adopt Rust for your company. You see that there are gaps in an area, but you don't know whether that is something the project is actively looking to close, or what.
* Or maybe you're a CTO who has adopted Rust and is looking to "give back" to the community by contributing. You want to help deliver support for a feature you need and that you know a lot of people in the community would like, but you can't figure out how to get started, and you can't afford to have an engineer or two work on something for months without a return.

## But some things work really well and we don't want to lose those

Rust's development may be chaotic, but there's a beauty to it as well. As Mara's classic blog post put it, ["Rust is not a company"](https://blog.m-ou.se/rust-is-not-a-company/). Rust's current structure allows for a feature to make progress in fits and starts, which means we can accommodate all kinds many different interest levels and motivation. Someone who is motivated can author and contribute an RFC, and then disappear. Somebody else can pick up the ball and move the implementation forward. And yet a third person can drive the docs and stabilization over the finish line. This is not only cool to watch, it also means that some features get done that would never be "top priority". Consider `let-else` -- this is one of the most popular features from the last few years, and yet, compared against core enabled like "async fn in trait", it clearly takes second place in the priority list. But that's fine, there are plenty of folks who don't have the time or expertise to work on async fn in trait, but they can move `let-else` forward. **It's really important to me that we don't lose this.**

## Proposal: project goal RFCs

So, top-down roadmaps are a poor fit for open-source. But working purely bottom-up has its own downsides. What can we do?

My proposal is to form roadmaps, but to do it bottom-up, via a new kind of RFC called a **project goal RFC**. A regular RFC proposes a solution to a problem. A project goal RFC proposes a **plan to solve a particular problem in a particular timeframe**. This could be specific, like *"stabilize support for async closures in 2024"*, or it could be more general, like *"land nightly support for managing resource cleanup in async functions in 2024"*. What it can't be is non-actionable, such as *"simplify async programming in 2024"* or *"make async Rust nice in 2024"*.

Project goal RFCs are opened by the **goal owners**, the people proposing to do the work. They are approved by the **teams** which will be responsible for approving that work.[^theory] The RFC serves as a kind of **contract**: the owners will drive the work and the team will review that work and/or provide other kinds of support (such as mentorship).

[^theory]: In theory, anyway. In practice, I imagine that many team maintainers may keep some draft project goal RFCs in their pocket, looking for someone willing to do the work.

### Project goal RFCs are aimed squarely at larger projects

Project goal RFCs are not appropriate for all projects. In fact, they're not appropriate for *most* projects. They are meant for larger, flagship projects, the kind where you want to be sure that the project is aligned around the goals before you start investing heavily. Here are some examples where I think project goal RFCs would be useful...

* The async WG [set an "unofficial" project goal of shipping async functions in traits this year](https://blog.rust-lang.org/inside-rust/2023/05/03/stabilizing-async-fn-in-trait.html) ([coming Dec 28!](https://github.com/rust-lang/rust/pull/115822)). Honestly, setting a goal like this felt a bit uncomfortable, as we didn't have a means to make it "official and blessed". I think that would have also helped  during the push to stabilization, since we could reference this goal to help make the case for "time to ship".
* Goals might also take the shape of internal improvements. The types team is driving a flagship goal to ship a new trait solver. Authoring a project goal RFC would help bring this visibility and would also make it easier to make the case for funding work on this project.
* I sometimes help to mentor collaborations with people in universities or with Master's students. Project goals would let us set expectations up front about what work we expect to do during that time.
* I'd like to drive consensus around the idea of [easing tradeoffs with profiles](https://smallcultfollowing.com/babysteps/blog/2023/09/30/profiles/) -- but I don't want to start off with an RFC that is going to focus discuss on the details of how profiles are specified. I want to start off by getting alignment around whether to do something like profiles at all. Wearing my Amazon manager hat, having alignment there would also influence whether I allocated some of our team's bandwidth to work on that. A project goal could be perfect for that.
* The Foundation has run several project grant programs, and one of the challenges has been trying to choose projects to fund which will be welcomed by the project. As I've been saying, we don't really have a mechanism for making those sorts of decisions.
* The embedded working group or the Rust For Linux folks have a bunch of pain points. I think it's been hard for us to manage cooperation between those really important efforts and the other Rust teams. Developing a joint project goal would be a way to highlight needs.
* Someone who wants to work on Rust at their company could work with a team to develop an official goal that they can show to their manager to get authorized work time.
* Companies that want to invest in Rust to close gaps could propose project goals. For example, Microsoft recently authored an I frequently get asked how a company can help move custom allocators forward. One candidate that comes up a lot is support for custom allocators or collections with fallible debugging. This same mechanism would also allow larger companies to propose goals that they'd like to drive. For example, there was a [recent RFC on debugger visualization aimed at better support for debugging Rust in Windows](https://rust-lang.github.io/rfcs/3191-debugger-visualizer.html). I could imagine folks from Microsoft proposing some goals in that area.


## Anatomy of a project goal RFC

Project goal RFCs need to include enough detail that both the owners and the teams know what they are signing up for. I believe a project goal RFC should answer the following questions:

* **Why** is this work important?
* **What** work will be done on what **timeframe**?
    * This should include...
        * **milestones** you will meet along the way,
        * **specific use-cases** you plan to address,
        * and **guiding principles** that will be used during design.
* **Who** will be doing the work, and how much time will the have?
* What **support** is needed and from which Rust teams?

The list above is intentionally somewhat detailed. **Project goal RFCs are not meant to be used for everything.** They are meant to be used for goals that are big enough that doing the planning is worthwhile. The planning also helps the owners and the teams set realistic timelines. (My assumption is that the first few project goals we set will be wildly optimistic, and over time we learn to temper our expectations.)

### **Why** is this work important?

Naturally whenever we propose to do something, it is important to explain **why** this thing is worth doing. A quality project goal will lay out the context and motivation. The goal is for the owners to explain to the team why the team should dedicate their maintenance bandwidth to this feature. It's also a space for the owners to explain to the world why they feel it's worth their time to do the work to develop this feature.

### What will be done and on what timeframe?

The heart of the project goal is declaring what work is to be done and when it will be done by. It's important that this "work to be done" is specific enough to be evaluated. For example, _"make async nice next year"_ is not a good goal. Something like _"stabilize async closures in 2024"_ is good. It's also ok to just talk about the problem to be solved, if the best solution isn't known yet. For example, _"deliver nightly support for managing resource cleanup in async programs in 2025"_ is a good goal that could be solved by ["async drop"][] but also by some other means.

#### Scaling work with timeframes and milestones

Goals should always include a **specific timeframe**, such as "in 2024" or "in 2025". I think these timeframes will typically be about a year. If the time is too short, then the work is probably not significant enough to call it a goal. But if the timeframe is much longer than a year, then it's probably best to scale back the "work to be done" to something more intermediate.

Of course, many goals will be part of a bigger project. For example, if one took a goal to deliver nightly support for something in 2024, then the next year, one might propose a goal to stabilize that support. 

Ideally, the goal will also include **milestones** along the way. For example, if the goal is to have something stable in 1 year, it might begin with an RFC after 3 months, then 3 months of impl, 3 months of gaining experience, and 3 months for stabilization.

#### Pinning things down with use-cases

Unlike a feature RFC, a project goal RFC does not specify a precise design for the feature in question. Even if the project goal is something relatively specific, like "add support for async functions in traits", there will still be a lot of ambiguity about what counts as success. For example, we decided to stabilize async functions in traits without support for [send bounds][sb]. This means that some use cases, notably a crate like [tower](https://crates.io/crates/tower), aren't supported yet. Does this count as success? To help pin this down, the project goal should include a list of use cases that it is trying to address. 

[sb]: https://smallcultfollowing.com/babysteps/blog/2023/02/01/async-trait-send-bounds-part-1-intro/

#### Establishing guiding principles early

Finally, especially when goals involve a fair bit of design leeway, it is useful to lay down some of the guiding principles the goal owners expect to use. I think having discussion around these principles early will really help focus discussions later on. For example, when discussing how dynamic dispatch for async functions in traits should work, Tyler Mandry and I had an [early goal that it should "just work" for simple cases](https://smallcultfollowing.com/babysteps/blog/2021/09/30/dyn-async-traits-part-1/) but give the ability to customize behavior. [But we quickly found that ran smack into Josh's prioritization of allocation transparency.](https://smallcultfollowing.com/babysteps/blog/2022/09/18/dyn-async-traits-part-8-the-soul-of-rust/) This conflict was precictable and I think it would have been useful to have had the discussion around these tenets early as a lang team, rather than waiting.[^profiles]

[^profiles]: The question of how to make `dyn` async traits easy to use *and* transparent remains unresolved, which is partly why I'm keen on something like [profiles](https://smallcultfollowing.com/babysteps/blog/2023/09/30/profiles/).

### **Who** will be doing the work, and how much time will the have?

Part of the goal is specifying who is going to be doing the work. For example, the goal might say "two developers to work at 50% time". It might also say something more flexible, like "one developer to create quest issues and then mentor a group of volunteers to drive most of the work". If possible, including specific names is useful too, particularly in more specialized areas. For example, "Ralf Jung and one graduate student will pursue an official set of rules for stacked borrows".

### What **support** is needed and from which Rust teams?

This section is where the project goal owners make asks of the project. Here are some typical asks that I expect we will have:

* A dedicated reviewer for PRs to the compiler and an expected [SLA] of reviews within 3 days (or 1 week, or something).
* An agreement from the lang team to review and provide feedback on RFCs.
* Mentorship on some aspect or other.

[SLA]: https://en.wikipedia.org/wiki/Service-level_agreement

I think teams should suggest the expected shape of asks and track their resources. For example, the lang team can probably have manage up to only a small number of "prioritized RFCs" at a time, so if there are more project goals, they may have to wait or accept a lower SLA.

## Tracking progress

One of the interesting things about project goals is that they give us an immediate roadmap. I would like to see the project author a quarterly report -- which means every 12 weeks, or two release cycles. This report would include all the current project goals and updates on their progress. Did they make their declared milestones? If not, why not? Because project goals don't cover the entirety of the work we do, the report could also include other significant developments. This would be published on the main Rust blog and would let people follow along with Rust development and get a sense for our current trajectory.

One thing I've learned, though: **you can't require the goal owners to author that blog post**. It would be much better to have a dedicated person or team authoring the blog posts and pinging the goal owners to get those status updates. Preparing an update so that it can be understood by a mass audience is its own sort of skill. Moreover, goal owners will be tempted to put it off, and the updates won't happen. I think it's quite important that these project updates happen every quarter, like clockwork, just as our Rust releases do. This is true even if the update has to ship without an update from some goals.

I envision this progress tracking as providing a measure of accountability. When somebody takes a goal, we'll be able to follow along with their progress. I've seen at Amazon and elsewhere that having written down a goal and declared milestones, and then having to say whether you've met them, helps to keep teams focused on getting the job done. I often find that I have a job about 95% done but then, in the week before I have to write an update about it, I'm inspired to go and finish that last 5%.

## Conclusion: next steps

My next step is that I am going to fashion an RFC making the case for project goals. This RFC will include a template. To try out the idea, I plan to also author an example project goal for "async function in traits" and perhaps some other ongoing or proposed efforts. In truth, I don't think we *need* an RFC to do project goals -- nothing is stopping us from accepting whatever RFC we want -- but I see some value in spelling out and legitimizing the process. I think this probably ought to be approved by the governance council, which is an interesting test for that new group.

There are some follow-up questions worth discussing. One of the ones I think is most interesting is how to manage the quarterly project updates. This deserves a post of its own. The short version of my opinion is that I think it'd be great to have an open source "reporting" team that has the job of authoring this update and others of its ilk. I suspect that this team would work best if we had one or more people paid to participate and to bear the brunt of some of the organizational lift. I further suspect that the Foundation would be a good place for at least one of those people. But this is getting pretty speculative by now and I'd have to make the case to the board and Rust community that it's a good use for the Foundation budget, which I certainly have not done.

It's worth noting that I see project goal RFCs as just one piece of a larger puzzle that is giving a bit more structure to our design effort. One thing I think went wrong in prior efforts was that we attemped to be too proscriptive and too "one size fits all". These days I tend to think that the only thing we *must have* to add a new feature to stable is an FCP-binding decision from the relevant teams(s). All the rest, whether it being authoring a feature RFC or creating a project goal RFC, are steps that make sense for projects of a certain magnitude, but not everything. Our job then should be to lay out the various kinds of RFCs one can write and when they are appropriate for use, and then let the teams judge how and when to request one.