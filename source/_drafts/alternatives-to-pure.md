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

[pcwalton]: http://pcwalton.github.com/
[mc]: http://www.webmd.com/digestive-disorders/digestive-diseases-constipation

### Where purity is important

The current type system includes three mutability qualifiers:

- immutable (the default): no one can change this data
- `mut`: the data can be changed via this pointer
- `const`: the data cannot be changed via this pointer but may be
  mutable through other pointers

`const` is the supertype of the other two qualifiers.  At first, you
might think that if you want to write code that operates over data
which may or may not be mutable, `const` would be just the thing you
want.  Unfortunately, this turns out not to be true a lot of the time.

To see why `const` is not sufficient, think of the implementation of a
sendable map.  The types involved look something like this:

```rust
struct Map<K: Const Eq Hash, V> {
    buckets: ~[Option<Bucket<K,V>>]
}
struct Bucket<K: Const Eq Hash, V> {
    hash: uint,
    key: K,
    value: V
}
```

Now in the `insert()` routine, we want to see whether an entry already
exists.  In the current send_map code, there is a pure routine that is
shared by both the `insert()` and `find()` routines:

```rust
pure fn find_bucket_index(&self, hash: uint, key: &K) -> Option<uint> {
    loop {
        ...
        match self.buckets[index] {
            Some(ref bkt) => {
                if hash == bkt.hash && bkt.key.eq(key) {
                    return Some(index);
                }
            }
            None => {
                ...
            }
        }
    }
}
```

Of course this isn't exactly how it works but you get the idea.  Now,
here is the tricky part.  If there were no purity, but only `const`,
then "self" would have type `&const Map<K,V>` which would make the
`ref bkt` illegal---particularly as within the body of the match we
invoke `bkt.key.eq()` which might mutate self, for all that we know,
and cause the bucket to be overwritten with `None`.

### So what can we do?

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

Anyway, I may do some experiments in this direction.  If we could remove
purity I think it'd be a win.

Interestingly, this definition of purity is still *mostly* compatible
with porting a [PJs or Rivertrail][pjs]-like approach to Rust.

[pjs]: 
