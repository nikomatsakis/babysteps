---
layout: post
title: Stability without stressing the !@#! out
date: 2023-09-18 11:04 -0400
---

One of Rust's core principles is ["stability without stagnation"](https://doc.rust-lang.org/book/appendix-07-nightly-rust.html#stability-without-stagnation). This is embodied by our use of a ["release train"](https://doc.rust-lang.org/book/appendix-07-nightly-rust.html#choo-choo-release-channels-and-riding-the-trains) model, in which we issue a new release every 6 weeks. Release trains make releasing a new release a "non-event". Feature-based releases, in contrast, are super stressful! Since they occur infrequently, people try to cram everything into that release, which inevitably makes the release late. In contrast, with a release train, it's not so important to make any particular release -- if you miss one deadline, you can always catch the next one six weeks later. *That's the theory, anyway:* but I've observed that, in practice, stabilizing a feature in Rust can still be a pretty stressful process. And the more important the feature, the more stress. This blog post talks over my theories as to why this is the case, and how we can tweak our processes (and our habits) to address it.

## TL;DR

I like to write, and sometimes my posts get long. Sorry! Let me summarize for you:

* Stabilization designs in Rust are stressful because they are conflating two distinct things: "does the feature do what it is supposed to do" (semver-stability) and "is the feature ready for general use for all its intended use cases" (recommended-for-use).
* Open source works incrementally: to complete the polish we want, we need users to encounter the feature; incremental milestones help us do that.
* Nightly is effective for getting some kinds of feedback, but not all; in particular, production users and library authors often won't touch it. This gives us less data to work with when making high stakes decisions, and it's a problem.
* We should modify our process to distinguish four phases
    * **Accepted RFC** -- The team agrees idea is worth implementing, but it may yet be changed or removed. Use at your own risk. (Nightly today)
    * **Preview** -- Team agrees feature is ready for use, but wishes more feedback before committing. We reserve the right to tweak the details, but will not remove functionality without some migration path or workaround. (No equivalent today)
    * **Stable** -- Team agrees feature is done. Semantics will no longer change. Implementation may lack polish and may not yet meet all its intended use cases (but should meet some). (Stable today)
    * **Recommended** -- everyone should use this, it rocks. :guitar:  (No equivalent today, though some would say stable)
* I have an initial proposal for how we could implement these phases for Rust, but I'm not sure on the details. The point is more to identify this as a problem and start a discussion on potential solutions, rather than to drive a particular proposal.

## Context

This post is inspired by years of experience trying to stabilize features. I've been meaning to write it for a while, but I was influenced most recently by the discussion on the PR to [stabilize async fn in trait and return-position impl trait](https://github.com/rust-lang/rust/pull/115822). I'm not intending this blog post to be an argument either way on that particular discussion, although I will be explaining my POV, which certainly has bearing on the outcome.

I will zoom out though and say that I think the Rust project needs to think about the whole "feature design lifecycle". This has been a topic for me for years -- just search for "adventures in consensus" on this blog. I think in the past I've been a bit too ambitious in my proposals[^many], so I'm thinking now about how we can move more incrementally. This blog post is one such example.

[^many]: A critique which many people pointed out to me at the time. 

## Summary of Rust's process today

Let me briefly summarize the "feature lifecycle" for Rust today. I'll focus on language features since that's what I know best: this material is also published on the ["How do I propose a change to the language"](https://lang-team.rust-lang.org/how_to/propose.html) page for the lang-team, which I suspect most people don't know exists[^howdoi].

[^howdoi]: The whole "How do I..." section on the page has some interesting things, if you're looking to interact with the lang team!

The path is roughly like this:

* **Author an RFC** that outlines the problem to be solved and the key aspects of your solution. The RFC doesn't have to have everything figured out, especially when it comes to the implementation -- but it should describe most everything that a user of the language would have to know. The RFC can include **"unresolved questions"** that lay out corner cases or things where we need more experience to figure out the right answer. 
    * Generally speaking, to avoid undue maintenance burden, we don't allow code to land until there is an accepted RFC. There is an exception though for experienced Rust contributors, who can create an experimental feature gate to do some initial hacking. That's sometimes useful to prove out designs.[^why]
* **Complete the implementation** on master. This should force you to work out answers to the all **unresolved questions** that came up in the RFC. Often, having an implementation to work with also leads to other changes in the design. Presuming these are relatively minor, these changes are discussed and approved by the lang team on issues on the rust-lang repository.
* **Author a stabilization report**, describing precisely what is being stabilized along with how each unresolved question was resolved.

[^why]: The decision to limit in-tree experimentation to experienced contributors was based on our experience with the earlier initiative system, where we were more open-ended. We found that the majority of those projects never went anywhere. Most of the people who signed up to drive experiments didn't really have the time or knowledge to move them independently, and there wasn't enough mentoring bandwidth to help them make progress. So we decided to limit in-tree experimentation to maintainers who've already demonstrated staying power.

## Observation: Stabilization means different things to different people.

In a technical sense, stabilization means exactly one thing: the feature is now available on the stable release, and hence **we can no longer make breaking changes to it**[^caveats].

[^caveats]: [RFC 1122](https://github.com/rust-lang/rfcs/blob/master/text/1122-language-semver.md) lays out the lang team's definition of "breaking change", which is not *quite* the same as "your code will always continue to compile". For example, we sometimes change the rules of inference; we also introduce or modify the behavior of lints (which can cause code that has `#[deny]` to stop compiling). Finally, we reserve the right to fix soundness bugs. And, in rare cases, we will override the policy altogether, if a feature's design is so broken, but the bar for that is quite high.

But, of course, stabilization also means that the feature is going to be encountered by users. Rust has always prided itself on holding a high bar for polish and quality, as reflected in how easy cargo is to use, our quality error messages, etc. There is always a concern when stabilizing a long-awaited feature that users are going to get excited, try it out, encounter rough edges, and conclude from this that Rust is impossible to use.

## Observation: Open source works incrementally

Something I've come to appreciate over time is that open source is most effective if you work **incrementally**. If you want people to contribute or to provide meaningful feedback, you have to give them something to play with. Once you do that, the pace of progress and polish increases dramatically. It's not magic, it's just people "scratching their own itch" -- once people have a chance to use the feature, if there is a confusing diagnostic or other similar issue, there's a good chance that somebody will take a shot at addressing it.

In fact, speaking of diagnostics, it's pretty hard to write a good diagnostic *until* you've thrown the feature at users. Often it's not obvious up front what is going to be confusing. If you've ever watched [Esteban](https://github.com/estebank) at work, you'll know that he scans all kinds of sources (github issues, twitter or whatever it's called now, etc) to see the kinds of confusions that people are having and to look for ideas on how to explain them better.

## Observation: Incremental progress boosts morale

The other big impact of working incrementally is for morale. If you've ever tried to push a big feature over the line, you'll know that achieving milestones along the way is **crucial**. There's a huge difference between trying to get everything perfect before you can ship and saying: "ok, this part is done, let's get it in people's hands, and then go focus on the next one". This is both because it's good to have the satisfaction of a job well done, and because stabilization is the only point at which we can **truly** end discussion. Up until stabilization is done, it's always possible to stop and revisit old decisions.[^separate]

[^separate]: One of the things I am proud of about the Rust project is that we *are* willing to stop and revisit old decisions -- I think we've dodged a number of bullets that way. At the same time, it's exhausting. I think there's more to say about finding ways to enable conversation that are not as draining on the participants, and especially on the designers and maintainers, but that's a topic for another post.

## Observation: Working incrementally has a cost

Obviously, I am a big of working incrementally, but I won't deny that it has a cost. For every person who encounters a bad diagnostic and gets inspired to open a PR, there are a lot more who will get confused. Some portion of them will walk away, concluding "Rust is too confusing". That's a problem.

## Observation: A polished feature has a lot of moving parts

A polished feature in Rust today has a lot of moving parts...

* a thoughtful design
* a stable, bug free implementation
* documentation in the Rust reference
* quality error messages
* tooling support, such as rustfmt, rustdoc, IDE, etc

...and we'd like to add more. For example, we are working on various Rust formalizations ([MiniRust](https://github.com/RalfJung/minirust), [a-mir-formality](https://github.com/rust-lang/a-mir-formality)) and talking about upgrading the Rust reference into a normative specification. 

## Observation: Distinct skillsets are required to polish a feature

One interesting detail is that, often, completeing a polished feature requires the work of different people with different skillsets, which in turn means the involvement of many distinct Rust teams -- in fact, when it comes to development tooling, this can mean the involvement of distinct projects that aren't even part of the Rust org! 

Just looking at language features, the *design*, for example, belongs to the lang-team, and often completes relatively early through the RFC process. The implementation is (typically) the compiler team, but often also more specialized teams and groups, like the types team or the diagnostics working group; RFCs can sometimes languish for a long time before being implemented. Documentation meanwhile is driven by the [lang-docs](https://www.rust-lang.org/governance/teams/lang#lang-docs%20team) team (for language features, anyway). Once that is done, the rustfmt, rustdoc, and IDE vendors also have work to do incorporating the new feature.

One of the challenges to open-source development is coordinating all of these different aspects. Open source development tends to be *opportunistic* -- you don't have dedicated resources available, so you have to do a balancing act where you adapt the work that needs to get done to the people that are available to do it. In my experience, it's neither top down nor bottom up, but a strange mixture of the two.[^tdbu] 

[^tdbu]: That said, my experience is that Amazon works in a surprisingly similar way -- there are top-down decisions, but there are an awful lot of bottom-up ones. I imagine this varies company to company, but I think ultimately every good manager tries to ensure that their people are working on things that are well-suited to their skills.

Because of the opportunistic nature of open-source development, some parts of a feature move more quickly than others -- often, the basic design gets hammered out early, but implementation can take a long time. Sadly, the reference is often the hardest thing to catch up, in part because the rather heroic [Eric Huss](https://github.com/ehuss) does not implement the `Clone` trait. 💜

## Observation: Polished features don't stand alone

And yet, to be **truly polished**, features need more than docs and error-messages: they need other features! It often happens that users using feature X will find that, to complete their task, they also need feature Y. This inevitably presents a challenge to our stabilization system, which judges the stability of each feature independently.

Async functions in trait are a great example: the core feature is working great on stable, but we haven't reached consensus on a solution to the [send bound problem][sbp]. For some users, like embedded users, this doesn't matter at all. For others, like Tower, this is a pretty big problem. So, do we hold back async function in traits until both features are ready? Or do we work incrementally, releasing what is ready *now* and then turning to focus on what's left?

[sbp]: https://smallcultfollowing.com/babysteps/blog/2023/02/01/async-trait-send-bounds-part-1-intro/

!["We seem to have been designed for each other" -- Mr Collins.](https://media.giphy.com/media/l4JyKQhSRBExNYzkc/giphy.gif)

## Observation: Nightly is just the beginning

I can hear readers saying now, "but wait, isn't this what Nightly is for?" And yes, in principle, the nightly release is our vehicle for enabling experimentation with in-progress features. Sometimes it works great! It can be a great way to get ahead of confusing error messages, for example, or to flush out bugs. But all too often, Nightly is a big barrier for people, particularly production Rust users or those building widely used libraries. And those are precisely the users whose feedback would be most valuable.

What's interesting is that many production users would be willing to tolerate a certain amount of instability. Many users tell me they wouldn't mind rebasing over small changes in the feature design[^cf], but what they can't tolerate is building a codebase around a feature and then having it removed entirely, or having dropped support for major use cases without some kind of workaround.

[^cf]: Many of which could be automated via [`cargo fix`](https://doc.rust-lang.org/cargo/commands/cargo-fix.html)!

Libraries are another interesting story. Library authors tend to be more advanced than your typical Rust user. They can tolerate a lack of polish in exchange for having access to a feature that lets them build a nicer experience for their users. Generic associated types are a clear example of this. One of the big arguments in favor of stabilizing them was that they often show up in the *implementation* of libraries but not in the *outward interfaces*. As one personal example, we've been using them extensively in [Duchess](https://duchess-rs.github.io/duchess/), an experimental library for Java-Rust interop, and yet you won't find any mention of them in the docs. Do we sometimes hit confusing errors or other problems? Yes. Is the syntax annoyingly verbose? Yes, absolutely. Am I glad they are stabilized? **Hell yes.**

## Observation: having users help us figure out what else is needed

Remember how I said that it was hard to design quality diagnostics until you had seen the ways that users got confused? Well, the same goes for designing related features. Once production users or library authors start playing with something, they find all kinds of clever things they can do with it -- or, often, things they could *almost* do, except for this one other missing piece. In this way, holding things unstable on Nightly -- which means far fewer users can touch it -- holds back the whole pace of Rust development significantly.

## Prior art

### Ember's feature lifecycle

The Ember and Rust projects have long had a lot of fruitful back-and-forth when it comes to governance and process, thanks in part to the fact that Yehuda Katz was deeply involved in both of them. In 2022, they adopted a [revised RFC process](https://blog.emberjs.com/improved-rfc-process/) in which each feature goes through a number of stages:[^wagenet]

0. Proposed -- An open pull request on the emberjs/rfcs repo.
1. Exploring -- An RFC deemed worth pursuing but in need of refinement. 
2. Accepted -- A fully specified RFC.
3. Ready for release -- The implementation of the RFC is complete, including learning materials.
4. Released -- The work is published. 
5. Recommended -- The feature/resource is recommended for general use. 

[^wagenet]: Speaking of Ember-Rust cross-polination, Peter Wagenet, co-author of the [Ember release blog post](https://blog.emberjs.com/improved-rfc-process/), also hacks on the Rust compiler from time to time.

This is pretty cool! One other interesting aspect for Ember is how they approach [editions](https://emberjs.com/editions/). Remember I talked about how features don't stand alone? In Ember, a significant cluster of related features is called an "edition". New editions are declaed when all the pieces are in place to enable a new model for programming. This is pretty distinct from Rust's time-based editions.

I'm not totally sure how to map Ember's edition to Rust, but I think that the concept of an "umbrella initiative" is pretty close. For example, the [async fundamentals initaitive roadmap](https://rust-lang.github.io/async-fundamentals-initiative/roadmap.html) identifies a cluster of related work that together constitute "async-sync language parity" -- i.e., you can truly use async operations everywhere you would like to.

One interesting aspect of Ember's editions is that they often begin by stabilizing "primitives" -- e.g., fundamental APIs that aren't really meant for end-users, but rather for plugin authors or people in the ecosystem, who can use them to experiment with the right end-user abstractions. I've found in Rust that we sometimes do this, though sometimes we find it better to begin with the end-user abstraction, and expose the primitives later. 

### The TC39 process for ECMAScript

The TC39 committee has a [nice staged process](https://github.com/tc39/how-we-work/blob/main/champion.md). It's not exactly comparable to Rust, but there are few things worth observing. First, I love the designation of a *champion* for a feature, and I think Rust would benefit from being more official about that in some ways. Second, I also love the [explainer](https://github.com/tc39/how-we-work/blob/main/explainer.md) concept of authoring user documentation as part of the process. Third, before they stabilize, they always make the feature available to end-users, but under gates. 

### Java's preview features

Ever since [JEP-12], Java has included **preview features** in their release process. A preview feature is one that is "fully specified, fully implemented, and yet impermanent" -- it's released for feedback, but it may be removed or changed based on the result of the evaluation. The motivation is to get more feedback on the design before committing to it:

> To build confidence in the correctness and completeness of a new feature -- whether in the Java language, the JVM, or the Java SE API -- it is desirable for the feature to enjoy a period of broad exposure after its specification and implementation are stable but before it achieves final and permanent status in the Java SE Platform.

When using preview features, users *opt-in* both at compilation time *and* at runtime. In other words, if you compile a Java file that uses preview features to a JAR, and distribute the JAR, people using the JAR must also opt-in.

## Proposal

Instead of rehashing the same debate every time we go to stabilize a feature, I think we should look at our feature release process so that we have more *gradations* of stability:

* **accepted RFC** -- With an accepted RFC, the team has agreed that we want the feature in principal. However, the details often change during development, and may even be removed. Use at your own risk.
* **preview** -- We are commited to keeping this functionality in some form, but we reserve the right to make changes. We won't remove functionality from preview state without some kind of workaround. You can use this feature so long as you are willing to update your code when moving to a new version of the compiler. **Preview features must be viral**, meaning that if I build a crate using preview features, consumers must opt-in to the resulting instability *somehow*.
* **semver stable** -- We have committed to the technical design of this feature and people can build on it without fear of breakage between compiler revisions. The experience may lack polish and some intended use cases may not yet be possible.
* **recommended for use** -- This feature has all the documentation, error messages, and associated features that are needed for most Rust users to be successful. USE IT!

**Comparison with today's release trains.** In our system today, the first three phases are both covered by "nightly" and the latter two are both covered by "stable", but of course we don't draw any formal distinctions. Async function in trait, for example, is clearly past the **accepted RFC** phase and is now in **preview**: the team is committed to shipping it in some form, and we don't expect any major changes. But how would you know this, if you aren't closely following Rust development? Generic associated types, meanwhile, are clearly **semver stable** rather than **recommended for use** -- we know of many major gaps in the experience, mostly blocked on the [trait system refactor initiative](https://github.com/rust-lang/trait-system-refactor-initiative/), but how would you know *that*, unless you were actively attending Rust types team meetings?

## Unresolved questions

I am confident that these four phases are important, but there are a number of details of which I am *not* sure. Let me pose some of the questions I anticipate here.

### How committed should we be to preview features?

In my proposal above, I said that the project would not remove functionality without a workaround. This is somewhat stronger than [JEP-12][], which indicates that preview features "will either be granted final and permanent status (with or without refinements) or be removed". I said something somewhat stronger because I was thinking of production users. I know many such users would happily make use of preview features, and they are willing to make updates, but they don't want to get stuck having based their codebase on something that completely goes away. I feel pretty confident that by the time we get to preview state, we should be able to say "yes, we want *something* like this". I think it's fine however if the feature gets removed in favor, say, of a procedural macro or some other solution, so long as the people using that preview feature has somewhere to go. (Naturally, my preference would be to provide as smooth a path as possible between compiler revisions; ideally, we'd issue automatable suggestions using [cargo fix], similar to what we do for editions.)

[cargo fix]: https://doc.rust-lang.org/cargo/commands/cargo-fix.html

### How should the features be reflected in our release trains?

I don't entirely know! I think there are a lot of different versions. I do know a few things:

* **Instability should be viral, whether experimental or preview:** today, if I depend on a crate that uses nightly features, I must use nightly myself; this falls out from the fact that Rust doesn't support binary distribution, but is very much intentional. The reason is that a crate cannot truly "hide" instability from its users. They can always upgrade to a new version of Rust and, if that causes the crate to stop compiling, they will perceive this as a failure of Rust's promise, even it is a result of the crate having used an unstable feature. We need to do the same kind of viral result for preview features.
* **Preview and stabilized features need to be internally consistent, but not complete or fully polished:** Preview features need to meet a certain quality bar -- e.g., support in rustfmt, adequate documentation -- but it's fine for them to be a subset of what we hope to do in the fullness of time. It's also ok for them to have less-than-ideal error messages. Those things come with time. 
* **Documentation is key:** A big challenge for Rust today is that we don't have a canonical way for people to find out the status of the things they care about. I think we should invest some effort in setting up a consistent format with bot/tooling support to make it easy to maintain. Users will understand the idea that a feature is unpolished *if* you can direct them to a page where they can understand the context and learn about the workarounds they need in the short term.

With that in mind, here is a possible proposal for how we might do this:

* Initially, **features are nightly only**, as today, and require an individual feature-gate. 
    * Until there is an accepted RFC, we should have a mandatory warning that the team has not yet decided if the feature is worth including; we also can continue to warn for features whose implementation is very incomplete.
* **Preview features** are usable on **stable**, but with opt-in:
    * Every project that uses any preview features, or which depends on crates that use preview features, must include `preview-features = true` in their `Cargo.toml`.
    * Every crate that directly uses preview features must additionally include the appropriate feature gates.
    * Reaching preview status should require some base level of support
        * core tooling, e.g. rustfmt, rustdoc, must work
        * an explainer must be available, but Rust reference material is not required
        * a nice landing page (or Github issue with known format) that indicates how to provide feedback; this page should also cover polish or supporting features that are known to be missing (similar to the [async fn fundamentals roadmap][roadmap])
        * the feature must be "complete enough" to meet some of its intended use cases; it doesn't have to meet *all* of its intended use cases.
    * This is an FCP decision, because it is commits the Rust project to supporting the use cases targeted by the preview feature (if not the details of how the feature works).
* **Semver stable features** features are usable on stable, but we make efforts to redirect users to the landing page have a landing page that outlines what kind of support is still missing and how to provide feedback.
    * Reaching semver stable requires an update to the Rust reference, in addition to the requirements for preview.
    * The feature must be "complete enough" to meet some of its intended use cases; it doesn't have to meet *all* of its intended use cases.
    * This is an FCP decision, because it is commits the Rust project to supporting the feature in its current form going forward.
* **Recommended for use** features would be just as today.
    * The feature must meet all of the major use cases, which may mean that other features are present.


## Other frequently asked questions and alternatives

Here are answers to a few other questions I anticipate.

### Who will maintain these "landing pages"?

This is a good question! It's easy for these to get out of date. I think part of designing this 'preview' process should also be investing in a standard template for the landing pages and some guidelines. My sense is that people would be happy to update landing pages as part of the stabilization process if it meant they can make progress on shipping the feature they've worked so hard to build! But I think we can do a lot to make it easier. Having a standard format would also mean that users can find the information they're looking for more easily. We can then also build bots and things to help. I've seen that investing in bots can make a real difference.

### How will we ensure polish gets done?

One concern that is commonly raised is that stabilization is the only gate we have to force polish work to get done. I agree that we should maintain a certain quality bar as features move towards being fully recommended. But I think that saying "we cannot ship something for widespread use until it is polished" misses the point that open-source is incremental. In other words, part of the *way that features get polished* is by releasing them for widespread use. 

Definitely though the Rust project can do a better job of tracking and ensuring that we do the follow-up items. There are plenty of examples of follow-up that never gets done. But I don't think blocking stabilization is an effective tool for that. If anything, it's demoralizing[^quit]. We really need to strengthen our project management skills -- pushing people to create better landing pages and to help identify the gaps more crisply feels like it can help, though more is needed.

[^quit]: There's nothing worse than investing months and months of work into getting something ready for stabilization, endlessly triaging issues, only to open a stabilization PR -- the culmination of all that effort -- and have the first few comments tell you that your work is not good enough. Oftentimes the people opening those PRs are volunteers, as well, which makes it all the worse.

### Why would we stabilize a feature if we know users will hit gaps?

Most features in Rust serve a lot of purposes. Even if we know about major gaps, there are often important blocks of users who are not affected by them. For async functions in traits, the [send bound problem][sbp] can be a total blocker -- but it's also a non-issue for a lot of users. I would like to see us focus more on how we can alert users to the gaps they are hitting rather than denying them access to features until everything is done.

### I thought you said you wanted to move incrementally? This feels like a big step.

Earlier, I said that I wanted to look for incremental ways to tweak Rust's process, since in the past I've gotten too ambitious. In truth, I think this blog post is really laying out *two* proposals, so let me separate them out:

* Part 1: Semver-stable vs recommended-for-use
    * The most immediate need is to clarify what stabilization means and what exactly is the "bar"; in my opinion, that is semver stability, and I think there is plenty of precedent for that.
    * But I think the risk of user confusion is very real, and we can take some simple steps to help mitigate it, such as creating good landing pages and having the compiler direct users to them when it thinks they may be encountering a gap.
        * Example: today if you try to use an async fn in a trait, you get directed to the `async-trait` crate. We can detect "send bound"-related failures and direct users to a github issue that explains how they can resolve it and also gives them a way to register interest or provide feedback.
    * I don't think anything is really blocking us from moving forward here immediately, though an RFC might be nice at some point to clarify terminology and help align the way we talk about this.
* Part 2: Preview features
    * Preview features is really a distinct concept, but I do think it's important. For example, we could have declared async functions in traits as a 'preview feature' over a year ago. This would have given us a lot more data and made it accessible to a much broader pool of people. I think this would have given us a clearer picture on how important the 'send bound' problem is, for example, and would inform other prioritization efforts.
    * Moving forward here will require an RFC and also implementation work.

## Conclusion

With [apologies to Jane Austen](http://www.literaturepage.com/read/prideandprejudice-34.html):

> "All Rust features are so accomplished. They all have stable semantics and even make helpful suggestions when you go astray. I am sure I never encountered a Rust feature without being informed that it was very accomplished."
>
> "Your list of the common extent of accomplishments," said Darcy, "has too much truth. The word is applied to many a feature who deserves it no otherwise than by being stabilized. But I am very far from agreeing with you in your estimation of Rust features in general. I cannot boast of knowing more than half-a-dozen, in the whole range of my acquaintance, that are really accomplished."
>
> "Then," observed Elizabeth, "you must comprehend a great deal in your idea of an accomplished feature."
>
> "Oh! certainly," cried his faithful assistant, "no feature can be really esteemed accomplished without strong support in the IDE, wondorous documentation, and perhaps a chapter in the Rust book."
>
> "All this it must possess," added Darcy, "and to all this it must yet add something more substantial: a host of related features that address common problems our users may encounter."
>
> "I am no longer surprised at your knowing ONLY six accomplished features. I rather wonder now at your knowing ANY."

To translate: I think our 'all or nothing' stability system is introducing unnecessary friction into Rust development. Let's change it!

---

