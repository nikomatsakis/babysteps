---
layout: post
title: "Focusing on ownership"
date: 2014-05-13 17:04
comments: true
categories: [Rust]
---

Over time, I've become convinced that it would be better to drop the
distinction between mutable and immutable local variables in
Rust. Many people are [highly skeptical][r], to say the least. I
wanted to lay out my argument in public. I'll give various
motivations: a philosophical one, an eductional one, and a practical
one, and also address the main defense of the current system. (Note: I
considered submitting this as a Rust RFC, but decided that the tone
was better suited to a blog post, and I don't have the time to rewrite
it now.)

### Just to be clear

I've written this article rather forcefully, and I do think that the
path I'm advocating would be the right one. That said, if we wind up
keeping the current system, it's not a disaster or anything like that.
It has its advantages and overall I find it pretty nice. I just think
we can improve it.

### One sentence summary

I would like to remove the distinction between immutable and mutable
locals and rename `&mut` pointers to `&my`, `&only`, or `&uniq` (I
don't care). There would be no mut keyword.

<!-- more -->

### Philosophical motivation

The main reason I want to do this is because I believe it makes the
language more coherent and easier to understand. Basically, it
refocuses us from talking about *mutability* to talking about
*aliasing* (which I will call "sharing", see below for more on that).

Mutability becomes a sideshow that is derived from uniqueness: "You
can always mutate anything that you have unique access to. Shared data
is generally immutable, but if you must, you can mutable it using some
kind of cell type."

Put another way, it's become clear to me over time that the problems
with data races and memory safety arise when you have *both* aliasing
and mutability. The functional approach to solving this problem is to
remove mutability. Rust's approach would be to remove aliasing. This
gives us a story to tell and helps to set us apart.

A note on terminology: I think we should refer to *aliasing* as
*sharing*.  In the past, we've avoided this because of its
multithreaded connotations.  However, if/when we implement the
[data parallelism][1] [plans][2] I have proposed, then this
connotation is not at all inappropriate. In fact, given the
[close relationship][3] between memory safety and data races, I
actually *want* to promote this connotation.

### Eductional motivation

I think that the current rules are harder to understand than they have
to be. It's not obvious, for example, that `&mut T` implies no
aliasing. Moreover, the notation `&mut T` suggests that `&T` implies
no mutability, which is not entirely accurate, due to types like
`Cell`. And nobody can agree on what to call them ("mutable/immutable
reference" is the most common thing to say, but it's not quite right).

In contrast, a type like `&my T` or `&only T` seems to make
explanations much easier. This is a *unique reference* -- of course
you can't make two of them pointing at the same place. And
*mutability* is an orthogonal thing: it comes from uniqueness, but
also cells. And the type `&T` is precisely its opposite, a *shared
reference*. [RFC PR #58][58] makes a number of similar arguments. I
won't repeat them here.

### Practical motivation

Currently there is a disconnect between borrowed pointers, which can
be either shared or mutable+unique, and local variables, which are
always unique, but may be mutable or immutable. The end result of this
is that users have to place `mut` declarations on things that are not
directly mutated.

#### Locals can't be modeled using references

This phenomena arises from the fact that references are just not as
expressive as local variables. In general, this hinders abstraction.
Let me give you a few examples to explain what I mean. Imagine I have
an environment struct that stores a pointer to an error counter:

    struct Env { errors: &mut int }

Now I might create this structure (and use it) like so:

    let mut errors = 0;
    let env = Env { errors: &mut errors };
    ...
    if some_condition {
        *env.errors += 1;
    }
    
OK, now imagine that I want to extract out the code that mutates
`env.errors` into a separate function. I might think that, since `env`
is not declared as mutable above, I can use a `&` reference:

    let mut errors = 0;
    let env = Env { errors: &mut errors };
    helper(&env);
    
    fn helper(env: &Env) {
      ...
      if some_condition {
          *env.errors += 1; // ERROR
      }
    }

But that is wrong. The problem is that `&Env` is an aliasable type,
and hence `env.errors` appears in an aliasable location. To make this
code work, I have to declare `env` as mutable and use an `&mut`
reference:

    let mut errors = 0;
    let mut env = Env { errors: &mut errors };
    helper(&mut env);

This problem arises because we know about locals being unique, but we
can't put that knowledge into a borrowed reference without making it
mutable.

This problem arises in a number of other places. Until now, we've
papered over it in a variety of ways, but I continue to feel like
we're papering over a disconnect that just shouldn't be there.

#### Type-checking closures

We had to work around this limitation with closures. Closures are
*mostly* desugarable into structs like `Env`, but not quite. This is
because I didn't want to require that `&mut` locals be declared `mut`
if they are used in closures. In other words, given some code like:

    fn foo(errors: &mut int) {
        do_something(|| *errors += 1)
    }
    
The closure expression will in fact create an `Env` struct like:

    struct ClosureEnv<'a, 'b> {
        errors: &uniq &mut int
    }

Note the `&uniq` reference. That's not something an end-user can type.
It means a "unique but not necessarily mutable" pointer. It's needed
to make this all type check. If the user tried to write that struct
manually, they'd have to write `&mut &mut int`, which would in turn
require that the `errors` parameter be declared `mut errors: &mut
int`.

#### Unboxed closures and procs

I foresee this limitation being an issue for unboxed closures. Let me
elaborate on the design I was thinking of. Basically, the idea would
be that a `||` expression is equivalent to some fresh struct type that
implements one of the `Fn` traits:

    trait Fn<A,R> { fn call(&self, ...); }
    trait FnMut<A,R> { fn call(&mut self, ...); }
    trait FnOnce<A,R> { fn call(self, ...); }

The precise trait would be selected by the expected type, as today. In this
case, consumers of closures can write one of two things:

    fn foo(&self, closure: FnMut<int,int>) { ... }
    fn foo<T:FnMut<int,int>>(&self, closure: T) { ... }
    
We'll ... probably want to bikeshed the syntax, maybe add sugar like
`FnMut(int) -> int` or retain `|int| -> int`, etc. That's not so
important, what matters is that we'd be passing in the closure *by
value*. Note that with current DST rules it is legal to pass in a
trait type by value as an argument, so the `FnMut<int,int>` argument
is legal in DST and not an issue.

*An aside:* This design isn't complete and I will describe the full
details in a separate post.

The problem is that calling the closure will require an `&mut`
reference.  Since the closure is passed by value, users will again
have to write a `mut` where it doesn't seem to belong:

    fn foo(&self, mut closure: FnMut<int,int>) {
        let x = closure.call(3);
    }

This is the same problem as the `Env` example above: what's *really*
happening here is that the `FnMut` trait just wants a *unique*
reference, but since that is not part of the type system, it requests
a *mutable* reference.

Now, we can probably work around this in various ways. One thing we
could do is to have the `||` syntax not expand to "some struct type"
but rather "a struct type or a pointer to a struct type, as dictated
by inference". In that case, the callee could write:

    fn foo(&self, closure: &mut FnMut<int,int>) {
        let x = closure.call(3);
    }
    
I don't mean to say this is the end of the world. But it's one more in
a growing of contortions we have to go through to retain this split
between locals and references.

#### Other parts of the API

I haven't done an exhaustive search, but naturally this distinction
creeps in elsewhere. For example, to read from a `Socket`, I need a
unique pointer, so I have to declare it mutable. Therefore, sometime
like this doesn't work:

    let socket = Socket::new();
    socket.read() // ERROR: need a mutable reference

Naturally, in my proposal, code like this would work fine. You'd still
get an error if you tried to read from a `&Socket`, but then it would
say something like "can't create a unique reference to a shared
reference", which I personally find more clear.

### But don't we need mut for safety?

No, we don't. Rust programs would be equally sound if you just
declared all bindings as mut. The compiler is perfectly capable of
tracking which locals are being mutated at any point in time --
precisely because they are *local* to the current function. What the
type system really cares about is uniqueness.

The value I see in the current mut rules, and I won't deny there is
value, is primarily that they help to declare intent. That is, when
I'm reading the code, I know which variables may be reassigned. On the
other hand, I spend a lot of time reading C++ code too, and to be
honest I've never noticed this as a major stumbling block. (Same goes
for the time I've spent reading Java, JavaScript, Python, or Ruby
code.)

It is also true that I have occasionally found bugs because I declared
a variable as `mut` and failed to mutate it. I think we could get
similar benefits via other, more aggressive lints (e.g., none of the
variables used in the loop condition are mutated in the loop body). I
personally cannot recall having encountered the opposite situation:
that is, if the compiler says something must be mutable, that
basically always means I forgot a `mut` keyword somewhere. (Think:
when was the last time you responded to a compiler error about illegal
mutation by doing anything other than restructuring the code to make
the mutation legal?)

### Alternatives

I see three alternatives to the current system:

1. The one I have given, where you just drop "mutability" and track
   only uniqueness.
2. One where you have three reference types: `&`, `&uniq`, and
   `&mut`. (As I wrote, this is in fact the type system we have today,
   at least from the borrow checker's point of view.)
3. A stricter variant in which "non-mut" variables are always
   considered aliased. That would mean that you'd have to write:

        let mut errors = 0;
        let mut p = &mut errors; // Note that `p` must be declared `mut`
        *p += 1;
    
   You'd need to declare `p` as `mut` because otherwise it'd be
   considered aliased, even though it's a local, and hence mutating
   `*p` would be illegal. What feels weird about this scheme is that
   the local variable is *not* aliased, and we clearly know that,
   since we will allow it to be moved, run destructors on it and so
   forth. That is, we still have a notion of "owned" that is distinct
   from "not aliased".
   
   On the other hand, if we described this system by saying that
   mutability inherits through `&mut` pointers, and not by talking
   about aliasing at all, it might make sense.
   
Of these three, I definitely prefer #1. It's the simplest, and right
now I am most concerned with how we can simplify Rust while retaining
its character. Failing that, I think I prefer what we have right now.

### Conclusions

Basically, I feel like the current rules around mutability have some
value, but they come at a cost. They are presenting a kind of leaky
abstraction: that is, they present a simple story that turns out to be
incomplete. This causes confusion for people as they transition from
the initial understanding, in which `&mut` is how mutability works,
into the full understanding: sometimes `mut` is needed just to get
uniqueness, and sometimes mutability comes without the `mut` keyword.

Moreover, we have to bend over backwards to maintain the fiction that
`mut` means mutable and not unique. We had to add special cases to
borrowck to check closures. We have to make the rules around `&mut`
mutability more complex in general. We have to either add `mut` to
closures so that we can call them, or make closure expressions have a
less obvious desugaring. And so forth.

Finally, we wind up with a more complicated language overall. Instead
of just having to think about aliasing and uniqueness, the user has to
think about both aliasing *and* mutability, and the two are somehow
tangled up together.

I don't think it's worth it.

[1]: http://smallcultfollowing.com/babysteps/blog/2013/06/11/data-parallelism-in-rust/
[2]: http://smallcultfollowing.com/babysteps/blog/2014/02/25/rust-rfc-stronger-guarantees-for-mutable-borrows/
[3]: http://smallcultfollowing.com/babysteps/blog/2013/06/11/on-the-connection-between-memory-management-and-data-race-freedom/
[r]: http://www.reddit.com/r/rust/comments/2581s5/informal_survey_which_is_clearer_mutability_or/
[58]: https://github.com/rust-lang/rfcs/pull/58
