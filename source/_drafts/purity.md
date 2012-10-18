In this post I propose an extension of Rust's purity rules.  The short
version is that pure functions would be allowed to mutate data owned
by their `&mut` parameters.  This extends the current Rust purity
rules which allow pure functions to invoke impure closures so long as
they are an argument to the function.  The principle is the same: pure
functions are functions whose side-effects can be completely
determined by examining their parameters (for the more formally minded
among you, this is effectively an effect-parametric system with *very*
lightweight notation).  The rest of the post is an elaboration and
justification of this idea.

### Background on purity and how it works in Rust today

Rust allows functions to be declared `pure`.  The general idea of a
`pure` function is that they do not mutate state reachable by the
caller.  That means that you can call a pure function twice in a row,
with the same arguments, and be guaranteed of getting the same result.

In practice, though, Rust provides a somewhat more complex, but
infinitely more useful, definition of purity.  Informally, rather than
saying that a pure function will not modify *anything* the caller can
reach, we say that executing a pure function will not modify anything
that the caller doesn't know they are going to modify.  To see what I
mean, consider the function `each()` which iterates over a vector and
invokes a callback for each element:

    pure fn each<T>(v: &[T], op: fn(&T)) {
        let i = 0, n = v.len();
        while i < n {
            op(&v[i]);
            i += 1;
        }
    }

We can't say that the function `each()` modifies *nothing*, because it
calls the closure `op` that the caller provided, and `op` could do
anything.  We could of course declare that `op` as a pure closure, but
that would make `each()` rather useless, since you would not be able
to do any mutation whenever you iterated over a vector. We could also
say that `each()` is not pure, but that loses some useful
information---after all, `each()` does not *itself* mutate anything
that the user has access to.  It's the *callback* which does!  So
`each()` is kind of "conditionally pure"---it is pure if its callback
is pure, but not otherwise.

This idea of "conditional purity" is precisely what Rust currently
adopts.  So in short a pure function today is permitted exactly one
kind of (potentially) impure action: invoking closures that it was
provided as argument.  This idea is really useful and opens up a wide
variety of functions to be declared as pure that could not have been
declared pure before.

#### What is purity used for in Rust

The primary purpose of purity in Rust is memory safety.  The Rust
compiler will permit you to create borrowed pointers that might be
invalidated by mutation so long as you only perform pure actions for
the lifetime of those pointers.  This is very useful in practice.

Another purpose for purity that I foresee is bringing a
[Rivertrail- or PJs-like model][rt] for data parallelism to Rust.  The
notion of purity I am talking about aligns very well here.  In that
model, in particular, being able to give the worker functions
controlled access to mutable data can be very useful, as I described
in this [HotPar paper][hotpar] that I wrote some time back (note
however that in the HotPar paper I made use of a transitive read-only
type qualifier to gain the same guarantees that `pure` functions give
us; using `pure` seems simpler).

[rt]: /blog/2012/10/10/rivertrail/
[hotpar]: https://www.usenix.org/conference/hotpar12/parallel-closures-new-twist-old-idea

### My proposed extension

I would like to extend the idea of conditional purity a little
further.  I want to say that, in addition to invoking impure closures
given as argument, a pure function can take one additional action: it
can write to any `&mut` pointer given as argument.  The principle is
the same as before: the side effects of executing a particular call to
a pure function can be completely determined by examining its
arguments.  This means that if the caller requires purity for a memory
safety reason, they can still identify all of the data which will be
modified by the pure function and make sure it's safe.

The problem I am trying to solve is succintly described by Tim in
[Issue #3722][3722]: right now, a pure function is permitted to mutate
its local variables, but there is no way to factor out bits of code
from a pure function into a helper.

[3722]: https://github.com/mozilla/rust/issues/3722

Tim's example is as follows:

```
pure fn make_str() -> ~str {
  let mut s = ~"";
  str::push_char(&mut s, 'c');
  return s;
}
```

Here, the call to `push_char()` is not considered pure because it
modifies the string `s` which was supplied as argument.  Therefore it
cannot be called from `make_str()`, as `make_str()` is pure.
Nonetheless, we know that this would be safe, as `push_char()` only
mutates the string it is given as argument, and `make_str()` is
permitted to mutate `s` without violating purity.

### An example

To help clarify the rule, and in particular what data would be mutable
and what would not, here is an example:

    struct Foo {
        mut counter1: uint,
        bar1: ~Bar,
        bar2: @Bar,
        bar2: &Bar
    }
    
    struct Bar {
        mut counter: uint
    }
    
    pure fn frob(p: &mut Foo) {
        p.counter += 1; // OK, counter is interior to `*p`
        p.bar1.counter += 1; // OK, counter is owned by `*p`
        p.bar2.counter += 1; // Error, counter is not owned by `*p`.
        p.bar3.counter += 1; // Error, counter is not owned by `*p`.
    }

You can see from the fn `frob` that mutating any data owned by `*p` is
legal, but not data that is reached via an `@` or `&` pointer.
    
### Enforcing and Formalizing the proposed rule

Under the rule I propose, a pure function could have two form of
externally visible side-effects:

- a pure function can write to any `&mut` pointer which it is given as a parameter;
- a pure function may invoke any closure which is passed to it as a parameter.

From the point of view of the pure function, the actions it may
legally take are something like the following:

- write to data owned by the current stack frame;
- write to data owned by an `&mut` parameter;
- read any data it likes;
- invoke closures given as parameters;
- invoke other pure functions or methods, however:
  - for each parameter of the pure function declared with `&mut` type,
    the value provided must be one which is writable by the current
    function;
  - for each parameter of the pure function declared with closure
    type, the value provided must be one which is callable by the
    current function.
    
These rules aren't really complete, however, because they don't take
into account what the limits ought to be when borrow check decides
that purity is needed for a particular block.
    
On the plane flying back from the Emerging Languages workshop, I wrote
out a formalization of this idea based on an effect system with heap
regions.  What I would like to do is move the current purity checking,
which is written using ad-hoc rules similar to the ones above, and
implement it based on this formalization, which I think is much easier
to think about, and helps to ensure it's giving the right answer in
various corner cases.

I wanted to write up this formalization here in this post, but I've
got too much on my plate today to spend the time on it, so it'll have
to wait.  I guess it's no crime if I post a blog post that's less than
22 pages when printed.

**UPDATE:** Added an example and a little bit of clarifying text.
