---
layout: post
title: In Rust, ordinary vectors are values
categories: [Rust]
---

I've been thinking a lot about persistent collections lately and
in particular how they relate to Rust, and I wanted to write up some
of my observations.[^chalk]

[^chalk]: As it happens, the SLG solver that I wrote about before seems like it would really like to use persistent collections.

### What is a persistent collection?

Traditionally, persistent collections are seen as this "wildly
different" way to setup your collection. Instead of having
methods like `push`, which grow a vector **in place**:

```rust
vec.push(element); // add element to `vec`
```

you have a method like `add`, which leaves the original vector alone
but returns a **new vector** that has been modified:

```rust
let vec2 = vec.add(element);
```

The key property here is that `vec` does not change. This makes
persistent collections a good fit for functional languages (as well
as, potentially, for parallelism).

### How do persistent collections work?

I won't go into the details of any particular design, but most of them
are based around some kind of tree. For example, if you have a vector
like `[1, 2, 3, 4, 5, 6]`, you can imagine that instead of storing
those values as one big block, you store them in some kind of tree,
the values at the leaves. In our diagram, the values are split into
two leaf nodes, and then there is a parent node with pointers to
those:

```
 [*        *] // <-- this parent node is the vector
  |        |
-----    -----
1 2 3    4 5 6
```

Now imagine that we want to mutate one of those values in the
vector. Say, we want to change the `6` to a `10`. This means we have
to change the right node, but we can keep using left one. Then we also
have to re-create the parent node so that it can reference the new
right node.

```
 [*        *]   // <-- original vector
  |        |    //     (still exists, unchanged)
-----    -----
1 2 3    4 5 6
-----
  |      4 5 10 // <-- new copy of the right node
  |      ------
  |        |
 [*        *]   // <-- the new vector
```

Typically speaking, in a balanced sort of tree, this means that an
insert opertion in a persistent vector tends to be O(log n) -- we have
to clone some leaf and mutate it, and then we have to clone and mutate
all the parent nodes on the way up the trees. **This is quite a bit
more expensive than mutating a traditional vector, which is just a
couple of CPU instructions.**

A couple of observations:

- If the vector is not *actually* aliased, and you *know* that it's
  not aliased, you can often avoid these clones and just mutate the
  tree in place. A bit later, I'll talk about an experimental,
  Rust-based persistent collection library called [`DVec`] which does
  that. But this is hard in a typical GC-based language, since you
  never know when you are aliased or not.
- There are tons of other designs for persistent collections, some of
  which are biased towards particular usage patterns. For example,
  [this paper][uf] has a design oriented specifically towards
  Prolog-like applications; this design uses mutation under the hood
  to make O(1) insertion, but hides that from the user via the
  interface. Of course, these cheap inserts come at a cost: older
  copies of the data structure are expensive to use.

[uf]: https://www.lri.fr/~filliatr/ftp/publis/puf-wml07.pdf

### Persistent collections makes collections into values

In some cases, persistent collections make your code easier to
understand.  The reason is that they act more like "ordinary values",
without their own "identity". Consider this JS code, with works with
integers:

```js
function foo() {
    let x = 0;
    let y = x;
    y += 1;
    return y - x;
}
```

Here, when we modify `y`, we don't expect `x` to change. This is
because `x` is just a simple value. However, if we change to use an
array:

```js
function foo() {
    let x = [];
    let y = x;
    y.push(22);
    use(x, y);
}
```

Now when I modify `y`, `x` changes too. This might be what I want, but
it might not be. And of course things can get even more confusing
when the vectors are hidden behind objects:

```js
function foo() {
    let object = {
        field: []
    };
    ...
    let object2 = {
        field: object.field
    };
    ...
    // Now `object.field` and `object2.field` are
    // secretly linked behind the scenes.
    ...
}
```

Now, don't get me wrong, sometimes it's super handy that
`object.field` and `object2.field` are precisely the same vector, and
that changes to one will be reflected in the other. But other times,
it's not what you want; I've often found that changing to use
persistent data structures can make my code cleaner and easier to
understand.

### Rust is different

If you've ever seen one of my talks on Rust[^talk], you'll know that
they tend to hammer on a key theme of Rust's design:

> Sharing and mutation: good on their own, TERRIBLE together.

[^talk]: If you haven't, I thought [this one] went pretty well.
[this one]: https://www.sics.se/nicholas-matsakis

Basically, the idea is that when you have two different ways to reach
the same memory (in our last example, `object.field` and
`object2.field`), then mutation becomes a very dangerous
prospect. This is particularly true when -- as in Rust -- you are
trying to forego the use of a garbage collector, because suddenly it's
not clear who should be managing that memory. **But it's true even
with a GC,** because changes like `object.field.push(...)` may effect
more objects than you expected, leading to bugs (particularly, but not
exclusively, when working with parallel threads).

So what happens in Rust if we try to have two accesses to the same
vector, anyway? Let's go back to those JavaScript examples we just
saw, but this time in Rust. The first one, with integers, works just
the same as in JS:

```rust
let x = 0;
let mut y = x;
y += 1;
return y - x;
```

But the second example, with vectors, won't even compile:

```rust
let x = vec![];
let mut y = x;
y.push(...);
use(x, y); // ERROR: use of moved value `x`
```

The problem is that once we do `y = x`, we have **taken ownership** of
`x`, and hence it can't be used anymore.

### In Rust, ordinary vectors are values

This leads us to a conclusion. In Rust, the "ordinary collections"
that we use every day **already act like values**: in fact, so does
any Rust type that doesn't use a `Cell` or a `RefCell`. Put another
way, presuming your code compiles, you know that your vector isn't
being mutated from multiple paths: you could replace it with an
integer and it would behave the same. This is kind of neat.

**This implies to me that persistent collections in Rust don't
necessarily want to have a "different interface" than ordinary ones.**
For example, as an experimental side project, I created a persistent
vector library called [dogged][][^name]. Dogged offers a vector type
called [`DVec`], which is based on the
[persistent vectors offered by Clojure][clojure]. But if you look at
the methods that [`DVec`] offers, you'll see they're kind of the
standard set (`push`, etc).

[dogged]: https://crates.io/crates/dogged
[`DVec`]: https://docs.rs/dogged/0.2.0/dogged/struct.DVec.html
[^name]: In English, if you are "dogged" in pursuing your goals, you are persistent.

For example, this would be a valid use of a `DVec`:

```rust
let mut x = DVec::new();
x.push(something);
x.push(something_else);
for element in &x { ... }
```

Nonetheless, a `DVec` *is* a persistent data structure. Under the
hood, a `DVec` is implemented as a [trie].  It contains an [`Arc`]
(ref-counted value) that refers to its internal data. When you call
`push`, we will update that `Arc` to refer to the new vector, leaving
the old data in place.

[trie]: https://en.wikipedia.org/wiki/Trie
[`Arc`]: https://doc.rust-lang.org/std/sync/struct.Arc.html
[clojure]: http://hypirion.com/musings/understanding-persistent-vector-pt-1

(As an aside, [`Arc::make_mut`] is a **really cool** method. It
basically tests the reference count of your `Arc` and -- if it is 1 --
gives you unique (mutable) access to the contents. If the reference
count is **not** 1, then it will clone the `Arc` (and its contents) in
place, and give you a mutable reference to that clone. If you're
recall how persistent data structures tend to work, this is *perfect*
for updating a tree as you walk. It lets you avoid cloning in the case
where your collection is not yet aliased.)

[`Arc::make_mut`]: https://doc.rust-lang.org/std/sync/struct.Arc.html#method.make_mut

### But persistent collections *are* different

The main difference then between a `Vec` and a `DVec` lies not in the
operations it offers, but in **how much they cost**. That is, when you
`push` on a standard `Vec`, it is an O(1) operation. But when you
clone, that is O(n). For a `DVec`, those costs are sort of inverted:
pushing is O(log n), but cloning is O(1).

**In particular, with a `DVec`, the `clone` operation just increments
a reference count on the internal `Arc`, whereas with an ordinary
vector, `clone` must clone of all the data.** But, of course, when you do
a `push` on a `DVec`, it will clone some portion of the data as it
rebuilds the affected parts of the tree (whereas a `Vec` typically can
just write into the end of the array).

But this "big O" notation, as everyone knows, only talks about
asymptotic behavior. One problem I've seen with `DVec` is that it's
pretty tough to compete with the standard `Vec` in terms of raw
performance. It's often just faster to copy a whole bunch of data than
to deal with updating trees and allocating memory. I've found you have
to go to pretty extreme lengths to justify using a `DVec` -- e.g.,
making tons of clones and things, and having a lot of data.

And, of course, it's not all about performance. If you are doing a
lot of clones, then a `DVec` ought to use less memory as well, since
they can share a lot of representation.

### Conclusion

I've tried to illustrate here how Rust's ownership system offers an
intriguing blend of functional and imperative styles, through the lens
of persistent collections. **That is, Rust's standard collections,
while implemented in the typical imperative way, actually act as if
they are "values"**: when you assign a vector from one place to
another, if you want to keep using the original, you must `clone` it,
and that makes the new copy independent from the old one.

This is not a new observation. For example, in 1990, Phil Wadler wrote
a paper entitled ["Linear Types Can Change The World!"][change] in
which he makes basically the exact same point, though from the
inverted perspective. Here he is saying that you can still offer a
persistent interface (e.g., a method `vec.add(element)` that returns a
new vector), but if you use linear types, you can secretly implement
it in terms of an imperative data structure (e.g.,
`vec.push(element)`) and nobody has to know.

[change]: http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.55.5439&rep=rep1&type=pdf

In playing with `DVec`, I've already found it very useful to have a
persistent vector that offers the same interface as a regular one. For
example, I was able to very easily modify the
[ena unification library][ena] (which is based on a vector under the
hood) to act in either [persistent mode] (using `DVec`) or
[imperative mode] (using `Vec`). Basically the idea is to be generic
over the exact vector type, which is easy since they both offer the
same interface.

[ena]: https://crates.io/crates/ena
[imperative mode]: https://docs.rs/ena/0.8.0/src/ena/unify/mod.rs.html#185
[persistent mode]: https://docs.rs/ena/0.8.0/src/ena/unify/mod.rs.html#188

(As an aside, I'd love to see some more experimentation here. For
example, I think it could be really useful to have a vector that
starts out as an ordinary vector, but changes to a persistent one
after a certain length.)

That said, I think there is another reason that some have taken
interest in persistent collections for Rust *specifically*. That is,
while simultaneous sharing and mutation can be a risky pattern, it is
sometimes a necessary and *dang useful* one, and Rust currently makes
it kind of unergonomic. **I do think we should do things to improve
this situation, and I have some specific thoughts**[^next_post], but I
think that persistent vs imperative collections are kind of a
non-sequitor here. Put another way, Rust already *has* persistent
collections, they just have a particularly inefficient `clone`
operation.

[`Cell`]: https://doc.rust-lang.org/std/cell/struct.Cell.html
[`RefCell`]: https://doc.rust-lang.org/std/cell/struct.RefCell.html
[^next_post]: Specific thoughts that will have to wait until the next blog post. Time to get my daughter up and ready for school! 

### Footnotes

