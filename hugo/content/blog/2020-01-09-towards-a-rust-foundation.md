---
categories:
- Rust
- Foundation
date: "2020-01-09T00:00:00Z"
slug: towards-a-rust-foundation
title: Towards a Rust foundation
---

In [my #rust2020 blog post][2020], I mentioned rather off-handedly
that I think the time has come for us to talk about forming a Rust
foundation. I wanted to come back to this topic and talk in more
detail about what I think a Rust foundation might look like. And,
since I don't claim to have the final answer to that question by any
means, I'd also like to talk about **how** I think we should have this
conversation going forward.

[2020]: http://smallcultfollowing.com/babysteps/blog/2019/12/02/rust-2020/

### Hat tip

Before going any further, I want to say that most of the ideas in this
post arose from conversations with others. In particular, Florian
Gilcher, Ryan Levick, Josh Triplett, Ashley Williams, and I have been
chatting pretty reguarly, and this blog post generally reflects the
consensus that we seemed to be arriving at (though perhaps they will
correct me). Thanks also to Yehuda Katz and Till Schneidereit for lots
of detailed discussions.

### Why do we want a Rust foundation?

I think this is in many ways the most important question for us to
answer: what is it that we hope to achieve by creating a Rust
foundation, anyway?

To me, there are two key goals:

* to help clarify Rust's status as an independent project, and thus
  encourage investment from more companies;
* to alleviate some practical problems caused by Rust not having a
  "legal entity" nor a dedicated bank account.

There are also some anti-goals. Most notably:

* the foundation should not replace the existing Rust teams as a
  decision-making apparatus.

The role of the foundation is to complement the teams and to help us
in achieving our goals. It is not to set the goals themselves.

### Start small and iterate

You'll notice that I've outlined a fairly narrow role for the
foundation. This is no accident. When designing a foundation, just as
when designing many other things, I think it makes sense for us to
move carefully, a step at a time.

We should try to address immediate problems that we are facing and
then give those changes some time to "sink in". We should also take
time to experiment with some of the various funding possibilities that
are out there (some of which I'll discuss later on). Once we've had
some more experience, it should be easier for us to see which next
steps make sense.

Another reason to start small is being able to move more quickly. I'd
like to see us setup a foundation like the one I am discussing as soon
as this year.

### Goal #1: Clarifying Rust's status as an independent project

So let's talk a bit more about the two goals that I set forth for a
Rust foundation. The first was to clarify Rust's status as an
independent project. In some sense, this is nothing new. Mozilla has
from the get-go attempted to create an independent governance
structure and to solicit involvement from other companies, because we
know this makes Rust a better language for everyone.

Unfortunately, there is sometimes a lingering perception that Mozilla
"owns" Rust, which can discourage companies from getting invested, or
create the perception that there is no need to support Rust since
Mozilla is footing the bill. Establishing a foundation will make
official what has been true in practice for a long time: that Rust is
an independent project.

We have also heard a few times from companies, large and small, who
would like to support Rust financially, but right now there is no
clear way to do that. Creating a foundation creates a place where that
support can be directed.

### Mozilla wants to support Rust... just not alone

Now, establishing a Rust foundation doesn't mean that Mozilla plans to
step back. After all, Mozilla has a lot riding on Rust, and Rust is
playing an increasingly important role in how Mozilla builds our
products. What we really want is a scenario where other companies join
Mozilla in supporting Rust, letting us do much more.

In truth, this has already started to happen. For example, just this
year [Microsoft started sponsoring Rust's CI costs][Microsoft] and
[Amazon is paying Rust's S3 bills][Amazon]. In fact, we recently
added a [corporate sponsors] page to the Rust web site to
acknowledge the many companies that are starting to support Rust.

[Microsoft]: https://internals.rust-lang.org/t/update-on-the-ci-investigation/10056/9?u=nikomatsakis
[Amazon]: https://aws.amazon.com/blogs/opensource/aws-sponsorship-of-the-rust-project/
[corporate sponsors]: https://www.rust-lang.org/sponsors

### Goal #2: Alleviating some practical difficulties

While the Rust project has its own governance system, it has never had
its own distinct legal entity. That role has always been played by
Mozilla. For example, Mozilla owns the Rust trademarks, and Mozilla is
the legal operator for services like crates.io. This means that
Mozilla is (in turn) responsible for ensuring that DMCA requests
against those services are properly managed and so forth. For a long
time, this arrangement worked out quite well for Rust. Mozilla Legal,
for example, provided excellent help in drafting Rust's trademark
agreements and coached us through how to handle DMCA takedown requests
(which thankfully have arisen quite infrequently).

Lately, though, the Rust project has started to hit the limits of what
Mozilla can reasonably support. One common example that arises is the
need to have some entity that can legally sign contracts "for the Rust
project". For example, we wished recently to sign up for Github's
[Token Scanning] program, but we weren't able to figure out who ought
to sign the contract.

[Token Scanning]: https://developer.github.com/partnerships/token-scanning/

Is token scanning by itself a burning problem? No. We could probably
work out a solution for it, and for other similar cases that have
arisen, such as deciding who should sign Rust binaries. But it might
be a sign that it is time for the Rust project to have its own legal
entity.

### Another practical difficulty: Rust has no bank account

Another example of a "practical difficulty" that we've encountered is
that Rust has no bank account. This makes it harder for us to
arrange for joint sponsorship and support of events and other programs
that the Rust program would like to run. The most recent example is
the Rust All Hands. Whereas in the past Mozilla has paid for the
venue, catering, and much of the airfare by itself, this year we are
trying to "share the load" and have multiple companies provide
sponsorship. However, this requires a bank account to collect and pool
funds. We have solved the problem for this year, but it would be
easier if the Rust organization had a bank account of its own. I
imagine we would also make use of a bank account to fund other sorts
of programs, such as Increasing Rust's Reach.

### On paying people and contracting

One area where I think we should move slowly is on the topic of
employing people and hiring contractors. As a practical matter, the
foundation is probably going to want to employ some people. For
example, I suspect we need an "operations manager" to help us keep the
wheels turning (this is already a challenge for the core team, and
it's only going to get worse as the project grows). We may also want
to do some limited amount of contracting for specific purposes (e.g.,
to pay for someone to run a program like Increasing Rust's Reach, or
to help do data crunching on the Rust survey).

### The Rust foundation should not hire developers, at least to start

But I don't think the Rust foundation should do anything like hiring
full-time developers, at least not to start. I would also avoid trying
to manage larger contracts to hack on rustc. There are a few reasons
for this, but the biggest one is simply that it is
**expensive**. Funding that amount of work will require a significant
budget, which will require significant fund-raising.

Managing a large budget, as well as employees, will also require more
superstructure. If we hire developers, who decides what they should
work on?  Who decides when it's time to hire? Who decides when it's
time to *fire*?

This is a bit difficult: on the one hand, I think there is a strong
need for more people to get paid for their work on Rust. On the other
hand, I am not sure a foundation is the right institution to be paying
them; even if it were, it seems clear that we don't have enough
experience to know how to answer the sorts of difficult questions that
will arise as a result. Therefore, I think it makes sense to fall back
on the approach to "start small and iterate" here. Let's create a
foundation with a limited scope and see what difference it makes
before we make any further decisions.

### Some other things the foundation wouldn't do

I think there are a variety of other things that a hypothetical
foundation should not do, at least not to start. For example, I think
the foundation should not pay for local meetups nor sponsor Rust
conferences. Why?  Well, for one thing, it'll be hard for us to come
up with criteria on when to supply funds and when not to. For another,
both meetups and conferences I think will do best if they can forge
strong relationships with companies directly.

However, even if there are things that the Rust foundation wouldn't
fund or do directly, I think it makes a lot of sense to collect a list
of the kinds of things it *might* do. If nothing else, we can try to
offer suggestions for where to find funding or obtain support, or
perhaps offer some lightweight "match-making" role.

### We should strive to have many kinds of Rust sponsorship 

Overall, I am nervous about a situation in which a Rust Foundation
comes to have a kind of "monopoly" on supporting the Rust project or
Rust-flavored events. I think it'd be great if we can encourage a
wider variety of setups. First and foremost, I'd like to see more
companies that use Rust hiring people whose job description is to
support the Rust project itself (at least in part). But I think it
could also work to create "trade associations" where multiple
companies pool funds to hire Rust developers. If nothing else, it is
worth experimenting with these sorts of setups to help gain
experience.

### We should create a "project group" to figure this out

Creating a foundation is a complex task. In this blog post, I've just
tried to sketch the "high-level view" of what responsiblities I think
a foundation might take on and why (and which I think we should avoid
or defer). But I left out a lot of interesting details: for example,
should the Foundation be a 501(c)(3) (a non-profit, in other words) or
not? Should we join an umbrella organization and -- if so -- which
one?

The traditional way that the Rust project makes decisions, of course,
is through RFCs, and I think that a decision to create a foundation
should be no exception. In fact, I do plan to open an RFC about
creating a foundation soon. However, I **don't** expect this RFC to
try to spell out all the details of how a foundation would
work. Rather, I plan to propose creating a **project group** with the
goal of answering those questions.

In short, I think the core team should select some set of folks who
will explore the best design for a foundation. Along the way, we'll
keep the community updated with the latest ideas and take feedback,
and -- in the end -- we'll submit an RFC (or perhaps a series of RFCs)
with a final plan for the core team to approve.

### Feedback

OK, well, enough about what I think. I'm very curious (and a bit
scared, I won't lie) to hear what people think about the contents of
this post. To collect feedback, I've created a [thread on
internals]. As ever, I'll read all the responses, and I'll do my best
to respond where I can. Thanks!

[thread on internals]: https://internals.rust-lang.org/t/blog-post-towards-a-rust-foundation/11601
