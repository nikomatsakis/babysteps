---
layout: post
title: Rustacean Principles, continued
date: 2021-09-16T09:42:00-0400
categories: [AiC]
---

RustConf is always a good time for reflecting on the project. For me, the last week has been particularly "reflective". Since announcing the [Rustacean Principles][RP], I've been having a number of conversations with members of the community about how they can be improved. I wanted to write a post summarizing some of the feedback I've gotten.

[RP]: https://rustacean-principles.netlify.app/

### The principles are a work-in-progress

Sparking conversation about the principles was exactly what I was hoping for when I posted the previous blog post. The principles have mostly been the product of [Josh] and I iterating, and hence reflect our experiences. While the two of us have been involved in quite a few parts of the project, for the document to truly serve its purpose, it needs input from the community as a whole.

[Josh]: https://github.com/joshtriplett/

Unfortunately, for many people, the way I presented the principles made it seem like I was trying to unveil a *fait accompli*, rather than seeking input on a work-in-progress. I hope this post makes the intention more clear!

### The principles as a continuation of Rust's traditions

Rust has a long tradition of articulating its values. This is why we have a [Code of Conduct](https://www.rust-lang.org/policies/code-of-conduct). This is why we wrote blog posts like [Fearless Concurrency](https://blog.rust-lang.org/2015/04/10/Fearless-Concurrency.html), [Stability as a Deliverable](https://blog.rust-lang.org/2014/10/30/Stability.html) and [Rust Once, Run Anywhere](https://blog.rust-lang.org/2015/04/24/Rust-Once-Run-Everywhere.html). Looking past the "engineering side" of Rust, aturon's classic blog posts on listening and trust ([part 1], [part 2], [part 3]) did a great job of talking about what it is like to be on a Rust team. And who could forget the whole ["fireflowers"] debate?[^captured]

**My goal with the Rustacean Principles is to help _coalesce_ the existing wisdom found in those classic Rust blog posts into a more concise form.** To that end, I took initial inspiration from how AWS uses [tenets], although by this point the principles have evolved into a somewhat different form. I like the way tenets use short, crisp statements that identify important concepts, and I like the way assigning a priority ordering helps establish which should have priority. (That said, one of Rust's oldest values is _synthesis_: we try to find ways to resolve constraints that are in tension by having our cake and eating it too.)

[part 1]: http://aturon.github.io/tech/2018/05/25/listening-part-1/
[part 2]: http://aturon.github.io/tech/2018/06/02/listening-part-2/
[part 3]: http://aturon.github.io/tech/2018/06/18/listening-part-3/
["fireflowers"]: https://brson.github.io/fireflowers/
[tenets]: https://aws.amazon.com/blogs/enterprise-strategy/tenets-provide-essential-guidance-on-your-cloud-journey/

[^captured]: Love that web page, [brson].

[brson]: https://github.com/brson

Given all of this backdrop, I was pretty enthused by a suggestion that I heard from [Jacob Finkelman][Eh2406]. He suggested adapting the principles to incorporate more of the "classic Rust catchphrases", such as the "no new rationale" rule described in the [first blog post from aturon's series][part 1]. A similar idea is to incorporate the lessons from RFCs, both successful and unsuccessful (this is what I was going for in the [case studies] section, but that clearly needs to be expanded).

[Eh2406]: https://github.com/Eh2406
[case studies]: https://rustacean-principles.netlify.app/case_studies.html

### The overall goal: Empowerment

My original intention was to structure the principles as a cascading series of ideas:

* **Rust's top-level goal:** *Empowerment*
    * **Principles:** Dissecting empowerment into its constituent pieces -- reliable, performant, etc -- and analyzing the importance of those pieces relative to one another.
        * **Mechanisms:** Specific rules that we use, like [type safety](https://rustacean-principles.netlify.app/how_rust_empowers/reliable/type_safety.html), that engender the principles (reliability, performance, etc.). These mechanisms often work in favor of one principle, but can work against others.

[wycats] suggested that the site could do a better job of clarifying that *empowerment* is the top-level, overriding goal, and I agree. I'm going to try and tweak the site to make it clearer.

[wycats]: https://twitter.com/wycats/

### A goal, not a minimum bar

The principles in ["How to Rustacean"] were meant to be aspirational: a target to be reaching for. We're all human: nobody does everything right all the time. But, as [Matklad describes][m], the principles could be understood as setting up a kind of minimum bar -- to be a team member, one has to [show up], [follow through], [trust and delegate], all while [bringing joy]? This could be really stressful for people.

[m]: https://internals.rust-lang.org/t/blog-post-rustacean-principles/15300/2?u=nikomatsakis
[show up]: https://rustacean-principles.netlify.app/how_to_rustacean/show_up.html
[follow through]: https://rustacean-principles.netlify.app/how_to_rustacean/follow_through.html
[trust and delegate]: https://rustacean-principles.netlify.app/how_to_rustacean/trust_and_delegate.html
[bringing joy]: https://rustacean-principles.netlify.app/how_to_rustacean/bring_joy.html
["How to Rustacean"]: https://rustacean-principles.netlify.app/how_to_rustacean.html

The goal for the ["How to Rustacean"] section is to be a way to lift people up by giving them clear guidance for how to succeed; it helps us to answer people when they ask "what should I do to get onto the lang/compiler/whatever team". The internals thread had a number of good ideas for how to help it serve this intended purpose without stressing people out, such as [cuviper's suggestion to use fictional characters like Ferris in examples](https://internals.rust-lang.org/t/blog-post-rustacean-principles/15300/6?u=nikomatsakis), [passcod's suggestion of discussing inclusion](https://internals.rust-lang.org/t/blog-post-rustacean-principles/15300/9?u=nikomatsakis), or Matklad's proposal to [add something to the effect of "You don't have to be perfect"][m] to the list. Iteration needed!

### Scope of the principles

Some people have wondered why the principles are framed in a rather general way, one that applies to all of Rust, instead of being specific to the lang team. It's a fair question! In fact, they didn't start this way. They started their life as a rather narrow set of ["design tenets for async"] that appeared in the [async vision doc](https://rust-lang.github.io/wg-async-foundations/vision.html). But as those evolved, I found that they were starting to sound like design goals for Rust as a whole, not specifically for async.

Trying to describe Rust as a "coherent whole" makes a lot of sense to me. After all, the experience of using Rust is shaped by all of its facets: the language, the libraries, the tooling, the community, even its internal infrastructure (which contributes to that feeling of reliability by ensuring that the releases are available and high quality). Every part has its own role to play, but they are all working towards the same goal of empowering Rust's users.[^tweak]

["design tenets for async"]: https://github.com/rust-lang/wg-async-foundations/blob/a109db290e99bcc9c1705e477694c2301ec7f658/src/vision/tenets.md

[^tweak]: One interesting question: I do think that some tools may vary the prioritization of different aspects of Rust. For example, a tool for formal verification is obviously aimed at users that *particularly* value reliability, but other tools may have different audiences. I'm not sure yet the best way to capture that, it may well be that each tool can have its own take on the way that it particularly empowers.

[internals thread]: https://internals.rust-lang.org/t/blog-post-rustacean-principles/15300

There is an interesting question about the long-term trajectory for this work. In my mind, the principles remain something of an experiment. Presuming that they prove to be useful, I think that they would make a nice RFC.

### What about "easy"?

One final bit of feedback I heard from [Carl Lerche] is surprise that the principles don't include the word "easy". This not an accident. I felt that "easy to use" was too subjective to be actionable, and that the goals of [productive] and [supportive] were more precise. However, I do think that for people to feel empowered, it's important for them not feel mentally overloaded, and Rust can definitely have the problem of carrying a high mental load sometimes. 

I'm not sure the best way to tweak the ["Rust empowers by being..."] section to reflect this, but the answer may lie with the [Cognitive Dimensions of Notation][CDN]. I was introduced to these from [Felienne Herman]'s excellent book [The Programmer's Brain]; I quite enjoyed [this journal article] as well. 

["Rust empowers by being..."]: https://rustacean-principles.netlify.app/how_rust_empowers.html
[Carl Lerche]: https://github.com/carllerche/
[productive]: https://rustacean-principles.netlify.app/how_rust_empowers/productive.html
[supportive]: https://rustacean-principles.netlify.app/how_rust_empowers/supportive.html

The idea of the [CDN] is to try and elaborate on the *ways* that tools can be easier or harder to use for a particular task. For example, Rust would likely do well on the "error prone" dimension, in that when you make changes, the compiler generally helps ensure they are correct. But Rust does tend to have a high "viscosity", because making local changes tends to be difficult: adding a lifetime, for example, can require updating data structures all over the code in an annoying cascade. 

It's important though to keep in mind that the [CDN] will vary from task to task. There are many kinds of changes one can make in Rust with very low viscosity, such as adding a new dependency. On the other hand, there are also cases where Rust can be error prone, such as [mixing async runtimes](https://rust-lang.github.io/wg-async-foundations/vision/submitted_stories/status_quo/alan_started_trusting_the_rust_compiler_but_then_async.html).

[Felienne Herman]: https://twitter.com/Felienne
[The Programmer's Brain]: https://www.manning.com/books/the-programmers-brain
[CDN]: https://en.wikipedia.org/wiki/Cognitive_dimensions_of_notations
[this journal article]: https://www.sciencedirect.com/science/article/abs/pii/S1045926X96900099?via%3Dihub

### Conclusion

In retrospect, I wish I had introduced the concept of the Rustacean Principles in a different way. But the subsequent conversations have been really great, and I'm pretty excited by all the ideas on how to improve them. I want to encourage folks again to come over to the [internals thread] with their thoughts and suggestions.
