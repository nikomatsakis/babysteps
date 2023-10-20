---
title: 'Idea: "Using Rust", a living document'
date: 2023-10-20T14:29:21-04:00
---

A few years back, the Async Wg tried something new. We collaboratively authored an [Async Vision Doc][avd]. The doc began by writing ["status quo" stories][sq], written as narratives from our [cast of characters][coc], that described how people were experiencing Async Rust at that time and then went on to plan a ["shiny future"][sf]. This was a great experience. My impression was that authoring the "status quo" stories *in particular* was really helpful. Discussions at EuroRust recently got me wondering: **can we adapt the "status quo" stories to something bigger?** What if we could author a living document on the Rust user experience? One that captures what people are trying to do with Rust, where it is working really well for them, and where it could use improvement. I love this idea, and the more I thought about it, the more I saw opportunities to use it to improve other processes, such as planning, public communication, and RFCs. But I'm getting ahead of myself! Let's dive in.

[avd]: https://rust-lang.github.io/wg-async/vision

[sq]: https://rust-lang.github.io/wg-async/vision/submitted_stories/status_quo.html

[sf]: https://rust-lang.github.io/wg-async/vision/shiny_future.html

[coc]: https://rust-lang.github.io/wg-async/vision/characters.html

[ws]: https://smallcultfollowing.com/babysteps/blog/2021/03/22/async-vision-doc-writing-sessions/

## TL;DR

I think authoring a living document (working title: "Using Rust") that collects ["status quo" stories][sq] could be a tremendous resource for the Rust community. I'm curious to [hear from](mailto:rust@nikomatsakis.com) folks who might like to be part of a group authoring such a document, especially (but not only) people with experience as product managers or developer advocates.

## Open source is full of ideas, but which to do?

The Rust open-source organization is a raucuous, chaotic, and, at its best, joyful environment. People are bubbling with ideas on how to make things better (some better than others). There are also a ton of people who want to be involved, but don't know what to do. This sounds great, but it presents a real challenge: **how do you decide which ideas to do?** 

The vast majority of ideas for improvement tend to be incremental. They take some small problem and polish it. If I sound disparaging, I don't mean to be. This kind of polish is **absolutely essential**. It's kind of ironic: there's always been a perception that open source can't build a quality product, but my experience has often been the opposite. Open source means that people show up out of nowhere with PRs that remove sharp edges. Sometimes it's an edge you knew was there but didn't have time to fix; other times it's a problem you weren't aware of, perhaps because of the [Curse of Knowledge][CoK].

[CoK]: https://en.wikipedia.org/wiki/Curse_of_knowledge

But finding those **revolutionary** ideas is harder. To be clear, it's hard in any environment, but I think it's particularly hard in open source. A big part of the problem is that open source has always focused on **coding** as our basic currency. Discussions tend to orient around specific proposals -- that could be as small as a PR or as large as an RFC. But finding a revolutionary idea doesn't start from coding or from a specific idea.

## It all starts with the "status quo"

So how do we go about having more "revolutionary ideas"? My experience is that it begins by **deeply understandly understanding the present moment**. It's amazing how often we take the "status quo" for granted. We assume that we know the problems people experience, and we assume that everybody else knows them too. In reality, we only know the problems that we *personally* experience -- and most of the time we are not even fully aware of those!

One thing [I remember from authoring the async vision doc][swtsq] is **how hard it was to focus on the "status quo"** -- and how rewarding it was when we did! When you get people talking about the problems they experience, the temptation is to *immediately* jump to how to fix the problem. But if you resist that, and you force yourself to just document the current state, you'll find you have a much richer idea of the problem.[^bb] And that richer understanding, in turn, gives rise to better ideas for how to fix it.

[^bb]: If you're hearing resonance of the wisdom of the Buddha, it was not intentional when I wrote this, but you are not alone.

[swtsq]: https://smallcultfollowing.com/babysteps/blog/2021/05/01/aic-vision-docs/#start-with-the-status-quo

## Idea: a living "Using Rust" document

So here is my idea: what if we created a living document, working title "Using Rust", that aims to capture the "status quo" of Rust today:

* What are people building with Rust?
* How are people's Rust experiences influenced by their background (e.g., prior programming experience, native language, etc)?
* What is working well? 
* What challenges are they encountering?

Just as with the Async Vision Doc, I imagine "Using Rust" would cover the whole gamut of experiences, including not just the language itself but tooling, libraries, etc. Unlike the vision doc, I wouldn't narrow it to async (though we might start by focusing on a particular domain to prove out the idea).

Like the vision doc, I imagine "Using Rust" would be composed of a series of vignettes, expressed in narrative form, using a similar [cast of characters][coc][^chars] to the Async Vision Doc (perhaps with variations, like Spanish-speaking Alano instead of Alan).

I personally found the narratives really helpful to get the emotional "heft" of some of the stories. For example, ["Alan started trusting the Rust compiler, but then... async"](https://rust-lang.github.io/wg-async/vision/submitted_stories/status_quo/alan_started_trusting_the_rust_compiler_but_then_async.html) helped drive home the importance of that "if it compiles, it works" feeling for Rust users, as well as the way that panics can undermine it. Even though these are narratives, they can still dive deep into technical details. Researching and writing ["Barbara battles buffered streams"](https://rust-lang.github.io/wg-async/vision/submitted_stories/status_quo/barbara_battles_buffered_streams.html), for example, really helped me to appreciate the trickiness of async cancellation's semantics.[^moro]

[coc]: https://rust-lang.github.io/wg-async/vision/characters.html

[^chars]: The cast of characters may look simple, but developing that cast of characters took a lot of work. Finding a set that is small enough to be memorable but which captures the essentials is hard work. One key insight was separating out the [projects people are building](https://rust-lang.github.io/wg-async/vision/projects.html) from the characters building them, since otherwise you get a combinatorial explosion. 

[^moro]: Async cancellation is an area I deseparately want to return to! I still think we want some kind of structured concurrency like solution. My current thinking is roughly that we want something like [moro](https://github.com/nikomatsakis/moro/) for task-based concurrency and something like Yosh's [merged streams](https://blog.yoshuawuyts.com/futures-concurrency-3/#concurrent-stream-processing-with-stream-merge) for handling "expect one of many possible message"-like scenarios.

I don't think "Using Rust" would ever be finished, nor would I narrow it to one domain. Rather, I imagine it being a living document, one that we continuously revise as Rust changes.

## Improving on the async vision doc

The async vision doc experience was great, but I learned a few things along the way that I would do differently now. One of them is that **collecting stories is good, but synthesizing them is better** (and harder). I also found that **people telling you the stories are not always the right ones to author them**. Last time, we had a lot of success with people authoring PRs, but many times people would tell a story, agree to author a PR, and then never follow up. This is pretty standard for open source but it also applies a sort of "selection bias" to the stories we got. **I would address both of these problems by dividing up the roles.** Rust users would just have to tell their stories. There would be a group of maintainers who would record those stories and then go try to author the PRs that integrate into "Using Rust".

The other thing I learned is that trying to **author a single shiny future does not work**. It was meant to be a unifying vision for the group, but there are just too many variables at play to reach consensus on that. We should **definitely** be talking about where we will be in 5 years, but we don't have to be entirely aligned on it. We just have to agree on the right next steps. **My new plan is to integrate the "shiny future" into RFCs, as I describe below.**

## Maintaining "Using Rust"

In the fullness of time, and presuming it works out well, I think "Using Rust" should be a rust-lang project, owned and maintained by its own team. My working title for this team is the *User Research Team*, which has the charter of gathering up data on how people use Rust and putting that data into a form that makes it accessible to the rest of the Rust project. But I tend to think it's better to prove out ideas before creating the team, so I think I would start with an experimental project, and create the team once we demonstrate the concept is working.

## Gathering stories

So how would this team go about gathering data? There's so many ways. When doing the async vision doc, we got some stories submitted by PRs on the repo. We ran [writing sessions](https://smallcultfollowing.com/babysteps/blog/2021/03/22/async-vision-doc-writing-sessions/) where people would come and tell us about their experiences.

I think it's very valuable to have people gather "in depth" data from within specific companies. For the Async Vision Doc, I also interviewed team members, culminating in the "meta-story" ["Alan extends an AWS service"](https://rust-lang.github.io/wg-async/vision/submitted_stories/status_quo/aws_engineer.html). Tyler Mandry and I also met with members from Google, and I recall we had folks from Embark and a few other companies reach out to tell us about their experiences.

Another really cool idea that came from Pietro Albini: set up a booth at various Rust conferences where people can come up and tell you about their stories. Or perhaps we can run a workshop. So many possibilities!

## Integrating "Using Rust" with the RFC process

The purpose of an RFC, in my mind, is to lay out a problem and a specific solution to that problem. The RFC is not code. It doesn't have to be a complete description of the problem. But it should be complete enough that people can imagine how the problem is going to be solved.

Every RFC includes a motivation, but when I read those motivations, I am often a bit at a loss as to how to evaluate them. Clearly there is some kind of problem. But is it important? How does it rank with respect to other problems that users are encountering?

I imagine that the "Using Rust" doc would help greatly here. I'd like to get to the point where the moivation for RFCs is primarily addressing particular stories or aspects of stories within the document. We would then be able to read over other related stories to get a sense for how this problem ranks compared to other problems for that audience, and thus how important the motivation is.

RFCs can also include a section that "retells" the story to explain how it would have played out had this feature been available. I've often found that doing this helps me to identify obvious gaps. For example, maybe we are adding a nifty new syntax to address an issue, but how will users learn about it? Perhaps we can add a "note" to the diagnostic to guide them.

## Frequently asked questions

### Will this help us in cross-team collaboration?

Like any organization, the Rust organization can easily wind up "shipping its org chart". For example, if I see a problem, as a lang-team member, I may be inclined to ship a language-based solution for it; similarly, I've seen that the embedded community works very hard to work within the confines of Rust as it is, whereas sometimes they could be a lot more productive if we added something to the language.

Although they are not a complete solution, I think having a "Using Rust" document will be helpful. Focusing on describing the problem means it can be presented to multiple teams and each can evaluate it to decide where the best solution lies.

### What about other kinds of stories?

I've focused on stories about Rust users, but I think there are other kinds of stories we might want to include. For example, what about the trials and travails of [Alan, Barbara, Grace, and Niklaus][coc] as they try to contribute to Rust? 

### How will we avoid "scenario solving"?

Scenario solving refers to a pattern where a feature is made to target various specific examples rather than being generalized to address a pattern of problems. It's possible that if we write out user stories, people will design features to target *exactly* the problems that they read about, rather than observing that a whole host of problems can be addressed via a single solution. That is true, and I think teams will want to watch out for that. At the same time, I think that having access to a full range of stories will make it much easier to *see* those large patterns and to help identify the full value for a proposal.

### What about a project management team?

From time to time there are proposals to create a "project management" team. There are many different shapes for what such a team would do, but the high-level motivation is to help provide "overall guidance" and ensure coherence between the Rust teams. I am skeptical about any idea that sounds like an "overseer" team. I trust the Rust teams to own and maintain their area. But I do think we can all benefit from getting more alignment on the sets of problems to be solved, which I think this "Using Rust" document would help to create. I can also imagine other interesting mechanisms that build on the doc, such as reviewing stories as a group online, or at "unconferences".

## Call to action: get in touch!

I'm feeling pretty excited about this project. I'm contemplating how to go about organizing it. I'm really interested to hear from people who would like to take part as authors and collators of user stories. If you think you'd be interested to participate, please [send me an email](mailto:rust@nikomatsakis.com). I'm particularly interested to hear from product managers or developer advocates.

[plan]: https://blog.rust-lang.org/2021/03/18/async-vision-doc.html

[sf]: https://blog.rust-lang.org/2021/04/14/async-vision-doc-shiny-future.html

[bbbs]: https://rust-lang.github.io/wg-async/vision/submitted_stories/status_quo/barbara_battles_buffered_streams.html

[bgbs]: https://rust-lang.github.io/wg-async/vision/submitted_stories/status_quo/barbara_gets_burned_by_select.html

[atrc]: https://rust-lang.github.io/wg-async/vision/submitted_stories/status_quo/alan_started_trusting_the_rust_compiler_but_then_async.html
