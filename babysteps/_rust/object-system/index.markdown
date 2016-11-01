---
layout: page
title: "object system"
date: 2011-12-06 10:54
comments: true
sharing: true
footer: true
---

This is an attempt to unify and combine the various proposals for a
new Rust object system.  It draws on several prior proposals by
pcwalton, marijn, and myself.

# Warning: incomplete and probably ill-advised!

## Key ingredients

The basic approach follows the strong OOP factorization pioneered by
pcwalton, introducing four concepts:

- Interfaces
- Classes
- Implementations
- Traits

## Interfaces

## Classes

Classes are a purely static grouping of a record with a set of
associated methods that operate over its fields.  Classes are defined
using a familiar syntax:

    class ClassName<X...> : (interfaces and traits) {
        let x: Type; // Field declaration.
        priv let y: Type; // Private field declaration.
        
        new() { } // Constructor declaration.
        
        fn foo() { } // Method declaration.
    }
    
### Constructor

The constructor must assign all fields of the object before accessing
the `self` pointer or invoking any methods (check using type state).

Object instances are created using the `new` keyword.  The type of
`new C` is `C`:

   let c0 = new C(...);   // by value
   let c1 = @new C(...);  // in shared heap
   let c2 = ~new C(...);  // in exchange heap

#### Literal syntax

If a class has no constructors defined, it can be instantiated using
literal syntax:

    { f1: ..., f2: ... }
    
If the class name cannot be uniquely identified by the names of the fields, 
it can be explicitly written:

    new ClassName { f1: ..., f2: ... }

### Private state

Fields and methods may be prefixed with the `priv` keyword, which
designates them as private. Private members may only be accessed from
within the class body itself.

## Implementations

An implementation defines methods for a non-class type.  Implementations
are written:

    impl<X...> Name for Type : (interfaces and traits) {
        fn 
    }
    
The name is optional if an interface or trait is provided following
the `:`.  In that case, the name of the interface/trait will be used.
For example, the following would declare an implementaton of the `hash`
interface for the type `T`:

    impl for T : hash {
    }
    
Because the name of the implementation is omitted, it would default to
`hash`.
