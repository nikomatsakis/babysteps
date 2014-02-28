---
layout: post
title: "Structural arrays in Typed Objects"
date: 2013-12-12 13:07
comments: true
categories: [PJs]
---

[Dave Herman][dherman] and I were tossing around ideas the other day for a
revision of the typed object specification in which we remove nominal
array types. The goal is to address some of the awkwardness that we
have encountered in designing the PJS API due to nominal array types.
I thought I'd try writing it out. This is to some extent a thought
experiment.

<!-- more -->

### Description by example

I've had a hard time trying to identify the best way to present the
idea, because it is at once so similar and so unlike what we have
today. So I think I'll begin by working through examples and then
try to define a more abstract version.

Let's begin by defining a new struct type to represent pixels:

    var Pixel = new StructType({r: uint8, g: uint8,
                                b: uint8, a: uint8});

Today, if we wanted an array of pixels, we'd have to create a new type
to represent that array (`new ArrayType(Pixel)`). Under the new
system, each type would instead come "pre-equipped" with a
corresponding array type, which can be used to create both single and
multidimensional arrays. This type is accessible under the property
`Array`. For example, here I create three objects:

    var pixel = new Pixel();
    var row   = new Pixel.Array(1024);
    var image = new Pixel.Array([1024, 768]);

The first object, `pixel`, represents just a single pixel. Its type is
simply `Pixel`. The second object, `row`, repesents a single
dimensional array of 1024 pixels. I denote this using the following
notation `[Pixel : 1024]`. The third object, `image`, represents a
two-dimensional array of 1024x768 pixels, which I denote as
`[Pixel : 1024 x 768]`.

No matter what dimensions they have, all arrays are associated
with a single type object. In other words:

    objectType(row) === objectType(image) === Pixel.Array
    
This implies that they share the same prototype as well:

    row.__proto__ === image.__proto__ === Pixel.Array.prototype

Whenever you have an instance of an array, such as `row` or `image`,
you can access the elements of the array as you would expect:

    var a = row[3];           // a has type Pixel
    var b = image[1022];      // b has type [Pixel : 768]
    var c = b[765];           // c has type Pixel
    var d = image[1022][765]; // d has type Pixel
    
Note that each time you index into an array instance, you remove the
"leftmost" (or "outermost") dimension, until you are left with the
core type.

As today, it is always possible to "redimension" an array, so long
as the total number of elements are preserved:

    // flat has type [Pixel : 786432]:
    var flat = image.redim(1024*768);

    // three has type [Pixel : 2 x 512 x 768]:
    var three = image.redim([2,512,768]);
    
The variables `flat`, `three`, and `image` all represent pointers into
the same underlying data buffer, but with different underlying
dimensions.

Sometimes it is useful to embed an array into a struct. For example,
imagine a type `Gradient` that embeds two pixel colors:

    var Gradient = new StructType({from: Pixel, to: Pixel})
    
Rather than having two fields, it might be convenient to express this
type using an array of length 2 instead. In the old system, we would
have used a fixed-length array type for this purpose. In the new system,
we invoke the method `dim`, which produces a *dimensioned type*:

    var Gradient = new StructType({colors: Pixel.dim(2)})
    
Dimensioned types are very similar to the older fixed-length array
types, except that they are not themselves types. They can only be
used as the specification for a field type. When a dimensioned field is
reference, the result is an instance of the corresponding array:

    var gradient = new Gradient(); // gradient has type Gradient
    var colors = gradient.colors;  // colors has type [Pixel : 2]
    var from = colors[0];          // from has type Pixel
    
### More abstract description

The type `T` of an typed object can be defined using the following grammar:

    T = S | [S : D]
    S = scalar | C
    D = N | D x N

Here `S` is what I call a *single* type. It can either be a scalar
type -- like `int32`, `float64`, etc. -- or a struct, denoted `C` (to
represent the fact that struct types are defined nominally).

**UPDATE:** This section has confused a few people. I meant for `T` to
represent the type of an instance, and hence it includes the specific
dimensions. There would only be on type object for all arrays, so if
we defined a `U` to represent the set of type objects, it would be `S
| [S]`. But when you instantiate an array `[S]` you give it a concrete
dimension. I realize that this is a bit of a confused notion of type,
where I am intermingling the "static" state ("this is an array type")
and the dynamic portion ("the precise dimensions"). Of course, in this
language we're defining types dynamically, so the analogy is imprecise
anyway.

For each struct `C`, there is a struct type definition `R` is defined
as follows:

    R = struct C { (f: T) ... }
    
Here `C` is the name of the struct, `f` is a field name, and `T` is
the (possibly dimensioned) type of the field.

This description is kind of formal-ish, and it may not be obvious how
to map it to the examples I gave above. Each time a new `StructType`
instance is created, that instance corresponds to a distinct struct
name `C`. When a new array instance like `image` is created, its type
corresponds to `[Pixel : 1024 x 768]`. This grammar reflects the fact
that struct types are *nominal*, meaning that the type is tied to a
specific struct type object, but array types are structural -- given
the element type and dimensions, we can construct an array type.

### Why make this change?

As time goes by we've encountered more and more scenarios where the
nominal nature of array types is awkward. The problem is that it seems
very natural to be able to create an array type given the type of the
elements and some dimensions. But in today's system, because those
array types are distinct objects, creating a new array type is both
heavyweight and has significance, since the array type has a new
prototype.

There are a number of examples from the PJS APIs. In fact, we already
did an [extensive redesign][nominal] to accommodate nominal array
types already. But let me give you instead an example of some code
that is hard to write in today's system, and which becomes much easier
in the system I described above.

Intel has been developing some examples that employ PJS APIs to do
[transforms on images taken from the camera][intel]. Those APIs define
a number of filters that are applied (or not applied) as the user
selects. Each filter is just a function that is supplied with some
information about the incoming image as well as the window size and so
on. For example, [the filter for detecting faces][func] looks like
this:

    function face_detect_parallel(frame, len, w, h, ctx) {
        var skin = isskin_parallel(frame, len, w, h);
        var row_sums = uint32.array(h).buildPar(i => ...);
        var col_sums = uint32.array(w).buildPar(i => ...);
        ...
    }
    
I won't go into the details of how the filter works. For our purposes,
it suffices to say that `isskin_parallel` computes a (two-dimensional)
array `skin` that contains, for each pixel, an indicator of whether
the pixel represents "skin" or not. The `row_sums` computation then
iterates over each row in the image and computes a sum of how many
pixels in that row contain skin. `col_sums` is similar except that the
value is computed for each column in the image.

Let's take a closer look at the `row_sums` computation:

    var row_sums = uint32.array(h).buildPar(i => ...);
    //             ^~~~~~~~~~~~~~~

What I am highlighting here is that this computation begins by
defining a new array type of length `h`. This is natural because the
height of the image can (potentially) change as the user resizes the
window. This means that we are defining *new array types for every
frame*.

This is bad for a number of reasons: 

1. It's inefficient. Creating an array type involves some overhead in the
   engine, and if nothing else it means creating two or three objects.
2. If we wanted to install methods on arrays or something like that,
   creating new array types all the time is problematic, since each will
   have a distinct prototype.
   
This pattern seems to come up a lot. Basically, it's useful to be able
to create arrays when you know the element type and the dimensions,
and right now that means creating new array types.

### What do we lose?

Nominal array types can be useful. They allow people to create local
types and attach methods. For example, if some library defines a struct
type `Pixel`, then (today) some other library could define:

    var MyPixelArray = new ArrayType(Pixel);
    MyPixelArray.prototype.myMethod = function(...) { ... }

I'm not too worried about this though. You can create wrapper types at
various levels. Most languages I can think of -- virtually all -- use
a structural approach rather than nominal for arrays (although the
situations are not directly analogous). I think there is a reason for
that.

### Is there a compromise?

I suppose we could allow array types to be explicitly instantiated but
keep the other aspects of this approach. This permits users to define
methods and so on. However, it also means that it is not enough to
have the element type and dimension to construct an array instance,
one must instead pass in the array type and dimension.

[strawman]: http://wiki.ecmascript.org/doku.php?id=harmony:typed_objects
[nominal]: /blog/2013/09/03/type-specifications-in-parallel-js/
[intel]: https://github.com/IntelLabs/ParallelJavaScript
[func]: https://github.com/IntelLabs/ParallelJavaScript/blob/a06e1a9daeadad345b0321313edee556e5f6a774/tutorial/src/complete/filters.js#L210
[dherman]: https://twitter.com/littlecalculist
