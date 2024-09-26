---
title: "Making overwrite opt-in #crazyideas"
date: 2024-09-26T21:51:55Z
---

What would you say if I told you that it was possible to (a) eliminate a lot of “inter-method borrow conflicts” *without* introducing something like [view types][] and (b) make pinning easier even than boats’s [pinned places][] proposal, all without needing pinned fields or even a pinned keyword? You’d probably say “Sounds great… what’s the catch?” The catch it requires us to change Rust’s fundamental assumption that, given `x: &mut T`, you can always overwrite `*x` by doing `*x = /* new value */`, for any type `T: Sized`. This kind of change is tricky, but not impossible, to do over an edition.

[view types]: https://smallcultfollowing.com/babysteps/blog/2021/11/05/view-types/
[pinned places]: https://without.boats/blog/pinned-places/
[pin]: https://without.boats/blog/pin/
[sp]: https://doc.rust-lang.org/std/pin/index.html#projections-and-structural-pinning

## TL;DR

We can reduce inter-procedural borrow check errors, increase clarity, and make pin vastly simpler to work with if we limit when it is possible to overwrite an `&mut` reference. The idea is that if you have a mutable reference `x: &mut T`, it should only be possible to overwrite `x` via `*x = /* new value */` or to swap its value via `std::mem::swap` if `T: Overwrite`. To start with, most structs and enums would implement `Overwrite`, and it would be a default bound, like `Sized`; but we would transition in a future edition to have structs/enums be `!Overwrite` by default and to have `T: Overwrite` bounds written explicitly.

## Structure of this series

This blog post is part of a series:

1. This first post will introduce the idea of immutable fields and show why they could make Rust more ergonomic and more consistent. It will then show how overwrites and swaps are the key blocker and introduce the idea of the `Overwrite` trait, which could overcome that.
2. In the next post, I'll dive deeper into `Pin` and how the `Overwrite` trait can help there.
3. After that, who knows? Depends on what people say in response.[^eep]

[^eep]: After this grandiose intro, hopefully I won't be printing a retraction of the idea due to some glaring flaw... eep!

## If you could change one thing about Rust, what would it be?

People often ask me to name something I would change about Rust if I could. One of the items on my list is the fact that, given a mutable reference `x: &mut SomeStruct` to some struct, I can overwrite the entire value of `x` by doing `*x = /* new value */`, versus only modifying individual fields like `x.field = /* new value */`. 

Having the ability to overwrite `*x` always seemed very natural to me, having come from C, and it’s definitely useful sometimes (particularly with `Copy` types like integers or newtyped integers). But it turns out to make borrowing and pinning much more painful than they would otherwise have to be, as I’ll explain shortly.

In the past, when I've thought about how to fix this, I always assumed we would need a new form of reference type, like `&move T` or something. That seemed like a non-starter to me. But at RustConf last week, while talking about the ergonomics of `Pin`, a few of us stumbled on the idea of using a *trait* instead. Under this design, you can always make an `x: &mut T`, but you can’t always assign to `*x` as a result. This turns out to be a much smoother integration. And, as I’ll show, it doesn’t really give up any expressiveness.

## Motivating example #1: Immutable fields

In this post, I’m going to motivate the changes by talking about **immutable fields**. Today in Rust, when you declare a local variable `let x = …`, that variable is immutable by default[^cell]. Fields, in contrast, inherit their mutability from the outside: when a struct appears in a `mut` location, all of its fields are mutable.

[^cell]: Whenever I saw immutable here, I mean immutable-modulo-[`Cell`][], of course. We should probably find another word for that, this is kind of terminology debt that Rust has bought its way into and I’m not sure the best way for us to get out!

[`Cell`]: https://doc.rust-lang.org/std/cell/struct.Cell.html

### Not all fields are mutable, but I can’t declare that in my Rust code

It turns out that declaring local variables as mut is [not needed for the borrow checker][foo] — and yet we do it nonetheless, in part because it helps readability. It's useful to see when a variable might change. But if that argument holds for local variables, it holds double for fields! For local variables, we can find all potential mutation just by searching one function. To know if a *field* may be mutated, we have to search across many functions. And for fields, precisely because they can be mutated across functions, declaring them as immutable can actually help the borrow checker to see that your code is safe.

[foo]: https://smallcultfollowing.com/babysteps/blog/2014/05/13/focusing-on-ownership/

### Idea: Declare fields as mutable

So what if we extended the mutable declaration to fields? The idea would be that, in your struct, if you want to mutate fields, you have to declare them as `mut`. This would allow them to be mutated: but only if the struct itself appears in a mutable local field.  

For example, maybe I have an `Analyzer` struct that is created with some vector of datums and which has to compute the number of “important” ones:

```rust
#[derive(Default)]
struct Analyzer {
    /// Data being analyzed: will never be modified.
    data: Vec<Datum>,

    /// Number of important datums uncovered so far.
    mut important: usize,
}
```

As you can see from the struct declaration, the field `data` is declared as immutable. This is because we are only going to be reading the `Datum` values. The `important`
field is declared as `mut`, indicating that it will be updated.

### When can you mutate fields?

In this world, mutating a field is only possible when (1) the struct appears in a mutable location and (2) the field you are referencing is declared as `mut`. So this code compiles fine, because the field `important` is `mut`:

```rust
let mut analyzer = Analyzer::new();
analyzer.important += 1; // OK: mut field in a mut location
```

But this code does not compile, because the local variable `x` is not:

```rust
let x = Analyzer::default();
x.important += 1; // ERROR: `x` not declared as mutable
```

And this code does not compile, because the field `data` is not declared as `mut`:

```rust
let mut x = Analyzer::default();
x.data.clear(); // ERROR: field `data` is not declared as mutable
```

### Leveraging immutable fields in the borrow checker

So why is it useful to declare fields as `mut`? Well, imagine you have a method like `increment_if_important`, which checks if  `datum.is_important()` is true and modifies the `important` flag if so:

```rust
impl Analyzer {
    fn increment_if_important(&mut self, datum: &Datum) {
        if datum.is_important() {
            self.important += 1;
        }
    }
}
```

Now imagine you have a function that loops over `self.data` and calls `increment_if_important` on each item:

```rust
impl Analyzer {
    fn count_important(&mut self) {
        for datum in &self.data {
            self.increment_if_important(datum);
        }
    }
}
```

I can hear the experienced Rustaceans crying out in pain now. This function, natural as it appears, will not compile in Rust today. Why is that? Well, we have a shared borrow on `self.data` but we are trying to call an `&mut self` function, so we have no way to be sure that `self.data` will not be modified.

### But what about immutable fields? Doesn’t that solve this?

Annoyingly, immutable fields on their own don’t change anything! Why? Well, just because you can’t write to a field directly doesn’t mean you can’t mutate the memory it’s stored in. For example, maybe I write a malicious version of `increment_if_important`:

```rust
impl Analyzer {
    fn malicious_increment_if_important(&mut self, datum: &Datum) {
        *self = Analyzer::default();
    }
}
```

This version never directly accesses the field `data`, but it just writes to `*self`, and hence it has the same impact. Annoying!

### Generics: why we can’t trivially disallow overwrites

Maybe you’re thinking “well, can’t we just disallow overwriting `*self` if there are fields declared `mut`?” The answer is yes, we can, and that’s what this blog post is about. But it’s not so simple as it sounds, because we are changing the “basic contract” that all Rust types currently satisfy. In particular, Rust today assumes that if you have a reference  `x: &mut T` and a value `v: T`, you can always do `*x = v` and overwrite the referent of `x`. That means I could can write a generic function like `set_to_default`:

```rust
fn set_to_default<T: Default>(r: &mut T) {
    *r = T::default();
}
```

Now, since `Analyzer` implements `Default`, I can make `increment_if_important` call `set_to_default`. This will still free `self.data`, but it does it in a sneaky way, where we can’t obviously tell that the value being overwritten is an instance of a struct with mut fields:

```rust
impl Analyzer {
    fn malicious_increment_if_important(&mut self, datum: &Datum) {
        // Overwrites `self.data`, but not in an obvious way
        set_to_default(self);
    }
}
```

## Recap

So let’s step back and recap what we’ve seen so far:

* If we could distinguish which fields were mutable and which were definitely not, we could eliminate many inter-function borrow check errors[^notall].
* However, just adding `mut` declarations is not enough, because fields can also be mutated indirectly. Specifically, when you have a `&mut SomeStruct`, you can overwrite with a fresh instance of `SomeStruct` or swap with another `&mut SomeStruct`, thus changing all fields at once.
* Whatever fix we use has to consider generic code like `std::mem::swap`, which mutates an `&mut T` without knowing precisely what `T` is. Therefore we can’t do something simple like looking to see if `T` is a struct with `mut` fields[^cpp].

[^cpp]: The simple solution — if a struct has `mut` fields, disallow overwriting it — is basically what C++ does with their `const` fields. Classes or structs with `const` fields are more limited in how you can use them. This works in C++ because they don’t wait until post-substitution to check templates for validity.

[^notall]: Immutable fields don't resolve *all* inter-function borrow conflicts. To do that, you need something like [view types][]. But in my experience they would eliminate many.

## The trait system to the rescue

My proposal is to introduce a new, built-in marker trait called `Overwrite`:

```rust
/// Marker trait that permits overwriting
/// the referent of an `&mut Self` reference.
#[marker] // <-- means the trait cannot have methods
trait Overwrite: Sized {}
```

### The effect of `Overwrite`

As a marker trait, `Overwrite` does not have methods, but rather indicates a property of the type. Specifically, assigning to a borrowed place of type `T` requires that `T: Overwrite` is implemented. For example, the following code writes to `*x`, which has type `T`; this is only legal if `T: Overwrite`:

```rust
fn overwrite<T>(x: &mut T, t: T) {
    *x = t; // <— requires `T: Overwrite`
}
```

Given this this code compiles today, this implies that a generic type parameter declaration like `<T>` would require a default `Overwrite` bound in the current edition. We would want to phase these defaults out in some future edition, as I'll describe in detail later on.

Similarly, the standard library’s swap function would require a `T: Overwrite` bound, since it (via unsafe code) assigns to `*x` and `*y`:

```rust
fn swap<T>(x: &mut T, y: &mut T) {
    unsafe {
        let tmp: T = std::ptr::read(x);
        std::ptr::write(*x, *y); // overwrites `*x`, `T: Overwrite` required
        std::ptr::write(*y, tmp); // overwrites `*y`, `T: Overwrite` required
    }
}
```

### `Overwrite` requires `Sized`

The `Overwrite` trait requires `Sized` because, for `*x = /* new value */` to be safe, the compiler needs to ensure that the place `*x` has enough space to store “new value”, and that is only possible when the size of the new value is known at compilation time (i.e., the type implements `Sized`).

### `Overwrite` only applies to borrowed values

The overwrite trait is only needed when assigning to a borrowed place of type `T`. If that place is owned, the owner is allowed to reassign it, just as they are allowed to drop it. So e.g. the following code compiles whether or not `SomeType: Overwrite` holds:

```rust
let mut x: SomeType = /* something */;
x = /* something else */; // <— does not require that `SomeType: Overwrite` holds
```

### Subtle: `Overwrite` is not infectious

Somewhat surprisingly, it is ok to have a struct that implements `Overwrite` which has fields that do not. Consider the types `Foo` and `Bar`, where `Foo: Overwrite` holds but `Bar: Overwrite` does not:

```rust
struct Foo(Bar);
struct Bar;
impl Overwrite for Foo { }
impl !Overwrite for Bar { }
```

The following code would type check:

```rust
let foo = &mut Foo(Bar);
// OK: Overwriting a borrowed place of type `Foo`
// and `Foo: Overwrite` holds.
*foo = Foo(Bar);
```

However, the following code would not:

```rust
let foo = &mut Foo(Bar);
// ERROR: Overwriting a borrowed place of type `Bar`
// but `Bar: Overwrite` does not hold.
foo.0 = Bar;
```

Types that do not implement `Overwrite` can therefore still be overwritten in memory, but only as part of overwriting the value in which they are embedded. In the FAQ I show how this non-infectious property preserves expressiveness.[^expressiveness]

[^expressiveness]: I love the [Felleisen definition of “expressiveness”](https://jgbm.github.io/eecs762f19/papers/felleisen.pdf): two language features are equally expressive if one can be converted into the other with only *local* rewrites, which I generally interpret as “rewrites that don’t affect the function signature (or other abstraction boundary)”. 

### Who implements `Overwrite`?

This section walks through which types should implement `Overwrite`.

#### `Copy` implies `Overwrite`

Any type that implements `Copy` would automatically implement `Overwrite`:

```rust
impl<T: Copy> Overwrite for T { }
```

(If you, like me, get nervous when you see blanket impls due to coherence concerns, it’s worth noting that [RFC #1268][] allows for overlapping impls of marker traits, though that RFC is not yet fully implemented nor stable. It’s not terribly relevant at the moment anyway.)

[RFC #1268]: https://rust-lang.github.io/rfcs/1268-allow-overlapping-impls-on-marker-traits.html

#### “Pointer” types are `Overwrite`

Types that represent pointers all implement `Overwrite` for all `T`:

* `&T`
* `&mut T`
* `Box<T>`
* `Rc<T>`
* `Arc<T>`
* `*const T`
* `*mut T`

#### `dyn`,`[]`, and other “unsized” types do not implement `Overwrite`

Types that do not have a static size, like `dyn` and `[]`, do not implement `Overwrite`. Safe Rust already disallows writing code like `*x = …` in such cases.

There are ways to do overwrites with unsized types in unsafe code, but they’d have to prove various bounds. For example, overwriting a `[u32]` value could be ok, but you have to know the length of data. Similarly swapping two `dyn Value` referents can be safe, but you have to know that (a) both dyn values have the same underlying type and (b) that type implements `Overwrite`.

#### Structs and enums

The question of whether structs and enums should implement `Overwrite` is complicated because of backwards compatibility. I’m going to distinguish two cases: Rust 2021, and Rust Next, which is Rust in some hypothetical future edition (surely not 2024, but maybe the one after that).

**Rust 2021.** Struct and enum types in Rust 2021 implement `Overwrite` by default. Structs could opt-out from `Overwrite` with an explicit negative impl (`impl !Overwrite for S`).

**Integrating `mut` fields.** Structs that have opted out from `Overwrite` require mutable fields to be declared as `mut`. Fields not declared as `mut` are immutable. This gives them the nicer borrow check behavior.[^default]

[^default]: We can also make the `!Overwrite` impl implied by declaring fields `mut`, of course. This is fine for backwards compatibility, but isn’t the design I would want long-term, since it introduces an odd “step change” where declaring one field as `mut` implicitly declares all *other* fields as immutable (and, conversely, deleting the `mut` keyword from that field has the effect of declaring all fields, including that one, as mutable).

**Rust Next.** In some future edition, we can swap the default, with fields being `!Overwrite` by default and having to opt-in to enable overwrites. This would make the nice borrow check behavior the default.

#### Futures and closures

Futures and closures can implement `Overwrite` iff their captured values implement `Overwrite`, though in future editions it would be best if they simple do not implement `Overwrite`.

### Default bounds and backwards compatibility

The other big backwards compatibility issue has to do with default bounds. In Rust 2021, every type parameter declared as `T` implicitly gets a `T: Sized` bound. We would have to extend that default to be `T: Sized + Overwrite`. This also applies to associated types in trait definitions and `impl X` types.[^trait]

[^trait]: The `Self` type in traits is exempt from the `Sized` default, and it could be exempt from the `Overwrite` default as well, unless the trait is declared as `Sized`.

Interestingly, type parameters declared as `T: ?Sized` *also* opt-out from `Overwrite`. Why is that? Well, remember that `Overwrite: Sized`, so if `T` is not known to be `Sized`, it cannot be known to be `Overwrite` either. This is actually a big win. It means that types like `&T` and `Box<T>` can work with “non-overwrite” types out of the box.

#### Associated type bounds are annoying, but perhaps not fatal

Still, the fact that default bounds apply to associated types and `impl Trait` is a pain in the neck. For example, it implies that `Iterator::Item` would require its items to be `Overwrite`, which would prevent you from authoring iterators that iterate over structs with immutable fields. This can to some extent be overcome by associated type aliases (we could declare `Item` to be a “virtual associated type”, mapping to `Item2021` in older editions, which require `Overwrite`, and `ItemNext` in newer ones, which do not).

## Frequently asked questions

### OMG endless words. What did I just read?

Let me recap!

* It would be more declarative and create fewer borrow check conflicts if we had users declare their fields as `mut` when they may be mutated and we were able to assume that non-`mut` fields will never be mutated.
	* If we were to add this, in the current Rust edition it would obviously be opt-in.
	* But in a future Rust edition it would become mandatory to declare fields as `mut` if you want to mutate them.
* But to do that, we need to prevent overwrites and swaps. We can do that by introducing a trait, `Overwrite`, that is required to a given location.
	* In the current Rust edition, this trait would be added by default to all type parameters, associated types, and `impl Trait` bounds; it would be implemented by all structs, enums, and unions.
	* In a future Rust edition, the trait would no longer be the default, and structs, enums, and unions would have to explicitly implement if they want to be overwriteable. 

### This change doesn't seem worth it just to get immutable fields. Is there more?

But wait, there’s more! Oh, you just said that. Yes, there’s more. I’m going to write a follow-up post showing how opting out from `Overwrite` eliminates most of the ergonomic pain of using `Pin`.

### In “Rust Next”, who would ever implement `Overwrite` manually?

I said that, in Rust Next, types should be `!Overwrite` by default and require people to implement `Overwrite` manually if they want to. But who would ever do that? It’s a good question, because I don’t think there’s very much reason to.

Because `Overwrite` is not infectious, you can actually make a wrapper type...

```rust
#[repr(transparent)]
struct ForceOverwrite<T> { t: T }
impl<T> Overwrite for ForceOverwrite <T> { }
```

...and now you can put values of any type `X` into an `ForceOverwrite <X>` which can be reassigned. 

This pattern allows you to make “local” use of overwrite, for example to implement a sorting algorithm (which has to do a lot of swapping). You could have a `sort` function that takes an `&mut [T]` for any `T: Ord` (`Overwrite` not required):

```rust
fn sort<T: Ord>(data: &mut [T])
```

Internally, it can safely transmute the `&mut [T]` to a `&mut [ForceOverwrite<T>]` and sort *that*. Note that at no point during that sorting are we moving or overwriting an element while it is borrowed (the slice that owns it is borrowed, but not the elements themselves).

### What is the relationship of `Overwrite` and `Unpin`?

I’m still puzzling that over myself. I think that `Overwrite` is “morally the same” as `Unpin`, but it is much more powerful (and ergonomic) because it is integrated into the behavior of `&mut` (of course, this comes at the cost of a complex backwards compatibility story).

Let me describe it this way. Types that do not implement `Overwrite` cannot be overwritten while borrowed, and hence are “pinned for the duration of the borrow”. This has always been true for `&T`, but for `&mut T` has traditionally not been true. We'll see in the next post that `Pin<&mut T>` basically just extends that guarantee to apply indefinitely.

Compare that to types that do not implement `Unpin` and hence are “address sensitive”. Such types are pinned for the duration of a `Pin<&mut T>`. Unlike `T: !Overwrite` types, they are *not* pinned by `&mut T` references, but that’s a bug, not a feature: this is why `Pin` has to bend over backwards to prevent you from getting your hands on an `&mut T`.

I’ll explain this more in my next post, of course.

#### Should `Overwrite` be an auto trait?

I think not. If we did so, it would lock people into semver hazards in the “Rust Next” edition where `mut` is mandatory for mutation. Consider a `struct Foo { value: u32 }` type. This type has not opted into becoming `Copy`, but it only contains types that are `Copy` and therefore `Overwrite`. By *auto trait* rules it would by default be `Overwrite`. But that would prevent you from adding a `mut` field in the future or benefit from immutable fields. This is why I said the default would just be `!Overwrite`, no matter the field types.

## Conclusion

![Obama Mic Drop](https://i.giphy.com/media/v1.Y2lkPTc5MGI3NjExd3cxYWNibXp5NnpyaW0xcTMyY3Rhdms3em00cWJjc3Y2NnYzdDJ2cSZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9dg/MknHSvehUtqfYMClV6/giphy.gif)

=)