---
categories:
- Rust
date: "2020-12-30T00:00:00Z"
slug: the-more-things-change
title: The more things change...
---
I've got an announcement to make. **As of Jan 4th, I'm starting at Amazon as the tech lead of their new Rust team.** Working at Mozilla has been a great experience, but I'm pretty excited about this change. It's a chance to help shape what I hope to be an exciting new phase for Rust, where we grow from a project with a single primary sponsor (Mozilla) to an industry standard, supported by a wide array of companies. It's also a chance to work with some pretty awesome people -- both familiar faces from the Rust community[^not-my-cake-to-bake] and some new folks. Finally, I'm hoping it will be an opportunity for me to refocus my attention to some long-standing projects that I really want to see through.

[^not-my-cake-to-bake]: I'll let them make their own announcements.

### New Rust teams are an opportunity, but we have to do it right

The goal for Rust has always been to create a language that will be used and supported by companies throughout the industry. With the [imminent launch][rf] of the Rust Foundation as well as the formation of new Rust teams at [Amazon], [Microsoft], and [Facebook], we are seeing that dream come to fruition. I'm very excited about this. This is a goal I've been working towards for years, and it was a [particular focus of mine for 2020][R2]. 

[rf]: https://blog.rust-lang.org/2020/12/14/Next-steps-for-the-foundation-conversation.html
[Microsoft]: https://twitter.com/ryan_levick/status/1171830191804551168
[Facebook]: https://twitter.com/nadavrot/status/1319003839018614784?lang=en
[Embark]: https://twitter.com/repi/status/1294987596146384897
[Amazon]: https://aws.amazon.com/blogs/opensource/why-aws-loves-rust-and-how-wed-like-to-help/
[R2]: {{ site.baseurl }}/blog/2019/12/02/rust-2020/#shifting-the-focus-from-adoption-to-investment

That said, I've talked to a number of people in the Rust community who feel nervous about this change. After all, we've worked hard to build an open source organization that values curiosity, broad collaboration, and uplifting others. As more companies form Rust teams, there's a chance that some of that could be lost, even if everyone has the best of intentions. While we all want to see more people paid to work on Rust, that can also result in "part time" contributors feeling edged out.

### Working to support Rust and its community

One reason that I am excited to be joining the team at Amazon is that our scope is very simple: **help make Rust the best it can be**.

In my view, "making Rust the best it can be" means not only doing good work, but doing that work **in concert with the rest of the Rust community**. That means sharing in the "maintenance work" of open source: reviews, bug fixes, tracking down regressions, organizing meetings, that sort of thing. But it also means expanding and nurturing the Rust teams we're a part of. It's good to fix a bug. It's better to find a newcomer and mentor them to fix it, or to extend the [rustc-dev-guide] so that it covers the code that had the bug.

The ultimate goal should be free and open collaboration. We'll know the Amazon team setup is working well if it doesn't really matter if the people we're collaborating with work at Amazon or not.

[rustc-dev-guide]: https://rustc-dev-guide.rust-lang.org/

### On pluralism and the Rust organization

I want to zoom out a bit to the broader picture. As I said in the intro, we are entering a new phase for Rust, one where there are multiple active Rust teams at different companies, all working as part of the greater Rust community to build and support Rust. This is something to celebrate. I think it will go a long way towards making Rust development more sustainable for everyone.

Even as we celebrate, it's worth recognizing that in many ways this exciting future is already here. Supporting Rust doesn't require forming a full-time Rust team. The Google [Fuchsia team], for example, has always made a point of not only using Rust but actively contributing to the community. [Ferrous Systems] has a number of folks who work within the Rust teams. In truth, there are a lot of employers who give their employees time to work on Rust -- way too many to list, even if I knew all their names. Then we have companies like [Embark] and others that actively fund work on their dependencies (shout-out to [cargo-fund](https://crates.io/crates/cargo-fund), an awesome tool developed by the equally awesome [acfoltzer](https://github.com/acfoltzer), who -- as it happens -- works at Fastly, another company that has been an active supporter of Rust).

[Fuchsia team]: https://fuchsia.dev/
[Ferrous Systems]: https://ferrous-systems.com/

This kind of collaboration is exactly what we envisioned when we setup things like the Rust teams and the RFC process. The ultimate goal is to have a "rich stew" of people with different interests and backgrounds all contributing to Rust, helping to ensure that Rust works well for systems programming everywhere. In order to do that successfully, you need both a structure like the Rust org but also an "open source whenever"[^jlord] setup that accommodates people with different amounts of availability, since the people you're trying to reach are not all available full time. I think we have room for improvement here -- this is what my [Adventures in Consensus][AiC] series is all about -- but ain't that always the truth?

[^jlord]: Hat tip to Jessica Lord, whose post ["Privilege, Community and Open Source"](http://jlord.us/blog/osos-talk.html) is one I still re-read regularly.

[AiC]: {{ site.baseurl }}/blog/2019/04/19/aic-adventures-in-consensus/

The trick of course is that in order to achieve "open source whenever", you need full-time people to help pull it all together. This in many ways has been the limiting factor for Rust thus far, and it is precisely what these new Rust teams -- with [support from the new Rust Foundation as well][scope] -- can and will change. We have a lot to look forward to!

[scope]: https://github.com/rust-lang/foundation-faq-2020/blob/main/FAQ.md#q-scope

### Footnotes
