---
layout: post
title: "Intermingled parameter lists"
date: 2013-10-29 15:04
comments: true
categories: [Rust]
---
I've been hard at work finishing up work on Rust's
["new" syntax for lifetimes][4846] -- I put "new" in quotes because
the syntax has been in use for some time, but in rustc itself the
change was only half-baked. In effect, the new syntax was a kind of
"bridge" to code that was designed for the older type system. This
resulted in some artificial limitations: for example, types could only
have a single lifetime parameter, and it had to be named `'self`.
Under my pull request, these limitations are lifted.  However, in the
process of implementing things, I realized one minor problem with the
new syntax that must be rectified. In this post I describe the problem
and my proposed solution.

For the impatient, the changes I propose are summarized here. These
are pretty nitty-gritty changes that won't affect most programs, but
are needed to make the current type system more coherent. The changes
are needed to fix [issue #5121][5121]. The full
motivation for these changes is somewhat subtle and is described below
the fold.

- Permit lifetime and type parameters to be intermingled within a
  parameter list, rather than requiring all lifetime parameters to appear
  up front.
- Do not bring all parameters into scope as a unit but rather one by one.
- Require that, when explicit parameters are supplied, values for *all*
  parameters must be supplied, unlike today where values for lifetime parameters
  can always be omitted.
- Introduce `_` as a notation for an unspecified lifetime or type.
  It can be used in any type that appears in a fn body or signature.
- For fn items, trailing lifetime parameters are considered "late
  bound", meaning that their value are substituted when the fn is
  called rather than when it is referenced. This is contrast to type
  parameters, which are "early bound". More on this point below.
- Make both type and lifetime parameters required on references to types
  in all contexts.
  
<!-- more -->  

### Early- vs late-bound lifetimes

In general lifetime parameters, work a lot like type parameters. For
example, consider the struct `VecIndex`, which has both a lifetime
parameter `'l` and a type parameter `T`:

    struct VecIndex<'l, T> {
        vec: &'l [T],
        index: uint
    }

Now if I were to write a type like `VecIndex<'foo, uint>`, that is
basically equivalent to search-and-replacing `'l` with `'foo` and
`T` with `uint`, so wind up with a type like:

    struct VecIndex {
        vec: &'foo [uint],
        index: uint
    }

However, when it comes to functions, lifetime parameters are more
flexible than type parameters. In particular, we can often wait to
specify the value for a lifetime parameter until the function is
called. To see what I mean, consider the function `get_index`, which
is again parameterized by both a lifetime `'l` and a type `T`:

    fn get_index<'l, T>(v: &'l [T], index: uint) -> &'l T {
        &v[index]
    }

Now suppose I were to call `get_index` twice, supplying
two different types of vectors as inputs:

    let vec1 = [1, 2, 3];
    let addr1 = get_index(vec1, 1);
    
    let vec2 = ['1', '2', '3'];
    let addr2 = get_index(vec2, 1);
    
Although they look like the are calling the same function, these two
calls to `get_index` are in fact executing completely different code
at runtime. This is because Rust uses a *monomorphization* scheme for
handling type parameters (similar to C++), which means that we must
create a duplicate copy of `get_index` for each set of types. To put
it another way, behind the scenes every reference to `get_index` must
specifiy a concrete set of type parameters (though the compiler
normally infers their values for us). We could therefore rewrite the
code example above in a more explicit way (for now, just ignore the
lifetime parameter, I will get to it):

    let vec1 = [1, 2, 3];
    let addr1 = get_index::<int>(vec1, 1);
    
    let vec2 = ['1', '2', '3'];
    let addr2 = get_index::<char>(vec2, 1);

Monomorphization is generally invisible but becomes visible if you
try to obtain a function pointer to `get_index`:

    let func = get_index::<?>; // must choose int or char here!
    
    let vec1 = [1, 2, 3];
    let addr1 = func(vec1, 1);
    
    let vec2 = ['1', '2', '3'];
    let addr2 = func(vec2, 1);
    
You can see that when we store `get_index` into a variable, we must
specify the types it will operate over. So we can pass `func` a slice
of ints or chars, but not both.

To put it another way, when you specify a closure type like `|uint| ->
float`, we don't permit that type to be *generic* with respect to
types. That is, you can't have a a type like `<T> fn(T) -> uint`, which
would be a function that converts any type to a `uint` (I am using the
[new syntax][cs] that was recently proposed). Even when you
define a generic function (like `fn foo<T>(t: T) -> uint`), the *type*
of a reference to that function at any point in time will have some
concrete type substituted for `T`. I will call type parameters
*early bound*, meaning that we substitute concrete values for them as
early as possible.

All this time I've been ignoring the lifetime parameter. Because
lifetimes are erased at runtime, meaning that they do not influence
the code we generate, they don't have to share the same limits.  We do
in fact permit closures that bind lifetime names, meaning I can write
a type like `<'a> fn(&'a [uint], uint) -> &'a T` (that is, a closure
that takes a slice with lifetime `'a` and returns a pointer with
lifetime `'a` -- but the lifetime `'a` can be different *each time the
closure is called*). I will call this a *late-bound lifetime
parameter*, because we don't need to substitute a specific lifetime
right away, but rather we can wait until the function is called.

Let's revisit our `get_index` in light of this distinction:

    fn get_index<'l, T>(v: &'l [T], index: uint) -> &'l T {
        &v[index]
    }

As we said, the type parameter `T` (like all type parameters) must be
early bound. We can't actually generate code for `v[index]`, for
example, without knowing `T` -- we wouldn't know how big `T` is and
thus how many bytes to skip over. However, for the lifetime `'l` there
is no problem. When we generate code for `get_index`, it will not
matter what lifetime `'l` represents, we just generate code that takes
a slice and indexes into it -- the type system guarantees us that this
dereference will not crash, but doesn't affect the code we generate to
actually *do* the dereference. Therefore, `'l` can be late bound.  We
could say, for example, that the type of an expression like
`get_index::<int>` is `<'l> fn(&'l [uint]) -> &'l uint`.

Not all lifetime parameters can be late bound. Lifetime parameters on
types, for example, are early bound. To see what I mean, consider a
struct like `Foo`:

    struct Foo<'a> { x: &'a int }
    
You cannot refer to a type `Foo` without specifying what `'a` is
(well, you can *write* `Foo` in some cases, but the compiler will
insert defaults or make use of inference to expend it to `Foo<'z>` for
some lifetime `'z`).

I used to think that this then was the divide: lifetime parameters on
types are early bound, lifetime parameter on fns are late bound. But
I've realized that this is not necessarily true. Consider a function
like the following:

    trait Allocator<'arena> {
        fn new_box(&mut self) -> &'arena mut Box;
    }

    fn with_alloc<'arena,A:Allocator<'arena>>(
        alloc: &mut A,
        ...)
    {
        ...
    }
    
What is important here is that the type parameter `A` has a bound that
*references the lifetime parameter* `'arena`. This means that we
cannot know `A` unless we know `'arena`. Since `A` is a type
parameter, and thus early bound, this implies that `'arena` must also
be early bound.

So we can see that lifetime parameters on fns may be early or late
bound. Unfortunately, our current syntax offers no way to distinguish
between early- and late-bound lifetimes. What's worse, we currently
require all lifetimes to go first in the list of parameters
(ironically, this is because I wanted them to be able to appear within
trait bounds, as shown in that last example, but I didn't consider the
full implications of that).

### My proposed solution

I think we should allow type and lifetime parameters to be freely
intermixed. Moreover, we should require that when you specify values
for generic parameters, you must always specify both lifetime and type
parameters, in the proper position. To make this less onerous, we'll
add a new specifier `_` that can be used to omit a lifetime/type
parameter and have the compiler fill in a default. `_` can be used to
supply a value for either a type or region parameter. Parameter names
are in scope for the bounds of all parameters that appear later in the
list.

One exception to the previous rules: on fn items, any trailing
lifetimes will be considered late bound. Late-bound lifetimes may be
but need not be specified on reference to a fn. If the value for a
late-bound lifetime is omitted, then the lifetime becomes bound in the
resulting fn type. This convention reserves room for adding late-bound
lifetimes to types, once some sort of semantics is defined for
that. ;)

That is pretty dense. Let me give some examples. First, our `get_index`
function that we saw before:

    fn get_index<'l, T>(v: &'l [T], index: uint) -> &'l T {
        &v[index]
    }

The way this function is written, `'l` would be considered *early
bound* because it comes *before* the type parameter `T`. That means
that the following code which I wrote before is now illegal:

    let func = get_index::<int>;

This code is illegal because there are two early-bound parameters
(`'l`, `T`) and the code only supplies a value for one of them. The
user could supply a named lifetime, like:

    fn foo<'a>(v: &'a [int]) -> &'a int{
        let func = get_index::<'a, int>;
        func(v, 0)
    }
    
Or, if they would prefer to allow the compiler to use inference,
they could just write `_`:

    fn foo<'a>(v: &'a [int]) -> &'a int{
        let func = get_index::<_, int>;
        func(v, 0)
    }

In fact, they could write `_` for both parameters:

    fn foo<'a>(v: &'a [int]) -> &'a int{
        let func = get_index::<_, _>;
        func(v, 0)
    }
    
All of these examples are equivalent.

What the user could *not* do, given this definition of `get_index`, is to
apply `func` to slices of two distinct lifetimes. For example:

    fn bar<'a, 'b>(v: &'a [int], w: &'b [int]) {
        let func = get_index::<_, _>;
        let x: 'a int = func(v, 0);    // Infers lifetime 'l to be 'a
        let y: 'b int = func(w, 0);    // <-- Error: 'l is 'a, not 'b
    }

To achieve this, the parameter `'l` must be late bound, which means that
it must be moved to the end of the list:

    fn get_index_late<T, 'l>(v: &'l [T], index: uint) -> &'l T {
        &v[index]
    }

Now, because `'l` is late bound, one can leave it out of the list of
parameters entirely, and simply refer to `get_index_late::<int>`:

    fn bar<'a, 'b>(v: &'a [int], w: &'b [int]) {
        let func = get_index_late::<int>;
        let x: 'a int = func(v, 0);    // OK
        let y: 'b int = func(w, 0);    // OK
    }

The type of `func` here is `<'l> fn(&'l [int]) -> &'l int` -- that is,
`'l` remains bound, and hence can be given different values when the
function is called multiple times.

If we go to our example which required an early-bound lifetime
parameter, we see that everything works out fine, because the lifetime
parameter `'arena` appears first in the list and hence is early bound:

    trait Allocator<'arena> {
        fn new_box(&mut self) -> &'arena mut Box;
    }

    fn with_alloc<'arena,A:Allocator<'arena>>(
        alloc: &mut A,
        ...)
    {
        ...
    }

The scoping rules would prevent a function definition like the
following, which attempts to reference a late-bound lifetime parameter
inside of a type bound:

    fn with_alloc_bad<A:Allocator<'arena>, 'arena>(
        // Note that 'arena appears second ^~~~~~
        alloc: &mut A,
        ...)
    {
        ...
    }
    
Note that the `_` notation can be used in other type contexts as well
as a convenient shorthand. So I could write a statement like:

    let v: ~[_] = vec.iter().map(...).collect();

This expression specifies that the type of `v` is some kind of owned
vector, but leaves the contents unspecified (presumably they can be
inferred). Today one can either omit a type in its entirety or specify
it down the smallest detail. This feature has been independently
requested as [issue #9508][9508].

`_` for types would be legal only within a function body. `_` for
lifetimes is legal either within a function body or in a function
signature: in the signature, it would mean "a fresh lifetime
parameter". (As an extension, we could potentially have `_` have the
same meaning for types)

With this change, I propose that we make lifetime parameters on types
mandatory. Today they are mandatory in type signatures but not in fn
signatures or fn bodies. If omitted in those contexts, they default to
a fresh lifetime. Using this proposal, we could simply write `_`
instead. So code like:

    struct MyMap<'a> { ... }
    fn foo(x: &MyMap) { ... }
    
would change to:

    struct MyMap<'a> { ... }
    fn foo(x: &MyMap<_>) { ... }
    
which is arguably more consistent and clear.

[4846]: https://github.com/mozilla/rust/issues/4846
[cs]: http://smallcultfollowing.com/babysteps/blog/2013/10/10/fn-types-in-rust/
[9508]: https://github.com/mozilla/rust/issues/9508
[5121]: https://github.com/mozilla/rust/issues/5121
