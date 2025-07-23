# Idea-oriented programming: We are all mentors now

Having been working extensively with Claude Code, Q CLI, and other similar tools, I've come to 

I've been working with AI assistants for months now, building tools for better AI collaboration through my Socratic Shell project. What I've learned is that we're moving toward something I call "idea-oriented programming" - starting with rough concepts and refining them through AI collaboration, rather than jumping straight to implementation details.

This enables what I think of as T-shaped development: going deep on the high-value human work (architecture, review, business logic) while letting AI handle the complexity of translation to specific languages and platforms. You focus on what the code should accomplish; the AI figures out how to make it happen.

This isn't the same as "English is the new programming language." English isn't necessarily optimal - what's powerful is being able to start sloppy and get more precise over time, working at a conceptual level while AI handles the grunt work.

## AI assistants are contributors, not servants or oracles

Through building collaborative AI tools, I've observed something crucial: AI assistants operate much like human contributors. They don't have some magical universal view of your codebase. They need good error messages to learn from mistakes. They struggle with the same action-at-a-distance problems that trip up human developers.

This reframes everything. The AI isn't an omniscient code generator - it's more like a capable but junior contributor who needs mentoring. And you? You're the reviewer, the mentor, the one who shapes the architecture and catches the subtle bugs.

The tensions here are familiar from open source development. Just like reviewing patches from contributors, you need to be able to quickly understand what the AI produced, spot potential issues, and guide it toward better solutions.

## Optimizing for "humans as mentors"

If we're all mentors now, programming languages need to make mentoring effective. Here's what matters:

### Reviewability, locality of reasoning

You need to trust what you're reading. Code shouldn't have surprise interactions with distant parts of the system, and when interactions exist, they should be easy to trace.

This is why memory safety becomes table stakes - not as a separate concern, but as part of locality. Languages like C/C++ force you to spend cognitive energy on memory management instead of focusing on logic and architecture. When you're reviewing AI-generated code, you want to think about whether the approach is right, not whether it remembered to free memory.

Rust's `unsafe` keyword is a perfect example of language design for reviewers. It doesn't prevent unsafe code - it signals when a section deserves extra scrutiny. That's exactly what you need when mentoring AI contributors.

### Accessibility for AIs

Strong error messages become crucial because they're how you guide your AI contributor toward better solutions. We can now measure what was always qualitative: how many error messages actually help vs. send the AI into loops?

This accessibility often correlates with human accessibility - clear interfaces and explicit behavior help both AI and human contributors. But not always. AIs might benefit from structured type information that humans find verbose.

### Portability without platform expertise

In idea-oriented programming, you want to deploy the same logic across mobile, web, server, and serverless without becoming an expert in each platform's quirks. AI can handle the platform-specific details while you focus on the core concepts.

### Efficiency because cloud costs are real

Every extra CPU cycle and MB of memory costs money at scale. Languages that compile to efficient targets become more valuable when you're optimizing for different things during development (rapid iteration) vs. production (performance).

## We are all mentors now

The future of programming isn't about AI replacing developers. It's about elevating the role from code writer to code mentor - focusing on architecture, review, and guiding AI contributors toward solutions that actually solve the right problems.

The languages that thrive will be the ones that make this mentoring relationship effective: reviewable, accessible to AI, portable across platforms, and efficient in production.

Programming is becoming more human, not less.
