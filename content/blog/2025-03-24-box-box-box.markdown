---
title: "Dyn async traits, part 10: Box box box"
date: 2025-03-24T19:00:41Z
series:
- "Dyn async traits"
---

This article is a slight divergence from my [Rust in 2025] series. I wanted to share my latest thinking about how to support `dyn Trait` for traits with async functions and, in particular how to do so in a way that is compatible with the [soul of Rust][sor].

[Rust in 2025]: {{< baseurl >}}/series/rust-in-2025/

[sor]: {{< baseurl >}}/blog/2022/09/18/dyn-async-traits-part-8-the-soul-of-rust/

[^afidt]: aka, Async fns in dyn trait, or AFIDT.

## Background: why is this hard?

Supporting `async fn` in dyn traits is a tricky balancing act. The challenge is reconciling two key things people love about Rust: its ability to express high-level, productive code *and* its focus on revealing low-level details. When it comes to async function in traits, these two things are in direct tension, as I explained in [my first blog post in this series]({{< baseurl >}}/blog/2021/09/30/dyn-async-traits-part-1/) -- written almost four years ago! (Geez.)

To see the challenge, consider this example `Signal` trait:

```rust
trait Signal {
    async fn signal(&self);
}
```

In Rust today you can write a function that takes an `impl Signal` and invokes `signal` and everything feels pretty nice:

```rust
async fn send_signal_1(impl_trait: &impl Signal) {
    impl_trait.signal().await;
}
```

But what I want to write that same function using a `dyn Signal`? If I write this...

```rust
async fn send_signal_2(dyn_trait: &dyn Signal) {
    dyn_trait.signal().await; //   ---------- ERROR
}
```

...I get an error. Why is that? The answer is that the compiler needs to know what kind of future is going to be returned by `signal` so that it can be awaited. At minimum it needs to know how *big* that future is so it can allocate space for it[^alloca]. With an `impl Signal`, the compiler knows exactly what type of signal you have, so that's no problem: but with a `dyn Signal`, we don't, and hence we are stuck.

[^alloca]: Side note, one interesting thing about Rust's async functions is that there size must be known at compile time, so we can't permit alloca-like stack allocation.

The most common solution to this problem is to *box* the future that results. The [`async-trait` crate](https://crates.io/crates/async-trait), for example, transforms `async fn signal(&self)` to something like `fn signal(&self) -> Box<dyn Future<Output = ()> + '_>`. But doing that at the trait level means that we add overhead even when you use `impl Trait`; it also rules out some applications of Rust async, like embedded or kernel development.

So the name of the game is to find ways to let people use `dyn Trait` that are both convenient *and* flexible. And that turns out to be pretty hard!

## The "box box box" design in a nutshell

I've been digging back into the problem lately in a series of conversations with [Michal Goulet (aka, compiler-errors)](https://github.com/compiler-errors) and it's gotten me thinking about a fresh approach I call "box box box".

The "box box box" design starts with the [call-site selection]({{< baseurl >}}/blog/2022/09/21/dyn-async-traits-part-9-callee-site-selection/) approach. In this approach, when you call `dyn_trait.signal()`, the type you get back is a `dyn Future` -- i.e., an unsized value. This can't be used directly. Instead, you have to allocate storage for it. The easiest and most common way to do that is to box it, which can be done with the new `.box` operator:

```rust
async fn send_signal_2(dyn_trait: &dyn Signal) {
    dyn_trait.signal().box.await;
    //        ------------
    // Results in a `Box<dyn Future<Output = ()>>`.
}
```

This approach is fairly straightforward to explain. When you call an async function through `dyn Trait`, it results in a `dyn Future`, which has to be stored somewhere before you can use it. The easiest option is to use the `.box` operator to store it in a box; that gives you a `Box<dyn Future>`, and you can await that.

But this simple explanation belies two fairly fundamental changes to Rust. First, it changes the relationship of `Trait` and `dyn Trait`. Second, it introduces this `.box` operator, which would be the first stable use of the `box` keyword[^br]. It seems odd to introduce the keyword just for this one use -- where else could it be used?

[^br]: The box keyword is in fact reserved already, but it's never been used in stable Rust.

As it happens, I think both of these fundamental changes could be very good things. The point of this post is to explain what doors they open up and where they might take us.

## Change 0: Unsized return value methods

Let's start with the core proposal. For every trait `Foo`, we add inherent methods[^errs] to `dyn Foo` reflecting its methods:

* For every fn `f` in `Foo` that is [dyn compatible][], we add a `<dyn Foo>::f` that just calls `f` through the vtable.
* For every fn `f` in `Foo` that returns an `impl Trait` value but would otherwise be [dyn compatible][] (e.g., no generic arguments[^apit], no reference to `Self` beyond the `self` parameter, etc), we add a `<dyn Foo>::f` method that is defined to return a `dyn Trait`.
    * This includes async fns, which are sugar for functions that return `impl Future`.

[^errs]: Hat tip to Michael Goulet (compiler-errors) for pointing out to me that we can model the virtual dispatch as inherent methods on `dyn Trait` types. Before I thought we'd have to make a more invasive addition to MIR, which I wasn't excited about since it suggested the change was more far-reaching.

[^apit]: In the future, I think we can expand this definition to include some limited functions that use `impl Trait` in argument position, but that's for a future blog post.

In fact, method dispatch *already* adds "pseudo" inherent methods to `dyn Foo`, so this wouldn't change anything in terms of which methods are resolved. The difference is that `dyn Foo` is only allowed if all methods in the trait are dyn compatible, whereas under this proposal some non-dyn-compatible methods would be added with modified signatures.

## Change 1: Dyn compatibility

Change 0 only makes sense if it is possible to create a `dyn Trait` even though it contains some methods (e.g., async functions) that are not dyn compatible. This revisits [RFC #255][], in which we decided that the `dyn Trait` type should also implement the trait `Trait`. I was a big proponent of [RFC #255][] at the time, but I've sinced decided I was mistaken[^oops]. Let's discuss.

The two rules today that allow `dyn Trait` to implement `Trait` are as follows:

[RFC #255]: https://rust-lang.github.io/rfcs/0255-object-safety.html

1. By disallowing `dyn Trait` unless the trait `Trait` is *[dyn compatible][]*, meaning that it only has methods that can be added to a vtable.
2. By requiring that the values of all associated types be explicitly specified in the `dyn Trait`. So `dyn Iterator<Item = u32>` is legal but not `dyn Iterator` on its own.

[dyn compatible]: https://doc.rust-lang.org/reference/items/traits.html#dyn-compatibility

[^oops]: I've noticed that many times when I favor a limited version of something to achieve some aesthetic principle I wind up regretting it.

### "dyn compatibility" can be powerful

The fact that `dyn Trait` implements `Trait` is at times quite powerful. It means for example that I can write an implementation like this one:

```rust
struct RcWrapper<T: ?Sized> { r: Rc<RefCell<T>> }

impl<T> Iterator for RcWrapper<T>
where
    T: ?Sized + Iterator,
{
    type Item = T::Item;
    
    fn next(&mut self) -> Option<T::Item> {
        self.borrow_mut().next()
    }
}
```

This impl makes `RcWrapper<I>` implement `Iterator` for any type `I`, *including* dyn trait types like `RcWrapper<dyn Iterator<Item = u32>>`. Neat. 

### "dyn compatibility" doesn't truly live up to its promise

Powerful as it is, the idea of `dyn Trait` implementing `Trait` doesn't quite live up to its promise. What you really want is that you could replace any `impl Trait` with `dyn Trait` and things would work. But that's just not true because `dyn Trait` is `?Sized`. So actually you don't get a very "smooth experience". What's more, although the compiler gives you a `dyn Trait: Trait` impl, it doesn't give you impls for *references* to `dyn Trait` -- so e.g. given this trait

```rust
trait Compute {
    fn compute(&self);
}
```

If I have a `Box<dyn Compute>`, I can't give that to a function that takes an `impl Compute`

```rust
fn do_compute(i: impl Compute) {
}

fn call_compute(b: Box<dyn Compute>) {
    do_compute(b); // ERROR
}
```

To make that work, somebody has to explicitly provide an impl like

```rust
impl<I> Compute for Box<I>
where
    I: ?Sized,
{
    // ...
}
```

and people often don't.

### "dyn compatibility" can be limiting

However, the requirement that `dyn Trait` implement `Trait` can be limiting. Imagine a trait like

```rust
trait ReportError {
    fn report(&self, error: Error);
    
    fn report_to(&self, error: Error, target: impl ErrorTarget);
    //                                ------------------------
    //                                Generic argument.
}
```

This trait has two methods. The `report` method is dyn-compatible, no problem. The `report_to` method has an `impl Trait` argument is therefore generic, so it is not dyn-compatible[^notnow] (well, at least not under today's rules, but I'll get to that).

(The reason `report_to` is not dyn compatible: we need to make distinct monomorphized copies tailored to the type of the `target` argument. But the vtable has to be prepared in advance, so we don't know which monomorphized version to use.)

[^notnow]: At least, it is not `dyn` compatible under today's rules. Convievably it could be made to work but more on that later.

And yet, just because `report_to` is not dyn compatible doesn't mean that a `dyn ReportError` would be useless. What if I only plan to call `report`, as in a function like this?

```rust
fn report_all(
    errors: Vec<Error>,
    report: &dyn ReportError,
) {
    for e in errors {
        report.report(e);
    }
}
```

Rust's current rules rule out a function like this, but in practice this kind of scenario comes up quite a lot. In fact, it comes up so often that we added a language feature to accommodate it (at least kind of): you can add a `where Self: Sized` clause to your feature to exempt it from dynamic dispatch. This is the reason that [`Iterator`](https://doc.rust-lang.org/std/iter/trait.Iterator.html) can be dyn compatible even when it has a bunch of generic helper methods like [`map`](https://doc.rust-lang.org/std/iter/trait.Iterator.html#method.map) and [`flat_map`](https://doc.rust-lang.org/std/iter/trait.Iterator.html#method.flat_map).

### What does all this have to do with AFIDT?

Let me pause here, as I imagine some of you are wondering what all of this "dyn compatibility" stuff has to do with AFIDT. The bottom line is that the requirement that `dyn Trait` type implements `Trait` means that we cannot put any kind of "special rules" on `dyn` dispatch and that is not compatible with requiring a `.box` operator when you call async functions through a `dyn` trait. Recall that with our `Signal` trait, you could call the `signal` method on an `impl Signal` without any boxing:

```rust
async fn send_signal_1(impl_trait: &impl Signal) {
    impl_trait.signal().await;
}
```

But when I called it on a `dyn Signal`, I had to write `.box` to tell the compiler how to deal with the `dyn Future` that gets returned:

```rust
async fn send_signal_2(dyn_trait: &dyn Signal) {
    dyn_trait.signal().box.await;
}
```

Indeed, the fact that `Signal::signal` returns an `impl Future` but `<dyn Signal>::signal` returns a `dyn Future` already demonstrates the problem. All `impl Future` types are known to be `Sized` and `dyn Future` is not, so the type signature of `<dyn Signal>::signal` is not the same as the type signature declared in the trait. Huh.

### Associated type values are needed for dyn compatibility

Today I cannot write a type like `dyn Iterator` without specifying the value of the associated type `Item`. To see why this restriction is needed, consider this generic function:

```rust
fn drop_all<I: ?Sized + Iterator>(iter: &mut I) {
    while let Some(n) = iter.next() {
        std::mem::drop(n);
    }
}
```

If you invoked `drop_all` with an `&mut dyn Iterator` that did not specify `Item`, how could the type of `n`? We wouldn't have any idea how much space space it needs. But if you invoke `drop_all` with `&mut dyn Iterator<Item = u32>`, there is no problem. We don't know which `next` method is being called, but we know it's returning a `u32`.

### Associated type values are limiting

And yet, just as we saw before, the requirement to list associated types can be limiting. If I have a `dyn Iterator` and I only call `size_hint`, for example, then why do I need to know the `Item` type?

```rust
fn size_hint(iter: &mut dyn Iterator) -> bool {
    let sh = iter.size_hint();
}
```

But I can't write code like this today. Instead I have to make this function generic which basically defeats the whole purpose of using `dyn Iterator`:

```rust
fn size_hint<T>(iter: &mut dyn Iterator<Item = T>) -> bool {
    let sh = iter.size_hint();
}
```

If we dropped the requirement that every `dyn Iterator` type implements `Iterator`, we could be more selective, allowing you to invoke methods that don't use the `Item` associated type but disallowing those that do.

### A proposal for expanded `dyn Trait` usability

So that brings us to full proposal to permit `dyn Trait` in cases where the trait is not fully dyn compatible:

* `dyn Trait` types would be allowed for any trait.[^r2027]
* `dyn Trait` types would not require associated types to be specified.
* dyn compatible methods are exposed as inherent methods on the `dyn Trait` type. We would disallow access to the method if its signature references associated types not specified on the `dyn Trait` type.
* `dyn Trait` that specify all of their associated types would be considered to implement `Trait` if the trait is fully dyn compatible.[^dyncompatfut]

[^dyncompatfut]: I actually want to change this last clause in a future edition. Instead of having dyn compatibility be determined automically, traits would declare themselves dyn compatible, which would also come with a host of other impls. But that's worth a separate post all on its own.

[^r2027]: This part of the change is similar to what was proposed in [RFC #2027][], though that RFC was quite light on details (the requirements for RFCs in terms of precision have gone up over the years and I expect we wouldn't accept that RFC today in its current form).

[RFC #2027]: https://rust-lang.github.io/rfcs/2027-object_safe_for_dispatch.html?highlight=safety#

## The `box` keyword

> A lot of things get easier if you are willing to call malloc.
>
> -- Josh Triplett, recently.

Rust has reserved the `box` keyword since 1.0, but we've never allowed it in stable Rust. The original intention was that the term *box* would be a generic term to refer to any "smart pointer"-like pattern, so `Rc` would be a "reference counted box" and so forth. The `box` keyword would then be a generic way to allocate boxed values of any type; unlike `Box::new`, it would do "emplacement", so that no intermediate values were allocated. With the passage of time I no longer think this is such a good idea. But I *do* see a lot of value in having a keyword to ask the compiler to automatically create *boxes*. In fact, I see a *lot* of places where that could be useful.

### boxed expressions

The first place is indeed the `.box` operator that could be used to put a value into a box. Unlike `Box::new`, using `.box` would allow the compiler to guarantee that no intermediate value is created, a property called *emplacement*. Consider this example:

```rust
fn main() {
    let x = Box::new([0_u32; 1024]);
}
```

Rust's semantics today require (1) allocating a 4KB buffer on the stack and zeroing it; (2) allocating a box in the heap; and then (3) copying memory from one to the other. This is a violation of our Zero Cost Abstraction promise: no C programmer would write code like that. But if you write `[0_u32; 1024].box`, we can allocate the box up front and initialize it in place.[^opt]

[^opt]: If you [play with this on the playground](https://play.rust-lang.org/?version=stable&mode=release&edition=2024&gist=bf0b4ee4cbb13b02efc83455128110da), you'll see that the memcpy appears in the debug build but gets optimized away in this very simple case, but that can be hard for LLVM to do, since it requires reordering an allocation of the box to occur earlier and so forth. The `.box` operator could be guaranteed to work.

The same principle applies calling functions that return an unsized type. This isn't allowed today, but we'll need some way to handle it if we want to have `async fn` return `dyn Future`. The reason we can't naively support it is that, in our existing ABI, the caller is responsible for allocating enough space to store the return value and for passing the address of that space into the callee, who then writes into it. But with a `dyn Future` return value, the caller can't know how much space to allocate. So they would have to do something else, like passing in a callback that, given the correct amount of space, performs the allocation. The most common cased would be to just pass in `malloc`.

The best ABI for unsized return values is unclear to me but we don't have to solve that right now, the ABI can (and should) remain unstable. But whatever the final ABI becomes, when you call such a function in the context of a `.box` expression, the result is that the callee creates a `Box` to store the result.[^intrinsic]

[^intrinsic]: I think it would be cool to also have some kind of unsafe intrinsic that permits calling the function with other storage strategies, e.g., allocating a known amount of stack space or what have you.

### boxed async functions to permit recursion

If you try to write an async function that calls itself today, you get an error:

```rust
async fn fibonacci(a: u32) -> u32 {
    match a {
        0 => 1,
        1 => 2,
        _ => fibonacci(a-1).await + fibonacci(a-2).await
    }
}
```

The problem is that we cannot determine statically how much stack space to allocate. The solution is to rewrite to a boxed return value. This [compiles](https://play.rust-lang.org/?version=stable&mode=debug&edition=2024&gist=b36baf737a2811412e2970103fee25ee) because the compiler can allocate new stack frames as needed.

```rust
fn fibonacci(a: u32) -> Pin<Box<impl Future<Output = u32>>> {
    Box::pin(async move {
        match a {
            0 => 1,
            1 => 2,
            _ => fibonacci(a-1).await + fibonacci(a-2).await
        }
    })
}
```

But wouldn't it be nice if we could request this directly?

```rust
box async fn fibonacci(a: u32) -> u32 {
    match a {
        0 => 1,
        1 => 2,
        _ => fibonacci(a-1).await + fibonacci(a-2).await
    }
}
```

### boxed structs can be recursive

A similar problem arises with recursive structs:

```rust
struct List {
    value: u32,
    next: Option<List>, // ERROR
}
```

The compiler tells you

```
error[E0072]: recursive type `List` has infinite size
 --> src/lib.rs:1:1
  |
1 | struct List {
  | ^^^^^^^^^^^
2 |     value: u32,
3 |     next: Option<List>, // ERROR
  |                  ---- recursive without indirection
  |
help: insert some indirection (e.g., a `Box`, `Rc`, or `&`) to break the cycle
  |
3 |     next: Option<Box<List>>, // ERROR
  |                  ++++    +
```

As it suggestes, to workaround this you can introduce a `Box`:

```rust
struct List {
    value: u32,
    next: Option<Box<List>>,
}
```

This though is kind of weird because now the head of the list is stored "inline" but future nodes are heap-allocated. I personally usually wind up with a pattern more like this:

```rust
struct List {
    data: Box<ListData>
}

struct ListData {
    value: u32,
    next: Option<List>,
}
```

Now however I can't create values with `List { value: 22, next: None }` syntax and I also can't do pattern matching. Annoying. Wouldn't it be nice if the compiler just suggest adding a `box` keyword when you declare the struct:

```rust
box struct List {
    value: u32,
    next: Option<List>,
}
```

and have `List { value: 22, next: None }` automatically allocate the box for me? The ideal is that the presence of a box is now completely transparent, so I can pattern match and so forth fully transparently:

```rust
box struct List {
    value: u32,
    next: Option<List>,
}

fn foo(list: &List) {
    let List { value, next } = list; // etc
}
```

### boxed enums can be recursive *and* right-sized

Enums too cannot reference themselves. Being able to declare something like this would be really nice:

```rust
box enum AstExpr {
    Value(u32),
    If(AstExpr, AstExpr, AstExpr),
    ...
}
```

In fact, I still remember when I used Swift for the first time. I wrote a similar enum and Xcode helpfully prompted me, "do you want to declare this enum as [`indirect`][]?" I remember being quite jealous that it was such a simple edit.

[`indirect`]: https://www.hackingwithswift.com/example-code/language/what-are-indirect-enums

However, there is another interesting thing about a `box enum`. The way I imagine it, creating an instance of the enum would always allocate a fresh box. This means that the enum cannot be changed from one variant to another without allocating fresh storage. This in turn means that you could allocate that box to *exactly* the size you need for that particular variant.[^vs] So, for your `AstExpr`, not only could it be recursive, but when you allocate an `AstExpr::Value` you only need to allocate space for a `u32`, whereas a `AstExpr::If` would be a different size. (We could even start to do "tagged pointer" tricks so that e.g. `AstExpr::Value` is stored without any allocation at all.)

[^vs]: We would thus *finally* bring Rust enums to "feature parity" with OO classes! I wrote a [blog post, "Classes strike back", on this topic]({{< baseurl >}}/blog/2015/05/29/classes-strike-back/) back in 2015 (!) as part of the whole "virtual structs" era of Rust design. Deep cut!

### boxed enum variants to avoid unbalanced enum sizes

Another option would to have particular enum *variants* that get boxed but not the enum as a whole:

```rust
enum AstExpr {
    Value(u32),
    box If(AstExpr, AstExpr, AstExpr),
    ...
}
```

This would be useful in cases you *do* want to be able to overwrite one enum value with another without necessarily reallocating, but you have enum variants of widely varying size, or some variants that are recursive. A boxed variant would basically be desugared to something like the following:

```rust
enum AstExpr {
    Value(u32),
    If(Box<AstExprIf>),
    ...
}

struct AstExprIf(AstExpr, AstExpr, AstExpr);
```

clippy has a [useful lint `large_enum_variant`](https://rust-lang.github.io/rust-clippy/master/index.html#large_enum_variant) that aims to identify this case, but once the lint triggers, it's not able to offer an actionable suggestion. With the box keyword there'd be a trivial rewrite that requires zero code changes.

### box patterns and types

If we're enabling the use of `box` elsewhere, we ought to allow it in patterns:

```rust
fn foo(s: box Struct) {
    let box Struct { field } = s;
}
```

## Frequently asked questions

### Isn't it unfortunate that `Box::new(v)` and `v.box` would behave differently?

Under my proposal, `v.box` would be the preferred form, since it would allow the compiler to do more optimization. And yes, that's unfortunate, given that there are 10 years of code using `Box::new`. Not really a big deal though. In most of the cases we accept today, it doesn't matter and/or LLVM already optimizes it. In the future I do think we should consider extensions to make `Box::new` (as well as `Rc::new` and other similar constructors) be just as optimized as `.box`, but I don't think those have to block *this* proposal.

### Is it weird to special case box and not handle other kinds of smart pointers?

Yes and no. On the one hand, I would like the ability to declare that a struct is *always* wrapped in an `Rc` or `Arc`. I find myself doing things like the following all too often:

```rust
struct Context {
    data: Arc<ContextData>
}

struct ContextData {
    counter: AtomicU32,
}
```

On the other hand, `box` is very special. It's kind of unique in that it represents full ownership of the contents which means a `T` and ` Box<T>` are semantically equivalent -- there is no place you can use `T` that a `Box<T>` won't also work -- unless `T: Copy`. This is not true for `T` and `Rc<T>` or most other smart pointers.

For myself, I think we should introduce `box` now but plan to generalize this concept to other pointers later. For example I'd like to be able to do something like this...

```rust
#[indirect(std::sync::Arc)]
struct Context {
    counter: AtomicU32,
}
```

...where the type `Arc` would implement some trait to permit allocating, deref'ing, and so forth:

```rust
trait SmartPointer: Deref {
    fn alloc(data: Self::Target) -> Self;
}
```

The original plan for `box` was that it would be somehow type overloaded. I've soured on this for two reasons. First, type overloads make inference more painful and I think are generally not great for the user experience; I think they are also confusing for new users. Finally, I think we missed the boat on naming. Maybe if we had called `Rc` something like `RcBox<T>` the idea of "box" as a general name would have percolated into Rust users' consciousness, but we didn't, and it hasn't. I think the `box` keyword *now* ought to be very targeted to the `Box` type.

### How does this fit with the "soul of Rust"?

In my [soul of Rust blog post], I talked about the idea that one of the things that make Rust *Rust* is having allocation be relatively explicit. I'm of mixed minds about this, to be honest, but I do think there's value in having a property similar to `unsafe` -- like, if allocation is happening, there'll be a sign somewhere you can find. What I like about most of these `box` proposals is that they move the `box` keyword to the *declaration* -- e.g., on the struct/enum/etc -- rather than the *use*. I think this is the right place for it. The major exception, of course, is the "marquee proposal", invoking async fns in dyn trait. That's not amazing. But then... see the next question for some early thoughts.

### If traits don't have to be dyn compatible, can we make dyn compatibility opt in?

The way that Rust today detects automatically whether traits should be dyn compatible versus having it be declared is, I think, not great. It creates confusion for users and also permits quiet semver violations, where a new defaulted method makes a trait no longer be dyn compatible. It's also a source for a lot of soundness bugs over time. 

I want to move us towards a place where traits are *not* dyn compatible by default, meaning that `dyn Trait` does not implement `Trait`. We would always allow `dyn Trait` types and we would allow individual items to be invoked so long as the item itself is dyn compatible.

If you want to have `dyn Trait` implement `Trait`, you should declare it, perhaps with a `dyn` keyword:

```rust
dyn trait Foo {
    fn method(&self);
}
```

This declaration would add various default impls. This would start with the `dyn Foo: Foo` impl:

```rust
impl Foo for dyn Foo /*[1]*/ {
    fn method(&self) {
        <dyn Foo>::method(self) // vtable dispatch
    }

    // [1] actually it would want to cover `dyn Foo + Send` etc too, but I'm ignoring that for now
}
```

But also, if the methods have suitable signatures, include some of the impls you *really ought* to have to make a trait that is well-behaved with respect to dyn trait:

```rust
impl<T> Foo for Box<T> where T: ?Sized { }
impl<T> Foo for &T where T: ?Sized { }
impl<T> Foo for &mut T where T: ?Sized { }
```

In fact, if you add in the ability to declare a trait as `box`, things get very interesting:

```rust
box dyn trait Signal {
    async fn signal(&self);
}
```

I'm not 100% sure how this should work but what I imagine is that `dyn Foo` would be pointer-sized and implicitly contain a `Box` behind the scenes. It would probably automatically `Box` the results from `async fn` when invoked through `dyn Trait`, so something like this:

```rust
impl Foo for dyn Signal {
    async fn bar(&self) {
        <dyn Signal>::signal(self).box.await
    }
}
```

I didn't include this in the main blog post but I think together these ideas would go a long way towards addressing the usability gaps that plague `dyn Trait` today.
