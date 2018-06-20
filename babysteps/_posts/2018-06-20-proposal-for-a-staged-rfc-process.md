---
layout: post
title: Proposal for a staged RFC process
categories: [Rust]
---

I consider Rust's RFC process one of our great accomplishments, but
it's no secret that it has a few flaws. At its best, the RFC offers an
opportunity for collaborative design that is really exciting to be a
part of. At its worst, it can devolve into bickering without any real
motion towards consensus. If you've not done so already, I strongly
recommend reading aturon's [excellent][a1] [blog][a2] [posts][a3] on
this topic.

[a1]: http://aturon.github.io/2018/05/25/listening-part-1/
[a2]: http://aturon.github.io/2018/06/02/listening-part-2/
[a3]: http://aturon.github.io/2018/06/18/listening-part-3/

The RFC process has also evolved somewhat organically over time. What
began as "just open a pull request on GitHub" has moved into a process
with a number of formal and informal stages (described below). I think
it's a good time for us to take a step back and see if we can refine
those stages into something that works better for everyone.

This blog post describes a proposal that arose over some discussions
at the Mozilla All Hands. This proposal represents an alternate take
on the RFC process, drawing on some ideas from [the TC39
process][tc39], but adapting them to Rust's needs. I'm pretty excited
about it.

**Important:** This blog post is meant to advertise a **proposal**
about the RFC process, not a final decision. I'd love to get feedback
on this proposal and I expect further iteration on the details. In any
case, until the Rust 2018 Edition work is complete, we don't really
have the bandwidth to make a change like this. (And, indeed, most of
my personal attention remains on NLL at the moment.)

[tc39]: https://tc39.github.io/process-document/

## TL;DR

The TL;DR of the proposal is as follows:

- **Explicit RFC stages.** Each proposal moves through a [series of
  explicit stages][diagram].
- **Each RFC gets its own repository.** These are automatically
  created by a bot. This permits us to use GitHub issues and pull
  requests to split up conversation. It also permits a RFC to have
  multiple documents (e.g., a FAQ).
- **The repository tracks the proposal from the early days until
  stabilization.** Right now, discussions about a particular proposal
  are scattered across internals, RFC pull requests, and the Rust
  issue tracker. Under this new proposal, a single repository would
  serve as the home for the proposal. In the case of more complex
  proposals, such as `impl Trait`, the repository could even serve as
  the home multiple layered RFCs.
- **Prioritization is now an explicit part of the process.** The new
  process includes an explicit step to move from the "spitballing"
  stage (roughly "Pre-RFC" today) to the "designing" stage (roughly
  "RFC" today). This step requires both a team champion, who agrees to
  work on moving the proposal through implementation and towards
  stabilization, and general agreement from the team. The aim here is
  two-fold.  First, the teams get a chance to provide early feedback
  and introduce key constraints (e.g., "this may interact with feature
  X"). Second, it provides room for a discussion about prioritization:
  there are often RFCs which are *good ideas*, but which are not a
  good idea *right now*, and the current process doesn't give us a way
  to specify that.
- **There is more room for feedback on the final, implemented
  design.** In the new process, once implementation is complete, there
  is another phase where we (a) write an explainer describing how the
  feature works and (b) issue a general call for evaluation. We've
  done this before -- such as cramertj's [call for feedback on `impl
  Trait`](https://internals.rust-lang.org/t/help-test-impl-trait/6516),
  aturon's call to [benchmark incremental
  compilation](https://internals.rust-lang.org/t/help-us-benchmark-incremental-compilation/6153),
  or alexcrichton's [push to stabilize some subset of procedural
  macros](https://internals.rust-lang.org/t/help-stabilize-a-subset-of-macros-2-0/7252)
  -- but each of those was an informal effort, rather than an explicit
  part of the RFC process.  

## The current process

Before diving into the new process, I want to give my view of the
*current* process by which an idea becomes a stable feature. This goes
beyond just the RFC itself. In fact, there are a number of stages,
though some of them are informal or sometimes skipped:

- **Pre-RFC (informal):** Discussions take place -- often on internals -- 
  about the shape of the problem to be solved and possible proposals.
- **RFC:** A specific proposal is written and debated. It may be changed during
  this debate as a result of points that are raised.
  - **Steady state:** At some point, the discussion reaches a "steady
    state". This implies a kind of consensus -- not necessarily a
    consensus about what **to do**, but a consensus on the pros and
    cons of the feature and the various alternatives.
    - Note that reaching a steady state does not imply that no new comments
      are being posted. It just implies that the **content** of those comments
      is not new.
  - **Move to merge:** Once the steady state is reached, the relevant team(s) can
    move to **merge** the RFC. This begins with a bunch of checkboxes, where
    each team member indicates that they agree that the RFC should be merged;
    in some cases, blocking concerns are raised (and resolved) during this
    process.
  - **FCP:** Finally, once the team has assented to the merge, the RFC
    enters the Final Comment Period (FCP). This means that we wait for
    10 days to give time for any final arguments to arise.
- **Implementation:** At this point, a tracking issue on the Rust repo
  is created. This will be the new home for discussion about the
  feature. We can also start writing code, which lands under a feature
  gate.
  - **Refinement:** Sometimes, after implementation the feature, we
  find that the original design was inconsistent, in which case we
  might opt to alter the spec. Such alterations are discussed on the
  tracking issue -- for significant changes, we will typically open a
  dedicated issue and do an FCP process, just like with the original
  RFC. A similar procedure happens for resolving unresolved questions.
- **Stabilization:** The final step is to move to stabilize. This is
  always an FCP decision, though the precise protocol varies. What I
  consider Best Practice is to create a dedicated issue for the
  stabilization: this issue should describe what is being stabilized,
  with an emphasis on (a) what has changed since the RFC, (b) tests
  that show the behavior in practice, and (c) what remains to be
  stabilized. (An example of such an issue is [#48453][], which
  proposed to stabilize the `?` in main feature.)

[#48453]: https://github.com/rust-lang/rust/issues/48453
  
## Proposal for a new process

The heart of the new proposal is that each proposal should go through
a series of explicit stages, depicted graphically here (you can also
view this [directly on Gooogle drawings][diagram], where the
oh-so-important emojis work better):

[diagram]: https://docs.google.com/drawings/d/11KtHLYsqJzi2_Y3mOBz2FbXeG3verSHz-PFBuiwYIQw/edit?usp=sharing

<div>
<img src="{{ site.baseurl }}/assets/2018-06-20-rfc-stages.svg" width="893" height="760"/>
</div>

You'll notice that the stages are divided into two groups. **The
stages on the left represent phases where significant work is being
done**: they are given "active" names that end in "ing", like
spitballing, designing, etc. The bullet points below describe the work
that is to be done. As will be described shortly, this work is done on
a dedicated repository, by the community at large, in conjunction with
at least one team champion.

**The stages on the right represent decision points, where the
relevant team(s) must decide whether to advance the RFC to the next
stage.** The bullet points below represent the questions that the team
must answer. If the answer is Yes, then the RFC can proceed to the
next stage -- note that sometimes the RFC can proceed, but unresolved
questions are added as well, to be addressed at a later stage.

### Repository per RFC

Today, the "home" for an RFC changes over the course of the
process. It may start in an internals thread, then move to the RFC
repo, then to a tracking issue, etc. Under the new process, we would
instead create a **dedicated repository for each RFC**. Once created,
the RFC would serve as the "main home" for the new proposal from start
to finish.

The repositories will live in the `rust-rfcs` organization. There will
be a convenient webpage for creating them; it will create a repo that
has an appropriate template and which is owned by the appropriate Rust
team, with the creator also having full permissions. These
repositories would naturally be subject to Rust's Code of Conduct and
other guidelines.

**Note that you do not have to seek approval from the team to create a
RFC repository.** Just like opening a PR, creating a repository is
something that anyone can do. The expectation is that the team will be
tracking new repositories that are created (as well as those seeing a
lot of discussion) and that members of the team will get involved when
the time is right.

The goal here is to create the repository early -- even before the RFC
text is drafted, and perhaps before there exists a specific
proposal. This allows joint authorship of RFCs and iteration in the
repository.

In addition to create a "single home" for each proposal, having a
dedicated RFC allows for a number of new patterns to emerge:

- One can create a `FAQ.md` that answers common questions and summarizes
  points that have already reached consensus.
- One can create an `explainer.md` that documents the feature and
  explains how it works -- in fact, creating such docs is mandatory
  during the "implementing" phase of the process.
- We can put more than one RFC into a single repository. Often, there
  are complex features with inter-related (but distinct) aspects, and
  this allows those different parts to move through the stabilization
  process at a different pace.

### The main RFC repository

The main RFC repository (named `rust-rfcs/rfcs` or something like that)  
would no longer contain content on its own, except possibly the final
draft of each RFC text. Instead, it would primarily serve as an index
into the other repositories, organized by stage (similar to [the TC39
`proposals` repository][tc39-proposals]). 

The purpose of this repository is to make it easy to see "what's
coming" when it comes to Rust. I also hope it can serve as a kind of
"jumping off point" for people contributing to Rust, whether that be
through design input, implementation work, or other things.

[tc39-proposals]: https://github.com/tc39/proposals

### Team champions and the mechanics of moving an RFC between stages

One crucial role in the new process is that of the **team
champion**. The team champion is someone from the Rust team who is
working to drive this RFC to completion. Procedurally speaking, the
team champion has two main jobs. First, they will give periodic
updates to the Rust team at large of the latest developments, which
will hopefully identify conflicts or concerns early on.
  
The second job is that **team champions decide when to try and move the
RFC between stages**. The idea is that it is time to move between stages
when two conditions are met:

- The discussion on the repository has reached a "steady state",
  meaning that there do not seem to be new arguments or
  counterarguments emerging. This sometimes also implies a general
  consensus on the design, but not always: it does however imply
  general agreement on the contours of the design space and the
  trade-offs involved.
- There are good answers to the questions listed for that stage.

The actual mechanics of moving an RFC between stages are as
follows. First, although not strictly required, the team champion
should open an issue on the RFC repository proposing that it is time
to move between stages. This issue should contain a draft of the
report that will be given to the team at large, which should include
summary of the key points (pro and con) around the design. Think of
like a [summary comment][] today. This issue can go through an FCP
period in the same way as today (though without the need for
checkmarks) to give people a chance to review the summary.

[summary comment]: https://github.com/rust-lang/rfcs/pull/1909#issuecomment-327565150

At that point, the team champion will open a PR on the **main
repository** (`rust-rfcs/rfcs`).  This PR itself will not have a lot
of content: it will mostly edit the index, moving the PR to a new
stage, and -- where appropriate -- linking to a specific revision of
the text in the RFC repository (this revision then serves as "the
draft" that was accepted, though of course further edits can and will
occur). It should also link to the issue where the champion proposed
moving to the next stage, so that the team can review the comments
found there.

The PRs that move an RFC between stages are primarily intended for the
Rust team to discuss -- they are not meant to be the source of
sigificant discussion, which ought to be taking place on the
repository. If one looks at the current RFC process, they might
consist of roughly the set of comments that typically occur once FCP
is proposed. The teams should ensure that a decision (yay or nay) is
reached in a timely fashion.

Finding the best way for teams to govern themselves to ensure prompt
feedback remains a work in progress. The TC39 process is all based
around regular meetings, but we are hoping to achieve something more
asynchronous, in part so that we can be more friendly to people from
all time zones, and to ease language barriers. But there is still a
need to ensure that progress is made. I expect that weekly meetings will
continue to play a role here, if only to nag people.

### Using stages to guide conversation

One of the things I am excited about in this proposal is that we can
use the explicit stage -- as well as the dedicated repository! -- to
help guide conversations. For example, during the spitballing phase,
it seems clear that the conversation should be focused on exploring
the motivation and unearthing constraints. Similarly, it often happens
we come across quandries that are hard to resolve until after we have
gained more experience using the feature -- often choosing what should
be the default behavior has this character, for example. The staged
process lets us explicitly revisit those concerns at the right time.

However, one concern that has arisen in the TC39 process is that this
same character can make it hard to object to a feature on "global" or
"cross-cutting" grounds. For example, it may be that there are two
features which are individually acceptable but which -- taken together
-- seem to blow the language complexity budget. How do you decide
between them and when does this decision get made?

In the current proposal, I think that the answer is *most likely* at
the Proposal stage. More generally, we aim to address these sorts of
concerns of controlling scope in a few ways:

- By ensuring that features are tied to the roadmap, which should
  ensure they have solid (and timely) motivation.
- By requiring a Team Champion to advance through the process, which
  should generally ensure that there is enough interest in a proposal
  and bandwidth to see it through.
- By having frequent check-ins with teams, who are charged to care for
  cross-cutting concerns.

Overall, though, I think this is an area where we will continue
iterating -- we might want some more dedicated way of tracking the
"overall budget" for Rust as a whole.

### Making implicit stages explicit

There are two new points in the process that I want to highlight.
Both of these represents an attempt to take "implicit" decision points
that we used to have and make them more explicit and observable.

#### The Proposal point and the change from Spitballing to Designing

The very first stage in the RFC is going from the Spitballing phase to
the Designing phase -- this is done by presenting a **Proposal**. One
crucial point is that **there doesn't have to be a primary design in
order to present a proposal**. It is ok to say "here are two or three
designs that all seem to have advantages, and further design is needed
to find the best approach" (often, that approach will be some form of
synthesis of those designs anyway).

The main questions to be answered at the proposal have to do with
**motivation and prioritization**. There are a few questions to answer:

- Is this a problem we want to solve?
  - And, specifically, is this a problem we want to solve **now**?
- Do we think we have some realistic ideas for solving it?
  - Are there major things that we ought to dig into.
  
The expectation is that all major proposals need to be connected to
the roadmap. This should help to keep us focused on the work we are
supposed to be doing. (I think it is possible for RFCs to advance that
are not connected to the roadmap, but they need to be simple
extensions that could effectively work at any time.)

There is another way that having an explicit Proposal step addresses
problems around prioritization. Creating a Proposal requires a Team
Champion, which implies that there is enough team bandwidth to see the
project through to the end (presuming that people don't become
champions for more than a few projects at a time). If we find that
there aren't enough champions to go around (and there aren't), then
this is a sign we need to grow the teams (something we've been trying
hard to do).

The Proposal point also offers a chance for other team members to
point out constraints that may have been overlooked. These constraints
wouldn't really serve to derail the proposal, just to add new points
that should be addressed during the Designing phase.

#### The Candidate point and the Evaluating phase

Another new addition to the process here is the Evaluation phase. The idea here
is that, once implementation is complete, we should do two things:

- Write up an explainer that describes how the feature works in terms
  suitable for end users. This is a kind of "preliminary"
  documentation for the feature.  It should explain how to enable the
  feature, what it's good for, and give some examples of how to use
  it.
  - For libraries, the explainer may not be needed, as the API docs serve
    the same purpose.
  - We should in particular cover points where the design has changed
    significantly since the "Draft" phase.
- Propose the RFC for **Candidate** status. If accepted, we will also
  issue a general call for evaluation. This serves as a kind of
  "pre-stabilization" notice.  It means that people should go take the
  new feature for a spin, kick the tires, etc.  This will hopefully
  uncover bugs, but also surprising failure modes, ergonomic hazards,
  or other pitfalls with the design. If any significant problems are
  found, we can correct them, update the explainer, and repeat until
  we are satisfied.

As I noted earlier, we've done this before, but always informally:

- cramertj's [call for feedback on `impl Trait`](https://internals.rust-lang.org/t/help-test-impl-trait/6516);
- aturon's call to [benchmark incremental compilation](https://internals.rust-lang.org/t/help-us-benchmark-incremental-compilation/6153);
- alexcrichton's [push to stabilize some subset of procedural macros](https://internals.rust-lang.org/t/help-stabilize-a-subset-of-macros-2-0/7252).

Once the evaluation phase seems to have reached a conclusion, we would
move to **stabilize** the feature. The explainer docs would then
become the preliminary documentation and be added to a kind of
addendum in the Rust book. The docs would be expected to integrate the
docs into the book in smoother form sometime after synchronization.

## Conclusion

As I wrote before, this is only a preliminary proposal, and I fully
expect us to make changes to it. Timing wise, I don't think it makes
sense to pursue this change immediately anyway: we've too much going
on with the edition. But I'm pretty excited about revamping our RFC
processes both by making stages explicit and adding explicit
repositories.

I have hopes that we will find ways to use explicit repositories to
drive discussions towards consensus faster. It seems that having the
ability, for example, to document "auxiliary" documents, such as lists
of constraints and rationale, can help to ensure that people's
concerns are both heard and met.

In general, I would also like to start trying to foster a culture of
"joint ownership" of in-progress RFCs. Maintaining a good RFC
repository is going to be a fair amount of work, which is a great
opportunity for people at large to pitch in. This can then serve as a
kind of "mentoring on ramp" getting people more involved in the lang
team. Similarly, I think that having a list of RFCs that are in the
"implementation" phase might be a way to help engage people who'd like
to hack on the compiler.

**Credits.** As I noted before, this proposal is heavily shaped by
[the TC39 process][tc39]. This particular version was largely drafted
in a big group discussion with [wycats], [aturon], [ag_dubs],
[steveklabnik], [nrc], [jntrnr], [erickt], and [oli-obk], though
earlier proposals also involved a few others.

[aturon]: https://github.com/aturon
[wycats]: https://twitter.com/wycats
[ag_dubs]: https://twitter.com/ag_dubs/
[jntrnr]: https://twitter.com/jntrnr/
[erickt]: https://github.com/erickt/
[steveklabnik]: https://github.com/steveklabnik/
[nrc]: https://github.com/nrc/
[oli]: https://github.com/oli-obk/


