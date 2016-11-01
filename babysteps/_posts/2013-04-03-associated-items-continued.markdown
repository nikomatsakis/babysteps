---
layout: post
title: "Associated items continued"
date: 2013-04-03 08:37
comments: true
categories: [Rust]
---
I want to [finish my discussion of associated items][pp] by taking a
look at how they are handled in Haskell, and what that might mean in
Rust.

These proposals have the same descriptive power as what I described
before, but they are backwards compatible.  This is nice.

<!-- more -->

### Object-oriented style name resolution

In the object-oriented, C++-like version of associated items that I
introduced before, the names of associated items and methods were
resolved relative to a type.  To see what I mean by this, consider a
(slightly expanded) variant the graph example I introduced before:

    trait Graph {
        type Node;      // associated type
        static K: uint; // associated constant
    }
    
    mod graph {
        fn depth_first_search<G: Graph>(
            graph: &G) -> ~[G::Node]
        {
            let k = G::K;
            ...
        }
    }

Consider a path like `graph::depth_first_search`, which names an item
within a module.  This kind of path is based solely on the module
hierarchy and can be resolved without knowing anything types
whatsoever.

Now consider the paths `G::Node` and `G::K` that appear in
`depth_first_search`. These paths *look* similar to in form to
`graph::depth_first_search`, but they are resolved quite
differently. Because `G` is a type and not a module, if we want to
figure out what names `Node` and `K` refer to, we don't examine the
module hierarchy but rather the properties of the type `G`. In this
case, `G` is a type parameter that implements the `Graph` trait, and
the `Graph` trait defines an associated type `Node` and an associated
constant `K`.

Note that the name lookup process here is exactly analogous to what
happens on a method call. With an expression like `a.b()`, the meaning
of the name `b` is resolved by first examining the type of the
expression `a` and then checking to see what methods that type
offers. The module hierarchy is not consulted.

The object-oriented style of naming specification is not fully
explicit. In particular, a path like `G::Node` does not specify the
trait in which `Node` was defined, the compiler must figure it out.
It is also possible that the type `G` implements multiple traits that
have an associated item `Node`, so the syntax could be ambiguous.  To
make things fully explicit, I proposed in my previous post that the
full syntax would be `Type::(Trait::Item)`.  So the fully explicit
form of `G::Node` would be `G::(Graph::Node)`, since the type `Node`
is defined in the trait `Graph`.

### Functional-style name resolution (take 1)

In Haskell, all name resolution is done based on lexical scoping and
the module hierarchy. This is no accident. It means that the Haskell
compiler can figure out what each name in a program refers to without
knowing anything about the types involved, which is helpful when
performing aggressive type inference.

What this means is that we can't use a path like `G::Node` to mean
"the type `Node` relative to the type `G`", because interpreting this
path would require examining the definition of the type `G` (as we saw
before). Instead, if we were to use a syntax analogous to what Haskell
uses, one would write something like `Graph::Node<G>`.  Note that all
the names here (`Graph::Node`, `G`) can be resolved using only the
module hierarchy.

So the example I gave before would look as follows:

    trait Graph {
        type Node;      // associated type
        static K: uint; // associated constant
    }
    
    mod graph {
        fn depth_first_search<G: Graph>(
            graph: &G) -> ~[Graph::Node<G>]
        {
            let k = Graph::K::<G>;
            ...
        }
    }

Note that where before we wrote `G::K` to refer to the constant `K`
associated with the type `G`, we would now write `Graph::K::<G>`.  As
is typical in Rust, the extra `::` that appears before the type
parameter `<G>` is necessary to avoid parsing ambiguities when the
path appears as part of an expression.

Let's look a bit more closely at what's going on here.  Effectively
what is happening is that, for each associated item within a trait, we
are adding a synthetic type parameter. For any reference to an
associated item, this type parameter tells the compiler which type is
implementing the trait. The path `Graph::Node` by itself is not
complete; `Graph::Node<G>` means "the type `Node` defined for the type
`G`".

Let's dig into it this Haskell-style convention a bit to see some of
the implications.

#### Return type inference

One benefit of the Haskell style convention is that the values for
the type parameters can often be deduced by inference. For example,
let's return to the trait `FromStr` from my [previous post][pp].
The trait `FromStr` is used to parse a string and produce a value of
some other type:

    trait FromStr {
        fn parse(input: &str) -> Self;
    }

We might implement `FromStr` for unsigned integers as follows:

    impl FromStr for uint {
        fn parse(input: &str) -> uint {
            uint::parse(input, 10) // 10 is the radix
        }
    }

Now we could write a function that invokes `parse()` like so:

    fn parse_strings(v: &[&str]) -> ~[uint] {
        v.map(|s| FromStr::parse(*s))
    }

Note that when we called `FromStr::parse(*s)`, we did not say what
type it should parse to.  The compiler was able to infer that we wanted
to parse a string into a `uint` based on the return type of
`parse_strings()` as a whole.  A fully explicit version of `parse_strings`
would look like:

    fn parse_strings(v: &[&str]) -> ~[uint] {
        v.map(|s| FromStr::parse::<uint>(*s))
        //                        ^~~~~~ specify return type
    }

#### Generic traits

Imagine that we have a generic trait, like this `Add` trait:

    trait Add<Rhs> {
        type Sum;
        
        fn add(&self, r: &Rhs) -> Sum<Self, Rhs>;
    }
    
This trait is very similar to the trait used in Rust to implement
operator overloading, except it has been adapted to use an associated
type for the `Sum` (which is probably how the Rust type should be
defined as well, since the type of the sum ought to be determined by
the types of the things being added).

Previously, with the associated type `Node`, we said that any
reference to node had to include a single type parameter to indicate
the type that was implementing `Graph`.  But with a generic trait like
`Add` a simple type parameter is not enough.  To fully specify all the
types involved, we need to include both the `Self` type and any type
parameters.  This is why the return type of the method `add()` is
`Sum<Self, Rhs>`---a mere reference to `Sum` or `Sum<Self>` would be incomplete.

**Comparison to object-oriented form.** Interestingly, this case is
something that the object-oriented style of naming cannot handle very
well. This is because the object-oriented convention is strongly
oriented towards specifying the `Self` type but does not easily expand
to accommodate generic traits. Using the fully explicit syntax that I
suggested in my [previous post][pp], I think the result would look
like `Self::(Add<Rhs>::Sum)`. (It's plausible that, within the trait
definition itself, one could simply write `Sum`, but from outside the
trait definition I think it would be necessary to specify the full
type parameters).

#### Generic items

It is also possible to have an associated item which itself has
type parameters.  For example, we might want to have a graph
where kind of node can carry its own userdata:

    trait Graph {
        type Node<B>;
        
        fn get_node_userdata<B>(n: &Node<Self, B>) -> B;
    }
   
Here we see that when we refer to the `Node` type in
`get_node_userdata`, we specify both the `Self` type parameter and the
type parameters defined on `Node` itself.  I think this is a bit
surprising.

**Comparison to object-oriented form.** The object-oriented naming
scheme handles this case very naturally.  For example, `get_node_userdata()`
would be declared as follows:

    fn get_node_userdata<B>(n: &Self::Node<B>) -> B;

### Functional-style name resolution (take 2)

In the previous section we added implicit type parameters to each
associated item.  Particularly in the cases of generic traits or
generic items, this can be a bit confusing. You wind up mixing type
parameters that were declared on the trait together with type
parameters declared on the item.

An alternative that would be a bit more explicit is to (1) designate
the implicit parameter for the trait's Self type using a special
keyword, such as `for` or `self` (I prefer `for` since it echoes the
`impl Trait for Type` form) and (2) push the trait type parameters
into the path itself.  So instead of writing `Graph::Node<G>` you
would write `Graph::Node<for G>`, and instead of `Add::Sum<Lhs, Rhs>`
you would write `Add<Rhs>::Sum<for Lhs>`. You'll see more examples of
how this looks in the next section.

### Conclusion: Comparing the conventions

I think none of these conventions is perfect. Each has cases where it
is a bit counterintuitive or ugly. To try and make the comparison
easier, I'm going to create a table summarizing the object-oriented,
functional 1, and functional 2 styles, and show how each syntax looks
for each of the use cases I identified in this post. For each use
case, I'll provide both the shortest possible form and the fully
explicit variant.

<p><table class="hor-minimalist-a">
<tr><th colspan=3>Reference to an associated type</th></tr>
<tr><td>G::Node</td><td>Node&lt;G&gt;</td><td>Node&lt;for G&gt;</td></tr>
<tr><td>G::(Graph::Node)</td><td>Graph::Node&lt;G&gt;</td><td>Graph::Node&lt;for G&gt;</td></tr>
<tr><th colspan=3>Reference to an associated constant</th></tr>
<tr><td>G::K</td><td>K::&lt;G&gt;</td><td>K::&lt;for G&gt;</td></tr>
<tr><td>G::(Graph::K)</td><td>Graph::K::&lt;G&gt;</td><td>Graph::K::&lt;for G&gt;</td></tr>
<tr><th colspan=3>Call of an associated function</th></tr>
<tr><td>uint::parse()</td><td>parse()</td><td>parse()</td></tr>
<tr><td>uint::(Graph::parse())</td><td>FromStr::parse::&lt;uint&gt;()</td><td>FromStr::parse()::&lt;for uint&gt;</td></tr>
<tr><th colspan=3>Generic trait</th></tr>
<tr><td>Self::(Add&lt;Rhs&gt;::Sum)</td><td>Sum&lt;Self,Rhs&gt;</td><td>Add&lt;Rhs&gt;::Sum&lt;for Self&gt;</td></tr>
<tr><td>Self::(Add&lt;Rhs&gt;::Sum)</td><td>Add::Sum&lt;Self,Rhs&gt;</td><td>Add&lt;Rhs&gt;::Sum&lt;for Self&gt;</td>
<tr><th colspan=3>Generic associated item</th></tr>
<tr><td>Self::Node&lt;B&gt;</td><td>Node&lt;Self,B&gt;</td><td>Node&lt;B for Self&gt;</td></tr>
<tr><td>Self::(Graph::Node&lt;B&gt;)</td><td>Graph::Node&lt;Self,B&gt;</td><td>Graph::Node&lt;B for Self&gt;</td></tr>
</table></p>

Based on this table, my feeling is that the object-oriented style
handles the simple cases the best (`G::Node`, `G::K`), but it handles
the "generic trait" case very badly.

There are also some side considerations:

1. Functional 1 is (mostly) backwards compatible with the current code.
2. Functional 1 provides return-type inference, which many people find
   appealing.
3. The object-oriented style means that `a.b(...)` is always
   sugar for `T::b(a, ...)` where `T` is the type of `a`, which is
   elegant.
4. The functional styles mean that `::` is always module-based name
   resolution and `.` is always type-based resolution, which has an
   elegance of its own.
   
It's a tough call, but right now I think on balance I lean towards one
of the two functional notations, probably functional 2 because,
despite being wordier, it seems a bit clearer what's going on. Just
appending the type parameters from the trait and the method together
is confusing.

### Appendix A. Functional notation (take 3)

There is one other where you might handle the placement of type
parameters in the functional style.  You might take the "self" type
and place it on the trait: i.e., instead of `Graph::Node<for G>` you'd
write `Graph<for G>::Node`.  This is arguably more correct if you
think about traits in terms of Haskell type classes, since the self
type is really the same as any other type parameter on the generic
trait.  But when I experimented with it I found that it was so wordy
and ugly it was a non-starter.

### Appendix B. Haskell and functional dependencies

In addition to associated types, Haskell also offers a feature called
functional dependencies, which is basically another, independently
developed, means of solving this same problem.  The idea of a
functional dependency is that you can define when some type parameters
of a trait are determined by others.  So, if we were to adapt
functional dependencies in their full generality to Rust syntax, we
might write out the graph example as something like this:

    // Associated types:
    trait Graph {
        type Node;
        type Edge;
    }

    // Functional dependencies:
    trait Graph<Node, Edge> {
        Self -> Node;
        Self -> Edge;
        ...
    }
    
The line `Self -> Node` states that, given the type of `Self`, you can
determine the type `Node` (and likewise for `Edge`).  You can see that
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

    trait Graph<Node, Edge> {
        Node -> Edge;
        ...
    }

This trait declaration says that, if you know the type of the nodes
`Node`, then you know the type of the edges `Edge`.  However, knowing the
type `Self` isn't enough to tell you either of them.  I don't know of
any examples where expressiveness like this is useful, however.
        
### Appendix C. "where" clauses.
        
There is one not-entirely-obvious interaction between associated types
and other parts of the syntax.  Suppose that I wanted to write a
function that worked over any graph whose nodes were represented as
integers (it is very common to represent graph nodes as integers when
working with large graphs). If we defined the graph trait using a
simple type parameter, like so:

    trait Graph1<N> { ... }
    
then I could write a depth-first-search routine that expects
a graph with `uint` nodes as follows:

    fn depth_first_search_over_uints<G: Graph1<uint>>(graph: &G) { ... }

But we saw in [the previous post][pp] that this definition of
`Graph` has a number of downsides. In fact, it was the motivating
example for associated types. So we'd rather write the trait
like so:

    trait Graph {
        type N;
        ...
    }
    
But now it seems that I cannot write a `depth_first_search_over_uints`
routine anymore! After all, where would I write it?
    
    fn depth_first_search_over_uints<G: Graph>(graph: &G) { ... }

Many languages answer this problem by adding a separate clause that
can be used to specify additional constraints.  In Rust we might write
it like so (hearkening back to the typestate constraint syntax):

    fn depth_first_search_over_uints<G: Graph>(graph: &G)
        : G::Node == uint
    { ... }

This is not the end of the world, but it's also unfortunate, since
this kind of clause leaks into closure types and all throughout the
language. But while discussing associated types with [Felix][pnkfelix]
at some point I realized that there is a workaround for this
situation. If you have a trait like `Graph` that uses an associated
type, but you would like to write a routine like
`depth_first_search_over_uints`, you can write an adapter:

    trait Graph1<N> { ... } // as before
    impl<G: Graph> Graph1<G::Node> for G { ... }
    
Now I can write `depth_first_search_over_uints` and have it work for
any type that implements `Graph`.

This adapter trait is not the most elegant solution but it works. I
would not expect this situation to arise that frequently, but it will
come up from time-to-time. The `Add` and `Iterable` traits come to
mind.

[pp]: {{ site.baseurl }}/blog/2013/04/02/associated-items
