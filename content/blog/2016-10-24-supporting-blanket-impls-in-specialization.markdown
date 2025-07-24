---
layout: post
title: "Supporting blanket impls in specialization"
date: 2016-10-24T13:42:24-0400
comments: false
categories: [Rust, Specialization, Traits]
---

In my [previous post][reuse], I talked about how we can separate out
specialization into two distinct concepts: **reuse** and **override**.
Doing so makes because the conditions that make reuse possible are
more stringent than those that make override possible. **In this post,
I want to extend this idea to talk about a new rule for specialization
that allow overriding in more cases.** These rules are a big enabler
for specialization, allowing it to accommodate many use cases that we
couldn't handle before. In particular, they enable us to add blanket
impls like `impl<T: Copy> Clone for T` in a backwards compatible
fashion, though only under certain conditions.

[reuse]: {{< baseurl >}}/blog/2016/09/29/distinguishing-reuse-from-override/
[ii]: {{< baseurl >}}/blog/2016/09/24/intersection-impls/
[1210]: https://github.com/rust-lang/rfcs/pull/1210

<!-- more -->

### Revised algorithm

The key idea in this blog post is to change the rules for when some
impl I specializes another impl J. Instead of basing the rules on
"subsets of types", I propose a two-tiered rule. Let me outline it
first and then I will go into more detail afterwards.

1. First, **impls with more specific types specialize other impls**
   (ignoring where clauses altogether).
  - So, for example, if impl I is `impl<T: Clone> Clone for
    Option<T>`, and impl J is `impl<U: Copy> Clone for U`, then I will
    be used in preference to J, at least for those types where they
    intersect (e.g., `Option<i32>`). This is because `Option<T>` is
    more specific than `U`.
    - For types where they do not intersect (e.g., `i32` or `Option<String>`),
      then only one impl is used.
    - Note that the where clauses like `T: Clone` and `U: Copy` don't matter
      at all for this test.
2. However, **reuse is only allowed if the full subset conditions are
   met**.
  - So, in our example, impl I is not a full subset of impl J, because
    of types like `Option<String>`. This means that impl I could not
    reuse items from impl J (and hence that all items in impl J must
    be declared default).
3. If the impls types are equally generic, then **impls with more specific where clauses
   specialize other impls**.
  - So, for example, if impl I is `impl<T: Debug> Parse for T` and
    impl J is `impl<T> Parse for T`, then impl I is used in preference
    to impl J where possible. In particular, types that implement
    `Debug` will prefer impl I.
    
Another way to express the rule is to say that impls can specialize one
another in two ways:

- if the **types matched by one impl are a subset of the other**,
  ignoring where clauses altogether;
- otherwise, if the types matched by the two impls are the same, then
  if the **where clauses of one impl are more selective**.

Interestingly, and I'll go into this a bit more later, this rule is
not necessarily an *alternative* to the intersection impls I discussed
at first. In fact, the two can be used together, and complement each
other quite well.

### Some examples

Let's revisit some of the examples we've been working through and see
how the rule would apply. The first three examples illustrate the
first three clauses. Then I'll show some other interesting examples
that highlight various other facets and interactions of the rules.

#### Blanket impl of Clone for Copy types

First, we started out considering the case of trying to add a blanket
impl of `Clone` for all `Copy` types:

```rust
impl<T: Copy> Clone for T {
  default fn clone(&self) -> Self {
    *self
  }
}
```

We were concerned before that there are existing impls of `Clone` that
will partially overlap with this new blanket impl, but which will not
be full subsets of it, and which would therefore not be considered
specializations. For example, an impl for the `Option` type:

```rust
impl<T: Clone> Clone for Option<T> {
  fn clone(&self) -> Self {
    self.as_ref().map(|c| c.clone())
  }
}
```

Under these rules, this is no problem: the `Option` impl will take
precedence over the blanket impl, because its types are more specific.

**Note the interesting tie-in with the orphan rules here.** When we add blanket
impls, we have to worry about backwards compatibility in one of two ways:

- existing impls will now fail coherence checks that used to pass;
- some code that used to use an existing impl will silently change to
  using the blanket impl instead.
  
Naturally, the biggest concern is about impls in other crates, since
those impls are not visible to us. Interestingly, the orphan rules
require that those impls in other crates must be using **some local
type** in their signature. **Thus I believe the orphan rules ensure
that existing impls in other crates will take precedence over our new
blanket impl** -- that is, we are guaranteed that they are considered
legal specializations, and hence will pass coherence, and moreover
that the existing impl is used in preference over the blanket one.

### Dump trait: Reuse requires full subset

In [previous blog post][reuse] I gave an example of a `Dump` trait that
had a blanket impl for `Debug` things:

```rust
trait Dump {
    fn display(&self);
    fn debug(&self);
}

impl<T> Dump // impl A
    where T: Debug,
{
    default fn display(&self) {
        self.debug()
    }
    
    default fn debug(&self) {
        println!("{:?}", self);
    }
}
```

The idea was that some other crate might want to specialize `Dump`
just to change how `display` works, perhaps trying something like this:

```rust
struct Widget<T> { ... }

impl<T: Debug> Debug for Widget<T> {...}

// impl B (note that it is defined for all `T`, not `T: Debug`):
impl<T> Dump for Widget<T> {
    fn display(&self) {
        ...
    }
}
```

Here, impl B only defines the `display()` item from the trait because
it intends to reuse the existing `debug()` method from impl A.
However, this poses a problem: impl A only applies when `Widget<T>:
Debug`, which *may* be true but is not always true. In particular,
impl B is defined for any `Widget<T>`.

Under the rules I gave, this is an error. Here we have a scenario
where impl B **does** specialize impl A (because its types are more
specific), but **impl B is not a full subset of impl A, and therefore
it cannot reuse items from impl A**. It must provide a full definition
for all items in the trait (this also implies that every item in impl
A must be declared as `default`, as is the case here).

Note that either of these two alternatives for impl B would be fine:

```rust
// Alternative impl B.1: provides all items
impl<T> Dump for Widget<T> {
    fn display(&self) {...}
    fn debug(&self) {...}
}

// Alternative impl B.2: full subset
impl<T: Debug> Dump for Widget<T> {
    fn display(&self) {...}
}
```

There is some intersection with backwards compatibility here. If the
impl of `Dump` for `Widget` were added **before** impl A, then it
necessarily would have defined all items (as in impl B.1), and hence
there would be no error when impl A is added later.

#### Using where clauses to detect `Debug`

You may have noticed that if you do an index into a map and the key is
not found,
[the error message is kind of lackluster](https://is.gd/ARxIyV):

```rust
use std::collections::HashMap;

fn main() {
    let mut map = HashMap::new();
    map.insert("a", "b");
    map[&"c"];
    // Error: thread 'main' panicked at 'no entry found for key', ../src/libcore/option.rs:700
}
```

In particular, it doesn't tell you what key you were looking for! I
would have liked to see 'no entry found for "c"'. Well, the reason for
this is that the map code doesn't require that the key type `K` have a
`Debug` impl.  That's good, but it'd be nice if we could get a better
error if a debug impl **happens to exist**.

We might do so by using specialization. Let's imagine defining a trait
that can be used to panic when a key is not found. Thus when a map fails
to find a key, it invokes `key.not_found()`:

```rust
trait KeyNotFound {
    fn not_found(&self) -> !;
}

impl<T> KeyNotFound for T { // impl A
    fn not_found(&self) -> ! {
        panic!("no entry found for key")
    }
}    
```

Now we could provide a specialized impl that kicks in when `Debug` is available:

```rust
impl<T: Debug> KeyNotFound for T { // impl B
    fn not_found(&self) -> ! {
        panic!("no entry found for key `{:?}`", self)
    }
}    
```

Note that the types for impl B are not "more specific" than impl A,
unless you consider the where clauses. That is, they are both defined
for any type T. It is only when we consider the *where clauses* that
we see that impl B can in fact be judged more specific than A. This is
the third clause in my rules (it also works with specialization
today).

#### Fourth example: AsRef

One longstanding ergonomic problem in the standard library has been
that we could add all of the impls of
[the `AsRef` trait](https://doc.rust-lang.org/std/convert/trait.AsRef.html)
that we wanted. `T: AsRef<U>` is a trait that says "an `&T` reference
can be converted into a an `&U` reference". It is particularly useful
for types that support slicing, like `String: AsRef<str>` -- this
states that an `&String` can be sliced into an `&str` reference.

There are a number of blanket impls for `AsRef` that one might expect:

- Naturally one might expect that `T: AsRef<T>` would always hold.
  That just says that an `&T` reference can be converted into another
  `&T` reference (duh) -- which is sometimes called being *reflexive*.
- One might also that `AsRef` would be compatible with deref
  coercions. That is, if I can convert an `&U` reference to an `&V`
  reference, than I can also convert an `&&U` reference to an `&V`
  reference.

Unfortunately, if you try to combine both of those two cases, the current
coherence rules reject it (I'm going to ignore lifetime parameters here
for simplicity):

```rust
impl<T> AsRef<T> for T { } // impl A

impl<U, V> AsRef<V> for &U
    where U: AsRef<V> { }  // impl B
```

It's clear that these two impls, at least potentially, overlap.  In
particular, a trait reference like `&Foo: AsRef<&Foo>` could be
satisfied by either one (assuming that `Foo: AsRef<&Foo>`, which is
probably not true in practice, but could be implemented by some type
`Foo` in theory).

At the same time, it's clear that neither represents a subset of one
another, even if ignore where clauses. Just consider these examples:

- `String: AsRef<String>` (matches impl A, but not impl B)
- `&String: AsRef<String>` (matches impl B, but not impl A)

However, we'll see that we can satisfy this example if we incorporate
intersection impls; we'll cover this later.

### Detailed explanation: drilling into subset of types

OK, that was the high-level summary, let's start getting a bit more
into the details. In this section, I want to discuss how to implement
this new rule. I'm going to assume you've read and understood the
["Algorithmic formulation" section of the specialization RFC][alg],
which describes how to implement the subset check (if not, go ahead
and do so, it's quite readable -- nice job aturon!).

[alg]: https://github.com/rust-lang/rfcs/blob/master/text/1210-impl-specialization.md#algorithmic-formulation

Implementing the rules today basically consists of two distinct tests,
applied in succession. RFC 1210 describes how, given two impls I and
J, we can say define an ordering *Subset(I, J)* that indicates I
matches a subset of the types of J (the RFC calls it `I <= J`). The
current rules then say that I *specializes* J if *Subset(I, J)*
holds but *Subset(J, I)* does not.

To decide if *Subset(I, J)* holds, we apply two tests (both of which
must pass):

- **Type(I, J):** For any way of instantiating `I.vars`,
  there is some way of instantiating `J.vars` such that the `Self`
  type and trait type parameters match up.
  - Here `I.vars` refers to "the generic parameters of impl I"
  - The actual technique here is to [skolemize `I.vars`][skol] and
    then [attempt unification][unif]. If unification succeeds, then
    `Type(I, J)` holds.
- **WhereClause(I, J):** For the instantiation of `I.vars` used in
  *Type(I, J)*, if you assume `I.wc` holds, you can prove `J.wc`.
  - Here `I.wc` refers to "the where clauses of impl I".
  - The actual technique here is to consider `I.wc` as true,
    and attempt to prove `J.wc` using the standard trait machinery.

[skol]: https://github.com/rust-lang/rfcs/blob/master/text/1210-impl-specialization.md#skolemization-asking-forallthere-exists-questions  
[unif]: https://github.com/rust-lang/rfcs/blob/master/text/1210-impl-specialization.md#unification-solving-equations-on-types

The algorithm to test whether an impl I can specialize an impl J is this:

- *Specializes(I, J)*:
    - If *Type(I, J)* holds:
        - If *Type(J, I)* does not hold:
            - true
        - Otherwise, if *WhereClause(I, J)* holds:
            - If *WhereClause(J, I)* does not hold:
                - true
            - else:
                - false
    - false
  
You could also write this as *Specializes(I, J)* is:

```
Type(I, J) && (!Type(J, I) || WhereClause(I, J) && !WhereClause(J, I))
```

Unlike before, we also need a separate test to check whether *reuse*
is legal. Reuse is legal if *Subset(I, J)* holds.

You can view the *Specializes(I, J)* test as being based on a partial
order, where the `<=` predicate is the lexicographic combination of
two other partial orders, *Type(I, J)* and *WhereClause(I, J)*. This
implies that it is transitive.

### Combining with intersection impls

It's interesting to note that this rule can also be combined with the
rule for intersection impls. The idea of intersection impls is really
somewhat orthogonal to what exact test is being used to decide which
impl specializes another. Essentially, whereas without intersection
impls we say: "two impls can overlap so long as one of them
specializes the other", we would now add the additional possibility
that "two impls can overlap so long as some other impl specializes
both of them".

This is helpful for realizing some other patterns that we wanted to
get out of specialization but which, until now, we could not.

#### Example: AsRef

We saw earlier that this new rule doesn't allow us to add the
reflexive `AsRef` impl that we wanted to add. However, using an
**intersection impl**, we can make progress. We can basically add a
third impl:

```rust
impl<T> AsRef<T> for T { } // impl A

impl<U, V> AsRef<V> for &U
    where U: AsRef<V> { }  // impl B

impl<W> AsRef<&W> for &W { ... } // impl C
```

Impl C is a specialiation of both of the others, since every type it
can match can also be matched by the others. So this would be
accepted, since impl A and B overlap but have a common specializer.

(As an aside, you might also expect a generic transitivity impl, like
`impl<T,U,V> AsRef<V> for T where T: AsRef<U>`. I haven't thought much
about if such an impl would work with the specialization rules, since
I'm pretty sure though that we'd have to improve the trait matcher
implementation in any case to make it work, as I think right now it
would quickly overflow.)

#### Example: Overlapping blanket impls for Dump

Let's see another, more conventional example where an intersection
impl might be useful. We'll return to our `Dump` trait.  If you
recall, it had a blanket impl that implemented `Dump` for any type `T`
where `T: Debug`:

```rust
trait Dump {
    fn display(&self);
    fn debug(&self);
}

impl<T> Dump // impl A
    where T: Debug,
{
    default fn display(&self) {
        self.debug()
    }
    
    default fn debug(&self) {
        println!("{:?}", self);
    }
}
```

But we might also want another blanket impl for types where `T: Display`:

```rust
impl<T> Dump // impl B
    where T: Display,
{
    default fn display(&self) {
        println!("{}", self);
    }
    
    default fn debug(&self) {
        self.display()
    }
}
```

Now we have a problem. Impl A and B clearly potentially overlap, but
(a) neither is more specific in terms of its types (both apply to any
type `T`, so *Type(A, B)* and *Type(B, A)* will both hold) and (b)
neither is more specific in terms of its where-clauses: one applies to
types that implement `Debug`, and one applies to types that implement
`Display`, but clearly types can implement both.

With intersection impls we could resolve this error by providing
a third impl for types `T` where `T: Debug + Display`:

```rust
impl<T> Dump // impl C
    where T: Debug + Display,
{
    default fn display(&self) {
        println!("{}", self);
    }
    
    default fn debug(&self) {
        println!("{:?}", self);
    }
}
```

#### Orphan rules, blanket impls, and negative reasoning 

Traditionally, we have said that it is considering backwards
compatible (in terms of semver) to add impls for traits, with the
exception of "backwards impls" that apply to all `T`, even if `T` is
guarded by some traits (like the impls we saw for `Dump` in the
previous section). This is because if I add an impl like `impl<T:
Debug> Dump for T` where none existed before, some other crate may
already have an impl like `impl Dump for MyType`, and then if `MyType:
Debug`, we would have an overlap conflict, and hence that downstream
crate will not compile (see [RFC 1023][1023] for more information on
these rules).

[1023]: https://github.com/rust-lang/rfcs/blob/master/text/1023-rebalancing-coherence.md

This new proposed specialization rule has the potential to change that
balance. In fact, at first you might think that adding a blanket impl
would **always** be legal, as long as all of its members are declared
`default`. After all, any pre-existing impl from another crate must,
because of [the orphan rules][orphan], have more specific types, and
will thus take precedence over the default impl (moreover, since there
was nothing for this impl to inherit from before, it must still
inherit). So something like `impl Dump for MyType` would still be
legal, right?

[orphan]: http://smallcultfollowing.com/babysteps/blog/2015/01/14/little-orphan-impls/

But there is actually still a risk from blanket impls around
**negative reasoning**. To see what I mean, let's continue with a
simplified variant of the `Dump` example from the previous section
which doesn't use intersection impls. So imagine that we have the
`Dump` trait and the following impls:

```rust
// crate `dump`
trait Dump { }
trait<T: Display> Dump for T { .. }
trait<T: Debug + Display> Dump for T { .. }
```

So, these are pre-existing impls. Now, imagine that in the standard
library, we decided to add a kind of "fallback" impl of `Debug` that
says "any type which implements `Display`, automatically implements
`Debug`":

```rust
impl<T: Display> Debug for T {
  fn fmt(&self, fmt: &mut Formatter) -> Result<(), Error> {
    Display::fmt(self, fmt)
  }
}
```

Interestingly, this impl creates a problem for the crate `dump`!
Before, its two impls were well-ordered; one applied to types that
implement `Display`, and one applied to types that implement both
`Debug` and `Display`. But with this new impl, *all* types that
implement `Display` also implement `Debug`, so this distinction is
meaningless.

But wait, you cry! That impl looks awfully familiar to our motivating
example from the very first post! Remember that this all started because
we wanted to implement `Clone` for all `Copy` types:

```rust
impl<T: Copy> Clone for T { .. }
```

So is that actually illegal?

It turns out that there is a crucial difference between these two. It
does not lie in the *impls*, but rather in the *traits*. In
particular, the `Copy` trait is a *subtrait* of `Clone` -- that is,
anything which is copyable must also be cloneable. But `Display` and
`Debug` have no relationship; in fact, the blanket impl
interconverting between them is effectively *imposing* an
**undeclared** subtrait relationship `Display: Debug`. After all, now
some type T implements `Display`, we are guaranteed that it also
implements `Debug`.

**So this suggests that the new rule for semver compatibility is that
one can add blanket impls after the fact, but only if a subtrait
relationship already existed.**

As an aside, this -- along with the
[similar example raised by withoutboats and reddit user oconnor663][neg]
-- strongly suggests to me that traits need to "predeclare" strong
relationships, like subtraits but also mutual exclusion if we ever
support that, at the point when they are created. I know withoutboats
has some interesting thoughts in this direction. =)

However, another possibility that aturon raised is to use a more
*syntactic* criteria for when something is more specialized -- in that
case, `Debug+Display` would be considered more specialized than
`Display`, even if in reality they are equivalent. This may wind up
being easier to understand -- and more flexible -- even if it is less
smart.

[neg]: https://github.com/rust-lang/rfcs/pull/1658#issuecomment-249453099

### Conclusion

This post lays out an alternative specialization predicate that I
believe helps to overcome a lot of the shortcomings of the current
*subset* rule. The rule is fairly simple to describe: **impls with
more specific types get precedence**. If the types of two impls are
equally generic, then the impl with **more specific where-clauses gets
precedence**. I claim this rule is intuitive in practice; perhaps more
intuitive than the current rule.

This predicate allows for a number of scenarios that the current
specialization rule excludes, but which we wanted initially.  The ones
I have considered mostly fall into the category of adding an impl of a
supertrait in terms of a subtrait backwards compatibly:

  - `impl<T: Copy> Clone for T { ... }`
  - `impl<T: Eq> PartialEq for T { ... }`
  - `impl<T: Ord> PartialOrd for T { ... }`

If we combine with intersection impls, we can also accommodate the
`AsRef` impl, and also get better support for having overlapping
blanket impls. I'd be interested to hear about other cases where the
coherence rules were limiting that may be affected by specializaton,
so we can see how they fare.

**One sour note has to do with negative reasoning.** Specialization
based on where clauses (orthogonally from the changes proposed in this
post, in fact) introduces a kind of negative reasoning that is not
currently subject to the rules in [RFC 1023][1023]. This implies that
crates cannot add blanket impls with impunity. In particular,
introducing subtrait relationships can still cause problems, which
affects a number of suggested "bridge" cases:

- `impl<R, T: Add<R> + Clone> AddAssign<R> for T`
  - anything that has `Add` and `Clone` is now `AddAssign`
- `impl<T: Display> Debug for T`  
  - anything that is `Debug` is now `Display`

There may be some room to revise the specialization rules to address
this, by tweaking the *WhereClause(I, J)* test to be more
conservative, or to be more syntactical in nature. This will require
some further experimentation and tinkering.

### Comments

Please leave comments in
[this internals thread](https://internals.rust-lang.org/t/blog-post-supporting-blanket-impls-in-specialization/4264).
