---
layout: post
title: 'Cyclic queries in chalk'
categories: [Rust, Chalk, Traits]
---

In my [last post about chalk queries][pp], I discussed how the query
model in chalk. Since that writing, there have been some updates, and
I thought it'd be nice to do a new post covering the current model.
This post will also cover the tabling technique that [scalexm][]
implemented for handling cyclic relations and show how that enables us
to implement implied bounds and other long-desired features in an
elegant way. (Nice work, scalexm!)

[pp]: {{ site.baseurl }}/blog/2017/05/25/query-structure-in-chalk/

### What is a chalk query?

A **query** is simply a question that you can ask chalk. For example,
we could ask whether `Vec<u32>` implements `Clone` like so (this is a
transcript of a `cargo run` session in chalk):

```
?- load libstd.chalk
?- Vec<u32>: Clone
Unique; substitution [], lifetime constraints []
```

As we'll see in a second, the answer "Unique" here is basically
chalk's way of saying "yes, it does". Sometimes chalk queries can
contain **existential variables**. For example, we might say
`exists<T> { Vec<T>: Clone }` -- in this case, chalk actually attempts
to not only tell us *if* there exists a type `T` such that `Vec<T>:
Clone`, it also wants to tell us what `T` must be:

```
?- exists<T> { Vec<T>: Clone }
Ambiguous; no inference guidance
```

The result "ambiguous" is chalk's way of saying "probably it does, but
I can't say for sure until you tell me what `T` is".

So you think can think of a chalk query as a kind of subroutine
like `Prove(Goal) = R` that evaluates some *goal* (the query) and returns
a result R which has one of the following forms:

- **Unique:** indicates that the query is provable and there is a unique
  value for all the existential variables.
  - In this case, we give back a **substitution** saying what each existential
    variable had to be.
  - Example: `exists<T> { usize: PartialOrd<T> }` would yield unique
    and return a substitution that `T = usize`, at least today (since
    there is only one impl that could apply, and we haven't
    implemented the open world modality that
    [aturon talked about][aturon-blog] yet).
- **Ambiguous:** the query *may* hold but we could not be sure. Typically,
  this means that there are multiple possible values for the
  existential variables.
  - Example: `exists<T> { Vec<T>: Clone }` would yield ambiguous,
    since there are many `T` that could fit the bill).
  - In this case, we sometimes give back **guidance**, which are suggested
    values for the existential variables. This is not important to this blog post
    so I'll not go into the details.
- **Error:** the query is provably false.

(The form of these answers has changed somewhat since my previous blog
post, because we incorporated some of
[aturon's ideas around negative reasoning][aturon-blog].)

[aturon-blog]: http://aturon.github.io/blog/2017/04/24/negative-chalk/

### So what is a cycle?

As I outlined long ago in my first post on
[lowering Rust traits to logic][lrtl], the way that the `Prove(Goal)`
subroutine works is basically just to iterate over all the possible
ways to prove the given goal and try them one at a time. This often
requires proving subgoals: for example, when we were evaluating `?-
Vec<u32>: Clone`, internally, this would also wind up evaluating `u32:
Clone`, because the impl for `Vec<T>` has a where-clause that `T` must
be clone:

[lrtl]: {{ site.baseurl }}/blog/2017/01/26/lowering-rust-traits-to-logic/


```rust
impl<T> Clone for Vec<T>
where
  T: Clone,
  T: Sized,
{ }
```

Sometimes, this exploration can wind up trying to solve the same goal
that you started with! The result is a **cyclic query** and,
naturally, it requires some special care to yield a valid answer. For
example, consider this setup:

```rust
trait Foo { }
struct S<T> { }
impl<U> Foo for S<U> where U: Foo { }
```

Now imagine that we were evaluating `exists<T> { T: Foo }`:

- Internally, we would process this by first instantiating the
  existential variable `T` with an inference variable, so we wind up
  with something like `?0: Foo`, where `?0` is an as-yet-unknown
  inference variable.
- Then we would consider each impl: in this case, there is only one.
  - For that impl to apply, `?0 = S<?1>` must hold, where `?1` is a
    new variable. So we can perform that unification.
    - But next we must check that `?1: Foo` holds (that is the
      where-clause on the impl). So we would convert this into "closed" form
      by replacing all the inference variables with `exists` binders, giving us
      something like `exists<T> { T: Foo }`. We can now perform this query.
      - Only wait: This is the same query we were *already* trying to
        solve! This is precisely what we mean by a **cycle**.

In this case, the *right* answer for chalk to give is actually `Error`.
This is because there is no **finite** type that satisfies this query.
The only type you could write would be something like

    S<S<S<S<...ad infinitum...>>>>: Foo

where there are an infinite number of nesting levels. As Rust requires
all of its types to have finite size, this is not a legal type. And
indeed if we ask chalk this query, that is precisely what it answers:

```
?- exists<T> { S<T>: Foo }
No possible solution: no applicable candidates
```

But cycles aren't *always* errors of this kind. Consider a variation
on our previous example where we have a few more impls:

```rust
trait Foo { }

// chalk doesn't have built-in knowledge of any types,
// so we have to declare `u32` as well:
struct u32 { }
impl Foo for u32 { }

struct S<T> { }
impl<U> Foo for S<U> where U: Foo { }
```

Now if we ask the same query, we get back an **ambiguous** result,
meaning that there exists many solutions:

```
?- exists<T> { T: Foo }
Ambiguous; no inference guidance
```

What has changed here? Well, introducing the new impl means that there
is now an infinite family of finite solutions:

- `T = u32` would work
- `T = S<u32>` would work
- `T = S<S<u32>>` would work
- and so on.

Sometimes there can even be *unique* solutions. For example, consider
this final twist on the example, where we add a second where-clause
concerning `Bar` to the impl for `S<T>`:

```rust
trait Foo { }
trait Bar { }

struct u32 { }
impl Foo for u32 { }

struct S<T> { }
impl<U> Foo for S<U> where U: Foo, U: Bar { }
//                                 ^^^^^^ this is new
```

Now if we ask the same query again, we get back yet a different response:

```
?- exists<T> { T: Foo }
Unique; substitution [?0 := u32], lifetime constraints []
```

Here, Chalk figured out that `T` must be `u32`. How can this be? Well,
if you look, it's the only impl that can apply -- for `T` to equal
`S<U>`, `U` must implement `Bar`, and there are no `Bar` impls at all.

So we see that when we encounter a cycle during query processing, it
doesn't necessarily mean the query needs to result in an
error. Indeed, the overall query may result in zero, one, or many
solutions. But how does should we figure out what is right? And how do
we avoid recursing infinitely while doing so? Glad you asked.

### Tabling: how chalk is handling cycles right now

Naturally, traditional Prolog interpreters have similar problems. It
is actually quite easy to make a Prolog program spiral off into an
infinite loop by writing what *seem* to be quite reasonable clauses
(quite like the ones we saw in the previous section). Over time,
people have evolved various techniques for handling this. One that is
relevant to us is called **tabling** or **memoization** -- I found
[this paper][tabling-paper] to be a particularly readable
introduction. As part of his work on implied bounds,
[scalexm][] implemented a variant of this idea in chalk.

[tabling-paper]: http://www.public.asu.edu/~dietrich/publications/ExtensionTablesMemoRelations.pdf
[scalexm]: https://github.com/scalexm/

The basic idea is as follows. When we encounter a cycle, we will
actually wind up **iterating** to find the result. Initially, we
assume that a cycle means an error (i.e., no solutions). This will
cause us to go on looking for other impls that may apply **without**
encountering a cycle. Let's assume we find some solution S that
way. Then we can start over, but this time, when we encounter the
cyclic query, we can use S as the result of the cycle, and we would
then check if that gives us a new solution S'.

If you were doing this in Prolog, where the interpreter attempts to
provide **all** possible answers, then you would keep iterating, only
this time, when you encountered the cycle, you would give back two
answers: S and S'. In chalk, things are somewhat simpler: multiple
answers simply means that we give back an ambiguous result.

So the pseudocode for solving then looks something like this:

- Prove(Goal):
  - If goal is ON the stack already:
    - return stored answer from the stack
  - Else, when goal is not on the stack:
    - Push goal on to the stack with an initial answer of **error**
    - Loop
      - Try to solve goal yielding result R (which may generate recursive calls to Solve with the same goal)
      - Pop goal from the stack and return the result R if any of the following are true:
        - No cycle was encountered; or,
        - the result was the same as what we started with; or,
        - the result is ambiguous (multiple solutions).
      - Otherwise, set the answer for Goal to be R and repeat.

If you're curious, the [real chalk code is here][solver]. It is pretty
similar to what I wrote above, except that it also handles
"coinductive matching" for auto traits, which I won't go into now. In
any case, let's apply this to our three examples of proving `exists<T>
{ T: Foo }`:

[solver]: https://github.com/nikomatsakis/chalk/blob/7eb0f085b86986159097da1cb34dc065f2a6c8cd/src/solve/solver.rs#L122-L248

- In the first example, where we only had `impl<U> Foo for S<U> where
  U: Foo`, the cyclic attempt to solve will yield an error (because
  the initial answer for cyclic alls is errors). There is no other way
  for a type to implement `Foo`, and hence the overall attempt to
  solve yields an error. This is the same as what we started with, so
  we just return and we don't have to cycle again.
- In the second example, where we added `impl Foo for u32`, we again
  encounter a cycle and return error at first, but then we see that `T
  = u32` is a valid solution. So our initial result R is
  `Unique[T = u32]`. This is not what we started with, so we try
  again.
  - In the second iteration, when we encounter the cycle trying to
    process `impl<U> Foo for S<U> where U: Foo`, this time we will
    give back the answer `U = u32`. We will then process the
    where-clause and issue the query `u32: Foo`, which succeeds.  Thus
    we wind up yielding a successful possibility, where `T = S<u32>`,
    in addition to the result that `T = u32`. This means that,
    overall, our second iteration winds up producing ambiguity.
- In the final example, where we added a where clause `U: Bar`,
  the first iteration will again produce a result of `Unique[T = u32]`.
  As this is not what we started with, we again try a second iteration.
  - In the second iteration, we will again produce `T = u32` as a result
    for the cycle. This time however we go on to evaluate `u32: Bar`,
    which fails, and hence overall we still only get one successful
    result (`T = u32`).
  - Since we have now reached a fixed point, we stop processing.

### Why do we care about cycles anyway?

You may wonder why we're so interested in handling cycles well. After
all, how often do they arise in practice? Indeed, today's rustc takes
a rather more simplistic approach to cycles. However, this leads to a
number of limitations where rustc fails to prove things that it ought
to be able to do. As we were exploring ways to overcome these
obstacles, as well as integrating ideas like implied bounds, we found
that a proper handling of cycles was crucial.

As a simple example, consider how to handle "supertraits" in Rust. In
Rust today, traits sometimes have supertraits, which are a subset of their
ordinary where-clauses that apply to `Self`:

```rust
// PartialOrd is a "supertrait" of Ord. This means that
// I can only implement `Ord` for types that also implement
// `PartialOrd`.
trait Ord: PartialOrd { }
```

As a result, whenever I have a function that requires `T: Ord`, that
implies that `T: PartialOrd` must also hold:

```rust
fn foo<T: Ord>(t: T) {
  bar(t); // OK: `T: Ord` implies `T: PartialOrd`
}  

fn bar<T: PartialOrd>(t: T) {
  ...
}  
```

The way that we handle this in the Rust compiler is through a
technique called **elaboration**. Basically, we start out with a base
set of where-clauses (the ones you wrote explicitly), and then we grow
that set, adding in whatever supertraits should be implied. This is an
iterative process that repeats until a fixed-point is reached. So the
internal set of where-clauses that we use when checking `foo()` is not
`{T: Ord}` but `{T: Ord, T: PartialOrd}`.

This is a simple technique, but it has some limitations. For example,
[RFC 1927](https://github.com/rust-lang/rfcs/pull/1927) proposed that
we should elaborate not only *supertraits* but arbitrary where-clauses
declared on traits (in general, a
[common request](https://github.com/rust-lang/rust/issues/20671)). Going
further, we have ideas like the
[implied bounds RFC](https://github.com/rust-lang/rfcs/pull/2089).
There are also just known limitations around associated types and
elaboration.

The problem is that the elaboration technique doesn't really scale
gracefully to all of these proposals: often times, the fully
elaborated set of where-clauses is infinite in size. (We somewhat
arbitrarily prevent cycles between supertraits to prevent this
scenario in that special case.)

So we tried in chalk to take a different approach. Instead of doing
this iterative elaboration step, we
[push that elaboration into the solver via special rules](https://github.com/nikomatsakis/chalk/issues/12#issuecomment-286728215).
The basic idea is that we have a special kind of predicate called a
`WF` (well-formed) goal. The meaning of something like `WF(T: Ord)` is
basically "`T` is *capable* of implementing `Ord`" -- that is, `T`
satisfies the conditions that would make it legal to implement
`Ord`. (It doesn't mean that `T` actually *does* implement `Ord`; that
is the predicate `T: Ord`.) As we lower the `Ord` and `PartialOrd` traits
to simpler logic rules, then, we can define the `WF(T: Ord)` predicate like so:

```
// T is capable of implementing Ord if...
WF(T: Ord) :-
  T: PartialOrd. // ...T implements PartialOrd.
```

Now, `WF(T: Ord)` is really an "if and only if" predicate. That is,
there is only one way for `WF(T: Ord)` to be true, and that is by
implementing `PartialOrd`. Therefore, we can define also the *opposite*
direction:

```
// T must implement PartialOrd if...
T: PartialOrd :-
  WF(T: Ord). // ...T is capable of implementing Ord.
```

Now if you think this looks cyclic, you're right! Under ordinary
circumstances, this pair of rules doesn't do you much good. That is,
you can't prove that (say) `u32: PartialOrd` by using these rules, you
would have to use other rules for that (say, rules arising from an
impl).

However, sometimes these rules *are* useful. In particular, if you have
a generic function like the function `foo` we saw before:

```rust
fn foo<T: Ord>() { .. }
```

In this case, we would setup the environment of `foo()` to contain
exactly two predicates `{T: Ord, WF(T: Ord)}`. This is a form of
elaboration, but not the iterative elaboration we had before. We
simply introduce `WF`-clauses.  But this gives us enough to prove that
`T: PartialOrd` (because we know, by assumption, that `WF(T: Ord)`).
What's more, this setup scales to arbitrary where-clauses and other
kinds of implied bounds.

### Conclusion

This post covers the tabling technique that chalk currently uses to
handle cycles, and also the key ideas of how Rust handles elaboration.

The current implementation in chalk is really quite naive. One
interesting question is how to make it more efficient. There is a lot
of existing work on this topic from the Prolog community, naturally,
with the work on the well-founded semantics being among the most
promising (see e.g. [this paper][wfs-paper]). I started doing some
prototyping in this direction, but I've recently become intrigued with
a different approach, where we use the techniques from [Adapton] (or
perhaps other incremental computation systems) to enable fine-grained
caching and speed up the more naive implementation. Hopefully this
will be the subject of the next blog post!

[Adapton]: http://adapton.org/
[wfs-paper]: http://www.sciencedirect.com/science/article/pii/0743106694000285
