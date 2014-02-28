Today, if you do a mutable borrow of a local variable, you lose the
ability to *write* to that variable except through the new reference
you just created:

    let mut x = 3;
    let p = &mut x;
    x += 1;  // Error
    *p += 1; // OK
    
However, you retain the ability to *read* the original variable:    

    let mut x = 3;
    let p = &mut x;
    print(x);  // OK
    print(*p); // OK
    
I would like to change the borrow checker rules so that both writes
and reads are illegal. This change is not motivated by soundness: the
current rules are perfectly sound. Rather, the motivation is that this
change will enable a more flexible kind of data parallelism API than
what I previously thought possible. As a side benefit, I personally
think it also makes the borrow checker rules more consistent and
composable. Let me explain!

<!-- more -->

### Brief overview of my previous data-parallelism proposal

In a previous post I outlined a plan for
[data parallelism in Rust][dp] based on closure bounds. The rough idea
is to leverage the checks that the borrow checker already does for
segregating state into mutable-and-non-aliasable and
immutable-but-aliasable. This is not only the recipe for creating
memory safe programs, but it is also the recipe for data-race freedom:
we can permit data to be shared between tasks, so long as it is
immutable.

The API that I outlined in that previous post was based on a `fork_join`
function that took an array of closures. You would use it like this:

    fn sum(x: &[int]) {
        if x.len() == 0 {
            return 0;
        }
        
        let mid = x.len() / 2;
        let mut left = 0;
        let mut right = 0;
        fork_join([
            || left = sum(x.slice(0, mid)),
            || right = sum(x.slice(mid, x.len())),
        ]);
        return left + right; 
    }
    
The idea of `fork_join` was that it would (potentially) fork into N
threads, one for each closure, and execute them in parallel. These
closures may access and even mutate state from the containing scope --
the normal borrow checker rules will ensure that, if one closure
mutates a variable, the other closures cannot read or write it. In
this example, that means that the first closure can mutate `left` so
long as the second closure doesn't touch it (and vice versa for
`right`). Note that both closures share access to `x`, and this is
fine because `x` is immutable.

This kind of API isn't safe for all data though. There are things that
cannot be shared in this way. One example is `Cell`, which is Rust's
way of cheating the mutability rules and making a value that is
*always* mutable. If we permitted two threads to touch the same
`Cell`, they could both try to read and write it and, since `Cell`
does not employ locks, this would not be race free.

To avoid these sorts of cases, the closures that you pass to to
`fork_join` would be *bounded* by the builtin trait `Fork` (I called
it `Isolate` in my previous post; I think `Fork` is a better name).
`Fork` indicates data that is safe for "forking" -- that is, for
potentially executing in another thread.

Most data is forkable:

- POD (plain old data) types are forkable, so things like `int` etc.
- `&T` is forkable, because it is imutable.
- `&mut T` is forkable, because only one closure can have access to it.
- `~T` is forkable, because is is not aliasable.
- Structs and enums that are composed of forkable data are forkable.
- `ARC`, because the reference count is maintained atomically.
- The various thread-safe atomic integer intrinsics and so on.

Things which are not forkable include:

- Many types that are unsafely implemented:
  - `Cell` and `RefCell`, which have interior mutability
  - `Rc`, which uses non-atomic reference counting
- Managed data (`Gc<T>`) because we do not wish to
  maintain or support a cross-thread garbage collector

There is a wrinkle though. With the *current* borrow checker rules,
forkable data is only safe to access from a parallel thread if the
*main thread* is suspended. Put another way, forkable closures can
only run concurrently with other forkable closures, but not with the
parent, which might not be a forkable thing.

This is reflected in the API, which consisted of a function
`fork_join` function that both spawned the threads and joined them.
The natural semantics of a function call would thus cause the parent
to block while the threads executed. For many use cases, this is just
fine, but there are other cases where it's nice to be able to fork off
threads continuously, allowing the parent to keep running in the
meantime.

*Note:* I've taken some liberties with the [previous proposal][dp].  I
renamed a few things, and I excluded the parallel map operation, which
is implemetable in terms of `fork_join` anyhow, given the `Share`
trait.

### A more flexible proposal

If we made the change that I described above -- that is, we prohibit
reads of data that is mutably borrowed -- then we could adjust the
`fork_join` API to be more flexible. In particular, we could support
an API like the following:

    fn sum(x: &[int]) {
        if x.len() == 0 {
            return 0;
        }
        
        let mid = x.len() / 2;
        let mut left = 0;
        let mut right = 0;
        
        fork_join_section(|sched| {
            sched.fork(|| left = sum(x.slice(0, mid)));
            sched.fork(|| right = sum(x.slice(mid, x.len())));
        });
        
        return left + right; 
    }

The idea here is that we replaced the `fork_join()` call with a call
to `fork_join_section()`. This function takes a closure argument and
passes it a an argument `sched` -- a scheduler. The scheduler offers a
method `fork` that can be invoked to fork off a potentially parallel
task. This task may begin execution immediately and will be joined
once the `fork_join_section` ends.

In some sense this is just a more verbose replacement for the previous
call, and I imagine that the `fork_join()` function I showed
originally will remain as a convenience function. But in another sense
this new version is much more flexible -- it can be used to fork off
any number of tasks, for example, and it permits the main thread to
continue executing while the fork runs.

*An aside:* it should be noted that this API also opens the door
(wider) to a kind of anti-pattern, in which the main thread quickly
enqueues a ton of small tasks before it begins to operate on
them. This is the opposite of what (e.g.) Cilk would do. In Cilk, the
processor would immediately begin executing the forked task, leaving
the rest of the "forking" in a stealable thunk. If you're lucky, some
other proc will come along and do the forking for you. This can reduce
overall overhead. But anyway, this is fairly separable.

### Beyond parallelism

Speaking more generally, if we know that `&mut` implies that nobody is
reading the referent (except through the `&mut` reference itself),
then we can permit *more kinds* of mutations. For example, we could
temporary move data out from the borrowed reference, so long as we
replace it (we have to be careful of failure, though!). This would
help with improving the performance of binary tree algorithms.

### Impact on existing code

It's hard to say what quantity of existing code relies on the current
rules. My gut tells me "not much" but without implementing the change
I can't say for certain.

### How to implement

Implementing this rule requires a certain amount of refactoring in the
borrow checker (refactoring that is needed for other reasons as well,
however). In the interest of actually completing this blog post, I'm
not going to go into more details (the post has been sitting for some
time waiting for me to have time to write this section). If you think
you might like to implement this change, though, let me know. =)


