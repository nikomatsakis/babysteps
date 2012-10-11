I'm very excited about one of the more recent developments in Rust,
which I call "freezable" data structures.  Freezable data structures
allow you to do things like create a mutable hashmap, initialize it,
and then "freeze" it to be immutable so that it can be shared between
threads.  In some cases, you can even "thaw" the data structure back
out and make it immutable.  No mainstream language that I know can
handle this pattern without copying or dynamic checks---for that
matter, only a few research languages can handle it.

Freezable data structures are not a feature per se: rather they are a
design pattern enabled by several other features.  In this post, I
want to explain how to work with freezable types. In a follow-up I
will cover how to create your own.

### Trivial freezable data structures: Scalar values and structs

I will start by looking at the simplest "freezable data structure" of
all: an integer.  You may be wondering why I am calling an integer a
"data structure".  Well, bear with me for a second.  We'll see that
working with a freezable data structure and working with an integer
are basically equivalent: in fact, another way of thinking about
freezable data structures is as "values", albeit values that are more
expensive to copy than a single integer.

So, imagine I have a counter stored in a local variable, such as the
variable `ints` in this example:

    fn count_ints(nums: &[Either<int, float>]) -> uint {
        let mut ints: uint = 0;
        for nums.each |num| {
            match num {
                &Left(_) => { ints += 1; }
                &Right(_) => { }
            }
        }
        return ints;
    }
    
Here I declared `ints` to be mutable so that I can increment it as we
iterate through the loop.  Now, let's look at the caller to this function:

    fn summarize_ints(nums: &[Either<int, float>]) {
        let ints = count_ints(nums);
        ...
    }
    
Here the returned count is stored into an immutable variable `ints`.
Effectively, the value has been *frozen*.  The value was mutable, but
it has now become immutable: this was achieved not by modifying the
original, exactly, but by moving the value into an new, immutable
location.

Ok, using a single integer as our "freezable value" isn't that
exciting, but hopefully you're all with my so far.  Let's tweak the
example just a little bit to make it mildly more interesting:

    struct Counters { ints: uint, floats: uint }
    fn count_nums(nums: &[Either<int, float>]) -> Counters {
        let mut counting = Counters { ints: 0, floats: 0 };
        for nums.each |num| {
            match num {
                &Left(_) => { counting.ints += 1; }
                &Right(_) => { counting.floats += 1; }
            }
        }
        return counting;
    }
    fn summarize_nums(nums: &[Either<int, float>]) {
        let counted = count_nums(nums);
        ...
    }

Now, instead of the freezable value being a single integer, it is a
struct `Counters` which consists of two integers.  But all the
principles are the same.

Even this simple example demonstrates some unique aspects of Rust's
mutability system.  For one thing, you'll notice that the *fields* of
the struct are not declared as mutable.  Nonetheless, code like
`counting.int += 1` is perfectly legal.  The reason for this is that
the variable `counting` is declared as mutable: in Rust, when you
declare a variable (or field) as mutable, that applies not only to the
variable itself, but also to *all data owned by the variable*.  We'll
dive into the precise definition of ownership later, but for now it
suffices to say that because the fields `ints` and `floats` are
interior to the struct, they are owned by the struct itself.

Now, in the function `summarize_nums()`, the counters are stored into
a variable named `counted`, but this variable is not declared as
mutable.  Just as with a single integer, this effectively *freezes*
the value.  `summarize_nums()` could not, for example, contain code
like `counted.ints += 1`: this would be a compilation error, because
neither `counted` nor the field `ints` are declared as mutable.

In fact, we've just covered *the* key point of freezable data
structures.  A data structure is freezable if (1) it owns all of its
contents and (2) none of its contents are declared as mutable.  These
two conditions effectively imply that the structure will inherit the
mutability of the location in which it is stored.  We can see that
with the struct `Counters`: in `count_nums()`, the struct instance is
stored in the mutable local variable `counting`, and hence its fields
are mutable, but in `summarize_nums()` the same struct is moved into
the local variable `counted`, and it now becomes immutable.

### An aside: ownership

Ownership is a key concept in the Rust memory model.  If you own data,
it means that you have the right to free it or to send it to another
task.  This implies then that nobody else has access to that data---if
they did, after all, then that might allow them to access freed memory
(dangling pointers) or create data races.  However, in practice,
ownership is too strict.... Blah blah blah.

### Less trivial example: vectors

We've seen two examples of freezable data structures, both pretty
trivial: one was just an integer and the other was a struct with two
integers.  Let's look at a more interesting example, one that appears
in basically every Rust program: owned vectors.

Here is a simple example of a function that creates a vector.  This
example takes as input a vector of uints ranging from 0 to `max`.
It produces another vector where each index represents the number of
times that this particular value appeared in the input.  So if the
input vector `values` were `[1, 3, 1, 0]`, the result would be
`[1, 2, 0, 1]`:

    fn histogram(max: uint, values: &[uint]) -> ~[uint] {
        let mut result: ~[uint] = vec::from_elem(max, 0);
        for values.each |value| {
            result[value] += 1;
        }
        return result;
    }

You can see that the basic form of this function is similar to our
earlier examples: the variable `result` is declared as mutable and
then, during the function body itself, mutated repeatedly to create
the final value.  In this case the initial value is a vector of length
`max` consisting entirely of zeroes.  Each element of the vector is
then incremented as needed.

This example further demonstrates the idea of *inherited mutability*.
As we said before, under Rust's mutability rules, whenever a variable
is declared as mutable, *all data owned by the variable is mutable*.
Before, we saw that interior data was owned, but ownership also
extends through `~` pointers (which we call *owned pointers* for a
reason).  Therefore, the variable `result` owns its `uint` elements,
and, as `result` is declared mutable, those `uint` elements are also
mutable.

It is instructive to compare the two parameter `values` and `result`.
The `values` vector is declared as a borrowed vector (`&[uint]`).
Borrowed types never indicate ownership: rather, this is a vector
whose contents are usable but belong to "someone else" (probably the
caller).  Unlike `result`, then, merely storing the borrowed vector
`values` into a mutable location does not mean that we can mutate its
contents:

    let mut mutable_values = values;
    mutable_values[0] += 1; // ERROR

In this case, the local variable is mutable, meaning that it can be
changed to point at different borrowed vectors, but that mutability
does not extend to the elements of the vector itself.  If we want to
mutate the contents of a borrowed vector, those contents must be
explicitly declared as mutable using a type like `&[mut uint]` (note:
in the future, we may change how we write this type to `&mut [uint]`,
to increase consistency between borrowed vectors and other kinds of
borrowed pointers).

Just like the struct we saw before, when an owned vector is assigned
into an immutable location, it is "frozen", meaning that it can no
longer be changed.  In the previous examples, we assigned the
counter/struct into an immutable local variable.  While this is
technically freezing, it's not especially impressive.  Here is a
slightly variation that creates a frozen copy of the histogram, but
stores it into managed data:

    let histo = @histogram(max, values);

Here we have taken the result of `histogram()` and placed it into a
managed box using the `@` operator.  Because the box is not declared
as mutable (i.e., we did not write `@mut`), this implies that the
histogram is now frozen.  Moreover, because it is in a managed box, it
can be freely aliased.  However, as a consequence of this potential
for aliasing, there are two downsides to using a managed box: the
value cannot be sent between tasks, and it cannot be *thawed*.

### Thawing

If freezing implies taking a mutable value and making it immutable,
thawing is the reverse.  As you may have guessed, thawing in Rust is
as simple as moving a value from an immutable location into a mutable
one.  Consider this example, which makes use of the `histogram()`
function we just defined:

    let frozen_histo = histogram(max, values);
    
    // This assignment would lead to an error, as
    // `frozen_histo` is immutable:
    // frozen_histo[0] += 1;
    
    let mut thawed_histo = move frozen_histo;
    thawed_histo[0] += 1;

Thawing is not possible when the value is found via a managed or
borrowed pointer.  This is simply because those kinds of pointers can
be aliased and one cannot move out of a potentially aliased location,
since that would leave a hole in the heap.  However, you can do
something very similar to a thaw using a copy:

    let frozen_histo = @histogram(max, values);
    
    let mut histo = copy *frozen_histo;
    histo[0] += 1;

Here we have "thawed" the histogram simply by copying it out of the
managed box and onto the stack.  I put "thaw" in quotes because the
thawed version is not the same array, but rather a copy of the
original.  The managed box itself remains valid (and frozen).

### Sharing frozen objects between tasks using ARC

Rust is generally a shared-nothing system, in which tasks have no
shared memory at all.  However, sometimes it is convenient to share
immutable data structures between tasks.  You can use the `ARC`
("atomically reference counted") type to package up a frozen data
structure.  ARCs can be *cloned*, which creates another pointer to the
same data, and they can also be sent between tasks.  As the name
implies, under the hood ARCs use an atomic reference counting
mechanism to track when the data can be freed.

To create an ARC, you would simply use the `ARC()` function:

    let histo_arc = ARC(histogram(max, values));
    
The data in the ARC can be accessed using the `get()` function,
which returns a borrowed pointer to the ARC's contents:

    let histo_data: &~[uint] = arc::get(histo_arc);
    for histo_data.each |h| { ... }
    
To send the ARC to another task, you generally want to clone it
and send the clone, so that you retain your own copy:

    let histo_arc2 = arc::clone(histo_arc);
    chan.send(move histo_arc2);
    
### Temporary immutability using borrow check

So far we've focused on values that begin as mutable and transition to
frozen after some fixed period.  This is a common and important
pattern, but of course there are other cases where a value must
transition smoothly between frozen and thawed and back again.  The
most common case is during iteration, which in Rust requires that the
container you are iterating over be immutable.

To see why the container must be immutable, consider iterating over a
vector.  In Rust, iteration is done using the `each()` method, which
provides a pointer to each value in the vector, one after the other.
If you were to push a new value onto the vector, this could cause the
vector to be freed and reallocated, which would invalidate the pointer
you were given.  This is covered in some detail in the
[tutorial on borrowed pointers][bp].

For values which are owned by the current stack, the Rust compiler
will track when the value is required to be immutable.

### Temporary immutability using the `Mut<>` type



### Bigger data structures

The examples in this tutorial have focused on 






<!-- Links: -->

[bp]: dl.rust-lang.org/doc/tutorial-borrowed-ptr.html


