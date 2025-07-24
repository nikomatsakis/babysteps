---
layout: post
title: "Parallel Iterators Part 1: Foundations"
date: 2016-02-19T06:32:44-0500
comments: false
categories: [Rust, Rayon]
---
Since [giving a talk about Rayon at the Bay Area Rust meetup][talk],
I've been working off and on on the support for *parallel
iterators*. The basic idea of a parallel iterator is that I should be
able to take an existing iterator chain, which operates sequentially,
and easily convert it to work in parallel. As a simple example,
consider this bit of code that computes the dot-product of two
vectors:

```rust
vec1.iter()
    .zip(vec2.iter())
    .map(|(i, j)| i * j)
    .sum()
```

Using parallel iterators, all I have to do to make this run in
parallel is change the `iter` calls into `par_iter`:

```rust
vec1.par_iter()
    .zip(vec2.par_iter())
    .map(|(i, j)| i * j)
    .sum()
```

This new iterator chain is now using Rayon's parallel iterators
instead of the standard Rust ones. Of course, implementing this simple
idea turns out to be rather complicated in practice. I've had to
iterate on the design many times as I tried to add new combinators. I
wanted to document the design, but it's too much for just one blog
post. Therefore, I'm writing up a little series of blog posts that
cover the design in pieces:

- **This post: sequential iterators.** I realized while writing the
  other two posts that it would make sense to first describe
  sequential iterators in detail, so that I could better highlight
  where parallel iterators differ. This post therefore covers the
  iterator chain above and shows how it is implemented.
- Next post: parallel producers.
- Final post: parallel consumers.

[talk]:https://air.mozilla.org/bay-area-rust-meetup-january-2016/

<!-- more -->

#### Review: sequential iterators

Before we get to parallel iterators, let's start by covering how
Rust's *sequential* iterators work. The basic idea is that iterators
are lazy, in the sense that constructing an iterator chain does not
actually *do* anything until you "execute" that iterator, either with
a `for` loop or with a method like `sum`. In the example above, that
means that the chain `vec1.iter().zip(...).map(...)` are all
operations that just build up a iterator, without actually *doing*
anything. Only when we call `sum` do we start actually doing work.

In sequential iterators, the key to this is
[the `Iterator` trait][iter].  This trait is actually very simple; it
basically contains two members of interest:

```rust
trait Iterator {
    type Item; // The type of item we will produce
    fn next(&mut self) -> Option<Self::Item>; // Request the next item
}
```

[iter]: http://doc.rust-lang.org/std/iter/trait.Iterator.html

The idea is that, for each collection, we have a method that will
return some kind of iterator type which implements this `Iterator`
trait. So let's walk through all the pieces of our example iterator
chain one by one (I've highlighted the steps in comments below):

```rust
vec1.iter()              // Slice iterator (over `vec1`)
    .zip(vec2.iter())    // Zip iterator (over two slice iterators)
    .map(|(i, j)| i * j) // Map iterator
    .sum()               // Sum executor
```

##### Slice iterators

The very start of our iterator chain was a call `vec1.iter()`. Here
`vec1` is a slice of integers, so it has a type like `&[i32]`. (A
*slice* is a subportion of a vector or array.) But the `iter()` method
(and the iterator it returns) is defined generically for slices of any
type `T`. The method looks something like this (because this method
applies to all slices in every crate, you can only write an impl like
this in the standard library):

```rust
impl<T> [T] {
    fn iter(&self) -> SliceIter<T> {
        SliceIter { slice: self }
    }
}
```

It creates and returns a value of the struct `SliceIter`, which is the
type of the slice iterator (in the standard library, this type is
[`std::slice::Iter`][iter], though it's implemented somewhat
differently). The definition of `SliceIter` looks something like this:

[iter]: http://doc.rust-lang.org/std/slice/struct.Iter.html

```rust
pub struct SliceIter<'iter, T: 'iter> {
    slice: &'iter [T],
}
```

The `SliceIter` type has only one field, `slice`, which stores the
slice we are iterating over. Each time we produce a new item, we will
update this field to contain a subslice with just the remaining items.

If you're wondering what the `'iter` notation means, it represents the
*lifetime* of the slice, meaning the span of the code where that
reference is in use. In general, references can be elided within
function signatures and bodies, but they must be made explicit in type
definitions. In any case, without going into too much detail here, the
net effect of this annotation is to ensure that the iterator does not
outlive the slice that it is iterating over.

Now, to use `SliceIter` as an iterator, we must implement the
`Iterator` trait. We want to yield up a reference `&T` to each item in
the slice in turn. The idea is that each time we call `next`, we will
peel off a reference to the first item in `self.slice`, and then
adjust `self.slice` to contain only the remaining items. That looks
something like this:

```rust
impl<'iter, T> Iterator for SliceIter<'iter, T> {
    // Each round, we will yield up a reference to `T`. This reference
    // is valid for as long as the iterator is valid.
    type Item = &'iter T;

    fn next(&mut self) -> Option<&'iter T> {
        // `split_first` gives us the first item (`head`) and
        // a slice with the remaining items (`tail`),
        // returning None if the slice is empty.
        if let Some((head, tail)) = self.slice.split_first() {
            self.slice = tail; // update slice w/ the remaining items
            Some(head) // return the first item
        } else {
            None // no more items to yield up
        }
    }
}
```

##### Zip iterators

Ok, so let's return to our example iterator chain:

```rust
vec1.iter()
    .zip(vec2.iter())
    .map(|(i, j)| i * j)
    .sum()
```

We've now seen how `vec1.iter()` and `vec2.iter()` work, but what
about `zip`? The [zip iterator][zip] is an adapter that takes two
other iterators and walks over them in lockstep. The return type
of `zip` then is going to be a type `ZipIter` that just stores
two other iterators:

[zip]: http://doc.rust-lang.org/std/iter/trait.Iterator.html#method.zip

```rust
pub struct ZipIter<A: Iterator, B: Iterator> {
    a: A,
    b: B,
}
```

Here the generic types `A` and `B` represent the types of the
iterators being zipped up.  Each iterator chain has its own type that
determines exactly how it works. In this example we are going to zip
up two slice iterators, so the full type of our zip iterator will be
`ZipIter<SliceIter<'a, i32>, SliceIter<'b, i32>>` (but we never have
to write that down, it's all fully inferred by the compiler).

When implementing the `Iterator` trait for `ZipIter`, we just want the
`next` method to draw the next item from `a` and `b` and pair them up,
stopping when either is empty:

```rust
impl<A: Iterator, B: Iterator> Iterator for ZipIter<A,B> {
    type Item = (A::Item, B::Item);
    
    fn next(&mut self) -> Option<(A::Item, B::Item)> {
        if let Some(a_item) = self.a.next() {
            if let Some(b_item) = self.b.next() {
                // If both iterators have another item to
                // give, pair them up and return it to
                // the user.
                return Some((a_item, b_item));
            }
        }
        None
    }
}
```

##### Map iterators

The next step in our example iterator chain is the call to `map`:

```rust
vec1.iter()
    .zip(vec2.iter())
    .map(|(i, j)| i * j)
    .sum()
```

Map is another iterator adapter, this time one that applies a function
to each item we are iterating, and then yields the result of that
function call. The `MapIter` type winds up with three generic types:

- `ITER`, the type of the base iterator;
- `MAP_OP`, the type of the closure that we will apply at each step (in
  Rust, closures each have their own unique type);
- `RET`, the return type of that closure, which will be the type of the
  items that we yield on each step.
  
The definition looks like this:  

```rust
pub struct MapIter<ITER, MAP_OP, RET>
    where ITER: Iterator,
          MAP_OP: FnMut(ITER::Item) -> RET
{
    base: ITER,
    map_op: MAP_OP
}
```

(As an aside, here I've switched to using a where clause to write out
the constraints on the various parameters. This is just a stylistic
choice: I find it easier to read if they are separated out.)

In any case, I want to focus on the second where clause for a second:

```rust
where MAP_OP: FnMut(ITER::Item) -> RET
```

There's a lot packed in here. First, we said that `MAP_OP` was the
type of the closure that we are going to be mapping over: `FnMut` is
[one of Rust's standard closure traits](http://doc.rust-lang.org/std/ops/trait.FnMut.html);
it indicates a function that will be called repeatedly in a sequential
fashion (notice I said *sequential*; we'll have to adjust this later
when we want to generalize to parallel execution). It's called `FnMut`
because it takes an `&mut self` reference to its environment, and thus
it can mutate data from the enclosing scope.

The where clause also indicates the argument and return type of the
closure. `MAP_OP` will take one argument, `ITER::Item` -- this it the
type of item that our base iterator produces -- and it will return
values of type `RET`.

OK, now let's write the iterator itself:

```rust
impl<ITER, MAP_OP, RET> Iterator for MapIter<ITER, MAP_OP>
    where ITER: Iterator,
          MAP_OP: FnMut(P::Item) -> RET
{
    // We yield up whatever type `MAP_OP` returns:
    type Item = RET;

    fn next(&mut self) -> Option<RET> {
        match self.base.next() {
            // No more items in base iterator:
            None => None,

            // If there is an item...
            Some(item) => {
                // ...apply `map_op` and return the result:
                Some((self.map_op)(item))
            }
        }
    }
}
```

##### Pulling it all together: the sum operation

The final step is the actual summation. This turns out to be fairly
straightforward. The [actual `sum` method][sum] is designed to work over any
kind of type that can be added in a generic way, but in the interest
of simplicity, let me just give you a version of `sum` that works on
integers (I'll also write it as a free-function rather than a method):

[sum]: http://doc.rust-lang.org/std/iter/trait.Iterator.html#method.sum

```rust
fn sum<ITER: Iterator<Item=i32>>(iter: ITER) -> i32 {
    let mut result = 0;
    while let Some(v) = iter.next() {
        result += v;
    }
    result
}
```

Here we take in some iterator of type `ITER`. We don't care what kind
of iterator it is, but it must produce integers, which is what the
`Iterator<Item=i32>` bound means. Next we repeatedly call `next` to
draw all the items out of the iterator; at each step, we add them up.

##### One last little detail

There is one last piece of the iterator puzzle that I would like to
cover, because I make use of it in the parallel iterator design. In my
example, I created iterators explicitly by calling `iter`:

```rust
vec1.iter()
    .zip(vec2.iter())
    .map(|(i, j)| i * j)
    .sum()
```

But you may have noticed that in idiomatic Rust code, this explicit call to
`iter` can sometimes be elided. For example, if I were actually writing
that iterator chain, I wouldn't call `iter()` from within the call to `zip`:

```rust
vec1.iter()
    .zip(vec2)
    .map(|(i, j)| i * j)
    .sum()
```

Similarly, if you are writing a simple for loop that just goes over a
container or slice, you can often elide the call to `iter`:

```rust
for item in vec2 {
    process(item);
}
```

So what is going on here? The answer is that we have another trait
called `IntoIterator`, which defines what types can be converted
into iterators:

```rust
trait IntoIterator {
    // the type of item our iterator will produce
    type Item;
    
    // the iterator type we will become
    type IntoIter: Iterator<Item=Self::Item>;
    
    // convert this value into an iterator
    fn into_iter(self) -> Self::IntoIter;
}
```

Naturally, anything which is itself an iterator implements
`IntoIterator` automatically -- it just gets "converted" into itself,
since it is already an iterator. Container types also implement
`IntoIterator`. The usual convention is that the container type itself
implements `IntoIterator` so as to give ownership of its contents:
e.g., converting `Vec<T>` into an iterator takes ownership of the
vector and gives back an iterator yielding ownership of its `T`
elements.  However, converting a *reference* to a vector (e.g.,
``&Vec<T>`) gives back *references* to the elements `&T`. Similarly,
converting a borrowed slice like `&[T]` into an iterator also gives
back references to the elements (`&T`). We can implement
`IntoIterator` for `&[T]` like so:

```rust
impl<'iter, T> IntoIterator for &'iter [T] {
    // as we saw before, iterating over a slice gives back references
    // to the items within
    type Item = &'iter T;
    
    // the iterator type we defined earlier
    type IntoIter = SliceIter<'iter, T>;
    
    fn into_iter(self) -> SliceIter<'iter, T> {
        self.iter()
    }
}
```

Finally, the `zip` helper method uses `IntoIterator` to convert its
argument into an iterator:

```rust
trait Iterator {
    ...
    fn zip<B>(self, other: B) -> ZipIter<Self, B::IntoIter>
        where B: IntoIterator
    {
        ZipIter { a: self, b: other.into_iter() }
    }
}
```

##### Taking a step back

Now that we've covered the whole iterator chain, let's take a moment
to reflect on some interesting properties of this whole setup. First,
notice that as we create our iterator chain, nothing actually
*happens* until we call `sum`. That is, you might expect that calling
`vec1.iter().zip(vec2.iter())` would go and allocate a new vector that
contains pairs from both slices, but, as we've seen, it does not. It
just creates a `ZipIter` that holds references to both slices. In
fact, no vector of pairs is *ever* created (unless you ask for one by
calling `collect`). Thus iteration can be described as *lazy*, since
the various effects described by an iterator take place at the last
possible time.

The other neat thing is that while all of this code looks very
abstract, it actually optimizes to something very efficient. This is a
side effect of all those generic types that we saw before. They
basically ensure that the resulting iterator has a type that describes
*precisely* what it is going to do. The compiler will then generate a
custom copy of each iterator function tailored to that particular
type. So, for example, we wind up with a custom copy of `ZipIter` that
is specific to iterating over slices, and a custom copy of `MapIter`
that is specific to multiplying the results of that particular
`ZipIter`. These copies can then be optimized independently. The end
result is that our dot-product iteration chain winds up being
optimized into some very tight assembly; in fact, it even gets
vectorized. You can verify this yourself by
[looking at this example on play](http://is.gd/auN5SL) and clicking
the "ASM" button (but don't forget to select "Release" mode). Here is
the inner loop you will see:

```
.LBB0_8:
	movdqu	(%rdi,%rbx,4), %xmm1
	movdqu	(%rdx,%rbx,4), %xmm2
	pshufd	$245, %xmm2, %xmm3
	pmuludq	%xmm1, %xmm2
	pshufd	$232, %xmm2, %xmm2
	pshufd	$245, %xmm1, %xmm1
	pmuludq	%xmm3, %xmm1
	pshufd	$232, %xmm1, %xmm1
	punpckldq	%xmm1, %xmm2
	paddd	%xmm2, %xmm0
	addq	$4, %rbx
	incq	%rax
	jne	.LBB0_8
```

Neat.

### Recap

So let's review the criticial points of sequential iterators:

- They are **lazy**. No work is done until you call `next`, and then the iterator
  does the minimal amount of work it can to produce a result.
- They **do not allocate** (unless you ask them to). None of the code
  we wrote here requires allocating any memory or builds up any
  intermediate data structures. Of course, if you use an operation
  like `collect`, which accumulates the iterator's items into a vector
  or other data structure, building that data structure will require
  allocating memory.
- They are **generic and highly optimizable**. Each iterator
  combinator uses generic type parameters to represent the types of
  the prior iterator that it builds on, as well as any closures that
  it references. This means that the compiler will make a custom copy
  of the iterator specialized to that particular task, which is very
  amenable to optimization.
  - This is in sharp contrast to iterators in languages like Java,
    which are based on virtual dispatch and generic interfaces.  The
    design is similar, but the resulting code is very different.
  
So in summary, you get to write really **high-level, convenient** code
with really **low-level, efficient** performance.

