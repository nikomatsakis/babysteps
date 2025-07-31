---
title: "Rust, Python, and TypeScript: the new trifecta"
date: 2025-07-31T09:52:16-04:00
---

You heard it here first: my guess is that Rust, Python, and TypeScript are going to become the dominant languages going forward (excluding the mobile market, which has extra wrinkles). The argument is simple. Increasing use of AI coding is going to weaken people's loyalty to programming languages, moving it from what is often a tribal decision to one based on fundamentals. And the fundamentals for those 3 languages look pretty strong to me: Rust targets system software or places where efficiency is paramount. Python brings a powerful ecosystem of mathematical and numerical libraries to bear and lends itself well to experimentation and prototyping. And TypeScript of course runs natively on browsers and the web and a number of other areas. And all of them, at least if setup properly, offer strong static typing and the easy use of dependencies. Let's walk through the argument point by point.

## AI is moving us towards *idea-oriented programming*

Building with an LLM is presently a rather uneven experience, but I think the long-term trend is clear enough. We are seeing a shift towards a new programming paradigm. Dave Herman and I have recently taken to calling it **idea-oriented programming**. As the name suggests, *idea-oriented programming* is *programming where you are focused first and foremost on **ideas** behind your project*.

Why do I say *idea-oriented programming* and not *vibe coding*? To me, they are different beasts. Vibe coding suggests a kind of breezy indifference to the specifics -- kind of waving your hand vaguely at the AI and saying "do something like this".
That smacks of [treating the AI genie](https://smallcultfollowing.com/babysteps/blog/2025/07/24/collaborative-ai-prompting/) -- or perhaps a servant, neither of which I think is useful.

## Idea-oriented programming is very much **programming**

Idea-oriented programming, in contrast, is definitely **programming**. But your role is different. As the programmer, you're more like the chief architect. Your coding tools are like your apprentices. You are thinking about the goals and the key aspects of the design. You lay out a crisp plan and delegate the heavy lifting to the tools -- and then you review their output, making tweaks and, importantly, generalizing those tweaks into persistent principles. When some part of the problem gets tricky, you are rolling up your sleeves and do some hands-on debugging and problem solving.

If you've been in the industry a while, this description wil lbe familiar. It's essentially the role of a Principal Engineer. It's also a solid description of what I think an open-source mentor ought to do.

## Idea-oriented programming changes the priorities for language choice

In the past, when I built software projects, I would default to Rust. It's not that Rust is the best choice for everything. It's that I know Rust best, and so I move the fastest when I use it. I would only adopt a different language if it offered a compelling advantage (or of course if I just wanted to try a new language, which I do enjoy).

But when I'm buiding things with an AI assistant, I've found I think differently. I'm thinking more about what libraries are available, what my fundamental performance needs are, and what platforms I expect to integrate with. I want things to be as straightforward and high-level as I can get them, because that will give the AI the best chance of success and minimize my need to dig in. The result is that I wind up with a mix of Python (when I want access to machine-learning libraries), TypeScript (when I'm building a web app, VSCode Extension, or something else where the native APIs are in TypeScript), and Rust otherwise.

Why Rust as the default? Well, I like it of course, but more importantly I know that its type system will catch errors up front and I know that its overall design will result in performant code that uses relatively little memory. If I am then going to run that code in the cloud, that will lower my costs, and if I'm running it on my desktop, it'll give more RAM for Microsoft Outlook to consume.[^kid]

[^kid]: Amazon is migrating to M365, but at the moment, I still receive my email via a rather antiquated Exchange server. I count it a good day if the mail is able to refresh at least once that day, usually it just stalls out.

## Type systems are hugely important for idea-oriented programming

LLMs kind of turn the tables on what we expect from a computer. Typical computers can cross-reference vast amounts of information and perform deterministic computations lightning fast, but falter with even a whiff of ambiguity. LLMs, in contrast, can be surprisingly creative and thoughtful, but they have limited awareness of things that are not right in front of their face, unless they correspond to some pattern that is ingrained from training. They're a lot more like humans that way. And the technologies we have for dealing with that, like RAG or memory MCP servers, are mostly about trying to put things in front of their face that they might find useful.

But of course programmers have evolved a way to cope with human's narrow focus: type systems, and particularly advanced type systems. Basic type systems catch small mistakes, like arguments of the wrong type. But more advanced type systems, like the ones in Rust and TypeScript, also capture domain knowledge and steer you down a path of success: using a Rust enum, for example, captures both which state your program is in and the data that is relevant to that state. This means that you can't accidentally read a field that isn't relevant at the moment. This is important for you, but it's even more important for your AI collaborator(s), because they don't have the comprehensive memory that you do, and are quite unlikely to remember those kind of things.

Notably, Rust, TypeScript, and Python all have pretty decent type systems. For Python you have to set things up to use mypy and pydantic.

## Ecosystems and package managers are mmore important than ever

Ecosystems and package managers are also hugely important to idea-oriented programming. Of course, having a powerful library to build on has always been an accellerator, but it also used to come with a bigger downside, because you had to take the time to get fluent in how the library works. That is much less of an issue now. For example, I have been building a [family tree application](https://github.com/nikomatsakis/www.family-tree/)[^mbfgw] to use with my family. I wanted to add graphical rendering. I talked out the high-level ideas but I was able to lean on Claude to manage the use of the d3 library -- it turned out beautifully!

[^mbfgw]: My family bears a striking resemblance to the family in My Big Fat Greek Wedding. There are many relatives that I consider myself very close to and yet have basically no idea how we are *actually* related (well, I didn't, until I setup my family tree app).

Notably, Rust, TypeScript, and Python all have pretty decent type systems. For Python you have to set things up to use `uv` (at least, that's what I've been using).

## Syntactic papercuts and non-obvious workarounds matter less, but error messages and accurate guidance are still important

In 2016, Aaron Turon and I gave a [RustConf keynote][2016] advocating for the [Ergonomics Initiative][EI]. Our basic point was that there were (and are) a lot of errors in Rust that are simple to solve -- but only if you know the trick. If you don't know the trick, they can be complete blockers, and can lead you to abandon the language altogether, even if the answer to your problem was just add a `*` in the right place.

[EI]: https://blog.rust-lang.org/2017/03/02/lang-ergonomics/
[2016]:https://www.youtube.com/watch?v=pTQxHIzGqFI

In Rust, we've put a lot of effort into addressing those, either by changing the language or, more often, by changing our error messages to guide you to success. What I've observed is that, with Claude, the calculus is different. Some of these mistakes it simply never makes. But others it makes but then, based on the error message, is able to quickly corret. And this is fine. If I were writing the code by hand, I get annoyed having to apply the same repetitive changes over and over again (add `mut`, ok, no, take it away, etc etc). But if Claude is doing, I don't care so much, and maybe I get some added benefit -- e.g., now I have a clearer indicating of which variables are declared as `mut`.

But all of this only works if Claude *can* fix the problems -- either because it knows from training or because the errors are good enough to guide it to success. One thing I'm very interested in, though, is that I think we now have more room to give ambiguous guidance (e.g., here are 3 possible fixes, but you have to decide which is best), and have the LLM navigate it.

## Bottom line: LLMs makes powerful tools more accessible

The bottom line is that what enables ideas-oriented programming isn't anything fundamentally *new*. But previously to work this way you had to be a Principal Engineer at a big company. In that case, you could let junior engineers sweat it out, reading the docs, navigating the error messages. Now the affordances are all different, and that style of work is much more accessible.

Of course, this does raise some questions. Part of what makes a PE a PE is that they have a wealth of experience to draw on. Can a young engineer do that same style of work? I think yes, but it's going to take some time to find the best way to teach people that kind of judgment. It was never possible before because the tools weren't there.

It's also true that this style of working means you spend less time in that "flow state" of writing code and fitting the pieces together. Some have said this makes coding "boring". I don't find that to be true. I find that I can have a very similar -- maybe even better -- experience by brainstorming and designing with Claude, writing out my plans and RFCs. A lot of the tedium of that kind of ideation is removed since Claude can write up the details, and I can focus on how the big pieces fit together. But this too is going to be an area we explore more over time.