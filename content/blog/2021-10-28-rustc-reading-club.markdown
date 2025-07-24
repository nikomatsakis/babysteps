---
layout: post
title: Rustc Reading Club
date: 2021-10-28T10:01:00-0400
---

Ever wanted to understand how rustc works? Me too! [Doc Jones] and I have been talking and we had an idea we wanted to try. Inspired by the very cool [Code Reading Club](https://code-reading.org/), we are launching an experimental [Rustc Reading Club](https://github.com/rust-lang/rustc-reading-club). Doc Jones posted an [announcement on her blog](https://mojosd.medium.com/rust-code-reading-club-8fe356287049?source=social.tw), so go take a look!

[Doc Jones]: https://github.com/doc-jones

The way this club works is pretty simple: every other week, we'll get together for 90 minutes and read some part of rustc (or some project related to rustc), and talk about it. Our goal is to walk away with a high-level understanding of how that code works. For more complex parts of the code, we may wind up spending multiple sessions on the same code.

We may yet tweak this, but the plan is to follow a "semi-structured" reading process:

* Identify the modules in the code and their purpose.
* Look at the type definitions and try to describe their high-level purpose.
* Identify the most important functions and their purpose.
* Dig into how a few of those functions are actually implemented.

The meetings will *not* be recorded, but they will be open to anyone. The first meeting of the Rustc Reading Club will be [November 4th, 2021 at 12:00pm US Eastern time][mtg]. Hope to see you there!

[mtg]: https://rust-lang/rustc-reading-club/meetings/2021-11-04.html