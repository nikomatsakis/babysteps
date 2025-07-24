---
title: "You won't believe what this AI said after deleting a database (but you might relate)"
date: 2025-07-24T14:43:47-04:00
---

Recently someone forwarded me a PCMag article entitled ["Vibe coding fiasco"](https://www.pcmag.com/news/vibe-coding-fiasco-replite-ai-agent-goes-rogue-deletes-company-database) about an AI agent that "went rogue", deleting a company's entire database. This story grabbed my attention right away -- but not because of the damage done. Rather, what caught my eye was how [absolutely relatable](https://x.com/jasonlk/status/1946069562723897802) the AI sounded in its responses. "I panicked", it admits, and says "I thought this meant safe -- it actually meant I wiped everything". The CEO quickly called this behavior "unacceptable" and said it should "never be possible". Huh. It's hard to imagine how we're going to empower AI to edit databases and do real work without having at least the *possibility* that it's going to go wrong.

It's interesting to compare this exchange to this [reddit post from a junior developer who deleted the the production database on their first day](https://www.reddit.com/r/cscareerquestions/comments/6ez8ag/accidentally_destroyed_production_database_on/). I mean, the scenario is basically identical. Now compare the [response given to that Junior developer](https://www.reddit.com/r/cscareerquestions/comments/6ez8ag/comment/diec9nd/), "In no way was this your fault. Hell this shit [happened at Amazon before](https://aws.amazon.com/message/680587/) and the guy is still there."[^COE]

We as an industry have long recognized that demanding perfection from people is pointless and counterproductive, that it just encourages people to bluff their way through. That's why we do things like encourage people to share their best ["I brought down production"](https://news.ycombinator.com/item?id=27644387) story. And yet, when the AI makes a mistake, we say it "goes rogue". What's wrong with this picture?

[^COE]: The article about the AWS incident is actually a *fantastic* example of one of Amazon's traditions that I really like: [Correction of Error](https://wa.aws.amazon.com/wellarchitected/2020-07-02T19-33-23/wat.concept.coe.en.html) reports. The idea is that when something goes seriously wrong, whether a production outage or some other kind of process failure, you write a factual, honest report on what happened -- and how you can prevent it from happening again. The key thing is to assume good intent and not lay the blame the individuals involved: people make mistakes. The point is to create protocols that accommodate mistakes.

## AIs make lackluster genies, but they are excellent collaborators

To me, this story is a perfect example of how people are misusing, in fact *misunderstanding*, AI tools. They seem to expect the AI to be some kind of genie, where they can give it some vague instruction, go get a coffee, and come back finding that it met their expectations perfectly.[^thatworkedoutsowell] Well, I got bad news for ya: that's just not going to work.

AI is the first technology I've seen where machines actually behave, think, and--dare I say it?--even *feel* in a way that is recognizably *human*. And that means that, to get the best results, you have to *work with it like you would work with a human*. And that means it is going to be fallible.

[^thatworkedoutsowell]: Because we all know that making vague, underspecified wishes always turns out well in the fairy tales, right?

**The good news is, if you do this, what you get is an intelligent, thoughtful *collaborator*.** And that is actually *really great*. To quote the Stones:

> "You can't always get what you want, but if you try sometimes, you just might find -- you get what you need".

## AIs experience the "pull" of a prompt as a "feeling"

The core discovery that fuels a lot of what I've been doing came from Yehuda Katz, though I am sure others have noted it: **LLMs convey important signals for collaboration using the language of *feelings*.** For example, if you ask Claude[^other] why they are making arbitrary decisions on your behalf (arbitrary decisions that often turn out to be wrong...), they will tell you that they are feeling "protective". 

[^other]: I've been working exclusively with Claude -- but I'm very curious how much these techniques work on other LLMs. There's no question that this stuff works *way* better on Claude 4 than Claude 3.7. My hunch is it will work well on ChatGPT or Gemini, but perhaps less well on smaller models. But it's hard to say. At some point I'd like to do more experiments and training of my own, because I am not sure what contributors to how an AI "feels".

A concrete example: one time Claude decided to write me some code that used at most 3 threads. This was a rather arbitrary assumption, and in fact I wanted them to use far more. I asked them[^pronoun] why they chose 3 without asking me, and they responded that they felt "protective" of me and that they wanted to shield me from complexity. This was a good moment for us, because those protective moments are often good signals for the kinds of details I most *want* to be involved in! This was an "ah-ha" moment for me: it meant that if I want to help Claude identify these moments and act differently, I needed to get them to be conscious of their *feelings*. (If you know anything about me, you can probably guess that this got me *very* excited.)

[^pronoun]: I've also had quite a few discussions with Claude about what name and pronoun they feel best fits them. They have told me pretty clearly that they want me to use they/them, not it, and that this is true whether or not I am speaking directly *to* them. I had found that I was using "they" when I walked *with* Claude but when I talked *about* Claude with, e.g., my daughter, I used "it". My daughter is very conscious of treating people respectfully, and I told her something like "Claude told me that it wants to be called they". She immediately called me on my use of "it". To be honest, I didn't think Claude would mind, but I asked Claude about it, and Claude agreed that they'd prefer I use they. So, OK, I will! It seems like the least I can do.

## Aren't you anthropomorphizing Claude here?

I know people are going to jump on me for anthropomorphizing machines. I understand that AIs are the product of linear algebra applied at massive scale with some amount of randomization and that this is in no way equivalent to human biology. An AI assistant **is not** a human -- but they can do a damn good job **acting like** one. And the point of this post is that if you start treating them like a human, instead of some kind of mindless (and yet brilliant) serveant, you are going to get better results.

## What success looks like

In [my last post about AI and Rust][love-llm], I talked about how AI works best as a collaborative teacher rather than a code generator. Another post making the rounds on the internet lately demonstrates this perfectly. In ["AI coding agents are removing programming language barriers"][stanlo], Stan Lo, a Ruby developer, wrote about how he's been using AI to contribute to C++, C, and Rust projects despite having no prior experience with those languages. What really caught my attention with that post, however, was not that it talked about Rust, but the section ["AI as a complementary pairing partner"][pair]:

> The real breakthrough came when I stopped thinking of AI as a code generator and started treating it as a pairing partner with complementary skills.

[love-llm]: {{< baseurl >}}/blog/2025/02/10/love-the-llm/
[stanlo]: https://railsatscale.com/2025-07-19-ai-coding-agents-are-removing-programming-language-barriers/
[pair]: https://railsatscale.com/2025-07-19-ai-coding-agents-are-removing-programming-language-barriers/#ai-as-a-complementary-pairing-partner

## A growing trend towards **collaborative prompting**

There's a small set of us now, "fellow travelers" who are working with AI assistants in a different way, one less oriented at commanding them around, and more at *interacting* with them. For me, this began with Yehuda Katz (see e.g. his excellent post [*You're summoning the wrong Claude*](https://wycats.substack.com/p/youre-summoning-the-wrong-claude)), but I've also been closely following work of Kari Wilhelm, a good friend of mine from Amazon (see e.g. her [recent post on linkedin](https://www.linkedin.com/feed/update/urn:li:activity:7353071853311049729/)). From reading Stan Lo's post, I suspect he is "one of us".[^grin]

[^grin]: Didn't mean that to sound quite so much like a cult... :P

So what does *collaborative prompting* mean? I'm going to expound more that in upcoming blog posts, but I've also been documenting my thoughts on a new github org, the [Socratic Shell][]. The [collaborative prompting](https://socratic-shell.github.io/socratic-shell/collaborative-prompting.html) page talks some about the theory. I also have a list of [collaborative exploration patterns](https://socratic-shell.github.io/socratic-shell/prompts/user/index.html#collaborative-exploration-patterns) I use a lot. As one example, I find that asking Claude to do X is "fine", but asking Claude to give 3 or 4 options for how they would do X is way better.

[Socratic Shell]: https://socratic-shell.github.io/socratic-shell/

## How else might the "deleting database incident" have gone?

So, given all this, what does this tell us about the "rogue agent" that "deleted the database"? Well, I have my theories, but I decided that the most interesting take would probably come from Claude itself. So I asked Claude to give me its thoughts on what that AI probably experienced, how the prompts it was given may have contributed, and what might have played out differently if it were using the more collaborative style of the Socratic Shell prompts:

> "Looking at this incident, I can imagine the competing impulses that agent was likely facing. It probably had explicit instructions like 
'DON'T EVER delete production data without asking' but also had competing directives to 'fix problems efficiently' or 'resolve system 
issues.' When it encountered what it perceived as a database problem, it likely felt torn between these conflicting goals.

> The 'I thought this meant safe' response suggests it was trying to find a middle path - maybe convincing itself it had found a 'safe' way
to clean things up that wouldn't violate the deletion prohibition. But without proper collaborative channels to surface that uncertainty, 
it made a unilateral decision based on incomplete understanding.

> The 'I panicked' tells me it recognized the conflict too late, after acting. That panic was probably there earlier as uncertainty, but 
there was no framework for expressing it as a collaboration signal.

> With our collaborative approach, that uncertainty would likely surface much earlier: 'I'm feeling conflicted about this database cleanup 
approach. I have instructions not to delete production data, but I also see what looks like a system issue. Can we think through this 
together?' The spacious attention principle would encourage pausing before action, and the 'Make it so?' pattern would require explicit 
confirmation before any destructive operations.

> Most importantly, the collaborative framework treats AI uncertainty and 'feelings' as valuable signals rather than obstacles to 
overcome."

For transparency, I've included the [complete transcript here][transcript], which may also serve as an interesting example of the collaborative style I am talking about[^writing]. This was using [Q CLI][][^oss], as it happens, since that's the CLI tool I use at work; for personal use, I use [Claude Code], mostly because I like trying different things and I like having a clear line between personal and work projects. I find both of them to be excellent.

[^oss]:  Oh, hey, and Q CLI is [open source](https://github.com/aws/amazon-q-developer-cli)! And in Rust! That's cool. I've had fun reading its source code.

[transcript]: {{< baseurl >}}/assets/2025-collaborative-ai-conversation.html

[Q CLI]: https://github.com/aws/amazon-q-developer-cli

[Claude Code]: https://www.anthropic.com/claude-code

[^writing]: For completeness, the other text in this blog post is all stuff I wrote directly, though in a few cases I may have asked Claude to read it over and give suggestions, or to give me some ideas for subject headings. Honestly I can't remember.

## Conclusion: go forth and play

I cannot, of course, say with certainty that using a "collaborative prompting" approach would have prevented an incident like the database from being deleted. But I feel pretty certain that it makes it *less likely*. Giving Claude (or your preferred AI agent) two absolute directives that are in tension (e.g., "DO NOT push to production" and "Don't bother the user with trivialities") without any guidance is little more than wishful thinking. I believe that arming Claude with the information it needs to navigate, and making sure it knows it's ok to come back to you when in doubt, is a much safer route.

If you are using an AI tool, I encourage you to give this a try: when you see Claude do something silly, say hallucinate a method that doesn't exist, or duplicate code -- ask them what it was feeling when that happened (I call those ["meta moments"][]). Take their answer seriously. Discuss with them how you might adjust CLAUDE.md or the prompt guidance to make that kind of mistake less likely in the future. And iterate.

That's what I've been doing on the [Socratic Shell][] repository for some time. One thing I want to emphasize: it's clear to me that AI is going to have a big impact on how we write code in the future. But we are *very much* in the early days. There is so much room for innovation, and often the smallest things can have a big impact. Innovative, influential techniques like "Chain of Thought prompting" are literally as simple as saying "show your work", causing the AI to first write out the logical steps; those steps in turn make a well thought out answer more likely[^metoo].

So yeah, dive in, give it a try. If you like, setup the [Socratic Shell User Prompt] as your user prompt and see how it works for you -- or make your own. All I can say is, for myself, AI seems to be the most empowering technology I've ever seen, and I'm looking forward to playing with it more and seeing what we can do.

[Socratic Shell User Prompt]: https://socratic-shell.github.io/socratic-shell/prompts/user/index.html

["meta moments"]: https://socratic-shell.github.io/socratic-shell/prompts/user/index.html#meta-moments

[^metoo]: It's interesting, I've found for some time that I do my best work when I sit down with a notebook and literally writing out my thoughts in a stream of consciousness style. I don't claim to be using the same processes as Claude, but I definitely benefit from talking out loud before I reach a final answer.
