---
date: "2021-10-06T00:00:00Z"
slug: dyn-async-traits-part-3
title: Dyn async traits, part 3
---

In the previous "dyn async traits" posts, I talked about how we can think about the compiler as synthesizing an impl that performed the dynamic dispatch. In this post, I wanted to start explore a theoretical future in which this impl was written manually by the Rust programmer. This is in part a thought exercise, but it’s also a possible ingredient for a future design: if we could give programmers more control over the “impl Trait for dyn Trait” impl, then we could enable a lot of use cases.

### Example

For this post, `async fn` is kind of a distraction. Let’s just work with a simplified `Iterator` trait:

```rust
trait Iterator {
    type Item;
    fn next(&mut self) -> Option<Self::Item>;
}
```

As we discussed in the previous post, the compiler today generates an impl that is something like this:

```rust
impl<I> Iterator for dyn Iterator<Item = I> {
    type Item = I;
    fn next(&mut self) -> Option<I> {
        type RuntimeType = ();
        let data_pointer: *mut RuntimeType = self as *mut ();
        let vtable: DynMetadata = ptr::metadata(self);
        let fn_pointer: fn(*mut RuntimeType) -> Option<I> =
            __get_next_fn_pointer__(vtable);
        fn_pointer(data)
    }
}
```

This code draws on the APIs from [RFC 2580], along with a healthy dash of “pseduo-code”. Let’s see what it does:

[RFC 2580]: https://rust-lang.github.io/rfcs/2580-ptr-meta.html

#### Extracting the data pointer

```rust
type RuntimeType = ();
let data_pointer: *mut RuntimeType = self as *mut ();
```

Here, `self` is a wide pointer of type `&mut dyn Iterator<Item = I>`. The rules for `as` state that casting a wide pointer to a thin pointer drops the metadata[^ugh], so we can (ab)use that to get the data pointer. Here I just gave the pointer the type `*mut RuntimeType`, which is an alias for `*mut ()` — i.e., raw pointer to something. The type alias `RuntimeType` is meant to signify “whatever type of data we have at runtime”. Using `()` for this is a hack; the “proper” way to model it would be with an existential type. But since Rust doesn’t have those, and I’m not keen to add them if we don’t have to, we’ll just use this type alias for now.

[^ugh]: I don’t actually like these rules, which have bitten me a few times. I think we should introduce an accessor function, but I didn’t see one in [RFC 2580] — maybe I missed it, or it already exists.

#### Extracting the vtable (or `DynMetadata`)

```rust
let vtable: DynMetadata = ptr::metadata(self);
```

The [`ptr::metadata`] function was added in [RFC 2580]. Its purpose is to extract the “metadata” from a wide pointer. The type of this metadata depends on the type of wide pointer you have: this is determined by the [`Pointee`] trait[^noreferent]. For `dyn` types, the metadata is a [`DynMetadata`], which just means “pointer to the vtable”. In today’s APIs, the [`DynMetadata`] is pretty limited: it lets you extract the size/alignment of the underlying `RuntimeType`, but it doesn’t give any access to the actual function pointers that are inside.

[`ptr::metadata`]: https://doc.rust-lang.org/std/ptr/fn.metadata.html
[`Pointee`]: https://doc.rust-lang.org/std/ptr/trait.Pointee.html
[`DynMetadata`]: https://doc.rust-lang.org/std/ptr/struct.DynMetadata.html

[^ynoreferent]: I wish that this was called “referent”. Ever since I learned that word a few years ago I have found it so elegant. But I admit that `Pointee` is both more obvious and kind of hilarious, and besides “referent” seems to simply *references* (which I consider to be safe things like `&` or `&mut`, as distinguished from mere *pointers*).

#### Extracting the function pointer from the vtable

```rust
let fn_pointer: fn(*mut RuntimeType) -> Option<I> = 
    __get_next_fn_pointer__(vtable);
```

Now we get to the pseudocode. *Somehow*, we need a way to get the fn pointer out from the vtable. At runtime, the way this works is that each method has an assigned offset within the vtable, and you basically do an array lookup; kind of like `vtable.methods()[0]`, where `methods()` returns a array `&[fn()]` of function pointers. The problem is that there’s a lot of “dynamic typing” going on here: the signature of each one of those methods is going to be different. Moreover, we’d like some freedom to change how vtables are laid out. For example, the ongoing (and awesome!) work on dyn upcasting by [Charles Lew][crlf0710] has required modifying our [vtable layout], and I expect further modification as we try to support `dyn` types with multiple traits, like `dyn Debug + Display`.

[crlf0710]: https://github.com/crlf0710
[duci]: https://rust-lang.github.io/dyn-upcasting-coercion-initiative/design-discussions/
[vtable layout]: https://rust-lang.github.io/dyn-upcasting-coercion-initiative/design-discussions/vtable-layout.html

So, for now, let’s just leave this as pseudocode. Once we’ve finished walking through the example, I’ll return to this question of how we might model `__get_next_fn_pointer__` in a forwards compatible way.

One thing worth pointing out: the type of `fn_pointer` is a `fn(*mut RuntimeType) -> Option<I>`. There are two interesting things going on here:

* The argument has type `*mut RuntimeType`: using the type alias indicates that this function is known to take a single pointer (in fact, it’s a reference, but those have the same layout). This pointer is expected to point to the same runtime data that `self` points at — we don’t know what it is, but we know that they’re the same. This works because `self` paired together a pointer to some data of type `RuntimeType` along with a vtable of functions that expect `RuntimeType` references.[^ub]
* The return type is `Option<I>`, where `I` is the item type: this is interesting because although we don’t know statically what the `Self` type is, we *do* know the `Item` type. In fact, we will generate a distinct copy of this impl for every kind of item. This allows us to easily pass the return value.

[^ub]: If you used unsafe code to pair up a random pointer with an unrelated vtable, then hilarity would ensue here, as there is no runtime checking that these types line up.

#### Calling the function

```rust
fn_pointer(data)
```

The final line in the code is very simple: we call the function! It returns an `Option<I>` and we can return that to our caller.

### Returning to the pseudocode

We relied on one piece of pseudocode in that imaginary impl:

```rust
let fn_pointer: fn(*mut RuntimeType) -> Option<I> = 
    __get_next_fn_pointer__(vtable);
```

So how could we possibly turn `__get_next_fn_pointer__` from pseudocode into real code? There are two things worth noting:

* First, the name of this function already encodes the method we want (`next`). We probably don’t want to generate an infinite family of these “getter” functions.
* Second, the signature of the function is specific to the method we want, since it returns a `fn` type(`fn *mut RuntimeType) -> Option<I>`) that encodes the signature for `next` (with the self type changed, of course). This seems better than just returning a generic signature like `fn()` that must be cast manually by the user; less opportunity for error.

### Using zero-sized fn types as the basis for an API

One way to solve these problems would be to build on the trait system. Imagine there were a type for every method, let’s call it `A`, and that this type implemented a trait like `AssociatedFn`:

```rust
trait AssociatedFn {
    // The type of the associated function, but as a `fn` pointer
    // with the self type erased. This is the type that would be
    // encoded in the vtable.
    type FnPointer;

    … // maybe other things
}
```

We could then define a generic “get function pointer” function like so:

```rust
fn associated_fn<A>(vtable: DynMetadata) -> A::FnPtr
where
    A: AssociatedFn
```

Now instead of `__get_next_fn_pointer__`, we can write 

```rust
type NextMethodType =  /* type corresponding to the next method */;
let fn_pointer: fn(*mut RuntimeType) -> Option<I> = 
   associated_fn::<NextMethodType>(vtable);
```

Ah, but what is this `NextMethodType`? How do we *get* the type for the next method? Presumably we’d have to introduce some syntax, like `Iterator::item`.

### Related concept: zero-sized fn types

This idea of a type for associated functions is *very close* (but not identical) to an already existing concept in Rust: zero-sized function types. As you may know, the type of a Rust function is in fact a special zero-sized type that uniquely identifies the function. There is (presently, anyway) no syntax for this type, but you can observe it by printing out the size of values ([playground](https://play.rust-lang.org/?version=stable&mode=debug&edition=2018&gist=e30569b1f9e4a36e436b7335627dd1ba)):

```rust
fn foo() { }

// The type of `f` is not `fn()`. It is a special, zero-sized type that uniquely
// identifies `foo`
let f = foo;
println!(“{}”, sizeof_value(&f)); // prints 0

// This type can be coerced to `fn()`, which is a function pointer
let g: fn() = f;
println!(“{}”, sizeof_value(&g)); // prints 8
```

There are also types for functions that appear in impls. For example, you could get an instance of the type that represents the `next` method on `vec::IntoIter<u32>` like so:

```rust
let x = <vec::IntoIter<u32> as Iterator>::next;
println!(“{}”, sizeof_value(&f)); // prints 0
```

### Where the zero-sized types don’t fit

The existing zero-sized types can’t be used for our “associated function” type for two reasons:

* You can’t name them! We can fix this by adding syntax.
* There is no zero-sized type for a *trait function independent of an impl*.

The latter point is subtle[^blog]. Before, when I talked about getting the type for a function from an impl, you’ll note that I gave a fully qualified function name, which specified the `Self` type precisely:

[^blog]: And, in fact, I didn’t see it until I was writing this blog post!

```rust
let x = <vec::IntoIter<u32> as Iterator>::next;
//       ^^^^^^^^^^^^^^^^^^ the Self type
```

But what we want in our impl is to write code that doesn’t know what the Self type is! So this type that exists in the Rust type system today isn’t quite what we need. But it’s very close.

### Conclusion

I’m going to leave it here. Obviously, I haven’t presented any kind of final design, but we’ve seen a lot of tantalizing ingredients:

* Today, the compiler generates a `impl Iterator for dyn Iterator` that extract functions from a vtable and invokes them by magic.
* But, using the APIs from [RFC 2580], you can *almost* write the by hand. What is missing is a way to extract a function pointer from a vtable, and what makes *that* hard is that we need a way to identify the function we are extracting
* We have zero-sized types that represent functions today, but we don’t have a way to name them, and we don’t have zero-sized types for functions in traits, only in impls.

Of course, all of the stuff I wrote here was just about normal functions. We still need to circle back to async functions, which add a few extra wrinkles. Until next time!

### Footnotes