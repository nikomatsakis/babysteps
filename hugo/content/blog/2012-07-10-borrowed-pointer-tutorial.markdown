---
categories:
- Rust
comments: true
date: "2012-07-10T00:00:00Z"
slug: borrowed-pointer-tutorial
title: Borrowed Pointer Tutorial
---

This is a draft of (the first section of) a new Rust tutorial on
borrowed pointers (the official name for "regions").  Comments
welcome.

**UPDATE:** I added a section "Why borrowed?"

# Borrowed pointers

Borrowed pointers are one of the more flexible and powerful tools
available in Rust. A borrowed pointer can be used to point anywhere:
into the shared and exchange heaps, into the stack, and even into the
interior of another data structure.  With regard to flexibility, it is
comparable to a C pointer or C++ reference.  However, unlike C and
C++, the Rust compiler includes special checks that ensure that
borrowed pointers are being used safely.  We have done our best to
ensure that these checks mostly occur behind the scenes; but to get
the most out of the system, you will have to understand a bit about
how the compiler reasons about your program.

## Why borrowed?

We call borrowed pointers *borrowed* because, unlike shared and unique
boxes, they never imply ownership.  A borrowed pointer is always a
pointer into memory owned by someone else, generally a caller to the
current function.

Borrowed pointers can be created in two ways.  The first is to explicitly
take the address of something, such as a local variable or a field:

    let r: {x: int, y: int} = {x: 10, y: 10};
    let p: &{x: int, y: int} = &r;
    let q: &int = &r.x;
    
In the previous example, the memory is a record `r` stored on the
stack.  The variable `p` is a borrow of the record as a whole.  The
variable `q` is a borrow of the field `x` specifically.

One convenience: in C, the `&` operator can only be applied to lvalues
(assignable locations).  In Rust, the `&` operator can also be applied
to rvalues, in which case it means "allocate some temporary space on
the stack and copy the value in there".  So, for example, the
following code create a new record, store it on the stack, and take
its address all in one step:

    let p = &{x: 10, y: 10};
    
The second way to create a borrowed pointer is by converting a shared
or unique box into a borrowed pointer.  These conversions happen
implicitly on function and method calls (we may later expand the
places where such conversions can occur).  This is useful for writing
routines that operate over data no matter where it is stored.  For
example:

    fn distance_from_origin(r: &{x: int, y: int}) {
        sqrt(r.x * r.x + r.y * r.y)
    }
    ...
    // Record stored on stack:
    let r1 = &{x: 10, y: 10};
    let d1 = distance_from_origin(r1);
    ...
    // Record stored in shared box:
    let r2 = @{x: 10, y: 10};
    let d2 = distance_from_origin(r2);
    ...
    // Record stored in unique box:
    let r3 = ~{x: 10, y: 10};
    let d3 = distance_from_origin(r3);

## Lifetimes

In the compiler, each borrowed pointer is associated with a *lifetime*
(you may also have heard the term *region*).  A lifetime is a block or
an expression during the pointer may be safely used.  The compiler
reports an error if a borrowed pointer is used outside of its
lifetime.

So far we have always written the type of a borrowed pointer as `&T`.
In fact, the full type is `&lt.T` where `lt` is a the name of a
lifetime.  You will rarely need to write this form but it may appear
in error messages, and we will use it in the tutorial to clarify
what's going on.  To make the idea of lifetimes more concrete, let's
look at two examples.

### Lifetimes

The first example is a function that declares an integer variable and
takes its address.  The resulting pointer is passed to a function
`proc_int()`.

    fn lifetime_example(cond: bool) { // --+ Lifetime A
        if cond {                     //   |--+ Lifetime B
            let x: int = 10;          //   |  |
                                      //   |  |--+ Lifetime C
            proc_int(&x);             //   |  |  |
                                      //   |  |--+
        }                             //   |--+
    }                                 // --+
    
    fn proc_int(x: &int) { /*...*/ }

Alongside the example is a depiction of three of the relevant
lifetimes.  The first, lifetime A, corresponds to the body of the
method.  The second, lifetime B, corresponds to the then block of the
if statement.  Finally, the third, lifetime C, corresponds to the call
to `proc_int()`.

When it sees the expression `&x`, the compiler will automatically
determine the lifetime for the resulting pointer.  The compiler
attempts to select the shortest lifetime that it can.  In this case,
the lifetime will be Lifetime C, because the pointer is only used
during the call expression itself.  The maximum lifetime that the
compiler would permit would be Lifetime B, because that is the
lifetime of the variable `x` itself.

This example shows that lifetimes have a hierarchical relationship
derived from the code itself.  Every expression has a corresponding
lifetime, and the lifetimes of subexpressions are nested inside of the
lifetimes for the outer expressions.

### Lifetime parameters

In the previous example, all of the relevant pointer lifetimes
corresponded to expressions within the method itself.  However, this
is not always the case.  Consider the function `proc_int()` that
we saw in the previous example:

    fn proc_int(x: &int) {  // --+ Lifetime D
        #debug["x=%d", *x]; //   |
    }                       // --+

What is the lifetime of the parameter `x`?  You might think it would
be `D`, the lifetime of the method body, but that is not correct.
After all, `x` was given to us from the caller, so its lifetime is
going to be some expression that the caller knows about, but the
callee (in this case, `proc_int()`) does not.

To handle this case, functions can be *parameterized* by lifetimes.
In fact, this happens implicitly whenever a parameter is a borrowed
pointer.  This means that the compiler invents a synthetic lifetime,
let's call if X, and says "the lifetime of the parameter `x` is
X". All the compiler knows about X is that it is some expression
in the caller which is at least as long as the method call itself.
So, in fact, this is the set of lifetimes that the compiler thinks
about:

                            // --+ Lifetime X
    fn proc_int(x: &int) {  //   |--+ Lifetime D
        #debug["x=%d", *x]; //   |  |
    }                       //   |--+
                            // --+

Here the lifetime D for the method body is seen as a sublifetime of
this lifetime parameter X.  Each time that `proc_int()` is called, the
lifetime X will refer to some lifetime in the caller.  So, in in the
case of our first example, the lifetime X would refer to the lifetime
C that corresponded to the call to `proc_int()`.

#### Multiple lifetime parameters

By default, every borrowed pointer that appears inside the function
signature is assigned to the same lifetime parameter.  So if you had a
function like `select_ints()`, each of the parameters and also the
return type are all assigned the same lifetime, X:

                                        // --+ Lifetime X
    fn max(a: &int, b: &int) -> &int {  //   |
        if *a > *b {a} else {b}         //   |
    }                                   //   |
                                        // --+

Just because `max()` considers each of those borrowed pointers to have
the same lifetime does not mean that they must have the same lifetime
in the caller.  For example, consider this function that calls
`max()`:

    fn calls_max(cond: bool) {         // --+ Lifetime A
        let x: int = 10;               //   |
        if cond {                      //   |--+ Lifetime B
            let y: int = 20;           //   |  |
            let z: &int = max(&x, &y); //   |  |
            assert *z == 20;           //   |  |
        }                              //   |--+
    }                                  // --+

In this case, the lifetime of `&x` is A and the lifetime of `&y` is B.
When calling `max()`, the lifetime of the parameter Y would be
selected as B, which is the shorter of the two.  This is also the
lifetime of the result `z`.

#### Named lifetime parameters

You can also opt to give lifetime parameters explicit names.  For example,
the `max()` function could be equivalently written as:

    fn max(a: &X.int, b: &X.int) -> &X.int {
        if *a > *b {a} else {b}
    }

This can sometimes be useful if you want to distinguish between the
lifetimes of certain parameters.  For example, the function `select()`
takes a third parameter `c` but that parameter is never returned:

    fn select(a: &X.int, b: &X.int, c: &Y.int) -> &X.int {
        if *z > 0 {x} else {y}
    }

Because `c` is never returned, `select()` assigns it to a named
lifetime parameter `Y` (vs `a`, `b`, and the return type, which are
given the lifetime `X`).  This means that `c` will be considered to
have a distinct lifetime from `a`, `b`, and the return type.

Pointers with no designated lifetime are considered distinct from all
other names, so `select()` could also be written with `a`, `b`, and
the return type using the anonymous lifetime:

    fn select(a: &int, b: &int, c: &Y.int) -> &int {
        if *z > 0 {x} else {y}
    }

