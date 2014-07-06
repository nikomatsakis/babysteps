---
layout: post
title: "Improving our parallel intrinsic"
date: 2012-12-06 09:27
comments: true
categories: [PJs, JS]
---

I mentioned in my previous post that we are using a single primitive
parallel operation to implement PJs.  It turns out that I am not very
satisfied with what we currently have and I have been thinking about
some alternatives. In this post I'll describe briefly how things
are setup, what problems I see, and then sketch out how I think we
could improve it.

### How things work now: `%ParallelBuildArray()`

The current intrinsic is `%ParallelBuildArray(length, func, args...)`.  It
attempts to construct an array in parallel using a pool of `N` worker
threads.  Conceptually, `%ParallelBuildArray()` allocates an array
`result` of length `length` and then instructs each worker thread to
invoke `func(result, id, N, warmup, ...args)`, where:

- `result` is the result array that is being construted in parallel;
- `id` is the id of the worker thread, ranging from `0` to `N`;
- `N` is the total number of worker threads;
- `warmup` is a special flag that is false for the real execution and
  true during a special pre-compilation step.  I will say more on
  `warmup` later.
- `...args` means that any extra arguments passed to `%ParallelBuildArray()`
  are passed on to the function.  This is occasionally useful.
  
`%ParallelBuildArray()` is not guaranteed to succeed: the function
`func` might not be executable in parallel, for example.  Therefore,
on success, it returns the new array, but on failure it returns
undefined.  

Here is an example of how `%ParallelBuildArray()` can be used to
implement a version of `map()` on standard JS arrays (not
`ParallelArray`) that potentially executes in parallel:

    function map(userfunc) {
        var self = this;
        
        // Try in parallel:
        var buffer = %ParallelBuildArray(self.length, fill);
        if (buffer)
            return buffer;
            
        // Fallback to sequential:
        buffer = [];
        fill(buffer, 0, 1, false);
        return buffer;
    
        function fill(result, id, N, warmup) {
            // Compute the portion of the array this thread
            // is responsible for:
            var [start, end] = ComputeTileBounds(self.length, id, N);
            
            // Fill in our portion of the array:
            for (var i = start; i < end; i++)
                result[i] = userfunc(self[i], i, self);
        }
    }
    
I think this code should be fairly self-explanatory. One thing to note
is that `ComputeTileBounds(length, id, N)` is a helper that just
evenly divides the total length among `N` workers and returns the
`id`'th portion. So let's look a bit closer now at how
`%ParallelBuildArray()` works.
    
**Compilation for parallel execution.** Now, normally when you have a
function call in SpiderMonkey, you begin by interpeting the function.
If the function is hot, it gets JIT compiled, first with JaegerMonkey
and then with IonMonkey.  However, to invoke `func` in parallel, we
cannot take this same path.  This is because SpiderMonkey---like all
JS engines---is not thread-safe, so we can't use the interpreter and
so forth.  Instead what we do is to skip right to the final
stage---IonMonkey compilation (hereafter just IM).  So basically
`%ParallelBuildArray()` tries to compile `func` using IM in a special
mode, called parallel execution mode.

When a function is compiled for parallel execution, it is restricted
to a subset of JS.  This subset contains only operations that we have
implemented in a thread-safe way.  It will grow over time.  Sometimes,
the function may be allowed to compile even if it looks like it might
do unsafe things: in those cases, the unsafe things will result in a
*bailout* dynamically, which is basically like throwing a special
exception that says "this parallel code tried to do something that is
not (yet) allowed in parallel execution!"

However, skipping the interpreter and JaegerMonkey and going straight
to IM compilation is a bit difficult.  The problem is that
SpiderMonkey is designed to gather type information and other data
during the interpreter phases.  This data is then used by IM to
generate more efficient code.  Generating efficient code is very
important to parallel execution because, as I explained in
[an earlier post][rt], efficient code is generally *threadsafe code*.

[rt]: /blog/2012/10/10/rivertrail

**Enter the warmup phase.** To handle this situation,
`%ParallelBuildArray()` does something called a warmup.  Basically, it
invokes `func()` in just the same manner as it would normally do,
except (1) sequentially and (2) with the `warmup` flag set to true.
The warmup flag is used by the function to do only a few iterations,
just enough to gather some data but not to do any real work.  During
warmup, the interpreter is in a special mode that records what
functions get called (more on that later).

Once warmup is complete, we have enough type information to compile
`func()`.  However, we also need to compile any functions that
`func()` might invoke during its execution!  The reason is that we
can't (at least not currently) do compilation during the parallel
execution, as it might trigger GC, affect the type inferencing
results, and do all kinds of non-thread-safe things.  So we want to
get those compilations done up front. This is where that list of
functions we gathered during warmup comes into play: we also make sure
that all of those are compiled for parallel execution at the same
time. Since warmup only executes a few iterations, it's possible of
course that `func()` will run code or invoke functions during runtime
that we haven't seen yet.  In that case, we bailout to sequential
execution dynamically.

**Thread safety.** There is one other wrinkle. Normally, code
executing in parallel is not permitted to write to shared objects.
This is enforced by the ion compiler, which only accepts writes that
it can see are legal. However, if you recall our `fill()` function,
you can see that it includes a write to the (shared) `result` array:

    function fill(result, id, N, warmup) {
        // Compute the portion of the array this thread
        // is responsible for:
        var [start, end] = ComputeTileBounds(self.length, id, N);
        
        // Fill in our portion of the array:
        for (var i = start; i < end; i++)
            result[i] = userfunc(self[i], i, self);
    }

This is safe because each thread has a distinct `id` and hence each
thread will write to disjoint portions of the `result` array.  But how
does the IM compiler know this? The answer, of course, is that it does
not.  Instead, there is a hack that says: "the function passed to
`%ParallelBuildArray()` is permitted to write to its first argument".
Essentially that function must be a trusted function.

### What's wrong with this approach?

I have three problems with this approach:

- `%ParallelBuildArray()` is too specialized: it always creates a single
  new array.  Sometimes I want to process an existing array, or create
  multiple arrays.
- The "special case the first argument" approach to thread safety is
  inelegant.  `%ParallelBuildArray()` can only be applied to trusted
  functions.
- The warmup phase is not sound if the user function has side-effects,
  and this is hard to fix.

Let's look at the first two points first, as they are well understood
and the solution is basically agreed upon within the group.  Our plan
to fix them is to change `%ParallelBuildArray()` into something like
`%ForkJoin(func, args...)`, which no longer creates any result arrays
but instead just invokes `func(id, N, ..args)` in parallel from each
worker.  This is basically the same as `%ParallelBuildArray()`, except
that it does not create an array.  We would then have a second
intrinsic, `%UnsafeSetElement()`, that permits unsafe writes into an
array.  Therefore, our map code would look something like:

    function map(userfunc) {
        var self = this;

        // Create buffer and ensure it is allocated to sufficient
        // length (see some discussion on this below):
        buffer = [];
        for (var i = 0; i < self.length; i++)
            buffer[i] = undefined;

        // Try in parallel:
        if (%ForkJoin(fill))
            return buffer;
            
        // Fallback to sequential:
        fill(0, 1, false);
        return buffer;
    
        function fill(id, N, warmup) {
            // Compute the portion of the array this thread
            // is responsible for:
            var [start, end] = ComputeTileBounds(self.length, id, N);
            
            // Fill in our portion of the array:
            for (var i = start; i < end; i++)
                %UnsafeSetElement(buffer, i, userfunc(self[i], i, self));
        }
    }

As you can see, we first create the buffer and then try to fill it,
either sequentially or in parallel.  One thing which is important is
that we have to ensure that `buffer` is preallocated and initialized.
This is because the various threads in the parallel case will be
writing into it at random locations without coordination, so they
can't be growing the buffer dynamically.  We also must be prepared for
GC, which means that the memory must be initializated.  For now, I've
just written an explicit for loop in JavaScript to grow and initialize
the array, but there are other, more efficient options.  I'll discuss
this matter specifically in a later post.

In any case, moving to `%ForkJoin()` addresses the first two points
pretty well.  The workers can write to any number of arrays as output.
There is no special-casing about which arguments are mutable.  It
would be fine to pass any old function to `%ForkJoin()`---unsafe
actions are only possible by using the `%UnsafeSetElement()` intrisic,
which is only permitted in self-hosted code.

### So, what about warmup?

The third problem I mentioned is that warmup is not sound if the user
function has side-effects.  The reason is that both
`%ParallelBuildArray()` (what we have today) and `%ForkJoin()` (what I
just proposed) are supposed to basically have no effect at all if they
return.  But if they ran some warmup iterations, those iterations may
have modified data structures, and that'd be bad.  Now, the current
strawman for Parallel JavaScript, at least, specifies that the
user-provided functions *should not* be mutating global state, but
it's up to the engine to enforce that of course.  And
[I am not sure that's the right thing][pure], in any case!

Another thing I don't like about the current approach to warmup is
that it only runs a small subset of the iterations and this subset
doesn't grow. So if there is some behavior that is not captured by the
warmup, it never will be.  Moreover, the work done in warmup is thrown
away.

So I was thinking.  What if we just did away with the warmup phase
altogether.  Instead, we write the code that invokes `%ForkJoin()` in
such a way that if `%ForkJoin()` fails, the sequential fallback is
itself the warmup.  That means that the final version of our parallel
map would look something like this:

    function map(userfunc) {
        var self = this;

        // Create buffer and ensure it is allocated:
        buffer = [];
        for (var i = 0; i < self.length; i++)
            buffer[i] = undefined;

        // As we iterate, we'll always try to do the remainder
        // of the loop in parallel.  If this fails, we'll execute the
        // next 32 iterations sequentially and try again.
        var chunk = 32;
        var seqi = 0;
        var seqn = length / chunk;
        while (seqi < seqn && !%ForkJoin(fill, seqi * chunk)) {
            fill(seqi++, seqn, 0);
        }
        return buffer;
    
        function fill(id, n, offset) {
            // How far has the sequential loop gotten?
            var [start, end] = ComputeTileBounds(self.length - offset, id, n);
            for (var i = start + offset; i < end + offset; i++)
                %UnsafeSetElement(buffer, i, userfunc(self.get(i), i, self));
        }
    }
    
In this version of the code, we try to run in parallel, but if that
fails we do a "little more work" sequentially and then try in parallel
again.  This means that the sequential loop effectively serves as the
warmup.  Note that it is important for the sequential loop to invoke
the same `fill()` function that is used by the parallel code or else
this technique won't work.

You may recall that part of the purpose of the warmup was to keep a
list of those functions that get used during the compilation so that
they be compiled for parallel execution.  My current plan for how to
address this is to take advantage of the monitoring of callsites that
our type inferencer already does.  Basically we can come up with a
conservative approximation of the functions that get called by walking
the bytecode and ensure that those are compiled.  If during execution
we hit functions that are not compiled, `%ForkJoin()` can compiled
them in parallel execution mode and then try again.

### Future enhancements

Off the top of my head I can think of some easy enhancements.  There
are likely more.

**Avoiding initialization.** It would be nice if we could avoid
initializing the full array, which is after all an O(n) sequential
cost.  I have a vague plan for this wherein we would allocate the
array to its full, final capacity but not initialize the data
(SpiderMonkey already distinguishes between the amount of memory
allocated and the amount of memory initialized).  The `%ForkJoin()`
call would then always be writing into the uninitialized portion; if
it succeeds, it would simply advance the "initialized" counter to the
full capacity.  That requires some care to ensure that it plays well
with the GC, but doesn't seem terribly hard.

**Detecting things that cannot be parallelized.** One thing which
would be useful is to add dynamic monitoring to detect functions that
repeatedly fail to execute in parallel, perhaps because they are
inherently non-threadsafe.  This is similar to the monitoring that
already takes place to find functions that are not suitable to Ion
compilation, as Ion doesn't support the full set of JavaScript either.
In that case, we could rewrite the loop to look something like:

    if (%ParallelDisabled(userfunc)) {
        fill(0, 1, 0);
    } else {
        /* ... the loop that attempts parallel execution
               which we saw before ... */
    }

This would mean that if parallel execution is disabled, we fall right
through to the plain old sequential execution.

[pure]: /blog/2012/10/24/purity-in-parallel-javascript
