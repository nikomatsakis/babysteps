---
layout: post
title: "Immutability and iteration"
date: 2012-07-31 08:37
comments: true
categories: [Rust, Mutability]
published: false
---

I am trying to figure out how our APIs should look in light of the
move to a region system.  One of the goals with borrowed pointers was
to make it more evident when you have a pointer and when you
don't---something which reference modes made quite hard to reason
about.  Of course, the fact that modes obscured the use of pointers
also made them nicer to use sometimes.

<!-- more -->

## The problem

## One solution

## Another option



As so often happens, one of the great
weaknesses of modes---that they hid where pointers were being
used---is also one of their greatest strengths.

So I started taking a tiny stab at modifying the map API to remove
modes.  Right now, maps define a method each with a (region-ified)
signature like:

    fn each(op: fn(key: &K, value: &V))

In other words, the callback takes pointers to the keys/values in each
entry.  This is (theoretically) great from an efficiency
point-of-view, and it works with non-copyable keys and values.  

In practice, however, we wind up making copies of the values, at
least.  This is because of the danger of someone modifying the hashmap
during the iteration.  The current situation is fairly suboptimal.  We
pay the full price of a copy but the callee only gets a reference and
hence can't take advantage of that.  However, if we want to allow
internal pointers into the data structure, we have to follow some
rules to make it safe (see below).

So my question is, what do we want to do?  How do want to design the
iteration APIs and what are the implications?  I see two main options.

<!-- more -->

There are actually two orthogonal (but interlinked) concerns.  The
first is, what kind of iteration methods do we want to support?
Currently we have `each()` which is given borrowed pointers; perhaps
we want `each()` and `each_ref()`, where the former iterates "by
value" and the second iterates "by reference".  

To help keep things concrete, I will focus on vector iteration at the
moment, but the same principles apply







## 1. Include "by-value" and "by-pointer" iteration functions

This has certain advantages but doesn't fully solve the problem.  The
API is probably mildly more convenient (fewer pointers) for common use
cases.  Also, it is possible to write "by-value" iterators that do not
require that the structure be fully immutable, though they are
generally less efficient than iterators that can assume immutability.
The reason for that inefficiency is that iterators which assume
immutability can iterate through vectors without bound checks and so
forth.

To see what I mean, let us consider the simple case of iterating over
a vector.  The current vector code basically reads the length once and
uses unsafe pointers to access the actual array elements.  The reason
is can safely do that is because it is actually iterating over a
*slice* `&[T]`.  The type system, right now, guarantees that a slice
`&[T]` will remain valid, which means that the length cannot change.
This in turn requires that the slice must either live in immutable
memory or live on the current stack frame.  Which means that you
cannot iterate over a vector stored in a mutable field of some managed
or borrowed data.  The following function, for example, would fail
because the vector lives in a mutable field of a managed box, and thus
we cannot guarantee that it will remain immutable during the iteration:

    struct record {
        mut f: ~[int]
    }
    fn foo(x: @record) {
        for x.f.each |v| { ... }        // reports an error
    }
    
If, however, we had defined iteration so that it did not rely on
immutability, we could accommodate the above case, but at a
performance cost.  We must re-check the bounds each iteration and we
must copy the values out rather than passing them by pointer.  In
fact, for this to work, the iteration must be defined over vectors and
not just slices: the whole formation of a slice requires a guarantee
that the source vector will not be freed.

So, in summary, we can have "by-value" functions that will operate
over collections in mutable locations, but they will be inherently
less efficient than the "by-pointer" variety.  This also implies that
there will probably be two separate iteration implementations, one
written to take advantage of interior pointers and one not.

## 2. Include only "by-pointer" iteration functions (as today)

This is simpler (fewer iteration functions) and more efficient, but to
do it safely will require following one of two patterns when writing
collection classes.

### 2a. Use managed data more extensively or be careful with mutability

The current hashmap has a linked list per bucket which looks like:

    struct entry<K,V> {
        hash: uint;
        key: K;
        mut value: V;
        mut next: option<@entry<K,V>>
    }
    struct hashmap<K,V> {
        hashfn: pure fn~(key: &K) -> uint;
        eqfn: pure fn~(key1: &K, key2: &K) -> bool;
        mut size: uint;
        mut buckets: ~[option<@entry<K,V>>];
    }

The fact that the value is mutable is what makes it necessary to copy
the value when iterating.  The reason is that the `each()` function
expects an `&V`—in other words, a pointer to an immutable `V`.  What
we have is of course `&mut v`.  No good.

This could be fixed in one of two ways.  First, we could make the
value field immutable.  This would make it less efficient to update an
existing entry in the map.  Second, we could change the value field to
have type `@V`.  This would mean that the `&V` pointer would in fact
be borrowing the immutable managed box, which is fine.

This approach is nice but it has a big downside: it doesn't work for
structures that eschew managed data.  This is because the compiler
cannot "root" a unique pointer to ensure it remains live.  The only
way to guarantee that a unique pointer is not freed is to guarantee
that the reference to it is not reassigned or moved.  Unfortunately, I
think we are going to want to define most of our collections so as to
avoid managed data whenever possible, because it means that they can
be sent and also shared between tasks.

### 2b. Ensure immutability

I have been experimenting (see my recent blog post) with the design of
freezable and sendable data structures.  The key idea there is to
write the data structure to use exclusively owned (`~`) pointers and to
avoid all explicit `mut` qualifiers.  For example, the hashmap could
be rewritten in this style:

    struct entry<K,V> {
        hash: uint;
        key: K;
        value: V;
        next: option<~entry<K,V>>;
    }
    struct hashmap<K,V> {
        hashfn: pure fn~(key: &K) -> uint;
        eqfn: pure fn~(key1: &K, key2: &K) -> bool;
        size: uint;
        buckets: ~[option<~entry<K,V>>];
    }

Notice how similar this is to the previous code.  The main difference
is that I have converted all `@` to `~` and removed the explicit
mutability qualifiers.  The trick now is that the mutability is
specified *from the outside*, in the type of the impl:

    impl<K,V> for &mut hashmap<K,V> {
        fn insert(+k: K, +v: V) -> bool { ... }
    }

Here, the type `&mut hashmap<K,V>` specifies a hashmap that lives in
mutable memory.  This implies that all of its fields are mutable as
well as any data which it owns (this is a recent change).  This
basically means that `insert()` may change any field it likes.

Using this style of definition, we can also write an impl that
requires deep *immutability*, by making an impl on `&hashmap<K,V>`.
More specifically, this requires that the structure be immutable only
for the duration of the method call. So if we write something like:

    impl<K,V> for &hashmap<K,V> {
        fn each(f: fn(key: &K, value: &V) -> bool) {...}
    }

The compiler will guarantee that the hashmap is immutable during the
call to each.  This means that it would be impossible to call
`insert()` on a hashmap that is being iterated.

There is a catch, though.  Using this style of definition, it is not
possible to have a managed box with a hashmap that is both mutable and
immutable, due to the possibility of aliasing.  So if I have a type
`@mut hashmap<K,V>`, I can insert, but not iterate, and if I have
`@hashmap<K,V>` I can iterate, but not insert.  Sometimes that's fine.
But sometimes it's not.

There is no super easy fix to this problem.  One option I have been
considering is that we could write a generic library that
*dynamically* ensures that the hashmap is mutable or immutable as
necessary.  You would use this type by writing something like
`@managed<T>`.  You could use this type as normal, for example just by
invoking map methods on it.  However, if you attempted to mix
mutable/immutable methods (for example, by invoking `insert()` while
iterating) it would fail.

The `managed<T>` type would be defined something like this:

    enum managed_state<T> {
        priv owned(~T),
        priv mutable(*mut T),
        priv immutable(*T)
        priv transient,
    }
    struct managed<T> {
        mut state: managed_state<T>
    }

And it would define an interface that contains three methods, each of
which allow you to get a temporary view on the structure using the
desired mutability:

    impl<T> &managed<T> {
        fn as_mutable<R>(op: fn(value: &mut T) -> R) -> R { ... }
        fn as_const<R>(op: fn(value: &const T) -> R) -> R { ... }
        fn as_immutable<R>(op: fn(value: &T) -> R) -> R { ... }
    }
    
Invoke `as_immutable()` from within an `as_mutable()` callback (or
vice versa) will lead to a dynamic failure.

The `as_mutable()` etc methods are not intended to be invoked directly
however.  Instead, for each collection interface, we would define
an impl that makes use of `as_mutable()` etc to get access to mutable
or immutable pointers as needed:

    impl<K,V,M: map<K,V>> &managed<M>: map<K,V> {
        fn insert(+key: K, +value: V) {
            do self.as_mutable |map| { map.insert(key, value) }
        }

        fn each(iterfn: fn(key: &K, value: &V)) {
            do self.as_immutable |map| { map.each(iterfn) }
        }

        ...
    }

The implementation of `as_mutable()` would look something like this
(`as_const()` and `as_immutable()` would be analogous):

    impl for &managed<T> {
        fn as_mutable<R>(op: fn(value: &mut T) -> R) -> R {
            alt self.state {
                transient => { fail; } // cannot happen
                immutable(ptr) => { fail "Mixing immutable and mutable"; }
                mutable(ptr) => { ret op(unsafe{*ptr}); }
                owned(val) => { /*fallthrough*/ }
            }
            let mut state = transient;
            state <-> self.state;
            let mut val = alt check move state { owned(val) { move val } };
            let mptr = &mut val;
            self.state <- mutable(mptr as *mut T);
            let result = op(mptr);
            self.state <- owned(val);
        }
    }

