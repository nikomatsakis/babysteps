---
categories:
- Rust
- Traits
comments: true
date: "2012-04-09T00:00:00Z"
slug: rusts-object-system
title: Rust's object system
---

On the `rust-dev` mailing list, someone pointed out another
["BitC retrospective" post by Jonathon Shapiro concerning typeclasses][post].
The Rust object system provides interesting solutions to some of the
problems he raises.  We also manage to combine traditional
class-oriented OOP with Haskell's type classes in a way that feels
seamless to me. I thought I would describe the object system as I see
it in a post.  However, it turns out that this will take me far too
long to fit into a single blog post, so I'm going to do a series.
This first one just describes the basics.

One caveat: I *think* that these techniques are novel, at least in
some parts. However, I am not well-versed in the Haskell literature
and it's possible that the techniques we aim to implement have been
explored already.  If so, I'd appreciate it if someone would point me
in the right direction!  There are some links in his post that I
haven't read, for example, but I will definitely put them on my
reading list.

**EDIT**: It's a bit unclear what I precisely think is novel.  In
fact, when I wrote the previous paragraph, I was referring to our
proposed technique for enforcing instance coherence.  However, I
didn't even describe this problem in this post, because I realized
there was a lot of background to cover.  So, to be clear, I don't
think that the basics in this post are terribly novel---with the
exception of our use of the same interfaces to unify Haskell-style
type-classes (or C++ concepts, if you prefer) with OOP-style
existential (sub)typing.  That particular part works out quite well, I
think.

[post]: http://www.bitc-lang.org/pipermail/bitc-dev/2012-April/003315.html

### The building block: ifaces

The fundamental building block of Rust's OOP system is the `iface`
(interface).  As in Java and other languages, an iface is just a set
of methods without implementations.  Let's use the example of a
`hashable` value, which might be suitable for use as the key in a
hashtable:

    iface hashable {
        fn hash() -> uint;
        fn eq(t: self) -> bool;
    }
    
This interface provides two methods.  The first, `hash()`, computes a
hash of the value and the second compares for equality.  You see that
an iface can use the special type `self`.  The type `self` means "the
same type as the receiver".  A later post will demonstrate that this
type---while extremely useful!---introduces some complications.

### Classes

Classes are like a pared down version of the classes you will find in
other languages. As in C++, they have fields, methods, constructors
and an optional destructor.  However, they do not inherit from one
another (we will see how to do polymorphism in a bit).  You can define
a class like so:

    class a_class {
        let x: int, y: uint;
        
        new(x: int, y: uint) {
            self.x = x;
            self.y = y;
        }
        
        fn get_x() -> int { self.x }
    }
    
The precise syntax will probably change (I am not fond of the
definition of constructors, in particular), but the basic idea will
remain the same: a class combines a set of fields with various
methods.  Members can be defined as private or public with the usual,
C++- or Java-like definition.  Fields can be immutable (the default)
or mutable (`let mut x: int`).

### Polymorphism using classes and ifaces

There is no subtyping between classes.  However, sometimes you would
like to have a routine that operates on multiple types.  The canonical
example is to have an interface for "drawable" things like:

    iface draw {
        fn draw(gfx: graphics_context);
    }

Along with various drawable shapes like:

    class square { fn draw(gfx: graphics_context) { ... } }
    class circle { fn draw(gfx: graphics_context) { ... } }
    ...

Rust then offers you two ways to work with these drawable things.  The
first, interface types, is more like C++ or Java.  The second, bounded
type parameters, is more like Haskell's type classes.  As we will see,
each technique is useful for different scenarios.

#### Interface types

As in Java, an interface like `draw` also has a corresponding type
(simply written as `draw`).  In fact, it has a family of types
(`draw@`, `draw~`, `draw&`, and `draw`) just as with function
pointers, but for now there is no need to get into the full details.
The type `draw` will suffice.

The type `draw` means "some value which implements the drawable
interface".  We can use the `draw` type to write a function which
takes a vector of drawable things and draws them all:

    fn draw_all(gfx: graphics_context, drawables: [draw]) {
        for drawables.each {|drawable|
            drawable.draw(gfx)
        }
    }

This looks pretty close to Java or C++.  However, what happens at
runtime is somewhat different in some pretty important ways.  For one
thing, the `draw` type in Rust is represented as the pair of a pointer
to the instance data along with a [vtable][vt].  Invoking the `draw`
method, therefore, is simply a matter of extracting the function
pointer from the vtable and invoking it with the instance data as the
(implicit) first argument.

[vt]: http://en.wikipedia.org/wiki/Virtual_method_table

This representation is somewhat different from Java or C++, both of
which would have a single pointer to the object and would embed the
vtable in the object itself.  There are a variety of reasons that we
take a different approach which I will cover later.

The reason I am talking about how `draw` instances are represented at
runtime is that it is not the same as the way that a `@circle`
instance (for example) is represented.  The type `@circle` is just a
pointer to the a block of memory containing the fields for the class
circle.  There is only a single pointer and there is no vtable.  So we
cannot simply interpret the type `@circle` as a `draw` instance
without doing some conversion.

In Rust, this conversion is accomplished by casting the `@circle`
instance to the `draw` type.  So, an example of using the `draw_all`
method might look like:

    fn draw_a_square_and_a_circle(gfx: graphics_context) {
        let s = @square(...);
        let c = @circle(...);
        let objs = [s as draw, c as draw];
        draw_all(gfx, objs);
    }

Here you can see that to construct the vector of drawables, we first
casted `s` and `c` to the type `draw`.  This cast constructs the pair
of the `s` and `c` pointers along with the appropriate vtable (in the
first case, one for `square`, in the second case, one for `circle`).

##### Why is it designed this way?

There are a variety of reasons that we took a different approach from
that used in Java or C++.  First, we wished to preserve the nice
quality of C++ that all virtual calls are implemented using simple
vtables: this is an efficient technique with reliable performance.  In
Java, in contrast, the precise implementation of interface calls can
vary.  Of course the JIT is able to generally produce efficient code
(typically using [PICs][pic] or similar things) but we want to be able
to statically compile Rust without the need for just-in-time
techniques.

[pic]: http://en.wikipedia.org/wiki/Inline_caching

However, we also did not want to require that classes be pre-declared
as "implementing" a particular interface (or, in the case of C++,
extending the given abstract class).  In C++, the subtyping
relationship is used to guide the construction and layout of the
vtables (and, in some cases, multiple such vtables may be needed,
meaning that there is no unique pointer to the object data itself).
Without having that pre-declared relationship, we cannot pre-compute
the vtable(s) for an object in advance.

Therefore, we instead wait and lazilly construct the vtable at the
point of the cast (actually, there will be one vtable for each
class-iface pair that appears within a crate).  By representing the
`draw` instance as the pair of the instance data with the vtable, we
can easily have one class instances associated with any number of
vtables.

#### Type classes

There are two fundamental approaches to writing polymorphic functions
(in general, not just for interface types).  The Java and C++
technique, which we illustrated in the previous section, is to use
subtyping.  Another approach, pioneered in functional languages
(though it is also available in OOP languages) is to use parametric
(or "generic") functions.  For example, we could write a function
`draw_many` like so:

    fn draw_many<D:draw>(gfx: graphics_context, drawables: [D]) {
        for drawables.each {|drawable|
            drawable.draw(gfx)
        }
    }
    
`draw_many()` looks very similar to `draw_all`.  It declares a type
parameters `D` and says that the type `D` must implement the `draw`
iface.  This `draw` interface is called the *bound* of the type
parameter `D`, because it bounds (or "puts a limit") on what types can
be used for `D`: they must be types for which the interface `draw` is
available. It then takes a vector of `D` instances and iterates over
its contents, invoking the `draw()` method on each value.

There is in fact a subtle different between `draw_all()` and
`draw_many()`.  `draw_all()` took a vector of type `[draw]`: this
means that each entry in the vector may in fact correspond to a
distinct kind of drawable thing.  For example, the vector might have a
square and a circle, as we saw.  `draw_many()`, in contast, takes a
vector of type `[D]`.  This means that the type `D` could be a square
(which is drawable) or it could be a circle (which is also drawable),
but you cannot have a vector containing both a square *and* a circle.

To see more closely why this is, consider that at runtime we implement
generic functions like `draw_many()` by following the C++ approach:
that is, we duplicate the function for each type that it is used with.
Therefore, we can easily create a version of `draw_many()` for
squares by substituting `square` for each use of the type `D`:

    fn draw_many<square>(gfx: graphics_context, drawables: [square]) {
        for drawables.each {|drawable|
            drawable.draw(gfx)
        }
    }
    
We can also create a similar one for circles, but there is no type
(other than `draw`) that we could use to create a version that accepts
a vector containing *both* circles and squares.  In fact, there can be
no such vector: all vectors must contain instances of a single type.

Using the type-class style of implementation is generally more
efficient than the traditional OOP-style, because it produces no
vtables at all (but it does produce more code, which has its own
inefficiencies).  This efficiency comes at the price of less
flexibility, because the style cannot deal with heterogeneous
collections.

Actually, this is not strictly true: it is (usually) allowed to
instantiate the type `D` with an iface type, so we could still invoke
`draw_many()` with a vector of draw instances, just as we did with
`draw_all()`.  This would be equally (in)efficient as the OOP version,
because all method calls would still go through a vtable.

#### Code reuse via traits

Inheritance is often used as a means of achieving code reuse in OOP
languages.  While it can be convenient, this is generally regarded as
unfortunate, because it ties together the sub*typing* relationship
with details about code reuse.  A more modern approach is to make use
of traits.  Rust offers traits but I won't go into detail here.  In
effect, traits allow you to factor out common method implementations
in a much more flexible way than inheritance, without introducing the
complications of traditional multiple inheritance.

### Impls

So far, the only way to define a value with a method is to define a
class and include the method in the class definition.  This is too
limiting, however, in two ways.  First, sometimes we want to define
methods outside the class body---for example, to extend a class
defined in one crate or module from somewhere else.  Second, not all
types in Rust are classes (for example, ints and vectors) and we don't
want them to be, for efficiency reasons and C compatibility.

To address these two needs we allow you to define methods for a given
type using the keyword `impl`.  For example, suppose we want to add a
method `bounds()` that computes a bounding rectangle for a shape.  You
might do something like this:

    impl bounds for square {
        fn bounds() -> rect;
    }

Here the syntax `impl N for T` defines a suite of methods named `N`
for the type `T`.  You can also associate an `impl` with an `iface`
like so:

    iface bounds {
        fn bounds() -> rect;
    }
    
    impl of bounds for square {
        fn bounds() -> rect;
    }

In this case, the name of the method suite is (by default) the name of
the iface.  The full syntax is `impl N of I for T`.

Using an `impl`, we can generalize interfaces to apply to arbitrary
types.  For example, we could implement the `draw` interface for a
`uint` (whatever that means):

    impl of draw for uint {
        fn draw(gfx: graphics_context) { ... }
    }
    
Then a `[uint]` could be passed to `draw_many()`.  Similarly, we could
cast a `uint` to `draw`.

#### Scoping of impls

In order to make use of the methods in an `impl`, you must bring the
`impl` into scope using an import statement.  This is where the impl
name comes into play.  So, to use the `bounds` method from another
module, I must include something like:

    import B::bounds;
    
where `B` is the module containing the `impl` declarations.  The same
visibility rules apply when trying to cast a type to an iface or use
the type as the value for a bounded generic type parameter.

### Mismatches

To some extent, the class and impl system were independently designed,
and there are a few mismatches (mostly in code that has not been fully
implemented).  The main one is that interfaces are duck-typed (not
declared) and impls declared when they implement an iface.  We will
align these to be the same (for the moment, probably initially by
adding the ability to declare an interface when you declare a class).
