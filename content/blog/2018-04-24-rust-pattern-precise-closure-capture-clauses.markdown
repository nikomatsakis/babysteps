---
layout: post
title: 'Rust pattern: Precise closure capture clauses'
categories: [Rust, RustPattern]
---

This is the **second** in a series of posts about Rust compiler
errors. Each one will talk about a particular error that I got
recently and try to explain (a) why I am getting it and (b) how I
fixed it. The purpose of this series of posts is partly to explain
Rust, but partly just to gain data for myself. I may also write posts
about errors I'm not getting -- basically places where I anticipated
an error, and used a pattern to avoid it. I hope that after writing
enough of these posts, I or others will be able to synthesize some of
these facts to make intermediate Rust material, or perhaps to improve
the language itself.

Other posts in this series:

- [Rooting an rc handle][post0]

[post0]: {{< baseurl >}}/blog/2018/04/16/rust-pattern-rooting-an-rc-handle/

### The error: closures capture too much

In some code I am writing, I have a struct with two fields. One of
them (`input`) contains some data I am reading from; the other is some
data I am generating (`output`):

[pg]: https://play.rust-lang.org/?gist=62c47ef4198dbb1c8dc2a22ea7c961a0&version=stable

```rust
use std::collections::HashMap;

struct Context {
  input: HashMap<String, u32>,
  output: Vec<u32>,
}
```

I was writing a loop that would extend the output based on the input.
The exact process isn't terribly important, but basically for each
input value `v`, we would look it up in the input map and use `0` if
not present:

```rust
impl Context {
  fn process(&mut self, values: &[String]) {
    self.output.extend(
      values
        .iter()
        .map(|v| self.input.get(v).cloned().unwrap_or(0)),
    );
  }
}
```

However, this code [will not compile][pg]:

```
error[E0502]: cannot borrow `self` as immutable because `*self.output` is also borrowed as mutable
  --> src/main.rs:13:22
     |
  10 |         self.output.extend(
     |         ----------- mutable borrow occurs here
 ...
  13 |                 .map(|v| self.input.get(v).cloned().unwrap_or(0)),
     |                      ^^^ ---- borrow occurs due to use of `self` in closure
     |                      |
     |                      immutable borrow occurs here
  14 |         );
     |         - mutable borrow ends here
```

As the various references to "closure" in the error may suggest, it
turns out that this error is tied to the closure I am creating in the
iterator. If I rewrite the loop to not use `extend` and an iterator,
but rather a for loop, [everything builds][pgfix1]:

[pgfix1]: https://play.rust-lang.org/?gist=9d212e98a66a27c4a95790b9b9c3f30d&version=stable

```rust
impl Context {
  fn process(&mut self, values: &[String]) {
    for v in values {
      self.output.push(
        self.input.get(v).cloned().unwrap_or(0)
      );
    }
  }
}
```

What is going on here?

### Background: The closure desugaring

The problem lies in how closures are desugared by the compiler. When
you have a closure expression like this one, it corresponds to
*deferred code execution*:

```rust
|v| self.input.get(v).cloned().unwrap_or(0)
```

That is, `self.input.get(v).cloned().unwrap_or(0)` doesn't execute
*immediately* -- rather, it executes later, each time the closure is
called with some specific `v`. So the closure expression itself just
corresponds to creating some kind of "thunk" that will hold on to all
the data it is going to need when it executes -- this "thunk" is
effectively just a special, anonymous struct. Specifically, it is a struct
with one field for each **local variable** that appears in the closure body;
so, something like this:

```rust
MyThunk { this: &self }
```

where `MyThunk` is a dummy struct name. Then `MyThunk` implements
the `Fn` trait with the actual function body, but each place that we
wrote `self` it will substitute `self.this`:

```rust
impl Fn for MyThunk {
  fn call(&self, v: &String) -> u32 {
    self.this.input.get(v).cloned().unwrap_or(0)
  }
}
```

(Note that you cannot, today, write this impl by hand, and I have
simplified the trait in various ways, but hopefully you get the idea.)

### So what goes wrong?

So let's go back to the example now and see if we can see why we are
getting an error. I will replace the closure itself with the `MyThunk`
creation that it desugars to:

```rust
impl Context {
  fn process(&mut self, values: &[String]) {
    self.output.extend(
      values
        .iter()
        .map(MyThunk { this: &self }),
        //   ^^^^^^^^^^^^^^^^^^^^^^^
        //   really `|v| self.input.get(v).cloned().unwrap_or(0)`
    );
  }
}
```

Maybe now we can see the problem more clearly; the closure wants to
hold onto a shared reference to the **entire `self` variable**, but
then we also want to invoke `self.output.extend(..)`, which requires a
mutable reference to `self.output`. This is a conflict! Since the
closure has shared access to the entirety of `self`, it might (in its
body) access `self.output`, but we need to be mutating that.

The root problem here is that the closure is capturing `self` but it
is only **using** `self.input`; this is because closures always
capture entire local variables. As discussed in the [previous post in
this series][post0], the compiler only sees one function at a time,
and in particular it does not consider the closure body while checking
the closure creator. 

To fix this, we want to refine the closure so that instead of
capturing `self` it only captures `self.input` -- but how can we do that,
given that closures only capture entire local variables? The way to do that
is to introduce a local variable, `input`, and initialize it with
`&self.input`. Then the closure can capture `input`:

[pgfix2]: https://play.rust-lang.org/?gist=149ccc90dd732496467f43d2a44532b8&version=stable

```rust
impl Context {
  fn process(&mut self, values: &[String]) {
    let input = &self.input; // <-- I added this
    self.output.extend(
      values
        .iter()
        .map(|v| input.get(v).cloned().unwrap_or(0)),
        //       ----- and removed the `self.` here
    );
  }
}
```

As you can [verify for yourself][pgfix2], this code compiles. 

To see why it works, consider again the desugared output. In the new
version, the desugared closure will capture `input`, not `self`:

```rust
MyThunk { input: &input }
```

The borrow checker, meanwhile, sees two overlapping borrows in the function:

- `let input = &self.input` -- shared borrow of `self.input`
- `self.output.extend(..)` -- mutable borrow of `self.output`

No error is reported because these two borrows affect different fields
of self.

### A more general pattern

Sometimes, when I want to be very precise, I will write closures in a
stylized way that makes it crystal clear what they are capturing.
Instead of writing `|v| ...`, I first introduce a block that creates a
lot of local variables, with the final thing in the block being a
`move` closure (`move` closures take ownership of the things they use,
instead of borrowing them from the creator). This gives complete
control over what is borrowed and how. In this case, the closure might look like:

```rust
{
  let input = &self.input;
  move |v| input.get(v).cloned().unwrap_or(0)
}
```

Or, [in context][pgfix3]:

[pgfix3]: https://play.rust-lang.org/?gist=8ea9d6acddfc11706fda29bde8550f3c&version=stable

```rust
impl Context {
  fn process(&mut self, values: &[String]) {
    self.output.extend(values.iter().map({
      let input = &self.input;
      move |v| input.get(v).cloned().unwrap_or(0)
    }));
  }
}
```

In effect, these `let` statements become like the ["capture clauses"]
in C++, declaring how precisely variables from the environment are
captured. But they give added flexibility by also allowing us to
capture the results of small expressions, like `self.input`, instead
of local variables.

["capture clauses"]: https://msdn.microsoft.com/en-us/library/dd293608.aspx

Another time that this pattern is useful is when you want to capture a *clone*
of some data versus the data itself:

```rust
{
  let data = data.clone();
  move || ... do_something(&data) ...
}
```

### How we could accept this code in the future

There is actually a pending RFC, [RFC #2229], that aims to modify
closures so that they capture entire paths rather than local
variables. There are various corner cases though that we have to be
careful of, particularly with moving closures, as we don't want to
change the times that destructors run and hence change the semantics
of existing code. Nonetheless, it would solve this particular case by
changing the desugaring.

[RFC #2229]: https://github.com/rust-lang/rfcs/pull/2229

Alternatively, if we had some way for functions to capture a refence
to a "view" of a struct rather than the entire thing, then closures
might be able to capture a reference to a "view" of `self` rather than
capturing a reference to the field `input` directly. There is some
discussion of the view idea in [this internals
thread](https://internals.rust-lang.org/t/having-mutability-in-several-views-of-a-struct/6882/2);
I've also tinkered with the idea of merging views and traits, as
[described in this internals
post](https://internals.rust-lang.org/t/fields-in-traits/6933/12). I
think that once we tackle NLL and a few other pending challenges,
finding some way to express "views" seems like a clear way to help
make Rust more ergonomic.

### Discussion

I've opened [a users
thread](https://users.rust-lang.org/t/blog-post-series-rust-patterns/20080)
to discuss this blog post (along with other Rust pattern blog posts).

