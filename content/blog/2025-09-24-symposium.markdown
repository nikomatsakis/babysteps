---
title: "Symposium: exploring new AI workflows"
date: 2025-09-24T16:39:46-04:00
---

<div style="overflow: auto;">
<img src="{{< baseurl >}}/assets/2025-09-24-symposium/logo-alcove.png" alt="Screenshot of the Symposium app" width="25%" style="float: left; margin-right: 15px; margin-bottom: 10px;"/>
  
This blog post gives you a tour of [Symposium][gh], a wild-and-crazy project that I've been obsessed with over the last month or so. Symposium combines an MCP server, a VSCode extension, an OS X Desktop App, and some [mindful prompts][mp] to forge new ways of working with agentic CLI tools.

</div>

Symposium is currently focused on my setup, which means it works best with VSCode, Claude, Mac OS X, and Rust. But it's meant to be unopinionated, which means it should be easy to extend to other environments (and in particular it already works great with other programming languages). The goal is not to compete with or replace those tools but to combine them together into something new and better.

In addition to giving you a tour of Symposium, this blog post is an invitation: [Symposium is an open-source project][gh], and I'm looking for people to explore with me! If you are excited about the idea of inventing new styles of AI collaboration, join the [symposium-dev Zulip][z]. Let's talk!

[gh]:  https://github.com/symposium-dev/symposium
[z]: https://symposium-dev.zulipchat.com
[mp]: https://github.com/symposium-dev/symposium/blob/main/symposium/mcp-server/src/guidance/main.md

<!--more-->

## Demo video

I'm not normally one to watch videos online. But in this particular case, I do think a movie is going to be worth 1,000,000 words. Therefore, I'm embedding a short video (6min) demonstrating how Symposium works below. Check it out! But don't worry, if videos aren't your thing, you can just read the rest of the post instead. 

{{< youtube gSGYYdrTFUk >}}

Alternatively, if you *really* love videos, you can watch the [first version I made, which went into more depth](https://youtu.be/HQcIp-IBj0Q). That version came in at 20 minutes, which I decided was...a bit much. 😁

[^hate]: I myself hate watching videos.

## Taskspaces let you juggle concurrent agents

The Symposium story begins with `Symposium.app`, an OS X desktop application for managing *taskspaces*. A taskspace is a clone of your project[^worktree] paired with an agentic CLI tool that is assigned to complete some task.

[^worktree]: Technically, a git worktree.

My observation has been that most people doing AI development spend a lot of time waiting while the agent does its thing. Taskspaces let you switch quickly back and forth.

Before I was using taskspaces, I was doing this by jumping between different projects. I found that was really hurting my brain from context switching. But jumping between *tasks* in a project is much easier. I find it works best to pair a complex topic with some simple refactorings.

Here is what it looks like to use Symposium:

<img src="{{< baseurl >}}/assets/2025-09-24-symposium/taskspaces.png" alt="Screenshot of the Symposium app" width="100%"/>

Each of those boxes is a taskspace. It has both its own isolated directory on the disk and an associated VSCode window. When you click on the taskspace, the app brings that window to the front. It can also hide other windows by positioning them exactly behind the first one in a stack[^stacked]. So it's kind of like a mini window manager.

[^stacked]: That's what the "Stacked" box does; if you uncheck it, the windows can be positioned however you like. I'm also working on a tiled layout mode.

Within each VSCode window, there is a terminal running an agentic CLI tool that has the Symposium [MCP server](https://modelcontextprotocol.io/docs/getting-started/intro). If you're not familiar with MCP, it's a way for an LLM to invoke custom tools; it basically just gives the agent a list of available tools and a JSON scheme for what arguments they expect.

The Symposium MCP server does a bunch of things--we'll talk about more of them later--but one of them is that it lets the agent interact with taskspaces. The agent can use the MCP server to post logs and signal progress (you can see the logs in that screenshot); it can also spawn new taskspaces. I find that last part very handy.

It often happens to me that while working on one idea, I find opportunities for cleanups or refactorings. Nowadays I just spawn out a taskspace with a quick description of the work to be done. Next time I'm bored, I can switch over and pick that up.

## An aside: the Symposium app is written in Swift, a language I did not know 3 weeks ago

It's probably worth mentioning that the Symposium app is written in Swift. I did not know Swift three weeks ago. But I've now written about 6K lines and counting. I feel like I've got a pretty good handle on how it works.[^threadsafe]

Well, it'd be more accurate to say that I have *reviewed* about 6K lines, since most of the time Claude generates the code. I mostly read it and offer suggestions for improvement[^DRY]. When I do dive in and edit the code myself, it's interesting because I find I don't have the muscle memory for the syntax. I think this is pretty good evidence for the fact that agentic tools help you get started in a new programming language.

[^threadsafe]: Well, mostly. I still have some warnings about something or other not being threadsafe that I've been ignoring. Claude assures me they are not a big deal (Claude can be so lazy omg).

[^DRY]: Mostly: "Claude will you please for the love of God stop copying every function ten times."

## Walkthroughs let AIs explain code to you

So, while taskspaces let you jump between tasks, the rest of Symposium is dedicated to helping you complete an individual task. A big part of that is trying to go beyond the limits of the CLI interface by connecting the agent up to the IDE. For example, the Symposium MCP server has a tool called `present_walkthrough` which lets the agent present you with a markdown document that explains how some code works. These walkthroughs show up in a side panel in VSCode:

<img src="{{< baseurl >}}/assets/2025-09-24-symposium/walkthrough.png" alt="Walkthrough screenshot" width="100%"/>

As you can see, the walkthroughs can embed mermaid, which is pretty cool. It's sometimes so clarifying to see a flowchart or a sequence diagram.

Walkthroughs can also embed *comments*, which are anchored to particular parts of the code. You can see one of those in the screenshot too, on the right.

Each comment has a Reply button that lets you respond to the comment with further questions or suggest changes; you can also select random bits of text and use the "code action" called "Discuss in Symposium". Both of these take you back to the terminal where your agent is running. They embed a little bit of XML (`<symposium-ref id="..."/>`) and then you can just type as normal. The agent can then use another MCP tool to expand that reference to figure out what you are referring to or what you are replying to.

To some extent, this "reference the thing I've selected" functionality is "table stakes", since Claude Code already does it. But Symposium's version works anywhere (Q CLI doesn't have that functionality, for example) and, more importantly, it lets you embed multiple refrences at once. I've found that to be really useful. Sometimes I'll wind up with a message that is replying to one comment while referencing two or three other things, and the `<symposium-ref/>` system lets me do that no problem.

## Integrating with IDE knowledge

Symposium also includes an `ide-operations` tool that lets the agent connect to the IDE to do things like "find definitions" or "find references". To be honest I haven't noticed this being that important (Claude is surprisingly handy with awk/sed) but I also haven't done much tinkering with it. I know there are other MCP servers out there too, like [Serena](https://github.com/oraios/serena), so maybe the right answer is just to import one of those, but I think there's a lot of interesting stuff we *could* do here by integrating deeper knowledge of the code, so I have been trying to keep it "in house" for now.

## Leveraging Rust conventions

Continuing our journey down the stack, let's look at one more bit of functionality, which are MCP tools aimed at making agents better at working with Rust code. By far the most effective of these so far is one I call [`get_rust_crate_source`][]. It is very simple: given the name of a crate, it just checks out the code into a temporary directory for the agent to use. Well, actually, it does a *bit* more than that. If the agent supplies a search string, it also searches for that string so as to give the agent a "head start" in finding the relevant code, and it makes a point to highlight code in the examples directory in particular. 

[`get_rust_crate_source`]: https://symposium-dev.github.io/symposium/design/mcp-tools/rust-development.html#get_rust_crate_source

## We could do a lot more with Rust...

My experience has been that this tool makes all the difference. Without it, Claude just geneates plausible-looking APIs that don't really exist. With it, Claude generally figures out exactly what to do. But really it's just scratching the surface of what we can do. I am excited to go deeper here now that the basic structure of Symposium is in place -- for example, I'd love to develop Rust-specific code reviewers that can critique the agent's code or offer it architectural advice[^mutex], or a tool like [CWhy](https://github.com/plasma-umass/CWhy) to help people resolve Rust trait errors or macro problems.

[^mutex]: E.g., don't use a tokio mutex you fool, [use an actor](https://ryhl.io/blog/actors-with-tokio/). That is one particular bit of advice I've given more than once.

## ...and can we decentralize it?

But honestly what I'm *most* excited about is the idea of **decentralizing**. I want Rust library authors to have a standard way to attach custom guidance and instructions that will help agents use their library. I want an AI-enhanced variant of `cargo upgrade` that automatically bridges over major versions, making use of crate-supplied metadata about what changed and what rewrites are needed. Heck, I want libraries to be able to ship with MCP servers implemented in WASM ([Wassette], anyone?) so that Rust developers using that library can get custom commands and tools for working with it. I don't 100% know what this looks like but I'm keen to explore it. If there's one thing I've learned from Rust, it's always bet on the ecosystem.

[Wassette]: https://opensource.microsoft.com/blog/2025/08/06/introducing-wassette-webassembly-based-tools-for-ai-agents/

## Looking further afield, can we use agents to help humans collaborate better?

One of the things I am very curious to explore is how we can use agents to help humans collaborate better. It's oft observed that coding with agents can be a bit lonely[^Claude]. But I've also noticed that structuring a project for AI consumption requires relatively decent documentation. For example, one of the things I did recently for Symposium was to create a Request for Dialogue (RFD) process -- a simplified version of Rust's RFC process. My motivation was partly in anticipation of trying to grow a community of contributors, but it was also because most every major refactoring or feature work I do begins with iterating on docs. The doc becomes a central tracking record so that I can clear the context and rest assured that I can pick up where I left off. But a nice side-effect is that the project has more docs than you might expect, considering, and I hope that will make it easier to dive in and get acquainted.

[^Claude]: I'm kind of embarassed to admit that Claude's dad jokes have managed to get a laugh out of me on occassion, though.

And what about other things? Like, I think that taskspaces should really be associated with github issues. If we did that, could we do a better job at helping new contributors pick up an issue? Or at providing mentoring instructions to get started? 

What about memory? I really want to add in some kind of automated memory system that accumulates knowledge about the system more automatically. But could we then share that knowledge (or a subset of it) across users, so that when I go to hack on a project, I am able to "bootstrap" with the accumulated observations of other people who've been working on it?

Can agents help in guiding and shepherding design conversations? At work, when I'm circulating a document, I will typically download a copy of that document with people's comments embedded in it. Then I'll use pandoc to convert that into Markdown with HTML comments and then ask Claude to read it over and help me work through the comments systematically. Could we do similar things to manage unwieldy RFC threads?

This is part of what gets me excited about AI. I mean, don't get me wrong. I'm scared too. There's no question that the spread of AI will change a lot of things in our society, and definitely not always for the better. But it's also a huge opportunity. AI is empowering! Suddenly, learning new things is just *vastly* easier. And when you think about the potential for integrating AI into community processes, I think that it could easily be used to bring us closer together and maybe even to make progress on previously intractable problems in open-source[^burnout].

[^burnout]: Narrator voice: *burnout. he means maintainer burnout.*

## Conclusion: Want to build something cool?

As I said in the beginning, this post is two things. Firstly, it's an advertisement for Symposium. If you think the stuff I described sounds cool, give Symposium a try! You can find [installation instructions](https://symposium-dev.github.io/symposium/install.html) here. I gotta warn you, as of this writing, I think I'm the only user, so I would not at all be surprised to find out that there's bugs in setup scripts etc. But hey, try it out, find bugs and tell me about them! Or better yet, fix them!

[^90s]: Tell me you went to high school in the 90s without telling me you went to high school in the 90s.

But secondly, and more importantly, this blog post is an invitation to come out and play[^90s]. I'm keen to have more people come and hack on Symposium. There's so much we could do! I've identified a number of ["good first issue" bugs](). Or, if you're keen to take on a larger project, I've got a set of invited "Request for Dialogue" projects you could pick up and make your own. And if none of that suits your fancy, feel free to pitch you own project -- just join the [Zulip][z] and open a topic!


