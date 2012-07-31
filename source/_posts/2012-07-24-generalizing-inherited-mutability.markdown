---
layout: post
title: "Generalizing inherited mutability"
date: 2012-07-24 11:33
comments: true
categories: [Rust]
---

I have been working on a change to the definition of mutability in
Rust.  This is a much smaller change than my [previous][t1]
[thought][t2] [experiments][t3], which were aimed at achieving better
parameterization (those are still percolating; I think the best
approach is a modified version of [the latest proposal][t1] where not
all types have mutability but type parameters do...but that's a
problem for another day with many complications).  The goal of these
changes is to enable operations like "freeze" and "thaw".

[t1]: http://smallcultfollowing.com/babysteps/blog/2012/05/31/mutability/
[t2]: http://smallcultfollowing.com/babysteps/blog/2012/05/30/mutability-idea-retracted/
[t3]: http://smallcultfollowing.com/babysteps/blog/2012/05/28/moving-mutability-into-the-type/

### Some background on freeze and thaw

The idea of "freeze" is that it takes a mutable data structure and
produces an immutable one.  "Thaw" similarly takes an immutable data
structure and produces a mutable one.  These operations are somewhat
challenging; Rust's type system, like most, allows you to declare that
a field or value is mutable, but doesn't allow you to change that
mutability back and forth.

One of the trickiest parts of freeze/thaw is that it requires a notion
of *time* in the type system.  That is, the type of a value
effectively changes.  Changing the type of a value in a way that
invalidates the old type---sometimes called a "strong update"---is
tricky because you have to rule out aliases.  To understand what I'm
getting at, imagine that you have two pointers, `p` and `q`, both of
which point at the same mutable hashtable.  Now you freeze `p`, so its
type states that the hashtable is *immutable*.  Now you're in a
pickle, because the `q` pointer can still be used to modify the
supposedly immutable contents of `p`.  So basically the type of `p` is
a lie (or the type of `q` is, depending on your point of view).

I don't have a magic solution to this problem.  The approach to
freeze/that that I'm going to discuss here only allows freezing and
thawing of values that are owned by the current stack frame (in that
case, the compiler can track the aliases precisely).  I'll discuss
some of the options for accommodating aliasable values later.  

As an aside, my PhD work on intervals also aimed to solve this problem
(among others).  What I did there was basically to integrate the time
span in which the hashtable was mutable into the type from the
beginning.  So the type of the hashtable never *changed* from mutable
to immutable.  Instead, when you made an object, you specified a time
interval stating how long the new object would be mutable for (which
might be forever).  Once that interval had expired, the type system
would treat the object as deeply immutable, which meant that it could
be shared between threads and so forth.  This is a powerful idea but
quite beyond Rust's type system, and I am interested in exploring
solutions that lead to similar expressiveness while avoiding the
quagmire of dependent types.

### More background: inherited mutability

Currently in Rust, when you declare a record you specify which fields
are mutable.  For example, you might write:

    type character = {
        name: ~str,
        mut hitPoints: uint
    };
    
Here, the field `hitPoints` was declared as mutable.  The field `name`
was not.  You might think that this means that the field `name` is
immutable, but it turns out that, as a consequence of by-value
types, this is not *strictly* true.  In fact, the mutability of the field
`name` is best described as "inherited" rather than "immutable".  To
see what I mean, consider this function:

    fn adjust_character() {
        let mut character = {name: ~"Richard Seifer", mut hitPoints: 22};
        ...
        character = {name: ~"Zedicus Zoorander", mut hitPoints: 5};
        ...
    }

Here a mutable local variable `character` was declared of record type.
Now, if the field `character.name` were truly immutable, that would
mean that the value `character.name` could never change.  But, because
the record can be overwritten as a whole, this is not true.  As you
can see in the example, the value `character.name` can in fact change
from `"Richard Seifer"` to `"Zedicus Zoorander"`.  What has happened,
in effect, is that the fields which were not declared as mutable
*inherited* mutability from the location in which the record was
stored (in this case, a mutable local variable).

In fact, this inherited mutability is recognized by the Rust
compiler.  This means that `adjust_character()` could also be written
as follows:

    fn adjust_character() {
        let mut character = {name: ~"Richard Seifer", mut hitPoints: 22};
        ...
        character.name = ~"Kaylin";
        ...
    }

Here we assigned directly to the field `name`, even though it was not
declared as mutable. This is allows only because the record is stored
in a mutable local variable.  If we changed the program so that the
record is stored in an immutable location, say in an immutable managed
box (the name de jour for `@T`), we get an error:

    fn adjust_character_in_imm_managed_box() {
        let mut character = @{name: ~"Richard Seifer", mut hitPoints: 22};
        ...
        character.name = ~"Kaylin"; // Error, modifying immutable box.
        ...
    }

The reason is that now we are not modifying the interior of a mutable
variable but rather the interior of a box, and the box was not declared
as mutable.  We could shift the mutability into the box if we liked,
which would then make the program legal again:

    fn adjust_character_in_mut_managed_box() {
        let character = @mut {name: ~"Richard Seifer", mut hitPoints: 22};
        ...
        character.name = ~"Kaylin"; // OK, managed box is mutable.
        ...
    }

### Foreground: Inherited mutability for unique pointers

So, we've seen that in Rust mutability is inherited for interior
values, but not when traversing into a managed box.  There are many
ways to think about this rule, but I find it most helpful to think
about the rule in terms of *ownership*.  Interior values are
exclusively owned by their container, meaning that when the container
is freed or goes out of scope, those interior values are also freed.
To put it another way, the only way to reach those interior values is
to go through the owning container, and hence it is safe to free the
interior value once the container is freed.  So in this case
mutability is inherited from the owner value to the owned value.

Managed boxes, on the other hand, are co-owned: that is, they may have
many equal owners.  So the fact that one such owner (the local
variable `character`, in this case) is mutability does not imply that
the data in the box should be mutable, as there may be other owners
that are not mutable.  Similar reasoning applies to borrowed pointers:
if you have a mutable pointer of type `&character`, that does not
imply that the character which is pointed at ought to be mutable,
since borrowed pointers never imply ownership.

Unique boxes, however, *do* imply exclusive ownership.  So if we
follow this line of reasoning that a mutable owner implies mutable
contents, it should be possible to write a function like the
following:

    fn adjust_character_in_mut_managed_box() {
        let mut character = ~{name: ~"Richard Seifer", mut hitPoints: 22};
        ...
        character.name = ~"Kaylin"; // Currently an error, but should it be?
        ...
    }

Today, however, this is not the rule. Today, mutability is never
inherited when you pass through a pointer.  My proposal is basically
that we change this rule so that mutability always follows exclusive
ownership.

### How does this interact with freeze/thaw?

One consequence of this rule is that when data structures are
implemented using only exclusive ownership, they can easily be frozen
and thawed.  In fact, this kind of freezing and thawing doesn't even
require special operations, it just "falls out" of the current
checking for borrowed pointers.  Over the weekend, I experimented with
building a hashtable in this style.  I want to share a bit of the
results of this experiment.

The hashtable definition looks something like this (I will use the new
`struct` notation for named records that should be coming soon):

    struct hashmap<K,V> {
        hashfn: ~pure fn(K) -> uint,
        eqfn: ~pure fn(K, K) -> bool,
        size: uint,
        buckets: ~[option<bucket<K,V>>]
    }
    
    struct bucket<K,V> {
        hash: uint,
        key: K,
        value: V
    }

As you can see, this is an open-addressed hashtable, so there is a
single array storing the various buckets.  There is no reason that one
could not design a hashtable that uses chains per bucket as well,
however. I just wanted to experiment various open-addressing schemes
and pit them against a chained version.

Two things you'll notice (and this is important) is that

- no data in the hashmap are declared as mutable, and
- all values are exclusively owned (either interior or unique).

As a consequence of this, if I have a pointer of type `&mut
hashmap<K,V>`, then I can use that pointer to mutate any field I like.
Similarly if I do `&hashmap<K,V>` then I know that the map is deeply
immutable.  Finally `&const hashmap<K,V>` means that the map is
read-only but potentially mutable.  Basically, the outermost qualifier
is inherited down to all the data of the hashmap, which makes it very
easy to "switch" the map between mutable and immutable (freeze/thaw).

When writing code for the hashmap, you end up with separate implementations
based on the level of mutability required.  For example, methods like
`insert()` and `remove()` are implemented for a mutable hashmap:

    impl<K,V> for &mut hashmap<K,V> {
        fn insert(k: K, v: V); // take K, V by value so that we own them
        fn remove(k: &K);      // use borrowed ptr, do not need to own
    }
    
Methods like `get_copy()` and `find_copy()`, which copy out of the
hashmap, can be implemented for a const pointer.  Similarly, we could
write an iterator like `each_value_copy()` which copies value out.
Note that `V` must take a copy bound for these methods (but not the
others!) since we will be copying `V`:

    impl<K, V: copy> for &const hashmap<K,V> {
        fn get_copy(k: &K) -> V;
        fn find_copy(k: &K) -> option<V>;
        fn each_value_copy(op: fn(V) -> bool);
    }
    
Finally, methods like `each()` and `find_ptr()`---which create
borrowed pointers into the (owned) interior of the data
structure---are implemented using an *immutable* pointer.  This
guarantees that, for example, the hashtable is not modified during
iteration.

    impl<K,V> for &hashmap<K,V> {
        pure fn each(op: fn(&K, &V) -> bool);
        pure fn find_ptr(k: &K) -> option<&self/V>;
    }

The method `find_ptr()` is particularly interesting.  It is able to
return a pointer into the bucket itself, so there are no copies at
all.  Interestingly, this pointer may even be into the interior of
unique boxes owned by the hashtable.  This is safe because we are
guaranteed that the hashtable is immutable for the lifetime `self`,
and so those unique boxes in turn cannot be freed for at least that
lifetime (note: the current implementation does realize this, have to
fix [issue #2979][2979]).  This is a really powerful idea that I
didn't originally realize would be possible.  It basically falls out
of the design.

[2979]: https://github.com/mozilla/rust/issues/2979

### Using these maps: the good side

These dual-mode data structures work great when they are stored in
local variables.  You can write code where the map goes between
mutable and immutable without any problem:

    fn insert_iterate() {
        let map: hashmap<K,V> = new_hashmap();
     
        while some_condition_holds {
            map.insert(...);
            map.insert(...);
            map.insert(...);
            
            for map.each |k, v| {
                // any attempt to call insert() in here reports an error
            }
            
            // iteration is done, I can use insert again
            map.insert(...);
        }
    }
 
You can take a mutable map and share it between threads:

    fn make_arc() {
        let map: hashmap<K,V> = new_hashmap();
        ...
        let shared = arc::create(move map);
        // shared can be sent freely
    }
    
Or perhaps just share a frozen copy locally using managed data:

    fn make_managed() -> @hashmap<K,V> {
        let map: hashmap<K,V> = new_hashmap();
        ...
        @(move map)
    }

### Using these maps: the bad side
    
Things get messier, however, when you want to use borrowed pointers or
managed data.  Right now, that means that to factor code between
functions, you end up having to thread the maps around so that it is
always local to each function.  Here I show the `insert_iterate()`
function from before but with the calls to `insert()` factored into a
new function `insert()`

    fn insert_iterate() {
        let map: hashmap<K,V> = new_hashmap();
        
        while some_condition_holds {
            map = bar(move map);
            for map.each |k, v| {
                // any attempt to call insert() in here reports an error
            }
        }
        
        ....
    }

    fn insert(map: hashmap<K,V>) -> hashmap<K,V> {
        map.insert(...);
        map.insert(...);
        map.insert(...);
        ret map;
    }

It would be nice if there were a way to borrow a local variable in a
unique way (i.e., to guarantee that there are no other borrowed
pointers to the same variable).  That is not possible today, sadly,
and to add such a thing would probably amount to a fourth pointer
type.  Hmm.  Unappealing.

Dual-mode data structures also do not work so well with managed data.
For example, if I define a `@mut hashmap<K,V>`, I will not be able to
use the method `find_ptr()` without purity, because the type system
can't prove that the map is not aliased and then modified.

There are various solutions to the problem of aliasing.  The most
limitation option is to use an option to "swap out" the hashmap from
the managed data so you are always working on a local copy:

    fn process(managed_map: @mut option<hashmap<K,V>>) {
        let mut map = none;
        map <-> *managed_map;
        let map = option::unwrap(map); // convert some(map) to map
        
        // use map however you like
        
        *managed_map <- some(map);
    }
    
This can of course be wrapped up in a library.  It works reasonably
well except that it will fail dynamically if you attempt to use the
managed pointer to the hashmap recursively, even if that use "ought to
be" legal (for example, a `find_ptr()` from inside an `insert()`).

Another more flexible option is to create a trusted library which
allows you to temporary make the managed map read-only (basically, the
owned copy of the map is replaced with an unsafe, immutable pointer
for the duration of the borrow).  This will still fail dynamically if
you try to perform a mutating operation during an immutable one (e.g.,
if you try to call `insert()` while iterating), but it does let you do
immutable or const operations.  

I see no other options besides adding type-based alias analysis or
something similar to borrowck, which will let it check managed boxes
with more (but still limited) precision.  In academic terms, this
means adding something like [Vault's `focus()` operation][focus].

I am actually satisfied with the swapping-based solutions,
particularly the second one.  It's an improvement on Java's
[fail-fast iteration][ff], for example, in that it is more precise and
non-optional---in practice, fail-fast was always good enough for me
anyhow.  My only concern though is that it cannot be wrapped in a
library in a generic way that works across types, you must still
create wrappers for each method basically.  Maybe we can use macros.

Also, we'll probably want to have a variety of hashmaps, some of which
are based on managed data and hence inherently local.  I don't imagine
they'll be able to support borrowed pointers into the interior and
other such fancy tricks though.

[focus]: http://dl.acm.org/citation.cfm?id=512532
[ff]: http://docs.oracle.com/javase/1.4.2/docs/api/java/util/Vector.html
