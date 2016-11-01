---
layout: post
title: "Imagine never hearing the phrase 'aliasable, mutable' again"
date: 2012-11-18 16:20
comments: true
categories: [Rust]
---

I've been thinking of a radical change we could make to the treatment
of mutability and borrowed pointers in Rust.  The goal is to eliminate
all of the error messages about "aliasable, mutable data" that the
borrow checker currently issues.  The idea is somewhat inspired by
writing a recent paper on Rust's current system---writing a paper on
something never fails to get me thinking about how to improve it,
though it sometimes fails to stimulate ideas which are actually
*good*---and also somewhat inspired by recent conversations on IRC and
in person.

The core of the idea is to build on a tradeoff that is already present
in Rust: static control and safety vs convenience.  Today, when it
comes to managing the heap, Rust programmers can opt for owned
pointers (`~`), which offer great control but also require a careful
coding style, or they can opt for managed pointers (`@`) which cede
control to the garbage collector in exchange for simplicity.  The
problem is that `@` pointers, due to their aliasable nature, actually
become *more complex to use* when combined with the borrow checker (at
least in some ways).

The summary, for the impatient who are already familiar with Rust, is
that borrow checking on an `@mut` value would be *dynamically checked*
(effectively building the `Mut<T>` wrapper into the language).  In
short, borrow checking on local variables would be static and borrow
checking on managed values would be dynamic.

<!-- more -->

### The problem situation

I've explained the problem with `@` pointers and mutability as best as
I will probably ever be able to
[over in the borrowed pointer tutorial][bpt]. The crux of the problem,
however, is that sometimes you have mutable data that must not be
mutated for some short time in order to guarantee safety.  A common
example [involves enums][bpt-enum].  Imagine this:

    struct SomeType {...}
    fn get_some_value(opt_v: @mut Option<SomeType>) -> SomeOtherType {
        match *opt_v {
            None => {
                return default_value();
            }
            Some(ref v) => {
                return v.compute_some_value();
            }
        }
    }

The interesting part here is the `ref v` declaration, which declares
`v` as a pointer into `*opt_v`.  That is, it's a pointer into the
inside of the `Option<>`.  Now, of course, if `v.compute_some_value()`
were to somehow execute `*opt_v = None`---which it could, since
`opt_v` is aliasable and mutable---then this pointer `v` would be
invalidated.  In other words, the pointer `v` only remains valid if
`*opt_v` is never mutated!

If `opt_v` were not an `@` pointer, this is less of an issue, because
the compiler can track and see if anyone is mutating `opt_v` directly.
But because `opt_v` is an `@` pointer, it is *aliasable*, meaning that
there can be other ways to reach `opt_v` that the compiler does not
know about.

### The current solutions: `pure` and `Mut<>`

Currently there are two ways to handle the situation of an aliasable,
mutable value that must be immutable.  One is to use only
[pure code][bpt-purity], which basically means "code that doesn't
mutate anything it doesn't own".  This means that the code cannot
mutate *any* other `@` boxes, which is quite extreme.  It permits a
surprising amount of code, but it also rules out a *lot* of perfectly
valid programs.

The other alternative is to replace something like `@mut T` with
`@Mut<T>`.  `Mut<T>` is a type that I added sometime back to the core
library that allows you to dynamically check borrows.  Each instance
of `Mut<T>` encapsulates a value of type `T`.  You cannot access this
value except through three methods: `borrow_imm()`, `borrow_mut()`,
and `borrow_const()`.  Each takes a closure as argument.  They will
invoke the closure with a borrowed pointer to the encapsulated data,
but with different mutability qualifiers.  The `Mut<T>` type
dynamically checks that the closure provided to `borrow_imm()` never
invokes `borrow_mut()`.  In other words, it checks dynamically that
you never request mutability during an immutable period.  This is
precisely the same guarantee that the borrow checker gives you, but
made dynamic.

The `Mut<T>` interface is not intended to be used directly, but rather
as a building block for wrapping another interface.  Take, for example,
an interface `Map<K,V>` for hashmaps:

    trait Map<K,V> {
        fn insert(&mut self, k: K, v: V);
        fn get(&self, k: &K) -> &self/V;
        ...
    }
    
This interface states that to insert a key into a map, you must have
mutable access, but to get the value from the map, it must be
immutable.  `get()` can therefore return a pointer directly into the
map itself with no need to copy the value.  This scheme relies on the
borrow checker to freeze the map so long as the value returned from
`get()` is in use.  This works great for maps stored in local
variables but does not work for a managed map like `@mut Map<K,V>`,
since the borrow checker doesn't know if there any other aliases to
the same map.

Better than `@mut Map<K,V>`, then, would be something like `@Mut<Map<K,V>>`.
We could then define an `impl` that looks something like:

    impl<M: Map<K,V>> Mut<M>: Map<K,V> {
        fn insert(&mut self, k: K, v: V) {
            self.borrow_mut(|m| m.insert(k, v))
        }
        fn get(&self, k: K, v: V) {
            self.borrow_imm(|m| m.insert(k, v))
        }
        ...
    }
    
This would allow you to have an `@Mut<Map<K,V>>` instance that can be
used like a map but where borrows are dynamically checked.  We'd
probably want to typedef this name to something like `DMap<K,V>` or,
as pcwalton and I have pondered, have parallel modules, so it'd be
more like `@dynamic::Map` where `dynamic` is the module for
dynamically checked collections.

What I like about this setup is that you can get either static or
dynamic checking, as you like.  Static checking is great when the map
is owned by a specific data structure or a function. Dynamic checking
is ultimately most appropriate when you want to share a map amongst
many data structures; in other words, with managed data.

The main thing that I *don't* like about this system is that, for
mutable data structures in managed data, `Mut<>` is almost certainly
what you want, but it takes a lot of work to "opt-in" to using it.
For example, you have to create an `impl` for your trait (like the one
I showed for `Map<K,V>` above).

### The key idea: make `@mut` dynamically checked

I have for a while been toying with the idea of building `Mut<>` into
the language, but I wasn't sure how to do it.  Recently it occurred to
me that we could just connect it with `@mut`.  Today, an `@mut`
pointer means a pointer that you can *definitely* mutate, presuming
that your current function is not pure.  In my proposed world, an
`@mut` pointer would be one that you can *maybe* mutate, presuming
nobody has frozen it.

The idea is to add an extra bit (actually two, see next section) to
each `@mut` box that indicates whether its contents are frozen (there
are plenty of free bits lying around in the header).  This bit would
start off as false.  Whenever you try to mutate the contents of an
`@mut` box, the compiler would dynamically assert that the bit is
false (i.e., the box is not frozen), and fail if it were true.

Now, intead of getting an error when you immutably borrow the contents
of an `@mut` box, the compiler will just set the bit to true for the
duration of the borrow.  This basically shifts the error from being
statically checked to dynamically checked.  This is (sort of) akin to
the way that the compiler automatically roots `@` pointers to keep
them live as long as you have a reference to the inside (but
different, of course, as it might cause dynamic failure).

Note that as long as you avoid `@`, you still get a purely static
check with zero overhead, just as you get well-defined memory
management.

#### Make `&mut` take temporary ownership

To really ensure that things are convenient to use, we need to make a
change to how an `&mut` pointer works.  Today, an `&mut` pointer is
basically the same as C: a pointer that can be freely copied and
aliased.  Moreover, the contract with `&mut` is the same as `@mut`: a
value that you can write whenever you please.  But this leads to the
same problem as `@mut`: you have aliasable, mutable data and thus the
borrow checker is forced to make overapproximations that can be
limiting.

So my idea is to change the semantics of `&mut` to say that an `&mut`
pointer is guaranteed to be *the only way to mutate the thing that it
points at*.  In fact, if we eliminate `const` (as I propose later),
then we could go further and say that an `&mut` pointer is *the only
pointer pointing at the thing that it points at*.  As with all borrow
checker guarantees, this guarantee would be achieved statically if the
pointer points into the stack and dynamically if the pointer points at
managed data.

Since we now know that the `&mut` pointer is the only way to mutate
the data it points at, the borrow checker can treat these values as if
they were owned/unique pointers, in a way.  So in particular it can
permit them to be frozen temporarily and so forth.  In effect, an
`&mut` pointer would be the same as
[the `&restrict` pointers I discussed in a previous blog post][restrict].

The primary effect of this, I believe, would be to eliminate all kinds
of annoying borrow check errors.  However some things that are legal
today would become illegal:

1. Mutable borrows (`&mut expr`) make the borrowed value *inaccessible*
   for the duration of the borrow.  No kind of borrow has this effect
   today.
2. Mutable borrowed pointers (`&mut T`) would be *non-copyable* types,
   though you could re-borrow their contents on function calls.

#### Borrowed values become inaccessible

Today if I borrow a value, the original always remains accessible,
though perhaps in limited capacity (no moves, perhaps no writes).  In
this new world, though, making a mutable borrow of a local variable,
like `&mut x`, would cause `x` to become inaccessible.  The permission
to access `x` is essentially moved into the `&mut` reference
(fractional permissions, anyone?).  I think this is basically ok: the
only reason to take a mutable reference to a local variable is to pass
it to another procedure anyhow, and once the procedure returns you
have your variable back.

Mutable borrows of managed data would work in a similar way, but it
would be checked dynamically.  So if `m` is a managed pointer, then
`&mut *m` would cause `m` to be marked as *inaccessible*, meaning no
reads or writes are permitted through `m` (or any alias of `m`, except
the new borrowed pointer).  This implies that we would need two bits
in the header of each managed box (rather than the one bit I said
earlier), because a managed box can have three states: *unclaimed*,
*immutable*, *const*.  An *unclaimed* managed box is one that is not
borrowed in any way; this is the initial state.  An *immutable*
managed box means that there exists an immutable `&T` reference to the
interior, and hence the contents cannot be mutated.  Finally, a
*const* box means that there exists a `&mut T` reference, and hence
the contents of the box can be read but not written or frozen.  The
reason that mutation is not allowed is that mutation must happen
through the `&mut T` reference. This state would be managed by code
inserted by the compiler automatically when borrows occur, exactly as
the compiler now inserts temporary values to root managed boxes.

#### `&mut` is non-copyable

If we are to retain the invariant that an `&mut` pointer is the only
way to mutate the data that it points at, then `&mut` pointers clearly
cannot be copied.  So they must become non-copyable.  This fits in
with the general precedent in Rust that mutable things are not
(implicitly) copyable.  There is one case I foresee being annoying,
however, though it is easily rectified.  Imagine a situation where you
have a mutable pointer and you wish to pass it to a helper function,
as shown here:

    fn foo(result: &mut int, ...) {
        helper(result, ...);
        helper(result, ...);
        helper(result, ...);

        fn helper(result: &mut int, ...) {
            *result += ...;
        }
    }
    
Presuming we adopt the [moves based on types][mbt] proposal (as seems
likely), this program would be in error, because the call to
`helper()` would in fact *move* `result` value into `helper()` in the
first call, and hence `result` would be inaccessible for the second
call.  The program could legally be written by 're-borrowing' `result`:

    fn foo(result: &mut int, ...) {
        helper(&mut *result, ...);
        helper(&mut *result, ...);
        helper(&mut *result, ...);

        fn helper(result: &mut int, ...) {
            *result += ...;
        }
    }
    
In this case, `result` would be made inaccessible for the duration of
the re-borrow, but that's harmless.  Still this is ugly and
surprising.  To make it less surprising, we could easily say that
`&mut` values are automatically re-borrowed, just as we automatically
borrow an `@` to an `&` pointer in a function call.

#### General thoughts on `&mut`

This change to `&mut` is the part I am least comfortable with.  It's
hard to explain and feels more complex, in a way.  The rule that
`&mut` values are re-borrowed in function calls is ad-hoc.  That said,
I see many benefits.  For example, I think knowing that each `&mut`
pointer is the *only* pointer to the data in question is generally
good and will help to maintain invariants.  You don't have to consider
the possibility that the data which you are mutating may also be
changed through an alias.

In any case, I don't see an attractive alternative.  If we want to
eliminate `&mut` as a source of borrow check errors, the only other
option I see is to (1) do not statically check borrows *at all*, even
for local variables, and (2) make `&` pointers in fact not just a C
pointer but rather a pair of pointers, where one of those pointers
points at the "borrow tracking bits".  This is because a pointer into
the middle of a struct (say at some mutable field) would need to have
a separate pointer indicating where the bits are that control whether
that field is frozen or not.  I find both (1) and (2), but especially
(1), very unappealing.

#### What about `&T`?

You might wonder if we should make `&T` (immutable borrowed pointer)
non-copyable as well, for consistency.  We could certainly do this,
though there seems to be no good reason to do so *at the moment*.
Immutable data can be freely aliased as much as you like, so making
the type non-copyable just adds inconvenience with no additional
safety.  The only reason I can see to do it is if it would make it
easier to explain how borrowed pointers work, but I think that saying
"borrowed pointers are non-copyable" is not really better than saying
"mutable borrowed pointers are non-copyable".

### Other changes

If we did take this direction, I think it also makes sense to make a
some other simplifications:

- remove `mut` declarations from fields and `~` pointers;
- remove purity;
- remove `const` (maybe);
  
I'll go over each of these briefly and outline why I think it makes sense.

#### Remove `mut` from fields and `~` pointers

The idea here is to limit mut declarations to the "top-level" of a
data structure.  Essentially mutability qualifiers would decorate the
*owning reference* for each data structure, which is always either a
local variable (`let mut`) or a managed value (`@mut`).  In terms of
the implementation, this means we can pick the extra data for tracking
whether something is frozen into the `@mut` header.  As a bonus, the
notion of a "freezable" type gets simplified: a freezable type is just
a sendable type.

If we allowed `mut` decls on fields or `~mut`, they could never be
dynamically tracked because we'd have to insert extra bits into the
field declaration or something like that.

#### Remove purity

If we made this change, we would not need the notation of purity
anymore.  The only reason we ever needed purity was to allow immutable
borrowing of aliasable, mutable data, and this proposal makes borrows
of aliasable, mutable data a non-issue: `&mut` pointers would no
longer be aliasable, and borrowing of `@mut` pointers would be checked
dynamically.

#### Remove `const`

In a world where everything is easily freezable, I think `const` is
basically unnecessary.  Just take `&T` if you want to only read and
`&mut T` if you want to change.  The contract is relatively simple: if
you are reading, no one is writing, and if you are writing, no one
else is reading (or writing).  However, you could imagine scenarios
where it makes sense to have a "read-only" pointer to data that
someone else might be writing, and we could keep `&const` and `@const`
pointers easily enough.

Removing `&const` also means that an `&mut` pointer is guaranteed to
be the only way to *access* the data it points at, which is stronger
than saying it is the only way to *mutate* the data it points at.
This is a nice invariant overall.  Who knows, it might even come in
handy for the type system, since if you are guaranteed to be the only
one who can even *read* a certain piece of data, you can temporarily
change its type and do other things without fear of violating type
safety.  Not that I have any concrete idea along these directions.

### Commentary and parting thoughts

I think this change is worth exploring.  It's largely backwards
compatible.  It would codify what appears to be best practice and make
the borrow checker a much less prominent part of people's experience
when using Rust.

There is some runtime cost to this proposal.  Writes and borrows from
managed boxes incur a dynamic check, though reads do not.  If we keep
`const` borrows, they also would not incur a runtime penalty.  But
these costs are only incurred for managed data, and it seems quite
possible that with a more advanced GC we might need a write barrier
anyway.  Perhaps this check could be rolled together with that.

There is little loss to the "safety" of Rust, perhaps even a gain.
Everything is the same except for `@mut T`, which effectively becomes
`@Mut<T>` in today's terms.  But `@mut T` is already nonworkable for
non-scalar T types so I suspect `@Mut<T>` to be far more common.

As far as the "complexity" of the system, I think things become
simpler overall: there are fewer rules governing mutability; you only
reason about mutability at the level of an entire data structure.
Purity and its associated rules are gone.  `const` might be gone.  You
never need to understand what the phrase "alisable, mutable" means.

The one place that does not seem simpler to me is `&mut`, which would
now mean "the *only* mutable reference to the data in question" rather
than "*a* mutable reference to the data in question".  But it's not
clear to me if this is really more complex, it might just be
different. Moreover, it removes the need to think carefully about
aliases when you have multiple mutable values, so it might even work
out simpler overall.

So yes I'm bullish, but more thought and experimentation is certainly
needed.

[bpt]: http://dl.rust-lang.org/doc/tutorial-borrowed-ptr.html#borrowing-unique-boxes
[restrict]: {{ site.baseurl }}/blog/2012/10/24/restrict-pointers/
[mbt]: {{ site.baseurl }}/blog/2012/10/01/moves-based-on-type/
[bpt-enum]: http://dl.rust-lang.org/doc/tutorial-borrowed-ptr.html#borrowing-and-enums
[bpt-purity]: http://dl.rust-lang.org/doc/tutorial-borrowed-ptr.html#purity
