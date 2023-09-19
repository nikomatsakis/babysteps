---
layout: post
title: "[AiC] Vision Docs!"
---

The [Async Vision Doc][vd] effort has been going now for [about 6 weeks](https://blog.rust-lang.org/2021/03/18/async-vision-doc.html). It's been a fun ride, and I've learned a lot. It seems like a good time to take a step back and start talking a bit about the vision doc structure and the process. In this post, I'm going to focus on the role that I see vision docs playing in Rust's planning and decision making, particularly as compared to RFCs.

[vd]: https://rust-lang.github.io/wg-async-foundations/vision.html

### Vision docs frame RFCs

If you look at a description of the design process for a new Rust feature, it usually starts with "write an RFC". After all, before we start work on something, we begin with an RFC that both motivates and details the idea. We then proceed to implementation and stabilization.

But the RFC process isn't really the beginning. The process really begins with identifying some sort of problem[^opp] -- something that doesn't work, or which doesn't work as well as it could. The next step is imagining what you would like it to be like, and then thinking about how you could make that future into reality.

[^opp]: Not problem, opportunity!

We've always done this sort of "framing" when we work on RFCs. In fact, RFCs are often just one small piece of a larger picture. Think about something like `impl Trait`, which began with an intentionally conservative step ([RFC #1522]) and has been gradually extended. Async Rust started the same way; in that case, though, even the first RFC was split into two, which together described a complete first step ([RFC #2394] and [RFC #2592]).

[RFC #1522]: https://github.com/rust-lang/rfcs/pull/1522
[RFC #2394]: https://github.com/rust-lang/rfcs/pull/2394
[RFC #1951]: https://github.com/rust-lang/rfcs/pull/1951
[RFC #2071]: https://github.com/rust-lang/rfcs/pull/2071
[RFC #2250]: https://github.com/rust-lang/rfcs/pull/2250
[RFC #2592]: https://github.com/rust-lang/rfcs/pull/2592

The role of a vision doc is to take that implicit framing and make it explicit. Vision docs capture both the problem and the end-state that we hope to reach, and they describe the first steps we plan to take towards that end-state.

### The "shiny future" of vision docs

There are many efforts within the Rust project that could benefit from vision docs. Think of long-running efforts like const generics or [library-ification]. There is a future we are trying to make real, but it doesn't really exist in written form.

[library-ification]: https://smallcultfollowing.com/babysteps/blog/2020/04/09/libraryification/

I can say that when the lang team is asked to approve an RFC relating to some incremental change in a long-running effort, it's very difficult for me to do. I need to be able to put that RFC into context. What is the latest plan we are working towards? How does this RFC take us closer? Sometimes there are parts of that plan that I have doubts about -- does this RFC lock us in, or does it keep our options open? Having a vision doc that I could return to and evolve over time would be a tremendous boon.

I'm also excited about the potential for 'interlocking' vision docs. While working on the Async Vision Doc, for example, I've found myself wanting to write examples that describe error handling. It'd be really cool if I could pop over to the [Error Handling Project Group][peh][^tada], take a look at their vision doc, and then make use of what I see there in my own examples. It might even help me to identify a conflict before it happens.

[peh]: https://github.com/rust-lang/project-error-handling

[^tada]: Shout out to the error handling group, they're doing great stuff!

### Start with the "status quo"

A key part of the vision doc is that it starts by documenting the ["status quo"][sq]. It's all too easy to take the "status quo" for granted -- to assume that everybody understands how things play out today. 

When we started writing "status quo" stories, it was really hard to focus on the "status quo". It's really tempting to jump straight to ideas for how to fix things. It took discipline to force ourselves to just focus on describing and understanding the current state.

I'm really glad we did though. If you haven't done so already, take a moment to browse through the [status quo][sq] section of the doc (you may find the [metanarrative] helpful to get an overview[^34]). Reading those stories has given me a much deeper understanding of how Async is working in practice, both at a technical level but also in terms of its impact on people. This is true even when presenting highly technical context. Consider stories like [Barbara builds an async executor][bbac] or [Barbara carefully dismisses embedded future][emb]. For me, stories like this have more resonance than just seeing a list of the technical obstacles one must overcome. They also help us talk about the various "dead-ends" that might otherwise get forgotten.

[^34]: Did I mention we have **34 stories** so far (and more in open PRs)? So cool. Keep 'em coming!

[sq]: https://rust-lang.github.io/wg-async-foundations/vision/status_quo.html
[metanarrative]: https://rust-lang.github.io/wg-async-foundations/vision/status_quo.html#metanarrative

[bbac]: https://rust-lang.github.io/wg-async-foundations/vision/status_quo/barbara_builds_an_async_executor.html
[emb]: https://rust-lang.github.io/wg-async-foundations/vision/status_quo/barbara_carefully_dismisses_embedded_future.html
[sq]: https://rust-lang.github.io/wg-async-foundations/vision/status_quo.html

Those kind of dead-ends are especially important for people new to Rust, of course, who are likely to just give up and learn something else if the going gets too rough. In working on Rust, we've always found that focusing on accessibility and the needs of new users is a great way to identify things that -- once fixed -- wind up helping everyone. It's interesting to think how long we put off doing NLL. After all, [metajack] filed [#6393] in 2013, and I remember people raising it with me earlier. But to those of us who were experienced in Rust, we knew the workarounds, and it never seemed pressing, and hence NLL got put off until 2018.[^hard] But now it's clearly one of the most impactful changes we've made to Rust for users at all levels.

[metajack]: github.com/metajack
[cok]: https://en.wikipedia.org/wiki/Curse_of_knowledge
[#6393]: https://github.com/rust-lang/rust/issues/6393
[^hard]: To be fair, it was also because designing and implementing NLL was really, really hard.[^polonius]
[^polonius]: And -- heck -- we're still working towards [Polonius]!

[Polonius]: https://github.com/rust-lang/polonius/



### Brainstorming the "shiny future"

A few weeks back, we [started writing "shiny future" stories][startsf] (in addition to "status quo"). The "shiny future" stories are the point where we try to imagine what Rust could be like in a few years.

[startsf]: https://blog.rust-lang.org/2021/04/14/async-vision-doc-shiny-future.html

Ironically, although in the beginning the "shiny future" was all we could think about, getting a lot of "shiny future" stories up and posted has been rather difficult. It turns out to be hard to figure out what the future should look like![^whoknew]

[^whoknew]: Who knew?

Writing "shiny future" stories sounds a bit like an RFC, but it's actually quite different:

* The focus is on the end user experience, not the details of how it works.
* We want to think a bit past what we know how to do. The goal is to "shake off" the limits of incremental improvement and look for ways to really improve things in a big way.
* We're not making commitments. This is a brainstorming session, so it's fine to have multiple contradictory shiny futures.

In a way, it's like writing *just* the "guide section" of an RFC, except that it's not written as a manual but in narrative form.

### Collaborative writing sessions

To try and make the writing process more fun, we started running [collaborative Vision Doc Writing Sessions][vii]. We were focused purely on status quo stories at the time. The idea was simple -- find people who had used Rust and get them to talk about their experiences. At the end of the session, we would have a "nearly complete" outline of a story that we could hand off to someone to finish.[^thanks]

[^thanks]: Big, big shout-out to [all those folks who have participated](https://rust-lang.github.io/wg-async-foundations/acknowledgments.html#-participating-in-an-writing-session), and  especially those [brave souls who authored stories](https://rust-lang.github.io/wg-async-foundations/acknowledgments.html#-directly-contributing).

[i]: https://smallcultfollowing.com/babysteps/blog/2021/03/22/async-vision-doc-writing-sessions/
[vii]: https://smallcultfollowing.com/babysteps/blog/2021/04/26/async-vision-doc-writing-sessions-vii/

The sessions work particularly well when you are telling the story of people who were actually in the session. Then you can simply ask them questions to find out what happened. How did you start? What happened next? How did you feel then? Did you try anything else in between? If you're working from blog posts, you sometimes have to take guesses and try to imagine what might have happened.[^ping] 

[^ping]: One thing that's great, though, is that after you post the story, you can [ping people](https://github.com/rust-lang/wg-async-foundations/pull/172#issuecomment-826156660) and ask them if you got it right. =)

One thing to watch out for: I've noticed people tend to jump steps when they narrate. They'll say something like "so then I decided to use `FuturesUnordered`", but it's interesting to find out how they made that decision. How did they learn about `FuturesUnordered`? Those details will be important later, because if you develop some superior alternative, you have to be sure people will find it.

### Shifting to the "shiny future"

Applying the "collaborative writing session" idea to the shiny future has been more difficult. If you get a bunch of people in one session, they may not agree on what the future should be like.

Part of the trick is that, with shiny future, you often want to go for breadth rather than depth. It's not just about writing one story, it's about exploring the design space. That leads to a different style of writing session, but you wind up with a scattershot set of ideas, not with a 'nearly complete' story, and it's hard to hand those off.

I've got a few ideas of things I would like to try when it comes to future writing sessions. One of them is that I would like to work directly with various luminaries from the Async Rust world to make sure their point-of-view is represented in the doc.

Another idea is to try and encourage more "end-to-end" stories that weave together the "most important" substories and give a sense of prioritization. After all, we know that [there are subtle footguns in the model as is](https://rust-lang.github.io/wg-async-foundations/vision/status_quo/barbara_battles_buffered_streams.html) and we also know that [intgrating into external event loops is tricky](https://rust-lang.github.io/wg-async-foundations/vision/status_quo/alan_has_an_event_loop.html). Ideally, we'd fix both. But which is a bigger obstacle to Async Rust users? In fact, I imagine that there is no single answer. The answer will depend on what people are doing with Async Rust.

### After brainstorming: Consolidating the doc and building a roadmap

The brainstorming period is scheduled to end mid-May. At that point comes the next phase, which is when we try to sort out all the contradictory shiny future stories into one coherent picture. I envision this process being led by the async working group leads (tmandry and I), but it's going to require a lot of consensus building as well.

In addition to building up the shiny future, part of this process will be deciding a concrete roadmap. The roadmap will describe the specific first steps we will take first towards this shiny future. The roadmap items will correspond to particular designs and work items. And here, with those specific work items, is where we get to RFCs: when those work items call for new stdlib APIs or extensions to the language, we will write RFCs that specify them. But those RFCs will be able to reference the vision doc to explain their motivation in more depth.

### Living document: adjusting the "shiny future" as we go

There is one thing I want to emphasize: **the "shiny future" stories we write today will be wrong**. As we work on those first steps that appear in the roadmap, we are going to learn things. We're going to realize that the experience we wanted to build is not possible -- or perhaps that it's not even desirable! That's fine. We'll adjust the vision doc periodically as we go. We'll figure out the process for that when the time comes, but I imagine it may be a similar -- but foreshortened -- version of the one we have used to draft the initial version.

### Conclusion

Ack! It's probably pretty obvious that I'm excited about the potential for vision docs. I've got a lot of things I want to say about them, but this post is getting pretty long. There are a lot of interesting questions to poke at, most of which I don't know the answers to yet. Some of the things on my mind: what are the best roles for the characters and should we tweak how they are defined[^four]? Can we come up with good heuristics for which character to use for which story? How are the "consolidation" and "iteration / living document" phases going to work? When is the appropriate time to write a vision doc -- right away, or should you wait until you've done enough work to have a clearer picture of what the future looks like? Are there lighterweight versions of the process? We're going to figure these things out as we go, and I will write some follow-up posts talking about them.

### Footnotes

[^four]: I feel pretty strongly that four characters is the right number ([it worked for Marvel](https://en.wikipedia.org/wiki/File:Fantastic_Four_2015_poster.jpg#/media/File:Fantastic_Four_2015_poster.jpg), it will work for us!)[^actual], but I'm not sure if we got their setup right in other respects.

[^actual]: Not my actual reason. I don't know my actual reason, it just seems right.