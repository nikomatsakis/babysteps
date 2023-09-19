---
layout: post
title: "AiC: Shepherds 3.0"
categories: [Rust, Consensus]
---

I would like to describe an idea that's been kicking around in my
head.  I'm calling this idea "shepherds 3.0" -- the 3.0 is to
distinguish it from the other places we've used the term in the past.
This proposal actually supplants both of the previous uses of the
term, replacing them with what I believe to be a preferred alternative
(more on that later).

## Caveat

This is an idea that has been kicking around in my head for a while.
It is not a polished plan and certainly not an accepted one. I've not
talked it over with the rest of the lang team, for example. However, I
wanted to put it out there for discussion, and I do think we should be
taking some step in this direction soon-ish.

## TL;DR

What I'm proposing, at its heart, is very simple. I want to better
document the "agenda" of the lang-team. Specifically, if we are going
to be moving a feature forward[^process], then it should have a **shepherd** (or
multiple) who is in charge of doing that.

[^process]: I could not find any single page that documents Rust's feature process from beginning to end. Seems like something we should fix. But what I mean by moving a feature forward is basically things like "accepting an RFC" or "stabilzing an unstable feature" -- basically the formal decisions governed by the lang team.

In order to avoid [unbounded queues], the **number of things that any
individual can shepherd should be limited**. Ideally, each person
should only shepherd one thing at a time, though I don't think we need
to make a firm rule about it.

**Becoming a shepherd is a commitment on the part of the shepherd.**
The first part of the lang team meeting should be to review the items
that are being actively shepherded and get any updates. If we haven't
seen any movement in a while, we should consider changing the
shepherd, or officially acknowleding that something is stalled and
removing the shepherd altogether.

**Assigning a shepherd is a commitment on the part of the rest of the
lang-team as well.** Before assigning a shepherd, we should discuss if
this agenda item is a priority.  In particular, if someone is
shepherding something, that means we all agree to help that item move
towards some kind of completion. This means giving feedback, when
feedback is requested.  It means doing the work to resolve concerns
and conflicts. And, sometimes, it will mean giving way. I'll talk more
about this in a bit.

## What was shepherds 1.0 and how is this different?

The initial use of the term shepherd, as I remember it, was actually
quite close to the way I am using it here. The idea was that we would
assign RFCs to a shepherd that should either drive to be accepted or
to be closed. This policy was, by and large, a failure -- RFCs got
assigned, but people didn't put in the time. (To be clear, sometimes
they did, and in those cases the system worked reasonably well.)

My proposal here differs in a few key respects that I hope will make it
more successful:

- We limit how many things you can shepherd at once.
- Assigning a shepherd is also a commitment from the lang team as a
  whole to review progress, resolve conflicts, and devote some time to
  the issue.
- We don't try to shepherd everything -- in contrast, shepherding marks
  the things we are moving forward.
- The shepherd is not something specific to an RFC, it refers to all
  kinds of "larger decisions". For example, stabilization would be a
  shepherd activity as well.
  
## What was shepherds 2.0 and how is this different?

We've also used the term shepherd to refer to a role that is moving
towards full lang team membership. That's different from this proposal
in that it is not tied to a specific topic area. But there is also
some interaction -- for example, **it's not clear that shepherds need
to be active lang team members**.

I think it'd be great to allow shepherds to be any person who is
sufficiently committed to help see something through. The main
requirement for a shepherd should be that they are able to give us
regular updates on the progress. Ideally, this would be done by
attending the lang team meeting. But that doesn't work for everyone --
whether it because of time zones, scheduling, or language barriers --
and so I think that any form of regular, asynchronous report would
work jsut fine.

**I think I would prefer for this proposal -- and this kind of
"role-specific shepherding" -- to entirely replace the "provisional
member" role on the lang team.** It seems strictly better to me. Among
other things, it's naturally time-limited. Once the work item
completes, that gives us a chance to decide whether it makes sense for
someone to become a full member of the lang team, or perhaps try
shepherding another idea, or perhaps just part ways. I expect there
are a lot of people who have interest in working through a specific
feature but for whom there is little desire to be long-term members of
the lang team.

## How do I get a shepherd assigned to my work item?

Ultimately, I think this question is ill-posed: there is no way to
"get" a shepherd assigned to your work. Having the expectation that a
shepherd will be assigned runs smack into the problems of [unbounded
queues] and was, I think, a crucial flaw in the Shepherds 1.0 system.

Basically, the way a shepherd gets assigned in this scheme is roughly
the same as the way things "get done" today. You convince someone in
the lang team that the item is a priority, and they become the
shepherd. That convincing takes place through the existing channels:
nominated issues, discord or zulip, etc. It's not that I don't think
this is something else we should be thinking about, it's just that
it's something of an orthogonal problem.

My model is that shepherds are how we *quantify and manage the things
we are doing*. The question of "what happens to all the existing
things" is more a question of *how we select which things to do* --
and that's ultimately a priority call.

## OK, so, what happens to all the existing things?

That's a very good question. And one I don't intend to answer here, at
least not in full. That said, I do think this is an important problem
that we should think about.  I would like to be exposing more
"insight" into our overall priorities.

In my ideal world, we'd have a list of projects that we are **not**
working on, grouped somewhat by how likely we are to work on them in
the future. This might then indicate ideas that we do *not* want to
pursue; ideas that we have mild interest in but which have a lot of
unknowns.  Ideas that we started working on but got blocked at some
point (hopefully with a report of what's blocking them). And so
forth. But that's all a topic for another post.

One other idea that I like is documenting on the website the "areas of
interest" for each of the lang team members (and possibly other folks)
who might be willing shepherds. This would help people figure out who
to reach out to.

## Isn't there anything I can do to help move Topic X along?

This proposal does offer one additional option that hadn't formally
existing before. **If you want to see something happen, you can offer
to shepherd it yourself -- or in conjunction with a member of the lang
team.** You could do this by pinging folks on discord, attending a
lang team meeting, or nominating an issue to bring it to the lang
team's attention.

## How many active shepherds can we have then?

It is important to emphasize that **having a willing shepherd is not
necessarily enough to unblock a project**. This is because, as I noted
above, assigning a shepherd is also a commitment on the part of the
lang-team -- a commitment to review progress, resolve conflicts, and
keep up with things. That puts a kind of informal cap on how many
active things can be occurring, even if there are shepherds to
spare. This is particularly true for subtle things. This cap is
probably somewhat fundamental -- even increasing the size of the lang
team wouldn't necessarily change it that much.

I don't know how many shepherds we should have at a time, I think
we'll have to work that out by experience, but I do think we should be
starting small, with a handful of items at a time. I'd much rather we
are consistently making progress on a few things than spreading
ourselves too thin.

## Expectations for a shepherd

I think the expectations for a shepherd are as follows.

First, they should **prepare updates for the lang team meeting** on a
weekly basis (even if it's "no update"). This doesn't have to be a
long detailed write-up -- even a "no update" suffices.

Second, when a design concern or conflict arises, they should help to
see it resolved. This means a few things. First and foremost, they
have to work to **understand and document the considerations at
play**, and be prepared to summarize those. (Note: they don't
necessarily have to do all this work themselves! I would like to see
us making more use of [collaborative summary documents], which allow
us to share the work of documenting concerns.)

They should also work to help resolve the conflict, possibly by
scheduling one-off meetings or through other means. I won't go into
too much detail here because I think looking into how best to resolve
design conflicts is worthy of a separate post.

Finally, while this is not a firm expectation, it is expected that
shepherds will become experts in their area, and would thus be able to
give useful advice about similar topics in the future (even if they
are not actively shepherding that area anymore).

## Expectations from the lang team

I want to emphasize this part of things. I think the lang team suffers
from the problem of doing too many things at once. Part of agreeing
that someone should shepherd topic X, I think, is agreeing that we
should be making progress on topic X.

This implies that the team agrees to follow along with the status
updates and give moderate amounts of feedback when requested. 

Of course, as the design progresses, it is natural that lang team
members will have concerns about various aspects. Just as today, we
operate on a consensus basis, so resolving those concerns is needed to
make progress. When an item has an active shepherd, though, that means
it is a priority, and this implies then that lang team members with
blocking concerns should make time to work with the shepherd and get
them resolved. (And, is always the case, this may mean accepting an
outcome that you don't personally agree with, if the rest of the team
is leaning the other way.)

## Conclusion

So, that's it! In the end, the specifics of what I propose are the following:

- We'll post on the [lang team repository] the list of active shepherds and their assigned areas.
- In order for a formal decision to be made (e.g., stabilization
  proposal accepted, RFC accepted, etc), a shepherd must be assigned. 
    - This happens at the lang team meeting. We should prepare a list of
      factors to take into account when making this decision, but one of
      the key ones is whether we agree as a team that this is something
      that is high enough priority that we can devote the required
      energy to seeing it progress.
- Shepherds will keep the lang-team updated on major developers and help to resolve
  conflicts that arise, with the cooperation of the lang-team, as described above.
    - If a shepherd seems inactive for a long time, we'll discuss if
      that's a problem.
      
## Footnotes 

[unbounded queues]: http://smallcultfollowing.com/babysteps/blog/2019/07/10/aic-unbounded-queues-and-lang-design/
[lang team repository]: https://github.com/rust-lang/lang-team/
[collaborative summary documents]: http://smallcultfollowing.com/babysteps/blog/2019/04/22/aic-collaborative-summary-documents/


