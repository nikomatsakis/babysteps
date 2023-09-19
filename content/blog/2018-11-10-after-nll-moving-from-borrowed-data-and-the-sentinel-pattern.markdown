---
layout: post
title: 'After NLL: Moving from borrowed data and the sentinel pattern'
---

Continuing on with my “After NLL” series, I want to look at another
common error that I see and its solution: today’s choice is about moves
from borrowed data and the *Sentinel Pattern* that can be used to enable
them.

# The problem

Sometimes when we have `&mut` access to a struct, we have a need to
*temporarily* take ownership of some of its fields. Usually what happens
is that we want to move out from a field, construct something new using
the old value, and then replace it. So for example imagine we have a
type `Chain`, which implements a simple linked list:

```rust
enum Chain {
  Empty,
  Link(Box<Chain>),
}

impl Chain {
  fn with(next: Chain) -> Chain {
    Chain::Link(Box::new(next))
  }
}
```

Now suppose we have a struct `MyStruct` and we are trying to add a link
to our chain; we might have something like:

```rust
struct MyStruct {
  counter: u32,
  chain: Chain,
}

impl MyStruct {
  fn add_link(&mut self) {
    self.chain = Chain::with(self.chain);
  }
}
```

Now, if we try to [run this code][play1],
we will receive the following error:

[play1]: https://play.rust-lang.org/?version=stable&mode=debug&edition=2015&gist=896551436908a5a7b8b76d5f5ace54af

```
error[E0507]: cannot move out of borrowed content
 --> ex1.rs:7:30
  |
7 |     self.chain = Chain::with(self.chain);
  |                              ^^^^ cannot move out of borrowed content
```

The problem here is that we need to *take ownership* of `self.chain`,
but you can only take ownership of things that you own. In this case, we
only have /borrowed/ access to `self`, because `add_link` is declared as
`&mut self`.

To put this as an analogy, it is as if you had borrowed a really nifty
Lego building that your friend made so you could admire it. Then, later,
you are building your own Lego thing and you realize you would like to
take some of the pieces from their building and put them into yours. But
you can’t do that – those pieces belong to your friend, not you, and
that would leave a hole in their building.

Still, this is kind of annoying – after all, if we look at the larger
context, although we are moving `self.chain`, we are going to replace it
shortly thereafter. So maybe it’s more like – we want to take some
blocks from our friend’s Lego building, but not to put them into our
/own/ building. Rather, we were going to take it apart, build up
something new with a few extra blocks, and then put that new thing back
in the same spot – so, by the time they see their building again, the
“hole” will be all patched up.

### Root of the problem: panics

You can imagine us doing a static analysis that permits you to take
ownership of `&mut` borrowed data, as long as we can see that it will be
replaced before the function returns. There is one little niggly problem
though: can we be *really sure* that we are going to replace
`self.chain`? It turns out that we can’t, because of the possibility of
panics.

To see what I mean, let’s take that troublesome line and expand it out
so we can see all the hidden steps. The original line was this:

```rust
self.chain = Chain::with(self.chain);
```

which we can expand to something like this:

```rust
let tmp0 = self.chain;        // 1. move `self.chain` out
let tmp1 = Chain::with(tmp0); // 2. build new link
self.chain = tmp1;            // 3. replace with `tmp2`
```

Written this way, we can see that in between moving `self.chain` out and
replacing it, there is a function call: `Chain::with`. And of course it
is possible for this function call to *panic*, at least in principle. If
it were to panic, then the stack would start unwinding, and we would
never get to step 3, where we assign `self.chain` again. This means that
there might be a destructor somewhere along the way that goes to inspect
`self` – if it were to try to access `self.chain`, it would just find
uninitialized memory. Or, even worse, `self` might be located inside of
some sort of `Mutex` or something else, so even if *our thread* panics,
other threads might observe the hole.

To return to our Lego analogy[^lego], it is as if – after we removed some
pieces from our friends Lego set – our parents came and made us go to
bed before we were able to finish the replacement piece.  Worse, our
friend’s parents came over during the night to pick up the set, and so
now when our friend gets it back, it has this big hole in it.

[^lego]: I really like this Lego analogy. You’ll just have to bear with me.

### One solution: sentinel

In fact, there *is* a way to move out from an `&mut` pointer – you can
use [the function `std::mem::replace`][replace][^useful]. `replace`
sidesteps the panic problem we just described because it requires you
to already have a new value at hand, so that we can move out from
`self.chain` and *immediately* put a replacement there.

[replace]: https://doc.rust-lang.org/std/mem/fn.replace.html
[^useful]: `std::mem::replace` is a super useful function in all kinds of scenarios; worth having in your toolbox.

Our problem here is that we need to do the move before we can construct
the replacement we want. So, one solution then is that we can put some
temporary, dummy value in that spot. I call this a *sentinel* value –
because it’s some kind of special value. In this particular case, one
easy way to get the code to compile would be to stuff in an empty chain
temporarily:

```rust
let chain = std::mem::replace(&mut self.chain, Chain::Empty);
self.chain = Chain::with(chain);
```

Now the compiler is happy – after all, even if `Chain::with` panics,
it’s not a memory safety problem. If anybody happens to inspect
`self.chain` later, they won’t see uninitialized memory, they will see
an empty chain.

To return to our Lego analogy[^omgstop], it’s as if, when we
remove the pieces from our friend’s Lego set, we immediately stuff in a
a replacement piece. It’s an ugly piece, with the wrong color and
everything, but it’s ok – because our friend will never see it.

[^omgstop]: OK, maybe I’m taking this analogy too far. Sorry. I need help.

### A more robust sentinel

The compiler is happy, but are we happy? Perhaps we are, but there is
one niggling detail. We wanted this empty chain to be a kind of
“temporary value” that nobody ever observes – but can we be sure of
that? Actually, in this *particular* example, we can be fairly sure…
other than the possibility of panic (which certainly remains, but is
perhaps acceptable, since we are in the process of tearing things down),
there isn’t really much else that can happen before `self.chain` is
replaced.

But often we are in a situation where we need to take temporary
ownership and then invoke other `self` methods. Now, perhaps we expect
that these methods will never read from `self.chain` – in other words,
we have a kind of [interprocedural conflict].  For example, maybe to
construct the new chain we invoke `self.extend_chain` instead, which
reads `self.counter` and creates that many new links[^gun] in the
chain:

[^gun]: I bet you were wondering what that `counter` field was for – gotta admire that [Chekhov’s Gun] action.

[Chekhov's Gun]: https://en.wikipedia.org/wiki/Chekhov%27s_gun
[interprocedural construct]: {{< baseurl >}}/blog/2018/11/01/after-nll-interprocedural-conflicts/

```rust
impl MyStruct {
  fn add_link(&mut self) {
    let chain = std::mem::replace(&mut self.chain, Chain::Empty);
    let new_chain = self.extend_chain(chain);
    self.chain = new_chain;
  }
  
  fn extend_chain(&mut self, chain: Chain) -> Chain {
    for _ in 0 .. self.counter {
      chain = Chain::with(chain);
    }
    chain
  }
}
```

Now I would get a bit nervous. I *think* nobody ever observes this empty
chain, but how can I be *sure*? At some point, you would like to test
this hypothesis.

One solution here is to use a sentinel value that is otherwise invalid.
For example, I could change my `chain` field to store an
`Option<Chain>`, with the invariant that `self.chain` should *always* be
`Some`, because if I ever observe a `None`, it means that `add_link` is
in progress. In fact, there is a handy method on `Option` called `take`
that makes this quite easy to do:

```rust
struct MyStruct {
  counter: u32,
  chain: Option<Chain>, // <-- new
}

impl MyStruct {
  fn add_link(&mut self) {
    // Equivalent to:
    // let link = std::mem::replace(&mut self.chain, None).unwrap();
    let link = self.chain.take().unwrap();
    self.chain = Some(Chain::with(self.chain));
  }
}
```

Now, if I were to (for example) invoke `add_link` recursively, I would
get a panic, so I would at least be alerted to the problem.

The annoying part about this pattern is that I have to “acknowledge” it
every time I reference `self.chain`. In fact, we already saw that in the
code above, since we had to wrap the new value with `Some` when
assigning to `self.chain`. Similarly, to borrow the chain, we can’t just
do `&self.chain`, but instead we have to do something like
`self.chain.as_ref().unwrap()`, as in the example below, which counts
the links in the chain:

```rust
impl MyStruct {
  fn count_chain(&self) -> usize {
    let mut links = 0;
    let mut cursor: &Chain = self.chain.as_ref().unwrap();
    loop {
      match cursor {
        Chain::Empty => return links,
        Chain::Link(c) => {
          links += 1;
          cursor = c;
        }
      }
    }
  }
}
```

So, the pro of using `Option` is that we get stronger error detection.
The con is that we have an ergonomic penalty.


### Observation: most collections do not allocate when empty

One important detail when mucking about with sentinels: creating an
empty collection is generally “free” in Rust, at least for the standard
library. This is important because I find that the fields I wish to move
from are often collections of some kind or another. Indeed, even in our
motivating example here, the `Chain::Empty` sentinel is an “empty”
collection of sorts – but if the field you wish to move were e.g. a
`Vec<T>` value, then you could as well use `Vec::new()` as a sentinel
without having to worry about wasteful memory allocations.

### An alternative to sentinels: prevent unwinding through abort

There is a crate called [`take_mut`][] on crates.io that offers a
convenient alternative to installing a sentinel, although it does not
apply in all scenarios. It also raises some interesting questions
about [“unsafe composability”][uc] that worry me a bit, which I’ll
discuss at the end.

[`take_mut`]: https://crates.io/crates/take_mut
[uc]: {{< baseurl >}}/blog/2016/10/02/observational-equivalence-and-unsafe-code/

To use `take_mut` to solve this problem, we would rewrite our `add_link`
function as follows:

```rust
fn add_link(&mut self) {
  take_mut::take(&mut self.chain, |chain| {
      Chain::with(chain)
  });
}
```

The [`take`][] function works like so: first, it uses unsafe code to
move the value from `self.chain`, leaving uninitialized memory in its
place. Then, it gives this value to the closure, which in this case
will execute `Chain::with` and return a new chain. This new chain is
then installed to fill the hole that was left behind.

[`take`]: https://docs.rs/take_mut/0.2.2/take_mut/fn.take.html

Of course, this begs the queston: what happens if the `Chain::with`
function panics? Since `take` has left a hole in the place of
`self.chain`, it is in a tough spot: the answer from the `take_mut`
library is that it will *abort the entire process*. That is, unlike with
a `panic`, there is no controlled shutdown. There is some precedent for
this: we do the same thing in the event of stack overflow, memory
exhaustion, and a “double panic” (that is, a panic that occurs when
unwinding another panic).

The idea of aborting the process is that, unlike unwinding, we are
guaranteeing that there are no more possible observers for that hole
in memory. Interestingly, in writing this article, I realized that
*aborting the process does not compose with some other unsafe
abstractions you might want*. Imagine, for example, that you had
memory mapped a file on disk and were supplying an `&mut` reference
into that file to safe code. Or, perhaps you were using shared memory
between two processes, and had some kind of locked object in there –
after locking, you might obtain an `&mut` into the memory of that
object. Put another way, if the `take_mut` crate is safe, that means
that an `&mut` can never point to memory not ultimately “owned” by the
current process. I am not sure if that’s a good decision for us to
make – though perhaps the real answer is that we need to permit unsafe
crates to be a bit more declarative about the conditions they require
from other crates, as I talk a bit about in this older blog post on
[observational equivalence][oe].

[oe]: {{< baseurl >}}/blog/2016/10/02/observational-equivalence-and-unsafe-code/

### My recommenation

I would advise you to use some variant of the sentinel pattern. I
personally prefer to use a “signaling sentinel”[^ss] like `Option`
if it would be a bug for other code to read the field, unless the range
of code where the value is taken is very simple. So, in our *original*
example, where we just invoked `Chain::new`, I would not bother with an
`Option` – we can locally see that `self` does not escape. But in the
variant where we recursively invoke methods on `self`, I would, because
there it would be possible to recursively invoke `self.add_link` or
otherwise observe `self.chain` in this intermediate state.

[^ss]: i.e., some sort of sentinel where a panic occurs if the memory is observed

It’s a *bit* annoying to use `Option` for this because it’s so explicit.
I’ve sometimes created a `Take<T>` type that wraps a `Option<T>` and
implements `DerefMut<Target = T>`, so it can transparently be used as a
`T` in most scenarios – but which will `panic` if you attempt to deref
the value while it is “taken”. This might be a nice library, if it
doesn’t exist already.

One other thing to remember: instead of using a sentinel, you may be
able to avoid moving altogether, and sometimes that’s better. For
example, if you have an `&mut Vec<T>` and you need ownership of the
`T` values within, you can use the [`drain`][] iterator method. The
only real difference from [`drain`] vs [`into_iter`] is that [`drain`]
leaves an empty iterator behind once iteration is complete.

[`drain`]: https://doc.rust-lang.org/std/vec/struct.Vec.html#method.drain
[`into_iter`]: https://doc.rust-lang.org/std/iter/trait.IntoIterator.html#tymethod.into_iter

(Similarly, if you are writing an API and have the option of choosing
between writing a `fn(self) -> Self` sort of signature vs `fn(&mut
self)`, you might adopt the latter, as it gives your callers more
flexibility. But this is a bit subtle; it would make a good topic for
the [Rust API guidelines], but I didn’t find it there.)

[Rust API guidelines]: https://rust-lang-nursery.github.io/api-guidelines/

### Discussion

If you’d like to discuss something in this post, there is a [dedicated
thread on the users.rust-lang.org site][thread].

[thread]: https://users.rust-lang.org/t/blog-post-series-after-nll-whats-next-for-borrowing-and-lifetimes/21864

### Appendix A. Possible future directions

Besides creating a more ergonomic library to replace the use of `Option`
as a sentinel, I can think of a few plausible extensions to the language
that would alleviate this problem somewhat.

#### Tracking holes

The most obvious change is that we could plausibly extend the borrow
checker to permit moves out of an `&mut`, so long as the value is
guaranteed to be replaced *before the function returns or panics*. The
“or panics” bit is the tricky part, of course.

Without any other extensions to the language, we would have to consider
virtually every operation to “potentially panic”, which would be pretty
limiting. Our “motivating example” from this post, for example, would
fail the test, because the `Chain::with` function – like any function –
might potentially panic. The main thing this would do is allow functions
like `std::mem::replace` and `std::mem::swap` to be written in safe
code, as well as other more complex rotations. Handy, but not earth
shattering.

If we wanted to go beyond that, we would have to start looking into
effect type systems, which allow us to annotate functions with things
like “does not panic” and so forth. I am pretty nervous about taking
that particular “step up” in complexity – though there may be other use
cases (for example, to enable FFI interoperability with things that
longjmp, we might want ways to for functions to declare whether they
panic and how anyway). But it feels like at best this will be a narrow
tool that we wouldn’t expect people to use broadly.

In order to avoid annotation, @eddyb has tossed around the idea of an
“auto trait”-style effect system. Basically, you would be able to state
that you want to take as argument a “closure that can never call the
function `X`” – in this case, that might mean “a closure that can never
invoke `panic!`”. The compiler would then do a conservative analysis of
the closure’s call graph to figure out if it works. This would then
permit a variant of the `take_mut` crate where we don’t have to worry
about aborting the process, because we know the closure never panics. Of
course, just like auto traits, this raises semver concerns – sure, your
function doesn’t panic *now*, but does that mean you promise never to
make it panic in the future?[^crates-io]

[^crates-io]: It occurs to me that we now have a corpus of crates at various versions. It would be interesting to see how common it is to make something panic which did not used to, as well sa to make other sorts of changes.

#### Permissions in, permissions out

There is another possible answer as well. We might generalize Rust’s
borrowing system to express the idea of a “borrow that never ends” –
presently that’s not something we can express. The idea would be that a
function like `add_link` would take in an `&mut` but somehow express
that, if a panic were to occur, the `&mut` is fully invalidated.

I’m not particularly hopeful on this as a solution to this particular
problem. There is a lot of complexity to address and it just doesn’t
seem even close to worth it.

There are however some other cases where *similar* sorts of “permission
juggling” might be nice to express. For example, people sometimes want
the ability to have a variant on `insert` – basically a function that
inserts a `T` into a collection and then returns a shared reference `&T`
to inserted data. The idea is that the caller can then go on to do other
“shared” operations on the map (e.g., other map lookups). So the
signature would look a little like this:

```rust
impl SomeCollection<T> {
  fn insert_then_get(&mut self, data: T) -> &T {
    //
  }
}
```

This signature is of course valid in Rust today, but it has an
existing meaning that we can’t change. The meaning today is that the
function requires unique access to `self` – and that unique access has
to persist until we’ve finished using the return value. It’s precisely
this interpretation that makes methods like [`Mutex::get_mut`] sound.

[`Mutex::get_mut`]: https://doc.rust-lang.org/std/sync/struct.Mutex.html#method.get_mut

If we were to move in this direction, we might look to languages like
[Mezzo] for inspiration, which encode this notion of “permissions in, permissons
out” more directly[^frac]. I’m definitely interested in
investigating this direction, particularly if we can use it to address
other proposed “reference types” like `&out` (for taking references to
uninitialized memory which you must initialized), `&move`, and so forth.
But this seems like a massive research effort, so it’s hard to predict
just what it would look like for Rust, and I don’t see us adopting this
sort of thing in the near to mid term.

[Mezzo]: http://gallium.inria.fr/~fpottier/publis/bpp-mezzo-journal.pdf
[^frac]: Also related: [fractional permissions] and a whole host of other things.
[fractional permissions]: https://pdfs.semanticscholar.org/f744/e6fe7b8d9f92205d3a407e0446369c5f02bd.pdf

### Panic = Abort having semantic impact

Shortly after I posted this, Gankro tweeted the following:

<blockquote class="twitter-tweet" data-conversation="none" data-lang="en"><p lang="en" dir="ltr">[chanting in distance] <br/>Appendix A With Panic=Abort Having Semantic Impact</p>&mdash; Alexis Beingessner (@Gankro) <a href="https://twitter.com/Gankro/status/1061364298449108992?ref_src=twsrc%5Etfw">November 10, 2018</a></blockquote>

I actually meant to talk about that, so I’m adding this quick section.
You may have noticed that panics and unwinding are a big thing in this
post. Unwinding, however, is only optional in Rust – many users choose
instead to convert panics into a hard abort of the entire process.
Presently, the type and borrow checkers do not consider this option in
any way, but you could imagine them taking it into account when deciding
whether a particular bit of code is safe, particularly in lieu of a more
fancy effect system.

I am not a big fan of this. For one thing, it seems like it would
encourage people to opt into “panic = abort” just to avoid a sentinel
value here and there, which would lead to more of a split in the
ecosystem. But also, as I noted when discussing the `take_mut` crate,
this whole approach presumes that an `&mut` reference can only ever
refer to memory that is owned by the current process, and I’m not sure
that’s something we wish to state.

Still, food for thought.

### Footnotes
