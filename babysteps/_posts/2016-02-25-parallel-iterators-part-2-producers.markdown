---
layout: post
title: "Parallel Iterators Part 2: Producers"
date: 2016-02-25 11:02:34 -0500
comments: false
categories: [Rust]
---

This post is the second post in my series on Rayon's parallel
iterators. The goal of this series is to explain how parallel
iterators are implemented internally, so I'm going to be going over a
lot of details and giving a lot of little code examples in Rust. If
all you want to do is *use* parallel iterators, you don't really have
to understand any of this stuff.

I've had a lot of fun designing this system, and I learned a few
lessons about how best to use Rust (some of which I cover in the
conclusions). I hope you enjoy reading about it!

This post is part 2 of a series. In the [initial post][] I covered
sequential iterators, using this dot-product as my running example:

[initial post]: http://smallcultfollowing.com/babysteps/blog/2016/02/19/parallel-iterators-part-1-foundations/

```rust
vec1.iter()
    .zip(vec2.iter())
    .map(|(i, j)| i * j)
    .sum()
```

In this post, we are going to take a first stab at extending
sequential iterators to parallel computation, using something I call
**parallel producers**. At the end of the post, we'll have a system
that can execute that same dot-product computation, but in parallel:

```rust
vec1.par_iter()
    .zip(vec2.par_iter())
    .map(|(i, j)| i * j)
    .sum()
```

Parallel producers are very cool, but they are not the end of the
story! In the next post, we'll cover **parallel consumers**, which
build on parallel producers and add support for combinators which
produce a variable number of items, like `filter` or `flat_map`.

<!-- more -->

### Parallel Iteration

When I explained sequential iterators in the
[previous post][initial post], I sort of did it bottom-up: I started
with how to get an iterator from a slice, then showed each combinator
we were going to use in turn (`zip`, `map`), and finally showed how
the `sum` operation at the end works.

To explain parallel iterators, I'm going to work in the opposite
direction. I'll start with the high-level view, explaining the
`ParallelIterator` trait and how `sum` works, and then go look at how
we implement the combinators. This is because the biggest difference
in parallel iterators is actually the "end" operations, like `sum`,
and not as much the combinators (or at least that is true for the
combinators we'll cover in this post).

In Rayon, the `ParallelIterator` traits are divided into a hierarchy:

- `ParallelIterator`: any sort of parallel iterator.
- `BoundedParallelIterator: ParallelIterator`: a parallel iterator that can
  give an upper-bound on how many items it will produce, such as `filter`.
- `ExactParallelIterator: BoundedParallelIterator`: a parallel iterator that
  knows precisely how many items will be produced.
- `IndexedParallelIterator: ExactParallelIterator`: a parallel
  iterator that can produce the item for a given index **without
  producing all the previous items**. A parallel iterator over a
  vector has this propery, since you can just index into the vector.
  - (In this post, we'll be focusing on parallel iterators in this
    category.  The next post will discuss how to handle things like
    `filter` and `flat_map`, where the number of items being iterated
    over cannot be known in advance.)

Like sequential iterators, parallel iterators represent a set of
operations to be performed (but in parallel). You can use combinators
like `map` and `filter` to build them up -- doing so does not trigger
any computation, but simply produces a new, extended parallel
iterator. Finally, once you have constructed a parallel iterator that
produces the values you want, you can use various "operation" methods
like `sum`, `reduce`, and `for_each` to actually kick off execution.

This is roughly how the parallel iterator traits are defined:

```rust
trait ParallelIterator {
    type Item;

    // Combinators that produce new iterators:
    fn map(self, ...);
    fn filter(self, ...);   // we'll be discussing these...
    fn flat_map(self, ...); // ...in the next blog post

    // Operations that process the items being iterated over:
    fn sum(self, ...);
    fn reduce(self, ...);
    fn for_each(self, ...);
}

trait BoundedParallelIterator: ParallelIterator {
}

trait ExactParallelIterator: BoundedParallelIterator {
    fn len(&self) -> usize; // how many items will be produced
}

trait IndexedParallelIterator {
    // Combinators:
    fn zip(self, ...);
    fn enumerate(self, ...);

    // Operations:
    fn collect(self, ...);
    fn collect_into(self, ...);

    // I'll come to this one shortly :)
    fn with_producer<CB>(self, callback: CB)
        where CB: ProducerCallback<Self::Item>;
}
```

These look superficially similar to the sequential iterator traits,
but you'll notice some differences:

- Perhaps most importantly, **there is no `next` method!** If you
  think about it, drawing the "next" item from an iterator is an
  inherently sequential notion. Instead, parallel iterators emphasize
  high-level **operations** like `sum`, `reduce`, `collect`, and
  `for_each`, which are then automatically distributed to worker
  threads.
- Parallel iterators are much more sensitive to being indexable than
  sequential ones, so some combinators like `zip` and `enumerate` are
  only possible when the underlying iterator is indexed. We'll discuss
  this in detail when covering the `zip` combinator.

### Implementing `sum` with producers

One thing you may have noticed with the `ParallelIterator` traits is
that, lacking a `next` method, there is no way to get data out of
them!  That is, we can build up a nice parallel iterator, and we can
call `sum` (or some other high-level method), but how do we
*implement* `sum`?

The answer lies in the `with_producer` method, which provides a way to
convert the iterator into a producer. A *producer* is kind of like a
splittable iterator: it is something that you can divide up into
little pieces and, eventually, convert into a sequential iterator to
get the data out. The trait definition looks like this:

```rust
trait Producer: IntoIterator {
    // Divide into two producers, one of which produces data
    // with indices `0..index` and the other with indices `index..`.
    fn split_at(self, index: usize) -> (Self, Self);
}
```

Using producers, we can implement a parallel version of `sum` based on
a divide-and-conquer strategy. The idea is that we start out with some
producer P and a count `len` indicating how many items it will
produce.  If that count is too big, then we divide P into two
producers by calling `split_at` and then recursively sum those up (in
parallel). Otherwise, if the count is small, then we convert P into an
iterator and sum it up sequentially. We can convert to an iterator by
using the `into_iter` method from the `IntoIterator` trait, which
`Producer` extends. Here is a parallel version of `sum` that works for
any producer (as with the sequential `sum` we saw, we simplify things
by making it only word for `i32` values):

```rust
fn sum_producer<P>(mut producer: P, len: usize) -> i32
    where P: Producer<Item=i32>
{
    if len > THRESHOLD {
        // Input too large: divide it up
        let mid = len / 2;
        let (left_producer, right_producer) =
            iter.split_at(mid);
        let (left_sum, right_sum) =
            rayon::join(
                || sum_producer(left_producer, mid),
                || sum_producer(right_producer, len - mid));
        left_sum + right_sum
    } else {
        // Input too small: sum sequentially
        let mut sum = 0.0;
        for value in producer {
            sum += value;
        }
        sum
    }
}
```

(The actual code in Rayon most comparable to this is called
[`bridge_producer_consumer`][bpc]; it uses the same basic divide-and-conquer
strategy, but it's generic with respect to the operation being
performed.)

[bpc]: https://github.com/nikomatsakis/rayon/blob/bed0da76215aef1a0d852339fd79cedba9ec4c40/src/par_iter/internal.rs#L100-L124

##### Ownership, producers, and iterators

You may be wondering why I introduced a separate `Producer` trait
rather than just adding `split_at` directly to one of the
`ParallelIterator` traits? After all, with a sequential iterator, you
just have one trait, `Iterator`, which has both "composition" methods
like `map` and `filter` as well as `next`.

The reason has to do with ownership. It is very common to have shared
resources that will be used by many threads at once during the
parallel computation and which, after the computation is done, can be
freed. We can model this easily by having those resources be *owned*
by the parallel iterator but *borrowed* by the producers, since the
producers only exist for the duration of the parallel
computation. We'll see an example of this later with the closure in
the `map` combinator.

#### Implementing producers

When we looked at sequential iterators, we saw three impls: one for
slices, one for zip, and one for map. Now we'll look at how to
implement the `Producer` trait for each of those same three cases.

##### Slice producers

Here is the code to implement `Producer` for slices. Since slices
already support the `split_at` method, it is really very simple.

```rust
pub struct SliceProducer<'iter, T: 'iter> {
    slice: &'iter [T],
}

impl<'iter, T> Producer for SliceProducer<'iter, T> {
    // Split-at can just piggy-back on the existing `split_at`
    // method for slices.
    fn split_at(self, mid: usize) -> (Self, Self) {
        let (left, right) = self.slice.split_at(mid);
        (SliceProducer { slice: left },
         SliceProducer { slice: right })
    }
}
```

We also have to implement `IntoIterator` for `SliceProducer`, so that
we can convert to sequential execution. This just builds on the slice
iterator type `SliceIter` that we saw in the [initial post][] (in
fact, for the next two examples, I'll just skip over the
`IntoIterator` implementations, because they're really quite
straightforward):

```rust
impl<'iter, T> IntoIterator for SliceProducer<'iter, T> {
    type Item = &'iter T;
    type IntoIter = SliceIter<'iter, T>;
    fn into_iter(self) -> SliceIter<'iter, T> {
        self.slice.iter()
    }
}
```

##### Zip producers

Here is the code to implement the `zip` producer:

```rust
pub struct ZipProducer<A: Producer, B: Producer> {
    a: A,
    b: B
}

impl<A, B> Producer for ZipProducer<A, B>
    where A: Producer, B: Producer,
{
    type Item = (A::Item, B::Item);

    fn split_at(self, mid: usize) -> (Self, Self) {
        let (a_left, a_right) = self.a.split_at(mid);
        let (b_left, b_right) = self.b.split_at(mid);
        (ZipProducer { a: a_left, b: b_left },
         ZipProducer { a: a_right, b: b_right })
    }
}
```

What makes zip interesting is `split_at` -- and I don't mean the code
itself, which is kind of obvious, but rather the implications of it.
In particular, if we're going to walk two iterators in lock-step and
we want to be able to split them into two parts, then those two parts
need to split at **the same point**, so that the items we're walking
stay lined up. This is exactly why the `split_at` method in the
`Producer` takes a precise point where to perform the split.

If it weren't for `zip`, you might imagine that instead of `split_at`
you would just have a function like `split`, where the producer gets
to pick the mid point:

```rust
fn split(self) -> (Self, Self);
```

But if we did this, then the two producers we are zipping might pick
different points to split, and we wouldn't get the right result.

The requirement that a producer be able to split itself at an
arbitrary point means that some iterator combinators cannot be
accommodated. For example, you can't make a producer that implements
the `filter` operation. After all, to produce the next item from a
filtered iterator, we may have to consume any number of items from the
base iterator before the filter function returns true -- we just can't
know in advance. So we can't expect to split a filter into two
independent halves at any precise point. But don't worry: we'll get to
`filter` (as well as the more interesting case of `flat_map`) later on
in this blog post series.

##### Map producers

Here is the type for map producers.

```rust
pub struct MapProducer<'m, PROD, MAP_OP, RET>
    where PROD: Producer,
          MAP_OP: Fn(PROD::Item) -> RET + Sync + 'm,
{
    base: P,
    map_op: &'m MAP_OP
}
```

This type definition is pretty close to the sequential case, but there
are a few crucial differences. Let's look at the sequential case again
for reference:

```rust
// Review: the sequential map iterator
pub struct MapIter<ITER, MAP_OP, RET>
    where ITER: Iterator,
          MAP_OP: FnMut(ITER::Item) -> RET,
{
    base: ITER,
    map_op: MAP_OP
}
```

All of the differences between the (parallel) producer and the
(sequential) iterator are due to the fact that the map closure is now
something that we plan to share between threads, rather than using it
only on a single thread. Let's go over the differences one by one to
see what I mean:

- `MAP_OP` implements `Fn`, not `FnMut`:
  - The `FnMut` trait indicates a closure that receives unique,
    mutable access to its environment. That makes sense in a
    sequential setting, but in a parallel setting there could be many
    threads executing map at once. So we switch to the `Fn` trait,
    which only gives shared access to the environment. This is part of
    the way that Rayon can statically prevent data races; I'll show
    some examples of that later on.
- `MAP_OP` must be `Sync`:
  - [The `Sync` trait](http://doc.rust-lang.org/std/marker/trait.Sync.html)
    indicates data that can be safely shared between threads. Since we
    plan to be sharing the map closure across many threads, it must be
    `Sync`.
- the field `map_op` contains a reference `&MAP_OP`:
  - The sequential map iterator owned the closure `MAP_OP`, but the
    producer only has a shared reference. The reason for this is that
    the producer needs to be something we can split into two -- and
    those two copies can't *both* own the `map_op`, they need to share
    it.

Actually implementing the `Producer` trait is pretty straightforward.
It looks like this:

```rust
impl<'m, PROD, MAP_OP, RET> Producer for MapProducer<'m, PROD, MAP_OP, RET>
    where PROD: Producer,
          MAP_OP: Fn(PROD::Item) -> RET + Sync + 'm,
{
    type Item = RET;

    fn split_at(self, mid: usize) -> (Self, Self) {
        let (left, right) = self.base.split_at(mid);
        (MapProducer { base: left, map_op: self.map_op },
         MapProducer { base: left, map_op: self.map_op })
    }
}
```

### Whence it all comes

At this point we've seen most of how parallel iterators work:

1. You create a parallel iterator by using the various combinator
   methods and so forth.
2. When you invoke a high-level method like `sum`, `sum` will
   convert the parallel iterator into a producer.
3. `sum` then recursively splits this producer into sub-producers
   until they represent a reasonably small (but not too small)
   unit of work. Each sub-producer is processed in parallel using
   `rayon::join`.
4. Eventually, `sum` converts the producer into an iterator and performs
   that work sequentially.

In particular, we've looked in detail at the last two steps. But we've
only given the first two a cursory glance. Before I finish, I want to
cover how one constructs a parallel iterator and converts it to a
producer -- it seems simple, but the setup here is something that took
me a long time to get right. Let's look at the map combinator in
detail, because it exposes the most interesting issues.

#### Defining the parallel iterator type for map

Let's start by looking at how we define and create the parallel
iterator type for map, `MapParIter`. The next section will dive into
how we convert this type into the `MapProducer` we saw before.

Instances of the map combinator are created when you call `map` on
some other, pre-existing parallel iterator. The `map` method
itself simply creates an instance of `MapParIter`, which wraps
up the base iterator `self` along with the mapping operation `map_op`:

```rust
trait ParallelIterator {
    type Item;

    fn map<MAP_OP, RET>(self, map_op: MAP_OP)
                       -> MapParIter<Self, MAP_OP, RET>
        where MAP_OP: Fn(Self::Item) -> RET + Sync,
    {
        MapParIter { base: self, map_op: map_op }
    }
}
```

The `MapParIter` struct is defined like so:

```rust
pub struct MapParIter<ITER, MAP_OP, RET>
    where ITER: ParallelIterator,
          MAP_OP: Fn(ITER::Item) -> RET + Sync,
{
    base: ITER,
    map_op: MAP_OP
}
```

The parallel iterator struct bears a strong resemblance to the
producer struct (`MapProducer`) that we saw earlier, but there are
some important differences:

1. The `base` is another parallel iterator of type `ITER`, not a producer.
2. The closure `map_op` is *owned* by the parallel iterator.

During the time when the producer is active, the parallel iterator
will be the one that owns the shared resources (in this case, the
closure) that the various threads need to make use of. Therefore, the
iterator must outlive the entire high-level parallel operation, so
that the data that those threads are sharing remains valid.

Of course, we must also implement the various `ParallelIterator`
traits for `MapParIter`. For the basic `ParallelIterator` this
is straight-forward:

```rust
impl<ITER, MAP_OP, RET> ParallelIterator for MapParIter<ITER, MAP_OP, RET>
    where ITER: ParallelIterator,
          MAP_OP: Fn(ITER::Item) -> RET + Sync,
{
    ...
}
```

When it comes to the more advanced classifications, such as
`BoundedParallelIterator` or `IndexedParallelIterator`, we can't say
unilaterally whether maps qualify or not. Since maps produce one item
for each item of the base iterator, they inherit their bounds from the
base producer. If the base iterator is bounded, then a mapped version
is also bounded, and so forth. We can reflect this by tweaking the
where-clauses so that instead of requiring that `ITER:
ParallelIterator`, we require that `ITER: BoundedParallelIterator` and
so forth:

```rust
impl<ITER, MAP_OP, RET> BoundedParallelIterator for MapParIter<ITER, MAP_OP, RET>
    where ITER: BoundedParallelIterator,
          MAP_OP: Fn(ITER::Item) -> RET + Sync,
{
    ...
}

impl<ITER, MAP_OP, RET> IndexedParallelIterator for MapParIter<ITER, MAP_OP, RET>
    where ITER: IndexedParallelIterator,
          MAP_OP: Fn(ITER::Item) -> RET + Sync,
{
    ...
}
```

#### Converting a parallel iterator into a producer

So this brings us to the question: how do we convert a `MapParIter`
into a `MapProducer`? My first thought was to have a method like
`into_producer` as part of the `IndexedParallelIterator` trait:

```rust
// Initial, incorrect approach:
pub trait IndexedParallelIterator {
    type Producer;

    fn into_producer(self) -> Self::Producer;
}
```

This would then be called by the `sum` method to get a producer, which
we could pass to the `sum_producer` method we wrote
earlier. Unfortunately, while this setup is nice and simple, it
doesn't actually get the ownership structure right. What happens is
that ownership of the iterator passes to the `into_producer` method,
which then returns a producer -- so all the resources owned by the
iterator must either be transfered to the producer, or else they will
be freed when `into_producer` returns. But it often happens that we
have shared resources that the producer just wants to borrow, so that
it can cheaply split itself without having to track ref counts or
otherwise figure out when those resources can be freed.

Really the problem here is that `into_producer` puts the caller in
charge of deciding how long the producer lives. What we want is a way
to get a producer that can only be used for a limited duration. The
best way to do that is with a *callback*. The idea is that instead of
calling `into_producer`, and then having a producer returned to us, we
will call `with_producer` and pass in a closure as argument. This
closure will then get called with the producer. This producer may have
borrowed references into shared state. Once the closure returns, the
parallel operation is done, and so that shared state can be freed.

The signature looks like this:

```rust
trait IndexedParallelIterator {
    ...
    fn with_producer<CB>(self, callback: CB)
        where CB: ProducerCallback<Self::Item>;
}
```

Now, if you know Rust well, you might be surprised here. I said that
`with_producer` takes a closure as argument, but typically in Rust
a closure is some type that implements one of the closure traits
(probably `FnOnce`, in this case, since we only plan to do a single
callback). Instead, I have chosen to use a custom trait, `ProducerCallback`,
defined as follows:

```rust
trait ProducerCallback<ITEM> {
    type Output;
    fn callback<P>(self, producer: P) -> Self::Output
        where P: Producer<Item=ITEM>;
}
```

Before I get into the reason to use a custom trait, let me just show
you how one would implement `with_producer` for our map iterator type
(actually, this is a simplified version, I'll revisit this example in
a bit to show the gory details):

```rust
impl IndexedParallelIterator for MapParIter<ITER, MAP_OP, RET>
    where ITER: ParallelIterator,
          MAP_OP: Fn(ITER::Item) -> RET + Sync
{
    fn with_producer<CB>(self, callback: CB)
        where CB: ProducerCallback<Self::Item>
    {
        let base_producer = /* convert base iterator into a
                               producer; more on this below */;
        let map_producer = MapProducer {
            base: base_producer,
            map_op: &self.map_op, // borrow the map op!
        };
        callback.callback(map_producer);
    }
}
```

So why did I choose to define a `ProducerCallback` trait instead of
using `FnOnce`? The reason is that, by using a custom trait, we can
make the `callback` method *generic* over the kind of producer that
will be provided. As you can see below, the `callback` method just
says it takes some producer type `P`, but it doesn't get more specific
than that:

```rust
    fn callback<P>(self, producer: P) -> Self::Output
        where P: Producer<Item=ITEM>;
        //    ^~~~~~~~~~~~~~~~~~~~~~
        //
        // It can be called back with *any* producer type `P`.
```

In contrast, if I were to use a `FnOnce` trait, I would have to write
a bound that specifies the producer's type (even if it does so through
an associated type). For example, to use `FnOnce`, we might change the
`IndexedParallelIterator` trait as follows:

```rust
trait IndexedParallelIteratorUsingFnOnce {
    type Producer: Producer<Self::Item>;
    //   ^~~~~~~~
    //
    // The type of producer this iterator creates.

    fn with_producer<CB>(self, callback: CB)
        where CB: FnOnce(Self::Producer);
        //               ^~~~~~~~~~~~~~
        //
        // The callback can expect a producer of this type.
}
```

(As an aside, it's conceivable that we could add the ability to write
where clauses like `CB: for<P: Producer> FnOnce(P)`, which would be
the equivalent of the custom trait, but we don't have that. If you're
not familiar with that `for` notation, that's fine.)

You may be wondering what it is so bad about adding a `Producer`
associated type. The answer is that, in order for the `Producer` to be
able to contain borrowed references into the iterator, its type will
have to name lifetimes that are internal to the `with_producer`
method. This is because the the iterator is owned by the
`with_producer` method. But you can't write those lifetime names
as the value for an associated type. To see what I mean,
imagine how we would write an `impl` for our modified
`IndexedParallelIteratorUsingFnOnce` trait:

```rust
impl<ITER, MAP_OP, RET> IndexedParallelIteratorUsingFnOnce
    for MapParIter<ITER, MAP_OP, RET>
    where ITER: IndexedParallelIteratorUsingFnOnce,
          MAP_OP: Fn(ITER::Item) -> RET + Sync,
{
    type Producer = MapProducer<'m, ITER::Producer, MAP_OP, RET>;
    //                          ^~
    //
    // Wait, what is this lifetime `'m`? This is the lifetime for
    // which the `map_op` is borrowed -- but that is some lifetime
    // internal to `with_producer` (depicted below). We can't
    // name lifetimes from inside of a method from outside of that
    // method, since those names are not in scope here (and for good
    // reason: the method hasn't "been called" here, so it's not
    // clear what we are naming).

    fn with_producer<CB>(self, callback: CB)
        where CB: FnOnce(Self::Producer)
    {
        self.base.with_producer(|base_producer| {
            let map_producer = MapProducer { // +----+ 'm
                base: base_producer,         //      |
                map_op: &self.map_op,        //      |
            };                               //      |
            callback(map_producer);          //      |
        })                                   // <----+

    }
}
```

Using the generic `ProducerCallback` trait totally solves this
problem, but it does mean that writing code which calls
`with_producer` is kind of awkward. This is because we can't take
advantage of Rust's builtin closure notation, as I was able to do in
the previous, incorrect example. This means we have to "desugar" the
closure manually, creating a struct that will store our environment.
So if we want to see the full gory details, implementing
`with_producer` for the map combinator looks like this (btw, here is
the [actual code][wpmap] from Rayon):

[wpmap]: https://github.com/nikomatsakis/rayon/blob/312fc8ccd7a28289138d2b0d3ce16dfec6269b04/src/par_iter/map.rs#L59-L90

```rust
impl IndexedParallelIterator for MapParIter<ITER, MAP_OP, RET>
    where ITER: ParallelIterator,
          MAP_OP: Fn(ITER::Item) -> RET + Sync
{
    fn with_producer<CB>(self, callback: CB)
        where CB: ProducerCallback<RET>
    {
        let my_callback = MyCallback { // defined below
            callback: callback,
            map_op: &self.map_op,
        };
        
        self.base.with_producer(my_callback);
        
        struct MyCallback<'m, MAP_OP, CB> {
            //          ^~
            //
            // This is that same lifetime `'m` we had trouble with
            // in the previous example: but now it only has to be
            // named from *inside* `with_producer`, so we have no
            // problems.
            
            callback: CB,
            map_op: &'m MAP_OP
        }
        
        impl<'m, ITEM, MAP_OP, CB> ProducerCallback<ITEM> for MyCallback<'m, MAP_OP, CB>
            where /* omitted for "brevity" :) */
        {
            type Output = (); // return type of `callback`

            // The method that `self.base` will call with the
            // base producer:
            fn callback<P>(self, base_producer: P)
                where P: Producer<Item=ITEM>
            {
                // Wrap the base producer in a MapProducer.
                let map_producer = MapProducer {
                   base: base_producer,
                   map_op: self.map_op,
                };
                
                // Finally, callback the original callback,
                // giving them out `map_producer`.
                self.callback.callback(map_producer);
            }
        }
    }
}
```

### Conclusions

OK, whew! We've now covered **parallel producers** from start to
finish. The design you see here did not emerge fully formed: it is the
result of a lot of iteration. This design has some nice features, many
of which are shared with sequential iterators:

- **Efficient fallback to sequential processing.** If you are
  processing a small amount of data, we will never bother with
  "splitting" the producer, and we'll just fallback to using the same
  old sequential iterators you were using before, so you should have
  very little performance loss. When processing larger amounts of
  data, we will divide into threads -- which you want -- but when the
  chunks get small enough, we'll use the same sequential processing to
  handle the leaves.
- **Lazy, no allocation, etc.** You'll note that nowhere in any of the
  above code did we do any allocation or eager computation.
- **Straightforward, no unsafe code.** Something else that you didn't
  see in this blog post: unsafe code. All the unsafety is packaged up
  in Rayon's join method, and most of the parallel iterator code just
  leverages that. Overall, apart from the manual closure "desugaring"
  in the last section, writing producers is really pretty
  straightforward.
  
#### Things I learned
  
My last point above -- that writing producers is fairly
straightforward -- was certainly not always the case: the initial
designs required a lot of more "stuff" -- phantom types, crazy
lifetimes, etc. But I found that these are often signs that your
traits could be adjusted to make things go more smoothly. Some of the
primary lessons follow.

**Align input/output type parameters on traits to go with dataflow.**
One of the biggest sources of problems for me was that I was overusing
associated types, which wound up requiring a lot of phantom types and
other things. At least in these cases, what worked well as a rule of
thumb was this: if data is "flowing in" to the trait, it should be an
input type parameter. It data is "flowing out", it should be an
associated type. So, for example, producers have an associated type
`Item`, which indicates the kind of data a `Producer` or iterator will
produce, is an associated type. But the `ProducerCallback<T>` trait is
parameteried over `T`, the type of that the base producer will create.
  
**Choose RAII vs callbacks based on who needs control.** When
designing APIs, we often tend to prefer RAII over callbacks. The
immediate reason is often superficial: callbacks lead to rightward
drift. But there is also a deeper reason: RAII can be more flexible.

Effectively, whether you use the RAII pattern or a callback, there is
always some kind of dynamic "scope" associated with the thing you are
doing.  If you are using a callback, that scope is quite explicit: you
will invoke the callback, and the scope corresponds to the time while
that callback is executing. Once the callback returns, the scope is
over, and you are back in control.

With RAII, the scope is open-ended. You are returning a value to your
caller that has a destructor -- this means that the scope lasts until
your caller chooses to dispose of that value, which may well be
**never** (particularly since they could leak it). That is why I say
RAII is more flexible: it gives the caller control over the scope of
the operation.  Concretely, this means that the caller can return the
RAII value up to their caller, store it in a hashmap, whatever.

But that control also comes at a cost to you. For example, if you have
resources that have to live for the entire "scope" of the operation
you are performing, and you are using a callback, you can easily
leverage the stack to achieve this. Those resources just live on your
stack frame -- and so naturally they are live when you call the
callback, and remain live until the callback returns. But if you are
using RAII, you have to push ownership of those resources into the
value that you will return. This in turn can make borrowing and
sharing harder.

So, in short, if you can align the scopes of your program with
callbacks and the stack frame, everthing works out more easily, but
you lose some flexibility on the part of your callers (and you incur
some rightward drift). Whether that is ok will depend on the context
-- in the case of Rayon, it's perfectly fine. The real user is just
calling `sum`, and they have to block until `sum` returns anyway to
get the result. So it's no problem if `sum` internally uses a callback
to phase the parallel operation. But in other contexts the
requirements may be different.

#### What's to come

I plan to write up a third blog post, about parallel consumers, in the
not too distant future. But I might take a break for a bit, because I
have a bunch of other half-finished posts I want to write up, covering
topics like specialization, the borrow checker, and a nascent grammar
for Rust using LALRPOP.
