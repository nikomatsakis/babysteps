---
title: "Rust turns 10"
date: 2025-05-15T17:46:56-04:00
---

Today is the [10th anniversary of Rust's 1.0 release](https://blog.rust-lang.org/2025/05/15/Rust-1.87.0/). Pretty wild. As part of RustWeek there was a fantastic celebration and I had the honor of giving some remarks, both as a long-time project member but also as representing Amazon as a sponsor. I decided to post those remarks here on the blog.

"It's really quite amazing to see how far Rust has come. If I can take a moment to put on my sponsor hat, [I've been at Amazon since 2021](http://localhost:1313/babysteps/blog/2020/12/30/the-more-things-change/) now and I have to say, it's been really cool to see the impact that Rust is having there up close and personal.

"At this point, if you use an AWS service, you are almost certainly using something built in Rust. And how many of you watch videos on PrimeVideo? [You're watching videos on a Rust client, compiled to WebAssembly, and shipped to your device.](https://www.youtube.com/watch?v=_wcOovoDFMI)

"And of course it's not just Amazon, it seems like all the time I'm finding out about this or that surprising place that Rust is being used. Just yesterday I really enjoyed hearing about how [Rust was being used to build out the software for tabulating votes in the Netherlands elections](https://rustweek.org/talks/mark/). Love it.

"On Tuesday, Matthias Endler and I did this live podcast recording. He asked me a question that has been rattling in my brain ever since, which was, 'What was it like to work with Graydon?'

"For those who don't know, Graydon Hoare is of course Rust's legendary founder. He was also the creator of [Monotone](https://en.wikipedia.org/wiki/Monotone_(software)), which, along with systems like Git and Mercurial, was one of the crop of distributed source control systems that flowered in the early 2000s. So defintely someone who has had an impact over the years.

"Anyway, I was thinking that, of all the things Graydon did, by far the most impactful one is that he articulated the right visions. And really, that's the most important thing you can ask of a leader, that they set the right north star. For Rust, of course, I mean first and foremost the goal of creating 'a systems programming language that won't eat your laundry'.

"The specifics of Rust have changed a LOT over the years, but the GOAL has stayed exactly the same. We wanted to replicate that productive, awesome feeling you get when using a language like Ocaml -- but be able to build things like web browsers and kernels. 'Yes, we can have nice things', is how I often think of it. I like that saying also because I think it captures something else about Rust, which is trying to defy the 'common wisdom' about what the tradeoffs have to be.

"But there's another North Star that I'm grateful to Graydon for. From the beginning, he recognized the importance of building the right culture around the language, one committed to 'providing a friendly, safe and welcoming environment for all, regardless of level of experience, gender identity and expression, disability, nationality, or other similar characteristic', one where being 'kind and courteous' was prioritized, and one that recognized 'there is seldom a right answer' -- that 'people have differences of opinion' and that 'every design or implementation choice carries a trade-off'.

"Some of you will probably have recognized that all of these phrases are taken straight from Rust's Code of Conduct which, to my knowledge, was written by Graydon. I've always liked it because it covers not only treating people in a respectful way -- something which really ought to be table stakes for any group, in my opinion -- but also things more specific to a software project, like the recognition of design trade-offs.

"Anyway, so thanks Graydon, for giving Rust a solid set of north stars to live up to. Not to mention for the `fn` keyword. Raise your glass!

"For myself, a big part of what drew me to Rust was the chance to work in a truly open-source fashion. I had done a bit of open source contribution -- I wrote an extension to the ASM bytecode library, I worked some on PyPy, a really cool Python compiler -- and I loved that feeling of collaboration. 

"I think at this point I've come to see both the pros and cons of open source -- and I can say for certain that Rust would never be the language it is if it had been built in a closed source fashion. Our North Star may not have changed but oh my gosh the path we took to get there has changed a LOT. So many of the great ideas in Rust came not from the core team but from users hitting limits, or from one-off suggestions on IRC or Discord or Zulip or whatever chat forum we were using at that particular time.

"I wanted to sit down and try to cite a bunch of examples of influential people but I quickly found the list was getting ridiculously long -- do we go all the way back, like the way Brian Anderson built out the `#[test]` infrastructure as a kind of quick hack, but one that lasts to this day? Do we cite folks like Sophia Turner and Esteban Kuber's work on error messages? Or do we look at the many people stretching the definition of what Rust is *today*... the reality is, once you start, you just can't stop.

"So instead I want to share what I consider to be an amusing story, one that is very Rust somehow. Some of you may have heard that in 2024 the ACM, the major academic organization for computer science, awarded their [SIGPLAN Software Award](https://www.sigplan.org/Awards/Software/) to Rust. A big honor, to be sure. But it caused us a bit of a problem -- what names should be on there? One of the organizers emailed me, Graydon, and a few other long-time contributors to ask us our opinion. And what do you think happened? Of course, we couldn't decide. We kept coming up with different sets of people, some of them absurdly large -- like thousands of names -- others absurdly short, like none at all. Eventually we kicked it over to the Rust Leadership Council to decide. Thankfully they came up with a decent list somehow.

"In any case, I just felt that was the most Rust of all problems: having great success but not being able to decide who should take credit. The reality is there is no perfect list -- every single person who got named on that award richly deserves it, but so do a bunch of people who aren't on the list. That's why the list ends with *All Rust Contributors, Past and Present* -- and so a big shout out to everyone involved, covering the compiler, the tooling, cargo, rustfmt, clippy, core libraries, and of course organizational work. On that note, hats off to Mara, Erik Jonkers, and the RustNL team that put on this great event. You all are what makes Rust what it is.

"Speaking for myself, I think Rust's penchant to re-imagine itself, while staying true to that original north star, is the thing I love the most. 'Stability without stagnation' is our most important value. The way I see it, as soon as a language stops evolving, it starts to die. Myself, I look forward to Rust getting to a ripe old age, interoperating with its newer siblings and its older aunts and uncles, part of the 'cool kids club' of widely used programming languages for years to come. And hey, maybe we'll be the cool older relative some day, the one who works in a bank but, when you talk to them, you find out they were a rock-and-roll star back in the day.

"But I get ahead of myself. Before Rust can get there, I still think we've some work to do. And on that note I want to say one other thing -- for those of us who work on Rust itself, we spend a lot of time looking at the things that are wrong -- the bugs that haven't been fixed, the parts of Rust that feel unergonomic and awkward, the RFC threads that seem to just keep going and going, whatever it is. Sometimes it feels like that's ALL Rust is -- a stream of problems and things not working right.

"I've found there's really only one antidote, which is getting out and talking to Rust users -- and conferences are one of the best ways to do that. That's when you realize that Rust really is something special. So I do want to take a moment to thank all of you Rust users who are here today. It's really awesome to see the things you all are building with Rust and to remember that, in the end, this is what it's all about: empowering people to build, and rebuild, the foundational software we use every day. Or just to 'hack without fear', as Felix Klock legendarily put it.

"So yeah, to hacking!"








