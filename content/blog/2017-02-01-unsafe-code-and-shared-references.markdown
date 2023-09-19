---
layout: post
title: Unsafe code and shared references
categories: [Rust, Unsafe]
---

In a previous post, I talked about a [proposed approach to drafting the
unsafe code guidelines][blame]. Specifically, I want to the approach of having
an **executable specification** of Rust with additional checks that
will signal when undefined behavior has occurred. In this post, I want
to try to dive into that idea a bit more and give some more specifics
of the approach I have in mind. I'm going to focus on this post on the
matter of the proper use of shared references `&T` -- I'll completely
ignore `&mut T` for now, since those are much more complicated
(because they require a notion of uniqueness).

[blame]: {{< baseurl >}}/blog/2017/01/22/assigning-blame-to-unsafe-code/

For the time being, I'm going to continue to talk about this
executable specification as a kind of "enhanced miri". I think
probably the right *formal* way to express it is not as code but
rather as an **operational semantics**, which is a basically a
mathematical description of an interpreter. But at the same time I
think we should keep in mind other ways of implementing those same
checks (e.g., as a valgrind plugin).

I'm also going to focus on single-thread semantics for now. It seems
best to start there, and extend to the multithreaded case only once we
have a good handle on how we think the sequential semantics ought to
roughly work (perhaps using an operationally-based model like [promises] as a starting
point).

[promises]: https://github.com/nikomatsakis/rust-memory-model/issues/32

### How to use shared references wrong

In Rust, a shared reference is more than a pointer. It's also a kind
of *promise* to the type system. Specifically, when you create a
shared reference, the data that it refers to ("referent") is
considered *borrowed*, which means that it is supposed to be
**immutable** (except for under an `UnsafeCell`) and **valid** so long
as the reference is in use. When you're writing *safe Rust*, of
course, the borrow checker ensures these properties for you:

```rust
fn foo() {
    let mut i = 0;
    let p = &i;
    i += 1; // <-- Error! `i` is shared, cannot mutate.
    println!("{}", *p);
}
```

But what about unsafe code? Certainly it is possible to violate either
of these properties. For now, I'm going to focus on *mutating*
borrowed data when you are not supposed to; in fact, freeing or moving
borrowed data can be seen as a kind of mutation (overwriting the data
with uninitialized). So here is a running example of an unsafely
implemented function `util::increment()`, which takes in a `&usize`
and increments it:

```rust
pub fn increment(u: &usize) {
  unsafe {
    let p: *const usize = u; 
    let q: *mut usize = p as *mut usize;
    *q += 1;
  }
}
```

Now, clearly, this is a sketchy function, and I think most would agree
that it should be considered illegal, at least under some
executions. In particular, if nothing else, its existence will
interfere with the compiler's ability to optimize. To see why, imagine
a caller like this one; let's further assume that the source of
`increment()` is unavailable for analysis (perhaps it is part of
another crate, or a different codegen-unit within the current crate).

```rust
fn innocent() {
    let i = &22;
    println!("i = {}", *i);
    increment(i);
    println!("i = {}", *i);
}
```

Ideally, the compiler ought to be able to deduce -- even without
knowing what `increment()` does -- that `*i` equals `22` throughout
this function execution. After all, the underlying temporary that `i`
points at is clearly only accessed through a shared reference, which
ought to be immutable. But, of course, that is not a valid assumption:
`increment()` is violating its contract. So if we perform
optimizations, such as replacing all uses of `i` with the constant
`22`, those will be visible to the end-user. In typical C fashion,
this can be justified if we say that the program encounters *undefined
behavior*, but how can we make that more precise?

### Instrumenting to detect failures

Earlier we mentioned that the key property of a shared reference is
that the borrowed memory will remain both *immutable* and *valid* for
the lifetime of the reference. The way that my mental model works, the
borrow model is kind of like a (compile time) read-write lock: when
you borrow data to create a shared reference, you have acquired a
"read-lock" on that data. As a first stab at what our "augmented
interpreter" might look like, let's see if we can realize that
intution. (Spoiler: this will turn out to be the wrong approach.)

The basic idea is that the interpreter would track a "reader count"
for every bit of memory. When we create a reference (i.e., when we
execute `&i`), that will instruct the interpreter to increment that
counter. The compiler would also generate "release" instructions when
the borrow goes out of scope which would decrement the lock count
again.

So in a sense our augmented program would look like this. The new
assertions are written in comments; the interpreter would understand
them, even if regular Rust execution does not:

```rust
fn innocent() {
    let i = &22;
    println!("i = {}", i);
    // acquire_read_lock(&i);
    increment(&i);
    // release_read_lock(&i);
    println!("i = {}", i);
}
```

Now, once we've inserted those instructions, then presumably
`increment()` would dynamically fail as it attempted to execute `*q +=
1`, because the memory was "read-locked".

### Dealing with unsafe abstractions

So, this idea of a read-write lock seems reasonable so far -- why did
I say that this would turn out to be the wrong approach? Well, one
catch is that it's not sufficient in general to just freeze a single
integer. Rather, when something gets borrowed, we have to freeze *all
the memory reachable from the point of borrow*. That turns out to be
problematic: given that Rust is built on unsafe abstractions, it's not
really **possible** to enumerate all that memory. To see what I mean,
consider this program:

```rust
fn foo() {
    let mut x: Vec<Vec<i32>> = vec![vec![]];
    let y = &x; // borrow `x`
    ...
}
```

Here, the reference `y` borrows `x`, which is a vector of
vectors. This implies that not only is the vector `x` itself frozen,
so are all the vectors within `x`, and so are all the integers in all
those vectors. This means that if the program were to create an unsafe
pointer and navigate to any one of those vectors and try to mutate it,
we should error out.

To enforce this, presumably the compiler would have to insert
something like the `acquire_read_lock(&x)` we saw before. This
instruction would cause the interpreter to navigate to all the memory
reachable from `x` -- but how can it do that? Vectors, after all, are
not a built-in concept in Rust. The `Vec` type is just a struct that
stores an unsafe pointer instead, ultimately looking something like this:

```struct
struct Vec<T> {
    data: *mut T,
    len: usize,
    capacity: usize,
}
```

It's clear that we can freeze the fields of the `Vec`, but it's less
clear how we can freeze the vector's data. Is it safe or reasonable
for us to reference `data`? How do we know that the memory that `data`
refers to is initialized? (In fact, since vectors over-allocated, some
portion of that data is basically guaranteed to be uninitialized.)

We actually encountered similar issues when thinking about how to
integrate tracing GCs (another topic that would make for a good blog
post!). The bottom line is that whatever scheme you create, people
will always want some way to apply their own customic logic (e.g.,
maybe the pointer isn't stored as a `*mut T`, it's actually a `usize`
and you can only extract it by doing an `xor` with some other
values). So it'd really be best if we can avoid the need to
"interpret" an unsafe data structure in any way.

### A second approach: cannot observe a violation 

There is another way to think about the freezing guarantees. Instead
of *eagerly locking* all the memory that is reachable through a
reference, we might instead declare that the *compiler should not be
able to observe any writes*. Under this model, modifying the referent
of an `&i32` is not -- in and of itself -- undefined behavior. It only
becomes undefined behavior when that reference is later loaded and
observed to have been written since its creation.

One way to express this is to imagine that there is a global counter
`WRITES` tracking the number of writes to memory. Every time we write
to a memory address `m`, the interpreter will increment `WRITES` and
store the new value to a global map `LAST_WRITE[m]` -- this map
records, for each address, the last time it was written. When we
*create* a shared reference `r`, we can also read the current value of
`WRITES` and associate this value with the reference as
`TIME_STAMP[r]` (you can think of it as some extra metadata that gets
carried along somehow).

Now, when we *read* from a shared reference `r` that refers to the
memory address `m`, we can check that `LAST_WRITE[m] <=
TIME_STAMP[r]`, which tells us that the memory has not been written
since the reference `r` was created (this may actually be stricter
than we want, but let's start here).

So, coming back to our running example, the code might look like this,
with comments indicating the meta-operations that are happening:

```rust
fn innocent() {
    let i = &22;
    // TIME_STAMP[i] = WRITES
    
    // assert(LAST_WRITES[i] <= TIME_STAMP[i])
    println!("i = {}", *i);

    increment(&i);

    // assert(LAST_WRITES[i] <= TIME_STAMP[i])
    println!("i = {}", *i);
}

fn increment(u: &usize) {
  unsafe {
    let p: *const usize = u; 
    let q: *mut usize = p as *mut usize;
    // WRITES += 1;
    // LAST_WRITES[q] = WRITES;
    *q += 1;
  }
}
```

Now we can clearly see that the second assertion in `innocent()` will
fail, since `LAST_WRITES[i]` is going to be equal to
`TIME_STAMP[i]+1`. This indicates that some form of undefined behavior
occurred.

### Unsafety levels

One of the premises of the [Tootsie Pop model][TPM] is that we can
leverage the fact that Rust separates *safe* from *unsafe* code to
allow for more optimization without making it harder to reason about
unsafe code. Although many specific details of the TPM proposal were
flawed, I think this basic idea is still necessary if we are to
achieve the level of optimization that I would like to achieve while
avoiding the problem of unsafe code becoming very hard to reason
about. I plan to write more on this specific topic ("safety levels")
in a follow-up post; for now, I want to take for granted that we have
some way to designate "safe" functions from "unsafe" functions, and
just talk about how we can reflect that designation using assertions,
and in turn use those assertions to drive optimization.

[TPM]: {{< baseurl >}}/blog/2016/05/27/the-tootsie-pop-model-for-unsafe-code/

Consider this variant of the example from
[my previous post about trusting types][tt]. Let's assume that the
function `patsy()` here is "safe code":

[tt]: {{< baseurl >}}/blog/2016/09/12/thoughts-on-trusting-types-and-unsafe-code/

```rust
fn patsy() {
    let i = &22;
    let v = *i;
    increment(i);
    println!("i = {}", v);
}
```

In this code, the author has loaded `*i` *before* calling
`increment()`, but the result is not used until afterwards. The
question is, given that this is safe code, can we optimize this code
by deferring the load until later? This kind of optimization could be
useful in improving register allocation and stack size, for example:

```rust
fn patsy() { // "optimized"
    let i = &22;
    increment(i);
    let v = *i; // this is moved here
    println!("i = {}", v);
}
```

In general, my goal is that we can drive whether an optimization is
legal based purely on the assertions and things that we are using to
instrument the code when we check for undefined behavior. The idea is
then similar to how C optimization works: we can perform an
optimization if we can show that it only affects executions that would
have resulted in an assertion failure anyhow. So let's see what our
instrumented `patsy()` looks like so far:

```rust
fn patsy() { // instrumented
    let i = &22;
    // TIME_STAMP[i] = WRITES

    // assert(TIME_STAMP[i] <= LAST_WRITES[i])
    let v = *i;

    increment(i);
    
    println!("i = {}", v);
}
```

Based only on these assertions, there is no way to justify the
optimization I want to perform. After all, `increment()` is free to
update `LAST_WRITES[i]` because there is no assertion that states
otherwise.

What went wrong? The disconnected is actually strongly related to my
previous post on [observational equivalence][oe] -- I would like to
optimize `patsy()` on the basis that `increment()`, being declared as
a safe function, will only do things that safe code could do (or,
rather, safe code augmented with the capabilities we define for unsafe
code). That's a pretty strong assumption -- since it assumes we can
fully describe the possible things the code might do -- but we can
weaken it by saying that, since `increment()` is declared safe, I
should get to assume that **any code** that its callers could write
that type-checks will not trigger undefined behavior. But that is
clearly false, as we saw in the previous section: if the caller simply
moves the `let v = *i` line down to *after* `increment()`, an
assertion failure occurs.

[oe]: {{< baseurl >}}/blog/2016/10/02/observational-equivalence-and-unsafe-code/

We can capture some of this intution by saying that, in safe code, we
add **additional assertions** at function boundaries. The idea is that
when safe code calls a function (and, by definition, that function
must be safe, since calling an unsafe function requires an unsafe
block), it can rely on that function not to disturb the types that it
has access to. So imagine that after every function call in a safe
function, we assert that all our publicly accessible state is still
valid. In this case, since `i` is an in-scope reference whose lifetime
has not expired (in particular, even in a [NLL world][NLL], its lifetime
would include the call to `increment()`), that means that the memory it
refers to must not have changed:

[NLL]: {{< baseurl >}}/blog/2016/04/27/non-lexical-lifetimes-introduction/
s
```rust
fn patsy() { // instrumented
    let i = &22;
    // TIME_STAMP[i] = WRITES

    // assert(TIME_STAMP[i] <= LAST_WRITES[i])
    let v = *i;
    
    increment(i);
    // assert(TIME_STAMP[i] <= LAST_WRITES[i])

    println!("i = {}", v);
}
```

Running with these augmented semantics, we see that `increment()` will
yield an assertion failure once `patsy()` calls it, even though we
don't access `*i` again. This in turn justifies our compiler's
decision to move `let v = *i` below the call.

Its clear that, even with these stronger assertions, we are not able
to fully check that some bit of unsafe code is a valid safe
abstraction. In other words, we can show that it did not disturb the
local variables of its caller function in any immediate way, but it
may well have disturbed them in some way that will show up later (for
example, `increment` might not immediately mutate `*i`, but it might
make an alias of `i` that will be used later to perform an illegal
mutation). However, we can hopefully show that the abstraction is
*safe enough* for the compiler to do the optimizations we would like
to do.

### Ginning up metadata for false references

Another question that you quickly run into in this approach -- and
it's a question we have to answer no matter what! -- is what to do
about references that are created in "unorthodox" ways. For example,
what happens if I make a reference by transmuting a `usize` (note: not
recommended):

```rust
// Don't do this at home, kids.
fn wacked(x: &T) -> &T {
    let i: usize = x as *const T as usize;
    let y: &T = transmute(i);
    y
}
```

If the reference `x` has some "identity" as a reference, you can
imagine that the machine might preserve that identity when `x` is cast
to a `usize`, in which case `TIME_STAMPS[y] == TIME_STAMPS[x]`. Or
perhaps the time stamp is reset. This is all strongly related to C
memory models (e.g., [this one][intptrcast]), which also have to
define this sort of thing (related question: at what point does a
pointer gain a numeric address?).

[intptrcast]: https://github.com/nikomatsakis/rust-memory-model/issues/30

In any case, I'm not sure just what the right answer is here, but I
like how focusing on something executable makes the issue at hand very
concrete. It also seems like that, as we thread this data through an
actual interpreter, these questions will naturally arise (i.e., "hmm,
we have to create a `Reference` value here, what should we use for the
time-stamp?"), which will help give us confidence that we have
convered the various corner cases.

### Conclusion

The aim of this post is not to make a specific proposal, not yet, but
to try and illustrate further the approach I have in mind for
specifying an executable form of unsafe code guidelines. The key
components are:

- An augmented interpreter that has meta-variables like `WRITES` and `LAST_WRITES`
  that track the set of state.
    - This interpreter will also have additional metadata for Rust values, such as a
      time-stamp for references.
- An augmented compilation that includes assertions that can employ these meta-variables
  at well-defined points:
    - before memory accesses and after function calls seem like likely candidates
    - This compilation might take into account the "safety level" of a function as well
- Using these assertions both to check for undefined behavior and to
  justify optimizations.
  
There is certainly plenty of work to be done. For example, we have to
work out just how to handle "reborrows" (i.e., `&*x` where `x: &T`) --
it seems clear that the resulting reference should get the
"time-stamp" of the one from which it is borrowed.

Going further, the approach we outlined here isn't quite enough to
handle `&mut T`, since there we have to reason about the path by which
memory was reached, and not just the state of the memory itself.  I
imagine though that we might be able to handle this by creating a
fresh id for each mutable borrow. When a memory cell is accessed, we
would track the id of those that did the access, and then when an
`&mut` is used (or the validity of an `&mut` is asserted, in safe
code) we would check that all publicly accessible memory is either
older than the reference or has the proper ID associated with it. Or
something like that, anyway.

(Also, there is a lot of related work in this area, much of which I am
not that familiar
with. [Robert Krebbers's thesis formalizing the C standard][33] is
certainly relevant (I'm happy to say that when I spoke with him at
POPL, he seemed to agree with the overall approach I am advocating
here, though of course we didn't get down to much level of
detail). Projects like [CompCert][] also leap to mind.)

[33]: https://github.com/nikomatsakis/rust-memory-model/issues/33
[CompCert]: http://compcert.inria.fr
