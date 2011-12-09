---
layout: page
title: "No implicit copies"
date: 2011-12-03 08:47
comments: true
sharing: true
footer: true
---

This is a proposal for Rust whose purpose is to **eliminate (most)
implicit copies,** while preserving most other aspects of the
language.  Secondary goals include:

- make vectors and strings non-unique;
- permit references into arrays;
- make destination passing style (DPS) a guaranteed optimization that
  is obvious from language syntax;
- support dynamically sized records.

## Revision History

- `2011-12-03`: initial version
- `2011-12-08`: removed `new` functions

## Why are these goals important?

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

## Summary

The following changes are made:

- vectors become fixed-length arrays;
- arrays can be embedded in record types as the final field, leading to a
  dynamically sized record;
- large, deep copies will require an explicit `copy` keyword;
- move-mode parameters go away, replaced with a `move` keyword.

## Terminology: kinds of types

Under this proposal, the only types which can be implicitly copied are
scalar types, shared pointers (i.e., `@`), and tuples of implicitly
copied types (inductive definition).  The user is guaranteed that no
values of any other types will be copied without an explicit `copy` or
`move` keyword.

I often have to refer to different kinds of types.  For my purposes, a
*pointer type* is either `@T` or `~T`: that is, a pointer.  A *value
type* is any non-pointer type. A *scalar type* is a type like `uint`
or `float`.

Types are not to be confused with modes.  In the following function,
for example, the parameter `point` has value type but is passed by
reference:

    fn foo(&point: (uint, uint));
    
Similarly, the parameter to `bar()` has reference type but is passed by value:

    fn bar(+point: @(uint, uint));
    
I assume that parameters of pointer and scalar type are passed by
value by default, and all other parameters are passed by (immutable)
reference, as I believe is the case with `rustc` today.

## Constructor and allocation expressions

The core change in this proposal is that assigning to an lvalue that
may be of explicitly copyable type requires that the rvalue be a
*constructor expression*.  A constructor expression is one which
inherently constructs a new value that did not exist before.  This new
value can then be written directly into the location being assigned
to. The set of constructor expressions is defined syntactically as
follows:

    CE = { ... }                 (Record literals)
       | ( ... )                 (Tuples)
       | 0, 0u, 'a', 1.2         (Numeric/character literals)
       | "..."                   (Strings)
       | x(...)                  (Function call with appropriate return type)
       | copy E                  (Copy of some other expression E)
       | move x                  (Move of some local variable x)
       
For the purpose of this proposal, an "assignment" includes not only
explicit assignments like `x=y` but also returns from a function (ret
"assigns" to the return type) and passing a parameter (assignment from
actual value to formal parameter).

One other category of expressions that will come up later is an
*allocation expression*; allocation expressions are those which
allocate a new value onto some heap (`@` or `~`).  They are defined as
follows:

    AE = @ AV
       | @ mutable AV            (Type of AV must be copyable)
       | ~ AV
    AV = CE
       | [ ... ]                 (Array literal)
       | { ..., f: [...]}        (Record literals of dynamic size)
       
The nonterminal `AV` indicates an allocatable value: something which
may be copied into the heap.  This is *almost* the same as a
constructor expression, but it also includes array literals and record
literals of dynamic size, both of which can produce values of dynamic
size which cannot be placed on the stack and must therefore go in the
heap.  More details about dynamically sized types come later.

Note: It is illegal to use `@ mutable` when the `AV` has a
non-copyable type.

### Copies and moves

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
- Copying a resource is illegal.
- Copying an array type `[T]` creates a new array and copies each
  member of the array.  The type `T` must be copyable.
  
The copy algorithm is designed to be as shallow as it can be while
preserving the aliasing guarantees of unique pointers.  Note that not
all types are copyable.
  
The `move x` expression moves the value of `x` to another location.
`x` will no longer be accessible after the move.  `x` must not have
reference mode (e.g., a parameter or an upvar in a block).
Effectively, code like `let y = move x` could be implemented
(inefficiently) in C as:

    T x, y;
    memmove(&y, &x, sizeof(T));
    memset(&x, 0, sizeof(T));   // for garbage collection, basically.

Moves are legal for all types. 

### Deprecating move-mode parameters

Given the `move` expression on the caller side, there is really no
need for `move` mode arguments.  The primary use case for move mode
arguments was to "give away" a unique pointer: this is now achieved by
having the callee simply declare a parameter of unique type and having
the caller `move` it to them.  In other words, it's the caller's job
to produce a unique pointer for the callee to consume: whether that
unique pointer is copied, moved, or newly constructed is up to the
caller.

## Fixed-length arrays, strings, and dynamically sized types

Currently, vectors and strings are implicitly accessed via unique
pointers.  This is the cause of much confusion.  This makes it easy to
append to a vector using the `+=` keyword, since the vector can be
safely grown in place without invalidating any other aliases (there
are none).  However, it requires a copy each time a vector is assigned
to another variable, and it makes it less efficient to share vectors
(the type `@[...]` yields a boxed unique pointer).  These performance
characterics are counterintuitive: vectors and strings are immutable
types which are cheap to modify but expensive to share/copy, exactly
the opposite of most persistent/immutable types.  Another downside of
dynamic vectors is that there is no way to allow references into the
vector; they might point to freed memory if the vector were resized.

*An aside:* it would be possible to use a ref-counting scheme to
ensure that vector data is not freed until all references are dead.
But you still have the problem of unpredictable aliasing when a vector
is being extended with live references to the interior, which I
consider unacceptable.

To address these problems, the native type in this proposal is
fixed-length arrays rather than growable vectors.  A fixed length
array is represented at runtime by something like the C++ struct:

    struct array<T> {
        size_t alloc;
        T[] data;
    }
    
Therefore it is not, itself, a C array, but it's very close.  A simple
helper could convert it to one, much as we do today.

Growable vectors can be implemented via a library.  Simple operator
overloading should address the issue that they are clumsy to use.

### Array creation

Arrays can be created either via literals `[v1, v2, v3]` or via the
use of creation functions.  Literals result in an array of the given
size which is stored on the stack.  There are two creation functions,
each of which creates an array of dynamic length:

    fn create_val<copy T>(size: uint, v: T) -> [T];
    fn create<T>(size: uint, b: block(uint) -> T) -> [T];

The function `create_val()` creates an array of a given size where
each value of the array is initially equal to `v`.  The second creates
an array where the initial value of the array at index `i` is given by
`b(i)`.  

### Mutability

As with vectors now, arrays can either be immutable (the default),
mutable, or read-only (`const`).  An immutable array cannot be
modified by anyone.  A read-only array is a reference to an array thay
may be mutated by someone else.

Functions returning arrays may be used to create either mutable or
immutable arrays at the callers' choice; the caller also decides
whether the array will be allocated in the shared or exchange heap.
For example:

    let f: @[int] = @arr::create_val(256, 0);
    let g: @[mutable int] = @arr::create_val(256, 0);
    let h: ~[int] = ~arr::create_val(256, 0);
    let i: ~[mutable int] = ~arr::create_val(256, 0);
    
Here the same function (`arr::create_val()`) is used to create arrays of
many different types.  We could also allow unique arrays to become
mutable and immutable if we wished.

### References of and into arrays

When invoking a function with by-ref parameters, users may pass a specific
value of a fixed-length array: 

    type T = { ... };
    fn foo(&x: T) { ... }
    fn bar(ts: [T]) { foo(ts[0]); }

Because the array cannot be grown or moved about, this is perfectly
safe.

### Limitations on array types and other dynamically sized types

Array types `[T]` are unlike other types in that they do not have a
static size.  Such dynamically sized types must generally be
manipulated by pointer (e.g., `@[T]` or `~[T]`).  One place that
array types may be used is as the last field in a record.  In that
case, the record type is itself considered dynamically sized and
subject to the same restrictions as array types.  Dynamically sized
types are also legal as the type of a by-ref parameter and as the
return type of a function (see below).

Lvalues of dynamically sized type cannot be assigned after they are
initially created.  In other words, given a record `x` with a field
`f` of type `[int]`, `x.f = ...` is always illegal.

An important restriction is that type variables cannot---by
default---be bound to a dynamically sized type.  To be bound to an
array or other dynamically sized type, a type variable must be
declared with the bound `var` (for "variably sized").  This is so that
the type checker can guarantee that such types are never allocated on
the stack.

As a consequence of the previous rule, functions whose return type may
have dynamic size can only be invoked from a limited set of contexts:

- they may be called as part of an allocation value (`AV`, defined
  previously).  An example would be `@f(...)`.
- they may be called as part of a `ret` statement from another function
  (which must itself have a dynamically sized return type, or else
  the types would not match).
- we might consider allowing them to be caller in an argument position
  when the parameter has reference mode, but this might be complex to
  check and is certainly not mandatory (e.g., `g(f(x))`).  Otherwise,
  such a call would be written `g(*@f(x))`.

### Handy wrappers

Because dynamically sized types can only be used in a limited set of
contexts, we might want to provide wrappers like the following:

    fn shared<S,T:var>(f: fn(S) -> T) -> (fn(S) -> @T) {
        ret lambda(s: S) { @f(s) }
    }
    
    fn unique<S,T:var>(f: fn(S) -> T) -> (fn(S) -> ~T) {
        ret lambda(s: S) { ~f(s) }
    }

Now a function `f()` returning an array `[T]` could be converted by
`shared(f)` to a function returning a boxed array `@[T]`, which has
static size.

### Implementation

Today, all Rust functions are compiled with an implicit first
parameter which is a pointer to the location to store their return
value.  Functions that may return values of dynamic size would contain
two additional implicit parameter: the heap in which to allocate space
for their result and the amount of prefix space required for the
allocation.

For example, the `arr::create()` with signature

    fn create<T>(size: uint, v: T) -> new [T]

would compile to a C function roughly like:

    void create(
        // Implict arguments:
        char **implicit_r, 
        rust_heap *implicit_h, 
        size_t implicit_off,
        tydesc *T,
        
        // Explicit arguments:
        size_t size, 
        void *v)
    {
        size_t bytes = size * T->size;
        char *ptr = implicit_h->malloc(bytes + implicit_off);
        rust_arr *result = (rust_arr*) (ptr - implicit_off);
        result->size = size;
        for (size_t i = 0; i < size; i++) {
            memcpy(result->data + i * T->size, v, T->size);
        }
        *implicit_r = ptr;
    }
    
The reason for the `implicit_off` parameter is when allocating a
record of dynamic size.  For example, imagine `create` is used like so:

    type T = { x: u32, y: u32, z: [bool] };
    fn use_create_in_record() -> T {
        ret { x: 0, y: 0, z: arr::create(32, false) };
    }
    
Here the array being created is actually interior to the record being
returned.  Therefore, `use_create_in_record()` would be compiled
something like:

    struct T { uint32_t x; uint32_t y; bool[] z; };
    void use_create_in_record(
        // Implict arguments:
        char **implicit_r, 
        rust_heap *implicit_h, 
        size_t implicit_off,
    {
        uint32_t x = x;
        uint32_t y = y;
        size_t off = sizeof(uint32_t) + sizeof(uint32_t); // x + y
        arr::create(implicit_r, implicit_h, implicit_off + off, false);
        T *ptr = (T*) (implicit_r + implicit_off);
        ptr->x = x;
        ptr->y = y;
    }

Note that there is an implicit move that occurs for the fields which
precede the final array.  I think this is OK but it is somewhat
unfortunate; if those are large value typed fields, the change in
performance might be noticable (one could see this as an implicit
copy, but in reality it is an implicit *move*, and only in a corner
case; I think having dynamic size records are worth it).

### Possible optimization for word-sized returns

For efficiency, we may choose to also distinguish between functions
that always return word-sized values, as C compilers do. Such
functions can use the native ABI to return their result (e.g., use the
EAX register on i386).  However, to avoid a proliferation of
user-visible ABIs, we would hide this distinction from users. This
means that such functions would also have a generic variant that takes
a return value parameter.

As an example, the following Rust function `foo()`:

    fn foo() -> int { ret 22; }

would compile to the following C functions:

    int foo_direct() { return 22; }
    int foo_by_val(int *r) { *r = 22; }

Direct calls to `foo()` would use `foo_direct()`.  Loading `foo()` as
a value would use `foo_by_val()`. Note that functions whose result may
have dynamic size always return a word-sized pointer.

## Interaction with generics

The user can never be sure that generic types are not bound to an
explicitly copied type.  Therefore, uses of variables of generic type
generally require `copy` or `move` annotations; however, the last use
optimization described by Marijn means that a variable which is only
used once is implicitly moved.

Some examples:

     fn identity<T>(t: T) -> T { ret t; } // ok because implicitly ret move t;
 
     fn apply<S,T>(s: S, blk: block(S) -> new T) -> new T { 
         ret blk(s); // implicitly: ret blk(move s); 
     }

     fn apply_twice<S:copy,T>(s: S, blk: block(S) -> new T) -> new (T,T) {
        ret (blk(copy(s)), blk(s)); // Note: first use of `s` requires a copy
     }

As stated earlier, type variables cannot be bound to dynamically sized
types like `[int]` unless declared with the "interface" `var` (e.g,
`<T:var>`). 

## Closures

Closures using `lambda` or `bind` can cause implicit copies.  I would
like to introduce capture clauses which would be required to access
any variable of an explicitly copied type (for convenience, upvars of
implicitly copied types would remain accessible as they are today).
For now, these clauses would look like:

    let l = lambda[copy x, y; move z](a: uint) -> {
        ...
    }

Variables which are copied or moved into scope cannot be moved out of
scope and are only freed when the lambda is deleted.  We cannot allow
such an upvar to be moved because the lambda could be invoked multiple
times, and the move cannot occur multiple times; to support that we
would need some sort of "one shot" lambda type.

These rules also apply to `bind`. A `bind f(e1, e2, e3)` expression
can be considered syntactic sugar for:

    {
        let x = e1;
        let y = e2;
        let z = e3;
        lambda[move x, y, z] () { f(x, y, z) }
    }

## Possible extensions or alternate designs

This section contains some possible extensions / alternate designs.  

### Regions

This proposal is not a proposal to include region types.  However, we
are looking at this as a possibility, and there are some interactions
with this proposal.  In particular, regions would make it possible to
safely allocate most values onto the stack.  The main change,
syntactically, is that the `AE` expressions become:

    AE = @ AV | @ mutable AV | ~ AV | & AV

The `&` form indicates that the newly allocated value ought to be
placed on the stack and a pointer into the stack is returned.
However, there is a limitation: `&foo()` where `foo` is a new function
is still illegal, as the callee cannot allocate space on the caller's
stack (`&[...]` is legal, however).

Regions are required to allow stack allocation because they allow us
to ensure that the stack does not grow endlessly within a single
function call.  This is done by using a different region for stack
allocations that occur within a loop body or a block.

Regions also enable taking the address of members of an array or of
fields in records and so forth using the familiar `&lvalue` form from
C.

### Binding type variables to dynamically sized types by default

Seeing as the "interface" `var` actually takes away options (the type
cannot be stored on the stack), it might be better to say that types
must have the interface `stack` to be stored on the stack.  Then `<T>`
would be the most general declaration, as seems natural, but on the
other hand types declared like `<T>` could not be used as the type of
a local variable, which might be surprising. This is the same question
Marijn confronted when deciding whether type variables ought to be
copyable by default.

### Unify `c_vec` arrays with fixed-length arrays

The arrays defined in this document are close but not identical to the
vectors in the `c_vec` module; those vectors contain a `T*` data
field, requiring another level of indirection for access.  We could
make our arrays work the same but it would have inferior performance
characteristics and would defeat the purpose of supporting
dynamic-sized records.

### Arrays of varying size but fixed capacity

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

### User-defined implicitly copyable types

If we moved to nominal records, it would be possible to designate
records as being implicitly copyable.
