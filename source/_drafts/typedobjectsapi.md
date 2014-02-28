At the recent TC39 meeting, Dmitry Lomov and I presented our latest
version of the [Typed Objects API][obj]. For those unfamiliar, the
idea of typed objects is to allow JavaScript users to define objects
with precise layouts and data types. Typed objects can also be viewed
as a generalization of the existing typed arrays: where typed arrays
allow you to define arrays of scalar types, typed objects allow you to
define arrays of structures and so forth. But typed objects are useful
for more than arrays: it is quite reasonable to define types for a
single object.

### Defining types

The first step in using the typed objects API is to define types. The
primary way to define a new type is using the `StructType` constructor:

    var PointType = new StructType({x: uint32, y: uint32});

This would create a new type descriptor object called `PointType`.
`PointType` describes a struct with two fields, `x` and `y`, both of
type `uint32`.

We can instantiate `PointType` to yield a *typed object*:

    var point = PointType();
    
Invoking a type descriptor as an object 
