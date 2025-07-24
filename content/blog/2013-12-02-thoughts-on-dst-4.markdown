---
layout: post
title: "Thoughts on DST, Part 4"
date: 2013-12-02T12:32:00Z
comments: true
categories: [Rust]
---
Over the Thanksgiving break I've been devoting a lot of time to
thinking about DST and Rust's approach to vector and object types.  As
before, this is very much still churning in my mind so I'm just going
to toss out some semi-structured thoughts.

### Brief recap

**Treating vectors like any other container.** Some time back, I wrote
up a post about how we could
[treat vectors like any other container][tvlc], which would (to some
extent) avoid the need for DST.

**Dynamically sized types (DST).** In [Part 1 of the series][part1], I
sketched out how "Dynamically Sized Types" might work. In that scheme,
`[T]` is interpreted as an [existential type][existential] like
`exists N. [T, ..N]`, and `Trait` is interpreted as `exists
T:Trait. T`. The type system ensures that DSTs always appear behind
one of the builtin pointer types, and those pointer types become fat
pointers:

- **Advantage.** Impls for objects and vectors work really well.
- **Disadvantage.** Hard to square with user-defined smart pointers
  like `RC<[int]>`. The problem is worse than I presented in that
  post, I'll elaborate a bit more.

**Statically sized types (SST).** In [Part 2 of the series][part2], I
sketched out an alternative scheme that I later dubbed "Statically
Sized Types".  In this scheme, in some ways similar to today, `[T]`
and `Trait` are not themselves types, but rather shorthands for
existential types where the `exists` qualifier is moved outside the
smart pointer. For example, `~[T]` becomes `exists N. ~[T, ..N]`. The
scheme does not involve fat pointers; rather, the existential type
carries the length, and the thin pointer is embedded within the
existential type.

- **Advantage.** It is easy to create a type like `RC<[int]>` 
  from an existing `RC<[int, ..N]>` (and, similarly, an
  `RC<Trait>` from an existing `RC<T>`).
- **Disadvantage.** Incompatible with monomorphization except via
  virtual calls. I described part of the problem in
  [Part 3 of the series][part3]. I'll elaborate a bit more here.

### Where does that leave us?

So, basically, we are left with two flawed schemes. In this post I just
want to elaborate on some of the thoughts I had over Thanksgiving.
Roughly speaking they are three:

1. DST and smart pointer interaction is even less smooth than I thought,
   but workable for `RC` at least.
2. SSTs, vectors, and smart pointers are just plain unworkable.
3. SSTs, objects, and smart pointers work out reasonable well.

At the end, I suggest two plausible solutions that seem workable to me at this
point:

- DST, after elaborating more examples to see whether they work;
- [Treat vectors like any other container][tvlc] combined with SST for
  object types.

<!-- more -->

### Making DST work with RC requires some contortions

In [part 1][part1], I gave the example of how we could adapt an `RC`
type to use smart pointers. I defined the `RC` type as followings:

    struct RC<T> {
        priv data: *T,
        priv ref_count: uint,
    }

Unfortunately, as Partick [pointed out on reddit][pcwalton], this
simply doesn't work. The ref count needs to be shared amongst
all clones of the `RC` pointer. Embarassing. Anyway, the correct definition
for `RC` is more like the following:

    struct RCData<T> {
        priv ref_count: uint,
        priv t: T,
    }

    struct RC<T> {
       priv data: *mut RCData<T>
    }

In order to be sure that I'm not forgetting details, permit me to
sketch out roughly how an `RC` implementation would look in actual
code.  To start, here is the code to allocate a new `RC` pointer,
based on an initial value. I'm going to allocate the memory using a
direct call to malloc, both so as to express the "maximally
customized" case and because this will be necessary later on.

    impl<T> RC<T> {
        pub fn new(t: T) -> RC<T> {
            unsafe {
                let data: *mut RCData<T> =
                    transmute(malloc(sizeof::<RCData<T>>()));
            
                // Intrinsic `init` initializes memory that contains
                // uninitialized data to begin with:
                init(&mut *data, RCData { ref_count: 1, t: t });
                
                RC { data: data }
            }
        }
    }

One could dereference and clone an `RC` pointer as follows:

    impl<T> Deref for RC<T> {
        fn deref<'a>(&'a self) -> &'a T {
            unsafe { &self.data.t }
        }
    }

    impl<T> Clone for RC<T> {
        fn clone(&self) -> RC<T> {
            unsafe {
                self.data.ref_count += 1;
                *self
            }
        }
    }

The destructor for an `RC<T>` would be written:

    impl<T> Drop for RC<T> {
        fn drop(&mut self) {
            unsafe {
                let rc = self.data.ref_count;
                if rc > 1 {
                    self.data.ref_count = rc - 1;
                    return;
                }
            
                // Intrinsic `drop` that frees memory:
                drop::<T>(&mut self.data.t);
                
                free(self.data);
            }
        }
    }
    
OK, everything seems reasonable. Only one problem -- this whole scheme
is incompatible with DST! To see why, consider again the type
`RCData`:

    struct RCData<T> {
        priv ref_count: uint,
        priv t: T,
    }

And, as you can see here, it references `T` by itself, without using
any kind of pointer indirection. But for `T` to be unsized, it must
always appear behind a `*T` or something similar. This is precisely
the example that I showed in the section
[Limitation: DSTs much appear behind a pointer][part1limitation] in
Part 1.

Now, it turns out we could rewrite `RC` to make it DST compatible.
The idea is to use the standard trick of storing the reference count
at a negative offset. Let's write up an `RC1` type that shows what I
mean:

    struct RC1Header {
        priv ref_count: uint,
    }

    struct RC1<unsized T> {
       priv data: *mut T
    }

In this scheme, we have a pointer `data` directly to a `*mut T`.  This
means that the compiler could "coerce" an `RC1<[int, ..3]>` into a
`RC1<[int]>` by expanding `data` into a fat pointer. It does have the
side-effect of makeing the code to allocate an `RC` and manipulate its
ref count a bit more complex, since more pointer arithmetic is
involved.

Here is the code to allocate an `RC1` instance. Hopefully it's fairly
clear. One interesting aspect is that, for allocation, we don't need
to accept `unsized` types `T`, since at allocation time the full type
is known. However, later on, we may "forget" the precise type of `T`
and convert it into an unsized, existential type like `[U]` or
`Trait`.  In that case, we still need to be able to find the reference
count, even without knowing the size or alignment of `T`. Therefore,
we must be conservative and do our calculations based on the maximal
possible alignment requirement for the platform.
                
    static MAXIMAL_ALIGNMENT: uint = 16; // platform specific
    
    impl<T> RC1<T> {
        pub fn new(t: T) -> RC1<T> {
            unsafe {
                // We need to be able to compute size of header
                // without knowing T, so be conservative:
                assert!(MAXIMAL_ALIGNMENT > sizeof::<uint>());
                let header_size = MAXIMAL_ALIGNMENT;
                
                // Allocate memory for header + data.
                let size = header_size + sizeof::<T>();
                let alloc: *mut u8 = malloc(size) as *mut u8;
                
                // Initialize the reference count.
                let header: *mut RC1Header = alloc as *mut RC1Header;
                *ref_count = 1;
                
                // Initialize the data itself.
                let data: *mut T = (alloc + header_size) as *mut T;
                init(&mut *data, t);
                
                // Construct the GC value.
                RC1 { data: data }
            }
        }
    }
    
Here is a helper to obtain a pointer to the ref count from an `RC1`
instance. Note that it is carefully written to be compatible with an
unsized `T`.

    impl<unsized T> RC1<T> {        
        fn header(&self) -> *mut RC1Header {
            let data: *mut u8 = self.data as *mut u8;
            let header_size = MAXIMAL_ALIGNMENT;
            (data - MAXIMAL_ALIGNMENT) as *mut uint
        }
    }
    
Based on this we can rewrite deref, clone, and drop in a fairly obvious way.
All of them are compatible with `unsized` types.

    impl<unsized T> Deref for RC1<T> {
        fn deref<'a>(&'a self) -> &'a T {
            unsafe { &*self.data }
        }
    }

    impl<unsized T> Clone for RC1<T> {
        fn clone(&self) -> RC<T> {
            unsafe {
                self.header().ref_count += 1;
                *self
            }
        }
    }

    impl<unsized T> Drop for RC1<T> {
        fn drop(&mut self) {
            unsafe {
                let rc = self.header().ref_count;
                if rc > 1 {
                    self.header().ref_count = rc - 1;
                    return;
                }
            
                // Intrinsic `drop` that frees memory:
                drop::<T>(&mut *self.data);
                
                free(self.data);
            }
        }
    }

OK, so we can see that DST *does* permit `RC<[int]>`, but only
barely. It makes me nervous. Is this a general enough solution to
scale to future smart pointers? It's certainly not universal.

### Why SST just doesn't work with vector types.

The SST approach does not employ fat pointers in the same sense and
thus is largely free of the limitations on smart pointer layout that
DST imposes. But not entirely. In [part 3][part3] I described the
problem of finding the correct monomorphized instance of `deref()`.
In general, this is not possible, though in many instances the
compiler could deduce that it doesn't matter which type of pointee
`deref()` is specialized to -- I thus proposed that a solution might
lie in formalizing this idea by permitting a type parameter `T` to be
labeled `erased`, which would cause the compiler to guarantee that the
generated code will be identical no matter what type `T` is
instantiated with. This seems nice, but there are many complications
in practice. Let me sketch them out.

**First, it is rare that a type can be *entirely* erased, even in
dereference routines.** For example, consider the straight-forward `RC`
type that I sketched out before, where the header was made explicit in
the representation, rather than being stored at a negative offset. Here is
the `Deref` routine:

    impl<T> Deref for RC<T> {
        fn deref<'a>(&'a self) -> &'a T {
            unsafe { &self.data.t }
        }
    }

At first, it appears that the precise type `T` is irrelevant, but in
fact we must know its alignment to compute the offset of the field
`t`.  This precise situation is why the alternative scheme `RC1` made
conservative assumptions about the alignment of `t`. We could address
this, though, by manually annotating the alignment of the `t` field
(something we do not yet support, but ought to in any case):

    struct RCData<T> {
        priv ref_count: uint,
        
        #[alignment(maximum)]
        priv t: T,
    }

**A deeper problem lies with the `drop` routine.** The destructor for an
`RC<T>` needs to do three things, and in a particular order:

1. Decrement ref count, returning if it is not yet zero.
2. Drop the value of `T` that we encapsulate.
3. Drop the memory we allocated.

The tricky part is that step 2 requires knowledge of `T`. I thought at
first we might be able to finesse this problem by having the
destructor run after the contained data had been freed, but that
doesn't work because in this case the data is found at the other end
of an unsafe pointer, and the compiler doesn't traverse that -- and
worse, we don't *always* want to free the `T` value of an `RC<T>`,
only if the ref count is zero.

Despite all the problems with `Drop`, it's possible to imagine that we
define some super hacky custom drop protocol for smart pointers that
makes this work. But that's not enough. **There are other operations
that make sense for `RC<[T]>` types beyond indexing, and they have the
same problems.** For example, perhaps I'd like to compare two values
of type `RC<[T]>` for equality:

    fn foo(x: RC<[int]>, y: RC<[int]>) {
        if x == y { ... }
    }
    
This seems reasonable, but we immediately hit the same problem: what
`Eq` implementation should we use? Can `Eq` be defined in an "erased"
way? Let's not forget that `Eq` is currently defined only between
instances of equal type. This winds up being basically the same
problem as drop -- we can only circumvent it by adding a bunch of
specialized logic for comparing existential types.

**Another problem lies in the case where the length of a vector is not
statically known.** The underlying assumption of all this work is that
a type like `~[T]` corresponds to a vector whose length was once
statically known but has been forgotten. We were going to move the
"dynamic length" case to a type like `Vec<T>`, that supports `push()`
and so on. But the idea was that `Vec<T>` should be convertible to
a `~[T]` -- frozen, if you will -- once we were doing building it.
And that doesn't work at all.

**Finally, even if we could, we don't want to generate those
monomorphized variants anyhow.** Even if we could overcome *all* the
above challenges, it's still silly to have a type like `RC<[int]>`
delegate to some specific destructor for `[int, ..N]` for whatever
length `N` it happens to be. That implies we're generating code for
every length o the vector that occurs in practice. Not good, and DST
wouldn't have this problem.

OK, so I hope I've convinced you that SST and vector types *just do
not mix*.

### Why SST could work for object types.

You'll note I was careful not to toss out the baby with the bathwater.
Although SST doesn't work well with vector types, I think it still has
potential for *object types*. There are a couple of crucial
differences here:

1. With object types, we carry a vtable, permitting us to make crucial
   operations -- like drop -- virtual calls.
2. Object types like `RC<Trait>` support a much more limited set of operations:
   - drop;
   - invoke methods offered by `Trait`.
   
There are many ways we could make `RC<Trait>` work. Here is one
possible scheme that is maximally flexible and does not require the
notion of erased type parameters. When you cast an `RC<T>` to an
`RC<Trait>`, we pair it with a vtable. This vtable contains an entry
for drop and an entry for each of the methods in `Trait`. These
entries are setup to take an `RC<T>` as input and to handle the
dereferencing etc themselves, delegating to a monomorphic variant
specialized to `T`. Let me explain by example. First let's create a
simple trait:

    trait Mobile {
        fn hit_points(&self) -> int;
    }
    
    struct PC { ... }
    impl Mobile for PC { ... }
    
    struct NPC { ... }
    impl Mobile for NPC { ... }
    
Now imagine I have a routine like:

    fn interact(pc: RC<PC>, npc: RC<NPC>) {
        let pc_mob: RC<Mobile> = pc as RC<Mobile>; // convert to object type
        let npc_mob: RC<Mobile> = npc as RC<Mobile>; // convert to object type
    }

The idea would be to package up the `RC<Mobile>` with a vtable
containing adapter routines. These routines would be auto-generated by
the compiler, and would look roughly similar to:

    fn RC_PC_drop(r: *RC<PC>) {
        drop(*r)
    }
    
    fn RC_PC_hit_points(r: *RC<PC>) -> uint {
        let pc: &PC = (*r).deref();
        pc.hit_points()
    }
    
Thus, when we convert a `RC<PC>` to a `RC<Player>`, we would pair the
`RC` pointer with a vtable consisting of `RC_PC_drop` and
`RC_PC_hit_points`. There are some minor complications to work out
around the various `self` pointer types, but that seems relatively
straightforward (famous last words). Anyway, the key idea here is to
specialize the vtable routines to the smart pointer type, by moving
the required deref into the generated method itself. This avoids the
need for us to ever invoke code in an erased fashion.

If we added the `erased` keyword, it could still be used to permit the
reuse of these adaptor methods across distinct pointer types. But this
can also be done without a special keyword as an optimization (unlike
before, it's not *necessary* for the type to be erased, merely
helpful).

### Squaring the circle

I think we could maybe make DST work, but I still worry it is too
magical. It has some real advantages though so perhaps the right thing
is to try and elaborate more examples of smart pointer types we
anticipate and see whether they can be made to work.

Another solution is to remove vectors from the language,
[treat them like any other container][tvlc], and use the SST approach
for object types. But there are lots of micro-decisions to be made
there, many of which boil down to usability things. For example, what
is the meaning of the literal syntax and so on? I'll leave those
thoughts for another day.

[tvlc]: {{< baseurl >}}/blog/2013/11/14/treating-vectors-like-any-other-container/
[part1]: {{< baseurl >}}/blog/2013/11/26/thoughts-on-dst-1/
[part1limitation]: {{< baseurl >}}/blog/2013/11/26/thoughts-on-dst-1/#limitation
[part2]: {{< baseurl >}}/blog/2013/11/27/thoughts-on-dst-2/
[part3]: {{< baseurl >}}/blog/2013/11/27/thoughts-on-dst-3/
[existential]: http://en.wikipedia.org/wiki/Type_system#Existential_types
[pcwalton]: http://www.reddit.com/r/rust/comments/1rkfqq/thoughts_on_dst_part_1/cdo9iv9
