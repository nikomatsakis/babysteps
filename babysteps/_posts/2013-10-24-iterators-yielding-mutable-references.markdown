---
layout: post
title: "Iterators yielding mutable references"
date: 2013-10-24 12:02
comments: true
categories: [Rust]
---

There is a [known bug][8624] with the borrowck rules that causes it to
be overly permissive. The fix is relatively simple but it
unfortunately affects some of our `Iterator` implementations,
specifically those iterators that iterate over `&mut` values. The
short version is that while it is possible to expose a safe
*interface* for iterating over `&mut` values, it is not possible to
*implement* such iterators without an unsafe block.

After giving this quite a bit of thought, I have come to the conclusion
that we have three options:

1. Keep things as they are, but accept that some iterators over
   mutable references will require unsafe implementations.
   
2. Split the `Iterator` trait into `Iterator` and `MutIterator`. The
   latter would only be used for iterating over mutable references.

3. Extend the type-system with higher-order types or integrate theorem
   provers to prove much higher-level constraints than we can
   currently reason about. I don't really consider this to be an
   option at this point in time, but I will briefly describe the sorts
   of extensions that might address the problem.

In this post, I'll explain the problem, describe the possible solutions,
and finally dive into some of the longer term implications. 

<!-- more -->

### What is the problem?

#### The iterator trait

To explain the problem, let's begin by examining the
basic iterator trait:

    pub trait Iterator<A> {
        fn next<'n>(&'n mut self) -> Option<A>;
    }

`next()` will be mutating the iterator itself to update the current
position and so forth, so it takes an `&mut self` parameter. I've
opted to make the lifetime `'n` of this pointer explicit, even though
it's not yet necessary, because this lifetime will feature heavily in
the discussion to come.

You can see that the iterator trait is parameterized by a type `A`
that indicates the kind of values being iterated over. One of the
appealing aspects of the iterator trait is that it is able to
encompass both by value iteration (when the type `A` is something like
`int`) and by reference iteration (when the type `A` is something like
`&T`). This all works great, the problems arise when we extend this
same iterator trait to handling mutable references like `&mut
int`. But let's take it step by step.

#### An iterator over mutable references

Now, let's examine how we might implement a mutable iterator over a
slice. By "mutable iterator" I mean an iterator that iterates over
mutable references into the slice, and thus permits you to modify the
contents of the slice in place. For example, one might use a mutable
iterator to increment all the elements in a vector like so:

    let mut vec = ~[1, 2, 3];
    for ref in vec.mut_iter() {
        *ref += 1;
    }
    // vec now equals ~[2, 3, 4];

What follows is a simple implementation of a mutable vector. For the
moment, I have omitted the body of the `next()` method, so you just
see the `struct` declaration and the `impl` of the `Iterator`
trait. The interface below *looks* reasonable, but we will see that
this interface as specified below is unsafe, and would permit user
code to create segfaults. We will also see that (as you would expect,
since it can cause segfaults) there is no way to implement this
interface without an unsafe block (modulo [#8624][8624]).

    // 'v: lifetime of the vector
    struct VecMutIterator<'v, T> {
        data: &'v mut [T],
        index: uint,
    }
    
    impl<'v, T> Iterator<&'v mut T> for VecMutIterator<'v, T> {
        // 'n: lifetime of the call to next()
        fn next<'n>(&'n mut self) -> Option<&'v mut T> {
            // Note lifetime of the result: ^~~
            ....
        }
    }

A mutable iterator holds both a mutable slice (the field `data`) and
an index into that slice (`index`). On every call to `next()`, it
returns another pointer into that slice. What is crucial in this bit
of code is the lifetime of the pointers that get returned from
`next()`. You can see that the lifetime is `'v`, which represents the
lifetime of the slice (I have highlighted the relevant bit with a
comment). Using the lifetime `'v` for those returned pointers makes
some measure of sense. After all, the pointers are pointers into the
slice `self.data`, and `self.data` has the lifetime `'v`.

The danger arises because of Rust's rule that mutable references must
be unique. In a nutshell, Rust requires that every `&mut T` pointer
must be the *only way to mutate the memory it references*. This rule
ensures [memory safety][bpt] and can also serve other purposes, such
as [preventing data races][drf] (I have in the past waxed
philosophical about how
[those two classes of errors are two sides of the same coin][conn]).

The borrow checker is the much loved (or sometimes hated) bit of code
tasked with enforcing this rule. To see an example of how the rules
work, consider this erroneous snippet of code:

    // vec is an array of boxed integers.
    
    let mut vec: ~[~int] = ~[~1, ~2, ~3];
    
    // Using an iterator, we create a pointer
    // `ptr0` that points to the first box in the list,
    // and then a pointer `int0` that points directly
    // at the integer in that box.
    
    let mut iterator = VecMutIterator { data: vec, index: 0 };
    let ptr0: &mut ~int = iterator.next().get();
    let int0: &mut int = &mut **ptr0;
    
    // Now, we modify the vector so as to replace
    // the first box. This will cause the original box
    // to be freed, and would make `int0` a DANGLING POINTER.
    
    vec[0] = ~4; // ERROR
    
    // Accessing `int0` now could cause a crash:
    
    let i = *int0;
    
Here the user has created an iterator and started iterating over the
vector, but then they attempt to mutate the vector and replace its
first element. The borrow checker will flag this as an
error. Intuitively, what happens is that the capability to mutate the
vector is taken from `vec` and moved into the iterator. Once the
iterator goes out of scope, the capability will return to vec, but in
the meantime code like `vec[0] = ~4` is illegal.

However, a devious user might note that there is another way to
create a crash. When creating the iterator, we gave up the capability
to access `vec`, but nowhere did we give up the capability to
access the *iterator itself*. That means that someone could write:

    // Same as before:
    
    let mut vec: ~[~int] = ~[~1, ~2, ~3];
    let mut iterator = VecMutIterator { data: vec, index: 0 };
    let ptr0: &mut ~int = iterator.next().get();
    let int0: &mut int = &mut **ptr0;

    // Same EFFECT as before, but expressed differently:
    
    iterator.data[0] = ~4;
    
Thus we see that the `VecMutIterator` type/impl I showed before is
broken. Fundamentally, the problem is that the code did nothing to
ensure that the mutable references returned are unique.

What's interesting is that the iterator protocol itself is fine. That
is, so long as we only obtain pointers by invoking `next()`
repeatedly, we will always get a new pointer each time, and hence
there is no overlap between the returned values. But because the slice
in its entirety is still available, things break down (astute readers
may note that this hints at a possible solution, see below).

#### How would the Rust type system prevent this?

Given that the `VecMutIterator` type/impl I showed before can be used
to create crashes, one would hope then that the Rust type system would
prevent you from using such an interface, and in fact it does (or
will, once I push the fix for [#8624][8624]). More specifically, there
is no way to implement the body of the `next()` method without using
an `unsafe` block.

To see how the type system rule works, let's examine a possible
implementation of the `Iterator` impl for `VecMutIterator`:

    impl<'v, T> Iterator<&'v mut T> for VecMutIterator<'v, T> {
        // 'n: lifetime of the call to next()
        fn next<'n>(&'n mut self) -> Option<&'v mut T> {
            let index = self.index;
            self.index += 1;
            if index < self.length {
                let ptr: &'v mut T = &mut self.data[index]; // ERROR
                Some(ptr)
            } else {
                None
            }
        }
    }

The code is straight-forward. We save the current index, increment the
index field for next time, and then return a pointer into `self.data`
at the saved index.

The type check error occurs when we attempt to create the pointer
`ptr`. The compiler flags this line as erroneous because it cannot
guarantee that `ptr` will be unique for its entire lifetime. Here the
lifetime of the pointer is `'v`, which means that the compiler must be
able to guarantee that for the entirety of `'v` nobody will be able to
mutate the source of the pointer (`self.data[index]`). The only means
that the compiler has of making this guarantee is to prevent access to
`self.data`. The problem is that the lifetime of `self` is only `'n`:
that is, the duration of the call to `next()`. That means that if we
prevent you from accessing `self` again, we could be sure that `ptr`
would be unique for the lifetime `'n`, but not the entire lifetime
`'v`, which might be longer than `'n`. Therefore an error is reported.

In order to make this impl type check, the `next()` function
would need to return pointers with the lifetime `'n`, not `'v`:

    impl<'v, T> Iterator<&'v mut T> for VecMutIterator<'v, T> {
    // Type from trait:  ^~~~~~~~~
        fn next<'n>(&'n mut self) -> Option<&'n mut T> {
            // Required return type:        ^~~~~~~~~
            ...
        }
    }
    
Of course, this is not possible, because the return type is specified
by the `Iterator` trait to be `Option<A>` where `A` is the type
parameter supplied to the `Iterator` trait (in this case,
`A=&'v mut T`). Moreover, we can't just change the impl to use the lifetime `'n`,
because `'n` is only in scope on the `next()` method. In fact,
for any given `VecMutIterator` instance, there isn't a *single* lifetime
`'n` but rather a distinct lifetime `'n` for each call to `next()`,
so there is no way we could put `'n` into the `VecMutIterator` type itself.

### So what can we do about it?

OK, we've now seen that in fact the `VecMutIterator` implementation I
showed you is unsafe and couldn't be implemented. But we *do* want to
have an iterator over mutable references. So what are our
alternatives? In the beginning of the article, I outlined three
possibilities, and I want to describe them now in more detail.

#### Option 1. Use privacy and an unsafe implementation.

Interestingly, the specific impl I showed you is only unsafe if users
violate the intended interface. That is, if people only call the
`next()` method, they will always be supplied with a fresh mutable
reference each time. Problems arise only when users reach into the
iterator itself and create new aliases into the slice that it
encapsulates. But we have the means to prevent that: privacy.
We could decide the iterator type like so:

    // 'v: lifetime of the vector
    struct VecMutIterator<'v, T> {
        priv data: &'v mut [T],
        priv index: uint,
    }
    
Using this definition, users of `VecMutIterator` cannot directly
access `data`, and instead are limited to using the `next()`
method.

Of course, the borrow checker doesn't understand or consider
privacy, so the implementation of `next()` would still yield
type errors. The solution there would be to use unsafe code:

    impl<'v, T> Iterator<&'v mut T> for VecMutIterator<'v, T> {
        fn next<'n>(&'n mut self) -> Option<&'v mut T> {
            let index = self.index;
            self.index += 1;
            if index < self.length {
            
                // Note: the lifetime `'n` is shorter than what we
                // want, but it's the only thing that the borrow
                // checker can prove.
                
                let ptr: &'n mut T = &mut self.data[index];
                
                // But we know that we never hand out same ref twice,
                // and there is no alternate means of accessing `self.data`,
                // so we can cheat and extend the lifetime by fiat:
                
                unsafe { Some(unsafe::copy_mut_lifetime(self.data, ptr)) }
            } else {
                None
            }
        }
    }
    
This solution is pragmatic but unsavory. It's safe and convenient for
the *user* of the interface. It does mean that implementing iterators
over mutable references would always require an `unsafe` keyword (and
hence more complex reasoning than normal), unless you are able to
build upon another iterator. An example where the latter is sufficient
would be the `Hashmap` type, which stores its data in a vector and
hence can utilize `VecMutIterator` to do the actual traversal.

There is some amount of precedent here. In general, the borrow checker
is not smart enough to reason about indices, which means that operations
like `mut_split` have traditionally been defined with a safe
interface but unsafe implementation:

    impl<T> [T] {
        fn mut_split<'n>(&'n mut self) -> (&'n mut [T], &'n mut [T]) {
            // Divides a single `&mut [T]` slice into two disjoint slices,
            // one covering the left half of the slice and one the right.
            ...
        }
    }
    
The difference to me between these cases is that the reasoning about
whether `MutVecIterator` is correct is more complex, since it requires
thinking not about what might happen in the course of a single
function call, but rather over all possible uses of the
`MutVecIterator` struct for its entire lifetime (including unintended
uses, as we have seen).

Another consideration is more complex iterators. For example, any
iterator trait that did not preserve the invariant that every item is
returned exactly once (e.g., [Java's `ListIterator`][li], or the
`RandomAccessIterator`) is just not compatible with
mutable references unless it is designed very carefully to limit the
lifetime of its return values (rather like the trait I describe in the
next section). However, in Rust we mostly we make use of the
`Iterator` and `DoubleEndedIterator` traits, which only require any
given element in the iteration space to be returned once (of course
one *can* have infinite iterators, but one can also choose not
to). This is partly a consequence of Rust's use of affine types,
meaning they cannot be aliased and must be moved from place to place
(mutable references are of course an example of such a type).

#### Option 2. Use a different trait for mutable references.

Another option is to create a new trait `MutIterator` for iterating
over mutable references. In this case, the existing trait (`Iterator`)
would be used for by-value and by-immutable-ref iteration. What these
two cases have in common is that the lifetime of the thing being
iterated over is independent from the iterator itself. In contrast,
the `MutIterator` trait would be designed to express that the lifetime
of the things you iterate over is linked to the iterator:

    trait MutIterator<A> {
        fn next<'n>(&'n mut self) -> Option<&'n mut A>;
    }
    
Here you can see that the lifetime of the result is *always* `'n`.

This solution permits safe implementations but is less convenient for
end users. You can't write a single function or type that operates
over *any* iterator, but must instead always handle the `MutIterator`
case separately. So things like `vec.iter().enumerate()` would likely
become `vec.mut_iter().mut_enumerate()` or some such. For better or
worse, though, separating out mutability into its own world is quite
common in Rust libraries, precisely because of the dangers to safety
inherent in mutation, so to some extent this is a natural solution.
Also, at least in our compiler and standard libraries, uses of
`mut_iter()` are rather simple and isolated, so having a distinct
trait with fewer capabilities would likely pose little problem.

Having a `MutIterator` trait that is distinct from `Iterator` would
complicate the `for` loop, since it would not be able to assume that
the thing being iterated over must implement `Iterator`. We could
either (1) have a `for mut` syntax; (2) keep the current "duck-typing"
implementation; or maybe (3) try `Iterator` and then
`MutIterator`. But "try-this-and-then-that" style reasoning interacts
poorly with type inference so I'd prefer to avoid it (though we
certainly do it at times).

#### Option 3. Extend the type system.

There are various ways we could extend the type system to resolve this
dilemna. 

**Higher-kinded types.** One solution to address the problem of how
the type parameter to the `Iterator` trait can refer to the lifetime
`'n` that appears below is to add some sort of
[higher-kinded types][HKT]. We could redefine the `Iterator` trait so
that it accepts a higher-kinded type parameter. Of course I have no
idea what the syntax would look like, but it might be something like:

    trait Iterator<A<'n>> {
        fn next<'n>(&'n mut self) -> Option<A<'n>>;
    }
    
Unlike Haskell, which primarily offers kinds of `*` for a simple type
and `* => K` for a higher-kinded type, we would add a kind like `LT`
for lifetime. So the kind of `A` would be `LT => *` (given a lifetime,
you get a simple type).

We could then define the `MutVecIterator` as something like

    impl<'v, T> Iterator<|'n| &'n mut T> for VecMutIterator<'v, T> {
        fn next<'n>(&'n mut self) -> Option<&'n mut T> {
            ....
        }
    }

Now the type being iterated over is `|'n| &'n mut T` -- I am using
`||` to copy our closure syntax, since this is effectively a function
where the parameters and result types are *types*, not *values*.

Anyway, there is clearly a fair amount of design work to be done, and
not to mention consideration of the ergonomics. The above notations
are somewhat intimidating. I also do not think this can be done in a
backwards compatible way -- that is, the existing `VecMutIterator`
which today requires an unsafe implementation would not be typable.
This is because the existing version returns `&'v mut T` values, but
the HKT version would be returning `&'n mut T` values.

**Theorem proving.** In principle, we could eventually integrate some
kind of optional theorem proving into rustc to enable it to reason
about array indices and time more extensively. Such an extension would
definitely allow something like `split` to be proven safe, and would
*probably allow* `VecMutIterator` as well. But the `VecMutIterator`
proof would require a more extensive integration, since it would
require reasoning about privacy etc.

### Some considerations

I think the choice is down to (1) unsafe implementations or (2) a
distinct `MutIterator` trait. I honestly don't know where I fall
yet. Here are the primary considerations that I have been pondering.

**Safety.** To be honest, I am not *that* concerned about the safety
impliciations of requiring unsafe implementations for mutable
iterators. Many data structures can just build on vectors and
hashtables, and so their iterators would be safe. For the rest, well,
data structures in general seem to be a prime place where unsafe code
makes sense -- they offer constrained, well-specified interfaces; they
are widely used and efficiency is paramount; and there is a long
history of efficient, novel data structures that the type system could
never hope to capture.

**Convenience and flexibility.** Choosing an unsafe impl but safe
interface yields the most convenience for end-users. Not only can you
write generic code that operates over *all* iterators, but the mutable
references you iterate over have longer lifetimes than they would in
the `MutIterator` trait approach. For example, the following snippet
of code works for the unsafe implementation but not the `MutIterator`
trait:

    let mut iter = VecMutIterator { ... };
    let ptr0 = iter.next().get();
    let ptr1 = iter.next().get();
    // ptr0 and ptr1 co-exist now
    
With a `MutIterator`, you would not be able to call `next()` until
`ptr0` had gone out of scope. With the unsafe impl approach, `ptr0`
remains in scope as long as the slice that the iterator encapsulated.
*But* traits like `RandomAccessIterator` cannot be supported,
since they would only be safe with a shorter lifetime.

**Future proofing.** On the other hand, precisely because it is offers
a more limited API, I think that the `MutIterator` trait is more
"future-proof". Choosing `MutIterator` would ensure that there are no
`Iterator` implementations for mutable references now. If we later
extended the type system in some way so as to make such
implementations checkable, we could then add iterators for `&mut T`
references in whatever form these extensions permit, and deprecate
`MutIterator`. In particular, if we added HKT, which seems more likely
than theorem proving, we could add iterators that only permit
iteration over `&'n mut T`. Such iterators could also support
the `RandomAccessIterator` trait.

### Conclusion

I kind of hate it when blog posts or news articles address the reader
in the last paragraph, since it generally seems like a rather
formulaic and pedestrian way of creating user interaction. But, in
this case, it seems like the right way to end the post, so I'll make
an exception: Tell me dear reader, what do *you* think we should do?

[bpt]: http://static.rust-lang.org/doc/0.6/tutorial-borrowed-ptr.html#borrowing-unique-boxes
[conn]: http://smallcultfollowing.com/babysteps/blog/2013/06/11/on-the-connection-between-memory-management-and-data-race-freedom/
[drf]: http://smallcultfollowing.com/babysteps/blog/2013/06/11/data-parallelism-in-rust/
[8624]: https://github.com/mozilla/rust/issues/8624
[HKT]: http://en.wikipedia.org/wiki/Kind_%28type_theory%29
[li]: http://docs.oracle.com/javase/6/docs/api/java/util/ListIterator.html
[rai]: http://static.rust-lang.org/doc/master/std/iter/trait.RandomAccessIterator.html
[it]: http://static.rust-lang.org/doc/master/std/iter/trait.Iterator.html
[dei]: http://static.rust-lang.org/doc/master/std/iter/trait.DoubleEndedIterator.html
