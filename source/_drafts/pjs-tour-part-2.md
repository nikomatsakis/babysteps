In my [last post about ParallelJS][pp], I discussed the `ForkJoin()`
intrinsic and showed how it was used to implement the parallel map
operation.  Today I want to dig further in and discuss the C++
implementation of `ForkJoin` as well as the `ThreadPool` that it is
based on.

<!-- more -->

### ThreadPool

The `ThreadPool` class is a very simple thread-pool abstraction.  It
is intended to be used both for the execution of parallel workloads as
well as for parallel compilation, though I still need to submit a
patch that implements parallel compilation on top of the threadpool
(parallel compilation is a JS feature in which JIT compilation
proceeds in parallel with the executing code, meaning that code can
continue to be interpreted until the compiled code is ready, which
helps to mask compiler latency).

The thread pool source is found in `vm/ThreadPool.cpp`. For our
purposes, the interface consists of a single function, `submitAll()`:

    bool submitAll(JSContext *cx, TaskExecutor *executor);
    
Here, `executor` represents a parallel task.  The `TaskExecutor` class
is just a simple abstract class with one method, `executeFromWorker()`:

    class TaskExecutor
    {
      public;
        virtual void executeFromWorker(uint32_t workerId, uintptr_t stackLimit) = 0;
    };

`submitAll()` will cause each worker thread to invoke
`executor->executeFromWorker()`, supplying the appropriate thread id
and stack limit.

Today each `JSRuntime` owns a single thread pool.  It probably makes
sense to modify the design so that multiple `JSRuntime` instances can
share a single thread pool. This would mean that web workers could
make use of Parallel JS functions without creating an inordinant
number of threads and without overloading the user's hardware.

### Implementing `ForkJoin`

The C++ definition of `ForkJoin` can be found in `vm/ForkJoin.cpp`.

[pp]: /blog/2013/03/20/a-tour-of-the-parallel-js-implementation.html
