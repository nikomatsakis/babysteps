---
title: "Sized, DynSized, and Unsized"
date: 2024-04-23T16:51:54-04:00
---

[Extern types][et] have been blocked for an unreasonably long time on a fairly narrow, specialized question: Rust today divides all types into two categories — *sized*, whose size can be statically computed, and *unsized*, whose size can only be computed at runtime. But for external types what we really want is a *third category*, types whose size can never be known, even at runtime (in C, you can model this by defining structs with an unknown set of fields). The problem is that Rust’s `?Sized` notation does not naturally scale to this third case. I think it’s time we fixed this. At some point I read a proposal — I no longer remember where — that seems like the obvious way forward and which I think is a win on several levels. So I thought I would take a bit of time to float the idea again, explain the tradeoffs I see with it, and explain why I think the idea is a good change.

[et]: https://rust-lang.github.io/rfcs/1861-extern-types.html

## TL;DR: write `T: Unsized` in place of `T: ?Sized` (and sometimes `T: DynSized`)

The basic idea is to deprecate the `?Sized` notation and instead have a family of `Sized` supertraits. As today, the default is that every type parameter `T` gets a `T: Sized` bound unless the user explicitly chooses one of the other supertraits:

```rust
/// Types whose size is known at compilation time (statically).
/// Implemented by (e.g.) `u32`. References to `Sized` types
/// are "thin pointers" -- just a pointer.
trait Sized: DynSized { }

/// Types whose size can be computed at runtime (dynamically).
/// Implemented by (e.g.) `[u32]` or `dyn Trait`.
/// References to these types are "wide pointers",
/// with the extra metadata making it possible to compute the size
/// at runtime.
trait DynSized: Unsized { }

/// Types that may not have a knowable size at all (either statically or dynamically).
/// All types implement this, but extern types **only** implement this.
trait Unsized { }
```

Under this proposal, `T: ?Sized` notation could be converted to `T: DynSized` or `T: Unsized`. `T: DynSized` matches the current semantics precisely, but `T: Unsized` is probably what most uses actually want. This is because most users of `T: ?Sized` never compute the size of `T` but rather just refer to existing values of `T` by pointer.

### Credit where credit is due?

For the record, this design is not my idea, but I'm not sure where I saw it. I would appreciate a link so I can properly give credit.

## Why do we have a default `T: Sized` bound in the first place?

It’s natural to wonder why we have this `T: Sized` default in the first place. The short version is that Rust would be very annoying to use without it. If the compiler doesn’t know the size of a value at compilation time, it cannot (at least, cannot easily) generate code to do a number of common things, such as store a value of type `T` on the stack or have structs with fields of type `T`. This means that a very large fraction of generic type parameters would wind up with `T: Sized`.

## So why the `?Sized` notation?

The `?Sized` notation was the result of a lot of discussion. It satisfied a number of criteria.

### `?` signals that the bound operates in reverse

The `?` is meant to signal that a bound like `?Sized` actually works in **reverse** from a normal bound. When you have `T: Clone`, you are saying “type `T` **must** implement `Clone`”. So you are **narrowing** the set of types that `T` could be: before, it could have been both types that implement `Clone` and those that do not. After, it can *only* be types that implement `Clone`. `T: ?Sized` does the reverse: before, it can **only** be types that implement `Sized` (like `u32`), but after, it can **also** be types that do not (like `[u32]` or `dyn Debug`). Hence the `?`, which can be read as “maybe” — i.e., `T` is “maybe” Sized.

### `?` can be extended to other default bounds

The `?` notation also scales to other default traits. Although we’ve been reluctant to exercise this ability, we wanted to leave room to add a new default bound. This power will be needed if we ever adopt [“must move” types][][^mm] or add a bound like `?Leak` to signal a value that cannot be leaked.

[“must move” types]: XXX

[^mm]: I still think [“must move” types][] are a good idea — but that’s a topic for another post.

## But `?` doesn’t scale well to “differences in degree”

When we debated the `?` notation, we thought a lot about extensibility to other *orthogonal* defaults (like `?Leak`), but we didn’t consider extending a single dimension (like `Sized`) to multiple levels. There is no theoretical challenge. In principle we could say…

* `T` means `T: Sized + DynSized`
* `T: ?Sized` drops the `Sized` default, leaving `T: DynSized`
* `T: ?DynSized` drops both, leaving any type `T`

…but I personally find that very confusing. To me, saying something “might be statically sized” does not signify that it *is* dynamically sized.

## And `?` looks “more magical” than it needs to

Despite knowing that `T: ?Sized` operates in reverse, I find that in practice it still *feels* very much like other bounds. Just like `T: Debug` gives the function the extra capability of generating debug info, `T: ?Sized` feels to me like it gives the function an extra capability: the ability to be used on unsized types. This logic is specious, these are different kinds of capabilities, but, as I said, it’s how I find myself thinking about it.

Moreover, even though I know that `T: ?Sized` “most properly” means “a type that may or may not be Sized”, I find it wind up *thinking* about it as “a type that is unsized”, just as I think about `T: Debug` as a “type that is `Debug`”. Why is that? Well, beacuse `?Sized` types *may* be unsized, I have to treat them as if they *are* unsized -- i.e., refer to them only by pointer. So the fact that they *might* also be sized isn’t very relevant.

## How would we use these new traits?

So if we adopted the “family of sized traits” proposal, how would we use it? Well, for starters, the `size_of` methods would no longer be defined as `T` and `T: ?Sized`…

```rust
fn size_of<T>() -> usize {}
fn size_of_val<T: ?Sized>(t: &T) -> usize {}
```

… but instead as `T` and `T: DynSized` …

```rust
fn size_of<T>() -> usize {}
fn size_of_val<T: DynSized>(t: &T) -> usize {}
```

That said, most uses of `?Sized` today do not need to compute the size of the value, and would be better translated to `Unsized`…

```rust
impl<T: Unsized> Debug for &T {
    fn fmt(&self, f: &mut std::fmt::Formatter<‘_>) { .. }
}
```

## Option: Defaults could also be disabled by supertraits?

As an interesting extension to today’s system, we could say that every type parameter `T` gets an implicit `Sized` bound unless either…

1. There is an explicit weaker alternative(like `T: DynSized` or `T: Unsized`);
2. Or some other bound `T: Trait` has an explicit supertrait `DynSized` or `Unsized`.  

This would clarify that trait aliases can be used to disable the `Sized` default. For example, today, one might create a `Value` trait is equivalent to `Debug + Hash + Org`, roughly like this:

```rust
trait Value: Debug + Hash + Ord {
    // Note that `Self` is the *only* type parameter that does NOT get `Sized` by default
}

impl<T: ?Sized + Debug + Hash + Ord> Value for T {}
```

But what if, in your particular data structure, all values are boxed and hence can be unsized. Today, you have to repeat `?Sized` everywhere:

```rust
struct Tree<V: ?Sized + Value> {
    value: Box<V>,
    children: Vec<Tree<V>>,
}

impl<V: ?Sized + Value> Tree<V> { … }
```

With this proposal, the *explicit* `Unsized` bound could be signaled on the trait:

```rust
trait Value: Debug + Hash + Ord + Unsized {
    // Note that `Self` is the *only* type parameter that does NOT get `Sized` by default
}

impl<T: Unsized + Debug + Hash + Ord> Value for T {}
```

which would mean that

```rust
struct Tree<V: Value> { … }
```

would imply `V: Unsized`.

## Alternatives

### Different names

The name of the `Unsized` trait in particular is a bit odd. It means “you can treat this type as unsized”, which is true of all types, but it *sounds* like the type is *definitely* unsized. I’m open to alternative names, but I haven’t come up with one I like yet. Here are some alternatives and the problems with them I see:

* `Unsizeable` — doesn’t meet our typical name conventions, has overlap with the `Unsize` trait
* `NoSize`, `UnknownSize` — same general problem as `Unsize`
* `ByPointer` — in some ways, I kind of like this, because it says “you can work with this type by pointer”, which is clearly true of all types. But it doesn’t align well with the existing `Sized` trait — what would we call that, `ByValue`? And it seems too tied to today’s limitations: there are, after all, ways that we can make `DynSized` types work by value, at least in some places.
* `MaybeSized` — just seems awkward, and should it be `MaybeDynSized`?

All told, I think `Unsized` is the best name. It’s a *bit* wrong, but I think you can understand it, and to me it fits the intuition I have, which is that I mark type parameters as `Unsized` and then I tend to just think of them as being unsized (since I have to).

### Some sigil

Under this proposal, the `DynSized` and `Unsized` traits are “magic” in that explicitly declaring them as a bound has the impact of disabling a default `T: Sized` bound. We could signify that in their names by having their name be prefixed with some sort of sigil. I’m not really sure what that sigil would be — `T: %Unsized`? `T: ?Unsized`? It all seems unnecessary.

### Drop the implicit bound altogether

The purist in me is tempted to question whether we need the default bound. Maybe in Rust 2027 we should try to drop it altogether. Then people could write

```rust
fn size_of<T: Sized>() -> usize {}
fn size_of_val<T: DynSized>(t: &T) -> usize {}
```

and

```rust
impl<T> Debug for &T {
    fn fmt(&self, f: &mut std::fmt::Formatter<‘_>) { .. }
}
```

Of course, it would also mean a lot of `Sized` bounds cropping up in surprising places. Beyond random functions, consider that every associated type today has a default `Sized` bound, so you would need

```rust
trait Iterator {
    type Item: Sized;
}
```

Overall, I doubt this idea is worth it. Not surprising: it was deemed too annoying before, and now it has the added problem of being hugely disruptive.

## Conclusion

I’ve covered a design to move away from `?Sized` bounds and towards specialized traits. There are avrious “pros and cons” to this proposal but one aspect in particular feels common to this question and many others: when do you make two “similar but different” concepts feel very different — e.g., via special syntax like `T: ?Sized` — and when do you make them feel very similar — e.g., via the idea of “special traits” where a bound like `T: Unsized` has extra meaning (disabling defaults).

There is a definite trade-off here. Distinct syntax help avoid potential confusion, but it forces people to recognize that something special is going on even when that may not be relevant or important to them. This can deter folks early on, when they are most “deter-able”. I think it can also contribute to a general sense of “big-ness” that makes it feel like understanding the entire language is harder.

Over time, I’ve started to believe that it’s generally better to make things feel similar, letting people push off the time at which they have to learn a new concept. In this case, this lessens my fears around the idea that `Unsized` and `DynSized` traits would be confusing because they behave differently than other traits. In this particular case, I also feel that `?Sized` doesn't "scale well" to default bounds where you want to pick from one of many options, so it's kind of the worst of both worlds -- distinct syntax that shouts at you but which *also* fails to add clarity.

Ultimately, though, I’m not wedded to this idea, but I am interested in kicking off a discussion of how we can unblock [extern types][et]. I think by now we've no doubt covered the space pretty well and we should pick a direction and go for it (or else just give up on [extern types][et]).