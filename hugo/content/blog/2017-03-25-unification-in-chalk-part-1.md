---
categories:
- Rust
- Traits
- Chalk
- PL
date: "2017-03-25T00:00:00Z"
slug: unification-in-chalk-part-1
title: Unification in Chalk, part 1
---

So in [my first post][pp] on [chalk], I mentioned that unification and
normalization of associated types were interesting topics. I'm going
to write a two-part blog post series covering that.  This first part
begins with an overview of how ordinary type unification works during
compilation. The next post will add in associated types and we can see
what kinds of mischief they bring with them.

[pp]: {{ site.baseurl }}/blog/2017/01/26/lowering-rust-traits-to-logic/
[chalk]: https://github.com/nikomatsakis/chalk/

### What is unification?

Let's start with a brief overview of what unification is. When you are
doing type-checking or trait-checking, it often happens that you wind
up with types that you don't know yet. For example, the user might
write `None` -- you know that this has type `Option<T>`, but you don't
know what that type `T` is. To handle this, the compiler will create a
**type variable**. This basically represents an unknown,
to-be-determined type. To denote this, I'll write `Option<?T>`, where
the leading question mark indicates a variable.

The idea then is that as we go about type-checking we will later find
out some constraints that tell us what `?T` has to be. For example,
imagine that we know that `Option<?T>` must implement `Foo`, and we
have a trait `Foo` that is implemented only for `Option<String>`:

```rust
trait Foo { }
impl Foo for Option<String> { }
```

In order for this impl to apply, it must be the case that the self
types are **equal**, i.e., the same type. (Note that trait matching
never considers subtyping.) We write this as a constraint:

    Option<?T> = Option<String>
    
Now you can probably see where this is going. Eventually, we're going
to figure out that `?T` must be `String`. But it's not **immediately**
obvious -- all we see right now is that two `Option` types have to be
equal. In particular, we don't yet have a simple constraint like `?T =
String`. To arrive at that, we have to do **unification**.

### Basic unification

So, to restate the previous section in mildly more formal terms, the
idea with unification is that we have:

- a bunch of **type variables** like `?T`. We often call these
  **existential type variables** because, when you look at things in a
  logical setting, they arise from asking questions like `exists
  ?T. (Option<String> = Option<?T>)` -- i.e., does there exist a type
  `?T` that can make `Option<String>` equal to
  `Option<?T>`.[^universal]
- a bunch of **unification constraints** `U1..Un` like `T1 = T2`, where `T1`
   and `T2` are types.  These are equalities that we know have to be
   true.

[^universal]: Later on, probably not in this post, we'll see universal type variables (i.e., `forall !T`); if you're interested in reading up on how they interact with inference, I recommend ["A Proof Procedure for the Logic of Hereditary Harrop Formulas", by Gopalan Nadathur][pphhf], which has a very concrete explanation.
[pphhf]: http://dl.acm.org/citation.cfm?id=868380

We would like to process these unification constraints and get to
one of two outcomes:

- the unification cannot be solved (e.g., `u32 = i32` just can't be true);
- we've got a **substitution** (mapping) from type variables to their
  values (e.g., `?T => String`) that makes all of the unification
  constraints hold.

Let's start out with a really simple type system where we only have
two kinds of types (in particular, we don't yet have associated types):

```
T = ?X             // type variables
  | N<T1, ..., Tn> // "applicative" types
```

The first kind of type is type variables, as we've seen. The second
kind of type I am calling "applicative" types, which is really not a
great name, but that's what I called it in chalk for whatever reason.
Anyway they correspond to types like `Option<T>`, `Vec<T>`, and even
types like `i32`. Here the name `N` is the **name** of the type (i.e.,
`Option`, `Vec`, `i32`) and the type parameters `T1...Tn` represent
the type parameters of the type. Note that there may be zero of them
(as is the case for `i32`, which is kind of "shorthand" for `i32<>`).

So the idea for unification then is that we start out with an empty
substitution `S` and we have this list of unification constraints
`U1..Un`. We want to pop off the first constraint (`U1`) and figure
out what to do based on what category it falls into. At each step, we
may update our substitution `S` (i.e., we may figure out the value of
a variable). In that case, we'll replace the variable with its value
for all the later steps. Other times, we'll create new, simpler
unification problems.

- `?X = ?Y` -- if `U` equates two variables together, we can replace
  one variable with the other, so we add `?X => ?Y` to our
  substitution, and then we replace all remaining uses of `?X` with
  `?Y`.
- `?X = N<T1..Tn>` -- if we see a type variable equated with an
  applicative type, we can add `?X => N<T1..Tn>` to our substitution
  (and replace all uses of it). But there is catch -- we have to do
  one check first, called the **occurs check**, which I'll describe
  later on.
- `N<X1..Xn> = N<Y1..Yn>` -- if we see two applicative types with the
  same name being equated, we can convert that into a bunch of smaller
  unification problems like `X1 = Y1`, `X2 = Y2`, ..., `Xn = Yn`. The
  idea here is that `Option<Foo> = Option<Bar>` is true if `Foo = Bar` is
  true; so we can convert the bigger problem into the smaller one, and
  then forget about the bigger one.
- `N<...> = M<...> where N != M` -- if we see two application
  types being equated, but their names are different, that's just an
  error. This would be something like `Option<T> = Vec<T>`.

OK, let's try to apply those rules to our example. Remember that we
had one variable (`?T`) and one unification problem (`Option<?T> =
Option<String>`). We start an initial state like this:

    S = [] // empty substitution
    U = [Option<?T> = Option<String>] // one constraint
    
The head constraint consists of two applicative types with the same
name (`Option`), so we can convert that into a simpler equation,
reaching this state:

    S = [] // empty substitution
    U = [?T = String] // one constraint

Now the next constraint is of the kind `?T = String`, so we can update
our substitution. In this case, there are no more constraints, but if
there were, we would replace any uses of `?T` in those constraints
with `String:

    S = [?T => String] // empty substitution
    U = [] // zero constraints

Since there are no more constraints left, we're done! We found a
solution.

Let's do another example. This one is a bit more interesting.
Imagine that we had two variables (`?T` and `?U`) and this
initial state:

    S = []
    U = [(?T, u32) = (i32, ?U),
         Option<?T> = Option<?U>]
         
The first constraint is unifying two tuples -- you can think of a
tuple as an applicative type, so `(?T, u32)` is kind of like
`Tuple2<?T, u32>`. Hence, we will simplify the first equation
into two smaller ones:

    // After unifiying (?T, u32) = (i32, ?U)
    S = []
    U = [?T = i32,
         ?U = u32,
         Option<?T> = Option<?U>]
         
To process the next equation `?T = i32`, we just update the
substitution. We also replace `?T` in the remaining problems
with `i32`, leaving us with this state:

    // After unifiying ?T = i32
    S = [?T => i32]
    U = [?U = u32,
         Option<i32> = Option<?U>]

We can do the same for `?U`:

    // After unifiying ?U = u32
    S = [?T => i32, ?U = u32]
    U = [Option<i32> = Option<u32>]

Now we, as humans, see that this problem is going to wind up
with an error, but the compiler isn't that smart yet. It has
to first break down the remaining unification problem by
one more step:

    // After unifiying Option<i32> = Option<u32>
    S = [?T => i32, ?U = u32]
    U = [i32 = u32]             // --> Error!

And now we get an error, because we have two applicative types with
different names (`i32` vs `u32`).

### The occurs check: preventing infinite types

When describing the unification procedure, I left out one little bit,
but it is kind of important. When we have a unification constraint
like `?X = T` for some type `T`, we can't just **immediately** add `?X
=> T` to our substitution. We have to first check and make sure that
`?X` does not appear in `T`; if it does, that's also an error. In
other words, we would consider a unification constraint like this to
be illegal:

    ?X = Option<?X>
    
The problem here is that this results in an infinitely big type. And I
don't mean a type that occupies an infinite amount of RAM on your
computer (although that may be true). I mean a type that I can't even
write down. Like if I tried to write down a type that satisfies this
inequality, it would look like:

```rust
Option<Option<Option<Option< /* ad infinitum */ >>>>
```

We don't want types like that, they cause all manner of mischief
(think non-terminating compilations). We already know that no such
type arises from our input program (because it has finite size, and it
contains all the types in textual form). But they can arise through
inference if we're not careful. So we prevent them by saying that
whenever we unify a variable `?X` with some value `T`, then `?X`
cannot **occur** in `T` (hence the name "occurs check").

Here is an example Rust program where this could arise:

```rust
fn main() {
    let mut x;    // x has type ?X
    x = None;     // adds constraint: ?X = Option<?Y>
    x = Some(x);  // adds constraint: ?X = Option<?X>
}
```

And indeed if you
[try this example on the playpen](https://is.gd/pc0D6E), you will get
"cyclic type of infinite size" as an error.

### How this is implemented

In terms of how this algorithm is typically **implemented**, it's
quite a bit different than how I presented it here. For example, the
"substitution" is usually implemented through a mutable unification
table, which uses [Tarjan's Union-Find algorithm][uf] (there are a
[number of implementations][crates] available on crates.io); the set
of unification constraints is not necessarily created as an explicit
vector, but just through recursive calls to a `unify` procedure.  The
relevant code in chalk, if you are curious, can be
[found here](https://github.com/nikomatsakis/chalk/blob/6a7bb25402987421d93d02bda3f5d79bf878812c/src/solve/infer/unify.rs).

[uf]: https://en.wikipedia.org/wiki/Disjoint-set_data_structure
[crates]: https://crates.io/search?q=union%20find

The
[main procedure is `unify_ty_ty`](https://github.com/nikomatsakis/chalk/blob/6a7bb25402987421d93d02bda3f5d79bf878812c/src/solve/infer/unify.rs#L69),
which unifies two types. It
[begins by normalizing them](https://github.com/nikomatsakis/chalk/blob/6a7bb25402987421d93d02bda3f5d79bf878812c/src/solve/infer/unify.rs#L71-L75),
which corresponds to applying the substitution that we have built up
so far. It then analyzes the various cases in roughly the way we've
described (ignoring the cases we haven't talked about yet, like
higher-ranked types or associated types):

- [Equating two variables unifies the variables.](https://github.com/nikomatsakis/chalk/blob/6a7bb25402987421d93d02bda3f5d79bf878812c/src/solve/infer/unify.rs#L81)
  You see that [updating the unification table](https://github.com/nikomatsakis/chalk/blob/6a7bb25402987421d93d02bda3f5d79bf878812c/src/solve/infer/unify.rs#L87) corresponds to modifying
  our substitution.
- [Equating a variable and an applicative type](https://github.com/nikomatsakis/chalk/blob/6a7bb25402987421d93d02bda3f5d79bf878812c/src/solve/infer/unify.rs#L91-L92)
  does the
  ["occurs check"](https://github.com/nikomatsakis/chalk/blob/6a7bb25402987421d93d02bda3f5d79bf878812c/src/solve/infer/unify.rs#L207)
  and
  [updates the unification table](https://github.com/nikomatsakis/chalk/blob/6a7bb25402987421d93d02bda3f5d79bf878812c/src/solve/infer/unify.rs#L209).
- [Equating two applicative type recursively equates their arguments](https://github.com/nikomatsakis/chalk/blob/6a7bb25402987421d93d02bda3f5d79bf878812c/src/solve/infer/unify.rs#L107) (in this case by using the [helper trait `Zip`](https://github.com/nikomatsakis/chalk/blob/master/src/zip.rs#L25-L27)).

(Note: these links are fixed to the head commit in chalk as of the
time of this writing; that code may be quite out of date by the time
you read this, of course.)

### Conclusion

This post describes how basic unification works. The unification
algorithm roughly as I presented it was first introduced by
[Robinson][r], I believe, and it forms the heart of
[Hindley-Milner type inference][HM] (used in ML, Haskell, and Rust as
well) -- as such, I'm sure there are tons of other blog posts covering
the same material better, but oh well.

In the next post, I'll talk about how I chose to extend this basic
system to cover associated types. Other interesting topics I would
like to cover include:

- integrating subtyping and lifetimes;
- how to handle generics (in particular, universal quantification like `forall`);
- why it is decidedly non-trivial to integrate add where-clauses like
  `where T = i32` into Rust (it breaks some assumptions that we made
  in this post, in particular).

### Comments

Post any comments or questions in
[this internals thread](https://internals.rust-lang.org/t/blog-series-lowering-rust-traits-to-logic/4673).

### Footnotes

[r]: http://dl.acm.org/citation.cfm?id=321253
[HM]: https://en.wikipedia.org/wiki/Hindley%E2%80%93Milner_type_system
