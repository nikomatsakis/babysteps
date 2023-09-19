---
layout: post
title: More than coders
categories: [Rust, Governance]
---

Lately, the compiler team has been changing up the way that we work.
Our goal is to make it easier for people to track what we are doing
and -- hopefully -- get involved. This is an ongoing effort, but one
thing that has become clear immediately is this: the compiler team
needs more than coders.

Traditionally, when we've thought about how to "get involved" in the
compiler team, we've thought about it in terms of writing PRs. But
more and more I'm thinking about all the *other* jobs that go into
maintaining the compiler. **"What kinds of jobs are these?", you're
asking.** I think there are quite a few, but let me give a few
examples:

- **Running a meeting** -- pinging folks, walking through the agenda.
- **Design documents and other documentation** -- describing how the
  code works, even if you didn't write it yourself.
- **Publicity** -- talking about what's going on, tweeting about
  exciting progress, or helping to circulate calls for help. Think
  [steveklabnik], but for rustc.
- ...and more! These are just the tip of the iceberg, in my opinion.

[steveklabnik]: https://twitter.com/steveklabnik/

**I think we need to surface these jobs more prominently and try to
actively recruit people to help us with them.** Hence, this blog post.

## "We need an open source whenever"

In [my keynote at Rust LATAM][latam], I quoted quite liberally from an
excellent blog post by Jessica Lord, ["Privilege, Community, and Open
Source"][jlord]. There's one passage that keeps coming back to me:

> We also need an open source *whenever*. Not enough people can or
> should be able to spare all of their time for open source work, and
> appearing this way really hurts us.

[latam]: https://nikomatsakis.github.io/rust-latam-2019/#1
[jlord]: http://jlord.us/blog/osos-talk.html

This passage resonates with me, but I also know it is not as simple as
she makes it sound. Creating a structure where people can meaningfully
contribute to a project with only small amounts of time takes a lot of
work. But it seems clear that the benefits could be huge.

I think looking to tasks beyond coding can be a big benefit
here. Every sort of task is different in terms of what it requires to
do it well -- and I think the more *ways* we can create for people to
contribute, the more people will be *able* to contribute.

## The context: working groups

Let me back up and give a bit of context. Earlier, I mentioned that
the compiler has been changing up the way that we work, with the goal
of making it much easier to get involved in developing rustc. A big
part of that work has been introducing the idea of a **working
group**.

A **working group** is basically an (open-ended, dynamic) set of
people working towards a particular goal. These days, whenever the
compiler team kicks off a new project, we create an associated working
group, and we list that group (and its associated Zulip stream) on
[the compiler-team repository][repo]. There is also a [central
calendar][cal] that lists all the group meetings and so forth. This
makes it pretty easy to quickly see what's going on.

[repo]: https://github.com/rust-lang/compiler-team
[cal]: https://github.com/rust-lang/compiler-team#meeting-calendar

## Working groups as a way into the compiler

Working groups provide an ideal vector to get involved with the
compiler. For one thing, they give people a more approachable target
-- you're not working on "the entire compiler", you're working towards
a particular goal. Each of your PRs can then be building on a common
part of the code, making it easier to get started. Moreover, you're
working with a smaller group of people, many of whom are also just
starting out. This allows people to help one another and form a
community.

## Running a working group is a big job

The thing is, running a working group can be quite a big job --
particularly a working group that aims to incorporate a lot of
contributors. Traditionally, we've thought of a working group as
having a **lead** -- maybe, at best, two leads -- and a bunch of
participants, most of whom are being mentored:

```
           +-------------+
           | Lead(s)     |
           |             |
           +-------------+

  +--+  +--+  +--+  +--+  +--+  +--+
  |  |  |  |  |  |  |  |  |  |  |  |
  |  |  |  |  |  |  |  |  |  |  |  |
  |  |  |  |  |  |  |  |  |  |  |  |
  +--+  +--+  +--+  +--+  +--+  +--+
  
  |                                |
  +--------------------------------+
   (participants)
```

Now, if all these participants are all being mentored to write code,
that means that the set of jobs that fall on the leads is something
like this:

- Running the meeting
- Taking and posting minutes from the meeting
- Figuring out the technical design
- Writing the big, complex PRs that are hard to mentor
- Writing the design documents
- Writing mentoring instructions
- Writing summary blog posts and trying to call attention to what's going on
- Synchronizing with the team at large to give status updates etc
- Being a "point of contact" for questions
- Helping contributors debug problems
- Triaging bugs and ensuring that the most important ones are getting fixed 
- ...

Is it any wonder that the vast majority of working group leads have
full-time, paid employees? Or, alternatively, is it any wonder that
often many of those tasks just don't get done?

(Consider the NLL working group -- there, we had both Felix and I
working as full-time leads, essentially. Even so, we had a hard time
writing out design documents, and there were never enough summary blog
posts.)

## Running a working group is really a lot of smaller jobs

The more I think about it, the more I think the flaw is in the way
we've talked about a "lead". Really, "lead" for us was mostly a kind
of shorthand for "do whatever needs doing". I think we should be
trying to get more precise about what those things are, and then that
we should be trying to split those roles out to more people.

For example, how awesome would it be if major efforts had some people
who were just trying to ensure that the design was **documented** --
working on [rustc-guide][] chapters, for example, showing the major
components and how they communicated. This is not easy work. It
requires a pretty detailed technical understanding. It does not,
however, really require *writing the PRs in question* -- in fact,
ideally, it would be done by different people, which ensures that
there are multiple people who understand how the code works.

[rustc-guide]: https://rust-lang.github.io/rustc-guide/

There will still be a need, I suspect, for some kind of "lead" who is
generally overseeing the effort. But, these days, I like to think of
it in a somewhat less... hierarchical fashion. Perhaps "organizer" is
the right term. I'm not sure.

## Each job is different

Going back to [Jessica Lord's post][jlord], she continues:

> We need everything we can get and are thankful for all that you can
> contribute whether it is two hours a week, one logo a year, or a
> copy-edit twice a year.

Looking over the list of tasks that are involved in running a
working-group, it's interesting how many of them have distinct time
profiles. Coding, for example, is a pretty intensive activity that can
easily take a kind of "unbounded" amount of time, which is something
not everyone has available. But consider the job of **running a weekly
sync meeting**.

Many working groups use short, weekly sync meetings to check up on
progress and to keep everything progressing. It's a good place for
newcomers to find tasks, or to triage new bugs and make sure they are
being addressed. One easy, and self-contained, task in a working group
might be to **run the weekly meetings**.  This could be as simple as
coming onto Zulip at the right time, pinging the right people, and
trying to walk through the status updates and take some
minutes. However, it might also get more complex -- e.g., it might
involve doing some pre-triage to try and shape up the agenda.

But note that, however you do it, this task is relatively
time-contained -- it occurs at a predictable point in the week. It
might be a way for someone to get involved who has a fixed hole in
their schedule, but can't afford the more open-ended, coding tasks.

## Just as important as code

In my last quote from [Jessica Lord's post][jlord], I left out the
last sentence from the paragraph.  Let me give you the paragraph in
full (emphasis mine):

> We need everything we can get and are thankful for all that you can
> contribute whether it is two hours a week, one logo a year, or a
> copy edit twice a year. **You, too, are a first class open source
> citizen.**

I think this is a pretty key point. I think it's important that we
recognize that **working on the compiler is more than coding** -- and
that we value those tasks -- whether they be organizational tasks,
writing documentation, whatever -- equally.

I am worried that if we had working groups where some people are
writing the code and there is somebody else who is "only" running the
meetings, or "only" triaging bugs, or "only" writing design docs, that
those people will feel like they are not "real" members of the working
group. But to my mind they are equally essential, if not more
essential. **After all, it's a lot easier to find people who will
spend their free time writing PRs than it is to find people who will
help to organize a meeting.**

## Growing the compiler team

The point of this post, in case you missed it, is that **I would like to grow
our conception of the compile team beyond coders**. I think we should be actively
recruiting folks with a lot of different skill sets and making them full members
of the compiler team:

- organizers and project managers
- documentation authors
- code evangelists

I'm not really sure what this full set of roles should be, but I know
that the compiler team cannot function without them.

## Beyond the compiler team

One other note: I think that when we start going down this road, we'll
find that there is overlap between the "compiler team" and other teams
in the rust-lang org.  For example, the release team already does a
great job of tracking and triaging bugs and regressions to help ensure
the overall quality of the release. But perhaps the compiler team also
wants to do its own triaging. Will this lead to a "turf war"?
Personally, I don't really see the conflict here.

One of the beauties of being an open-source community is that we don't
need to form strict managerial hierarchies. We can have the same
people be members of *both* the release team *and* the compiler
team. As part of the release team, they would presumably be doing more
general triaging and so forth; as part of the compiler team, they
would be going deeper into rustc. But still, it's a good thing to pay
attention to. Maybe some things don't belong in the compiler-team
proper.

## Conclusion

I don't quite a have a **call to action** here, at least not yet. This
is still a WIP -- we don't know quite the right way to think about
these non-coding roles. I think we're going to be figuring that out,
though, as we gain more experience with working groups.

I guess I **can** say this, though: **If you are a project manager or
a tech writer**, and you think you'd like to get more deeply involved
with the compiler team, now's a good time. =) Start attending our
[steering meetings][sm], or perhaps the weekly meetings
of the [meta working group][meta-wg], or just ping me over on [the
rust-lang Zulip][z].

[meta-wg]: https://github.com/rust-lang/compiler-team/tree/master/working-groups/meta
[z]: https://github.com/rust-lang/compiler-team/blob/master/about/chat-platform.md
[sm]: https://github.com/rust-lang/compiler-team/blob/master/about/steering-meeting.md
