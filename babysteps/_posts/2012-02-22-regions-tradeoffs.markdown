---
layout: post
title: "Regions tradeoffs"
date: 2012-02-22 17:35
comments: true
categories: [Rust]
---

In the last few posts I've been discussing various options for
regions.  I've come to see region support as a kind of continuum,
where the current system of reference modes lies at one end and a
full-blown region system with explicit parameterized types and
user-defined memory pools lies at the other.  In between there are
various options.  To better explore these tradeoffs, I wrote up a
document that
[outlines various possible schemes and also details use cases that are enabled by these schemes][doc].
I don't claim this to be a comprehensive list of all possible schemes,
just the ones I've thought about so far.  In some cases, the
descriptions are quite hand-wavy.  I also think some of them don't
hang together so well.

[doc]: /rust/regions-tradeoffs
