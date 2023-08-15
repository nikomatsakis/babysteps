---
categories:
- Rust
- Consensus
date: "2019-07-10T00:00:00Z"
slug: aic-unbounded-queues-and-lang-design
title: 'AiC: Unbounded queues and lang design'
---

I have been thinking about how language feature development works in
Rust[^lang]. I wanted to write a post about what I see as one of the
key problems: too much concurrency in our design process, without any
kind of "back-pressure" to help keep the number of "open efforts"
under control. This setup does enable us to get a lot of things done sometimes,
but I believe it also leads to a number of problems.

[^lang]: I'm coming at this from the perspective of the lang team, but I think a lot of this applies more generally.

Although I don't make any proposals in this post, I am basically
advocating for changes to our process that can help us to stay focused
on a few active things at a time. Basically, incorporating a notion of
**capacity** such that, if we want to start something new, we either
have to finish up with something or else find a way to grow our
capacity.

### The feature pipeline

Consider how a typical language feature gets introduced today:

- **Initial design** in the form of an RFC. This is done by the **lang team**.
- **Initial implementation** is done. This work is overseen by the
  **compiler team**, but often it is done by a volunteer contributor
  who is not themselves affiliated. 
- **Documentation** work is done, again often by a contributor,
  overseen by the docs team.
- **Experimentation in nightly** takes places, often leading to
  changes in the design.  (These changes have their own FCP periods.)
- Finally, at some point, we **stabilize** the feature. This involves
  a stabilization report that summarizes what has changed, known bugs,
  what tests exist, and other details. This decision is made by the
  **lang team**.

At any given time, therefore, we have a number of features at each
point in the pipeline -- some are being designed, some are waiting for
an implementor to show up, etc. 

### Today we have unbounded queues

One of the challenges is that the "links" between these pipeline are
effectively **unbounded queues**. It's not uncommon that we get an RFC
for a piece of design that "seems good". The RFC gets accepted. But
nobody is really **driving** that work -- as a result, it simply
languishes.  To me, the poster child for this is [RFC 66] -- a modest
change to our rules around the lifetime of temporary values. I still
think the RFC is a good idea (although its wording is very imprecise
and it needs to be rewritten to be made precise). But it's been
[sitting around unimplemented][15023] since **June of 2014**. At this
point, is the original decision approving the RFC even still valid? (I
sort of think no, but we don't have a formal rule about that.)

[15023]: https://github.com/rust-lang/rust/issues/15023
[RFC 66]: https://rust-lang.github.io/rfcs/0066-better-temporary-lifetimes.html

### How can an RFC sit around for 5 years?

Why did this happen? I think the reason is pretty clear: the idea was
good, but it didn't align with any particular priority. We didn't have
resources lined up behind it. It needed somebody from the lang team
(probably me) to rewrite its text to be actionable and
precise[^ref]. It needed somebody from the compiler team (maybe me
again) to either write a PR or mentor somebody through it. And all
those people were busy doing other things. So why did we accept the PR
in the first place? Well, **why wouldn't we?** Nothing in the process
states that we should consider available resources when making an RFC
decision.

[^ref]: For that matter, it would be helpful if there were a spec of the current behavior for it to build off of. 

### Unbounded queues lead to confusion for users

So why does it matter when things sit around? I think it has a number
of negative effects. The most obvious is that it sends really
confusing signals to people trying to follow along with Rust's
development. It's really hard to tell what the current priorities are;
it's hard to tell when a given feature might actually appear. Some of
this we can help resolve just by better labeling and documentation.

### Unbounded queues make it harder for teams

But there are other, more subtle effects. Overall, it makes it much
harder for the team itself to stay organized and focused and that in
turn can create a lot of stress. Stress in turn magnifies all other
problems.

How does it make it harder to stay organized? Under the current setup,
people can add new entries into any of these queues at basically any
time. This can come in many forms, such as new RFCs (new design work
and discussion), proposed changes to an existing design (new design or
implementation work), etc.

Just having a large number of existing issues means that, in a very
practical sense, it becomes challenging to follow GitHub notifications
or stay on top of all the things going on. I've lost count of the
number of attempts I've made at this personally.

Finally, the fact that design work stretches over such long periods
(frequently years!) makes it harder to form stable communities of
people that can dig deeply into an issue, develop a rapport, and reach
a consensus.

### Leaving room for serendipity?

Still, there's a reason that we setup the system the way we did. This
setup can really be a great fit for an open source project. After all,
in an open source project, it can be **really hard for us to figure
out how many resources we actually have**. It's certainly more than
the number of folks on the teams. It happens pretty regularly that
people appear out of the blue with an amazing PR implementing some
feature or other -- and we had no idea they were working on it!

In the [2018 RustConf keynote], we talked about the contrast between
**OSS by serendipity** and **OSS on purpose**. We were highlighting
exactly this tension: on the one hand, Rust is a product, and like any
product it needs direction. But at the same time, we want to enable
people to contribute as much as we can.

[2018 RustConf keynote]: https://www.youtube.com/watch?v=J9OFQm8Qf1I

### Reviewing as the limited resource

Still, while the existing setup helps ensure that there are many
opportunities for people to get involved, it also means that people
who come with a new idea, PR, or whatever may wind up waiting a long
time to get a response. Often the people who are supposed to answer
are just busy doing other things. Sometimes, there is a (often
unspoken) understanding that a given issue is just not high enough
priority to worry about.

In an OSS project, therefore, I think that the right way to measure
capacity is in terms of **reviewer bandwidth**. Here I mean "reviewer"
in a pretty general way. It might be someone who reviews a PR, but it
might also be a lang team member who is helping to drive a particular
design forward.

### Leaving room for new ideas?

One other thing I've noticed that's worth highlighting is that,
sometimes, hard ideas just need time to bake. Trying to rush something
through the design process can be a bad idea. 

Consider specialization: On the one hand, this feature was [first
proposed][rfc1210] in July of **2015**. We had a lot of really
important debate at the time about the importance of parametricity and
so forth. We have an initial implementation. But there was one key
issue that never got satisfactorily resolved, a technical soundness
concern around lifetimes and traits. As such, the issue has sat around
-- it would get periodically discussed but we never came to a
satisfactory conclusion. Then, in Feb of **2018**, [I had an idea][s1]
which [aturon then extended][s2] in April. It *seems* like these ideas
have basically solved the problem, but we've been busy in the meantime
and haven't had time to follow up.

[rfc1210]: https://github.com/rust-lang/rfcs/pull/1210
[s1]: http://smallcultfollowing.com/babysteps/blog/2018/02/09/maximally-minimal-specialization-always-applicable-impls/
[s2]: http://aturon.github.io/tech/2018/04/05/sound-specialization/

This is a tricky case: maybe if we had tried to push specialization
all the way to stabilization, we would have had these same ideas. But
maybe we wouldn't have. Overall, I think that deciding to wait has
worked out reasonably well for us, but probably not *optimally*. I
think in an ideal world we would have found some *useful subset* of
specialization that we could stabilize, while deferring the tricky
questions.

### Tabling as an explicit action

Thinking about specialization leads to an observation: one of the
things we're going to have to figure out is how to draw good
boundaries so that we can push out a useful subset of a feature (an
"MVP", if you will) and then leave the rest for later. Unlike today,
though, I think should be an explicit process, where we take the time
to document the problems we still see and our current understanding of
the space, and then explicitly "table" the remainder of the work for
another time.

### People need help to set limits

One of the things I think we should put into our system is some kind
of **hard cap** on the number of things you can do at any given time.
I'd like this cap to be pretty small, like one or two. This will be
frustrating. It will be tempting to say "sure I'm working on X, but I
can make a little time for Y too". It will also slow us down a bit.

But I think that's ok. We can afford to do a few less things. Or, if
it seems like we can't, that's probably a sign that we need to grow
that capacity: find more people we trust to do the reviews and lead
the process. If we can't do that, then we have to adjust our ambitions.

In other words, in the absence of a cap, it is very easy to "stretch"
to achieve our goals. That's what we've done often in the past. But
you can only stretch so far and for so long.

### Conclusion

As I wrote in the beginning, I'm not making any proposals in this
post, just sharing my current thoughts. I'd like to hear if you think
I'm onto something here, or heading in the wrong direction. Here is a
link to the [Adventures in Consensus thread on internals][thread].

[thread]: https://internals.rust-lang.org/t/aic-adventures-in-consensus/9843

One thing that has been pointed out to me is that these ideas resemble
a number of management philosophies, most notably [kanban]. I don't
have much experience with that personally but it makes sense to me
that others would have tried to tackle similar issues.

[kanban]: https://en.wikipedia.org/wiki/Kanban

### Footnotes
