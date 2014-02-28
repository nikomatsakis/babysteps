I would like to propose a small extension to Rust's syntax. I think we
should add a `where` clause as an alternative way to specify type
parameter bounds. The motivation for this change is three-fold:

1. The current syntax for trait bounds is nice for small examples, but
   quickly becomes unwieldy.
2. I believe a `where` clause will help us down the line as we
   increase the expressiveness of traits and other parts of Rust.

Let me give examples of the proposed syntax and then I will expand on
the various points in the motivation one by one.

*A note on timing:* This is a backwards compatible change and I see
no reason to tie it to the 1.0 schedule, though we want to reserve
the keyword `where` (I think we've already done this).

### Example of new syntax

Today, when declared a type parameter, one may introduce trait bounds
following a `:`:

    impl<K:Hash+Eq,V> HashMap<K, V> {
        ..
    }

Sometimes the number of parameters can grow quite large, such as
this example extracted from some rather generic code in `rustc`:

    fn set_var_to_merged_bounds<T:Clone + InferStr + LatticeValue,
                                V:Clone+Eq+ToStr+Vid+UnifyVid<Bounds<T>>>(
                                &self,
                                v_id: V,
                                a: &Bounds<T>,
                                b: &Bounds<T>,
                                rank: uint)
                                -> ures;
                                
I propose to permit a `where` clause that follows the generic parameterized
item but precedes the `{`. Thus the first example could be rewritten:

    impl<K,V> HashMap<K, V>
        where K : Hash + Eq
    {
        ..
    }

Naturally this applies to anything that can be parameterized: `impl`
declarations, `fn` declarations, and possibly `trait` and `struct`
definitions, though those do not current admit trait bounds.

The grammar for a `where` clause would be as follows (BNF):

    WHERE = 'where' BOUND { ',' BOUND } [,]
    BOUND = TYPE ':' TRAIT { '+' TRAIT } [+]
    TRAIT = Id [ '<' [ TYPE { ',' TYPE } [,] ] '>' ]
    TYPE  = ... (same type grammar as today)

The bounds which appear in the `WHERE` clause are unioned together.
Note that we accept the `+` notation in the `where` clause, which
gives the end user some license to bunch together small bounds or
space them out:

    fn set_var_to_merged_bounds<T,V>(&self,
                                     v_id: V,
                                     a: &Bounds<T>,
                                     b: &Bounds<T>,
                                     rank: uint)
                                     -> ures
        where T:Clone,
              T:InferStr,
              T:LatticeValue,
              V:Clone + Eq + ToStr + Vid + UnifyVid<Bounds<T>>,
    {                                     
        ..
    }
    
`where` clauses are strictly more general than the current syntax (see
the section on *future expressiveness* below for more details). The
current syntax would still be accepted and would effectively be
syntactic sugar for a `where` clause.

#### Other syntactic options

Here are some variations on the syntax I considered:

- Do not accept `+` in `where` clauses. I think this makes some
  examples quite verbose, however.
- Repeat the `where` keyword rather than accepting a comma-separated
  list.
- Use the syntax `Trait<...> for Type` instead of `Type : Trait<...>`
  (e.g., `Eq for K` rather than `K: Eq`). This echoes `impl` declarations
  but seems less obvious.
- Use the `:` instead of the `where` keyword. This is ambiguous
  for traits with the list of supertraits. Perhaps the list of
  supertraits and `where` conditions could be mixed together though.

No doubt there are many more.

### Motivation #1: Current syntax can become unwieldy

I think the current syntax works well for short examples like `HashMap`:

    impl<K:Hash+Eq,V> HashMap<K, V> {
        ..
    }

But with longer examples it quickly becomes hard to read and hard
to format:

    fn set_var_to_merged_bounds<T:Clone + InferStr + LatticeValue,
                                V:Clone+Eq+ToStr+Vid+UnifyVid<Bounds<T>>>(
                                &self,
                                v_id: V,
                                a: &Bounds<T>,
                                b: &Bounds<T>,
                                rank: uint)
                                -> ures;

More abstractly, I find the current syntax "frontloads" a lot of
information that the reader of the type signature may not (yet) care
about. For example, even in the simple case of `HashMap`, I find it
useful to be able to read the `impl` declaration in *stages*:

    impl<K,V> HashMap<K, V> 
        where K:Hash+Eq
    {
        ..
    }

In this form, I first learn that the impl is for `HashMap<K,V>` for
some types `K` and `V`. That is the most important bit of
information. Now I can read on to the `where` clause to learn the
precise requirements on `K`. The same is true for the
`set_var_to_merged_bounds()` example.

### Motivation #2: Future expressiveness

There are situations that our current syntax cannot express. For
example, let us suppose we were to add support for true multiparameter
type classes (which I hope we will do; I have been working on some
details, thoughts coming soon-ish). In that case, we might imagine
converting our `Add` trait (which defines the `+` operator) into a
multi-parameter type class for adding values:

    trait Add<Rhs,Sum> {
        fn add(left: &Self, right: &Rhs) -> Sum;
    }

Now imagine I wanted to implement a `Vector` type and I wanted
to permit vectors to be added with integers:

    impl Add<Vector,Vector> for int { ... }    // int + vec
    impl Add<int,Vector> for Vector { ... }    // vec + int
    impl Add<Vector,Vector> for Vector { ... } // vec + vec

(Declarations like these would not be legal today, since we do not yet
support multiparameter type classes in full.)

Now, imagine I wanted to write a function that took in "something
which can serve as the RHS for an addition to a vector". I could
express this with a `where` clause as follows:

    fn add_to_vec<R,S>(v: &Vector, r: R) -> S
        where Vector : Add<R,S>
    {
      ..
    }

Using today's syntax, however, this would be inexpressible, because
the `Self` parameter of the bound `Vector : Add<R,S>` is a type,
`Vector`, and not a type parameter.

I believe `where` clauses will also be helpful when we grow support
for higher-kinded types and might also be used to express other kinds
of higher-level constraints (e.g., what we once called type state).
