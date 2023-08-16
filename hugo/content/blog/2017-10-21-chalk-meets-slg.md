---
categories:
- Rust
- Traits
- Chalk
- PL
date: "2017-10-21T00:00:00Z"
slug: chalk-meets-slg
title: Chalk meets SLG
---

For the last month or so, I've gotten kind of obsessed with exploring
a new evaluation model for Chalk. Specifically, I've been looking at
adapting the [SLG algorithm][nftd], which is used in the
[XSB Prolog engine][XSB]. I recently
[opened a PR that adds this SLG-based solver as an alternative][PR],
and this blog post is an effort to describe how that PR works, and
explore some of the advantages and disadvantages I see in this
approach relative to
[the current solver that I described in my previous post][pp].

[XSB]: http://xsb.sourceforge.net/
[pp]: http://smallcultfollowing.com/babysteps/blog/2017/09/12/tabling-handling-cyclic-queries-in-chalk/
[nftd]: https://link.springer.com/chapter/10.1007/3-540-48159-1_12
[ews]: http://www.sciencedirect.com/science/article/pii/0743106694000285
[PR]: https://github.com/rust-lang-nursery/chalk/pull/59

### TL;DR

For those who don't want to read all the details, let me highlight the
things that excite me most about the new solver:

- There is a very strong caching story based on tabling.
- It handles negative reasoning very well, which is important for coherence.
- It guarantees termination without relying on overflow, but rather a
  notion of maximum size.
- There is a lot of work on how to execute SLG-based designs very
  efficiently (including virtual machine designs).

However, I also have some concerns. For one thing, we have to figure
out how to include coinductive reasoning for auto traits and a few
other extensions. Secondly, the solver as designed always enumerates
all possible answers up to a maximum size, and I am concerned that in
practice this will be very wasteful. I suspect both of these problems
can be solved with some tweaks.

### What is this SLG algorithm anyway?

There is a lot of excellent work exploring the SLG algorithm and
extensions to it. In this blog post I will just focus on the
particular variant that I implemented for Chalk, which was heavily
based on this paper
["Efficient Top-Down Computation of Queries Under the Well-formed Semantics" by Chen, Swift, and Warren (JLP '95)][EWFS],
though with some extensions from other work (and some of my own).

Like a traditional Prolog solver, this new solver explores
[**all possibilities in a depth-first, tuple-at-a-time fashion**](#all-possibilities-depth-first-tuple-at-a-time),
though with some extensions to
[**guarantee termination**](#guaranteed-termination)[^term1]. Unlike a
traditional Prolog solver, however, it natively incorporates
[**tabling**](#tabling) and has a strong story for
[**negative reasoning**][neg]. In the rest of the post, I will go into
each of those bolded terms in more detail (or you can click on one of
them to jump directly to the corresponding section).

[neg]: #negative-reasoning-and-the-well-founded-semantics
[EWFS]: https://ac.els-cdn.com/0743106694000285/1-s2.0-0743106694000285-main.pdf?_tid=f8beb358-b642-11e7-b052-00000aacb35f&acdnat=1508578621_12290e1834d94c48d36219f58be6e87f
[^term1]: True confessions: I have never (personally) managed to make a non-trivial Prolog program terminate. I understand it can be done. Just not by me.

### All possibilities, depth-first, tuple-at-a-time

One important property of the new SLG-based solver is that it, like
traditional Prolog solvers, is **complete**, meaning that it
will find **all possible answers** to any query[^term2]. Moreover, like
Prolog solvers, it searches for those answers in a so-called
**depth-first, tuple-at-a-time** fashion. What this means is that,
when we have two subgoals to solve, we will fully explore the
implications of one answer through multiple subgoals before we turn to
the next answer. This stands in contrast to our current solver, which
rather breaks down goals into subgoals and processes each of them
entirely before turning to the next. As I'll show you now, our current
solver can sometimes fail to find solutions as a result (but, as I'll
also discuss, our current solver's approach has advantages too).

[^term2]: Assuming termination. More on that later.

Let me give you an example to make it more concrete. Imagine this
program:

```rust
// sour-sweet.chalk
trait Sour { }
trait Sweet { }

struct Vinegar { }
struct Lemon { }
struct Sugar { }

impl Sour for Vinegar { }
impl Sour for Lemon { }

impl Sweet for Lemon { }
impl Sweet for Sugar { }
```

Now imagine that we had a query like:

```
exists<T> { T: Sweet, T: Sour }
```
    
That is, find me some type `T` that is both sweet and
sour. If we plug this into Chalk's current solver, it gives back an
"ambiguous" result (this is running on [my PR][PR]):

```
> cargo run -- --program=sour-sweet.chalk
?- exists<T> { T: Sour, T: Sweet }
Ambiguous; no inference guidance
```

This is because of the way that our solver handles such compound
queries; specifially, the way it breaks them down into individual
queries and performs each one recursively, always looking for a
**unique** result. In this case, it would first ask "is there a unique
type `T` that is `Sour`?"  Of course, the answer is no -- there are
two such types. Then it asks about `Sweet`, and gets the same
answer. This leaves it with nowhere to go, so the final result is
"ambiguous".

The SLG solver, in contrast, tries to **enumerate** individual answers
and see them all the way through. If we ask it the same query, we see
that it indeed **finds** the unique answer `Lemon` (note the use of `--slg`
in our `cargo run` command to enable the SLG-based solver):

```
> cargo run -- --program=sour-sweet.chalk --slg
?- exists<T> { T: Sour, T: Sweet }     
1 answer(s) found:
- ?0 := Lemon
```

This result is saying that the value for the 0th (i.e., first)
existential variable in the query (i.e., `T`) is `Lemon`.[^notsweet]

[^notsweet]: Some might say that lemons are not, in fact, sweet. Well fooey. I'm not rewriting this blog post now, dang it.

In general, the way that the SLG solver proceeds is kind of like a sort of
loop. To solve a query like `exists<T> { T: Sour, T: Sweet }`, it is
sort of doing something like this:

```
for T where (T: Sour) {
  if (T: Sweet) {
    report_answer(T);
  }
}
```

(The actual struct is a bit complex because of the possibility of
cycles; this is where **tabling**, the subject of a later section,
comes in, but this will do for now.)

As we have seen, a tuple-at-a-time strategy finds answers that our
current strategy, at least, does not. If we adopted this strategy
wholesale, this could have a very concrete impact on what the Rust
compiler is able to figure out. Consider these two functions, for
example (assuming that the traits and structs we declared earlier are
still in scope):

```rust
fn foo() {
  let vec: Vec<_> = vec![];
  //           ^
  //           |
  // NB: We left the element type of this vector
  // unspecified, so the compiler must infer it.

  bar(vec);
  //   ^
  //   |
  // This effectively generates the two constraints
  //
  //     ?T: Sweet
  //     ?T: Sour
  //
  // where `?T` is the element type of our vector.
}

fn bar<T: Sweet + Sour>(x: Vec<T>) {
}
```

Here, we wind up creating the very sort of constraint I was talking
about earlier. rustc today, which follows a chalk-like strategy, will
[fail compilation](https://play.rust-lang.org/?gist=66b525d27e973a07a9a8219e8fec9e6c&version=stable),
demanding a type annotation:

```
error[E0282]: type annotations needed
  --> src/main.rs:15:21
     |
  15 |   let vec: Vec<_> = vec![];
     |       ---           ^^^^^^ cannot infer type for `T`
     |       |
     |       consider giving `vec` a type
```     

An SLG-based solver of course could find a unique answer here. (Also,
rustc could give a more precise error message here regarding *which*
type you ought to consider giving.)

Now, you might ask, is this a **realistic** example? In other words,
here there happens to be a single type that is both `Sour` and
`Sweet`, but how often does that happen in practice? Indeed, I expect
the answer is "quite rarely", and thus the extra expressiveness of the
tuple-at-a-time approach is probably not that useful in practice. (In
particular, the type-checker does not want to "guess" types on your
behalf, so unless we can find a single, unique answer, we don't
typically care about the details of the result.) Still, I could
imagine that in some narrow circumstances, especially in crates like
[Diesel](http://diesel.rs/) that use traits as a complex form of
meta-programming, this extra expressiveness may be of use. (And of
course having the trait solver fail to find answers that exist kind of
sticks in your craw a bit.)

There are some other potential downsides to the tuple-at-a-time
approach. For example, there may be an awfully large number of types
that implement `Sweet`, and we are going to effectively enumerate them
all while solving. In fact, there might even be an **infinite** set of
types! That brings me to my next point.

### Guaranteed termination

Imagine we extended our previous program with something like a type
`HotSauce<T>`. Naturally, if you add hot sauce to something sour, it
remains sour, so we can also include a trait impl to that effect:

```
struct HotSauce<T> { }
impl<T> Sour for HotSauce<T> where T: Sour { }
```

Now if we have the query `exists<T> { T: Sour }`, there are actually
an infinite set of answers. Of course we can have `T = Vinegar` and `T
= Lemon`. And we can have `T = HotSauce<Vinegar>` and `T =
HotSauce<Lemon>`. But we can also have `T = HotSauce<HotSauce<Lemon>>`.
Or, for the real hot-sauce enthusiast[^me], we might have:

    T = HotSauce<HotSauce<HotSauce<HotSauce<Lemon>>>>
    
[^me]: Try [this stuff](https://store.davesgourmet.com/ProductDetails.asp?ProductCode=DAIN), it's for real.

In fact, we might have an infinite number of `HotSauce` types wrapping
either `Lemon` or `Vinegar`.

This poses a challenge to the SLG solver. After all, it tries to
enumerate **all** answers, but in this case there are an infinite
number! The way that we handle this is basically by imposing a
**maximum size** on our answers. You could measure size various ways. A common choice is to use depth,
but the total size of a type can still grow exponentially relative to
the depth, so I am instead limiting the maximum size of the tree as a whole.
So, for example,
our really long answer had a size of 5:

    T = HotSauce<HotSauce<HotSauce<HotSauce<Lemon>>>>

The idea then is that once an answer exceeds that size, we start to
**approximate** the answer by introducing variables.[^rr] In this
case, if we imposed a maximum size of 3, we might transform that
answer into:

    exists<U> { T = HotSauce<HotSauce<U>> }

The original answer is an *instance* of this -- that is, we can
substitute `U = HotSauce<HotSauce<Lemon>>` to recover it.

Now, when we introduce variables into answers like this, we lose some
precision. We can now only say that `exists<U> { T =
HotSauce<HotSauce<U>> }` **might** be an answer, we can't say for
sure. It's a kind of "ambiguous" answer[^WFS].

[^rr]: This technique is called ["radial restraint"] by its authors.
["radial restraint"]: http://www3.cs.stonybrook.edu/~tswift/webpapers/aaai-13.pdf
[^WFS]: In terms of the well-formed semantics that we'll discuss later, its truth value is considered "unknown".

So let's see it in action. If I invoke the SLG solver using a maximum
size of 3, I get the following:[^5answers]

```
> cargo run -- --program=sour-sweet.chalk --slg --overflow-depth=3
7 answer(s) found:
- ?0 := Vinegar
- ?0 := Lemon
- ?0 := HotSauce<Vinegar>
- ?0 := HotSauce<Lemon>
- exists<U0> { ?0 := HotSauce<HotSauce<?0>> } [ambiguous]
- ?0 := HotSauce<HotSauce<Vinegar>>
- ?0 := HotSauce<HotSauce<Lemon>>
```

[^5answers]: Actually, in the course of writing this blog post, I found I sometimes only see 5 answers, so YMMV. Some kind of bug I suppose. (Update: fixed it.)

Notice that middle answer:

```
- exists<U0> { ?0 := HotSauce<HotSauce<?0>> } [ambiguous]
```

This is precisely the point where the abstraction mechanism kicked in,
introducing a variable. Note that the two instances of `?0` here refer
to different variables -- the first one, in the "key", refers to the
0th variable in our original query (what I've been calling `T`). The
second `?0`, in the "value" refers, to the variable introduced by the
`exists<>` quantifier (the `U0` is the "universe" of that variable,
which has to do with higher-ranked things and I won't get into here).
Finally, you can see that we flagged this result as `[ambiguous]`,
because we had to truncate it to make it fit the maximum size.

Truncating answers isn't on its own enough to guarantee termination.
It's also possible to setup an ever-growing number of **queries**.
For example, one could write something like:

```rust
trait Foo { }
impl<T> Foo for T where HotSauce<T>: Foo { }
```

If we try to solve (say) `Lemon: Foo`, we will then have to solve
`HotSauce<Lemon>`, and `HotSauce<HotSauce<Lemon>>`, and so forth ad
infinitum. We address this by the same kind of tweak. After a point,
if a query grows too large, we can just truncate it into a shorter
one[^sa]. So e.g. trying to solve

    exists<T> HotSauce<HotSauce<HotSauce<HotSauce<T>>>>: Foo
    
with a maximum size of 3 would wind up "redirecting" to the query

    exists<T> HotSauce<HotSauce<HotSauce<T>>>: Foo
    
Interestingly, unlike the "answer approximation" we did earlier,
redirecting queries like this doesn't produce imprecision (at least
not on its own). The new query is a generalization of the old query,
and since we generate **all** answers to any given query, we will find
the original answers we were looking for (and then some more). Indeed,
if we try to perform this query with the SLG solver, it correctly
reports that there exists no answer (because this recursion will never
terminate):

```
> cargo run -- --program=sour-sweet.chalk --slg --overflow-depth=3
?- Lemon: Foo
No answers found.
```       

(The original solver panics with an overflow error.)

[^sa]: This technique is called ["subgoal abstraction"] by its authors.
["subgoal abstraction"]: http://www3.cs.stonybrook.edu/~tswift/webpapers/tocl-14.pdf

### Tabling

The key idea of **tabling** is to keep, for each query that we are
trying to solve, a table of answers that we build up over
time. Tabling came up in my [previous post][pp], too, where I
discussed how we used it to handle cyclic queries in the current
solver. But the integration into SLG is much deeper.

In SLG, we wind up keeping a table for **every** subgoal that we
encounter. Thus, any time that you have to solve the same subgoal
twice in the course of a query, you automatically get to take
advantage of the cached answers from the previous attempt. Moreover,
to account for cyclic dependencies, tables can be linked together, so
that as new answers are found, the suspended queries are re-awoken.

Tables can be in one of two states:

- **Completed:** we have already found all the answers for this query.
- **Incomplete:** we have not yet found all the answers, but we may have found some of them.

By the time the SLG processing is done, all tables will be in a
completed state, and thus they serve purely as caches. These tables
can also be remembered for use in future queries. I think integrating
this kind of caching into rustc could be a tremendous performance
enhancement.

#### Variant- versus subsumption-based tabling

I implemented "variant-based tabling" -- in practical terms, this
means that whenever we have some subgoal `G` that we want to solve, we
first convert it into a canonical form. So imagine that we are in some
inference context and `?T` is a variable in that context, and we want
to solve `HotSauce<?T>: Sour`. We would replace that variable `?T` with `?0`,
since it is the first variable we encountered as we traversed the type,
thus giving us a canonical query like:

    HotSauce<?0>: Sour
    
This is then the key that we use to lookup if there exists a table
already. If we do find such a table, it will have a bunch of answers; these
answers are in the form of substitutions, like

- `?0 := Lemon`
- `?0 := Vinegar`

and so forth. At this point, this should start looking familiar: you
may recall that earlier in the post I was showing you the output from
the chalk repl, which consisted of stuff like this:

```
> cargo run -- --program=sour-sweet.chalk --slg
?- exists<T> { T: Sour, T: Sweet }     
1 answer(s) found:
- ?0 := Lemon
```

This printout is exactly dumping the contents of the table that we
constructed for our `exists<T> { T: Sour, T: Sweet }` query. That
query would be canonicalized to `?0: Sour, ?0: Sweet`, and hence we
have results in terms of this canonical variable `?0`.

However, this form of tabling that I just described has its
limitations. For example, imagine that I we have the table for
`exists<T> { T: Sour, T: Sweet }` all setup, but then I do a query
like `Lemon: Sour, Lemon: Sweet`. In the solver as I wrote it today,
this will create a brand new table and begin computation again.  This
is somewhat unfortunate, particularly for a setting like rustc, where
we often solve queries first in the generic form (during
type-checking) and then later, during trans, we solve them again for
specific instantiations.

The [paper about SLG that I pointed you at earlier][nftd] describes an
alternative approach called "subsumption-based tabling", in which you
can reuse a table's results even if it is not an exact match for the
query you are doing. This extension is not *too* difficult, and we
could consider doing something similar, though we'd have to do some
more experiments to decide if it pays off. 

(In rustc, for example, subsumption-based tabling might not help us
that much; the queries that we perform at trans time are often not the
same as the ones we perform during type-checking. At trans time, we
are required to "reveal" specialized types and take advantage of other
details that type-checking does not do, so the query results are
somewhat different.)

### Negative reasoning and the well-founded semantics

One last thing that the SLG solver handles quite well is negative
reasoning. In coherence -- and maybe elsewhere in Rust -- we want to
be able to support **negative** queries, such as:

    not { exists<T> { Vec<T>: Foo } }

This would assert that there is **no type** `T` for which `Vec<T>:
Foo` is implemented. In the SLG solver, this is handled by creating a
table for the positive query (`Vec<?0>: Foo`) and letting that
execute. Once it completes, we can check whether the table has any
answers or not.

There are some edge cases to be careful of though. If you start to
allow negative reasoning to be used more broadly, there are logical
pitfalls that start to arise. Consider the following Rust impls, in a
system where we supported negative goals:

```rust
trait Foo { }
trait Bar { }

impl<T> Foo for T where T: !Bar { }
impl<T> Bar for T where T: !Foo { }
```

Now consider the question of whether some type `T` implements `Foo`
and `Bar`. The trouble with these two impls is that the answers to
these two queries (`T: Foo`, `T: Bar`) are no longer independent from
one another. We could say that `T: Foo` holds, but then `T: Bar` does
not (because `T: !Foo` is false). Alternatively, we could say that `T:
Bar` holds, but then `T: Foo` does not (because `T: !Bar` is
false). How is the compiler to choose?

The SLG solver chooses not to choose. It is based on the
**well-founded semantics**, which ultimately assigns one of three
results to every query: true, false, or unknown. In the case of
negative cycles like the one above, the answer is "unknown".

(In contrast, our current solver will answer that both `T: Foo` and
`T: Bar` are false, which is clearly wrong. I imagine we could fix
this -- it was an interaction we did not account for in our naive
tabling implementation.)

### Extensions and future work

The SLG papers themselves describe a fairly basic set of logic
programs. These do not include a number of features that we need to
model Rust. My current solver already extends the SLG work to cover
first-order hereditary harrop clauses (meaning the ability to have
queries like `forall<T> { if (T: Clone) { ... } }`) -- this was
relatively straight-forward. But I did not yet cover some of the other
things that the current solver handles:

- Coinductive predicates: To handle auto traits, we need to support coinductive
  predicates like `Send`. I am not sure yet how to extend SLG to handle this.
- Fallback clauses: If you normalize something like `<Vec<u32> as IntoIterator>::Item`,
  the correct result is `u32`. The SLG solver gives back two answers, however: `u32`
  or the unnormalized form `<Vec<u32> as IntoIterator>::Item`. This is not *wrong*,
  but the current solver understands that one answer is "better" than the other.
- Suggested advice: in cases of ambiguity, the current solver knows to privilege where
  clauses and can give "suggestions" for how to unify variables based on those.

The final two points I think can be done in a fairly trivial fashion,
though the full implications of fallback clauses may require some
careful thought, but coinductive predicates seem a bit harder and may require some
deeper tinkering.

### Conclusions

I'm pretty excited about this new SLG-based solver. I think it is a
big improvement over the existing solver, though we still have to work
out the story for auto traits. The things that excited me the most:

- The deeply integrated use of tabling offers a very strong caching story.
- There is a lot of work on efficienctly executing the SLG solving algorithm.
  The work I did is only the tip of the iceberg: there are existing virtual machine
  designs and other things that we could adapt if we wanted to.
  
I am also quite keen on the story around guaranteed termination. I
like that it does not involve a concept of **overflow** -- that is, a
hard limit on the depth of the query stack -- but rather simply a
**maximum size imposed on types**. The problem with overflow is that
it means that the results of queries wind up dependent on where they
were executed, complicating caching and other things. In other words,
a query that may well succeed can wind up failing just because it was
executed as part of something else. This does not happen with the
SLG-based solver -- queries always succeed or fail in the same way.

However, I am also worried -- most notably about the fact that the
current solver is designed to **always** enumerate all the answers to
a query, even when that is unhelpful. I worry that this may waste a
ton of memory in rustc processes, as we are often asked to solve silly
queries like `?T: Sized` during type-checking, which would basically
wind up enumerating nearly all types in the system up to the maximum
size[^ms]. Still, I am confident that we can find ways to address this
shortcoming in time, possibly without deep changes to the algorithm.

### Credit where credit is due

I also want to make sure I thank all the authors of the many papers on
SLG whose work I gleefully ~~stole~~ built upon. This is a list of the
papers that I papers that described techniques that went into the new
solver, in no particular order; I've tried to be exhaustive, but if I
forgot something, I'm sorry about that.

- [Efficient Top-Down Computation of Queries Under the Well-formed Semantics][ewfs]
  - Chen, Swift, and Warren; JLP '95.
  - The specific solution strategy for SLG that I used.
- [A New Formulation of Tabled resolution With Delay][nftd]
  - Swift; EPIA '99
  - Describes SLG in the abstract.
- [Terminating Evaluation of Logic Programs with Finite Three-Valued Models]["subgoal abstraction"]
  - Riguzzi and Swift; ACM Transactions on Computational Logic 2013
  - Describes approximating subgoals. 
- [OLD Resolution with Tabulation][oldt]
  - Tamaki and Sato 86
  - Describes approximating subgoals. 
- [Radial Restraint]["radial restraint"]
  - Grosof and Swift; 2013
  - Describes approximating answers.
- [Scoping constructs in logic programming: Implementation problems and their solution][fohh]
  - Nadathur, Jayaraman, Kwon; JLP '95.
  - Describes how to integrate first-order hereditary harrop clauses into logic programming. 

[fohh]: http://www.sciencedirect.com/science/article/pii/074310669500037K
[oldt]: https://www.researchgate.net/publication/220986525_OLD_Resolution_with_Tabulation

### Footnotes
