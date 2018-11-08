---
layout: post
title: Splash 2018 Mid-Week Report
categories: [Conference, Rust]
---

This week I've been attending SPLASH 2018. It's already been quite an
interesting week, and it's only just begun. I thought I'd write up a
quick report on some of the things that have been particularly
interesting to me, and some of the ideas that they've sparked off.

### Teaching programming (and Rust!)

I really enjoyed this talk by Felienne Hermans entitled ["Explicit
Direct Instruction in Programming Education"][talk]. The basic gist of
the talk was that, when we teach programming, we often phrase it in
terms of "exploration" and "self-expression", but that this winds up
leaving a lot of folks in the cold and may be at least *partly*
responsible for the lack of diversity in computer science today. She
argued that this is like telling kids that they should just be able to
play a guitar and create awesome songs without first practicing their
chords[^d] -- it kind of sets them up to fail.

[talk]: https://2018.splashcon.org/event/splash-2018-keynotes-explicit-direct-instruction-in-programming-education

[^d]: My daughter insists she can do this... let's just say she's lucky she's so cute. =)

The thing that really got me excited about this was that it seemed
very connected to mentoring and open source. If you watched the Rust
Conf keynote this year, you'll remember Aaron talking about "OSS by
Serendipity" -- this idea that we should just expect people to come
and produce PRs. This is in contrast to the "OSS by Design" that we've
been trying to practice and preach, where there are explicit in-roads
for people to get involved in the project through mentoring, as well
as explicit priorities and goals (created, of course, through open
processes like the roadmap and so forth). It seems to me that the
things like working groups, intro bugs, quest issues, etc, are all
ways for people to "practice the basics" of a project before they dive
into creating major new features.

One other thing that Felienne talked about which I found exciting was
the idea that -- in fields like reading -- there are taxonomies of
common errors as well as diagnostic tools that one can use to figure
out where your student falls in this taxonomy. The idea is that you
can give a relatively simple quiz that will help you identify what
sorts of mental errors they are making, which you can then directly
target. (Later, I talked to someone -- whose name unfortunately I do
not remember -- doing similar research around how to categorize
mathematical errors which sounded quite cool.)

I feel like both the idea of "practice" but also of "taxonomy of
errors" applies to Rust quite well. Learning to use Rust definitely
involves a certain amount of "drill", where one works with the
mechanics of the ownership/borrowing system until they start to feel
more natural. Moreover, I *suspect* that there are common "stages of
understanding" that we could try to quantify, and then directly target
with instructional material. To some extent we've been doing this all
along, but it seems like something we could do more formally.

### Borrow checker field guide

Yesterday I had a very nice conversation with Will Creigthon and Anna
Zeng. They were presenting the results of work they have been doing to
identify barriers to adoption for Rust ([they have a paper you can
download here to learn more][wcaz]). Specifically, they've been
surveying comments, blog posts, and other things and looking for
patterns. I'm pretty excited to dig deeper into their findings, and I think
that we should think about forming a working group or something else to continue
this line of work to help inform future directions.

[wcaz]: https://2018.splashcon.org/event/plateau-2018-papers-identifying-barriers-to-adoption-for-rust-through-online-discourse

Talking with them also helped to crystallize some of the thoughts I've
been having with respect to this "After NLL" blog post series. What
I've realized is that it is a bit tricky to figure out how to organize
the "taxonomy of tricky situations" that commonly result with
ownership as well as their solutions. For example, in reading the
responses to my previous post about *interprocedural conflicts*, I
realized that this one *fundamental conflict* can manifest in a number
of ways -- and also that there are a number of possible solutions,
depending on the specifics of your scenario.

I've decided for the time being to just press on, writing out various
blog posts that highlight -- in a somewhat sloppy way -- the kinds of
errors I see cropping up, some of the solutions I see available for
them, and also the possible language extensions we might pursue in the
future.

However, I think that once this series is done, it would be nice to
pull this material together (along with other things) into a kind of
*Borrow Checker Field Guide*. The idea would be to distinguish:

- **Root causes** -- there are relatively few of these, but these are the
  root aspects of the borrow checker that give rise to errors.
- **Troublesome patterns** -- these are the designs that people are often
  shooting for from another language which can cause trouble in Rust.
  Examples might be "tree with parent pointer", "graph", etc.
- **Solutions** -- these would be solutions and design patterns that work
  today to resolve problems.
- **Proposals** -- in some cases, there might be links to proposed designs.

The idea is that for the **root causes** and **troublesome patterns**,
there would be links over to the solutions and proposals that can help
resolve them. I don't intend to include a lot of details about
proposals in particular in this document, but I'd like to see a way to
drive people towards the "work in progress" as well, so they can give
their feedback or maybe even get involved.

### An Eve retrospective

Chris Granger gave an [amazing and heartfelt talk about the Eve effort][eve]
to construct a more accessible model of programming. I had not
realized what a monumental effort it was. I had two main takeaways:
first, that the *crux* of programming is *modeling and
feedback*. Excel works for so many people because it gives a simple
model you can fit your data into and immediate feedback -- but it's
inflexible and limited. If we can change that up or scale it, it could
be a massive enabler. Second, that the VC approach of trying to change
the world over the course of a few ridiculously high-pressure years
sounds very punishing and doesn't feel just or right. It'd be
wonderful if Chris and co. could continue their efforts without such
personal sacrifice. (As an aside, Chris had a few nice things to say
about Rust, which were much appreciated.)

[eve]: https://2018.splashcon.org/event/live-2018-papers-keynote

### Incremental datalog and Rust type checking

Finally, I spent some time talking to Sebastian Erdweg and Tamás Szabó
about [their work on incremental datalog][inca]. They had a very cool
demo of their system at work where they implemented various analyses
-- unreachable code and out-of-bounds index detection -- and showed
how quickly they could update as the input source changed. Sebastian
also has a master's student (whose name I don't know -- yet! but I
will find out) that implemented a prototype Rust type checker in their
system; I look forward to reading more about it.

[inca]: https://2018.splashcon.org/event/splash-2018-splash-i-better-living-through-incrementality-immediate-static-analysis-feedback-without-loss-of-precision

Their system is much finer grained than anything we've attempted to do
in rustc. It seems like we could easily port Polonius to that system
and see how well it works, though it seems like it would also make
sense to compare against Frank McSherry's amazing differential-datalog
system.

I've been thinking for some time that the next frontier in terms of
improving rustc is to start formalizing and simplifying name
resolution and type-checking. Talking to them did get me more inspired
to see that work proceed, since it could well be the foundation for
super snappy IDE integration. (But first: got to see Polonius and
Chalk over the finish line!)

### Logic 

Finally, I had a very long conversation with Will Byrd and Michael
Ballantyne about how [Chalk] works. We discussed some details of how
MiniKanren's search algorithm works and also some details how Chalk
lowering works. I won't try to summarize here, except to say that Will
gave me an exciting pointer to something called ["default logic"][dl],
which I had never heard of, but which seems like a very good match for
specialization. I look forward to reading more about it.

[dl]: https://en.wikipedia.org/wiki/Default_logic
[Chalk]: https://github.com/rust-lang-nursery/chalk

### Me talking about Rust

I am posting this in the morning on Thursday. Today I am going to give
a talk about Rust -- I plan to focus on both some technical aspects
but also how Rust governance works and some of the "ins and outs" of
running an open source project. I'm excited but a bit nervous, since
this is material that I've never tried to present to a general
audience before. Let's see how it goes![^video] (Tonight there is also a joint
Rust-Scala meetup, so that should be fun.)

### Footnotes
