---
categories:
- Rust
date: "2019-03-01T00:00:00Z"
slug: async-await-status-report
title: Async-await status report
---

I wanted to post a quick update on the status of the async-await
effort. The short version is that we're in the **home stretch** for
some kind of stabilization, but there remain some significant
questions to overcome.

## Announcing the implementation working group

As part of this push, I'm happy to announce we've formed a
[**async-await implementation working group**][wg]. This working group
is part of the whole async-await effort, but focused on the
implementation, and is part of the compiler team. If you'd like to
help get async-await over the finish line, we've got a list of issues
where we'd definitely like help (read on).

**If you are interested in taking part, we have an "office hours"
scheduled for Tuesday (see the [compiler team calendar])** -- if you
can show up then on [Zulip], it'd be ideal! (But if not, just pop in any
time.)

[wg]: https://github.com/rust-lang/compiler-team/blob/master/README.md
[compiler team calendar]: https://github.com/rust-lang/compiler-team#meeting-calendar[
[Zulip]: https://github.com/rust-lang/compiler-team/blob/master/about/chat-platform.md

## Who are we stabilizing for? 

I mentioned that there remain significant questions to overcome before
stabilization. I think the most root question of all is this one:
**Who is the audience for this stabilization?**

The reason that question is so important is because it determines how
to weigh some of the issues that currently exist. If the point of the
stabilization is to start promoting async-await as something for
**widespread use**, then there are **issues that we probably ought to
resolve first** -- most notably, the `await` syntax, but also other
things.

If, however, the point of stabilization is to let **'early adopters'**
start playing with it more, then **we might be more tolerant of
problems**, so long as there are no backwards compatibility concerns.

My take is that either of these is a perfectly fine answer. But **if
the answer is that we are trying to unblock early adopters, then we
want to be clear in our messaging**, so that people don't get turned
off when they encounter some of the bugs below.

OK, with that in place, let's look in a bit more detail.

## Implementation issues

One of the first things that we did in setting up the implementation
working group is to do a [complete triage of all existing async-await
issues][triage-paper]. From this, we found that there was one very
firm blocker, [#54716][]. This issue has to do the timing of drops in
an async fn, specifically the drop order for parameters that are not
used in the fn body.  We want to be sure this behaves analogously with
regular functions. This is a blocker to stabilization because it would
change the semantics of stable code for us to fix it later.

[triage-paper]: https://paper.dropbox.com/doc/Async-Await-Triage-2019.02.20--AYdZ6puVcqdJ0Jnu37FRiisiAg-ZyzRUbTENfdgFjCRja2vm
[#54716]: https://github.com/rust-lang/rust/issues/54716

We also uncovered a number of **major ergonomic problems**. In a
follow-up meeting ([available on YouTube][implvideo]), cramertj and I
also drew up plans for **fixing these bugs**, though these plans have
not yet been writting into mentoring instructions. These issues
include all focus around async fns that take borrowed references as
arguments -- for example, the [async fn syntax today doesn't support
more than one lifetime in the
arguments](https://github.com/rust-lang/rust/issues/56238), so
something like `async fn foo(x: &u32, y: &u32)` doesn't work.

[implvideo]: https://youtu.be/xe2_whJWBC0

Whether these ergonomic problems are **blockers**, however, depends a
bit on your perspective: as @cramertj says, a number of folks at
Google are using async-await today productively despite these
limitations, but you must know the appropriate workarounds and so
forth. **This is where the question of our audience comes into play.**
My take is that these issues are blockers for "async fn" being ready
for "general use", but probably not for "early adopters".

Another big concern for me personally is the **maintenance story**.
Thanks to the hard work of Zoxc and cramertj, we've been able to
standup a functional async-await implementation very fast, which is
awesome. But we don't really have a large pool of active contributors
working on the async-await implementation who can help to fix issues
as we find them, and this seems bad.

## The syntax question

Finally, we come to the question of the `await` syntax. At the All
Hands, we had a number of conversations on this topic, and it became
clear that **we do not presently have consensus for any one syntax**.
We did a **lot** of exploration here, however, and enumerated a number
of subtle arguments in favor of each option. At this moment,
@withoutboats is busily trying to write-up that exploration into a
document.

Before saying anything else, it's worth pointing out that we don't
actually **have** to resolve the `await` syntax in order to stabilize
async-await. We could stabilize the `await!(...)` macro syntax for the
time being, and return to the issue later. This would unblock "early
adopters", but doesn't seem like a satisfying answer if our target is
the "general public". If we were to do this, we'd be drawing on the
precedent of `try!`, where we first adopted a macro and later moved
that support to native syntax.

That said, we do **eventually** want to pick another syntax, so it's
worth thinking about how we are going to do that. As I wrote, the
first step is to complete an overall summary that tries to describe
the options on the table and some of the criteria that we can use to
choose between them. Once that is available, we will need to settle on
next steps.

## Resolving hard questions

I am looking at the syntax question as a kind of opportunity -- one of
the things that we as a community frequently have to do is to find a
way to **resolve really hard questions without a clear answer**. The
tools that we have for doing this at the moment are really fairly
crude: we use discussion threads and manual summary
comments. Sometimes, this works well. Sometimes, amazingly well. But
other times, it can be a real drain.

I would like to see us trying to resolve this sort of issue in other
ways. I'll be honest and say that I don't entirely know what those
are, **but I know they are not open discussion threads**. For example,
I've found that the \#rust2019 blog posts have been an incredibly
effective way to have an open conversation about priorities without
the usual ranchor and back-and-forth. I've been very inspired by
systems like [vTaiwan][], which enable a lot of public input, but in a
structured and collaborative form, rather than an "antagonistic"
one. Similarly, I would like to see us perhaps consider running more
*experiments* to test hypotheses about learnability or other factors
(but this is something I would approach with great caution, as I think
designing good experiments is very hard).

[vTaiwan]: https://www.technologyreview.com/s/611816/the-simple-but-ingenious-system-taiwan-uses-to-crowdsource-its-laws/

Anyway, this is really a topic for a post of its own. In this
particular case, I hope that we find that enumerating in detail the
arguments for each side leads us to a clear conclusion, perhaps some
kind of "third way" that we haven't seen yet. But, thinking ahead,
it'd be nice to find ways to have these conversations that take us to
that "third way" faster.

## Closing notes

As someone who has not been closely following async-await thus far,
I'm super excited by all I see. The feature has come a ridiculously
long way, and the remaining blockers all seem like things we can
overcome. async await is coming: I can't wait to see what people build
with it.

[Cross-posted to internals here.](https://internals.rust-lang.org/t/async-foundations-working-group-status/9540/2?u=nikomatsakis)
