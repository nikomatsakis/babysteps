---
date: "2022-04-12T00:00:00Z"
slug: implied-bounds-and-perfect-derive
title: Implied bounds and perfect derive
---

There are two ergonomic features that have been discussed for quite some time in Rust land: *perfect derive* and *expanded implied bounds*. Until recently, we were a bit stuck on the best way to implement them. Recently though I’ve been working on a new formulation of the Rust trait checker that gives us a bunch of new capabilities — among them, it resolved a soundness formulation that would have prevented these two features from being combined. I’m not going to describe my fix in detail in this post, though; instead, I want to ask a different question. Now that we *can* implement these features, should we?

Both of these features fit nicely into the *less rigamarole* part of the [lang team Rust 2024 roadmap][2024]. That is, they allow the compiler to be smarter and require less annotation from you to figure out what code should be legal. Interestingly, as a direct result of that, they both *also* carry the same downside: semver hazards.

[2024]: https://blog.rust-lang.org/inside-rust/2022/04/04/lang-roadmap-2024.html

## What is a semver hazard?

A **semver hazard** occurs when you have a change which *feels* innocuous but which, in fact, can break clients of your library. Whenever you try to automatically figure out some part of a crate’s public interface, you risk some kind of semver hazard. This doesn’t necessarily mean that you shouldn’t do the auto-detection: the convenience may be worth it. But it’s usually worth asking yourself if there is some way to lessen the semver hazard while still getting similar or the same benefits.

Rust has a number of semver hazards today.[^hazards] The most common example is around thread-safety. In Rust, a struct `MyStruct` is automatically deemed to implement the trait `Send` so long as all the fields of `MyStruct` are `Send` (this is why we call `Send` an [auto trait]: it is *automatically* implemented). This is very convenient, but an implication of it is that adding a private field to your struct whose type is not thread-safe (e.g., a `Rc<T>`) is potentially a breaking change: if someone was using your library and sending `MyStruct` to run in another thread, they would no longer be able to do so.

[^hazards]: Rules regarding semver are documented [here](https://doc.rust-lang.org/cargo/reference/semver.html), by the way.

[auto trait]: https://doc.rust-lang.org/reference/special-types-and-traits.html#auto-traits

## What is “perfect derive”?

So what is the *perfect derive* feature? Currently, when you derive a trait (e.g., `Clone`) on a generic type, the derive just assumes that *all* the generic parameters must be `Clone`. This is sometimes necessary, but not always; the idea of *perfect derive* is to change how derive works so that it instead figures out *exactly* the bounds that are needed. 

Let’s see an example. Consider this `List<T>` type, which creates a linked list of `T` elements. Suppose that `List<T>` can be deref’d to yield its `&T` value. However, lists are immutable once created, and we also want them to be cheaply cloneable, so we use `Rc<T>` to store the data itself:

```rust
#[derive(Clone)]
struct List<T> {
    data: Rc<T>,
    next: Option<Rc<List<T>>>,
}

impl<T> Deref for List<T> {
    type Target = T;

    fn deref(&self) -> &T { &self.data }
}
```

Currently, derive is going to generate an impl that requires `T: Clone`, like this…

```rust
impl<T> Clone for List<T> 
where
    T: Clone,
{
    fn clone(&self) {
        List {
            value: self.value.clone(),
            next: self.next.clone(),
        }
    }
}
```

If you look closely at this impl, though, you will see that the `T: Clone` requirement is not actually necessary. This is because the only `T` in this struct is inside of an `Rc`, and hence is reference counted. Cloning the `Rc` only increments the reference count, it doesn’t actually create a new `T`.

With *perfect derive*, we would change the derive to generate an impl with one where clause per field, instead. The idea is that what we *really* need to know is that every field is cloneable (which may in turn require that `T` be cloneable):

```rust
impl<T> Clone for List<T> 
where
    Rc<T>: Clone, // type of the `value` field
    Option<Rc<List<T>>: Clone, // type of the `next` field
{
    fn clone(&self) { /* as before */ }
}
```

## Making perfect derive sound was tricky, but we can do it now

This idea is quite old, but there were a few problems that have blocked us from doing it. First, it requires changing all trait matching to permit cycles (currently, cycles are only permitted for auto traits like `Send`). This is because checking whether `List<T>` is `Send` would not require checking whether `Option<Rc<List<T>>>` is `Send`. If you work that through, you’ll find that a cycle arises. I’m not going to talk much about this in this post, but it is not a trivial thing to do: if we are not careful, it would make Rust quite unsound indeed. For now, though, let’s just assume we can do it soundly.

## The semver hazard with perfect derive

The other problem is that it introduces a new semver hazard: just as Rust currently commits you to being `Send` so long as you don’t have any non-`Send` types, `derive` would now commit `List<T>` to being cloneable even when `T: Clone` does not hold. 

For example, perhaps we decide that storing a `Rc<T>` for each list wasn’t really necessary. Therefore, we might refactor `List<T>` to store `T` directly, like so:

```rust
#[derive(Clone)]
struct List<T> {
    data: T,
    next: Option<Rc<List<T>>>,
}
```

We might expect that, since we are only changing the type of a private field, this change could not cause any clients of the library to stop compiling. **With perfect derive, we would be wrong.**[^other] This change means that we now own a `T` directly, and so `List<T>: Clone` is only true if `T: Clone`. 

[^other]: Actually, you were wrong before: changing the types of private fields in Rust can already be a breaking change, as we discussed earlier (e.g., by introducing a `Rc`, which makes the type no longer implement `Send`).

## Expanded implied bounds

An *implied bound* is a where clause that you don’t have to write explicitly. For example, if you have a struct that declares `T: Ord`, like this one…

```rust
struct RedBlackTree<T: Ord> { … }

impl<T: Ord> RedBlackTree<T> {
    fn insert(&mut self, value: T) { … }
}
```

…it would be nice if functions that worked with a red-black tree didn’t have to redeclare those same bounds:

```rust
fn insert_smaller<T>(red_black_tree: &mut RedBlackTree<T>, item1: T, item2: T) {
    // Today, this function would require `where T: Ord`:
    if item1 < item2 {
        red_black_tree.insert(item);
    } else {
        red_black_tree.insert(item2);
    }   
}\
```

I am saying *expanded* implied bounds because Rust already has two notions of implied bounds: expanding supertraits (`T: Ord` implies `T: PartialOrd`, for example, which is why the fn above can contain `item1 < item2`) and outlives relations (an argument of type `&’a T`, for example, implies that `T: ‘a`). The most maximal version of this proposal would expand those implied bounds from supertraits and lifetimes to **any where-clause at all**.

## Implied bounds and semver

Expanding the set of implied bounds will also introduce a new semver hazard — or perhaps it would be better to say that is expands an existing semver hazard. It’s already the case that removing a supertrait from a trait is a breaking change: if the stdlib were to change `trait Ord` so that it no longer extended `Eq`, then Rust programs that just wrote `T: Ord` would no longer be able to assume that `T: Eq`, for example.

Similarly, at least with a maximal version of expanded implied bounds, removing the `T: Ord` from `BinaryTree<T>` would potentially stop client code from compiling. Making changes like that is not that uncommon. For example, we might want to introduce new methods on `BinaryTree` that work even without ordering. To do that, we would remove the `T: Ord` bound from the struct and just keep it on the impl:

```rust
struct RedBlackTree<T> { … }

impl<T> RedBlackTree<T> {
    fn len(&self) -> usize { /* doesn’t need to compare `T` values, so no bound */ }
}

impl<T: Ord> RedBlackTree<T> {
    fn insert(&mut self, value: T) { … }
}
```

But, if we had a maximal expansion of implied bounds, this could cause crates that depend on your library to stop compiling, because they would no longer be able to assume that `RedBlackTree<X>` being valid implies `X: Ord`. As a general rule, I think we want it to be clear what parts of your interface you are committing to and which you are not.

## PSA: Removing bounds not always semver compliant

Interestingly, while it is true that you can remove bounds from a struct (today, at least) and be at semver complaint[^maybe], this is not the case for impls. For example if I have

```rust
impl<T: Copy> MyTrait for Vec<T> { }
```

and I change it to `impl<T> MyTrait for Vec<T>`, this is effectively introducing a new blanket impl, and that is not a semver compliant change (see [RFC 2451] for more details).

[^maybe]: Uh, no promises — there may be some edge cases, particularly involving regions, where this is not true today. I should experiment.

[RFC 2451]: https://rust-lang.github.io/rfcs/2451-re-rebalancing-coherence.html

## Summarize

So, to summarize:

* Perfect derive is great, but it reveals details about your fields—- sure, you can clone your `List<T>` for any type `T` now, but maybe you want the right to require `T: Clone` in the future?
* Expanded implied bounds are great, but they prevent you from “relaxing” your requirements in the future— sure, you only ever have a `RedBlackTree<T>` for `T: Ord` now, but maybe you want to support more types in the future?
* But also: the rules around semver compliance are rather subtle and quick to anger.

## How can we fix these features?

I see a few options. The most obvious of course is to just accept the semver hazards. It’s not clear to me whether they will be a problem in practice, and Rust already has a number of similar hazards (e.g., adding a `Box<dyn Write>` makes your type no longer `Send`).

## Another extreme alternative: crate-local implied bounds

Another option for implied bounds would be to expand implied bounds, but only on a *crate-local* basis. Imagine that the `RedBlackTree` type is declared in some crate `rbtree`, like so…

```rust
// The crate rbtree
struct RedBlackTree<T: Ord> { .. }
…
impl<T> RedBlackTree<T> {
    fn insert(&mut self, value: T) {
        …
    }
}
```

This impl, because it lives in the same crate as `RedBlackTree`, would be able to benefit from expanded implied bounds. Therefore, code inside the impl could assume that `T: Ord`. That’s nice. If I later remove the `T: Ord` bound from `RedBlackTree`, I can move it to the impl, and that’s fine.

But if I’m in some downstream crate, then I don’t benefit from implied bounds. If I were going to, say, implement some trait for `RedBlackTree`, I’d have to repeat `T: Ord`…

```rust
trait MyTrait { }

impl<T> MyTrait for rbtrait::RedBlackTree<T>
where
    T: Ord, // required
{ }
```

## A middle ground: declaring “how public” your bounds are

Another variation would be to add a *visibility* to your bounds. The default would be that where clauses on structs are “private”, i.e., implied only within your module. But you could declare where clauses as “public”, in which case you would be committing to them as part of your semver guarantee:

```rust
struct RedBlackTree<T: pub Ord> { .. }
```

In principle, we could also support `pub(crate)` and other visibility modifiers. 

## Explicit perfect derive

I’ve been focused on implied bounds, but the same questions apply to perfect derive. In that case, I think the question is mildly simpler— we likely want some way to expand the perfect derive syntax to “opt in” to the perfect version (or “opt out” from it).

There have been some proposals that would allow you to be explicit about which parameters require which bounds. I’ve been a fan of those, but now that I’ve realized we can do perfect derive, I’m less sure. Maybe we should just want some way to say “add the bounds all the time” (the default today) or “use perfect derive” (the new option), and that’s good enough. We could even make there be a new attribute, e.g. `#[perfect_derive(…)]` or `#[semver_derive]`. Not sure.

## Conclusion

In the past, we were blocked for technical reasons from expanding implied bounds and supporting perfect derive, but I believe we have resolved those issues. So now we have to think a bit about semver and decide how much explicit we want to be.

Side not that, no matter what we pick, I think it would be great to have easy tooling to help authors determine if something is a semver breaking change. This is a bit tricky because it requires reasoning about two versions of your code. I know there is [rust-semverer]  but I’m not sure how well maintained it is. It’d be great to have a simple github action one could deploy that would warn you when reviewing PRs.

[rust-semverer]: https://github.com/rust-lang/rust-semverver
