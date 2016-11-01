---
layout: post
title: "Rust without implicit copies"
date: 2011-12-03 08:50
comments: true
categories: [Rust]
---

I just posted a draft of a [proposal for Rust that aims to eliminate
implicit copies][no-implicit-copies].  At the moment, it is not the
final version; there are some flaws I need to correct.  For one thing,
I need to address implicit capturing of variables by lambdas.

From the introduction:

> This is a proposal for Rust whose purpose is to **eliminate implicit
> copies of aggregate types,** while preserving most other aspects of
> the language.  Secondary goals include:
> 
> - permit references into arrays;
> - make destination passing style (DPS) a guaranteed optimization that
>   is obvious from language syntax;
> - support dynamically sized records.

[no-implicit-copies]: /rust/no-implicit-copies