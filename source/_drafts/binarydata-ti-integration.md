Since the new version of PJS is going to be based on binary data, we
are going to need to have a well-optimized binary data implementation.
Nikhil Marathe has prepared an [initial implementation][578700], but
it is limited to the interpreter. I am looking now at how to integrate
binary data into the JIT. The goal is to have accesses get compiled to
very efficient generated code. In this blog post, I specifically want
to cover the plan for integrating our type inference with binary data.

### Descriptors

In binary data, users create type descriptors as follows:

    var PointType = new StructType({x: Float64, y: Float64});
    var LineType = new StructType{{start: Point, end: Point});
    
It is also possible to create types that include non-scalar data.
For example, here is a struct that might be used for a binary tree:

    var TreeType = new StructType({value: Any,
                                   left: Object,
                                   right: Object});

Once you have a type descriptor, you can create instances of that
type descriptor using the `new` operator:

    var origin = new PointType({x: 0, y: 0});
    var unit = new PointType({x: 1, y: 1});
    var line = new LineType({start: origin, end: unit});

You can access the properties of these instances just as you would
expect:

    var length = Math.sqrt(Math.pow(line.end.x - line.start.x, 2) +
                           Math.pow(line.end.y - line.start.y, 2));
                             
The aim of this work is to optimize an expression like `line.end.x` so
that it can be compiled into a simple load of the relevant data.



                                   

[578700]: https://bugzilla.mozilla.org/show_bug.cgi?id=578700&sourceid=Mozilla-search
