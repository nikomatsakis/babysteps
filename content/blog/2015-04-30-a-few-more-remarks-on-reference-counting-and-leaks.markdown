---
layout: post
title: "A few more remarks on reference-counting and leaks"
date: 2015-04-30T18:00:05-0700
comments: true
categories: [Rust]
---

So there has been a lot of really interesting discussion in response
to my blog post. I wanted to highlight some of the comments I've seen,
because I think they raise good points that I failed to address in the
blog post itself. My comments here are lightly edited versions of what
I wrote elsewhere.

### Isn't the problem with objects and leak-safe types more general?

[Reem writes][1]:

> I posit that this is in fact a problem with trait objects, not a
  problem with Leak; the exact same flaw pointed about in the blog
  post already applies to the existing OIBITs, Send, Sync, and
  Reflect. The decision of which OIBITs to include on any trait object
  is already a difficult one, and is a large reason why std strives to
  avoid trait objects as part of public types.

I agree with him that the problems I described around `Leak` and
objects apply equally to `Send` (and, in fact, I said so in my post),
but I don't think this is something we'll be able to solve later on,
as he suggests. I think we are working with something of a fundamental
tension. Specifically, objects are all about encapsulation. That is,
**they completely hide the type you are working with**, even from the
compiler. This is what makes them useful: without them, Rust just
plain wouldn't work, since you couldn't (e.g.) have a vector of
closures. **But, in order to gain that flexibility, you have to state
your requirements up front**. The compiler can't figure them out
automatically, because it doesn't (and shouldn't) know the types
involved.

[1]: http://www.reddit.com/r/rust/comments/34bj7z/on_referencecounting_and_leaks_from_nmatsakiss/cqtksn3
[2]: http://www.reddit.com/r/rust/comments/34bj7z/on_referencecounting_and_leaks_from_nmatsakiss/cqtrzi7

So, given that objects are here to stay, the question is whether
adding a marker trait like `Leak` is a problem, given that we already
have `Send`. I think the answer is yes; basically, because we can't
expect object types to be analyzed statically, we should do our best
to minimize the number of fundamental splits people have to work
with. **Thread safety is pretty fundamental. I don't think `Leak`
makes the cut.** (I said some of the reasons in conclusion of my
previous blog post, but I have a few more in the questions below.)

### Could we just remove `Rc` and only have `RcScoped`? Would that solve the problem?

[Original question.](http://smallcultfollowing.com/babysteps/blog/2015/04/29/on-reference-counting-and-leaks/#comment-1994859272)

Certainly you could remove `Rc` in favor of `RcScoped`. Similarly, you
could have only `Arc` and not `Rc`. But you don't want to because you
are basically failing to take advantage of extra constraints. If we
only had `RcScoped`, for example, then creating an `Rc` always
requires taking some scoped as argument -- you can have a global
constant for `'static` data, but it's still the case that generic
abstractions have to take in this scope as argument. Moreover, there
is a runtime cost to maintaining the extra linked list that will
thread through all `Rc` abstractions (and the `Rc` structs get bigger,
as well). So, **yes, this avoids the "split" I talked about, but it
does it by pushing the worst case on all users.**

Still, I admit to feeling torn on this point. **What pushes me over
the edge, I think, is that simple reference counting of the kind we
are doing now is a pretty fundamental thing.** You find it in all
kinds of systems
([Objective C](http://clang.llvm.org/docs/AutomaticReferenceCounting.html),
[COM](https://msdn.microsoft.com/en-us/library/windows/desktop/ms687260%28v=vs.85%29.aspx),
etc). This means that if we require that safe Rust cannot leak, then
you cannot safely integrate borrowed data with those systems. I think
it's better to just use closures in Rust code -- particularly since,
as annodomini points out on Reddit,
[there are other kinds of cases where RAII is a poor fit for cleanup](http://www.reddit.com/r/rust/comments/34bj7z/on_referencecounting_and_leaks_from_nmatsakiss/cqt983d).

### Could a proper GC solve this? Is reference counting really worth it?

[Original question.](http://www.reddit.com/r/rust/comments/34bj7z/on_referencecounting_and_leaks_from_nmatsakiss/cqtpxga)

It'll depend on the precise design, but **tracing GC most definitely
is not a magic bullet**. If anything, the problem around leaks is
somewhat worse: GC's don't give any kind of guarantee about when the
destructor bans. So we either have to ban GC'd data from having
destructors or ban it from having borrowed pointers; either of those
implies a bound very similar to `Leak` or `'static`. Hence I think
that **GC will never be a "fundamental building block" for
abstractions in the way that `Rc`/`Arc` can be**. This is sad, but
perhaps inevitable: GC inherently requires a runtime as well, which
already limits its reusability.
