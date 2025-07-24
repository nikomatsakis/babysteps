---
layout: post
title: "Associated items"
date: 2013-04-02T14:21:00Z
comments: true
categories: [Rust]
---
I've been doing a lot of thinking about Rust's trait system lately.
The current system is a bit uneven: it offers a lot of power, but the
implementation is inconsistent and incomplete, and in some cases we
haven't thought hard enough about precisely what should be allowed and
what should not.  I'm going to write a series of posts looking at
various aspects of the trait system and trying to suss out what we
should be doing in each case. In particular I want to be sure that our
trait design is *forwards compatible*: that is, I expect that we will
defer final decisions about various aspects of the trait system until
after 1.0, but we should look now and try to anticipate any future
difficulties we may encounter.

As the inaugural post in this series, I want to take a look at
*associated items* (e.g., associated types, constants, functions,
etc).  Associated items are requested often, though under various
names.  When I first started this post, it was actually part of a
larger post, but I quickly found that the topic of associated items
was too large to be a footnote of another post.  In fact, I'm finding
it's too large to fit into one post at all.  So I'll be breaking this
post up until multiple pieces.  This first post will cover what an
associated item *is* and what you might want to use it for, and it
will do so from a C++ perspective.

**I will also propose some changes to how we handle so-called "static"
fns (which I will be calling "associated" functions, because the name
"static" gives all the wrong connotations).** These changes are not
backwards compatible.  I do not take such an idea lightly; we are
trying very hard to stabilize Rust so such changes must pass a high
bar (I personally think the change would be worth it, but opinions
will vary).  In the next post, I will present the Haskell approach to
associated items, which is closer to what we have today and which can
be adapted in a mostly backwards-compatible fashion.

<!-- more -->

Associated items sound like some kind of crazy language extension, but
they're actually pretty straight-forward and natural.  They are used
very frequently both in C++ and Haskell, as well as other languages.
To get an idea what you might want one for, imagine you were going to
design a generic graph library, and you want to implement some
algorithms that operate over any sort of graph.

You might begin with defining a generic graph trait that defines
the interface your algorithms will expect to manipulate the graph:

    trait Graph<Node> {
        fn get_visited(&self, n: &Node) -> bool;
        fn set_visited(&mut self, n: &Node);
        fn get_successors(&self, n: &Node) -> ~[Node];
        ...
    }

The details are not too important but you get the idea.  Now, we might
implement a function like `depth_first_search`, which executes a depth
first search and returns the nodes we visited in order:
    
    fn depth_first_search<N, G: Graph<N>>(
        graph: &mut Graph,
        start_node: &N) -> ~[N]
    {
        let mut nodes = ~[];
        let mut stack = ~[start_node];
        while !stack.is_empty() {
            let node = stack.pop();
            if graph.get_visited(node) {
                loop; // already visited
            }
            graph.set_visited(node);
            nodes.push(node);
            stack.push_all(graph.get_successors(node));
        }
        return nodes;
    }

Notice that `depth_first_search` takes two type parameters, `N` and
`G`, where `N` is the type of the nodes used by the graph `G`.  If you
think about it, this is a bit odd, because these two type parameters
are not really independent.  Typically, when one implements a graph,
you implement it for a specific kind of node, and only that kind of
node.  Now, so long as the `Graph` trait is only parameterized by the
type of the nodes, this is not so bad, but in practice a real graph
library will grow a number of similar type parameters. For example, we
might want the type of the edges, which would give us two type parameters:

    trait Graph<Node, Edge> {
        ...
    }
    
    fn depth_first_search<N, E, G: Graph<N, E>>(
        graph: &mut Graph,
        start_node: &N) -> ~[N]
    {
        ...
    }
    
Already you can see that our signatures are getting complicated.
There is another problem as well: even though `depth_first_search`
does not need to consider edges, after all we saw the implementation
before and it only needed the type `N`, we must include the edge type
`E` in the signature.

Now imagine that we want to make an efficient graph type.  It is
likely that we can use a specialized type to represent a set of edges
or nodes; a bitset, for example.  In that case, we would want a third
and maybe even a fourth type parameter (`NodeSet` or `EdgeSet`).  The
list just keeps growing.  And for each such type parameter, we will
have to extend the signature of `depth_first_search` along with every
generic function that is implemented over our graph.  This is not only
unwieldy, it's a refactoring hazard that will limit the ability of
people to write generic libraries.

### Enter associated types

C++ had a similar problem in the design of the STL.  Because C++
traits are basically just macros, however, clever C++ programmers were
able to come up with a useful pattern that avoids all these hazards (I
probably have my history wrong here, no doubt C++ programmers adapted
a solution first used in other languages, perhaps without even knowing
it, but it reads better this way, doesn't it?).  Instead of defining
the trait `Graph` as being parameterized over the node type `Node`,
define the node type `Node` as an "associated type":

    trait Graph {
        type Node; // associated type
        
        fn get_visited(&self, n: &N) -> bool;
        fn set_visited(&mut self, n: &N);
        fn get_successors(&self, n: &N) -> ~[N];
        ...
    }

Notice that the definition of `Node` has moved *inside* the trait.
The meaning of this is that any given `Graph` implementation will
define a type `Node` that represents nodes.  That is, rather than
`Node` being a "input" to the trait, it is an "output", just like the
functions `get_visited()` etc are "outputs".

Now we can adapt our `depth_first_search` routine as follows:
    
    fn depth_first_search<G: Graph>(
        graph: &mut Graph,
        start_node: &G::Node) -> ~[G::N]
    {
        /* same as before */
    }
    
Note that `depth_first_search` only takes one type parameter, the
graph type `G`.  The type of the node is then relative to `G` (so
`G::Node` would be "the node type used by the graph type `G`").

Interestingly, I can now add as many associated types to `Graph` as I
like without affecting the signature of `depth_first_search` in the
slightest.

### Associated constants

It is not hard to imagine extending this idea to other kinds of
associated members.  For example, we might write up a trait like
`Vector` that has an associated constant specifying the number of
dimensions in vectors of this type:

    trait Vector {
        static dims: uint;
        fn get(&self, dim: uint) -> uint;
    }
    
Now I can write up an implementation, say for a two-dimensional point
type:

    struct Point2D { x: uint, y: uint }
    
    impl Vector for Point2D {
        static dims: uint = 2;
        fn get(&self, dim: uint) -> uint {
            assert!(dim < 2);
            if dim == 0 {self.x} else {self.y}
        }
    }

And then I can use this with generic code:

    fn sum<V: Vector>(v: &V) -> uint {
        let sum = 0;
        for uint::range(0, V::dims) |i| {
            sum += v.get_dim(i);
        }
        return sum;
    }

### Associated functions

Associated functions are useful in a couple of different contexts.
One common example is where you would like to define a trait that
includes some sort of constructor, such as `FromStr`:

    trait FromStr {
        fn parse(input: &str) -> Self;
    }

Here the trait defines an associated function `parse()` that will
parse a string and return an instance of the `Self` type.  I could
for example implement `FromStr` for integers:

    impl FromStr for uint {
        fn parse(input: &str) -> uint {
            uint::parse(input, 10) // 10 is the radix
        }
    }

Using `FromStr`, I can write a generic routine that, for example,
parses a comma-separate list of values:
    
    fn parse_comma_separated<T: FromStr>(input: &str) -> ~[T] {
        let substrings = input.split(",");
        substrings.map(|substring| T::parse(substring))
    }
    
Experienced Rust users might note that the syntax in that example is
actually not what one would write today.  This is the
"non-backwards-compatible change" I alluded to earlier.  In Rust
today, when one invokes an associated function, it is not named via
the self type as I did above, but rather it is named via the trait to
which the function belongs:

    substrings.map(|substring| FromStr::parse(substring))

The compiler uses inference to decide that the return type here is `T`
and therefore the self type for this call to `parse` must be `T`. This
approach is elegant in many ways, as I'll cover in the next post in
more detail, but it also has some downsides.  Perhaps the most serious
is that, if the associated function does not return an instance of
`Self`, then the compiler cannot disambiguate what version of the
function you are trying to call!

To see where you might have an associated function that does not
return `Self`, consider a trait like the following:

    trait TemperatureUnit {
        fn to_kelvin(f: float) -> float;
    }

Using the C++-approach I have been describing thus far, I could write 
a generic function like:

    fn do_some_chemistry<TU: TemperatureUnit>(f: float) -> float {
        let kelvin = TU::to_kelvin(f);
        ...
    }
    
Of course, this example is somewhat artificial, because one would be
better off integrate the temperature units as types in your type
system rather than using floats. But real examples like this do come
up. The associated constant `V::dims` is an example.

### So is there a proposal here?

Yes and no. Partially I just wanted to explain what an associated item
is and what you might use it for. But I've also kind of baked in an
alternate proposal for how we should address associated items, which
is to switch from a Haskell-like approach to a C++-like approach.  In
the next post, I'll explain how the Haskell solution works, and what
it would look like in Rust.  Frankly the difference is not so great so
it's a matter of taste.

Anyway, if you wanted to implement the scheme I've described in this
post, it would work as follows.  When resolving a path, if you find
that some prefix of the path evaluates to a type, then later elements
in the path are resolved using the same algorithm that we use today
for method lookup.  So, to look at our examples, if I wrote `G::Node`,
the path `G` here is a type, which means that the type `Node` would be
determined by examining the traits that are in scope to see whether
any of them both (1) define a type member `Node` and (2) are
implemented by `G`.

This is exactly analogous to how method lookup operates.  When you see
a call `a.b()`, we determine the type `T` of the expression `a` and
then look to see whether any of the traits which are in scope (1)
offer a method `b()` and (2) are implemented by `T`.

In fact, it's a bit more complex, because we also consider the
inherent members of a type that are defined without any trait at all.
We can do the same thing when resolving associated items.

Interestingly, unifying the algorithm used to specify associated items
and method calls also allows us to say that a call like `a.b(...)` is
just sugar for `T::b(a, ...)` where `T` is the type of `a`.

### Corner cases

There are a few corner cases to consider in this proposal.

#### Ambiguous references

It is possible to have two traits `A` and `B` that define the same
associated item `I`.  If both those traits are imported, and both
those traits are implemented by the same type `T`, then a reference
like `T::I` could refer to the item defined by `A` or the item defined
by `B`.  If we wish to provide an explicit syntax to disambiguate the
reference, it could be something like `T::(A::I)`.  That is, we refer
to the item `I` as defined in the trait `A` implemented for the type
`T`.

Another possible ambiguity can arise when you have a generic trait.
Consider something like the following:

    trait Getter<T> {
        static default: T;
        fn get(&self) -> T;
    }
    
Now imagine that I have some type with two implementations of
`Getter`:

    struct Circle {
        center: Point, radius: float
    }
    
    impl Getter<Point> for Circle {
        static default: Point = Point {x: 0, y: 0};
        fn get(&self) -> Point { self.point }
    }

    impl Getter<float> for Circle {
        static default: float = 0;
        fn get(&self) -> Point { self.radius }
    }

If I then write a generic routine such as:

    fn is_default<G: Getter<float> Getter<Point>>(g: &G) -> bool {
        let x = G::default;
        let y = g.get();
        x == y
    }
    
Then what value for `default` is `G::default` are we going to obtain?
The `Point` or the `float`?

Using the syntax that I proposed, one could write this unambiguously,
if verbosely:

    fn is_default<G: Getter<float> Getter<Point>>(g: &G) -> bool {
        let x = G::(Getter::<float>::default);
        let y = g.(Getter::<float>::get)();
        x == y
    }
    
#### Not all types are paths

Another problem is that if you wanted to get an associated member
of a type like `~[int]`, you couldn't write `~[int]::foo`.  But
this is easily circumvented by creating a type alias

    type T<U> = U;
    
and writing `T::<~[int]>::foo`, or else by permitting the syntax
`<~[int]>::foo`.

