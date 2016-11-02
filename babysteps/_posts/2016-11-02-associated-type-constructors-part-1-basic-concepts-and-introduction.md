---
layout: post
title: 'Associated type constructors, part 1: basic concepts and introduction'
---

So for the end of last week, I was at Rust Belt Rust. This was
awesome.  And not only because the speakers and attendees at Rust Belt
Rust were awesome, though they were. But also because it gave aturon,
withoutboats, and I a chance to talk over a lot of stuff in person. We
covered a lot of territory and so I wanted to do a series of blog
posts trying to write down some of the things we were thinking so as
to get other people's input.

The first topic I'm going to focus on is [RFC 1598][], which is a
proposal by withoutboats to add **associated-type constructors** (ATC)
to the language. ATC makes it possible to have "generic" associated
types, which in turn means we can support important patterns like
collection and iterable traits.

ATC also (as we will see) potentially subsumes the idea of
**higher-kinded types**. A big focus of our conversation was on
elaborating a potential alternative design based on HKT, and trying to
see whether choosing to add ATC would lock us into a suboptimal path.

This is quite a big topic, so I'm going to spread it out over many
posts. **This first post will introduce the basic idea of associated
type constructors. It also gives various bits of background
information on Rust's trait system and how type inference works. A
certain familiarity with Rust is expected, but expertise should not be
necessary.**

**Aside:** Now higher-kinded types especially are one of those PL
topics that **sound** forebodingly complex and kind of abstract (like
monads). But once you learn what it is, you realize it's actually
relevant to your life (unlike monads). So I hope to break it down in a
relatively simple way.

(Oh, and I'm just trolling about monads. Sorry, couldn't resist. Don't
hate me.)

<!-- more -->

### Background: traits and associated types

Before I can get to [RFC 1598][], let me lay out a bit of
background. This post is going to be talking a lot about
traits. Traits are Rust's version of a generic interface. Naturally,
these traits can define a bunch of methods that are part of the
interface, but they can also define **types** that are part of the
interface. We call these **associated types**. So, for example,
consider the `Iterator` trait:

```rust
trait Iterator {
    type Item;
    fn next(&mut self) -> Option<Self::Item>;
}
```

This means that every implementation of `Iterator` must specify both a
`next()` method, which defines how we iterate, as well as the type
`Item`, which defines what kind of values this iterator produces.  The
two items are linked, since the return value of `next()` is
`Self::Item`.

The notation `Self::Item` means "the `Item` defined in the impl for
the type `Self`" -- in other words, the `Item` type defined for this
iterator. This notation is actually shorthand for something more
explicit that spells out all the parts: `<Self as Iterator>::Item` --
here we are saying "the `Item` type defined in the implementation of
`Iterator` for the type `Self`". (I prefer to call such paths "fully
qualified", but in the past they have sometimes been called "UFCS" in
the Rust community; this stands for "universal functional call
syntax", which is a term borrowed from D, where it unfortunately means
something totally different.)

So now we can use the iterator trait to write generic code. For
example, we could write a generic routine `position` that returns the
position.  I'm going to write this code using a
[`while let`](https://doc.rust-lang.org/book/if-let.html#while-let)
loop instead of a `for` loop, so as to make the iterator protocol more
explicit:

```rust
fn position<ITER>(mut iterator: ITER, value: ITER::Item) -> Option<usize>
    where ITER: Iterator, ITER::Item: Eq,
{
    let mut index = 0;
    while let Some(v) = iterator.next() {
        if value == v {
            return Some(index); // found it!
        }
        index += 1;
    }
    None // did not find it
}
```

Take a look at the types in the signature there. The first argument,
`iterator` is of type `ITER`, which is a generic type parameter; the
where clause also declares that `ITER: Iterator`. So basically we just
know that `iterator`'s type is "some kind of iterator". The second
argument, `value`, has the type `ITER::Item` -- this is also a kind of
generic type. We're saying that `value` is "whatever kind of item
`ITER` produces". We could also write that in a slightly different
way, using two generic parameters:

```rust
fn position<ITER, VALUE>(mut iterator: ITER, value: VALUE) -> Option<usize>
    where ITER: Iterator<Item=VALUE>, VALUE: Eq
{
    ...
}
```

Here the `where` clause states that `ITER: Iterator<Item=VALUE>`. This
means "`ITER` is some sort of iterator producing values of type
`VALUE`".

### Running example: linked list and iterator

OK, let's elaborate out an example that I can use throughout the post.
We'll start by defining a simple collection type, `List<T>`, that is a
kind of linked list:

```rust
/// Very simple linked list. If `cell` is `None`,
/// the list is empty.
pub struct List<T> {
    cell: Option<Box<ListCell<T>>
}

/// A single cell in a non-empty list. Stores one
/// value and then another list.
struct ListCell<T> {
    value: T,
    next: List<T>
}
```

We can define some customary methods on this list:

- `new()` -- returns an empty list; 
- `prepend()` -- insert a value on the front of the list, which is
  usually best when working with singly linked lists with no
  tail pointer;
- `iter()` -- creates an iterator that yields up
  [shared references](http://intorust.com/tutorial/shared-borrows/) to
  the items in the list.

Here are some example implementations of those methods:

```rust
impl<T> List<T> {
    pub fn new() -> List<T> {
        List { cell: None }
    }
    
    pub fn prepend(&mut self, value: T) {
        // get ahold of the current head of the list, if any
        let old_head = self.cell.take();
        
        // Create a new cell to serve as the new head of the list,
        // and then store it in `self.cell`.
        let cell = ListCell { value: value, next: old_head };
        self.cell.next = Some(Box::new(cell));
    }
    
    pub fn iter<'iter>(&'iter self) -> ListIter<'iter, T> {
        ListIter { cursor: self }
    }
}
```

Let's look more at this last method, and in particular let's look at
how we can define the iterator type `ListIter` (by the way, if you'd
like to read up more on iterators and how they work, you might enjoy
[this old blog post of mine][iter], which walks through several
different kinds of iterators in more detail). The `ListIter` iterator
will basically hold a reference to a `List<T>`. At each step, if the
list is non-empty, it will return a reference to the `value` field and
then update the cursor to the next cell. That struct might look
something like this:

[iter]: /blog/2016/02/19/parallel-iterators-part-1-foundations/

```rust
/// Iterator over linked lists.
pub struct ListIter<'iter, T> {
    cursor: &'iter List<T>
}
```

The `'iter` lifetime here is the lifetime of the reference to our
list.  I called it `'iter` because the idea is that it lives as long
as the iteration is still ongoing (after that, we don't need it
anymore). Anyway, then we can implement the iterator *trait* like so:

```rust
impl<'iter, T> Iterator for ListIter<'iter, T> {
    type Item = &'iter T;
    fn next(&mut self) -> Option<&'iter T> {
        // If the list is non-empty, borrow a reference
        // to the cell (`cell`).
        if let Some(ref cell) = self.cursor.cell {
            // Point the cursor at the next cell.
            self.cursor = &cell.next;
            
            // Return reference to the value in the
            // the current cell.
            Some(&cell.value)
        } else {
            // List is empty, return `None`.
            None
        }
    }
}
```

Here you see that the impl specifies the type `Item` to be `&'iter
T`. This is sort of interesting, because, in a sense, it's not really
telling us what the type is, since we don't yet know what lifetime
`'iter` is nor what type `T` is (it'll depend on what type of values
are in the list, of course). But there is a key point here -- even
though the impl is generic, we know that given any particular type
`ListIter<'a, Foo>`, there is exactly one associated `Item` type (in
this case, `&'a Foo`).

### Background: The role of type inference

Now that we've seen the `List` example, I want to briefly go over the
role of type inference in doing trait matching. This will be very
important when we talk later about higher-kinded types. Imagine that I
have some code that uses a list like this:

```rust
fn list(v: &List<u32>) {
    let mut iter = list.iter();
    let value = iter.next();
    ...
}
```

So how does the compiler infer the type of the variable `value`? The
way that this works is by searching the declared impls. In particular,
in the call `iter.next()`, we know that the type of `iter` is
`ListIter<'foo, u32>` (for some lifetime `'foo`). We also know that
the method `next()` is part of the trait `Iterator` (actually,
figuring this out is a big job in and of itself, but I'm going to
ignore that part of it for this post and just assume it is given). So
that tells us that we have to go searching for the `Iterator` impl
that applies to `ListIter`.

We do this, basically, by iterating over all the impls that we see and
try to match up the types with the one we are looking for.  Eventually
we will come to the `ListIter` impl we saw earlier; it looks like
this:

```rust
impl<'iter, T> Iterator for ListIter<'iter, T> { ... }
```

So how do we relate these generic impl parameters (`'iter`, `T`) to
the type we have at hand `ListIter<'foo, u32>`? We do this by
replacing those parameters with "inference variables", which I will
denote with a leading `?` -- lifetime variables will be lower-case,
type variables up-ercase. So that means that the impl type looks like
something like `ListIter<?iter, ?T>`. We then try to figure out what
values of those variables will make the two types the same. In this
case, `?iter` will map to `'foo` and `?T` will map to `u32`.

Once we know how to map `?iter` and `?T`, we can look at the actual
signature of `next()` as declared in the impl and apply that same mapping:

```rust
// Signature as declared, written in a more explicit style:
fn next(self: &mut ListIter<'iter, T>) -> Option<&'iter T>;

// Signature with mapping applied
fn next(self: &mut ListIter<'foo, u32>) -> Option<&'foo u32>;
```

Now we can see that the type of `value` is the (mapped) return type of
this signature, and hence that it must be `Option<&'foo u32>`. Very
good.

Some key points here:

- When doing trait selection, we replace the generic parameters
  on the impl (e.g., `T`, `'iter`) with variables (`?T`, `?iter`).
- We use unification to then figure out what those variables must be.

### Associated type constructors: the iterable trait

OK, so far we've seen that we can define an `Iterator` trait that lets
us operate generically over iterators like `ListIter<'iter,
T>`. That's very useful, but you might be wondering if it's possible
to define a `Collection` trait that lets us operate generically over
collections, like `List<T>`. Perhaps something like this:

```rust
// Collection trait, take 1.
trait Collection<Item> {
    // create an empty collection of this type:
    fn empty() -> Self;
    
    // add `value` to this collection in some way:
    fn add(&mut self, value: Item);

    // iterate over this collection:
    fn iterate(&self) -> Self::Iter;
    
    // the type of an iterator for this collection (e.g., `ListIter`)
    type Iter: Iterator<Item=Item>;
}
```

If we try to write an impl of this collection for `List<T>`, we will
find that it *almost* works, but not quite. Let's give it a try!

```rust
impl<T> Collection<T> for List<T> {
    fn empty() -> List<T> {
        List::new()
    }        

    fn add(&mut self, value: T) {
        self.prepend(value);
    }
    
    fn iterate<'iter>(&'iter self) -> ListIter<'iter, T> {
        self.iter()
    }
    
    type Iter = ListIter<'iter, T>;
    //                   ^^^^^ oh, wait, this is not in scope!
}
```

Everything seems to be going great until we get to the last item, the
associated type `Iter`. Then we see that we can't actually write out
the full type -- that's because the full type needs to talk about the
lifetime `'iter` of the iteration, and that is not in scope at this
point. Remember that each call to `iterate()` will require a distinct
lifetime `'iter`.

This shows that in fact modeling *collections* is actually harder than
modeling *iterators*. Recall that, with iterators, we said that once
we know the type of an iterator, we know everything we need to know to
figure out the type of items that iterator produces. But with
*collections*, knowing the collection type (`List<T>`) does **not**
tell us everything we need to know to get the type of an iterator
(`ListIter<'iter, T>`).

[RFC 1598][] proposes to solve this problem by making it possible to
have not only *associated types* but associated type **constructors**.
Basically, associated types can themselves have generic type
parameters:

```rust
// Collection trait, take 2, using RFC 1598.
trait Collection<Item> {
    // as before
    fn empty() -> Self;
    fn add(&mut self, value: Item);

    // Here, we use associated type constructors:
    fn iterate<'iter>(&'iter self) -> Self::Iter<'iter>;
    type Iter<'iter>: Iterator<Item=Item>;
}
```

Now, writing the impl of `Collection` for `List` becomes fairly
straightforward. In fact, the only difference is the definition of the
type `Iter`:

```rust
impl<T> Collection<T> for List<T> {
    ... // same as above
    
    type Iter<'iter> = ListIter<'iter, T>;
    //        ^^^^^ brings `'iter` into scope
}
```

We could also imagine writing impls for other types, like `Vec<T>`
in the standard library:

```rust
use std::slice;
impl<T> Collection<T> for Vec<T> {
    fn empty() -> Self { vec![] }
    fn add(&mut self, value: Item) { self.push(value); }
    fn iterate<'iter>(&'iter) -> slice::Iter<'self, T> { self.iter() }
    type Iter<'iter> = slice::Iter<'iter, T>;
}
```

### Writing code that is generic over collections

Now that we have a collection trait, we can write code that works
generically over collections. That's pretty nifty. For example, this
function takes in a collection of floating point numbers and returns
to you another collection with the same numbers, but rounded down to 
the nearest integer:

```rust
fn round_all<C>(collection: &C) -> C
    where C: Collection<f32>
{
    let mut rounded = C::empty();
    for &f in c.iterate() {
        rounded.add(f.floor());
    }
    rounded
}
```

### Conclusion

That's it for today. Let's review what we covered thus far:

- Traits today can define **associated types**;
  - but, this type cannot make use of any types or lifetimes that aren't
    part of the implementing type
- Whenever you have something with **generic parameters**, like an `impl`, `fn`, or `struct`,
  inference is used to determine the value of those parameters;
  - this means that if you try to extend the sorts of thing that a generic parameter can
    be used to represent (such as permitting things that are generic over constants), you
    have to think about how it will interact with inference.
- If you have a collection type like `List<T>`, the iterator usually
  includes a lifetime `'iter` that is not part of the original type (`ListIter<'iter, T>`);
  - therefore, you cannot model a `Collection` trait today in Rust, at least not
    in a nice way.
    - There are some tricks I didn't cover. =)
- **Associated type constructors** are basically just "generic" associated types;
  - this is great for modeling `Collection`.

[RFC 1598]: https://github.com/rust-lang/rfcs/pull/1598

