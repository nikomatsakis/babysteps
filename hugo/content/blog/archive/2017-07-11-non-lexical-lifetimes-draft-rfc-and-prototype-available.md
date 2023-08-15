---
categories:
- Rust
- NLL
date: "2017-07-11T00:00:00Z"
slug: non-lexical-lifetimes-draft-rfc-and-prototype-available
title: 'Non-lexical lifetimes: draft RFC and prototype available'
---

I've been hard at work the last month or so on trying to complete the
non-lexical lifetimes RFC. I'm pretty excited about how it's shaping
up. I wanted to write a kind of "meta" blog post talking about the
current state of the proposal -- almost there! -- and how you could
get involved with helping to push it over the finish line.

### TL;DR

What can I say, I'm loquacious! In case you don't want to read the
full post, here are the highlights:

- The NLL proposal is looking good. As far as I know, the proposal
  covers all major **intraprocedural** shortcomings of the existing
  borrow checker. The appendix at the end of this post talks about the
  problems that we **don't** address (yet).
- The draft RFC is [available in a GitHub repository][nll-rfc]:
  - Read it over! Open issues! Open PRs!
  - In particular, if there is some pattern you think may not be
    covered, please let me know about it by opening an issue.
- There is a [working prototype as well][proto]:
  - The prototype includes region inference as well as the borrow
    checker.
  - I hope to expand it to become the normative prototype of how the
    borrow checker works, allowing us to easily experiment with
    extensions and modifications -- analogous to Chalk.

### Background: what the proposal aims to fix

The goal of this proposal is to fix the **intra-procedural**
shortcomings of the existing borrow checker. That is, to fix those
cases where, without looking at any other functions or knowing
anything about what they do, we can see that some function is safe.
The core of the proposal is the idea of defining reference lifetimes
in terms of the control-flow graph, as I discussed (over a year ago!)
in my [introductory blog post;][intro] but that alone isn't enough to
address some common annoyances, so I've grown the proposal somewhat.
In addition to defining how to infer and define non-lexical lifetimes
themselves, it now includes an improved definition of the Rust borrow
checker -- that is, how to decide **which loans are in scope** at any
particular point and **which actions are illegal as a result**.

[intro]: {{ site.baseurl }}/blog/2016/04/27/non-lexical-lifetimes-introduction/

When combined with [RFC 2025][2025], this means that we will accept
two more classes of programs. First, what I call "nested method calls":

[2025]: https://github.com/rust-lang/rfcs/pull/2025

```rust
impl Foo {
  fn add(&mut self, value: Point) { ... }
  fn compute(&self) -> Point { ... }
  
  fn process(&mut self) {
    self.add(self.compute()); // Error today! But not with RFC 2025.
  }
}
```

Second, what I call "reference overwrites". Currently, the borrow
checker forbids you from writing code that updates an `&mut` variable
whose referent is borrowed. This most commonly shows up when iterating
down a slice in place ([try it on play](https://is.gd/FumP9w)):

```rust
fn search(mut data: &mut [Data]) -> bool {
  loop {
    if let Some((first, tail)) = data.split_first_mut() {
      if is_match(first) {
        return true;
      }
      
      data = tail; // Error today! But not with the NLL proposal.
    } else {
      return false;
    }
  }
}
```

The problem here is that the current borrow checker sees that
`data.split_first_mut()` borrows `*data` (which has type
`[Data]`). Normally, when you borrow some path, then all prefixes of
the path become immutable, and hence borrowing `*data` means that,
later on, modifying `data` in `data = tail` is illegal. This rule
makes sense for "interior" data like fields: if you've borrowed the
field of a struct, then overwriting the struct itself will also
overwrite the field. But the rule is too strong for references and
indirection: if you overwrite an `&mut`, you don't affect the data it
refers to. You can workaround this problem by forcing a *move* of
`data` (e.g., by writing `{data}.split_first_mut()`), but you
shouldn't have to. (This issue has been filed for some time as
[#10520][], which also lists some other workarounds.)

[#10520]: https://github.com/rust-lang/rust/issues/10520

### Draft RFC

The Draft RFC is almost complete. I've created
[a GitHub repository][nll-rfc] containing the text. I've also opened
issues with some of the things I wanted to get done before posting it,
though the descriptions are vague and it's not clear that all of them
are necessary. If you're interested in helping out -- please, read it
over! Open issues on things that you find confusing, or open PRs with
suggestions, typos, whatever. I'd like to make this RFC into a group
effort.

### The prototype

The other thing that I'm pretty excited about is that I have a
[working prototype of these ideas][proto]. The prototype takes as
input individual `.nll` files, each of which contains a few struct
definitions as well as the control-flow graph of a single function.
The tests are aimed at demonstrating some particular scenario. For
example, the [`borrowck-walk-linked-list.nll`][bwll] test covers the
"reference overwrites" that I was talking about earlier. I'll go over
it in some detail to give you the idea.

[bwll]: https://github.com/nikomatsakis/nll/blob/724156e86236052fb6c483e2359d99c47dd29dc7/test/borrowck-walk-linked-list.nll

The test begins with struct declarations. These are written in a
*very* concise form because I was too lazy to make it more
user-friendly:

```rust
struct List<+> {
  value: 0,
  successor: Box<List<0>>
}

// Equivalent to:
// struct List<T> {
//   value: T,
//   successor: Box<List<T>>
// }
```

As you can see, the type parameters are not named. Instead, we specify
the variance (`+` here means "covariant"). Within the function body,
we reference type parameters via a number, counting backwards from the
end of the list. Since there is only one parameter (`T`, in the Rust
example), then `0` refers to `T`.

(In real life, this struct would use `Option<Box<List<T>>>`, but the
prototype
[doesn't model enums yet](https://github.com/nikomatsakis/nll/issues/8),
so this is using a simplified form that is "close enough" from the
point-of-view of the checker itself. We also
[don't model raw pointers yet](https://github.com/nikomatsakis/nll/issues/10).
PRs welcome!)

After the struct definitions, there are some `let` declarations,
declaring the global variables:

```rust
let list: &'list mut List<()>;
let value: &'value mut ();
```

Perhaps surprisingly, the named lifetimes like `'list` and `'value`
correspond to **inference variables**. That is, they are not like
named lifetimes in a Rust function -- which are the one major thing
I've yet to implement -- but rather correspond to inference
variables. Giving them names allows for us to add "assertions" (we'll
see one later) that test what results got inferred. You can also use
`'_` to have the parser generate a unique name for you if you don't
feel like giving an explicit one.

After the local variables, comes the control-flow graph declarations,
as a series of basic-block declarations:

```
block START {
    list = use();
    goto LOOP;
}
```

Here, `list = use()` means "initialize `list` and use the (empty) list
of arguments". I'd like to improve this to support
[named function prototypes](https://github.com/nikomatsakis/nll/issues/60),
but for now the prototype just has the idea of an 'opaque use'. Basic
blocks can optionally have successors, specified using `goto`.

One thing the prototype understands pretty well are borrows:

```
block LOOP {
    value = &'b1 mut (*list).value;
    list = &'b2 mut (*list).successor.data;
    use(value);
    goto LOOP EXIT;
}
```

An expression like `&'b1 mut (*list).value` borrows `(*list).value`
mutably for the lifetime `'b1` -- note that the lifetime of the borrow
itself is independent from the lifetime where the reference ends
up. Perhaps surprisingly, the reference can have a *bigger* lifetime
than the borrow itself: in particular, a single reference variable may
be assigned from multiple borrows in disjoint parts of the graph.

Finally, the tests support two kinds of assertions. First, you can
mark a given line of code as being "in error" by adding a `//!`
comment. There isn't one in this example, but you can see them
[in other tests][err]; these identify errors that the borrow checker
would report. We can also have **assertions** of various kinds. These
check the output from lifetime inference. This test has a single
assertion:

[err]: https://github.com/nikomatsakis/nll/blob/724156e86236052fb6c483e2359d99c47dd29dc7/test/borrowck-read-struct-containing-shared-ref-whose-referent-is-borrowed.nll#L11

```
assert LOOP/0 in 'b2;
```

This assertion specifies that the point `LOOP/0` (that is, the start
of the loop) is contained within the lifetime `'b2` -- that is, we
realize that the reference produced by `(*list).successor.data` may
still be in use at `LOOP/0`. But note that this does not prevent us
from reassigning `list` (nor borrowing `(*list).successor.data`). This
is because the new borrow checker is smart enough to understand that
`list` has been reassigned in the meantime, and hence that the borrows
from different loop iterations do not overlap.

### Conclusion and how you can help

I think the NLL proposal itself is close to being ready to submit -- I
want to add a section on named lifetimes first, and add them to the
prototype -- but there is still lots of interesting work to be
done. Naturally, reading and improving the RFC would be
useful. However, I'd also like to improve the prototype. I would like
to see it evolve into a more complete -- but simplified -- model of
the borrow checker, that could serve as a good basis for analyzing the
Rust type system and investigating extensions. Ideally, we would merge
it with chalk, as the two complement one another: **put together, they
form a fairly complete model of the Rust type system** (the missing
piece is the initial round of type checking and coercion, which I
would eventually like to model in chalk anyhow). If this vision
interests you, please reach out! I have open issues on both projects,
though I've not had time to write in tons of details -- leave a
comment if something sparks your interest, and I'd be happy to give
more details and mentor it to completion as well.

### Questions or comments?

[Take it to internals!](https://internals.rust-lang.org/t/non-lexical-lifetimes-draft-rfc-prototype/5527)

#### Appendix: What the proposal won't fix

I also want to mention a few kinds of borrow check errors that the
current RFC will **not** eliminate -- and is not intended to. These
are generally errors that cross procedural boundaries in some form or
another.  For each case, I'll give a short example, and give some
pointers to the current thinking in how we might address it.

**Closure desugaring.** The first kind of error has to do with the
closure desugaring. Right now, closures always capture local
variables, even if the closure only uses some sub-path of the variable
internally:

```rust
let get_len = || self.vec.len(); // borrows `self`, not `self.vec`
self.vec2.push(...); // error: self is borrowed
```

This was discussed on [an internals thread][tc]; as I
[commented there][cc], I'd like to fix this by making the closure
desugaring smarter, and I'd love to mentor someone through such an
RFC! However, it is out of scope for this one, since it does not
concern the borrow check itself, but rather the details of the closure
transformation.

[tc]: https://internals.rust-lang.org/t/borrow-the-full-stable-name-in-closures-for-ergonomics/5387
[cc]: https://internals.rust-lang.org/t/borrow-the-full-stable-name-in-closures-for-ergonomics/5387/11?u=nikomatsakis

**Disjoint fields across functions.** Another kind of error is when
you have one method that only uses a field `a` and another that only
uses some field `b`; right now, you can't express that, and hence
these two methods cannot be used "in parallel" with one another:

```rust
impl Foo {
  fn get_a(&self) -> &A { &self.a }
  fn inc_b(&mut self) { self.b.value += 1; }
  fn bar(&mut self) {
    let a = self.get_a();
    self.inc_b(); // Error: self is already borrowed
    use(a);
  }
}
```

The fix for this is to refactor so as to expose the fact that the methods
operate on disjoint data. For example, one can factor out the methods into
methods on the fields themselves:

```rust
fn bar(&mut self) {
  let a = self.a.get();
  self.b.inc();
  use(a);
}
```

This way, when looking at `bar()` alone, we see borrows of `self.a`
and `self.b`, rather than two borrows of `self`. Another technique is
to introduce "free functions" (e.g., `get(&self.a)` and `inc(&mut
self.b)`) that expose more clearly which fields are operated upon, or
to inline the method bodies. I'd like to fix this, but there are a lot
of considerations at play: see
[this comment on an internals thread][cpb] for my current thoughts. (A
similar problem sometimes arises around `Box<T>` and other smart
pointer types; the desugaring leads to rustc being more conservative
than you might expect.)

[cpb]: https://internals.rust-lang.org/t/partially-borrowed-moved-struct-types/5392/2

**Self-referential structs.** The final limitation we are not fixing
yet is the inability to have "self-referential structs". That is, you
cannot have a struct that stores, within itself, an arena and pointers
into that arena, and then move that struct around. This comes up in a
number of settings.  There are various workarounds: sometimes you can
use a vector with indices, for example, or
[the `owning_ref` crate](https://crates.io/crates/owning_ref). The
latter, when combined with [associated type constructors][ATC], might
be an adequate solution for some uses cases, actually (it's basically
a way of modeling "existential lifetimes" in library code). For the
case of futures especially, [the `?Move` RFC][?Move] proposes another
lightweight and interesting approach.

[?Move]: https://github.com/rust-lang/rfcs/pull/1858

<!-- links -->

[nll-rfc]: https://github.com/nikomatsakis/nll-rfc/
[proto]: https://github.com/nikomatsakis/nll/
[ATC]: https://github.com/rust-lang/rfcs/pull/1598
