I want to take some time to write out a description of how I think
traits in Rust ought to eventually work (but don't today). I'll
also describe how I think these changes ought to be phased in.

### Trait definitions and associated items

A trait definition has the form:

    trait TraitName<A...Z> { ... }
    
The trait has the explicit type parameters `A...Z` and an implicit
type parameter called `Self`. Inside the trait can be various members,
which may be functions, constants, or types. These are called
"associated items" of the trait.

#### Associated functions

Associated functions may begin with a "self-declaration" of the form
`self`, `&self`, `&mut self`, `@self`, `@mut self`, or `~self`. In
terms of the semantics, a self declaration is just syntactic sugar for
a parameter declaration like `self: Self`, `self: &Self`, and so
on. However, as self is a keyword, self declarations are the only way
to actually have a parameter named self. Associated functions with
a self-type are also called methods.

Associated functions may supply a default implementation. This code
will be compiled with the `self` variable will be bound to an
(appropriately transformed) version of `Self`, as described in the
previous paragraph.

#### Associated types

Associated types (`type T`) may also include trait bounds (`type T:
Iterable`) and default values.

#### Associated constants

Associated constants (`static [mut] x: T`) may include default values.
The type `T` of an associated constant may refer to type parameters
defined on the trait itself.

*Comparison to Haskell:* A trait with no type parameters is basically
a Haskell type class. A generic trait is a multi-parameter type class.
Associated items are roughly equivalent to what Haskell offers.

### Trait implementations and coherence

A trait can be implemented as follows:

    impl<...> Trait<A...Y> for Z { ... }
    
You are only permitted to implement a trait *once* for any given set
of types `A..Z`. In order to be able to enforce this rule
across crates, we impose the *coherence requirement* that either

1. The trait `Trait` is defined in the current crate; or,
2. At least one of the types `A..Z` is defined in the current crate.

The implementation must contain an item for each of the items defined
in the trait (and no additional items), unless that item has a default
value in the trait. The items must be *compatible* with their
definition in the trait as follows:

1. Associated constants must have the same type.
2. Associated types must meet any trait bounds specified in the
   trait declaration.
3. Associated fuctions have the same number of generic lifetime/type
   parameters as appear in the trait. The bounds that appear on the
   trait must imply the bounds that appear in the impl. The types of
   the parameters and return values must also be implied by the trait
   types.
   
*Comparison to Haskell:* An `impl` is a an instance declaration in
Haskell. The coherence rule is the same as Haskell's orphan rule.

### Infinite recursion

In some cases, trait-impl matching may lead to infinite recursion.
The implementation will detect this and report an error after a
suitable maximum depth is reached. The maximum depth should be
configurable at the crate level with an annotation.

### Thoughts on implementation

