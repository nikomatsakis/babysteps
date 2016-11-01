---
layout: post
title: "Rivertrail"
date: 2012-10-10 17:36
comments: true
categories: [PJs, JS]
---
I have started work on implementing [Rivertrail][rt], Intel's proposal
for data parallelism in JS.  I am excited about this project, it seems
like it's going to be great fun.  The initial version that we produce
is going to be focused on Intel's [specification][spec], but I hope we
can eventually combine it with the more general stuff I've been doing
as part of PJs.  There is an awful lot of overlap between the two,
though also a few minor differences that will need to be ironed out.

In this post I'll sketch an overview of what we're doing.  I plan to
come more of the implementation details in further posts.

[rt]: https://github.com/RiverTrail/RiverTrail/
[spec]: http://wiki.ecmascript.org/doku.php?id=strawman:data_parallelism

<!-- more -->

## Rivertrail for dummies

For those of you who don't know what it is, RiverTrail is a specification
that enables parallel array processing.  The core idea is to add a new
class, `ParallelArray`.  Parallel arrays have some key differences
from JavaScript arrays:

- They are immutable
- They never have holes
- They can be multidimensional but always in a regular way (e.g., in a
  two-dimensional matrix, each row has the same number of columns)

Parallel arrays support a wide variety of higher-order operations,
such as `map()` and `reduce()` but also others.  See the
[Rivertrail specification][spec] for the full list.  These methods
take a function as argument and operate basically the same as those
you would find on a normal JavaScript `Array`.  However, there are two
key differences:

- First, the function that is taken as argument is required to be
  a *pure* function (defined shortly).
- Second, whenever possible, the JavaScript engine will execute
  the function in parallel.
  
### Pure functions  
  
A pure function is just an ordinary JavaScript function which does not
mutate shared state.  This does not mean that the function cannot
mutate *anything*: it can mutate local variables or objects that it
itself allocated.  So, for example, this function which computes the
mandelbrot set is pure:

    function mandelbrot(x, y) {
        var Cr = (x - 256) / scale + 0.407476;
        var Ci = (y - 256) / scale + 0.234204;
        var I = 0, R = 0, I2 = 0, R2 = 0;
        var n = 0;
        while ((R2+I2 < 2.0) && (n < 512)) {
            I = (R+R)*I+Ci;
            R = R2-I2+Cr;
            R2 = R*R;
            I2 = I*I;
            n++;
        }
        return n;
    }

`mandelbrot()` is simple as it only modifies local
variables.  A mildly more interesting example might be `sums()`.
This function computes the partial sums of the input array
`x` and stores them into an output array `sums`:

    function sums(x) {
        var sums = [], sum = 0;
        for (var i = 0; i < x.length; i++) {
            sum += x[i];
            sums[i] = sum;
        }
        return sums;
    }

The main thing I want to highlight here is that the function is
assigning its results into to the array `sums`, and thus modifying a
heap object, rather than simply modifying local variables.  But
because this object was allocated by the function itself, and hence no
one else can observe it, this is still pure. (Actually, this
particular example would not be executable in parallel given some of
the limitations of the *current* RiverTrail implementation, but I hope
to lift those particular limitations soon).

This function is *not* pure, because it modifies `x` which
is not locally allocated:

    x = [1, 2, 3];
    function impure() {
        x[0] += 1;
    }

## Parallel execution

Of course the magic of `ParallelArray` is that, whenever possible, it
will execute your functions in parallel.  Precisely when you get
parallel execution and when you get sequential execution will depend
on the JavaScript implementation.  The fact that the function which
must be executed in parallel is pure means that it is always
*conceptually* safe to execute in parallel, but it does not mean that
the JavaScript engine will be capable of doing so.  JavaScript engines
do a lot of optimizations behind the scenes, and many of them are not
thread-safe.

Our initial implementation is fairly conservative with what kinds of
operations it will execute in parallel.  Over time this set of
operations will gradually expand; I hope that it will someday grow so
wide as to permit any pure function to be executed in parallel.  Time
will tell.

It turns out that the set of things which you ought to do to ensure
that your JavaScript code runs fast is also the same thing things you
ought to do to ensure your JavaScript code runs in parallel.  To see
why this is, consider some JavaScript code like `a.b = c`.  If the JIT
compiler is able to analyze the type of `a` and determine, for
example, that the property `b` is always stored at a specific offset,
it can optimize a store like this into a single assembly instruction.
On the other hand, if it *cannot* analyze this store, in the worst
case, it will be compiled into a call into the interpreter which will
work over various hashtables, the prototype tree, and so forth to
figure out what to do.  Now, when we must decide whether a statement
like `a.b = c` will be thread-safe, it's easy enough to see that a
single store instruction is thread-safe, presuming that the memory
being stored into is only accessible from a single thread (which
purity guarantees).  It's very hard to decide whether that call into
the interpreter that touches hundreds if not thousands of lines of
code is thread-safe.

Of course, knowing what code can be efficiently compiled is no mean
feat (though it's a problem that JS devs have already).  In some later
posts, I will dive into some of the things that work for parallel
execution today and also look at what we expect to work in the near
future.

## Modes of parallel execution

Mozilla's implementation of the Rivertrail spec differs quite a bit
from the [Rivertrail prototype][rt] developed by Intel; the prototype
is a plugin that compiles from JavaScript to OpenCL.  The native
implementation will eventually have four possible ways of running your
code, though only two work at the moment:

- *Sequentially:* This is the fallback mode; it is basically equivalent
  to writing for loops or using the existing higher-order methods on
  `Array`.  Sequential mode works now in Nightly and possibly in
  Aurora (try typing `var x = new ParallelArray([1, 2, 3])` in the
  console if you like).
- *Multicore:* this is the mode we are currently working on.  In Multicore
  mode, there is one worker thread for each core in your system.  Each
  worker thread will be running one copy of the function in parallel.
  We expect a reasonably functional version of this mode to be landing
  on the trunk within a month or two.  We will then be upgrading its capabilities
  over time.
- *Vectorized:* Vectorized mode is similar to multicore, except that each
  worker thread is making use of SSE instructions to process more than
  one element in the array at a time.  Once multicore execution is working,
  this is the next thing we plan to do.
- *GPU:* GPU is actually just a variant on vectorized execution in
  which the vectorized code runs on the GPU instead of the CPU.  There
  are numerous technical differences, though.  For one thing, the GPU
  hardware handles the vectorization, rather than the compiler having
  to use special instructions.  For another, on some platforms at
  least, we have to think about the movement of memory betwen the CPU
  and GPU.
  
Of these modes, the sequential mode is the most general: it can be
applied to any pure function.  The multicore mode is also fairly
general, and can be used with any pure function that restricts itself
to the support set of threadsafe operations.

The vectorized and GPU modes will be more limited.  Vectorized mode is
only profitable for functions where we are able to convert the code
into SSE instructions without creating too much packing and unpacking.
GPU mode similarly imposes limitations on data movement and so forth.

## What about performance?

I won't post extensive numbers here because (1) I have not done any
proper profiling; (2) we don't have good benchmarks; and (3) we have
not spent *any* time optimizing the implementation.  That said, here
are some results from running a mandelbrot computation locally on my
laptop, which has four cores with two hyperthreads each.  The Seq column
lists the time to run sequentially and the Par column lists the time
to run in parallel using the given number of worker threads
(naturally, in normal use the implementation decides how many threads
to use automatically).  The Ratio is sequential divided by parallel,
so higher is better.

<p><table class="hor-minimalist-a">
<tr><th>Threads</th><th>Seq (ms)</th><th>Par (ms)</th><th>Ratio (Seq/Par)</th></tr>
<tr><td>2</td>  <td>2976</td> <td>2515</td> <td>1.18</td></tr>
<tr><td>3</td>  <td>2952</td> <td>1782</td> <td>1.65</td></tr>
<tr><td>5</td>  <td>2964</td> <td>1417</td> <td>2.09</td></tr>
<tr><td>9</td>  <td>2880</td> <td>1149</td> <td>2.50</td></tr>
<tr><td>17</td> <td>2891</td> <td>1109</td> <td>2.60</td></tr>
</table></p>

Obviously, these numbers have room for improvement.  I'd like to see
performance ramp up roughly linearly, at least until we reach the
number of cores.  However, there is definitely some low hanging fruit,
so I am optimistic.

Incidentally, the sequential numbers here are using a normal
JavaScript implementation based on arrays, not the sequential
ParallelArray mode, and I ran the code for a while first to ensure
that the JIT was in use.  At least I think the JIT was in use (this is
what I mean by "I have not done any proper profiling").

**UPDATE:** I realized that I was counting the number of worker
threads, but there is always an extra thread (the "main thread") that
is helping out too.  Hence instead of measuring 1, 2, 4, etc threads,
I have been measuring 2, 3, 5, etc threads.  I have updated the chart
accordingly.

## What about PJs?

Some of you may recall previous ideas I had for
[parallel JavaScript][pjs], which I codenamed "PJs".  For now those
plans are on hold, but I do hope that we'll be able to repurpose some
of the Rivertrail machinery into the PJs API.  I don't see any reason
why it wouldn't work once we have expanded the set of
"multicore-enabled" functions to be wide enough.

[pjs]: blog/categories/pjs/

## In summary...

Parallelism is coming to JS (at least in Firefox) and it's coming
soon.  In a way, I think the APIs that we are implementing will put JS
at the forefront of programming languages with regard to parallelism.
They are extremely easy to use *and* guarantee that executions are
serializable (PJs also guarantees deterministic execution, but
Rivertrail does not due to functions like `reduce()`).  Not many
languages can say that.

**UPDATE:** Some paragraphs edited and expanded slightly for clarity.
