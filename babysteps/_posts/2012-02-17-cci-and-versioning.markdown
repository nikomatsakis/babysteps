---
layout: post
title: "CCI and versioning"
date: 2012-02-17 21:40
comments: true
categories: [Rust]
---

I've been busily implementing the Cross-Crate Inlining stuff, but one
area I haven't looked at much is versioning.  In particular, if we are
going to be serializing the AST, we need a plan for what to do when
the AST changes.  Actually, if inlining were only to be used for
performance, we wouldn't really *need* to have a plan: we could just
not inline when the AST appeared to be stored in some form we don't
understand. However, if we fully monomorphize, we will not have that
luxury: without type descriptors, the only way to compile cross-crate,
generic calls will be by inlining.  

This because particularly important because Rust is self-hosting.  In
particular, the compilation process begins by compiling the standard
libraries for use by later stages.  But if we change the form of the
AST, the snapshot compiler that bootstraps our compilation will still
be generating the older AST---so we had better have a way of reading
it!

I am not really sure what's the best way to handle this.  I had always
assumed that one we reach 1.0, we would just keep a version of that
AST module around forever, and convert to the newer AST formats.  This
is a somewhat painful but acceptable price to pay, so long as the set
of versions is not too high.  But this scheme looks less attractive if
we have to do it for every field that we add to the AST.  

In addition, there is another wrinkle I hadn't really thought about:
alongside the AST, we also store the results of various analyses which
are used during code gen.  For example, there is an analysis that
indicates whether a variable is mutated, or whether a particular copy
can in fact be implemented with a move.  If new analyses are added in
the future (and they will be), we won't have results available for
older crates, so we will have to be sure we can always get by without
those results.  In most cases, though, these results are just used to
generate faster code, so we can always generate less efficient code
without a problem.  But it is something that we nonetheless have to be
aware of---and it affects how the side table information is stored.
For example, keeping a set of variables that we can optimize better is
good, but keeping a set of variables for which we must be conservative
is bad.  This is because if the set leads to optimization, we can
always just use an empty set without affecting correctness.  But
anyhow this can all be handled with some code.

Anyway, what would be nicest is to have attributes into the AST to
indicate what kind of values should be provided for fields that are
missing and so forth.  This would mean that the serialization code
would have to get somewhat smarter, so that it can cope with things
like a record with fields that may or may not be present.  This is
where having automated the serialization process should really pay
off, though, since I can make these adjustments once and have all the
code be automatically adjusted.  Still, I'd have to figure out how to
best encode things so that I can figure out what data *is* present and
what is not, and what kinds of changes we should accept.

> One note: these kinds of "default-providing" attributes can be dropped
> once a new snapshot is generated, except in cases where they are
> required for backwards compatibility to some publicly supported
> release.

I had rather hoped to avoid these kinds of questions, at least not
yet.  These seem like detailed questions that are the domain of a
specialized library.  But I think that they will be hard to avoid so
long as we are bootstrapping, as we will always have to deal with
executables generated based on the older AST definition.
