---
layout: post
title: "Destructors and finalizers in Rust"
date: 2013-01-17T09:45:00Z
comments: true
categories: [Rust]
---
Rust features destructors and, as of this moment, they are simply not
sound with respect to many other features of the language, such as
borrowed and managed pointers.  The problem is that destructors are
granted unlimited access to arbitrary data, but the type system and
runtime do not take that into account.  I propose to fix this by
limiting destructors to *owned* types, meaning types that don't contain
borrowed or managed pointers.

<!-- more -->

### Dangers today

The root of our problems lies in the fact that if you have a struct
type `S` that has a destructor, it is legal to place an instance of
`S` into a managed box (`@S`).  This is problematic because it implies
that the destructor will run when the managed box is collected, which
can occur at any arbitrary time (in fact, if the garbage collector
were to run on a different thread, it could even occur in parallel
with the owning thread!).  I will use the term [finalizer][finalizer]
to mean a destructor associated with an object that is owned by a
managed box.  In other words, a destructor that can run asynchronously
with respect to the main program.

Note: Many of the thoughts in this post were inspired by Hans Boehm.
For those seeking a deeper undestanding, I recommend his paper
["Destructors, Finalizers, and Synchronization"][boehm].

#### Problem number one: finalizers and borrowed pointers

In our current system, there is nothing to prevent a borrowed pointer
from being stored in a managed box.  Although it is sometimes
surprising to people that it is legal, this scenario is generally
harmless.  Although the managed box may outlive the data that the
borrowed pointer references, the type system will guarantee that the
managed box will never be *dereferenced* once the loan expires.  In
other words, you can put a pointer into your stack frame into a
managed box, but you could never return that managed box to your
caller or store it into any data structure that outlives your stack
frame.  So we know for certain that *if we were to run the garbage
collector, that box would be collected*.  Finalizers change this
equation.  A finalizer provides a backdoor that would allow borrowed
pointers in managed boxes to be dereferenced.  See [issue 3167][3167] for
examples of dangerous programs and more details.

The only way I can see to address this unsoundness is to create a new
intrinsic trait that indicates when data can safely be placed into a
managed box.  I have some thoughts on this at the end.

#### Problem number two: finalizers and managed data

There is another dangerous situation that can arise which has nothing
to do with borrowed pointers.  Imagine we have a cycle of managed data
and two objects on that cycle have a finalizer.  Which finalizer do
you run first?  Normally, you want to finalize an object X before you
finalize any object Y that X references, but because there is a cycle
that is impossible to guarantee.  Different systems have solved this
problem in different ways, none of which are wholly satisfactory.  

#### Problem number three: finalizers and mutable state

Another more subtle problem which can occur with finalizers is that
the finalizer may have access to mutable state which is not yet dead.
Imagine, for example, a struct whose job is to increment and decrement
a counter automatically:

    struct SomeDataStructure { value: uint, ... }
    
    struct Counter { s: @mut SomeDataStructure }
    impl Counter: Drop {
        fn new(s: @mut SomeDataStructure) -> Counter {
            s.value += 1;
            Counter { s: s }
        }
        fn drop(self) { self.s.value -= 1; }
    }
    
As long as this counter is stored on the stack frame, everything
should be fine.  But if you were to place this counter into a managed
box, suddenly you have a ticking time bomb: now the field `s.value`
will be decremented at some random time, whenever the garbage
collector elects to collect this managed box.  Even if the garbage
collector does not run in parallel with the mutator thread, this can
essentially cause `s.value` to be decremented in between virtually any
statement, leading to race conditions that are very similar to those
problems you face with threads and mutable state.  Note that due to
compiler optimizations and so forth it is entirely possible for value
to be decremented earlier than you might expect as well as later.

Of all the problems, I am perhaps most worried about this one, because
it is relatively easy to overlook.  It's not a soundness issue per se
but it can lead to very surprising bugs, particularly in light of
aggressive compiler optimization.  Hans Boehm goes so far as to say
that finalizes *require* a multithreaded, shared memory context to
make any sense, precisely because of Problem #3.  Basically, the
asynchrony inherent in finalizers is more natural in a parallel
language and you have tools like locks to defend against it.  If
finalizers run in the mutator thread, locks lead to deadlocks and not
having locks leads to bugs.

You might think that moving data into a managed box can only cause the
destructor to be delayed from when it would otherwise run, but this is
not the case.  In fact the destructor can also run much *earlier* than
you might expect.  Consider this Java program from Boehm's paper:

    class X {
        Y mine;
        public foo() { Mine m = mine; ...; m.bar(); }
        public void finalize() { mine.baz(); }
    }
    
Here, in the `foo()` method, the `this` pointer may actually be dead
right after the first statement, and so `this` can be collected before
`m.bar()` is called.  Boehm's point with this example is that, in
Java, this could result in `m.bar()` and `mine.baz()` executing in
parallel, but in general the behavior is very surprising.  I recall
that similar problems were prevalent with Apple's failed attempt at an
Objective-C garbage collector.

### Restricting to owned data

All of these problems are solved by limiting destructors to types
which contain only owned data.  Borrowed pointers and managed pointers
are disallowed, so problems one and two cannot arise. Problem three
cannot arise because there is no way for the destructor to directly
access shared, mutable state.

Limiting to owned data still permits many interesting use cases for
destructors. You can embed a file descriptor and guarantee it gets
closed.  You can ensure that random C resources, such as database
descriptors or blocks of memory obtained from `malloc()`, are cleaned
up, since these are typically described by unsafe pointers anyhow.
You can also embed a channel and use it to send messages from the
destructor.

There is one very useful scenario that is ruled out, however, which is
basically the "auto counter" (or any "auto adjustment") type from
problem number three.  That is, it is often very useful to have some
adjustment that will automatically occur when a stack frame exits, and
destructors are one common way to achieve that.  Of course this is
dangerous if abused, as we have seen, but what about the good guys,
who *don't* put an auto-object into managed data?

The good news is that even with the limitation I propose there are
still two valid ways to achieve the auto-pattern, depending on your
precise needs.  First, if you don't care whether the auto code
executes on failure---and you probably don't, remember that Rust
failures are unrecoverable---you can just use a function with a
closure argument:

    fn auto_adjust<R>(s: @mut SomeDataStructure, f: &fn() -> R) -> R{
        s.value += 1;
        let v = f();
        s.value -= 1;
        return v;
    }

Now in your code you can write:

    do auto_adjust(s) { ... }
    
But what if you really *do* care about failure *and* you need access
to the current stack frame when unwinding?  We should be able to
provide a function in the standard library to handle this case.  That
function would look something like:

    do defer(|| {
        /* This code will execute once the block below exits, even on failure */
    }) {
        /* This code executes immediately */
    }

Naturally we can play around with the precise signature of this
function a bit, but you get the idea: you supply two closures to a
library function, it executes them as appropriate.  Internally, the
function would use unsafe pointers and a destructor, but it would
never expose the object that carries the destructor to the outside,
and thus could ensure that this object is never placed into a managed
box.

### Caveat: Not quite future proof

In some sense, I am advocating the conservative approach: we begin
with a narrow set of types that can have a destructor, and we can then
expand later if that proves to be insufficient. However, there is a
catch.  If we ever wanted to permit borrowed pointers to be referenced
by destructors, the only way that this can be made sound is to limit
the set of types that can be placed into a managed box.  Since, at the
moment, any type can be placed into a managed box, this is a backwards
incompatible change.  To see what I mean, consider a function like
`box()`:

    fn box<A>(a: A) -> @A { @a }
    
This function is legal today, but it would become illegal.  This is because
there is no guarantee that `A` can be placed into a managed box.  So you'd
need to write something like:

    fn box<A:Manageable>(a: A) -> @A { @a }
    
where `Manageable` is the hypothetical intrinsic trait that
characterizes types that can safely be placed into managed boxes.  Of
course we could change the defaults, so that `<A>` no longer means
"any type at all" but rather "the usual set of types you want to do
the usual set of operations" (in which case, perhaps `A:` would mean
"any type at all", I don't know).  But that too is backwards
incompatible.

[boehm]: http://www.hpl.hp.com/techreports/2002/HPL-2002-335.html
[finalizer]: http://en.wikipedia.org/wiki/Finalizer
[3167]: https://github.com/mozilla/rust/issues/3167
