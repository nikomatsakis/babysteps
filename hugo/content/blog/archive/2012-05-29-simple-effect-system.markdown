---
categories:
- Rust
comments: true
date: "2012-05-29T00:00:00Z"
slug: simple-effect-system
title: Simple effect system
---

Currently, Rust has an effect system but refuses to admit it.  In an
effort to broaden the set of things that can be safely done in the
face of extant aliases into the heap, I have been experimenting with a
lightweight extension to Rust's system.  So far I think it is
promising but also no magic bullet.

### Background

For those who aren't familiar with the term, an "effect system" is
basically just a fancy name for tagging functions with some extra
information beyond the types of their arguments and their return type.

Effect systems vary wildly in their complexity and in their purpose.
Probably the most widely deployed---and perhaps least popular---effect
system is Java's system of checked exceptions.  In that system, the
"effect" is the list of exceptions that may get thrown during the
execution of the function.  (In the research literature, effects are
used for everything from ensuring [consistent lock use][SafeJava] to
[bridging functional and imperative software][FX] to
[supporting safe, live updates of running software][rs], and that's
just getting started).

[SafeJava]: http://pmg.csail.mit.edu/pubs/boyapati04safejava-abstract.html
[FX]: http://citeseerx.ist.psu.edu/viewdoc/summary?doi=10.1.1.62.534
[rs]: http://drum.lib.umd.edu/handle/1903/7494?mode=simple

The truth is, though, that effect systems as commonly envisioned do
not scale, and every Java programmers already knows this very well.
The problem is that language designers face an annoying choice.  They
can take the Java route and keep the system very simple.  Things work
pretty well as long as your classes are all very concrete.  But when
you get to a highly abstract interface like `Runnable`, you start to
run into trouble: what exceptions should the `run()` method of
`Runnable` *throw*, anyhow?  Obviously it's impossible to say, as the
interface can be used for any number of things.

The traditional solution to this problem is to allow *effect
parameterization*. If you're not careful, though, the sickness can
easily be worse than the disease.  Effect parameterization is
basically like generic types, except that instead of defining your
class in terms of an unknown type, you are defining it in terms of an
unknown set of effects.  To continue with the Java example, this would
mean that `Runnable` does not declare the set of types that the
`run()` method may throw but rather is defined something like this:

    interface Runnable<throws E> {
        void run() throws E;
    }

Now, this is a bit confusing, because it looks like `E` is a type (and
in fact you can define Java like this where `E` is a type).  But I
added the extra `throws` keyword to try and make it clear that `E`
here is *not* a type parameter, but an effect parameter: its value, so
to speak, is not a single type, but rather a set of exception types
that may be thrown.  So perhaps I might define a concrete `Runnable`
like (this syntax is again imaginary, and even ambiguous to boot, but
hopefully you get the idea):

    class RunnableThatUsesFilesAndJoinsThreads
    implements Runnable<throws IOException, InterruptedException>
    {
        void run() throws IOException, InterruptedException {
            ...
        }
    }
    
Obviously I think both of these solutions are unacceptable.  The first
(Java as it is today) because it is too inexpressive and the second
(hypothetical, parametric Java) because it is a pain.

### Rust today

Rust today has a simple effect system in which each function is
labeled as either pure, impure, or unsafe (impure is the default).
Pure functions are not permitted to modify any aliasable state.
Impure functions may modify any mutable state they wish but may not
perform unsafe operations like pointer arithmetic.  Unsafe functions
may do arbitrary things.

We address the matter of polymorphic effects just as Java does (this
is the crux of what I propose to change; read on).  Functions must be
statically labeled with their effect.  Closure pointers cannot have an
effect and thus must be impure; however, we have some special rules
around stack closure functions: for example, a stack closure in an
unsafe function may perform unsafe actions.

Effects can be "hidden" and justed by using special blocks.  For
example, an `unsafe` block hides the unsafe effect:

    fn foo() {
        unsafe {
           /* do unsafe things here,
              even though `foo()` is not unsafe */
        }
    }

and an `unchecked` block hides the impure effect:

    pure fn foo() {
        unchecked {
           /* do impure things here,
              even though `foo()` is pure */
        }
    }

One thing you cannot do today is declare a pure function that takes
closure parameters (or, at least, they cannot be called without using
`unchecked`).  This is too bad, because there most higher-order
functions are basically pure, assuming their closures are pure.

### Rust tomorrow, perhaps?

My basic idea (inspired by [Lightweight Polymorphic Effects][lpe]) is
to say that a pure function is only as pure as its arguments are.  So,
you can write a pure function like `all()`, which applies a closure to
each parameter:

    pure fn all<T>(v: [T], f: fn(T) -> bool) -> bool {
        for v.each { |e| if !f(e) { ret false; } }
        ret true;
    }

The caller then knows that, because `all()` is declared pure, it is
does not itself do anything impure---but invoking `all()` can still
cause impure effects, if an impure closure is passed to it. In type
theoretical terms, every pure function is implicitly parameterized by
the effects of its closure arguments.

This boils down to a single rule.  A call expression `f(a, ..., z)` is
pure if `f` and all the arguments `a...z` are "pure-callable".  An
expression `e` is "pure-callable" if:

  - it is not a function;
  - it is a function with effect `pure`;
  - it is one of the formal arguments to the enclosing pure function (if any);
  - it is a stack closure, in which case its contents
    will be checked for purity.
    
I implemented this check, and in the process made it possible to have
a type like `pure fn(S) -> T` or `unsafe fn(S) -> T`.  It was easy.
It's pretty nice, but doesn't cover all cases that you might like.

[lpe]: http://infoscience.epfl.ch/record/175240/files/ecoop.pdf

### Going further to allow limited mutation?

One I had to use `unchecked` in a few places, such as this:

    pure fn map<T,U>(v: [T], f: fn(T) -> U) -> bool {
        let u = [];
        unchecked {
            vec::reserve(&mut u, v.len());
        }
        for v.each { |e| u += f(e); }
        ret u;
    }
    
    fn reserve<T>(v: &mut [T], l: uint) {...}

Here the problem is that `vec::reserve()` modifies its argument and is
hence considered not pure.  In some sense, it'd be nice if a pure
function could give away mutable pointers to state that it is allowed
to modify.  In principle, we could extend this idea for lightweight
polymorphism and say "a pure function cannot modify data except for
its immediate arguments".  But maybe this is going too far.  For now,
I just inserted the occasional `unchecked` block.

