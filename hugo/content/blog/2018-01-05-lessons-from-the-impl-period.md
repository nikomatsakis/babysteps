---
categories:
- Rust
date: "2018-01-05T00:00:00Z"
slug: lessons-from-the-impl-period
title: Lessons from the impl period
---

So, as you likely know, we tried something new at the end of 2017. For
roughly the final quarter of the year, we essentially stopped doing
design work, and instead decided to focus on implementation -- what we
called the ["impl period"][]. We had two goals for the impl period:
(a) get a lot of high-value implementation work done and (b) to do
that by expanding the size of our community, and making it easy for
new people to get involved. To that end, we spun up **about 40 working
groups**, which is really a tremendous figure when you think about it,
each of which was devoted to a particular task.

["impl period"]: https://blog.rust-lang.org/2017/09/18/impl-future-for-rust.html

For me personally, this was a very exciting three months. I really
enjoyed the enthusiasm and excitement that was in the air. I also
enjoyed the opportunity to work in a group of people collectively
trying to get our goals done -- one thing I've found working on an
open-source project is that it is often a much more "isolated"
experience than working in a more traditional company. The impl period
really changed that feeling.

I wanted to write a brief post kind of laying out my experience and
trying to dive a bit into what **I** felt worked well and what did
not. **I'd very much like to hear back from others who participated
(or didn't). I've opened up a
[dedicated thread on internals for discussion](https://internals.rust-lang.org/t/lessons-from-the-impl-period/6485),
please leave comments there!**

### TL;DR

If you don't want to read the details, here are the major points:

- Overall, the impl period worked great. **Having structure to the
  year felt liberating** and I think we should do more of it.
- We need to **grow and restructure the compiler team around the idea
  of mentoring and inclusion**. I think having more focused working
  groups will be a key part of that.
- We have work to do on making the compiler code base accessible,
  beginning with **top-down documentation** but also **rustdoc**.
- We need to develop **skills and strategies** for how to split tasks
  up.
- IRC isn't great, but Gitter wasn't either. The search for a better
  chat solution continues. =)

### Worked well: establishing focus and structure to the year

Working on Rust often has this kind of firehose quality: so much is going on at once.
At any one time, we are:

- fixing bugs in existing code,
- developing code for new features that have been designed,
- discussing the minutae and experience of some existing feature we may consider stabilizing,
- designing new features and APIs via RFCs.

It can get pretty exhausting to keep all that in your head at once. I
really enjoyed having a quarter to just focus on one thing --
implementing. I would like us to introduce more structure into future
years, so that we can have a time when we are just focused on design,
and so forth.

I also appreciated that the impl period imposed a kind of "soft
deadline".  I found that helpful for defining our scope. I felt like
it ensured that difficult discussions did reach an end point.

That said, I don't think we managed this deadline especially well this
year. The final discussions were pretty frantic and it was hard -- no,
impossible -- to keep up with all of them (I know I certainly
couldn't, and I work on Rust full time). Clearly in the future we
need to manage the schedule better, and make sure that design work is
happening at a more measured pace. I think that having more structure
to the year can help with that, by ensuring that we do the design work
at the time it needs to get done.

### Worked well: newcomers developing key, important features

Earlier, I said that the goals of impl period were to (a) get a lot of
high-value implementation work done and (b) to do that by expanding
the size of our community. There is a bit of a tension there: if you
have some high-value new feature, there is a tendency to think that we
should have an established developer do it. After all, they know the
codebase, and they will get it done the fastest. That is (often) true,
but it is not the complete story. 

What we wanted to do in the impl period was to focus on bringing new
people into the project. Hopefully, many of those people will stick
around, working on new projects, and eventually becoming experienced
Rust compiler developers themselves. This increases our overall
bandwidth and grows our community, making us stronger.

And even when people don't have time to keep hacking on the Rust
compiler, there are still advantages to developing through
mentoring. The fact is that coding takes a lot of time. A single
experienced developer can only really effectively code up a single
feature at a time, but they can be mentoring many people at once.

Still, it must be said, there are plenty of people who just enjoy
coding and who don't particularly want to do mentoring. So obviously
we should ensure we always have a place for experienced devs who just
want to code.

### Worked mostly well: smaller working groups

First and foremost, a key part of our plan was breaking up tasks into
**working groups**. A working group was meant to be a small set of
people focused on a common goal. The hope was that having smaller
groups would make it easier for people to get involved and would also
encourage more collaboration.

I felt the working groups worked best when they had relatively clear
focus and an active leader: the NLL group is a good example. It was
great to see the people in the chatrooms working together and starting
to help one another out when more experienced devs weren't available.

Other working group divisions worked less well. For example, there
were a few groups in the compiler that were not specific to particular
tasks, but rather parts of the compiler pipeline: WG-compiler-front,
WG-compiler-middle, etc. Lots of people participated in those groups,
and a lot got done, but the division into groups felt a bit more
arbitrary to me. It wasn't always clear where to put the tasks.

Going forward, I continue to think there is a role for working groups,
but I think we should try to keep them focused on **goals**, not on
the parts of the project that they touch.

### Worked well: clear mentoring instructions

I've noticed something: if you tag a bug on the Rust's issue tracked
as `E-Easy` and leave a comment like "ping me on IRC", it can easily
sit there for years and years. But if you write some **mentoring
instructions** -- that is, lay out the steps to take -- it will be
closed, often within hours.

This makes total sense. You want to make sure that all the tools
people need to hack on Rust are ready and immediately available. This
way, when somebody says "I have a few hours, let me see if I can fix a
bug in rustc", they can sieze the moment. If you say "ping me on IRC",
then it may well be that you are not available at that time. Or that
may be intimidating. In general, every roadblock gives them a chance
to get distracted.

Of course, ideally mentoring doesn't stop at mentoring instructions.
Especially for more complex projects, I often find myself scheduling
times with people so that we can have an hour or two to discuss
directly what is going on, often with screen sharing or a voice
call. That doesn't always work -- timezones being what they are -- but
when it does, it can be a big win.

### Clear problem: lack of leadership bandwidth

One problem we encountered is that there just weren't enough
experienced rustc developers who were willing and able to lead up
working groups. Writing mentoring instructions is hard work. Breaking
up a big task into smaller parts is hard work. This is a problem
outside of the impl period too. It's hard to balance all the
maintenance, bug fixing, performance monitoring, and new feature
development work that needs to get done.

I don't see a real solution here other than growing the set of people
who hack on rustc. I think this should be a top priority for us. I
think we should try to incorporate the idea of "contributor
accessibility" into our workflow wherever possible. In other words,
**we should have clear paths for (a) how to get started hacking on
rustc and then (b) once you've gotten a few PRs under your belt, how
to keep growing**. The impl period focused on (a) and it's clear we do
pretty well there, but have room for improvement. Part (b) is harder,
and I think we need to work on it.

### Clear problem: rustc documentation

One problem that makes writing mentoring instructions very difficult
is that the compiler is woefully underdocumented. At the start of the
impl period, many of the basic idioms and concepts (e.g., what is "the
HIR" or "the MIR"?  what is this `'tcx` I see everywhere?) were not
written up at all. It's somewhat better now, but not great.

We also lack documentation on common workflows. How do I build the
compiler?  How do I debug things and get debug logs? How do I run an
individual test? Some of this exists, but not always in an
easy-to-find place.

I think we really need to work on this. I'd like to form a working
group and focus on it early this year -- but more on that later. (If you're 
interested in the idea of helping to document the compiler, though, please contact me,
or stay tuned!)

### Clear problem: some tasks are hard to subdivide

One thing we also found is that some tasks are just plain hard to
subdivide. I think a good example of this was incremental compilation:
it seems like, in principle, there ought to be a lot of things that
can be done in parallel there. And we had some success with newcomers,
for example, picking off tasks relating to testing and doing other
refactorings. I think we need to work on better strategies
here. Knowing how to structure tasks for massive participation is a
skillset -- not unrelated to coding, but clearly distinct from it.  I
don't have answers yet, but I suspect we can gain experience with this
as a community and find best practices.

In the case of NLL, the model that seemed to work best was to have one
more experienced developer pushing on the "main trunk" of development
(myself), but actively seeking places to spin out isolated tasks into
issues that could be mentored. To avoid review and bors latecy from
slowing us down, we used a dedicated feature branch on my repo
(`nll-master`) and I would periodically open up pull requests
containing a variety of commits. This seemed to work out pretty well
-- oh, and by the way, the job is not done. If you're still hoping to
get involved, we've [still got plenty of work to do][nll]. =) (Though
most of those issues do not yet have mentoring instructions.)

[nll]: https://github.com/rust-lang/rust/milestone/43

### Mixed bag: gitter and dedicated chat rooms

One key part of our experiment was moving from a small number of chat
rooms on IRC (e.g., `#rustc`) to dedicate rooms on Gitter, one per
working group. I had mixed feelings about this. 

Let me start with the pros of Gitter itself:

- **Gitter means everybody has a persistent connection.** It is great
  to be able to send someone a message when they may or may not be
  online, and get an answer sometime later.
- **Gitter means everything can be easily linked from the web.** I
  love being able to make a link to some conversation with one click
  and copy it into a GitHub issue.  I love being able to link to a
  Gitter chat room very easily.
- **Gitter means single sign on and only one name to remember.** I
  love that I can just use people's GitHub names, which makes it
  easier for me to then correlate their pull requests, or checkout
  their fork of Rust, etc.
  
But there are some pretty big cons. Mostly having to do with Gitter
being buggy. The android client doesn't deliver notifications (and
maybe others as well). The IRC bridge seems to mostly work, but
sometimes people get funny names (e.g., I think the Discord bridge has
only one user?) or we hit other arbitrary limits.

Similarly, I felt like having dedicated rooms had pros and cons. On
the one hand, it was really helpful to me personally. I find it hard
to keep up with `#rustc` on IRC.  I liked that I could be sure to read
every message in WG-compiler-nll, but I could just skim over groups
like WG-compiler-const that I was not directly involved in.

On the other hand, a bigger room offers more opportunity for "cross
talk".  People have told me that they like having the chance to hear
something interesting.  And others found it was hard to follow all the
rooms they were interested in.

Finally, I found that I personally still wound up doing a lot of
mentoring over private messages. This is not ideal, because it doesn't
offer visibility to the rest of the group, and you can wind up
repeating things, but -- particularly when you're discussing
asynchronously -- it's often the most natural way to set things up.

I don't know what's the ideal solution here, but I do think there's
going to be a role for smaller chat rooms (though probably not based
on Gitter).
  
### Conclusion

The impl period was awesome. We got a lot of things done. And I do
mean we: the vast majority of that work was done by newcomers to the
community, many of whom had never worked on a compiler before. I loved
the overall enthusiasm that was in the air. To me, it felt like what
open source is supposed to be like.

Of course, though, there are things we can do better. I hope to drill
into these more in later posts (or perhaps forum discussion), but I
think the most important thing is that we need to think carefully
about how to enable mentoring and inclusion throughout our team
structure. I think we do quite well, but we can do better -- and in
particular we should think more about how to help people who have
already done a few PRs take the next step.

### Advertisement

As you may have heard, we're trying something new this
year. [We're encouraging people to write blog posts about what they think Rust ought to focus on for 2018][rustblog]
-- if you do it, you can either tweet about it with the hashtag
#Rust2018, or else e-mail `community@rust-lang.org`. I'm pretty
excited about this; I've been enjoying reading the posts that have
arrived thus far, and I plan to write a few of my own!

[rustblog]: https://blog.rust-lang.org/2018/01/03/new-years-rust-a-call-for-community-blogposts.html


