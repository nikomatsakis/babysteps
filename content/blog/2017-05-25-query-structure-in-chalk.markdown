---
layout: post
title: Query structure in chalk
categories: [Rust, Traits, Chalk, PL]
---

For my next post discussing [chalk], I want to take kind of a
different turn. I want to talk about the general struct of **chalk
queries** and how chalk handles them right now. (If you've never heard
of chalk, it's sort of "reference implementation" for Rust's trait
system, as well as an attempt to describe Rust's trait system in terms
of its logical underpinnings; see
[this post for an introduction to the big idea][logic].)

[chalk]: https://github.com/nikomatsakis/chalk/
[logic]: {{ site.baseurl }}/blog/2017/01/26/lowering-rust-traits-to-logic/

### The traditional, interactive Prolog query

In a traditional Prolog system, when you start a query, the solver
will run off and start supplying you with every possible answer it can
find. So if I put something like this (I'm going to start adopting a
more Rust-like syntax for queries, versus the Prolog-like syntax I
have been using):

    ?- Vec<i32>: AsRef<?U>
    
The solver might answer:

    Vec<i32>: AsRef<[i32]>
        continue? (y/n)

This `continue` bit is interesting. The idea in Prolog is that the
solver is finding **all possible** instantiations of your query
that are true. In this case, if we instantiate `?U = [i32]`, then the
query is true (note that the solver did not, directly, tell us a value
for `?U`, but we can infer one by unifying the response with our
original query). If we were to hit `y`, the solver might then give us
another possible answer:

    Vec<i32>: AsRef<Vec<i32>>
        continue? (y/n)

This answer derives from the fact that there is a reflexive impl
(`impl<T> AsRef<T> for T`) for `AsRef`. If were to hit `y` again,
then we might get back a negative response:

    no

Naturally, in some cases, there may be no possible answers, and hence
the solver will just give me back `no` right away:

    ?- Box<i32>: Copy
        no

In some cases, there might be an infinite number of responses. So for
example if I gave this query, and I kept hitting `y`, then the solver
would never stop giving me back answers:

    ?- Vec<?U>: Clone
       Vec<i32>: Clone
         continue? (y/n)
       Vec<Box<i32>>: Clone
         continue? (y/n)
       Vec<Box<Box<i32>>>: Clone
         continue? (y/n)
       Vec<Box<Box<Box<i32>>>>: Clone
         continue? (y/n)

As you can imagine, the solver will gleefully keep adding another
layer of `Box` until we ask it to stop, or it runs out of memory.

Another interesting thing is that queries might still have variables
in them. For example:

    ?- Rc<?T>: Clone
    
might produce the answer:

    Rc<?T>: Clone
        continue? (y/n)
        
After all, `Rc<?T>` is true **no matter what type `?T` is**.        

### Do try this at home: chalk has a REPL

I should just note that ever since
[aturon recently added a REPL to chalk](https://github.com/nikomatsakis/chalk/pull/30/),
which means that -- if you want -- you can experiment with some of the
examples from this blog post. It's not really a "polished tool", but
it's kind of fun. I'll give my examples using the REPL.

### How chalk responds to a query

chalk responds to queries somewhat differently. Instead of trying to
enumerate **all possible** answers for you, it is looking for an
**unambiguous** answer. In particular, when it tells you the value for
a type variable, that means that this is the **only possible
instantiation** that you could use, given the current set of impls and
where-clauses, that would be provable.

Overall, chalk's answers have three parts:

- **Status:** Yes, No, or Maybe
- **Refined goal:** a version of your original query with some substitutions
  applied
- **Lifetime constraints:** these are relations that must hold between
  the lifetimes that you supplied as inputs. I'll come to this in a
  bit.
 
*Future compatibility note:* It's worth pointing out that I expect
some the particulars of a "query response" to change, particularly as
aturon continues [the work on negative reasoning][aturon]. I'm
presenting the current setup here, for the most part, but I also
describe some of the changes that are in flight (and expected to land
quite soon).

[aturon]: http://aturon.github.io/blog/2017/04/24/negative-chalk/

Let's look at these three parts in turn.

### The **status** and **refined goal** of a query response

The "status" tells you how sure chalk is of its answer, and it can be
**yes**, **maybe**, or **no**.

A **yes** response means that your query is **uniquely provable**, and
in that case the refined goal that we've given back represents the
only possible instantiation. In the examples we've seen so far, there
was one case where chalk would have responded with yes:

```
> cargo run
?- load libstd.chalk
?- exists<T> { Rc<T>: Clone }
Solution {
    successful: Yes,
    refined_goal: Query {
        value: Constrained {
            value: [
                Rc<?0>: Clone
            ],
            constraints: []
        },
        binders: [
            U0
        ]
    }
}
```

(Since this is the first example using the REPL, a bit of explanation
is in order. First, `cargo run` executs the REPL, naturally. The first
command, `load libstd.chalk`, loads up some standard type/impl
definitions.  The next command, `exists<T> { Rc<T>: Clone }` is the
actual *query*.  In the section of Prolog examples, I used the Prolog
convention, which is to implicitly add the "existential quantifiers"
based on syntax. chalk is more explicit: writing `exists<T> { ... }`
here is saying "is there a `T` such that `...` is true?". In future
examples, I'll skip over the first two lines.)

You can see that the response here (which is just the `Debug` impl for
chalk's internal data structures) included not only `Yes`, but also a
"refined-goal". I don't want to go into all the details of how the
refined goal is represented just now, but if you skip down to the
`value` field you will pick out the string `Rc<?0>: Clone` -- here the
`?0` indicates an existential variable. This is saying thatthe
"refined" goal is the same as the query, meaning that `Rc<T>: Clone`
is true no matter what `Clone` is. (We saw the same thing in the
Prolog case.)

So what about some of the more ambiguous cases. For example, what
happens if we ask `exists<T> { Vec<T>: Clone }`. This case is
trickier, because for `Vec<T>` to be clone, `T` must be `Clone`, so it
matters what `T` is:

```
?- exists<T> { Vec<T>: Clone }
Solution {
    successful: Maybe,
    ... // elided for brevity
}
```

Here we get back **maybe**. This is chalk's way of saying that the
query is provable for some instants of `?T`, but we need more type
information to find a *unique* answer. The idea is that we will
continue type-checking or processing in the meantime, which may yield
results that further constrain `?T`; e.g., maybe we find a call to
`vec.push(22)`, indicating that the type of the values within is
`i32`. Once that happens, we can repeat the query, but this time with
a more specific value for `?T`, so something like `Vec<i32>: Clone`:

```
?- Vec<i32>: Clone
Solution {
    successful: Yes,
    ...
}
```

Finally, some times chalk can decisively prove that something is not
provable. This would occur if there is just no impl that could
possibly apply (but see [aturon's post][aturon], which covers how we
plan to extend chalk to be able to reason beyond a single crate):

```
?- Box<i32>: Copy
`Copy` is not implemented for `Box<i32>` in environment `Env(U0, [])`
```

### Refined goal in action

The refined goal so far hasn't been very important; but it's generally
a way for the solver to communicate back a kind of **substitution** --
that is, to communicate back what values the type variables have to
have in order for the query to be provable. Consider this query:

```
?- exists<U> { Vec<i32>: AsRef<Vec<U>> }
```

Now, in general, a `Vec<i32>` implements `AsRef` twice:

- `Vec<i32>: AsRef<Slice<i32>>` (chalk doesn't understand the syntax `[i32]`, so I made a type `Slice` for it)
- `Vec<i32>: AsRef<Vec<i32>>`

But here, we know we are looking for `AsRef<Vec<U>>`. This implies
then that `U` must be `i32`. And indeed, if we give this query, chalk
tells us so, using the refined goal:

```
?- exists<U> { Vec<i32>: AsRef<Vec<U>> }
Solution {
    successful: Yes,
    refined_goal: Query {
        value: Constrained {
            value: [
                Vec<i32>: AsRef<Vec<i32>>
            ],
            constraints: []
        },
        binders: []
    }
}
```

Here you can see that there are no variables. Instead, we see
`Vec<i32>: AsRef<Vec<i32>>`. If we unify this with our original query
(skipping past the `exists` part), we can deduce that `U = i32`.

You might imagine that the refined goal can only be used when the
response is **yes** -- but, in fact, this is not so. There are times
when we can't say for sure if a query is provable, but we can still
say something about what the variables must be for it to be provable.
Consider this example:

```
?- exists<U, V> { Vec<Vec<U>>: AsRef<Vec<V>> }
Solution {
    successful: Maybe,
    refined_goal: Query {
        value: Constrained {
            value: [
                Vec<Vec<?0>>: AsRef<Vec<Vec<?0>>>
            ],
            constraints: []
        },
        binders: [
            U0
        ]
    }
}
```

Here, we were asking if `Vec<Vec<U>>` implements `AsRef<Vec<V>>`. We
got back a **maybe** response. This is because the `AsRef` impl
requires us to know that `U: Sized`, and naturally there are many
sized types that `U` could be, so we need to wait until we get more
information to give back a definitive response.

However, leaving aside concerns about `U: Sized`, we can see that
`Vec<Vec<U>>` must equal `Vec<V>`, which implies that, for this query
to be provable, `Vec<U> = V` must hold. And the refined goal reflects
as much:

```
Vec<Vec<?0>>: AsRef<Vec<Vec<?0>>>
```

### Open vs closed queries

Queries in chalk are always "closed" formulas, meaning that all the
variables that they reference are bound by either an `exists<T>` or a
`forall<T>` binder. This is in contrast to how the compiler works, or
a typical prolog implementation, where a trait query occurs in the
context of an ongoing set of processing. In terms of the current rustc
implementation, the difference is that, in rustc, when you wish to do
some trait selection, you invoke the trait solver with an inference
context in hand.  This defines the context for any inference variables
that appear in the query.

In chalk, in contrast, the query starts with a "clean slate". The only
context that it needs is the global context of the entire program --
i.e., the set of impls and so forth (and you can consider those part
of the query, if you like).

To see the difference, consider this chalk query that we looked at earlier:

```
?- exists<U> { Vec<i32>: AsRef<Vec<U>> }
```

In rustc, such a query would look more like `Vec<i32>:
AsRef<Vec<?22>>`, where we have simply used an existing inference
variable (`?22`). Moreover, the current implementation simply gives
back the yes/maybe/no part of the response, and does not have a notion
of a refined goal. This is because, since we have access to the raw
inference variable, we can just unify `?22` (e.g., with `i32`) as a
side-effect of processing the query.

The new idea then is that when some part of the compiler needs to
prove a goal like `Vec<i32>: AsRef<Vec<?22>>`, it will first create a
**canonical** query from that goal
([chalk code is in `query.rs`][query-rs]). This is done by replacing
all the random inference variables (like `?22`) with existentials. So
you would get `exists<T> Vec<i32>: AsRef<Vec<T>>` as the output. One
key point is that this query is independent of the precise inference
variables involved: so if we have to solve this same query later, but
with different inference variables (e.g., `Vec<i32>:
AsRef<Vec<?44>>`), when we make the canonical form of that query, we'd
get the same result.

[query-rs]: https://github.com/nikomatsakis/chalk/blob/1f63c8ad20d27f3ef394f230a56430c89482d8d4/src/solve/infer/query.rs#L10-L39

Once we have the canonical query, we can
[invoke chalk's solver](https://github.com/nikomatsakis/chalk/blob/1f63c8ad20d27f3ef394f230a56430c89482d8d4/src/solve/solver/mod.rs#L27-L29). The
code here varies depending on the kind of goal, but the basic strategy
is the same. We create a
["fulfillment context"](https://github.com/nikomatsakis/chalk/blob/1f63c8ad20d27f3ef394f230a56430c89482d8d4/src/solve/fulfill.rs),
which is the combination of
[an inference context](https://github.com/nikomatsakis/chalk/blob/1f63c8ad20d27f3ef394f230a56430c89482d8d4/src/solve/fulfill.rs#L14)
(a set of inference variables) and
[a list of goals we have yet to prove](https://github.com/nikomatsakis/chalk/blob/1f63c8ad20d27f3ef394f230a56430c89482d8d4/src/solve/fulfill.rs#L15). (The
compiler has a similar data structure, but it is setup somewhat
differently; for example, it doesn't own an inference context itself.)

Within this fulfillment context, we can
["instantiate"](https://github.com/nikomatsakis/chalk/blob/1f63c8ad20d27f3ef394f230a56430c89482d8d4/src/solve/fulfill.rs#L34-L39)
the query, which means that we replace all the variables bound in an
`exists<>` binder with an inference variable (here is
[an example of code invoking `instantiate()`](https://github.com/nikomatsakis/chalk/blob/1f63c8ad20d27f3ef394f230a56430c89482d8d4/src/solve/match_program_clause.rs#L28). This
effectively converts back to the original form, but with fresh
inference variables. So `exists<T> Vec<i32>: AsRef<Vec<T>>` would
become `Vec<i32>: AsRef<Vec<?0>>`. Next we can actually try to prove
the goal, for example by searching through each impl,
[unifying the goal with the impl header](https://github.com/nikomatsakis/chalk/blob/1f63c8ad20d27f3ef394f230a56430c89482d8d4/src/solve/match_program_clause.rs#L42-L44),
and then
[recursively processing the where-clauses on the impl](https://github.com/nikomatsakis/chalk/blob/1f63c8ad20d27f3ef394f230a56430c89482d8d4/src/solve/match_program_clause.rs#L45-L49)
to make sure they are satisfied.

An advantage of the chalk approach where queries are closed is that
they are much easier to cache. We can solve the query once and then
"replay" the result an endless number of times, so long as the
enclosing context is the same.

### Lifetime constraints

I've glossed over one important aspect of how chalk handles queries,
which is the treatment of **lifetimes**. In addition to the refined
goal, the response from a chalk query also includes a set of
**lifetime constraints**. Roughly speaking, the model is that the
chalk engine gives you back the lifetime constraints that *would have
to be satisfied* for the query to be provable.

In other words, if you have a full, lifetime-aware logic, you might
say that the query is provable in some environment `Env` that also
includes some facts about the lifetimes (i.e., which lifetime outlives
which other lifetime, and so forth):

    Env, LifetimeEnv |- Query
    
but in chalk we are only giving in `Env`, and the engine is giving
back to us a `LifetimeEnv`:

    chalk(Env, Query) = LifetimeEnv
    
with the intention that we know that if we can prove that `LifetimeEnv`
holds, then `Query` also holds.

One of the main reasons for this split is that we want to ensure that
the results from a chalk query do not depend on the specific lifetimes
involved. This is because, in part, we are going to be solving chalk
queries in contexts when lifetimes have been fully erased, and hence
we don't actually *know* the original lifetimes or their relationships
to one another.  (In this case, the idea is roughly that we will get
back a `LifetimeEnv` with the relationships that would have to hold,
but we can be sure that an earlier phase in the compiler has proven to
us that this `LifetimeEnv` will be satisfied.)

Anyway, I plan to write a follow-up post (or more...) focusing just on
lifetime constraints, so I'll leave it at that for now. This is also
an area where we are doing some iteration, particularly because of the
interactions with specialization, which are complex.

### Future plans

Let me stop here to talk a bit about the changes we have
planned. aturon has been working on a branch that makes a few key
changes. First, we will **replace the notion of "refined goal" with a
more straight-up substitution**. That is, we'd like chalk to answer
back with something that just tells you the values for the variables
you've given.  This will make later parts of the query processing
easier.

Second, following the approach that
[aturon outlined in their blog post][aturon], when you get back a
"maybe" result, we are actually going to be considering two cases. The
current code will return a refined substitution only if there is a
**unique assignment to your input variables that must be true** for
the goal to be provable. But in the newer code, we will also have the
option to return a "suggestion" -- something which isn't **necessary**
for the goal to be provable, but which we think is likely to be what
the user wanted. We hope to use this concept to help replicate, in a
more structured and bulletproof way, some of the heuristics that are
used in rustc itself.

Finally, we plan to implement the "modal logic" operators, so that you
can make queries that explicitly reason about "all crates" vs "this
crate".




