---
layout: post
title: 'AiC: Collaborative summary documents'
categories: [Rust, Consensus]
---

In my [previous post][pp], I talked about the idea of *mapping the
solution space*:

[pp]: http://smallcultfollowing.com/babysteps/blog/2019/04/19/aic-adventures-in-consensus/

> When we talk about the RFC process, we always emphasize that the point
> of RFC discussion **is not to select the best answer**; rather, the
> point is to **map the solution space**. That is, to explore what the
> possible tradeoffs are and to really look for alternatives.  This
> mapping process also means exploring the ups and downs of the current
> solutions on the table.

**One of the challenges I see with how we often do design is that this
"solution space" is actually quite implicit.** We are exploring it
through comments, but each comment is only tracing out one path
through the terrain. I wanted to see if we could try to represent the
solution space explicitly. This post is a kind of "experience report"
on one such experiment, what I am calling a **collaborative summary
document** (in contrast to the more standard **summary comment** that
we often do).

### The idea: a collaborative summary document

I'll get into the details below, but the basic idea was to create a
shared document that tried to present, in a neutral fashion, the
arguments for and against a particular change. I asked the people to
stop commenting in the thread and instead read over the document, look
for things they disagreed with, and offer suggestions for how it could
be improved.

My hope was that we could not only get a thorough summary from the
process, but also do something deeper: change the *focus* of the
conversation from "advocating for a particular point of view" towards
"trying to ensure a complete and fair summary". I figured that after
this period was done, people were likely go back to being advocates
for their position, but at least for some time we could try to put
those feelings aside.

### So how did it go?

Overall, I felt very positive about the experience and I am keen to
try it again. I think that something like "collaborative summary
documents" could become a standard part of our process. Still, I think
it's going to take some practice trying this a few times to figure out
the best structure. Moreover, I think it is not a silver bullet: to
realize the full potential, we're going to have to make other changes
too.

### What I did in depth 

What I did more specifically was to [create a Dropbox Paper
document][doc]. [This document][doc] contained my best effort at
summarizing the issue at hand, but it was not meant to be just my
work. The idea was that we would all jointly try to produce the best
summary we could.

[gh]: https://github.com/rust-lang/rust/pull/59119#issuecomment-473655294
[ask]: https://paper.dropbox.com/doc/Future-proof-the-Futures-API-Summary--AbpsrNFMirDHgOtZimF11AEUAg-JODniiQQQcNhHD7iNZ8iM#:uid=739200718850749032543986&h2=This-is-an-experiment
[doc]: https://paper.dropbox.com/doc/Future-proof-the-Futures-API-Summary--AbplHExNn34jm1~y2i02FYARAg-JODniiQQQcNhHD7iNZ8iM

After that, I [made an announcement][gh] on the original thread asking
people to participate in the document. Specifically, [as the document
states][ask], the idea was for people to do something like this:

- Read the document, looking for things they didn't agree with or felt were unfairly represented.
- Leave a comment explaining their concern; or, better, supplying alternate wording that they *did* agree with
  - The intention was always to preserve what they felt was the sense
    of the initial comment, but to make it more precise or less judgemental.

I was then playing the role of editor, taking these comments and
trying to incorporate them into the whole. The idea was that, as
people edited the document, we would gradually approach a **fixed point**,
where there was nothing left to edit.

### Structure of the shared document

Initially, when I created the document, I structured it into two
sections -- basically "pro" and "con". The issue at hand was a
particular change to the Futures API (the details don't matter
here). In this case, the first section advocated **for** the change,
and the second section advocated against it. So, something like this
(for a fictional problem):

> **Pro:**
>
> We should make this change because of X and Y. The options
> we have now (X1, X2) aren't satisfying because of problem Z.
>
> **Con:**
>
> This change isn't needed. While it would make X easier, there are
> already other useful ways to solve that problem (such as X1, X2).
> Similarly, the goals of isn't very desirable in the first
> place because of A, B, and C.

I quickly found this structure rather limiting. It made it hard to
compare the arguments -- as you can see here, there are often
"references" between the two sections (e.g., the con section refers to
the argument X and tries to rebut it). Trying to compare and consider
these points required a lot of jumping back and forth between the
sections.

### Using nested bullets to match up arguments

So I decided to restructure the document to integrate the arguments
for and against. I created nesting to show when one point was directly
in response to another. For example, it might read like this (this is
not an actual point; those were much more detailed):

- **Pro:** We should make this change because of X.
  - **Con:** However, there is already the option of X1 and X2 to satisfy that use-case.
    - **Pro:** But X1 and X2 suffer from Z.
- **Pro:** We should make this change because of Y and Z.
  - **Con:** Those goals aren't as important because of A, B, and C.

Furthermore, I tried to make the first bullet point a bit special --
it would be the one that encapsulated the **heart** of the dispute,
from my POV, with the later bullet points getting progressively more
into the weeds.

### Nested bullets felt better, but we can do better still I bet

I definitely preferred the structure of nested bullets to the original
structure, but it didn't feel perfect. For one thing, it requires me
to summarize each argument into a single paragraph. Sometimes this
felt "squished". I didn't love the repeated "pro" and "con". Also,
things don't always fit neatly into a *tree*; sometimes I had to
"cross-reference" between points on the tree (e.g., referencing
another bullet that had a detailed look at the trade-offs).

**If I were to do this again,** I might tinker a bit more with the
format. The most extreme option would be to try and use a "wiki-like"
format.  This would allow for free inter-linking, of course, and would
let us hide details into a recursive structure. But I worry it's *too
much* freedom.

### Adding "narratives" on top of the "core facts"

One thing I found that surprised me a bit: the summary document aimed
to summarize the "core facts" of the discussion -- in so doing, I
hoped to summarize the two sides of the argument. But I found that
**facts alone cannot give a "complete" summary:** to give a complete
summary, you also need to present those facts "in context". Or, put
another way, you also need to explain the *weighting* that each side
puts on the facts.

In other words, the document did a good job of enumerating the various
concerns and "facets" of the discussion. But it didn't do a good job
of explaining **why** you might fall on one side or the other.

I tried to address this by [crafting a "summary comment"][sc1] on the main
thread. This comment had a very specific form. It begin by trying to identify
the "core tradeoff" -- the crux of the disagreement:

[sc1]: https://github.com/rust-lang/rust/pull/59119#issuecomment-474444350

> So the core tradeoff here is this:
> - By leaving the design as is, we keep it as simple and ergonomic as it can be;
>   - **but**, if we wish to pass **implicit** parameters to the future when polling, we must use TLS.

It then identifies some of the "facets" of the space which different people weight
in different ways:

> So, which way you fall will depend on
> 
> - how important you think it is for `Future` to be ergonomic
>   - and naturally how much of an ergonomic hit you believe this to be
>   - how likely you think it is for us to want to add implicit parameters
>   - how much of a problem you think it is to use TLS for those implicit parameters

**And then it tried to tell a series of "narratives".** Basically to
tell the **story** of each group that was involved and **why** that
led them to assign different weights to those points above. Those
weights in turn led to a different opinion on the overall issue.

For example:

> I think a number of people feel that, by now, between Rust and other
> ecosystems, we have a pretty good handle on what sort of data we
> want to thread around and what the best way is to do it. Further,
> they feel that TLS or passing parameters explicitly is the best
> solution approach for those cases. Therefore, they prefer to leave
> the design as is, and keep things simple. (More details in the doc,
> of course.)

Or, on the other side:

> Others, however, feel like there is additional data they want to
> pass implicitly and they do not feel convinced that TLS is the best
> choice, and that this concern outweights the ergonomic
> costs. Therefore, they would rather adopt the PR and keep our
> options open.

Finally, it's worth noting that there aren't always just two sides. In
fact, in this case I identified a third camp:

> Finally, I think there is a third position that says that this
> controversy just isn't that important. The performance hit of TLS,
> if you wind up using it, seems to be minimal. Similarly, the
> clarity/ergonomics of `Future` are not as criticial, as users who
> write `async fn` will not implement it directly, and/or perhaps the
> effect is not so large. These folks probably could go either way,
> but would mostly like us to stop debating it and start building
> stuff. =)

One downside of writing the narratives in a standard summary comment
was that it was not "part of" the main document. In fact, it feels to
me like these narratives are a pretty key part of the whole thing.  In
fact, it was only once I added these narratives that I really felt I
started to *understand* why one might choose one way or the other when
it came to this decision.

**If I were to do this again,** I would make **narratives** more of a
first-place entity in the document itself. I think I would also focus
on some other "meta-level reasoning", such as **fears and risks**. I
think it's worth thinking, for any given decision, "what if we make
the wrong call" -- e.g., in this case, what happens if we decide *not*
to future proof, but then we regret it; in contrast, what happens if
we decide to *add* future proofing, but we never use it.

### We never achieved "shared ownership" of the summary

One of my goals was that we could, at least for a moment, disconnect
people from their particular position and turn their attention towards
the goal of achieving a shared and complete summary. I didn't feel
that we were very succesful in this goal.

For one thing, most participants simply left comments on parts they
disagreed with; they didn't themselves suggest alternate wording. That
meant that I personally had to take their complaint and try to find
some "middle ground" that accommodated the concern but preserved the
original point. This was stressful for me and a lot of work. **More
importantly, it meant that most people continued to interact with the
document as *advocates* for their point-of-view, rather than trying to
step back and advocate for the completeness of the summary.**

In other words: when you see a sentence you disagree with, it is easy
to say that you disagree with it. It is much harder to rephrase it in
a way that you *do* agree with -- but which still preserves (what you
believe to be) the original intent. Doing so requires you to think
about what the other person likely meant, and how you can preserve
that.

However, one possible reason that people may have been reluctant to
offer suggestions is that, often, it was hard to make "small edits"
that addressed people's concerns. Especially early on, I found that,
in order to address some comment, I would have to make larger
restructurings. For example, taking a small sentence and expanding it
to a bullet point of its own.

Finally, some people who were active on the thread didn't participate
in the doc. Or, if they did, they did so by leaving comments on the
original GitHub thread. This is not surprising: I was asking people to
do something new and unfamiliar. Also, this whole process played out
relatively quickly, and I suspect some people just didn't even *see*
the document before it was done.

**If I were to do this again,** I would want to start it earlier in
the process. I would also want to consider synchronous meetings, where
we could go try to process edits as a group (but I think it would take
some thought to figure out how to run such a meeting).

In terms of functioning asynchronously, I would probably change to use
a Google Doc instead of a Dropbox Paper. Google Docs have a better
workflow for suggesting edits, I believe, as well, as a richer permissions
model. 

Finally, I would try to draw a harder line in trying to get people to
"own" the document and suggest edits of their own. I think the
challenge of trying to neutrally represent someone else's point of
view is pretty powerful.

### Concluding remarks

Conducting this exercise taught me some key lessons:

- We should experiment with the best way to *describe* the
  back-and-forth (I found it better to put closely related points
  together, for example, rather than grouping the arguments into 'pro
  and con').
- We should include not only the "core facts" but also the
  "narratives" that weave those facts together.
- We should do this summary process earlier and we should try to find
  better ways to encourage participation.

Overall, I felt very good about the idea of "collaborative summary
documents". I think they are a clear improvement over the "summary
comment", which was the prior state of the art.

If nothing else, the quality of the summary itself was greatly
improved by being a collaborative document. I felt like I had a pretty
good understanding of the question when I started, but getting
feedback from others on the things they felt I misunderstood, or just
the places where my writing was unclear, was very useful.

But of course my aims run larger. I hope that we can change how design
work *feels*, by encouraging all of us to deeply understand the design
space (and to understand what motivates the other side). My experiment
with this summary document left me feeling pretty convinced that it
could be a part of the solution.

### Feedback

I've created a discussion thread on [the internals forum][internals]
where you can leave questions or comments. I'll definitely read them
and I will try to respond, though I often get overwhelmed[^somany], so
don't feel offended if I fail to do so.

[internals]: https://internals.rust-lang.org/t/aic-adventures-in-consensus/9843
[^somany]: So many things, so little time.

### Footnotes
