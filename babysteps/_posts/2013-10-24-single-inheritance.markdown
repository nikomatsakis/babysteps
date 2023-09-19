---
layout: post
title: "Single inheritance"
date: 2013-10-24 14:30
comments: true
categories: [Rust]
---
The following is a draft proposal to support a form of single
inheritance, similar to that found in object-oriented languages. The
goal is to enable servo to efficiently support structures like the
DOM. The proposal is not completely rounded out, but I wanted to put
it up in its current form so as to gather any comments.

In a nutshell, the proposal is to:

1. Enable structs to extend other structs, meaning that the substruct
   inherits all fields of the superstruct, and also enabling a
   subtyping relationship between borrowed pointers.

2. Enable traits to extend structs. This allows direct access to
   fields of that struct, but means that the trait can only be
   implemented by structs that extend the base struct. In short, a
   trait that extends a struct is less general but potentially more
   efficient (this is a similar tradeoff to using a abstract class vs
   an interface in Java).
   
<!-- more -->

### Structs extending structs

Syntactically, struct inheritance would be done with a single colon:

```
struct NodeFields {
    id: uint,
    ...
}

struct ElementFields : NodeFields {
    ...
}
```

A struct type can extend at most one other struct. A struct which
extends another is called a *substruct* of the extended struct. Hence,
`ElementFields` is a substruct of `NodeFields`. Note that `ElementFields` is *not* a
subtype of `NodeFields` (subtyping will be discussed in detail later).
Every struct is considered a substruct of itself (hence `NodeFields` is a
substruct of `NodeFields`).

### Traits extending structs

When declaring a trait, it is already legal to specify a set of
supertraits. It would now be possible to specify at most one
superstruct. The superstruct must appear first in the list.

Example:

    trait Node : NodeFields {
        ...
    }
    
    trait Element : ElementFields, Node {
        ...
    }

If a trait `T` extends a struct `S`, then any subtraits of `T` must
themselves extend substructs of `S`. In other words, in the previous
example, it would be illegal for `Element` to extend `Node` without
also extending `NodeFields` or some substruct of `NodeFields` (in this case,
`Element` extends `ElementFields`). This rule extends naturally to cases
where a trait extends many other traits: the trait must then extend a
struct which is a substruct of the superstructs of all its
supertraits.

#### Implementing a trait with a superstruct

If a trait extends a struct, then it can only be implemented by
substructs of that struct.

Example:

    impl Node for NodeFields {
      /* ok -- `NodeFields` is a substruct of `NodeFields` */
    }
    
    impl Node for ElementFields {
      /* ok -- `ElementFields` is a substruct of `NodeFields` */
    }
    
    impl Node for &NodeFields {
      /* not ok, `&NodeFields` is not a struct at all */
    }
    
    struct Foo { ... }
    impl Node for Foo {
      /* not ok, `Foo` does not extend `NodeFields` */
    }

#### Access to fields

When a trait `T` extends a struct, it is legal to access the fields of
that struct any value known to implement trait `T`. That includes type
parameters bounded by `T` and objects of type `T`.

Example:

    fn get_id<T:Node>(x: &T) -> uint {
        x.id
    }
    
    fn get_id(x: &Node) -> uint {
        x.id
    }

### Subtyping

Borrowed pointers to substructs have a subtyping relationship. More
concretely, `&S <: &T` and `&mut S <: &mut T` if S is a substruct of
T.

Note that the following relationships do not hold:

- `S <: T` -- the two struct types have differing sizes and are generally not
  equivalent. Consider the ramifications on types like `~[S]` and `~[T]` etc.
- `~S <: ~T` -- when freed, any destructors associated with `S` and
  `T` would run. If we permitted subtyping, we'd need virtual
  destructors for all owned struct pointers.
  
### Inherent methods

Inherent methods defined on a struct type `S` are available for use by
substructs of `S`, objects for some subtrait of `S`, and type
parameters implementing a subtrait of `S`.

### Interaction with coherence

I think that there is no special interaction with coherence required.
We already have the means to reason about coherence in the face of
possible subtyping. But I reserve the right to add something more here
if I think of it. =)

### Coercions

If a trait `T` extends a struct `S`, it should be possible to coerce
an object `&T` to an `&S`. Same is true for type parameter `&A` where
`A:T`. Not sure whether this should be an automatic coercion or one
that requires some keyword -- automatic should be possible.

### Expected patterns

Struct inheritance can be combined with traits and object types to
achieve a combination of direct field access, virtual method calls,
and statically dispatched calls. For example, the DOM in Servo would
likely be modeled as follows (the code sample assumes DST).

    ////////////////////////////////////////////////////////////
    // Structs model the data:
    
    struct NodeFields {
        // Tree is a linked list:
        parent: Option<JSGC<Node>>,
        child: Option<JSGC<Node>>,
        sibling: Option<JSGC<Node>>,
    }
    
    struct ElementFields : NodeFields {
        // Something specific to elements
    }
    
    struct TextFields : NodeFields {
        // Something specific to text
    }
    
    ////////////////////////////////////////////////////////////
    // Traits model virtual dispatch:
    
    trait Node : NodeFields {
        fn layout(&self); // virtual method
    }
    
    trait Element : ElementFields + Node {
    }
    
    trait Text : TextFields + Node {
    }
    
    ////////////////////////////////////////////////////////////
    // Impls of traits like `Node` etc provide
    // the implementation of virtual methods for a
    // specific leaf class.
    
    impl Node for ElementFields {
        fn layout(&self) {
            ...
        }
    }
    
    ////////////////////////////////////////////////////////////
    // Impls on trait objects model static dispatch.
    // You could also do an impl on the struct (`NodeFields`,
    // for example) but then you would not have access to
    // virtual methods like `layout()`.
    
    impl Node {
        fn layout_children(&self) {
            // Here self is an `&Node` object
            let mut opt_ptr = self.child; // Note: direct access to field
            loop {
                match opt_ptr {
                    None => { return; }
                    Some(ptr) => {
                        ptr.layout(); // virtual call
                        opt_ptr = ptr.sibling; // direct field reference
                    }
                }
            }
        }
    }

