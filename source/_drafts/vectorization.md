I've been thinking about how we might go about adding vectorization to
our Parallel JS implementation.  I thought I'd start by summarizing
the technique described
[the excellent paper on whole-function vectorization by Karrenberg and Hack][cgo].
Their approach seems to apply very well to the `ParallelArray` API,
though using it in IonMonkey will require some modification.

<!-- more -->

### Whole-function vectorization

Rather than summarize the paper in detail, I suggest you simply read
it yourself.  It is very readable.  Their model is that you have a
kernel function which is being applied consecutively to elements in an
array, and you'd like to transform this kernel function to operate on
multiple elements at a time.  This is very similar to `ParallelArray`,
clearly.

They do this transformation in two phases:

1. Converting values into SIMD operations;
2. Converting control flow into data flow using mask bits.

To see how this works, let's consider a `ParallelArray` example:

    var parray1 = new ParallelArray(size, ...);
    var parray2 = new ParallelArray(size, ...);
    var parray3 = new ParallelArray(size, function(i) {
        if (parray1[i] > parray2[i])
            return parray1[i] + 1;
        else
            return parray2[i] + 2;
    });
    
This rather artificial example creates three arrays.  The first two
have the same size.  The third is created by comparing `parray1[i]`
and `parray2[i]` and then selecting `parray[i] + 1` or `parray2[i] +
2`.  We'll be looking at this third call.

#### Converting values into SIMD operations

In general, the analysis will convert each value into a SIMD array of
values.  However, there are two special cases where we can be more
optimal.  The first case is when the value is known to have the same
value on every iteration, such as a constant---this case does not come
up in our example.  The second case is when the value is known to be
*consecutive*, meaning that if it has the value `x` in the first
iteration, it will have the value `x+1` in the next iteration, `x+2`
after that, and so on.  In other words, if we are transforming the
function to process `W` elements at a time, the values would be
`x...x+W-1`.

In our example, the variable `i` could be classified as consecutive.
In fact, it can be further classified as consecutive, aligned.  The
aligned means that its value in the first iteration is always a
multiple of the SIMD width `W`.  We know this is true because we
processing `W` elements at a time, so the first call will have an `i`
of 0, and the next call will have an `i` of `W`, then `2W`, and so on.
Note that if size is not evenly divisible by W, we'll have to do some
cleanup iterations in the normal way.

Because `i` is known to be consecutive, the array loads `parray1[i]`
and `parray2[i]` can be converted into a SIMD load (in fact, since `i`
is known to be aligned, we can use the aligned variant, which can be
slightly faster).  If `i` were not known to be consecutive, we'd have
to convert an array load like `parray1[i]` into four distinct loads and
then pack those values into a SIMD register (unless a gather
instruction is available for the CPU we are targeting).  This is
likely to be so expensive as to be not even worth the trouble.

#### Converting control-flow

For instruction sets like SSE, we have to be very careful about
control flow.  The function in our prior example included an `if` that
could easily take different paths for each consecutive iteration.
Instructions set like SSE cannot tolerate this kind of
divergence---when you have a branch, each of the iterations that are
being concurrently processed must take the branch together. The
solution to this problem is to transform the program so that it does
not have any branches.

So, if our original function were:

    function (i) {
        if (parray1[i] > parray2[i])
            return parray1[i];
        else
            return parray2[i];
    }
    
We would compile the function into two instructions, which are
something like:

    Load parray1[i...i+W] into SIMD register R0
    Load parray2[i...i+W] into SIMD register R1
    Compare R0 > R1 into R2
    R0 = R0 + 1
    R1 = R1 + 2
    R3 = Select R0 or R1 based on R2
    Return R3

The first two instructions load the consecutive elements of the two
arrays into SIMD registers, each of which are like a mini-vector
containing `W` values.  The next instruction compares those individual
values and computes a new vector of booleans.  So each element in `R2`
will be `1` if the corresponding element in `R0` was greater than
`R1`.  Finally, we add `1` to each element in `R0` and `2` to each
element in `R1`, and then select from `R0` or `R1` based on the value
`R2`.  Here the value `R2` is called a mask, because it effectively
tells you what path the individual iteration would have taken---if
`R2` is 1 for a given element, it says that this element would have
gone down the `if` path versus the `else` path.

What is interesting about this transformation is that we have
effectively executed *both* the if and the else path for each
transform.  This is ok because those paths are side-effect free.  In
the paper, they generalize this mask computation to arbitrary
situations, including loops and so forth, so that you can effectively
transform arbitrary control flow.

This transformation starts to break down, however, if there are
side-effects or operations without SIMD equivalents.  To handle such
cases you have to stop and unpack the mask registers and other values
so as to execute the code normally.  As before, this is probably so
slow as to not be worthwhile.

### Applying whole-function vectorization to Parallel JS

One big difference between their approach and our own compiler is
that, in our compiler, we don't want to vectorize the whole function.
The reason is that while the ParallelJS *API* takes a kernel function
that applies to each value in the array separately, the parallel
intrinsic in our self-hosted runtime takes a kernel functon that is
applied to a slice of the array.  That means that

[cgo]: http://ieeexplore.ieee.org/xpl/articleDetails.jsp?arnumber=5764682
