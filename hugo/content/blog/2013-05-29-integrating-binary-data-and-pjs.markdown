---
categories:
- PJs
- JS
comments: true
date: "2013-05-29T00:00:00Z"
slug: integrating-binary-data-and-pjs
title: Integrating binary data and PJs
---

We've been making a lot of *conceptual* progress with the PJS API that
has not been written down anywhere, so I want to cover some of that
work. This post focuses on the integration of parallel methods with
the binary data API. It shows how the new API approach allows users to
avoid allocation for higher efficiency.

<!--more-->

### Methods, not types

We are moving away from a `ParallelArray` type and into methods that
will be offered on existing array types. Current plan is to name them
things like `pmap` (vs normal sequential `map`). The defined semantics
are similar to the sequential version except that the order of
iterations is undefined, because iterations may occur in parallel (I
described [the subset of JS][subset] that we expect to parallelize in
a previous post).

In place of the parallel array constructor, we will add `build` and
`pbuild` methods to `Array.prototype`, permitting you to construct
an array from nothing. Therefore, instead of writing code that pushes
onto an array like so:

```js
    var array = [];
    for (var i = 0; i < c; i++)
        array.push(f(i));
```        
        
You could write that same exact loop using the sequential `build`
method:

```js
    var array = Array.build(c, i => f(i));
```

Or, if you know that `f` is side-effect free, you might try a parallel
build instead:

```js
    var array = Array.pbuild(c, i => f(i));
```

### Addressing inefficient memory usage via the binary data specification

One of the bottlenecks which we have found with the existing parallel
array code is that building on JavaScript arrays can be inefficient
when the data set is very large.

To see what I mean, consider a program that wishes to represent an
image of RGBA pixels. A common way to represent each pixel is to use a
4-element array, where each element in the array is a uint8 (meaning a
number from 0 to 255). Using `ParallelArray` today, you might create
such a matrix with code like the following:

```js
    function computePixel(x, y) {
        ...
        return [ r, g, b, a ];
    }
    var myImage = new ParallelArray([W, H], (x, y) => computePixel(x, y));
```

As you can probably imagine, representing an image this way is rather
inefficient: you will wind up with one array object per pixel. Each of
these array objects is only storing 4 bytes of data, but it will
consume quite a bit more space and create a large amount of GC
overhead to manage.

To address this problem, we are building on the upcoming
[binary data specification][bd]. For those of you not familiar with
it, the binary data specification is a generalization of typed arrays
that allows you to build-up JavaScript type descriptors that describe
C-like data structures.

Using the binary data specification, I could create a pixel type descriptor
as follows:

```js
    var PixelType = new StructType({r: uint8,
                                    g: uint8,
                                    b: uint8,
                                    a: uint8});
```

Now I can instantiate new pixels as follows:

```js
    var p1 = new PixelType({r: 22, g: 44, b: 66, a: 88});
    var p2 = PixelType({r: 22, g: 44, b: 66, a: 88});
```

Here I have created two points, one with `new` (`p1`) and one without
(`p2`).  Using `PixelType` the `new` keyword results in a mutable
pixel whereas using `PixelType` without the `new` keyword results in
an immutable pixel. You can use the `p1` and `p2` values as follows:

```js
    // Read the red, green, and blue components:
    var average = p2.r + p2.g + p2.b / 3;
    
    // Double the red component:
    p1.r *= 2;
    p2.r *= 2; // Error, modifying `p2` is illegal
```

To represent a two-dimensional image of size `W x H`, I can use
`ArrayType` to build up a type descriptor representing an array of
arrays of pixels:

```js
    var ImageType = ArrayType(ArrayType(PixelType, H), W);
```

### Parallel methods on binary data arrays

We plan to add the same set of parallel methods to binary data arrays
that are currently offered on standard JS arrays, which means
that I could replace the constructor call you saw before:

```js
    function computePixel(x, y) {
        ...
        return [ r, g, b, a ];
    }
    var myImage = new ParallelArray([W, H], (x, y) => computePixel(x, y));
```
    
with a call to the `pbuild` method:

```js
    function computePixel(x, y) {
        ...
        return PixelType({ r:..., g:..., b:..., a:... });
    }
    var myImage = ImageType.pbuild((x, y) => computePixel(x, y));
```

Although these two function calls look quite similar, they are in fact
very different. In the first case, the JavaScript engine didn't know
anything about what kind of data was going to be in the array array,
and thus it had to use a very conservative data representation.

In the second case, the `ImageType` tells us precisely what kind of
data will be in the array: the array will be a `W x H` array of
`PixelType` values. This means that at runtime we can allocate the
entire image all at once, and then simply update the pixels in place.
The end result will be much more efficient.

### Avoiding memory allocation with out pointers

In the previous example, I showed how the binary data types could
improve efficiency by allowing us to allocate an entire image worth of
pixels at once. However, if you look carefully at the code, you will
see that in fact there is still allocation occurring for every pixel:

```js
    function computePixel(x, y) {
        ...
        return PixelType({ r:..., g:..., b:..., a:... });
    }
    var myImage = ImageType.pbuild((x, y) => computePixel(x, y));
```

In particular, the `computePixel()` function creates a new `PixelType`
instance and returns it. The runtime will copy the pixel data out of
this object and store it into its final home. The garbage collector is
then free to collect this intermediate `PixelType` instance as it
likes. In fact, if you look closely, you'll see that there would be
two intermediate objects, since `PixelType()` takes an object literal
`{r:...,g:...,...}` as its argument. Most likely the compiler would
optimize away the object literal, but the `PixelType` instantiation
would remain.

The situation thus far has clearly improved from the original, since
these objects are short-lived (this reminds me, there is another post
to be written on the interaction between PJS and generational garbage
collection), but there is still room for improvement. We don't really
need temporary objects at all.

The way we plan to address the problem of temporary object creation is
to add an optional *out pointer* parameter to the binary data APIs.
The idea is that your callback gets a parameter that is basically a
pointer into the final array which is being created. Rather than
returning a value, then, you can choose to just write directly into
this array, avoiding any intermediaries. Using the out pointer,
we could rewrite the code above to look like:

```js
    function computePixel(x, y, out) {
        ...
        out.r = ...;
        out.g = ...;
        out.b = ...;
        out.a = ...;
    }
    var myImage = ImageType.pbuild((x, y, out) => computePixel(x, y, out));
```

Now there are no allocations at all except for the final array. These
out pointers will be the same sort of pointers that the binary data
API already provides. The data will be initialized with zeros, and you
can use the out pointer to update it in place, but not to mutate any
of the elements in the array besides the one you are intended to write
to.

*Update:* I realized I forgot to write about safety concerns. You
might be worried that the presence of an out pointer creates a danger
for race conditions or other similar problems, but this is not the
case. Of course it is possible for an out pointer to be stored in the
result or otherwise escape, but such a pointer cannot be communicated
betweeen the parallel threads without mutating shared state, and thus
falling back to sequential execution.

[subset]: {{ site.baseurl }}/blog/2013/04/30/parallelizable-javascript-subset/
[bd]: http://wiki.ecmascript.org/doku.php?id=harmony:binary_data
