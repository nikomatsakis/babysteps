---
categories: []
comments: true
date: "2012-04-11T00:00:00Z"
slug: doa-dont-overabstract
title: 'DOA: Don''t overabstract'
---

I'd like to propose a term for code that has been "over-DRY'd"
(dessicated?).  I occasionally run across some method which just seems
*horribly complex*.  Reading it closer, it usually turns out that what
happened is that two or three independent operations got collected
into one subroutine.  Perhaps they started out as doing almost the
same thing---but before long, they diverged, and now the subroutine
has grown a hundred parameters and has a control-flow path that
requires a whiteboard and a ultra-super-fine-point marker to follow.
But, just as often, you can tear this routine apart into two or three
routines that read just fine, even if they share a line or two of code
in common.  So I'm going to start calling such routines "DOA", though
the acronym has a bit of a [different expansion][doa] when used as an
adjective.

[doa]: http://en.wikipedia.org/wiki/Dead_on_arrival
