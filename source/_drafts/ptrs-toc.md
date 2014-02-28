One of the hot topics we are trying to nail down in Rust right now is
support for user-defined pointers. In the early design, we attempted
to define builtin types for the most common patterns we saw in
practice: ownership (`~`), temporary borrows (`&`), and garbage
collection (`@`). As we gain more experience with Rust, though, we've
found that ownership and temporary borrows are flexible enough to
accommodate a great many use cases. Moreover, there are a number of
other use cases that we didn't initially consider:

1. Cross-thread sharing of immutable data (the [ARC][ARC] type).
2. Reference counting, which is sometimes preferable to tracing
   garbage collection since it provides more predictability and a
   simple story for interacting with C code (the [Rc][Rc] type).
3. Interaction with existing memory management schemes, such as
   Objective C reference counting or the SpiderMonkey garbage collector.
4. Arena allocation (the [Arena][arena] type; see also #[10444][10444]).

Finally, one of the first questions people ask when presented with the
design of Rust it is possible to write types that are generic with
respect to the kind of pointer that they employ. As a concrete
example, it'd be nice to be able to write a persistent collection type
that can be used with either reference counted, garbage collected, or
atomically reference counted pointers.

For these reasons and more, we have for some time now been planning a
move towards user-defined pointer types, commonly called "smart
pointers" in a nod towards C++ (which, as is so often the case, points
the way towards solid extensible design). This argument was
[first elucidated][gc] by pcwalton; this introduction has been my own
summary and elaboration on his post.

The basic idea is to retain `~T` and `&T` as the only built-in pointer
types. The `@T` type will be renamed to `GC<T>` and moved into a
library (albeit a rather privileged one; more on this later). We will
extend the language operators that have to do with pointers so that
they can be used with *any* kind of pointer, including builtin types
like `~T`, standard library types like `GC<T>`, and completely foreign
types defined by end users.

As far as I know, the plan has never been written out in more detail.
I want to draft a series of posts laying out how I think this can work.
Here is a rough summary of the various bits and pieces:

1. **Extensible deref operator:** make it possible for smart pointer
   types to override what `*` means and to link into the general
   autoderef mechanism.
2. **Extensible allocation:** make a general `new` operator that will
   be used for all allocation. The syntax `new(alloc) expr` will
   permit users to specify a custom allocator `alloc`, which may
   produce a smart pointer.
   - **Higher-kinded Rust:** properly handling `new` seems to require
     support for higher-kinded Rust.
3. **Objects and DST:** discussion about objects and why DST is really
   necessary to handle them nicely.
  

1. Extensible operators:
   - add an extensible `new` that will be used for all memory allocation;
   - add a way for users to overload deref (`*`).
2. 

I plan to write a couple of posts elaborating a concrete plan in this
direction.

<!-- more -->

### Extensible operators

Despite the existence of a number of pointer-like types (e.g.,
`ARC<T>`, `Rc<T>`, etc), Rust itself has relatively little support for
custom pointers. This means that types like `Rc` cannot take advantage
of standard operators and must use custom methods instead:

    let x: Rc<int> = Rc::new(5); // no standard creation mechanism
    let y: &int = x.borrow();    // no way to dereference
    
Compare that pattern to the equivalent using a built-in type like `~`:

    let x: ~int = ~5;
    let y: &int = &*x;
    
    
    
The next few posts will be unveiling a mostly complete proposal that enables
users to write code like the following:

    let x: Rc<int> = new(Rc) 5;
    let y: &int = &*x;
    



there is no standard way to allocate
a new `RC<T>`

The current thinking is to retain `~T` and `&T` as built-in pointer
types. The `@T` type will be renamed to `GC<T>` and moved into a
library; it is likely though that this `GC` library will be rather
privileged, in that the compiler will generate special hooks to enable
identifying roots on the stack as well as write guards. What this means
is that it is not 
tracing and moving collector.

[gc]: http://pcwalton.github.io/blog/2013/06/02/removing-garbage-collection-from-the-rust-language/
[ARC]: https://github.com/mozilla/rust/blob/master/src/libextra/arc.rs
[RC]: https://github.com/mozilla/rust/blob/master/src/libstd/rc.rs
[arena]: https://github.com/mozilla/rust/blob/master/src/libextra/arena.rs
[10444]: https://github.com/mozilla/rust/issues/10444

