It's been a while since I talked about parallel JavaScript, so I
thought I would give an update.  I've been working for some time now
on implementing the [Rivertrail API][rt] for data-parallelism.  This
is somewhat different from my previous post which discussed the
[PJS API][pjs], though there has been (slower) progress on that front
as well.

### Rivertrail 

It is interesting to compare and contrast the two APIs.  The
Rivertrail API, developed initially by researchers at Intel but now
being floated before the [ECMA committee in strawman form][ecma], is
focused on enabling the parallel processing of large arrays (or
N-dimensional matrices) of data.  To that end, it exposes a new class
called ParallelArray which offers various higher-order operations
(`map()`, `reduce()`, `scatter()`, and so forth).  Compared to a
normal array, a ParallelArray has many limitations:

- it is immutable;
- it cannot have holes;
- the higher-order operations like `map()` can only be used with
  *side-effect-free functions* (more on this topic soon)

However, the benefit of using a ParallelArray is that the compiler
will attempt to execute your operations in parallel.  In fact, it will
often be possible to use both worker threads (multicore) but also
vector units (intracore).  Intel's prototype even executes on the GPU,
though we have no immediate plans to do that in our implementation
(someday).

An example of using Rivertrail might be the following:

    function multiply(matrix1, matrix2) {
        assert matrix1.shape[1] == matrix2.shape[0];
        let m = matrix1.shape[1];
        return new ParallelArray(
            [matrix2.shape[1], matrix1.shape[0]],
            function(i, j) {
                let sum = 0;
                for (let k = 0; k < m; k++)
                    sum += matrix1.get(i, k) + matrix2.get(k, j);
                return sum;
            });
    }

    function multiply(matrix, vector) {
        return matrix1.map(
            function(row) {
                let products = row.map((e, i) => row[i] * vector[i]);
                return products.reduce((a, b) => a + b);
            });
    }

### PJS 

The PJS API, in contrast, is focused on what is called *task
parallelism*.  

[rt]: https://github.com/RiverTrail/RiverTrail
[ecma]: http://wiki.ecmascript.org/doku.php?id=strawman:data_parallelism
[pjs]: http://smallcultfollowing.com/babysteps/blog/2012/02/01/update/
