---
layout: post
title: "Non-lexical lifetimes: adding the outlives relation"
date: 2016-05-09T16:15:58-0700
comments: false
categories: [Rust, NLL]
---

This is the third post in my
[series on non-lexical lifetimes][nll]. Here I want to dive into
**Problem Case \#3** from the introduction. This is an interesting
case because exploring it is what led me to move away from the
continuous lifetimes proposed as part of [RFC 396][].

<!-- more -->

### Problem case \#3 revisited

As a reminder, problem case \#3 was the following fragment:

```rust
fn get_default<'m,K,V:Default>(map: &'m mut HashMap<K,V>,
                               key: K)
                               -> &'m mut V {
    match map.get_mut(&key) { // -------------+ 'm
        Some(value) => value,              // |
        None => {                          // |
            map.insert(key, V::default()); // |
            //  ^~~~~~ ERROR               // |
            map.get_mut(&key).unwrap()     // |
        }                                  // |
    }                                      // |
}                                          // v
```

What makes this example interesting is that it crosses functions. In
particular, when we call `get_mut` the first time, if we get back a
`Some` value, we plan to return the point, and hence the value must
last until the end of the lifetime `'m` (that is, until some point in
the caller). However, if we get back a `None` value, we wish to
release the loan immediately, because there is no reference to return.

Many people lack intuition for named lifetime parameters. To help get
some better intuition for what a *named lifetime parameter* represents,
imagine some caller of `get_default`:

```rust
fn get_default_caller() {
    let mut map = HashMap::new();
    ...
    let map_ref = &mut map; // -----------------------+ 'm
    let value = get_default(map_ref, some_key()); //  |
    use(value);                                   //  |
    // <----------------------------------------------+
    ...
}
```

Here we can see that we first create a reference to `map` called
`map_ref` (I pulled this reference into a variable for purposes of
exposition). This variable is passed into `get_default`, which returns
a reference into the map called `value`. The important point here is
that the signature of `get_default` indicates that `value` is a
reference into the map as well, so that means that the lifetime of
`map_ref` will also include any uses of `value`. Therefore, the
lifetime `'m` winds up extending from the creation of `map_ref` until
after the call to `use(value)`.

### Running example: inline

Although ostensibly problem case \#3 is about cross-function use, it
turns out that -- for the purposes of this blog post -- we can create
an equally interesting test case by inlining `get_default` into the
caller. This will produce the following combined example, which will
be the running example for this post. I've also taken the liberty of
"desugaring" the method calls to `get_mut` a bit, which helps with
explaining what's going on:

```rust
fn get_default_inlined() {
    let mut map = HashMap::new();
    let key = ...;
    ...
    let value = {
        // this is the body of `get_default`, just inlined
        // and slightly tweaked:
        let map_ref1 = &mut map; // --------------------------+ 'm1
        match map_ref1.get_mut(&key) {                     // |
            Some(value) => value,                          // |
            None => {                                      // .
                map.insert(key.clone(), V::default());     // .
                let map_ref2 = &mut map;                   // .
                map_ref2.get_mut(&key).unwrap() // --+ 'm2    .
            }                                   //   |        .
        }                                       //   |        |
    };                                          //   |        |
    use(value);                                 //   |        |
    // <---------------------------------------------+--------+
}
```

Written this way, we can see that there are two loans: `map_ref1` and
`map_ref2`. Both loans are passed to `get_mut` and the resulting
reference must last until after the call to `use(value)` has finished.
I've depicted the lifetime of the two loans here (and denoted them
`'m1` and `'m2`).

Note that, for this fragment to type-check, `'m1` must *exclude* the
`None` arm of the match. I've denoted this by using a `.` for that
part of the line. This area must be excluded because, otherwise, the
calls to `insert` and `get_mut`, both of which require mutable borrows
of `map`, would be in conflict with `map_ref1`.

But if `'m1` excludes the `None` part of the match, that means that
control can flow **out** of the region `'m1` (into the `None` arm) and
then **back in again** (in the `use(value)`).

### Why RFC 396 alone can't handle this example

At this point, it's worth revisiting [RFC 396][]. RFC 396 was based on
the very clever notion of defining lifetimes based on the dominator
tree. The idea (in my own words here) was that a lifetime consists of
a dominator node (the entry point `H`) along with a series of of
"tails" `T`. The lifetime then consisted of all nodes that were
dominated by `H` but which dominated one of the tails `T`. Moreover,
you have as a consistency condition, that for every edge `V -> W` in
the CFG, if `W != H` is in the lifetime, then `V` is in the lifetime.

The RFC's definition is somewhat different but (I believe) equivalent.
It defines a non-lexical lifetime as a set R of vertifes in the CFG,
such that:

1. R is a subtree (i.e. a connected subgraph) of the dominator tree.
2. If W is a nonroot vertex of R, and `V -> W` is an edge in the CFG
such that V doesn't strictly dominate W, then V is in R.

In the case of our example above, the dominator tree looks like this
(I'm labeling the nodes as well):

- A: `let mut map = HashMap::new();`
  - B: `let key = ...;`
    - C: `let map_ref1 = &mut map`
      - D: `map_ref1.get_mut(&key)`
        - E: `Some(value) => value`
        - F: `map.insert(key.clone(), V::default())`
          - G: `let map_ref2 = &mut map`
            - H: `map_ref2.get_mut(&key).unwrap()`
        - I: `use(value)`

Here the lifetime `'m1` would be a set containing *at least* {D, E, I}, because the value in
question is used in those places. But then there is an edge in the CFG from H to I,
and thus by rule #2, H must be in `'m1` as well. But then rule 1 will require that F and G
are in the set, and hence the resulting lifetime will be {D, E, F, G, H, I}. This implies
then that the calls to `insert` and `get_mut` are disallowed.

### The outlives relation in light of control-flow

In my [previous post][post2], I defined a lifetime as simply a set of
points in the control-flow graph and showed how we can use liveness to
ensure that references are valid at each point where they are
used. But that is not the full set of constraints we must consider. We
must also consider the `'a: 'b` constraints that arise as a result of
type-checking as well as where clauses.

The constraint `'a: 'b` means "the lifetime `'a` outlives `'b`". It
basically means that `'a` corresponds to something *at least as long
as* `'b` (note that the outlives relation, like many other relations
such as dominators and subtyping, is reflexive -- so it's ok for `'a`
and `'b` to be equally big). The intuition here is that, if you a
reference with lifetime `'a`, it is ok to approximate that lifetime to
something shorter. This corresponds to a subtyping rule like:

    'a: 'b
    ----------------------
    &'a mut T <: &'b mut T

In English, you can approximate a mutable reference of type `&'a mut
T` to a mutable reference of type `&'b mut T` so long as the new
lifetime `'b` is shorter than `'a` (there is a similar, though
different in one particular, rule governing shared references).

We're going to see that for the type system to work most smoothly, we
really want this subtyping relation to be extended to take into
account the *point P in the control-flow graph where it must hold*. So
we might write a rule like this instead:

    ('a: 'b) at P
    --------------
    (&'a mut T <: &'b mut T) at P

However, let's ignore that for a second and stick to the simpler
version of the subtyping rules that I showed at first. This is
sufficient for the running example. Once we've fully explored that
I'll come back and show a second example where we run into a spot of
trouble.

### Running example in pseudo-MIR

Before we go any further, let's transform our running example into a
more MIR-like form, based on a control-flow graph. I will use the
convention that each basic block ia assigned a letter (e.g., A) and
individual statements (or the terminator, in MIR speak) in the basic
block are named via the block and an index. So `A/0` is the call to
`HashMap::new()` and `B/2` is the `goto` terminator.

```
                A [ map = HashMap::new() ]
                1 [ key = ...            ]
                2 [ goto                 ]
                      |
                      v
                B [ map_ref = &mut map           ]
                1 [ tmp = map_ref1.get_mut(&key) ]
                2 [ switch(tmp)                  ]
                      |          |
                     Some       None
                      |          |
                      v          v
C [ v1 = (tmp as Some).0 ]  D [ map.insert(...)                      ]
1 [ value = v1           ]  1 [ map_ref2 = &mut map                  ]
2 [ goto                 ]  2 [ v2 = map_ref2.get_mut(&key).unwrap() ]
                      |     3 [ value = v2                           ]
                      |     4 [ goto                                 ]
                      |          |
                      v          v
                   E [ use(value) ]
```

Let's assume that the types of all these variables are as follows (I'm
simplifying in various respects from what the real MIR would do, just
to keep the number of temporaries and so forth under control):

- `map: HashMap<K,V>`
- `key: K`
- `map_ref: &'m1 mut HashMap<K,V>`
- `tmp: Option<&'v1 mut V>`
- `v1: &'v1 mut V`
- `value: &'v0 mut V`
- `map_ref2: &'m2 mut HashMap<K,V>`
- `v2: &'v2 mut V`

If we type-check the MIR, we will derive (at least) the following
outlives relationships between these lifetimes (these fall out from
the rules on subtyping above; if you're not sure on that point, I have
an explanation below of how it works listed under *appendix*):

- `'m1: 'v1` -- because of B/1
- `'m2: 'v2` -- because of D/2
- `'v1: 'v0` -- because of C/2
- `'v2: 'v0` -- beacuse of D/5

In addition, the liveness rules will add some inclusion constraints
as well. In particular, the constraints on `'v0` (the lifetime of the `value`
reference) will be as follows:

- `'v0: E/0` -- `value` is live here
- `'v0: C/2` -- `value` is live here
- `'v0: D/4` -- `value` is live here

For now, let's just treat the outlives relation as a "superset"
relation.  So `'m1: 'v1`, for example, requires that `'m1` be a
superset of `'v1`. In turn, `'v0: E/0` can be written `'v0: {E/0}`.
In that case, if we turn the crank and compute some minimal lifetimes
that satisfy the various constraints, we wind up with the following
values for each lifetime:

- `'v0 = {C/2, D/4, E/0}`
- `'v1 = {C/*, D/4, E/0}`
- `'m1 = {B/*, C/*, E/0, D/4}`
- `'v2 = {C/2, D/{3,4}, E/0}`
- `'m2 = {C/2, D/{2,3,4}, E/0}`

This turns out not to yield any errors, but you can see some kind of
surprising results. For example, the lifetime assigned to `v1` (the
value from the `Some` arm) includes some points that are in the `None`
arm -- e.g., D/5. This is because `'v1: 'v0` (subtyping from the
assignment in C/2) and `'v0: {D/5}` (liveness). It turns out you can
craft examples where these "extra blocks" pose a problem.

### Simple superset considered insufficient

To see where these extra blocks start to get us into trouble, consider
this example (here I have annotated the types of some variables, as
well as various lifetimes, inline). This is a variation on the
previous theme in which there are two maps. This time, along one
branch, `v0` will equal this reference `v1` pointing into `map1`, but
in the in the `else` branch, we assign `v0` from a reference `v2`
pointing into `map2`. After that assignment, we try to insert into
`map1`.  (This might arise for example if `map1` represents a cache
against some larger `map2`.)

```rust
let mut map1 = HashMap::new();
let mut map2 = HashMap::new();
let key = ...;
let map_ref1 = &mut map1;
let v1 = map_ref1.get_mut(&key);
let v0;
if some_condition {
    v0 = v1.unwrap();
} else {
    let map_ref2 = &mut map2;
    let v2 = map_ref2.get_mut(&key);
    v0 = v2.unwrap();
    map1.insert(...);
}
use(v0);
```

Let's view this in CFG form::

```
                A [ map1 = HashMap::new()       ]
                1 [ map2 = HashMap::new()       ]
                2 [ key: K = ...                ]
                3 [ map_ref1 = &mut map1        ]
                4 [ v1 = map_ref1.get_mut(&key) ]
                5 [ if some_condition           ]
                          |               |
                         true           false
                          |               |
                          v               v
      B [ v0 = v1.unwrap() ]   C [ map_ref2 = &mut map2        ]
      1 [ goto             ]   1 [ v2 = map_ref2.get_mut(&key) ]
                          |    2 [ v0 = v2.unwrap()            ]
                          |    3 [ map1.insert(...)            ]
                          |    4 [ goto                        ]
                          |               |
                          v               v
                        D [ use(v0)       ]
```

The types of the interesting variables are as follows:

- `v0: &'v0 mut V`
- `map_ref1: &'m1 mut HashMap<K,V>`
- `v1: Option<&'v1 mut V>`
- `map_ref2: &'m2 mut HashMap<K,V>`
- `v2: Option<&'v2 mut V>`

The outlives relations that result from type-checking this fragment are as follows:

- `'m1: 'v1` from A/4 
- `'v1: 'v0` from B/0
- `'m2: 'v2` from C/1
- `'v2: 'v0` from C/2
- `'v0: {B/1, C/3, C/4, D/0}` from liveness of `v0`
- `'m1: {A/3, A/4}` from liveness of `map_ref1`
- `'v1: {A/5, B/0}` from liveness of `v1`
- `'m2: {C/0, C/1}` from liveness of `map_ref2`
- `'v2: {C/2}` from liveness of `v2`

Following the simple "outlives is superset rules we've covered so far,
this in turn implies the lifetime `'m1` would be `{A/3, A/4, B/*, C/3,
C/4, D/0}`. Note that this includes `C/3`, precisely where we *would*
call `map1.insert`, which means we will get an error at this point.

### Location-area outlives

What I propose as a solution is to have the outlives relationship take
into account the current position. As I sketched above, the rough idea
is that the `'a: 'b` relationship becomes `('a: 'b) at P` -- meaning
that `'a` must outlive `'b` *at the point P*. We can define this
relation as follows:

- let S be the set of all points in `'b` reachable from P,
  - without passing through the entry point of `'b`
    - reminder: the entry point of `'b` is the mutual dominator of all points in `'b`
- if `'a` is a superset of `S`,
- then `('a: 'b) at P`

Basically, the idea is that `('a: 'b) at P` means that, given that we
have arrived at point P, any points that we can reach from here that
are still in `'b` are also in `'a`.

If we apply this new definition to the outlives constraints from the
previous section, we see a key difference in the result. In
particular, the assignment `v0 = v1.unwrap()` in B/0 generates the
constraint `('v1: 'v0) at B/0`. `'v0` is `{B/1, C/3, C/4, D/0}`.
Before, this meant that `'v1` must include `C/3` and `C/4`, but now we
can screen those out because they are not reachable from `B/0` (at
least, not without calling the enclosing function again). Therefore,
the result is that `'v1` becomes `{A/5, B/0, B/1, D/0}`, and hence
`'m1` becomes `{A/3, A/4, A/5, B/0, B/1, D/0}` -- notably, it no
longer includes C/3, and hence no error is reported.

### Conclusion and some discussion of alternative approaches

This post dug in some detail into how we can define the outlives
relationship between lifetimes. Interestingly, in order to support the
examples we want to support, when we move to NLL, we have to be able
to support *gaps* in lifetimes. In all the examples in this post, the
key idea was that we want to exit the lifetime when we enter one
branch of a conditional, but then "re-enter" it afterwards when we
join control-flow after the conditional. This works out ok because we
know that, when we exit the first-time, all references with that
lifetime are dead (or else the lifetime would have to include that
exit point).

There is another way to view it: one can view a lifetime as a set of
*paths* through the control-flow graph, in which case the points after
the `match` or after the `if` would appear on only on paths that
happened to pass through the right arm of the match. They are
"conditionally included", in other words, depending on how
control-flow proceeded.

One downside of this approach is that it requires augmenting the
subtyping relationship with a location. I don't see this causing a
problem, but it's not something I've seen before. We'll have to see as
we go. It might e.g. affect caching.

### Comments

Please comment on
[this internals thread](http://internals.rust-lang.org/t/non-lexical-lifetimes-based-on-liveness/3428/).

### Appendix A: An alternative: variables have multiple types

There is another alternative to lifetimes with gaps that we might
consider. We might also consider allow variables to have multiple
types.  I explored this a bit by using an SSA-like renaming, where
each verson assignment to a variable yielded a fresh type. However, I
thought that in the end it felt more complicated than just allowing
lifetimes to have gaps; for one thing, it complicates determining
whether two paths overlap in the borrow checker (different versions of
the same variable are still stored in the same lvalue), and it doesn't
interact as well with the notion of *fragments* that I talked about in
[the previous post][post2] (though one can use variants of SSA that
operate on fragments, I suppose). Still, it may be worth exploring --
and there more precedent for that in the literature, to be sure.  One
advantage of that approach is that one can use "continuous lifetimes",
I think, which may be easier to represent in a compact fashion -- on
the other hand, you have a lot more lifetime variables, so that may
not be a win. (Also, I think you still need the outlives relationship
to be location-dependent.)

### Appendix B: How subtyping links the lifetime of arguments and the return value

Given the definition of the `get_mut` method, the compiler is able to
see that the reference which gets returned is reborrowed from the
`self` argument. That is, the compiler can see that as long as you are using
the return value, you are (indirectly) using the `self` reference
as well. This is indicated by the named lifetime parameter `'v` that
appears in the definition of `get_mut`:

```rust
fn get_mut<'v>(&'v mut self, key: &Key) -> Option<&'v mut V> { ... }
```

There are various ways to think of this signature, and in particular
the named lifetime parameter `'v`. The most intuitive explanation is
this parameter indicates that the return value is "borrowed from" the
`self` argument (because they share the same lifetime `'v`). Hence we
could conclude that when we call `tmp = map_ref1.get_mut(&key)`, the
lifetime of the input (`'m1`) must outlive the lifetime of the output
(`'v1`). Written using outlives notation, that would be that this call
requires that `'m1: 'v1`. This is the right conclusion, but it may be
worth digging a bit more into how the type system actually works
internally.

Specifically, the way the type system works, is that when `get_mut` is
called, to find the signature at that particular callsite, we replace
the lifetime parameter `'v` is replaced with a new inference variable
(let's call it `'0`). So at the point where `tmp = map_ref1.get_mut(&key)`
is called, the signature of `get_mut` is effectively:

    fn(self: &'0 mut HashMap<K,V>,
       key: &'1 K)
       -> Option<&'0 mut V>

Here you can see that the `self` parameter is treated like any other
explicit argument, and that the lifetime of the key reference (now
made explicit as `'1`) is an independent variable from the lifetime of
the `self` reference. Next we would require that the type of each
supplied argument must be a subtype of what appears in the signature.
In particular, for the `self` argument, that results in this
requirement:

    &'m1 mut HashMap<K,V> <: &'0 mut HashMap<K,V>

from which we can conclude that `'m1: '0` must hold. Finally, we
require that the declared return type of the function must be a
subtype of the type of the variable where the return value is stored,
and hence:

             Option<&'0 mut V> <: Option<&'v1 mut V>
    implies: &'0 mut V <: &'v1 mut V
    implies: '0: 'v1

So the end result from all of these subtype operations is that we have
two outlives relations:

    'm1: '0
    '0: 'v

These in turn imply an indirect relationship between `'m1` and `'v`:

    `'m1: 'v1`

This final relationship is, of course, precisely what our intuition led
us to in the first place: the lifetime of the reference to the map
must outlive the lifetime of the returned value.

[nll]: http://smallcultfollowing.com/babysteps/blog/categories/nll/
[RFC 396]: https://github.com/rust-lang/rfcs/pull/396
[post2]: http://smallcultfollowing.com/babysteps/blog/2016/05/04/non-lexical-lifetimes-based-on-liveness/

