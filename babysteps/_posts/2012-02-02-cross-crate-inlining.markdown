---
layout: post
title: "Cross-crate inlining"
date: 2012-02-02 08:41
comments: true
categories: [Rust]
---

Cross-crate inlining (CCI) refers to the ability to inline a function
across crate boundaries.  In Rust, a "crate" is the unit of
compilation, rather than an individual file as in C or C++.  A crate
basically corresponds to a single library or executable, but it may
contain any number of modules and source files internally.  CCI is
important for performance due to the ubiquitous use of small methods
like `vec::iter()` in our source code.  Such methods have proven to be
a very scalable way to define iteration abstracts, but performance is
currently somewhat lacking.

The major language-level issue associated with CCI is that it
interferes with separate compilation.  I won't talk about this at the
moment; we may choose to only inline when statically linking, or to
give users some way to distinguish what can be inlined and what must
not be, etc.

What I do want to look at is the best way to *implement* CCI in our
compiler.  Right now the compiler is focused on compiling one crate at
a time and so a few things will have to change.

pcwalton forwarded me a partial patch which tries to separate out
various parts of the compiler to generalize to multiple crates.  I am
not sure, though, that this is worth the effort: after all, we are
still compiling one *main* crate, we're just borrowing code from other
crates.  Furthermore, we never intend to report errors on the imported
crates: they have typechecked etc, so nothing should go wrong.  The
only reason that we will need to know about them at all is for line
number reporting within the compiler.  Therefore, I am leaning now
towards keeping things mostly the same, but adding files from inlined
crates into the existing `codemap` structure where necessary.

Another question is how to make the AST available within a compiled
crate; the inliner will need to reference it to produce an inlined
version, after all.  There are a couple of dimensions here.  The first
is how to serialize the AST at all---the easiest way is to use the
Rust pretty printer.  The best way, I think, is to write the tree out
in EBML.  The reason for this is that it allows to retain the spans
from the original source, which will be lost by the pretty printer.
It also allows us to keep the various information we keep in
side-tables, such as the type associated with each node.  We may
nonetheless start with pretty printed source and change later, if that
proves expedient.

The second dimension to the question of serializing source is at what
granularity to do it.  Graydon has pointed out that we should be
sensitive to the compile-time impact of inlining and monomorphization,
and I agree.  However, we are primarily interested in the compile-time
impact on *debug-mode* compilations, meaning that inlining would
probably be disabled.  Nonetheless, we should be careful about how we
package up the source for three reasons: (1) monomorphization, when it
occurs, will require access even in debug mode; (2) if we play our
cards right, we may be able to consolidate some of the control paths
we use in type checking and elsewhere (more on that in a bit); and (3)
having faster compile times even with optimizations enabled never
hurts.

This suggests to me that we do not want to include the source for an
entire crate at a time.  It seems like items are the logical level for
this.  I am wondering if we could encode the module structure using
EBML but at each top-level item we stop and encode two things: the
signature of the item as well as the source.  Currently, we encode the
signature using EBML, and perhaps we can just keep that path, though
it may be easier to pretty-print the signature and then parse it
again.

Why would that be easier, you ask? After all, the current system
works, right? Well, the idea (hat tip to pcwalton here) is to
consolidate some of the logic in the compiler.  Currently, everytime
we resolve the type of an item, we must ask "is it in the current
crate or not?" If it is, we go through one path, which involves
looking up the AST and other internal tables.  If it is not, then we
look into a crate metadata cache and---if needed---reconstruct the
signature by parsing EBML.  So my thought is that perhaps we can bring
these paths together by filling in the AST and other information lazilly,
extracting what is needed out of the crate.

Actually, the question of pretty-printing vs EBML is somewhat
orthogonal, I suppose.  In fact, it might be better to keep the EBML
for the reasons discussed earlier (easier to reconstruct the various
side table information that is required).

So, I am starting to see a high-level vision for how this might all be
organized, but I don't know these paths of the code that well, so I
might turn out to be rather confused.  It's also a bit unclear to me
if consolidating the paths through the compiler is important to CCI or
just a nice thing to do.  I'd rather get results first and work on
refactoring second.

