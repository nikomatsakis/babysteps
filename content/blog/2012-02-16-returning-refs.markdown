---
layout: post
title: "Returning refs"
date: 2012-02-16T08:06:00Z
comments: true
categories: [Rust, PL]
---

One commonly requested feature for regions is the ability to return
references to the inside of structures.  I did not allow that in the
proposal in [my previous post][pp] because I did not want to have any
region annotations beyond a simple `&`.  I think, however, that if you
want to allow returning references to the interior of a parameter, you
need a way for the user to denote region names explicitly.  

The big problem with returning references to the interior of data
structures is ensuring the lifetime and validity of that reference.  I
think it can be supported in some cases but not particularly well in
general.  It will work ok for structures allocated on the stack but be
quite limited for structures allocated in the heap, unless we have
strong support from the garbage collector.  Another scenario where it
could work well would be user-managed memory pools (which we probably
do want to support eventually).

### Simplest case

Let's start with the simplest case:

    type T = {mut f: uint};
    fn get_f(t: r&T) -> r&mut uint { &t.f }

Here we have a function that returns a pointer to a field of its
parameter.  On the callee side, I think this is fairly
straightforward.  You name the region in which the parameter is
located (`r`) and say that the return value is a mutable pointer to
`uint` in the same region (`r&mut uint)`.  The notation may leave
something to be desired, but the concept is hopefully clear enough.

#### Returning references to the stack

But what about the caller?  Again we'll start with the simplest case,
where `get_f()` is invoked with data that lives on the stack:

    fn caller_on_stack() {   // let region `b` refer to the function body
        let t = &{mut f: 3}; // type of t: `b&T`
        let p = get_f(t);    // type of p: `b&mut uint`
        *p = 5;              // legal, `b` region is in scope.
    }

In this case, there is no concern about memory management per se.  The
returned pointer is in the region `b`.  The type checker will enforce
the rule that if a function returns a reference type, the reference
must be in scope (note: I haven't thought through what this means for
generic types with the `ref` kind, but I guess they can be handled one
way or another).  Generally, because the parameter regions must be in
scope for the call, the returned region will be in scope too---but
we'll see that this does not always hold.

#### Returning references to the heap, take 1

Let's move on to a more complicated case where the data being accessed
is in the heap.  I'll first discuss how it could work in some
theoretical world and then show how this can cause problems:

    fn caller_on_heap() {    // (note: not fully sound)
        let t = @{mut f: 3}; // type of t: `@T`
        let p = get_f(t);    // type of p: `@mut uint`
        *p = 5;              // legal, `@` region is in scope.
    }

The only difference is that the variable `t` is in the heap region
`@`.  Now the returned pointer is considered to be in that region as
well, and so the assignment is permitted.  This seems reasonable at
first, but it is of course incompatible with ref counting (`p` is not
a ref-counted entity). If we moved to a garbage collector which could
handle interior pointers, this would be reasonably safe.  Interior
pointer support is needed to accomodate cases where `p` gets returned,
like this one:

    fn caller_on_heap_r() -> @mut uint {
        let t = @{mut f: 3};
        ret get_f(t);
    }
    
So is there anything we can do that is compatible with ref. counting?
The answer is "sort of".
    
#### Returning references to the heap, take 2

One thought is that we say that `@` is not actually a region.  It's
never been the best fit, due to ref counting requirements and implicit
headers.  Instead, we say that regions always refer to some
block-scoped slice of the program execution.  The most common case
would be a block in the program, but in some cases the region might be
"the time in which a given expression is evaluated" and so forth (as
an aside: this is basically what I called an "interval" in my
thesis...minus all the parallel parts).

An `@T` pointer could then be implicitly coerced into an `r&T` pointer
where the region `r` is the biggest region for which the type checker
can guarantee the validity of the `@T` pointer.  So, we can now
revisit the previous examples.  The first example works more-or-less
the same as before:

    fn caller_on_heap() {    // region of the block is `r`
        let t = @{mut f: 3}; // type of t: `@T`
        let p = get_f(t);    // type of p: `r&mut uint`
        *p = 5;              // legal, `r` region is in scope.
    }

The differences here lie in the type checker.  The pointer `p` is no
longer in the `@` region but rather in the region `r` corresponding to
the function body.  The reason that the region `r` could be safely
used is that `t` is an immutable local variable (I am assuming
[issue #1273][1273] is implemented...working on *that* right now).
This means that the memory will remain valid as long as `t` is in
scope.

**EDIT: There is no reason to impose the following restriction.  See
discussion below.** This implies that if `t` were mutable, the example
would not work In that case, the validity of the memory to `t` could
not be guaranteed for the entire block, as `t` could be overwritten.
In other words, a program might do something like this:

    fn caller_on_heap() {
        let mut t = @{mut f: 3};
        let p = get_f(t);
        t = @{mut f: 22};    // original memory is now freed
        *p = 5;              // memory error.
    }

However, such a program would not type check.  The reason is that,
because `t` is mutable, when `t` was coerced to a region type, a
narrow region `s` would be assigned.  The region `s` would correspond
to precisely the call to `get_f()`.  The result of `get_f()` would
therefore have type `s&mut uint`, but the region `s` would be out of
scope after `get_f()` returned, and so a type error occurs (this is
that rule I mentioned before: when returning a reference, the region
must be in scope).

As an aside, coercing a unique pointer `~T` into a region would work
similarly to the second case: that is, the resulting region is always
a very narrow one.  It does not matter if the variable storing the
unique pointer is immutable or not.  The reason is that the local
variable is being borrowed for the lifetime of the region.  If we
assigned a large region, the local variable would be inaccessible
after the call, because we would not be able to guarantee the
uniqueness invariant, as there might be escaped region-typed pointers
into its interior. Anyway, I don't want to go into details about
unique pointers in this post as it's already plenty long.

**EDIT:** pcwalton pointed out to me that there is no reason to treat
mutable variables specially.  Instead, we can basically just increment
the ref count whenever we coerce an `@T` to a `r&T`. The region `r`
would still be the region of an enclosing block `b` (probably the
innermost one, or perhaps the one where the variable is declared) and
we would release the reference upon exiting the block `b` can still
optimize immutable variables to not increase the reference at all
because it is unnecessary.  I rejected this approach initially because
I was thinking that we would want to keep it very predictable when
references would be dropped, but that's not actually an important
property.  Garbage collection traditionally does not define precisely
when dead memory will be reclaimed, after all (and, as graydon
correctly points out, RC+CC is garbage collection).  Note though that
borrowing unique pointers probably still ought to use a narrow region
corresponding to the call or `alt` statement in which the borrow
occurs.

### But does it scale?

So, I think this system I showed above is reasonable.  I think it has
a clear story, too, which is important to me, because it helps me
believe that it is sound even though I haven't made any kind of formal
proof or argument.  The story is basically that 

- a region is always a block-scoped slice of the dynamic execution;
- when a `@T` is coerced into a region pointer, the result is the largest
  region for which the validity of the `@T` pointer can be guaranteed;
- when a `~T` is coerced into a region, the result is a narrow region
  corresponding to just the duration of the borrow (I haven't gone into
  details on this... perhaps in a later post)
  
However, in all of these examples I showed only the simplest case,
where a pointer was returned directly into one of the parameters.  A
more realistic scenario is probably returning some interior pointer to
a record reachable from a parameter.  For example, a common C trick is
to have a hashtable lookup not return the value which was found but
rather a pointer to the value.  This allows the caller to update the
value without having to use any further API calls.  Let's look at that
example: we will find that the regions don't scale up.

The prototype for such a function might be:

    fn get_value_ptr<K,V>(m: r&map<K,V>, k: &K) -> option<r&V> {
        ...
    }
    
This looks reasonable, but once we start digging into the details
things don't work so well.  Let's assume a hashmap with chains for
each key:

    enum bucket<K,V> = {k: K, mut v: V, mut next: option<@bucket<K,V>>};
    enum map<K,V> = {buckets: [mut option<@bucket<K,V>>], ...};

    fn get_value_ptr<K,V>(m: r&map<K,V>, k: &K) -> option<r&mut V> {
        let bkt_idx: uint = find_bucket_index(m, k);
        alt search_bucket_chain(m.buckets[bkt_idx], k) {
            none { none }     // no bucket with key k
            some(bkt) {       // found a bucket with key k
                              // bkt has type @bucket<K,V>
                some(&bkt.v)  // (*) error
            }
        }
    }
    
The example should be straightforward if you've ever coded up a
hashtable.  The tricky part is marked with a `(*)`: once we've found
the bucket containing the value, we attempt to return a pointer to its
interior.  But this is not safe, of course!  The caller expects a
pointer in the same region as the map: that is, with the same
lifetime.  There is no way for `get_value_ptr()` to guarantee that
`bkt` is valid as long as the map `m` is valid.  The caller might, for
example, remove the key from the hashtable, thus invalidating the
bucket.  This error manifests itself as a type error, because the type
of `&bkt.v` is a region pointer corresponding to the region of the
`alt`, not the region `r` which was provided as a parameter.

#### Could this example be made to work?

I don't think it can without a lot of work.  You could imagine that
the caller would consider the map "borrowed" while the returned value
is in scope and thus try not to modify it.  But there may be aliases
to the map, so there are still no guarantees.  

I think there are two ways to handle an example like that in a safe
fashion:

- Improve the GC, as described before
- Re-write the example into a top-down style.

The second "solution" is what we support today, and what is supported
by the ["Regions Lite" idea I described before][pp].  You would write:

    fn get_value_ptr<K,V,R>(
        m: r&map<K,V>,
        k: &K,
        f: fn(option<&mut V>) -> R) -> R {
        ...
    }
    
In other words, the `get_value_ptr()` method will call the closure `f`
with the result of the lookup.  In this way, the `get_value_ptr()`
method itself can guarantee that the reference is valid. 

### Is it all worth it?

It may still be worth having labeled region parameters and supporting
a limited form of returning references, but I am not sure.  I feel
like writing things in a "top-down", CPS-ish style is perhaps just a
better solution---it's certainly more widely applicable.

Regardless, I do like the idea of formalizing regions as representing
a slice of time, and defining coercions from `@T` and `~T`.  I think
that feels intuitively sensible and I think it can be explained in a
reasonable way.

There is however one potentially important future case where the
simple form of returning references would be enough.  If we had
user-defined memory pools, then it would be possible to have large,
dynamically allocated, multi-object data structures that all lie
within one region (the memory pool).  A map, for example, might have
an associated arena.  This scheme would then work.  When you think
about it, treating `@` as a region and having a GC which can handle
interior pointers is really the same thing as this scheme, from an
abstract point of view.

Another important thing is that I think there is a path from all of
these more limited forms to the more general ones.  If we say, for
now, that `@` is not a region and we do not support labeled
parameters, we can add both of those later. Existing programs will
continue to type check.

[pp]: blog/2012/02/15/regions-lite-dot-dot-dot-ish/
[1273]: https://github.com/mozilla/rust/issues/1273
