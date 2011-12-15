---
layout: post
title: "Dynamic race detection"
date: 2011-12-14 15:25
comments: true
categories: [PL]
published: false
---

This is not a technique that would fly for Rust, but I was just discussing with 
[Terence Parr][tp] about the design of parallel languages, and we 
touched on an idea that's been rattling around in my brain for a while. 
[Christoph][ca] and I used to talk about something similar back in the old ETH days.
The idea is for a lightweight language facility for detecting race conditions dynamically
in a language that has scoped, hierarchical parallelism.  


[tp]: http://www.cs.usfca.edu/~parrt/
[ca]: http://people.inf.ethz.ch/angererc/