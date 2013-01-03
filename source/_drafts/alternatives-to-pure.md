[Patrick Walton][pcwalton] and I have been discussing alternatives to
purity over the last day or two.  The fact is both he and I would
really like to remove the notion of a "pure function" from the
language---it is handy, certainly, but it creates a kind of two-level
divide between functions that are pure and those that are not that is
really best avoided.  This post is parly a repackaging of an e-mail
that I sent to Patrick recently.

After all, what if you want to use a library and they forgot to
declare that helper function as pure, even though they could have?
Anyone familiar with C++ will know the term "const-ification"; I am
quite sure that Rust would quickly develop a corresponding term like
"pure-ification", though it certainly fails to allude to a
[mildly humorous medical condition][mc] and thus is inherently less
appealing.

Some of you loyal readers may be thinking: "I thought there was no
need for purity if we implemented
[the ideas you wrote about in your previous post][imagine]?"  Of
course you are correct, but those ideas have not been implemented yet
and may never be.  In particular, Patrick and I were discussing that
perhaps it would be best to make `@mut` dynamically checked but leave
`&mut` as it is today, meaning that the possibility of aliasable,
mutable data still exists.  That means that purity---or something like
it!---will remain relevant.

<!-- more -->

### Where purity is important

Purity is currently needed whenever the user attempts to *freeze* data
is that both mutable *and* aliasable.  To see why it is necessary
imagine a borrowed pointer `b` of type `&mut T`.  Now if the compiler
wants to guarantee that the value `*b` pointed at by `b` is not
mutated, it can easily prevent you from writing to `*b`, but it also
has to prevent you from writing to some alias `b1` of `b`.  To make
this worse, the compiler tries not to look at the contents of
functions you call (that is, the check is modular) and hence if the
compiler sees a call to some function `f()` it must assume that `f`
may mutate `b` or some alias of `b`.

Today, we allow functions to be declared as pure, which basically
means "I promise not to mutate any data that you the caller can see".
In fact the rule is more like, "I won't mutate any data that you the
caller can see, except by calling closures that you gave to me".  But
the principle is the same: the caller never needs to examine the body
of the function `f()` to know what `f()` might mutate.  It only needs
to examine the closures that the caller passes to `f()` as argument,
if any, to make sure that those closures do not modify `b` or any
alias of `b`.

Let's get more concrete with an example.  Here's one of my favorites.
If you have a freezable hashmap, you wind up with some functions to
insert and retrieve keys from it:

    struct Map<K,V> { buckets: ~[Option<Bucket<K,V>>], ... }
    struct Bucket<K,V> { key: K, value: V}
    fn insert<K,V>(m: &mut Map<K,V>, k: K, v: V) {...}
    fn get<K,V>(m: &r/Map<K,V>, k: &K) -> &r/V {...}

Note that these functions both take a borrowed pointer `m` to a
`Map<K,V>`, but for `insert()` the pointer is mutable and for `get()`
the pointer is immutable.  By the rules of inherited mutability, this
means that `insert()` is able to mutate the data any data owned by the
map, which includes its `buckets` array and the contents of the
buckets themselves.

    
    
### So what is the alternative?

Note that emphasis on *mutation* in that previous paragraph.  That's
what purity, at least in Rust, is really about: ensuring that the
function you are calling doesn't mutate the data that you have frozen.

The basic idea is to replace the idea of a pure function with the idea
of a function that doesn't have access to mutable state.




Part of the current plan for closure types is to introduce a bound on
the environment of the closure.  So, for example, one could write
something like `@fn:Const()` to indicate a closure whose environment
consists entirely of `Const` data (confusingly, capital C `Const`
refers to the `Const` trait, which means deep
immutability---completely different from lower-case c `const`, which
is a shallow read-only qualifier). 

The idea of a closure with a `Const` bound is *very similar* to
purity.  Purity means that the function will not mutate any data in
its environment nor data reachable through its parameters.  A closure
with a const bound cannot mutate data in its environment (as it is
immutable) but it could still mutate data found (transitively) through
its parameters.

So that means that we could adjust the rule.  We could allow
aliasable, mutable data to be borrowed, so long as the code is locally
pure, and any functions which are invoked (1) have a `Const` bound on
their environment and (2) take only `Const` arguments.  This ensures
that those functions have no access to mutable data and hence cannot
possibly cause us trouble.

We could also tighten this and use type-based alias analysis (or some
other form) to gain more precision.  I'd like to avoid that if
possible because it is more complex to formulate the rules and I worry
about fragility to small changes in the code.

### What would be the best practices in this system?

The current best practices are basically: "use pure whenever you can"
and "prefer Const data".  The new best practices would be "use `&const
T` whenever you can and `&T` otherwise" and "prefer Const data".  Not
so different.  

You'll note that there is still a potential "const-ification" issue if
you use `&T` when you could have used `&const T`.  I hope that this
will be less serere in practice than purity.  For one thing, if you
use `&T` when you should have used `&const T`, and `T` is Const, you
have no problem.  If T is not Const, it only means that the function
cannot be applied to data in aliasable, mutable locations.

### How does this compare in expressiveness?

This definition of purity is less expressive than the current one and
far less expressive than the one I proposed recently.  However, it is
likely expressive enough.

There is still a kind of "const-ification" problem: you can 

I went through the rustc code base and looked at each place where we
rely on purity in the borrow checker.  Many of them would just work
with this definition.  Some would work after some minor tweaks.  The
large

###

Anyway, I may do some experiments in this direction.  If we could
remove purity I think it'd be a win.

Interestingly, this definition of purity is still *mostly* compatible
with porting a [PJs or Rivertrail][pjs]-like approach to Rust.

[pjs]: /blog/categories/pjs/
[pcwalton]: http://pcwalton.github.com/
[imagine]: /blog/2012/11/18/imagine-never-hearing-the-phrase-aliasable/
[mc]: http://www.webmd.com/digestive-disorders/digestive-diseases-constipation
