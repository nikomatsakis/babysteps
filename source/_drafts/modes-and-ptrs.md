
I am trying to figure out how our APIs should look in light of the
move to a region system.  One of the goals with borrowed pointers was
to make it more evident when you have a pointer and when you
don't---something which reference modes made quite hard to reason
about.  Of course, the fact that modes obscured the use of pointers
also made them nicer to use sometimes.

<!-- more -->

## The problem

### Collection APIs today

Today our generic classes (such as collections) tend to manipulate
their values by reference.  This is quite invisible in the Rust source,
however, due to the defaults.  So you have traits like the following:

    trait map<K, V: copy> {
        fn insert(+key: K, +value: V);
        fn get(&&key: K) -> V;
        fn find(&&key: K) -> option<V>;
        ...
    }

Here the method `insert()` takes it arguments by "copy mode", meaning
basically that it expects to own its arguments (so the caller must
either move its value into the argument or else copy it).  For
something like an `int`, copy mode is irrelevant, but for something
like a `~int`, copy mode means that the unique pointer is either moved
or cloned and can be quite relevant. The methods `get()` and `find()`
specify the mode `&&`, which means "by immutable reference" (in the
actual code, this mode is specified by default, but I chose to keep
all modes explicit in this post for clarity).

When you actually use a map, the modes work behind the scenes to create
and resolve pointers.  So if you write code like this:

    map.get(3)
    
what is actually happening is that the integer `3` is being stashed on
the stack and a pointer to that location is being passed in.

One other detail: you can see that the generic type `K` is declared
with no bounds.  This means that any type at all can be used as a key.
The type `V` is declared with the bound `copy`, which means that
values must be copyable.  This requirement is imposed because the
`get()` and `find()` methods copy the value out of the table in order
to return it to the user.  In general, for collections, fewer bounds
is better: in fact, I'd prefer it if the basic map API did not require
values to be copyable (we will see later how that can be achieved).

### Collection APIs in regions

Anyway, if we were to translate this signature to its direct
equivalent in a system that uses borrowed pointers in place of modes,
we would wind up with:

    trait map<K, V: copy> {
        fn insert(key: K, value: V);
        fn get(key: &K) -> V;
        fn find(key: &K) -> option<V>;
        ...
    }

In this system, all arguments are passed "by value", meaning that the
callee takes ownership.  So the `insert()` method simply takes a `K`
and `V` which it expects to own.  The `get()` and `find()` methods
both take an `&K`, because they merely need to use the key, they don't
need to own it.

Unlike modes, regions require you to be explicit about pointers.  That
means that if we use the API above, you would have to write

    map.get(&3)
    
in order to fetch the item with the key `3`.  This is precisely the
same as we saw with modes, except that the `&` operator is used to
convert the integer 3 into a pointer-to-integer.  

I personally find this...ok.  I like knowing where pointers come from
and I understand why collection classes tend to manipulate things by
pointer.  But it's not attractive.  It's also not especially
efficient: an integer and a pointer are the same size, after all, so
stashing 3 onto the stack just so I can pass a pointer to it is a bit
silly.

## The "many methods" solution

One option is to add more methods.  For example, we might have:

    trait map<K, V: copy> {
        fn insert(K, V);
        fn get(K) -> V;
        fn find(K) -> option<V>;
        fn get_by_ref(&K) -> V;
        fn find_by_ref(&K) -> option<V>;
        ...
    }

Now you can elect to call `get()`, which supplies the key by value, or
for those cases where that would be too expensive, `get_by_ref()`.  If
you make an obviously choice, for example where cloning the key would
require allocation, the Rust implicit copy system will warn you.

I personally find this...inelegant but perhaps ok, so long as we can
keep it down to two variations per method (`get()` and
`get_by_ref()`).  It is not clear that this is possible, though, as
we'll see.  Furthermore, there are some other complications that
arise.

### Complication #1: keys must be copyable

If we apply the 'by value' or 'by reference' dichotomy to all map
methods, we hit a complication: in some cases, keys must be copyable
(which is undesirable).  This occurs with the hashtable method
`each()`, which iterates over the keys and values in the table.  Today
(with modes) it is written as:

    trait map<K, V: copy> {
        ...
        fn each(op: fn(&&key: K, &&value: V) -> bool);
        ...
    }
    
That is, `each()` takes an argument `op` which is a function that it
will invoke on each key and value.  The key and value are passed using
the same by-immutable-reference mode.  Following the standard Rust
iteration protocol, `op` returns false if `each()` should stop
iterating.  The translation to by value would mean that the hashtable
must pass *a new copy of the key* to the function `op()`, which
implies that the key must be copyable.  As I wrote before, though, I
want to remove all bounds from the key and the value.

One solution to this is to break up the map trait (which I think we
have to do anyway) into distinct traits.  One such trait would include
the by-value `each()`, and it would require that keys are copyable.
But another trait would include `each_by_ref()`, which imposes no such
requirement.  This sort of thing would work more smoothly with the
ability for traits to inherit from one another, which lkuper is
working on but which we do not yet have.

### Complication #2: returning pointers

One of the nice features that regions give us is the ability to
return pointers into a data structure.  The work I've been doing on
[building sendable maps][sm] has made it clear that it is possible
to build maps which support a method like:

    fn get_ref(k: &K) -> &V
    
That is, a `get()` method that returns a pointer directly into the map
rather than copying it out.  This is exciting because (a) it's more
efficient for bigger types and (b) it allows us to drop the copy bound
on values.  However, it implies a combinatorial explosion of four
possible get methods: 

    fn(k: &K) -> &V
    fn(k: &K) -> V
    fn(k: K) -> &V
    fn(k: &K) -> &V
    
No good.  But perhaps it's enough to just support all by-value or all
by-ref.

[sm]: /blog/2012/07/24/generalizing-inherited-mutability/

## Another option

For a brief while I entertained a "thought experiment"---what if we
made region pointers be more like C++ references.  That is, you
wouldn't have to "derefence" them.  The `&` operator would go away;
instead, you create a reference just by assigning to a variable with
reference type.  I think you can create a rather nice system in this
way, but there is a fly in the ointment: type inference.  Basically,
what this system amounts to, is something like applying "auto-ref" to
all function arguments.  And the problem is that we often don't know
the full type of function arguments, so you don't know when to
"auto-ref".  Now, to be fair, the current auto-borrow rules have the
same problem; in practice, it is minimal, both because we aren't doing
that much borrowing yet and because the type inferencer often knows
*enough* about the types in question to know whether a borrow is
needed or not. However, the auto-borrow rules have the advantage that
there is always an out.

