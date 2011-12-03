---
layout: page
title: "No implicit copies"
date: 2011-12-03 08:47
comments: true
sharing: true
footer: true
---

This is a proposal for Rust whose purpose is to **eliminate implicit
copies of aggregate types,** while preserving most other aspects of
the language.  Secondary goals include:

- permit references into arrays;
- make destination passing style (DPS) a guaranteed optimization that
  is obvious from language syntax;
- support dynamically sized records.

# Why are these goals important?

Implicit copies are dangerous for many reasons:

- they hurt performance;
- with mutable fields, they silently change the semantics of your program.

It is true that destination passing style (DPS) often optimizes
implicit copies away in practice.  However, *often* is not *always*;
small syntactic changes can lead to surprising effects on performance.
Under this proposal, DPS is effectively built into the language.  If
the optimization would fail, the `copy` keyword is required.

In summary: we do *not* want a language like C++, where it is
difficult if not impossible to know how many copies will occur in a
given piece of code.

# Summary

The following changes are made:

- vectors become fixed-length arrays;
- arrays can be embedded in record types as the final field, leading to a
  dynamically sized record;
- dynamically sized types cannot live on the stack;
- aggregate and unique types must be explicitly copied using the copy keyword
  (shared pointers and scalars can be implicit);
- lvalues of aggregate or unique type can only be assigned using a
  subset of expressions that guarantee the new value is either freshly
  created (in which case it can be directly written into the lvalue's
  memory slot) or explicitly copied or moved;
- functions can designate a `new T` return type, meaning they return a
  `T` which is freshly allocated but where the user decides whether it
  is shared or unique.

# Sources of implicit copies

Implicit copies today occur when one variable is assigned to another
and its type is unique or of aggregate value type.  Prominent unique
types are vectors and strings, of course; this is also a source of
some confusion.  Vectors and strings are immutable types which are
cheap to modify but expensive to share/copy, exactly the opposite of
most persistent/immutable types.

# Terminology: kinds of types

In this document, I often have to refer to different kinds of types.
For my purposes, a *reference type* is either `@T` or `~T`: that is, a
pointer.  A *value type* is any non-reference type. A *scalar type* is
a type like `uint` or `float`. Any value type that is not a scalar
type is an *aggregate value type*.

Types are not to be confused with modes.  In the following function,
for example, the parameter `point` has value type but is passed by
reference:

    fn foo(&point: (uint, uint));
    
Similarly, the parameter to `bar()` has reference type but is passed by value:

    fn bar(+point: @(uint, uint));
    
I assume that parameters of reference and scalar type are passed by
value by default, and all other parameters are passed by (immutable)
reference, as I believe is the case with `rustc` today.
    
# Fixed-length arrays and dynamically sized types

Rather than vectors, the native type is fixed-length arrays
`[1, 2, 3]`.  A fixed length array is represented at runtime by
something like the C++ struct:

    struct array<T> {
        size_t alloc;
        T[] data;
    }
    
Therefore it is not, itself, a C array, but it's very close.  A simple
helper could convert it to one, much as we do today.

## Array creation

Arrays can be created either via literals `[v1, v2, v3]` or via the
use of creation functions.  Literals result in an array of the given
size which is stored on the stack.  There are two creation functions,
each of which creates an array of dynamic length:

    fn create_val<copy T>(size: uint, v: T) -> new [T];
    fn create<T>(size: uint, b: block(uint) -> T) -> new [T];

The function `create_val()` creates an array of a given size where
each value of the array is initially equal to `v`.  The second creates
an array where the initial value of the array at index `i` is given by
`b(i)`.  The `new [T]` return type is explained below.

## Mutability

As with vectors now, arrays can either be immutable (the default),
mutable, or read-only (`const`).  An immutable array cannot be
modified by anyone.  A read-only array is a reference to an array thay
may be mutated by someone else.

Functions returning `new` arrays may be used to create either mutable
or immutable arrays at the callers' choice.  For example:

    let f: @[int] = @arr::create_val(256, 0);
    let g: @[mutable int] = @arr::create_val(256, 0);
    let h: ~[int] = ~arr::create_val(256, 0);
    let i: ~[mutable int] = ~arr::create_val(256, 0);
    
Here the same function (`arr::create_val()`) is used to create arrays of
many different types.  We could also allow unique arrays to become
mutable and immutable if we wished.

## Limitations on array types and other dynamically sized types

Array types `[T]` are unlike other types in that they do not have a
static size.  Such dynamically sized types must generally be
manipulated by reference (e.g., `@[T]` or `~[T]`).  One place that
array types may be used is as the last field in a record.  In that
case, the record type is itself considered dynamically sized and
subject to the same restrictions as array types.  Dynamically sized
types are also legal as the type of a by-ref parameter and as the
return type of a `new` function (see below).

Lvalues of dynamically sized type cannot be assigned after they are
initially created.  In other words, given a record `x` with a field
`f` of type `[int]`, `x.f = ...` is always illegal.

An important restriction is that type variables cannot---by
default---be bound to a dynamically sized type.  To be bound to an
array or other dynamically sized type, a type variable must be
declared with the bound `var` (for "variably sized").  This is so that
the type checker can guarantee that such types are never allocated on
the stack.

# Constructor and allocation expressions

A *constructor expression* is one which inherently constructs a new
value that did not exist before.  The set of constructor expressions
is defined as follows:

    CE = { ... }                 (Record literals)
       | ( ... )                 (Tuples)
       | 0, 0u, 'a', 1.2         (Numeric/character literals)
       | "..."                   (Strings)
       | x(...)                  (Function call with appropriate return type)
       | copy E                  (Copy of some other expression E)
       | move x                  (Move of some local variable x)
       
Any assignment to an lvalue that is potentially of aggregate value
type (i.e., including type variables) must be done from a constructor
expression.  This includes returning from a function whose return
value is of aggregate value type.  Type variables are restricted in
this way because they *may* refer to values of aggregate value type or
to values of unique type; in both cases explicit copies and moves are
required.

An *allocation expression* is one which allocates a new value onto
some heap (`@` or `~`).  They are defined as follows:

    AE = @ AV
       | @ mutable AV            (Type of AV must be copyable)
       | ~ AV
    AV = CE
       | [ ... ]                 (Array literal)
       | x(...)                  (Function call with new return type)
       
`AE` indicates an allocation expression and `AV` an allocation value.
Each allocation expression consists of an allocation value preceded by
some prefix.  The `@` and `~` prefixes allocate enough space in the
appropriate heap for the allocation value.  Allocation values are
either constructor expressions, in which case the value is constructed
in the newly allocated space, array literals, which are allocated into
the heap, or calls to a function with `new` return type (see next section).

It is illegal to use `@ mutable` when the `AV` has a non-copyable
type.  This includes array literals and type variables that are not
designed as copyable.

## Copies and moves

As a sort of escape hatch, the `copy` and `move` keywords can be used
to convert any expression into a constructor expression.  The keyword
`copy expr` evaluates the expression `expr` and then performs a
(mostly) shallow copy according to the following rules:

- Copying a scalar like `int` just returns the scalar.
- Copying an aggregate value type `T` recursively copies the contents of T.
  Each type referenced by `T` must be copyable.
- Copying an `@T` type increments the ref count and returns the same
  pointer.
- Copying a unique type `~T` creates a box on the exchange heap and
  copies the contents of `T` into that box (`T` must be copyable).
- Copying a reference `&T` simply copies the pointer (*regions only*)
- Copying a resource is illegal.
- Copying an array type `[T]` creates a new array and copies each
  member of the array.  The type `T` must be copyable.

The `move x` expression is similar in some ways to a copy followed by
a nullification of the local variable `x`.  The local variable must
not be a reference mode parameter or from an enclosing scope. The
variable cannot be accessed after the move.  The algorithm for `move`
is the same as copy except for unique types and resources:

- Moving a unique type or resource simply copies the value and
  performs no recursive copies.  

# New functions

The return type of a function can be tagged with the keyword `new`.
This indicates that the function will be allocating a (potentially
dynamically sized) value and returning it, but it does not specify the
heap in which that value will be allocated.  That decision is left to
the caller. `new` functions are not compatible non-`new` functions.
That is, the types `fn(S) -> T` and `fn(S) -> new T` are distinct.
Within a `new` function, the return keyword must be followed by an
allocation value `AV`, as defined previously. It is a static error to
invoke a `new` function outside of an allocator expression or the
`ret` expression of another `new` function.

Some examples:

    fn make_arr(a: int, b: int, c: int) -> new [int] {
        ret [a, b, c];
    }

    type T = { a: int, b: int, c: int };
    fn make_rec(a: int, b: int, c: int) -> new T {
        ret { a: a, b: b, c: c };
    }

A `new` value can also be obtained by returning the value of another
function that has a `new` return type, such as `arr::create()` and
`arr::create_val()`:

    fn map<S,T>(a: [S], f: block(S) -> T) -> new [T] {
        ret arr::create(arr::len(a), { |i| block(a[i]) });
    }

## Impedance mismatch between new functions and normal functions

The compiler could automatically convert non-new functions to new
functions if we decide that is a good thing.  Otherwise, the user can
trivially write code like:

    fn foo() -> T { ... }
    fn wrapped_foo() -> new T {
        ret foo();
    }
    
The difference here is that the return value of `wrapped_foo()` must
be placed into the heap by its caller.

Converting a `new` function to a non-new function cannot be done
automatically, because `new` functions offer the ability to select
what heap the result is placed in.  Therefore, it might be useful to
create a few helper functions for converting in the opposite
direction:

    fn shared<S,T:var>(f: fn(S) -> new T) -> (fn(S) -> @T) {
        ret lambda(s: S) { @f(s) }
    }
    
    fn unique<S,T:var>(f: fn(S) -> new T) -> (fn(S) -> ~T) {
        ret lambda(s: S) { ~f(s) }
    }
    
Now, to continue our previous example, `shared(wrapped_foo())` would
yield a function that always returns `@T` and `unique(wrapped_foo())`
would yield a function that always returns `~T`.

## Implementation

Today, all Rust functions are compiled with an implicit first
parameter which is a pointer to the location to store their return
value.  `new` functions would contain an additional implicit
parameter: the heap in which to allocate space for their result.

For example, the `arr::create()` with signature

    fn create<T>(size: uint, v: T) -> new [T]

would compile to a C function roughly like:

    void create(
        rust_arr **implicit_r, rust_heap *implicit_h, tydesc *T,
        size_t size, void *v)
    {
        size_t bytes = size * T->size;
        rust_arr *result = implicit_h->malloc(bytes);
        result->size = size;
        for (size_t i = 0; i < size; i++) {
            memcpy(result->data + i * T->size, v, T->size);
        }
        *implicit_r = result;
    }

## Possible optimization for word-sized returns

For efficiency, we may choose to also distinguish between functions
that always return word-sized values, as C compilers do. Such
functions can use the native ABI to return their result (e.g., use the
EAX register on i386).  However, to avoid a proliferation of
user-visible ABIs, we would hide this distinction from users. This
means that such functions would also have a generic variant that takes
a return value parameter.

> Example:
> 
> The following Rust function `foo()`:
> 
>     fn foo() -> int { ret 22; }
> 
> would compile to the following C functions:
>
>     int foo_direct() { return 22; }
>     int foo_by_val(int *r) { *r = 22; }
>
> Direct calls to `foo()` would use `foo_direct()`.  Loading `foo()` 
> as a value would use `foo_by_val()`. Note that all `new` functions
> always return a word-sized pointer.

# References

When invoking a function with by-ref parameters, users may pass a specific
value of a fixed-length array: 

    type T = { ... };
    fn foo(&x: T) { ... }
    fn bar(ts: [T]) { foo(ts[0]); }

Because the array cannot be grown or moved about, this is perfectly
safe.

# Interaction with generics

The user can never be sure that generic types are not bound to
aggregate value types or unique types.  Therefore, uses of variables
of generic type generally require explicit `copy` or `move`
annotations; however, the last use optimization described by Marijn
means that a variable which is only used once is implicitly moved.

> Examples:
>
>     fn identity<T>(t: T) -> T { ret t; } // ok because implicitly ret move t;
> 
>     fn apply<S,T>(s: S, blk: block(S) -> new T) -> new T { 
>         ret blk(s); // implicitly: ret blk(move s); 
>     }
>
>     fn apply_twice<S:copy,T>(s: S, blk: block(S) -> new T) -> new (T,T) {
>        ret (blk(copy(s)), blk(s)); // Note: first use of `s` requires a copy
>     }

As stated earlier, type variables cannot be bound to dynamically sized
types like `[int]` unless declared with the "interface" `var` (e.g,
`<T:var>`).  

# Regions

Regions would make it possible to safely allocate statically sized
values onto the stack.  The main change, syntactically, is that the
`AE` expressions become:

    AE = @ AV | @ mutable AV | ~ AV | & AV

The `&` form indicates that the newly allocated value ought to be
placed on the stack and a pointer into the stack is returned.
However, there is a limitation: `&foo()` where `foo` is a new function
is still illegal, as the callee cannot allocate space on the caller's
stack.

Regions are required to allow stack allocation because they allow us
to ensure that the stack does not grow endlessly within a single
function call.  This is done by using a different region for stack
allocations that occur within a loop body or a block.

Regions also enable taking the address of members of an array or of
fields in records and so forth using the familiar `&lvalue` form from
C.

# Possible extensions or alternate designs

This section contains some possible extensions / alternate designs.  

## Binding type variables to dynamically sized types by default

Seeing as the "interface" `var` actually takes away options (the type
cannot be stored on the stack), it might be better to say that types
must have the interface `stack` to be stored on the stack.  Then `<T>`
would be the most general declaration, as seems natural. This is the
same question Marijn confronted when deciding whether type variables
ought to be copyable by default.

## Arrays of varying size but fixed capacity

Currently all arrays must instantly become fully initialized.  I am
also partial to the idea that an array begins with a fixed capacity
but a size of 0.  The array could then be appended to until the fixed
capacity is reached.  Arrays could not be made smaller.  

The array creation routines would then all be based on a single primitive
creation routine:

    fn create_cap<T>(cap: uint) -> new [T];
    
Arrays would be represented at runtime *exactly* as vectors are
represented today:

    struct rust_array<T> {
        size_t fill, alloc;
        T[] data;
    }

This would make it possible to implement dynamic vectors in pure Rust
without a loss of efficiency, except that there is no way to handle
the case where items are removed from the end of a dynamic vector
without recopying the entire array.  This limitation is why I rejected
the idea, figuring it may not be worth the mental complexity.

