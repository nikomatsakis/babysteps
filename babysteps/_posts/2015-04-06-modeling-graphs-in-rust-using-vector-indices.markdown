---
layout: post
title: "Modeling graphs in Rust using vector indices"
date: 2015-04-06 14:58:37 -0400
comments: true
categories: [Rust]
---

After reading [nrc's blog post about graphs][1], I felt inspired to
write up an alternative way to code graphs in Rust, based on vectors
and indicates. This encoding has certain advantages over using `Rc`
and `RefCell`; in particular, I think it's a closer fit to Rust's
ownership model. (Of course, it has disadvantages too.)

[1]: http://featherweightmusings.blogspot.com/2015/04/graphs-in-rust.html

I'm going to describe a simplified version of the strategy that rustc
uses internally. The [actual code in Rustc][graph.rs] is written in a
somewhat dated "Rust dialect". I've also put the sources to this blog
post in their [own GitHub repository][gh]. At some point, presumably
when I come up with a snazzy name, I'll probably put an extended
version of this library up on crates.io. Anyway, the code I cover in
this blog post is pared down to the bare essentials, and so it doesn't
support (e.g.) enumerating incoming edges to a node, or attach
arbitrary data to nodes/edges, etc. It would be easy to extend it to
support that sort of thing, however.

[graph.rs]: https://github.com/rust-lang/rust/blob/master/src/librustc/middle/graph.rs
[gh]: https://github.com/nikomatsakis/simple-graph

<!-- more -->

### The high-level idea

The high-level idea is that we will represent a "pointer" to a node or
edge using an index. A graph consists of a vector of nodes and a
vector of edges (much like the mathematical description `G=(V,E)` that
you often see):

```rust
pub struct Graph {
    nodes: Vec<NodeData>,
    edges: Vec<EdgeData>,
}
```

Each node is identified by an index. In this version, indices are just
plain `usize` values. In the real code, I prefer a struct wrapper just
to give a bit more type safety.

```rust
pub type NodeIndex = usize;

pub struct NodeData {
    first_outgoing_edge: Option<EdgeIndex>,
}
```

Each node just contains an optional edge index, which is the start of
a linked list of outgoing edges. Each edge is described by the
following structure:

```rust
pub type EdgeIndex = usize;

pub struct EdgeData {
    target: NodeIndex,
    next_outgoing_edge: Option<EdgeIndex>
}
```

As you can see, an edge contains a target node index and an optional
index for the next outgoing edge. All edges in a particular linked
list share the same source, which is implicit. Thus there is a linked
list of outgoing edges for each node that begins in the node data for
the source and is threaded through each of the edge datas.

The entire structure is shown in this diagram, which depicts a simple
example graph and the various data structures. Node indices are
indicated by a number like `N3` and edge indices by a number like
`E2`. The fields of each `NodeData` and `EdgeData` are shown.

```
Graph:
    N0 ---E0---> N1 ---E1---> 2
    |                         ^
    E2                        |
    |                         |
    v                         |
    N3 ----------E3-----------+
    
Nodes (NodeData):
  N0 { Some(E0) }     
  N1 { Some(E1) }
  N2 { None     } 
  N3 { Some(E2) } 
  
Edges:
  E0 { N1, Some(E2) }
  E1 { N2, None     }
  E2 { N3, None     }
  E3 { N2, None     }
```

### Growing the graph

Writing methods to grow the graph is pretty straightforward. For
example, here is the routine to add a new node:

```rust
impl Graph {
    pub fn add_node(&mut self) -> NodeIndex {
        let index = self.nodes.len();
        self.nodes.push(NodeData { first_outgoing_edge: None });
        index
    }
}
```

This routine will add an edge between two nodes (for simplicity, we
don't bother to check for duplicates):

```rust
impl Graph {
    pub fn add_edge(&mut self, source: NodeIndex, target: NodeIndex) {
        let edge_index = self.edges.len();
        let node_data = &mut self.nodes[source];
        self.edges.push(EdgeData {
            target: target,
            next_outgoing_edge: node_data.first_outgoing_edge
        });
        node_data.first_outgoing_edge = index;
    }
}
```

Finally, we can write an iterator to enumerate the successors of a
given node, which just walks down the linked list:

```rust
impl Graph {
    pub fn successors(&self, source: NodeIndex) -> Successors {
        let first_outgoing_edge = self.nodes[source].first_outgoing_edge;
        Successors { graph: self, current_edge_index: first_outgoing_edge }
    }
}

pub struct Successors<'graph> {
    graph: &'graph Graph,
    current_edge_index: Option<EdgeIndex>,
}

impl<'graph> Iterator for Successors<'graph> {
    type Item = NodeIndex;
    
    fn next(&mut self) -> Option<NodeIndex> {
        match self.current_edge_index {
            None => None,
            Some(edge_num) => {
                let edge = &self.graph.edges[edge_num];
                self.current_edge_index = edge.next_outgoing_edge;
                Some(edge.target)
            }
        }
    }
}
```

### Advantages

This approach plays very well to Rust's strengths. This is because,
unlike an `Rc` pointer, an index alone is not enough to mutate the
graph: you must use one of the `&mut self` methods in the graph. This
means that can track the mutability of the graph as a whole in the
same way that it tracks the mutability of any other data structure.

As a consequence, graphs implemented this way can easily be sent
between threads and used in data-parallel code (any graph shared
across multiple threads will be temporarily frozen while the threads
are active). Similarly, you are statically prevented from modifying
the graph while iterating over it, which is often desirable. If we
were to use `Rc` nodes with `RefCell`, this would not be possible --
we'd need locks, which feels like overkill.

Another advantage of this apprach over the `Rc` approach is
efficiency: the overall data structure is very compact. There is no
need for a separate allocation for every node, for example (since they
are just pushes into a vector, additions to the graph are O(1),
amortized). In fact, many C libaries that manipulate graphs also use
indices, for this very reason.

### Disadvantages

The primary disadvantage comes about if you try to remove things from
the graph. The problem then is that you must make a choice: either you
reuse the node/edge indices, perhaps by keeping a free list, or else
you leave a placeholder. The former approach leaves you vulnerable to
"dangling indices", and the latter is a kind of leak. This is
basically exactly analogous to malloc/free. Another similar problem
arises if you use the index from one graph with another graph (you can
mitigate that with fancy type tricks, but in my experience it's not
really worth the trouble).

However, there are some important qualifiers here:

- It frequently happens that you don't have to remove nodes or edges
  from the graph.  Often you just want to build up a graph and use it
  for some analysis and then throw it away. In this case the danger is
  much, much less.
- The danger of a "dangling index" is much less than a traditional
  dangling pointer. For example, it can't cause memory unsafety.
  
Basically I find that this is a *theoretical problem* but for many use
cases, it's not a *practical* one.

The big exception would be if a long-lived graph is the heart of your
application. In that case, I'd probably go with a `Rc` (or maybe
`Arc`) based approach, or perhaps even a hybrid -- that is, use
indices as I've shown here, but reference count the indices too. This
would preserve the data-parallel advantages.

### Conclusion

The key insights in this approach are:

- indices are often a compact and convenient way to represent complex
  data structures;
- they play well with multithreaded code and with ownership;
- but they also carry some risks, particularly for long-lived data
  structures, where there is an increased change of indices being
  misused between data structures or leaked.
