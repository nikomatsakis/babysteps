---
title: "Just call clone (or alias)"
date: 2025-11-10T13:55:41-05:00
series:
- "Ergonomic RC"
---


<img src="{{< baseurl >}}/assets/2025-justcallclone/keep-calm-and-call-clone-rendered.svg" width="20%" style="float: right; margin-right: 1em; margin-bottom: 0.5em;" />

Continuing my series on ergonomic ref-counting, I want to explore another idea, one that I'm calling "just call clone (or alias)". This proposal specializes the `clone` and `alias` methods so that, in a new edition, the compiler will (1) remove redundant or unnecessary calls (with a lint); and (2) automatically capture clones or aliases in `move` closures where needed.

The goal of this proposal is to simplify the user's mental model: whenever you see an error like "use of moved value", the fix is always the same: just call `clone` (or `alias`, if applicable). This model is aiming for the balance of ["low-level enough for a Kernel, usable enough for a GUI"][eeh] that I described earlier. It's also making a statement, which is that the key property we want to preserve is that *you can always find where new aliases might be created* -- but that it's ok if the fine-grained details around *exactly when* the alias is created is a bit subtle.

[eeh]: {{< baseurl >}}/blog/2025/10/13/ergonomic-explicit-handles/
[ecc]: {{< baseurl >}}/blog/2025/10/22/explicit-capture-clauses/
[handle]: {{< baseurl >}}/blog/2025/10/07/the-handle-trait/

<!-- more -->

## The proposal in a nutshell

### Part 1: Closure desugaring that is aware of clones and aliases

Consider this `move` future:

```rust
fn spawn_services(cx: &Context) {
    tokio::task::spawn(async move {
        //                   ---- move future
        manage_io(cx.io_system.alias(), cx.request_name.clone());
        //        --------------------  -----------------------
    });
    ...
}
```

Because this is a `move` future, this takes ownership of `cx.io_system` and `cx_request_name`. Because `cx` is a borrowed reference, this will be an error unless those values are `Copy` (which they presumably are not). Under this proposal, capturing *aliases* or *clones* in a `move` closure/future would result in capturing an *alias* or *clone* of the place. So this future would be desugared like so (using [explicit capture clause strawman notation][ecc]):


```rust
fn spawn_services(cx: &Context) {
    tokio::task::spawn(
        async move(cx.io_system.alias(), cx.request_name.clone()) {
            //     --------------------  -----------------------
            //     capture alias/clone respectively

            manage_io(cx.io_system.alias(), cx.request_name.clone());
        }
    );
    ...
}
```

### Part 2: Last-use transformation

Now, this result is inefficient -- there are now *two* aliases/clones. So the next part of the proposal is that the compiler would, in newer Rust editions, apply a new transformat called the **last-use transformation**. This transformation would identify calls to `alias` or `clone` that are not needed to satisfy the borrow checker and remove them. This code would therefore become:

```rust
fn spawn_services(cx: &Context) {
    tokio::task::spawn(
        async move(cx.io_system.alias(), cx.request_name.clone()) {
            manage_io(cx.io_system, cx.request_name);
            //        ------------  ---------------
            //        converted to moves
        }
    );
    ...
}
```

The last-use transformation would apply beyond closures. Given an example like this one, which clones `id` even though `id` is never used later:

```rust
fn send_process_identifier_request(id: String) {
    let request = Request::ProcessIdentifier(id.clone());
    //                                       ----------
    //                                       unnecessary
    send_request(request)
}
```

the user would get a warning like so[^clippy]:

[^clippy]: Surprisingly to me, `clippy::pedantic` doesn't have a dedicated lint for unnecessary clones. This [particular example](https://play.rust-lang.org/?version=stable&mode=debug&edition=2024&gist=1b170aea4b8dfb879bd5ec2ffb4135b6) does get a lint, but it's a lint about taking an argument by value and then not consuming it. If you rewrite the example to create `id` locally, [clippy does not complain](https://play.rust-lang.org/?version=stable&mode=debug&edition=2024&gist=3a6fcf9639114b5e44f5d68b06feee13).

```
warning: unnecessary `clone` call will be converted to a move
 --> src/main.rs:7:40
  |
8 |     let request = Request::ProcessIdentifier(id.clone());
  |                                              ^^^^^^^^^^ unnecessary call to `clone`
  |
  = help: the compiler automatically removes calls to `clone` and `alias` when not
    required to satisfy the borrow checker
help: change `id.clone()` to `id` for greater clarity
  |
8 -     let request = Request::ProcessIdentifier(id.clone());
8 +     let request = Request::ProcessIdentifier(id);
  |
```

and the code would be transformed so that it simply does a move:

```rust
fn send_process_identifier_request(id: String) {
    let request = Request::ProcessIdentifier(id);
    //                                       --
    //                                   transformed
    send_request(request)
}
```

## Mental model: just call "clone" (or "alias")

The goal of this proposal is that, when you get an error about a use of moved value, or moving borrowed content, the fix is always the same: you just call `clone` (or `alias`). It doesn't matter whether that error occurs in the regular function body or in a closure or in a future, the compiler will insert the clones/aliases needed to ensure future users of that same place have access to it (and no more than that).

I believe this will be helpful for new users. Early in their Rust journey new users are often sprinkling calls to clone as well as sigils like `&` in more-or-less at random as they try to develop a firm mental model -- this is where the ["keep calm and call clone"](https://keepcalmandcallclone.website/) joke comes from. This approach breaks down around closures and futures today. Under this proposal, it will work, but users will *also* benefit from warnings indicating unnecessary clones, which I think will help them to understand where clone is really *needed*.

## Experienced users can trust the compiler to get it right

But the real question is how this works for *experienced users*. I've been thinking about this a lot! I think this approach fits pretty squarely in the classic Bjarne Stroustrup definition of a zero-cost abstraction:

> "What you don't use, you don't pay for. And further: What you do use, you couldn't hand code any better."

The first half is clearly satisfied. If you don't call `clone` or `alias`, this proposal has no impact on your life.

The key point is the second half: earlier versions of this proposal were more simplistic, and would sometimes result in redundant or unnecessary clones and aliases. Upon reflection, I decided that this was a non-starter. The only way this proposal works is if experienced users know there is **no performance advantage to using the more explicit form**.This is precisely what we have with, say, iterators, and I think it works out very well. I believe this proposal hits that mark, but I'd like to hear if there are things I'm overlooking.

## The *last-use transformation* codifies a widespread intuition, that `clone` is never *necessary*

I think most users would expect that changing `message.clone()` to just `message` is fine, as long as the code keeps compiling. But in fact nothing *requires* that to be the case. Under this proposal, APIs that make `clone` significant in unusual ways would be more annoying to use in the new Rust edition and I expect ultimately wind up getting changed so that "significant clones" have another name. I think this is a good thing.

## Frequently asked questions

I think I've covered the key points. Let me dive into some of the details here with a FAQ.

### Can you summarize all of these posts you've been writing? It's a lot to digest!

I get it, I've been throwing a lot of things out there. Let me begin by recapping the motivation as I see it:

* I believe our goal should be to focus first on a design that is ["low-level enough for a Kernel, usable enough for a GUI"][eeh].
    * The key part here is the word *enough*. We need to make sure that low-level details are exposed, but only those that truly matter. And we need to make sure that it's ergonomic to use, but it doesn't have to be as nice as TypeScript (though that would be great).
* Rust's current approach to `Clone` fails both groups of users;
    * calls to `clone` are not explicit enough for kernels and low-level software: when you see `something.clone()`, you don't know that is creating a new alias or an entirely distinct value, and you don't have any clue what it will cost at runtime. There's a reason much of the community recommends writing `Arc::clone(&something)` instead.
    * calls to `clone`, particularly in closures, are a **major ergonomic pain point**, this has been a clear consensus since we first started talking about this issue.

I then proposed a set of three changes to address these issues, authored in individual blog posts:

* First, we [introduce the `Alias` trait (originally called `Handle`)][handle]. The `Alias` trait introduces a new method `alias` that is equivalent to `clone` but indicates that this will be creating a second alias of the same underlying value.
* Second, we introduce [explicit capture clauses][ecc], which lighten the syntactic load of capturing a clone or alias, make it possible to declare up-front the full set of values captured by a closure/future, and will support other kinds of handy transformations (e.g., capturing the result of `as_ref` or `to_string`).
* Finally, we introduce the **just call clone** proposal described in this post. This modifies closure desugaring to recognize clones/aliases and also applies the last-use transformation to replace calls to clone/alias with moves where possible.

### What would it feel like if we did all those things?

Let's look at the impact of each set of changes by walking through the "Cloudflare example", which originated in [this excellent blog post by the Dioxus folks](https://dioxus.notion.site/Dioxus-Labs-High-level-Rust-5fe1f1c9c8334815ad488410d948f05e):

```rust
let some_value = Arc::new(something);

// task 1
let _some_value = some_value.clone();
tokio::task::spawn(async move {
    do_something_with(_some_value);
});

// task 2:  listen for dns connections
let _some_a = self.some_a.clone();
let _some_b = self.some_b.clone();
let _some_c = self.some_c.clone();
tokio::task::spawn(async move {
  	do_something_else_with(_some_a, _some_b, _some_c)
});

```
As the original blog post put it:

> Working on this codebase was demoralizing. We could think of no better way to architect things - we needed listeners for basically everything that filtered their updates based on the state of the app. You could say “lol get gud,” but the engineers on this team were the sharpest people I’ve ever worked with. Cloudflare is all-in on Rust. They’re willing to throw money at codebases like this. Nuclear fusion won’t be solved with Rust if this is how sharing state works.

Applying the [`Alias` trait][handle] and [explicit capture clauses][ecc] makes for a modest improvement. You can now clearly see that the calls to `clone` are `alias` calls, and you don't have the awkward `_some_value `and `_some_a` variables. However, the code is still pretty verbose:

```rust
let some_value = Arc::new(something);

// task 1
tokio::task::spawn(async move(some_value.alias()) {
    do_something_with(some_value);
});

// task 2:  listen for dns connections
tokio::task::spawn(async move(
    self.some_a.alias(),
    self.some_b.alias(),
    self.some_c.alias(),
) {
  	do_something_else_with(self.some_a, self.some_b, self.some_c)
});
```

Applying the Just Call Clone proposal removes a lot of boilerplate and, I think, captures the *intent* of the code very well. It also retains quite a bit of explicitness, in that searching for calls to `alias` reveals all the places that aliases will be created. However, it does introduce a bit of subtlety, since (e.g.) the call to `self.some_a.alias()` will actually occur when the future is *created* and not when it is *awaited*:

```rust
let some_value = Arc::new(something);

// task 1
tokio::task::spawn(async move {
    do_something_with(some_value.alias());
});

// task 2:  listen for dns connections
tokio::task::spawn(async move {
  	do_something_else_with(
        self.some_a.alias(),
        self.some_b.alias(),
        self.some_c.alias(),
    )
});
```

### I'm worried that the execution order of calls to alias will be too subtle. How is thie "explicit enough for low-level code"?

There is no question that Just Call Clone makes closure/future desugaring more subtle. Looking at task 1:

```rust
tokio::task::spawn(async move {
    do_something_with(some_value.alias());
});
```

this gets desugared to a call to `alias` when the future is *created* (not when it is *awaited*). Using the explicit form:

```rust
tokio::task::spawn(async move(some_value.alias()) {
    do_something_with(some_value)
});
```

I can definitely imagine people getting confused at first -- "but that call to `alias` looks like its inside the future (or closure), how come it's occuring earlier?"

**Yet, the code really seems to preserve what is most important:** when I search the codebase for calls to `alias`, I will find that an alias is creating for this task. And for the vast majority of real-world examples, the distinction of whether an alias is creating *when the task is spawned* versus *when it executes* doesn't matter. Look at this code: the important thing is that `do_something_with` is called with an alias of `some_value`, so `some_value` will stay alive as long as `do_something_else` is executing. It doesn't really matter how the "plumbing" worked.

### What about futures that *conditionally* alias a value?

Yeah, good point, those kind of examples have more room for confusion. Like look at this:

```rust
tokio::task::spawn(async move {
    if false {
        do_something_with(some_value.alias());
    }
});
```

In this example, there is code that uses `some_value` with an alias, but only under `if false`. So what happens? I would assume that indeed the future *will* capture an alias of `some_value`, in just the same way that this future will *move* `some_value`, even though the relevant code is dead:

```rust
tokio::task::spawn(async move {
    if false {
        do_something_with(some_value);
    }
});
```

### Can you give more details about the closure desugaring you imagine?

Yep! I am thinking of something like this:

* If there is an [explicit capture clause][ecc], use that.
* Else:
    * For non-`move` closures/futures, no changes, so
        * Categorize usage of each place and pick the "weakest option" that is available:
            * by ref
            * by mut ref
            * moves
    * For `move` closures/futures, we would change
        * Categorize usage of each place `P` and decide whether to capture that place...
            * *by clone*, there is at least one call `P.clone()` or `P.alias()` and all other usage of `P` requires only a shared ref (reads)
            * *by move*, if there are no calls to `P.clone()` or `P.alias()` or if there are usages of `P` that require ownership or a mutable reference
        * Capture by clone/alias when a place `a.b.c` is only used via shared references, and at least one of those is a clone or alias.
            * For the purposes of this, accessing a "prefix place" `a` or a "suffix place" `a.b.c.d` is also considered an access to `a.b.c`.
    
Examples that show some edge cased:

```rust
if consume {
    x.foo().
}
```

### Why not do something similar for non-move closures?

In the relevant cases, non-move closures will already just capture by shared reference. This means that later attempts to use that variable will generally succeed:

```rust
let f = async {
    //  ----- NOT async move
    self.some_a.alias()
};

do_something_else(self.some_a.alias());
//                ----------- later use succeeds

f.await;
```

This future does not need to take ownership of `self.some_a` to create an alias, so it will just capture a *reference* to `self.some_a`. That means that later uses of `self.some_a` can still compile, no problem. If this had been a move closure, however, that code above would currently not compile.

There is an edge case where you might get an error, which is when you are *moving*:

```rust
let f = async {
    self.some_a.alias()
};

do_something_else(self.some_a);
//                ----------- move!

f.await;
```

In that case, you can make this an `async move` closure and/or use an explicit capture clause:

### Can you give more details about the last-use transformation you imagine?

Yep! We would during codegen identify candidate calls to `Clone::clone` or `Alias::alias`. After borrow check has executed, we would examine each of the callsites and check the borrow check information to decide:

* Will this place be accessed later?
* Will some reference potentially referencing this place be accessed later?

If the answer to both questions is no, then we will replace the call with a move of the original place.

Here are some examples:


```rust
fn borrow(message: Message) -> String {
    let method = message.method.to_string();

    send_message(message.clone());
    //           ---------------
    //           would be transformed to
    //           just `message`

    method
}
```

```rust
fn borrow(message: Message) -> String {
    send_message(message.clone());
    //           ---------------
    //           cannot be transformed
    //           since `message.method` is
    //           referenced later

    message.method.to_string()
}
```

```rust
fn borrow(message: Message) -> String {
    let r = &message;

    send_message(message.clone());
    //           ---------------
    //           cannot be transformed
    //           since `r` may reference
    //           `message` and is used later.

    r.method.to_string()
}
```

### Why are you calling it the *last-use transformation* and not *optimization*?

In the past, I've talked about the last-use *transformation* as an *optimization* -- but I'm changing terminology here. This is because, typically, an *optimization* is supposed to be unobservable to users except through measurements of execution time (or though UB), and that is clearly not the case here. The transformation would be a mechanical transformation performed by the compiler in a deterministic fashion.

### Would the transformation "see through" references?

I think yes, but in a limited way. In other words I would expect

```rust
Clone::clone(&foo)
```

and

```rust
let p = &foo;
Clone::clone(p)
```

to be transformed in the same way (replaced with `foo`), and the same would apply to more levels of intermediate usage. This would kind of "fall out" from the MIR-based optimization technique I imagine. It doesn't have to be this way, we could be more particular about the syntax that people wrote, but I think that would be surprising.

On the other hand, you could still fool it e.g. like so

```rust
fn identity<T>(x: &T) -> &T { x }

identity(&foo).clone()
```

### Would the transformation apply across function boundaries?

The way I imagine it, no. The transformation would be local to a function body. This means that one could write a `force_clone` method like so that "hides" the clone in a way that it will never be transformed away (this is an important capability for edition transformations!):

```rust
fn pipe<Msg: Clone>(message: Msg) -> Msg {
    log(message.clone()); // <-- keep this one
    force_clone(&message)
}

fn force_clone<Msg: Clone>(message: &Msg) -> Msg {
    // Here, the input is `&Msg`, so the clone is necessary
    // to produce a `Msg`.
    message.clone()
}
```


### Won't the last-use transformation change behavior by making destructors run earlier?

Potentially, yes! Consider this example, written using [explicit capture clause][ecc] notation and written assuming we add an `Alias` trait:

```rust
async fn process_and_stuff(tx: mpsc::Sender<Message>) {
    tokio::spawn({
        async move(tx.alias()) {
            //     ---------- alias here
            process(tx).await
        }
    });

    do_something_unrelated().await;
}
```

The precise timing when `Sender` values are dropped can be important -- when all senders have dropped, the `Receiver` will start returning `None` when you call `recv`. Before that, it will block waiting for more messages, since those `tx` handles could still be used.

So, in `process_and_stuff`, when will the sender aliases be fully dropped? The answer depends on whether we do the last-use transformation or not:

* Without the transformation, there are two aliases: the original `tx` and the one being held by the future. So the receiver will only start returning `None` when `do_something_unrelated` has finished *and* the task has completed.
* With the transformation, the call to `tx.alias()` is removed, and so there is only one alias -- `tx`, which is moved into the future, and dropped once the spawned task completes. This could well be earlier than in the previous code, which had to wait until both `process_and_stuff` and the new task completed.

Most of the time, running destructors earlier is a good thing. That means lower peak memory usage, faster responsiveness. But in extreme cases it could lead to bugs -- a typical example is a `Mutex<()>` where the guard is being used to protect some external resource. 

### How can we change when code runs? Doesn't that break stability?

This is what editions are for! We have in fact done a very similar transformation before, in Rust 2021. RFC 2229 changed destructor timing around closures and it was, by and large, a non-event.

The desire for edition compatibility is in fact one of the reasons I want to make this a *last-use transformation* and not some kind of *optimization*. There is no UB in any of these examples, it's just that to understand what Rust code does around clones/aliases is a bit more complex than it used to be, because the compiler will do automatic transformation to those calls. The fact that this transformation is local to a function means we can decide on a call-by-call basis whether it should follow the older edition rules (where it will always occur) or the newer rules (where it may be transformed into a move).

### Does that mean that the last-use transformation would change with Polonius or other borrow checker improvements?

In theory, yes, improvements to borrow-checker precision like Polonius could mean that we identify more opportunities to apply the last-use transformation. This is something we can phase in over an edition. It's a bit of a pain, but I think we can live with it -- and I'm unconvinced it will be important in practice. For example, when thinking about the improvements I expect under Polonius, I was not able to come up with a realistic example that would be impacted.

### Isn't it weird to do this after borrow check?

This last-use transformation is guaranteed not to produce code that would fail the borrow check. However, it can affect the correctness of unsafe code:

```rust
let p: *const T = &*some_place;

let q: T = some_place.clone();
//         ---------- assuming `some_place` is
//         not used later, becomes a move

unsafe {
    do_something(p);
    //           -
    // This now refers to a stack slot
    // whose value is uninitialized.
}
```

Note though that, in this case, there would be a lint identifying that the call to `some_place.clone()` will be transformed to just `some_place`. We could also detect simple examples like this one and report a stronger deny-by-default lint, as we often do when we see guaranteed UB.

### Shouldn't we use a keyword for this?

When I originally had this idea, I called it "use-use-everywhere" and, instead of writing `x.clone()` or `x.alias()`, I imagined writing `x.use`. This made sense to me because a keyword seemed like a stronger signal that this was impacting closure desugaring. However, I've changed my mind for a few reasons.

First, Santiago Pastorino gave strong pushback that `x.use` was going to be a stumbling block for new learners. They now have to see this keyword and try to understand what it means -- in contrast, if they see method calls, they will likely not even notice something strange is going on.

The second reason though was TC who argued, in the lang-team meeting, that all the arguments for why it should be ergonomic to clone a ref-counted value in a closure applied equally well to `clone`, depending on the needs of your application. I completely agree. As I mentioned earlier, this also [addresses the concern I've heard with the `Alias` trait], which is that there are things you want to ergonomically clone but which don't correspond to "aliases". True.

[concern]: {{< baseurl >}}/blog/2025/11/05/bikeshedding-handle/#handle-doesnt-cover-everything

In general I think that `clone` (and `alias`) are fundamental enough to how Rust is used that it's ok to special case them. Perhaps we'll identify other similar methods in the future, or generalize this mechanism, but for now I think we can focus on these two cases.

### What about "deferred ref-counting"?

One point that I've raised from time-to-time is that I would like a solution that gives the compiler more room to optimize ref-counting to avoid incrementing ref-counts in cases where it is obvious that those ref-counts are not needed. An example might be a function like this:

```rust
fn use_data(rc: Rc<Data>) {
    for datum in rc.iter() {
        println!("{datum:?}");
    }
}
```

This function requires ownership of an alias to a ref-counted value but it doesn't actually *do* anything but read from it. A caller like this one...

```rust
use_data(source.alias())
```

...doesn't really *need* to increment the reference count, since the caller will be holding a reference the entire time. I often write code like this using a `&`:


```rust
fn use_data(rc: &Rc<Data>) {
    for datum in rc.iter() {
        println!("{datum:?}");
    }
}
```

so that the caller can do `use_data(&source)` -- this then allows the callee to write `rc.alias()` in the case that it *wants* to take ownership.

I've basically decided to punt on adressing this problem. I think folks that are very performance sensitive can use `&Arc` and the rest of us can sometimes have an extra ref-count increment, but either way, the semantics for users are clear enough and (frankly) good enough.