---
layout: post
title: "Parallel pipelines for JS"
date: 2014-04-24T19:33:00Z
comments: true
categories: [JS]
---

I've been thinking about an alternative way to factor the PJS API.
Until now, we've had these methods like `mapPar()`, `filterPar()` and
so forth. They work mostly like their sequential namesakes but execute
in parallel. This API has the advantage of being easy to explain and
relatively clear, but it's also not especially flexible nor elegant.

Lately, I've been prototyping an alternate design that I call
*parallel pipelines* (that's just a working title; I expect the name
to change). Compared to the older approach, parallel pipelines are a
more expressive API that doesn't clutter up the array prototypes. The
design draws on precedent from a lot of other languages, such as
Clojure, Ruby, and Scala, which all offer similar capabilities. I've
prototyped the API on a [branch of SpiderMonkey][branch], though the
code doesn't yet run in parallel (it is structured in such a way as to
make parallel execution relatively straightforward, though).

**CAVEAT:** To be clear, this design is just one that's in my head. I
still have to convince everyone else it's a good idea. :) Oh, and one
other caveat: most all the names in here are just temporary, I'm sure
they'll wind up changing. Along with probably everything else.

<!-- more -->

### Pipelines in a nutshell

The API begins with a single method called `parallel()` attached to
`Array.prototype` and typed object arrays. When you invoke
`parallel()`, no actual computation occurs yet. Instead, the result is
a *parallel pipeline* that, when executed, will iterate over the
elements of the array.

You can then call methods like `map` and `filter` on this
pipeline. None of these transformers takes any immediate action;
instead they just return a new parallel pipeline that will, when
executed, perform the appropriate `map` or `filter`.

So, for example, you might write some code like:

    var pipeline = [1, 2, 3, 4, 5].parallel().map(x => x * 3).filter(x % 2);
    
This yields a pipeline that, when executed, will multiply each element
of the array by 3 and then select the results that are even.

Once you've finished building up your pipeline, you execute it by
using one of two methods, `toArray()` or `reduce()`. `toArray()` will
execute the pipeline and return a new array with the results.
`reduce()` will exeute the pipeline but instead of returning an array
it reduces the elements returns a single scalar result.

Execution works the same way as PJS today: that is, we will attempt to
execute in parallel. If your code mutates global state, or uses other
features of JS that are not safe for parallel execution, then you will
wind up with a sequential fallback semantics.

So for example, I might write:

    var pipeline = [1, 2, 3, 4, 5, 6].parallel().map(x => x * 3).filter(x % 2);
    
    // Returns [3, 9, 15]
    var results = pipeline.toArray();
    
    // Returns 27 (i.e., 3+9+15)
    var reduction = pipeline.reduce((x, y) => x + y);

### Pipelines and typed objects

The pipeline API is integrated with typed objects. Each pipeline stage
generates values of a specific type; when you `toArray()` the result,
you get back a typed object array based around this type.

Producing typed object arrays doesn't incur any limitations vs using a
normal JS array, because the element type can always just be `any`.
Moreover, in those cases where you are able to produce a more
specialized type, such as `int32`, you will get big savings in memory
usage since typed object arrays enable a very compact representation.

### Ranges

In the previous example, I showed how to create a pipeline given an
array as the starting point. Sometimes you want to create parallel
operations that don't have any array but simply iterate over a range
of integers. One obvious case is when you are producing a fresh array
from scratch.

To support this, we will add a new "parallel" module with a variety of
functions for producing pipelines from scratch. One such function is
`range(min, max)`, which just produces a range of integers starting
with `min` and stepping up to `max`. So if we wanted to compute
the first N fibonnaci numbers in parallel, we could write:

    var fibs = parallel.range(0, N).map(fibonacci).toArray();
    
In fact, using `range()`, we can implement the `parallel()` method
for normal JS arrays:

    Array.prototype.parallel = function() {
        return parallel.range(0, this.length).map(i => this[i]);
    }
    
### Shapes and n-dimensional pipelines    

Arrays are great, but it frequently happens that we want to work with
multiple dimensions. For this reasons, parallel pipelines are not
limited to iterating over a single dimensional space. They are can
also iterate over multiple dimensions simultaneously.

We call the full iteration space a *shape*. Shapes are a list, where
the length of the shape corresponds to the number of dimensions. So a
1-dimensional iteration, such as that produced by `range()`, has a
shape like `[N]`. But a 2-d iteration might have the shape `[W, H]`
(where `W` and `H` might be the width and height of an image).
Similarly, iterating over some 3-D space would have a shape
`[X, Y, Z]`.

To iterate over a parallel shape, you can use the `parallel.shape()`
function. For example, the following command iterates over a 5x5
space, and produces a two-dimensional typed object array of integers:

    var matrix = parallel.shape([5, 5])
                         .map(([x, y]) => x + y)
                         .toArray();
                         
You can see that `shape()` produces a vector `[x, y]` specifying the
current coordinates of each element in the space. In this case, we map
that result and add x and y, which means that the end result will be:

    0 1 2 3 4
    1 2 3 4 5
    2 3 4 5 6
    3 4 5 6 7
    4 5 6 7 8

Another way to get N-dimensional iteration is to start with an
N-dimensional typed object array. The `parallel()` method on typed
object arrays takes an optional *depth* argument specifying how many
of the outer dimensions you want to iterate over in parallel; this
argument defaults to 1. This means we could further transform our matrix
as shown here:

    var matrix2 = matrix.parallel(2).map(i => i + 1).toArray();

The end result would be to add one to each cell in the matrix:

    1 2 3 4 5
    2 3 4 5 6
    3 4 5 6 7
    4 5 6 7 8
    5 6 7 8 9

### Deferred pipelines

All the pipelines I showed so far were essentially "single shot". They
began with a fixed array and applied various operations to it and then
created a result. But sometimes you would like to specify a pipeline
and then apply it to multiple different arrays. To support this, you
can create a "detached" pipeline. For example, the following code
would create a pipeline for incrementing each element by one:

    var pipeline = parallel.detached().map(i => i + 1);

Before you actually execute a detached pipeline, you must attach it to
a specific input. The result is a new, attached pipeline which can
then be converted to an array or reduced. Of course, you can attach
the pipeline many times:

    // yields [2, 3, 4]
    pipeline.attach([1, 2, 3]).toArray();
    
    // yields 12
    pipeline.attach([2, 3, 4]).reduce((a,b) => a+b).reduce();

### Put it all together

Here is relatively complete, if informal, description of the pipeline
methods I've thought about thus far.

#### Creating pipelines

The fundamental ways to create a pipeline are the methods `range()`,
`shape()`, and `detached()`, all available from a `parallel` module.
In addition, `Array.prototype` and the prototype for typed object
arrays both feature a `parallel()` method that creates a pipeline
as we showed before.

#### Transforming pipelines

Each of the methods described here are available on all pipelines.
Each produces a new pipeline.

The most common methods for transforming a pipeline will probably be
`map` and `mapTo`:

1. `pipeline.map(func)` -- invokes `func` on each element, preserving
   the same output type as `pipeline`.
1. `pipeline.mapTo(type, [func])` -- invokes `func` on each element,
   converting the result to have the type `type`. In fact, `func` is
   optional if you just want to convert between types.

`map` and `mapTo` are somewhat special in that they work equally well
over any number of dimensions. The rest of the available methods
always operate only over the outermost dimension of the pipeline.
They also create a single dimensional output. Because this is a blog
post and not a spec, I won't bother writing out the descriptions in
detail:
   
1. `pipeline.flatMap(func)` -- like map, but flatten one layer of arrays
1. `pipeline.filter(func)` -- drop elements for which `func` returns false
1. `pipeline.scan(func)` -- prefix sum
1. `pipeline.scatter(...)` -- move elements from one index to another

Finally, there is the `attach()` method, which is only applicable to
detached pipelines. It produces a new pipeline that is attached to a
specific input. If the pipeline is already attached, an exception results.
   
#### Executing pipelines

There are two fundamental ways to execute a pipeline:

1. `pipeline.toArray()` -- executes the pipeline and collects
   the result into a new typed object array. The dimensions and type
   of this array are determined by the `pipeline`.
1. `pipeline.reduce(func, [initial])` -- executes the pipeline and reduces
   the results using `func`, possibly with an initial value. Returns
   the result of this reduction.

## Open questions

**Should pipelines provide the index to the callback?** I decided to
strive for simplicity and just say that pipeline transformers like
`map` always pass a *single value* to their callback. I imagine we
could add an `enumerate` transformer if indices are desired. But then
again, this pollutes the value being produced with indices that just
have to be stripped away. So maybe it's better to just pass the index
as a second argment that the user can use or ignore as they choose. I
imagine that the index will be an integer for a 1D pipeline, and an
array for a multidimensional pipeline.

**Should pipelines be iterable?** It has been suggested that pipelines
be iterable. I guess that this would be equivalent to collecting the
pipeline into an array and then iterating over that. (Since, unless
you are doing a map operation, the only real purpose for iteration is
to produce side-effects.) This would be say enough to add, I just was
worried that it might be misleading to see code like this:

    for (var e of array.parallel().map(...)) {
        /* Maybe it looks like this for loop body
           executes in parallel? (Which it doesn't.) */
    }

## Updates

- Renamed `collect()` to `toArray()`, which seems clearer.

[branch]: https://github.com/nikomatsakis/gecko-dev/tree/Pipeline-b
[ps]: http://en.wikipedia.org/wiki/Prefix_sum
