---
layout: post
title: Thoughts on async closures
date: 2023-03-29 11:41 -0400
---

I've been thinking about async closures and how they could work once we have static async fn in trait. Somewhat surprisingly to me, I found that async closures are a strong example for where [async transformers][at] could be an important tool. Let's dive in! We're going to start with the problem, then show why modeling async closures as "closures that return futures" would require some deep lifetime magic, and finally circle back to how async transformers can make all this "just work" in a surprisingly natural way.

[at]: https://smallcultfollowing.com/babysteps/blog/2023/03/03/trait-transformers-send-bounds-part-3/

## Sync closures

Closures are omnipresent in combinator style APIs in Rust. For the purposes of this post, let's dive into a really simple closure function, `call_twice_sync`:

```rust
fn call_twice_sync(mut op: impl FnMut(&str)) {
    op("Hello");
    op("Rustaceans");
}
```

As the name suggests, `call_twice_sync` invokes its argument twice. You might call it from synchronous code like so:

```rust
let mut buf = String::new();
call_twice_sync(|s| buf.push_str(s));
```

As you might expect, after this code executes, `buf` will have the value `"HelloRustaceans"`. [(Playground link, if you're curious to try it out.)](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=1abb09471dad55daa545761fdd80d71e)

## Async closures as closures that return futures

Suppose we want to allow the closure to do async operations, though. That won't work with `call_twice_sync` because the closure is a synchronous function:

```rust
let mut buf = String::new();
call_twice_sync(|s| s.push_str(receive_message().await));
//                                               ----- ERROR
```

Given that an async function is just a sync function that returns a future, perhaps we can model an async clousure as a sync closure that returns a future? Let's try it.


```rust
async fn call_twice_async<F>(op: impl FnMut(&str) -> F)
where
    F: Future<Output = ()>,
{
    op("Hello").await;
    op("Rustaceans").await;
}
```

[This compiles](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=ce12829f92ffcd55b9582db42f2172b5). So far so good. Now let's try using it. For now we won't even use an await, just the same sync code we tried before:

```rust
// Hint: won't compile
async fn use_it() {
    let mut buf = String::new();
    call_twice_async(|s| async { buf.push_str(s); });
    //                   ----- Return a future
}
```

Wait, what's this? Lo and behold, we get an error, and a kind of intimidating one:

```
error: captured variable cannot escape `FnMut` closure body
  --> src/lib.rs:13:26
   |
12 |     let mut buf = String::new();
   |         ------- variable defined here
13 |     call_twice_async(|s| async { buf.push_str(s); });
   |                        - ^^^^^^^^---^^^^^^^^^^^^^^^
   |                        | |       |
   |                        | |       variable captured here
   |                        | returns an `async` block that contains a reference to a captured variable, which then escapes the closure body
   |                        inferred to be a `FnMut` closure
   |
   = note: `FnMut` closures only have access to their captured variables while they are executing...
   = note: ...therefore, they cannot allow references to captured variables to escape
```

So what is this all about? The last two lines actually tell you, but to really see it you have to do a bit of desugaring. 

## Futures capture the data they will use

The closure tries to construct a future with an `async` block. This async block is going to capture a reference to all the variables it needs: in this case, `s` and `buf`. So the closure will become something like:

```rust
|s| MyAsyncBlockType { buf, s }
```

where `MyAsyncBlockType` implements `Future`:

```rust
struct MyAsyncBlockType<'b> {
    buf: &'b mut String,
    s: &'b str,
}

impl Future for MyAsyncBlockType<'_> {
    type Output = ();
    
    fn poll(..) { ... }
}
```

**The key point here is that the closure is returning a struct (`MyAsyncBlockType`) and this struct is holding on to a reference to both `buf` and `s` so that it can use them when it is awaited.**

## Closure signature promises to be finished

The problem is that the `FnMut` closure signature actually promises something different than what the body does. The *signature* says that it takes an `&str` -- this means that the closure is allowed to use the string while it executes, but it cannot hold on to a reference to the string and use it later. The same is true for `buf`, which will be accessible through the implicit `self` argument of the closure. But when the closure return the future, it is trying to create references to `buf` and `s` that outlive the closure itself! This is why the error message says:

```
= note: `FnMut` closures only have access to their captured variables while they are executing...
= note: ...therefore, they cannot allow references to captured variables to escape
```

This is a problem!

## Add some lifetime arguments?

So maybe we can declare the fact that we hold on to the data? It turns out you *almost* can, but not quite, and making an async closure be "just" a sync closure that returns a future would require some rather fundamental extensions to Rust's trait system. There are two variables to consider, `buf` and `s`. Let's begin with the argument `s`.

## An aside: impl Trait capture rules

Before we dive more deeply into the closure case, let's back up and imagine a top-level function that returns a future:

```rust!
fn push_buf(buf: &mut String, s: &str) -> impl Future<Output = ()> {
    async move {
        buf.push_str(s);
    }
}
```

If you try to compile this code, you'll find that it does not build ([playground](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=75fe203778735be39418daa3d1b1eb0b)):

```
error[E0700]: hidden type for `impl Future<Output = ()>` captures lifetime that does not appear in bounds
 --> src/lib.rs:4:5
  |
3 |   fn push_buf(buf: &mut String, s: &str) -> impl Future<Output = ()> {
  |                    ----------- hidden type `[async block@src/lib.rs:4:5: 6:6]` captures the anonymous lifetime defined here
4 | /     async move {
5 | |         buf.push_str(s);
6 | |     }
  | |_____^
  |
help: to declare that `impl Future<Output = ()>` captures `'_`, you can introduce a named lifetime parameter `'a`
  |
3 | fn push_buf<'a>(buf: &'a mut String, s: &'a str) -> impl Future<Output = ()> + 'a  {
  |            ++++       ++                 ++                                  ++++
```

`impl Trait` values can only capture borrowed data if they explicitly name the lifetime. This is why the suggested fix is to use a named lifetime `'a` for `buf` and `s` and declare that the `Future` captures it:

```rust
fn push_buf<'a>(buf: &'a mut String, s: &'a str) -> impl Future<Output = ()> + 'a 
```

If you desugar this return position impl trait into an explicit type alias impl trait, you can see the captures more clearly, as they become parameters to the `type`. The original (no captures) would be:

```rust
type PushBuf = impl Future<Output = ()>;
fn push_buf<'a>(buf: &'a mut String, s: &'a str) -> PushBuf
```

and the fixed version would be:

```rust
type PushBuf<'a> = impl Future<Output = ()> + 'a
fn push_buf<'a>(buf: &'a mut String, s: &'a str) -> PushBuf<'a>
```

## From functions to closures

OK, so we just saw how we can define a function that returns an `impl Future`, how that future will wind up capturing the arguments, and how that is made explicit in the return type by references to a named lifetime `'a`. We could do something similar for closures, although Rust's rather limited support for explicit closure syntax makes it awkward. I'll use the unimplemented syntax from [RFC 3216], you can [see the workaround on the playground](https://play.rust-lang.org/?version=nightly&mode=debug&edition=2021&gist=7a06bc923e23d187fc1cf8db3af50af1) if that's your thing:

[RFC 3216]: https://github.com/rust-lang/rfcs/pull/3216

```rust
type PushBuf<'a> = impl Future<Output = ()> + 'a


async fn test() {
    let mut c = for<'a> |buf: &'a mut String, s: &'a str| -> PushBuf<'a> {
        async move { buf.push_str(s) }
    });
    
    let mut buf = String::new();
    c(&mut buf, "foo").await;
}
```

(Side note that this is an interesting case for the ["currently under debate" rules around defining type alias impl trait](https://github.com/rust-lang/rust/issues/107645).)

## Now for the HAMMER

OK, so far so grody, but we've shown that indeed you *could* define a closure that returns a future and it seems like things would work. But now comes the problem. Let's take a look at the `call_twice_async` function -- i.e., instead of looking at where the closure is defined, we look at the function that takes the closure as argument. That's where things get tricky. 

Here is `call_twice_async`, but with the anonymous lifetime given an explicit name `'a`:

```rust
fn call_twice_async<F>(op: impl for<'a> FnMut(&str) -> F)
where
    F: Future<Output = ()>,
```

Now the problem is this: we need to declare that the future which is returned (`F`) might capture `'a`. But `F` is declared in an outer scope, and it can't name `'a`. In other words, right now, the return type `F` of the closure `op` must be the same each time the closure is called, but to get the semantics we want, we need the return type to include a different value for `'a` each time.

If Rust had higher-kinded types (HKT), you could do something a bit wild, like this...

```rust
fn call_twice_async<F<'_>>(op: impl for<'a> FnMut(&'a str) -> F<'a>)
//                  ----- HKT
where
    for<'a> F<'a>: Future<Output = ()>,
```

but, of course, we *don't* have HKT (and, cool as they are, I don't think that's a good fit for Rust right now, it would bust our complexity barrier in my opinion and then some without near enough payoff).

Short of adding HKT or some equivalent, I believe the option workaround is to use a `dyn` type:

```rust
fn call_twice_async(op: impl for<'a> FnMut(&'a str) -> Box<dyn Future<Output = ()> + 'a>)
```

This works today (and it is, for example, what [moro does][md] to resolve exactly this problem). Of course that means that the closure has to allocate a box, instead of just returning an async move. That's a non-starter.

[md]: https://github.com/nikomatsakis/moro/blob/6aa675e4b1676e21291296687f1d9ff40984b866/src/lib.rs#L145

So we're kind of stuck. As far as I can tell, modeling async closures as "normal closures that happen to return futures" requires one of two unappealing options

* extend the language with HKT, or possibly some syntactic sugar that ultimately however desugars to HKT
* use `Box<dyn>` everywhere, giving up on zero cost futures, embedded use cases, etc.

## More traits, less problems

But wait, there is another way. Instead of modeling async closures using the normal `Fn` traits, we could define some *async* closure traits. To keep our life simple, let's just look at one, for `FnMut`:

```rust
trait AsyncFnMut<A> {
    type Output;
    
    async fn call(&mut self, args: A) -> Self::Output;
}
```

This is identical to the [sync `FnMut`] trait, except that `call` is an `async fn`. But that's a pretty important difference. If we desugar the `async fn` to one using impl Trait, and then to GATs, we can start to see why:

```rust
trait AsyncFnMut<A> {
    type Output;
    type Call<'a>: Future<Output = Self::Output> + 'a;
    
    fn call(&mut self, args: A) -> Self::Call<'_>;
}
```

Notice the Generic Associated Type (GAT) `Call`. GATs are basically the Rusty way to do HKTs (if you want to go deeper, I [wrote][1] [a][2] [comparison][3] [series][4] which may help; back then we called them associated type constructors, not GATs). **Essentially what has happened here is that we moved the "HKT" into the trait definition itself, instead of forcing the caller to have it.**

[1]: https://smallcultfollowing.com/babysteps/blog/2016/11/02/associated-type-constructors-part-1-basic-concepts-and-introduction/
[2]: https://smallcultfollowing.com/babysteps/blog/2016/11/03/associated-type-constructors-part-2-family-traits/
[3]: https://smallcultfollowing.com/babysteps/blog/2016/11/04/associated-type-constructors-part-3-what-higher-kinded-types-might-look-like/
[4]: https://smallcultfollowing.com/babysteps/blog/2016/11/09/associated-type-constructors-part-4-unifying-atc-and-hkt/

Given this definition, when we try to write the "call twice async" function, things work out more smoothly:

```rust
async fn call_twice_async<F>(mut op: impl AsyncFnMut(&str)) {
    op.call("Hello").await;
    op.call("World").await;
}
```

[Try it out on the playground, though note that we don't actually support the `()` sugar for arbitrary traits, so I wrote `impl for<'a> AsyncFnMut<&'a str, Output = ()>` instead.](https://play.rust-lang.org/?version=nightly&mode=debug&edition=2021&gist=082006281e7b30f112c16e2a4b1d334c)

## Connection to trait transformers

The translation between the normal `FnMut` trait and the `AsyncFnMut` trait was pretty automatic. The only thing we did was change the "call" function to `async`. So what if we had an [async trait transformer][tt], as was discussed earlier? Then we only have one "maybe async" trait, `FnMut`:

```rust!
#[maybe(async)]
trait FnMut<A> {
    type Output;
    
    #[maybe(async)]
    fn call(&mut self, args: A) -> Self::Output;
}
```

[tt]: https://smallcultfollowing.com/babysteps/blog/2023/03/03/trait-transformers-send-bounds-part-3/

Now we can write `call_twice` either sync or async, as we like, and the code is virtually identical. The only difference is that I write `impl FnMut` for sync or `impl async FnMut` for async:

```rust!
fn call_twice_sync<F>(mut op: impl FnMut(&str)) {
    op.call("Hello");
    op.call("World");
}

async fn call_twice_async<F>(mut op: impl async FnMut(&str)) {
    op.call("Hello").await;
    op.call("World").await;
}
```

Of course, with a more general maybe-async design, we might just write this function once, but that's separate concern. Right now I'm only concerned with the idea of authoring traits that can be used in two modes, but not necessarily with writing code that is generic over which mode is being used.

## Final note: creating the closure in a maybe-async world

When calling `call_twice`, we could write `|s| buf.push_str(s)` or `async |s| buf.push_str(s)` to indicate which traits it implements, but we could also infer this from context. We already do similar inference to decide the type of `s` for example. In fact, we could have some blanket impls, so that every `F: FnMut` also implements `F: async FnMut`; I guess this is generally true for any trait.

## Conclusion

My conclusions:

* Nothing in this discussion required or even suggested any changes to the underlying design of async fn in trait. Stabilizing the statically dispatched subset of async fn in trait should be forwards compatible with supporting async closures. :tada: 
* The "higher-kinded-ness" of async closures has to go somewhere. In stabilizing GATs, in my view, we've committed to the path that it should go into the trait definition (vs HKT, which would push it to the use site). The standard "def vs use site" tradeoffs apply here, I think: def sites often feel simpler and easier to understand, but are less flexible. I think that's fine.
* Async trait transformers feel like a great option here that makes async closures work just like you would expect.