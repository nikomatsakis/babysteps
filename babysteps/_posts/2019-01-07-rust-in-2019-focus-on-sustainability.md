---
layout: post
title: 'Rust in 2019: Focus on sustainability'
categories: [Rust]
---

To me, 2018 felt like a big turning point for Rust, and it wasn't just
the edition. Suddenly, it has become "normal" for me to meet people
using Rust at their jobs. Rust conferences are growing and starting to
have large number of sponsors. Heck, I even met some professional Rust
developers amongst the parents at a kid's birthday party
recently. Something has shifted, and I like it.

At the same time, I've also noticed a lot of exhaustion. I know I feel
it -- and a lot of people I talk to seem to feel the same way. It's
great that so much is going on in the Rust world, but we need to get
better at scaling our processes up and processing it effectively.

When I think about a "theme" for 2019, the word that keeps coming to
mind for me is **sustainability**. I think Rust has been moving at a
breakneck pace since 1.0, and that's been great: it's what Rust
needed. But as Rust gains more solid footing out there, it's a good
idea for us to start looking for how we can go back and tend to the
structures we've built.

### Sustainable processes

There has been a lot of great constructive criticism of our current
processes: most recently, boat's post on [organizational debt], along
with [Florian's series of posts][fg], did a great job of crystallizing
a lot of the challenges we face. I am pretty confident that we can
adjust our processes here and make things a lot better, though
obviously some of these problems have no easy solution.

[organizational debt]: https://boats.gitlab.io/blog/post/rust-2019/
[fg]: https://yakshav.es/rust-2019/

Obviously, I don't know exactly what we should do here. But I think I
see some of the pieces of the puzzle. Here is a variety of bullet
points that have been kicking around in my head.

**Working groups.** In general, I would like to see us adopting the
idea of **working groups** as a core "organizational unit" for Rust,
and in particular as the core place where work gets done. A working
group is an ad-hoc set of people that includes both members of the
relevant Rust team but also interested volunteers. Among other
benefits, they can be a great vehicle for mentoring, since it gives
people a particular area to focus on, versus trying to participate in
the Rust project as a whole, which can be very overwhelming.

**Explicit stages.** Right now, Rust features go through a number of
official and semi-official stages before they become "stable". As I
have [argued before][staged-rfc], I think we would benefit from making
these stages a more explicit part of the process (much as e.g. the
[TC39] and [WebAssembly] groups already do).

[staged-rfc]: http://smallcultfollowing.com/babysteps/blog/2018/06/20/proposal-for-a-staged-rfc-process/
[WebAssembly]: https://github.com/WebAssembly/proposals
[TC39]: https://github.com/tc39/proposals

**Finishing what we start.** Right now, we have no mechanism to expose
the "capacity" of our teams -- we tend to, for example, accept RFCs
without any idea who will implement it, or even mentor an
implementation. In fact, there isn't really a defined set of people to
try and ensure that it happens. The result is that a lot of things
linger in limbo, either unimplemented, undocumented, or unstabilized.
**I think working groups can help to solve this, by having a core
leadership team that is committed to seeing the feature through**.

**Expose capacity.** Continuing the previous point, I think we should
integrate a notion of capacity into the staging process: so that we
avoid moving too far in the design until we have some idea who is
going to be implementing (or mentoring an implementation). If that is
hard to do, then it indicates we may not have the capacity to do this
idea right now -- **if that seems unacceptable, then we need to find
something else to stop doing**.

**Don't fly solo.** One of the things that we discussed in [a recent
compiler team steering
meeting](https://internals.rust-lang.org/t/compiler-steering-meeting/8588/16?u=nikomatsakis)
is that being the leader of a working group is **super stressful** --
it's a lot to manage!  However, being a **co-leader** of a working
group is very different. Having someone else (or multiple someones)
that you can share work with, bounce ideas off of, and so forth makes
all the difference. It's also a great mentoring opportunities, as the
leaders of working groups don't necessarily have to be full members of
the team (yet). Part of exposing capacity, then, is trying to ensure
that we don't just have one person doing any one thing -- we have
multiple. **This is scary: we will get less done. But we will all be
happier doing it.**

**Evaluate priorities regularly.** In my ideal world, we would make it
very easy to find out what each person on a team is working on, but we
would also have regular points where we evaluate whether those are the
right things. Are they advancing our roadmap goals? Did something else
more promising arise in the meantime? Part of the goal here is to
**leave room for serendipity**: maybe some random person came in from
the blue with an interesting language idea that seems really cool. We
want to ensure we aren't too "locked in" to pursue that
idea. Incidentally, this is another benefit to not "flying solo" -- if
there are multiple leaders, then we can shift some of them around
without necessarily losing context.

**Keeping everyone in sync.** Finally, I think we need to think hard
about how to help keep people in sync. The narrow focus of working
groups is great, but it can be a liability. We need to develop regular
points where we issue "public-facing" updates, to help keep people
outside the working group abreast of the latest developments.  I
envision, for example, meetings where people give an update on what's
been happening, the key decision and/or controversies, and seek
feedback on interesting points. We should probably tie these to the
stages, so that ideas cannot progress forward unless they are also
being communicated.

**TL;DR.** The points above aren't really a coherent proposal yet,
though there are pieces of proposals in them. Essentially I am calling
for a bit more structure and process, so that it is clearer what we
are doing *now* and it's more obvious when we are making decisions
about what we should do *next*. I am also calling for more redundancy.
I think that both of these things will initially mean that we do fewer
things, but we will do them more carefully, and with less stress.  And
ultimately I think they'll pay off in the form of a larger Rust team,
which means we'll have more capacity.

### Sustainable technology

So what about the technical side of things? I think the "sustainable"
theme fits here, too. I've been working on rustc for 7 years now
(wow), and in all of that time we've mostly been focused on "getting
the next goal done". This is not to say that nobody ever cleans things
up; there have been some pretty epic refactoring PRs. But we've also
accumulated a fair amount of technical debt. We've got plenty of
examples where a new system was added to replace the old -- but only
90%, meaning that now we have two systems in use. This makes it harder
to learn how rustc works, and it makes us spend more time fixing bugs
and ICEs.

I would like to see us put a lot of effort into making rustc more
approachable and maintaineable. This means writing documentation, both
of the [rustdoc] and [rustc-guide] variety. It also means finishing up
things we started but never quite finished, like replacing the
remaining uses of [`NodeId`] with the newer [`HirId`]. In some cases,
it might mean rewriting whole subsystems, such as with the trait
system and chalk.

[`NodeId`]: https://doc.rust-lang.org/nightly/nightly-rustc/syntax/ast/struct.NodeId.html
[`HirId`]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc/hir/struct.HirId.html
[rustdoc]: https://doc.rust-lang.org/nightly/nightly-rustc/rustc/?search=&search=
[rustc-guide]: https://rust-lang.github.io/rustc-guide/

None of this means we can't get new toys. Cleaning up the trait system
implementation, for example, makes things like Generic Associated
Types (GATs) and specialization much easier. Finishing the transition
into the on-demand query system should enable better incremental
compilation as well as more complete parallel compilation (and better
IDE support). And so forth.

Finally, it seems clear that we need to continue our focus on reducing
compilation time. I think we have a lot of [good avenues to
pursue][sep18] here, and frankly a lot of them are blocked on needing
to improve the compiler's internal structure.

[sep18]: https://internals.rust-lang.org/t/next-steps-for-reducing-overall-compilation-time/8429/2?u=nikomatsakis

### Sustainable finances

When one talks about sustainability, that naturally brings to mind the
question of financial sustainability as well. Mozilla has been the
primary corporate sponsor of Rust for some time, but we're starting to
see more and more sponsorship from other companies, which is
great. This comes in many forms: both Google and Buoyant have been
sponsoring people to work on the async-await and Futures proposals,
for example (and perhaps others I am unaware of); other companies have
used contracting to help get work done that they need; and of course
many companies have been sponsoring Rust conferences for years.

Going into 2019, I think we need to open up new avenues for supporting
the Rust project financially. As a simple example, having more money
to help with running CI could enable us to parallelize the bors queue
more, which would help with reducing the time to land PRs, which in
turn would help everything move faster (not to mention improving the
experience of contributing to Rust).

I do think this is an area where we have to tread carefully. I've
definitely heard horror stories of "foundations gone wrong", for
example, where decisions came to be dominated more by politics and
money than technical criteria. There's no reason to rush into things.
We should take it a step at a time.

From a personal perspective, I would love to see more people paid to
work part- or full-time on rustc. I'm not sure how best to make that
happen, but I think it is definitely important. It has happened more
than once that great rustc contributors wind up taking a job elsewhere
that leaves them no time or energy to continue contributing. These
losses can be pretty taxing on the project.

### Reference material

I already mentioned that I think the compiler needs to put more
emphasis on documentation as a means for better sustainability. I
think the same also applies to the language: I'd like to see the lang
team getting more involved with the Rust Reference and really trying
to fill in the gaps. I'd also like to see the Unsafe Code Guidelines
work continue. I think it's quite likely that these should be roadmap
items in their own right.
