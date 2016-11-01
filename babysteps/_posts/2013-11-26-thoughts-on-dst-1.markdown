---
layout: post
title: "Thoughts on DST, Part 1"
date: 2013-11-26 21:52
comments: true
categories: [Rust]
---
In the past, I've been quite the champion of dynamically sized types
(DST). Specifically what this means is that things like `[T]` and
`Trait` would be "types" in the Rust type system. Lately I've been
investing a lot of effort thinking through the ramifications of
offering better support for smart pointers, and in particular how this
interacts with dynamically sized types, and I am no longer persuaded
that DST offer the best way forward. I'm a bit unsure, though, and the
topic is complicated, so I wanted to stop and write up a short series
of posts laying out my thought process thus far. This post will
describe what it would mean to offer DST in more detail. I don't plan
to give a lot of Rust background, since there's enough to talk about.

This is part 1 of a series:

1. Examining DST.
2. [Examining an alternative formulation of the current system.][part2]
3. [...and then a twist.][part3]
4. [Further complications.][part4]

<!-- more -->

### Vectors vs braces

I am assuming that we adopt the `Vec` vs `~[T]` proposal that
[originated on Reddit][reddit]. The basic idea is to have the builtin
vector notation `[T]` be used for *fixed-length vectors*, whereas
growable vectors would be implemented with a library type like
`Vec<T>`. This slices the gordian knot that, to be growable, you need
a pointer, length, *and* capacity (hence `sizeof::<~[T]>()` would be 3
words) but otherwise a pointer and a length will suffice (hence
`sizeof::<&[T]>()` would be 2 words). Since `~[T]` would not be
growable, all "pointers-to-`[T]`" can be 2 words in length.

### Interpreting DSTs as existential types

Informally, a type like `[T]` means "0 or more instances of `T` laid
out sequentially in memory". Formally, we can describe that type like
`exists N. [T, ..N]` -- this is called an *existential type* and it
means "this memory can be described as the type `[T, ..N]` for some
value of `N`, but we don't know what that value of `N` is".

For now, I'm going to limit my discussion to vector types, because I
think the interactions are more clear, but everything applies equally
well to "trait types". For example, the type `Trait` can be described
as `exists T:Trait. T`, which is read "an instance of some type `T`
that implements `Trait`, but we don't know what that type `T` is".

Anyway, so back to vector types. Now imagine that we have a value
`slice` of type `&[T]` -- armed with existential types, we can
interpret this sa `&(exists N. [T, ..N])`. That is, "a borrowed
pointer to some memory containing some number of `T` instances". Of
course, before we can do anything useful with `slice`, we kind of need
to know how many instances of `T` are present: otherwise if we had an
expression like `slice[i]`, we'd have no way to know whether the index
`i` was in bounds or not.

To address this problem, we say that pointers to a DST (i.e., `&[T]`,
`~[T]`, and `*[T]`) are all *fat pointers*, meaning that they are
represented as two words: the data pointer and a length. We also
impose limitations that ensures that DSTs only appear behind one of
their built-in pointer types.

This does not mean that you will never see a DST anyplace else.  For
example, I could write a struct definition like `RC` (for
reference-counted data):

    struct RC<T> {
        priv data: *T,
        priv ref_count: uint,
    }
    
Now, a type like `RC<[int]>` would be legal -- this is because, when
the structure definition is "expanded out", the DST `[int]` appears
behind a `*` sigil (i.e., the type of `data` will be `*[int]`).

This setup implies that a type like `RC<[int, ..3]>` and a type like
`RC<[int]>` will have different sizes; we'll see later that this is a
bit of a complication in some regards. The reason that the sizes are
different is that `[int, ..3]` has a statically known size, and hence
`*[int, ..3]` is a thin pointer. This means that `RC<[int, ..3]>` is
represented in memory as two words: `(pointer, ref_count)`. `[int]`,
in contrast, requires a fat pointer, and thus the layout of
`RC<[int]>` is `((pointer, length), ref_count)`.

### Constructing instances of DSTs via coercion

So how do we get an instance of a type that includes a DST? Let's
start by discussing `~[int]` and then extend to `RC<[int]>`.

My preferred approach is to extend the "casting" approach that we use
for creating objects. For now, let me just discuss this in terms of
the built-in

Recall that an object type like `~Writer` is creating by
repackaging an existing pointer of some type `~Foo`, where `Foo`
implements `Writer`, with a vtable. In other words, we convert the
static knowledge of the precise type (`Foo`) into dynamic knowledge
(the vtable).

You can imagine using a similar process to obtain a `~[int]`. For
example, suppose we created a vector `v` like `v = ~[1, 2, 3]` -- this
would have type `~[int, ..3]`. This vector `v` could then be coerced
into a `~[int]` by "forgetting" the length and moving it to a dynamic
value. That is, our thin pointer `v` can be converted into a fat
poiner `(v, 3)`. This is exactly analogous to the object creation
case: the static knowledge about the length has been moved into a
dynamic value.

Using this coercion approach addresses one of the annoying
inconsistencies we suffer with today. That is, today, the expression
`~[1, 2, 3]` allocates a `~[int]` of length 3, but the expression
`~([1, 2, 3])` allocates a `~[int, ..3]`. That is, there is a special
case in the parser where `~[...]` is not treated as the composition of
the `~` operator with a `[...]` expression but rather as a thing in
and of itself. This is consistent with our current approach to the
types, where `~[int]` is a single, indivisible unit, but it is not
particularly consistent with a DST approach, nor it is particularly
elegant.

Another problem with the current "special allocation form" approach is
that it doesn't extend to objects, unless we want to force object
creation to allocate a new pointer. That was how we used to do things,
but we found that re-packaging an existing pointer is much cleaner and
opens up more coding patterns. (For example, I could take as input an
`&[int, ..3]` and then pass it to a helper routine that expects a
`&[int]`.)

### Extending coercion to user-defined smart pointer types

OK, in the previous section I showed coercion is an elegant option for
creating DSTs. But can we extend it to user-defined smart pointer
types like `RC`? The answer is mostly yes, though not without some
complications. The next post will cover an alternative interpretation
of `RC<[int]>` that works more smoothly.

The challenge here is that the memory layouts for a type like
`RC<[int, ..3]>` and a type like `RC<[int]>` are quite different.  As
I showed before, the former is simply `(data, refcount)`, but the
latter is `((data, length), refcount)`. Still, we are *coercing* the
pointer, which means that we're allowed to change the representation.
So you can imagine the compiler would emit code to move each field of
the `RC<[int, ..3]>` into its proper place, inserting the length as
needed.

For a simple type like `RC`, the compiler adaption is always possible,
but it won't work when the data for the smart pointer is itself
located behind another pointer. For example, imagine a smart pointer
that connects to some other allocation scheme, in which the allocation
is always associated with a header allocated in some fixed location:

    struct Header<unsized T> {
        header1: uint,
        header2: uint,
        payload: *T
    }
    
    struct MyAlloc<unsized T> {
        data: *Header<T>
    }

Here the `*T` which must be coerced from a `*[int, ..3]` into a
`*[int]` is located behind another pointer. We clearly can't adapt
this type.

<a name="limitation"></a>

### Limitation: DSTs must appear behind a pointer

That example is rather artificial, but it points the way at another
limitation. It's easy to imagine a special allocator that inserts
a header before the payload itself. If we attemped to model this
header explicitly in the types, it might look like the following:

    struct Header1<T> {
        header1: uint,
        header2: uint,
        payload: T     // Not *T as before, but T
    }
    
    struct MyAlloc1<T> {
        data: *Header1<T>
    }

This is basically the same as before but the type of `payload` has
changed. As before, we can't hope to coerce this type, but this is for
an even more fundamental reason: because the `T` type doesn't appear
*directly* behind a `*` pointer, it couldn't even be instantiated with
an `unsized` type to begin with.

This same principle extends to another use case, one where DSTs seem
like they offer a good approach, but in fact they do not. A common C
idiom is to have a structure that is coupled with an array; because
the length of this array does not change, the structure and the array
are allocated in one chunk. As an example, let's look briefly at
functional trees, where the shape doesn't change once the trees are
construted; in such a case, we might want to allocate the node and its
array of children all together.

There are many ways to encode this in C but this is my personal
preferred one, because it is quite explicit:

    struct Tree {
        int value;
        int num_children;
    }
    Tree **children(Tree *t) {
        return (Tree**) (t + 1);
    }
    
Whenever we allocate a new tree node, we make sure to allocate
enough space not only for the `Tree` fields but for the array
of children:

    Tree *new_tree(int value, int num_children) {
        size_t children_size = sizeof(Tree*) * num_children;
        size_t parent_size = sizeof(Tree);
        Tree *parent = (Tree*) malloc(parent_size + children_size);
        parent->value = value;
        parent->num_children = num_children;
        parentset(children(parent), 0, children_size);
        return parent;
    }
    
And I can easily iterate over a subtree like so:

    int sum(Tree *parent) {
      int r = parent->value;
      for (int i = 0; i < parent->num_children; i++)
        sum(children(parent)[i]);
    }
    
This is all nice but of course horribly unsafe. Can we create a safe
Rust equivalent?

You might at first think that I could write a type like:

    struct Tree {
        value: uint,
        num_children: uint,
        children: [RC<Tree>], // Refcounting works great for trees!
    }

But of course this structure wouldn't be permitted, since a DST like
`[RC<Tree>]` must appear behind a pointer. And of course Rust also has
no idea that `num_children` is the length of `children`.

This is not to say that there is no way to handle this familiar C
pattern, but it's not clear how DST supports it. The next scheme I
discuss offers a clearer path.

### Impls and DSTs

One big argument in favor of DST is that it permits impls over types
like `[T]` and `Trait`. This promises to eliminate a lot of
boilerplate.  But when I looked into it in more detail, I found the
story wasn't quite that simple.

#### Implementing for vector types is not that useful.

In my initial post, I gave the example of implementing `ToStr`,
pointing out that without DST, you need a lot of impls to handle the
"boilerplate" cases:

    impl<T:ToStr> ToStr for ~T { ... }
    impl<'a, T:ToStr> ToStr for &'a T { ... }
    impl<T:ToStr> ToStr for ~[T] { ... }
    impl<'a, T:ToStr> ToStr for &'a [T] { ... }
    
Whereas with DST things are more composable:

    impl<T:ToStr> ToStr for ~T { ... }
    impl<'a, T:ToStr> ToStr for &'a T { ... }
    impl<T:ToStr+Sized> ToStr for [T] { ... }

This point is still valid, but the question is, how far does this get
you? When I started experimenting with other traits, I found that
implementing on `[T]` often didn't work out so well.

For example, consider the `Map` trait:

    trait Map<K,V> {
        fn insert(&mut self, key: K, value: V);
        fn get<'a>(&'a self, key: K) -> &'a V;
    }

Imagine I wanted to implement the `Map` trait on association lists
(vector of pairs). I'd prefer to implement on the type `[(K,V)]`
because that would 

    impl<K:Eq,V> Map<K,V> for [(K,V)] {
        fn insert(&mut self, key: K, value: V) {
            // Here: self has type `&mut [(K,V)]`
            self.push((key, value)); // ERROR.
        }
        fn get<'a>(&'a self, key: K) -> &'a V {
            // Here: self has type `&[(K,V)]`
            for &(ref k, ref v) in self.iter() {
                if k == key { return v; }
            }
            fail!("Bad key");
        }
    }

The problem here lies in the `insert()` method, where I find that I
cannot push onto a slice.

#### But implementing for object types is useful.

On the other hand, because able to write an impl over a type like
`Trait` is quite useful. Let me elaborate. Currently an object type
like `&Trait` or `~Trait` is not automatically considered to implement
the interface `Trait`. This is because it is not always
possible. Consider the following example:

    trait Message {
        fn send(~self);
        fn increment(&mut self);
        fn read(&self) -> int;
    }

Now imagine that we were trying to implement this trait for an object
type such as `&Message`. We're going to run into problems because the
object type bakes in a particular pointer type -- in this case, `&` --
and thus we are not able to implement the methods `send()` or
`increment()`:

    impl Message for &Message {
        fn send(~self) {
            // Argh! `self` has type `~&Message`, but I need
            // a `~Message`.
        }
        fn increment(&mut self) {
            // Argh! `self` has type `&mut &Message`, but I need
            // an `&mut Message`.
        }
        fn read(&self) -> int {
            // OK, `self` has type `&&Message`, I can
            // transform that to an `&Message` and call `read()`:
            (*self).read();
        }
    }

Thanks to inherited mutability, what would *work* is to implement `Message`
for `~Message`:

    impl Message for ~Message {
        fn send(~self) {
            // OK, `self` has type `~~Message`. A bit silly but workable.
            (*self).send()
        }
        fn increment(&mut self) {
            // `self` has type `&mut ~Message`. Inherited mutability
            // implies that the `~Message` itself is thus mutable.
            (*self).increment();
        }
        fn read(&self) -> int {
            // `self` has type `&~Message`. We can read it.
            (*self).read();
        }
    }

Note that while this will compile, the type of `send()` is rather
inefficient.  We wind up with a double allocation. (I leave as an
exercise to the reader to imagine what will happen when we extend
`self` types to include things like `self: RC<Self>` and so on.)

If we are limited to implementing traits for object types, then, I
think one must be careful when designing traits to be used as objects.
You should avoid mixing sigils and instead have a series of base
traits that are combined. And you should avoid `~self` and prefer by-value
self (modulo [issue 10672][10672]).

    trait ReadMessage {
        fn read(&self) -> int;
    }
    trait WriteMessage { 
        fn increment(&mut self);
    }
    trait Message : ReadMessage+WriteMessage {
        fn send(self);
    }

    
Now we can implement `ReadMessage` for `&Message`, `WriteMessage` for
`&mut Message`, and `Message` for `~Message` (or other smart pointer
types that convey ownership), no problem.

#### DST offers a way out

Alternatively, under a DST system, we could implement the original
`Message` trait once for all object types:

    impl Message for Message {
        fn send(~self) { /* self: ~Message, OK! */ }
        fn increment(&mut self) { /* self: &mut Message, OK! */ }
        fn read(&self) -> int { /* self: &Message, OK! */ }
    }

We could probably just have the compiler implement this automatically,
even. One catch is that we could not support a by-value self method
like `fn send(self)`. This is mildly hostile to user-defined smart
pointers since ownership transfer via object type methods would really
be limited to `~` pointers.

### Conclusion

None yet, wait for the thrilling part 2!
    
[10672]: https://github.com/mozilla/rust/issues/10672
[reddit]: http://www.reddit.com/r/rust/comments/1r082g/meetingweekly20131119_static_linking_wildcards/
[part2]: {{ site.baseurl }}/blog/2013/11/26/thoughts-on-dst-2/
[part3]: {{ site.baseurl }}/blog/2013/11/26/thoughts-on-dst-3/
[part4]: {{ site.baseurl }}/blog/2013/12/02/thoughts-on-dst-4/
