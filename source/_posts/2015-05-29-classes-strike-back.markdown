---
layout: post
title: "Virtual Structs Part 2: Classes strike back"
date: 2015-05-29 11:52:26 -0400
comments: true
categories: [Rust]
---

This is the second post summarizing my current thoughts about ideas
related to "virtual structs". In the [last post], I described how,
when coding C++, I find myself missing Rust's enum type. In this post,
I want to turn it around. I'm going to describe why the class model
can be great, and something that's actually kind of missing from
Rust. In the next post, I'll talk about how I think we can get the
best of both worlds for Rust. As in the first post, I'm focusing here
primarily on the data layout side of the equation; I'll discuss
virtual dispatch afterwards.

<!-- more -->

### (Very) brief recap

In the previous post, I described how one can setup a class hierarchy
in C++ (or Java, Scala, etc) with a base class and one subclass for
every variant:

```cpp
class Error { ... };
class FileNotFound : public Error { ... };
class UnexpectedChar : public Error { ... };
```

This winds up being very similar to a Rust enum:

```rust
enum ErrorCode {
    FileNotFound,
    UnexpectedChar
}
```

However, there are are some important differences. Chief among them is
that the Rust enum has a size equal to the size of its largest
variant, which means that Rust enums can be passed "by value" rather
than using a box. This winds up being absolutely crucial to Rust: it's
what allows us to use `Option<&T>`, for example, as a zero-cost
nullable pointer. It's what allows us to make arrays of enums (rather
than arrays of boxed enums). It's what allows us to overwrite one enum
value with another, e.g. to change from `None` to `Some(_)`. And so
forth.

### Problem #1: Memory bloat

There are a lot of use cases, however, where having a size equal to
the largest variant is actually a handicap. Consider, for example, the
way the rustc compiler represents Rust types (this is actually a
cleaned up and simplified version of the [real thing][ty]).

[ty]: https://github.com/rust-lang/rust/blob/9854143cba679834bc4ef932858cd5303f015a0e/src/librustc/middle/ty.rs#L1359-L1397

The type `Ty` represents a rust type:

```rust
// 'tcx is the lifetime of the arena in which we allocate type information
type Ty<'tcx> = &'tcx TypeStructure<'tcx>;
```

As you can see, it is in fact a reference to a `TypeStructure` (this
is called `sty` in the Rust compiler, which isn't completely up to
date with modern Rust conventions). The lifetime `'tcx` here
represents the lifetime of the arena in which we allocate all of our
type information. So when you see a type like `&'tcx`, it represents
interned information allocated in an arena. (As an aside, we
[added the arena][1759] back before we even had lifetimes at all, and
used to use unsafe pointers here. The fact that we use proper
lifetimes here is thanks to the awesome [eddyb] and his super duper
[safe-ty] branch. What a guy.)

[1759]: https://github.com/rust-lang/rust/pull/1759
[safe-ty]: https://github.com/rust-lang/rust/pull/18483
[eddyb]: https://github.com/eddyb/

So, here is the first observation: in practice, we are already boxing
all the instances of `TypeStructure` (you may recall that the fact
that classes forced us to box was a downside before). We have to,
because types are recursively structured. In this case, the 'box' is
an arena allocation, but still the point remains that we always pass
types by reference. And, moreover, once we create a `Ty`, it is
immutable -- we never switch a type from one variant to another.

The actual `TypeStructure` enum is defined something like this:

```rust
enum TypeStructure<'tcx> {
    Bool,                                      // bool
    Reference(Region, Mutability, Type<'tcx>), // &'x T, &'x mut T
    Struct(DefId, &'tcx Substs<'tcx>),         // Foo<..>
    Enum(DefId, &'tcx Substs<'tcx>),           // Foo<..>
    BareFn(&'tcx BareFnData<'tcx>),            // fn(..)
    ...
}
```

You can see that, in addition to the types themselves, we also intern
a lot of the data in the variants themselves. For example, the
`BareFn` variant takes a `&'tcx BareFnData<'tcx>`. The reason we do
this is because otherwise the size of the `TypeStructure` type
balloons very quickly. This is because some variants, like `BareFn`,
have a lot of associated data (e.g., the ABI, the types of all the
arguments, etc). In contrast, types like structs or references have
relatively little associated data. Nonetheless, the size of the
`TypeStructure` type is determined by the largest variant, so it
doesn't matter if all the variants are small but one: the enum is
still large. To fix this, [Huon][huonw]
[spent quite a bit of time][19549] analyzing the size of each variant
and introducing indirection and interning to bring it down.

Consider what would have happened if we had used classes instead.  In
that case, the type structure might look like:

```cpp
typedef TypeStructure *Ty;
class TypeStructure { .. };
class Bool : public TypeStructure { .. };
class Reference : public TypeStructure { .. };
class Struct : public TypeStructure { .. };
class Enum : public TypeStructure { .. };
class BareFn : public TypeStructure { .. };
```

In this case, whenever we allocated a `Reference` from the arena, we
would allocate precisely the amount of memory that a `Reference`
needs. Similarly, if we allocated a `BareFn` type, we'd use more
memory for that particular instance, but it wouldn't affect the other
kinds of types. Nice.

[huonw]: https://github.com/huonw
[19549]: https://github.com/rust-lang/rust/pull/19549

### Problem #2: Common fields

The definition for `Ty` that I gave in the previous section was
actually somewhat simplified compared to what we really do in rustc.
The actual definition looks more like:

```rust
// 'tcx is the lifetime of the arena in which we allocate type information
type Ty<'tcx> = &'tcx TypeData<'tcx>;

struct TypeData<'tcx> {
    id: u32,
    flags: u32,
    ...,
    structure: TypeStructure<'tcx>,
}
```

As you can see, `Ty` is in fact a reference not to a `TypeStructure`
directly but to a struct wrapper, `TypeData`. This wrapper defines a
few fields that are common to all types, such as a unique integer id
and a set of flags. We could put those fields into the variants of
`TypeStructure`, but it'd be repetitive, annoying, and inefficient.

Nonetheless, introducing this wrapper struct feels a bit indirect. If
we are using classes, it would be natural for these fields to live on
the base class:

```cpp
typedef TypeStructure *Ty;
class TypeStructure {
    unsigned id;
    unsigned flags;
    ...
};
class Bool : public TypeStructure { .. };
class Reference : public TypeStructure { .. };
class Struct : public TypeStructure { .. };
class Enum : public TypeStructure { .. };
class BareFn : public TypeStructure { .. };
```

In fact, we could go further. There are many variants that share
common bits of data. For example, structs and enums are both just a
kind of nominal type ("named" type). Almost always, in fact, we wish
to treat them the same. So we could refine the hierarchy a bit to
reflect this:

```cpp
class Nominal : public TypeStructure {
    DefId def_id;
    Substs substs;
};
class Struct : public Nominal {
};
class Enum : public Nominal {
};
```

Now code that wants to work uniformly on either a struct or enum could
just take a `Nominal*`.

Note that while it's relatively easy in Rust to handle the case where
*all* variants have common fields, it's a lot more awkward to handle a
case like `Struct` or `Enum`, where only *some* of the variants have
common fields.

### Problem #3: Initialization of common fields

Rust differs from purely OO languages in that it does not have special
constructors. An instance of a struct in Rust is constructed by
supplying values for all of its fields. One great thing about this
approach is that "partially initialized" struct instances are never
exposed. However, the Rust approach has a downside, particularly when
we consider code where you have lots of variants with common fields:
there is no way to write a fn that initializes *only* the common
fields.

C++ and Java take a different approach to initialization based on
*constructors*. The idea of a constructor is that you first allocate
the complete structure you are going to create, and then execute a
routine which fills in the fields. This approach to constructos has a
lot of problems -- some of which I'll detail below -- and I would not
advocate for adding it to Rust. However, it does make it convenient to
separately abstract over the initialization of base class fields from
subclass fields:

```cpp
typedef TypeStructure *Ty;
class TypeStructure {
    unsigned id;
    unsigned flags;
    
    TypeStructure(unsigned id, unsigned flags)
      : id(id), flags(flags)
    { }
};

class Bool : public TypeStructure {
    Bool(unsigned id)
      : TypeStructure(id, 0) // bools have no flags
    { }
};
```

Here, the constructor for `TypeStructure` initializes the
`TypeStructure` fields, and the `Bool` constructor initializes the
`Bool` fields. Imagine we were to add a field to `TypeStructure` that
is always 0, such as some sort of counter. We could do this without
changing any of the subclasses:

```cpp
class TypeStructure {
    unsigned id;
    unsigned flags;
    unsigned counter; // new
    
    TypeStructure(unsigned id, unsigned flags)
      : id(id), flags(flags), counter(0)
    { }
};
```

If you have a lot of variants, being able to extract the common
initialization code into a function of some kind is pretty important.

Now, I promised a critique of constructors, so here we go. The biggest
reason we do not have them in Rust is that constructors rely on
exposing a partially initialized `this` pointer. This raises the
question of what value the fields of that `this` pointer have before
the constructor finishes: in C++, the answer is just undefined
behavior. Java at least guarantees that everything is zeroed. But
since Rust lacks the idea of a "universal null" -- which is an
important safety guarantee! -- we don't have such a convenient option.
And there are other weird things to consider: what happens if you call
a virtual function during the base type constructor, for example? (The
answer here again varies by language.)

So, I don't want to add OO-style constructors to Rust, but I do want
some way to pull out the initialization code for common fields into a
subroutine that can be shared and reused. This is tricky.

### Problem #4: Refinement types

Related to the last point, Rust currently lacks a way to "refine" the
type of an enum to indicate the set of variants that it might be. It
would be great to be able to say not just "this is a `TypeStructure`",
but also things like "this is a `TypeStructure` that corresponds to
some nominal type (i.e., a struct or an enum), though I don't know
precisely which kind". As you've probably surmised, making each
variant its own type -- as you would in the classes approach -- gives
you a simple form of refinement types for free.

To see what I mean, consider the class hierarchy we built for `TypeStructure`:

```cpp
typedef TypeStructure *Ty;
class TypeStructure { .. };
class Bool : public TypeStructure { .. };
class Reference : public TypeStructure { .. };
class Nominal : public TypeStructure { .. }
class Struct : public Nominal { .. };
class Enum : public Nominal { .. };
class BareFn : public TypeStructure { .. };
```

Now, I can pass around a `TypeStructure*` to indicate "any sort of
type", or a `Nominal*` to indicate "a struct or an enum", or a
`BareFn*` to mean "a bare fn type", and so forth.

If we limit ourselves to single inheritance, that means one can
construct an arbitrary tree of refinements. Certainly one can imagine
wanting arbitrary refinements, though in my own investigations I have
always found a tree to be sufficient. In C++ and Scala, of course, one
can use multiple inheritance to create arbitrary refinements, and I
think one can imagine doing something similar in Rust with traits.

As an aside, the right way to handle 'datasort refinements' has been a
topic of discussion in Rust for some time; I've posted a
[different proposal][vg] in the past, and, somewhat amusingly, my
[very first post][fp] on this blog was on this topic as well. I
personally find that building on a variant hierarchy, as above, is a
very appealing solution to this problem, because it avoids introducing
a "new concept" for refinements: it just leverages the same structure
that is giving you common fields and letting you control layout.

### Conclusion

So we've seen that there also advantages to the approach of using
subclasses to model variants. I showed this using the `TypeStructure`
example, but there are lots of cases where this arises. In the
compiler alone, I would say that the abstract syntax tree, the borrow
checker's `LoanPath`, the memory categorization `cmt` types, and
probably a bunch of other cases would benefit from a more class-like
approach. Servo developers have long been requesting something more
class-like for use in the DOM. I feel quite confident that there are
many other crates at large that could similarly benefit.

Interestingly, Rust can gain a lot of the benefits of the subclass
approach---namely, common fields and refinement types---just by making
enum variants into types. There have [been proposals][324] along these
lines before, and I think that's an important ingredient for the final
plan.

Perhaps the biggest difference between the two approaches is the size
of the "base type". That is, in Rust's current enum model, the base
type (`TypeStructure`) is the size of the maximal variant. In the
subclass model, the base class has an indeterminate size, and so must
be referenced by pointer. Neither of these are an "expressiveness"
distinction---we've seen that you can model anything in either
approach. But it has a big effect on how easy it is to write code.

One interesting question is whether we can concisely state conditions
in which one would prefer to have "precise variant sizes" (class-like)
vs "largest variant" (enum). I think the "precise sizes" approach is
better when the following apply:

1. A recursive type (like a tree), which tends to force boxing anyhow.
   Examples: the AST or types in the compiler, DOM in servo, a GUI.
2. Instances never change what variant they are.
3. Potentially wide variance in the sizes of the variants.

The fact that this is really a kind of efficiency tuning is an
important insight. Hopefully our final design can make it relatively
easy to change between the 'maximal size' and the 'unknown size'
variants, since it may not be obvious from the get go which is better.

### Preview of the next post

The next post will describe a scheme in which we could wed together
enums and structs, gaining the advantages of both. I don't plan to
touch virtual dispatch yet, but intead just keep focusing on concrete
types.


[349]: https://github.com/rust-lang/rfcs/issues/349
[last post]: http://smallcultfollowing.com/babysteps/blog/2015/05/05/where-rusts-enum-shines/
[vg]: http://smallcultfollowing.com/babysteps/blog/2012/08/24/datasort-refinements/
[fp]: http://smallcultfollowing.com/babysteps/blog/2011/12/02/why-case-classes-are-better-than-variant-types/
