---
date: "2022-04-17T00:00:00Z"
slug: coherence-and-crate-level-where-clauses
title: Coherence and crate-level where-clauses
---
Rust has been wrestling with coherence more-or-less since we added methods; our current rule, the “orphan rule”, is safe but overly strict. Roughly speaking, the rule says that one can only implement foreign traits (that is, traits defined by one of your dependencies) for local types (that is, types that you define). The goal of this rule was to help foster the crates.io ecosystem — we wanted to ensure that you could grab any two crates and use them together, without worrying that they might define incompatible impls that can’t be combined. The rule has served us well in that respect, but over time we’ve seen that it can also have a kind of chilling effect, unintentionally working **against** successful composition of crates in the ecosystem. For this reason, I’ve come to believe that we will have to weaken the orphan rule. The purpose of this post is to write out some preliminary exploration of ways that we might do that.

## So wait, how does the orphan rule protect composition?

You might be wondering how the orphan rule ensures you can compose crates from crates.io. Well, imagine that there is a crate `widget` that defines a struct `Widget`:

```rust
// crate widget
#[derive(PartialEq, Eq)]
pub struct Widget {
    pub name: String,
    pub code: u32,
}
```

As you can see, the crate has derived `Eq`, but neglected to derive `Hash`. Now, I am writing another crate, `widget-factory` that depends on `widget`. I’d like to store widgets in a hashset, but I can’t,  because they don’t implement `Hash`! Today, if you want `Widget` to implement `Hash`, the only way is to open a PR against `widget` and wait for a new release.[^newtype] But if we didn’t have the orphan rule, we could just define `Hash` ourselves:

[^newtype]: You could also create a newtype and making your hashmap key off the newtype, but that’s more of a workaround, and doesn’t always work out.

```rust
// Crate widget-factory
impl Hash for Widget {
    fn hash(&self) {
        // PSA: Don’t really define your hash functions like this omg.
        self.name.hash() ^ self.code.hash()
    }
}
```

Now we can define our `WidgetFactory` using `HashSet<Widget>`…

```rust
pub struct WidgetFactory {
    produced: HashSet<Widget>,
}

impl WidgetFactory {
    fn take_produced(&mut self) -> HashSet<Widget> {
        self.produced.take()
    }
}
```

OK, so far so good, but what happens if somebody else defines a `widget-delivery` crate and they too wish to use a `HashSet<Widget>`? Well, they will also define `Hash` for `Widget`, but of course they might do it differently — maybe even very badly:

```rust
// Crate widget-factory
impl Hash for Widget {
    fn hash(&self) {
        // PSA: You REALLY shouldn’t define your hash functions this way omg
        0
    }
}
```

Now the problem comes when I try to develop my `widget-app` crate that depends on `widget-delivery` *and* `widget-factory`. I now have two different impls of `Hash` for `Widget`, so which should the compiler use?

There are a bunch of answers we might give here, but most of them are bad:

* We could have each crate use its own impl, in theory: but that wouldn’t work so well if the user tried to take a `HashSet<Widget>` from one crate and pass it to another crate.
* The compiler could pick one of the two impls arbitrarily, but how do we know which one to use? In this case, one of them would give very bad performance, but it’s also possible that some code is designed to expect the exact hash algorithm it specified.
	* This is even harder with associated types.
* Users could tell us which impl they want, which is maybe better, but it also means that the `widget-delivery` crates have to be prepared that any impl they are using might be switched to another one by some other crate later on. This makes it impossible for us to inline the hash function or do other optimizations except at the very last second.

Faced with these options, we decided to just rule out orphan impls altogether. Too much hassle!

## But the orphan rules make it hard to establish a standard

The orphan rules work well at ensuring that we can link two crates together, but ironically they can also work to make *actual interop* much harder. Consider the async runtime situation. Right now, there are a number of async runtimes, but no convenient way to write code that works with *any* runtime. As a result, people writing async libraries often wind up writing directly against one *specific* runtime. The end result is that we cannot combine libraries that were written against different runtimes, or at least that doing so can result in surprising failures. 

It would be nice if we could implement some traits that allowed for greater interop. But we don’t quite know what those traits should look like (we also lack support for async fn in traits, but that’s coming!), so it would be nice if we could introduce those traits in the crates.io ecosystem and iterate a bit there — this was indeed the original vision for the futures crate! But if we do that, in practice, then the same crate that defines the trait must *also* define an implementation for every runtime. The problem is that the runtimes won’t want to depend on the futures crate, as it is still unstable; and the futures crate doesn’t want to have to depend on every runtime. So we’re kind of stuck. And of course if the `futures` crate were to take a dependency on some specific runtime, then that runtime couldn’t later add `futures` as a dependency, since that would result in a cycle.

## Distinguishing “I need an impl” from “I prove an impl”

At the end of the day, I think we’re going to have to lift the orphan rule, and just accept that it may be possible to create crates that cannot be linked together because they contain overlapping impls. However, we can still give people the tools to ensure that composition works smoothly.

I would like to see us distinguish (at least) two cases:

* I need this type to implement this trait (which maybe it doesn’t, yet).
* I am supplying an impl of a trait for a given type.

The idea would be that most crates can just declare *that they need an impl* without actually supplying a specific one. Any number of such crates can be combined together without a problem (assuming that they don’t put inconsistent conditions on associated types). 

Then, separately, one can have a crate that actually *supplies* an impl of a foreign trait for a foreign type. These impls can be isolated as much as possible. The hope is that only the final binary would be responsible for actually supplying the impl itself.

## Where clauses are how we express “I need an impl” today

If you think about it, expressing “I need an impl” is something that we do all the time, but we typically do it with generic types. For example, when I write a function like so…

```rust
fn clone_list<T: Clone>(v: &[T]) {
    …
}
```

I am saying “I need a type `T` and I need it to implement `Clone`”, but I’m not being specific about what those types are.

In fact, it’s also possible to use where-clauses to specify things about non-generic types…

```rust
fn example()
where 
    u32: Copy,
{
{
```

…but the compiler today is a bit inconsistent about how it treats those. The plan is to move to a model where we “trust” what the user wrote — e.g., if the user wrote `where String: Copy`, then the function would treat the `String` type as if it were `Copy`, even if we can’t find any `Copy` impl. It so happens that such a function could never be *called*, but that’s no reason you can’t *define* it[^warning].

[^warning]: It might be nice of us to give a warning.

## Where clauses at the crate scope

What if we could put where clauses at the crate scope? We could use that to express impls that we need to exist without actually providing those impls. For example, the `widget-factory` crate from our earlier example might add a line like this into its lib.rs:

```rust
// Crate widget-factory
where Widget: Hash;
```

As a result, people would not be able to use that crate unless they either (a) supplied an impl of `Hash` for `Widget` or (b) repeated the where clause themselves, propagating the request up to the crates that depend on them. (Same as with any other where-clause.)

The intent would be to do the latter, propagating the dependencies up to the root crate, which could then either supply the impl itself or link in some other crate that does.

## Allow crates to implement foreign traits for foreign impls

The next part of the idea would be to allow crates to implement foreign traits for foreign impls. I think I would convert the orphan check into a “deny by default” lint. The lint text would explain that these impls are not permitted because they may cause linker errors, but a crate could mark the impl with `#[allow(orphan_impls])` to ignore that warning. Best practice would be to put orphan impls into their own crate that others can use.

## Another idea: permit duplicate impls (especially those generated via derive)

Josh Triplett floated another interesting idea, which is that we could permit duplicate impls. One common example might be if the impl is defined via a derive (though we’d have to extend derive to permit one to derive on a struct definition that is not local somehow).

## Conflicting where clauses

Even if you don’t supply an actual impl, it’s possible to create two crates that can’t be linked together if they contain contradictory where-clauses. For example, perhaps `widget-factory` defines `Widget` as an iterator over strings…

```rust
// Widget-factory
where Widget: Iterator<Item = String>;
```

…whilst `widget-lib` wants `Widget` to be an iterator over UUIDs:

```rust
// Widget-lib
where Widget: Iterator<Item = UUID>;
```

At the end of the day, at most one of these where-clauses can be satisfied, not both, so the two crates would not interoperate. That seems inevitable and ok.

## Expressing target dependencies via where-clauses

Another idea that has been kicking around is the idea of expressing portability across target-architectures via traits and some kind of `Platform` type. As an example, one could imagine having code that says `where Platform: NativeSimd` to mean “this code requires native SIMD support”, or perhaps `where Platform: Windows` to mean “this msut support various windows APIs. This is just a “kernel” of an idea, I have no idea what the real trait hierarchy would look like, but it’s quite appealing and seems to fit well with the idea of crate-level where-clauses. Essentially the idea is to allow crates to “constrain the environment that they are used in” in an explicit way.

## Module-level generics

In truth, the idea of crate-level where clauses is kind of a special case of having module-level generics, which I would very much like. The idea would be to allow modules (like types, functions, etc) to declare generic parameters and where-clauses.[^applicative] These would be nameable and usable from all code within the module, and when you referenced an item from *outside* the module, you would have to specify their value. This is very much like how a trait-level generic gets “inherited” by the methods in the trait. 

[^applicative]: Fans of ML will recognize this as “applicative functors”.

I have wanted this for a long time because I often have modules where all the code is parameterized over some sort of “context parameter”. In the compiler, that is the lifetime `’tcx`, but very often it’s some kind of generic type (e.g., `Interner` in salsa).

## Conclusion

I discussed a few things in this post:

* How coherence helps composability by ensuring that crates can be linked together, but harms composability by making it much harder to establish and use interoperability traits.
* How crate-level where-clauses can allow us to express “I need someone to implement this trait” without actually providing an impl, providing for the ability to link things together.
* A sketch of how crate-level where-clauses might be generalized to capture other kinds of constraints on the environment, such as conditions on the target platform, or to module-level generics, which could potentially be an ergonomic win.

Overall, I feel pretty excited about this direction. I feel like more and more things are becoming possible if we think about generalizing the trait system and making it more uniform. All of this, in my mind, builds on the work we’ve been doing to create a more precise definition of the trait system in [a-mir-formality](https://github.com/nikomatsakis/a-mir-formality) and to build up a team with expertise in how it works (see the [types team RFC](https://github.com/rust-lang/rfcs/pull/3254)). I’ll write more about those in upcoming posts though! =)