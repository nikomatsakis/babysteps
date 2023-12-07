---
title: "Being Rusty: Discovering Rust's design axioms"
date: 2023-12-07T08:46:19-05:00
---

To your average Joe, being "rusty" is not seen as a good thing.[^news] But readers of this blog know that being *R*usty -- with a capitol *R*! -- is, of course, something completely different! So what is that makes Rust *Rust*? Our slogans articulate key parts of it, like *fearless concurrency*, *stability without stagnation*, or the epic *Hack without fear*. And there is of course Lindsey Kuper's [epic haiku][haiku]: "A systems language / pursuing the trifecta: / fast, concurrent, safe". But I feel like we're still missing a unified set of axioms that we can refer back to over time and use to guide us as we make decisions. Some of you will remember the [Rustacean Principles][rp], which was my first attempt at this. I've been dissatisfied with them for a couple of reasons, so I decided to try again. The structure is really different, so I'm calling it Rust's *design axioms*. This post documents the current state -- I'm quite a bit happier with it! But it's not quite there yet. So I've also got a link to a [repository][repo] where I'm hoping people can help improve them by opening issues with examples, counter-examples, or other thoughts.

[haiku]: https://www.youtube.com/watch?t=52&v=DSR7EHeySlw&feature=youtu.be

[^news]: I have a Google alert for "Rust" and I cannot tell you how often it seems that some sports teams or another shakes off Rust. I'd never heard that expression before signing up for this Google alert. 

[rp]: http://localhost:1313/babysteps/blog/2021/09/08/rustacean-principles/

<!--more-->

## Axioms capture the principles you use in your decision-making process

What I've noticed is that when I am trying to make some decision -- whether it's a question of language design or something else -- I am implicitly bringing assumptions, intuitions, and hypotheses to bear. Oftentimes, those intutions fly by very quickly in my mind, and I barely even notice them. *Ah yeah, we could do X, but if we did that, it would mean Y, and I don't want that, scratch that idea.* I'm slowly learning to be attentive to these moments -- whatever *Y* is right there, it's related to one of my **design axioms** --- something I'm implicitly using to shape my thinking.

I've found that if I can capture those axioms and write them out, they can help me down the line when I'm facing future decisions. It can also help to bring alignment to a group of people by making those intutions explicit (and giving people a chance to refute or sharpen them). Obviously I'm not the first to observe this. I've found Amazon's practice of using [tenets][] to be quite useful[^culture], for example, and I've also been inspired by things I've read online about the importance of making your hypotheses explicit.[^hypotheses]

[tenets]: https://aws.amazon.com/blogs/enterprise-strategy/tenets-supercharging-decision-making/

In proof systems, your *axioms* are the things that you assert to be true and take on faith, and from which the rest of your argument follows. I choose to call these Rust's *design axioms* because that seemed like exactly what I was going for. What are the starting assumptions that, followed to their conclusion, lead you to Rust? The more clearly we can articulate those assumptions, the better we'll be able to ensure that we continue to follow them as we evolve Rust to meet future needs.

## Axioms have a hypothesis and a consequence

I've structured the axioms in a particular way. They begin by stating the **axiom** itself -- the core belief that we assert to be true. That is followed by a **consequence**, which is something that we do as a result of that core belief. To show you what I mean, here is one of the Rust design axioms I've drafted:

> **Rust users want to surface problems as early as possible,** and so Rust is designed to be **reliable**. We make choices that help surface bugs earlier. We don't make guesses about what our users meant to do, we let them tell us, and we endeavor to make the meaning of code transparent to its reader. And we always, always guarantee memory safety and data-race freedom in safe Rust code.

[^culture]: I'm perhaps a bit unusual in my love for things like Amazon's [Leadership Principles][lp]. I can totally understand why, to many people, they seem like corporate nonsense. But if there's one theme I've seen consistenly over my time working on Rust, it's that *process and structure are essential*. Take a look at the ["People Systems" keynote that Aaron, Ashley, and I gave at RustConf 2018][ps] and you will see that theme running throughout. So many of Rust's greatest practices -- things like the teams or RFCs or public, rfcbot-based decision making -- are an attempt to take some kind of informal, unstructured process and give it shape.

[lp]: https://www.amazon.jobs/content/en/our-workplace/leadership-principles

[ps]: https://youtu.be/J9OFQm8Qf1I?si=0L6jkbD501-_ACka

[^hypotheses]: I really like this [Learning for Action page][lfa], which I admit I found just by [googling for "strategy articulate a hypotheses"][lmgtfy]. I'm less into this [super corporate-sounding LinkedIn post][strategy-hypothesis], but I have to admit I think it's right on the money. 

[lfa]: http://learningforaction.com/articulate-the-hypothesis

[lmgtfy]: https://letmegooglethat.com/?q=strategy+articulate+a+hypothesis

[strategy-hypothesis]: https://www.linkedin.com/pulse/strategy-hypothesis-bryan-whitefield-1c

## Axioms have an ordering and earlier things take priority

Each axiom is useful on its own, but where things become interesting is when they come into conflict. Consider reliability: that is a core axiom of Rust, no doubt, but is it the most important? I would argue it is not. If it were, we wouldn't permit unsafe code, or at least not without a safety proof. I think our core axiom is actually that Rust is is meant to be used, and used for building a particular kind of program. I articulated it like this:

> **Rust is meant to empower *everyone* to build reliable and efficient software,** so above all else, Rust needs to be **accessible** to a broad audience. We avoid designs that will be too complex to be used in practice. We build supportive tooling that not only points out potential mistakes but helps users understand and fix them.

When it comes to safety, I think Rust's approach is eminently practical. We've designed a safe type system that we believe covers 90-95% of what people need to do,  and we are always working to expand that scope. We to get that last 5-10%, we fallback to unsafe code. Is this as safe and reliable as it could be? No. That would be requiring 100% proofs of correctness. There are systems that do that, but they are maintained by a [small handful of experts](http://web1.cs.columbia.edu/~junfeng/09fa-e6998/papers/sel4.pdf), and that idea -- that systems programming is just for "wizards" -- is exactly what we are trying to get away from.

To express this in our axioms, we put **accessible** as the top-most axiom. It defines the mission overall. But we put **reliability** as the second in the list, since that takes precedence over everything else.

## The design axioms I really like

Without further ado, here is my current list design axioms. Well, part of it. These are the axioms that I feel pretty good about it. The ordering also feels right to me.

> We believe that...
>
> * **Rust is meant to empower *everyone* to build reliable and efficient software,** so above all else, Rust needs to be **accessible** to a broad audience. We avoid designs that will be too complex to be used in practice. We build supportive tooling that not only points out potential mistakes but helps users understand and fix them.
> * **Rust users want to surface problems as early as possible,** and so Rust is designed to be **reliable**. We make choices that help surface bugs earlier. We don't make guesses about what our users meant to do, we let them tell us, and we endeavor to make the meaning of code transparent to its reader. And we always, always guarantee memory safety and data-race freedom in safe Rust code.
> * **Rust users are just as obsessed with quality as we are,** and so Rust is **extensible**. We empower our users to build their own abstractions. We prefer to let people build what they need than to try (and fail) to give them everything ourselves.
> * **Systems programmers need to know what is happening and where,** and so system details and especially performance costs in Rust are **transparent and tunable**. When building systems, it's often important to know what's going on underneath the abstractions. Abstractions should still leave the programmer feeling like they're in control of the underlying system, such as by making it easy to notice (or avoid) certain types of operations.
>
> ...where earlier things take precedence.

## The design axioms that are still a work-in-progress

These axioms are things I am less sure of. It's not that I don't think they are true. It's that I don't know yet if they're worded correctly. Maybe they should be combined together? And where, exactly, do they fall in the ordering?

> * **Rust users want to focus on solving their problem, not the fiddly details,** so Rust is **productive**. We favor APIs that where the most convenient and high-level option is also the most efficient one. We support portability across operating systems and execution environments by default. We aren't explicit for the sake of being explicit, but rather to surface details we believe are needed.
> * **N✕M is bigger than N+M**, and so we design for **composability and orthogonality**. We are looking for features that tackle independent problems and build on one another, giving rise to N✕M possibilities.
> * **It's nicer to use one language than two,** so Rust is **versatile**. Rust can't be the best at everything, but we can make it decent for just about anything, whether that's low-level C code or high-level scripting.

Of these, I like the first one best. Also, it follows the axiom structure better, because it starts with a hypothesis about Rust users and what they want. The other two are a bit older and I hadn't adopted that convention yet.

## Help shape the axioms!

My ultimate goal is to author an RFC endorsing these axioms for Rust. But I need help to get there. Are these the right axioms? Am I missing things? Should we change the ordering?

I'd love to know what you think! To aid in collaboration, I've created a [nikomatsakis/rust-design-axioms][repo] github repository. It [hosts the current state of the axioms](https://nikomatsakis.github.io/rust-design-axioms/intro.html) and also has [suggested ways to contribute](https://nikomatsakis.github.io/rust-design-axioms/contributing.html).

[repo]: https://github.com/nikomatsakis/rust-design-axioms

I've already opened [issues](https://github.com/nikomatsakis/rust-design-axioms/issues) for some of the things I am wondering about, such as:

* [nikomatsakis/rust-design-axioms#1](https://github.com/nikomatsakis/rust-design-axioms/issues/1): Maybe we need a "performant" axiom? Right now, the idea of "zero-cost abstractions" and ""the default thing is also the most efficient one" feels a bit smeared across "transparent and tunable" and "productive".
* [nikomatsakis/rust-design-axioms#2](https://github.com/nikomatsakis/rust-design-axioms/issues/2): Is "portability" sufficiently important to pull out from "productivity" into its own axiom?
* [nikomatsakis/rust-design-axioms#3](https://github.com/nikomatsakis/rust-design-axioms/issues/3): Are "versatility" and "orthogonality" really expressing something different from "productivity"?

[Check it out!](https://nikomatsakis.github.io/rust-design-axioms/)



