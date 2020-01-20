---
layout: post
title: 'Async Interview #4: Florian Gilcher'
---

Hello! For the latest [async interview], I spoke with Florian Gilcher
([skade]). Florian is involved in the [async-std] project, but he's
also one of the founders of [Ferrous Systems], a Rust consulting firm
that also does a lot of trainings. In that capacity, he's been
teaching people to use async Rust now since Rust's 1.0 release.

[Ferrous Systems]: https://ferrous-systems.com/
[async interview]: http://smallcultfollowing.com/babysteps/blog/2019/11/22/announcing-the-async-interviews/
[skade]: https://github.com/skade/
[async-std]: https://async.rs

### Video

You can watch the [video] on YouTube. I've also embedded a copy here
for your convenience:

[video]: https://youtu.be/Ezwd1vKSfCo

<center><iframe width="560" height="315" src="https://www.youtube.com/embed/Ezwd1vKSfCo" frameborder="0" allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe></center>

One note: something about our setup meant that I was hearing a lot of
echo. I think you can sometimes hear it in the recording, but not
nearly as bad as it was live. So if I seem a bit spacey, or take very
long pauses, you might know the reason why!

### Prioritize stability, read/write traits

The first thing we discussed was some background on async-std
itself. From there we started talking about what the Rust org ought to
prioritize. Florian felt like having stable, uniform `AsyncRead` and
`AsyncWrite` traits would be very helpful, as most applications are
interested in having access to a "readable/writable thing" but don't
care that much where the bytes are coming from. 

He felt that `Stream`, while useful, might be somewhat lower priority.
The main reason was that while streams are useful, in many of the
applications that he's seen, there wasn't as much need to be *generic*
over a stream. Of course, having a standard `Stream` trait would still
be of use, and would enable libraries as well, so it's not an argument
not to do it, just a question of how to prioritize.

### Prioritize diagnostics perhaps even more

Although we've done a lot of work on it, there continues to be a need
for improved error diagnostics. This kind of detailed ergonomics work may indeed
be the highest priority overall.

(A quick plug for the [async await working
group](https://rust-lang.github.io/compiler-team/working-groups/async-await/),
which has been steadily making progress here. Big thanks especially to
tmandry, who has been running the triage meetings lately, but also (in
no particular order) csmoe, davidtwco, gilescope, and centril -- and
perhaps others I've forgotten (sorry!).)

### Levels of stability and the futures crate

We discussed the futures crate for a while. In particular, the
question of whether we should be "stabilizing" traits by moving them
into the standard library, or whether we can use the futures crate as
a "semi-stable" home. There are obviously advantages either way.

On the one hand, there is no clearer signal for stability than adding
something to libstd. On the other, the future crate facade gives a
"finer grained" ability to talk about semver. 

One thing Florian noted is that the futures crate itself, although it
has evolved a lot, has always maintained an internal consistency,
which is good.

One other point Florian emphasized is that people really want to be
building applications, so in some way the most important thing is to
be moving towards stability, so they can avoid worrying about the sand
shifting under their feet.

### Deprioritize: Attached and detached streams

I asked Florian how much he thought it made sense to wait on things
like streams until the GAT story is straightened out, so that we might
have support for "attached" streams. He felt like it would be better
to move forward with what we have now, and consider extensions
later. 

He noted an occasional tendency to try and create the single, perfect
generic abstraction that can handle everything -- while this can be
quite elegant, it can sometimes also lead to really confusing
interfaces that are complex to use.

### Deprioritize: Special syntax for streams

I asked about syntactic support for generators, but Florian felt that
it was too early to prioritize that, and that it would be better to
focus first on the missing building blocks.

### The importance of building and discovering patterns

Florian felt that we're now in a stage where we're transitioning a
little. Until now, we've been tinkering about with the most primitive
layers of the async ecosystem, such as the `Future` trait, async-await
syntax, etc. As these primitives are stabilized, we're going to see a
lot more tinkering with the "next level up" of patterns. These might
be questions like "how do I stop a stream?", or "how do I construct my app?".
But it's going to be hard for people to focus on these higher-level patterns
(and in particular to find new, innovative solutions to them) until the
primitives even out.

As these patterns evolve, they can be extracted into crates and types
and shared and reused in many contexts. He gave the example of the
[async-task] crate, which extracts out quite a bit of the complexity
of managing allocation of an async task. This allows other runtimes to reuse that
fairly standard logic. (Editor's note: If you haven't seen async-task,
you should check it out, it's quite cool.)

[async-task]: https://docs.rs/async-task/newest/async_task/

### Odds and ends

We then discussed a few other features and how much to prioritize them.

**Async fn in traits.** Don't rush it, the async-trait crate is a
pretty reasonable practice and we can probably "get by" with that for
quite a while.

**Async closures.** These can likely wait too, but they would be
useful for stabilzing convenience combinators. On the other hand,
those combinators often come attached to the base libaries you're
using.

### Communicating over the futures crate

Returning to the futures crate, I raised the question of how best to
help convey its design and stability requirements. I've noticed that there
is a lot of confusion around its various parts and how they are meant
to be used. 

Florian felt like one thing that might be helpful is to break apart
the facade pattern a bit, to help people see the smaller
pieces. Currently the futures crate seems a bit like a monolithic
entity. Maybe it would be useful to give more examples of what each
part is and how it can be used in isolation, or the overall best
practices.

### Learning

Finally, I posed to Florian a question of how can help people to learn
async coding. I'm very keen on the way that Rust manages to avoid
hard-coding a single runtime, but one of the challenges that comes
with that is that it is hard to teach people how to use futures
without referencing a runtime. 

We didn't solve this problem (shocker that), but we did talk some
about the general value in having a system that doesn't make all the
choices for you. To be quite honest I remember that at this point I
was getting very tired. I haven't listened back to the video because
I'm too afraid, but hopefully I at least used complete sentences. =)

One interesting idea that Florian raised is that it might be really
useful for people to create a "learning runtime" that is oriented not
at performance but at helping people to understand how futures work or
their own applications. Such a runtime might gather a lot of data, do
tracing, or otherwise help in visualizing. Reading back over my notes,
I personally find that idea sort of intriguing, particularly if the
focus is on helping people learn how futures work early on -- i.e., I
don't think we're anywhere close to the point where you could take
production app written against async-std and then have it use this
debugging runtime. But I could imagine having a "learner's runtime"
that you start with initially, and then once you've got a feel for
things, you can move over to more complex runtimes to get better
performance.

### Conclusion

I think the main points from the conversation were:

* Diagnostics and documentation remain of very high importance. We
  shouldn't get all dazzled with new, shiny things -- we have to keep
  working on polish.
* Beyond that, though, we should be working to stabilize building
  blocks so as to give more room for the ecosystem to flourish and
  develop. The `AsyncRead/AsyncWrite` traits, along with `Stream`,
  seem like plausible candidates.
  * We shouldn't necessarily try to make those traits be as generic as
    possible, but instead focus on building something usable and
    simple that meets the most important needs right now.
* We need to give time for people to develop patterns and best
  practices, and in particular to figure out how to "capture" them as
  APIs and crates.  This isn't really something that the *Rust
  organization* can do, it comes from the ecosystem, by library and
  application developers.
