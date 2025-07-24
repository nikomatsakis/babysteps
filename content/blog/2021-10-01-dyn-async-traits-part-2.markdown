---
layout: post
title: Dyn async traits, part 2
date: 2021-10-01T11:56:00-0400
series:
- "Dyn async traits"
---

In the [previous post], we uncovered a key challenge for `dyn` and async traits: the fact that, in Rust today, `dyn` types have to specify the values for all associated types. This post is going to dive into more background about how dyn traits work today, and in particular it will talk about where that limitation comes from.

[previous post]: {{< baseurl >}}/blog/2021/09/30/dyn-async-traits-part-1/

### Today: Dyn traits implement the trait

In Rust today, assuming you have a “dyn-safe” trait `DoTheThing `, then the type `dyn DoTheThing ` implements `Trait`. Consider this trait:

```rust
trait DoTheThing {
	fn do_the_thing(&self);
}

impl DoTheThing for String {
    fn do_the_thing(&self) {
        println!(“{}”, self);
    }
}
```

And now imagine some generic function that uses the trait:

```rust
fn some_generic_fn<T: ?Sized + DoTheThing>(t: &T) {
	t.do_the_thing();
}
```

Naturally, we can call `some_generic_fn` with a `&String`, but — because `dyn DoTheThing` implements `DoTheThing` — we can also call `some_generic_fn` with a `&dyn DoTheThing`:

```rust
fn some_nongeneric_fn(x: &dyn DoTheThing) {
    some_generic_fn(x)
}
```

### Dyn safety, a mini retrospective

Early on in Rust, we debated whether `dyn DoTheThing` ought to implement the trait `DoTheThing` or not. This was, indeed, the origin of the term “dyn safe” (then called “object safe”). At the time, I argued in favor of the current approach: that is, creating a binary property. Either the trait was dyn safe, in which case `dyn DoTheThing` implements `DoTheThing`, or it was not, in which case `dyn DoTheThing` is not a legal type. I am no longer sure that was the right call.

What I liked at the time was the idea that, in this model, whenever you see a type like `dyn DoTheThing`, you know that you can use it like any other type that implements `DoTheThing`. 

Unfortunately, in practice, the type `dyn DoTheThing` is not comparable to a type like `String`. Notably, `dyn` types are not sized, so you can’t pass them around by value or work with them like strings. You must instead always pass around some kind of *pointer* to them, such as a `Box<dyn DoTheThing>` or a `&dyn DoTheThing`. This is “unusual” enough that we make you *opt-in* to it for generic functions, by writing `T: ?Sized`. 

What this means is that, in practice, generic functions don’t accept `dyn` types “automatically”, you have to design *for* dyn explicitly. So a lot of the benefit I envisioned didn’t come to pass.

### Static versus dynamic dispatch, vtables

Let’s talk for a bit about dyn safety and where it comes from. To start, we need to explain the difference between *static dispatch* and *virtual (dyn) dispatch*. Simply put, static dispatch means that the compiler knows which function is being called, whereas dyn dispatch means that the compiler doesn’t know. In terms of the CPU itself, there isn’t much difference. With static dispatch, there is a “hard-coded” instruction that says “call the code at this address”[^link]; with dynamic dispatch, there is an instruction that says “call the code whose address is in this variable”. The latter can be a bit slower but it hardly matters in practice, particularly with a successful prediction.

[^link]:  Modulo dynamic linking.

When you use a `dyn` trait, what you actually have is a *vtable*. You can think of a vtable as being a kind of struct that contains a collection of function pointers, one for each method in the trait. So the vtable type for the `DoTheThing` trait might look like (in practice, there is a bit of extra data, but this is close enough for our purposes):

```rust
struct DoTheThingVtable {
    do_the_thing: fn(*mut ())
}
```

Here the `do_the_thing` method has a corresponding field. Note that the type of the first argument *ought* to be `&self`, but we changed it to `*mut ()`. This is because the whole idea of the vtable is that you don’t know what the `self` type is, so we just changed it to “some pointer” (which is all we need to know).

When you create a vtable, you are making an instance of this struct that is tailored to some particular type. In our example, the type `String` implements `DoTheThing`, so we might create the vtable for `String` like so:

```rust
static Vtable_DoTheThing_String: &DoTheThingVtable = &DoTheThingVtable {
    do_the_thing: <String as DoTheThing>::do_the_thing as fn(*mut ())
    //            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    //            Fully qualified reference to `do_the_thing` for strings
};
```

You may have heard that a `&dyn DoTheThing` type in Rust is a *wide pointer*. What that means is that, at runtime, it is actually a pair of *two* pointers: a data pointer and a vtable pointer for the `DoTheThing` trait. So `&dyn DoTheThing` is roughly equivalent to:

```
(*mut (), &’static DoTheThingVtable)
```

When you cast a `&String` to a `&dyn DoTheThing`, what actually happens at runtime is that the compiler takes the `&String` pointer, casts it to `*mut ()`, and pairs it with the appropriate vtable. So, if you have some code like this:

```rust
let x: &String = &”Hello, Rustaceans”.to_string();
let y: &dyn DoTheThing = x;
```

It winds up “desugared” to something like this:

```rust
let x: &String = &”Hello, Rustaceans”.to_string();
let y: (*mut (), &’static DoTheThingVtable) = 
    (x as *mut (), Vtable_DoTheThing_String);
```

### The dyn impl

We’ve seen how you create wide pointers and how the compiler represents vtables. We’ve also seen that, in Rust, `dyn DoTheThing` implements `DoTheThing`. You might wonder how that works. Conceptually, the compiler generates an impl where each method in the trait is implemented by extracting the function pointer from the vtable and calling it:

```rust
impl DoTheThing for dyn DoTheThing {
    fn do_the_thing(self: &dyn DoTheThing) {
        // Remember that `&dyn DoTheThing` is equivalent to
        // a tuple like `(*mut (), &’static DoTheThingVtable)`:
        let (data_pointer, vtable_pointer) = self;

        let function_pointer = vtable_pointer.do_the_thing;
        function_pointer(data_pointer);
    }
}
```

In effect, when we call a generic function like `some_generic_fn` with `T = dyn DoTheThing`, we monomorphize that call exactly like any other type. The call to `do_the_thing` is dispatched against the impl above, and it is *that special impl* that actually does the dynamic dispatch. Neat.

### Static dispatch permits monomorphization

Now that we’ve seen how and when vtables are constructed, we can talk about the rules for dyn safety and where they come from. One of the most basic rules is that a trait is only dyn-safe if it contains no generic methods (or, more precisely, if its methods are only generic over lifetimes, not types). The reason for this rule derives directly from how a vtable works: when you construct a vtable, you need to give a single function pointer for each method in the trait (or, perhaps, a finite set of function pointers). The problem with generic methods is that there is no single function pointer for them: you need a different pointer for each type that they’re applied to. Consider this example trait, `PrintPrefixed`:

```rust
trait PrintPrefixed {
    fn prefix(&self) -> String;
    fn apply<T: Display>(&self, t: T);
}

impl PrintPrefixed for String {
    fn prefix(&self) -> String {
        self.clone()
    }
    fn apply<T: Display>(&self, t: T) {
        println!(“{}: {}”, self, t);
    }
}
```

What would a vtable for `String as PrintPrefixed` look like? Generating a function pointer for `prefix` is no problem, we can just use `<String as PrintPrefixed>::prefix`. But what about `apply`? We would have to include a function pointer for `<String as PrintPrefixed>::apply<T>`, but we don’t know yet what the `T` is!

In contrast, with static dispatch, we don’t have to know what `T` is until the point of call. In that case, we can generate just the copy we need.

### Partial dyn impls

The previous point shows that a trait can have *some* methods that are dyn-safe and some methods that are not. In current Rust, this makes the entire trait be “not dyn safe”, and this is because there is no way for us to write a complete `impl PrintPrefixed for dyn PrintPrefixed`:

```rust
impl PrintPrefixed for dyn PrintPrefixed {
    fn prefix(&self) -> String {
        // For `prefix`, no problem:
        let prefix_fn = /* get prefix function pointer from vtable */;
        prefix_fn(…);
    }
    fn apply<T: Display>(&self, t: T) {
        // For `apply`, we can’t handle all `T` types, what field to fetch?
        panic!(“No way to implement apply”)
    }
}
```

Under the alternative design that was considered long ago, we could say that a `dyn PrintPrefixed` value is always legal, but `dyn PrintPrefixed` only implements the `PrintPrefixed` trait if all of its methods (and other items) are dyn safe. Either way, if you had a `&dyn PrintPrefixed`, you could call `prefix`. You just wouldn’t be able to use a `dyn PrintPrefixed` with generic code like `fn foo<T: ?Sized + PrintPrefixed>`.

(We’ll return to this theme in future blog posts.)

If you’re familiar with the “special case” around trait methods that require `where Self: Sized`, you might be able to see where it comes from now. If a method has a `where Self: Sized` requirement, and we have an impl for a type like `dyn PrintPrefixed`, then we can see that this impl could never be called, and so we can omit the method from the impl (and vtable) altogether. This is awfully similar to saying that `dyn PrintPrefixed` is always legal, because it means that there only a subset of methods that can be used via virtual dispatch. The difference is that `dyn PrintPrefixed: PrintPrefixed` still holds, because we know that generic code won’t be able to call those “non-dyn-safe” methods, since generic code would have to require that `T: ?Sized`.

### Associated types and dyn types

We began this saga by talking about associated types and `dyn` types. In Rust today, a dyn type is required to specify a value for each associated type in the trait. For example, consider a simplified `Iterator` trait:

```rust
trait Iterator {
    type Item;

    fn next(&mut self) -> Option<Self::Item>;
}
```

This trait is dyn safe, but if you actually have a `dyn` in practice, you would have to write something like `dyn Iterator<Item = u32>`. The `impl Iterator for dyn Iterator` looks like:

```
impl<T> Iterator for dyn Iterator<Item = T> {
    type Item = T;
    
    fn next(&mut self) -> Option<T> {
        let next_fn = /* get next function from vtable */;
        return next_fn(self);
    }
}
```

Now you can see why we require all the associated types to be part of the `dyn` type — it lets us write a complete impl (i.e., one that includes a value for each of the associated types).

### Conclusion

We covered a lot of background in this post:

* Static vs dynamic dispatch, vtables
* The origin of dyn safety, and the possibility of “partial dyn safety”
* The idea of a synthesized `impl Trait for dyn Trait`

