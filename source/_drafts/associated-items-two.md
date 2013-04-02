### A fly in the ointment

So, ignoring all the details of the implementation, associated types,
constants and so forth seem like a simple addition to the language
conceptually, at least to me.  However, there is a difficulty.

The closest existing concept in Rust to an associated type is the
so-called "static method", which is really just an associated
function.  An example might be the `FromStr` trait, which provides a
generic interface for converting a string into a value (sort of the
opposite of `ToStr`):

    trait FromStr {
        fn parse(input: &str) -> Self;
    }
    
Using `FromStr`, I can write a generic routine that, for example,
parses a comma-separate list of values:
    
    fn parse_comma_separated<T: FromStr>(input: &str) -> ~[T] {
        let substrings = input.split(",");
        substrings.map(|substring| FromStr::parse(substring))
    }
    
If you look carefully, you will see that the way that we used a static
method is actually rather different from the examples I gave that used
associated items.  The difference lies in the last line, which
actually packs quite a bit of type-inference magic altogether:

    substrings.map(|substring| FromStr::parse(substring))
    
Notice that we invoked `FromStr::parse`---that is, we invoke the
`parse` function as a member of the *trait* `FromStr`, rather than as
a member of the generic type `T`.  In fact, we did not specify
anywhere in this call what type of value `parse()` should produce.
Instead, the compiler could infer that the return type of `parse()`
should be `T`, and so it will invoke the appropriate `parse()` routine
for `T`.

If we were going to write this code in the same fashion as we wrote
the code for associated items above, the connection between `T` and
`parse` would be made explicit, as follows:

    substrings.map(|substring| T::parse(substring))

So where does this mismatch arise? What's happened is that our
treatment of "static" functions actually follows Haskell, which takes
a slightly different tack towards type classes and functional
dependencies.

### Haskell vs object-oriented programming

In traditional object-oriented languages, a method call like `a.b()`
interprets the name `b` relative to the type of the receiver `a`.
Haskell works differently. In Haskell, a "method call" like that would
be written `b(a)` (actually, `b a`, since Haskell does not use
parentheses for function calls), where the name `b` is defined in some
trait (type class, in Haskell terminology).  So in fact what Rust
calls "static" functions are just the only way to do things in
Haskell.

This has some serious advantages: for one thing, it permits greater
type inference. In the traditional OO approach, and in Rust, in order
to understand the meaning of a function call like `a.b()`, one must
know the type of the expression `a`, so that we can figure out what
methods `b` are defined for `a`.  In Haskell, that is not necessary.
In a call like `b(a)`, we know the trait from which `b` derives, and
we can figure out later whether `a` implements that trait, once we
know what the type of `a` is.

This same strength---the lack of ambiguity---can also be a
weakeness. It is often very natural to interpret names relative to the
method receiver. The classic example is that I have two types both of
which define a method `draw()`:

    trait Shape {
        fn draw(&self, canvas: &Canvas); // a picture
    }
    
    trait Cowboy {
        fn draw(&self); // a gun
    }

Now in Rust I might write some code like:

    fn gun_duel(
        canvas: &Canvas,
        good_guy: &Character,
        bad_guy: &Character)
    {
        // Draw the guns, then redraw the shape on to the canvas:
        good_guy.draw();
        bad_guy.draw();
        good_guy.shape.draw(canvas);
        bad_guy.shape.draw(canvas);
    }

In Haskell, I would have to give either these two methods distinct
names, or import them "qualified", meaning that I would write
the equivalent of something like this:


    fn gun_duel(
        canvas: &Canvas,
        good_guy: &Character,
        bad_guy: &Character)
    {
        // Draw the guns, then redraw the shape on to the canvas:
        good_guy.Shape::draw();
        bad_guy.Shape::draw();
        good_guy.shape.Cowboy::draw(canvas);
        bad_guy.shape.Cowboy::draw(canvas);
    }

Here I specified explicitly what trait the `draw()` method derived
from in each case.

Of course, in this example, we did not attempt to implement both
`Shape` and `Cowboy` for the same type.  If we were to do so, then the
something like `obj.draw()` would be ambiguous using the
object-oriented conventions. So you do require a way to disambiguate.
That is, the Haskell-like syntax (`object.Trait::Draw()`) becomes a
kind of explicit fallback. (Actually, this is precisely the reason
that Rust requires you to `use` a trait before you can call methods
from that trait, so that you can define the set of traits whose
methods are "in scope" to avoid collisions like this).

### Ok, enough about methods, what about types?

So, in Haskell, an associated type is actually a "higher-kinded" type,
which roughly means "a type that takes type parameters".  So where C++
programmers would write `G::Node` to mean "the `Node` type associated
with the graph `G`", Haskell programmers would write (the equivalent
of) `Graph::Node<G>`.  I suppose that there is no reason that we could
not support a similar notation in Rust. For example, to reference the
`dims` constant in a vector as I showed before would be something like
`Vector::dims::<V>` (rather than `V::dims`). Here the `::` before the
type parameters is required because `Vector::dims` is part of an
expression, and type parameters in expressions are prefixed with `::`
so as to make parsing unambiguous.  Naturally one could `use` both
`Node` and `dims` to make this shorter (`Node<G>` and `dims::<V>`
respectively).

#### Multi-parameter type classes

However, there is an...oddity with this approach.  The examples I have
given were all single-parameter traits.  Let's consider a
multi-parameter trait, like `Add` (defined with an associated
function):


    Graph::<for G>::Node

    trait Add<Rhs, Sum> {
        fn add(lhs: &Self, rhs: &Rhs) -> Sum;
    }

#### An alternative syntax


### Summary of the two approaches

Here is a brief summary of the syntax that the two approaches would
yield.  I'll begin with the common case, where there are no
conflicting names in scope.  To be fair to both approaches, I'll
assume here that the user has imported all trait names so as keep
things as pretty as possible.

    // Reference an associated type
    G::Node                Node<G>
    
    // Reference an associated constant
    V::dims                dims::<V>
    
    // Reference an associated function
    T::parse(s)            parse(s)

Now, imagine that there are conflicts.  For example, perhaps there are
multiple traits defining each of these associated items.  In that
case, the user would have to be more explicit, which might look as
follows:

    // Reference an associated type
    G::(Graph::Node)       Graph::Node<G>
    
    // Reference an associated constant
    V::(Vector::dims)      Vector::dims::<V>
    
    // Reference an associated function
    T::parse(s)            FromStr::parse(s)

Finally, let us assume that there is some sort of type inference
failure and we wish to specify every type as explicitly as possible.
Then the snippets might look like:

    // Reference an associated type
    G::(Graph::<...>::Node)       Graph::<...>::Node<G>
    
    // Reference an associated constant
    V::(Vector::<...>::dims)      Vector::dims::<V>
    
    // Reference an associated function
    T::parse(s)            FromStr::parse(s)

### So what should we do?

If this decision were up to me, and there were no other factors
besides personal taste, I would prefer the C++-style syntax.  I like
how Rust has embraced Haskell type classes but made them "feel"
object-oriented, and I find this to be a natural extension.  Plus it
means that access to "associated items" of types and method lookup
follows precisely the same algorithm, which appeals to me.

However there are other factors.  For one thing, not everyone shares
my taste.  For another, we'd like to stabilize the language, so
changes that are not backwards compatible (like changing how we invoke
static functions) are frowned upon without good justification.

It seems to me that our current approach where we take a hybrid of
Haskell's lexically-derived binding and the type-derived binding of
object-oriented languages is not the best option.  We fail to get the
total clarity of Haskell, but we also fail to get the very natural
notation that OO offers (such as `G::Node`).

However, Haskell programmers are very fond of inferred return types,
and the C++-like notation gives those up.  I don't consider this a big
loss (in fact, I find the inferred return types a bit magical in
practice and often write them out explicitly), but I recognize that
opinions will differ on this point. Still, Rust has generally erred on
the side of being a bit more explicit (for example, specifying the
signatures of functions) and I do find it makes the code more readable
overall.

### End-note: Haskell and functional dependencies

In addition to associated types, Haskell also offers a feature called
functional dependencies, which is basically another, independently
developed, means of solving this same problem.  The idea of a
functional dependency is that you can define when some type parameters
of a trait are determined by others.  So, if we were to adapt
functional dependencies in their full generality to Rust syntax, we
might write out graph example as something like this:

    trait Graph<N, E> {
        Self -> N; // functional dependency
        Self -> E
        ...
    }
    
The line `Self -> N` states that, given the type of `Self`, you can
determine the type `N` (and likewise for `E`).  You can see that
associated types can be translated to functional dependencies in a
quite straightforward fashion.

When functional dependencies have been declared, it implies that there
is no need to specify the values of all the type parameters.  For
example, it would be legal to to write our `depth_first_search`
routine without specifying the type parameter `E` on `Graph`:

    fn depth_first_search<N, G: Graph<N>>(
        graph: &mut Graph,
        start_node: &N) -> ~[N]
    {
        /* same as before */
    }

The reason that we do not have to specify `E` is because (1) we do not
use it and (2) it is fully determined by the type `G` anyhow, so there
is no ambiguity here.  In other words, there can't be multiple
implementations of `Graph` that have the same self type but different
edge types.

Functional dependencies are more general than associated types.  They
allow you to say a number of other things that you could never write
with an associated type, for example:

    trait Graph<N, E> {
        N -> E;
        ...
    }

This trait declaration says that, if you know the type of the nodes
`N`, then you know the type of the edges `E`.  However, knowing the
type `Self` isn't enough to tell you either of them.  I don't know of
any examples where expressiveness like this is useful, however.
        
### End-end-note: "where" clauses
        
