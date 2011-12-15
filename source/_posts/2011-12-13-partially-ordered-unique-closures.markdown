---
layout: post
title: "Partially ordered unique closures"
date: 2011-12-13 10:09
comments: true
categories: [Rust]
---

On a call with other Rust developers, I realized that I was thinking about
unique closures all wrong.  I had in mind a total ordering:

    fn[send] <: fn <: block
    
but of course this is not necessary.  What is desirable is a partial ordering:

    fn[send] <: block
    fn <: block
    
just as `~` and `@` pointers can both be aliased using a reference.
Ironically, this is precisely what I proposed in my list of possible
solutions, but I did so using region terminology.  Embarrassingly
obvious, in retrospect, particularly as that was Graydon's original
design I believe.  I think I got confused by the total ordering of
kinds into thinking that this should translate to a total ordering of
functions that close over data in those kinds.  Anyhow, I will now
work on implementing unique closures in this partially ordered way,
and hopefully things will go more smoothly!
