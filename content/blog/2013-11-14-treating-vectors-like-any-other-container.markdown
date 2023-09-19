---
layout: post
title: "Treating vectors like any other container"
date: 2013-11-14 19:21
comments: true
categories: [Rust]
---
Some [astute][c1] [comments][c2] on a recent thread to rust-dev got me
thinking about our approach to vectors. Until now, we have focused on
having built-in support for vectors via the vector type (`~[T]`) and
slice types (`&[T]`). However, another possible approach would be to
move vector support out of the language (almost) entirely and into
standard libraries. I wanted to write out a post exploring this idea;
I find it brings some simplifications and reduces the need for
DST. Seems like an idea worth considering. Consider this a thought
experiment, not exactly a *proposal*.

<!-- more -->

### Summary

In a nutshell, the idea is to change the following types:

    Current          Proposed
    
    ~[T]        ==>  Vector<T>
    &'a [T]     ==>  Slice<'a, T>
    &'a mut [T] ==>  MutSlice<'a, T>
    ~str        ==>  String
    &'a str     ==>  Substring<'a>

`Vector`, `Slice`, etc would all be normal types defined in the
standard library, though they would also be lang items (meaning that
the compiler knows about them). It's possible that we could define the
type `[T]` as sugar for `Vector<T>`, but to keep things clearer I'm
going to ignore this for now and just use explicit type names.

This approach has some interesting implications. For one thing, it
sidesteps the need for [DST][dst] when it comes to vectors. Instead,
vectors work just like existing collections like `HashMap` work: the
collection (`Vector<T>`, in this case) specifies the ownership
internally. To put it another way, the only kind of vector is `~[T]`
(those of you who have been following Rust for more than the last year
or so will find this sounds familiar).

If you want to pass around a vector by reference, you'd have two
choices. You could pass a `&Vector<T>` around, but that's not quite as
good as passing a `Slice<T>` (in both cases there is a lifetime
parameter that I have omitted since you wouldn't typically need to
write it). It will be easy, and perhaps automatic like today, to
coerce a `Vector<T>` into a `Slice<T>` (more on that later).

### Vector literal syntax

Right now, if you write `~[1, 2, 3]` you get a vector allocator on the
heap. If you write `[1, 2, 3]` you get a fixed-size vector
(`[int, ..3]`). If you write `&[1, 2, 3]` you get an explicit slice --
which is basically a fixed-size vector, stored on the stack, and then
immediately coerced to a slice. Given the automatic coercion rules,
`&[...]` is not a particularly useful expression, and I generally just
write `[...]` and let the coercion rules take care of the rest.

If vectors move into the library, then all this syntax no longer
works.  It's not clear to me what we should replace it with. One
possibility is to take the "generalized literal" approach, which is
similar to how C++11 handles things, and also similar to how Haskell
handles integers. This would mean that you would define a builder trait,
probably something like:

    trait Builder<T> {
       fn new(length: uint) -> Self;
       fn push(&mut self, t: T);
       fn finish(self) -> Self;
    }
    
A literal like `[1, 2, 3]` would basically be desugared into some code
like:

    {
        let mut builder = Builder::new(3);
        builder.push(1);
        builder.push(2);
        builder.push(3);
        builder.finish()
    }
    
This would rely on type inference to select the appropriate type of
container.

(In fact, we already have something very much like builder, called
`FromIterator`:

    pub trait FromIterator<A> {
        fn from_iterator<T: Iterator<A>>(iterator: &mut T) -> Self;
    }

So it might be that we just use `FromIterator` instead, though it
makes it somewhat less obvious precisely what `[1, 2, 3]` desugars
into. Or perhaps we replace `FromIterator` and just make `collect` use
something like `builder`.)

Taking this approach would mean that we could easily define new
vector types and have them fit in seamlessly. We could also use
the same trait to have hashmap literals, though if we left the
syntax as is, you'd have to write something like:

    let mut map = [(key1, value1), (key2, value2)];
    
But it'd be easy enough to add some sugar where `expr1 -> expr2` is
equivalent to `(expr1, expr2)`, which would permit:

    let mut map = [key1 -> value1, key2 -> value2];

(Languages like Scala, Smalltalk, or Haskell, where operators can be
freely defined, often play tricks like this.)

### Slicing

In the [DST][dst] proposal, slicing and borrowing are the same
operation. That is, given a variable `x` of type `~[T]`, one could
write `&*x` to obtain a slice of type `&[T]`. This also implies that
any autoborrowing rules we have extend naturally to autoslicing.
(Note that this *also* implies, I believe, that if we permit
overloading the `Deref` operator, then random types can also make
themselves coercable to a slice by implementing a `Deref` that yields
`[T]`.)

With `Vector<T>`, that won't work, so we must consider the question
though of how and when slices are created, and in particular how to
preserve the current behavior of coercing vectors into slices when the
vector appears as a method receiver or function call argument (it may
be that we don't want to preserve this behavior, but it's good to know
how we would so -- I'm actually not the biggest fan of autoborrowing
for function call arguments, though I introduced the idea).

My rough idea is to make slicing something that is more overloadable,
and hence something that user-defined types might tie into. It is
essentially the "multi-object" version of overridable deref (subject
of another upcoming blog post). So where a smart pointer gets deref'd
into an `&T` (borrowed pointer to a `T`), a collection can get sliced
into a `Slice<T>` (borrowed pointer to multiple `T` values).

We might imagine defining two traits:

    trait Dice<T> { // "It slices! It dices!"
        fn slice<'a>(&'a self) -> Slice<'a, T>;
        fn slice_from<'a>(&'a self, from: uint) -> Slice<'a, T>;
        fn slice_to<'a>(&'a self, to: uint) -> Slice<'a, T>;
        fn slice_between<'a>(&'a self, from: uint, to: uint) -> Slice<'a, T>;
    }
    
    trait MutDice<T> {
        fn mut_slice<'a>(&'a mut self) -> MutSlice<'a, T>;
        fn mut_slice_from<'a>(&'a mut self, from: uint) -> MutSlice<'a, T>;
        fn mut_slice_to<'a>(&'a mut self, to: uint) -> MutSlice<'a, T>;
        fn mut_slice_between<'a>(&'a mut self, from: uint, to: uint) -> MutSlice<'a, T>;
    }

(Incidentally, we could also add a slice operator like `v[a..b]` that
corresponds to the `Dice` trait. But that's neither here nor there.)

It is not clear to me just how much coercion we want to preserve.  For
arguments, we'd check for formal arguments of type `Slice<U>` where
the actual argument is of some type `T != Slice` and we'd search for
an implementation of `Dice<U> for T` (an analogous process works for
`MutSlice`).

Method lookup would work in a similar way. We would autoderef until we
reached a point where we don't know how to deref the receiver type
`R`. At the time, we would search for an implementation of `Dice<U>
for R` (where `U` is a fresh variable). If we find one, we can then
search for methods on `Slice<U>`. Similarly we can search for
`MutDice<U>`. I don't want to go into details here because I have an
in-progress post talking about adding a user-defined deref that covers
many of the same issues. It's a bit messy but I think it can work, and
moreover if we're going to be supporting user-defined deref, the
process will already largely be in place, and this would just add on
to that.

### Compile-time constants

Whenever we start discussing moving language features into libraries,
it raises the specter of how to deal with compile-time
constants. Right now, one can place a static array in a compile-time
constant easily enough:

    static FIRST_FEW_PRIMES: &'static [uint] = &[1, 2, 3, 5];
    
It's not clear how this would work under a builder scenario, nor with
slicing being a trait. (Enqueue requests for compile-time functional
evaluation and constexprs.)

### Fixed-length arrays

Similarly to compile-time constants, fixed-length arrays currently
occupy something of a magic territory. This is due to our inability to
generate impls that are parameterized by an integer. This means that
they do not fit well with generic `Builder` and `Dice` traits and so
on. Incidentally, fixed length arrays are naturally the only kind we
can *really* generate on the stack or at compile-time, so they are
sort of a primitive notion to begin with. (Enqueue requests for impls
parameterized by integers, which actually seems fairly doable to me,
at least in a limited sense.)

### Match patterns

Currently we have pattern matching on vectors, so you can write
something like `match vec { [a, b, ..c] => ... }`. This doesn't work
well if vectors aren't built into the language. This syntax isn't that
widely used so I think we'd just have to drop it. Note that similar
complications arise when trying to pattern match against smart
pointer.

Another option is to have the compiler issue calls to the slice trait
in order to process such a pattern, but there are several
complications that arise:

- Allowing user-defined code to be invoked as part of pattern matching
  exposes evaluation order and adds complications for refutable patterns.
  This might be more of a theoretical concern -- perhaps just saying that
  it's undefined when, if, and how often that code might be invoked is
  fine, but maybe it's not. It's at least kind of scary.
  
  - On a related note, right now, because match code is built into the
    compiler, we allow it to inspect freely without worrying about
    whether data is mutably borrowed or not. We know, after all, that
    during a match the only possibility for side effects is when the
    guard condition runs. If usre-defined code might run, though,
    we'd have to be more careful.
  
- Currently you can move out of vectors that are being matched as well,
  but I can't see how that would be possible if we build on the slicing
  mechanism.
  
**UPDATE:** After some discussion on IRC, I decided I overstated the
difficulty here. The straightforward way to support user operators in
patterns is just to fix the evaluation order as "first to last, depth
first". We would have a naive code generation pass as a fallback.  In
the event that no slice patterns are found, we can try something more
optimized. This is a good way to structure pattern testing in any
event; the current code tries to handle all cases in an optimal way,
and as a result is quite complex, it'd probably be simpler if we
limited it to the easier (and more frequent) cases.

### Index operation

We currently support overloading the index operator but the trait is
not defined correctly. Indexes are lvalues but this is not reflected
in the trait definition, and hence if we do not change the trait we
would not be able to write an expression like:

    vec[3] = foo
    
Clearly a problem. Note that we will [want to fix this][6515] regardless of
what happens with the rest of the proposal.

I propose we change the Index trait to:

    trait Index<I, E> {
        fn index<'a>(&'a self, index: I) -> &'a E;
    }
    
Here you can see that index returns a borrowed pointer to the
element. This allows us to write expressions like `&vec[3]`; the
compiler will automatically insert a dereference if the expression is
`vec[3]`.

For mutable indexing, the trait would look as follows:
    
    trait MutIndex {
        fn mut_index<'a>(&'a self, index: I) -> &'a mut E;
        fn assign_index(&'a mut self, index: I, value: E);
    }

The first method would be used for an expression like `&mut vec[3]`.
The second would be used for an expression like `vec[3] = foo`. The
reason to separate the two is so that hashtables can use `map[key] =
index` as the notation for inserting a key even if the key is not
already present (this avoids the need to allocate a key-value pair
with an uninitialized value).

#### Moves and indexing

One feature that works today but would not work with these index
traits is moving out of a vector by index. However, as it turns out, I
think that we won't be able to support this long term in any case, so
this is no loss. Let me briefly explain what I mean. Today, you
can write code like:

    let x = ~[~"Hello, ~"World"];
    let y = x[0];
    
Right now the second assignment moves the string out of `x[0]` and
thus renders the vector `x` completely inaccessible (because it's 0th
element is missing). (If `x` were a vector of integers or other types
that do not need to be freed, of course, then `x` would remain
accessible.)

Using the index trait, however, moves like that are not possible.
This is because the access `x[0]` would be translated to (roughly)
`*x.index(0)`. `x.index(0)` would be returning a borrowed pointer to a
string (`&~str`) and hence the move would be a move out of a borrowed
pointer, which is not permitted.

Nonetheless, I think that these sorts of moves will have to become
illegal anyhow as part of [issue 5016][5016]. The reason is that they
are currently implementing by zeroing out `x[0]`. But we plan to stop
doing that and instead have the compiler track precisely which things
on the stack need to be freed. We can't do that and permit vector
indices.  But this is no great loss; moving out of a vector will be
accomplished through methods like `pop()` etc.

### Conclusion

I've outlined the key interactions I thought of. Here is a kind of
summary of the effects. I don't feel "concluded" right now, in the
sense that I don't know which approach I prefer. I am worried that we
must resolve the niggly details of compile-time constants and
fixed-length vectors before we could adopt this approach.

I don't feel that either has the advantage of being conceptually
*cleaner* or *simpler*. This approach makes vectors much more like all
other collections, which is nice; a DST-based approach permits
generalizing "pointer-to-one" (`&T`, `~T`) to "pointer-to-many"
(`&[T]`, `~[T]`) and brings them both under the same framework.

#### Advantages

**Simpler type system.** The type system is certainly simplified by
this change.  We move vectors out of the language core and into a
library.

**Reduced need for DST.** There may still be some need for DST as part
of dealing with objects (I'll cover this in a later post), but this
will arise less frequently. DST has a few sharp edges of its own --
mostly annotation burden -- so this is perhaps good. Because it will
be less important, this might in turn mean that DST can be deferred
till post 1.0.

**More extensible.** Allowing other kinds of vectors to opt into
slicing in particular helps to put collections on common footing.
However, in a DST world, extensible slicing can also be achieved by
having types overload the deref operator to yield `[T]`.

**Literal notation.** Flexible literal notation is neat and something
people commonly request. Of course, it's worth pointing out that it
can be achieved today using macros. For example, `seq!(a, b, c)` would
expand to the same code as above, and perhaps `map!(k1 -> v1, k2 ->
v2)` could cover the map case. Macros would be much simpler on the
compiler but often feel second class (queue Dave saying "I told you
so"), though as we use them more and more commonly for fairly
fundamental things like `fail!` and `assert!` perhaps this is no
longer true.

#### Disadvantages

**Compile-time constants and fixed-length arrays.** It's unclear to
what extent we can make these work, at least without implementing
other features we might prefer to hold off on.

**Orthogonality of allocation method.** One thing we give up with this
approach is the ability to have vectors whose storage is managed by a
smart pointer. Using a DST-like approach, it's at least plausible to
have a type like `Gc<[uint]>`. Using this library based approach, we'd
either need to make a `GcVector` type, or else use `GC<Vector<uint>>`.

**More type hints.** Building on type inference will mean that sometimes
you have to give more type hints than today.

**Notation.** `Slice<T>` is significantly longer than `&[T]`. One
could imagine making the type `[T]` be sugar for `Slice<T>`, but then
one must accommodate the region
(`['a T`?) and perhaps mutability (`['a mut T]`?). This problem was
solved neatly by DST.

**Vector match patterns.** There seems to be no smooth way to integrate this
current feature.

[c1]: https://mail.mozilla.org/pipermail/rust-dev/2013-November/006381.html
[c2]: https://mail.mozilla.org/pipermail/rust-dev/2013-November/006376.html
[dst]: {{< baseurl >}}/blog/2013/04/30/dynamically-sized-types/
[6515]: https://github.com/mozilla/rust/issues/6515
[5016]: https://github.com/mozilla/rust/issues/5016
