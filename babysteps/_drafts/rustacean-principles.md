---
layout: post
title: 'Rustacean Principles'
categories: [AiC]
excerpt_separator: <!--more-->
---

As the [web site] says, Rust is a *language empowering everyone to build reliable and efficient software*. I think it's precisely this feeling of *empowerment* that has kept Rust as the top of the stackoverflow "most loved" list for so long. As [wycats] put it recently to me, "[using Rust,] I feel like things are possible that otherwise feel out of reach". But what is it that makes Rust feel that way? If we can describe it, then we can use that description to help us improve Rust, and to guide us as we design extensions to Rust.

Besides the language itself, Rust is also an open-source community, one that prides itself on our ability to do collaborative design. But what do we do which makes us able to work well together? If we can describe *that*, then we can use those descriptions to help ourselves improve, and to instruct new people on how to better work within the community.

This blog post describes a project I and others have been working on called [the Rustacean principles][RP]. This project is an attempt to enumerate the (heretofore implicit) principles that govern both Rust's design and the way our community operates. The principles are a definite "work-in-progress"; for the time being, they live in the [nikomatsakis/rustacean-principles][repo] repository.

[repo]: https://github.com/nikomatsakis/rustacean-principles

<!-- more -->

### How the principles got started

The Rustacean Principles were [Shane]'s idea. She suggested them during a discussion about how to grow the Rust organization while keeping it true to itself. Shane pointed out that, at AWS, mechanisms like [tenets] and the [leadership principles] are used to communicate and preserve shared values.[^team] The goal is to have teams that operate independently but which still wind up "itching in the same direction", as [aturon] [so memorably put it]. The idea was that these same mechanisms might be useful in an open source context.

[^team]: One of the first things that our team did at Amazon was to draft [its own tenets]; the discussion helped us to clarify what we were setting out to do and how we planned to do it.

Since that initial conversation, the principles have undergone quite some iteration. The initial effort, which I [presented](https://youtu.be/ksSuXNmGZNA?t=2001) at the [CTCFT] on [2021-06-21], were quite closely modeled on AWS tenets. After a number of in-depth conversations with both [joshtriplett] and [aturon], though, I wound up evolving the structure quite a bit to what you see today. I expect them to continue evolving, particularly the section on what it means to be a team member, which has received less attention.

### Rust empowers by being...

The [principles][RP] are broken into two main sections. The first describes Rust's particular way of empowering people. This description comes in the form of a list of *properties* that we are shooting for:

* [Rust empowers by being...]
    * ⚙️ [Reliable]: "if it compiles, it works"
    * 🐎 [Performant]: "idiomatic code runs efficiently"
    * 🧩 [Productive]: "a little effort does a lot of work"
    * 🥰 [Supportive]: "the language, tools, and community are here to help"
    * 🔧 [Transparent]: "predict and control low-level details"
    * 🤸 [Versatile]: "you can do anything with Rust"

These properties are frequently in tension with one another. Our challenge as designers is to find ways to satisfy all of these properties at once. For those cases where we must tradeoff one with another, the properties are ordered: we tend to prefer to satisfy those earlier in the list (while making design choices that minimize the impact on those that come later in the list). As an example, making Rust feel *reliable* can easily come at the cost of making Rust feel *productive* or *supportive*, and so we must be careful as we make changes to weigh the impact carefully.

Each of the properties has a page that describes it in more detail. The page also describes some specific **mechanisms** that we use to achieve this property. These mechanisms take the form of more concrete rules that we apply to Rust's design. For example, the page for [reliability][reliable] discusses [type safety], [consider all cases], and several other mechanisms. The discussion gives concrete examples of the tradeoffs at play and some of the techniques we have used to mitigate them.

### How to Rustacean

Rust has been an open source project since its inception, and over time we have evolved and refined the way that we operate. One key concept for Rust are the [governance teams](https://www.rust-lang.org/governance), whose members are responsible for decisions regarding Rust's design and maintenance. We definitely have a notion of what it means "to Rustacean" -- there are specific behaviors that we are looking for. But it has historically been really challenging to define them, and in turn to help people to achieve them (or to recognize when we ourselves are falling short!). The next section of this site, [How to Rustacean], is a first attempt at drafting just such a list. You can think of it like a companion to the [Code of Conduct][CoC]: whereas the [CoC] describes the bare minimum expected of any Rust participant, the [How to Rustacean] section describes what is means to excel.

* [How to Rustacean]
    * [💖 Be kind and considerate]
    * [✨ Bring joy to the user]
    * [👋 Show up]
    * [🔭 Recognize others' knowledge]
    * [🔁 Start somewhere]
    * [✅ Follow through]
    * [🤝 Pay it forward]
    * [🎁 Trust and delegate]

This section of the site has undergone less iteration than the "Rust empowerment" section. The idea is that each of these principles has a dedicated page that elaborates on the principle and gives examples of it in action. The [Show up][👋 Show up] page is the most developed and a good one to look at to get the idea. You can see that it 

[^goldilocks]: Hat tip to Marc Brooker, who suggested the "Goldilocks" structure.

### What comes next

I think at this point the principles have evolved enough that it makes sense to get more widespread feedback. I'm interested in hearing from people who are active in the Rust community about whether they reflect what you love about Rust (and, if not, what might be changed). I also plan to try and use them to guide both design discussions and questions of team membership, and I encourage others in the Rust teams to do the same. If we find that they are useful, then I'd like to see them live on forge or somewhere more central.

[aturon]: https://github.com/aturon/

[wycats]: https://github.com/wycats/

[so memorably put it]: https://youtu.be/J9OFQm8Qf1I?t=1312 

[CTCFT]: https://rust-ctcft.github.io/ctcft/

[DP]: https://youtu.be/ksSuXNmGZNA?t=2001

[its own tenets]: https://aws.amazon.com/blogs/opensource/how-our-aws-rust-team-will-contribute-to-rusts-future-successes/

[Shane]: https://foundation.rust-lang.org/posts/2021-04-15-introducing-shane-miller/

[pnkfelix]: http://pnkfx.org/pnkfelix/

[RP]: https://rustacean-principles.netlify.app/

[tenets]: https://aws.amazon.com/blogs/enterprise-strategy/tenets-provide-essential-guidance-on-your-cloud-journey/

[leadership principles]: https://www.amazon.jobs/en/principles

[repo]: https://github.com/nikomatsakis/rustacean-principles

[Rust empowers by being...]: https://rustacean-principles.netlify.app/how_rust_empowers.html
[Reliable]: https://rustacean-principles.netlify.app/how_rust_empowers/reliable.html
[Performant]: https://rustacean-principles.netlify.app/how_rust_empowers/performant.html
[Productive]: https://rustacean-principles.netlify.app/how_rust_empowers/productive.html
[Supportive]: https://rustacean-principles.netlify.app/how_rust_empowers/supportive.html
[Transparent]: https://rustacean-principles.netlify.app/how_rust_empowers/transparent.html
[Versatile]: https://rustacean-principles.netlify.app/how_rust_empowers/versatile.html

[type safety]: https://rustacean-principles.netlify.app/how_rust_empowers/reliable.html#type-safety-but-with-an-unsafe-escape-hatch

[consider all cases]: https://rustacean-principles.netlify.app/how_rust_empowers/reliable.html#consider-all-cases

[CoC]: https://www.rust-lang.org/policies/code-of-conduct

[how to rustacean]: https://rustacean-principles.netlify.app/how_to_rustacean.html

[💖 Be kind and considerate]: https://rustacean-principles.netlify.app/how_to_rustacean/be_kind.html
[✨ Bring joy to the user]: https://rustacean-principles.netlify.app/how_to_rustacean/bring_joy.html
[👋 Show up]: https://rustacean-principles.netlify.app/how_to_rustacean/show_up.html
[🔭 Recognize others' knowledge]: https://rustacean-principles.netlify.app/how_to_rustacean/recognize_others.html
[🔁 Start somewhere]: https://rustacean-principles.netlify.app/how_to_rustacean/start_somewhere.html
[✅ Follow through]: https://rustacean-principles.netlify.app/how_to_rustacean/follow_through.html
[🤝 Pay it forward]: https://rustacean-principles.netlify.app/how_to_rustacean/pay_it_forward.html
[🎁 Trust and delegate]: https://rustacean-principles.netlify.app/how_to_rustacean/trust_and_delegate.html