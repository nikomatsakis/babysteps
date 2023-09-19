---
layout: post
title: The Lane Table algorithm
---

For some time now I've been interested in better ways to construct
LR(1) parsers. LALRPOP currently allows users to choose between the
full LR(1) algorithm or the LALR(1) subset. Neither of these choices
is very satisfying:

- the full LR(1) algorithm gives pretty intuitive results but produces
  a lot of states; my hypothesis was that, with modern computers, this
  wouldn't matter anymore. This is sort of true -- e.g., I'm able to
  generate and process even the [full Rust grammar][rp] -- but this
  results in a **ton** of generated code.
- the LALR(1) subset often works but sometimes mysteriously fails with
  indecipherable errors. This is because it is basically a hack that
  conflates states in the parsing table according to a heuristic; when
  this heuristic fails, you get strange results.
  
[rp]: https://github.com/nikomatsakis/rustypop

The [Lane Table algorithm][lt] published by Pager and Chen at APPLC
'12 offers an interesting alternative. It is an alternative to earlier
work by Pager, the "lane tracing" algorithm and practical general
method. In any case, the goal is to generate an LALR(1) state machine
*when possible* and gracefully scale up to the full LR(1) state
machine *as needed*.

[lt]: http://cssauh.com/xc/pub/LaneTable_APPLC12.pdf

I found the approach appealing, as it seemed fairly simple, and also
seemed to match what I would try to do
intuitively. [I've been experimenting with the Lane Table algorithm in LALRPOP and I now have a simple prototype that seems to work.][impl]
Implementing it required that I cover various cases that the paper
left implicit, and the aim of this blog post is to describe what I've
done so far. I do not claim that this description is what the authors
originally intended; for all I know, it has some bugs, and I certainly
think it can be made more efficient.

[impl]: https://github.com/nikomatsakis/lalrpop/blob/27e154f07230ee35268bd014a6bc499d840c80b2/lalrpop/src/lr1/lane_table/README.md

My explanation is intended to be widely readable, though I do assume
some familiarity with the basic workings of an LR-parser (i.e., that
we shift states onto a stack, execute reductions, etc). But I'll
review the bits of table construction that you need.

### First example grammar: G0

To explain the algorithm, I'm going to walk through two example
grammars. The first I call G0 -- it is a reduced version of what the
paper calls G1. It is interesting because it does not require
splitting any states, and so we wind up with the same number of states
as in LR(0). Put another way, it is an LALR(1) grammar.

I will be assuming a basic familiarity with the LR(0) and LR(1) state
construction.

#### Grammar G0

```
G0 = X "c"
   | Y "d"
X  = "e" X
   | "e"
Y  = "e" Y
   | "e"
```

The key point here is that if you have `"e" ...`, you could build an
`X` or a `Y` from that `"e"` (in fact, there can be any number of
`"e"` tokens). You ultimately decide based on whether the `"e"` tokens
are followed by a `"c"` (in which case you build an `X`) or a `"d"`
(in which case you build a `Y`).

LR(0), since it has no lookahead, can't handle this case. LALR(1)
*can*, since it augments LR(0) with a token of lookahead; using that,
after we see the `"e"`, we can peek at the next thing and figure out
what to do.

#### Step 1: Construct an LR(0) state machine

We begin by constructing an LR(0) state machine. If you're not familiar
with the process, I'll briefly outline it here, though you may want to
read up separately. Basically, we will enumerate a number of different *states*
indicating what kind of content we have seen so far. The first state `S0` indicates
that we are at the very beginning out "goal item" `G0`:

```
S0 = G0 = (*) X "c"
   | G0 = (*) Y "d"
   | ... // more items to be described later
```   

The `G0 = (*) X "c"` indicates that we have started parsing a `G0`;
the `(*)` is how far we have gotten (namely, nowhere). There are two
items because there are two ways to make a `G0`. Now, in these two
items, immediately to the right of the `(*)` we see the symbols that
we expect to see next in the input: in this case, an `X` or a `Y`.
Since `X` and `Y` are nonterminals -- i.e., symbols defined in the
grammar rather than tokens in the input -- this means we might also be
looking at the beginning of an `X` or a `Y`, so we have to extend `S0`
to account for that possibility (these are sometimes called "epsilon
moves", since these new possibilities arise from consuming *no* input,
which is denoted as "epsilon"):

```
S0 = G0 = (*) X "c"
   | G0 = (*) Y "d"
   | X = (*) "e" X
   | X = (*) "e"
   | Y = (*) "e" Y
   | Y = (*) "e"
```

This completes the state `S0`. Looking at these various possibilities,
we see that a number of things might come next in the input: a `"e"`,
an `X`, or a `Y`. (The *nonterminals* `X` and `Y` can "come next" once
we have seen their entire contents.) Therefore we construct three
successors states: one (`S1`) accounts for what happens when see an
`"e"`. The other two (`S3` and `S5` below) account for what happens
after we recognize an `X` or a `Y`, respectively.

S1 (what happens if we see an `"e"`) is derived by advancing the `(*)`
past the `"e"`:

```
S1 = X = "e" (*) X
   | X = "e" (*)
   | ... // to be added later
   | Y = "e" (*) Y
   | Y = "e" (*)
   | ... // to be added later
```

Here we dropped the `G0 = ...` possibilities, since those would have
required consuming a `X` or `Y`. But we have kept the `X = "e" (*) X`
etc. Again we find that there are nonterminals that can come next (`X`
and `Y` again) and hence we have to expand the state to account for
the possibility that, in addition to being partway through the `X` and
`Y`, we are at the beginning of *another* `X` or `Y`:

```
S1 = X = "e" (*) X
   | X = "e" (*)
   | X = (*) "e"     // added this
   | X = (*) "e" "X" // added this
   | Y = "e" (*) Y
   | Y = "e" (*)
   | Y = (*) "e"     // added this
   | Y = (*) "e" Y   // added this
```

Here again we expect either a `"e"`, an `"X"`, or a `"Y"`. If we again
check what happens when we consume an `"e"`, we will find that we
reach `S1` again (i.e., moving past an `"e"` gets us to the same set
of possibilities that we already saw). The remaining states all arise
from consuming an `"X"` or a `"Y"` from `S0` or `S1`:

```
S2 = X = "e" X (*)

S3 = G0 = X (*) "c"

S4 = Y = "e" Y (*)

S5 = G0 = Y (*) "d"

S6 = G0 = X "c" (*)

S7 = G0 = Y "d" (*)
```

We can represent the set of states as a graph, with edges representing
the transitions between states. The edges are labeled with the symbol
(`"e"`, `X`, etc) that gets consumed to move between states:

```
S0 -"e"-> S1
S1 -"e"-> S1
S1 --X--> S2
S0 --X--> S3
S1 --Y--> S4
S0 --Y--> S5
S3 -"c"-> S6
S5 -"d"-> S7
```

**Reducing and inconsistent states.** Let's take another look at this
state S1:


```
S1 = X = "e" (*) X
   | X = "e" (*)      // reduce possible
   | X = (*) "e"
   | X = (*) "e" "X"
   | Y = "e" (*) Y
   | Y = "e" (*)      // reduce possible
   | Y = (*) "e"
   | Y = (*) "e" Y
```

There are two interesting things about this state. The first is that
it contains some items where the `(*)` comes at the very end, like `X
= "e" (*)`. What this means is that we have seen an `"e"` in the
input, which is enough to construct an `X`. If we chose to do so, that
is called **reducing**. The effect would be to build up an `X`, which
would then be supplied as an input to a prior state (e.g., `S0`).

However, the other interesting thing is that our state actually has
**three** possible things it could do: it could reduce `X = "e" (*)`
to construct an `X`, but it could also reduce `Y = "e" (*)` to
construct a `Y`; finally, it can **shift** an `"e"`. Shifting means
that we do not execute any reductions, and instead we take the next
input and move to the next state (which in this case would be S1
again).

A state that can do both shifts and reduces, or more than one reduce,
is called an **inconsistent state**. Basically it means that there is
an ambiguity, and the parser won't be able to figure out what to do --
or, at least, it can't figure out what to do unless we take some
amount of lookahead into account. This is where LR(1) and LALR(1)
come into play.

In an LALR(1) grammar, we keep the same set of states, but we augment
the reductions with a bit of lookahead. In this example, as we will
see, that suffices -- for example, if you look at the grammar, you
will see that we only need to do the `X = "e" (*)` reduction if the
next thing in the input is a `"c"`. And similarly we only need to do
the `Y = "e" (*)` reduction if the next thing is a `"d"`. So we can
transform the state to add some *conditions*, and then it is clear
what to do:

```
S1 = X = "e" (*) X    shift if next thing is a `X`
   | X = "e" (*)      reduce if next thing is a "c"
   | X = (*) "e"      shift if next thing is a "e"
   | X = (*) "e" "X"  shift if next thing is a "e"
   | Y = "e" (*) Y    shift if next thing is a `Y`
   | Y = "e" (*)      reduce if next thing is a "d"
   | Y = (*) "e"      shift if next thing is a "e"
   | Y = (*) "e" Y    shift if next thing is a "e"
```

Note that the shift vs reduce part is implied by where the `(*)` is:
we always shift unless the `(*)` is at the end. So usually we just
write the lookahead part. Moreover, the "lookahead" for a shift is
pretty obvious: it's whatever to the right of the `(*)`, so we'll
leave that out.  That leaves us with this, where `["c"]` (for example)
means "only do this reduction if the lookahead is `"c"`":

```
S1 = X = "e" (*) X
   | X = "e" (*)      ["c"]
   | X = (*) "e"
   | X = (*) "e" "X"
   | Y = "e" (*) Y
   | Y = "e" (*)      ["d"]
   | Y = (*) "e"
   | Y = (*) "e" Y
```

We'll call this augmented state a LR(0-1) state (it's not *quite*
how a LR(1) state is typically defined). Now that we've added the
lookahead, this state is no longer inconsistent, as the parser always
knows what to do.

The next few sections will show how we can derive this lookahead
automatically.

#### Step 2: Convert LR(0) states into LR(0-1) states.

The first step in the process is to naively convert all of our LR(0)
states into LR(0-1) states (with no additional lookahead). We will
denote the "no extra lookahead" case by writing a special "wildcard"
lookahead `_`. We will thus denote the inconsistent state after
transformation as follows, where each reduction has the "wildcard"
lookahead:

```
S1 = X = "e" (*) X
   | X = "e" (*)     [_]
   | X = (*) "e"
   | X = (*) "e" "X"
   | Y = "e" (*) Y
   | Y = "e" (*)     [_]
   | Y = (*) "e"
   | Y = (*) "e" Y
```

Naturally, the state is still inconsistent.

#### Step 3: Resolve inconsistencies.

In the next step, we iterate over all of our LR(0-1) states. In this
example, we will not need to create new states, but in future examples
we will. The iteration thus consists of a queue and some code like
this:

```rust
let mut queue = Queue::new();
queue.extend(/* all states */);
while let Some(s) = queue.pop_front() {
    if /* s is an inconsistent state */ {
        resolve_inconsistencies(s, &mut queue);
    }
}
```

#### Step 3a: Build the lane table.

To resolve an inconsistent state, we first construct a **lane
table**. This is done by the code in the `lane` module (the `table`
module maintains the data structure). It works by structing at each
conflict and tracing **backwards**. Let's start with the final table
we will get for the state S1 and then we will work our way back to how
it is constructed. First, let's identify the conflicting actions from
S1 and give them indices:

```
S1 = X = (*) "e"         // C0 -- shift "e"
   | X = "e" (*)     [_] // C1 -- reduce `X = "e" (*)`
   | X = (*) "e" "X"     // C0 -- shift "e"
   | X = "e" (*) X
   | Y = (*) "e"         // C0 -- shift "e"
   | Y = "e" (*)     [_] // C2 -- reduce `Y = "e" (*)`
   | Y = (*) "e" Y       // C0 -- shift "e"
   | Y = "e" (*) Y
```

Several of the items can cause "Confliction Action 0" (C0), which is
to shift an `"e"`. These are all mutually compatible. However, there
are also two incompatible actions: C1 and C2, both reductions. In
fact, we'll find that we look back at state S0, these 'conflicting'
actions all occur with distinct lookahead. The purpose of the lane
table is to summarize that information. The lane table we will up
constructing for these conflicting actions is as follows:

```
| State | C0    | C1    | C2    | Successors |
| S0    |       | ["c"] | ["d"] | {S1}       |
| S1    | ["e"] | []    | []    | {S1}       |
```

Here the idea is that the lane table summarizes the lookahead
information contributed by each state. Note that for the *shift* the
state S1 already has enough lookahead information: we only shift when
we see the terminal we need next ("e"). But state C1 and C2, the lookahead
actually came from S0, which is a predecessor state.

As I said earlier, the algorithm for constructing the table works by
looking at the conflicting item and walking backwards. So let's
illustrate with conflict C1. We have the conflicting item `X = "e"
(*)`, and we are basically looking to find its lookahead. We know
that somewhere in the distant past of our state machine there must be
an item like

    Foo = ...a (*) X ...b
    
that led us here. We want to find that item, so we can derive the
lookahead from `...b` (whatever symbols come after `X`).

To do this, we will walk the graph. Our state at any point in time
will be the pair of a state and an item in that state. To start out,
then, we have `(S1, X = "e" (*))`, which is the conflict C1. Because
the `(*)` is not at the "front" of this item, we have to figure out
where this `"e"` came from on our stack, so we look for predecessors
of the state S1 which have an item like `X = (*) e`. This leads us to
S0 and also S1. So we can push two states in our search: `(S0, X = (*)
"e")` and `(S1, X 5B= (*) "e")`. Let's consider each in turn.

The next state is then `(S0, X = (*) "e")`. Here the `(*)` lies at the
front of the item, so we search **the same state** S0 for items that
would have led to this state via an *epsilon move*.  This basically
means an item like `Foo = ... (*) X ...` -- i.e., where the `(*)`
appears directly before the nonterminal `X`. In our case, we will find
`G0 = (*) X "c"`. This is great, because it tells us some lookahead
("c", in particular), and hence we can stop our search. We add to the
table the entry that the state S0 contributes lookahead "c" to the
conflict C1.  In some cases, we might find something like `Foo =
... (*) X` instead, where the `X` we are looking for appears at the
end. In that case, we have to restart our search, but looking for the
lookahead for `Foo`.

The next state in our case is `(S1, X = (*) e)`. Again the `(*)` lies
at the beginning and hence we search for things in the state S1 where
`X` is the next symbol. We find `X = "e" (*) X`. This is not as good
as last time, because there are no symbols appearing after X in this
item, so it does not contribute any lookahead. We therefore can't stop
our search yet, but we push the state `(S1, X = "e" (*) X)` -- this
corresponds to the `Foo` state I mentioned at the end of the last
paragraph, except that in this case `Foo` is the same nonterminal `X`
we started with.

Looking at `(S1, X = "e" (*) X)`, we again have the `(*)` in the
middle of the item, so we move it left, searching for predecessors
with the item `X = (*) e X`. We will (again) find S0 and S1 have such
items. In the case of S0, we will (again) find the context "c", which
we dutifully add to the table (this has no effect, since it is already
present). In the case of S1, we will (again) wind up at the state
`(S1, X = "e" (*) X)`.  Since we've already visited this state, we
stop our search, it will not lead to new context.

At this point, our table column for C1 is complete. We can repeat the
process for C2, which plays out in an analogous way.

#### Step 3b: Update the lookahead

Looking at the lane table we built, we can union the context sets in
any particular column. We see that the context sets for each
conflicting action are pairwise disjoint. Therefore, we can simply
update each reduce action in our state with those lookaheads in mind,
and hence render it consistent:

```
S1 = X = (*) "e"
   | X = "e" (*)     ["c"] // lookahead from C1
   | X = (*) "e" "X"
   | X = "e" (*) X
   | Y = (*) "e"
   | Y = "e" (*)     ["d"] // lookahead from C2
   | Y = (*) "e" Y
   | Y = "e" (*) Y
```

This is of course also what the LALR(1) state would look like (though
it would include context for the other items, though that doesn't play
into the final machine execution).

At this point we've covered enough to handle the grammar G0.  Let's
turn to a more complex grammar, grammar G1, and then we'll come back
to cover the remaining steps.

### Second example: the grammar G1

G1 is a (typo corrected) version of the grammar from the paper. This
grammar is not LALR(1) and hence it is more interesting, because it
requires splitting states.

#### Grammar G1

```
G1 = "a" X "d"
   | "a" Y "c"
   | "b" X "c"
   | "b" Y "d"
X  = "e" X
   | "e"
Y  = "e" Y
   | "e"
```

The key point of this grammar is that when we see `... "e" "c"` and we
wish to know whether to reduce to `X` or `Y`, we don't have enough
information. We need to know what is in the `...`, because `"a" "e"
"c"` means we reduce `"e"` to `Y` and `"b" "e" "c"` means we reduce to
`X`. In terms of our *state machine*, this corresponds to *splitting*
the states responsible for X and Y based on earlier context.

Let's look at a subset of the LR(0) states for G1:

```
S0 = G0 = (*) "a" X "d"
   | G0 = (*) "a" Y "c"
   | G0 = (*) "b" X "c"
   | G0 = (*) "b" X "d"
   
S1 = G0 = "a" (*) X "d"
   | G0 = "a" (*) Y "c"
   | X = (*) "e" X
   | X = (*) "e"
   | Y = (*) "e" Y
   | Y = (*) "e"

S2 = G0 = "b" (*) X "c"
   | G0 = "b" (*) Y "d"
   | X = (*) "e" X
   | X = (*) "e"
   | Y = (*) "e" Y
   | Y = (*) "e"

S3 = X = "e" (*) X
   | X = "e" (*)      // C1 -- can reduce
   | X = (*) "e"      // C0 -- can shift "e"
   | X = (*) "e" "X"  // C0 -- can shift "e"
   | Y = "e" (*) Y
   | Y = "e" (*)      // C2 -- can reduce
   | Y = (*) "e"      // C0 -- can shift "e"
   | Y = (*) "e" Y    // C0 -- can shift "e"
```

Here we can see the problem. The state S3 is inconsistent. But it is
reachable from both S1 and S2. If we come from S1, then we can have (e.g.)
`X "d"`, but if we come from S2, we expect `X "c"`.

Let's walk through our algorithm again. I'll start with step 3a.

#### Step 3a: Build the lane table.

The lane table for state S3 will look like this:

```
| State | C0    | C1    | C2    | Successors |
| S1    |       | ["d"] | ["c"] | {S3}       |
| S2    |       | ["c"] | ["d"] | {S3}       |
| S3    | ["e"] | []    | []    | {S3}       |
```

Now if we union each column, we see that both C1 and C2 wind up with
lookahead `{"c", "d"}`. This is our problem. We have to isolate things
better. Therefore, step 3b ("update lookahead") does not apply. Instead
we attempt step 3c.

#### Step 3c: Isolate lanes

This part of the algorithm is only loosely described in the paper, but
I think it works as follows. We will employ a union-find data
structure. With each set, we will record a "context set", which
records for each conflict the set of lookahead tokens (e.g.,
`{C1:{"d"}}`).

A context set tells us how to map the lookahead to an action;
therefire, to be self-consistent, the lookaheads for each conflict
must be mutually disjoint. In other words, `{C1:{"d"}, C2:{"c"}}` is
valid, and says to do C1 if we see a "d" and C2 if we see a "c". But
`{C1:{"d"}, C2:{"d"}}` is not, because there are two actions.

Initially, each state in the lane table is mapped to itself, and the
conflict set is derived from its column in the lane table:

```
S1 = {C1:d, C2:c}
S2 = {C1:c, C2:d}
S3 = {C0:e}
```

We designate "beachhead" states as those states in the table that are
not reachable from another state in the table (i.e., using the
successors). In this case, those are the states S1 and S2. We will be
doing a DFS through the table and we want to use those as the starting
points.

(Question: is there always at least one beachhead state? Seems like
there must be.)

So we begin by iterating over the beachhead states.

```rust
for beachhead in beachheads { ... }
```

When we visit a state X, we will examine each of its successors Y. We
consider whether the context set for Y can be merged with the context
set for X. So, in our case, X will be S1 to start and Y will be S3.
In this case, the context set can be merged, and hence we union S1, S3
and wind up with the following union-find state:

```
S1,S3 = {C0:e, C1:d, C2:c}
S2    = {C1:c, C2:d}
```

(Note that this union is just for the purpose of tracking context; it
doesn't imply that S1 and S3 are the 'same states' or anything like
that.)

Next we examine the edge S3 -> S3. Here the contexts are already
merged and everything is happy, so we stop. (We already visited S3,
after all.)

This finishes our first beachhead, so we proceed to the next edge, S2
-> S3. Here we find that we **cannot** union the context: it would
produce an inconsistent state. So what we do is we **clone** S3 to
make a new state, S3', with the initial setup corresponding to the row
for S3 from the lane table:

```
S1,S3 = {C0:e, C1:d, C2:c}
S2    = {C1:c, C2:d}
S3'   = {C0:e}
```

This also involves updating our LR(0-1) state set to have a new state
S3'. All edges from S2 that led to S3 now lead to S3'; the outgoing
edges from S3' remain unchanged. (At least to start.)

Therefore, the edge `S2 -> S3` is now `S2 -> S3'`. We can now merge
the conflicts:

```
S1,S3  = {C0:e, C1:d, C2:c}
S2,S3' = {C0:e, C1:c, C2:d}
```

Now we examine the outgoing edge S3' -> S3. We cannot merge these
conflicts, so we search (greedily, I guess) for a clone of S3 where we
can merge the conflicts. We find one in S3', and hence we redirect the
S3 edge to S3' and we are done. (I think the actual search we want is
to make first look for a clone of S3 that is using literally the same
context as us (i.e., same root node), as in this case. If that is not
found, *then* we search for one with a mergable context. If *that*
fails, then we clone a new state.)

The final state thus has two copies of S3, one for the path from S1,
and one for the path from S2, which gives us enough context to
proceed.

### Conclusion

As I wrote, I've been experimenting with the Lane Table algorithm in LALRPOP and
I now have a simple prototype that seems to work. It is not by any means
exhaustively tested -- in fact, I'd call it minimally tested -- but hopefully
I'll find some time to play around with it some more and take it through
its paces. It at least handles the examples in the paper.

The implementation is also inefficient in various ways. Some of them
are minor -- it clones more than it needs to, for example -- and
easily corrected. But I also suspect that one can do a lot more
caching and sharing of results. Right now, for example, I construct
the lane table for each inconsistent state completely from scratch,
but perhaps there are ways to preserve and share results (it seems
naively as if this should be possible). On the other hand,
constructing the lane table can probably be made pretty fast: it
doesn't have to traverse that much of the grammar. I'll have to try it
on some bigger examples and see how it scales.

### Edits

- The lane table I originally described had the wrong value for the
  successor column. Corrected.
