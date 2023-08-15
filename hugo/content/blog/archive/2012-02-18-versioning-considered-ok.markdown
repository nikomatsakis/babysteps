---
categories:
- Rust
comments: true
date: "2012-02-18T00:00:00Z"
slug: versioning-considered-ok
title: Versioning considered OK
---

Marijn pointed out to me that our current setup should avoid the worst
of the versioning problems I was afraid of.  In the snapshot, we
package up a copy of the compiler along with its associated libraries,
and use this compiler to produce the new compiler.  The new compiler
can then compilers its own target libraries, thus avoiding the need to
interact with libraries produced by the snapshot.

Of course, I should have known this, since I have relied on this so
that I can changed the metadata format without worrying about
backwards compatibility.  That's what I get for writing blog posts
late at night.

Anyhow, the good news is that we are able to serialize and deserialize
AST trees faithfully, and I have written (but not tested) the code to
serialize the side tables.  I am now working on the deserialization
code and the pass which will instantiate sources to be inlined.
