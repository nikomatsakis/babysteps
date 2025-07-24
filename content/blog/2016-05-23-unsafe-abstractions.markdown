---
layout: post
title: "Unsafe abstractions"
date: 2016-05-23T08:17:07-0400
comments: false
categories: [Rust]
---

The `unsafe` keyword is a crucial part of Rust's design. For those not
familiar with it, the `unsafe` keyword is basically a way to bypass
Rust's type checker; it essentially allows you to write something more
like C code, but using Rust syntax.

The existence of the `unsafe` keyword sometimes comes as a surprise at
first. After all, isn't the point of Rust that Rust programs should
not crash? Why would we make it so easy then to bypass Rust's type
system? It can seem like a kind of flaw in the design.

In my view, though, `unsafe` is anything but a flaw: in fact, it's a
critical piece of how Rust works. The `unsafe` keyword basically
serves as a kind of "escape valve" -- it means that we can keep the
type system relatively simple, while still letting you pull whatever
dirty tricks you want to pull in your code. The only thing we ask is
that you package up those dirty tricks with some kind of abstraction
boundary.

This post introduces the `unsafe` keyword and the idea of unsafety
boundaries. It is in fact a lead-in for another post I hope to publish
soon that discusses a potential design of the so-called
[Rust memory model][1447], which is basically a set of rules that help
to clarify just what is and is not legal in unsafe code.

<!-- more -->

### Unsafe code as a plugin

I think a good analogy for thinking about how `unsafe` works in Rust
is to think about how an interpreted language like Ruby (or Python)
uses C modules. Consider something like the JSON module in Ruby. The
JSON bundle includes a pure Ruby implementation (`JSON::Pure`), but it
also includes a re-implementation of the same API in C
(`JSON::Ext`). By default, when you use the JSON bundle, you are
actually running C code -- but your Ruby code can't tell the
difference. From the outside, that C code looks like any other Ruby
module -- but internally, of course, it can play some dirty tricks and
make optimizations that wouldn't be possible in Ruby. (See this
excellent blog post on [Helix][helix] for more details, as well as
some suggestions on how you can write Ruby plugins in Rust instead.)

Well, in Rust, the same scenario can arise, although the scale is
different. For example, it's perfectly possible to write an efficient
and usable hashtable in pure Rust. But if you use a bit of unsafe
code, you can make it go faster still. If this a data structure that
will be used by a lot of people or is crucial to your application,
this may be worth the effort (so e.g. we use unsafe code in the
standard library's implementation). But, either way, normal Rust code
should not be able to tell the difference: the unsafe code is
**encapsulated** at the API boundary.

Of course, just because it's *possible* to use unsafe code to make
things run faster doesn't mean you will do it frequently. Just like
the majority of Ruby code is in Ruby, the majority of Rust code is
written in pure safe Rust; this is particularly true since safe Rust
code is very efficient, so dropping down to unsafe Rust for
performance is rarely worth the trouble.

In fact, probably the single most common use of unsafe code in Rust is
for FFI. Whenever you call a C function from Rust, that is an unsafe
action: this is because there is no way the compiler can vouch for the
correctness of that C code.

### Extending the language with unsafe code

To me, the most interesting reason to write unsafe code in Rust (or a
C module in Ruby) is so that you can extend the capabilities of the
language. Probably the most commonly used example of all is the `Vec`
type in the standard library, which uses unsafe code so it can handle
uninitialized memory; `Rc` and `Arc`, which enable shared ownership,
are other good examples. But there are also much fancier examples,
such as how [Crossbeam][] and [deque][] use unsafe code to implement
non-blocking data structures, or [Jobsteal][] and [Rayon][] use unsafe
code to implement thread pools.

In this post, we're going to focus on one simple case: the
`split_at_mut` method found in the standard library. This method is
defined over mutable slices like `&mut [T]`. It takes as argument a
slice and an index (`mid`), and it divides that slice into two pieces
at the given index. Hence it returns two subslices: ranges from
`0..mid`, and one that ranges from `mid..`.

You might imagine that `split_at_mut` would be defined like this:

```rust
impl [T] {
    pub fn split_at_mut(&mut self, mid: usize) -> (&mut [T], &mut [T]) {
        (&mut self[0..mid], &mut self[mid..])
    }
}    
```

If it compiled, this definition would do the right thing, but in fact
if you [try to build it][play] you will find it gets a compilation
error. It fails for two reasons:

1. In general, the compiler does not try to reason precisely about
   indices. That is, whenever it sees an index like `foo[i]`, it just
   ignores the index altogether and treats the entire array as a unit
   (`foo[_]`, effectively).  This means that it cannot tell that `&mut
   self[0..mid]` is disjoint from `&mut self[mid..]`. The reason for
   this is that reasoning about indices would require a much more
   complex type system.
2. In fact, the `[]` operator is not builtin to the language when
   applied to a range anyhow. It is
   [implemented in the standard library][range]. Therefore, even if
   the compiler knew that `0..mid` and `mid..` did not overlap, it
   wouldn't necessarily know that `&mut self[0..mid]` and `&mut
   self[mid..]` return disjoint slices.
   
Now, it's plausible that we could extend the type system to make this
example compile, and maybe we'll do that someday. But for the time
being we've preferred to implement cases like `split_at_mut` using
unsafe code. This lets us keep the type system simple, while still
enabling us to write APIs like `split_at_mut`.

### Abstraction boundaries

Looking at unsafe code as analogous to a plugin helps to clarify the
idea of an **abstraction boundary**. When you write a Ruby plugin, you
expect that when users from Ruby call into your function, they will
supply you with normal Ruby objects and pointers. Internally, you can
play whatever tricks you want: for example, you might use a C array
instead of a Ruby vector. But once you return values back out to the
surrounding Ruby code, you have to repackage up those results as
standard Ruby objects.

It works the same way with unsafe code in Rust. At the public
boundaries of your API, your code should act "as if" it were any other
safe function. This means you can assume that your users will give you
valid instances of Rust types as inputs. It also means that any values
you return or otherwise output must meet all the requirements that the
Rust type system expects. *Within* the unsafe boundary, however, you
are free to bend the rules (of course, just *how* free you are is the
topic of debate; I intend to discuss it in a follow-up post).

Let's look at the `split_at_mut` method we saw in the previous
section. For our purposes here, we only care about the "public
interface" of the function, which is its signature:

```rust
impl [T] {
    pub fn split_at_mut(&mut self, mid: usize) -> (&mut [T], &mut [T]) {
        // body of the fn omitted so that we can focus on the
        // public inferface; safe code shouldn't have to care what
        // goes in here anyway
    }
}    
```

So what can we derive from this signature? To start, `split_at_mut`
can assume that all of its inputs are "valid" (for safe code, the
compiler's type system naturally ensures that this is true; unsafe
callers would have to ensure it themselves). Part of writing the rules
for unsafe code will require enumerating more precisely what this
means, but at a high-level it's stuff like this:

- The `self` argument is of type `&mut [T]`. This implies that we will
  receive a reference that points at some number `N` of `T` elements.
  Because this is a mutable reference, we know that the memory it
  refers to cannot be accessed via any other alias (until the mutable
  reference expires). We also know the memory is initialized and the
  values are suitable for the type `T` (whatever it is).
- The `mid` argument is of type `usize`. All we know is that it is
  some unsigned integer.

There is one interesting thing missing from this list,
however. Nothing in the API assures us that `mid` is actually a legal
index into `self`. This implies that whatever unsafe code we write
will have to check that.

Next, when `split_at_mut` returns, it must ensure that its return
value meets the requirements of the signature. This basically means it
must return two valid `&mut [T]` slices (i.e., pointing at valid
memory, with a length that is not too long). Crucially, since those
slices are both valid at the same time, this implies that the two
slices must be *disjoint* (that is, pointing at different regions of
memory).

### Possible implementations

So let's look at a few different implementation strategies for
`split_at_mut` and evaluate whether they might be valid or not. We
already saw that a pure safe implementation doesn't work. So what if
we implemented it using raw pointers like this:

```rust
impl [T] {
    pub fn split_at_mut(&mut self, mid: usize) -> (&mut [T], &mut [T]) {
        use std::slice::from_raw_parts_mut;
        
        // The unsafe block gives us access to raw pointer
        // operations. By using an unsafe block, we are claiming
        // that none of the actions below will trigger
        // undefined behavior.
        unsafe {
            // get a raw pointer to the first element
            let p: *mut T = &mut self[0]; 

            // get a pointer to the element `mid`
            let q: *mut T = p.offset(mid as isize);
            
            // number of elements after `mid`
            let remainder = self.len() - mid;
        
            // assemble a slice from 0..mid
            let left: &mut [T] = from_raw_parts_mut(p, mid);

            // assemble a slice from mid..
            let right: &mut [T] = from_raw_parts_mut(q, remainder);

            (left, right)
        }
    }
}    
```

This is a mostly valid implementation, and in fact fairly close to
what [the standard library actually does][split_at_mut]. However, this
code is making a critical assumption that is not guaranteed by the
input: it is assuming that `mid` is "in range". Nowhere does it check
that `mid <= len`, which means that the `q` pointer might be out of
range, and also means that the computation of `remainder` might
overflow and hence (in release builds, at least by default) wrap
around. **So this implementation is incorrect**, because it requires
more guarantees than what the caller is required to provide.

We could make it correct by adding an assertion that `mid` is a valid
index (note that the assert macro in Rust always executes, even in
optimized code):

```rust
impl [T] {
    pub fn split_at_mut(&mut self, mid: usize) -> (&mut [T], &mut [T]) {
        use std::slice::from_raw_parts_mut;

        // check that `mid` is in range:
        assert!(mid <= self.len());
        
        // as before, with fewer comments:
        unsafe {
            let p: *mut T = &mut self[0]; 
            let q: *mut T = p.offset(mid as isize);
            let remainder = self.len() - mid;
            let left: &mut [T] = from_raw_parts_mut(p, mid);
            let right: &mut [T] = from_raw_parts_mut(q, remainder);
            (left, right)
        }
    }
}    
```

OK, at this point we have basically reproduced the
[implementation in the standard library][split_at_mut] (it uses some
slightly different helpers, but it's the same idea).

### Extending the abstraction boundary

Of course, it might happen that we actually *wanted* to assume `mid`
that is in bound, rather than checking it. We couldn't do this for the
actual `split_at_mut`, of course, since it's part of the standard
library. But you could imagine wanting a private helper for safe code
that made this assumption, so as to avoid the runtime cost of a bounds
check. In that case, `split_at_mut` is **relying on the caller** to
guarantee that `mid` is in bounds. This means that `split_at_mut` is
no longer "safe" to call, because it has additional requirements for
its arguments that must be satisfied in order to guarantee memory
safety.

Rust allows you express the idea of a fn that is not safe to call by
moving the `unsafe` keyword out of the fn body and into the public
signature. Moving the keyword makes a big difference as to the meaning
of the function: the unsafety is no longer just an **implementation
detail** of the function, it's now part of the **function's
interface**.  So we could make a variant of `split_at_mut` called
`split_at_mut_unchecked` that avoids the bounds check:

```rust
impl [T] {
    // Here the **fn** is declared as unsafe; calling such a function is
    // now considered an unsafe action for the caller, because they
    // must guarantee that `mid <= self.len()`.
    unsafe pub fn split_at_mut_unchecked(&mut self, mid: usize) -> (&mut [T], &mut [T]) {
        use std::slice::from_raw_parts_mut;
        let p: *mut T = &mut self[0]; 
        let q: *mut T = p.offset(mid as isize);
        let remainder = self.len() - mid;
        let left: &mut [T] = from_raw_parts_mut(p, mid);
        let right: &mut [T] = from_raw_parts_mut(q, remainder);
        (left, right)
    }
}    
```

When a `fn` is declared as `unsafe` like this, calling that fn becomes
an `unsafe` action: what this means in practice is that the caller
must read the documentation of the function and ensure that what
conditions the function requires are met. In this case, it means that
the caller must ensure that `mid <= self.len()`.

If you think about abstraction boundaries, declaring a fn as `unsafe`
means that it does not form an abstraction boundary with safe code.
Rather, it becomes part of the unsafe abstraction of the fn that calls
it.

Using `split_at_mut_unchecked`, we could now re-implemented `split_at_mut`
to just layer on top the bounds check:

```rust
impl [T] {
    pub fn split_at_mut(&mut self, mid: usize) -> (&mut [T], &mut [T]) {
        assert!(mid <= self.len());
        
        // By placing the `unsafe` block in the function, we are
        // claiming that we know the extra safety conditions
        // on `split_at_mut_unchecked` are satisfied, and hence calling
        // this function is a safe thing to do.
        unsafe {
            self.split_at_mut_unchecked(mid)
        }
    }
    
    // **NB:** Requires that `mid <= self.len()`.
    pub unsafe fn split_at_mut_unchecked(&mut self, mid: usize) -> (&mut [T], &mut [T]) {
        ... // as above
    }
}
```

### Unsafe boundaries and privacy

Although there is nothing in the language that *explicitly* connects
the privacy rules with unsafe abstraction boundaries, they are naturally interconnected. This is because
privacy allows you to control the set of code that can modify your
fields, and this is a basic building block to being able to construct
an unsafe abstraction.

Earlier we mentioned that the `Vec` type in the standard library is
implemented using unsafe code. This would not be possible without
privacy. If you look at the definition of `Vec`, it looks something
like this:

```rust
pub struct Vec<T> {
    pointer: *mut T,
    capacity: usize,
    length: usize,
}
```

Here the field `pointer` is a pointer to the start of some
memory. `capacity` is the amount of memory that has been allocated and
`length` is the amount of memory that has been initialized.

The vector code is all very careful to maintain the invariant that it
is always safe the first `length` elements of the the memory that
`pointer` refers to. You can imagine that if the `length` field were
public, this would be impossible: anybody from the outside could go
and change the length to whatever they want!

For this reason, unsafety boundaries tend to fall into one of two
categories:

- a single functions, like `split_at_mut`
  - this could include unsafe callees like `split_at_mut_unchecked`
- a type, typically contained in its own module, like `Vec`
  - this type will naturally have private helper functions as well
  - and it may contain unsafe helper types too, as described in
    the next section
  
### Types with unsafe interfaces
  
We saw earlier that it can be useful to define `unsafe` functions like
`split_at_mut_unchecked`, which can then serve as the building block
for a safe abstraction. The same is true of types. In fact, if you
look at the [actual definition][vec] of `Vec` from the standard
library, you will see that it looks just a bit different from what we
saw above:

```rust
pub struct Vec<T> {
    buf: RawVec<T>,
    len: usize,
}
```

What is this `RawVec`? Well, that turns out to be an [unsafe helper
type][raw_vec] that encapsulates the idea of a pointer and a capacity:

```rust
pub struct RawVec<T> {
    // Unique is actually another unsafe helper type
    // that indicates a uniquely owned raw pointer:
    ptr: Unique<T>,
    cap: usize,
}
```

What makes `RawVec` an "unsafe" helper type? Unlike with functions,
the idea of an "unsafe type" is a rather fuzzy notion. I would define
such a type as a type that doesn't really let you do anything useful
without using unsafe code. Safe code can construct `RawVec`, for example,
and even resize the backing buffer, but if you want to actually access
the data *in* that buffer, you can only do so by calling
[the `ptr` method][ptr], which returns a `*mut T`. This is a raw
pointer, so dereferencing it is unsafe; which means that, to be
useful, `RawVec` has to be incorporated into another unsafe
abstraction (like `Vec`) which tracks initialization.

### Conclusion

Unsafe abstractions are a pretty powerful tool. They let you play just
about any dirty performance trick you can think of -- or access any
system capbility -- while still keeping the overall language safe and
relatively simple. We use unsafety to implement a number of the core
abstractions in the standard library, including core data structures
like `Vec` and `Rc`. But because all of these abstractions encapsulate
the unsafe code behind their API, users of those modules don't carry
the risk.

#### How low can you go?

One thing I have not discussed in this post is a lot of specifics
about *exactly* what is legal within unsafe code and not. Clearly, the
point of unsafe code is to bend the rules, but how far can you bend
them before they break? At the moment, we don't have a lot of
published guidelines on this topic. This is something we
[aim to address][1447]. In fact there has even been a
[first RFC][1578] introduced on the topic, though I think we can
expect a fair amount of iteration before we arrive at the final and
complete answer.

As I [wrote on the RFC thread][c], my take is that we should be
shooting for rules that are "human friendly" as much as possible. In
particular, I think that most people will not read our rules and fewer
still will try to understand them. So we should ensure that the unsafe
code that people write in ignorance of the rules is, by and large,
correct. (This implies also that the majority of the code that exists
ought to be correct.)

Interestingly, there is something of a tension here: the more unsafe
code we allow, the less the compiler can optimize. This is because it
would have to be conservative about possible aliasing and (for
example) avoid reordering statements.

In my next post, I will describe how I think that we can leverage
unsafe abstractions to actually get the best of both worlds. The basic
idea is to aggressively optimized safe code, but be more conservative
within an unsafe abstraction (but allow people to opt back in with
additional annotations).

**Edit note:** Tweaked some wording for clarity.

[Rayon]: http://smallcultfollowing.com/babysteps/blog/2015/12/18/rayon-data-parallelism-in-rust/
[Crossbeam]: https://github.com/aturon/crossbeam
[jobsteal]: https://github.com/rphmeier/jobsteal
[deque]: https://github.com/kinghajj/deque
[range]: https://github.com/rust-lang/rust/blob/b9a201c6dff196fc759fb1f1d3d292691fc5d99a/src/libcore/slice.rs#L572-L589
[split_at_mut]: https://github.com/rust-lang/rust/blob/b9a201c6dff196fc759fb1f1d3d292691fc5d99a/src/libcore/slice.rs#L338-L349
[transmute_copy]: https://doc.rust-lang.org/std/mem/fn.transmute_copy.html
[helix]: http://blog.skylight.io/introducing-helix/
[play]: https://is.gd/2UpNUr
[1447]: https://github.com/rust-lang/rfcs/issues/1447
[1578]: https://github.com/rust-lang/rfcs/pull/1578
[vec]: https://github.com/rust-lang/rust/blob/cf37af162721f897e6b3565ab368906621955d90/src/libcollections/vec.rs#L272-L275
[raw_vec]: https://github.com/rust-lang/rust/blob/cf37af162721f897e6b3565ab368906621955d90/src/liballoc/raw_vec.rs
[ptr]: https://github.com/rust-lang/rust/blob/cf37af162721f897e6b3565ab368906621955d90/src/liballoc/raw_vec.rs#L143-L145
[c]: https://github.com/rust-lang/rfcs/pull/1578#issuecomment-217184537
