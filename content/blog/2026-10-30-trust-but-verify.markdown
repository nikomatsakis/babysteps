---
title: "'Trust but verify'; or, 'the correctness ratchet'"
date: 2026-10-30T10:40:38+01:00
---

The name of the game in agentic development is figuring out how to clearly tell agents what you want-- and then how to be sure they follow through. Lately I've been tinkering with an interesting technique around this that I'd like to share.[^novel] I call it "trust but verify"[^reagan].

The basic idea is that sometimes you have things you want to "verify" but they can't really be *mechanistically* checked. In that case, you let your agent do its best. But you also have it create an *evidence* file that contains the *inputs* it drew on to make that decision along with its *rationale*. Then you gate your CI on checking that these evidence files exist and that the inputs are accurate. Those checks are deterministic and cheap. The *rationale* itself is natural language and can't be checked.

Doing this "trust but verify" technique on its own is helpful. It creates a kind of *hill-climbing towards correctness* that is stronger than (e.g.) tests alone. It helps to check meta-reasoning like "is the set of tests sufficient to show this requirement is true". Documenting the input also means that if any input should change, the CI check will start to fail, and the agent will be forced to revalidate its reasoning.

What I find *most* interesting though is that "trust but verify" can be used to create a kind of *correctness ratchet* over time. The idea is that, now that the inputs + rationale are documented, you can have other agents come back and double-check that reasoning, even when the inputs have not otherwise changed. As agents naturally improve, or just due to the randomness inherent in how agents work, they will naturally find things the original rationale overlooked, and you'll be able to address them.

[^novel]: I do not claim this technique is novel. I am quite sure people have been doing variants of it forever. But it's novel to me, and I don't think I've heard people talk about some of the potential long-term implications around "the correctness ratchet".

<!--more-->

## When you say "hill climbing towards correctness", what do you mean by "hill-climbing"?

Agents are none too smart, but they can be awfully dogged and persistent. If you ask them to climb a hill, they are going to find a way to do it. The tricky bit of course is that they don't always climb that hill [in the way you intended](https://en.wikipedia.org/wiki/OpenAI_rogue_agent_breach_of_Hugging_Face). Also, they may not exactly *climb* it so much as find a route to the top: they may be persistent, but they are also lazy <span style="white-space: nowrap">f!@#kers</span>[^cursing], and they love to take shortcuts.

## What if the *hills* are propositions about your program?

The fact that agents are good at climbing hills has got a lot of people in the automated reasoning community[^nai] very excited. After all, what better way could there be to make sure your program does what you expect than to formally prove that it is true? And we've seen that when you set a model loose with a Lean theorem, it can be quite adept at proving things[^bug]. 

[^nai]: *Automated reasoning* is the same thing as *formal methods*, just more appealingly branded. As an aside, lately I've been hearing people talk about *Neurosymbolic AI*, which I believe is a shameless (and brilliant) way for your SAT solver to jump on the LLM hype train. I suppose it's also a reasonable way to push back against "AI scope creep". While I'm on the topic: it seems to me that John McCarthy's quip ([*"as soon as it works, no one calls it AI anymore"*](https://quoteinvestigator.com/2024/06/20/not-ai/)) has been proven false. I would rather people stopped saying "AI" and just said "LLM", but nobody really cares what I want, do they?

[^bug]: [Even if they aren't actually true](https://leodemoura.github.io/blog/2026-8-1-postmortem-for-kernel-soundness-bug-14576/).

## But there are a few caveats...

Myself, I'm quite excited about tools like [Lean](https://lean-lang.org) but also [Verus](https://verus-lang.github.io/verus/guide/), [Aeneas](https://github.com/AeneasVerif/aeneas), and [Creusot](https://github.com/creusot-rs/creusot). I think we're going to be using them a lot more. And yet, I also think that proving propositions is not the end of the story.

### Who writes those propositions? 

Let's start with the obvious problem. **An agent may be good at *proving* a proposition, but who is actually *writing* it?** Even when something can be formalized, doing that formalization is a fair bit of work. Consider this random example of a requirement from a project I am working on[^write]:

> A Fleet using Functionality A must be attributed to every Functionality reachable through any number of recorded deprecation steps, while being counted only once when routes converge.

[^write]: I did not actually write this text, of course, an agent did. It's pretty convoluted. Sigh.

This is part of a project that is analyzing fleets across Amazon and looking at how much DRAM they consume. Our goal is to make sure that every large fleet at Amazon has Rust versions of every library it would need to be rewritten into Rust. We want to be able to go to the maintainers of those libraries and say, "there are fleets accounting for X% of Amazon's total DRAM consumption that use your library; you should make a Rust version".

The point is, while the *concept* of this DRAM accounting is not complex, formulating it in a precise, mathematical way is not at all trivial. You have to have some notion of transitive closure, talk about the graph of dependencies, etc. There is no way that the lazy, spoiled programmers of the future are going to write a formula like that by hand.

Much more likely is that they are going to give high-level direction to the agent and ask it to connect the dots. After all, this is what agents are good for! And in this case, I would trust an agent to get it right. As I said, it's not really *complex*, just... tedious.

### Can they say what you want?

And of course this leaves aside that there are many things that are just plain hard to formalize. Consider a requirement like, "a warning must be displayed on every relevant form in a prominent fashion". Checking this requirement requires a notion of what is "prominent", which is unlikely to be a mathematical property one can write down. And while I would not trust an agent's judgment over an actual graphic designer, it is also the kind of thing where the agent can likely do a "good enough" job to catch many failures.

### And what does it cost to do the proof?

The other point is that while agents are good at authoring proofs, it still takes them tokens -- and more importantly, *time* -- to do it. And sometimes quite a bit. If developers have to wait a while for the agent to find a proof to a complex property, that better be worth it. If the property you are proving is key to your system, it probably is. But if the cost of a mistake is less than the cost of a proof, people won't bother, so it's worth thinking about leaner, easier ways to gain confidence. 

### And what about when you are iterating?

One final point is that applying too much rigor too early in the process can be a real problem. This one is tricky because rigor can surface problems earlier, too. But it's often helpful to start by defining your requirements and things at a higher level and gradually get more precise as you go, tolerating a bit of "looseness" early on when you know there are details you have to nail down, but it's not important to do so *yet*.[^ratchet]

[^ratchet]: This feels reminiscent of [Terry Tao's classic post outlining how an experienced mathematician leans on instinct informed by rigor](https://terrytao.wordpress.com/career-advice/theres-more-to-mathematics-than-rigour-and-proofs/) rather than just one or just the other.

A key point for me is that just because you haven't formalized your requirement all the way to a mathematical proposition doesn't mean that you've got nothing at all. You can often phrase a high-level version of what you want, perhaps one that is overly simplified. In fact, it's pretty useful to do so, because when you find that your rule doesn't quite work, that helps you figure out how to refine it into the more precise rule you actually want.

## Evidence and "trust but verify"

The key idea of the "trust but verify" technique is that leaning on agentic reasoning is good, fine actually. **But when you do so, you should have the agent explain itself and also have it lay out what inputs and evidence it used to reach that conclusion.** Basically, leave yourself a trail so that you (or another agent...) can come back and audit what decisions were reached and on what basis.

Following this approach helps in two ways:

1. In the short term, it forces the agent to at least acknowledge your requirement, which generally means they will do a better job at meeting it.
2. In the long term, it lets you go back and double-check the agent's reasoning, leading to a kind of "correctness ratchet" in which you are generally improving the alignment of "what you have" with "what you asked for".

## One example: Habeas Codicem

Probably the simplest example of this "trust but verify" technique is [Habeas Codicem](https://github.com/nikomatsakis/habeas-codicem/). This is a small project I made in part as an experiment. The idea is that you write **requirements** into your docs and then Habeas Codicem adds a test into your system that can only be passed if an agent has written an explanation of why each of those requirements is satisfied. Those explanations are recorded as **evidence files** that are committed into your repository along with the code.

The interesting bit about Habeas Codicem is that the evidence files contain not only the agent's rationale and judgement, but also a list of the inputs it used to reach that conclusion. And these inputs have to have certain contents. For example, if you have a function that is labeled as part of the requirement's implementation, or a test that is tied to a requirement, then the agent must include that function or that test in its evidence.

The final part of Habeas is some skills that instruct the agent to always check with you, the human, before editing requirements, and to confirm agreement on requirements before implementing.

## Another example: an internal data store

Early in the post I mentioned an internal project I am working on at Amazon to analyze which missing dependencies might block fleets from migrating to Rust. This system involves a lot of agent-driven investigation. For example, perhaps there is a Rust version of a Java library, but it only handles *some* of the features (this is pretty common). Then we need to know whether the fleet's code cares about those features that aren't included.

My early attempts at gathering this data were pretty crude. I basically just sat there telling Amazon Quick "try harder, make no mistakes". Not great. I didn't really trust the result.

My newer attempts are much more thorough. I ask the agents to produce an evidence record of what data points they looked at and to include a written rationale for how those data points connect. I then test that the data points hold. For example, to determine if the method `convertData` in some library is called, the agent might register specific lines from `.java` files showing a call like `value.convertData()`. Or it might show the results from a grep that show no matches for `convertData`.

The interesting bit is that while the *rationale* from the agent can't really be evaluated in an automated fashion, the **evidence** can be. So before we accept any agent-created conclusion, we run a deterministic checker that ensures the evidence is valid (those lines really do appear where the agent said they would) and then records a **receipt** that the check was done. So the agent cannot just hallucinate evidence.

## What we are asserting: the agent has done work

Habeas Codicem does not prove your code obeys its requirements; nor does my inventory system prove that a given Java feature is used. But it **does** prove that the agent actually considered the question enough to write out some evidence + a justification. And assuming your agent is not actively malicious, that's actually quite a bit.

One thing that we've seen is that [agents often "lie" about what work they did](https://www.forbes.com/councils/forbestechcouncil/2026/09/11/ai-agents-will-take-shortcuts-the-solution-is-to-design-better-paths/). They'll claim to have carefully read through a document when an examination of their tool invocations shows that they've just looked at a few random bytes. 

## Tightening and revalidating rationale

One of the ideas I find most interesting in this space is the idea of *revalidating* rationale. Now that we have evidence files committed to git, we can absolutely have another adversarial agent that periodically pulls up those files and gives them another look. That agent can go looking for holes in the original logic and produce modified and improved proofs or counterexamples. I find this particularly compelling when you think about new and better models that might be more adept at finding holes.

## Applying this idea to propositions

I think this technique suggests how we can begin to tackle the problem of converting "high-level requirements" into formal theorems. Instead of expecting humans to write and review logical formulae, we can ask an agent to do the conversion -- and to record its thinking process (with verifiable evidence). Then we keep that evidence around and we periodically revisit it, looking for potential edge cases. We wind up with a kind of 'confidence score' -- the more reviews that have approved a given "requirement->formula" translation, the more likely it is to be accurate.

## The risk of ping-ponging and what it means

That said, I've not really put this into practice yet, and I anticipate it may be tricky to get it working right. People have told me to expect that agents may ping-pong a bit: for example, maybe one of them translates your plain English into logic, and then another says "that translation doesn't look right" and takes a new approach. But then yet another agent reverts that and goes back to the original. This seems very plausible-- I suspect it can be resolved by adding enough history to recognize that it actually reflects ambiguity in your original statement, and to surface the problem up to you.



[^cursing]: God, agents have gotten me so frustrated lately. I'm not usually prone to cursing when sober[^computers] but more than once lately I've found myself typing, *"I have no idea what the <span style="white-space: nowrap">f!#!</span> you are talking about"*. This seems to happen slightly more often with Claude than GPT. Claude really likes to develop a kind of [cryptophasic](https://en.wikipedia.org/wiki/Cryptophasia) shorthand where it drops random words that I used 3 weeks ago as if that will mean anything to me now. "You still have to handle the first-cut case!"

[^computers]: I had written, "I don't usually curse at computers", but my daughter (reading over my shoulder) told me, *"That is not true, you curse at computers all the time"*. And she's right! But I realized that it feels different. When I am using some restaurant website that seems purposefully designed not to tell me their opening hours or show me a menu, I certainly say *"oh <span style="white-space: nowrap">f!@#k</span> you!"*, but in that case, I am actually cursing at the person who designed that website. I am not cursing at *the website itself*; it's just an inert vessel. In contrast, when I curse at a model, I am not cursing at the people who trained it. I am cursing at the dang model, because it just seems to be going out of its way to be annoying. Anthropomorphizing is a pain.

[^reagan]: I know this phrase from Reagan, of course, but when I started reading into its background I found it had a more interesting history than I expected. Apparently it is a Russian proverb and was suggested to Reagan as a way to communicate with Gorbachev in familiar idioms. As with "less is more", it's always had that delightfully contradictory feeling ("if you have to verify, are you really trusting?") -- and at least the way I interpret it, it's really more like "trust through verification". In other words, I know I can trust you because we've set up the means for me to verify your logic.
