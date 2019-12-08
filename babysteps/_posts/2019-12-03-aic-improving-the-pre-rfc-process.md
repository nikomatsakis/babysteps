---
layout: post
title: "AiC: Improving the pre-RFC process"
categories: [Rust, Consensus]
---

I want to write about an idea that Josh Triplett and I have been
iterating on to revamp the lang team RFC process. I have written a
[draft] of an RFC already, but this blog post aims to introduce the
idea and some of the motivations. The key idea of the RFC is formalize
the steps leading *up* to an RFC, as well as to capture the lang team
operations around **project groups**. The hope is that, if this
process works well, it can apply to teams beyond the lang team as
well.

[draft]: https://github.com/nikomatsakis/project-staged-rfcs/blob/master/rfcs/0001-shepherded-rfcs.md

### TL;DR

In a nutshell, the [proposal][draft] is this:

* When you see a problem you think we should try to solve, you open an
  issue on the [lang-team] repository. This is called a **[proposal issue]**.
* In the **[proposal issue]**, you include a description of the problem
  and a link to a thread on [internals] where the problem is being
  discussed.
    * You might have a sketch of a solution in mind, but that's not
      required. Even if there is a possible solution, we would always
      expect to start by looking at different alternatives as well, to
      make sure we're headed in the overall direction.
    * Proposals would not be expected to use the full RFC
      template. The idea is to be lightweight.
    * It is important that discussion does **not** take place on the issue.
* The lang-team [periodically reviews those issues][r?]. If someone on the
  team likes the idea, we will create a "project group" around the
  design. Each project group has a repository, a [lang team liaison], and
  one or more [shepherds][sh]. The repository houses the draft RFC and
  potentially other documents, such as design notes.
* The project group will continue working on the idea until it is
  complete, meaning that the design has been implemented and become
  stable. For smaller ideas, this could go quite quickly; for larger
  ideas, it might take longer. (Of course, we may also decide to
  cancel the idea at some point.)

[r?]: https://github.com/nikomatsakis/project-staged-rfcs/blob/master/rfcs/0001-shepherded-rfcs.md#reviewing-proposals
[proposal issue]: https://github.com/nikomatsakis/project-staged-rfcs/blob/master/rfcs/0001-shepherded-rfcs.md#proposal-issues
[sh]: https://github.com/nikomatsakis/project-staged-rfcs/blob/master/rfcs/0001-shepherded-rfcs.md#shepherds
[lang team liaison]: https://github.com/nikomatsakis/project-staged-rfcs/blob/master/rfcs/0001-shepherded-rfcs.md#lang-team-liason
[lang-team]: https://github.com/rust-lang/lang-team/
[internals]: https://internals.rust-lang.org/

Note that I did not say anything yet about the main RFCs repository.
The idea is that, when a project group feels the design is ready, they
will open the RFC on the main repository. At that point, the RFC
represents a design that has already undergone a fair amount of
iteration. Moreover, the shepherds and lang team liaison should ensure
that the lang team is getting regular updates on the
progress. **Therefore, the RFC process itself should go significantly
faster.**

One of my hopes is that a lighter and faster RFC process will also
mean that we can use RFCs for smaller decisions, and not just the
final design. For example, I think it'd be useful to write an RFC
documenting a major choice in the direction, and then have follow-up
RFCs that work out some of the details. (This is somewhat similar to
the eRFC idea that [we used for coroutines][2033] but never
formalized.)

[2033]: https://github.com/rust-lang/rfcs/blob/master/text/2033-experimental-coroutines.md

### Goal: Increased transparency

One of the goals here is to increase our **transparency** --
specifically, I want it to be easier to follow along with the design
that is taking place. I also want you to be able to control how
"deeply" you follow along. I think that this proposal helps in two
ways:

* First, the lang team will have an active list of **project groups**
  which represent the work that is being monitored by the team. This alone
  gives a good overview of what we're doing.
* Each project group should also have a repository documenting their
  meetings and communication channels. A well-run group will also have
  links to blog posts, discussion articles, or other documents. So if
  you want to dig deeper into a design, or get involved, you can do it
  that way.
* Finally, the RFC repo itself is a good way to get an overview of
  "major" decisions that are taking place. Monitoring this repo would
  be a good way for you to raise a red flag if you see something that
  has been overlooked. However, since RFCs will often be the result
  of a lot more iteration and design, it wouldn't be the best place
  for smaller bikeshedding.

One thing that is worth emphasizing is that RFCs in this model will
not be 'early stage' ideas. They will be the result of a lot more
iteration. This will frequently mean that we are not looking for
"general feedback" so much as specific, useful criticism.

### Goal: Clearer on-ramp

Another goal is to make a clearer "on-ramp" for getting the lang
team's attention. Right now, there isn't really a good way to
"propose" an idea and bring it to the lang team's attention. You can
create a thread on internals, but that is not guaranteed to be
seen. You can open an RFC, but if the idea is half-baked, you will get
pushback, and if it's highly developed, you might find that you've
been going down the wrong road.

I feel like this procedure offers a clearer "invitation" for bringing
an idea forward. I think it's important though that we couple it with
lang-team procedures that help us ensure that we stay on top of
meeting proposals.

### Putting this idea into practice

One question that arises with this idea is what to do with the
existing RFC PRs on the repository. If we adopt this proposal, my plan
is to encourage authors to migrate those PRs to proposal issues
instead. After some period of time, we will close the RFC PRs (except
for those that have an active project group behind them). We could
also consider an automatic migration, but I think it might be useful
to be a bit more selective.

### Lang team practice and serendipity

Although it is not part of the RFC proper, I think that it is also
important for the lang-team to restructure how we operate a bit. I
would like us to use project groups to expose and declare the things
we are actively working on, and I think we should devote *most* of our
time to those things. But I also think we should reserve some time for
ideas that are not on that list.

I have two goals here. First, sometimes there are just smaller ideas
that will never be a kind of "top priority" but are nonetheless nice
to have. A prime example might be a syntactic addition like `if let`.

Second, sometimes there are nice ideas like [RFC 2580]. These ideas
have been well developted, and it might be good to move forward, but
it's hard to find the time to discuss them. As a result, the RFCs hang
about in a sort of "limbo", where it's totally unclear whether
anything will ever happen.

I also expect that as part of this we will impose cerain limits.  For
example, I don't think any one person should be shepherding or serving
as a liason for more than a few things at a time -- possibly just one
if the proposal is big enough. That will put an overall cap on how
much the lang team can try to do at one time, but that seems like a
good limit. The [Shepherding 3.0][3.0] blog post had more notes on
this topic.

I am hoping that if we have a clearer meeting queue, we can put ideas
like that on the list, and at least there will be a clear time to
discuss and decide definitively whether we can indeed move forward or
not.

[RFC 2580]: https://github.com/rust-lang/rfcs/pull/2580
[3.0]: http://smallcultfollowing.com/babysteps/blog/2019/09/11/aic-shepherds-3-0/

### Conclusion

In general, you can think of the RFC process as a kind of "funnel"
with a number of stages. We've traditionally thought of the process as
beginning at the point where an RFC with a complete design is opened,
but of course the design process **really** begins much
earlier. Moreover, a single bit of design can often span multiple
RFCs, at least for complex features -- moreover, at least in our
current process, we often have changes to the design that occur during
the implementation stage as well. This can sometimes be difficult to
keep up with, even for lang-team members.

This post describes a revision to the process that aims to "intercept"
proposals at an earlier stage. It also proposes to create "project
groups" for design work and a dedicated repository that can house
documents. For smaller designs, these groups and repositories might be
small and simple. But for larger designs, they offer a space to
include a lot more in the way of design notes and other documents. 

Assuming we adopt this process, one of the things I think we should be
working on is developing "best practices" around these
repositories. For example, I think that for every non-trivial design
decision, we should be creating a [summary document] that describes
the pros/cons and the eventual decision (along with, potentially,
comments from people who disagreed with that decision outlining their
reasoning).

[summary document]: http://smallcultfollowing.com/babysteps/blog/2019/04/22/aic-collaborative-summary-documents/

We are already starting to experiment with this sort of process.  The
[FFI-unwind project group], for example, is pursuing an attempt to
decide on the rules regarding unwinding across FFI boundaries. And, as
I noted in [my post announcing the Async Interviews][async], I'd like
to see us collecting design notes for new traits and features that we
propose in the async space.

[FFI-unwind project group]: https://github.com/rust-lang/project-ffi-unwind
[async]: http://smallcultfollowing.com/babysteps/blog/2019/11/22/announcing-the-async-interviews/

As always, I'd love to hear your feedback. Please leave any comments
in the [internals thread devoted to the "Adventures in Consensus"
series][AiC].

[AiC]: https://internals.rust-lang.org/t/aic-adventures-in-consensus/9843

### Thanks

I just wanted to add a "Thank you!" to Josh Triplett, who co-developed
a lot of these specific ideas with me, but also Withoutboats, Yoshua
Wuyts, Centril, Steve Klabnik, and the many others that have been
discussing variants of this proposal with me over time.
