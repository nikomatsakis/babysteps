---
layout: post
title: 'After NLL: Interprocedural conflicts'
categories: [Rust, NLL]
---

In my previous post on the status of NLL, I promised to talk about
"What is next?" for ownership and borrowing in Rust. I want to lay out
the various limitations of Rust's ownership and borrowing system that
I see, as well as -- where applicable -- current workarounds. I'm
curious to get feedback on which problems affect folks the most.

The first limitation I wanted to focus on is **interprocedural
conflicts**.  In fact, I've covered a special case of this before --
where a closure conflicts with its creator function -- in my post on
[Precise Closure Capture Clauses][cc]. But the problem is more
general.

[cc]: {{ site.baseurl }}/blog/2018/04/24/rust-pattern-precise-closure-capture-clauses/

## The problem

Oftentimes, it happens that we have a big struct that contains a
number of fields, not all of which are used by all the
methods. Consider a struct like this:

```rust
use std::sync::mpsc::Sender;

struct MyStruct {
  widgets: Vec<MyWidget>,
  counter: usize,
  listener: Sender<()>,
}

struct MyWidget { .. }
```

Perhaps we have a method `increment` which increments the counter each
time some sort of event occurs. It also fires off a message to some
listener to let them know.

```rust
impl MyStruct {
  fn signal_event(&mut self) {
    self.counter += 1;
    self.listener.send(()).unwrap();
  }
}
```

The problem arises when we try to invoke this method while we are
simultaneously using some of the other fields of `MyStruct`.  Suppose
we are "checking" our widgets, and this process might generate the
events we are counting; that might look like so:

```rust
impl MyStruct {
  fn check_widgets(&mut self) {
    for widget in &self.widgets {
      if widget.check() {
        self.signal_event();
      }
    }
  }
}  
```

Unfortunately, [this code is going to yield a compilation error][pg1].
The error I get presently is:

[pg1]: https://play.rust-lang.org/?version=beta&mode=debug&edition=2018&gist=ef84f42cd30a8c110e6d5ce4eceac5df

```
error[E0502]: cannot borrow `*self` as mutable because it is also borrowed as immutable
  --> src/main.rs:26:17
     |
  24 |         for widget in &self.widgets {
     |                       -------------
     |                       |
     |                       immutable borrow occurs here
     |                       immutable borrow used here, in later iteration of loop
  25 |             if widget.check() {
  26 |                 self.signal_event();
     |                 ^^^^^^^^^^^^^^^^^^^ mutable borrow occurs here
```

What this message is trying to tell you[^improvement] is that:

- During the loop, you are holding a borrow of `self.widgets`.
- You are then giving away access to `self` in order to call `signal_event`.
  - The danger here is that `signal_event` may mutate `self.widgets`,
    which you are currently iterating over.

[^improvement]: This message is actually a bit confusing.

Now, you and I know that `signal_event` is not going to touch the
`self.widgets` field, so there should be no problem here. But the
compiler doesn't know that, because it only examines one function at a
time.

### Inlining as a possible fix

The *simplest* way to fix this problem is to modify `check_widgets`
to inline the body of `signal_event`:

```rust
impl MyStruct {
  fn check_widgets(&mut self) {
    for widget in &self.widgets {
      if widget.check() {
        // Inline `self.signal_event()`:
        self.counter += 1;
        self.listener.send(()).unwrap(); 
      }
    }
  }
}  
```

Now the compiler can clearly see that distinct fields of `self` are
being used, so everything is hunky dory. Of course, now we've created
a "DRY"-failure -- we have two bits of code that know how to signal an
event, and they could easily fall out of sync.

### Factoring as a possible fix

One way to address the DRY failure is to factor our types better.
For example, perhaps we can extract a `EventSignal` type and
move the `signal_event` method there:

```rust
struct EventSignal {
  counter: usize,
  listener: Sender<()>,
}

impl EventSignal {
  fn signal_event(&mut self) {
    self.counter += 1;
    self.listener.send(()).unwrap();
  }
}
```

Now we can modify the `MyStruct` type to embed an `EventSignal`:

```rust
struct MyStruct {
  widgets: Vec<MyWidget>,
  signal: EventSignal,
}
```

Finally, instead of writing `self.signal_event()`, we will write `self.signal.signal_event()`:

```rust
impl MyStruct {
  fn check_widgets(&mut self) {
    for widget in &mut self.widgets {
      if widget.update() {
        self.signal.signal_event(); // <-- Changed
      }
    }
  }
}  
```

[This code compiles fine][pg2], since the compiler now sees access to
two distinct fields: `widgets` and `signal`. Moreover, we can invoke
`self.signal.signal_event()` from as many places as we want without
duplication.

[pg2]: https://play.rust-lang.org/?version=beta&mode=debug&edition=2018&gist=6512551bf58cd66917895a588f3643dc

Truth be told, factoring sometimes makes for cleaner code: e.g., in
this case, there was a kind of "mini type" hiding within `MyStruct`,
and it's nice that we can extract it. But definitely not always. It
can be more verbose, and I sometimes find that it makes things more
opaque, simply because there are now just more structs running around
that I have to look at.  Some things are so simple that the complexity
of having a struct outweights the win of isolating a distinct bit of
functionality.

The other problem with factoring is that it doesn't always work:
sometimes we have methods that each use a specific set of fields, but
those fields don't factor *nicely*. For example, if we return to our
original `MyStruct` (where everything was inlined), perhaps we might
have a method that used both `self.counter` and `self.widgets` but not
`self.listener` -- the factoring we did can't help us identify a
function that uses `counter` but not `listener`.

### Free variables as a general, but extreme solution

One very general way to sidestep our problem is to move things out of
method form and into a "free function". The idea is that instead of
`&mut self`, you will take a separate `&mut` parameter for each field
that you use. So `signal_event` might look like:

```rust
fn signal_event(counter: &mut usize, listener: &Sender<()>) {
  *counter += 1;
  listener.send(()).unwrap();
}
```

Then we would replace `self.signal_event()` with:

```rust
signal_event(&mut self.counter, &self.listener)
```

Obviously, this is a significant ergonomic regression. However, it is
very effective at exposing the set of fields that will be accessed to
our caller.

Moving to a free function also gives us some extra flexibility. You
may have noted, for example, that the `signal_event` function takes a
`&Sender<()>` and not a `&mut Sender<()>`. This is because [the `send`
method on `Sender` only requires `&self`][send], so a shared borrow is
all we need. This means that we could invoke `signal_event` in some
location where we needed another shared borrow of `self.listener`
(perhaps another method or function).

[send]: https://doc.rust-lang.org/std/sync/mpsc/struct.Sender.html#method.send

### View structs as a general, but extreme solution

I find moving to a free function to be ok in a pinch, but it's pretty
annoying if you have a lot of fields, or if the method you are
converting calls other methods (in which case you need to identify the
transitive set of fields). There is another technique I have used from
time to time, though it's fairly heavy weight. The idea is to define a
"view struct" which has all the same fields as the orignal, but it
uses references to identify if those fields are used in a "shared"
(immutable) or "mutable" way.

For example, we might define `CheckWidgetsView`

```rust
struct CheckWidgetsView<'me> {
  widgets: &'me Vec<MyWidget>,
  counter: &'me mut usize,
  listener: &'me mut Sender<()>,
}
```

Now we can define methods on the view without a problem:

```rust
impl<'me> CheckWidgetsView<'me>  {
  fn signal_event(&mut self) {
    *self.counter += 1;
    self.listener.send(()).unwrap();
  }

  fn check_widgets(&mut self) {
    for widget in &self.widgets {
      if widget.check() {
        self.signal_event();
      }
    }
  }
}  
```

You might wonder why this solved the problem. After all, the `check_widgets`
method here basically looks the same -- the compiler still sees two overlapping
borrows:

- a shared borrow of `self.widgets`, in the for loop
- a mutable borrow of `self`, when invoking `signal_event`

The difference here lies in the type of `self.widgets`: because it is
a `&Vec<MyWidget>`, we already know that the vector we are iterating
over cannot change -- that is, we are not giving away mutable access
to the iterator itself, just to a *reference to the iterator*. So
there is nothing that `signal_event` could do to mess up our
iteration.

(Note that if we needed to mutate the widgets as we iterated, this
"view struct" trick would not work here, and we'd be back where we
started -- or rather, we'd need a new view struct just for
`signal_event`.)

One nice thing about view structs is that we can have more than one,
and we can change the set of fields that each part refers to. So, for
example, one sometimes has "double buffering"-like algorithms that use
one field for input and one field for output, but which field is used
alternates depending on the phase (and which perhaps use other fields
in a shared capacity). Using view struct(s) can handle this quite
elegantly.

### Relation to closures

As I mentioned, one common place where this problem arises is actually
with closures. This occurs because closures always capture entire
local variables; so if a closure only uses some particular field of a
local, it can create an unnecessary conflict. For example:

```rust
fn check_widgets(&mut self) {
  // Make a closure that uses `self.counter`
  // and `self.listener`; but it will actually
  // capture all of `self`.
  let signal_event = || {
    self.counter += 1;
    self.listener.send(()).unwrap(); 
  };
  
  for widget in &self.widgets {
    if widget.check() {
      signal_event();
    }
  }
}
```

Even though it's an instance of the same general problem, it's worth
calling out specially, because it can be solved in different ways. In
fact, we've accepted [RFC #2229], which proposes to change the closure
desugaring. In this case, the closure would only capture
`self.counter` and `self.listener`, avoiding the problem.

[RFC #2229]: https://github.com/rust-lang/rfcs/pull/2229

### Extending the language to solve this problem

There has been discussion on and off about how to solve this problem.
Clearly, there is a need to permit methods to expose information about
which fields they access and how they access those fields, but it's not
clear what's the best way to do this. There are a number of tradeoffs at play:

- Adding more concepts to the surface language.
- Core complexity; this probably involves extending the base borrow checker rules.
- Annotation burden.
- Semver considerations (see below).

There is some discussion of the view idea in [this internals
thread](https://internals.rust-lang.org/t/having-mutability-in-several-views-of-a-struct/6882/2);
I've also tinkered with the idea of merging views and traits, as
[described in this internals
post](https://internals.rust-lang.org/t/fields-in-traits/6933/12). I've
also toyed with the idea of trying to infer some of this information
for private functions (or perhaps even crate-private functions), but I
think it'd be best to start with some form of explicit syntax.

**Semver considerations.** One of the things you'll notice about all
of the solutions to the problem is that they are all ways of exposing
information to the compiler about which fields will be used in
`signal_event` or (in the case of view structs) how they will be
used. This has semver implications: imagine you have a public function
`fn get(&self) -> &Foo` that returns a reference to something in
`self`. If we now permit your clients to invoke other methods while
that borrow is live (because we know somehow that they won't
interfere), that is a semver commitment. The current version, where
your struct is considered an atomic unit, gives you maximal freedom to
change your implementation in the future, because it is maximally
conservative with respect to what your clients can do.

### Conclusion

The general problem here I think is being able to identify which
fields are used by a method (or set of methods) and how. I've shown a
number of workarounds you can use today. I'm interested to hear,
however, how often this problem affects you, and which (if any) of the
workarounds might have helped you. (As noted, I would break out
closures into their own subcategory of this problem, and one for which
we will hopefully have a solution sooner.)

To discuss this, I [have opened a thread on
`users.rust-lang.org`](https://users.rust-lang.org/t/blog-post-series-after-nll-whats-next-for-borrowing-and-lifetimes/21864). Once
the "What's next?" series is done, I will also open a survey to gather
more quantitive feedback.
