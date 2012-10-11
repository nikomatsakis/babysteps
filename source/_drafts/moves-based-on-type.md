I have been trying to come up with a reasonable set of rules for
deciding when a pattern binding ought to be a move and when it ought
to be a copy and utterly failing.  Simultaneously, pcwalton, brson,
and I kind of simultaneously arrived at an alternate design that tries
to simplify the copy/move distinction.  I think that it also solves
the question of when to copy/move pattern bindings in a nice way.
Therefore, I wanted to write up this proposal.

The idea is to repurpose the idea of an *implicitly copyable* (IC)
type.  Expressions whose type is not IC would be *moved by default*.
This implies that an assignment like `x = a.b.c` could be either a
copy or a move, depending on the type of `a.b.c`.  If the type of
`a.b.c` were a non-IC type, but you wanted to *force* a copy, you
would write `x = a.b.c.clone()` (more on the `clone()` method later).
Today, in contrast, `x = a.b.c` would always be a copy unless you
write `x = move a.b.c`.

When we were initially discussing this design, it seemed simpler to me
to make it so that the rules for copies and moves were independent of
the type, particularly as types are inferred.  I now no longer believe
this to be true.  Some discussion on that lies below.

This same reasoning would apply not only to expressions but also to
other uses, such as capture clauses and bindings.  That means that if
you write a closure that references a non-IC type, it always *moves*
that value into its environment, and never copies.  If you wish to
copy, you simply make a clone of the value and close over that.

Similarly, in a by-value binding, we decide whether the binding moves
or copies based on the type of the value being bound.  A binding to a
non-IC type will move by default, unless it is declared as a `ref`
binding.

### What's with this `clone()` method?

I think we should have two traits that describe whether a type is
copyable: `Copy` and `Clone`.

`Copy` is implicitly defined for IC types.  It contains no methods.
It indicates that something can be cheaply copied using `memcpy`,
basically (in today's implementation, we'd also have to increment
ref-counts for embedded `@T` values, but that requirement would go
away with a tracing GC).

The `Clone` trait is intended for copying any kind of value.  It
defines a single method, `clone()`, which returns a new copy of the
receiver.  This can be custom defined by different types, or you can
derive a default implementation.

Generic functions in the standard library that must perform copies
would generally be written to take a bound of `Clone`, not `Copy`.
`Copy` would likely only be used in specific cases.

### So what are the syntactic implications?

We lose two keywords (`copy`, `move`), but also the concept of capture
clauses altogether.  Moreover, there are only two kinds of bindings:
by-value bindings (written `a`), and ref bindings, written `ref a`.

### Wait, doesn't this make it hard to know what your program does?

I used to think it would be easier to follow the flow of the program
if copy/move were defined *syntactically* rather than being based on
the (sometimes inferred) type.  I now think this was wrong---or rather,
it was missing the forest for the trees.

It's true that using an explicit `copy` or `move` keyword makes it
clearer what *any particular expression* does.  But it turns out that,
to a first approximation, you *never* want to copy non-IC types.  In
today's system, you have to keep track in your head of which values
are those that you should not copy and make sure to add extra `move`
annotations and so forth for those particular values.

In the proposed system, in contrast, you *know* that nothing will be
copied except for IC types unless you see a call to `clone()`.  So
instead of having to track the code and make sure that `move` is used
everywhere it's supposed to be used, you only have to look for the calls
to `clone()` and make sure that they make sense.

Moreover, before writing this post, I spent some time trying to come
up with a sensible set of syntactic rules for designating when a
pattern match ought to be a move versus a copy.  I failed.  There are
so many scenarios to consider, and it turns out that our current rules
are utterly inconsistent.  For example:

    let v = bar().f;                    /* copies */
    let Foo {f: v} = bar();             /* moves  */
    match bar() { Foo {f: v} => {       /* copies */ } }
    match bar() { Foo {f: move v} => {  /* moves  */ } }
    match bar().f { move v => {         /* error  */ } }
    
Any rule that wants to really work correctly I think will ultimately
require either a very large number of `move` annotations or else some
kind of rules that examine the ownership of fields and so forth and
make a decision based on that information.  Once you take that final
step you might as well consider the type.

### Some open questions

- Is the division into `Copy`/`Clone` traits correct?  For example, I
  could also see removing the `Copy` trait altogether and renaming
  `Clone` to `Copy`.
- Should it be possible for types to "opt-in" to the `Copy` trait?
  Maybe I want to define a struct that is implicitly copyable, even
  though it contains mutable fields, because I know that this struct
  does not carry identity (note, though, that you can do this today by
  using an `@mut` type).

### Background: Which types are implicitly copyable?

We already have the notion of an *implicitly copyable type*: this is a
type that (1) is `Const` (contains no mutable fields) and (2) contains
no owned pointers (`~T`).  So, all scalar types (`int`, `uint`, etc)
are implicitly copyable, as are managed and borrowed points like `@T`
and `&T`, as well as structs and enums composed of those types.
Basically, this is the set of types that we can cheaply copy from one
place to another without having to do any memory allocation.

The reason that types with mutable fields are not considered
implicitly copyable is that those tend to be values but rather types
with *identity*.  This is particularly true with the rules about
inherited mutability.  Therefore, copying those is generally an error.










