---
layout: post
title: 'Parallel iterators, part 3: Consumers'
categories: [Rust, Rayon]
---

This post is the (long awaited, or at least long promised) third post
in my series on Rayon's parallel iterators. The previous two posts
were some time ago, but I've been feeling inspired to push more on
Rayon lately, and I remembered that I had never finished this blog
post series.

Here is a list of the other posts in the series. If you haven't read
them, or don't remember them, you will want to do so before reading
this one:

1. The first post, ["Foundations"][part-a], explains how sequential
   iterators work. It is also a nice introduction to some of the key
   techniques for zero-cost abstraction.
2. The second post, ["Producers"][part-b], then shows how we can adapt
   the sequential iterator approach to permit parallel iteration.  It
   focuses on the concept of **parallel producers**: these are
   basically splittable iterators. They give you the ability to say
   "break this producer into two producer, one of which produces the
   left half, and one the right half". You can then process those two
   halves in parallel. When the number of work items gets small
   enough, you can convert a producer into a sequential iterator and
   consume it sequentially.

This third post will introduce **parallel consumers**. Parallel
consumers are the dual to a parallel producer: they abstract out the
parallel algorithm. We'll use this to extend beyond the `sum()` action
and cover how we can implementation a `collect()` operation that
efficiently builds up a big vector of data.

(Note: originally, I had intended this third post to cover how
combinators like `filter()` and `flat_map()` work. These combinators
are special because they produce a variable number of
elements. However, in writing this post, it became clear that it would
be better to first introduce consumers, and then cover how to extend
them to support `filter()` and `flat_map()`.)

[part-a]: {{ site.baseurl }}/blog/2016/02/19/parallel-iterators-part-1-foundations/
[part-b]: {{ site.baseurl }}/blog/2016/02/25/parallel-iterators-part-2-producers/

### Motivating example

In this post, we'll cover two examples. The first will be the running
example from the previous two posts, a dot-product iterator chain:

```rust
vec1.par_iter()
    .zip(vec2.par_iter())
    .map(|(i, j)| i * j)
    .sum()
```

After that, we'll look at a slight variation, where instead of summing
up the partial products, we collect them into a vector:

```rust
let c: Vec<_> =
  vec1.par_iter()
      .zip(vec2.par_iter())
      .map(|(i, j)| i * j)
      .collect(); // <-- only thing different
```

### Review: parallel producers

In the [second post][part-b], I introduced the basics of how parallel
iterators work. The key idea was the `Producer` trait, which is a
variant on iterators that is amenable to "divide-and-conquer"
parallelization:

```rust
trait Producer: IntoIterator {
  // Divide into two producers, one of which produces data
  // with indices `0..index` and the other with indices `index..`.
  fn split_at(self, index: usize) -> (Self, Self);
}
```

Unlike normal iterators, which only support extracting one element at
a time, a parallel producer can be split into two -- and this can
happen again and again. At some point, when you think you've got small
enough pieces, you can convert it into an iterator (you see it extends
`IntoIterator`) and work sequentially.

To see this in action, let's revisit the `sum_producer()` function
that [I covered in my previous blog post][sum_producer];
`sum_producer()` basically executes the `sum()` operation, but
extracting data from a producer. Later on in the post, we're going to
see how consumers abstract out the *sum* part of this code, leaving us
with a generic function that can be used to execute all sorts of
parallel iterator chains.

[sum_producer]: {{ site.baseurl }}/blog/2016/02/25/parallel-iterators-part-2-producers/#implementing-sum-with-producers

```rust
fn sum_producer<P>(mut producer: P, len: usize) -> i32
    where P: Producer<Item=i32>
{
  if len > THRESHOLD {
    // Input too large: divide it up
    let mid = len / 2;
    let (left_producer, right_producer) = producer.split_at(mid);
    let (left_sum, right_sum) = rayon::join(
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

### Enter parallel consumers

What we would like to do in this post is to try and make an abstract
version of this `sum_producer()` function, one that can do all kinds
of parallel operations, rather than just summing up a list of numbers.
The way we do this is by introducing the notion of a **parallel
consumer**. Consumers represent the "action" at the end of the
iterator; they define what to do with each item that gets produced:

```rust
vec1.par_iter()           // defines initial producer...
    .zip(vec2.par_iter()) // ...wraps to make a new producer...
    .map(|(i, j)| i * j)  // ...wraps again...
    .sum()                // ...defines the consumer
```

The `Consumer` trait looks like this. You can see it has a few more
moving parts than producers. 

```rust
// `Item` is the type of value that the producer will feed us.
pub trait Consumer<Item>: Send + Sized {
  // Type of value that consumer produces at the end.
  type Result: Send;

  // Splits the consumer into two consumers at `index`.
  // Also returns a *reducer* for combining their results afterwards.
  type Reducer: Reducer<Self::Result>;
  fn split_at(self, index: usize) -> (Self, Self, Self::Reducer);

  // Convert the consumer into a *folder*, which can sequentially
  // process items one by one and produce a result.
  type Folder: Folder<Item, Result=Self::Result>;
  fn into_folder(self) -> Self::Folder;
}
```

The basic workflow for driving a producer/consumer pair is as follows:

1. You start out with one producer/consumer pair; using `split_at()`,
   these can be split into two pairs and then those pairs can be
   processed in parallel. Splitting a consumer also returns something
   called a *reducer*, we'll get to its role in a bit.
2. At some point, to process sequentially, you convert the producer
   into an iterator using `into_iter()` and convert the consumer into
   a *folder* using `into_folder()`. You then draw items from the
   producer and feed them to the folder. At the end, the folder
   produces a result (of type `C::Result`, where `C` is the consumer
   type) and this is returned.
3. As we walk back up the stack, at each point where we had split the
   consumer into two, we now have two results, which must be combined
   using the *reducer* (also returned by `split_at()`).

Let's take a closer look at the folder and reducer. Folders are
defined by [the `Folder` trait][folder], a simplified version of which
is shown below. They can be fed items one by one and, at the end,
produce some kind of result:

```rust
pub trait Folder<Item> {
  type Result;
  
  /// Consume next item and return new sequential state.
  fn consume(self, item: Item) -> Self;
  
  /// Finish consuming items, produce final result.
  fn complete(self) -> Self::Result;
}
```

Of course, when we split, we will have two halves, both of which will
produce a result. Thus when a consumer splits, it also returns a
*reducer* that knows how to combine those results back
again. [The `Reducer` trait][reducer] is shown below. It just consists
of a single method `reduce()`:

```rust
pub trait Reducer<Result> {
  /// Reduce two final results into one; this is executed after a
  /// split.
  fn reduce(self, left: Result, right: Result) -> Result;
}
```

### Generalizing `sum_producer()`

In effect, the consumer abstracts out the "parallel operation" that
the iterator is going to perform. Armed with this consumer trait, we
can now revisit the `sum_producer()` method we saw before. That function
was specific to adding up a series of values, but we'd like to produce
an abstract version that works for any consumer. In the Rayon source,
[this function is called `bridge_producer_consumer`][bpc]. Here is a
simplified version. It is helpful to compare it to `sum_producer()`
from before; I'll include some "footnote comments" (like `[1]`, `[2]`)
to highlight those differences.

```rust
// `sum_producer` was specific to summing up a series of `i32`
// values, which produced another `i32` value. This version is generic
// over any producer/consumer. The consumer consumes `P::Item` (whatever
// the producer produces) and then the fn as a whole returns a
// `C::Result`.
fn bridge_producer_consumer<P, C>(len: usize,
                                  mut producer: P,
                                  mut consumer: C)
                                  -> C::Result
    where P: Producer, C: Consumer<P::Item>
{
  if len > THRESHOLD {
    // Input too large: divide it up
    let mid = len / 2;
    
    // As before, split the producer into two halves at the mid-point.
    let (left_producer, right_producer) = producer.split_at(mid);

    // Also divide the consumer into two consumers.
    // This also gives us a *reducer* for later.
    let (left_consumer, right_consumer, reducer) = consumer.split_at(mid);
        
    // Parallelize the processing of the left/right halves,
    // producing two results.
    let (left_result, right_result) =
      rayon::join(
        || bridge_producer_consumer(mid, left_producer, left_consumer),
        || bridge_producer_consumer(len - mid, right_producer, right_consumer));
        
    // Finally, reduce the two intermediate results.
    // In `sum_producer`, this was `left_result + right_result`,
    // but here we use the reducer.
    reducer.reduce(left_result, right_result)
  } else {
    // Input too small: process sequentially.
    
    // Get a *folder* from the consumer.
    // In `sum_producer`, this was `let mut sum = 0`.
    let mut folder = consumer.into_folder();
    
    // Convert producer into sequential iterator.
    // Feed each item to the folder in turn.
    // In `sum_producer`, this was `sum += item`.
    for item in producer {
      folder = folder.consume(item);
    }
    
    // Convert the folder into a result.
    // In `sum_producer`, this was just `sum`.
    folder.complete()
  }
}
```

### Implementing the consumer for `sum()`

Next, let's look at how one might implement the `sum` consumer, so
that we can use it with `bridge_producer_consumer()`. As before, we'll
just focus on a `sum` that works on `i32` values, to keep things
relatively simple. We'll start out by declaring a trio of three types
(consumer, folder, and reducer).

```rust
struct I32SumConsumer {
  // This type requires no state. This will be important
  // in the next post!
}
struct I32SumFolder {
  // Current sum thus far.
  sum: i32
}
struct I32SumReducer {
  // No state here either.
}
```

Next, let's implement the `Consumer` trait for `I32SumConsumer`:

```rust
impl Consumer for I32SumConsumer {
  type Folder = I32SumFolder;
  type Reducer = I32SumReducer;
  type Result = i32;
  
  // Since we have no state, "splitting" just means making some
  // empty structs:
  fn split_at(self, _index: usize) -> (Self, Self, Self::Result) {
    (I32SumConsumer { }, I32SumConsumer { }, I32SumReducer { })
  }

  // Folder starts out with a sum of zero.
  fn into_folder(self) -> Self::Folder {
    I32SumFolder { sum: 0 }
  }
}
```

The folder is also very simple. It takes each value and
adds it to the current sum.

```rust
impl Folder<i32> for I32SumFolder {
  type Result = i32;
  
  fn consume(self, item: i32) -> Self {
    // we take ownership the current folder
    // at each step, and produce a new one
    // as the result:
    I32SumFolder { sum: self.sum + item }
  }
    
  fn complete(self) -> i32 {
    self.sum
  }
}
```

And, finally, the reducer just sums up two sums. The `self` goes
unused since our reducer doesn't have any state of its own.

```rust
impl Reducer<i32> for I32SumFolder {
  fn reduce(self, left: i32, right: i32) -> i32 {
    left + right
  }
}
```

### Implementing the consumer for `collect()`

Now that we've built up this generic framework for consumers, let's
put it to use by defining a second consumer. This time I want to
define how `collect()` works; just like in sequential iterators,
`collect()` allows users to accumulate the parallel items into a
collection. In this case, we're going to examine one particular
variant of `collect()`, which writes values into a vector:

```rust
let c: Vec<_> =
  vec1.par_iter()
      .zip(vec2.par_iter())
      .map(|(i, j)| i * j)
      .collect(); // <-- only thing different
```

In fact, internally, Rayon's `collect()` for vectors is
[written in terms of a more efficient primitive][collect],
`collect_into()`. `collect_into()` takes a mutable reference to a
vector and stores the results in there: this allows you to re-use a
pre-existing vector and avoid allocation overheads. It's particularly
good for [double buffering][] scenarios. To use `collect_into()`
explicitly, one would write something like:

```rust
  let mut c: Vec<_> = vec![];
  vec1.par_iter()
      .zip(vec2.par_iter())
      .map(|(i, j)| i * j)
      .collect_into(&mut c);
```

`collect_into()` first ensures that the vector has enough capacity for
the items in the iterator and then creates a particular consumer that,
for each item, will store it into the appropriate place in the vector.

We're going to walk through a simplified version of the
`collect_into()` consumer. This version will be specialized to vectors
of `i32` values; moreover, it's going to avoid any use of unsafe code
and just assume that the vector is initialized to the right length
(perhaps with `0` values). The [real version][collect_consumer] works
for arbitrary types and avoids initialization by using a dab of unsafe
code (just about the only unsafe code in the parallel iterators part
of Rayon, actually).

Let's start with the type definitions for the consumer, folder, and
reducer. They look like this:

```rust
struct I32CollectVecConsumer<'c> {
  data: &'c mut [i32],
}
struct I32CollectVecFolder<'c> {
  data: &'c mut [i32],
  index: usize,
}
struct I32SumReducer {
}
```

These type definitions kind of suggest to you an outline for this is
going to work. When the consumer starts, it has a mutable slice of
integers that it will eventually store into (the `&'c mut [i32]`); the
lifetime `'c` here represents the span of time in which the collection
is happening. Remember that in Rust a mutable reference is also a
*unique* reference, which means that we don't have to worry about
other threads reading or messing with our array while we store into
it.

When the time comes to switch to the folder, we still have a slice to
store into, but now we also have an index. That tracks how many items we
have stored thus far.

Finally, the reducer struct is empty, because once the values are
stored, there really isn't any data to reduce. For collect, the
reduction step will just be a no-op.

OK, let's see how the consumer trait is defined. The idea here is
simple: each time the consumer is split at some index `N`, it splits
its mutable slice into two halves at `N`, and returns two consumers, one with
each half:

```rust
impl<'c> Consumer for I32VecCollectConsumer<'c> {
  type Folder = I32VecCollectFolder<'c>;
  type Reducer = I32VecCollectReducer;
  
  // The "result" of a `collect_into()` is just unit.
  // We are executing this for its side effects.
  type Result = ();
  
  fn split_at(self, index: usize) -> (Self, Self, Self::Reducer) {
    // Divide the slice into two halves at `index`:
    let (left, right) = self.data.split_at_mut(index);
    
    // Construct the new consumers:
    (I32VecCollectConsumer { data: left },
     I32VecCollectConsumer { data: right },
     I32VecCollectReducer { })
  }

  // When we convert to a folder, give over the slice and start
  // the index at 0.
  fn into_folder(self) -> Self::Folder {
    I32VecCollectFolder { data: self.data, index: 0 }
  }
}
```

The folder trait is also pretty simple. Each time we consume a new
integer, we'll store it into the slice and increment `index`:

```rust
impl Folder<i32> for I32SumFolder {
  type Result = ();
  
  fn consume(self, item: i32) -> Self {
    self.data[self.index] = item;
    I32CollectVecFolder { data: self.data, index: self.index + 1 }
  }
    
  fn complete(self) {
  }
}
```

Finally, since `collect_into()` has no result, the "reduction" step
is just a no-op:

```rust
impl Reducer<()> for I32CollectVecFolder {
  fn reduce(self, _left: (), _right: ()) {
  }
}
```

### Conclusion

This post continued our explanation of how Rayon's parallel iterators
work. Whereas the [previous post][part-b] introduced parallel
producers, this post showed how we can abstract out **parallel
consumers** as well. Parallel consumers basically represent the
"parallel actions" at the end of a parallel iterator, like `sum()` or
`collect()`.

Using parallel consumers allows us to have one common routine,
`bridge_producer_consumer()`, that is used to draw items from a
producer and feed them to a consumer. This routine thus defines
precisely the parallel logic itself, independent from any particular
parallel iterator. In future posts, we'll discuss a bit how that same
routine can also use some adaptive techniques to try and moderate
splitting overhead automatically and dynamically.

I want to emphasize something about this post and the previous one:
you may have noticed a general lack of unsafe code. **One of the very
cool things about Rayon is that the vast majority of the unsafety is
confined to the `join()` implementation.** For the most part, the
parallel iterators just build on this new abstraction.

It is hard to overstate the benefits of confining unsafe code in this
way. For one thing, I've caught a lot of bugs in the iterator code I
was writing. But even better, **it means that it is relatively easy to
unit test and review parallel iterator PRs**. We don't have to worry
about crazy data-race bugs that only crop up if we test for hours and
hours. It's enough to just make sure we use a variant of
`bridge_producer_consumer()` that splits very deeply, so that we test
the split/recombine logic.

[folder]: https://github.com/nikomatsakis/rayon/blob/a0047facd2df584c771775bd8812c02f915e577c//src/par_iter/internal.rs#L60-L72
[reducer]: https://github.com/nikomatsakis/rayon/blob/a0047facd2df584c771775bd8812c02f915e577c//src/par_iter/internal.rs#L74-L78
[consumer]: https://github.com/nikomatsakis/rayon/blob/a0047facd2df584c771775bd8812c02f915e577c//src/par_iter/internal.rs#L33-L58
[bpc]: https://github.com/nikomatsakis/rayon/blob/a0047facd2df584c771775bd8812c02f915e577c//src/par_iter/internal.rs#L170-L197
[collect]: https://github.com/nikomatsakis/rayon/blob/a0047facd2df584c771775bd8812c02f915e577c/src/par_iter/from_par_iter.rs#L39-L43
[collect_consumer]: https://github.com/nikomatsakis/rayon/blob/a0047facd2df584c771775bd8812c02f915e577c/src/par_iter/collect/consumer.rs
[double buffering]: https://en.wikipedia.org/wiki/Double_buffering
