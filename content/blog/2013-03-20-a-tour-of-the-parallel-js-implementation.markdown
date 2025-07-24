---
layout: post
title: "A tour of the Parallel JS implementation (Part 1)"
date: 2013-03-20T16:30:00Z
comments: true
categories: [PJs, JS]
---
I am going to write a series of blog posts giving a tour of the
current Parallel JS implementation in SpiderMonkey.  These posts are
intended to serve partly as documentation for the code.  The plan is
to begin high level and work my way down to the nitty gritty details,
so here we go!

I will start my discussion at the level of the intrinsic `ForkJoin()`
function.  As an intrinsic function, `ForkJoin()` is not an API
intended for use by end-users.  Rather, it is available only to
self-hosted code and is intended to serve as a building block for
other APIs (`ParallelArray` among them).

<!-- more -->

### The ForkJoin function

The idealized view of how `ForkJoin` works is that you give it a
callback `fjFunc` and it will invoke `fjFunc` once on each worker thread.
Each call to `fjFunc` should therefore do one slice of the total work.

In reality, though, the workings of `ForkJoin` are rather more
complex.  The problem is that we can only execute Ion-compiled code in
parallel. Moreover, we can only handle ion-compiled code that avoids
the interpreter, since most of the pathways in the interpreter are not
thread-safe. This means that we require accurate type
information. However, we can only *get* accurate type information by
running the code (and, moreover, we can't run the code in parallel
because the type monitoring infrastructure is not thread-safe).

What we wind up doing therefore is using sequential executions
whenever we can't run in parallel.  This might be because there isn't
enough type information, or it might be because the code contains
operations that require parts of the interpreter that are not
thread-safe.

In the general case, a single call to `ForkJoin` can move back and
forth between parallel and sequential execution many times, gathering
more information and potentially recompiling at each step.  After a
certain number of bailouts, however, we will just give up and execute
the remainder of the operations sequentially.

The `ForkJoin` function is designed such that the caller does not have
to care whether the execution was done in parallel or sequential.
Either way, presuming that the callback `fjFunc` is properly written,
the same results will have been computed in the end.

#### The arguments to ForkJoin

ForkJoin expects one or two arguments:

    ForkJoin(fjFunc)               // Either like this...
    ForkJoin(fjFunc, feedbackFunc) // ...or like this.
    
Both arguments are functions.  `fjFunc` defines the operation that
will execute in parallel and `feedbackFunc` is used for reporting on
whether bailouts occurred and why.  `feedbackFunc` is optional and may
be undefined or null.  Not passing in feedback will result in slightly
faster execution as less data is gathered.  The `ForkJoin` function
does not return anything and neither `fjFunc` nor `feedbackFunc` are
expected to return any values; instead, `fjFunc` and `feedbackFunc`
are expected to mutate values in place to produce their output.

#### `fjFunc`: The parallel operation

The signature of `fjFunc` is as follows:

    fjFunc(sliceId, numSlices, warmup)
    
Here `sliceId` and `numSlices` are basically the thread id and the
thread count respectively (though we purposefully distinguish between
the *slice*, a unit of work, and the *worker thread*---today there is
always one slice per worker thread, but someday we may improve the
scheduler to support work-stealing or other more intelligent
strategies for dividing work and then this would not necessarily be
true).

The `warmup` flag indicates whether the function is being called in
*warmup mode*.  As will be explained in the next section, we expect
`fjFunc` to generally track how much work it has done so far.  When
`warmup` is true, the function should do "some" of the remaining work,
but not too much.  When `warmup` is false, it should attempt to do all
the remaining work.  Thus, if `fjFunc` successfully returns when
`warmup` is false, then `ForkJoin` can assume that all of the work for
that slice has been completed.

#### Warmups and bailouts

On the very first call to `ForkJoin`, it is very likely that the
callback `fjFunc` has never been executed and therefore no type
information is available.  In that case, `ForkJoin` will begin by
invoking the callback `fjFunc` *sequentially* (i.e., with the normal
interpreter) and with the `warmup` argument set to true.  We currently
invoke `fjFunc` once for each slice. As we just said, because `warmup`
is true, each call to `fjFunc` should do some of the work in its slice
but not all (`fjFunc` is responsible for tracking how much work it has
done; I'll explain that in a second).  Once the calls to `fjFunc`
return, and presuming no exceptions are thrown, `ForkJoin` will
attempt compilation for parallel execution.

Presuming compilation succeeds, `ForkJoin` will attempt parallel
execution.  This means that we will spin up worker threads and invoke
`fjFunc` in each one.  This time, the `warmup` argument will be set to
false, so `fjFunc` should try and do all the rest of the work that
remains in each slice.  If all of these invocations are successful,
then, the `ForkJoin` procedure is done.

However, it is possible that one or more of those calls to `fjFunc` may
*bailout*, meaning that it will attempt some action that is not
permitted in parallel mode.  There are many possible reasons for
bailouts but they generally fall into one of three categories:

- The type information could be incomplete, leading to a failed type
  guard;
- The script might have attempted some action that is not (yet?)
  supported in parallel mode even though it seems like it might be
  theoretically safe, such as access to a JS proxy, built-in C++
  function, or DOM object;
- The script might have attempted to mutate shared state.

What we do in response to a bailout is to fallback to another
sequential, warmup phase.  As part of this fallback, we typically
invalidate the parallel version of `fjFunc` that bailed out, meaning
that we'll recompile it later.  Next, just as we did in the initial
warmup, we invoke `fjFunc` using the normal interpterer once for each
slice with the `warmup` argument set to true.

Once this "recovery" warmup phase has completed, we will re-attempt
parallel execution.  The idea is that we now have more accurate type
and profiling information, so we should be able to compile
successfully this time.

This process of alternating parallel execution and sequential recovery
runs continues until either (1) a parallel run completes without error
(in which case we're done) or (2) we have bailoud out three times
(which is a random number, obviously, that we probably want to
tune). Once we've had three bailouts, we'll give up and just invoke
`fjFunc` sequentially with `warmup` set to false.

#### An example: ParallelArray.map

To make this more concrete, I want to look in more detail about how
`ParallelArray.map` is implemented in the self-hosted code.  All the
other `ParallelArray` functions work in a similar fashion so I will
just focus on this one.

The semantics of a parallel map are simple: when the user writes
`pa.map(kernelFunc)`, a new ParallelArray is returned with the result of
invoking `kernelFunc` on each element in `pa`. In effect, this is just
like `Array.map`, except that the order of each iteration is
undefined.

Our implementation works by dividing the array to be mapped into
chunks, which are groups of 32 elements.  These chunks are then
divided evenly amongst the `N` worker threads.  The implementation
relies on shared mutable state to track how many chunks each thread
has been able to process thus far.  There is a private array called
`info` that stores, for each chunk, a start index, end index, and a
current index.  The start and end indices simply reflect the range of
items assigned to the worker.  The current index, which is initially
the same as the start index, indicates the next chunk that the worker
should attempt to process.  This array is shared across all threads
and is unsafely mutated using special intrinsics (thus bypassing the
normal restrictions against mutating shared state).

The `ParallelArray` map function is built on `ForkJoin`.  A simplified
verison looks something like this:

    function map(kernelFunc) {
        // Compute the bounds each slice will have to operate on:
        var length = this.length;
        var numSlices = ForkJoinSlices();
        var info = prepareInfoArray(length, numSlices);
        
        // Create the result buffer:
        var buffer = NewDenseArray(length);
        
        // Perform the computation itself, writing into `buffer`:
        ForkJoin(mapSlice);
        
        // Package up the buffer in a parallel array and return it:
        return NewParallelArray(buffer);
        
        function mapSlice(sliceId, numSlices, warmup) {
            // ... see below ...
        }
    }

Here is the source to the map callback function `mapSlice`:

    function mapSlice(sliceId, numSlices, warmup) {
      var chunkPos = info[SLICE_POS(sliceId)];
      var chunkEnd = info[SLICE_END(sliceId)];
  
      if (warmup && chunkEnd > chunkPos)
        chunkEnd = chunkPos + 1;
  
      while (chunkPos < chunkEnd) {
        var indexStart = chunkPos << CHUNK_SHIFT;
        var indexEnd = std_Math_min(indexStart + CHUNK_SIZE, length);
  
        // Process current chunk:
        for (var i = indexStart; i < indexEnd; i++)
          UnsafeSetElement(buffer, i, kernelFunc(self.get(i), i, self));
  
        UnsafeSetElement(info, SLICE_POS(sliceId), ++chunkPos);
      }
    }

This same code is used both for parallel execution and the sequential
fallback.  Each time `mapSlice` is invoked, it will use the `sliceId`
it is given to lookup the current chunk (`info[SLICE_POS(sliceId)]`;
`SLICE_POS` is a macro that computes the correct index).  It will then
process that chunk and update the shared array with the index of the
next chunk (results are unsafely written into the result array
`buffer`---note that this result is not yet exposed to non-self-hosted
code).  If we are in warmup mode, it will stop and return once it has
processed a single chunk.  Otherwise, it keeps going and processes the
remaining chunks, updating the shared array at each point.

The purpose of updating the shared array is to record our progress in
the case of a bailout.  If a bailout occurs, it means that after
processing some portion of the current chunk, the function will simply
exit.  As a result, the "current chunk" will not be incremented, and
the next time that `mapSlice` is invoked with that same `sliceId`, it
will pick up and start re-processing the same chunk.  This does mean
that if a bailout occurs we will process some portion of the chunk
twice, once in parallel mode and then again in sequential mode after
the bailout.  This is unobservable to the end user, though, because
parallel executions are guaranteed to be pure and thus the user could
not have modified shared state or made any observable changes.

The various worker threads will unsafely mutate this shared array to
track their progress.  Unsafe mutations make use of the intrinsic
`UnsafeSetElement(array, index, value)`, which is more-or-less
equivalent to `array[index] = value` except that (1) it assumes the
index is in bounds; (2) it assumes that `array` is a dense array or a
typed array; (3) it does not do any data race detection.  In other
words, you have to know what you're doing.  The same intrinsic is also
used to store the intermediate results.

### `feedback`: Reporting on bailouts

The precise API for `feedback` is to some extent still being hammered
out. Right now this function is used primarily for unit testing so
that we can be sure that parallelization works when we think it
should.  The eventual goal is to display information in the profiler
or other dev tools that indicate what happened. This post is already
long enough, so I'll defer a discussion of the precise process by
which we gather bailout information.  Suffice to say that in the event
of a bailout, each thread records the cause of the bailout (e.g.,
"write to illegal object" or "type guard failure") along with a stack
trace showing the script and its position.

### Note

This note describes the code as it is found on [our branch][shu].
This differs slightly from what is currently landed on trunk.  In
particular, there have been some recent refactorings that renamed the
`ParallelDo` function to `ForkJoin`.  This is because we recently
refactored the source so that `ParallelDo.cpp` and `ForkJoin.cpp`,
originally two distinct but tightly interwoven layers, are now fused
into one abstraction.

[shu]: https://github.com/syg/iontrail
