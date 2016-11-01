---
layout: post
title: "Optimizing SIMD"
date: 2013-11-21 21:56
comments: true
categories: [PJs, JS]
---

There is currently some [ongoing effort][904913] to implement the
proposed [JavaScript SIMD API][simd] in Firefox. The basic idea of the
API is to introduce explicit vector value types called `float32x4` and
`int32x4`. These types fit into the typed objects hierarchy, so you
can create arrays of them, embed them in structs, and so forth.

The semantics of these vectors types is designed to make it possible
for JIT engines to detect and optimize their use. One crucial bit is
that they are *values* and hence do not have identity. Basically
`float32x4` values work like numbers and strings do today -- they are
equal if they have the same value. This is quite different from
objects, which may be unequal if their properties are the same (e.g.,
`{} !== {}`).

The purpose of this post is to outline one possible strategy for
optimizing the use of SIMD types in IonMonkey. The initial set of
optimizations don't require any new analyses, though we can add an
optional simple analysis in order to optimize more programs. This
analysis is actually fairly general and can be applied to other kinds
of typed objects.

<!-- more -->

### Example

This is the example function that I intend to optimize. `addArrays()`
takes as input two arrays of float32x4 values and adds them pairwise,
returning a new array.

    function addArrays(a, b) { // a and b are instances of ArrayType(float32x4)
        var c = new Float32x4Array(a.length);
        for (var i = 0; i < a.length; i++) {
            c[i] = SIMD.float32x4.add(a[i], b[i]);
        }
        return c;
    } 

What we would like to do is emit optimized assembly that uses the SIMD
operations offered by our CPU.

### Strategy

The basic strategy is similar to the [existing optimizations][opt]
that we use for all typed objects. In that case, the trick is that we
generate the full IR at first, including all the boxing
operations. However, whenever possible we don't make use of the boxed
values but rather pull out the inputs to the boxing and use those
directly. Similar logic is currently encoded in
[loadTypedObjectElements()][dxr] for the purpose of optimizing out
derived temporaries.

#### Line by line

Let me explain better by looking at the example. Consider the body of
the loop that adds the two vectors:

    c[i] = SIMD.float32x4.add(a[i], b[i]);

First let me introduce temporaries for ease of discussion:

    var tmp0 = a[i];
    var tmp1 = b[i];
    var tmp2 = SIMD.float32x4.add(tmp0, tmp1);
    c[i] = tmp2;

When processing the first two temporaries we generate MIR (mid-level
IR) like so:

    var elem0 = MTypedObjectElements(a);  // (1)
    var i0 = MBoundsCheck(i, ...);        // (2)
    var arg0 = MLoadVector(elem0, i0);    // (3)
    var tmp0 = MVectorTypedObject(arg0);  // (4)

    var elem1 = MElements(b);
    var i1 = MBoundsCheck(i, ...);
    var arg1 = MLoadVector(elem1, i1);
    var tmp1 = MVectorTypedObject(arg1);

Instruction (1) loads the "elements" of a typed object, which is
basically just a pointer at the raw binary data of the `a` object.
Since `a` is an array of `float32x4` values, `elem0` will be just an
array of floats. Instruction (2) checks that the next line checks that
`i` is within bounds of the array. In instruction (3), the load of
`arg0` extracts the vector data from `elem0` at the given offset.
This will hopefully be translated to the vector load instructions
offered by the CPU. Finally, in instruction (4), we package up the
loaded vectors into a new typed object `tmp0` -- this is a boxing
operation and it's fairly expensive, it allocates a new object and
copies the vector data into it. The same set of operations repeats
again for `tmp1`.

Where things get interesting is what we generate when processing the
call to `SIMD.float32x4.add(tmp0, tmp1)`. Adding two vectors requires
unboxed data; we observe that `tmp0` and `tmp1` are boxed vectors and
so rather than loading the data out of them with more `MLoadVector`
instructions, we just directly extract the source values `arg0` and
`arg1` that were used to create `tmp0` and `tmp1`:

    var sum2 = MAddVector(arg0, arg1);
    var tmp2 = MVectorTypedObject(sum2);

Finally we process the store `c[i] = tmp2`, generating the following
instructions:

    var elem2 = MElements(c);
    var i2 = MBoundsCheck(i, ...);
    MStoreVector(elem2, i2, sum2);

Here again we do not generate instructions to load data out of `tmp2`
but rather just use its input `sum2` directly.

#### Putting it all together

This is the full IR that we generate initially:

    var elem0 = MElements(a);
    var i0 = MBoundsCheck(i, ...);
    var arg0 = MLoadVector(elem0, i0 * sizeof(float32x4));
    var tmp0 = MVectorTypedObject(arg0);
    
    var elem1 = MElements(b);
    var i1 = MBoundsCheck(i, ...);
    var arg1 = MLoadVector(elem1, i1 * sizeof(float32x4));
    var tmp1 = MVectorTypedObject(arg1);
     
    var sum2 = MAddVector(tmp0, tmp1);
    var tmp2 = MVectorTypedObject(sum2);
    
    var elem2 = MElements(c);
    var i2 = MBoundsCheck(i, ...);
    MStoreVector(elem2, i2 * sizeof(float32x4), sum2);

Note that in this code `tmp0`, `tmp1`, and `tmp2` are all dead (though
we had to generate them as part of the `IonBuilder`
process). Furthermore, we know that the boxing operation
`MVectorTypedObject` is side-effect free and thus safe to move or
eliminate as needed. When dead code runs, therefore, it will be
simplified to:

    var elem0 = MElements(a);
    var elem1 = MElements(b);
    var arg0 = MLoadVector(elem0, i * sizeof(float32x4));
    var arg1 = MLoadVector(elem1, i * sizeof(float32x4));
    var sum2 = MAddVector(arg0, arg1);
    var elem2 = MElements(c);
    MStoreVector(elem2, i * sizeof(float32x4), sum2);

Loop-invariant code motion, in turn, will hoist out the `MElements`
calls (and possibly bounds checks etc but I'll ignore that for
now). This means that after optimization the entire routine will look
something like:

    var elem0 = MElements(a);
    var elem1 = MElements(b);
    var elem2 = MElements(c);
    for (...) {
        var i0 = MBoundsCheck(i, ...);
        var i1 = MBoundsCheck(i, ...);
        var i2 = MBoundsCheck(i, ...);
        var arg0 = MLoadVector(elem0, i * sizeof(float32x4));
        var arg1 = MLoadVector(elem1, i * sizeof(float32x4));
        var sum0 = MAddVector(arg0, arg1);
        MStoreVector(elem2, i * sizeof(float32x4), sum0);
    }

### Limitations and improvements

There are some limitations to this strategy. For example, it won't
work with conditional code. So if we modified the body of the loop to
include a conditional expression, we'd be out of luck:

     c[i] = SIMD.float32x4.add((cond ? a[i] : b[i]), b[i]);

Here the first input would be a "phi" node, and thus we could not
definitely trace it to a `MVectorTypedObject` instruction. This means
that we would generate unboxing instructions that read from the
temporary, and thus introduce an extra MLoadVector as well as a live
temporary. We can easily optimize this in a second pass that walks
over the IR and detects phi nodes where all inputs are boxed
temporaries and the output is boxed. We can then convert the phi node

Another limitation is that the boxed temporaries will still appear in
the "resumepoint" instructions that encode the state of the stack for
the purposes of bailouts. For simple loops like the one I showed,
those might get optimized away, particularly if the bounds checks are
hoisted; but otherwise, we'll need to replace the temporaries with the
unboxed variations, and modify the bailout code to understand how to
rebox the data.

### Comparing with the float32 optimization

IonMonkey currently includes an optimization where it switches to use
float32 arithmetic rather than float64 if it can detect that the
values being added (1) originated from a float32 value and (2) will be
stored back into a float32 value. This is similar to the phi
optimization I suggested above. One difference between that approach
and the one I suggested here is that the float32 optimization is only
performed if all producers *and* consumers expect float32, and not
just the producers.  In contrast, my approach here has says that so
long as a consumer wants unboxed data, it can bypass the box on its
own. If all consumers wind up bypassing the box, then the box is
collected as dead code, but it's also possible for some consumers to
remain, in which case the box remains live. Thus the optimization
described here is more aggressive -- this approach is not possible
with float32s because we are attempting to take an addition that is
specified as a float64 add and perform it using float32 arithmetic,
and that's only legal when the result is always coerced back to
float32. But this scenario does not apply to `SIMD.float32x4.add()`.

### Changes needed

This is a summary of the (front end) changes needed to make this work
happen.

0. Add `MIRType_float32x4` and `MIRType_int32x4`
1. Add the following MIR instructions:
   - `MPackVector(v1, v2, v3, v4) -> {MIRType_float32x4, MIRType_int32x4}`
   - `MLoadVector(elements, offset) -> {MIRType_float32x4, MIRType_int32x4}`
   - `MStoreVector(elements, offset, value)` where `value : {MIRType_float32x4, MIRType_int32x4}`
   - `MAddVector(value1, value2)` where `value1, value2 : {MIRType_float32x4, MIRType_int32x4}`
   - `MVectorTypedObject(value) -> MIRType_object` (similar to `MDerivedTypeObject`)
2. Calls to `SIMD.float32x4.add` are inlined specially if:
   - both operands are typed objects of type T where T = either
     `float32x4` or `int32x4`
   - in that case, insert `MLoadVector` for each argument (using
     existing code that skips indirection as a model -- detecting
     `MDerivedTypeObject` and `MVectorTypedObject` and shortcircuit)
   - insert `MAddVector` with unboxed operands
   - insert `MVectorTypedObject` to box result
3. Loads of typed object values of type `float32x4` are modified to do
   a `MLoadVector` and `MVectorTypedObject`
4. Stores into typed object lvalues of type `float32x4` where value we
   are storing from is a `MVectorTypedObject` would be optimized to
   avoid intermediate
5. Add appropriate LIR instructions and modify register allocator etc.   

[simd]: http://wiki.ecmascript.org/doku.php?id=strawman:simd_number
[904913]: https://bugzilla.mozilla.org/show_bug.cgi?id=904913&sourceid=Mozilla-search
[938728]: https://bugzilla.mozilla.org/show_bug.cgi?id=938728
[opt]: /blog/2013/11/04/optimizing-complex-typed-object-assignments/
[dxr]: http://dxr.mozilla.org/mozilla-central/source/js/src/jit/IonBuilder.cpp#9631
