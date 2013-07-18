I want to take some time to write out a description of how I think
traits in Rust ought to eventually work (but don't today). I'll also
describe how I think these changes ought to be phased in and
implemented.

### Trait definitions and associated items

A trait definition has the form:

    trait TraitName<A...Z> : PrerequisiteTrait1<...>, ... { ... }
    
The trait has the explicit type parameters `A...Z` and an implicit
type parameter called `Self`. Inside the trait can be various members,
which may be functions, constants, or types. These are called
"associated items" of the trait.

Traits can also have any number of prerequisites (aka, "supertraits").
The trait cannot be implemented without also implementing the
prerequisites (in the case of built-in traits, like `Send`, the trait
cannot be implemented for a `Self` type that is not an instance of
that trait). The compiler will check this at each `impl` site.

#### Associated functions and methods

Associated functions that begin with a "self-declaration" of the form
`self`, `&self`, `&mut self`, `@self`, `@mut self`, or `~self` are
also called *methods*. In terms of the expected arguments of the
function, a self declaration is equivalent to an argument like `self:
Self`, `self: &Self`, `self: &mut Self` and so on. Methods can be
invoked using "method syntax" `a.m()`. Example: `receiver.to_str()`,
where `receiver` implements the `ToStr` trait.

All functions, whether they contain a self-declaration or not, can
also be invoked by naming the function via the trait. Example:
`ToStr::to_str(receiver)`. In such invocations, the `Self` type and
any type parameters of the trait which are not specified are inferred.
There is also an explicit syntax (see section *Referencing associated
items* below) for cases where inference is inadequate.

Associated functions/methods may supply a default implementation. This
code will be type-checked with the `Self` type bound to a fresh free
type that is assumed to implement all of the supertraits of the
current trait. The default implementation will be used for impls that
do not provide their own definition.

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

#### Referencing associated items

Associated items may be referenced in two ways. One is "the Haskell way",
in which the item is cited via a path leading through the trait.
For example, `ParseInt::parse_int()`. In this case, the path may or may
not supply the trait type parameters (if any) but the path can never
supply the `Self` type. Any unsupplied type parameters plus the `Self`
type must then be inferred.

*Note:* In the current implementation, the type parameters of the
trait and self type are preprended onto the list of type parameters
for the associated fn. This should not happen.

For referencing associated types or constants, where the `Self` type
cannot be inferred, we supply an explicit reference syntax. This is
detailed by Felix [in his epic blog post][pnkfelix].

[pnkfelix]: http://blog.pnkfx.org/blog/2013/04/22/designing-syntax-for-associated-items-in-rust/

### Trait implementations

A trait can be implemented as follows:

    impl<X0:B0...Xn:Bn> Trait<T0...Tm-1> for Tm { ... }
    
You are only permitted to implement a trait *once* for any given set
of types `T0..Tm`. An implementation for a trait is only legal if
implementations can also be found for each of the trait's
prerequisites.

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

#### Coherence

We wish to enforce a *coherence requirement* that guarantees that
given a trait `Trait` and associated set of types `A...Z`, there is at
most one matching implementation.

Enforcing coherence is done in two parts. First, we require that
either:

1. the trait `Trait` is defined in the current crate; or,
2. at least one of the types `A..Z` is defined in the current crate.

These conditions guarantee to us that we can find all of the implementations
for a given set of types and a given trait.

Next, we must check for every implementation that there is no other
implementation that could possibly match the same types. This is done
by examining all impls of the same trait pairwise. We wish to
determine if there is any legal substitution of types such that the
two impls wind up implementing the same trait with the same type
parameters.  The procedure for making this determination is as
follows:

1. Let `impl<X0:B0...Xn:Bn> Trait<T0...Tm-1> for Tm` be the first impl
2. Let `impl<Y0:C0...Yn:Cn> Trait<U0...Um-1> for Um` be the second impl
3. Formally, we wish to determine whether there exists a substitution `S1` and
   `S2` such that
   - `S1(T0...Tm) == S2(U0...Um)`
   - `S1(Xi)` meets all bounds `S1(Bi)` declared for the type parameter `Xi`
   - `S2(Yi)` meets all bounds `S2(Ci)` declared for the type parameter `Yi`
4. To do so, 

*Comparison to Haskell:* An `impl` is a an instance declaration in
Haskell. The coherence rule is the same as Haskell's orphan rule.

#### Dot notation

Methods can be invoked using "dot" notation (e.g., `a.m(...)`). In
this case, the compiler will search for a suitable implementation.  A
simplified version of the search works as follows:

- Given the set of traits that are imported;
- Let the *candidate traits* be those traits that offer a method `m`;
- Remove candidate traits where the self type cannot be unified with
  the type of `a` [1];
- 

Note that method selection in this case is typically based solely on
the `Self` parameter, and thus can be ambiguous for multiparameter
type classes.

### Objects

A trait `Trait` may also be used as an object type (`&Trait`, `&mut
Trait`, `@Trait`, and so on). Objects are formed by combining a
pointer of a suitable type with a vtable (e.g., to make an
`&Trait<B..Z>` object, you require an `&T` pointer of some type `T`
that implements `Trait<B..Z>`).

Some methods cannot be invoked through an object:
- Methods with type parameters of their own may not be invoked via an object
  (impossible to codegen);
- Methods with where `Self` appears in the return type or the type
  of an argument other than `self` (impossible to type check);
- Methods with "by value" self (`fn(self, ...)`) (impossible to code-gen).

*Note:* The limitations above follow naturally from viewing objects as
an existential type package.

### Thoughts on implementation

#### The algorithm

#### Infinite recursion

In some cases, trait-impl matching may lead to infinite recursion.
The implementation will detect this and report an error after a
suitable maximum depth is reached. The maximum depth should be
configurable at the crate level with an annotation.

### Unresolved questions

(*1) accounting for subtyping and variance

(*2) can we make guarantee termination?
 
(*3) can an associated function whose first argument is `this: &Self`,
for example, be invoked with dot notation? I don't think there is any
great technical challenge per se here, just a matter of deciding on
the rules.
