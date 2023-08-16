---
date: "2023-02-01T00:00:00Z"
slug: async-trait-send-bounds-part-1-intro
title: 'Async trait send bounds, part 1: intro'
---

Nightly Rust now has [support for async functions in traits][irblog], so long as you limit yourself to static dispatch. That’s super exciting! And yet, for many users, this support won’t yet meet their needs. One of the problems we need to resolve is how users can conveniently specify when they need an async function to return a `Send` future. This post covers some of the background on send futures, why we don't want to adopt the solution from the `async_trait` crate for the language, and the general direction we would like to go. Follow-up posts will dive into specific solutions.

[irblog]: https://blog.rust-lang.org/inside-rust/2022/11/17/async-fn-in-trait-nightly.html

## Why do we care about Send bounds?

Let’s look at an example. Suppose I have an async trait for performs some kind of periodic health check on a given server:

```rust
trait HealthCheck {
    async fn check(&mut self, server: &Server) -> bool;
}
```

Now suppose we want to write a function that, given a `HealthCheck`, starts a parallel task that runs that check every second, logging failures. This might look like so:

```rust
fn start_health_check<H>(health_check: H, server: Server)
where
    H: HealthCheck + Send + 'static,
{
    tokio::spawn(async move {
        while health_check.check(&server).await {
            tokio::time::sleep(Duration::from_secs(1)).await;
        }
        emit_failure_log(&server).await;
    });
}
```

[eg]: https://play.rust-lang.org/?version=nightly&mode=debug&edition=2021&gist=a4a2cf7b541a4c7b89eac1a3ddd8596d

So far so good! So what happens if we try to compile this? [You can try it yourself if you use the `async_fn_in_trait` feature gate][eg], you should see a compilation error like so:

```
error: future cannot be sent between threads safely
   --> src/lib.rs:15:18
    |
15  |       tokio::spawn(async move {
    |  __________________^
16  | |         while health_check.check(&server).await {
17  | |             tokio::time::sleep(Duration::from_secs(1)).await;
18  | |         }
19  | |         emit_failure_log(&server).await;
20  | |     });
    | |_____^ future created by async block is not `Send`
    |
    = help: within `[async block@src/lib.rs:15:18: 20:6]`, the trait `Send` is not implemented for `impl Future<Output = bool>`
```

The error is saying that the future for our task cannot be sent between threads. But why not? After all,  the `health_check` value is both `Send` and `’static`, so we know that `health_check` is safe to send it over to the new thread. But the problem lies elsewhere. The error has an attached note that points it out to us:

```
note: future is not `Send` as it awaits another future which is not `Send`
   --> src/lib.rs:16:15
    |
16  |         while health_check.check(&server).await {
    |               ^^^^^^^^^^^^^^^^^^^^^^^^^^^ await occurs here
```

The problem is that the call to `check` is going to return a future, and that future is not known to be `Send`. To see this more clearly, let’s desugar the `HealthCheck` trait slightly:

```rust
trait HealthCheck {
    // async fn check(&mut self, server: &Server) -> bool;
    fn check(&mut self, server: &Server) -> impl Future<Output = bool>;
                                           // ^ Problem is here! This returns a future, but not necessarily a `Send` future.
}
```

The problem is that `check` returns an `impl Future`, but the trait doesn’t say whether this future is `Send` or not. The compiler therefore sees that our task is going to be awaiting a future, but that future might not be sendable between threads.

## What does the async-trait crate do?

Interestingly, if you rewrite the above example to use the `async_trait` crate, [it compiles][eg2]. What’s going on here? The answer is that the `async_trait` proc macro uses a different desugaring. Instead of creating a trait that yields `-> impl Future`, it creates a trait that returns a `Pin<Box<dyn Future + Send>>`. This means that the future can be sent between threads; it also means that the trait is dyn-safe. 

[eg2]: https://play.rust-lang.org/?version=nightly&mode=debug&edition=2021&gist=c399a94d05e9e278ba7f6f97cd03afa7

This is a good answer for the `async-trait` crate, but it’s not a good answer for a core language construct as it loses key flexibility. We want to support async in single-threaded executors, where the `Send` bound is irrelevant, and we also to support async in no-std applications, where `Box` isn’t available. Moreover, we want to have key interop traits (e.g., `Read`) that can be used for all three of those applications at the same time. An approach like the used in `async-trait` cannot support a trait that works for all three of those applications at once.

## How would we like to solve this?

Instead of having the trait specify whether the returned future is `Send` (or boxed, for that matter), our preferred solution is to have the `start_health_check` function declare that it requires `check` to return a sendable future. Remember that `health_check` already included a where clause specifying that the type `H` was sendable across threads:

```rust
fn start_health_check<H>(health_check: H, server: Server)
where
    H: HealthCheck + Send + 'static,
    // —————  ^^^^^^^^^^^^^^ “sendable to another disconnected thread”
    //     |
    // Implements the `HealthCheck` trait
```

Right now, this where clause says two independent things:

* `H` implements `HealthCheck`;
* values of type `H` can be sent to an independent task, which is really a combination of two things
    * type `H` can be sent between threads (`H: Send`)
    * type `H` contains no references to the current stack (`H: ‘static`)

What we want is to add syntax to specify an additional condition:

* `H` implements `HealthCheck` **and its check method returns a `Send` future**

In other words, we don’t want just any type that implements `HealthCheck`. We specifically want a type that implements `HealthCheck` and returns a `Send` future.

Note the contrast to the desugaring approach used in the `async_trait` crate: in that approach, we changed what it means to implement `HealthCheck` to always require a sendable future. In this approach, we allow the trait to be used in both ways, but allow the function to say when it needs sendability or not.

The approach of “let the function specify what it needs” is very in-line with Rust. In fact, the existing where-clause demonstrates the same pattern. We don’t say that implementing `HealthCheck` implies that `H` is `Send`, rather we say that the trait can be implemented by any type, but allow the function to specify that `H` must be both `HealthCheck` *and* `Send`.

## Next post: Let’s talk syntax

I’m going to leave you on a cliffhanger. This blog post setup the problem we are trying to solve: for traits with async functions, **we need some kind of syntax for declaring that you want an implementation that returns `Send` futures, and not just *any* implementation**. In the next set of posts, I’ll walk through our proposed solution to this, and some of the other approaches we’ve considered and rejected.
 
## Appendix: Why does the returned future have to be send anyway?

Some of you may wonder why it matters that the future returned is not `Send`. After all, the only thing we are actually sending between threads is `health_check` — the future is being created on the new thread itself, when we call `check`. It *is* a bit surprising, but this is actually highlighting an area where async tasks are different from threads (and where we might consider future language extensions).

Async is intended to support a number of different task models:

* Single-threaded: all tasks run in the same OS thread. This is a great choice for embedded systems, or systems where you have lightweight processes (e.g., [Fuchsia][][^spell]).
* [Work-dealing][wd], sometimes called [thread-per-core][tpc]: tasks run in multiple threads, but once a task starts in a thread, it never moves again.
* [Work-stealing][ws]: tasks start in one thread, but can migrate between OS threads while they execute.

[Fuchsia]: https://fuchsia.dev
[wd]: https://dl.acm.org/doi/10.1145/564870.564900
[ws]: https://en.wikipedia.org/wiki/Work_stealing
[tpc]: https://www.datadoghq.com/blog/engineering/introducing-glommio/

[^spell]: I have finally learned how to spell this word without having to look it up! 💪

Tokio’s `spawn` function supports the final mode (work-stealing). The key point here is that the future can  move between threads at any `await` point. This means that it’s possible for the future to be moved between threads while awaiting the future returned by `check`. Therefore, **any data in this future must be `Send`**.

This might be surprising. After all, the most common example of non-send data is something like a (non-atomic) `Rc`. It would be fine to create an `Rc` within one async task and then move that task to another thread, so long as the task is paused at the point of move. But there are other non-`Send` types that wouldn’t work so well. For example, you might make a type that relies on thread-local storage; such a type would not be `Send` because it’s only safe to use it on the thread in which it was created. If that type were moved between threads, the system could break.

In the future, it might be useful to separate out types like `Rc` from other `Send` types. The distinguishing characteristic is that `Rc` can be moved between threads so long as all possible aliases are also moved at the same time. Other types are really tied to a *specific* thread. There’s no example in the stdlib that comes to mind, but it seems like a valid pattern for Rust today that I would like to continue supporting. I’m not sure yet the right way to think about that!
