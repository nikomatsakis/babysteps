---
categories:
- Rust
- RustPattern
date: "2018-09-02T00:00:00Z"
slug: rust-pattern-iterating-an-over-a-rc-vec-t
title: 'Rust pattern: Iterating an over a Rc<Vec<T>>'
---

This post examines a particular, seemingly simple problem: given
ownership of a `Rc<Vec<u32>>`, can we write a function that returns an
`impl Iterator<Item = u32>`? It turns out that this is a bit harder
than it might at first appear -- and, as we'll see, for good
reason. I'll dig into what's going on, how you can fix it, and how we
might extend the language in the future to try and get past this
challenge.

### The goal

To set the scene, let's take a look at a rather artifical function
signature. For whatever reason, this function has to take
ownership of an `Rc<Vec<u32>>` and it wants to return an `impl
Iterator<Item = u32>`[^impl_trait] that iterates over that vector.

[^impl_trait]: This just means it wants to return "some iterator that yields up `u32` values".

```rust
fn iterate(data: Rc<Vec<u32>>) -> impl Iterator<Item = u32> {
    ... // what we want to write!
}
```

(This post was inspired by a problem we hit in the NLL working group.
The details of that problem were different -- for example, the vector
in question was not given as an argument but instead cloned from another
location -- but this post uses a simplified example so as to focus on
interesting questions and not get lost in other details.)

### First draft

The first thing to notice is that our function takes ownership of a
`Rc<Vec<u32>>` -- that is, a reference counted[^immut] vector of
integers. Presumably, this vector is reference counted because it is
shared amongst many places.

[^immut]: Also worth nothing: in Rust, reference counted data is typically immutable.

**The fact that we have ownership of a `Rc<Vec<u32>>` is precisely
what makes our problem challenging.** If the function were taking a
`Vec<u32>`, it would be rather trivial to write: we could invoke
[`data.into_iter()`][into_iter] and be done with it ([try it on
play][play-move]).

Alternatively, if the function took a borrowed vector of type
`&Vec<u32>`, there would still be an easy solution. In that case, we
couldn't use `into_iter`, because that requires ownership of the
vector. But we could write `data.iter().cloned()` --
[`data.iter()`][iter] gives us back references (`&u32`) and [the
`cloned()` adapter][cloned] then "clones" them to give us back a `u32`
([try it on play][play-ref]).

[iter]: https://doc.rust-lang.org/std/primitive.slice.html#method.iter
[into_iter]: https://doc.rust-lang.org/std/vec/struct.Vec.html#method.into_iter
[cloned]: https://doc.rust-lang.org/std/iter/trait.Iterator.html#method.cloned
[play-move]: https://play.rust-lang.org/?gist=e5474c80b2f7fa290917b1bf3f522c30&version=stable&mode=debug&edition=2015
[play-ref]: https://play.rust-lang.org/?gist=e5474c80b2f7fa290917b1bf3f522c30&version=stable&mode=debug&edition=2015

But we have a `Rc<Vec<u32>>`, so what can we do? We can't invoke
[`into_iter`][into_iter], since that requires **complete** ownership
of the vector, and we only have **partial** ownership (we share this
same vector with whoever else has an `Rc` handle). So let's try using
`.iter().cloned()`, like we did with the shared reference:

```rust
// First draft
fn iterate(data: Rc<Vec<u32>>) -> impl Iterator<Item = u32> {
    data.iter().cloned()
}
```

If you [try that on playground][play-iter-rc], you'll find you get this error:

[play-iter-rc]: https://play.rust-lang.org/?gist=dbf25e623505ebbb9a118b9155107fbc&version=stable&mode=debug&edition=2015

```
error[E0597]: `data` would be dropped while still borrowed
 --> src/main.rs:4:5
   |
 4 |     data.iter().cloned()
   |     ^^^^ borrowed value does not live long enough
 5 | }
   | - borrowed value only lives until here
   |
   = note: borrowed value must be valid for the static lifetime...
```

This error is one of those frustrating error messages -- it says
*exactly* what the problem is, but it's pretty hard to understand.
(I've filed [#53882] to improve it, though I'm not yet sure what I
think it should say.) So let's dig in to what is going on.

### iter() borrows the collection it is iterating over

Fundamentally, the problem here is that when we invoke `iter`,
it borrows the variable `data` to create a reference (of type `&[u32]`).
That reference is then part of the iterator that is getting returned.
The problem is that the memory that this reference refers to is owned
by the `iterate` function, and when `iterate` returns, that memory will
be freed. Therefore, the iterator we give back to the caller will refer
to invalid memory.

[#53882]: https://github.com/rust-lang/rust/issues/53882

If we kind of 'inlined' the `iter` call a bit, what's going on would look like this:

```rust
fn iterate(data: Rc<Vec<u32>>) -> impl Iterator<Item = u32> {
    let iterator = Iterator::new(&data); // <-- call to iter() returns this
    let cloned_iterator = ClonedIterator::new(iterator); <-- call to cloned()
    cloned_iterator
}
```

Here you can more clearly see that `data` is being borrowed in the
first line.

### drops in Rust are deterministic

Another crucial ingredient is that the local variable `data` will be
"dropped" when `iterate` returns. "Dropping" a local variable means
two things:

- We run the destructor, if any, on the value within.
- We free the memory on the stack where the local variable is stored.

Dropping in Rust proceeds at fixed point. `data` is a local variable,
so -- unless it was moved before that point -- it will be dropped when
we exit its scope. (In the case of temporary values, we use a set of
syntactic rules to decide its scope.) In this case, `data` is a
parameter to the function `iterate`, so it is going to be dropped when
`iterate` returns.

Another key thing to understand is that the borrow checker does not
"control" when drops happen -- that is controlled entirely by the
syntactic structure of the code.[^lifetime] The borrow checker then comes after
and looks to see what could go wrong if that code were executed. In
this case, it seems that we have a reference to `data` that will be
returned, but -- during the lifetime of that reference -- `data` will
be dropped. That is bad, so it gives an error.

[^lifetime]: In other words, lifetime inference doesn't affect execution order. This is crucial -- for example, it is the reason we can move to [NLL] without breaking backwards compatibility.

[NLL]: https://rust-lang.github.io/rfcs/2094-nll.html

### What is the fundamental problem here?

This is actually a bit of a tricky problem to fix. The problem here is
that `Rc<Vec<u32>>` only has **shared** ownership of the `Vec<u32>`
within -- therefore, it does not offer any API that will return you a
`Vec<u32>` value. You can only get back `&Vec<u32>` values -- that is,
references to the vector inside.

**Furthermore, the references you get back will never be able to
outlive the `Rc<Vec<u32>>` value they came from!** That is, they will
never be able to outlive `data`. The reason for this is simple: once
`data` gets dropped, those references might be invalid.

So what all of this says is that we will never be able to return an
iterator over `data` unless we can somehow **transfer ownership of
`data` back to our caller**.

It is interesting to compare this example with the alternative signatures
we looked at early on:

- If `iterate` took a `Vec<u32>`, then it would have full ownership of
  the vector. It can use `into_iter` to transfer that ownership into
  an iterator and return the iterator. Therefore, **ownership was
  given back to the caller**.
- If `iterate` took a `&Vec<u32>`, it never owned the vector to begin
  with! It can use `iter` to create an iterator that references into
  that vector.  We can return that iterator to the caller without
  incident because **the data it refers to is owned by the caller, not
  us**.
  
### How can we fix it?

As we just saw, to write this function we need to find some way to
give ownership of `data` back to the caller, while still yielding up
an iterator. One way to do it is by using a `move` closure, like so
([playground][play-closure]):

[play-closure]: https://play.rust-lang.org/?gist=2fc90fb310e8fac9298d7c34a67e9a21&version=stable&mode=debug&edition=2015

```rust
fn iterate(data: Rc<Vec<u32>>) -> impl Iterator<Item = u32> {
    let len = data.len();
    (0..len).map(move |i| data[i])
}
```

So why does this work? In the first line, we just read out the length
of the `data` vector -- note that, in Rust, any vector stored in a
`Rc` is also immutable (only a full owner can mutate a vector), so we
know that this length can never change. Now that we have the length
`len`, we can create an iterator `0..len` over the integers from `0`
to `len`. Then we can map from each index `i` to the data using
`data[i]` -- since the data inside is just an integer, it gets copied
out.

In terms of ownership, the key point is that here the closure is
taking ownership of `data`. The closure is then placed into the
iterator, and the iterator is returned. **So indeed ownership of the
vector *is* passing back to the caller as part of the iterator.**

### What about if I don't have integers?

You could use the same trick to return an iterator of any type, but
you must be able to clone it. For example, you could iterate over
strings ([playground][play-strings]):

[play-strings]: https://play.rust-lang.org/?gist=ab0595b0cdbacd30a9d19493281fca52&version=stable&mode=debug&edition=2015

```rust
fn iterate(data: Rc<Vec<String>>) -> impl Iterator<Item = String> {
    let len = data.len();
    (0..len).map(move |i| data[i].clone())
}
```

Why is it important that we clone it? Why can't we return references?
This falls out from how the `Iterator` trait is designed. If you look
at the definition of iterator, it states that it **gives ownership**
of each item that it iterates over:

```rust
trait Iterator {
    type Item;
    fn next<'s>(&'s self) -> Option<Self::Item>;
    //           ^^ This would normally be written
    //           `&self`, but I'm giving it a name
    //           so I can refer to it below.
}
```

In particular, the `next` function borrows `self` **only for the
duration of the call to `next`**. `Self::Item`, the return type, does
not mention the lifetime `'s` of the self reference, so it cannot
borrow from `self`. This means that I can write generic code where we
extract an item, drop the iterator, and then go on using the item:

```rust
fn dump_first<I>(some_iter: impl Iterator<Item = I>)
where
    I: Debug,
{
    // Get an item from the iterator.
    let item = some_iter.next();
    
    // Drop the iterator early.
    std::mem::drop(some_iter);
    
    // Keep using the item.
    println!("{:?}", item);
}
```

Now, imagine what would happen it we permitted the closure to
return `move |i| &data[i]` and we then passed the resulting iterator
to `dump_first`:

1. We would first extract a reference into `data` and store it in `item`.
2. We would then drop the iterator, which in turn would drop `data`,
   potentially freeing the vector (if this is the last `Rc` handle).
3. Finally, we would then go on to use `item`, which has a reference
   into the (now possibly freed) vector.

So, the lesson is: **if you want to return an iterator over borrowed
data, per the design of the `Iterator` trait, you must be iterating
over a borrowed reference to begin with** (i.e., `iterate` would need
to take a `&Rc<Vec<u32>>`, `&Vec<u32>`, or `&[u32]`).

### How could we extend the language to help here?

#### Self references

This is an interesting question. If we focus just on the original
problem -- that is, how to return an `impl Iterator<Item = u32>` --
then most obvious thing is the idea of extending the lifetime system
to permit "self-references" -- for example, it would be nice if you
could have a struct that owns some data (e.g., our `Rc<Vec<u32>>`) and
also had a reference into that data (e.g., the result of invoking
`iter`). This might allow us a nicer way of writing the solution to
our original problem (returning an `impl Iterator<Item = u32>`). In
particular, what we effectively did in our solution was to use an
integer as a kind of "reference" into the vector -- each step, we
index again. Since indexing is very cheap, this is fine for iterating
over a vector, but it wouldn't work with (say) a `Rc<HashMap<K, V>>`.

My personal hope is that once we wrap up work on the MIR
borrow-checker (NLL) -- and we are starting to get close! -- we can
start to think about self-references and how to model them in
Rust. I'd like to transition to [a Polonius-based system][alias]
first, though.

[alias]: {{ site.baseurl }}/blog/2018/04/27/an-alias-based-formulation-of-the-borrow-checker/

#### Auxiliary values

Another possible direction that has been kicked around is having some
way for a function to return data that its caller must store, which
can then be referenced by the "real" return value. The idea would be
that `iterate` would somehow "store" the `Rc<Vec<u32>>` into its
caller's stack frame, and then return an iterator over
that. Ultimately, this is very similar to the "self-reference"
concept: the difference is that, with self-references, `iterate` has
to return one value that stores both the `Rc<Vec<u32>>` and the
iterator over it. With this "store data in caller" approach, `iterate`
would return just the iterator, but would specify that the iterator
borrows from this other value (the `Rc<Vec<u32>>`) which is returned
in a separate channel.

Interestingly, this idea of returning "auxiliary" values might permit
us to return an iterator that gives back references -- even though I
said that was impossible, per the design of the `Iterator` trait. How
could that work? Well, the problem fundamentally is that we *want* a
signature like this, where the iterator yields up `&T` references:

```rust
fn iterate<T>(data: Rc<Vec<T>>) -> impl Iterator<Item = &T>
```

Right now, we can't have this signature, because we have no lifetime
to assign to the `&T` type. In particular, the answer to the question
"where are those references borrowing from?" is that they are
borrowing from the function `iterate` itself, which won't work (as
we've seen).

But if we had some "auxiliary" slot of data that we could fill and then reference,
we might be able to give it a lifetime -- let's call it `'aux`. Then we could
return `impl Iterator<Item = &'aux T>`.

Anyway, this is just wild, irresponsible speculation. I don't have
concrete ideas for how this would work[^out]. But it's an interesting
thought.

[^out]: In terms of the underlying semantics, though, I imagine it could be a kind of sugar atop either self-references or [out pointers]. But that's sort of as far as I got. =)
[out pointers]: https://internals.rust-lang.org/t/thoughts-about-additional-built-in-pointer-types/959

### Discussion

I've opened [a users
thread](https://users.rust-lang.org/t/blog-post-series-rust-patterns/20080)
to discuss this blog post (along with other Rust pattern blog posts).

### Footnotes

