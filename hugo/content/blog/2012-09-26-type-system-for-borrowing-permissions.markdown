---
categories:
- Papers
comments: true
date: "2012-09-26T00:00:00Z"
slug: type-system-for-borrowing-permissions
title: Type system for borrowing permissions
---

Well, I have not done too well with my
[goal of reading a research paper a day on the train][prrf] (actually
my initial goal was two papers, but seeing as how I've failed so
spectacularly, I've dialed it back some).  However, I've decided to
give it another go.  I've bought a printer now so I can print papers
out (double-sided, no less!) at home (I had initially planned to buy
an iPad or something, but a decent printer is only $100, and paper is
still nicer to read and write notes on...you do the math).  As
additional motivation, I'm working again on the paper on Rust's new
borrowed pointers and so I have to catch up on a lot of related work.

[prrf]: {{ site.baseurl }}/blog/2012/04/25/permission-regions-for-race-free-parallelism/

To that end, I downloaded and read
[*A Type System for Borrowing Permissions*][paper], published at POPL
2012 by Naden, Bocchino, Aldrich, and Bierhoff.  It's a very good
read: pretty easy to follow and certainly directly related to a lot of
what we've been doing in Rust.  Overall, I found it to be both more
and less expressive than Rust's system.  It's hard to compare the
complexity of the two: each is complex in its own way.

[paper]: http://www.cs.cmu.edu/~aldrich/papers/borrowing-popl11.pdf

<!--more-->

### A brief summary of their work

The basic idea of their system is to label object types
with permissions.  There are several such permissions:

- `unique` --- the only pointer to an object
- `immutable` --- the object can be shared but not modified
- `shared` --- the object can be freely shared and modified
- `local immutable` --- the object can be aliased from local variables but not mutated
- `local shared` --- the object can be aliased from local variables and modified

Each variable is annotated with such a permission.  Parameters are annotated not 
only with a permission but with a "change" permission.  For example, something like
Rust's `send()` function, which consumes its parameter, would be written:

    void send<T>(unique >> none T send) { ... }
    
This indicates that the value must begin as unique but, after the
function call, will have the permission "none".  You can also annotate the receiver
in the typical, C++-inspired style:

    void foo() unique { /* Can only be called if the receiver is unique */ }

Unique objects can be temporarily aliased using the "local"
permissions, such as `local shared` or `local immutable`.  Such
objects cannot be used outside of local variables.

It is also possible to temporary alias fields of unique type, so long
as they are stored in unique objects.  This causes the object to be
only partially valid: an aliased unique field is no longer unique,
after all.  An object in this state is called "unpacked": it must be
packed again before it can be passed around.  Unpacking like this is
only permitted when the owner of the field is unique.

### Comparisons to Rust

This is quite close to Rust's lifetime and borrowing system in many
ways.  The notion of packing and unpacking operates much like borrow
check's loans, for example.  There are of course some differences.

### How it is less expressive than Rust?

#### Storing borrowing items into data structures

There are two areas where our system is more expressive.  The first is
that, in their system, borrowed, aliasable things ("local
permissions") are confined to local variables; our borrowed pointers
suffer from no such limitations.  In fact, lifting this restriction
was probably *the* major goal of the shift to using borrowed pointers
in place of reference modes.

An example of where this limitation is problematic is when you have
some largish function that needs some context to perform its
computation.  For example, in our compiler translation pass, you get
as input a "type context" (`&TypeContext`) that contains information
about the types of all expressions.  Then we create a crate context
(`&CrateContext`) that is local to the compilation pass.  Moreover we
make a function (`&FnContext`) for each function and a block
(`&BlockContext`) for each basic block.  Each of these embeds a
pointer to the context up the chain, so from the block context you can
reach the function context, then the crate context, and finally the
type context.  A system confined to local variables cannot express
this sort of pattern without passing each of the various contexts as a
parameter.  You wind up with a lot of functions all taking some big
set of parameters initially---the usual solution is to refactor by
making a single object to pass around, but you won't be able to do
that if you are using local aliases.

Regions allow us to move past this problem.  We can permit arbitrary
aliasing, secure in the knowledge that the type system will prevent
these aliases from escaping out into the wild.  In other words, we
know that even if you package up all those redundant arguments into a
struct, that struct itself will never outlive the function where it is
created.  This sort of reasoning is absolutely crucial to effectively
support stack allocation, which is a primary goal of Rust (but which I
doubt is a goal for Plaid; nonetheless I am sure they will encounter
this problem from time to time).

#### Inherited mutability

The second is that our notion of [inherited mutability][gim] lets us
freeze an entire family of owned objects at once.  I intend to write
another tutorial-style blog post on this, so for now I'll just say
that if you own a freezable data structure---and all the various
container types in Rust will eventually be freezable, I think---you
can convert it between mutable and immutable and back again.  They
have a similar notion of converting `unique` to `immutable`, but as
far as I can tell this is a shall immutability that does not itself
extend to the unique objects within.  It's possible that I am
misreading the type rules on this point though.  Also, I think Rust's
notion of inherited mutability could be applied to their system
without great difficulty.

[gim]: {{ site.baseurl }}/blog/2012/07/24/generalizing-inherited-mutability/

### How is it more expressive than Rust?

The main thing which they can do that we cannot is express the idea of
borrowing a unique pointer but retaining the knowledge that the
pointer is unique.  For us, borrowing is intrinsically tied to
aliasing---for one thing, borrowing a unique value does not make the
original inaccessible, it just lessens the things you can do with it.
For another, we always allow `&T` types to be copied.

Basically, in our system, a `~T` type is always owned.  So if you
write:

    fn foo(bar: ~Map<K,V>) {
        bar.insert(k, v);
        for bar.each |k, v| {
            ...                 // (bar is immutable here)
        }
    }

This is a function which takes in a map, modifies it some, iterates
over it, and then (implicitly) frees it.  The same function could, if
it wanted to, continue by sending `bar` to another task, or doing
whatever.  But, of course, it doesn't here, and perhaps what I really
wanted was just to do some work on behalf of the caller `foo()`.

Typically, the way that one expresses the idea that you want to take
a `Map` but not consume it is to use a borrowed pointer:

    fn foo(bar: &Map<K,V>) {
        bar.insert(k, v);            // (Error)
        for bar.each |k, v| {
            ...                 // (bar is immutable here)
        }
    }
    
Unfortunately, as indicated in the comments, this code will not
compile.  This is because when you borrow a freezable data structure
like a map, you must select if it is immutable (`&Map<K,V>`) or
mutable (`&mut Map<K,V>`).  But this example uses `insert()`, which
requires mutability, and iteration, which requires immutability
(modifying the map while iterating is a no-no).

There are ways to solve this problem.  One is that, in the caller, you
could use a `~Mut<Map<K,V>>`: the `Mut` type basically moves the
safety checks from compile-time to runtime.  This means that if you
try to insert into the map while iterating your task will fail (just
as it would in Java, for example, or most other languages).  However,
using the `Mut` type adds some (slight) overhead and gives you fewer
static guarantees, so it is not ideal.  It's really intended for use
with managed data (e.g., `@Mut<Map<K,V>>`), where there is no hope of
tracking the mutability statically since the map can be aliased.

Another option is to move the map into the function `foo()` and then
return it back to the caller when `foo()` has finished:

    fn foo(mut bar: ~Map<K,V>) -> ~Map<K,V> {
        bar.insert(k, v);
        for bar.each |k, v| {
            ...                 // (bar is immutable here)
        }
        return map;
    }
    
This is a bit annoying, but it works.  It's similar to other affine
systems like [Alms].

[alms]: http://www.eecs.harvard.edu/~tov/pubs/alms/

Under the system proposed in this paper, however, a parameter labeled
`unique Map<K,V>` would not be consumed by the callee.  Basically it
must be unique on entry to the callee *and on exit*.  If the callee
wished to consume the map, such as by sending it to another task, it
would write `unique >> none Map<K,V>`.
