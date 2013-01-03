---
layout: post
title: "Function and object types"
date: 2012-10-23 16:41
comments: true
categories: [Rust, FnTypes]
---

My big goal for 0.5 is to straighten out our function types ([yet again][fn]).  I've
been tossing the design for these over in my head since the summer and
I wanted to lay out my plan.  This is a variation of something
that Ben Blum and I sketched out on a whiteboard.

[fn]: /blog/categories/fntypes

### Closure type

The closure type will be described something like so.  Beware, it's
got a lot of options.  It turns out that there is a very large variety
of things one might want to use closures for, and supporting them
requires a fair number of knobs.  I *believe* that in practice there
will be a smallish set of standard forms (I'll describe those later).
In any case, this is the closure type in its full generality, with
annotations:

    (&|~|@) [r/] [pure|unsafe] [once] fn [:K] (S) -> T
    ^~~~~~^ ^~~^ ^~~~~~~~~~~~^ ^~~~~^    ^~~^ ^~^    ^
       |     |     |             |        |    |     |
       |     |     |             |        |    |   Return type
       |     |     |             |        |  Argument types
       |     |     |             |    Environment bounds
       |     |     |          Once-ness (a.k.a., affine)
       |     |   Purity
       | Lifetime bound
    Allocation type

Let's go through each of these things to see what they mean,
left to right.  I'll also mention defaults for the optional
sections (indicated above with braces `[]`).

- *Allocation type:* A closure always includes a pointer to its
  environment.  The allocation type indicates what kind of pointer
  this is.
- *Lifetime bound:* If the environment contains borrowed pointers,
  this is the intersection of all of their lifetimes.  For any sigil
  other than `&`, it defaults to `&static`, meaning only statically
  allocated data.  For `&`, the default is selected as per any
  region pointer.
- *Purity*: Indicates whether a function may mutate state visible to
  its caller.  Defaults to impure.
- *Once-ness:* Indicates whether the function will only
  be called at most once.  Defaults to
  a function that can be called many times.
- *Environment bounds:* Indicates the kind of data that appears in the
  environment (e.g., sendable data, copyable data, immutable data, any
  old data at all).  Defaults to an empty list.
- *Argument and return types:* Obvious, I should hope.

### Use cases and common combinations

Here are some of the scenarios where we use closures, and the types
I would expect to see (here I am leaving out the argument and return
types):

- Iterators and higher-order functions like `fold` will use
  `&fn()`---which basically means "any old function at all".
- Cleanup- or finally-style patterns will use `&once fn()`, because they
  only invoke their function once.
- Callbacks stored in data structures will be `@fn()`, which means
  "some heap-allocated function".
- The main function of a task will be `~once fn:Send()`, meaning
  a function that can be sent around and can only be called once.
- A clonable or restartable task might be specified with `~fn:Send Copy()`,
  which indicates that the environment is deeply copyable.
- The hash function of a map might be `~pure fn:Send Const()`, which would
  allow the hash function to be sent between tasks and also executed
  many times in parallel (this would be important if the hash function
  were put into a map).
 
### Uncommon scenarios
 
One uncommon scenario that will work is that you might want to return
a closure that closes over a borrowed pointer.  Since you are going to
*return* the closure, you must allocate its environment in the managed
heap; ordinarily such a closure could not enclose a borrowed pointer,
but under the new types you could write:

    fn create_count_fn(x: &lt/mut int) -> @lt/fn() -> int {
        || {
            let v = *x;
            *x += 1;
            v
        }
    }
    
Here `@lt/fn()` means "a function whose environment is on the managed
heap but which contains data that is only valid for the lifetime
`lt`".  This could be used like:

    let mut x = 1;
    let count_fn = create_count_fn(&mut x);
    assert count_fn() == 1;
    assert count_fn() == 2;
    
Of course, this example is artificial.  I have wanted to use a pattern
like this one time, when I was building a combinator library, but I
don't feel like elaborating out a more realistic example.  Certainly I
would not expect this pattern to come up frequently, if at
all---combinator libraries are generally better built using purely
managed data.

### Copyability

Today, all closures types are copyable (despite the fact this is
[not sound][2828]).  This will not be true under this scheme.  Whether
or not a closure is copyable will depend on a number of factors:

- `once` closures are never copyable;
- otherwise:
  - copying a `~` induces a deep clone of its state, and hence
    a `~` closure is copyable if and only if they include the `Copy` bound;
  - copying a `&` or `@` closure is valid and results in a shallow
    copy.

[2828]: https://github.com/mozilla/rust/issues/2828

### Subtyping

There is a subtyping relationship between function types that have the
same allocation type based on the other parameters:

- *Lifetime:* Contravariant with respect to the lifetime, as borrowed
  pointers are;
- *Purity:* Pure is a subtype of impure, impure is a subtype of unsafe;
- *Bounds:* More bounds is a subtype of fewer bounds;
- *Argument types:* Contravariant with respect to the argument type;
- *Return types:* Covariant with respect to the return type.

Today, `@fn()` is a subtype of `&fn()`.  This is unsound and will no
longer be true (because the drop glue for `@fn()` is different, this
subtyping relationship can induce memory leaks).  However, it will
still be allowed to use an `@fn()` or `~fn()` as the value of a
parameter whose type is declared as `&fn()`---this is simply a borrow.

### Trait instances (objects)

Trait instances, which I have decided we should call objects, can be
modeled similarly.  Basically an object is a closure with (a) only one
piece of closed over data and (b) multiple methods.  Here is the
diagram, I won't bother to explain the details as they are analogous
to the function case, except applied to the receiver and not to the
captured upvars:

    (&|~|@) [r/] Trait [:K]
    ^~~~~~^ ^~~^       ^~~^
       |     |          |
       |     |      Environment bounds
       | Lifetime bound
    Allocation type

### Bare functions and extern functions

One thing you'll note: the bare function type, used for function items
without an environment, is going away.  Instead we'll just allow
function items to be coerced to any function type.  Also, we're going
to change our approach to C-style function pointers and add a type
like:

    extern "abi" [pure|unsafe] fn(S) -> T

Here "abi" might be "C", for example.  I'll expand on this in a later
post.
