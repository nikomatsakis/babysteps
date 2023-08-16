---
categories:
- Rust
comments: true
date: "2014-07-06T00:00:00Z"
slug: implied-bounds
title: Implied bounds
---
I am on vacation for a few weeks. I wanted to take some time to jot
down an idea that's been bouncing around in my head. I plan to submit
an RFC at some point on this topic, but not yet, so I thought I'd
start out by writing a blog post. Also, my poor blog has been
neglected for some time. Consider this a draft RFC. Some important
details about references are omitted and will come in a follow-up blog
post.

The high-level summary of the idea is that we will take advantage of
bounds declared in *type* declarations to avoid repetition in `fn` and
`impl` declarations.

<!--more-->

### Summary and motivation

Recent RFCs have introduced the ability to declare bounds within type
declarations. For example, a `HashMap` type might be defined as
follows:

    struct HashMap<K:Hash,V> { ... }
    trait Hash : Eq { ... }

These type declarations indicate that every hashmap is parameterized
by a key type `K` and a value type `V`. Furthermore, `K` must be a
hashable type. (The trait definition for `Hash`, meanwhile, indicates
that every hashable type must also be equatable.)

Currently, the intention with these bounds is that every time the user
writes `HashMap<SomeKey,SomeValue>`, the compiler will run off and
verify that, indeed, `SomeKey` implements the trait `Hash`. (Which in
turn implies that `SomeKey` implements `Eq`.)

This RFC introduces a slight twist to this idea. For the types of
function parameters as well as the self types of impls, we will not
verify their bounds immediately, but rather attach those bounds as
[where clauses][where] on the `fn`. This shifts the responsibility for
proving the bounds are satisfied onto the fn's caller; in turn, it
allows the fn to *assume* that the bounds are satisfied. The net
result is that you don't have to write as many duplicate bounds.

#### As applied to type parameter bounds    
    
Let me give an example. Here is a generic function that inserts a key
into a hashmap if there is no existing entry for the key:

    fn insert_if_not_already_present<K,V>(
        hashmap: &mut HashMap<K,V>
        key: K,
        value: V)
    {
        if hashmap.contains_key(&key) { return; }
        hashmap.insert(key, value);
    }
    
Today this function would not type-check because the type `K` has no
bounds. Instead one must declare `K:Hash`. But this bound feels rather
pointless -- after all, the fact that the function takes a `hashmap`
as argument *implies* that `K:Hash`. With the proposed change,
however, the fn above is perfectly legal.

Because impl self types are treated the same way, it will also be less
repititious to define methods on a type. Whereas before one would
have to write:

    impl<K:Hash,V> HashMap<K,V> {
        ...
    }
    
it is now sufficient to leave off the `Hash` bound, since it will be
inferred from the self-type:

    impl<K,V> HashMap<K,V> {
        ...
    }
    
#### As applied to lifetimes    

In fact, we [already have a similar rule][lt] for
lifetimes. Specifically, in some cases, we will infer a relationship
between the lifetime parameters of a function. This is the reason that
the following function is legal:

    struct Foo { field: uint }
    fn get_pointer<'a,'b>(x: &'a &'b Foo) -> &'a int {
        &x.field
    }

Here, the lifetime of `(**x).field` (when all dereferences are written
in full) is most properly `'b`, but we are returning a reference with
lifetime `'a`. The compiler permits this because there exists a
parameter of type `&'a &'b Foo` -- from this, the compiler infers that
`'a <= 'b`. The basis for this inference is a rule that you cannot
have a reference that outlives its referent. This is very helpful for
making some programs typecheck: this is particularly true with generic
traits, as described in [this blog post][lt].

### Detailed design

#### Well-formed types and the BOUNDS function

We say that a type is *well-formed* if all of its bounds are met.  We
define a function `BOUNDS(T)` that maps from a type `T` to the set of
bounds that must be satisfied for `T` to be called well-formed.

For the scalar types like int or float, `BOUNDS` just returns the
empty set:

    BOUNDS(int) = {}
    BOUNDS(uint) = {}
    BOUNDS(...) = {}
    
For struct types like `HashMap<SomeKey,SomeValue>`, the function
combines the bounds declared on the `HashMap` type with those declared
on `SomeKey` and `SomeValue`. (The `SUBST()` function is used to
substitute the actual type parameters `T1 ... Tn` for their formal
counterparts.)
    
    BOUNDS(Id<T1,...,Tn>) = UNION(SUBST(T1...Tn, DECLARED_BOUNDS(Id)),
                                  BOUNDS(T1), ..., BOUNDS(Tn))

Enum and object types are handled in precisely the same way as struct
types.

For vector types, the element type must be sized:

    BOUNDS([T, ..N]) = UNION({T : Sized}, BOUNDS(T))

#### Well-formed references

For references, the type must have a suitable *lower bound*:

    BOUNDS(&'a T) = UNION({'a <= LOWER-BOUND(T)}, BOUNDS(T))
    BOUNDS(&'a mut T) = UNION({'a <= LOWER-BOUND(T)}, BOUNDS(T))

Note that I have not defined the `LOWER-BOUND` function. The proper
definition of this function is important and I have been working on
it, but I prefer to defer that subject to a post/RFC of its own.
(Clarifying the lower-bound function, however, is the heart of #5723
along with a number of other recent bugs being filed on lifetimes.)
Note that this definition subsumes the existing rule for references
described in [my prior blog post][lt].



[lt]: http://smallcultfollowing.com/babysteps/blog/2013/04/04/nested-lifetimes/
