---
layout: post
title: 'Library-ification and support Rust analysis'
categories: [Rust]
---

I've noticed that the ideas that I post on my blog are getting much
more "well rounded". That is a problem. It means I'm waiting too long
to write about things. So I want to post about something that's a bit
more half-baked -- it's an idea that I've been kicking around to
create a kind of informal "analysis API" for rustc.

### The problem statement

I am interested in finding better ways to support advanced analyses
that "layer on" to rustc. I am thinking of projects like [Prusti] or
Facebook's [MIRAI], or even the venerable [Clippy]. All of these
projects are attempts to layer on additional analyses atop Rust's
existing type system that prove useful properties about your code.
[Prusti], for example, lets you add pre- and post-conditions to your
functions, and it will prove that they hold.

[MIRAI]: https://github.com/facebookexperimental/MIRAI
[Prusti]: https://www.pm.inf.ethz.ch/research/prusti.html
[Clippy]: https://github.com/rust-lang/rust-clippy

### In theory, Rust is a great fit for analysis

There has been a trend lately of trying to adapt existing tools build
initially for other languages to analyze Rust. [Prusti], for example,
is adapting an existing project called [Viper], which was built to
analyze languages like C# or Java. However, actually analyzing
programs written in C# or Java *in practice* is often quite difficult,
precisely because of the kinds of pervasive, mutable aliasing that
those languages encourage.

[Viper]: https://www.pm.inf.ethz.ch/research/viper.html

Pervasive aliasing means that if you see code like

```java
a.setCount(0);
```

it can be quite difficult to be sure whether that call might also
modify the state of some variable `b` that happens to be floating
around. If you are trying to enforce contracts like "in order to call
this method, the count must be greater than zero", then it's important
to know which variables are affected by calls like `setCount`.

Rust's ownership/borrowing system can be really helpful here. The
borrow checker rules ensure that it's fairly easy to see what data a
given Rust function might read or mutate. This is of course the key to
how Rust is able to steer you away from data races and segmentation
faults -- but the key insight here is that those same properties can
also be used to make higher-level correctness guarantees. Even better,
many of the more complex analyses that analysis tools might need --
e.g., alias analysis -- map fairly well onto what the Rust compile
already does.

### In practice, analyzing Rust is a pain, but not because of the language

Unfortunately, while Rust ought to be a great fit for analysis tools,
it's a horrible pain to try and implement such a tool **in practice**.
The problem is that there is lots of information that is needed to do
this sort of analysis, and that information is not readily accessible.
I'm thinking of information like the types of expressions or the kind
of aliasing information that the borrow check gathers. [Prusti], for
example, has to resort to reading the debug output from the borrow
checker and trying to reconstitute what is going on.

Ideally, I think what we would want is some way for analyzer tools to
leverage the compiler itself. They ought to be able to use the
compiler to do the parsing of Rust code, to run the borrow check, and
to construct MIR. They should then be able to access the [MIR] and the
accompanying borrow check results and use that to construct their own
internal IRs (in practice, virtually all such verifiers would prefer
to start from an abstraction level like MIR, and not from a raw Rust
AST). They should be able to ask the compiler for information about
the layout of data structures in memory and other things they might
need, too, or for information about the type signature of other
methods.

[MIR]: https://rustc-dev-guide.rust-lang.org/mir/index.html

### Enter: on-demand analysis and library-ification

A few years back, the idea of enabling analysis tools to interact with
the compiler and request this sort of detailed information would have
seemed like a fantasy. But the architectural work that we've been
doing lately is actually quite a good fit for this use case.

I'm referring to two different trends:

* on-demand analysis
* library-ification

### The first trend: On-demand analysis

On-demand analysis is basically the idea that we should structure the
compiler's internal core into a series of "queries". Each query is a
pure function from some inputs to an output, and it might be something
like "parse this file" (yielding an AST) or "type-check this function"
(yielding a set of errors). The key idea is that each query can in
turn invoke other queries, and thus execution begins from the *end
state* that we want to reach ("give me an executable") and works its
way *backwards* to the first few steps ("parse this file"). This winds
up [fitting quite nicely with incremental computation][incrblog] as
well as parallel execution. (If you'd like to learn more about this, I
gave a talk at [PLISS] that is [available on YouTube].)

On-demand analysis is also a great fit for IDEs, since it allows us to
do "just as much work" as we have to" in order to figure out key bits
of information (e.g., "what is the type of the expression at the
cursor"). The rust-analyzer project is based entirely on on-demand
computation, using the [salsa] library.

[incrblog]: https://blog.rust-lang.org/2016/09/08/incremental.html
[PLISS]: https://pliss.org/
[available on YouTube]: https://www.youtube.com/watch?v=N6b44kMS6OM
[salsa]: https://github.com/salsa-rs/salsa

### On-demand analysis is a good fit for analysis tools

On-demand analysis is not only a good fit for IDEs: it'd be a great
fit for tools like [Prusti]. If we had a reasonably stable API, tools
like [Prusti] could use on-demand analysis to ask for just the results
they need. For example, if they are analyzing a particular function,
they might ask for the borrow check results. In fact, if we did it
right, they could also leverage the same incremental compilation
caches that the compiler is using, which would mean that they don't
even have to re-parse or recompute results that are already available
from a previous build (or, conversly, upcoming builds can re-use
results that [Prusti] computed when doing its analysis).

### The second trend: Library-ification

There is a second trend in the compiler, one that's only just begun,
but one that I hope will transform the way rustc development feels by
the time it's done. We call it "library-ification". The basic idea is
to refactor the compiler into a set of *independent libraries*, all
knit together by the query system. 

One of the immediate drivers for library-ification is the desire to
integrate [rust-analyzer] and rustc into one coherent codebase. Right
now, the [rust-analyzer] IDE is basically a re-implementation of the
front-end of the Rust compiler. It has its own parser, its own name
resolver, and its own type-checker. 

### The vision: shared components

So we saw that, presently, rust-analyzer is effectively a
re-implementation of many parts of the the Rust compiler. But it's
also interesting to look at what rust-analyzer does **not** have --
its own trait system. rust-analyzer uses the [chalk] library to handle
its trait system. And, of course, work is [also underway] to integrate
chalk into rustc.

[also underway]: https://blog.rust-lang.org/inside-rust/2020/03/28/traits-sprint-1.html

At the moment, chalk is a promising but incomplete project. But if it
works as well as I hope, it points to a promising possibility. We can
have the "trait solver" as a coherent block of functionality that is
shared by multiple projects. And we could go further, so that we wind
up with rustc and rust-analyzer being just two "small shims" over top
the same core packages that make up the compiler. One shim would
export those packages in a "batch compilation" format suitable for use
by cargo, and one as a LSP server suitable for use by IDEs.

### The vision: Clean APIs defined in terms of Rust concepts

Chalk is interesting for another reason, too. The API that Chalk
offers is based around core concepts and should, I think, be fairly
stable. For example, it communicates with the compiler via a trait,
the [`RustIrDatabase`], that allows it to query for specific bits of
information about the Rust source (e.g., ["tell me about this
impl"][impl_datum]), and doesn't require a full AST or lots of
specifics from its host. One of the benefits of this is that we can
have a relatively simple testing harness that lets us write [chalk
unit tests] in a simplified form of Rust syntax.

[`RustIrDatabase`]: http://rust-lang.github.io/chalk/chalk_solve/trait.RustIrDatabase.html
[impl_datum]: http://rust-lang.github.io/chalk/chalk_solve/trait.RustIrDatabase.html#tymethod.impl_datum
[chalk unit tests]: https://github.com/rust-lang/chalk/blob/73a74be3bc1d0cdef3f76fa529a112a0d8367ddb/tests/test/impls.rs#L9-L22

The fact that chalk's unit tests are "mini Rust programs" is nice
because they're readable, but it's important a deeper reason,
too. I've many times experienced problems when using unit tests where
the tests wind up tied very tightly to the structure of the code, and
hence big swaths of tests get invalidated when doing refactoring, and
it's often quite hard to port them to the new interface. We don't
generally have to worry about this with rustc, since its tests are
just example programs -- and the same is true for Chalk, by and large.
My sense is that one of the ways that we will know where good library
boundaries lie will be our ability to write unit tests in a clear way.

### Library-ification can help make rustc more accessible

Right now, many folks have told me that the rustc code base can be
quite intimidating. There's a lot of code. It takes a while to build
and requires some custom setup to get things going (not to mention
gobs of RAM). Although, like any large code-base, it is factored into
several relatively independent modules, it's not always obvious where
the boundaries between those modules are, so it's hard to learn it a
piece at a time.

But imagine instead that rustc was composed of a relatively small
number of well-defined libraries, with clear and well-documented APIs
that separated them. Those libraries might be in separate repositories
and they might not, but regardless you could jump into a single
library and start working. It would have a clear API that connects it
to the rest of the compiler, and a testing harness that lets you run
unit tests that exercise that API (along of course with our existing
suite of example programs, which serve as integration tests).

The benefits of course aren't limited to new contributors. I really
enjoy hacking on chalk because it's a relatively narrow and pliable
code base.  It's easy to jump from place to place and find what I'm
looking for. In contrast, working on rustc feels much more difficult,
even though I know the codebase quite well.

### Library-ification will work best if APIs aren't changing

One thing I want to emphasize. I think that this whole scheme will
work best if we can find interfaces between components that are not
changing all the time. Frequently changing interfaces would indicate
that the modules between the compiler are coupled in ways we'd prefer
to avoid, and it will make it harder for people to work within one
library without having to learn the details of the others.

### Libaries could be used by analysis tools as well

Now we come to the final step. If we imagine that we are able to
subdivide rustc into coherent libraries, and that those libraries have
relatively clean, stable APIs betwen them, then it is also plausible
that we can start publishing those libraries on crates.io (or perhaps
wrappers around them, with simplified and more limited APIs). This
then starts to look sort of like the [.NET Roslyn compiler] -- we are
exporting the tools to help people analyze and understand Rust code
for themselves. So, for example, [Prusti] could invoke rustc's borrow
checker and read its results directly, without having to resort to
elaborate hacks.

[.NET Roslyn compiler]: https://github.com/dotnet/roslyn

### On stability and semver

I've tossed out the term "stable" a few times throughout this post, so
it's worth putting in a few words for how I think stability would work
if we went down this direction. **I absolutely do not think we would
want to commit to some kind of fixed, unchanging API for rustc or
libraries used by rustc.** In fact, in the early days, I imagine we'd
just publish a new major version of each library with each Rust
release, which would imply that you'd have to do frequent updates.

But once the APIs settle down -- and, as I wrote, I really hope that
they do -- I think we would simply want to have meaningful semver,
like any other library.  In other words, we should always feel free to
make breaking changes to our APIs, but we should announce when we do
so, and I hope that we don't have to do so frequently.

If this all **really** works out, I imagine we'd start to think about
scheduling breaking changes in APIs, or finding alternatives that let
us keep tooling working. I think that'd be a fine price to pay in
exchange for having a host of powerful tooling available, but in any
case it's quite far away.

### Conclusion

This post sketches out my vision for how Rust compiler development in
the long term. I'd like to see a rustc based on a relatively small
number of well-defined components that encapsulate major chunks of
functionality, like "the trait system", "the borrow checker", or "the
parser". In the short term, these components should allow us to share
code between rustc and rust-analyzer, and to make rustc more
understandable. In the longer term, these components could even enable
us to support a broad ecosystem of compiler tools and analyses.

