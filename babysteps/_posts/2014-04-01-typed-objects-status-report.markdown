---
layout: post
title: "Typed Objects Status Report"
date: 2014-04-01 15:20
comments: true
categories: [JS]
---

I recently wrote up a
[paper describing the current version of the Typed Objects API][paper]. Anyone
who is interested in the current state of the art in that
specification should take a look. It's not too long and intended to be
an easy read. This is just a draft copy, and feedback is naturally
very welcome -- in particular, I expect that before we submit it, the
implementation section will change, since it will be much further
along.

Dmitry and I have also been hard at work on the
[actual specification itself][spec] and naturally I've been working on
the implementation too. The most significant deviation between the
current implementation and the intended specification is described by
[Bug 973238][973238] -- basically the way we handle arrays is not
right. I'm about 16 patches into the process of fixing that: it
affects a lot of code and I'm trying to do it carefully. Overall,
though, the new model is making the code much cleaner, so I'm excited
about that.

I've also been working on an upcoming blog post describing an
extension to typed objects that supports *value types* -- that is,
immutable objects representing small, identity-less values like
colors, points, and so forth. That should be coming soon. It'll build
on the API described in the [draft paper][paper], so you might want to
read that first. ;)

[paper]: /pubs/2014.04.01-TypedObjects.pdf
[spec]: https://github.com/dslomov-chromium/typed-objects-es7
[973238]: https://bugzilla.mozilla.org/show_bug.cgi?id=973238
