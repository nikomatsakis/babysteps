---
categories:
- Rust
- Unsafe
comments: false
date: "2016-05-27T12:12:15Z"
slug: the-tootsie-pop-model-for-unsafe-code
title: The 'Tootsie Pop' model for unsafe code
---

In my [previous post][pp], I spent some time talking about the idea of
**unsafe abstractions**. At the end of the post, I mentioned that Rust
does not really have any kind of official guidelines for what kind of
code is legal in an unsafe block and what is not.What this means in
practice is that people wind up writing what "seems reasonable" and
checking it against what the compiler does today. This is of course a
risky proposition since it means that if we start doing more
optimization in the compiler, we may well wind up breaking unsafe code
(the code would still compile; it would just not execute like it used
to).

Now, of course, merely having published guidelines doesn't entirely
change that dynamic. It does allow us to "assign blame" to the unsafe
code that took actions it wasn't supposed to take. But at the end of
the day we're still causing crashes, so that's bad.

This is partly why I have advocated that I want us to try and arrive
at guidelines which are "human friendly". Even if we *have* published
guidelines, I don't expect most people to read them in practice. And
fewer still will read past the introduction. So we had better be sure
that "reasonable code" works by default.

Interestingly, there is something of a tension here: the more unsafe
code we allow, the less the compiler can optimize. This is because it
would have to be conservative about possible aliasing and (for
example) avoid reordering statements. We'll see some examples of this
as we go.

Still, to some extent, I think it's possible for us to have our cake
and eat it too. In this blog post, I outline a proposal to **leverage
unsafe abstaction boundaries** to inform the compiler where it can be
aggressive and where it must be conservative. The heart of the
proposal is the intution that:

- when you enter the unsafe boundary, you can rely that the Rust type
  system invariants hold;
- when you exit the unsafe boundary, you must ensure that the Rust
  type system invariants are restored;
- in the interim, you can break a lot of rules (though not all the
  rules).
  
I call this the **Tootsie Pop** model: the idea is that an unsafe
abstraction is kind of like a [Tootsie Pop][]. There is a gooey candy
interior, where the rules are squishy and the compiler must be
conservative when optimizing. This is separated from the outside world
by a hard candy exterior, which is the interface, and where the rules
get stricter.  Outside of the pop itself lies the safe code, where the
compiler ensures that all rules are met, and where we can optimize
aggressively.

One can also compare the approach to what would happen when writing a
C plugin for a Ruby interpreter. In that case, your plugin can assume
that the inputs are all valid Ruby objects, and it must produce valid
Ruby objects as its output, but internally it can cut corners and use
C pointers and other such things.

In this post, I will elaborate a bit more on the model, and in
particular cover some example problem cases and talk about the grey
areas that still need to be hammered out.

<!--more-->

#### How do you define an unsafe boundary?

My initial proposal is that we should define an unsafe boundary as
being "a module that unsafe code somewhere inside of it". So, for
example, the module that contains `split_at_mut`, which we have seen
earlier is a fn defined with unsafe code, would form an unsafety
boundary. Public functions in this module would therefore be "entry
points" into the unsafe boundary; returning from such a function, or
issuing a callback via a closure or trait method, would be an exit
point.

Initially when considering this proposal, I wanted to use a an unsafe
boundary defined at the function granularity. So any function which
contained an unsafe block but which did not contain `unsafe` in its
signature would be considered the start of an unsafe boundary; and any
`unsafe fn` would be a part of its callers boundary (note that its
caller must contain an unsafe block). This would mean that
e.g. `split_at_mut` is its own unsafe boundary. However, I have come
to think that this definition is too precise and could cause problems
in practice -- we'll see some examples below. Therefore, I have
loosened it.

Ultimately I think that deciding where to draw the unsafe boundary is
still somewhat of an open question. Even using the module barrier
means that some kinds of refactorings that might seem innocent
(migrating code between modules, specifically) can change code from
legal to illegal. I will discuss various alternatives later on.

#### Permissions granted/required at the unsafe boundary

In the model I am proposing, most of your reasoning happens as you
cross into or out of an unsafe abstraction. When you enter into an
unsafe abstraction -- for example, by calling a method like
`split_at_mut`, which is not declared as `unsafe` but uses `unsafe`
code internally -- you implicitly provide that function with certain
permissions. These permissions are derived from the types of the
function's arguments and the rules of the Rust type system. In the
case of `split_at_mut`, there are two arguments:

- The slice `self` that is being split, of type `&'a mut [T]`; and,
- the midpoint `mid` at which to perform the split, of type `usize`.

Based on these types, the `split_at_mut` method can assume that the
variable `self` refers to a suitably initialized slice of values of
type `T`. That reference is valid for the lifetime `'a`, which
represents some span of execution time that encloses at least the
current call to `split_at_mut`. Similarly, the argument `mid` will be
an unsigned integer of suitable size.

At this point we are within the unsafe abstraction. It is now free to
do more-or-less whatever it likes, so long as all the actions it takes
fall within the initial set of permissions. More on this below.

Finally, when you exit from the unsafe boundary, you must ensure that
you have restored whatever invariants and permissions the Rust type
system requires. These are typically going to be derived from the
types of the function's outputs, such as its return type. In the case
of `split_at_mut`, the return type is `(&mut [T], &mut [T])`, so this
implies that you will return a tuple of slices. Since those slices are
both active at the same time, they must (by the rules of Rust's type
system) refer to disjoint memory.

#### Specifying the permissions

In this post, I am not trying to define the complete set of
permissions. We have a reasonably good but not formalized notion of
what these permissions are. Ralf Jung and Derek Dryer have been
working on making that model more precise as part of the [Rust Belt][]
project. I think writing up those rules in one central place would
obviously be a big part of elaboring on the model I am sketching out
here.

If you are writing safe code, the type system will ensure that you
never do anything that exceeds the permissions granted to you. But if
you dip into unsafe code, then you take on the responsibility for
verifying that you obey the given permissions. Either way, the set of
permissions remain the same.

#### Permissons on functions declared as unsafe

If a function is declared as unsafe, then its permissions are not
defined by the type system, but rather in comments and documentation.
This is because the `unsafe` keyword is a warning that the function
arguments may have additional requirements of its caller -- or may
return values that don't meet the full requirements of the Rust type
system.

#### Optimizations within an unsafe boundary

So far I've primarily talked about what happens when you **cross** an
unsafe boundary, but I've not talked much about what you can do
**within** an unsafe boundary. Roughly speaking, the answer that I
propose is: "whatever you like, so long as you don't exceed the
initial set of permissions you were given".

What this means in practice is that when the compiler is optimizing
code that originates inside an unsafe boundary, it will make
pessimistic assumptions about aliasing. This is effectively what C
compilers do today (except they sometimes employ
[type-based alias analysis][tbaa]; we would not).

As a simple example: in safe code, if you have two distinct variables
that are both of type `&mut T`, the compiler would assume that they
represent disjoint memory. This might allow it, for example, to
re-order reads/writes or re-use values that have been read if it does
not see an intervening write. But if those same two variables appear
inside of an unsafe boundary, the compiler would not make that
assumption when optimizing. If that was too hand-wavy for you, don't
worry, we'll spell out these examples and others in the next section.

### Examples

In this section I want to walk through some examples. Each one
contains unsafe code doing something potentially dubious. In each
case, I will do the following:

1. walk through the example and describe the dubious thing;
2. describe what my proposed rules would do;
3. describe some other rules one might imagine and what their
   repercussions might be.
   
By the way, I have been [collecting these sorts of examples][rmm] in a
repository, and am very interested in seeing more such dubious cases
which might offer insight into other tricky situations. The names of
the sections below reflect the names of the files in that repository.

#### split-at-mut-via-duplication

Let's start with a familiar example. This is a variant of the familiar
`split_at_mut` method that I covered in [the previous post][pp]:

```rust
impl [T] {
    pub fn split_at_mut(&mut self, mid: usize) -> (&mut [T], &mut [T]) {
        let copy: &mut [T] = unsafe { &mut *(self as *mut _) }; 
        let left = &mut self[0..mid];
        let right = &mut copy[mid..];
        (left, right)
    }
}    
```

This version works differently from the ones I showed before. It
doesn't use raw pointers. Instead, it cheats the compiler by
"duplicating" `self` via a cast to `*mut`. This means that both `self`
and `copy` are `&mut [T]` slices pointing at the same memory, at the
same time. In ordinary, safe Rust, this is impossible, but using
unsafe code, we can make it happen.

The rest of the function looks almost the same as our original attempt
at a safe implementation (also in the [previous post][pp]). The only
difference now is that, in defining `right`, it uses `copy[mid..]`
instead of `self[mid..]`. The compiler accepts this because it assumes
that `copy` and `self`, since they are both simultaneously valid, must
be disjoint (remember that, in unsafe code, the borrow checker still
enforces its rules on safe typess, it's just that we can use tricks
like raw pointers or transmutes to sidestep them).

**Why am I showing you this?** The key question here is whether the
optimizer can "trust" Rust types within an unsafe boundary. After all,
this code is only accepted because the borrowck thinks (incorrectly)
that `self` and `copy` are disjoint; if the optimizer were to think
the same thing, that could lead to bad optimizations.

**My belief is that this program ought to be legal.** One reason is
just that, when I first implemented `split_at_mut`, it's the most
natural thing that I thought to write. And hence I suspect that many
others would write unsafe code of this kind.

However, to put this in terms of the model, the idea is that the
unsafe boundary here would be the module containing
`split_at_mut`. Thus the dubious aliasing between `left` and `right`
occurs **within** this boundary. In general, my belief is that
whenever we are **inside** the boundary we cannot fully trust the
types that we see. We can only assume that the user is supplying the
types that seem most appropriate to them, not necessarily that they
are accounting for the full implications of those types under the
normal Rust rules. When optimizing, then, the compiler will *not*
assume that the normal Rust type rules apply -- effectively, it will
treat `&mut` references the same way it might treat a `*mut` or
`*const` pointer.

(I have to work a bit more at understanding LLVM's annotations, but I
think that we can model this using the [aliasing metadata][] that LLVM
provides. More on that later.)

**Alternative models.** Naturally alternative models might consider
this code illegal. They would require that one use raw pointers, as
the current implementation does, for any pointer that does not
necessarily obey Rust's memory model.

(Note that this raises another interesting question, though, about
what the legal aliasing is between (say) a `&mut` and a `*mut` that
are actively in use -- after all, an `&mut` is supposed to be unique,
but does that uniqueness cover raw pointers?)

#### refcell-ref

The `borrow()` method on the type `RefCell` employs a helper type that
returns a value of a helper type called `Ref`:

```rust
pub struct Ref<'b, T: ?Sized + 'b> {
    value: &'b T,
    borrow: BorrowRef<'b>,
}
```

Here the `value` field is a reference to the interior of the
`RefCell`, and the `borrow` is a value which, once dropped, will cause
the "lock" on the `RefCell` to be released. This is important because
it means that once `borrow` is dropped, `value` can no longer safely
be used. (You could imagine the helper type `MutexGuard` employing a
similar pattern, though actually it works ever so slightly differently
for whatever reason.)

This is another example of unsafe code is using the Rust types in a
"creative" way. In particular, the type `&'b T` is supposed to mean: a
reference that can be safely used right up until the end of `'b` (and
whose referent will not be mutated). However, in this case, the actual
meaning is "until the end of `'b` or until `borrow` is dropped,
whichever comes first".

So let's consider some imaginary method defined on `Ref`,
`copy_drop()`, which works when `T == u32`. It would copy the value
and then drop the borrow to release the lock.

```rust
use std::mem;
impl<'b> Ref<'b, u32> {
    pub fn copy_drop(self) -> u32 {
        let t = *self.value; // copy contents of `self.value` into `t`
        mem::drop(self.borrow); // release the lock
        t // return what we read before
    }
}
```

Note that there is **no unsafe code** in this function at all. I claim
then that the Rust compiler would, ideally, be within its rights to
rearrange this code and to delay the load of `self.value` to occur later,
sort of like this:

```rust
mem::drop(self.borrow); // release the lock
let t = *self.value; // copy contents of `self.value` into `t`
t // return what we read before
```

This might seem surprising, but the idea here is that the type of
`self.value` is `&'b u32`, which is supposed to mean a reference valid
for all of `'b`.  Moreover, the lifetime `'b` encloses the entire call
to `copy_drop`. Therefore, the compiler would be free to say "well,
maybe I can save a register if I move this load down". 

However, I think that reordering this code would be an invalid
optimization.  Logically, as soon as `self.borrow` is dropped,
`*self.value` becomes inaccessible -- if you imagine that this pattern
were being used for a mutex, you can see why: another thread might
acquire the lock!

Note that because these fields are private, this kind of problem can
only arise for the methods defined on `Ref` itself. The public cannot
gain access to the raw `self.value` reference. They must go through
the deref trait, which returns a reference for some shorter lifetime
`'r`, and that lifetime `'r` always ends before the ref is dropped.
So if you were to try and write the same `copy_drop` routine from the
outside, there would be no problem:

```rust
let some_ref: Ref<u32> = ref_cell.borrow();
let t = *some_ref;
mem::drop(some_ref);
use(t);
```

In particular, the `let t = *some_ref` desugars to something like:

```
let t = {
    let ptr: &u32 = Deref::deref(&some_ref);
    *ptr
};
```

Here the lifetime of `ptr` is just going to be that little enclosing
block there.

**Why am I showing you this?** This example illustrates that, in the
presence of `unsafe` code, the `unsafe` keyword itself is not
necessarily a reliable indicator to where "funny business" could
occur. Ultimately, I think what's important is the **unsafe abstraction
barrier**.

**My belief is that this program ought to be legal.** Frankly, to me,
this code looks entirely reasonable, but also it's the kind of code I
expect people will write (after all, we wrote it). Examples like this
are why I chose to extend the unsafe boundary to enclose the **entire
module** that uses the unsafe keyword, rather than having it be at the
fn granularity -- because there can be functions that, in fact, do
unsafe things where the full limitations on ordering and so forth are
not apparent, but which do not directly involve unsafe code. Another
classic example is modifying the length or capacity fields on a
vector.

Now, I chose to extend to the enclosing, module because it corresponds
to the privacy boundary, and there can be no unsafe abstraction
barrier without privacy. But I'll explain below why this is not a
perfect choice and we might consider others.

#### usize-transfer

Here we have a trio of three functions. These functions collaborate
to hide a reference in a `usize` and then later dereference it:

```rust
// Cast the reference `x` into a `usize`
fn escape_as_usize(x: &i32) -> usize {
    // interestingly, this cast is currently legal in safe code,
    // which is a mite unfortunate, but doesn't really affect
    // the example
    x as *const _ as usize
}

// Cast `x` back into a pointer and dereference it 
fn consume_from_usize(x: usize) -> i32 {
    let y: &i32 = unsafe { &*(x as *const i32) };
    *y
}

pub fn entry_point() {
    let x: i32 = 2;
    let p: usize = escape_as_usize(&x);
    
    // (*) At this point, `p` is in fact a "pointer" to `x`, but it
    // doesn't look like it!
    
    println!("{}", consume_from_usize(p));
}
```

The key point in this example is marked with a `(*)`. At that point,
we have effected created a pointer to `x` and stored it in `p`, but
the type of `p` does not reflect that (it just says it's a
pointer-sized integer). Note also that `entry_point` does not itself
contain unsafe code (further evidence that private helper functions
can easily cause unsafe reasoning to spread beyond the border of a
single fn). So the compiler might assume that the stack slot `x` is
dead and reuse the memory, or something like that.

There are a number of ways that this code might be made less shady.
`escape_as_usize` might have, for example, returned a `*const i32`
instead of `usize`. In that case, `consume_from_usize` would look like:

```rust
fn consume_from_usize(x: *const i32) -> i32 { ... }
```

This itself raises a kind of interesting question though. If a
function is not declared as unsafe, and it is given a `*const i32`
argument, can it dereference that pointer? Ordinarily, the answer
would clearly be no. It has **no idea** what the provenance of that
pointer is (and if you think back to the idea of permissions that are
granted and expected by the Rust type system, the type system does
**not** guarantee you that a `*const` can be dereferenced). So
effectively there is no difference, in terms of the public
permissions, between `x: usize` and `x: *const i32`. Really I think
the **best** way to structure this code would have been to declare
`consume_from_usize()` as `unsafe`, which would have served to declare
to its callers that it has extra requirements regarding its argument
`x` (namely, that it must be a pointer that can be safely
dereferenced).

Now, if `consume_from_usize()` were a **public** function, then not
having an `unsafe` keyword would almost certainly be flat out
wrong. There is nothing that stops perfectly safe callers from calling
it with any old integer that they want; even if the signature were
changed to take `*const u32`, the same is basically true. But
`consume_from_usize()` is not public: it's private, and that perhaps
makes a difference.

It often happens, as we've seen in the other examples, that people cut
corners within the unsafe boundary and declare private helpers as
"safe" that are in fact assuming quite a bit beyond the normal Rust
type rules.

**Why am I showing you this?** This is a good example for playing with
the concept of an unsafe boundary. By moving these functions about,
you can easily create unsafety, as they must all three be contained
within the same unsafe boundary to be legal (if indeed they are legal
at all). Consider these variations:

**Private helper module.** 

```rust
mod helpers {
    pub fn escape_as_usize(x: &i32) -> usize { ... }
    pub fn consume_from_usize(x: usize) -> i32 { ... }
}

pub fn entry_point() {
    ... // calls now written as `helpers::escape_as_usize` etc
}
```

**Private helper module, but restriced scope to an outer scope.** 

```rust
mod helpers {
    pub(super) fn escape_as_usize(x: &i32) -> usize { ... }
    pub(super) fn consume_from_usize(x: usize) -> i32 { ... }
}

pub fn entry_point() {
    ... // calls now written as `helpers::escape_as_usize` etc
}
```

**Public functions, but restricted to an outer scope.** 

```rust
pub mod some_bigger_abstraction {
    mod helpers {
        pub(super) fn escape_as_usize(x: &i32) -> usize { ... }
        pub(super) fn consume_from_usize(x: usize) -> i32 { ... }
        pub(super) fn entry_point() { ... }
    }
}     
```

**Public functions, but de facto restricted to an outer scope.** 

```rust
pub mod some_bigger_abstraction {
    mod helpers {
        pub fn escape_as_usize(x: &i32) -> usize { ... }
        pub fn consume_from_usize(x: usize) -> i32 { ... }
        pub fn entry_point() { ... }
    }

    // no `pub use`, so in fact they are not accessible
}     
```

**Just plain public.**

```rust
pub fn escape_as_usize(x: &i32) -> usize { ... }
pub fn consume_from_usize(x: usize) -> i32 { ... }
pub fn entry_point() { }
```

**Different crates.**

```rust
// crate A:
pub fn escape_as_usize(x: &i32) -> usize { ... }
// crate B:
pub fn consume_from_usize(x: usize) -> i32 { ... }
// crate C:
extern crate a;
extern crate b;
pub fn entry_point() {
    ...
    let p = a::escape_as_usize(&x)
    ...
    b::consume_from_usize(p)
    ...
}
```

**My belief is that some of these variations ought to be legal.** The
current model as I described it here would accept the original
variation (where everything is in one module) but reject all other
variations (that is, they would compile, but result in undefined
behavior). I am not sure this is right: I think that at least the
"private helper module" variations seems maybe reasonable.

Note that I think any or all of these variations should be fine with
appropriate use of the `unsafe` keyword. If the helper functions were
declared as `unsafe`, then I think they could live anywhere. (This is
actually an interesting point that deserves to be drilled into a bit
more, since it raises the question of how distinct unsafe boundaries
"interact"; I tend to think of there as just being safe and unsafe
code, full stop, and hence any time that unsafe code in one module
invokes unsafe code in another, we can assume they are part of the
same boundary and hence that we have to be conservative.)

### On refactorings, harmless and otherwise

One interesting thing to think about with an kind of memory model or
other guidelines is what sorts of refactorings people can safely
perform. For example, under this model, *manually* inlining a fn body
is always safe, so long as you do so within an unsafe abstraction.
Inlining a function from inside an abstraction into the outside is
usually safe, but not necessarily -- the reason it is usually safe is
that most such functions have `unsafe` blocks, and so by manually
inlining, you will wind up changing the caller from a safe function
into one that is part of the unsafe abstraction.

(Grouping items and functions into modules is another example that may
or may not be safe, depending on how we chose to draw the boundary
lines.)

**EDIT:** To clarify a confusion I have seen in a few places. Here I
am talking about *inlining by the user*. Inlining by the compiler is
different. In that case, when we inline, we would track the
"provenance" of each instruction, and in particular we would track
whether the instruction originated from unsafe code. (As I understand
it, LLVM already does this with its aliased sets, because it is needed
for handling C99 `restrict`.) This means that when we decide e.g.  if
two loads may alias, if one (or both) of those loads originated in
unsafe code, then the answer would be different than if they did not.

### Impact of this "proposal" and mapping it to LLVM

I suspect that we are doing some optimizations now that would not be
legal under this proposal, though probably not that many -- we haven't
gone very far in terms of translating Rust's invariants to LLVM's
alias analysis metadata. Note though that in general this proposal is
very optimization friendly: all safe code can be fully optimized.
Unsafe code falls back to more C-like reasoning, where one must be
conservative about potential aliasing (note that I do not want to
employ any [type-based alias analysis][tbaa], though).

I expect we may want to add some annotations that unsafe code can use
to recover optimizations. For example, perhaps something analogous to
the `restrict` keyword in C, to declare that pointers are unaliased,
or some way to say that an `unsafe` fn (or module) nonetheless ensures
that all safe Rust types meet their full requirements.

One of the next steps for me personally in exploring this model is to
try and map out (a) precisely what we do today and (b) how I would
express what I want in LLVM's terms. It's not the best formalization,
but it's a concrete starting point at least!

### Tweaking the concept of a boundary 

As the final example showed, a module boundary is not clearly right.
In particular, the idea of using a module is that it aligned to
privacy, but by that definition it should probably include submodules
(that is, any module where an unsafe keyword appears either in the
module or in some parent of the module is considered to be an unsafe
boundary module).

### Conclusion

Here I presented a high-level proposal for how I think a Rust "memory
model" ought to work. Clearly this doesn't resemble a formal memory
model and there are tons of details to work out. Rather, it's a
guiding principle: be aggressive outside of unsafe abstractions and
conservative inside.

I have two major concerns:

- First, what is the impact on execution time?  I think this needs to
  be investigated, but ultimately I am sure we can overcome any 
  deficit by allowing unsafe code authors to "opt back in" to more aggressive
  optimization, which feels like a good tradeoff.
- Second, what's the best way to draw the optimization boundary?
  Can we make it more explicit?

In particular, the module-based rule that I proposed for the unsafe
boundary is ultimately a kind of heuristic that makes an "educated
guess" as to where the unsafe boundary lies. Certainly the boundary
must be aligned with modules, but as the last example showed, there
may be a lot of ways to set thigns up that "seem reasonable". **It
might be nicer if we could have a way to *declare* that boundary
affirmatively.** I'm not entirely sure that this looks like.  But if
we did add some way, we might then say that if you use the older
`unsafe` keyword -- where the boundary is implicit -- we'll just
declare the whole crate as being an "unsafe boundary". This likely
won't break any code (though of course I mentioned the "different
crates" variation above...), but it would provide an incentive to use
the more explicit form.

For questions or discussion, please see
[this thread on the Rust internals forum][thread].

### Edit log

Some of the examples of dubious unsafe code originally used
`transmute` and `transmute_copy`.  I was asked to change them because
`transmute_copy` really is exceptionally unsafe, even for unsafe code
(type inference can make it go wildly awry from what you expected),
and so we didn't want to tempt anyone into copy-and-pasting them. For
the record: don't copy and paste the unsafe code I labeled as dubious
-- it is indeed dubious and may not turn out to be legal! :)



[pp]: http://smallcultfollowing.com/babysteps/blog/2016/05/23/unsafe-abstractions/
[transmute_copy]: https://doc.rust-lang.org/std/mem/fn.transmute_copy.html
[Rust Belt]: http://plv.mpi-sws.org/rustbelt/
[cell]: https://doc.rust-lang.org/core/cell/struct.UnsafeCell.html
[aliasing metadata]: http://llvm.org/docs/LangRef.html#noalias-and-alias-scope-metadata
[rmm]: https://github.com/nikomatsakis/rust-memory-model/
[tbaa]: http://www.drdobbs.com/cpp/type-based-alias-analysis/184404273
[Tootsie Pop]: https://en.wikipedia.org/wiki/Tootsie_Pop
[thread]: http://internals.rust-lang.org/t/tootsie-pop-model-for-unsafe-code/3522
