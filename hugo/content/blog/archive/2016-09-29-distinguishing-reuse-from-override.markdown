---
categories:
- Rust
- Specialization
- Traits
comments: false
date: "2016-09-29T06:02:19Z"
slug: distinguishing-reuse-from-override
title: Distinguishing reuse from override
---
In my [previous post][pp], I started discussing the idea of
intersection impls, which are a possible extension to
[specialization][1210]. I am specifically looking at the idea of
making it possible to add blanket impls to (e.g.) implement `Clone`
for any `Copy` type. We saw that intersection impls, while useful, do
not enable us to do this in a backwards compatible way.

Today I want to dive a bit deeper into specialization. We'll see that
specialization actually couples together two things: refinement of
behavior and reuse of code. This is no accident, and its normally a
natural thing to do, but I'll show that, in order to enable the kinds
of blanket impls I want, it's important to be able to tease those
apart somewhat.

This post doesn't really propose anything. Instead it merely explores
some of the implications of having specialization rules that are not
based purely on "subsets of types", but instead go into other areas.

<!--more-->

### Requirements for backwards compatibility

In the previous post, my primary motivating example focused on the
`Copy` and `Clone` traits. Specifically, I wanted to be able to add an
impl like the following (we'll call it "impl A"):

[pp]: {{ site.baseurl }}/blog/2016/09/24/intersection-impls/
[1210]: https://github.com/rust-lang/rfcs/pull/1210

```rust
impl<T: Copy> Clone for T { // impl A
    default fn clone(&self) -> Point {
        *self
    }
}
```

The idea is that if I have a `Copy` type, I should not have to write a
`Clone` impl by hand. I should get one automatically.

The problem is that there are already lots of `Clone` impls "in the
wild" (in fact, every `Copy` type has one, since `Copy` is a subtrait
of `Clone`, and hence implementing `Copy` requires implememting
`Clone` too). To be backwards compatible, we have to do two things:

- continue to compile those `Clone` impls without generating errors;
- give those existing `Clone` impls **precedence** over the new one.

The last point may not be immediately obvious. What I'm saying is that
if you already had a type with a `Copy` and a `Clone` impl, then any
attempts to clone that type need to keep calling the `clone()` method
you wrote. Otherwise the behavior of your code might change in subtle
ways.

So for example imagine that I am developing a `widget` crate with some
types like these:

```rust
struct Widget<T> { data: Option<T> }

impl<T: Copy> Copy for Widget<T> { } // impl B

impl<T: Clone> Clone for Widget<T> { // impl C
    fn clone(&self) -> Widget<T> {
        Widget {
            data: self.data.clone()
        }
    }
}
```

Then, for backwards compatibility, we want that if I have a variable
`widget` of type `Widget<T>` **for any `T`** (including cases where
`T: Copy`, and hence `Widget<T>: Copy`), then `widget.clone()` invokes
impl C.

### Thought experiment: Named impls and explicit specialization

For the purposes of this post, I'd like to engage now in a thought
experiment. Imagine that, instead of using type subsets as the basis
for specialization, we gave every impl a name, and we could explicitly
specify when one impl specializes another using that name. When I say
that an impl X *specializes* an impl Y, I mean primarily that items in
the impl X **override** items in impl Y:

- When we go looking for an associated item, we use the one in X first.

However, in the specialization RFC as it currently stands,
specializing is also tied to **reuse**. In particular:

- If there is no item in X, then we go looking in Y.

The point of this thought experiment is to show that we may want to
separate these two concepts.

To avoid inventing syntax, I'll use a `#[name]` attribute to specify
the name of an impl and a `#[specializes]` attribute to declare when
one impl specializes another. So we might declare our two `Clone`
impls from the previous section as follows:

```rust
#[name = "A"]
impl<T: Copy> Clone for T {...}

#[name = "B"]
#[specializes = "A"]
impl<T: Clone> Clone for Widget<T> {...}
```

Interestingly, it turns out that this scheme of using explicit names
interacts really poorly with the **reuse** aspects of the
specialization RFC. The `Clone` trait is kind of too simple to show
what I mean, so let's consider an alternative trait, `Dump`, which has
two methods:

```rust
trait Dump {
    fn display(&self);
    fn debug(&self);
}
```

Now imagine that I have a blanket implementation of `Dump` that
applies to any type that implements `Debug`. It defines both
`display` and `debug` to print to `stdout` using the `Debug`
trait. Let's call this "impl D".

```rust
#[name = "D"]
impl<T> Dump
    where T: Debug,
{
    default fn display(&self) {
        self.debug()
    }
    
    default fn debug(&self) {
        println!("{:?}", self);
    }
}
```

Now, maybe I'd like to specialize this impl so that if I have an
iterator over items that also implement `Display`, then `display` dumps
out their debug instead. I don't want to change the behavior for
`debug`, so I leave that method unchanged. This is sort of analogous
to subtyping in an OO language: I am **refining** the impl for
`Dump` by tweaking how it behaves in certain scenarios. We'll call
this impl E.

```rust
#[name = "E"]
#[specializes = "D"]
impl<T> Dump
    where T: Display + Debug,
{
    fn display(&self) {
        println!("{}", value);
    }
}
```

So far, everything is fine. In fact, if you just remove the `#[name]`
and `#[specializes]` annotations, this example would work with
specialization as currently implemented. **But imagine that we did a
slightly different thing.** Imagine we wrote impl E but **without**
the requirement that `T: Debug` (everything else is the same). Let's
call this variant impl F.

```rust
#[name = "F"]
#[specializes = "D"]
impl<T> Dump
    where T: Display,
{
    fn display(&self) {
        println!("{}", value);
    }
}
```

Now we no longer have the "subset of types" property. Because of the
`#[specializes]` annotation, impl F specializes impl D, but in fact it
applies to an overlapping, but different set of types (those that
implement `Display` rather than those that implement `Debug`).

**But losing the "subset of types" property makes the reuse in impl F
invalid.** Impl F only defines the `display()` method and it claims to
inherit the `debug()` method from Impl D. But how can it do that?  The
code in impl D was written under the assumption that the types we are
iterating over implement `Debug`, and it uses methods from the `Debug`
trait. Clearly we can't reuse that code, since if we did so we might
not have the methods we need.

So the takeaway here is that **if an impl A wants to reuse some items
from impl B, then impl A must apply to a subset of impl B's types**.
That guarantees that the item from impl B will still be well-typed
inside of impl A.

### What does this mean for copy and clone?

"Interesting thought experiment," you are thinking, "but how does this
relate to `Copy` and `Clone`?" Well, it turns out that if we ever want
to be able to add add things like an autoconversion impl between
`Copy` and `Clone` (and `Ord` and `PartialOrd`, etc), we are going to
have to move away from "subsets of types" as the sole basis for
specialization. **This implies we will have to separate the concept of
"when you can reuse" (which requires subset of types) from "when you
can override" (which can be more general).**

Basically, in order to add a blanket impl backwards compatibly, we
**have** to allow impls to override one another in situations where
reuse would not be possible. Let's go through an example. Imagine that
-- at timestep 0 -- the `Dump` trait was defined in a crate `dump`,
but without any blanket impl:

```rust
// In crate `dump`, timestep 0
trait Dump {
    fn display(&self);
    fn debug(&self);
}
```

Now some other crate `widget` implements `Dump` for its type `Widget`,
at timestep 1:

```rust
// In crate `widget`, timestep 1
extern crate dump;

struct Widget<T> { ... }

// impl G:
impl<T: Debug> Debug for Widget<T> {...}

// impl H:
impl<T> Dump for Widget<T> {
    fn display(&self) {...}
    fn debug(&self) {...}
}
```

Now, at timestep 2, we wish to add an implementation of `Dump`
that works for any type that implements `Debug` (as before):

```
// In crate `dump`, timestep 2
impl<T> Dump // impl I
    where T: Debug,
{
    default fn display(&self) {
        self.debug()
    }
    
    default fn debug(&self) {
        println!("{:?}", self);
    }
}
```

**If we assume that this set of impls will be accepted -- somehow,
under any rules -- we have created a scenario very similar to our
explicit specialization.** Remember that we said in the beginning
that, for backwards compatibility, we need to make it so that adding
the new blanket impl (impl I) does not cause any existing code to
change what impl it is using. That means that `Widget<T>: Dump` also
needs to be resolved to impl H, the original impl from the crate
`widget`: even if impl I also applies.

This basically means that impl H **overrides** impl I (that is, in
cases where both impls apply, impl H takes precedence). But impl H
**cannot reuse** from impl I, since impl H does not apply to a subset
of blanket impl's types. Rather, these impls apply to overlapping but
distinct sets of types. For example, the `Widget` impl applies to all
`Widget<T>`, even in cases where `T: Debug` does not hold. But the
blanket impl applies to `i32`, which is not a widget at all.

### Conclusion

This blog post argues that if we want to support adding blanket impls
backwards compatibly, we have to be careful about reuse. I actually
don't think this is a mega-big deal, but it's an interesting
observation, and one that wasn't obvious to me at first. It means that
"subset of types" will always remain a relevant criteria that we have
to test for, no matter what rules we wind up with (which might in turn
mean that intersection impls remain relevant).

The way I see this playing out is that we have some rules for when one
impl specializes one another. Those rules do not guarantee a subset of
types and in fact the impls may merely overlap. If, **additionally**,
one impl matches a subst of the other's types, then that first impl
may reuse items from the other impl.

### PS: Why **not** use names, anyway?

You might be thinking to yourself right now "boy, it is nice to have
names and be able to say explicitly what we specialized by what". And
I would agree. In fact, since "specializable" impls must mark their
items as default, you could easily imagine a scheme where those impls
had to also be given a name at the same time. Unfortunately, that
would not at all support my copy-clone use case, since in that case we
want to add the base impl after the fact, and hence the extant
specializing impls would have to be modified to add a `#[specializes]`
annotation. Also, we tried giving impls names back in the day; it felt
quite artificial, since they don't have an identity of their own,
really.

### Comments

Since this is a continuation of my [previous post][pp], I'll just
re-use the
[same internals thread](https://internals.rust-lang.org/t/blog-post-intersection-impls/4129/)
for comments.
