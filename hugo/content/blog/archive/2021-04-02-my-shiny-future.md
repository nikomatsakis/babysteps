---
date: "2021-04-02T00:00:00Z"
slug: my-shiny-future
title: My "shiny future"
---

I've been working on the Rust project for just about ten years. The language has evolved radically in that time, and so has the project governance. When I first started, for example, we communicated primarily over the [rust-dev] mailing list and the #rust IRC channel. I distinctly remember coming into the Mozilla offices[^offices] one day and [brson] excitedly telling me, "There were almost a dozen people on the #rust IRC channel last night! Just chatting! About Rust!" It's funny to think about that now, given the scale Rust is operating at today.

## Scaling the project governance

Scaling the governance of the project to keep up with its growing popularity has been a constant theme. The first step was when we created a core team (initially [pcwalton], [brson], and I) to make decisions. We needed some kind of clear decision makers, but we didn't want to set up a single person as "BDFL". We also wanted a mechanism that would allow us to include non-Mozilla employees as equals.[^huonw] 

Having a core team helped us move faster for a time, but we soon found that the range of RFCs being considered was too much for one team. We needed a way to expand the set of decision makers to include focused expertise from each area. To address these problems, [aturon] and I created [RFC 1068], which expanded from a single "core team" into many Rust teams, each focused on accepting RFCs and managing a particular area.

[^huonw]: I think the first non-Mozilla member of the core team was [Huon Wilson], but I can't find any announcements about it. I did find this [very nicely worded post by Brian Andersion][3784] about Huon's *departure* though. "They live on in our hearts, and in our IRC channels." Brilliant.

[Huon Wilson]: https://huonw.github.io/
[3784]: https://internals.rust-lang.org/t/rust-team-alumni/3784

As written, [RFC 1068] described a central technical role for the core team[^feature], but it quickly became clear that this wasn't necessary. In fact, it was a kind of hindrance, since it introduced unnecessary bottlenecks. In practice, the Rust teams operated quite independently from one another. This independence enabled us to move rapidly on improving Rust; the RFC process -- [which we had introduced in 2014][RFC][^rfc] -- provided the "checks and balances" that kept teams on track.[^pub] As the project grew further, new teams like the [release team] were created to address dedicated needs.

[release team]: https://internals.rust-lang.org/t/announcing-the-release-team/6561

[^pub]: Better still, the RFC mechanism invites public feedback. This is important because no single team of people can really have expertise in the full range of considerations needed to design a language like Rust.

[dropbox]: https://dropbox.tech/infrastructure/rewriting-the-heart-of-our-sync-engine

The teams were scaling well, but there was still a bottleneck: most people who contributed to Rust were still doing so as volunteers, which ultimately limits the amount of time people can put in. This was a hard nut to crack[^nut], but we've finally seen progress this year, as more and more companies have been employing people to contribute to Rust. Many of them are forming entire teams for that purpose -- including AWS, where I am working now. And of course I would be remiss not to mention the [launch of the Rust Foundation][rf1] itself, which gives Rust a legal entity of its own and creates a forum where companies can pool resources to help Rust grow.

## My own role

My own trajectory through Rust governance has kind of mirrored the growth of the project. I was an initial member of the core team, as I said, and after we landed [RFC 1068] I became the lead of the compiler and language design teams. I've been wearing these three hats until very recently. 

In December, I decided to [step back as lead of the compiler team](https://smallcultfollowing.com/babysteps/blog/2020/12/11/rotating-the-compiler-team-leads/). I had a number of reasons for doing so, but the most important is that I want to ensure that the Rust project continues to scale and grow. For that to happen, we need to transition from one individual doing all kinds of roles to people focusing on those places where they can have the most impact.[^latam]

**Today I am announcing that I am stepping back from the Rust core team.** I plan to focus all of my energies on my roles as lead of the language design team and tech lead of the [AWS Rust Platform team][awsblog]. 

## Where we go from here

So now we come to my ["shiny future"][sf]. My goal, as ever, is to continue to help Rust pursue its vision of being an accessible systems language. Accessible to me means that we offer strong safety guarantees coupled with a focus on ergonomics and usability; it also means that we build a welcoming, inclusive, and thoughtful community. To that end, I expect to be doing more product initiatives like the [async vision doc] to help Rust build a coherent vision for its future; I also expect to continue working on ways to [scale the lang team], improve the RFC process, and help the teams function well.

I am so excited about all that we the Rust community have built. Rust has become a language that people not only use but that they love using. We've innovated not only in the design of the language but in the design and approach we've taken to our community. ["In case you haven't noticed...we're doing the impossible here people!"][impossible] So here's to the next ten years!

---

[^feature]: If you read [RFC 1068], for example, you'll see some language about the core team deciding what features to stabilize. I don't think this happened even once: it was immediately clear that the teams were better positioned to make this decision.

[rotation]: https://smallcultfollowing.com/babysteps/blog/2020/12/11/rotating-the-compiler-team-leads/

[^nut]: If you look back at my Rust roadmap posts, you'll see that this has been a theme in [every][] [single][] [one][].

[problems]: https://smallcultfollowing.com/babysteps/blog/2020/01/09/towards-a-rust-foundation/
[AWS]: https://smallcultfollowing.com/babysteps/blog/2020/12/30/the-more-things-change/
[every]: https://smallcultfollowing.com/babysteps/blog/2018/01/09/rust2018/
[single]: https://smallcultfollowing.com/babysteps/blog/2019/01/07/rust-in-2019-focus-on-sustainability/
[one]: https://smallcultfollowing.com/babysteps/blog/2019/12/02/rust-2020/#many-are-stronger-than-one
[tenets]: https://aws.amazon.com/blogs/opensource/how-our-aws-rust-team-will-contribute-to-rusts-future-successes/


[^latam]: I kind of love [these three slides](https://nikomatsakis.github.io/rust-latam-2019/#109) from my Rust LATAM 2019 talk, which expressed the same basic idea, but from a different perspective.

[scale the lang team]: https://github.com/rust-lang/lang-team/blob/master/design-meeting-minutes/2021-03-24-lang-team-organization.md

[impossible]: https://nikomatsakis.github.io/rust-latam-2019/#101

[sf]: https://rust-lang.github.io/wg-async-foundations/vision/shiny_future.html

[async vision doc]: https://blog.rust-lang.org/2021/03/18/async-vision-doc.html

[path to membership]: https://blog.rust-lang.org/inside-rust/2020/07/09/lang-team-path-to-membership.html

[rfc2229]: https://github.com/rust-lang/project-rfc-2229

[^aws]: Oh yeah, I [joined AWS] somewhere along the way, too.

[joined AWS]: https://smallcultfollowing.com/babysteps/blog/2020/12/30/the-more-things-change/

[awsblog]: https://aws.amazon.com/blogs/opensource/how-our-aws-rust-team-will-contribute-to-rusts-future-successes/

[lib]: https://smallcultfollowing.com/babysteps/blog/2020/04/09/libraryification/

[rf0]: https://smallcultfollowing.com/babysteps/blog/2020/01/09/towards-a-rust-foundation/

[rf1]: https://foundation.rust-lang.org/posts/2021-02-08-hello-world/

[^precore]: [dherman] was the one who suggested naming a formal core team. Before that, I think we didn't have a clear set of folks who decided what to do and what not to do. Very [Tyranny of Structurelessness][tyranny].

[^rfc]: The email makes this sound like a minor tweak to the process. Don't be fooled. It's true that people had always written "RFCs" to the mailing list. But they weren't mandatory, and there was no real process around "accepting" or "rejecting" them. The RFC process was a pretty radical change, more radical I think than we ourselves even realized. The best part of it was that it was not optional for anyone, including core developers.

[tyranny]: https://en.wikipedia.org/wiki/The_Tyranny_of_Structurelessness

[dherman]: https://github.com/dherman

[RFC 1068]: https://rust-lang.github.io/rfcs/1068-rust-governance.html

[RFC]: https://mail.mozilla.org/pipermail/rust-dev/2014-March/008973.html

[compiler]: https://www.rust-lang.org/governance/teams/compiler

[language design]: https://www.rust-lang.org/governance/teams/lang

[stepped back from the core team]: https://internals.rust-lang.org/t/aturon-retires-from-the-core-team-but-not-from-rust/9392/3

[^offices]: Offices! Remember those? Actually, I've been working remotely since 2013, so to be honest I barely do.

[brson]: https://github.com/brson

[aturon]: https://github.com/aturon

[pcwalton]: https://github.com/pcwalton

[rust-dev]: https://mail.mozilla.org/pipermail/rust-dev/

