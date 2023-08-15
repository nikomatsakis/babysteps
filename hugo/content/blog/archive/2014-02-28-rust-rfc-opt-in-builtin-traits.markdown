---
categories:
- Rust
comments: true
date: "2014-02-28T00:00:00Z"
slug: rust-rfc-opt-in-builtin-traits
title: 'Rust RFC: Opt-in builtin traits'
---

In today's Rust, there are a number of builtin traits (sometimes
called "kinds"): `Send`, `Freeze`, `Share`, and `Pod` (in the future,
perhaps `Sized`). These are expressed as traits, but they are quite
unlike other traits in certain ways. One way is that they do not have
any methods; instead, implementing a trait like `Freeze` indicates
that the type has certain properties (defined below). The biggest
difference, though, is that these traits are not implemented manually
by users. Instead, the compiler decides automatically whether or not a
type implements them based on the contents of the type.

In this proposal, I argue to change this system and instead have users
manually implement the builtin traits for new types that they define.
Naturally there would be `#[deriving]` options as well for
convenience. The compiler's rules (e.g., that a sendable value cannot
reach a non-sendable value) would still be enforced, but at the point
where a builtin trait is explicitly implemented, rather than being
automatically deduced.

There are a couple of reasons to make this change:

1. **Consistency.** All other traits are opt-in, including very common
   traits like `Eq` and `Clone`. It is somewhat surprising that the
   builtin traits act differently.
2. **API Stability.** The builtin traits that are implemented by a
   type are really part of its public API, but unlike other similar
   things they are not declared. This means that seemingly innocent
   changes to the definition of a type can easily break downstream
   users. For example, imagine a type that changes from POD to non-POD
   -- suddenly, all references to instances of that type go from
   copies to moves. Similarly, a type that goes from sendable to
   non-sendable can no longer be used as a message.  By opting in to
   being POD (or sendable, etc), library authors make explicit what
   properties they expect to maintain, and which they do not.
3. **Pedagogy.** Many users find the distinction between pod types
   (which copy) and linear types (which move) to be surprising. Making
   pod-ness opt-in would help to ease this confusion.
4. **Safety and correctness.** In the presence of unsafe code,
   compiler inference is unsound, and it is unfortunate that users
   must remember to "opt out" from inapplicable kinds. There are also
   concerns about future compatibility. Even in safe code, it can also
   be useful to impose additional usage constriants beyond those
   strictly required for type soundness.
   
I will first cover the existing builtin traits and define what they
are used for. I will then explain each of the above reasons in more
detail.  Finally, I'll give some syntax examples.

<!--more-->

#### The builtin traits

We currently define the following builtin traits:

- `Send` -- a type that deeply owns all its contents.
  (Examples: `int`, `~int`, not `&int`)
- `Freeze` -- a type which is deeply immutable when accessed via an
  `&T` reference.
  (Examples: `int`, `~int`, `&int`, `&mut int`, not `Cell<int>` or
   `Atomic<int>`)
- `Pod` -- "plain old data" which can be safely copied via memcpy.
  (Examples: `int`, `&int`, not `~int` or `&mut int`)

We are in the process of adding an additional trait:

- `Share` -- a type which is threadsafe when accessed via an `&T`
  reference. (Examples: `int`, `~int`, `&int`, `&mut int`,
  `Atomic<int>`, not `Cell<int>`)

#### Proposed syntax

Under this proposal, for a struct or enum to be considered send,
freeze, pod, etc, those traits must be explicitly implemented:

    struct Foo { ... }
    impl Send for Foo { }
    impl Freeze for Foo { }
    impl Pod for Foo { }
    impl Share for Foo { }

For generic types, a conditional impl would be more appropriate:

    enum Option<T> { Some(T), None }
    impl<T:Send> Send for Option<T> { }
    // etc
    
As usual, deriving forms would be available that would expand into
impls like the one shown above.

Whenever a builtin trait is implemented, the compiler will enforce the
same requirements it enforces today. Therefore, code like the
following would yield an error:

    struct Foo<'a> { x: &'a int }
    
    // ERROR: Cannot implement `Send` because the field `x` has type
    // `&'a int` which is not sendable.
    impl<'a> Send for Foo<'a> { }

These impls would follow the usual coherence requirements. For
example, a struct can only be declared as `Share` within the crate
where it is defined.

For convenience, I also propose a deriving shorthand
`#[deriving(Data)]` that would implement a "package" of common traits
for types that contain simple data: `Eq`, `Ord`, `Clone`, `Show`,
`Send`, `Share`, `Freeze`, and `Pod`.

#### Pod and linearity

One of the most important aspects of this proposal is that the `Pod`
trait would be something that one "opts in" to. This means that
structs and enums would *move by default* unless their type is
explicitly declared to be `Pod`. So, for example, the following
code would be in error:

    struct Point { x: int, y: int }
    ...
    let p = Point { x: 1, y: 2 };
    let q = p;  // moves p
    print(p.x); // ERROR
    
To allow that example, one would have to impl `Pod` for `Point`:

    struct Point { x: int, y: int }
    impl Pod for Point { }
    ...
    let p = Point { x: 1, y: 2 };
    let q = p;  // copies p, because Point is Pod
    print(p.x); // OK
    
Effectively this change introduces a three step ladder for types:

1. If you do nothing, your type is *linear*, meaning that it moves
   from place to place and can never be copied in any way. (We need a
   better name for that.)
2. If you implement `Clone`, your type is *cloneable*, meaning that it
   moves from place to place, but it can be explicitly cloned. This is
   suitable for cases where copying is expensive.
3. If you implement `Pod`, your type is *plain old data*, meaning that
   it is just copied by default without the need for an explicit
   clone.  This is suitable for small bits of data like ints or
   points.
   
What is nice about this change is that when a type is defined, the
user makes an *explicit choice* between these three options.

#### Consistency

This change would bring the builtin traits more in line with other
common traits, such as `Eq` and `Clone`. On a historical note, this
proposal continues a trend, in that both of those operations used to
be natively implemented by the compiler as well.

#### API Stability

The set of builtin traits implemented by a type must be considered
part of its public inferface. At present, though, it's quite invisible
and not under user control. If a type is changed from `Pod` to
non-pod, or `Send` to non-send, no error message will result until
client code attempts to use an instance of that type. In general we
have tried to avoid this sort of situation, and instead have each
declaration contain enough information to check it indepenently of its
uses. Issue #12202 describes this same concern, specifically with
respect to stability attributes.

Making opt-in explicit effectively solves this problem. It is clearly
written out which traits a type is expected to fulfill, and if the
type is changed in such a way as to violate one of these traits, an
error will be reported at the `impl` site (or `#[deriving]`
declaration).

#### Pedagogy

When users first start with Rust, ownership and ownership transfer is
one of the first things that they must learn. This is made more
confusing by the fact that types are automatically divided into pod
and non-pod without any sort of declaration. It is not necessarily
obvious why a `T` and `~T` value, which are *semantically equivalent*,
behave so differently by default. Makes the pod category something you
opt into means that types will all be linear by default, which can
make teaching and leaning easier.

#### Safety and correctness: unsafe code

For safe code, the compiler's rules for deciding whether or not a type
is sendable (and so forth) are perfectly sound. However, when unsafe
code is involved, the compiler may draw the wrong conclusion. For such
cases, types must *opt out* of the builtin traits.

In general, the *opt out* approach seems to be hard to reason about:
many people (including myself) find it easier to think about what
properties a type *has* than what properties it *does not* have,
though clearly the two are logically equivalent in this binary world
we programmer's inhabit.

More concretely, opt out is dangerous because it means that types with
unsafe methods are generally *wrong by default*. As an example,
consider the definition of the `Cell` type:

    struct Cell<T> {
        priv value: T
    }
    
This is a perfectly ordinary struct, and hence the compiler would
conclude that cells are freezable (if `T` is freezable) and so forth.
However, the *methods* attached to `Cell` use unsafe magic to mutate
`value`, even when the `Cell` is aliased:

    impl<T:Pod> Cell<T> {
        pub fn set(&self, value: T) {
            unsafe {
                *cast::transmute_mut(&self.value) = value
            }
        }
    }

To accommodate this, we currently use *marker types* -- special types
known to the compiler which are considered nonpod and so forth. Therefore,
the full definition of `Cell` is in fact:

    pub struct Cell<T> {
        priv value: T,
        priv marker1: marker::InvariantType<T>,
        priv marker2: marker::NoFreeze,
    }

Note the two markers. The first, `marker1`, is a hint to the variance
engine indicating that the type `Cell` must be invariant with respect
to its type argument. The second, `marker2`, indicates that `Cell` is
non-freeze. This then informs the compiler that the referent of a
`&Cell<T>` can't be considered immutable. The problem here is that, if
you don't know to opt-out, you'll wind up with a type definition that
is unsafe.

This argument is rather weakened by the continued necessity of a
`marker::InvariantType` marker. This could be read as an argument
towards explicit variance. However, I think that in this particular
case, the better solution is to introduce the `Mut<T>` type described
in #12577 -- the `Mut<T>` type would give us the invariance.

Using `Mut<T>` brings us back to a world where any type that uses
`Mut<T>` to obtain interior mutability is correct by default, at least
with respect to the builtin kinds. Types like `Atomic<T>` and
`Volatile<T>`, which guarantee data race freedom, would therefore have
to *opt in* to the `Share` kind, and types like `Cell<T>` would simply
do nothing.

#### Safety and correctness: future compatibility

Another concern about having the compiler automatically infer
membership into builtin bounds is that we may find cause to add new
bounds in the future. In that case, existing Rust code which uses
unsafe methods might be inferred incorrectly, because it would not
know to opt out of those future bounds. Therefore, any future bounds
will *have* to be opt out anyway, so perhaps it is best to be
consistent from the start.

#### Safety and correctness: semantic constraints

Even if type safety is maintained, some types ought not to be copied
for semantic reasons. An example from the compiler is the
`Datum<Rvalue>` type, which is used in code generation to represent
the computed result of an rvalue expression. At present, the type
`Rvalue` implements a (empty) destructor -- the sole purpose of this
destructor is to ensure that datums are not consumed more than once,
because this would likely correspond to a code gen bug, as it would
mean that the result of the expression evaluation is consumed more
than once. Another example might be a newtype'd integer used for
indexing into a thread-local array: such a value ought not to be
sendable. And so forth. Using marker types for these kinds of
situations, or empty destructors, is very awkward. Under this
proposal, users needs merely refrain from implementing the relevant
traits.

#### The `Sized` bound

In DST, we plan to add a `Sized` bound. I do not feel like users
should manually implemented `Sized`. It seems tedious and rather
ludicrous.

#### Counterarguments

The downsides of this proposal are:

- There is some annotation burden. I had intended to gather statistics
  to try and measure this but have not had the time.
  
- If a library forgets to implement all the relevant traits for a
  type, there is little recourse for users of that library beyond pull
  requests to the original repository. This is already true with
  traits like `Eq` and `Ord`. However, as SiegeLord noted on IRC, that
  you can often work around the absence of `Eq` with a newtype
  wrapper, but this is not true if a type fails to implement `Send` or
  `Pod`. This danger (forgetting to implement traits) is essentially
  the counterbalance to the "forward compatbility" case made above:
  where implementing traits by default means types may implement too
  much, forcing explicit opt in means types may implement too little.
  One way to mitigate this problem would be to have a lint for when an
  impl of some kind (etc) would be legal, but isn't implemented, at
  least for publicly exported types in library crates.

