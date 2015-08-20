---
layout: post
title: "Virtual Structs Part 3: Bringing Enums and Structs Together"
date: 2015-08-20 09:29:45 -0400
comments: true
categories: [Rust]
---

So, in [previous][pp1] [posts][pp2], I discussed the pros and cons of two different
approaches to modeling variants: Rust-style enums and C++-style
classes. In those posts, I explained why I see Rust enums and OO-style
class hierarchies as more alike than different (I personally credit
Scala for opening my eyes to this, though I'm sure it's been
understood by others for much longer). The key points were as follows:

[pp1]: http://smallcultfollowing.com/babysteps/blog/2015/05/05/where-rusts-enum-shines/
[pp2]: http://smallcultfollowing.com/babysteps/blog/2015/05/29/classes-strike-back/

- Both Rust-style enums and C++-style classes can be used to model the
  idea of a value that be one of many variants, but there are
  differences in how they work at runtime. These differences mean that
  Rust-style enums are more convenient for some tasks, and C++-style
  classes for others. In particular:
  - A Rust-style enum is sized as large as the largest variant. This is
    great because you can lay them out flat in another data structure
    without requiring any allocation. You can also easily change from
    one variant to another. One downside of Rust enums is that you cannot
    "refine" them to narrow the set of variants that a particular value
    can have.
  - A C++-style class is sized to be exactly as big as one variant. This
    is great because it can be much more memory efficient. However, if
    you don't know what variant you have, you must manipulate the value
    by pointer, so it tends to require more allocation. It is also
    impossible to change from one variant to another. Class hierarchies
    also give you a simple, easily understood kind of refinement, and
    the ability to have common fields that are shared between variants.
- C++-style classes offer constructors, which allows for more
  abstraction and code reuse when initially creating an instance, but
  raise thorny questions about the type of a value under construction;
  Rust structs and enums are always built in a single-shot today,
  which is simpler and safer but doesn't compose as well.

What I want to talk about in this post is a proposal (or
proto-proposal) for bridging those two worlds in Rust. I'm going to
focus on data layout in this post. I'll defer virtual methods for
another post (or perhaps an RFC). *Spoiler alert:* they can be viewed
as a special case of [specialization].

[specialization]: https://github.com/rust-lang/rfcs/pull/1210

I had originally intended to publish this post a few days after the
others. Obviously, I got delayed. Sorry about that!  Things have been
very busy! In any case, better late than never, as
some-great-relative-or-other always (no doubt) said. Truth is, I
really miss blogging regularly, so I'm going to make an effort to
write up more "in progress" and half-baked ideas (yeah yeah, promises
to blog more are a dime a dozen, I know).

*Note:* I want to be clear that the designs in this blog post are not
"my" work per se. Some of the ideas originated with me, but others
have arisen in the course of conversations with others, as well as
earlier proposals from nrc, which in turn were heavily based on
community feedback. And of course it's not like we Rust folk invented
OO or algebraic data types or anything in the first place. :)

<!-- more -->

### Unifying structs and enums into type hierarchies

The key idea is to generalize enums and structs into a single concept.
This is often called an *algebraic data type*, but "algebra" brings
back memories of balancing equations in middle school (not altogether
unpleasant ones, admittedly), so I'm going to use the term *type
hierarchy* instead. Anyway, to see what I mean, let's look at my
favorite enum ever, `Option`:

```rust
enum Option<T> {
    Some(T), None
}
```

The idea is to reinterpret this enum as three types arranged into a
tree or hierarchy. An important point is that every node in the tree
is now a type: so there is a type representing the `Some` variant, and
a type representing the `None` variant:

```
enum Option<T>
|
+- struct None<T>
+- struct Some<T>
```

As you can see, the leaves of the tree are called structs. They
represent a particular variant. The inner nodes are called enums, and
they represent a set of variants. Every existing `struct` definition
can also be reinterpreted as a hierarchy, but just a hierarchy of size
1.

These generalized type hierarchies can be any depth. This means you
can do nested enums, like:

```rust
enum Mode {
    enum ByRef {
        Mutable,
        Immutable
    }
    ByValue
}
```

This creates a nested hierarchy:

```
enum Mode
|
+- enum ByRef
|  |
|  +- struct Mutable
|  +- struct Immutable
+- ByValue
```

Since all the nodes in a hiearchy are types, we get refinement types
for free. This means that I can use `Mode` as a type to mean "any mod
at all", or `Mode::ByRef` for the times when I know something is one
of the `ByRef` modes, or even `Mode::ByRef::Mutable` (which is a
singleton struct).

As part of this change, it should be possible to declare the variants
out of line.  For example, we could change enum to look as follows:

```rust
enum Option<T> {
}
struct Some<T>: Option<T> {
    value: T
}
struct None<T>: Option<T> {
}
```

This definitely is not exactly equivalent to the older one, of course.
The names `Some` and `None` live alongside `Option`, rather than
within it, and I've used a field (`value`) rather than a tuple struct.

### Common fields

Enum declarations are extended with the ability to have fields as well
as variants. These fields are inherited by all variants of that enum.
In the syntax, fields must appear before the variants, and it is also
not possible to combine "tuple-like" structs with inherited fields.

Let's revisit an example from [the previous post][pp2]. In the compiler,
we currently represent types with an enum. However, there are certain
fields that every type carries. These are handled via a separate struct,
so that we wind up with something like this:

```rust
type Ty<'tcx> = &'tcx TypeData<'tcx>;

struct TypeData<'tcx> {
    id: u32,
    flags: u32,
    ...,
    structure: TypeStructure<'tcx>,
}

enum TypeStructure<'tcx> {
    Int,
    Uint,
    Ref(Ty<'tcx>),
    ...
}
```

Under this newer design, we could simply include the common fields in the
enum definition:

```rust
type Ty<'tcx> = &'tcx TypeData<'tcx>;

enum TypeData<'tcx> {
    // Common fields:
    id: u32,
    flags: u32,
    ...,

    // Variants:
    Int { },
    Uint { },
    Ref { referent_ty: Ty<'tcx> },
    ...
}
```

Naturally, when I create a `TypeData` I should supply all the fields,
including the inherited ones (though in a later section I'll present
ways to extract the initialization of common fields into a reusable
fn):

```rust
let ref =
    TypeData::Ref {
        id: id,
        flags: flags,
        referent_ty: some_ty
    };
```

And, of course, given a reference `&TypeData<'tcx>`, we can access these common
fields:

```rust
fn print_id<'tcx>(t: &TypeData<'tcx>) {
    println!("The id of `{:?}` is `{:?}`", t, t.id);
}
```

Convenient!

[pp]: http://smallcultfollowing.com/babysteps/blog/2015/05/29/classes-strike-back/

### Unsized enums

As today, the size of an enum type, by default, is equal to the
largest of its variants. However, as I've outlined in the last two
posts, it is often useful to have each value be sized to a particular
variant. In the previous posts I identified some criteria for when
this is the case:

*One interesting question is whether we can concisely state
conditions in which one would prefer to have “precise variant sizes”
(class-like) vs “largest variant” (enum). I think the “precise
sizes” approach is better when the following apply:*

- *A recursive type (like a tree), which tends to force boxing
  anyhow. Examples: the AST or types in the compiler, DOM in servo, a
  GUI.*
- *Instances never change what variant they are.*
- *Potentially wide variance in the sizes of the variants.*

Therefore, it is possible to declare the root enum in a type hierarchy
as either sized (the default) or *unsized*; this choice is inherited
by all enums in the hierarchy. If the hierarchy is declared as
unsized, it means that **each struct type will be sized just as big as
it needs to be**.  This means in turn that the **enum types in the
hierarchy are unsized types**, since the space required will vary
depending on what variant an instance happens to be at runtime.

To continue with our example of types in rustc, we currently go
through some contortions so as to introduce indirection for uncommon
cases, which keeps the size of the enum under control:

```rust
type Ty<'tcx> = &'tcx TypeData<'tcx>;

enum TypeData<'tcx> {
    ...,

    // The data for a fn type is stored in a different struct
    // which is cached in a special arena. This is helpful
    // because (a) the size of this variant is only a single word
    // and (b) if we have a type that we know is a fn pointer,
    // we can pass the `BareFnTy` struct around instead of the
    // `TypeData`.
    FnPointer { data: &'tcx FnPointerData<'tcx> },
}

struct FnPointerData<'tcx> {
    unsafety: Unsafety,
    abi: Abi,
    signature: Signature,
}
```

As discussed in a comment in the code, the current scheme also serves
as a poor man's refinement type: if at some point in the code we know
we have a fn pointer, we can write a function that takes a
`FnPointerData` argument to express that:

```
fn process_ty<'tcx>(ty: Ty<'tcx>) {
    match ty {
        &TypeData::FnPointer { data, .. } => {
            process_fn_ty(ty, data)
        }
        ...
    }
}

// This function expects that `ty` is a fn pointer type. The `FnPointerData`
// contains the fn pointer information for `ty`.
fn process_fn_ty<'tcx>(ty: Ty<'tcx>, data: &FnPointerData<'tcx>) {
}
```

This pattern works OK in practice, but it is not perfect. For one
thing, it's tedious to construct, and it's also a little
inefficient. It introduces unnecessary indirection and a second memory
arena. Moreover, the refinement type scheme isn't great, because you
often have to pass both the `ty` (for the common fields) and the
internal `data`.

Using a type hierarchy, we can do much better. We simply remove the
`FnPointerData` struct and inline its fields directly into `TypeData`:

```rust
type Ty<'tcx> = &'tcx TypeData<'tcx>;

unsized enum TypeData<'tcx> {
    ...,

    // No indirection anymore. What's more, the type `FnPointer`
    // serves as a refinement type automatically.
    FnPointer {
        unsafety: Unsafety,
        abi: Abi,
        signature: Signature,
    }
}
```

Now we can write functions that process specific categories of types
very naturally:

```rust
fn process_ty<'tcx>(ty: Ty<'tcx>) {
    match ty {
        fn_ty @ &TypeData::FnPointer { .. } => {
            process_fn_ty(fn_ty)
        }
        ...
    }
}

// Don't even need a comment: it's obvious that `ty` should be a fn type
// (and enforced by the type system).
fn process_fn_ty<'tcx>(ty: &TypeData::FnPointer<'tcx>) {
}
```

### Matching as downcasting

As the previous example showed, one can continue to use match to select
the variant from an enum (sized or not). Maching also gives us an
elegant downcasting mechanism. Instead of writing `(Type) value`, as
in Java, or `dynamic_cast<Type>(value)`, one writes `match value` and
handles the resulting cases. Just as with enums today, `if let` can be
used if you just want to handle a single case.

### Crate locality

An important part of the design is that the entire type hierarchy must
be declared **within a single crate**. This is of course trivially
true today: all variants of an enums are declared in one item, and
structs correspond to singleton hierarchies.

Limiting the hierarchy to a single crate has a lot of advantages.
Without it, you simply can't support today's "sized" enums, for one
thing. It allows us to continue doing exhaustive checks for matches
and to generate more efficient code. It is interesting to compare to
`dynamic_cast`, the C++ equivalent to a match:

- `dynamic_cast` is often viewed as a kind of code smell, versus a
  virtual method. I'm inclined to agree, as `dynamic_cast` only checks
  for a particular variant, rather than specifying handling for the
  full range of variants; this makes it fragile in the face of edits
  to the code. In contrast, the exhaustive nature of a Rust `match`
  ensures that you handle every case (of course, one must still be
  judicious in your use of `_` patterns, which, while convenient, can
  be a refactoring hazard).
- `dynamic_cast` is somewhat inefficient, since it must handle the
  fully general case of classes that spread across compilation units;
  in fact, it is very uncommon to have a class hierarchy that is truly
  extensible -- and in such cases, using `dynamic_cast` is
  particularly hard to justify. This leads to projects like LLVM
  [reimplementing RTTI (the C++ name for matching) from scratch][rtti].

[rtti]: http://llvm.org/docs/CodingStandards.html#do-not-use-rtti-or-exceptions

Another advantage of confining the hierarchy to a single crate is that
it allows us to continue doing variance inference across the entire
hierarchy at once. This means that, for example, that in the "out of
line" version of `Option` (below) we can infer a variance for the
parameter `T` declared on `Option`, in the same way we do today
(otherwise, the declaration of `enum Option<T>` would require some
form of phantom data, and that would be *binding* on the types
declared in other crates).

I also find that confining the hierarchy to a single crate helps to
clarify the role of type hierarchies versus traits and, in turn, avoid
some of the pitfalls so beloved by OO haters. Basically, it means that
if you want to define an open-ended extension point, you must use a
trait, which also offers the most flexibility; a type hierarchy, like
an enum today, can only be used to offer a choice between a fixed
number of crate-local types. An analogous situation in Java would be
deciding between an abstract base class and an interface; under this
design, you would have to use an interface (note that the problem of
code reuse can be tackled separately, [via specialization]).

*Finally,* confining extension to a trait is relevant to the
construction of vtables and handling of specialization, but we'll dive
into that another time.

Even though I think that limiting type hierarchies to a single crate
is very helpful, it's worth pointing out that it IS possible to lift
this restriction if we so choose. This can't be done in all cases,
though, due to some of the inherent limitations involved.

### Enum types as bounds

In the previous section, I mentioned that enums and traits (both today
and in this proposed design) both form a kind of interface. Whereas
traits define a list of methods, enums indicate something about the
memory layout of the value: for example, they can tell you about a
common set of fields (though not the complete set), and they clearly
narrow down the universe of types to be just the relevant variants.
Therefore, it makes sense to be able to use an enum type as a bound on
a type parameter. Let's dive into an example to see what I mean and
why you might want this.

Imagine we're using a type hiererachy to represent the
[HTML DOM][dom].  It might look something like this (browser people:
forgive my radical oversimplification):

[dom]: https://developer.mozilla.org/en-US/docs/Web/API/Document_Object_Model/Introduction

```rust
unsized enum Node {
  // where this node is positioned after layout
  position: Rectangle,
  ...
}

enum Element: Node {
  ...
}

struct TextElement: Element {
  ...
}

struct ParagraphElement: Element {
  ...
}

...
```

Now imagine that I have a helper function that selects nodes based on whether
they intersect a particular box on the screen:

```rust
fn intersects(box: Rectangle, elements: &[Rc<Node>]) -> Vec<Rc<Node>> {
    let mut result = vec![];
    for element in elements {
        if element.position.intersects(box) {
            result.push(element.clone());
        }
    }
    result
}
```

OK, great! But now imagine that I have a slice of text elements
(`&[Rc<TextElement>]`), and I would like to use this function. I will
get back a `Vec<Rc<Node>>` -- I've lost track of the fact that my
input contained only text elements.

Using generics and bounds, I can rewrite the function:

```rust
fn intersects<T:Node>(box: Rectangle, elements: &[Rc<T>]) -> Vec<Rc<T>> {
    // identical to before
}
```

Nothing in the body had to change, only the signature.

Permitting enum types to appear as bounds also means that they can be
referenced by traits as supertraits. This allows you to define
interfaces that cut across the primary inheritance hierarchy. So, for
example, in the DOM both the `HTMLTextAreaElement` and the
`HTMLInputElement` can carry a block of text, which implies that they
have a certain set of text-related methods and properties in
common. And of course they are both elements. This can be modeled
using a trait like so:

```rust
trait TextAPIs: HTMLElement {
    fn maxLength(&self) -> usize;
    ..
}
```

This means that if you have an `&TextApis` object, you can access the
fields from `HTMLElement` with no overhead, because they are stored in
the same place for both cases. But if you want to access other things,
such as `maxLength`, that implies virtual dispatch, since the address
is dynamically computed and will vary.

#### Enums vs traits

The notion of enums as bounds raises questions about potential overlap
in purpose between enums and traits. I would argue that this overlap
already exists: both enums and traits today are ways to let you write
a single function that operates over values of more than one type.
However, in practice, it's rarely hard to know which one you want to
use. This I think is because they come at the problem from two
different angles:

- Traits start with the assumption that you want to work with any
  type, and let you narrow that. Basically, you get code that is *as
  general as possible*.
- In contrast, enums assume you want to work with a fixed set of
  types. This means you can write code that is *as specific as
  possible*. Enums also work best when the types you are choosing
  between are related into a kind of family, like "all the different
  variants of types in the Rust language" or "some and none".
  
If we extend enums in the way described here, then they will become
more capable and convenient, and so you might find that they overlap a
bit more with plausible use cases for traits. However, I think that in
practice there are still fairly clear guidelines for which to choose
when:

- If you have a fixed set of related types, use an enum. Having an
  enumerated set of cases is advantageous in a lot of ways: we can
  generate faster code, you can write matches, etc.
- If you want open-ended extension, use a trait (and/or trait object).
  This will ensure that your code makes as few assumptions as possible,
  which in turn means that you can handle as many clients as possible.
  
Because enums are tied to a fixed set of cases, they allow us to
generate tighter code, particularly when you are not monomorphizing.
That is, if you have a value of type `&TypeData`, where `TypeData` is
the enum we mentioned before, you can access common fields at no
overhead, even though we don't know what variant it is. Moreover, the
pointer is thin and thus takes only a single word.

In contrast, if you had made `TypeData` a trait and hence `&TypeData`
was a trait object, accessing common fields would require some
overhead.  (This is true even if we were to add "virtual fields" to
traits, as [eddyb and kimundi proposed in RFC #250][250].) Also,
because traits are "added on" to other values, your pointer would be a
fat pointer, and hence take two words.

(As an aside, I still like the idea of adding virtual fields to
traits.  The idea is that these fields could be "remapped" in an
implementation to varying offsets. Accessing such a field implies
dynamically loading the offset, which is slower than a regular field
but faster than a virtual call. If we additionally added the
restriction that those fields must access content that is orthogonal
from one another, we might be able to make the borrow checker more
permissive in the field case as well. But that is kind of an
orthogonal extension to what I'm talking about here -- and one that
fits well with my framing of "traits are for open-ended extension
across heterogeneous types, enums are for a single cohesive type
hierarchy".)

[250]: https://github.com/rust-lang/rfcs/pull/250

### Associated structs (constructors)

One of the distinctive features of OO-style classes is that they
feature constructors. Constructors allow you to layer initialization
code, so that you can build up a function that initializes (say) the
fields for `Node`, and that function is used as a building block by
one that initializes the `Element` fields, and so on down the
hierarchy. This is good for code reuse, but constructors have an
Achilles heel: while we are initializing the `Node` fields, what value
do the `Element` fields have? In C++, the answer is "who knows" -- the
fields are simply uninitialized, and accessing them is undefined
behavior. In Java, they are null. But Rust has no such "convenient"
answer. And there is an even weirder question: what happens when you
downcast or match on a value while it is being constructed?

Rust has always sidestepped these questions by using the functional
language approach, where you construct an aggregate value (like a
struct) by supplying all its data at once. This works good for small
structs, but it doesn't scale up to supporting refinement types and
common fields. Consider the example of types in the compiler:

```rust
enum TypeData<'tcx> {
    // Common fields:
    id: u32,
    flags: u32,
    counter: usize, // ok, I'm making this field up :P

    ...,
    FnPointer {
        unsafety: Unsafety,
        abi: Abi,
        signature: Signature,
    }
    ..., // other variants here
}
```

I would like to be able to write some initialization routines that
compute the `id`, flags, and whatever else and then reuse those across
different variants. But it's hard to know what such a function should
return:

```rust
fn init_type_data(cx: &mut Context) -> XXX {
    XXX { id: cx.next_id(), flags: DEFAULT_FLAGS, counter: 0 }
}
```

What is this type `XXX`? What I want is basically a struct with just
the common fields (though of course I don't want to have to define
such a struct mself, too repetitive):

```rust
struct XXX {
    id: u32,
    flags: u32,
    counter: usize,
}
```

And of coures I also want to be able to use an instance of this struct
in an initializer as part of a `..` expression, like so:

```rust
fn make_fn_type(cx: &mut Context, unsafety: Unsafety, abi: Abi, signature: Signature) {
    TypeData::FnPointer {
        unsafety: unsafety,
        abi: abi,
        signature: signature,
        ..init_type_data(cx)
    }
}
```

If we had a type like this, it strikes a reasonable nice balance
between the functional and OO styles. We can layer constructors and
build constructor abstractions, but we also don't have a value of type
`TypeData` until all the fields are initialized. In the interim, we
just have a value of this type `XXX`, which only has the shared fields
that are common to all variants.

All we need now is a reasonable name for this type `XXX`. The proposal
is that every enum has an associated struct type called `struct` (i.e,
the keyword). So instead of `XXX`, I could write `TypeData::struct`,
and it means "a struct with all the fields common to any `TypeData`
variant". Note that a `TypeData::struct` value is *not* a `TypeData`
variant; it just has the same data as a variant.

### Subtyping and coercion

There is one final wrinkle worth covering in the proposal. And
unfortunately, it's a tricky one. I've been sort of tacitly assuming
that an enum and its variants have some sort of typing relationship,
but I haven't said explicitly what it is. This part is going to take
some experimentation to find the right mix. But let me share some
intermediate thoughts.

**Unsized enums.** For unsized enums, we are always dealing with an
indirection. So e.g.  we have to be able to smoothly convert from a
reference to a specific struct like `&TextElement` to a reference to a
base enum like `&Node`.  We've traditionally viewed this as a special
case of ["DST coercions"][rfc982]. Basically, coercing to `&Node` is
more-or-less exactly like coercion to a trait object, except that we
don't in fact need to attach a vtable -- that is, the "extra data" on
the `&Node` fat pointer is just `()`. But in fact we don't necessarily
HAVE to view upcasting like this as a coercion -- after all, there is
no runtime change happening here.

This gets at an interesting point. Subtyping between OO classes is
normally actually subtyping between *references*. That is, in Java we
say that `String <: Object`, but that is because everything in Java is
in fact a reference. In C++, not everything is a reference, so if you
aren't careful this in fact gives rise to creepy hazards like
[object slicing][os]. The problem here is that in C++ the superclass
type is really just the superclass fields; so if you do `superclass =
subclass`, then you are just going to drop the extra fields from the
subclass on the floor (usually). This probably isn't what you meant to
do.

Because of unsized types, though, Rust can safely say that a struct
type is a subtype of its containing enum(s). So, in the DOM example,
we could say that `TextElement <: Node`. We don't have to fear slicing
because the type `TextElement` is unsized, and hence the user could
only ever make use of it by value. In other words, object slicing
arises C++ precisely because it doesn't have a notion of unsized
types.

**Sized enums.** To be honest, unsized enums are not the scary case,
because they are basically a new feature to the language. The harder
and more interesting case is sized enums. The problem here is that we
are introducing new types into existing code, and we want to be sure
not to break things. So consider this example:

```rust
let mut x = None;
x = Some(3);
```

In today's world, the first assignment gives `x` a type of
`Option<_>`, where the `_` represents something to be inferred
later. This is because the expression `None` has type `Option<_>`. But
under this RFC, the type of `None` is `None<_>` -- and hence we have
to be smart enough to infer that the type of `x` should not be
`None<_>` but rather `Option<_>` (because it is later assigned a
`Some<_>` value).

This kind of inference, where the type of a variable changes based on
the full set of values assigned to it, is traditionally what we have
called "subtyping" in the Rust compiler. (In contrast, coercion is an
instantaneous decision that the compiler makes based on the types it
knows thus far.) This is sort of technical minutia in how the compiler
works, but of course it impacts the places in Rust that you need type
annoations.

Now, to some extent, we already have this problem. There are known
cases today where coercions don't work as well as we would like. The
proposed `box` syntax, for example, suffers from this a bit, as do
other patterns.  We're investing ways to make the compiler smarter,
and it may be that we can combine all of this into a more intelligent
inference infrastructure.

**Variance and mutable references.** It's worth pointing out that
we'll always need some sort of coercion support, because subtyping
alone doesn't allow one to convert between mutable references. In
other words, `&mut TextElement` is not a subtype of `&mut Node`, but
we do need to be able to coercion from the former to the latter. This
is safe because the type `Node` is unsized (basically, it is safe for
the same reason that `&mut [i32; 3]` -> `&mut [i32]` is safe). The
fact that `&mut None<i32>` -> `&mut Option<i32>` is *not* safe is an
example of why sized enums can in fact be more challenging here.

[os]: http://stackoverflow.com/questions/274626/what-is-object-slicing

### Type parameters, GADTs, etc

One detail I want to note. At least to start, I anticipate a
requirement that every type in the hierarchy has the same set of type
parameters (just like an `enum` today). If you use the "inline"
syntax, this is implicit, but you'll have to write it explicitly with
the out of line syntax (we could permit reordering, but there should
be a 1-to-1 correspondence). This simplifies the type-checker and
ensures that this is more of an incremental step in complexity when
compared to today's enums, versus the giant leap we could have
otherwise -- loosening this rule also interacts with monomorphization
and specialization, but I'll dig into that more in a future post.

### An alternative variation

If, in fact, we can't solve the subtyping inference problems, there is
another option. Rather than unifying enums and structs, we could add
struct inheritance and leave enums as they are. Things would work
more-or-less the same as in this proposal, but base structs would play
the role of unsized enums, and sized enums would stay how they
are. This can be justified on the basis that enums are used in
different stylistic ways (like `Option` etc) where e.g. refinement
types and common fields are less important; however, I do find the
setup described in this blog post appealing.

### Conclusion

This post describes a proposal for unifying structs and enums to make
each of them more powerful. It builds on prior work but adds a few new
twists that close important gaps:

- Enum bounds for type parameters, allowing for smoother interaction with generic code.
- The "associated struct" for enums, allowing for constructors.

One of the big goals of this design is to find something that fits
well within Rust's orthogonal design. Today, data types like enums and
structs are focused on describing data layout and letting you declare
natural relationships that mesh well with the semantics of your
program. Traits, in contrast, are used to write generic code that
works across a heterogeneous range of types. This proposal retains
that character, while alleviating some of the pain points in Rust
today:

- Support for refinement types and nested enum hierarchies;
- Support for common fields shared across variants;
- Unsized enums that allow for more efficient memory layout.

