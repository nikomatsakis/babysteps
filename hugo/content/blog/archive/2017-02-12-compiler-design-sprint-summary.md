---
categories:
- Rust
date: "2017-02-12T00:00:00Z"
slug: compiler-design-sprint-summary
title: Compiler design sprint summary
---

This last week we had the **rustc compiler team design sprint**.  This
was our second rustc compiler team sprint; the first one (last year)
we simply worked on pushing various projects over the finish line (for
example, in an epic effort, arielb1 completed dynamic drop during that
sprint).

This sprint was different: we had the goal of talking over many of the
big design challenges that we'd like to tackle in the upcoming year
and making sure that the compiler team was roughly on board with the
best way to implement them.

I or others will be trying to write up many of the details in various
forums, either on this blog or perhaps on internals etc, but I thought
it'd be fun to start with a quick post that describes the overall
topics of discussion. For each one, I'll give a quick summary and,
where possible, point you at the minutes and notes that we took.

### On-demand processing and incremental compilation

The first topic of discussion was perhaps the most massive, in terms
of its impact on the codebase. The goal is to reorient how rustc works
internally completely. Right now, like many compilers, rustc works by
running a series of **passes**, one after the other. So for example we
first parse, then do macro expansion and name resolution (these used
to be distinct, but have now become interwoven as part of the work on
macros 2.0), then type-checking, and so forth. This is a time-honored
approach, but it's beginning to show its age:

- Some parts of the compiler front-end cannot be so neatly separated.
  I already mentioned how macro expansion and name resolution are now
  interdependent (you have to resolve the path that leads to a macro
  to know which macro to expand). Similar things arise in
  type-checking, particularly as we aim to support constant
  expressions in types.  In that case, we have to type-check the
  constant expression, but it must also be part of a type, and so
  forth.
- For better IDE support, it is desirable to be able to compile just
  what is needed to type-check a particular function (we can come back
  and cleanup the rest later).
- Things like `impl Trait` make the type-checking of some functions
  partially dependent on the results of others, so the old approach of
  type-checking all function bodies in an arbitrary order doesn't work.
  
The idea is to replace it with **on-demand** compilation, which
basically means that we will have a graph of "things we might want to
compute" (for example, "does the function `foo` type-check"). We can
"demand" any one of these "queries", and the compiler will go and do
what it has to do to figure out the answer. That may involve
satisfying other queries internally (hopefully without cycles). In the
end, your entire type-check will complete, but the order in which we
do the compiler will be far less specified.
  
This idea for on-demand compilation naturally dovetails with the plans
for the next generation of incremental compilation. The current design
is similar to make: when a change is made, we eagerly propagate the
effect of that change, throwing away any old results that might have
been affected.  Often, though, we don't know that the old results
**would have been** affected.  It frequently happens that one makes
changes which only affect some parts of a result: e.g., a change to a
fn body that just renames some variables might still wind up
generating precisely the same MIR in the end.

Under the newer scheme, the idea is to limit the spread of changes.
If the inputs to a particular computation change, we do indeed have to
re-run the computation, but we can check if its output is different
from the output we have saved. If not, we don't have to dirty things
that were dependent on the computation. (The scheme we wound up with
can be considered a specialized variant of
[Adapton](http://adapton.org/), which is a very cool Rust and Ocaml
library for doing generic incrementalized computation.)

Links:

- [etherpad](https://public.etherpad-mozilla.org/p/rust-compiler-design-sprint-paris-2017-odi)

### Supporting alternate backends

We spent some time discussing how to integrate alternate backends
(e.g., [Cretonne], [WASM], and -- in its own way -- [miri].). Now that
we have MIR, a lot of the hard work is done: the translation from MIR
to LLVM is fairly straightforward, and the translation from MIR to
Cretonne or WASM might be even more simple (particularly since eddyb
already made the code that computes field and struct layouts be
independent from LLVM).

There are still some parts of the system that we will need to factor out
from `librustc_trans`. For example, the "collector", which is the bit of code
that determines what monomorphizations we need to generate of each function,
is independent from LLVM.

The goal with Cretonne, as [discussed on internals][thread], is
ultimately to use it as the debug-mode backend. It promises to offer a
very fast, "decent quality" compilation experience, with LLVM sticking
around as the heavyweight compiler (and to support more
architectures). The plan for Cretonne integration is (most likely) to
begin with a stateless REPL, similar to
[play.rust-lang.org](https://play.rust-lang.org) or the playbot on
IRC. The idea would be to take a complete Rust program (i.e., with a
`main()` function), compile it to a buffer, and execute that. This
avoids the need to generate `.o` files from Cretonne, since that code
does not exist (Cretonne's first consumer is going to be a JIT, after
all).

After we had finished admiring [stoklund]'s admirable job of writing
clean, documented code in Cretonne, we also dug into some of the
details of how it works. There are still a number of things that are
needed before we can really get this project off the ground (notably:
a register allocator), but in general it is a very nice match with MIR
and also our plans around constant evaluation via miri (discussed in
an upcoming part of this blog post). We discussed how best to maintain
debuginfo, and in particular some of [stoklund]'s very cool ideas to
use the same feature that JITs use to perform de-optimization to track
debuginfo values (which would then guarantee perfect fidelity).

We had the idea that we might enable different backends per
codegen-unit (i.e., per module, in incremental compilation), so that
we can use LLVM to accommodate some of the more annoying features
(e.g., inline assembly) that may not appear in Cretonne any time soon.

[Cretonne]: https://github.com/stoklund/cretonne
[miri]: https://github.com/tsion/miri
[WASM]: http://webassembly.org/
[stoklund]: https://github.com/stoklund
[thread]: https://internals.rust-lang.org/t/possible-alternative-compiler-backend-cretonne/4275

Links:

- [internals thread about Cretonne][thread]
- [etherpad](https://public.etherpad-mozilla.org/p/rust-compiler-design-sprint-paris-2017-mir)

### MIR Optimization

We spent some time -- not as much as I might have liked -- digging
into the idea of optimizing MIR and trying to form an overall
strategy. Almost any optimization we might do requires *some* notion
of unsafe code guidelines to justify, so one of the things we talked
about was how to "separate out" that part of the system so that it can
be evolved and tightened as we get a more firm idea of what unsafe
code can and cannot do. The general conclusion was that this could be
done primarily by having some standard dataflow analyses that try to
detect when values "escape" and so forth -- we would probably start
with a VERY conservative notion that any local which has *ever* been
borrowed may be mutated by any pointer write or function call, for
example, and then gradually tighten up.

In general, we don't expect rustc to be doing a lot of aggressive
optimization, as we prefer to leave that to the backends like
LLVM. However, we would like to generate better code primarily for the
purposes of improving compilation time. This works because optimizing
MIR is just plain simpler and faster than other IRs, since it is
higher-level, and because it is pre-monomorphization. If we do a good
enough job, it can also help to close the gap between the performance
of debug mode and release mode builds, thus also helping with
compilation time by allowing people to use debug more builds more
often.

Finally, we discussed [aatch's inlining PR][39648], and iterated around
different designs. In particular, we considered an "on the fly"
inlining design where we did inlining more like a JIT does it, during
the lowering to LLVM (or Cretonne, etc) IR.  Ultimately we deciding
that the current plan (inlining in MIR) seemed best, even though it
involves potentially allocating more data-structures, because it
enables us to optimize (A) before monomorphization, multiplying the
benefit and (B) we can remove a lot of temporaries and so forth, in
particular around small functions like `Deref::deref`, whereas if we
do the inlining as we lower, we are ultimately leaving that to LLVM to
do.

[39648]: https://github.com/rust-lang/rust/pull/39648

- [etherpad](https://public.etherpad-mozilla.org/p/rust-compiler-design-sprint-paris-2017-mir)

### Unsafe code guidelines

We spent quite a while discussing various aspects of the intersection
of (theoretical) unsafe code guidelines and the compiler. I'll be
writing up some detailed posts on this topic, so I won't go into much
detail, but I'll leave some high-level notes:

- We discussed exhaustiveness and made up plans for how to incorporate
  the `!` type there.
- We discussed how to ensure that we can still optimize safe code
  even in the presence of unsafe code, and what kinds of guarantees
  we need to require.
  - Likely the kinds of assertions I was describing in
    [my most recent post on the topic][ucgpost] aren't quite right,
    and we want the "locking" approach I began with, but modified to
    account for privacy.
- We looked some at how LLVM handles dependence analysis and so forth,
  and what kinds of rules we would need to ensure that LLVM is not
  doing more aggressive optimization than our rules would permit.
  - The LLVM rules we looked at all seem to fall under the rubrik of
    "LLVM will consider a local variable to have escaped unless it can
    prove that it hasn't". What I wonder about is the extent to which
    other optimizations might take advantage of the ways that the C
    standard technically forbid you to transmute a pointer to a
    `usize` and then back again (or at least forbid you from using the
    resulting pointer). Apparently gcc will do *some* amount of
    optimization on this basis, but perhaps not LLVM, though more
    investigation is warranted.

[ucgpost]: http://smallcultfollowing.com/babysteps/blog/2017/02/01/unsafe-code-and-shared-references/

Links:

- [etherpad](https://public.etherpad-mozilla.org/p/rust-compiler-design-sprint-paris-2017-ucg)

### Macros 2.0, hygiene, spans

jseyfried called in and filled us in on some of the latest progress
around Macros 2.0. We discussed the best way to track hygiene
information -- in particular, whether we could do it using the same
spans that we use to track line number and column information. In
general I think there was consensus that this could work. =) We also
discussed some of the interactions with privacy and hygiene that arise
when you try to be smarter than our current macro system.

Links:

- [etherpad](https://public.etherpad-mozilla.org/p/rust-compiler-design-sprint-paris-2017-macros)

### Diagnostic improvements

While talking about spans, we discussed some of the ways we could
address some shortcomings in our current diagnostic output. For
example, we'd like to avoid highlighting multiple lines when citing a
method, and instead just underlyine the method name, and that sort of
thing. We'd also like to print out types using identifiers local to
the site of the error (i.e., `Option<T>` and not
`::std::option::Option<T>`).  Hopefully we'll be converting those
rough plans into mentoring instructions, as these seem like good
starter projects for someone wanting to learn more about how rustc
works.

Links:

- [etherpad](https://public.etherpad-mozilla.org/p/rust-compiler-design-sprint-paris-2017-macros)
  (scroll down)

### miri integration

We discussed integrating the [miri] interpreter. The initial plan is
to have it play a very limited role: simply replacing the current
constant evaluator that lowers to LLVM constants. Since miri produces
basically a big binary blob (possibly with embedded pointers called
"redirections"), but LLVM wants a higher-level thing, we have to use
some bitcasts and so forth to encode it. This is actually an area
where [Cretonne's][Cretonne] level of abstraction, which is lower than
LLVM, is probably a better fit. But it should all work out fine in any case.

This initial step of using miri as constant evaluator would not change
in any way the set of programs that are accepted, except in so far as
it makes them work better and more reliably. But it does give us the
tools to start handling constants in the front-end as well as a much
wider range of `const fn` bodies and so forth (possibly even including
limited amounts of unsafe code).

Links:

- [etherpad](https://public.etherpad-mozilla.org/p/rust-compiler-design-sprint-paris-2017-miri)

### Variable length arrays and allocas

We discussed the desire to support allocas ([RFC 1808]) coupled with
the desire to support unsized types in more locations (in particular
as the types of parameters). We worked through how we would implement
this and what some of the complications might be, and drew up a rough
plan for an extension to the language that would be expressive,
efficiently implementable, and avoid unpredictable rampant stack
growth. This will hopefully makes its way into an RFC soon.

[RFC 1808]: https://github.com/rust-lang/rfcs/pull/1808

Links:

- [etherpad](https://public.etherpad-mozilla.org/p/rust-compiler-design-sprint-paris-2017-unsized)

### Non-lexical lifetimes

We spent quite a while iterating on the design for non-lexical
lifetimes. I plan to write this up shortly in another blog post, but
the summary is that we think we have a design that we are quite happy
with. It addresses (I believe) all the known examples and even
extends to support [nested method calls] where the outer call has an
`&mut self` argument (e.g., `vec.push(vec.len())`, which today do not
compile. 

[nested method calls]: https://internals.rust-lang.org/t/accepting-nested-method-calls-with-an-mut-self-receiver/4588

Links:

- [etherpad](https://public.etherpad-mozilla.org/p/rust-compiler-design-sprint-paris-2017-nll)

### Conclusion

Those were the main topics of discussion -- pretty exciting stuff!  I
can't wait to see these changes play out over the next year. Thanks to
all the attendees, and particularly those who dialed in remotely at
indecent hours of the day and night (notably jseyfried and nrc) to
accommodate the Parisian time zone.

[Comments? Check out the internals thread.][comments]

[comments]: http://smallcultfollowing.com/babysteps/blog/2017/02/12/compiler-design-sprint-summary/
