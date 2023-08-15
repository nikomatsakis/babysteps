---
categories:
- AiC
date: "2021-09-08T00:00:00Z"
excerpt_separator: <!-- more -->
slug: rustacean-principles
title: Rustacean Principles
---

As the [web site] says, Rust is a *language empowering everyone to build reliable and efficient software*. I think it's precisely this feeling of *empowerment* that people love about Rust. As [wycats] put it recently to me, Rust makes it "feel like things are possible that otherwise feel out of reach". But what exactly makes Rust feel that way? If we can describe it, then we can use that description to help us improve Rust, and to guide us as we design extensions to Rust.

[web site]: https://www.rust-lang.org/

Besides the language itself, Rust is also an open-source community, one that prides itself on our ability to do collaborative design. But what do we do which makes us able to work well together? If we can describe *that*, then we can use those descriptions to help ourselves improve, and to instruct new people on how to better work within the community.

This blog post describes a project I and others have been working on called [the Rustacean principles][RP]. This project is an attempt to enumerate the (heretofore implicit) principles that govern both Rust's design and the way our community operates. **The principles are still in draft form**; for the time being, they live in the [nikomatsakis/rustacean-principles][repo] repository.

[repo]: https://github.com/nikomatsakis/rustacean-principles

<!--more-->

### How the principles got started

The Rustacean Principles were suggested by [Shane] during a discussion about how we can grow the Rust organization while keeping it true to itself. Shane pointed out that, at AWS, mechanisms like [tenets] and the [leadership principles] are used to communicate and preserve shared values.[^team] The goal at AWS, as in the Rust org, is to have teams that operate independently but which still wind up "itching in the same direction", as [aturon][] [so memorably put it][].

[^team]: One of the first things that our team did at Amazon was to draft [its own tenets]; the discussion helped us to clarify what we were setting out to do and how we planned to do it.

Since that initial conversation, the principles have undergone quite some iteration. The initial effort, which I [presented](https://youtu.be/ksSuXNmGZNA?t=2001) at the [CTCFT] on [2021-06-21], were quite closely modeled on AWS tenets. After a number of in-depth conversations with both [joshtriplett] and [aturon], though, I wound up evolving the structure quite a bit to what you see today. I expect them to continue evolving, particularly the section on what it means to be a team member, which has received less attention.

### Rust empowers by being...

The [principles][RP] are broken into two main sections. The first describes Rust's particular way of empowering people. This description comes in the form of a list of *properties* that we are shooting for:

* [Rust empowers by being...]
    * ⚙️ [Reliable]: "if it compiles, it works"
    * 🐎 [Performant]: "idiomatic code runs efficiently"
    * 🥰 [Supportive]: "the language, tools, and community are here to help"
    * 🧩 [Productive]: "a little effort does a lot of work"
    * 🔧 [Transparent]: "you can predict and control low-level details"
    * 🤸 [Versatile]: "you can do anything with Rust"

These properties are frequently in tension with one another. Our challenge as designers is to find ways to satisfy all of these properties at once. In some cases, though, we may be forced to decide between slightly penalizing one goal or another. In that case, we tend to give the edge to those goals that come earlier in the list over those that come later. Still, while the ordering is important, it's important to emphasize that for Rust to be successful we need to achieve **all of these feelings at once**.

Each of the properties has a page that describes it in more detail. The page also describes some specific **mechanisms** that we use to achieve this property. These mechanisms take the form of more concrete rules that we apply to Rust's design. For example, the page for [reliability][reliable] discusses [type safety], [consider all cases], and several other mechanisms. The discussion gives concrete examples of the tradeoffs at play and some of the techniques we have used to mitigate them.

One thing: these principles are meant to describe more than just the language. For example, one example of Rust being [supportive] are the great [error messages], and Cargo's lock files and dependency system are geared towards making Rust feel [reliable]. 

[error messages]: https://rustacean-principles.netlify.app/how_rust_empowers/supportive/polished.html

### How to Rustacean

Rust has been an open source project since its inception, and over time we have evolved and refined the way that we operate. One key concept for Rust are the [governance teams], whose members are responsible for decisions regarding Rust's design and maintenance. We definitely have a notion of what it means "to Rustacean" -- there are specific behaviors that we are looking for. But it has historically been really challenging to define them, and in turn to help people to achieve them (or to recognize when we ourselves are falling short!). The next section of this site, [How to Rustacean], is a first attempt at drafting just such a list. You can think of it like a companion to the [Code of Conduct][CoC]: whereas the [CoC] describes the bare minimum expected of any Rust participant, the [How to Rustacean] section describes what it means to excel.

[governance teams]: https://www.rust-lang.org/governance

* [How to Rustacean]
    * 💖 [Be kind and considerate]
    * ✨ [Bring joy to the user]
    * 👋 [Show up]
    * 🔭 [Recognize others' knowledge]
    * 🔁 [Start somewhere]
    * ✅ [Follow through]
    * 🤝 [Pay it forward]
    * 🎁 [Trust and delegate]

This section of the site has undergone less iteration than the "Rust empowerment" section. The idea is that each of these principles has a dedicated page that elaborates on the principle and gives examples of it in action. The example of [Raising an objection about a design] (from [Show up]) is the most developed and a good one to look at to get the idea. One interesting bit is the "goldilocks" structure[^goldilocks], which indicates what it means to "show up" too little but also what it means to "show up" *too much*.

[raising an objection about a design]: https://rustacean-principles.netlify.app/how_to_rustacean/show_up/raising_an_objection.html

[^goldilocks]: Hat tip to [Marc Brooker], who suggested the "Goldilocks" structure, based on how the [Leadership Principles] are presented in the AWS wiki.

[Marc Brooker]: https://twitter.com/marcjbrooker

### How the principles can be used

For the principles to be a success, they need to be more than words on a website. I would like to see them become something that we actively reference all the time as we go about our work in the Rust org.

As an example, we were recently wrestling with a minor point about the semantics of closures in Rust 2021. The details aren't that important ([you can read them here, if you like][writeup]), but the decision ultimately came down to a question of whether to adapt the rules so that they are smarter, but more complex. I think it would have been quite useful to refer to these principles in that discussion: ultimately, I think we chose to (slightly) favor [productivity] at the expense of [transparency], which aligns well with the ordering on the site. Further, as I noted in [my conclusion], I would personally like to see some form of [explicit capture clause](https://zulip-archive.rust-lang.org/stream/213817-t-lang/topic/capture.20clauses.html) for closures, which would give users a way to ensure total [transparency] in those cases where it is most important.

The [How to Rustacean] section can be used in a number of ways. One thing would be cheering on examples of where someone is doing a great job: [Mara]'s [issue celebrating all the contributions to the 2021 Edition][#88623] is a great instance of [paying it forward][pay it forward], for example, and I would love it if we had a precise vocabulary for calling that out. 

[Mara]: https://github.com/m-ou-se/
[#88623]: https://github.com/rust-lang/rust/issues/88623

Another time these principles can be used is when looking for new candidates for team membership. When considering a candidate, we can look to see whether we can give concrete examples of times they have exhibited these qualities. We can also use the principles to give feedback to people about where they need to improve. I'd like to be able to tell people who are interested in joining a Rust team, "Well, I've noticed you do a great job of [showing up][show up], but your designs tend to get mired in complexity. I think you should work on [start somewhere]." 

"Hard conversations" where you tell someone what they can do better are something that mangers do (or try to do...) in companies, but which often get sidestepped or avoided in an open source context. I don't claim to be an expert, but I've found that having structure can help to take away the "sting" and make it easier for people to hear and learn from the feedback.[^ft]

[^ft]: Speaking of which, one glance at my queue of assigned PRs make it clear that I need to work on my [follow through].

### What comes next

I think at this point the principles have evolved enough that it makes sense to get more widespread feedback. I'm interested in hearing from people who are active in the Rust community about whether they reflect what you love about Rust (and, if not, what might be changed). I also plan to try and use them to guide both design discussions and questions of team membership, and I encourage others in the Rust teams to do the same. If we find that they are useful, then I'd like to see them turned into an RFC and ultimately living on forge or somewhere more central.

### Questions?

I've opened an [internals thread](https://internals.rust-lang.org/t/blog-post-rustacean-principles/15300) for discussion.

### Footnotes

[writeup]: https://github.com/rust-lang/project-rfc-2229/blob/master/design-doc-closure-capture-drop-copy-structs.md

[my conclusion]: https://github.com/rust-lang/project-rfc-2229/blob/master/design-doc-closure-capture-drop-copy-structs.md#nikos-conclusion

[aturon]: https://github.com/aturon/

[joshtriplett]: https://github.com/joshtriplett/

[wycats]: https://github.com/wycats/

[so memorably put it]: https://youtu.be/J9OFQm8Qf1I?t=1312 

[CTCFT]: https://rust-ctcft.github.io/ctcft/

[DP]: https://youtu.be/ksSuXNmGZNA?t=2001

[its own tenets]: https://aws.amazon.com/blogs/opensource/how-our-aws-rust-team-will-contribute-to-rusts-future-successes/

[Shane]: https://foundation.rust-lang.org/posts/2021-04-15-introducing-shane-miller/

[pnkfelix]: http://pnkfx.org/pnkfelix/

[tenets]: https://aws.amazon.com/blogs/enterprise-strategy/tenets-provide-essential-guidance-on-your-cloud-journey/

[leadership principles]: https://www.amazon.jobs/en/principles

[repo]: https://github.com/nikomatsakis/rustacean-principles

[RP]: https://rustacean-principles.netlify.app/
[Rust empowers by being...]: https://rustacean-principles.netlify.app/how_rust_empowers.html
[Reliable]: https://rustacean-principles.netlify.app/how_rust_empowers/reliable.html
[Performant]: https://rustacean-principles.netlify.app/how_rust_empowers/performant.html
[Productive]: https://rustacean-principles.netlify.app/how_rust_empowers/productive.html
[Productivity]: https://rustacean-principles.netlify.app/how_rust_empowers/productive.html
[Supportive]: https://rustacean-principles.netlify.app/how_rust_empowers/supportive.html
[Transparent]: https://rustacean-principles.netlify.app/how_rust_empowers/transparent.html
[Transparency]: https://rustacean-principles.netlify.app/how_rust_empowers/transparent.html
[Versatile]: https://rustacean-principles.netlify.app/how_rust_empowers/versatile.html
[Be kind and considerate]: https://rustacean-principles.netlify.app/how_to_rustacean/be_kind.html
[Bring joy to the user]: https://rustacean-principles.netlify.app/how_to_rustacean/bring_joy.html
[Show up]: https://rustacean-principles.netlify.app/how_to_rustacean/show_up.html
[Recognize others' knowledge]: https://rustacean-principles.netlify.app/how_to_rustacean/recognize_others.html
[Start somewhere]: https://rustacean-principles.netlify.app/how_to_rustacean/start_somewhere.html
[Follow through]: https://rustacean-principles.netlify.app/how_to_rustacean/follow_through.html
[Pay it forward]: https://rustacean-principles.netlify.app/how_to_rustacean/pay_it_forward.html
[Trust and delegate]: https://rustacean-principles.netlify.app/how_to_rustacean/trust_and_delegate.html
[type safety]: https://rustacean-principles.netlify.app/how_rust_empowers/reliable/type_safety.html
[consider all cases]: https://rustacean-principles.netlify.app/how_rust_empowers/reliable/consider_all_cases.html

[CoC]: https://www.rust-lang.org/policies/code-of-conduct

[how to rustacean]: https://rustacean-principles.netlify.app/how_to_rustacean.html

[2021-06-21]: https://rust-ctcft.github.io/ctcft/meetings/2021-06-21.html