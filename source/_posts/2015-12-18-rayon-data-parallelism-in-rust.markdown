---
layout: post
title: "Rayon: data parallelism in Rust"
date: 2015-12-18 09:52:00 -0500
comments: false
categories: [Rust]
---

Over the last week or so, I've been working on an update to
[Rayon][rayon], my experimental library for **data parallelism** in
Rust. I'm pretty happy with the way it's been going, so I wanted to
write a blog post to explain what I've got so far.

**Rayon's goal is to make it easy to add parallelism to your
sequential code** -- so basically to take existing for loops or
iterators and make them run in parallel. For example, if you have an
existing iterator chain like this:

``` rust
let total_price = stores.iter()
                        .map(|store| store.compute_price(&list))
                        .sum();
```

then you could convert that to run in parallel just by changing from
the standard "sequential iterator" to Rayon's "parallel iterator":

``` rust
let total_price = stores.par_iter()
                        .map(|store| store.compute_price(&list))
                        .sum();
```

Of course, part of making parallelism easy is making it safe. **Rayon
guarantees you that using Rayon APIs will not introduce data races**.

This blog post explains how Rayon works. It starts by describing the
core Rayon primitive (`join`) and explains how that is implemented.  I
look in particular at how many of Rust's features come together to let
us implement `join` with very low runtime overhead and with strong
safety guarantees. I then explain briefly how the parallel iterator
abstraction is built on top of `join`.

I do want to emphasize, though, that Rayon is very much "work in
progress". I expect the design of the parallel iterator code in
particular to see a lot of, well, iteration (no pun intended), since
the current setup is not as flexible as I would like. There are also
various corner cases that are not correctly handled, notably around
panic propagation and cleanup. Still, Rayon is definitely usable today
for certain tasks. I'm pretty excited about it, and I hope you will be
too!

<!-- more -->

### Rayon's core primitive: join

In the beginning of this post, I showed an example of using a parallel
iterator to do a map-reduce operation:

``` rust
let total_price = stores.par_iter()
                        .map(|store| store.compute_price(&list))
                        .sum();
```

In fact, though, parallel iterators are just a small utility library
built atop a more fundamental primitive: `join`. The usage of `join`
is very simple. You invoke it with two closures, like shown below, and
it will *potentially* execute them in parallel. Once they have both
finished, it will return:

``` rust
// `do_something` and `do_something_else` *may* run in parallel
join(|| do_something(), || do_something_else())
```

The fact that the two closures *potentially* run in parallel is key:
**the decision of whether or not to use parallel threads is made
dynamically, based on whether idle cores are available**. The idea is
that you can basically annotate your programs with calls to `join` to
indicate where parallelism might be a good idea, and let the runtime
decide when to take advantage of that.

This approach of "potential parallelism" is, in fact, the key point of
difference between Rayon's approach and
[crossbeam's scoped threads][scoped-threads]. Whereas in crossbeam,
when you put two bits of work onto scoped threads, they will always
execute concurrently with one another, calling `join` in Rayon does
not necessarily imply that the code will execute in parallel. This not
only makes for a simpler API, it can make for more efficient
execution. This is because knowing when parallelism is profitable is
difficult to predict in advance, and always requires a certain amount
of global context: for example, does the computer have idle cores?
What other parallel operations are happening right now? **In fact, one
of the main points of this post is to advocate for *potential
parallelism* as the basis for Rust data parallelism libraries**, in
contrast to the *guaranteed concurrency* that we have seen thus far.

This is not to say that there is no role for guaranteed concurrency
like what crossbeam offers. "Potential parallelism" semantics also
imply some limits on what your parallel closures can do. For example,
if I try to use a channel to communicate between the two closures in
`join`, that will likely deadlock. The right way to think about `join`
is that it is a parallelization hint for an otherwise sequential
algorithm. Sometimes that's not what you want -- some algorithms are
inherently *parallel*. (Note though that it is perfectly reasonable to
use types like `Mutex`, `AtomicU32`, etc from within a `join` call --
you just don't want one closure to *block* waiting for the other.)

[scoped-threads]: https://github.com/aturon/crossbeam/blob/master/src/scoped.rs

### Example of using join: parallel quicksort

`join` is a great primitive for "divide-and-conquer" algorithms. These
algorithms tend to divide up the work into two roughly equal parts and
then recursively process those parts. For example, we can implement a
[parallel version of quicksort][parquick] like so:

[parquick]: https://github.com/nikomatsakis/rayon/blob/22f04aee0e12b31e029ec669299802d6e2f86bf6/src/test.rs#L6-L28

``` rust
fn quick_sort<T:PartialOrd+Send>(v: &mut [T]) {
    if v.len() > 1 {
        let mid = partition(v);
        let (lo, hi) = v.split_at_mut(mid);
        rayon::join(|| quick_sort(lo),
                    || quick_sort(hi));
    }
}
fn partition<T:PartialOrd+Send>(v: &mut [T]) -> usize {
    // see https://en.wikipedia.org/wiki/Quicksort#Lomuto_partition_scheme
}
```

In fact, the only difference between this version of quicksort and a
sequential one is that we call `rayon::join` at the end!

### How join is implemented: work-stealing

Behind the scenes, `join` is implemented using a technique called
**work-stealing**. As far as I know, work stealing was first
introduced as part of the Cilk project, and it has since become a
fairly standard technique (in fact, the name Rayon is an homage to
Cilk).

The basic idea is that, on each call to `join(a, b)`, we have
identified two tasks `a` and `b` that could safely run in parallel,
but we don't know yet whether there are idle threads. All that the
current thread does is to add `b` into a local queue of "pending work"
and then go and immediately start executing `a`. Meanwhile, there is a
pool of other active threads (typically one per CPU, or something like
that). Whenever it is idle, each thread goes off to scour the "pending
work" queues of other threads: if they find an item there, then they
will steal it and execute it themselves. So, in this case, while the
first thread is busy executing `a`, another thread might come along
and start executing `b`.

Once the first thread finishes with `a`, it then checks: did somebody
else start executing `b` already? If not, we can execute it
ourselves. If so, we should wait for them to finish: but while we
wait, we can go off and steal from other processors, and thus try to
help drive the overall process towards completion.

In Rust-y pseudocode, `join` thus looks something like this (the
[actual code][join] works somewhat differently; for example, it allows
for each operation to have a result):

``` rust
fn join<A,B>(oper_a: A, oper_b: B)
    where A: FnOnce() + Send,
          B: FnOnce() + Send,
{
    // Advertise `oper_b` to other threads as something
    // they might steal:
    let job = push_onto_local_queue(oper_b);
    
    // Execute `oper_a` ourselves:
    oper_a();
    
    // Check whether anybody stole `oper_b`:
    if pop_from_local_queue(oper_b) {
        // Not stolen, do it ourselves.
        oper_b();
    } else {
        // Stolen, wait for them to finish. In the
        // meantime, try to steal from others:
        while not_yet_complete(job) {
            steal_from_others();
        }
        result_b = job.result();
    }
}
```

What makes work stealing so elegant is that it adapts naturally to the
CPU's load. That is, if all the workers are busy, then `join(a, b)`
basically devolves into executing each closure sequentially (i.e.,
`a(); b();`). This is no worse than the sequential code. But if there
*are* idle threads available, then we get parallelism.

### Performance measurements

Rayon is still fairly young, and I don't have a lot of sample programs
to test (nor have I spent a lot of time tuning it). Nonetheless, you
can get pretty decent speedups even today, but it does take a *bit*
more tuning than I would like. For example, with a
[tweaked version of quicksort][demo], I see the following
[parallel speedups][speedup] on my 4-core Macbook Pro (hence, 4x is
basically the best you could expect):

<table class="ndm">
<tr> <th>Array Length</th> <th>Speedup</th> </tr>
<tr> <td> 1K         </td> <td>0.95x   </td> </tr>
<tr> <td> 32K        </td> <td>2.19x   </td> </tr>
<tr> <td> 64K        </td> <td>3.09x   </td> </tr>
<tr> <td> 128K       </td> <td>3.52x   </td> </tr>
<tr> <td> 512K       </td> <td>3.84x   </td> </tr>
<tr> <td> 1024K      </td> <td>4.01x   </td> </tr>
</table>
<p></p>

The change that I made from the original version is to introduce
*sequential fallback*. Basically, we just check if we have a small
array (in my code, less than 5K elements). If so, we fallback to a
sequential version of the code that never calls `join`. This can
actually be done without any code duplication using traits, as you can
see from [the demo code][demo]. (If you're curious, I explain the idea
in an appendix below.)

Hopefully, further optimizations will mean that sequential fallback is
less necessary -- but it's worth pointing out that higher-level APIs
like the parallel iterator I alluded to earlier can also handle the
sequential fallback for you, so that you don't have to actively think
about it.

In any case, if you **don't** do sequential fallback, then the results
you see are not as good, though they could be a lot worse:

<table class="ndm">
<tr> <th>Array Length</th> <th>Speedup</th> </tr>
<tr> <td> 1K         </td> <td>0.41x   </td> </tr>
<tr> <td> 32K        </td> <td>2.05x   </td> </tr>
<tr> <td> 64K        </td> <td>2.42x   </td> </tr>
<tr> <td> 128K       </td> <td>2.75x   </td> </tr>
<tr> <td> 512K       </td> <td>3.02x   </td> </tr>
<tr> <td> 1024K      </td> <td>3.10x   </td> </tr>
</table>
<p></p>

In particular, keep in mind that this version of the code is **pushing
a parallel task for all subarrays down to length 1**. If the array is
512K or 1024K, that's a lot of subarrays and hence a lot of task
pushing, but we still get a speedup of 3.10x. I think the reason that
the code does as well as it does is because it gets the "big things"
right -- that is, Rayon avoids memory allocation and virtual dispatch,
as described in the next section. Still, I would like to do better
than
0.41x for a 1K array (and I think we can).

### Taking advantage of Rust features to minimize overhead 

As you can see above, to make this scheme work, you really want to
drive down the overhead of pushing a task onto the local queue. After
all, the expectation is that most tasks will *never* be stolen,
because there are far fewer processors than there are tasks. Rayon's
API is designed to leverage several Rust features and drive this
overhead down:

- `join` is defined generically with respect to the closure types of
  its arguments. This means that monomorphization will generate a
  distinct copy of `join` **specialized to each callsite**. This in turn
  means that when `join` invokes `oper_a()` and `oper_b()` (as opposed
  to the relatively rare case where they are stolen), those calls are
  statically dispatched, which means that they can be inlined.
  It also means that creating a closure requires no allocation.
- Because `join` blocks until both of its closures are finished, we
  are able to make **full use of stack allocation**. This is good both
  for users of the API and for the implementation: for example, the
  quicksort example above relied on being able to access an `&mut [T]`
  slice that was provided as input, which only works because `join`
  blocks. Similarly, the implementation of `join` itself is able to
  **completely avoid heap allocation** and instead rely solely on the
  stack (e.g., the closure objects that we place into our local work
  queue are allocated on the stack).
 
As you saw above, the overhead for pushing a task is reasonably low,
though not nearly as low as I would like. There are various ways to
reduce it further:

- Many work-stealing implementations use heuristics to try and decide
  when to skip the work of pushing parallel tasks. For example, the
  [Lazy Scheduling][] work by Tzannes et al. tries to avoid pushing a
  task at all unless there are idle worker threads (which they call
  "hungry" threads) that might steal it.
- And of course good ol' fashioned optimization would help. I've never
  even *looked* at the generated LLVM bitcode or assembly for `join`,
  for example, and it seems likely that there is low-hanging fruit
  there.

### Data-race freedom

Earlier I mentioned that Rayon also guarantees data-race freedom.
This means that you can add parallelism to previously sequential code
without worrying about introducing weird, hard-to-reproduce bugs.

There are two kinds of mistakes we have to be concerned about.  First,
the two closures might share some mutable state, so that changes made
by one would affect the other. For example, if I modify the above
example so that it (incorrectly) calls `quick_sort` on `lo` in both
closures, then I would hope that this will not compile:

```rust
fn quick_sort<T:PartialOrd+Send>(v: &mut [T]) {
    if v.len() > 1 {
        let mid = partition(v);
        let (lo, hi) = v.split_at_mut(mid);
        rayon::join(|| quick_sort(lo),
                    || quick_sort(lo)); // <-- oops
    }
}
```

And indeed I will see the following error:

```text
test.rs:14:10: 14:27 error: closure requires unique access to `lo` but it is already borrowed [E0500]
test.rs:14          || quick_sort(lo));
                    ^~~~~~~~~~~~~~~~~
```

Similar errors arise if I try to have one closure process `lo` (or
`hi`) and the other process `v`, which overlaps with both of them.

*Side note:* This example may seem artificial, but in fact this is an
actual bug that I made (or rather, would have made) while implementing
the parallel iterator abstraction I describe later. It's very easy to
make these sorts of copy-and-paste errors, and it's very nice that
Rust makes this kind of error a non-event, rather than a crashing bug.

Another kind of bug one might have is to use a non-threadsafe type
from within one of the `join` closures. For example, Rust offers a
[non-atomic reference-counted type][rc] called `Rc`. Because `Rc` uses
non-atomic instructions to update the reference counter, it is not
safe to share an `Rc` between threads. If one were to do so, as I show
in the following example, the ref count could easily become incorrect,
which would lead to double frees or worse:

[rc]: http://doc.rust-lang.org/std/rc/struct.Rc.html

``` rust
fn share_rc<T:PartialOrd+Send>(rc: Rc<i32> {
    // In the closures below, the calls to `clone` increment the
    // reference count. These calls MIGHT execute in parallel.
    // Would not be good!
    rayon::join(|| something(rc.clone()),
                || something(rc.clone()));
}
```

But of course if I try that example, I get a compilation error:

```
test.rs:14:5: 14:9 error: the trait `core::marker::Sync` is not implemented
                          for the type `alloc::rc::Rc<i32>` [E0277]
test.rs:14     rayon::join(|| something(rc.clone()),
               ^~~~~~~~~~~
test.rs:14:5: 14:9 help: run `rustc --explain E0277` to see a detailed explanation
test.rs:14:5: 14:9 note: `alloc::rc::Rc<i32>` cannot be shared between threads safely
```

As you can see in the final "note", the compiler is telling us that
you cannot share `Rc` values across threads.

So you might wonder what kind of deep wizardry is required for the
`join` function to enforce both of these invariants? In fact, the
answer is surprisingly simple. The first error, which I got when I
shared the same `&mut` slice across two closures, falls out from
Rust's basic type system: you cannot have two closures that are both
in scope at the same time and both access the same `&mut` slice. This
is because `&mut` data is supposed to be *uniquely* accessed, and
hence if you had two closures, they would both have access to the same
"unique" data. Which of course makes it not so unique.

(In fact, this was one of the [great epiphanies for me][epiphany] in
working on Rust's type system. Previously I thought that "dangling
pointers" in sequential programs and "data races" were sort of
distinct bugs: but now I see them as two heads of the same Hydra.
Basically both are caused by having rampant aliasing and mutation, and
both can be solved by the ownership and borrowing. Nifty, no?)

[epiphany]: http://smallcultfollowing.com/babysteps/blog/2013/06/11/on-the-connection-between-memory-management-and-data-race-freedom/

So what about the second error, the one I got for sending an `Rc`
across threads? This occurs because the `join` function declares that
its two closures must be `Send`. `Send` is the Rust name for a trait
that indicates whether data can be safely transferred across
threads. So when `join` declares that its two closures must be `Send`,
it is saying "it must be safe for the data those closures can reach to
be transferred to another thread and back again".

### Parallel iterators

At the start of this post, I gave an example of using a parallel
iterator:

``` rust
let total_price = stores.par_iter()
                        .map(|store| store.compute_price(&list))
                        .sum();
```

But since then, I've just focused on `join`. As I mentioned earlier,
the parallel iterator API is really just a
[pretty simple wrapper][par_iter] around `join`. At the moment, it's
more of a proof of concept than anything else. But what's really nifty
about it is that it does not require *any* unsafe code related to
parallelism -- that is, it just builds on `join`, which encapsulates
all of the unsafety. (To be clear, there *is* a small amount of unsafe
code related to [managing uninitialized memory][collect] when
collecting into a vector. But this has nothing to do with
*parallelism*; you'll find similar code in `Vec`. This code is also
wrong in some edge cases because I've not had time to do it properly.)

I don't want to go too far into the details of the existing parallel
iterator code because I expect it to change. But the high-level idea
is that we have this trait `ParallelIterator` which
[has the following core members][pariter]:

``` rust
pub trait ParallelIterator {
    type Item;
    type Shared: Sync;
    type State: ParallelIteratorState<Shared=Self::Shared, Item=Self::Item> + Send;
            
    fn state(self) -> (Self::Shared, Self::State);
    
    ... // some uninteresting helper methods, like `map` etc
}
```

The idea is that the method `state` divides up the iterator into some
shared state and some "per-thread" state. The shared state will
(potentially) be accessible by all worker threads, so it must be
`Sync` (sharable across threads). The per-thread-safe will be split
for each call to `join`, so it only has to be `Send` (transferrable to
a single other thread). 

The [`ParallelIteratorState` trait][pariterstate] represents some
chunk of the remaining work (e.g., a subslice to be processed). It has
three methods:

``` rust
pub trait ParallelIteratorState: Sized {
    type Item;
    type Shared: Sync;
        
    fn len(&mut self) -> ParallelLen;
            
    fn split_at(self, index: usize) -> (Self, Self);
                
    fn for_each<OP>(self, shared: &Self::Shared, op: OP)
        where OP: FnMut(Self::Item);
}
```

The `len` method gives an idea of how much work remains. The
`split_at` method divides this state into two other pieces.  The
`for_each` method produces all the values in this chunk of the
iterator. So, for example, the parallel iterator for a slice `&[T]`
would:

- implement [`len`][len] by just returning the length of the slice,
- implement [`split_at`][split_at] by splitting the slice into two subslices,
- and implement [`for_each`][for_each] by iterating over the array and
  invoking `op` on each element.
  
Given these two traits, we can implement a parallel operation like
collection by following the same basic template. We check how much
work there is: if it's too much, we split into two pieces. Otherwise,
we process sequentially (note that this automatically incorporates the
sequential fallback we saw before):

``` rust
fn process(shared, state) {
  if state.len() is too big {
    // parallel split
    let midpoint = state.len() / 2;
    let (state1, state2) = state.split_at(midpoint);
    rayon::join(|| process(shared, state1),
                || process(shared, state2));
  } else {
    // sequential base case
    state.for_each(|item| {
        // process item
    })
  }
}
```

Click these links, for example, to see the code to
[collect into a vector][collect] or to
[reduce a stream of values into one][reduce].

[len]: https://github.com/nikomatsakis/rayon/blob/22f04aee0e12b31e029ec669299802d6e2f86bf6/src/par_iter/slice.rs#L30-L36
[split_at]: https://github.com/nikomatsakis/rayon/blob/22f04aee0e12b31e029ec669299802d6e2f86bf6/src/par_iter/slice.rs#L38-L41
[for_each]: https://github.com/nikomatsakis/rayon/blob/22f04aee0e12b31e029ec669299802d6e2f86bf6/src/par_iter/slice.rs#L43-L49
[collect]: https://github.com/nikomatsakis/rayon/blob/22f04aee0e12b31e029ec669299802d6e2f86bf6/src/par_iter/collect.rs#L27-L47
[reduce]: https://github.com/nikomatsakis/rayon/blob/22f04aee0e12b31e029ec669299802d6e2f86bf6/src/par_iter/reduce.rs#L20-L42
[pariter]: https://github.com/nikomatsakis/rayon/blob/22f04aee0e12b31e029ec669299802d6e2f86bf6/src/par_iter/mod.rs#L30-L35
[pariterstate]: https://github.com/nikomatsakis/rayon/blob/22f04aee0e12b31e029ec669299802d6e2f86bf6/src/par_iter/mod.rs#L80-L90

### Conclusions and a historical note

I'm pretty excited about this latest iteration of Rayon. It's dead
simple to use, very expressive, and I think it has a lot of potential
to be very efficient.

It's also very gratifying to see how elegant data parallelism in Rust
has become. This is the result of a long evolution and a lot of
iteration. In Rust's early days, for example, it took a strict,
Erlang-like approach, where you just had parallel tasks communicating
over channels, with no shared memory. This is good for the high-levels
of your application, but not so good for writing a parallel
quicksort. Gradually though, as we refined the type system, we got
closer and closer to a smooth version of parallel quicksort.

If you look at some of my [earlier][dataparinrust] [designs][hotpar],
it should be clear that the current iteration of `Rayon` is by far the
smoothest yet. What I particularly like is that it is simple for
users, but also simple for *implementors* -- that is, it doesn't
require any crazy Rust type system tricks or funky traits to achieve
safety here.  I think this is largely due to two key developments:

- ["INHTWAMA"][IM], which was the decision to make `&mut` references
  be non-aliasable and to remove `const` (read-only, but not
  immutable) references. This basically meant that Rust authors were
  now writing data-race-free code *by default*.
- [Improved Send traits][SS], or RC 458, which modified the `Send`
  trait to permit borrowed references. Prior to this RFC, which was
  authored by [Joshua Yanovski][py], we had the constraint that for
  data to be `Send`, it had to be `'static` -- meaning it could not
  have any references into the stack. This was a holdover from the
  Erlang-like days, when all threads were independent, asynchronous
  workers, but none of us saw it. This led to some awful contortions
  in my early designs to try to find alternate traits to express the
  idea of data that was threadsafe but also contained stack
  references. Thankfully Joshua had the insight that simply removing
  the `'static` bound would make this all much smoother!

### Appendix: Implementing sequential fallback without code duplication

Earlier, I mentioned that for peak performance in the quicksort demo,
you want to fallback to sequential code if the array size is too
small. It would be a drag to have to have two copies of the quicksort
routine. Fortunately, we can use Rust traits to generate those
two copies automatically from a single source. This appendix explains
the [trick that I used in the demo code][demo].

First, you define a trait `Joiner` that abstracts over the `join`
function:

``` rust
trait Joiner {
    /// True if this is parallel mode, false otherwise.
    fn is_parallel() -> bool;
    
    /// Either calls `rayon::join` or just invokes `oper_a(); oper_b();`.
    fn join<A,R_A,B,R_B>(oper_a: A, oper_b: B) -> (R_A, R_B)
        where A: FnOnce() -> R_A + Send, B: FnOnce() -> R_B + Send;
}
```

This `Joiner` trait has two implementations, corresponding to
sequential and parallel mode:

``` rust
struct Parallel;
impl Joiner for Parallel { .. }

struct Sequential;
impl Joiner for Sequential { .. }
```

Now we can rewrite `quick_sort` to be generic over a type `J: Joiner`,
indicating whether this is the parallel or sequential implementation.
The parallel version will, for small arrays, convert over to
sequential mode:

``` rust
fn quick_sort<J:Joiner, T:PartialOrd+Send>(v: &mut [T]) {
  if v.len() > 1 {
    // Fallback to sequential for arrays less than 5K in length:
    if J::is_parallel() && v.len() <= 5*1024 {
      return quick_sort::<Sequential, T>(v);
    }
                                
    let mid = partition(v);
    let (lo, hi) = v.split_at_mut(mid);
    J::join(|| quick_sort::<J,T>(lo),
            || quick_sort::<J,T>(hi));
}
```

[join]: https://github.com/nikomatsakis/rayon/blob/22f04aee0e12b31e029ec669299802d6e2f86bf6/src/api.rs#L23-L64
[demo]: https://github.com/nikomatsakis/rayon/blob/22f04aee0e12b31e029ec669299802d6e2f86bf6/demo/quicksort/src/main.rs#L47-L60
[sync]: http://doc.rust-lang.org/std/sync/index.html
[Lazy Scheduling]: http://dl.acm.org/citation.cfm?id=2629643
[dataparinrust]: http://smallcultfollowing.com/babysteps/blog/2013/06/11/data-parallelism-in-rust/
[hotpar]: http://smallcultfollowing.com/babysteps/blog/2012/06/11/hotpar/
[IM]: http://smallcultfollowing.com/babysteps/blog/2012/11/18/imagine-never-hearing-the-phrase-aliasable/
[SS]: https://github.com/rust-lang/rfcs/blob/master/text/0458-send-improvements.md
[py]: https://github.com/pythonesque
[pjs]: http://smallcultfollowing.com/babysteps/blog/2014/04/24/parallel-pipelines-for-js/
[par_iter]: https://github.com/nikomatsakis/rayon/tree/22f04aee0e12b31e029ec669299802d6e2f86bf6/src/par_iter
[collect]: https://github.com/nikomatsakis/rayon/blob/22f04aee0e12b31e029ec669299802d6e2f86bf6/src/par_iter/collect.rs#L17-L19
[rayon]: https://github.com/nikomatsakis/rayon/
[speedup]: https://en.wikipedia.org/wiki/Speedup#Speedup_in_latency
