# Babysteps Blog

This is Niko Matsakis' technical blog "baby steps" where he posts various thoughts and ideas about Rust, programming language design, and software development.

## About the Blog

- **URL**: https://smallcultfollowing.com/babysteps/
- **Description**: This blog is where Niko posts up various half-baked ideas that he has
- **Built with**: Hugo static site generator
- **Key Topics**: Rust language design, async/await, traits, lifetimes, borrow checking, type systems, programming language theory
- **Started**: 2011

## Key Context

Niko is one of the lead designers of the Rust programming language and has been writing on this blog since 2011. The blog contains deep technical discussions about:
- Rust language features and design decisions
- Memory management and ownership
- Type inference and trait systems
- Async programming in Rust
- Developer tooling and ergonomics

## Working with the Blog

### Structure
- Blog posts are in `content/blog/` with date-prefixed filenames (e.g., `2024-03-04-borrow-checking-without-lifetimes.markdown`)
- Drafts go in `drafts/` directory
- Uses Markdown with Hugo frontmatter
- Images and assets go in `static/assets/`

### Important Conventions
- **Deployment**: Automatic via GitHub push
- **URLs**: Preserved by keeping filenames unchanged - NEVER change the date in a filename as it determines the URL
- **Cross-referencing**: Use the `{{< baseurl >}}` shortcode when linking to other posts on this blog
  - Use "out of line" link definitions for readability
  - In the text: `[link text][ref]`
  - Define links at the bottom of the paragraph where they're first used: `[ref]: {{< baseurl >}}/blog/YYYY/MM/DD/slug/`
  - Example: `[soul of Rust][sor]` with `[sor]: {{< baseurl >}}/blog/2022/09/18/dyn-async-traits-part-8-the-soul-of-rust/` after the paragraph
  - Avoid absolute URLs as they make local testing harder
- **Updates**: If updating an existing post, add an "Updated: YYYY-MM-DD" note but keep the original date

### Post Format Example
```markdown
---
title: "Your Title Here"
date: 2024-03-04T10:00:00-05:00
series:
- "Series Name Here"
- "Another Series If Applicable"
---

Post content here...
```

### Series
Posts can belong to one or more series using the `series:` frontmatter field. This helps connect related posts together. Common series include:
- "Dyn async traits" - exploring dynamic async traits
- "Polonius" - the new borrow checker formulation
- "Async interviews" - conversations about async Rust
- Posts can belong to multiple series simultaneously

### Writing Style
- Technical but accessible
- Often uses examples to illustrate concepts
- Includes code snippets to demonstrate ideas
- Personal and conversational tone while discussing complex topics
- Often explores "half-baked ideas" and thinking out loud
- Target audience: Rust developers (intermediate to expert), language designers, systems programmers

### When Helping with Blog Posts
- Maintain the existing conversational yet technical tone
- Use concrete examples to illustrate abstract concepts
- Feel free to include Rust code examples where relevant
- Blog posts often explore ideas in progress, not just finished thoughts
- For code blocks, use language tags: ```rust, ```bash, etc.