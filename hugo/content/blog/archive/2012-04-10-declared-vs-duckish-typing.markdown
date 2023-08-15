---
categories:
- Rust
comments: true
date: "2012-04-10T00:00:00Z"
slug: declared-vs-duckish-typing
title: Declared vs duckish typing
---

One of the questions in our object system is what precisely how
"declared" we want things to be when it comes to interfaces and
implementations.  In a discussion on IRC, graydon suggested it'd
be nice to have terms like "duck-typing" defined more precisely in
a Rust syntax, and he is correct.  So here is my effort.

### The current setup

Currently, implementations must declare precisely what types they
implement.  For example, it looks like this:

    impl of draw for T {
        ...
    }
    
where `draw` is an interface.  Then, later, if we have an instance of
type `S` and we wish to know whether it implementations the interface
`draw`, we can scan through the set of implementations that are
declared to implement `draw` and see if any of them are for the type
`S`.

### A more duck-typing like setup

Another option would be to remove the requirement that an impl
declares what interfaces it implements.  In that case, when we have a
need to know if the type `S` implements the iface `draw`, we would
again scan all of the implementations in scope for the type `S`.  For
each one, we would check whether it contains all the methods defined
in `draw`.  If so, we declare to be an implementation of the iface (we
must also check that the methods contain the right types; it's unclear
to me whether we should do this check before or after deciding that it
is an implementation, though).

### Why duck typing?

It's more convenient.  There is also, currently, no good way to create
an "after the fact" interface: support I have a bunch of types that
all already have a `draw()` method and a `bounds()` method defined,
and I'd like to make an iface like:

    iface draw_and_bounds {
        fn draw();
        fn bounds();
    }
    
and then just use it.  Now everything just works.  In the more statically
declared world, I would then have to go over each type and do something
like:

    impl of draw_and_bounds for S { }
    impl of draw_and_bounds for T { }
    
These impls just serve to declare that the type `S` (and `T`)
implements the iface `draw_and_bounds` (and needs no additional
methods to do so).  Actually, this wouldn't work today at all, because
we don't check for existing methods when deciding, so you'd really have
to do something like:

    impl of draw_and_bounds for S {
        fn draw() { self.some_other_impl::draw() }
        fn bounds() { self.some_other_impl::bounds() }
    }
    
But of course the `some_other_impl::draw` syntax for naming a method
isn't implemented, so you'd have to do something like:

    fn my_draw(self: S) { import some_other_impl; self.draw(); }
    fn my_bounds(self: S) { import some_other_impl; self.draw(); }
    impl of draw_and_bounds for S {
        fn draw() { my_draw(self) }
        fn bounds() { my_bounds(self) }
    }

But we could fix that by implementing features.

### Why not?

Just because methods with the right *names* are available doesn't mean
that they will do what you expect.  Maybe you mean `draw()` as in
"draw your gun" not "draw yourself on the screen".  It also prevents
'marker interfaces', like Java's `serializable`.

### Non-obvious implications and small design decisions

#### Simplicity and compilation time

One of the arguments for a non-duck-typing scenario is that it makes
the system easier to implement.  We can generate the vtable at the
point of impl declaration and then refer to it from other places,
rather than having to generate the vtable lazilly as needed.  

It seems to me that it would affect compilation time.  It's bound to
be faster to check compliance with the iface once, at the `impl`, then
at each point of invocation.  However, we can cache these results, so
that's probably not a big deal.

#### Frankenstein impls

A big open question (to me) is whether we should consider an interface
to be implemented if all the necessary methods are available but they
come from different sources.  For example, consider something like:

    impl draw for T { fn draw() { ... } }
    impl bounds for T { fn bounds() { ... } }

Now, in a duck-typing world, is the `draw_and_bounds` iface
implemented or not?  It seems to involve a similar set of tradeoffs.
If the answer is that they are not implemented, we need to write
something explicit like `impl draw_and_bounds for T { ... }` just as
we had to do when not using duck typing at all.

Still, I think that we should disallow such "frankenstein" impls.  The
main reason is that it makes instance coherence just about impossible
to address (more on that in a later post, but in short form it
prevents us from concisely naming the origin of the iface methods).
It also makes the compiler more complex and heightens the danger of
matching methods with the same names but different semantics.

This is a short-ish post.  I'm sure there are many details I have
omitted.

### What do I want?

I don't know.  I originally wanted duck typing.  Now I am somewhat
undecided.  I do think Frankenstein impls (something else I originally
wanted) are bad (because of the instance coherence problems I alluded
to).  I think if we make the syntax for "reusing" existing methods to
implement a new iface sufficiently compact, it's probably not so
painful.  I am not really worried about semantic mismatches: these are
rare in dynamically typed languages, and we have types and other
checks that make such a mismatch unlikely.
