Although the general shape of the PJS API is agreed upon -- at least
amongst ourselves -- there are still some lingering areas of
disagreement. The largest of these is what the API for creating a
fresh array should look like.

<!-- more -->

### Background

In this section I provide a bit of background about the original
`ParallelArray` API as well as how typed objects work. If you are
familiar with this work, you can skip this section.

For example, in the original `ParallelArray` API, you could construct
a new `ParallelArray` from nothing by writing something like:

```js
new ParallelArray([w, h], (x, y) => 22)
```

This constructor call would create a 2-D parallel array with
dimensions `w x h`. It would iterate in parallel over those dimensions
and initialize each element of the parallel array with the result of
invoking the function with the appropriate coordinates (in this case,
always `22`).

The newer approach is based on typed objects. This means that rather
than creating a new parallel array, users will define a type object
specifying the type of the array to be created.  For example,





In the new API that is based on typed objects, we cannot use a
*constructor* call as we used to do.  This is because the
`ParallelArray` type no longer exists. Instead, users simply define
their own array types as they choose. For example, I might default
a type like:

    var ImageType = new ArrayType(new ArrayType(uint32, h), w);
    
This defines a type for two dimensional arrays of integers. This is
similar to the `ParallelArray` that would have been produced by the
previous example, with some important differences:

- The types of the elements in parallel arrays was not specified.
  This implies that without a lot of advanced engine optimization, the
  parallel array *storage* could not be specialized to a `uint32`,
  which means that ultimately space was wasted.
- `ImageType` instances are mutable, whereas Parallel Array instances
  were immutable.

This last point regarding immutability is important. To construct
a new image type instance, one would typically write code
like:

```js
var image = new ImageType();
for (var x = 0; x < w; x++)
    for (var y = 0; y < h; y++)
        image[x][y] = 22;
```
            
Here the constructor takes no arguments and thus you are returned a
zeroed array of the desired size. You can then iterate over the
elements and initialize them yourself. This is possible because the
array is mutable.

The other (existing) way to construct an image is to write `new
ImageType(foo)`, which creates a new image and initializes it by
copying values from a "model instance" `foo`. Foo must be something
"array-like" that can be adapted to `ImageType`. However, if you don't
already have a `foo` object to copy from -- as is often the case --
then this is not a particularly efficient pattern, since you wind up
creating a dummy object.

### Value objects and array initialization

One of the anticipated directions for typed objects is something
called *value objects*. A *value object* is -- basically -- an
*immutable object*, meaning one whose values cannot be changed after
it is created.

The precise API is not known, but the basic idea is that you
define separate value types. Let's imagine 

define a type, you can also specify if it is a *value type* or
not. For example, imagine that in addition to `ArrayType` there were
another constructor `ValueArrayType` (this is probably not what the
actual API will be, but anyway). Then one might convert our
`ImageType` into a value type (and hence make all our images
immutable) like so:

```js
var ValueImageType = new ValueArrayType(new ValueArrayType(uint8, h), w)
```

Immutability has a number of advantages. One of the big ones is that
it gives the compiler more freedom to optimize. If we know that a
value is immutable, we don't have to worry about stores modifying it,
so we can eliminate more loads and memory accesses. Because value
objects also lack *identity* (meaning: two value objects are `===` iff
they have the same value, where with mutable data two arrays might
have the same values but still be distinct *objects*), we can also
optimize storage and avoid allocations. This is less likely or
important for big values like an image, but it can be *very* useful
for smaller values like an individual struct.

In any case, there is a complication. How do we initialize an instance
of `ValueImageType`? The "for loop" style of initialization isn't
really suitable, since that requires that the object which was just
created be mutable. Of course we still have the option of initializing
based on a model instance, but as I wrote before, that is somewhat
inefficient. It also begs the question of "how do you create the model
instance in the first place?"

The usual answer to this problem is to create an initialization method
very similar to the one sported by parallel arrays. We have been
calling this method `build`. The basic question that we are trying to
answer, then, is "what does `build` look like"?

### Option 1: Type object method

There are basically two options on the table. The first is to
define a method `build` on the array type objects themselves.
This means that to create a new image one would write:

```js
var image = ImageType.build(2, (x, y) => 22)
```

Here the argument `2` might be unexpected. It indicates the *depth of
the iteration space*. Recall that `ImageType` was defined as:

    var ImageType = new ArrayType(new ArrayType(uint32, h), w);

There are actually two ways to interpret this type. One is as a
two-dimensional array of ints, but the other is as a 1-D array of
arrays of ints. Both interpretations have the same layout in memory,
so we don't consider them to be distinct types; however, when you call
`build`, it is useful to be able to distinguish the two cases.

In patricular, in the example I gave, the value of each cell in the
2-d array is independent. Therefore, we supply a depth parameter of 2,
indicating that the `build` method should iterate over the outermost
2 dimensions.

However, if we wanted, we could also supply a depth parameter of 1,
which indicate that `build` should iterate over the outermost
dimension only. In that case, the callback might look like:

```js
var image = ImageType.build(1, (x, out) => {
    var sharedState = new SharedState();
    for (var y = 0; y < h; y++)
        out[y] = sharedState.nextValue();
})
```

Note that here I used the optional `out` parameter to initialize the
result rather than returning a value. This is because the result type
is an array of ints, rather than a single int, and so returning a
value would result in inefficient copying. The out parameter however
allows us to update the array directly in place, as discussed in my
[previous blog post][bp].

One aspect of this API is that you must define the type that you plan
to construct. So, for example, if you will be creating images of many
different, dynamically computed sizes, you might wind up writing
a helper function in place of a single type object. For example,
we could replace `ImageType` with a function like `ImageTypeWithDims`:

```js
function ImageTypeWithDims(w, h) {
    return new ArrayType(new ArrayType(uint8, h), w)
}
```

and then instead of writing `ImageType.build` you would write

```js
ImageTypeWithDims(w, h).build(depth, ...)
```

### Option 2: Method on `ArrayType`

Another option is to add a method to `ArrayType`. The proposal is that
one would write something like:

```js
var image = ArrayType.build([w, h], uint8, (x, y) => 22)
```

The effect of this call is two-fold:

1. Construct a new array type of dimensions `w x h` of `uint8` values.
2. Construct an instance of this type and initialize it by calling
   the helper function as before

In the first approach, these two steps were distinct. You created the
type on your own, and build just initializd the instance.

One nice benefit of this is that there is no need for the `depth`
parameter. That is instead "rolled in" to the existing arguments.
So to build a column at a time, one would write:

```js
var image = ArrayType.build([w], new ArrayType(uint8, h), (x, out) => {
    var sharedState = new SharedState();
    for (var y = 0; y < h; y++)
        out[y] = sharedState.nextValue();
})
```

Here the first argument is now just `[w]` but the second argument is
`new ArrayType(uint8, h)`. When these are combined, you get the same
type as before, but in this second case we only iterate over one
dimension.

### Interaction with value types

One interesting aspect of the second approach, and indeed the main
thought which motivated writing this entire blog post, is that the
`ArrayType` method approach cannot create value types (or else, it
cannot create mutable arrays). 

### Some more advanced ideas

#### Parallel in-place initialization

#### Build many


[bp]: /blog/2013/07/19/integrating-binary-data-and-type-inference-in-spidermonkey/
