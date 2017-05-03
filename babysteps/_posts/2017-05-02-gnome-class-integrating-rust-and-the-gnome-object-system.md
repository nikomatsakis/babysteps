---
layout: post
title: 'gnome-class: Integrating Rust and the GNOME object system'
categories: [Rust, GNOME]
---

I recently participated in the GNOME / Rust "dev sprint" in Mexico
City. While there I spent some time working on the
[gnome-class plugin](https://github.com/nikomatsakis/gnome-class). The
goal of gnome-class was to make it easy to write GObject
implementations in Rust which would fully interoperate with C code.

Roughly speaking, my goal was that you should be able to write code
that looked and felt like
[Vala code](https://wiki.gnome.org/Projects/Vala), but where the
method bodies (and types, and so forth) are in Rust. The plugin is in
no way done, but I think it's already letting you do some pretty nice
stuff. For example, this little snippet defines a `Counter` class
offering two methods (`add()` and `get()`):

```rust
gobject_gen! {
    class Counter {
        struct CounterPrivate {
            f: Cell<u32>
        }

        fn add(&self, x: u32) -> u32 {
            let private = self.private();
            let v = private.f.get() + x;
            private.f.set(v);
            v
        }

        fn get(&self) -> u32 {
            self.private().f.get()
        }
    }
}
```

You can access these classes from Rust code in a natural way:

```rust
let c = Counter::new();
c.add(2);
c.add(20);
```

[rc]: https://doc.rust-lang.org/std/rc/struct.Rc.html

Under the hood, this is all hooked up to the GNOME runtime. So, for
example, `Counter::new()` translates to a call to `g_object_new()`,
and the `c.add()` calls translate into virtual calls passing through
the GNOME class structure. We also generate `extern "C"` functions so
you should be able to call the various methods from C code.

Let's go through this example bit-by-bit and I'll show you what each
part works. Along the way, we can discuss the GNOME object
model. Finally, we can cover some of the alternative designs that I
considered and discarded, and a few things we could change in Rust to
make everything smoother.

### Mapping between GNOME and Rust ownership

The basic GNOME object model is that every object is ref-counted. In
general, if you are given a `Foo*` pointer, it is assumed you are
*borrowing* that ref, and it you want to store that `Foo*` value
somewhere, you should increment the ref-count for yourself. However,
there are other times when ownership transfer is assumed. (In general,
the GNOME has strong conventions here, which is great.)

I've debating about how best to mirror this in Rust. My current branch
works as follows, using the type `Counter` as an example.

- `Counter` represents an **owned reference** to a `Counter` object.
  This is implicitly heap-allocated and reference-counted, per the
  object model.
  - `Counter` implements `Clone`, which will simply increment the reference
    count but return the same object.
  - `Counter` implements `Drop`, which will decrement the reference count.
  - In terms of its representation, `Counter` is a newtype'd `*mut
    GObject`.
- `&Counter` is used for functions that wish to "borrow" a counter; if
  they want to store a version for themselves, they can call
  `clone()`.
  - Hence the methods like `add()` are `&self` methods.
  - This works more-or-less exactly like passing around an `&Rc<T>` or
    `&Arc<T>` (which, incidentally, is the style I've started using
    all of the time for working with ref-counted data).

Note that since every `Counter` is implicitly ref-counted data, there
isn't much point to working with an `&mut Counter`. That is, you may
have a unique reference to a single handle, but you can't really know
how many aliases are of `Counter` are out there from other sources.
**As a result, when you use `gnome_gen!`, all of the methods and so
forth that you define are always going to be `&self` methods.** In
other words, you will always get a *shared* reference to your data.

Because we have only shared references, the fields in your GNOME
classes are going to be immutable unless you package them up `Cell`
and `RefCell`. This is why the counter type, for example, stores its
count in a field `f: Cell<u32>` -- the `Cell` type allows the counter
to be incremented and decremented even when aliased. It *does* imply
that it would be unsafe to share the `Counter` across multiple threads
at once; but this is roughly the default in GNOME (things cannot be
shared across threads unless they've been designed for that).

### Private data in GNOME

When it comes to data storage, the GNOME object model works a bit
differently than a "traditional" OO language like Java or C++. In
those more traditional languages, an object is laid out with the
vtable first, and then the fields from each class, concatenated in
order:

```
object --> +-------------------+
           | vtable            |
           | ----------------- |
           | superclass fields |
           | ----------------- |
           | subclass fields   |
           +-------------------+
```

The nice thing about this is that the `object` pointer can safely be
used as either a `Superclass` pointer or a `Subclass` pointer.  But
there is a catch. If new fields are added to the superclass, then the
offset of all my subclass fields will change -- this implies that all
code using my object as a `Subclass` has to be recompiled. What's
worse, this is true even if all I wanted to do is to add a **private**
field to the superclass. In other words, adding fields in this scheme
is an **ABI-incompatible change** -- meaning that we have to recompile
all downstream code, even if we know that this compilation cannot
fail.

Therefore, the GNOME model works a bit differently. While you *can*
have fields allocated inline as I described, the recommendation is
instead to use a facility called "private data". With private data,
you define a struct of fields accessible only to your class; these
fields are not stored "inline" in your object at some statically
predicted offset. Instead, when you allocate your object, the GNOME
memory manage will also allocate space for the private data each class
needs, and you can ask (dynamically) for the
offset. ([Appendix A](#appendix-a) goes into details on the actual
memory layout.)

The `gobject_gen!` macro is setup to always use private data in the
recommended fashion. If take another look at the header, we can see
the private data struct for the `Counter` class is defined in the very
beginning, and given the name `CounterPrivate`:

```rust
gobject_gen! {
    class Counter {
        struct CounterPrivate {
            f: Cell<u32>
        }
        
        ...
    }
}
```

In the code, when we want to access the "private" data, we use the
`private()` method. This will return to us a `&CounterPrivate`
reference that we can use. For example, defining the `get()` method on
our counter looks like this:

```rust
fn get(&self) -> u32 {
    self.private().f.get()
}
```

Although the offset of the private data for a particular class is not
known statically, it is still always constant in any given execution.
It's just that it can change from run to run if different versions of
libraries are in use. Therefore, in C code, most classes will inquire
once, during creation time, to find the offset of their private data,
and then store this result in a global variable. The current Rust code
just inquires dynamically every time.

### Object construction

`gobject_gen!` does not expose traditional OO-style
constructors. Instead, you can define a function that produces the
initial values for your private struct -- if you do not provide
anything, then we will use
[the Rust `Default` trait](https://doc.rust-lang.org/std/default/trait.Default.html).

The `Counter` example, in fact, provided no initialization function,
and hence it was using the `Default` trait to initialize the field `f`
to zero.  If we wanted to write this explicitly, we could have added
an `init { }` block. For example, the following variant will initialize
the counter to `22`, not `0`:

```rust
gobject_gen! {
    class Counter {
        struct CounterPrivate {
            f: Cell<u32>
        }

        init {
            CounterPrivate {
                f: Cell::new(22)
            }
        }
        
        ...
    }
}    
```

Note that `init` blocks take no parameters -- at the time when it
executes, the object's memory is still not fully initialized, and
hence we can't safely give access it. (Unlike in Java, we don't
necessarily have a "null" value for all types.)

The general consensus at the design sprint was that the Best Practices
for writing a GNOME object was to avoid a "custom constructor" but
instead to define public properties and have creators specify those
properties at construction time. I did not yet model properties, but
it seems like that would fit nicely with this initialization
setup.There is also a hook that one can define that will execute once
all the "initial set" of properties have been initialized -- I'd like
to expose this too, but didn't get around to it. This would be similar
to `init`, presumably, except that it would give access to a `&self`
pointer.

Similarly, we could extend `gobject_gen!` does not offer is a more
""traditional" OO constructor model, similar to the one that Vala
offers. This too would layer on top of the existing code: so your
`init()` function would run first, to generate the initial values for
the private fields, but then you could come afterwards and update
them, making use of the parameters. (You can model this today just by
defining an `fn initialize(&self)` method, effectively.)

### What still needs work?

So we've seen what does work (or what kind of works, in the case of
subclassing).  What work is left? Lots, it turns out. =)

#### Subclassing

The `gobject_gen!` macro is *intended* to support subclassing other
classes, no matter what language they are defined in. However, that
support is not fully done. I won't go into a lot of detail in this
blog post, because it's already too long, but there are some
interesting constraints here. In particular, the procedural macro must
be able to generate code that permits you to (e.g.) invoke superclass
methods on a subclass instance, but it should be able to do that
without necessarily having access to the list of superclass methods.
I concocted a reasonably nice scheme for this that I *think* will
work, but it requires
[overlapping marker traits](https://github.com/rust-lang/rust/issues/29864),
which
[have been implemented](https://github.com/rust-lang/rust/pull/40097)
but are not yet stable. It probably also requires
[inherent traits](https://internals.rust-lang.org/t/inconvenience-of-using-functions-defined-in-traits-an-ugly-workaround-and-proposed-solution/5166/)
to work well, since otherwise one must import a trait like
`CounterTrait` to get access to the methods of a `Counter` value.

#### Procedural macro support on Rust is young 

There is still a long ways to before the `gnome_gen!` plugin is really
usable. For one thing, it relies on a number of unstable Rust language
features -- not the least of them being the new procedural macro
system. It also inherits one very annoying facet of the current
procedural macros, which is that all source location information is
lost. This means that if you have type errors in your code it just
gives you an error like "somewhere in this usage of the `gnome_gen!`
macro", which is approximately useless since that covers the entire
class definition. This is obviously something we aim to improve
through [PRs like #40939][40939].

[40939]: https://github.com/rust-lang/rust/pull/40939 

#### Private data support could be smoother

I would prefer if you did not have to type `self.private()` to access
private data. I would rather if you could just do `self.f` to get
access to a private field `f`. For that to work, though, we'd need to
have something like the
[fields in traits RFC](https://github.com/rust-lang/rfcs/pull/1546) --
and probably an expanded version that has a few additional features.
In particular, we'd need the ability to map through derefs, or
possibly through custom code; read-only fields would likely help
too. Now that this blog post is done, I plan to post a comment on that
RFC with some observations and try to get it moving again.

#### Interfacing with C

I haven't really implemented this yet, but I wanted to sketch how I
envision that this macro could interface with C code. We already
handle the "Rust" side of this, which is that we generate C-compatible
functions for each method that do the ceorrect dispatch; these follow
the GNOME naming conventions (e.g., `Counter_add()` and
`Counter_get()`). I'd also to have the macro to generate a `.h` file
for you (or perhaps this should be done by a `build.rs` script, I'm
not yet sure), so that you can easily have C code include that `.h`
file and seamlessly use your Rust object.

#### Interfacing with gtk-rs

There has already been a lot of excellent work mirroring the various
GNOME APIs through the [gtk-rs crates](http://gtk-rs.org/). I'm using
some of those APIs already, but we should do some more work to make
the crates more intercompatible.  I'd love it if you easily subclass
existing classes from the GNOME libraries using `gnome_gen!`. It
should be possible to make this work, it'll just take some
coordination.

#### Making it more convenient to work with shared, mutable data

Since all GNOME objects are shared, it becomes very important to have
ergonomic libraries for working with shared, mutable data. The
existing types in the standard library -- `Cell` and `RefCell` -- are
very general but not always the most pleasant to work with.

If nothing else, we could use some convenient types for other
scenarios, such as a `Final<T>` that corresponds to a "write-once"
variable (the name is obviously inspired by final fields in Java,
though ivars is another name commonly used in the parallel programming
community). `Final<T>` would be nice for fields that start out as null
but which are always initialized during construction and then never
changed again. The nice thing would be that `Final<T>` could implement
`Deref` (it would presumably panic if the value has not yet been
assigned).

#### Supporting more of the GNOME object model

There are also many parts of GNOME that we don't model yet.

**Properties** are probably the biggest thing; they are fairly simple conceptually,
but there are lots of knobs and whistles to get right.

We don't support **constructing an object with a list of initial
property values** nor do we support the **post-initialization
hook**. In C code, when constructing a GNOME object, once can use a
var-args style API to supply a bunch of initial values:

```C
g_object_new(TYPE_MEDIA,
             "inventory-id", 42,
             "orig-package", FALSE,
             NULL); 
```

I imagine modeling this in Rust using a builder pattern:

```rust
Media::with()
    .inventory_id(42)
    .orig_package(false)
    .new()
```

We don't support **signals**, which are a kind of message bus system that I don't
really understand very well. =)

### Conclusion

Obviously, this macro is in its early days, but I'm really excited
about its current state nonetheless. I think there is a lot of
potential for GNOME and Rust to have a truly seamless integration, and
I look forward to seeing it come together.

I don't know how much time I'm going to have to devote to hacking on
the macro, but I plan to open up various issues on [the repository]
over the next little while with various ideas for expansions and/or
design questions, so if you're interested in seeing the work proceed,
please get involved!

Finally, I want to take a moment to give a shoutout to jseyfried and
dtolnay, who have done excellent work pushing forward with procedural
macro support in rustc and the `quote!` libraries. Putting
`gobject_gen!` together was really an altogether pleasant
experience. I can't wait to see those APIs evolve more: support for
spans, first and foremost, but proper hygiene would be nice too, since
`gobject_gen!` has to generate various names as part of its mapping.

-----

<a id="appendix-b">

### Appendix A: Memory layout of private data

My understanding is that the private data feature evolved over
time. When the challenges around ABI compatibility were first
discovered, a convention developed of having each object have just a
single "inline" field. Each class would then malloc a separate struct
for its private fields. So you wound up with something like this:

```
object --> +--------------------+
           | vtable             |
           | ------------------ |
           | SuperclassPrivate* | ---> +-------------------+
           | ------------------ |      | superclass fields |
           | SubclassPrivate*   | --+  +-------------------+
           +--------------------+   |
                                    +--> +-----------------+
                                         | subclass fields |
                                         +-----------------+
```

Naturally any class can now add private fields without changing the
offset of others' fields. However, making multiple allocations per
object is inefficient, and it's easy to mess up the manual memory
management involved as well. So the GNOME runtime added the "private"
feature, which allows each class to request that some amount of
additional space be allocated, and provides an API for finding the
offset of that space from the main object. The exact memory layout is
(I presume) not defined, but as I understand it things are currently
laid out with the private data stored at a negative offset:

```
           +--------------------+
           | subclass fields    |
           | ------------------ |
           | superclass fields  |
object --> + ------------------ +
           | vtable             |
           +--------------------+
```

Although no longer necessary, it is also still common to include a
single "inline" field that points to the private data, setup during
initialization time:

```
           +--------------------+ <---+
           | subclass fields    |     |
           | ------------------ | <-+ |
           | superclass fields  |   | |
object --> + ------------------ +   | |
           | vtable             |   | |
           + ------------------ +   | |
           | SuperclassPrivate* | --+ |
           | ------------------ |     |
           | SubclassPrivate*   | ----+
           +--------------------+
```
