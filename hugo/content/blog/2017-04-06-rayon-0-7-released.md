---
date: "2017-04-06T00:00:00Z"
slug: rayon-0-7-released
title: Rayon 0.7 released
---

We just released Rayon 0.7. This is a pretty exciting release, because
it marks the official first step towards Rayon 1.0. In addition, it
marks the first release where Rayon's parallel iterators reach
"feature parity" with the standard sequential iterators! To mark the
moment, I thought I'd post the release notes here on the blog:

------

This release marks the first step towards Rayon 1.0. **For best
performance, it is important that all Rayon users update to at least
Rayon 0.7.** This is because, as of Rayon 0.7, we have taken steps to
ensure that, no matter how many versions of rayon are actively in use,
there will only be a single global scheduler. This is achieved via the
`rayon-core` crate, which is being released at version 1.0, and which
encapsulates the core schedule APIs like `join()`. (Note: the
`rayon-core` crate is, to some degree, an implementation detail, and
not intended to be imported directly; it's entire API surface is
mirrored through the rayon crate.)

We have also done a lot of work reorganizing the API for Rayon 0.7 in
preparation for 1.0. The names of iterator types have been changed and
reorganized (but few users are expected to be naming those types
explicitly anyhow). In addition, a number of parallel iterator methods
have been adjusted to match those in the standard iterator traits more
closely. See the "Breaking Changes" section below for
details.

Finally, Rayon 0.7 includes a number of new features and new parallel
iterator methods. **As of this release, Rayon's parallel iterators
have officially reached parity with sequential iterators** -- that is,
every sequential iterator method that makes any sense in parallel is
supported in some capacity.

### New features and methods

- The internal `Producer` trait now features `fold_with`, which enables
  better performance for some parallel iterators.
- Strings now support `par_split()` and `par_split_whitespace()`.
- The `Configuration` API is expanded and simplified:
    - `num_threads(0)` no longer triggers an error 
    - you can now supply a closure to name the Rayon threads that get created 
      by using `Configuration::thread_name`.
    - you can now inject code when Rayon threads start up and finish
    - you can now set a custom panic handler to handle panics in various odd situations
- Threadpools are now able to more gracefully put threads to sleep when not needed.
- Parallel iterators now support `find_first()`, `find_last()`, `position_first()`,
  and `position_last()`.
- Parallel iterators now support `rev()`, which primarily affects subsequent calls
  to `enumerate()`.
- The `scope()` API is now considered stable (and part of `rayon-core`).
- There is now a useful `rayon::split` function for creating custom
  Rayon parallel iterators.
- Parallel iterators now allow you to customize the min/max number of
  items to be processed in a given thread. This mechanism replaces the
  older `weight` mechanism, which is deprecated.
- `sum()` and friends now use the standard `Sum` traits

### Breaking changes

In the move towards 1.0, there have been a number of minor breaking changes:

- Configuration setters like `Configuration::set_num_threads()` lost the `set_` prefix,
  and hence become something like `Configuration::num_threads()`.
- `Configuration` getters are removed
- Iterator types have been shuffled around and exposed more consistently:
    - combinator types live in `rayon::iter`, e.g. `rayon::iter::Filter`
    - iterators over various types live in a module named after their type,
      e.g. `rayon::slice::Windows`
- When doing a `sum()` or `product()`, type annotations are needed for the result
  since it is now possible to have the resulting sum be of a type other than the value
  you are iterating over (this mirrors sequential iterators).

### Experimental features

Experimental features require the use of the `unstable` feature. Their
APIs may change or disappear entirely in future releases (even minor
releases) and hence they should be avoided for production code.

- We now have (unstable) support for futures integration. You can use
  `Scope::spawn_future` or `rayon::spawn_future_async()`.
- There is now a `rayon::spawn_async()` function for using the Rayon
  threadpool to run tasks that do not have references to the stack.

### Contributors

Thanks to the following people for their contributions to this release:

- @Aaronepower
- @ChristopherDavenport
- @bluss
- @cuviper
- @froydnj
- @gaurikholkar
- @hniksic
- @leodasvacas
- @leshow
- @martinhath
- @mbrubeck
- @nikomatsakis
- @pegomes
- @schuster
- @torkleyy
