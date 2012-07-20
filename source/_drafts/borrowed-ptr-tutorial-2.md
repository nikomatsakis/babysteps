# Borrowed pointers

Borrowed pointers are one of the more flexible and powerful tools
available in Rust. A borrowed pointer can be used to point anywhere:
into the shared and exchange heaps, into the stack, and even into the
interior of another data structure.  With regard to flexibility, it is
comparable to a C pointer or C++ reference.  However, unlike C and
C++, the Rust compiler includes special checks that ensure that
borrowed pointers are being used safely.  Another advantage of
borrowed pointers is that they are invisible to the garbage collector,
so working with borrowed pointers helps keep things efficient.

We have done our best to ensure that these checks mostly occur behind
the scenes; but to get the most out of the system, you will have to
understand a bit about how the compiler reasons about your program.

This document can be considered a reference guide to borrowed
pointers.  I have tried to explain the ideas in a sort-of tutorial
style but at a level of depth that is inappropriate for a tutorial.
This is my first attempt at explaining these concepts in written form,
so feedback is welcome.  I hope later to revisit this document and
extract a subset that will be more suitable for a general tutorial.

> An aside: In this document, I am assuming that some outstanding bugs
> in the region implementation are fixed, notably #XXX and #YYY. This
> should happen soon.

## Why are they called borrowed pointers?

We call borrowed pointers *borrowed* because, unlike shared and unique
boxes, they never imply ownership.  A borrowed pointer is always a
pointer into memory owned by someone else, generally a caller to the
current function.  In this context, *owning* memory basically means
taking responsibility for freeing it.  The fact that borrowed pointers
never imply ownership is also why they can be ignored by the garbage
collector: it is never the responsibility of the borrowed pointer to
keep memory alive.

Borrowed pointers can be created in two ways.  The first is to explicitly
take the address of something, such as a local variable or a field:

    let r: {x: int, y; int} = {x: 10, y: 10};
    let p: &{x: int, y; int} = &r;
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

    type point = {x: int, y: int};
    fn distance_from_origin(r: &point) {
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

One rather bizarre looking expression that you might see from time to
time is something like `&*r2` (where `r2` is the shared box defined in
the previous example).  This has the effect of converting a type like
`@point` into a `&point` (it also works for a `~point`).  It works
because we are taking the address of the dereference of the pointer.
In effect, the `&` and `*` "cancel each other out" and so you are left
with a borrowed copy of `r2`.

## Some examples of using borrowed pointers

### Storing data on the stack

The stack is a very convenient and efficient place to store data with
a limited lifetime.  For example, imagine that we were going to be
drawing a scene; we might have some context that will be required at
each point:

    type point = {x: int, y: int};
    type rect = {upper_left: point, lower_right: point};
    type draw_context = {
        canvas: &canvas,
        bounds: rect
    };

Here the type `draw_context` is defined with two fields.  The first,
`canvas`, is presumably some sort of OS drawing layer.  We don't need
to *own* the canvas, just use it, so `draw_context` contains a borrowed
pointer to the canvas.  The second field is a rectangle that contains
the drawing bounds.

Now let's look at the top-level routine for drawing the scene:

    fn draw_scene(canvas: &canvas, bounds: rect) {
        let ctxt = &{canvas: canvas, bounds: bounds};
        
        draw_starry_sky(ctxt);
        draw_tree(ctxt, 15, 25);
        reticulate_splines(ctxt);
    }

The first line which defines the variable `ctxt` uses the `&` operator
to allocate space on the stack and create the context record.  Using
the `&` operator in this way (that is, with an rvalue, or
non-assignable expression) is actually a shorthand for something like
the following:

    let temp = {canvas: canvas, bounds: bounds};
    let ctxt = &temp;
    
    


## Lifetimes

In the compiler, each borrowed pointer is associated with a *lifetime*
(you may also have heard the term *region*).  A lifetime is a block or
an expression during the pointer may be safely used.  The compiler
reports an error if a borrowed pointer is used outside of its
lifetime.

So far we have always written the type of a borrowed pointer as `&T`.
In fact, the full type is `&lt/T` where `lt` is a the name of a
lifetime.  You will rarely need to write this form but it may appear
in error messages, and we will use it in the tutorial to clarify
what's going on.  To make the idea of lifetimes more concrete, let's
look at two examples.

### Concrete lifetimes

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

    fn max(a: &X/int, b: &X/int) -> &X/int {
        if *a > *b {a} else {b}
    }

This can sometimes be useful if you want to distinguish between the
lifetimes of certain parameters.  For example, the function `select()`
takes a third parameter `c` but that parameter is never returned:

    fn select(a: &X/int, b: &X/int, c: &Y/int) -> &X/int {
        if *z > 0 {x} else {y}
    }

Because `c` is never returned, `select()` assigns it to a named
lifetime parameter `Y` (vs `a`, `b`, and the return type, which are
given the lifetime `X`).  This means that `c` will be considered to
have a distinct lifetime from `a`, `b`, and the return type.

Pointers with no designated lifetime are considered distinct from all
other names, so `select()` could also be written with `a`, `b`, and
the return type using the anonymous lifetime:

    fn select(a: &int, b: &int, c: &Y/int) -> &int {
        if *z > 0 {x} else {y}
    }

### How do lifetimes help ensure safety?

Lifetimes are important for safety because they limit how long a
borrowed pointer can be used.  Without this guarantee, it would not be
possible to lend out unique and shared boxes.  Consider the case of a
unique box `u` that gets lent out as a parameter and is later sent to
another task:

    type point = {mut x: int, mut y: int};
    fn example() {
        let u = ~{mut x: 10, mut y: 10};
        process_point(u);
        send_to_other_task(u);
    }
    fn process_point(p: &point) { /* ... */ }
    fn send_to_other_task(p: ~point) { /* ... */ }

Without lifetimes, we could not rule out the possibility that
`process_point()` squirelled away a copy of `p`, perhaps in a data
structure somewhere.  Then, after the point was sent to another task,
we might still make use of that copy, causing data races and generally
wreaking havoc.  Similar problems can occur with shared boxes, since
borrowed pointers are invisible to the garbage collector.  Lifetimes
ensure that these scenarios can't happen because they guarantee that
borrowed pointers like `p` will only be used during their lifetimes.

## Borrowing and safety

The previous section explained pointer lifetimes and showed how they
prevent a borrowed pointer from "leaking out" and being used after the
loan has expired.  In a sense, lifetimes protect the lender from a
misbehaving borrower, by ensuring that the borrower does not keep
ahold of the pointer longer than they are supposed to.  However, there
is another side to this coin: the borrower must also be protected from
a misbehaving lender.

Lenders can misbehave by invalidating memory that has been lent out.
Just to push the loan metaphor to the breaking point, we call this
overleveraging.  As an example, consider the following program, which
creates a unique value, lends it out, and then---before the loan has
expired---tries to send the unique value to another task:

    fn example() {                       // --+ Lifetime A
        let u = ~{mut x: 10, mut y: 10}; //   |
        let b = &*u;                     //   |
        send_to_other_task(u);           //   |
        b.x += 1;                        //   |
    }                                    // --+
    // (Note: this program is invalid and will be rejected
    //  by the compiler)

Here, the variable `b` is a borrowed pointer pointing at the interior
of `u`.  The lifetime of this pointer will be the method body, shown
as lifetime A.  Immediately after creating `b`, the value in `u` is
sent to another task.  But then the program uses `b` to modify the
fields of that value.  If this program were allowed to execute, it
would result in an data race.

But of course it does not execute.  In fact the compiler reports an
error:

    example.rs:4:27: 4:28 error: moving out of immutable local variable
                          prohibited due to outstanding loan
    example.rs:4         send_to_other_task(u);
                                            ^
    example.rs:3:18: 3:19 note: loan of immutable local variable granted here
    example.rs:3         let b = &*u;
                                   ^

What this message is telling you is that the variable `u` cannot be
moved because it was lent out to create `b`, and the lifetime of `b`
has not expired.

### How can lenders invalidate memory?

There are actually three ways that lenders could potentially invalid
borrowed pointers.  The first way is to move the memory, as we have
seen.  The second way is to reassign a unique box.  The third way is
to mutate an enum.  Let's look at those two cases in more detail.

#### Reassigning unique boxes

Unlike shared boxes, unique boxes are not garbage collected.  Instead,
they are eagerly freed as soon as the owning reference to them goes
out of scope or is mutated.  So, if we have a program like the following:

    fn incr_unique() {
        let mut u = ~0;
        for 10.times {
            u = ~(*u + 1);
        }
    }

Each iteration around the loop, the variable `u` is reassigned with a
new unique value.  The previous unique value will be freed.  Without
extra safety checks, these eager frees could result in the dreaded
"dangling pointer" that haunts the nightmares of C programmers
everywhere:

    fn incr_unique() {
        let mut u = ~0;
        for 10.times {
            let b = &*u;
            u = ~(*u + 1);

            // here, the memory pointed at in `b` has been freed
            use(*b);
        }
    }
    // (Note: this program is invalid and will be rejected
    //  by the compiler)

#### Reassigning enums

Enums have the interesting behavior that when they are reassigned they
can *change the types* of their contents or even cause their contents
not to exist altogether.  For example, consider this program:

    fn incr_some() {
        let v = some(~3);
        alt v {
            none => {}
            some(ref p) => {
                v = none;
                use(*p);
            }
        }
    }
    // (Note: this program is invalid and will be rejected
    //  by the compiler)

Here, the value `v` is initially assigned a `some` value.  We then
match against this value and, using a `ref` binding, create a pointer
`p` to the inside of `v`.  However, then, on the next line we reassign
`v` with `none`---now the pointer `p` is invalidated, because it was
supposed to point to the argument of the `some` variant, but `v` is no
longer a `some` variant.

To better understand what's going on, consider the following depiction
which shows the stack and heap for a call to `incr_some()` right
before the (second) assignment to `v`.  The value `v` is on the stack
with a tag of `some` and a data field of type `~int`, which points
into the exchange heap.  The value `p` is a pointer into this data
field.

                Stack                Exchange heap
                -----                -------------

              v +------------+
                | tag: some  |
            +-->| ~int       |------>+---+
            | p +------------+       | 3 |
            |   | &~int      |--+    +---+
            |   +------------+  |
            |                   |
            +-------------------+

Now this is the situation after the assignment occurs.  Note that the
tag of `v` has changed to `none` and the data field has been
invalidated, as `none` has no arguments.  This in turn causes the data
in the exchange heap to be freed.  But now the pointer `p` still
exists, and it points into the (now invalidated) data field of `v`.
This is bad.

                Stack                Exchange heap
                -----                -------------

              v +------------+
                | tag: none  |
            +-->| xxx        |
            | p +------------+
            |   | &~int      |--+
            |   +------------+  |
            |                   |
            +-------------------+

### How the compiler prevents overleverage

The goal of the compiler is to guarantee that each time a borrowed
pointer with lifetime L is created, the compiler will ensure that the
memory which is being borrowed is valid for the entirety of the
lifetime L.  We can currently make this guarantee in one of three
ways, depending on the *owner* of the data being borrowed.

#### Data ownership

Before getting into the precise rules that the compiler uses to
prevent overleverage, it is important to understand how Rust defines
*data ownership*.  In Rust, owning data essentially means that you are
responsible for freeing it.  In C and C++, ownership is typically by
convention (though the various smart pointers in C++ help to formalize
these conventions).  In Rust, ownership is built into the type system.

Rust types basically fall into four categories: by value (`T`), unique
boxes (`~T`), shared boxes (`@T`), and borrowed pointers (`&T`):

- **Value types** and **unique boxes** both imply exclusive ownership.
  This means that if a variable with value type or a unique box goes
  out of scope, its contents will be *dropped* (I'll define drop more
  specifically below, but it essentially means "freed").  The same
  applies if a mutable location of value/unique box type is
  overwritten with a new value.
- **Shared boxes** imply shared- or co-ownership: that is, a shared
  box is collected only when all references to it are overwritten or
  go out of scope.  Each reference is therefore a kind of equal owner:
  any one is enough to keep the shared box alive. In the same sense,
  no reference is an owner, as there is no way to guarantee the
  absence of other owners.  Therefore, we say that shared boxes are
  not owned at all, but rather co-owned.
- Finally, **borrowed pointers** never imply ownership.  Borrowed
  pointers must always have a lifetime that is a subset of some other
  owning type.

To help clarify, consider this example:

    fn ownership_example(x: @int) {
        let mut y = {f: ~4, g: x};
        let z = &y.f;
        x = {f: ~5, @5}; // (*)
    }

Here, the parameter `x` is a shared box.  It therefore shares ownership
of its referent with all other references.

The variable `y` has a value type `{f: ~int, g: @int}`.  This is an
interesting type because it shows how ownership is transitive: that
is, because the variable `y` owns its referent, it also owns anything
that is owned by the record itself.  In this case, that means that
`y.f` is also owned, and `y.g` is co-owned (it's a shared box).

Finally, the variable `z` is a borrowed pointer pointing at the
interior of `y`.  Its lifetime, as we'll see shortly, will be limited
by the compiler to the lifetime of the current stack frame, as the
current stack frame owns `y` which in turn owns the field `y.f`.

Here is a graphical depiction of the state of the program immediately
*before* the assignment marked with `(*)`:

        Stack            Exchange Heap     Shared Heap

      x +---------+
        | @int    | ---------------------+
      y +---------+      +---+           |   +---+
    +-> | f: ~int | ---> | 4 |           +-->| _ |
    |   | g: @int | ---+ +---+           |   +---+
    |   +---------+    |                 |
    | z | &~int   | -+ |                 |
    |   +---------+  | +-----------------+
    |                |
    +----------------+

Once the assignment occurs, everything that was owned by `y` will be
freed.  Therefore, the heap afterwards looks like:

        Stack            Exchange Heap     Shared Heap

      x +---------+
        | @int    | ---------------------+
      y +---------+             +---+    |   +---+
    +-> | f: ~int | ----------> | 5 |    +-->| _ |
    |   | g: @int | ---+        +---+        +---+
    |   +---------+    |
    | z | &~int   | -+ |                     +---+
    |   +---------+  | +-------------------> | 5 |
    |                |                       +---+
    +----------------+

Here you can see that the unique box was freed (that was (indirectly)
owned by `y`).  The shared box is no longer referenced by `y`, but it
is not freed because it was co-owned by `x`.  Meanwhile, the variable
`z` is unaffected, though of course the value `*z` will be different.

#### The rules for preventing overleverage

The rules for preventing overleverage depend on the owner of the data
being borrowed.  Basically the compiler tries to accept as many
programs as it can, so it takes advantage of whatever knowledge is
available.

The best case is when the data to be borrowed is exclusively owned by
the stack frame.  This does not *necessarily* mean that the data is
stored on the stack frame.  For example, the data might be found in a
unique box stored in a local variable: in that case, the stack frame
owns the local, which then owns the box, which owns its contents, and
so the data is ultimately owned by the stack frame.  As described
below, data owned by the stack frame can be closely tracked by the
compiler and hence it can be very flexible with what it accepts.

For data which is not owned by the stack frame---or for which the
compiler cannot determine a concrete owner---a stricter set of rules
is applied.  If the data being borrowed is unstable---meaning that
mutating the container would invalidate the borrowed pointer---then
the data must reside in an immutable field, so as to guarantee that no
mutations occur.  

Finally, if the program is borrowing unstable data in a mutable
location, the final fallback is to accept the borrow but only for pure
actions.  *Pure* actions are actions which do not modify any data
unless it is owned by the current stack frame.

The next three subsections examine the three cases in more detail.

##### Loaning out data owned by the current stack frame

When the data to be borrowed is owned by the current stack frame, the
compiler can track it quite precisely.  The compiler internally tracks
all loans of values owned by the stack frame that are in scope at each
point.  A loan is in scope for the entire lifetime of the borrowed
pointer.

The compiler will check that all actions are compatible with the set
of loans that are in scope.  This means that it is not legal to move
data out a variable or path when a loan for that path (or some
enclosing) is in scope.  Similarly, if the borrowed pointer is an
immutable pointer (i.e., `&T` and not `&const T` or `&mut T`), then
any assignment to the value which was lent out is prohibited.

This last point concerning mutability is subtle.  In general, it is
legal to create an *immutable pointer* to *mutable data* so long as
the compiler can guarantee that the data will not be mutated for the
lifetime of the pointer.  Currently we can guarantee immutability in
two cases: one is when the data that is lent out is owned by the
current stack frame, and the other is when only pure actions are taken
for the lifetime of the reference.  Purity is discussed below.

Most of the prior examples have made use of loans, so I will just give
one more example that shows loans of subfields as well as immutable
loans of mutable data.

    fn example() {
        let u = ~{mut x: 10, mut y: 10};
        let b = &u.x;                    // (0)
        u.x += 11;                       // (1)
        send_to_other_task(u);           // (2)
        #debug["%d", *b];
    }
    // (Note: this program is invalid and will be rejected
    //  by the compiler)

Here the `b` has type `&int`---that is, a pointer to immutable memory
containing an `int`.  However, `b` points at the field `u.x`, which is
declared as mutable.  The compiler notes this discrepancy and records
that `u.x` is lent out as immutable for the lifetime of `b` (here, the
remainder of the method body).  This means that the assignment to
`u.x` marked as `(1)` will be considered illegal.  The compiler will
report a message like "assigning to mutable field prohibited due to
outstanding loan" followed by a note indicating that the loan was
granted on the line marked `(0)`.

The attempt to move `u` on the line marked `(2)` will be prohibited in
a similar fashion.  The compiler will report "moving out of immutable
local variable prohibited due to outstanding loan".  This is somewhat
interesting, because it shows that although we borrowed `u.x` this
also implicitly borrows `u`, as `u` is the owner of `u.x`.  In
general, borrowing a value also borrows its owner.

##### Data owned by a shared box or with an unknown owner

The previous section focused on data which was owned by the current
stack frame, but said nothing about other cases.  Very often, of
course, we would like to borrow data owned by a shared box.  Unless
the data being borrowed is part of a unique box or the interior of an
enum, this is not generally an issue.

For example, the following program does not cause any sort of error:

    type T = @{mut f: {g: int}};
    
    fn foo(v: T) -> int {
        let x = &mut v.f.g;
        *x
    }
    
The reason is that even though the field `g` is part of a record
stored in a mutable location, it is not harmful if the field `f` is
reassigned, as it will not change the type of the field `g`.  Field
`g` will remain an integer.  Note however that when we took the
address of `v.f.g` we used the operator `&mut`, which means that the
type of `x` will be `&mut int`: basically, we had to explicitly
acknowledge that the value we borrowed is stored in mutable memory.

However, if there is an attempt to borrow *unstable* memory then the
compiler must be more careful:

    type T = @{mut f: {g: ~int}};
    
    fn foo(v: T) -> int {
        let x = &*v.f.g;
        ...
        *x
    }

Here we attempted to borrow the integer found inside the unique box
`v.f.g`.  This is dangerous because if `v.f.g` were reassigned, then
the pointer `x` would be invalidated.  Furthermore, it is not enough
for the compiler to prevent you from modifying `v.f.g`: because `v` is
a shared box, there may some alias to `v` that you could modify
instead and still cause the same effect.  Therefore, this program
is illegal.

Basically borrowing unstable memory that is owned by a shared box is
only safe if it is stored in an immutable field.  For example, if we
modify the type `T` to remove the `mut` qualified:

    type T = @{f: {g: ~int}};

Now, so long as the shared box remains live, there is no way for the
fields `f` or `g` to be modified, and hence the unique box will remain
live.  

It is still true that the compiler must guarantee that the shared box
remains live.  Because of the nature of shared boxes, however, this is
not a problem: all we must do is guarantee that some reference to the
shared box exists for the duration of the borrow.  In some cases, the
compiler can see that this is already the case in your program: for
example, in the function `foo`, the parameter `v` is immutable and
refers to the shared box, so so long as `v` is in scope the shared box
will not be freed.  

However, even if `v` were a mutable local, there is no problem: the
compiler would just create a temporary with the current value so as to
ensure that the shared box is not collected while the borrowed pointer
exists.  Here is an example `bar()` that makes use of this feature:

    fn bar() -> int {
        let mut x = @{f: 3};
        let y = &x.f;
        assert *y == 3;
        x = @{f: 4};    // overwrite x with new value
        assert *y == 3; // but y still points at the old memory
    }
    
What happens here is that the field `f` of the shared box is borrowed,
but then the reference `x` to the shared box is mutated.  If `x` were
the last reference to the box, and the compiler did nothing, then the box
might be freed at this point.  But in fact the compiler sees that `x` is
declared as a mutable local variable and so it inserts a temporary that
refers to `x`.  This is called *rooting* `x`, because it ensures that
there is a root for the garbage collector to find.  In other words,
the function `bar()` is compiled to something like:

    fn bar() -> int {
        let mut x = @{f: 3};
        let _x = x;     // compiler-inserted root
        let y = &x.f;
        assert *y == 3;
        x = @{f: 4};    // overwrite x with new value
        assert *y == 3; // but y still points at the old memory
    }

##### Purity

Sometimes neither of the two techniques described above apply.  In
that case, the compiler will accept any borrow, so long as all code
for the lifetime of the borrow is *pure*. Pure code is code which does
not modify any data that is not owned by the current stack
frame. Basically you can borrow anything so long as you promise not to
make any mutation (except for local variables).
