---
title: "Fun With Dada"
date: 2026-02-08T21:20:47-05:00
series:
- "Dada"
---

<img src="{{< baseurl >}}/assets/2026-fun-with-dada/dada-logo.svg" width="20%" style="float: right; margin-right: 1em; margin-bottom: 0.5em;" />

Waaaaaay back in 2021, I started experimenting with a new programming language I call ["Dada"](https://dada-lang.org). I've been tinkering with it ever since and I just realized that (oh my gosh!) I've never written even a single blog post about it! I figured I should fix that. This post will introduce some of the basic concepts of Dada as it is now.

Before you get any ideas, Dada isn't fit for use. In fact the compiler doesn't even really work because I keep changing the language before I get it all the way working. Honestly, Dada is more of a "stress relief" valve for me than anything else[^relax] -- it's fun to tinker with a programming language where I don't have to worry about backwards compatibility, or RFCs, or anything else.

[^relax]: Yes, I relax by designing new programming languages. Doesn't everyone?

That said, Dada has been a very fertile source of ideas that I think could very well be applicable to Rust. And not just for language design: playing with the compiler is also what led to the [new `salsa` design](https://smallcultfollowing.com/babysteps/blog/2022/08/18/come-contribute-to-salsa-2022/)[^yakshave], which is now used by both rust-analyzer and [Astral's ty](https://github.com/astral-sh/ty). So I really want to get those ideas out there!

[^yakshave]: Designing a new version of [`salsa`](https://salsa-rs.github.io/salsa/) so that I could write the Dada compiler in the way I wanted really was an epic yak shave, now that I think about it.

<!--more-->

## I took a break, but I'm back baby!

I stopped hacking on Dada about a year ago[^LLM], but over the last few days I've started working on it again. And I realized, hey, this is a perfect time to start blogging! After all, I have to rediscover what I was doing anyway, and writing about things is always the best way to work out the details.

[^LLM]: I lost motivation as I got [interested in LLMs](https://smallcultfollowing.com/babysteps/blog/2025/02/10/love-the-llm/). To be frank, I felt like I had to learn enough about them to understand if designing a programming language was "fighting the last war". Having messed a bunch with LLMs, I definitely feel that they [make the choice of programming language less relevant](https://smallcultfollowing.com/babysteps/blog/2025/07/31/rs-py-ts-trifecta/). But I also think they really benefit from higher-level abstractions, even more than humans do, and so I like to think that Dada could still be useful. Besides, it's fun.

## Dada started as a gradual programming experiment, but no longer

Dada has gone through many phases. Early on, the goal was to build a *gradually typed* programming language that I thought would be easier for people to learn.

The idea was that you could start writing without any types at all and just execute the program. There was an interactive playground that would let you step through and visualize the "borrow checker" state (what Dada calls permissions) as you go. My hope was that people would find that easier to learn than working with type checker checker.

I got this working and it was actually pretty cool. [I gave a talk about it at the Programming Language Mentoring Workshop in 2022](https://www.youtube.com/watch?v=tdg03gEbyS8), though skimming that video it doesn't seem like I really demo'd the permission modeling. Too bad. 

At the same time, I found myself unconvinced that the gradually typed approach made sense. What I wanted was that when you executed the program without type annotations, you would stil get errors at the point where you violated a borrow. And that meant that the program had to track a lot of extra data, kind of like miri does, and it was really only practical as a teaching tool. I still would like to explore that, but it also felt like it was adding a lot of complexity to the language design for something that would only be of interest very early in a developer's journey[^LLM2].

[^LLM2]: And, with LLMs, that period of learning is shorter than ever.

Therefore, I decided to start over, this time, to just focus on the static type checking part of Dada.

## Dada is like a streamlined Rust

Dada today is like Rust but *streamlined*. The goal is that Dada has the same basic "ownership-oriented" *feel* of Rust, but with a lot fewer choices and nitty-gritty details you have to deal with.

Rust often has types that are semantically equivalent, but different in representation. Consider `&Option<String>` vs `Option<&String>`: both of them are equivalent in terms of what you can do with them, but of course Rust makes you carefully distinguish between them. In Dada, they are the same type. Dada also makes `&Vec<String>`, `&Vec<&String>`, `&[String]`, `&[&str]`, and many other variations all the same type too. And before you ask, it does it without heap allocating everything or using a garbage collector.

To put it pithily, Dada aims to be **"Rust where you never have to call `as_ref()`".**

## Dada has a fancier borrow checker

Dada also has a fancier borrow checker, one which already demonstrates much of [the borrow checker within](https://smallcultfollowing.com/babysteps/blog/2024/06/02/the-borrow-checker-within/), although it doesn't have view types. Dada's borrow checker supports [internal borrows](https://smallcultfollowing.com/babysteps/blog/2024/06/02/the-borrow-checker-within/#step-4-internal-references) (e.g., you can make a struct that has fields that borrow from other fields) and it supports [borrow checking without lifetimes](https://smallcultfollowing.com/babysteps/blog/2024/03/04/borrow-checking-without-lifetimes/). Much of this stuff can be brought to Rust, although I did tweak a few things in Dada that made some aspects easier.

## Dada targets WebAssembly natively

Somewhere along the line in refocusing Dada, I decided to focus exclusively on building WebAssembly components. Initially I felt like targeting WebAssembly would be really convenient:

* WebAssembly is like a really simple and clean assembly language, so writing the compiler backend is easy.
* WebAssembly components are explicitly designed to bridge between languages, so they solve the FFI problem for you.
* With WASI, you even get a full featured standard library that includes high-level things like "fetch a web page". So you can build useful things right off the bat.

## WebAssembly and on-demand compilation = compile-time reflection almost for free

But I came to realize that targeting WebAssembly has another advantage: **it makes compile-time reflection almost trivial**. The Dada compiler is structured in a purely on-demand fashion. This means we can compile one function all the way to WebAssembly bytecode and leave the rest of the crate untouched.

And once we have the WebAssembly bytecode, we can run that from inside the compiler! With wasmtime, we have a high quality JIT that runs very fast. The code is even sandboxed!

So we can have a function that we compile and run during execution and use to produce other code that will be used by other parts of the compilation step. In other words, we get something like miri or Zig's comptime for free, essentially. Woah.

## Wish you could try it? Me too!

Man, writing this blog post made ME excited to play with Dada. Too bad it doesn't actually work. Ha! But I plan to keep plugging away on the compiler and get it to the point of a live demo as soon as I can. Hard to say exactly how long that will take.

In the meantime, to help me rediscover how things work, I'm going to try to write up a series of blog posts about the type system, borrow checker, and the compiler architecture, all of which I think are pretty interesting.