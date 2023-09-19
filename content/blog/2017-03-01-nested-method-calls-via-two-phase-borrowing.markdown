---
layout: post
title: Nested method calls via two-phase borrowing
categories: [Rust, NLL]
---

In my previous post, I
[outlined a plan for non-lexical lifetimes][NLL]. I wanted to write a
follow-up post today that discusses different ways that we can extend
the system to support nested mutable calls. The ideas here are based
on some the ideas that emerged in a
[recent discussion on internals][internals], although what I describe
here is a somewhat simplified variant. If you want more background,
it's worth reading at least the top post in the thread, where I laid
out a lot of the history here. I'll try to summarize the key bits as I
go.

[NLL]: {{< baseurl >}}/blog/2017/02/21/non-lexical-lifetimes-using-liveness-and-location/
[internals]: https://internals.rust-lang.org/t/accepting-nested-method-calls-with-an-mut-self-receiver/4588

### The problem we'd like to solve

*This section is partially copied from the internals post; if you've read
that, feel free to skip or skim.*

The overriding goal here is that we want to accept nested method calls
where the outer call is an `&mut self` method, like
`vec.push(vec.len())`. This is a common limitation that beginners
stumble over and find confusing and which experienced users have as a
persistent annoyance. This makes it a natural target to eliminate as
part of the [2017 Roadmap][roadmap].

[roadmap]: https://github.com/rust-lang/rfcs/blob/master/text/1774-roadmap-2017.md

You may wonder why this code isn't accepted in the first place. To see
why, consider what the resulting MIR looks like (I'm going to number
the statements for later reference in the post):

```rust
/* 0 */ tmp0 = &mut vec;       // mutable borrow starts here.. -+
/* 1 */ tmp1 = &vec; // <-- shared borrow overlaps here         |
/* 2 */ tmp2 = Vec::len(tmp1); //                               |
/* 3 */ Vec::push(tmp0, tmp2); // <--.. and ends here-----------+
```

As you can see, we first take a mutable reference to `vec` for
`tmp0`. This "locks" `vec` from being accessed in any other way until
after the call to `Vec::push()`, but then we try to access it again
when calling `vec.len()`. Hence the error.

When you see the code desugared in that way, it should not surprise
you that there is in fact a real danger here for code to crash if we
just "turned off" this check (if we even could do such a thing). For
example, consider this rather artificial Rust program:

```rust
let mut v: Vec<String> = vec![format!("Hello, ")];
v[0].push_str({ v.push(format!("foo")); "World!" });
//              ^^^^^^^^^^^^^^^^^^^^^^ sneaky attempt to mutate `v`
```

The problem is that, when we desugar this, we get:

```rust
let mut v: Vec<String> = vec![format!("Hello, ")];
// creates a reference into `v`'s current data array:
let arg0: &mut String = &mut v[0];
let arg1: &str = {
    // potentially frees `v`'s data array:
    v.push(format!("foo"));
    "World!"
};
// uses pointer into data array that may have been freed:
String::push_str(arg0, arg1)
```

So, to put it another way, as we evaluate the arguments, we are
creating references and pointers that we will give to the final
function. But evaluating arguments can also have arbitrary
side-effects, which might invalidate the references that we prepared
for earlier arguments. So we have to be sure to rule that out.

In fact, even when the receiver is just a local variable (e.g.,
`vec.push(vec.len())`) we have to be wary. We wouldn't want it to be
possible to give ownership of the receiver away in one of the
arguments: `vec.push({ send_to_another_thread(vec); ... })`. That
should still be an error of course.

(Naturally, these complex arguments that are blocks look really
artificial, but keep in mind that most of the time when this occurs in
practice, the argument is a method or fn call, and that could in
principle have arbitrary side-effects.)

### How can we fix this?

Now, we could address this by changing how we desugar method calls
(and indeed the [original post on the internals thread][internals]
contained two such alternatives). But I am more interested in seeing
if we can keep the current desugaring, but enrich the lifetime and
borrowing system so that it type-checks for cases that we can see
won't lead to a crash (such as this one).

The key insight is that, today, when we execute the mutable borrow of
`vec`, we start a borrow **immediately**, even though the reference
(`arg0`, here) is not going to be used until later:

```rust
/* 0 */ tmp0 = &mut vec;   // mutable borrow created here..
/* 1 */ tmp1 = &vec; // <-- shared borrow overlaps here         |
/* 2 */ tmp2 = Vec::len(tmp1); //                               |
/* 3 */ Vec::push(tmp0, tmp2); // ..but not used until here!
```

The proposal -- which I will call **two-phased mutable borrows** -- is
to modify the borrow-checker so that mutable borrows operate in **two
phases**:

- When an `&mut` reference is first created, but before it is used,
  the borrowed path (e.g., `vec`) is considered **reserved**. A
  reserved path is subject to the same restrictions as a shared borrow
  -- reads are ok, but moves and writes are not (except under a
  `Cell`).
- Once you start using the reference in some way, the path is
  considered **mutably borrowed** and is subject to the usual
  restrictions.

So, in terms of our example, when we execute the MIR statement `tmp0 =
&mut vec`, that creates a **reservation** on `vec`, but doesn't start
the actual borrow yet. `tmp0` is not used until line 3, so that means
that for lines 1 and 2, `vec` is only reserved. Therefore, it's ok to
share `vec` (as line 1 does) so long as the resulting reference
(`tmp1`) is dead as we enter line 3. Since `tmp1` is only used to call
`Vec::len()`, we're all set!

### Code we would not accept

To help understand the rule, let's look at a few other examples, but
this time we'll consider examples that would be rejected as illegal
(both today and under the new rules). We'll start with the example we
saw before that could have trigged a use-after-free:

```rust
let mut v: Vec<String> = vec![format!("Hello, ")];
v[0].push_str({ v.push(format!("foo")); "World!" });
```

We can *partially* desugar the call to `push_str()` into MIR
that would look something like this:

```rust
/* 0 */ tmp0 = &mut v;
/* 1 */ tmp1 = IndexMut::index_mut(tmp0, 0);
/* 2 */ tmp2 = &mut v;
/* 3 */ Vec::push(tmp2, format!("foo"));
/* 4 */ tmp3 = "World!";
/* 5 */ Vec::push_str(tmp1, tmp3);
```

In one sense, this example turns out to be not that interesting in
terms of the new rules. This is because `v[0]` is actually an
overloaded operator; when we desugar it, we see that `v` would be
reserved on line 0 and then (mutably) borrowed starting on line 1.
This borrow extends as long as `tmp1` is in use, which is to say, for
the remainder of the example. Therefore, line 2 is an error, because
we cannot have two mutable borrows at once.

However, in another sense, this example is very interesting: this is
because it shows how, while the new system is more expressive, it
preserves the existing behavior of safe abstractions. That is,
[the `index_mut()` method][indexmut] has a signature like:

[indexmut]: https://doc.rust-lang.org/std/ops/trait.IndexMut.html#tymethod.index_mut

```rust
fn index_mut(&mut self) -> &mut Self::Output
```

Since calling this method is going to "use" the receiver, and hence
activate the borrow, the method is guaranteed that as long as its
return value is in use, the caller will not be able to access the
receiver. This is precisely how it works today as well.

The next example is artificial but inspired by one that is covered
in my original post to the internals thread:

```rust
/*0*/ let mut i = 0;
/*1*/ let p = &mut i; // (reservation of `i` starts here)
/*2*/ let j = i;      // OK: `i` is only reserved here
/*3*/ *p += 1;        // (mutable borrow of `i` starts here, since `p` is used)
/*4*/ let k = i;      // ERROR: `i` is mutably borrowed here
/*5*/ *p += 1;       
      // (mutable borrow ends here, since `p` is not used after this point)
```

This code fails to compile as well. What happens, as you can see in
the comments, is that `i` is considered *reserved* during the first
read, but once we start using `p` on line 3, `i` is considered
borrowed. Hence the second read (on line 4) results in an
error. Interestingly, if line 5 were to be removed, then the program
would be accepted (at least once we move to [NLL]), since the borrow
only extends until the last use of `p`.

The final example shows that this analysis doesn't permit **any** kind
of nesting you might want. In particular, for better or worse, it does
not permit calls to `&mut self` methods to be nested inside of a call
to an `&self` method. This means that something like
`vec.get({vec.push(2); 0})` would be illegal. To see why, let's check
out the (partial) MIR desugaring:

```rust
/* 0 */ tmp0 = &vec;
/* 1 */ tmp1 = &mut vec;
/* 2 */ Vec::push(tmp1, 2);
/* 3 */ Vec::get(tmp0, 0);
```

Now, you might expect that this would be accepted, because the borrow
on line 0 would not be active until line 3. But this isn't quite
right, for two reasons.  First, as I described it, only mutable
borrows have a reserve/active cycle, shared borrows start right
away. And the reason for this is that **when a path is reserved, it
acts the same as if it had been shared**. So, in other words, even if
we used two-phase borrowing for shared borrows, it would make no
difference (which is why I described reservations as only applying to
mutable borrows). At the end of the post, I'll describe how we could
-- if we wanted -- support examples like this, at the cost of making
the system slightly more complex.

### How to implement it

The way I envision implementing this rule is part of borrow check.
Borrow check is the final pass that executes as part of the compiler's
safety checking procedure. In case you're not familiar with how the
compiler works, Rust's safety check is done using three passes:

- Normal type check (like any other language);
- Lifetime check (infers the lifetimes for each reference, as described in [my previous post][NLL]);
- Borrow check (using the lifetimes for each borrow, checks that all uses are acceptable,
  and that variables are not moved).

#### How borrow check would work before this proposal

Before two-phase borrows, then, the way the borrow-check would begin
is to iterate over every borrow in the program. Since the lifetime
check has completed, we know the lifetimes of every reference and
every borrow. In MIR, borrows always look like this:

```rust
var = &'lt mut? lvalue;
  //   ^^^ ^^^^
  //   |   |
  //   |   distinguish `&mut` or `&` borrow
  //   lifetime of borrow
```

This says "borrow `lvalue` for the lifetime `'lt`" (recall that, under
NLL,
[each lifetime is a set of points in the MIR control-flow graph][wil]). So
we would go and, for each point in `'lt`, add `lvalue` to the list of
borrowed things at that point.  If we find that `lvalue` is already
borrowed at that point, we would check that the two borrows are
compatible (both must be shared borrows).

At this point, we now have a list of what is borrowed at each point in
the program, and whether that is a shared or mutable borrow. We can then
iterate over all statements and check that they are using the values in
a compatible way. So, for example, if we see a MIR statement like:

    k = i // where k, i are integers
    
then this would be illegal if `k` is borrowed in any way (shared or
mutable).  It would also be illegal if `i` is mutably borrowed.
Similarly, it is an error if we see a move from a path `p` when `p` is
borrowed (directly or indirectly). And so forth.

#### Supporting two-phases

To support two-phases, we can extend borrow-check in a simple way.
When we encounter a mutable borrow:

    var = &'lt mut lvalue;

we do not go and immediately mark `lvalue` as borrowed for all the
points in `'lt`. Instead, we find the points `A` in `'lt` where the
borrow is **active**. This corresponds to any point where `var` is
used and any point that is reachable from a use (this is a very simple
inductive definition one can easily find with a data-flow
analysis). For each point in `A`, we mark that `lvalue` is mutably
borrowed. For the points `'lt - U`, we would mark `lvalue` as merely
*reserved*. We can then do the next part of the check just as before,
except that anywhere that an lvalue is treated as reserved, it is
subject to the same restrictions as if it were shared.

### Comparing to other approaches

There have been a number of proposals aimed at solving this same
problem.  This particular proposal is, I believe, a new variant, but
it accepts a similar set of programs to the other proposals. I wanted
to compare and contrast it a bit with prior ideas and try to explain
why I framed it in just this way.

#### Borrowing for the future.

My own first stab at this problem was using the idea of "borrowing for
the future", [described in the internals thread][internals]. The basic
idea was that the lifetime of a borrow would be inferred **to start on
the first use**, and the borrow checker, when it sees a borrow that
doesn't start immediately, would consider the path "reserved" until
the start. This is obviously very close to what I have presented
here. **The key difference is that here the borrow checker itself
computes the active vs reserved portions of the borrow, rather than
this computation being done in lifetime inference.**

This seems to me to be more appropriate: lifetime inference figures
out how long a given reference is live (may later be used), based on
the type system and its rules. The borrow checker then uses that
information to figure out if the program may cause the reference to be
invalidated.

The formulation I presented here also fits much better with the
[NLL rules][NLL] that I presented previously. This is because it
allows us to keep the rule that when a reference is *live* at some
point P (may be dereferenced later), its lifetime include that point
P. To see what I mean, let's reconsider our original example, but in
the "borrowing for the future" scheme. I'll annotate lifetimes using
braces to describe sets:

```rust
/* 0 */ tmp0 = &{3} mut vec;
/* 1 */ tmp1 = &vec;
/* 2 */ tmp2 = Vec::len(tmp1);
/* 3 */ Vec::push(tmp0, tmp2);
```

Here `tmp0` would have the type `&{3} mut Vec`, but `tmp0` is clearly
live at point 1 (i.e., it will be used later, on line 3). So we would
have to make the [NLL rules][NLL] that I outlined later incorporate a
more complex invariant, one that considers two-phase borrows as a
first-class thing (cue next piece of 'related work' in 1...2...3....).

### Two-phase lifetimes

In the internals thread, arielb1 had [an interesting proposal][ref2]
that they called "two-phase lifetimes". The goal was precisely to take
the "two-phase" concept but incorporate it into lifetime inference,
rather than handling it in borrow checking as I present here. The idea
was to define a type `RefMut<'r, 'w, T>`[^phi] which stands in for a
kind of "richer" `&mut` type.[^unify] In particular, it has two
lifetimes:

[^phi]: arielb1 called it `Ref2Φ<'immut, 'mutbl, T>`, but I'm going to take the liberty of renaming it.
[^unify]: arielb1 also proposed to unify `&T` into this type, but that introduces complications because `&T` are `Copy` but `&mut` are not, so i'm leaving that out too.

- `'r` is the "read" lifetime. It includes every point where the reference
   may later be used.
- `'w` is a subset of `'r` (that is, `'r: 'w`) which indicates the "write" lifetime.
  This includes those points where the reference is actively being written.
 
We can then conservatively translate a `&'a mut T` type into
`RefMut<'a, 'a, T>` -- that is, we can use `'a` for both of the two
lifetimes. This is what we would do for any `&mut` type that appears
in a struct declaration or fn interface. But for `&mut T` types within
a fn body, we can infer the two lifetimes somewhat separately: the
`'r` lifetime is computed just as I described in my
[NLL post][NLL]. But the `'w` lifetime only needs to include those
points where a write occurs. The borrow check would then guarantee
that the `'w` regions of every `&mut` borrow is disjoint from the `'r`
regions of every other borrow (and from shared borrows).

This proposal accepts more programs than the one I outlined. In
particular, it accepts the example with interleaved reads and writes
that we saw earlier. Let me give that example again, but annotation
the regions more explicitly:

```rust
/* 0 */ let mut i = 0;
/* 1 */ let p: RefMut<{2-5}, {3,5}, i32> = &mut i;
//                    ^^^^^  ^^^^^
//                     'r     'w
/* 2 */ let j = i;  // just in 'r
/* 3 */ *p += 1;    // must be in 'w
/* 4 */ let k = i;  // just in 'r
/* 5 */ *p += 1;    // must be in 'w
```

As you can see here, we would infer the write region to be just the
two points 3 and 5. This is precisely those portions of the CFG where
writes are happening -- and not the gaps in between, where reads are
permitted.

#### Why I do not want to support discontinuous borrows

As you might have surmised, these sorts of "discontinuous" borrows
represent a kind of "step up" in the complexity of the system. If it
were vital to accept examples with interleaved writes like the
previous one, then this wouldn't bother me (NLL also represents such a
step, for example, but it seems clearly worth it). But given that the
example is artificial and not a pattern I have ever seen arise in
"real life", it seems like we should try to avoid growing the
underlying complexity of the system if we can.

To see what I mean about a "step up" in complexity, consider how we
would integrate this proposal into lifetime inference. The current
rules treat all regions equally, but this proposal seems to imply that
regions have "roles".  For example, the `'r` region captures the
"liveness" constraints that I described in the original NLL
proposal. Meanwhile the `'w` region captures "activity".

(Since we would always convert a `&'a mut T` type into `RefMut<'a, 'a,
T>`, all regions in struct parameters would adopt the more
conservative "liveness" role to start. This is good because we
wouldn't want to start allowing "holes" in the lifetimes that unsafe
code is relying on to prevent access from the outside. It would
however be possible for type inference to use a `RefMut<'r, 'w ,T>`
type as the value for a type parameter; I don't yet see a way for that
to cause any surprises, but perhaps it can if you consider
specialization and other non-parametric features.)

Another example of where this "complexity step" surfaces came from
[Ralf Jung][rjung]. As you may know, Ralf is working on a
formalization of Rust as part of the [RustBelt project][rb] (if you're
interested, there is video available of a
[great introduction to this work][am] which Ralf gave at the Rust
Paris meetup). In any case, their model is a kind of generalization of
Rust, in that it can accept a lot of programs that standard Rust
cannot (it is intended to be used for assigning types to unsafe code
as well as safe code). The two-phase borrow proposal that I describe
here should be able to fit into that system in a fairly
straightforward way. But if we adopted discontinuous regions, that
would require making Ralf's system more expressive. This is not
necessarily an argument against doing it, but it does show that it
makes the Rust system qualitatively more complex to reason about.

[rb]: http://plv.mpi-sws.org/rustbelt/
[rjung]: https://www.ralfj.de/blog/
[am]: https://air.mozilla.org/rust-paris-meetup-35-2017-01-19/

If all this talk of "steps in complexity" seems abstract, I think that
the most immediate way it will surface is when we try to
**teach**. Supporting discontinous borrows just makes it that much
harder to craft small examples that show how borrowing works. It will
make the system feel more mysterious, since the underlying rules are
indeed more complex and thus harder to "intuit" on your own.

#### Two-phase lifetimes without discontinuous borrows

For a while I was planning to describe a variant on arielb1's proposal
where the write lifetimes were required to be continuous -- in effect,
they would be required to be a suffix of the overall read lifetime;
this would make the proposal roughly equivalent to the current one.
Given that the set of programs that are accepted are the same, this
becomes more a question of **presentation** than anything.

I ultimately settled on the current presentation because it seems
simpler to me. In particular, lifetime inference today is based solely
on **liveness**, which is a "forward-looking property". In other
words, something is live if it may be used **later**. In contrast, the
borrow check today is interested in tracking, at a particular point,
the "backwards-looking property" of whether something has been
borrowed. So adding another "backwards-looking property" -- whether
that borrow has been activated -- fits borrowck quite naturally.[^terminology]

[^terminology]: In more traditional compiler terminology,
                "forwards-looking properties" are ones computed using
                a reverse data-flow analysis, and "backwards-looking
                properties" are those that would be computed by a
                forwards data-flow analysis.

### Possible future extensions

There are two primary ways I see that we might extend this proposal in
the future. The first would be to allow "discontinuous borrows", as I
described in the previous section under the heading "Two-phase
lifetimes".

The other would be to apply the concept of reservations to **all**
borrows, and to loosen the restrictions we impose on a "reserved"
path. In this proposal, I chose to treat reserved and shared paths in
the same way. This implies that some forms of nesting do not work; for
example, as we saw in the examples, one cannot write
`vec.get({vec.push(2); 0})`. These conditions are stronger than is
strictly needed to prevent memory safety violations. We could consider
reserved borrows to be something akin to the old `const` borrows we
used to support: these would permit reads **and** writes of the
original path, but not moves. There are some tricky cases to be
careful of (for example, if you reserve `*b` where `b: Box<i32>`, you
cannot permit people to mutate `b`, because that would cause the
existing value to be dropped and hence invalidate your existing
reference to `*b`), but it seems like there is nothing fundamentally
stopping us. I did not propose this because (a) I would prefer not to
introduce a third class of borrow restrictions and (b) most examples
which would benefit from this change seem quite artificial and not
entirely desirable (though there are exceptions). Basically, it seems
ok for `vec.get({vec.push(2); 0})` to be an error. =)

### Conclusion

I have presented here a simple proposal that tries to address the
"nested method call" problem as part of the NLL work, without
modifying the desugaring into MIR at all (or changing MIR's dynamic
semantics). It works by augmenting the borrow checker so that mutable
borrows begin as "reserved" and then, on first use, convert to active
status. While the borrows are reserved, they impose the same
restrictions as a shared borrow.

In terms of the "overall plans" for NLL, I consider this to be the
second out of a series of three posts that lay out a complete proposal[^overlook]:

- [the core NLL system][NLL], covered in the previous post;
- nested method calls, this post;
- incorporating dropck, still to come.

**Comments?** Let's use [this internals thread for comments][comments].

[comments]: https://internals.rust-lang.org/t/blog-post-nested-method-calls-via-two-phase-borrowing/4886

### Footnotes

[^overlook]: Presuming I'm not overlooking something. =)
[ref2]: https://internals.rust-lang.org/t/accepting-nested-method-calls-with-an-mut-self-receiver/4588/24?u=nikomatsakis
[wil]: {{< baseurl >}}/blog/2017/02/21/non-lexical-lifetimes-using-liveness-and-location/#step-0-what-is-a-lifetime
