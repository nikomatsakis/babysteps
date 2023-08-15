---
categories:
- Rust
- PL
comments: true
date: "2012-02-15T00:00:00Z"
slug: regions-lite-dot-dot-dot-ish
title: Regions-lite...ish
---

I was talking to brson today about the possibility of moving Rust to a
regions system.  He pointed out that the complexity costs may be high.
I was trying to make a slimmer version where explicit region names
were never required.  This is what I came up with.  The truth is, it's
not that different from the original: adding back region names wouldn't
change much.  But I'm posting it anyway because it includes a description
of how to handle regions in types and I think it's the most complete and
correct proposal at the moment.

## The summary

You would have four kinds of Rust pointers:

    @MT --- pointers to task-local, boxed data
    ~MT --- pointers to unique data
    &MT --- safe references
    *MT --- unsafe, C-like pointers
    
Here the `M` refers to a mutability qualifier (default, `mut`, or
`const`) and `T` refers to a type.

`&MT` types, called references, are the new addition.  A reference is
a pointer which always points at memory whose validity is guaranteed
by some outer stack frame.  The idea is that a caller can give a
callee a reference to some memory that the callee may use but which
may not escape the callee.  This memory may be on the caller's stack
frame or it may be a reference into the task or exchange heaps which
the caller is going to keep valid.  This guarantee is upheld by the
type system.

Reference types may appear anywhere.  However, if they are used within
another aggregate type such as a record, enum, or class, they "infect"
their container so that it too is considered to be a reference.  This
is done by introducing a new kind into the type system, `ref`
(actually, this is sort of a negative kind: more formally, there is a
kind `heap` which contains all types but for those that may
transitively include a reference).  This kind may or may not be user
visible: see the section on generics for a discussion of the options.

## Coercion between pointer types

The type `&MT` is not a supertype of `@MT` and `~MT`, but it is
coercable.  In the case of `@`, we could probably make it a true
subtype, but at the moment a box pointer includes a header, ref count,
etc and so is not binary compatible with a `&` pointer, which would be
just a pointer to the box body.  If we changed our representation so
that `@` pointers point directly to the box and the header is stored
at a negative offset, then we could allow `@T` to be a subtype of
`&T`.

The type `~MT`, however, can never be a subtype.  `~` is not a region.
Rather, the data at the other end of the pointer logically belongs to
a region of its own.  So we can allow `~MT` to be coerced to `&MT`,
but the region will be a fresh region, and access to the `~MT` pointer
must be prevented for the scope of that fresh region.  This is called
"borrowing" a unique pointer.  It is only possible for "unique paths",
where a "unique path" is a path of identifiers `a.b.c...z` that is the
only path by which the unique variable can be reached (in practice,
this means that `a` must be a local variable and all of the fields
`b...z` must have unique or interior type).  All of the prefixes of
the unique path must be considered borrowed as well.  I am not going
into great detail on the handling of uniques here: it should be quite
similar to what we have today in practice.

## Tracking validity of references

Although the user never needs to write it explicitly, each instance of
a reference type is internally associated with a region.  There is one
region for every block in the code.  In addition, each function/method
has a special region called `caller`.  For simplicity I do not
consider classes nor impls; it is relatively straightforward to extend
the system to such cases.

Regions are arranged into a tree derived from the structure of the
blocks in the source code.  The region `caller` is a superregion of
all the internal regions to a function.

In the implementation / formal version of the type system, these
regions are represented explicitly.  So a user-written type `&MT`
expands to a type `r&MT` where `r` is the node id of the block or of
the function itself (in the case of the `caller` region).  The region `r`
is derived from the position where `&MT` appears and by inference: 

- if `&MT` appears within a parameter list, `r` is the `caller` region.
- if `&MT` appears on the type of a local variable, inference is used.
- if `&MT` appears in a type declaration, see section below.

In general, the type `a&T` is a subtype of `b&T` if `b` is a subregion
`a`.  The reason is that, because `a` is a superregion of `b`, the
pointer `a&T` is always valid whenever the region `b` is valid.

### References in type declarations

The rules for which region is assigned when the user writes `&MT`
omitted one important case: what happens when this type appears in a
type declaration?  Consider the following example:

    type crate_ctxt = {
        mut_map: &map<...>,
        node_map: &map<...>,
        another_map: &map<...>,
        yet_another_map: &map<...>
    };

In such cases, the region for the internal references will be assigned
when the type is used.  For example:

    fn trans_foo(ccx: &crate_ctxt) {...}

Here, the type of `ccx` will be expanded to:

    caller&{mut_map: caller&map<...>, node_map: caller&map<...>, ... }

In effect, types which contain references (transitively) are
implicitly parameterized by a region parameter.  There is only one
such parameter.  When the type is instantiated in a specific context,
the value for that parameter is provided based on the context.

## Taking the address of variables and so forth

The unary operator `&M` can be be used with both lvalues and rvalues.
When used with an lvalue, it takes the address of the lvalue.  The
mutability qualifier provided must agree with the mutability of the
lvalue.  When used with an rvalue, it creates temporary space on the
stack and copies the rvalue into it.

Here is an example of taking the address of lvalues:

    fn foo() { // region for this block is "r"
        let x = 3;
        let mut y = 4;
        let px1 = &x;       // OK: yields type r&int
        let px2 = &const x; // OK: yields type r&const int
        let px2 = &mut x;   // Error: x is immutable
        let py1 = &y;       // Error: y is mutable.
        let py1 = &const y; // OK: yields type r&const int
        let py1 = &mut y;   // OK: yields type r&mut int
    }

Here is an example of taking the address of rvalues:

    fn foo() { // region for this block is "r"
        let p1 = &{x: 3, y: 4}; // OK: yields type r&{x:int,y:int}
        let p2 = &mut {x: 3, y: 4}; // OK: yields type r&mut {x:int,y:int}
    }

## Limitations on references

In order to guarantee that reference types do not escape the callee,
the type system imposes some limitations:

- Reference types may not be returned.  
- Reference types may not be closed over (copied/moved into a closure
  or interface instance).
- Generic type variables cannot be bound to reference types unless
  the generic type variable is of the `ref` kind.  

I will cover each restriction in turn.  First, though, I want to more
precisely define what the type checker considers to be a reference
type.  The definition is inductive:

- a reference `&MT`;
- a type whose definition may contain a reference (e.g., `@&T` or
  `{x: &T}`, or a class with a field of reference type);
- a generic variable with bound `ref`.

### Reference types may not be returned

The danger here is that the callee may pass back a reference to the
caller that is no longer valid.  This is relatively straightforward to
prevent: do not allow the return type of a function to be a reference
type.

### Reference types may not be closed over

It is not allowed to copy a reference type into a boxed/unique closure
nor is it allowed to cast a reference type to a boxed or unique iface.
The reason is that these are the points where the type system loses
the ability to track the constituent types and so we cannot
distinguish a `fn@()` that closes over a reference type from other
`fn@()` types.

### Generic types

There is of course a concern that the limitations on reference types
might be circumvented through the use of generics.  This is prevented
through the use of a type kind `ref`.  A generic type variable may not
be bound to a reference type unless it includes the bound `ref`.
Moreover, any generic type variables bound by `ref` are considered
reference types and therefore must obey the above restrictions.

## A note on variance

In general, ptr types like `&MT` or `@MT` are covariant in T if `M` is
not `mut`.  This is different from references today which are always
covariant in T; the current behavior is what leads to the type hole
pointed out in the mailing list.
