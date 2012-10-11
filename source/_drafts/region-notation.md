I am not satisfied with the syntax we have for lifetimes.  It is
lightweight but, I think, not especially intuitive.  I am thinking of
some changes.  I'd prefer to anticipate future needs as much as
possible so that we change the syntax *once* and not again.

<!-- more -->

### Referencing types that can contain borrowed pointers

One of the key advances that borrowed pointers bring over the older
mode system is that a borrowed pointer can be embedded within another
type.  For example, all of the following types are valid:
 
    struct Foo { f: &Bar }
    enum Foo2 { Foo(&Bar) }
    type Foo3 = &Bar;

Each of these type definitions declares a type (or, in the final case,
a type alias, but the distinction is not important here) which
contains a borrowed pointer to a value of type `Bar`. Now, imagine
that we have a variable of type `Foo`, such as the parameter `foo` to
this function:

    fn example_fn(foo: Foo) { ... }
    
To guarantee safety, the compiler must have some idea what the
lifetime of `foo.f` is.  Remember, `foo.f` has the type `&Bar`, which
is itself short for `&a/Bar` where `a` is the lifetime.

Internally, when you write a type like `Foo` which contains borrowed
pointers, it gets expanded to `Foo/&b` where `b` is a lifetime.  This
is basically the same as generic types: the lifetime of each borrowed
pointer within `Foo` will be replaced with `b`.

What I would like to do is replace this notation of `Type/Lifetime`
with one that is more akin to generic types.  It's the same notation I
use to explain how it works when people ask.  So instead of writing
`Foo/&b` you would write `Foo<&b>`.  If the type `Foo` also has type
parameters, you'd write `Foo<&b, T>` instead of `Foo/&b<T>`.  Region
parameters always come first (in some ways this is the opposite of
what I expected; more on this later).

I've already discussed this particular change with the team and I
think we're all in agreement.

### Two possibilities

I see two possibilities for how we should approach the matter of
lifetime parameter declarations.  One is to try and never require
named lifetimes to be declared, as we do today.  The other is to
always require *named* lifetimes to be declared, but to permit the
anonymous notation `&T` as a default.

I don't know how best to explain these two possibilities except by
example.  Here is some code in the first, declaration-less style:

    // Here: TypeContext is parameterized by &self:
    struct TypeContext {
        type_data: &TypeData      // &T in a type is short for &self/T
    }
    
    // Multiple lifetime parameters on a type must be declared
    // because we need an order for them
    struct FnContext<&self, &tcx> {
        tcx: &tcx/TypeContext,
        fn_data: &FnData
    }
    
    // Short for TyContext<&r>, where &r is a fresh lifetime
    fn tcx_by_value(tcx: TyContext) { ... }

    // Short for &r/TyContext<&r>, where &r is a fresh lifetime
    fn tcx_by_ref(tcx: &TyContext) { ... }

    // Takes two type contexts where &t is the intersection of their lifetimes
    fn select(tcx1: &t/TyContext, tcx2: &t/TyContext) -> &t/TyContext { ... }

    // Short for &r/FnContext<&r, &s>, where &r and &s are fresh lifetimes
    fn fcx(fcx: &FnContext) { ... }
    
    // Short for &f/FnContext<&f, &r>, where &r is a fresh lifetime
    fn both(fcx: &f/FnContext<&f, &>) { ... }

    // Fully explicit, used to take a tcx and fcx with same lifetimes
    fn both(tcx: &t/TyContext, fcx: &f/FnContext<&f, &t>) { ... }

That same example in the second style, where named lifetimes must be declared:

    // Here: TypeContext is parameterized by &self:
    struct TypeContext {
        type_data: &TypeData      // &T in a type is short for &self/T
    }
    
    // Multiple lifetime parameters on a type must be declared
    // because we need an order for them
    struct FnContext<&self, &tcx> {
        tcx: &tcx/TypeContext,
        fn_data: &FnData
    }
    
    // Short for TyContext<&r>, where &r is a fresh lifetime
    fn tcx_by_value(tcx: TyContext) { ... }

    // Short for &r/TyContext<&r>, where &r is a fresh lifetime
    fn tcx_by_ref(tcx: &TyContext) { ... }

    // Takes two type contexts where &t is the intersection of their lifetimes
    fn select<&t>(tcx1: &t/TyContext, tcx2: &t/TyContext) -> &t/TyContext { ... }

    // Short for &r/FnContext<&r, &s>, where &r and &s are fresh lifetimes
    fn fcx(fcx: &FnContext) { ... }

    // Short for &f/FnContext<&f, &r>, where &r is a fresh lifetime
    fn both<&f>(fcx: &f/FnContext<&f, &>) { ... }

    // Fully explicit, used to take a tcx and fcx with same lifetimes
    fn both<&t, &f>(tcx: &t/TyContext, fcx: &f/FnContext<&f, &t>) { ... }

I think I prefer the more explicit style.  Named lifetimes are
reasonably rare.  Having them be declared makes the code clearer,
though heavier.  It is more expressive in some scenarios.  It also
will simplify the (rather terrifying) code that deals with the
implicit declarations right now.

### Combining lifetime and type parameters

I was a bit vague about the precise rules for lifetime parameters.  My
feeling is that you should be able to omit all lifetime parameters
altogether, in which case they all default to `&`.  If you supply any
lifetime parameters, however, you must provide all of them, though you
can write `&`.  A value of `&` expands to a fresh lifetime in a
function binding scope or `&self` in a type scope.  If you do provide
lifetime parameters, they should come first.  The reason for this is
that (in the future) they may appear in the bounds of later type
parameters (currently type parameters do not have lifetime bounds;
this should change).
