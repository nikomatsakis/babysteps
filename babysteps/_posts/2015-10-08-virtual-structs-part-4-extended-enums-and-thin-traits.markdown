---
layout: post
title: "Virtual Structs Part 4: Extended Enums And Thin Traits"
date: 2015-10-08 12:46:29 -0400
comments: false
categories: [Rust]
---

So, aturon wrote this [interesting post][tt] on an alternative
"virtual structs" approach, and, more-or-less since he wrote it, I've
been wanting to write up my thoughts. I finally got them down.

Before I go any further, a note on terminology. I will refer to
Aaron's proposal as [the Thin Traits proposal][tt], and my own
previous proposal as [the Extended Enums proposal][ee]. Very good.

(OK, I lied, one more note: starting with this post, I've decided to
disable comments on this blog. There are just too many forums to keep
up with! So if you want to discuss this post, I'd recommend doing so
on [this Rust internals thread][internals].)

### Conclusion

Let me lead with my conclusion: **while I still want the Extended
Enums proposal, I *lean* towards implementing the Thin Traits
proposal now, and returning to something like Extended Enums
afterwards (or at some later time)**. My reasoning is that the Thin
Traits proposal can be seen as a design pattern lying latent in the
Extended Enums proposal. Basically, once we implement
[specialization][], which I want for a wide variety of reasons, we
*almost* get Thin Traits for free. And the Thin Traits pattern is
useful enough that it's worth taking that extra step.

Now, since the Thin Traits and Extended Enums proposal appear to be
alternatives, you may wonder why I would think there is value in
potentially implementing both. The way I see it, they target different
things. Thin Traits gives you a way to very precisely fashion
something that acts like a C++ or Java class. This means you get thin
pointers, inherited fields and behavior, and you even get open
extensibility (but, note, you thus do not get downcasting).

Extended Enums, in contrast, is targeting the "fixed domain" use case,
where you have a defined set of possibilities. This is what we use
enums for today, but (for the reasons I outlined before) there are
various places that we could improve, and that was what the extended
enums proposal was all about. One advantage of targeting the fixed
domain use case is that you get additional power, such as the ability
to do match statements, or to use inheritance when implementing any
trait at all (more details on this last point below).

To put it another way: with Thin Traits, you write virtual methods
whereas with Extensible Enums, you write match statements -- and I
think match statements are far more common in Rust today.

Still, Thin Traits will be a very good fit for various use cases.
They are a good fit for Servo, for example, where they can be put to
use modeling the DOM. The extensibility here is probably a plus, if
not a hard requirement, because it means Servo can spread the DOM
across multiple crates. Another place that they might (maybe?) be
useful is if we want to have a stable interface to the AST someday
(though for that I think I would favor something like [RFC 757][]).

But I think there a bunch of use cases for extensible enums that thin
traits don't cover at all. For example, I don't see us using thin
traits in the compiler very much, nor do I see much of a role for them
in LALRPOP, etc. In all these cases, the open-ended extensibility of
Thin Traits is not needed and being able to exhaustively match is key.
Refinement types would also be very welcome.

Which brings me to my final thought. The Extended Enums proposal,
while useful, was not perfect. It had some rough spots we were not
happy with (which I'll discuss later on). Deferring the proposal gives
us time to find new solutions to those aspects. Often I find that when
I revisit a troublesome feature after letting it sit for some time, I
find that either (1) the problem I thought there was no longer bothers
me or (2) the feature isn't that important anyway or (3) there is now
a solution that was either previously not possible or which just never
occurred to me.

OK, so, with that conclusion out of the way, the post continues by
examining some of the rough spots in the Extended Enums proposal, and
then looking at how we can address those by taking an approach like
the one described in Thin Traits.

<!-- more -->

### Thesis: Extended Enums

Let's start by reviewing a bit of the
[Extended Enums proposal][ee]. Extended Enums, as you may recall,
proposed making types for each of the enum variants, and allowing them
to be structured in a hierarchy.  It also proposed permitting enums to
be declared as "unsized", which meant that the size of the enum type
varies depending on what variant a particular instance is.

In that proposal, I used a syntax where enums could have a list of
common fields declared in the body of the enum:

```rust
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

One could also declare the variants out of line, as in this example:

```rust
unsized enum Node {
  position: Rectangle, // <-- common fields, but no variants
  ...
}

enum Element: Node {
  ...
}

struct TextElement: Element {
  ...
}

...
```

Note that in this model, the "variants", or leaf nodes in the type
hierarchy, are always structs. The inner nodes of the hierarchy (those
with children) are enums.

In order to support the [abstraction of constructors][csbctor], the
proposal includes a special associated type that lets you pull out a
struct [containing the common fields from an enum][eector]. For
example, `Node::struct` would correspond to a struct like

```rust
struct NodeFields {
    position: Rectangle,
    ...
}
```

#### Complications with common fields

The original post glossed over certain complications that arise around
common fields. Let me outline some of those complications. To start,
the associated `struct` type has always been a bit odd. It's just an
unusual bit of syntax, for one thing. But also, the fact that this
struct is not declared by the user raises some thorny questions. For
example, are the fields declared as public or private?  Can we
implement traits for this associated `struct` type? And so forth.

There are similar questions raised about the common fields in the enum
itself. In a struct, fields are private by default, and must be
declared as public (even if the struct is public):

```rust
pub struct Foo { // the struct is public...
   f: i32        // ...but its fields are private.
}
```

But in an enum, variants (and their fields) are public if the enum is
public:

```rust
pub enum Foo { // the enum is public...
    Variant1 { f: i32 }, // ...and so are its variants, and their fields.
}
```

This default matches how enums and structs are typically used: public
structs are used to form abstraction barriers, and public enums are
exposed in order to allow the outside world to match against the
various cases. (We used to make the fields of public structs be public
as well, but we found that in practice the overwhelming majority were
just declared as private.)

However, these defaults are somewhat problematic for common fields.
For example, let's look at that DOM example again:

```rust
unsized pub enum Node {
  position: Rectangle,
  ...
}
```

This field is declared in an enum, and that enum is public. So should
the field `position` be public or private? I would argue that this
enum is more "struct-like" in its usage pattern, and the default
should be private. We could arrive at this by adjusting the defaults
based on whether the enum declares its variant inline or out of
line. I expect this would actually match pretty well with actual
usage, but you can see that this is a somewhat subtle rule.

### Antithesis: Thin Traits

Now let me pivot for a bit and discuss the Thin Traits proposal.  In
particular, let's revisit the DOM hierarchy that we saw before
(`Node`, `Element`, etc), and see how that gets modeled. In the thin
traits proposal, every logical "class" consists of two types. The
first is a struct that defines its common fields and the second is a
trait that defines any virtual methods. So, the root of a DOM might be
a `Node` type, modeled like so:

```rust
struct NodeFields {
    id: u32
}

#[repr(thin)]
trait Node: NodeFields {
    fn something(&self);
    fn something_else(&self);
}
```

The struct `NodeFields` here just represents the set of fields that
all nodes must have. Because it is declared as a superbound of `Node`,
that means that any type which implements `Node` must have
`NodeFields` as a prefix. As a result, if we have a `&Node` object, we
can access the fields from `NodeFields` at no overhead, even without
knowing the precise type of the implementor.

(Furthermore, because `Node` was declared as a thin trait, a `&Node`
pointer can be a thin pointer, and not a fat pointer. This does mean
that `Node` can only be implemented for local types. Note though that
you could use this same pattern without declaring `Node` as a thin
trait and it would still work, it's just that `&Node` references would
be fat pointers.)

The `Node` trait shown had two virtual methods, `something()` and
`something_else()`.  Using specialization, we can provide a default
impl that lets us give some default behavior there, but also allows
subclasses to override that behavior:

```rust
partial impl<T:Node> Node for T {
    fn something(&self) {
        // Here something_else() is not defined, so it is "pure virtual"
        self.something_else();
    }
}
```

Finally, if we have some methods that we would like to dispatch
statically on `Node`, we can do that by using an inherent method:

```rust
impl Node {
    fn get_id(&self) -> u32 { self.id }
}
```

This impl looks similar to the partial impl above, but in fact it is
not an impl *of* the trait `Node`, but rather adding inherent methods
that apply to `Node` objects. So if we call `node.get_id()` it doesn't
go through any virtual dispatch at all.

You can continue this pattern to create subclasses. So adding an
`Element` subclass might look like:

```rust
struct ElementFields: NodeFields {
  ..
}

#[repr(thin)]
trait Element: Node + ElementFields {
  ..
}
```

and so forth.

### Synthesis: Extended Enums as a superset of Thin Traits

The Thin Traits proposal addresses common fields by creating explicit
structs, like `NodeFields`, that serve as containers for the common
fields, and by adding struct inheritance. This is an alternative to
the special `Node::struct` we used in the Extended Enums
proposal. There are pros and cons to using struct inheritance over
`Node::struct`. On the pro side, struct inheritance sidesteps the
various questions about privacy, visibility, and so forth that arose
with `Node::struct`. On the con side, using structs requires a kind of
parallel hierarchy, which is something we were initially trying to
avoid. A final advantage for using struct inheritance is that it is a
"reusable" mechanism.  That is, whereas adding common fields to enums
only affects enums, using struct inheritance allows us to add common
fields to enums, traits, and other structs. Considering all of these
things, it seems like struct inheritance is a better choice.

If we were to convert the DOM example to use struct inheritance, it
would mean that an enum may inherit from a struct, in which case it
gets the fields of that struct. For out-of-line enum declarations,
then, we can simply create an enum with an empty body:

```rust
struct NodeFields {
  position: Rectangle, // <-- common fields, but no variants
}

#[repr(unsized)]
enum Node: NodeFields;

struct ElementFields: NodeFields {
  ..
}

enum Element: Node + ElementFields;
```

(I've also taken the liberty of changing from the `unsized` keyword to
an annotation, `#[repr(unsized)]`. Given that making an enum `unsized`
doesn't really affect its semantics, just the memory layout, using a
`#[repr]` attribute seems like a good choice. It was something we
considered before; I'm not really sure why we rejected it anymore.)

### Method dispatch

My post did not cover how virtual method dispatch was going to work.
Aaron gave a [quick summary in the Thin Trait proposal][summary].  I
will give an even quicker one here. It was a goal of the proposal that
one should be able to use inheritance to refine the behavior over the
type hierarchy. That is, one should be able to write a set of impls
like the following:

```rust
impl<T> MyTrait for Option<T> {
    default fn method1() { ... }
    default fn method2() { ... }
    default fn method3();
}

impl<T> MyTrait for Option::Some<T> {
    fn method1() { /* overrides the version above */ }
    fn method3() { /* must be implemented */ }
}

impl<T> MyTrait for Option::None<T> {
    fn method2() { /* overrides the version above */ }
    fn method3() { /* must be implemented */ }
}
```

This still seems like a very nice feature to me. As the Thin Traits
proposal showed, specialization makes this kind of refinement
possible, but it requires a variety of different impls. The example
above, however, didn't have quite so many impls -- why is that?

What we had envisioned to bridge the gap was that we would use a kind
of implicit sugar. That is, the impl for `Option<T>` would effectively
be expanded to two impls. One of them, the partial impl, provides the
defaults for the variants, and other, a concrete impl, effectively
implements the virtual dispatch, by matching and dispatching to the
appropriate variant:

```rust
// As originally envisioned, `impl<T> MyTrait for Option<T>`
// would be sugar for the following two impls:

partial impl<T> MyTrait for Option<T> {
    default fn method1() { ... }
    default fn method2() { ... }
    default fn method3();
}

impl<T> MyTrait for Option<T> {
    fn method1(&self) {
        match self {
            this @ &Some(..) => Option::Some::method1(this),
            this @ &None => Option::None::method1(this),
        }
    }
    ... // as above, but for the other methods
}
```

Similar expansions are needed for inherent impls. You may be wondering
*why* it is that we expand the one impl (for `Option<T>`) into two
impls in the first place. Each plays a distinct role:

- The `partial impl` handles the defaults part of the picture. That
  is, it supplies default impls for the various methods that impls for
  `Some` and `None` can reuse (or override).
- The `impl` itself handles the "virtual" dispatch part of things.  We
  want to ensure that when we call `method1()` on a variable `o` of
  type `Option<T>`, we invoke the appropriate `method1` depending on
  what variant `o` actually is at runtime. We do this by matching on
  `o` and then delegating to the proper place. If you think about it,
  this is roughly equivalent to loading a function pointer out of a
  vtable and dispatching through that, though the performance
  characteristics are interesting (in a way, it resembles a fully
  expanded builtin [PIC][]).

Overall, this kind of expansion is a bit subtle. It'd be nice to have
a model that did not require it. In fact, in an earlier design, we DID
avoid it. We did so by introducing a new shorthand, called `match
impl`. This would basically create the "downcasting" impl that we
added implicitly above. This would make the correct pattern as
follows:

```rust
partial impl<T> MyTrait for Option<T> { // <-- this is now partial
    default fn method1() { ... }
    default fn method2() { ... }
    default fn method3();
}

match impl<T> MyTrait for Option<T>; // <-- this is new

impl<T> MyTrait for Option::Some<T> {
    fn method1() { /* overrides the version above */ }
    fn method3() { /* must be implemented */ }
}

impl<T> MyTrait for Option::None<T> {
    fn method2() { /* overrides the version above */ }
    fn method3() { /* must be implemented */ }
}
```

At first glance, this bears a strong resemblance to how the Thin Trait
proposal handled virtual dispatch. In the Thin Trait proposal, we have
a `partial impl` as well, and then concrete impls that override the
details. However, there is no `match impl` in Thin Trait proposal. It
is not needed because, in that proposal, we were implementing the
`Node` trait for the `Node` type -- and in fact the compiler supplies
that impl automatically, as part of the [object safety][os] notion.

#### Expression problem, I know thee well---a serviceable villain

But there is another difference between the two examples, and it's
important. In this code I am showing above, there is in fact no
connection between `MyTrait` and `Option`. That is, under the Extended
Enums proposal, I can implement foreign traits and use inheritance to
refine the behavior depending on what variant I have.  The Thin Traits
pattern, however, only works for implementing the "main" traits (e.g.,
`Node`, `Element`, etc) -- and the reason why is because you can't
write "match impls" under the Thin Traits proposal, since the set of
types is open-ended. (Instead we lean on the compiler-generated
virtual impl of `Node` for `Node`, etc.)

What you *can* do in the Thin Traits proposal is to add methods to the
main traits and just delegate to those. So I could do something like:

```rust
trait MyTrait {
    fn my_method(&self);
}

...

trait Node {
    fn my_trait_my_method(&self);
}

impl MyTrait for Node {
    fn my_method(&self) {
        // delegate to the method in the `Node` trait
        self.my_trait_my_method();
    }
}
```

Now you can use inheritance to refine the behavior of
`my_trait_my_method` if you like. But note that this only works if the
`MyTrait` type is in the same crate as `Node` or some ancestor crate.

The reason for this split is precisely the open-ended nature of the
Thin Trait pattern. Or, to give this another name, it is the famous
[expression problem][]. With Extensible Enums, we enumerated all the
cases, so that means that other, downstream crates, can now implement
traits against those cases. We've fixed the set of cases, but we can
extended infinitely the set of operations. In contrast, with Thin
Traits, we enumerated the operations (as the contents of the master
traits), but we allow downstream crates to implement new cases for
those operations.

So method dispatch proves to be pretty interesting:

- It gives further evidence that Extensible Enums represent a useful
  entity in their own right.
- It seems like a case where we may find that the tradeoffs change
  over time. That is, maybe `match impl` is not such a bad solution
  after all, particularly if the Thin Trait pattern is covering some
  share of the "object-like" use cases. In which case one of the main
  bits of "magic" in the Extensible Enums proposal goes away.
  
### Conclusion

Oh, wait, I already gave it. Well, the most salient points are:

- Extensible Enums are about a fixed set of cases, open-ended set of
  operations. Thin Traits are not. This matters.
- Thin Traits are (almost) a "latent pattern" in the Extensible Enums
  proposal, requiring only `#[repr(thin)]` and struct inheritance.
  - Struct inheritance might be nicer than associated structs anyway.
- We could consider doing both, and if so, it would probably make
  sense to implement Specialization, then Thin Traits, and only then
  consider Extensible Enums.

[tt]: http://aturon.github.io/blog/2015/09/18/reuse/
[RFC 250]: https://github.com/rust-lang/rfcs/pull/250
[RFC 757]: https://github.com/rust-lang/rfcs/pull/757
[ee]: http://smallcultfollowing.com/babysteps/blog/2015/08/20/virtual-structs-part-3-bringing-enums-and-structs-together/
[eector]: http://smallcultfollowing.com/babysteps/blog/2015/08/20/virtual-structs-part-3-bringing-enums-and-structs-together/#associated-structs-constructors
[csbctor]: http://smallcultfollowing.com/babysteps/blog/2015/05/29/classes-strike-back/#problem-3-initialization-of-common-fields
[subtyping]: http://smallcultfollowing.com/babysteps/blog/2015/08/20/virtual-structs-part-3-bringing-enums-and-structs-together/#subtyping-and-coercion
[os]: http://huonw.github.io/blog/2015/01/object-safety/
[summary]: http://aturon.github.io/blog/2015/09/18/reuse/#ending-2:-the-enum-based-approach
[PIC]: https://en.wikipedia.org/wiki/Inline_caching#Polymorphic_inline_caching
[Expression Problem]: https://en.wikipedia.org/wiki/Expression_problem
[internals]: https://internals.rust-lang.org/t/blog-post-extended-enums-and-thin-traits/2755
[specialization]: https://github.com/rust-lang/rfcs/pull/1210
