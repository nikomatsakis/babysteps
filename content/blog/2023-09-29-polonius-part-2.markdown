---
title: "Polonius revisited, part 2"
date: 2023-09-29T06:43:09-04:00
---

In the [previous Polonius post][pp], we formulated the original borrow checker in a Polonius-like style. In this post, we are going to explore how we can extend that formulation to be flow-sensitive. In so doing, we will enable the original Polonius goals, but also overcome some of its shortcomings. I believe this formulation is also more amenable to efficient implementation. As I'll cover at the end, though, I do find myself wondering if there's still more room for improvement.

[pp]: https://smallcultfollowing.com/babysteps/blog/2023/09/22/polonius-part-1/

## Running example

We will be working from the same Rust example as the original post, but focusing especially on the mutation in the `false` branch[^artificial]:

[^artificial]: If this particular example feels artificial, that's because it is. But similar errors cause more common errors, most notably [Problem Case #3][pppc3].

[pppc3]: https://rust-lang.github.io/rfcs/2094-nll.html#problem-case-3-conditional-control-flow-across-functions


```rust
let mut x = 22;
let mut y = 44;
let mut p: &'0 u32 = &x;
y += 1;
let mut q: &'1 u32 = &y; // Borrow `y` here (L1)
if something() {
    p = q;  // Store borrow into `p`
    x += 1;
} else {
    y += 1; // Mutate `y` on `false` branch
}
y += 1;
read_value(p); // May refer to `x` or `y`
```

There is no reason to have an error on this line. There *is* a borrow of `y`, but on the `false` branch that borrow is only stored in `q`, and `q` will never be read again. So there cannot be undefined behavior (UB).

## Existing borrow checker flags an error

The existing borrow checker, however, is not that smart. It sees `read_value(p)` at the end and, because that line could potentially read `x` or `y`, it flags the `y += 1` as an error. When expressed this way, maybe you can have some sympathy for the poor borrow checker -- it's not an unreasonable conclusion! But it's wrong.

The core issue of the existing borrow check stems from its use of a [*flow insensitive* subset graph][ppsg]. This in turn is related to how it does the type check. In Polonius today, each variable has a single type and hence a single origin (e.g., `q: &'1 u32`). This causes us to conflate all the possible loans that the variable may refer to throughout execution. And yet as we have seen, this information is actually flow dependent.

[ppsg]: https://smallcultfollowing.com/babysteps/blog/2023/09/22/polonius-part-1/#compute-the-subset-graph

The borrow checker today is based on a pretty standard style of type checker applied to [the MIR][ppmir]. Essentially there is an **environment** that maps each variable to a type.

[ppmir]: https://smallcultfollowing.com/babysteps/blog/2023/09/22/polonius-part-1/#construct-the-mir

```
Env  = { X -> Type }
Type = scalar | & 'Y T | ...
```

Then we have type-checking [inference rules][] that thread this same environment everywhere. Conceptually the structure of the the rules is as follows:

```
construct Env from local variable declarations
Env |- each basic block type checks
--------------------------
the MIR type checks
```

Type-checking a [place][] then uses this `Env`, bottoming out in an inference rule like:

```
Env[X] = T
-------------
Env |- X : T
```

[inference rules]: https://en.wikipedia.org/wiki/Rule_of_inference
[place]: https://rustc-dev-guide.rust-lang.org/mir/index.html?highlight=places%3A#key-mir-vocabulary

## Flow-sensitive type check

The key thing that makes the borrow checker *flow insensitive* is that we use the same environment at all points. What if instead we had one environment *per program point*:

```
EnvAt = { Point -> Env }
```

Whenever we type check a statement at program point `A`, we will use `EnvAt[A]` as its environment. When program point `A` flows into point `B`, then the environment at `A` must be a *subenvironment* of the environment at `B`, which we write as `EnvAt[A] <: EnvAt[B]`.

The subenvironment relationship `Env1 <: Env2` holds if

* for each variable `X` in `Env2`:
    * `X` appears in `Env1`
    * `Env1[X] <: Env2[X]`

There are two interesting things here. The first is that the **set of variables can change over time**. The idea is that once a variable goes dead, you can drop it from the environment. The second is that **the type of the variable can change according to the subtyping rules**. 

You can think of flow-sensitive typing as if, for each program variable like `q`, we have a separate copy per program point, so `q@A` for point `A` and `q@B` for point at `B`. When we flow from one point to another, we assign from `q@A` to `q@B`. Like any assignment, this would require the type of `q@A` to be a subtype of the type of `q@B`.

## Flow-sensitive typing in our example

Let's see how this idea of a flow-sensitive type check plays out for our example. First, recall the MIR for our example from the [previous post][pp]:

```mermaid
flowchart TD
  Intro --> BB1
  Intro["let mut x: i32\nlet mut y: i32\nlet mut p: &'0 i32\nlet mut q: &'1 i32"]
  BB1["<b><u>BB1:</u></b>\np = &x;\ny = y + 1;\nq = &y;\nif something goto BB2 else BB3"]
  BB1 --> BB2
  BB1 --> BB3
  BB2["<b><u>BB2</u></b>\np = q;\nx = x + 1;\n"]
  BB3["<b><u>BB3</u></b>\ny = y + 1;"]
  BB2 --> BB4;
  BB3 --> BB4;
  BB4["<b><u>BB4</u></b>\ny = y + 1;\nread_value(p);\n"]

  classDef default text-align:left,fill-opacity:0;
```

### One environment per program point

In the original, flow-insensitive type check, the first thing we did was to create origin variables (`'0`, `'1`) for each of the origins that appear in our types. You can see those variables in the chart above. So we effectively had an environment like

```
Env_flow_insensitive = {
    p: &'0 i32,
    q: &'1 i32,
}
```

But now we are going to have one environment per program point. There is one program point in between each MIR statement. So the point `BB1_0` would be the entry to basic block `BB1`, and `BB1_1` would be after the first statement. So we have `Env_BB1_0`, `Env_BB1_1`, etc. We are going to create distinct origin variables for each of them:

```
Env_BB1_0 = {
    p: &'0_BB1_0 i32,
    q: &'1_BB1_0 i32,
}

Env_BB1_1 = {
    p: &'0_BB1_1 i32,
    q: &'1_BB1_1 i32,
}

...
```

### Type-checking the edge from BB1 to BB2

Let's look at point `BB1_3`, which is the final line in BB1, which in MIR-speak is called the *terminator*. It is an *if* terminator (`if something goto BB2 else BB3`). To type-check it, we will take the environment on entry (`Env_BB1_3`) and require that it is a sub-environment of the environment on entry to the true branch (`Env_BB2_0`) and on entry to the false branch (`Env1_BB3_0`).

Let's start with the *true branch*. Here we have the environment `Env_BB2_0`:

```
Env_BB2_0 = {
    q: &'1_BB2_0 i32,
}
```

You should notice something curious here -- why is there no entry for `p`? The reason is that the variable `p` is **dead** on entry to BB2, because its current value is about to be overridden. The type checker knows not to include dead variables in the environment. 

This means that...

* `Env_BB1_3 <: Env_BB2_0` if the type of `q` at `BB1_3` is a subtype of the type of `q` at `BB2_0`...
* ...so `&'1_BB1_3 i32 <: &'1_BB2_0 i32` must hold...
* ...so `'1_BB1_3 : '1_BB2_0` must hold.

What we just found then is that, because of the edge from BB1 to BB2, the version of `'1` on exit from BB1 flows into `'1` on entry to BB2.

### Type-checking the `p = q` assignment

let's look at the assignment `p = q`. This occurs in statement BB2_0. The environment before we just saw:

```
Env_BB2_0 = {
    q: &'1_BB2_0 i32,
}
```

For an assignment, we take the type of the left-hand side (`p`) from the environment *after*, because that is what we are storing into. The environment after is `Env_BB2_1`:

```
Env_BB2_1 = {
    p: &'0_BB2_1 i32,
}
```

And so to type check the statement, we get that `&'1_BB2_0 i32 <: &'0 BB2_1 i32`, or `'1_BB2_0 : '0_BB2_1`. 

In addition to this relation from the assignment, we also have to make the environment `Env_BB2_0` be a subenvironment of the env after `Env_BB2_1`. But since the set of live variables are disjoint, in this case, that doesn't add anything to the picture.

### Type-checking the edge from BB1 to BB3

As the final example, let's look at the *false* edge from BB1 to BB3. On entry to BB3, the variable `q` is dead but `p` is not, so the environment looks like

```
Env_BB3_0 = {
    p: &'0_BB3_0 i32,
}
```

Following a similar process to before, we conclude that `'0_BB1_3 : '0_BB3_0`.


## Building the flow-sensitive subset graph

We are now starting to see how we can build a **flow-sensitive** version of the flow graph. Instead of having one node in the graph per origin variable, we now have one node in the graph per origin variable per program point, and we create an edge `N1 -> N2` between two nodes if the type check requires that `N1 : N2`, just as before. Basically the only difference is that we have a lot more nodes.

Putting together what we saw thus far, we can construct a subset graph for this program like the following. I've excluded nodes that correspond to dead variables -- so for example there is no node `'1_BB1_0`, because `'1` appears in the variable `q`, and `q` is dead at the start of the program.

```mermaid
flowchart TD
    subgraph "'0"
        N0_BB1_0["'0_BB1_0"]
        N0_BB1_1["'0_BB1_1"]
        N0_BB1_2["'0_BB1_2"]
        N0_BB1_3["'0_BB1_3"]
        N0_BB2_1["'0_BB2_1"]
        N0_BB3_0["'0_BB3_0"]
        N0_BB4_0["'0_BB4_0"]
        N0_BB4_1["'0_BB4_1"]
    end

    subgraph "'1"
        N1_BB1_2["'1_BB1_2"]
        N1_BB1_3["'1_BB1_3"]
        N1_BB2_0["'1_BB2_0"]
    end
    
    subgraph "Loans"
        L0["{L0} (&x)"]
        L1["{L1} (&y)"]
    end
    
    L0 --> N0_BB1_0
    L1 --> N1_BB1_2
    
    N0_BB1_0 --> N0_BB1_1 --> N0_BB1_2 --> N0_BB1_3
    N0_BB1_3 --> N0_BB3_0
    N0_BB3_0 --> N0_BB4_0 --> N0_BB4_1
    N0_BB2_1 --> N0_BB4_0

    N1_BB1_2 --> N1_BB1_3
    N1_BB1_3 --> N1_BB2_0
    
    N1_BB2_0 --> N0_BB2_1
```

Just as before, we can trace back from the node for a particular origin O to find all the loans contained within O. Only this time, the origin O also indicates a program point.

In particular, compare `'0_BB3_0` (the data reachable from `p` on the `false` branch of the if) to `'0_BB4_0` (the data reachable after the if finishes). We can see that in the first case, the origin can only reference `L0`, but afterwards, it could reference `L1`.

## Active loans

Just as in described in the [previous post][ppal], to complete the analysis we compute the *active loans*. Active loans are defined in almost exactly the same way, but with one twist. A loan `L` is *active* at a program point `P` if there is a path from the borrow that created `L` to `P` where, for each point along the path...

[ppal]: https://smallcultfollowing.com/babysteps/blog/2023/09/22/polonius-part-1/#active-loans

* there is some live variable **whose type at `P`** may reference the loan; and,
* the place expression that was borrowed by `L` (here, `x`) is not reassigned at `P`.

See the bolded test? We are now taking into account the fact that the type of the variable can change along the path. In particular, it may reference distinct origins.

### Implementing using dataflow

Just as in the [previous post][ppdf], we can compute active loans using dataflow. In particular, we **gen** a loan when it is issued, and we **kill** a loan `L` at a point `P` if (a) there are no live variables whose origins contain `L` or (b) the path borrowed by `L` is assigned at `P`.

[ppdf]: https://smallcultfollowing.com/babysteps/blog/2023/09/22/polonius-part-1/#implementing-using-dataflow

### Applying this to our running example

When we apply this to our running example, the unnecessary error on the `false` branch of the `if` goes away. Let's walk through it. 

#### Entry block

In `BB1`, we gen `L0` and `L1` at their two borrow sites, respectively. As a result, the active loans on exit from `BB1` wil be `{L0, L1}`:

```mermaid
flowchart TD
  Start["..."]
  BB1["<b><u>BB1:</b></u>
       p = &x; <b><i>// Gen: L0</i></b>
       y = y + 1;
       q = &y; <b><i>// Gen: L1</i></b>
       if something goto BB2 else BB3
  "]
  BB2["..."]
  BB3["..."]
  BB4["..."]
 
  Start --> BB1
  BB1 --> BB2
  BB1 --> BB3
  BB2 --> BB4
  BB3 --> BB4
 
  classDef default text-align:left,fill:#ffffff;
  classDef highlight text-align:left,fill:yellow;
  class BB3 highlight
```

#### The `false` branch of the `if`

On the `false` branch of the `if` (`BB3`), the only live reference is `p`, which will be used later on in `BB4`. In particular, `q` is dead.

In the flow **insensitive** version, when the borrow checker looked at the type of `p`, it was `p: &'0 i32`, and `'0` had the value `{L0, L1}`, so the borrow checker concluded that both loans were active. 

But in the flow **sensitive** version we are looking at now, the type of `p` on entry to `BB3` is `p: &'0_BB3_0 i32`. And, consulting the subset graph shown earlier in this post, the value of `'0_BB3_0` is just `{L0}`. **So there is a *kill* for `L1` on entry to the block.** This means that the only active loan is `L0`, which borrows `x`. This in turn means that `y = y + 1` is not an error.

```mermaid
flowchart TD
  Start["
    ...
  "]
  BB1["
      <b><u>BB1:</u></b>
      p = &x; <b><i>// Gen: L0</i></b>
      ...
      q = &y; <b><i>// Gen: L1</i></b>
      ...
  "]
  BB2["
      <b><u>BB2:</u></b>
      ...
  "]
  BB3["
      <b><u>BB3:</u></b>
      <b><i>// Kill `L1`</i></b> (no live references)
      <b><i>// Active loans: {L0}</i></b>
      y = y + 1;
  "]
  BB4["
      <b><u>BB4:</u></b>
      ...
      read_value(p); // later use of `p`
  "]
 
  Start --> BB1
  BB1 --> BB2
  BB1 --> BB3
  BB2 --> BB4
  BB3 --> BB4
 
  classDef default text-align:left,fill:#ffffff;
  classDef highlight text-align:left,fill:yellow;
  class BB3 highlight
```

## The role of invariance: vec-push-ref

I didn't highlight it before, but invariance plays a really interesting role in this analysis. Let's see another example, a simplified version of [`vec-push-ref`](https://github.com/rust-lang/polonius/blob/0a754a9e1916c0e7d9ba23668ea33249c7a7b59e/inputs/vec-push-ref/vec-push-ref.rs#L5) from polonius:

```rust
let v: Vec<&'v u32>;
let p: &'p mut Vec<&'vp u32>;
let x: u32;

/* P0 */ v = vec![];
/* P1 */ p = &mut v; // Loan L0
/* P2 */ x += 1; // <-- Expect NO error here.
/* P3 */ p.push(&x); // Loan 1
/* P4 */ x += 1; // <-- 💥 Expect an error here!
/* P5 */ drop(v);
```

What makes this interesting? We create a reference `p` at point `P1` that points at `v`. We then insert a borrow of `x` into the reference `p`. **After that point, the reference `p` is dead, but the loan `L1` is still active** -- this is because it is also stored in `v`. This connection between `p` and `v` is what is key about this example.

The way that this connection is reflected in the type system is through *[variance]*. In particular, a type `&mut T` is **invariant** with respect to `T`. This means that when you assign one reference to another, the type that they reference must be exactly the same.

[variance]: https://en.wikipedia.org/wiki/Covariance_and_contravariance_(computer_science)

In terms of the subset graph, invariance works out to creating **bidirectional edges** between origins. Take a look at the resulting subset graph to see what I mean. To keep things simple, I am going to exclude nodes for `p`: the interesting origins here at `'v` (the data in the vector `v`) and `'vp` (the data in the vector referenced by `p` -- which is also `v`).

```mermaid
flowchart TD
    subgraph "Loans"
      L1["L1 (&x)"]
    end
    
    subgraph "'v"
      V_P0["'v_P0"]
      V_P1["'v_P1"]
      V_P2["'v_P2"]
      V_P3["'v_P3"]
      V_P4["'v_P4"]
      V_P5["'v_P5"]
    end

    subgraph "'vp"
      VP_P1["'vp_P1"]
      VP_P2["'vp_P2"]
      VP_P3["'vp_P3"]
    end

    V_P0 --> V_P1 --> V_P2 --> V_P3 --> V_P4 --> V_P5
    
    V_P1 <---> VP_P1
    VP_P1 <---> VP_P2 <---> VP_P3
        
    L1 --> VP_P3
```

The key part here are the bidirectional arrows between `v_P1` and `vp_P1` and between `vp_P1` and `vp_P3`. How did those come about? 

* The first edge resulted from `p = &mut v`. The type of `v` (at `P1`) is `Vec<&'v_P1 u32>`, and that type had to be equal to the referent of `p` (`Vec<&'vp_P1 u32>`). Since the types must be equal, that means `'v_P1: 'vp_P1` and vice versa, hence a bidirectional arrow.
* The second edge resulted from the flow from `P1` to `P3`. The variable `p` is live across that edge, so its type before (`&'p_P1 mut Vec<&'vp_P1 u32>`) must be a subtype of its type after (`&'p_P3 mut Vec<&'vp_P3 u32>`). Because `&mut` references are invariant with respect to their referent types, this implies that `'vp_P1` and `'vp_P3` must be equal.

Put all together, and we see that `L1` can reach `'v_P4` and `'v_P5`, even though it only flowed into an earlier point in the graph. That's cool! We will get the error we expect.

On the other hand, we can also see that there is some imprecision introduced through invariance. The loan `L1` is introduced at point `P3`, and yet it appears to flow from `'vp_P3` backwards in time to `'vp_P2`, `'vp_P1`, over to `'v_P1`, and downward from there. If we were *only* looking at the subset graph, then, we would conclude that both `x += 1` statements in this program are illegal, but in fact only the second one causes a problem.

### Active loans to the rescue (again)

The imprecision we see here is very similar to the imprecision we saw in the original polonius. Effectively, invariance is taking away some of our flow sensitivity. Interestingly, the active loans portion of the analysis makes up for this, in the same way that it did in the [previous post][ppal]. In vec-push-ref, `L1` will only be generated at `P3`, so even though it can reach `'v_P2` via the subset graph, it is not considered active at `P2`. But once it is generated, it is not killed, even when `p` goes dead, because it can flow into `'v_P4`. Therefore we get the one error we expect.

## Conclusion

I'm going to stop this post here. I've described a version of polonius where we give variables distinct types at each program point and then relate those types together to create an improved subset graph. This graph increases the precision of the active loans analysis such that we don't get as many false errors, but it is still imprecise in some ways. 

I think this formulation is interesting for a few reasons. First, the most expensive part of it is going to be the subset graph, which has a LOT of nodes and edges. But that can be compressed significantly with some simple heuristics. Moreover, the core operation we perform on that graph is reachability, and that can be implemented quite efficiently as well (do a [strongly connected components][scc] computation to reduce the graph to a tree, and then you can assign pre- and post-orderings and just compare indices). So I believe it could scale in practice.

[scc]: https://en.wikipedia.org/wiki/Strongly_connected_component

I have worked through a few more classic examples, and I may come back to them in future posts, so far this analysis seems to get the results I expect. However, I would also like to go back and compare it more deeply to the original polonius, as well as to some of the formulations that came out of academia. There is still something odd about leaning on the dataflow check. I hope to talk about some of that in follow-up posts (or perhaps on Zulip or elsewhere with some of you readers!).
