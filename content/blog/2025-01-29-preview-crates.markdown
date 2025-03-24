---
title: "Preview crates"
date: 2025-01-29T22:26:31Z
---

This post lays out the idea of *preview crates*.[^hattip] Preview crates would be special crates released by the rust-lang org. Like the standard library, preview crates would have access to compiler internals but would still be usable from stable Rust. They would be used in cases where we know we want to give users the ability to do X but we don't yet know precisely how we want to expose it in the language or stdlib. In git terms, preview crates would let us stabilize the [*plumbing*](https://git-scm.com/book/en/v2/Git-Internals-Plumbing-and-Porcelain) while retaining the ability to iterate on the final shape of the [*porcelain*](https://git-scm.com/book/en/v2/Git-Internals-Plumbing-and-Porcelain).

[^hattip]: Hat tip to Yehuda Katz and the Ember community, Tyler Mandry, Jack Huey, Josh Triplett, Oli Scherer, and probably a few others I've forgotten with whom I discussed this idea. Of course anything you like, they came up with, everything you hate was my addition.

## Nightly is not enough

Developing large language features is a tricky business. Because everything builds on the language, stability is very important, but at the same time, there are some questions that are very hard to answer without experience. Our main tool for getting this experience has been the nightly toolchain, which lets us develop, iterate, and test features before committing to them.

Because the nightly toolchain comes with no guarantees at all, however, most users who experiment with it do so lightly, just using it for toy projects and the like. For some features, this is perfectly fine, particularly syntactic features like `let-else`, where you can learn everything you need to know about how it feels from a single crate.

## Nightly doesn't let you build a fledgling ecosystem

Where nightly really fails us though is the ability to estimate the impact of a feature on a larger ecosystem. Sometimes you would like to expose a capability and see what people build with it. How do they use it? What patterns emerge? Often, we can predict those patterns in advance, but sometimes there are surprises, and we find that what we thought would be the default mode of operation is actually kind of a niche case.

For these cases, it would be cool if there were a way to issue a feature in "preview" mode, where people can build on it, but it is not yet released in its final form. The challenge is that if we want people to use this to build up an ecosystem, we don't want to disturb all those crates when we iterate on the feature. We want a way to make changes that lets those crates keep working until the maintainers have time to port to the latest syntax, naming, or whatever.

## Editions are closer, but not quite right

The other tool we have for correct mistakes is [editions](https://doc.rust-lang.org/edition-guide/editions/). Editions let us change what syntax means and, because they are opt-in, all existing code continues to work. 

Editions let us fix a great many things to make Rust more self-consistent, but they carry a heavy cost. They force people to relearn how things in Rust work. The make books oudated. This price is typically too high for us to ship a feature *knowing* that we are going to change it in a future edition.

## Let's give an example

To make this concrete, let's take a specific example. The const generics team has been hard at work iterating on the meaning of `const trait` and in fact there is a [pending RFC](https://github.com/rust-lang/rfcs/pull/3762) that describes their work. There's just one problem: it's not yet clear how it should be exposed to users. I won't go into the rationale for each choice, but suffice to say that there are a number of options under current consideration. All of these examples have been proposed, for example, as the way to say "a function that can be executed at compilation time which will call `T::default`":

* `const fn compute_value<T: ~const Default>()`
* `const fn compute_value<T: const Default>()`
* `const fn compute_value<T: Default>()`

At the moment, I personally have a preference between these (I'll let you guess), but I figure I have about... hmm... 80-90% confidence in that choice. And what's worse, to really decide between them, I think we have to see how the work on async proceeds, and perhaps also what kinds of patterns turn out to be common in practice for `const fn`. This stuff is difficult to gauge accurately in advance.

## Enter preview crates

So what if we released a crate `rust_lang::const_preview`. In my dream world, this is released on crates.io, using the namespaces described in [RFC #3243][https://rust-lang.github.io/rfcs/3243-packages-as-optional-namespaces.html]. Like any crate, `const_preview` can be versioned. It would expose exactly one item, a macro `const_item` that can be used to write const functions that have const trait bounds:

```rust
const_preview::const_item! {
    const fn compute_value<T: ~const Default>() {
        // as `~const` is what is implemented today, I'll use it in this example
    }
}
```

Interally, this `const_item!` macro can make use of internal APIs in the compiler to parse the contents and deploy the special semantics.

### Releasing v2.0

Now, maybe we use this for a while, and we find that people really don't like the `~`, so we decide to change the syntax. Perhaps we opt to write `const Default` instead of `~const Default`. No problem, we release a 2.0 version of the crate and we also rewrite 1.0 to take in the tokens and invoke 2.0 using the [semver trick](https://github.com/dtolnay/semver-trick).

```rust
const_preview::const_item! {
    const fn compute_value<T: const Default>() {
        // as `~const` is what is implemented today, I'll use it in this example
    }
}
```

### Integrating into the language

Once we decide we are happy with `const_item!` we can merge it into the language proper. The preview crates are deprecated and simply desugar to the true language syntax. We all go home, drink non-fat flat whites, and pat ourselves on the back.

## User-based experimentation

One thing I like about the preview crates is that then others can begin to do their own experiments. Perhaps somebody wants to try out what it would be like it `T: Default` meant `const` by default--they can readily write a wrapper that desugars to `const_preview::const_item` and try it out. And people can build on it. And all that code keeps working once we integrate const functions into the language "for real", it just looks kinda dated.

## Frequently asked questions

### Why else might we use previews?

Even if we know the semantics, we could use previews to stabilize features where the user experience is not great. I'm thinking of Generic Associated Types as one example, where the stabilization was slowed because of usability concerns.

### What are the risks from this?

The previous answers hints at one of my fears... if preview crates become a widespread way for us to stabilize features with usability gaps, we may accumulate a very large number of them and then never move those features into Rust proper. That seems bad.

### Shouldn't we just make a decision already?

I mean...maybe? I do think we are sometimes very cautious. I would like us to get better at leaning on our judgment. But I also seem that sometimes there is a tension between "getting something out the door" and "taking the time to evaluate a generalization", and it's not clear to me that this tension is an inherent complexity or an artificial artifact of the way we do business.

### But would this actually work? What's in that crate and what if it is not matched with the right version of the compiler?

One very special thing about libstd is that it is released together with the compiler and hence it is able to co-evolve, making use of internal APIs that are unstable and change from release to release. If we want to put this crate on crates.io, it will not be able to co-evolve in the same way. Bah. That's annoying! But I figure we still handle it by *actually* having the preview functionality exposed by crates in sysroot that are shipping along the compiler. These crates would not be directly usable except by our blessed crates.io crates, but they would basically just be shims that expose the underlying stuff. We could of course cut out the middleman and just have people use those preview crates directly-- but I don't like that as much because it's less obvious and because we can't as easily track reverse dependencies on crates.io to evaluate usage.

### A macro seems heavy weight! What other options have you considered?

I also considered the idea of having `p#` keywords ("preview"), so e.g. 

```rust
#[allow(preview_feature)]
p#const fn compute_value<T: p#const Default>() {
    // works on stable
}
```

Using a `p#` keyword would fire off a lint (`preview_feature`) that you would probably want to `allow`.

This is less intrusive, but I like the crate idea better because it allows us to release a v2.0 of the `p#const` keyword.

### What kinds of things can we use preview crates for?

Good question. I'm not entirely sure. It seems like APIs that require us to define new traits and other things would be a bit tricky to maintain the total interoperability I think we want. Tools like trait aliases etc (which we need for other reasons) would help.

### Who else does this sort of thing?

*Ember* has formalized this "plumbing first" approach in [their version of editions](https://emberjs.com/editions/). In Ember, from what I understand, an edition is not a "time-based thing", like in Rust. Instead, it indicates a big shift in paradigms, and it comes out when that new paradigm is ready. But part of the process to reaching an edition is to start by shipping core APIs (plumbing APIs) that create the new capabilities. The community can then create wrappers and experiment with the "porcelain" before the Ember crate enshrines a best practice set of APIs and declares the new Edition ready.

*Java* has a notion of preview features, but they are not semver guaranteed to stick around.

I'm not sure who else!

### Could we use decorators instead?

Usability of decorators like `#p[const_preview::const_item]` is better, particularly in rust-analyzer. The tricky bit there is that decorates can only be applied to valid Rust syntax, so it implies we'd need to extend the parser to include things like `~const` forever, whereas I might prefer to have that complexity isolated to the `const_preview` crate.

### So is this a done deal? Is this happening?

I don't know! People often think that because I write a blog post about something it will happen, but this is currently just in "early ideation" stage. As I've written before, though, I continue to feel that we need something kind of "middle state" for our release process (see e.g. this blog post, [*Stability without stressing the !@#! out*]({{< baseurl >}}/blog/2023/09/18/stability-without-stressing-the-out/)), and I think preview crates could be a good tool to have in our toolbox.
