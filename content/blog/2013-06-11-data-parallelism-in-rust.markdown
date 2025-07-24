---
layout: post
title: "Data Parallelism in Rust"
date: 2013-06-11T11:57:00Z
comments: true
categories: [Rust]
---

Rust currently has very strong support for concurrency in the form of
actors which exchange messages and do not share memory. However, there
are many tasks for which actors are not a good fit. The unbounded
lifetime of actors means that they cannot safely access
stack-allocated memory from another task, even if it is
immutable. Actors cannot share memory except through the relatively
clumsy (and somewhat expensive) mechanism of `Arc` structures (which
stands for "atomic reference count"), meaning that if there are large
data structures they can be a pain to access. `Arc` is also
inapplicable to data structures that transition between mutable and
immutable and back again.

I was recently pointed to the paper
["Three layer cake for shared-memory programming"][cake], which
describes perfectly the direction in which I would like to see Rust
go. Message passing is retained at the top-level, but within an actor,
you have support for fork-join concurrency. I've been calling these
fork-join tasks "jobs". Within a job, you can get yet more concurrency
via SIMD primitives.

To that end, I've been working on promising design for fork-join
concurrency in Rust. I am very pleased both because the API looks like
it will be simple, flexible, and easy to use, and because we are able
to statically guarantee data-race freedom *even with full support for
shared memory* with only minimal, generally applicable modifications
to the type system (closure bounds, a few new built-in traits). The
scheme also requires no changes to the runtime; it can be implemented
simply as a library.

In particular, the existing borrow checker rules, which were aimed at
preventing dangling pointers, turn out to be extremely well-suited to
this task.  I find this very interesting and very heartening as well,
and I think it points to a kind of deeper analogy between memory
errors in sequential programs and data races in parallel programs.
I will elaborate on this theory in a later post.

<!-- more -->

### The API

The API is based on a fork-join model. There are a number of helper
functions, each of which starts up a number of parallel jobs and
returns when those jobs have completed. The API builds on Rust's type
system to statically guarantee data-race freedom. Under typical usage,
in fact, the API even guarantees deterministic results, though this
guarantee can be voided by making use of locks, ports, and certain
other advanced types.

I have adopted the term `job` to distinguish the lightweight parallel
tasks that from Rust's normal tasks. Although both can be used for
parallel execution, they are quite different in most other respects.
For example, jobs all share the same memory space as their parent
task, whereas tasks are strictly isolated from one another.  Jobs also
have a fixed lifetime, whereas tasks run asynchronously. In general,
executing a parallel job is supposed to act exactly as though the text
of that job were inlined into the task body, modulo certain observable
timing differences (and nondeterminism around locks and message
ordering).

To some extent, the API that I'm going to discuss is a strawman.
Expect changes to the details, of course. Also, I only present the
primitive operations here; there will be a number of higher-level
wrappers for common operations (like parallel map and reduce and so
forth). In keeping with the ["three layer cake"][cake] idea, these
higher-level primitives may employ SIMD as well.

#### Parallel execute

The most primitive method in Parallel arsenal is `parallel::execute(jobs)`,
which takes an array of closures and executes the closures in parallel
jobs (well, at least potentially---it may opt to run them sequentially
if insufficient parallel resources exist). Once these jobs complete,
`execute()` returns.

These closures are permitted to share memory and capture values by
reference.  We will see later that the type checker will validate that
if one of these jobs writes to a particular value, then none of the
other jobs can access it; you are allowed however to access the same
data so long as all jobs treat it as immutable.

To make the usage more concrete, here is an example that uses
`parallel::execute` to sum up the values in a binary tree in parallel.
Note that no heap allocation is required at any point in the
iteration, which is nice from a performance point of view.

    struct Tree {
      val: uint,
      left: Option<~Tree>,
      right: Option<~Tree>,
    }
    
    fn sum_tree(tree: &Tree) -> uint {
      let mut left_sum = 0;
      let mut right_sum = 0;
      
      parallel::execute([
        || left_sum = sum_opt_tree(&tree.left),
        || right_sum = sum_opt_tree(&tree.right),
      ]);
      
      left_sum + right_sum + tree.val
    }

    fn sum_opt_tree(tree: &Option<~Tree>) -> uint {
      match tree {
         Some(~ref t) => sum_tree(t),
         None => 0,
      }
    }
    
The type of `execute()` is:

    fn execute(jobs: &[fn:Isolate()])
    
Here the `fn:Isolate()` means "a closure that only closes over state
that is either shared or isolated from other threads". I'll explain
this bound and the other details of static safety checking shortly.

#### Parallel divide

The other primitive parallel operation is `divide()`, which takes a
mutable slice and a closure. It will divide up the slice into a number
of subslices and invoke your closure on it; the precise means that it
uses to divide the subslice is unspecified. You can also configure
`divide()` with the minimum granularity that it should use when dividing
the array (for example, you might prefer to be called back with
subslices that are a multiple of 10 items).

In a way, `execute()` is more fundamental than `divide()`, as you can
implement `divide()` using `execute()` by recursively dividing the array
in half. However, I choose to call `divide()` a second primitive because
it can be far more efficient to divide the array using other
strategies, such as determining how many worker threads are available
and just chopping the slice into `N` equal parts (of course this will
depend on the workload).

The reason that `divide()` provides you with a mutable subslice, rather
than say a pointer to an individual element, is that often there is
setup work that can be shared between consecutive elements when
processing an array. Consider the following example, which treates a
vector `v` as a 2d array, and invokes the closure `f` in parallel with
each element in the array and its `x` and `y` coordinate. In this
case, the initial computation of `x` and `y` from the index in `v` is
relatively expensive, as it requires division, but updating `x` and
`y` is very cheap. Using `divide()`, the initial division can be
amortized over a large subslice.

    fn update_two_dim<T>(v: &mut [T],
                         width: uint,
                         f: fn:Share(&mut T, x: uint, y: uint)) {
      assert!(v.len() % width == 0);                     
      do parallel::divide(array, 1) |slice, offset| {
        let mut (x, y) = (offset % width, offset / width);
        for slice.each_mut |p| {
          update(p, x, y);
          x += 1;
          if x == width {
            x = 0;
            y += 1;
          }
        }
      }
    }
    
The type of `divide()` is:

    fn divide<T>(data: &mut [T],
                 granularity: uint,
                 job: fn:Share(&mut [T], uint))

You'll note that the type of the closure is different from
`execute()`. Whereas before we had `fn:Isolate`, for `divide()` we
have `fn:Share`. This is in fact a tighter bound that only permits
content that can safely be accessed in parallel by multiple
threads. The difference is due to the fact that, with `execute()`,
each closure got its own parallel job, but with `divide()`, the same
closure will be called simultaneously from multiple jobs.

### Checking safety

So how can we guarantee that these APIs are used safely? For example,
what ensures that the user doesn't write a program like this one (variations
on this example will serve as examples through this section):

    fn compute_foo_and_bar(dataset: &[uint]) -> (uint, uint) {
        let mut foo = 0;
        let mut bar = 0;
        parallel::execute([
            || foo = compute_foo(dataset),
            || foo = compute_bar(dataset), // <-- Bug here!
        ]);
        (foo, bar)
    }
    fn compute_foo(dataset: &[uint]) -> uint { ... }
    fn compute_bar(dataset: &[uint]) -> uint { ... }


In this example, the function `compute_foo_and_bar()` creates two
closures, one of which creates `compute_foo()` and one of which
invokes `compute_bar()`. The two closures run in parallel.  However,
there is a slight bug: both closures write to `foo`, though presumably
the author meant for the second closure to write to `bar`. Therefore,
this program will be rejected as racy: let's see how the borrow
checker comes to that conclusion.

#### Desugaring closures

In fact, this conclusion falls out of the normal borrow checker safety
rules for closures (more accurately, it *will* fall out of those rules
once I fix them).  The way the borrow checker handles closures is
essentially to "desugar" them into the pair of a struct that contains
pointers and a fn pointer.  To see what, let's examine the first
closure from our example in more detail:

    || foo = compute_foo(dataset)
    
If we wanted to model this closure more precisely, we could
consider it as the pair of an environment struct and a function.
It would look something like this:

    struct FooEnv {
        foo: &mut uint,
        dataset: &[uint]
    }
    
    fn foo_fn(env: &mut TheEnv) {
        *env.foo = compute_foo(env.dataset);
    }

This means that the call to `parallel::execute` would look something
like this:

    parallel::execute([
      // Roughly equivalent to `|| foo = compute_foo(dataset)`
      (&FooEnv {foo: &mut foo, dataset: dataset}, foo_fn),

      // Roughly equivalent to `|| bar = compute_bar(dataset)`
      (&BarEnv {bar: &mut foo, dataset: dataset}, bar_fn),
    ])
    
This is in fact the kind of code that gets generated at runtime.  The
interesting thing about looking at closure creations this way is that
we can apply the standard Rust borrowing rules to them. In particular,
we see that there are two mut borrows of the variable `foo`, and those
borrows have overlapping lifetimes, which is not permitted.

#### The role of closure bounds

As the previous example showed, the borrow checker's normal rules
already gives us many of the guarantees we require. We covered
specifically how the borrow checker handles closures, but in general
the borrow check guarantees that:

- `&mut T` pointers are the *only way* to modify the memory that they
  point at (thus guaranteeing that if job A has an `&mut` pointer,
  no other job can be writing that memory);
- `&T` pointers are *immutable* (thus guaranteeing that if job A has a
  `&T` pointer, no job can be writing to that memory).
  
However, there are several guarantees that the borrow checker does
*not* provide which are unnecessary in a sequential context but become
important when discussing data races:

- Although `&mut T` pointers are the only way to *mutate* the memory
  they point at, they are not the only way to *read* the memory they
  point at. Both `&const T` and `@mut T` can produce read-only
  aliases; thus is one job holds an `&mut T` and another an `&const
  T`, the two jobs could race.
- The Rust standard library includes a number of types that include
  "interior mutability", meaning mutability inherent in the type
  itself, vs imposed from the outside. Examples are `@mut`, `RcMut`,
  and `Cell`. Many of these types are not threadsafe, with the notable
  exception of `RwArc`, which employs mutual exclusion.
- Managed pointers like `@T` and `@mut T` are currently not safe
  to pass between parallel jobs, though in the case of `@T` this is
  an implementation limitation and not a theoretical one.

What all this means is that if the `parallel::execute()` accepted an
array of any old closures, it could be sure that those closures would
not race on any `&mut T` or `&T` values that they may have access to,
but races could arise if those closures had access to `&const T`
values (not to mention `@mut T`, `Cell`, and so on).

There is a similar danger for `parallel::divide()`. Unlike
`execute()`, which accepts an array of closures and executes each one
from its own parallel job, `divide()` accepts a single closure and it
invokes that same closure many times in parallel. This means that if
the closure were close over an `&mut` pointer, that *same pointer*
would be available to many threads, and thus races could arise.

##### Enter closure bounds

We prevent both of these scenarios with *closure bounds*. A closure
bound is a limitation on the kinds of values that a closure can
contain in its environment. This is directly analogous to the bounds
that appear on type parameters in generic functions. For example,
if we declare a generic function `f` like so:

    fn f<T:Freeze>(v: &[T]) { ... }
    
The bound `:Freeze` on `T` indicates that `T` may only be used with
values that are freezable (which means "no interior mutability", so
e.g. `@mut` and `Cell` are excluded). Similarly, the type
`fn:Freeze()` would indicate a function whose environment contained
only freezable values.

As currently planned, closure bounds are less general than the
bounds which appear on type parameters, in that they are limited to
the "built-in" traits like `Freeze` and `Send`. These traits differ
from other traits in that they offer no methods and you never explicitly
implement them. The traits are used to describe properties of the data
in question, like whether it may be mutable, and the compiler just
decides automatically whether a given type belongs to this trait or
not. Normally, the compiler would never consider a closure type `fn()`
to be a member of such a trait, because it does not know what data the
closure contains, but this does not necessarily apply to bounded
closure types.  For example, the type `fn:Freeze()` is itself a member
of `Freeze`.

Perhaps in the future we can extend closure bounds to arbitrary
traits. For example, a type like `fn:Eq()` might permit deep
comparison of closure environments, or `fn:Clone()` could permit deep
cloning.  I haven't thought deeply about this, though, and it would
presumably require some sort of `impl` based on reflection.

##### Closure bounds apply to "desugared" environments

One thing that is not entirely obvious is that closure bounds refer to
the *desugared references* found in a closure environment. Recall
that a closure like `|| foo = compute_foo(dataset)` in fact desugars
to an environment where `foo` is represented as an `&mut` pointer:

    struct FooEnv {
        foo: &mut uint,
        dataset: &[uint]
    }

This means that such a closure would not be considered to meet the bound
`Freeze`, because in its environment the field `foo` is an `&mut`
pointer, which is not freezable. This is true even though the type of
the *variable* `foo` is just `uint`, which does meet `Freeze`.

As a side-effect, a closure of type `fn:Send()` can only exist as a
coercion from an environment-less function, since any true closure
will have borrowed pointers of *some kind* in its environment, and
they are not sendable.

*Hat tip*: Promising Young Intern [bblum][bblum] first expressed this
view of closure bounds. It is much cleaner than the formulation I had
before, which included some ad-hoc rules to achieve the same effect.

##### `execute` and the `Isolate` bound

You may recall that the `parallel::execute()` fn was declared as `fn
execute(jobs: &[fn:Isolate()])`. As the type indicates, it accepts an
array of closures that carry the `Isolate` bound. The `Isolate` bound
accepts "all values that can be transmitted and isolated to a single
parallel job", which in practice means:

- `&mut T` where `T:Isolate`
- `&T` where `T:Isolate`
- Scalar values like `uint`, `int`, etc
- Structs, tuples, and enums if all components can be isolated,
  and the types are not internally mutable
- The "atomic ref count" type `Arc`
- The "mutex" type `RwArc`
- Closures that can be isolated (i.e., `fn:Isolate(T1, T2) -> T3`, where
  `T1`, `T2`, and `T3` need not meet any bound in particular)

Note that this list excludes both `&const T` and `@mut T`, as well as
types like `Cell`, `Rc`, and `RcMut` that employ internal mutation.
The list still includes a number of mutable types, however:

- `&mut T` is safe because, as discussed previously, if one closure has 
  access to an `&mut T`, then none of the other closures has access
  to that same value.
- `Arc` is safe because its reference counters are maintained atomically.
- `RwArc` is safe because it uses a mutex to guarantee that any
  mutation which occurs is always threadsafe.
  
The `Isolate` bound excludes all managed data. More discussion on this
topic is found below.

##### `divide` and the `Share` bound

The `divide` function is declared as follows:

    fn divide<T:Isolate>(data: &mut [T],
                         granularity: uint,
                         job: fn:Share(&mut [T], uint))
                 
Note that the `job` closure requires the `Share` bound, which
specifies data that can be safely shared amongst many parallel jobs
(meaning, the same value can be accessed simultaneously by many jobs
at once). The data that is being divided only requires the `Isolate`
bound, since that data will never be accessible to multiple jobs at a
time.

The definition of `Share` is a subset of `Isolate` that excludes `&mut`:

- `&T` where `T:Share`
- Scalar values like `uint`, `int`, etc
- Structs, tuples, and enums if all components can be shared,
  and the types are not internally mutable
- The "atomic ref count" type `Arc`
- The "mutex" type `RwArc`
- Closures that can be shared (i.e., `fn:Share(T1, T2) -> T3`, where
  `T1`, `T2`, and `T3` need not meet any bound in particular)

Note that it is still safe to share `RwArc` (the mutex type).

##### Relationship of `Isolate` and `Share` to existing bounds

Rust already has two "built-in" bounds, `Freeze` and `Send`, which are
both somewhat more strict that `Isolate` and `Share` (`Freeze`, for
example, would reject `RwArc`, and `Send` would reject all `&T` or
`@T` values). I think the full hierarchy is as follows:

    Isolate
      Share
        Freeze
        Send

Here the indentation is intended to indicate an inclusion
relationship.  In other words, anything that meets `Send` or `Freeze`
meets both `Isolate` and `Share`, but not vice versa. Similarly,
anything that meets `Share` meets `Isolate`, but not vice versa.

#### Extending to permit sharing of managed data

In general we can implement a minimal version of this scheme with no
changes to the runtime. The parallel job dispatching can be
implemented as a library building on the existing scheduler. Unsafe
code would be used to "leak" the closures outside of one task and into
another. This is safe because we know that parent thread will be
blocking, and thus the stack-allocated closures will remain valid;
data-race-freedom is then guaranteed by the mechanisms I have already
discussed. Once the jobs are executed over on the tasks, messages are
sent back and the `execute` or `divide` function returns and permits
the main thread to resume executing.

If we wanted to allow `@T` values to be passed to parallel jobs, we
would have to make some deeper changes. First, this is incompatible
with the non-atomic reference counting and cycle collection mechanism
we use today. Even when we move to a tracing collector, though, we
will have to generalize the collector to permit multiple parallel jobs
to access in parallel. This is still a more limited setting than a
full-on cross-process garbage collector, as you find in JVMs, but it
will nonetheless add significant complexity. Similar issues arise in
PJS; I have a blog post coming out soon that will discuss some of our
plans in that regard, most of which apply equally to Rust, though not
entirely, because the Rust model is more general than PJS.

Note that nothing prevents parallel jobs from allocating and using
`@T` and other values internally. This is fine; we are guaranteed that
these values cannot outlive the parallel job because the closure
cannot closure over any location that could store such values, and the
closure argument and return types must always meet the `Isolate`
bound.

### Summary

This post summarizes my current thinking about how to achieve
ligher-weight data parallelism in Rust. The critical differences
between the *parallel jobs* described here and the existing tasks are
that *jobs* would have access to borrowed pointers and thus to data
found in the stack frame and even, to some extent, managed heap of the
parent task. Jobs would always have a fixed lifetime and follow a
fork-join pattern. Parallel jobs as I describe form the "second layer"
in the ["three layer cake" of parallel programming][cake], enabling
fork-join parallelism while retaining deterministic semantics (modulo
the use of `RwArc`). They can also form the basis for a number of
higher-level APIs and combine well with future extensions to support
SIMD.

[cake]: http://dl.acm.org/citation.cfm?id=1953616
[bblum]: http://winningraceconditions.blogspot.com/
