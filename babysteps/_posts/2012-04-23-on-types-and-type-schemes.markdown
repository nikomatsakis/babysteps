---
layout: post
title: "On types and type schemes"
date: 2012-04-23 08:54
comments: true
categories: [Rust]
---

After my recent dalliance in
[Matters of a Truly Trivial Nature][trivial], I'd like to return to
Matters Most Deep and Profound.  I'm running up against an interesting
question with regions that has to do with the nature of function types
like `fn(&int)`: up until now, I've assumed that this refers to a
function that takes an integer pointer in some region that is
specified by the caller.  That is, it is a kind of shorthand for a
type that might be written like `fn<r>(&r.int)`, where the `<r>`
indicates that the function type is *parameterized* by the region `r`.

[trivial]: {{ site.baseurl }}/blog/2012/04/15/syntax-matters-dot-dot-dot/

### But first, a digression on types and type schemes...

This notation is analogous to a generic function, like:

    fn identity<T>(t: T) -> T { ret t; }

However, there is an important distinction.  In Rust, as in ML,
parameterization only occurs on named items.  So, you can have a named
function `identity` defined generically, but you cannot have a type
`fn<T>(T) -> T`. 

This is an interesting and subtle point.  In fact, all Rust types are
*monotypes*, meaning types that refer to exactly one thing.  Now, it
may not be known precisely what that thing *is*, but there must be a
name for it.  So, the type of the `t` parameter is `T`, which is a
type variable.  This is a monotype, it can only refer to one thing:
the type `T`.  It just so happens, however, that we do not know when
typechecking `identity` what that type `T` is.

The type of the `identity` function itself, however, cannot be
represented as a monotype.  We cannot name a specific type for its
parameter and return value, it could safely be used with any type.  To
accommodate this concept, ML introduced the idea of a *type scheme*,
also called a polytype. (at least by [Wikipedia][hm], I've never
heard the term before.  but it seems logical.)

[hm]: http://en.wikipedia.org/wiki/Hindley%E2%80%93Milner

A type scheme is basically a type along with a set of *bound type
variables*.  A bound type variable is one that is defined within the
scheme itself.  So, if you have the type scheme `fn<T>(T) -> T`, then
the variable `T` is said to be *bound* in this scheme.  In a scheme
like `fn<T>(T, U) -> T`, the variable `T` is bound, but the variable
`U` is called *free*, as it is not defined in the scheme.  Note that
in a monotype all variables are free, as monotypes do not define any
type variables.

So, in a way, a like `fn<r>(&r.T)` is really a monotype, although it
does not bind type variables.  But it can still refer to many concrete
types.  This entails complexity.

### ...and now back to regions.

So, the question is, should region variables be bound or free within a
function type?  It certainly makes life simpler if they are always
free, and it still results in a fairly expressive system.

But first let's examine why bound regions make life complex.  To help
keep things clear, I will use the explicit "bound region" notation I
introduced earlier, even though it's not an actual Rust type, and I
will eschew anonymous regions. This means that the notation for
writing function types and so forth will be a bit heavier than it
would be in "real life".  

I will use a few conventions: lowercase letters early in the alphabet
like `a`, `b`, and `c` refer to bound regions.  Lowercase letters late
in the alphabet (`r`, `s`) refer to free regions.  Plus, I generally
drop the types of a region pointer if they are not important, so let
`&r` be shorthand for something like `&r.int`.

#### Subtyping of bound regions

**Renaming of bound regions.** Imagine a type `A=fn<a>(&a)` and a type
`B=fn<b>(&b)`.  Is `A` a subtype of `B`?  Clearly, the answer should
be yes: they are basically the same type, as you could rename the
bound variable `a` in `A` to `b`, and they would be precisely the
same.  So here we find that we have to consider possible renamings of
bound regions when considering subtyping.

**Instantiating bound regions.** OK, well, now imagine the type
`C=fn(&r)`.  Here, the region variable `r` is *not* bound but rather
free.  So in this case, is `A` a subtype of `C`?  I would argue that
the answer *should be* yes: after all, if you *instantiate* `A` with
the value `a` for `r`, you get `fn(&r.T)`, the same as `C`.  So we
ought to consider possible instantiations of bound variables as well.

**Coallescing bound regions.** Finally, one more example:

    fn<a,b>(&a, &b)     <:    fn<c>(&c, &c)

Here the subtype is more flexible than the supertype.  The subtype
accepts two region pointers in any two regions, but the supertype
requires that they be in the same region.  

#### ...with type variables, too

Now, just to make things more fun, imagine we throw in a type variable
`X` into the mix.  Here we play the role of the inference engine,
which is trying to find a value for `X`.  So the question becomes,
is there any type that I can assign to `X` which would make the subtype
relation true?  

**Referring to free regions.** Let's start with a simple example.
  Consider:

    fn(&r)    <:    fn(X)
    
In this case, `r` is free, so we can assign `X` the value of `&r` and
everything should be fine.

**Bound regions.**  Ok, what if the subtype refers to a bound region?

    fn<a>(&a)    <:    fn(X)

We can still handle this case, but it requires a *region variable* as well.
In other words, if we create a region variable `R`, then we can substitute
that region variable for `a` and obtain:

    fn(&R) <: fn(X)
    
Now we can assign `X` to `&R` and then assume that the inference
engine will find a suitable region for `R`.  This will be based on
constraints from the rest of the program.

**Multiple parameters.**  Of course, if there are multiple parameters,
there may be interactions between them:

    fn<a>(&a, &a)    <:    fn(X, &r)

In this case, because `r` appears free in the supertype, `X` can be
assigned `&r`.  That would mean that `a` can be instantiated with
`r` and the subtyping relation holds.

**Bound regions within the supertype.** What if the region in the
supertype is bound, not free?

    fn<a>(&a, &a)    <:    fn<c>(X, &r)
    
In this case, there is no value of `X` which is suitable.  This is
perhaps not obvious: you might think that `&c` would be a fine value
for `X`.  But that means that the value of `X` would refer to the
region `c`, which is bound within the type.  It's a scoping violation.
The name `c` has no meaning outside of the supertype, whereas the type
`X` (which appears free) does have meaning.  So `X` cannot refer to
regions bound within the supertype.

#### Woah.

Yeah, it's complex.  I haven't come up with an elegant implementation
for the inference engine that accommodates all of these scenarios.
One option is to not handle all of these cases.  I also ought to read
up in The Literature as well as the implementations of other languages
(e.g., Haskell, Scala) to see what they do in similar scenarios.
Still, I dislike the idea of having things in our type system that
require citations to explain.

### So, can we just drop bound type variables in function types?

Actually, I think we definitely *could* (not yet sure if we *should*).
Most things I've thought of will "just work", and when they won't,
there is workaround via interfaces (more on that later).

First, an example of something that works:

    fn iter(v: [T], f: fn(&T)) { 
        uint::range(0, v.len()) { |i|
            f(&v[i]);
        }
    }
    
This function iterates over each item in the slice `v` and invokes the
function `f` (I am assuming Graydon's work on slices and vectors is
complete).  If we fully expand this type to see all the regions
involved, you end up with:

    fn iter(v: [T]/&a, f: fn/&a(&a.T)) { ... }
    
This signature is probably a bit confusing.  As usual, I find the best
way to think about regions is as lifetimes (in fact, I am considering
changing my terminology over to use the word lifetime exclusively).
So what this notation means is that there is some span of time `a` in
which the vector data and the function closure is valid.  The function
itself expects a pointer which is also valid for this same span of
time (in this case, that pointer will be a pointer into the vector
contents, so its lifetime comes from there).  This span of time `a`
will generally be the call to `iter()` itself.

### What doesn't work?

Basically, what doesn't work is when you want to have a function whose
arguments can have lifetimes whose lifetime is not yet known.  This
most commonly occurs when functions are stored into records.  One
example that comes to mind is the `hash` and `eq` functions that we
use to implement hashtables right now.

Currently, our hashtables are defined with a structure something like:

    type hash<K,V> = {
        hashfn: fn(&K) -> uint,
        eqfn: fn(&K, &K) -> bool,
        ...
    };
    
Here you see that the `hashfn` takes a pointer to the key `K` and
returns the hash (a `uint`).  The `eqfn` takes two keys and returns a
boolean if they are equal.

The key point here is that the lifetimes for the key arguments are not
known and cannot be known in advance.  The data for the hashtable is
stored in a structure on the heap and so its lifetime is not
stack-based and hence has no region; for any given hashtable
operation, the current array will be borrowed and thus tied to the
stack of that particular operation, but these future operations cannot
be given a name.

#### Did you say something about a workaround?

Yes, we can use ifaces to work around this problem.  Imagine an iface:

    iface hash_key_ops<K> {
        fn hash(k: &K) -> uint;
        fn eq(k1: &K, k2: &K) -> bool;
    }
    
I am mildly abusing ifaces here because the "self" would not be a
particular key but rather some singleton object representing the hash
function itself.  For example, I might define:

    enum murmur_hash { murmur_hash };
    impl of hash_key_ops<str> for murmur_hash {
        fn hash(k: &str) -> uint { ... }
        fn eq(k1: &str, k2: &str) -> bool { k1 == k2 }
    }

Now we could define the hashtable like:

    type hash<K,V> = {
        ops: hash_key_ops/@<K>,
        ...
    };

    fn new_hash<K,V>(ops: hash_key_ops/@<K>) { ... }

Now whenever we want to hash a key we can invoke `tbl.ops.hash(key)`.
The key point is that the named functions in an iface, just like
function items, can have polytypes even though normal function types
are monotypes.  Then each time we invoke `hash()` we would instantiate
the bound regions with fresh region variables.

Of course, if we were going to use ifaces with hashtables, we might
rather define the iface over the key type itself.  That raises some
interesting issues about instance coherence which I plan to discuss in
a blog post Real Soon Now, but if you're curious about *that* you may
also want to read my [mailing list post][mlp] on the topic as it is
still my preferred solution.

[mlp]: https://mail.mozilla.org/pipermail/rust-dev/2011-December/001036.html
