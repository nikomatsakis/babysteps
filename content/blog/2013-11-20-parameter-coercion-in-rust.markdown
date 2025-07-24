---
layout: post
title: "Parameter coercion in Rust"
date: 2013-11-20T11:10:00Z
comments: true
categories: [Rust]
---

Alex Chrichton recently sent a
[message to the rust-dev mailing list][msg] discussing the fate of
parameter coercion in Rust. I've been thinking about this for a while
and feeling conflicted. As is my wont, I decided to try and write up a
blog post explaining precisely what's under debate and exporing the
tradeoffs.

<!-- more -->

## Historical background

In the interest of clarity, I wanted to briefly explain some
terminology and precisely what the rules *are*. I refer to "autoref"
as the addition of an implicit `&`: so converting from `T` to `&T`, in
terms of the type. "Autoderef" is the addition of an implicit `*`:
converting from `&T`, `~T`, etc to `T`. Finally, "autoborrow" is the
addition of both a `&` and a `*`, which effectively converts from
`~T`, `&T` etc to `&T`. "Autoslice" is the conversion from `~[..]` and
`&[...]` to `&[...]` -- if we had a DST-based system, autoslice and
autoborrow would be the same thing, but in today's world they are not,
and in fact there is no explicit syntax for slicing.

Currently we apply implicit transformations in the following circumstances:

- For method calls and field accesses (the `.` operator) and indexing
  (`[]`), we will autoderef, autoref, and autoslice the
  receiver. We're pretty aggressive here, happily autoderefing through
  many layers of indirection.  This means that, in the extreme case,
  we can convert from some nested pointer type like `&&@T` to a type
  like `&T`.
  
- For parameter passing, local variable initializers with a declared
  type, and struct field initializers, we apply *coercion*. This is a
  more limited set of transformations. We could and probably should
  apply coercion in a *somewhat* wider set of contexts, notably return
  expressions.
  
Currently we are specifically referring to what the *coercion* rules
ought to be. Nobody is proposing changing the method lookup behavior.
Furthermore, nobody is proposing removing coercion altogether, just
changing the set of coercions we apply.

### Current coercion rules

The current coercion rules are as follows:

  - Autoborrow from `~T` etc to `&T` or `&mut T`.
    - Reborrowing from `&'a T` to `&'b T`, `&'a mut T` to `&'b mut T`,
      which is a special case. See discussion below.
  - Autoslice from `~[T]`, `&[T]`, `[T, ..N]` etc to `&[T]`
  - Convert from `&T` to `*T`
  - Convert from a bare fn type `fn(A) -> R` to a closure type `|A| -> R`

In addition, I believe that we *should* have the rule that we will
convert from a pointer type `&T` to an object type `&Trait` where
`T:Trait`. I have found that making widespread but non-uniform use of
object types without this rule requires a lot of explicit and verbose
casting.

### Slicing

If we had DST, then slicing and borrowing are the same thing. Without
DST, there is in fact no explicit way to "slice" a vector type like
`~[T]` or `[T, ..N]` into a slice `&[N]`. You can call the `slice()`
method, but that in fact relies on the fact that we will "autoslice" a
method receiver. For vectors like `~[N]` and so on, we could implement
`slice` methods manually, but fixed-length vectors like `[T, ..N]` are
particularly troublesome because there is no way to do such a thing.

### Reborrowing

One of the less obvious but more important coercions is what I call
*reborrowing*, though it's really a special case of autoborrow. The
idea here is that when we see a parameter of type `&'a T` or `&'a mut
T` we always "reborrow" it, effectively converting to `&'b T` or `&'b
mut T`.  While both are borrowed pointers, the reborrowed version has
a different (generally shorter) lifetime. Let me give an example where
this becomes important:

    fn update(x: &mut int) {
        *x += 1;
    }

    fn update_twice(x: &mut int) {
        update(x);
        update(x);
    }
    
In fact, thanks to auto-borrowing, the second function is implicitly
transformed to:

    fn update_twice(x: &mut int) {
        update(&mut *x);
        update(&mut *x);
    }

This is needed because `&mut` pointers are *affine*, meaning that
otherwise the first call to `update(x)` would move the pointer `x`
into the callee, leading to an error during the second call. The
reborrowing however means that we are in fact not moving `x` but
rather a temporary pointer (let's call it `y`). So long as `y` exists,
access to `x` is disabled, so this is very similar to giving `x` away.
However, lifetime inference will find that the lifetime of this
temporary pointer `y` is limited to the first call to `update` itself,
and so after the call access to `x` will be restored. The borrow
checker rules permit reborrowing under the same conditions in which a
move would be allowed, so this transformation never introduces errors.

### Interactions with inference

One interesting aspect of coercion is its interaction with inference.
For coercion rules to make sense, we need to know all the types
involved. But in some cases we are in the process of inferring the
types, and the decision of whether or not to coerce would in fact
affect the results of that inference. In such cases we currently do
not coerce. This can occasionally lead to surprising results. Here is
a relatively simple example:

    fn foo<T>(x: T, y: T) -> T { ... }
    
    fn bar(x: ~U, y: ~U) {
    
        // This would be legal, and would imply that `z` has type `~U`.
        let z = foo::<~U>(x, y);
        
        // This would be legal, because the arguments are autoborrowed,
        // and would imply that `z` has type `&U`.
        let z = foo::<&U>(x, y);
        
        // Here we are inferring value of `T`. Which version is intended?
        let z = foo(x, y);
    
    }
    
Currently, the coercion rules would favor the first intepretation. But
there is ambiguity here. And in more advanced cases, the decision of
whether or not to coerce might depend on peculiarities of our type
inference process. To be honest, though, this rarely seems to be a
problem in practice, though I'm sure it arises.

## What are the complaints about the system?

I'll give my personal take. The current coercion rules date from the
early days of the region system. I did not understand then how Rust
would ultimately be used, nor had we adopted the current mutability
rules. The rules were designed around the idea of *pointers* -- so
they convert between any pointer type to a borrowed pointer. But since
then, I've stopped thinking of `~T` as a pointer type and started
thinking of it as a value type. The choice between `T` and `~T` is
really an efficiency tradeoff; the two types behave similarly in most
respects. Except parameter coercion. Speaking personally, this unequal
treatment of `T` and `~T` is what bothers me the most -- but whether
it should be rectified by making `T` automatically coercable to `&T`
or by disallowing `~T` from being coerced to `&T` is unclear.

An argument in favor of limiting coercion is that it makes it easier
to read and follow a function independent of its callees. For example,
when you see some code like the following, you don't know whether `x`
is moved or autosliced:

    let x = ~[1, 2, 3];
    foo(x); // Does this consume `x`, or auto-slice it?

Automatic coercions also interact in an unfortunate way with inherited
mutability, in that they permit "silent" mutability:

    let mut x = ~[1, 2, 3];
    sort(x); // This mutates x in place
    
The reason that this surprises me is precisely because I've stopped
thinking of a `~[int]` array as a pointer -- in other languages, it
wouldn't surprise me that when I give a pointer to a function, it may
mutate the data that pointer points at. But because I think of a
`~[int]` as a value, I feel like `sort(x)` shouldn't be able to mutate
"the value" `x` without some explicit acknowledgement (e.g.,
`sort(&mut *x)`). (Note that when the rules were first created,
mutability was not inherited, so you would have had to declare `let x
= ~mut [1, 2, 3]`, in which case the fact that `sort` mutates `x`
feels more natural to me.)

When discussing "silent mutability", it's worth pointing out that C++
references make this sort of mutation implicit as well, so it's hardly
without precedent. I've never considered this to be a particularly
good thing, though, even if it can be convenient.

It's also worth pointing out that, whatever change we make, it's not
*actually* possible to reason about a function independently of its
callees, for a variety of reasons: there are still some coercions that
remain; method notation has a number of conveniences including autoref
(with mutation!); type inference might be affected by the parameter
types of a function; and so on. Also, if we had an IDE and not just a
simple emacs mode, of course, autorefs and so on could be indicated
using syntax highlighting. But we don't have an IDE and I wouldn't
consider that likely in the short term. Besides, I dig emacs. ;)

## What are the proposed changes?

The issue discusses two possible changes. We could either *limit*
coercion by removing autoborrowing (but keeping reborrowing), or we
could *expand* coercion by including autoref.

Limiting coercion has appeal because less magic is, all other things
being equal, good. We've been bitten by attempting to be too smart.
It often makes the system harder for new users to understand, since it
makes errors less predictable, and it means that distinct concepts
(like `T` vs `~T`) get muddled together. On the other hand, it makes
it easier to get started, and reduces overhead for advanced users.

Expanding coercion has appeal because it'd lower notational overhead.
This is particularly true around generic types like `HashMap` that make
extensive use of borrowed pointers. For example, to look up a key
in a hash map, one typically writes `map.find(&key)` today. If we
expanded coercion to include autoref, one would write `map.find(key)`,
and the borrow would be implicit.

Independently, we could *tweak* coercion by removing the ability to
autoborrow to an `&mut T` (except from another `&mut T`). This is
probably a good idea.

I am concerned that if we remove autoborrow the notational overhead
will be too large, I am also annoyed that we must keep at least the
autoslicing from fixed-length vectors to slices, since we have no
other way to achieve that. (Unless we added a [slice operator][op], as
discussed in another blog post.) *But* I am very sympathetic to the
less magic angle -- and it's the conservative path as well, since as
we can always add magic back later if it proves to be necessary.

## What should we do?

I think we ought to experiment. It's not too hard to whip up a branch
with the two alternatives and work through the implications. I'm
currently doing the same with more stringent rules around operator
overloading, and the experience has been instructive -- I haven't yet
decided if it's acceptable or not. But that's a topic for another
post.

[msg]: https://mail.mozilla.org/pipermail/rust-dev/2013-November/006849.html
[op]: http://smallcultfollowing.com/babysteps/blog/2013/11/14/treating-vectors-like-any-other-container/
