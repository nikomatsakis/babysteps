In the last week or so, we've begun the work of merging the old PJS
code based on `ParallelArray` with the [newer API design][strawman]
based on typed objects. As a first step, Felix Klock has been
integrating our [prollyfill][polyfill] into Nightly
([bug 939715][939715]). This means that Nightly users will be able to
use the new API, although they will not (yet) get parallel execution.

The next step then is modify the API implementation to take advantage
of parallel execution. I've been examining what's required and I
turned up one minor issue that needs to be fixed. The issue concerns
*write guards*. In this post I discuss how the current definition must
be updated and review some of the options. In particular I am
interesting in finding an option that is maimally performant.

<!-- more -->

### The current definition of write guards.

The current code permits mutation of objects, but only if those
objects were allocated by the kernel function itself. This ensures
that there is no mutated of shared state, which would of course lead
to data races.

Our current definition was adequate for the Parallel Array code, but
it fails to take into account the *out pointers* featured in the newer
API. For a brief review, in the new API each callback is given an
optional *out pointer* that can be used to write the result of the
callback directly into the output array. This avoids the need for
allocation in many cases, helping to create more efficient code. Here
is a simple example, in which we represent pixels as a struct with
four components, and then build an image in parallel:

    var Pixel = new StructType({r: uint8, g: uint8, b: uint8, a: uint8});
    var Image = Pixel.array(1024, 768);
    
    var anImage = Image.buildPar(2, (x, y, out) => {
        // Here out is a *handle* to a Pixel in the output buffer,
        // so I can write it's value directly rather than allocating
        // and returning a `new Pixel(...)`. We'll create vertical
        // stripes of width 10.
        
        var c = ((y % 20) < 10) ? 0xFF : 0x00;
        out.r = out.g = out.b = c;
        out.a = 0xFF; // never transparent
    });

The interesting part of this example are the assignments to fields of
`out`, such as the last line: `out.a = 0xFF`. Here we are mutating
`out`, which points into the destination buffer. This is safe because
the API guarantees that the portion of the buffer referenced by `out`
is not aliased, so no other thread can see it. Nonetheless, the write
`out.a = 0xFF` would be disallowed by the definition of write guards I
gave before, because the destination buffer was allocated before the
kernel function began execution. Clearly a better definition is needed.

There is one other subtlety to be clear on. The handle `out` in this
case is actually *not* the object being mutated. It is a handle into
the final output buffer, and it's that output buffer that is being
mutated. Therefore, we also have to be sure that out write guards do
not consider `out.a` to be a mutation to the *handle* `out` but rather
to the underlying typed object that `out` points into.

### Sequential fallback, movable handles, and other dangers

There are several complicating factors we have to be aware of when
exploring the design space.

First, it is possible for the handles that we give the kernel
functions to escape in two ways. The most obvious is that the handles
can be stored in the destination array by the kernel function:

    var ObjectArray = Object.array(100);
    ObjectArray.buildPar((_, out) => out)
    
Interestingly, this only works if the resulting array type is
*non-scalar* (that is, if it contains an `Any` or `Object` value).

Handles can also escape by being stored into global variables:

    var globalOut;
    var ObjectArray = Object.array(100);
    ObjectArray.buildPar((i, out) => {
        if (someFunc(i)) {
            globalOut = out; // Mutate shared state.
        }
        use(globalOut);
    });
    
You might expect this to be illegal, because the kernel function is
mutating shared state. You are correct that we will not be able to
execute this code *in parallel*, but we will execute it during the
[sequential fallback][fallback], and the assignment will work just
fine. This kind of escape is creepier than the previous kind because
it is possible for this escaped `out` pointer to be used by later
iterations -- it is even possible for us to re-enter parallel
execution. This implies that the aliasing invariant is more subtle
than "the destination array is unaliased until the operation
terminates". Rather, we must assume that some portions of the
destination array may be aliased, though not the portion that is
currently being written into.

Another consideration is that handles, at least as currently
implemented, are *movable*. This decision is
[somewhat controversial][handles] and potentially malleable. The
reason this matters is that it is possible for users to redirect
the output pointer to point somewhere else:

    var ObjectArray = Object.array(100);
    var array1 = ObjectArray.buildPar(...);
    ObjectArray.buildPar((i, out) => {
        Handle.move(out, array1, i); // move handle to point at `array1`
        use(out);
    });
    
Naturally we must ensure that if users move handles like this, it
doesn't allow them to mutate data they wouldn't otherwise be able to
mutate.

It is also possible for users to create new handles, effectively
"copying" the original handle we gave them:

    var ObjectArray = Object.array(100);
    ObjectArray.buildPar((i, out) => {
        var out2 = Object.handle(out);
        ...
    });
    
Ideally, these copied handles would continue to work just like the
original. That is, mutability is a property of the underlying memory
being mutated, not the handle used to access it.

### Interaction between nullability and handles

Nullability helps to mitigate the dangers posed by escaping handles
(which I mentioned in the previous section). We can say that all
handles used during the parallel operation are nullified upon exit,
and thus guarantee that handles which escape are not particularly
useful. In particular, we can easily prevent later parallel operations
from accessing handles employed by earlier parallel operations this
way.

### Cost of handle allocation and determinism

During execution, we'd prefer not to have to allocate fresh handles
for every iteration. However, it's hard to say how often we *would*
want to allocate fresh handles. This will depend a bit on how we
choose to implement. My first guess is that we would want to implement
one handle per worker thread before the parallel execution begins, and
then simply reuse these handles between iterations, modifying them to
point at subsequent array elements, and finally nullifying them when
the operation is completed. For every sequential fallback, we'd
allocate a single handle and scoot it from place to place.

In any case, for maximum freedom, we'd prefer to allow implementations
to reuse handles or create fresh ones whenever they like, but this
introduces non-determinism into the spec. Since users ought not to be
escaping handles nor relying on their precise identity, this
non-determinism seems fairly harmless -- not to mention that some
parallel operations (like `reduce()`) inherently involve a certain
amount of non-determinism -- but this may still be undesirable.

To make things determinstic, though, we'd have to specify one of
two possible strategies:

- Use the same handle for every iteration. This is perhaps possible,
  but it effectively requires us to use a special kind of handle and
  thread-local data to obtain the correct address for the current thread.
- Use new handles for every iteration. This is easy but potentially
  expensive, since it requires allocation. Interestingly, we could
  *still* reuse the same out pointer in the case of parallel execution
  with a scalar result type, since in that case the handle cannot
  escape and thus the user cannot observe if a new handle was
  supplied.

### Further considerations

If possible, it would be nice if self-hosted code could select
arbitrary buffers to share in a mutable way between PJS worker
threads.  This gives us more internal flexibility to optimize. We
currently achieve this by only sharing arrays and using special
intrinsics like `UnsafePutElement` to write into those arrays.  That
is workable but does not allow us to make use of typed object
specifications, and thus we can't define an (unsafely shared) array of
structs and so on.

### Possible strategy #1 -- Adding a "designated target buffer" to write guards

The initial approach I was considering was simple but rather special purpose:

1. Modify guards to check whether the thing we are writing to is a handle
   or typed object, and consider the underlying buffer rather than the handle.
2. Add a *designated target buffer* to thread-local data.
3. Consider a write to object `X` legal if it is either thread-local or
   the designated target buffer.

The most general form of the write guard would then be something like:

    if (objectToWrite is not a handle) {
        objectToCheck = objectToWrite;
    } else {
        objectToCheck = objectToWrite.owner;
    }
    
    return (isDesignatedTargetObject(objectToCheck) ||
            isThreadLocal(objectToCheck));
            
This can be optimized using TI into two specialized variants, one for
handles and one for other objects. Both specialized variants can
disregard the initial if, and the version for other objects can ignore
the `isDesignatedTargetObject()` check as well.

If we lose support for nullable handles, the "designated target
object" must be replaced with a "designated target region" to account
for the possibility of a handle escaping during sequential fallback
and then being used by later parallel code to write outside of its
target region.

### Possible strategy #2 -- Flags on buffers

The previous strategy feels rather special purpose and does not permit
us to make use of typed objects for internal storage. I then thought
we could generalize it by having a flag on buffers indicating whether
they are *racy* -- meaning mutable from parallel threads -- or not.
We would set this flag for the output object and for any internal
objects, and then clear the flag for the output object once the
operation is done.  In some sense this just modifies the previous
check to permit multiple "designated target objects" (and it requires
a similar generalization, using nonces and counters, if we remove
nullable handles). The obvious downside is that we add data to *every
typed object* just to make our lives a bit more convenient. Probably a
nonstarter.

### Possible strategy #3 -- New class of Racy Handle

The previous two schemes are unsatisfying to me because they do not
leverage our type inference infrastructure in any way. It'd be nice if
we could optimize write guards out in the simple case of writing to
the output handle. This is a bit tricky, though, because whether a
particular output handle object is writable or not is a time-sensitive
property; that is, the same buffer starts out as a "target buffer" --
meaning one that can be written by parallel workers -- but once the
parallel op finishes, the buffer becomes a non-target. Since an object
cannot change its type object dynamically, this implies that whatever
type set summarizes the out pointer will be sullied as containing both
target buffers and non-target-buffers.

*If* handles are nullable, though, there is a way we could leverage TI
to eliminate write guards in many cases. The idea would be to ensure
that every out pointer is always nulled out once a parallel section
ends. In that case, we could omit write guards altogether for out
pointers and just replace them with null pointer checks. An out
pointer handle will be non-null iff it is safe to write.

In terms of the implementation, this would imply a new subclass of
`TypedDatum`. In addition to `TypedObject` and `Handle`, there would
be `RacyHandle`. Instances of `RacyHandle` can only be created by
self-hosted code (sort of, read on). They are exempted from
write-guard checks. The self-hosted code is responsible for only
permitting access to buffers that are not otherwise shared, and for
nullifying the racy handles once that is no longer the case.

There would be one way for users to create a racy handle: they could

ARGH: Handle nullification doesn't really work!

#### Complications

Of course, the spec for handles as originally written *does* include
movability (in fact, it was the original *purpose* of handles). But,
as I wrote before, that feature is somewhat controversial. In
particular it permits oddities like having a callback that moves the
handle you give it, which is a real footgun.

To my mind, handles are all about *capability control*. A handle lets
you create a pointer into a buffer, give it out, and then take it back
(via nullability).

In contrast, movability is an optimization to avoid GC overhead. But
it is a useful one. So could we preserve mutability while eliminating
the footgun of 

Ideally, movability would be limited so that the *creator* of a handle
can move it around to anyplace they like, including nowhere
("nullifying" it), but the *user* of a handle cannot. This can be
achieved via object capabilities, but it implies two objects per
handle.


is not an optimization.

movability is less importnat than nullability. Nullability
gives you the ability 

it's possible to imagine
that we create output handles to target buffers as a distinct `JSClass`.
Essentially out pointers would be a different category of handle. This second
class of handle would behave identically from the user's point of view,
but it would be exempted from write-guard checks. Even better, these
out pointers 
will be able to tell us 
that it permits mutation

### Possible strategy #3 -- Single handle indirected via TLS


<!-- more -->

[strawman]: http://wiki.ecmascript.org/doku.php?id=strawman:data_parallelism
[polyfill]: https://github.com/nikomatsakis/pjs-polyfill
[939715]: https://bugzilla.mozilla.org/show_bug.cgi?id=939715
[fallback]: /blog/2012/10/24/purity-in-parallel-javascript/
[handles]: /blog/2013/10/18/typed-object-handles/
