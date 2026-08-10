---
title: "Cylic trait implementations: motivation"
date: 2026-08-10T09:35:40-04:00
series:
- "Cyclic trait impls"
---

Lately I've been thinking about cyclic trait implementations. This is a problem that I've been trying to understand for years and years and I *finally* feel like I'm geting somewhere. I'm going to try to write out a series of blog posts documenting those explorations and, hopefully, culminating in a design that could be RFC'd. In this first post, I want to talk about one of the interesting questions, what I am going to call "internal" vs "external" proofs. I know that this material can seem abstract, so I'm going to try and connect it to "real Rust" as much as possible! This particular blog post is an introduction, explaining the general problem and giving some motivation for why we care.

## What *are* cyclic trait implementations?

Right now in Rust we require most traits to have *non-cyclic*, or *inductive*, implementations. To explain what I mean, let's consider this trait:

```rust
trait Dump {
    fn dump(&self);
}
```

Now imagine that we have an impl of this for `i32`:

```rust
// Impl I
impl Dump for i32 {
    fn dump(&self) {
        println!("{self}");
	}
}
```

A simple impl for `Rc<T>` and `Option<T>:

```rust
// Impl RC
impl<T> Dump for Rc<T>
where
    T: Dump,
{
	fn dump(&self) {
		T::dump(self)
	}
}

// Impl Opt
impl<T> Dump for Option<T>
where
    T: Dump,
{
	fn dump(&self) {
		if let Some(v) = self {
			T::dump(v)
		}
	}
}
```

and finally a recursive `List` type that has an impl as well:

```rust
struct List<T> {
    value: Rc<T>,
    next: Option<Rc<List<T>>>,
}

// Impl L
impl<T> Dump for List<T>
where
    T: Dump,
{
    fn dump(&self) {
		Dump::dump(&self.value);
       if let Some(n) = &self.next {
			Dump::dump(n);
		}
    }
}
```

If I try to show that `List<i32>: Debug`, I do that by

* Applying "impl L" to show that `List<i32>: Debug` if `i32: Debug`
	* Then applying "impl I" to show that `i32: Debug`

There's no *cycle* here -- that is, I didn't have to use impl L to show that impl L is valid.

## Cyclic logic sounds bad, but it can be exactly what you want

Now, when I said that "the impl L didn't have to use the impl L to show that it is valid" that might not have sounded suspicious to you. In fact, it's a pretty natural idea. After all, generally when you try to establish a logical argument, you aren't allowed to use cyclic reasoning. That is, you can't say: I know that Niko likes Rust because Niko lists Rust. So, in the same sense, it seems natural that I should not be able to say "I know that `List<i32>` implements `Dump` because `List<i32>` implements `Dump`".

But actually, it would sometimes be really useful to say *exactly* that. One example is so-called "perfect derive". In our `Dump` impl above, we had one where-clause, `T: Dump`. And if you were to create a custom derive for `Dump` and write `#[derive(Dump)]`, the impl I showed is typically exactly what you would get. But it's not necessarily what you *want*. Consider what you get with `#[derive(Clone)]`:

```rust
// Impl LC1
impl<T> Clone for List<T>
where
    T: Clone, // <-- generated but not really required!
{
    fn dump(&self) {
		List {
			value: Clone::clone(&self.value),
			next: Clone::clone(&self.next),
		}
	}
}
```

Here, the derive is going to create an impl that requires `T: Clone`. But if you look closely, you'll see that all the fields only use `Rc<T>`, so in fact, we should be able to clone a `List` even without `T: Clone`! But how is the compiler to know this?

You might think that the compiler could do some super smarty-pants analysis on the fields to figure it out. And, in a way, it can: that is what cyclic trait solving is all about. The thing is, while the *compiler* can do that, the *derive* cannot -- the derive doesn't have access to the definitions of other types and so forth, and clearly we would need to know things about `Option` and `Rc` to figure out whether `T: Clone` is required here.

But what we *could* do is to generate a different impl. Instead of adding `T: Clone` for each type parameter, we could add a where-caluse for each field type. This makes sense: after all, we are just going to be calling `Clone` on every field, so it's quite logical to say that the impl is valid if every field is cloneable:

```rust
// Impl LC2
impl<T> Clone for List<T>
where
    Rc<T>: Clone,
    Option<Rc<List<T>>>: Clone,
{
    // .. as above ..
}
```

Under *this* formulation, we can see that all we have to be able to do is to clone an `Rc<_>` and clone an `Option<Rc<_>>`, neither of which require that `T: Clone`.

## This idea is called **perfect derive**

We call this idea [perfect derive][] and it's been a goal for a while. The thing is, cyclic reasoning *is* tricky to get right. The `Clone` example is actually an easy one: that one doesn't really require cyclic reasoning:

* To show that `List<i32>: Clone` we have to show that...
	* `Rc<i32>: Clone`, which is easy because `impl<T> Clone for Rc<T>` doesn't have any where-clauses[^Sized]
	* `Option<Rc<List<i32>>>: Clone` uses the `impl<T> Clone for Option<T> where T: Clone` impl which requires...
		* `Rc<List<i32>>: Clone`, which is again easy 

[^Sized]: Apart from the default `Sized` bound, I'm ignoring that here

## But it's not so easy for `Dump`

But if we use that same "cyclic derive pattern" to generate our `Dump` impl, things don't work out so well. Instead of just a `T: Dump` bound, our `Dump` impl now has two bounds:

```rust
// impl L1
impl<T> Dump for List<T>
where
    Rc<T>: Dump, // <-- Used to be `T: Dump`
    Option<Rc<List<T>>>, // <-- This one is new!
{
    fn dump(&self) {...}
}
```

Now imagine we try to show `List<i32>: Dump`. We begin by applying impl L1, which requires us to show that its where clauses hold:

* To show `List<i32>: Dump` we use impl L1, which has two where-clauses:
	* `Rc<i32>: Dump`, this one is easy because the `Rc` impl requires that `i32: Dump` which is true.
	* But `Option<Rc<List<i32>>>: Dump` is tricky. The `Option` impl requires that...
		* We need to prove `Rc<List<i32>>: Dump`, and then the `Rc` impl requires that...
			* We need to prove `List<i32>: Dump`, but that is what we started with! That's cyclic logic!

Ugh. Something's tricky here!

## We can't just accept any old cycle because of supertraits

Now, maybe you think we can just accept any cycles. And for these examples, it would be fine: but it's not correct if you consider *supertraits*. Consider this trait and impl pair:

```rust
trait Magic: Copy { }

// Impl M
impl<T> Magic for T
where
    T: Magic,
{}
```

If you are naive, this weird trait-impl pair can be used to prove that *any* type is `Copy`, regardless of whether it has a `Copy` impl. For example:

* Say we want to prove that `String: Copy`. We observe that if a type implements `Magic`, it must implement `Copy`, so...
	* We begin by proving `String: Magic`. We use the impl M, which requires
		* that we show `String: Magic`, which is a cycle, so we accept it.

Uh oh, now we did something wrong. We proved that `String: Copy` even though there is no `Copy` impl. Something is fishy.

Now clearly we can all see the problem here -- the implementation of `Magic` didn't really add any information. It was just a tautology, saying that `T: Magic` if `T: Magic`. It's not *wrong*, but implementing `Magic` was supposed to tell us more than just the fact that there is an impl of `Magic`, it was supposed to tell us also that the supertrait `Copy` is implemented. And that's not true here.

But if you think about it, it's hard to decide why we should reject impl M but accept the impl L1 of `Dump` for `List<T>`. They both wind up with a cyclic proof. So what's the difference? This is the question we'll be exploring over the next few blog posts.

## Soundness for traits

This gets at an interesting question: what does it mean for the trait system to be *sound*. This seems obvious but actually it was a question I found kind of non-obvious for a long time. 

We've found two satisfactory answers to that question. One of them involves converting to dictionary-passing style. [Nadri explained that in a blog post][dps]. I think that's a great post to read. I'm going to give another definition here that doesn't require converting to a dependently typed program[^both]

[^both]: I have found that both the dictionary-passing interpretation and the logic approach I'm using are valuable. In the end, they're more or less equivalent, which I guess shouldn't be surprising if you've heard of the [Curry Howard Correspondence][chc], but I'll talk about that later perhaps.

[chc]: https://en.wikipedia.org/wiki/Curry–Howard_correspondence

[dps]: https://nadrieril.github.io/blog/2026/03/22/what-if-traits-carried-values.html

My rough definition is this[^def]: the trait system is sound if, whenever it accepts some program P, that program cannot have a function that believes some `Trait` holds for the `T`, but there is no impl of `Trait` that can be used. So in the case of `Magic` and `Copy`, it's easy to write a program that shows simple cyclic trait solving is unsound:

```rust
trait Magic: Copy {}

impl<T: Magic> Magic for T {}

fn is_copy<T: Copy>() {
	// this function believes `T: Copy`
}

fn main() {
	// this can be called because we believe that
	// * `String: Magic` because
	//     * `String: Magic`, and we accept cycles.
	// And then `String: Magic` implies `String: Copy`.
	is_copy::<String>();
}
```

By my definition, any sound type/trait system must reject this program because, if it were to execute, then execution would reach `is_copy::<String>` and yet there is no` Copy` impl that is judged to ber applicable to `String`. Uh oh!

[^def]: I would like to, but haven't, define a simplified version of Rust that includes trait solving and simple type checkoing and show that it cannot ["go wrong"][gw].

[gw]: https://en.wikipedia.org/wiki/Type_safety#Definitions

## Coming next

As I promised, this post was mostly focused on "setting the scene". My goal was to explain what the problem is that we are trying to solve -- permitting "good cyclic impls" but forbidding bad ones. I didn't spend a lot of time on the bad ones, but it turns out that there's a wide variety of unsound things one can do, some of which the compiler currently gets wrong, others of which it would only get wrong if we started permitting cycles.

My motivation for getting into this work is a bit complicated. I want perfect derive. But it's also a loose end in our trait semantics that I really want to see nailed down before we move onto other tasks. Having auto traits (e.g., `Send`) work differently from other traits is clearly a "smell", and without a strong understanding of the logical underpinnings of our trait system it's easy to get things wrong when we build extensions.

In the next few posts I'll go a bit deeper into the exploration I and others have been doing. I'll talk about some of the "false starts" we took along the way and why they don't work, and then about some of the solutions that are under consideration. Working through this stuff has really helped me to broaden my understanding of various areas of logic. By the time we're done, we'll cover[^shallow] coinduction and productivity, modal logic and the later modality, and we'll see how our techniques might even help us with resolving specialization[^plottwist].

I cited it earlier, but if you want to read other tasks on the same subject, I definitely recommend [Nadri's post on dictionary-passing style][dps].

[^shallow]: In a shallow way, I'm no expert!

[^plottwist]: Plot twist, bet you didn't see that coming! I sure didn't.

