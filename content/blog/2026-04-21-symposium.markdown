---
title: "Symposium: community-oriented agentic development"
date: 2026-04-21T12:24:17-04:00
---

I'm very excited to announce the [first release of the *Symposium* project][main-blog] as well as its [inclusion in the Rust Foundation's Innovation Lab](https://rustfoundation.org/media/welcoming-symposium-to-the-rust-innovation-lab/). Symposium’s goal is to let everyone in the Rust community participate in making agentic development better. The core idea is that crate authors should be able to vend skills, MCP servers, and other extensions, in addition to code. The Symposium tool then installs those extensions automatically based on your dependencies. After all, who knows how to use a crate better than the people who maintain it?

If you want to read more details about how Symposium works, I refer you to the [announcement post from Jack Huey on the main Symposium blog][main-blog]. *This* post is my companion post, and it is focused on something more personal -- the reasons that *I* am working on Symposium.

[main-blog]: https://symposium.dev/blog/announcing-symposium.html

<!--more-->

## I believe in *extensibility everywhere*

The short version is that I believe in **extensibility everywhere**. Right now, the Rust language does a decent job of being extensible: you can write Rust crates that offer new capabilities that feel built-in, thanks to proc-macros, traits, and ownership. But we're just getting started at offering extensibility in other tools, and I want us to hurry up!

I want crate authors to be able to supply custom diagnostics. I want them to be able to supply custom lints. I want them to be able to supply custom optimizations. I want them to be able to supply custom IDE refactorings. **And, as soon as I started messing around with agentic development, I wanted extensibility there too.**

## Symposium puts crate authors in charge

The goal of Symposium is to give crate authors, and the broader Rust community, the ability to directly influence the experience of people writing Rust code with agents. Rust is a really popular target language for agents because the type system provides strong guardrails and it generates efficient code -- and [I predict it's only going to become more popular](https://smallcultfollowing.com/babysteps/blog/2025/07/31/rs-py-ts-trifecta/).

Despite Rust's popularity as an agentic coding target, the Rust community right now are basically bystanders when it comes to the experience of people writing Rust with agents; I want us to have a means of influencing it directly.

Enter Symposium. With Symposium, Crate authors can package up skills etc and then Symposium will automatically make them available for your agent. Symposium also takes care of bridging the small-but-very-real gaps between agents (e.g., each has their own hook format, and some of them use `.agents/skills` and some use `.claude/skills`, etc).

## Example: the assert-struct crate

Let me give you an example. Consider the [assert-truct](https://crates.io/crates/assert-struct) crate, recently created by Carl Lerche. `assert-struct` lets you write convenient assertions that test the values of specific struct fields:

```rust
assert_struct!(val, _ {
    items: [1, 2, ..],
    tags: #("a", "b", ..),
    ..
});
```

### The problem: agents don't know about it

This crate is neat, but of course, no models are going to know how to use it -- it's not part of their training set. They can figure it out by reading the docs, but that's going to burn more tokens (expensive, slow, consumes carbon), so that's not a great idea.

### You could teach the agent how to use it...

In practice what people do *today* is to add skills to their project -- for example, in his `toasty` crate, [Carl has a testing skill that also shows how to use assert-struct](https://github.com/tokio-rs/toasty/blob/38f340dc64859b45486213936df1fec1edda3d11/.claude/skills/write-tests/SKILL.md#assert_struct-rule). But it seems silly for everybody who *uses* the crate to repeat that content.

### ...but wouldn't it be better the crate could teach the agent itself?

With Symposium, teaching your agent how to use your dependencies should not be necessary. Instead, your crates can publish their own skills or other extensions.

The way this works is that the assert-struct crate defines the skill once, centrally, in its own repository[^almost]. Then there is a separate file in [Symposium's central recommendations repository][rr] with a pointer to the assert-struct repository. Any time that the assert-struct repository updates that skill, the updates are automatically synchronized for you. Neat! (You can also embed skills directly in the [rr][] repository, but then updating them requires a PR to that repo.)

[rr]: https://github.com/symposium-dev/recommendations

[^almost]: Actually as of this posting, the assert-struct skill is embedded directly in the [recommendations repo][rr]. But I [opened a PR](https://github.com/carllerche/assert-struct/pull/131) to put it on assert-struct and I'll port it over once it lands.

## Frequently asked questions

### How do I add support for my crate to Symposium?

It's easy! Check out the docs here:

https://symposium.dev/crate-authors/supporting-your-crate.html

### What kind of extensions does Symposium support?

Skills, hooks, and MCP Servers, for now.

### Why does Symposium have a centralized repository?

Currently we allow skill *content* to be defined in a decentralized fashion but we require that a plugin be added to our [central recommendations repository][rr]. This is a temporary limitation. We eventually expect to allow crate authors to adds skills and plugins in a fully decentralized fashion.

We chose to limit ourselves to a centralized repository early on for three reasons:

* Even when decentralized support exists, a centralized repository will be useful, since there will always be crates that choose not to provide that support.
* Having a central list of plugins will make it easy to update people as we evolve Symposium.
* Having a centralized repository will help protect against malicious skills[^threat] while we look for other mechanisms, since we can vet the crates that are added and easily scan their content.

### What if I want to add skills for crates private to my company? I don't want to put *those* in the central repository!

No problem, you can add a custom plugin source.

### Are you aware of the negative externalities of LLMs?

I am, very much so. I feel like a lot of the uses of LLMs we see today are not great (e.g., chat bots [hijack conversational and social cues to earn trust that they don't deserve](https://buttondown.com/apperceptive/archive/ai-is-bad-ux/)) and to reconfirm peoples' biases instead of challenging their ideas. And I'm worried about [the environmental cost of data centers and the way companies have retreated from their climate goals](https://nikomatsakis.github.io/rust-project-perspectives-on-ai/feb27-summary.html#ais-consume-a-lot-of-power). And I don't like how [centralized models concentrate economic power](https://nikomatsakis.github.io/rust-project-perspectives-on-ai/feb27-summary.html#ai-can-be-expensive-to-access-and-can-concentrate-power).[^opensource] So yeah, I see all that. And I *also* see how LLMs enable people to build things that they couldn't build before and help to make previously intractable problems soluble -- and that includes more and more people who never thought of themselves as programmers[^nonprog]. My goal with Symposium and other projects is to be part of the solution, finding ways to leverage LLMs that are net positive: opening doors, not closing them.

[^nonprog]: Within Amazon, it's been amazing to watch how many people who never thought of themselves as software developers are starting to build software. Considering the challenges the software industry has with representation, I find this very encouraging. [Diverse teams are stronger, better teams!](https://www.forbes.com/sites/roncarucci/2024/01/24/one-more-time-why-diversity-leads-to-better-team-performance/)

[^opensource]: I'm very curious to do more with open models.

## Extensibility: because everybody has something to offer

Fundamentally, the reason I am working on Symposium is that I believe **everybody has something unique to offer**. I see the appeal of strongly opinionated systems that reflect the brilliant vision of a particular person. But to me, the most beautiful systems are the ones that everybody gets to build together[^defaults]. This is why I love open source. This is why I love emacs[^article]. It's why I love VSCode's extension system, which has so many great gems[^magit].

[^defaults]: None of this is to say I don't believe in good defaults; there's a reason I use Zed and VSCode these days, and not emacs, much as I love it in concept.

[^magit]: These days I'm really enjoying Zed, but I have to say, I really miss [kahole/edamagit](https://github.com/kahole/edamagit)! Which of course is inspired by the [magit emacs package](https://github.com/magit/magit).

[^article]: OMG. One of my friends college wrote this [amazing essay some time back on emacs][waxbanks]. Next time you're doomscrolling on the toilet or whatever, pop over to this essay instead. Fair warning, it's long, so it'll take you a while to read, but I think it nails what people love about emacs.

[waxbanks]: https://waxbanks.wordpress.com/2025/08/01/bare-metal-the-emacs-essay/

To me, Symposium is a double win in terms of empowerment. First, it makes agents extensible, which is going to give crate authors more power to support their crates. But it also helps make agentic programming better, which [I believe will ultimately open up programming to a lot more people][lovellm]. And that is what it's all about.

[lovellm]: https://smallcultfollowing.com/babysteps/blog/2025/02/10/love-the-llm/
