---
layout: post
title: 'Rust pattern: Rooting an Rc handle'
categories: [Rust, RustPattern]
---

I've decided to do a little series of posts about Rust compiler
errors. Each one will talk about a particular error that I got
recently and try to explain (a) why I am getting it and (b) how I
fixed it. The purpose of this series of posts is partly to explain
Rust, but partly just to gain data for myself. I may also write posts
about errors I'm not getting -- basically places where I anticipated
an error, and used a pattern to avoid it. I hope that after writing
enough of these posts, I or others will be able to synthesize some of
these facts to make intermediate Rust material, or perhaps to improve
the language itself.

### The error: Rc-rooting

The inaugural post concerns Rc-rooting. I am currently in the midst of
editing some code. In this code, I have a big vector of data:

```rust
struct Data {
  vector: Vec<Datum>
}

struct Datum {
}
```

Many different consumers are sharing this data, but in a read-only
fashion, so the data is stored in an `Rc<Data>`, and each consumer has
their own handle. Here is one such consumer:

```rust
struct Consumer {
  data: Rc<Data>
}
```

In that consumer, I am trying to iterate over the data and process it,
one datum at a time:

```rust
impl Consumer {
  fn process_data(&mut self) {
    for datum in &self.data.vector {
      self.process_datum(datum);
    }
  }

  fn process_datum(&mut self, datum: &Datum) {
    /* ... */
  } 
}
```

This seems reasonable enough, but [when I try to compile
this](https://play.rust-lang.org/?gist=e69482ca8f539f0353b0a7da5aa08b5f&version=stable),
I find that I get a borrow check error:

```
error[E0502]: cannot borrow `*self` as mutable because `self.data` is also borrowed as immutable
  --> src/main.rs:19:7
   |
18 |     for datum in &self.data.vector {
   |                   ---------      - immutable borrow ends here
   |                   |
   |                   immutable borrow occurs here
19 |       self.process_datum(datum);
   |       ^^^^ mutable borrow occurs here
```

Why is that? Well, the borrow checker is pointing out a legitimate
concern here (though the span for "immutable borrow ends here" is odd,
I [filed a
bug](https://github.com/rust-lang/rust/issues/49756)). Basically, when
I invoke `process_datum`, I am giving it both `&mut self` *and* a
reference to a `Datum`; but that datum is owned by `self` -- or, more
precisely, it's owned by a `Data`, which is in an `Rc`, and that `Rc`
is owned by `self`. This means it would be possible for
`process_datum` to cause that to get freed, e.g. by writing to `self.data`:

```rust
fn process_datum(&mut self, datum: &Datum) {
  // Overwriting `data` field will lower the ref-count
  // on the `Rc<Data>`; if this is the last handle, then
  // that would cause the `Data` to be freed, in turn invalidating
  // `datum` in the caller we looked at:
  self.data = Rc::new(Data { vector: vec![] });
  ...
}
```

Now, of course you and I know that `process_datum` is not going to
overwrite `data`, because that data is supposed to be an immutable
input. But then again -- can we say with total confidence that all
other people editing this code now and in the future know and
understand that invariant? Maybe there will be a need to swap in new
data in the future.

To fix this borrow checker bug, we need to ensure that mutating `self`
cannot cause `datum` to get freed. Since the data is in an `Rc`, one
easy way to do this is to get a second handle to that `Rc`, and store
it on the stack:

```rust
fn process_data(&mut self) {
  let data = self.data.clone(); // this is new
  for datum in &data.vector {
    self.process_datum(datum);
  }
}
```

If you try this, [you will find the code
compiles](https://play.rust-lang.org/?gist=30919dcc7f2618050a1389e2c2961341&version=stable),
and with good reason: even if `process_datum` were to modify
`self.data` now, we have a second handle onto the original data, and
it will not be deallocated until the loop in `process_data` completes.

(Note that invoking `clone` on an `Rc`, as we do here, merely
increases the reference count; it doesn't do a deep clone of the
data.)

### How the compiler thinks about this

OK, now that we understand intuitively what's going on, let's dive in
a bit into how the compiler's check works, so we can see why the code
is being rejected, and why the fixed code is accepted.

The first thing to remember is that the compiler checks **one method
at a time**, and it makes **no assumptions** about what other methods
may or may not do beyond what is specified in the types of their
arguments or their return type. This is a key property -- it ensures
that, for example, you are free to modify the body of a function and
it won't cause your callers to stop compiling[^crash]. It also ensures
that the analysis is scalable to large programs, since adding
functions doesn't make checking any individual function harder (so
total time scales linearly with the number of functions[^time]).

[^time]: Total time for the safety check, that is. Optimizations and other things are sometimes inter-procedural.

[^crash]: Or crash, as would happen without the compiler's checks.

Next, we have to apply the borrow checker's basic rule: **"While some
path is shared, it cannot be mutated."** In this case, the shared
borrow occurs in the `for` loop:

```rust
    for datum in &self.data.vector {
    //           ^^^^^^^^^^^^^^^^^ shared borrow
```

Here, the **path** being borrowed is `self.data.vector`. The
compiler's job here is to ensure that, so long as the reference
`datum` is in use, that path `self.data.vector` is not mutated
(because mutating it could cause `datum` to be freed).

So, for example, it would be an error to write `*self = ...`, because
that would overwrite `self` with a new value, which might cause the
old value of `data` to be freed, which in turn would free the vector
within, which would invalidate `datum`. Similarly, writing `self.data
= ...` could cause the vector to be freed as well (as we saw earlier).

In the actual example, we are not directly mutating `self`, but we are
invoking `process_datum`, which takes an `&mut self` argument:

```rust
  for datum in &self.data.vector {
            // ----------------- shared borrow
    self.process_datum(datum);
    //   ^^^^^^^^^^^^^ point of error
  }
```

Since `process_datum` is declared as `&mut self`, invoking
`self.process_datum(..)` is treated as a potential write to `*self`
(and `self.data`), and hence an error is reported.

Now compare what happens after the fix. Remember that we cloned
`self.data` into a local variable and borrowed *that*:

```
  let data = self.data.clone();
  for datum in &data.vector {
            // ^^^^^^^^^^^^ shared borrow
    self.process_datum(datum);
  }
```

Now that path being borrowed is `data.vector`, and so when we invoke
`self.process_datum(..)`, the compiler does not see any potential
writes to `data` (only `self`).  Therefore, no errors are
reported. Note that the compiler *still* assumes the worst about
`process_datum`: `process_datum` may mutate `*self` or
`self.data`. But even if it does so, that won't cause `datum` to be
freed, because it is borrowed from `data`, which is an independent
handle to the vector.

### Synopsis

Sometimes it is useful to clone the data you are iterating over into a
local variable, so that the compiler knows it will not be freed. If
the data is immutable, storing that data in an `Rc` or `Arc` makes
that clone cheap (i.e., O(1)). (Another way to make that clone cheap
is to use a [persistent collection type] -- such as those provided by
the [im] crate.)

[persistent collection type]: {{ site.baseurl }}/blog/2018/02/01/in-rust-ordinary-vectors-are-values/
[im]: https://crates.io/crates/im

If the data *is* mutable, there are various other patterns that you
could deploy, which I'll try to cover in follow-up articles -- but
often it's best if you can get such data into a local variable,
instead of a field, so you can track it with more precision.

### How we could accept this code in the future

There would be various ways for the compiler to accept this code: for
example, we've thought about extensions to let you declare the sets of
fields accessed by a function (and perhaps the ways in which they are
accessed), which might let you declare that `process_datum` will never
modify the `data` field.

I've also kicked around the idea of "immutable" fields from time to
time, which would basically let you declare that *nobody* will
ovewrite that field, but that gets complicated in the face of
generics. For example, one can mutate the field `data` not just by
doing `self.data = ...` but by doing `*self = ...`; and the latter
might be in generic code that works for any `&mut T`: this implies
we'd have to start categorizing the types `T` into "assignable or
not"[^cpp]. I suspect we would not go in this direction.

[^cpp]: Interestingly, C++ does this when you have `const` fields.

### Discussion

I've opened [a users
thread](https://users.rust-lang.org/t/blog-post-series-rust-patterns/20080)
to discuss this blog post (along with other Rust pattern blog posts).

### Footnotes

