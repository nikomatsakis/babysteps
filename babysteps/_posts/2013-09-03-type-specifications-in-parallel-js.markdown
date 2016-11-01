---
layout: post
title: "Type specifications in Parallel JS"
date: 2013-09-03 13:35
comments: true
categories: [PJs, JS]
---

Since I last wrote, we've made great progress with the work on the
Parallel JS and Typed Objects (nee Binary Data) implementation.  In
particular, as of this morning, preliminary support for typed objects
has landed in Mozilla Nightly, although what's currently checked in is
not fully conformant with the current version of the standard (for
this reason, support is limited to Nightly and not available in Aurora
or Beta builds).

Meanwhile, we've been fixing small bugs in the existing Parallel JS
support code and also working on a prototype of the new API. There is
still some amount of work left to do with typed objects before we can
eliminate the old `ParallelArray` code entirely: in particular, we
have to implement handles and make further progress on the JIT
integration.

We've also been working hard with the Rivertrail team at Intel on
figuring out what the final API will look like. My [prior post][pp]
sketched out the basic design we've been working with. But the devil's
in the details, so the latest work has been trying to figure out
precisely what the methods look like and so forth.  One of the recent
shifts that looks like it will be necessary is to change how the
return types from PJs methods are specified. This is due to a
non-obvious interaction with typed object prototypes that I want to
describe in this post.

<!-- more -->

### Type objects and prototypes

To begin, let me briefly explain how the typed objects API works with
prototypes. Whenever you create a new type object -- that is, a
descriptor for a type -- it has an associated prototype. This can be
used to add methods to the instances of the type object in the usual
way:

```js
var ColorType1 = new StructType({r: uint8, g: uint8, b: uint8});

ColorType1.prototype.average = function() {
    return (this.r + this.g + this.b) / 3;
}

var white1 = new ColorType1({r: 255, g: 255, b: 255});
var avg = white1.average(); // returns 255
```

If I go off and define an equivalent struct type somewhere else, it
will nonetheless have a distinct prototype and therefore a distinct
set of methods:

```js
var ColorType2 = new StructType({r: uint8, g: uint8, b: uint8});
var white2 = new ColorType2({r: 255, g: 255, b: 255});
var avg = white2.average(); // ERROR
```

### Implications for the PJs API

The fact that otherwise equivalent type objects have distinct
prototypes has concrete implications for our PJs API design.  We had
originally been contemplating an API in which users provided the
component types and we would synthesize them into a final type. For
example, if you have an array of pixels and you want to map it into an
array of doubles, you might have written code like:

```js
var ColorType = new StructType({r: uint8, g: uint8, b: uint8});
var ImageType = new ArrayType(ColorType, 1024*768);

var myImage = new ImageType();
var averages = myImage.mapPar(c => (c.r + c.g + c.b) / 3, uint8);
```
    
The interesting line is the final one, which maps from an array of
pixels into an array of `uint8`. The second argument to map here
specified the *return type* of the closure (this argument is optional;
if you omit it, we would use the type specification `any`, meaning any
kind of value can be returned).

In this style of API, the type of the value returned from map would
then by (internally) created as `new ArrayType(uint8, 1024*768)`. This
is fine if equivalent types all behave in exactly the same way. But
what if the user wanted to add methods to the prototype of the
returned value? Since `mapPar` would presumably be creating a fresh type
object, each result would also have a fresh prototype, which would be
both expensive (many objects being allocated) and not useful (no way
to add methods).

So instead we should take an approach where we always specify the
*final return type* of the function. That means that the code above
would be changed slightly to read like so:

```js
var ColorType = new StructType({r: uint8, g: uint8, b: uint8});
var ImageType = new ArrayType(ColorType, 1024*768);
var AverageType = new ArrayType(uint8, 1024*768);

var myImage = new ImageType();
var averages = myImage.mapPar(c => (c.r + c.g + c.b) / 3, AverageType);
```
    
You can see that we introduced a new type (`AverageType`) which is an
array of the same length as `ImageType` but with a different element
type (`uint8` vs `ColorType`). Now we can use this type as the type
annotation for the call to `mapPar`. Furthermore, users can add their
own methods to `AverageType.prototype` as they choose.

[pp]: {{ site.baseurl }}/blog/2013/05/29/integrating-binary-data-and-pjs/
