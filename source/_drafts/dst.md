This is a summary of the discussion regarding the DST proposal.  I
provide rationales for controversial decisions and identify some
pending decisions.

### things you can't do with an unsized type

- To assign to an lvalue, it must be sized
- To move from an rvalue, it must be sized 
  - Modulo parameter passing :)
- To return a value, it must be sized

### unsized keyword

I haven't come up with a compelling alternative. Here are the places
it can go:

1. Before type parameters (`struct Foo<unsized T>`).
2. Before a trait declaration (`unsized trait`).
3. Before a struct declaration (`unsized struct`). // NO

In all cases, the `unsized` keyword means that some type *might* be
unsized (not that it *must* be). In case 1, the type bound to `T`
might be unsized. In case 2, the type bound to `Self` might be unsized
(this is needed to type check default method implementations
separately). In case 3, this struct type may be unsized if
instantiated with suitable type parameters.

**PENDING DECISION:** Should we continue require case 3? It is not
precisely needed. It was added to be more compatible with the "opt in"
proposal for builtin kinds. That is, it makes opting *out* of `Sized`
explicit in the same way that opting *in* to `Share` is explicit.

I am concerned because `unsized struct` reads like the struct is
definitely unsized when in fact it is only *conditionally* unsized. Of
course the same is true for the other uses, but I find it less
problematic with `unsized T` because you must always act as thought
`T` were unsized, whereas with a struct, that is not true:

    unsized struct String<T> { value: T }
    
    fn wrapper(s: String<[u8, ..10]>) {
        // s is Sized here, though `String` was declared unsized.
    }

#### Rationale and alternatives.

**Explicit sized bound.** One obvious alternative is to make a `Sized`
bound. However, experiments suggested that this is just too painful in
practice, and that the vast majority of type parameters would need to
be sized. I am still vaguely interested in re-running these
experiments, but I think it's likely just the wrong default.

**Unsized trait.** Ergonomically I find the notion of an `Unsized`
trait appealing (`struct Foo<T:Unsized>`, `trait Foo : Unsized`).
However, it can also be quite confusing because it acts unlike other
traits.  In other words, if I have `trait A : B` and then I have a
type parameter `T : A`, I know that `T` implements both `A` and `B`.
But if I have `trait C : Unsized` and `U : C`, `U` does not inherit
the `Unsized` qualifier and rather still defaults to sized. Weird.

There is also a kind of odd interaction with declaring structs as
unsized, in that the struct decl would only be legal with an
accompanying `impl<T:Unsized> Unsized for Foo<T>` decl. I find this
less troublesome but others strongly disliked it. (Of course, as noted
about, we could just make `Unsized` purely inferred rather than having
explicit opt out.)

**Negative bounds.** It has sometimes been proposed that we should
support negative bounds, meaning "this trait is not implemented". The
naming of `Unsized` suggests that it would be the same as `!Sized`,
but this is not the case. `!Sized` would mean that the type is
*definitely not* `Sized`, whereas `unsized` means *maybe not*. So no
unification is possible here.

### DST and Strings

There are several goals with respect to strings. One is to try and get
strings "out of the type system". In particular, to make them less
special. Another is to generalize strings so that we can support
multiple encodings, since servo requires UTF16.

#### The `String` type

The design is to introduce the following standard library types:

    unsized struct String<E=UTF8> {
        priv chars: [E]
    }
    
    trait EncodingUnit {
        /* PENDING: Precise details need to be worked out */
    }
    
    impl<E:EncodingUnit> String<E> {
        /* Various methods offered on strings */
    }
    
    struct UTF8 { c: u8 }
    impl EncodingUnit for UTF8 { ... }
    
    struct UTF16 { c: u16 }
    impl EncodingUnit for UTF16 { ... }
    

The type of a string literal would be `"abc"` is `&'static
String<UTF8>`. The compiler will generate the correct UTF8 bytes and
insert them into static memory. It will return a fat pointer with the
suitable length here.

To support other encodings, we can provide standard macros that do the
same thing, perhaps with a transmute (e.g.,
`utf16!("hi")`). Eventually we may wish to have some sort of suffix
notation (`"abc"_utf16`).

**RATIONALE:** I opted to define the `String` type as being
*always unsized*, because the type of the field `chars` is `[E]`.
This is not the recommend pattern for end-users for constructing
such a type. Normally they would be encouraged to write the type
so that it can be constructed in a sized fashion, which would look
like:

    unsized struct String<unsized E=[UTF8]> { chars: E }
    
This way, you could write `String<[UTF8, ..5>]` to get a string of
exactly 5 UTF-8 characters, or `String<[UTF8]>` to get a string whose
length is not statically known. The statically sized variant can then
be coerced to the dynamically sized variant.

In this case, though, there is little reason to have a statically
sized variant. It is very unusual that one has a string of *exactly* N
characters. Moreover, if for some reason you did, you could just use
the type `[UTF8, ..N]` and lose the `String` newtype. Finally, strings
are not constructed in the "two-step" fashion that other types are.
That is, we don't construct a sized variant and then coerce to
unsized. Rather one of two things happens:

1. String constants are automatically coerced to unsized. 
2. Strings are built using a `StringBuilder` in which case the length
   is never statically known (see details below).
   
Therefore, it feels more ergonomic to have the unsizedness be "baked
in" to the string. (It occurs to me that, in general, there might be a
way to have arbitrary user-defined types follow the builder pattern
and thus gain more ergonomics as well.)

#### `StringBuffer` type

To construct strings of dynamic length, we introduce a `StringBuffer`
type, analogous to `Vec` (**QUESTION:** should `Vec` be called
`VecBuffer`?):

    struct StringBuffer<E:EncodingUnit> {
        priv chars: *[E],
        ...
    }

String buffers permit coercion to `~[E]`.

How do I get `Rc<String>` :

```
let x: Rc<String> = Box::from("abc"); // "abc" : &String ==> &[u8]
```

```
let y: = Box::new(|| x.clone());
```

### Integrating with smart pointers



The `Box` trait used by `Box` will look roughly like this:

    trait Box<T,P> {
        fn new<F:FnOnce<T>>(f: F) -> P;
        fn from<unsized T:CloneTo>(value: &T) -> P;
    }

*One oddity about the notion of "unsized"* -- it's not "inherited".
It's also not exactly a negative trait. I give up. Just use the keyword.

Purpose of `from` is to make it possible to convert from slices. It
seems nice to have anyway.

This requires the somewhat funky `CloneTo` trait, which materializes
the out pointer for compatibility with unsized results. Note that for
this to be correct we rely on a kind of "existential open" or
"existential capture" that our type system can't directly
express. That is, based on the *trait*, we know that the out pointer
and input should have the same size, but the impl types lose that
constraint.

```
// Writes a copy of `Self` into `*p`.
// Callee may assume that `*p` is writable and
// has enough memory for `sizeof_value(self)`.
// This is used by smart pointers to clone
// unsized values.
pub unsized trait CloneTo<T> {
  unsafe fn clone_to(&self, p: *mut Self);
}
impl<T:Clone> CloneTo for T {
  unsafe fn clone_to(&self, p: *mut T) {
      *p = self.clone();
  }
}
impl<unsized T:CloneTo> CloneTo for [T] {
  unsafe fn clone_to(&self, p: *mut [T]) {
      assert_eq!(self.len(), len(p)); // should be able to do this
      for i in range(0, self.len()) {
          self[i].clone_to(&(*q)[i]);
      }
  }
}
```

### Generalizing the build pointer

```
struct Tree { value: uint, children: [~Tree] }

trait Builder<H,E> {
    fn new(H) -> Self;
    fn push(&mut self, elem: E);
    fn get(self) -> ~(H,[E]);
}

struct BuilderImpl<H,E> {
    data: *(H,[E]),
    len: uint,
}

impl<H,E> Builder<H,E> for BuilderImpl<H,E> {
    fn new(header: H) -> BuilderImpl<H,E> {
        BuilderImpl {
           ...
        }
    }
    
    fn push(&mut self, elem: E) {
    }
    
    fn get(self) -> ~(H,[E]) {
        ...
    }
}

struct TreeHeader { value: uint }
type Tree = (TreeHeader, [~Tree]);
```

### Overview

#### Dynamically sized types

The core idea of this proposal is to introduce two new types `[T]` and
`Trait`. `[T]` represents "some number of instances of `T` laid out
sequentially in memory", but the exact number if unknown. `Trait`
represents "some type `T` that implements the trait `Trait`".

Both of these types share the characteristic that they are
*existential variants* of existing types. That is, there are
corresponding types which would provide the compiler with full static
information.  For example, `[T]` can be thought of as an instance of
`[T, ..n]` where the constant `n` is unknown. We might use the more
traditional -- but verbose -- notation of `exists n. [T, ..n]` to
describe the type. Similarly, `Trait` is an instance of some type `T`
that implements `Trait`, and hence could be written `exists
T:Trait. T`. Note that I do not propose adding existential syntax into
Rust; this is simply a way to explain the idea.

These existential types have an important facet in common: their size
is unknown to the compiler. For example, the compiler cannot compute
the size of an instance of `[T]` because the length of the array is
unknown. Similarly, the compiler cannot compute the size of an
instance of `Trait` because it doesn't know what type that really
is. Hence I refer to these types as *dynamically sized* -- because the
size of their instances is not known at compilation time. More often,
I am sloppy and just call them *unsized*, because everybody knows that
-- to a compiler author, at least -- compile time is the only
interesting thing, so if we don't know the size at compile time, it is
equivalent to not knowing it at all.

##### Restrictions on dynamically sized types

Because the type (and sometimes alignment) of dynamically sized types
is unknown, the compiler imposes various rules that limit how
instances of such types may be used. In general, the idea is that you
can only manipulate an instance of an unsized type via a pointer.  So
for example you can have a local variable of type `&[T]` (pointer to
array of `T`) but not `[T]` (array of `T`).

Pointers to instances of dynamically sized types are *fat pointers* --
that means that they are two words in size. The secondary word
describes the "missing" information from the type. So a pointer like
`&[T]` will consist of two words: the actual pointer to the array, and
the length of the array. Similarly, a pointer like `&Trait` will
consist of two words: the pointer to the object, and a vtable for `Trait`.

I'll cover the full restrictions later, but the most pertinent are:

1. Variables and arguments cannot have dynamically sized types.
2. Only the last field in a struct may have a dynamically sized type;
   the other fields must not. Enum arguments must not have dynamically
   sized types.

### `unsized` keyword

Any type parameter which may be instantiated with an unsized type must
be designed using the `unsized` keyword. This means that `<T>` is not
the most general definition for a type parameter; rather it should be
`<unsized T>`.

I originally preferred for all parameters to be unsized by default.
However, it seems that the annotation burden here is very high, so for
the moment we've been rejecting this approach.

The unsized keyword crops up in a few unlikely places. One particular
place that surprised me is in the declaration of traits, where we need
a way to annotate whether the `Self` type may be unsized. It's not
entirely clear what this syntax should be. `trait Foo<unsized Self>`,
perhaps? This would rely on `Self` being a keyword, I suppose. Another
option is `trait Foo : unsized`, since that is typically where bounds
on `Self` appear. **(TBD)**

#### Bounds in type definitions

Currently we do not permit bounds in type declarations. The reasoning
here was basically that, since a type declaration never *invokes
methods*, it doesn't need bounds, and we could mildly simplify things
by leaving them out.

But the DST scheme needs a way to tag type parameters as potentially
unsized, which is a kind of bound (in my mind). Moreover, we
[also need bounds to handle destructors][drop], so I think this rule
against bounds in structs is just not tenable.

Once we permit bounds in structs, we have to decide where to enforce
them. My proposal is that we check bounds on the type of every
expression.  Another option is just to check bounds on struct
literals; this would be somewhat more efficient and is theoretically
equivalent, since it ensures that you will not be able to create an
instance of a struct that does not meet the struct's declared
boundaries. However, it fails to check illegal `transmute` calls.

### Creating an instance of a dynamically sized type

Instances of dynamically sized types are obtained by coercing an
existing instance of a statically sized type. In essence, the compiler
simply "forgets" a piece of the static information that it used to
know (such as the length of the vector); in the process, this static
bit of information is converted into a dynamic value and added into
the resulting fat pointer.

#### Intuition

The most obvious cases to be permitted are coercions from built-in
pointer types, such as `&[T, ..n]` to `&[T]` or `&T` to `&Trait`
(where `T:Trait`). Less obvious are the rules to support coercions for
smart pointer types, such as `Rc<[T, ..n]>` being casted to `Rc<[T]>`.

This is a bit more complex than it appears at first. There are two
kinds of conversions to consider. This is easiest to explain by example.
Let us consider a possible definition for a reference-counting smart
pointer `Rc`:

    struct Rc<unsized T> {
        ptr: *RcData<T>,
        
        // In this example, there is no need of more fields, but
        // for purposes of illustration we can imagine that there
        // are some additional fields here:
        dummy: uint
    }
    
    struct RcData<unsized T> {
        ref_count: uint,
        
        #[max_alignment] // explained later
        data: T,
    }
    
From this definition you can see that a reference-counted pointer
consists of a pointer to an `RcData` struct. The `RcData` struct
embeds a reference count followed by the data from the pointer itself.

We wish to permit a type like `Rc<[T, ..n]>` to be cast to a type like
`Rc<[T]>`. This is shown in the following code snippet.

    let rc1: Rc<[T, ..3]> = ...;
    let rc2: Rc<[T]> = rc1 as RC<[T]>;

What is interesting here is that the type we are casting to, `RC<[T]>`,
is not actually a pointer to an unsized type. It is a struct that *contains*
such a pointer. In other words, we could convert the code fragment above
into something equivalent but somewhat more verbose:

    let rc1: Rc<[T, ..3]> = ...;
    let rc2: Rc<[T]> = {
        let Rc { ptr: ptr1, dummy: dummy1 } = rc1;
        let ptr2 = ptr as *RcData<[T]>;
        Rc { ptr: ptr2, dummy: dummy }
    };

In this example, we have unpacked the pointer (and dummy field) out of
the input `rc1` and then cast the pointer itself. This second cast,
from `ptr1` to `ptr2`, is a cast from a thin pointer to a fat pointer.
We then repack the data to create the new pointer. The fields in the
new pointer are the same, but because the `ptr` field has been
converted from a thin pointer to a fat pointer, the offsets of the
`dummy` field will be adjusted accordingly.

So basically there are two cases to consider. The first is the literal
conversion from *thin pointers* to *fat pointers*. This is relatively
simple and is defined only over the builtin pointer types (currently:
`&`, `*`, and `~`). The second is the conversion of a struct which
contains thin pointer fields into another instance of that same stuct
type where fields are fat pointers. The next section defines these
rules in more detail.

#### Conversion rules

Let's start with the rule for converting thin pointers into fat
pointers. This is based on the relation `Fat(T as U) = v`. This
relation says that a pointer to `T` can be converted to a fat pointer
to `U` by adding the value `v`. Afterwards, we'll define the full
rules that define when `T as U` is permitted.

##### Conversion from thin to fat pointers

There are three cases to define the `Fat()` function. The first rule
`Fat-Array` permits converting a fixed-length array type `[T, ..n]`
into the type `[T]` for an of unknown length. The second half of the
fat pointer is just the array length in that case.

    Fat-Array:
      ----------------------------------------------------------------------
      Fat([T, ..n] as [T]) = n
    
The second rule `Fat-Object` permits a pointer to some type `T` to be
coerced into an object type for the trait `Trait`. This rule has three
conditions. The first condition is simply that `T` must implement
`Trait`, which is fairly obvious. The second condition is that `T`
itself must be *sized*. This is less obvious and perhaps a bit
unfortunate, as it means that even if a type like `[int]` implements
`Trait`, we cannot create an object from it. This is for
implementation reasons: the representation of an object is always
`(pointer, vtable)`, no matter the type `T` that the pointer points
at. If `T` were dynamically sized, then `pointer` would have to be a
fat pointer -- since we do not known `T` at compile time, we would
have no way of knowing whether `pointer` was a thin or fat
pointer. What's worse, the size of fat pointers would be effectively
unbounded. The final condition in the rule is that the type `T` has a
suitable alignment; this rule may not be necessary. See Appendix A
for more discussion.

    Fat-Object:
      T implements Trait
      T is sized
      T has suitable alignment (see Appendix A)
      ----------------------------------------------------------------------
      Fat(T as Trait) = vtable

The final rule `Fat-Struct` permits a pointer to a struct type to be
coerced so long as all the fields will still have the same type except
the last one, and the last field will also be a legal coercion. This
rule would therefore permit `Fat(RcData<[int, ..3]> as RcData<[int]>)
= 3`, for example, but not `Fat(RcData<int> as RcData<float>)`.

    Fat-Struct:
      T_0 ... T_i T_n = field-types(R<T ...>)
      T_0 ... T_i U_n = field-types(R<U ...>)
      Fat(T_n as U_n) = v
      ----------------------------------------------------------------------
      Fat(R<T...> as R<U...>) = v

##### Coercion as a whole

Now that we have defined that `Fat()` function, we can define the full
coercion relation `T as U`. This relation states that the type `T` is
coercable to the type `U`; I'm just focusing on the DST-related
coercions here, though we do in fact do other coercions. The rough
idea is that the compiler allows coercion not only simple pointers but
also structs that include pointers. This is needed to support smart
pointers, as we'll see.

The first and simplest rule is the identity rule, which states that we
can "convert" a type `T` into a type `T` (this is of course just a
memcpy at runtime -- note that if `T` is affine then coercion consumes the
value being converted):

    Coerce-Identity:
      ----------------------------------------------------------------------
      T as T

The next rule states that we can convert a thin pointer into a fat pointer
using the `Fat()` rule that we described above. For now I'll just give
the rule for unsafe pointers, but analogous rules can be defined for
borrowed pointers and `~` pointers:

    Coerce-Pointer:
      Fat(T as U) = v
      ----------------------------------------------------------------------
      *T as *U
    
Finally, the third rule states that we can convert a struct `R<T...>`
into another instance of the same struct `R<U...>` with different type
parameters, so long as all of its fields are pairwise convertible:

    Coerce-Struct:
      T_0 ... T_n = field-types(R<T ...>)
      U_0 ... U_n = field-types(R<U ...>)
      forall i. T_i as U_i
      ----------------------------------------------------------------------
      R<T...> as R<U...>
    
The purpose of this rule is to support smart pointer coercion. Let's
work out an example to see what I mean. Imagine that I define a smart
pointer type `Rc` for ref-counted data, building on the `RcData` type
I introduced earlier:

    struct Rc<unsized U> {
        data: *RcData<U>
    }
    
Now if I had a ref-counted, fixed-length array of type
`Rc<[int, ..3]>`, I might want to coerce this into a variable-length
array `Rc<[int]>`. This is permitted by the `Coerce-Struct` rule.  In
this case, the `Rc` type is basically a newtyped pointer, so it's
particularly simple, but we can permit coercions so long as the
individual fields either have the same type or are converted from a
thin pointer into a fat pointer.

These rules as I presented them are strictly concerned with type
checking. The code generation of such casts is fairly
straightforward. The identity relation is a memcpy. The thin-to-fat
pointer conversion consists of copying the thin pointer and adding the
runtime value dictated by the `Fat` function. The struct conversion is
just a recursive application of these two operations, keeping in mind
that the offset in the destination must be adjusted to account for the
size of the increased size of the fat pointers that are produced.

### Working with values of dynamically sized types

Just as with coercions, working with DST values can really be
described in two steps. The first are the builtin operators. These are
only defined over builtin pointer types like `&[T]`. The second is the
method of converting an instance of a smart pointer type like
`RC<[T]>` into an instance of a builtin pointer type. We'll start by
examining the mechanism for converting smart pointers into builtin
pointer types, and then examine the operations themselves.

#### Side note: custom deref operator

The key ingredients for smart pointer integration is an overloadable
deref operator. I'll not go into great detail, but the basic idea is
to define various traits that can be implemented by smart pointer
types. The precise details of these types merits a separate post and
is somewhat orthogonal, but let's just examine the simplest case, the
`ImmDeref` deref:

    trait ImmDeref<unsized T> {
        fn deref<'a>(&'a self) -> &'a T;
    }

This trait would be implemented by most smart pointer types. The type
parameter `T` is the type of the smart pointer's referent. The trait
says that, given a (borrowed) smart pointer instance with lifetime
`'a`, you can dereference that smart pointer and obtain a borrowed
pointer to the referent with lifetime `'a`.

For example, the `Rc` type defined earlier might implement `ImmDeref`
as follows:

    impl<unsized T> ImmDeref<T> for Rc<T> {
        fn deref<'a>(&'a self) -> &'a T {
            unsafe {
                &(*self.ptr).data
            }
        }
    }
    
*Note:* As implied by my wording above, I expect there will be a small
number of deref traits, basically to encapsulate different mutability
behaviors and other characteristics. I'll go into this in a separate
post.
    
#### Indexing into variable length arrays

rustc natively supports indexing into two types: `[T]` (this is a fat
pointer, where the bounds are known dynamically) and `[T, ..n]` (a
fixed length array, where the bounds are known statically). In the
first case, the type rules ensure that the `[T]` value will always be
located as the referent of a fat pointer, and the bounds can be loaded
from the fat pointer and checked dynamically. In the second case, the
bounds are inherent in the type (though they must still be checked,
unless the index is a compile-time constant). In addition, the set of
indexable types can be extended by implementing the `Index` trait. I
will ignore this for now as it is orthogonal to DST.

To participate in indexing, smart pointer types do not have to do
anything special, they need simply overload deref. For example, given
an expresion `r[3]` where `r` has type `Rc<[T]>`, the compiler will
handle it as follows:

1. The type `Rc<[T]>` is not indexable, so the compiler will attempt to
   dereference it as part of the autoderef that is associated with the
   indexing operator.
2. Deref succeeds because `Rc` implements the `ImmDeref` trait described
   above. The type of `*r` is thus `&[T]`.
3. The type `&[T]` is not indexable either, but it too can be dereferenced.
4. We now have an lvalue `**r` of type `[T]`. This
   type is indexable, so the search completes.

#### Invoking methods on objects

This works in a similar fashion to indexing. The normal autoderef
process will lead to a type like `Rc<Trait>` being converted to
`&Trait`, and from there method dispatch proceeds as normal.

#### Drop glue and so on

There are no particular challenges here that I can see. When asked to
drop a value of type `[T]` or `Trait`, the information in the fat
pointer should be enough for the compiler to proceed.

By way of example, here is how I imagine `Drop` would be implemented
for `Rc`:

    impl<unsized T> Drop for Rc<T> {
        fn drop<'a>(&'a mut self) {
            unsafe {
                intrinsics::drop(&mut (*self.ptr).data);
                libc::free(self.ptr);
            }
        }
    }

### Appendices

#### A. Alignment for fields of unsized type

There is one interesting subtlety concerning access to fields of type
`Trait` -- in such cases, the alignment of the field's type is
unknown, which means the compiler cannot statically compute the
field's offset. There are two options:

1. Extract the alignment information from the vtable, which is
   present, and compute the offset dynamically. More complicated to
   codegen but retains maximal flexibility.
2. Require that the alignment for fields of (potentially) unsized type be
   statically specified, or else devise custom alignment rules for such
   fields corresponding to the same alignment used by `malloc()`.
   
The latter is less flexible in that it implies types with greater
alignment requirements cannot be made into objects, and it also
implies that structs with low-alignment payloads, like `RC<u8>`, may
be bigger than they need to be, strictly speaking.

The other odd thing about solution #2 is that it implies that a
generic structure follows separate rules from a specific version of that
structure. That is, given declarations like the following:

    struct Foo1<T> { x: T }
    struct Foo2<unsized U> { x: U }
    struct Foo3 { x: int }
    
It is currently true that `Foo1<int>`, `Foo2<int>`, and `Foo3` are
alike in every particular. But under solution 2 the alignment of
`Foo2<int>` may be greater than `Foo1<int>` or `Foo3` (since the field
`x` was *declared* with unsized type `U` and hence has maximal
alignment).

#### B. Traits and objects

Currently, we only permit method calls with an object receiver if the
method meets two conditions:

- The method does not employ the `Self` type except as the type of the
  receiver.
- The method does not have any type parameters.

The reason for the first restriction is that, in an object, we do not
know what value the type parameter `Self` is instantiated with, and
therefore we cannot type check such a call. The reason for the second
restriction is that we can only put a single function pointer into the
vtable and, under a monomorphization scheme, we potentially need an
infinite number of such methods in the vtable. (We could lift this
restriction if we supported an "erased" type parameter system, but
that's orthogonal.)

Under a DST like system, we can easily say that, for any trait `Trait`
where all methods meet the above restrictions, then the dynamically
sized type `Trait` implements the trait `Trait`. This seems rather
logical, since the type `Trait` represents some unknown type `T` that
implements `Trait`. We must however respect the above two
restrictions, since we will still be dispatching calls dynamically.

(It might even be simpler, though less flexible, to just say that we
can only create objects for traits that meet the above two
restrictions.)

[fh]: https://github.com/nikomatsakis/rust-redex
