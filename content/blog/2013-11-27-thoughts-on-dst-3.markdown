---
layout: post
title: "Thoughts on DST, Part 3"
date: 2013-11-27 15:06
comments: true
categories: [Rust]
---

After posting [part 2][part2] of my DST series, I realized that I had
focusing too much on the pure "type system" aspect and ignoring some
of the more...mundane semantics, and in particular the impact of
monomorphization. I realize now that -- without some further changes
-- we would not be able to compile and execute the second proposal
(which I will dub *statically sized typed* (SST) from here on
out). Let me first explain the problem and then show how my first
thoughts on how it might be addressed.

This is part 3 of a series:

1. [Examining DST.][part1]
2. [Examining an alternative formulation of the current system.][part2]
3. ...and then a twist.
4. [Further complications.][part4]

<!-- more -->

### The problem

The problem with the SST solution becomes apparent when you think
about how you would compile a dereference `*rc` of a value `rc` that
has type `exists N. RC<[int, ..N]>` (written long-hand). *Typing* this
dereference is relatively straightforward, but when you think about
the *actual code* that we generate, things get more complicated.

In particular, imagine the `Deref` impl I showed before:

    impl<T> Deref<T> for RC<T> {
        fn deref<'a>(&'a self) -> &'a T {
            &*self.data
        }
    }

The problem here is that the way monomorphization currently works,
there will be a different impl generated for `RC<[int, ..2]>` and
`RC<[int, ..3]>` and `RC<[int, ..4]>` and so on. So if we actually try
to generate code, we'll need to know which of those versions of deref
we ought to call. But all we know that we have a `RC<[int, ..N]>` for
some unknown `N`, which is not enough information. What's frustrating
of course is that it doesn't actually *matter* which version we call
-- they all generate precisely the same code, and in fact they would
generate the same code regardless of the type `T`. In some cases, as
an optimization, LLVM or the backend might even collapse these
functions into one, since the code is identical, but we have no way at
present to guarantee that it would do so or to ensure that the
generated code is identical.

### A solution

One possible solution for this would be to permit users to mark type
parameters as *erased*. If a type parameter `T` is marked erased, the
compiler would enforce distinctions that guarantee that the generated
code will be the same no matter what type `T` is bound to. This in
turn means the code generator can guarantee that there will only be a
single copy of any function parameterized over `T` (presuming of
course that the function is not parameterized over other, non-erased
type parameters).

If we apply this notion, then we might rewrite our `Deref`
implementation for `RC` as follows:

    impl<erased T> Deref<T> for RC<T> {
        fn deref<'a>(&'a self) -> &'a T {
            &*self.data
        }
    }

It would be illegal to perform the following actions on an `erased` parameter `T`:

- Drop a value of type `T` -- that would require that we know what type `T` is
  so we can call the appropriate destructor.
- Assign to an lvalue of type `T` -- that would require dropping the previous
  value
- Invoke methods on values of type `T` -- in other words, erased parameters can
  have no bounds.
- Take an argument of type `T` or have a local variable of type `T` -- that would
  require knowing how much space to allocate on the stack
- Probably a few other things.

### But maybe that erases too much...?

For the most part those restrictions are ok, but one in particular
kind of sticks in my craw: how can we handle drops? For example,
imagine we have a a value like `RC<[~int]>`. If this gets dropped,
then we'll need to recursively free all of the `~int` values that are
contained in the vector. Presumably this is handled by having `RC<T>`
invoking the appropriate "drop glue" (Rust-ese for destructor) for its
type `T` -- but if `T` is erased, we can't know which drop glue to
run.  And if `T` is *not* erased, then when `RC<[~int]>` is dropped,
we won't know whether to run the destructor for `RC<[~int, ..5]>` or
`RC<[~int, ..6]>` etc. *And* -- of course -- it's wildly wasteful to have
distinct destructors for each possible length of an array.

### Erased is the new unsized?

This `erased` annotation should of course remind you of the `unsized`
annotation in DST. The two are very similar: they guarantee that the
compiler can generate code even in ignorance of the precise
characteristics of the type in question. The difference is that, with
`unsized`, the compile was still generating code specific to each
distinct instantiation of the parameter `T`, it's just that one valid
instantiation would be an unsized type `[U]` (that is, `exists
N. [U, ..N]`). The compiler knew it could always find the length for
any instance of `[U]` and thus could generate drop glue and so on.

So perhaps the solution is not to have *erased*, which says "code
generation knows *nothing* about `T`, but rather some sort of partial
erasure (similar to the way that we erase lifetimes from types at code
generation, and thus can't the code generator can't distinguish the
lifetimes of two borrowed pointers).

### Conclusion

This naturally throws a wrench in the works. I still lean towards the
SST approach, but we'll have to find the correct variation on *erased*
that preserves enough type info to run destructors but not so much as
to require distinct copies of the same function for every distinct
vector length. And it seems clear that we don't get SST "for free"
with no annotation burden at all on smart pointer implementors. As a
positive, having a smarter story about type erasure will help cut down
on code duplication caused by monomorphization.

**UPDATE:** I realize what I'm writing here isn't enough. To actually
drop a value of existential type, we'll need to make use of the
dynamic info -- i.e., the length of the vector, or the vtable for the
object.  So it's not enough to say that the type parameter is erased
during drop -- or rather drop can't possibly work with the type
parameter being erased. However, what is somewhat helpful is that
user-defined drops are always a "shallow" drop. In other words, it's
the compiler's job (typically) to drop the fields of an object. And
the compiler knows the length of the array etc. In any case, I thnk
with some effort, we can make this work, but it's not as simple as
erasing type parameters -- we have to be able to tweak the drop
protocol, or perhaps convert "partially erased" type parameters into a
dynamic value (that would be the length, vtable, or just `()` for
non-existential types) that can be used to permit calls to drop and so
on.

[part1]: {{< baseurl >}}/blog/2013/11/26/thoughts-on-dst-1/
[part2]: {{< baseurl >}}/blog/2013/11/26/thoughts-on-dst-2/
[part4]: {{< baseurl >}}/blog/2013/12/02/thoughts-on-dst-4/
