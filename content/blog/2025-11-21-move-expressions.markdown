---
title: "Move Expressions"
date: 2025-11-21T05:45:10-05:00
series:
- "Ergonomic RC"
---

This post explores another proposal in the space of ergonomic ref-counting that I am calling **move expressions**. To my mind, these are an alternative to [explicit capture clauses][ecc], one that addresses many (but not *all*) of the goals from that design with improved ergonomics and readability.

[ecc]: {{< baseurl >}}/blog/2025/10/22/explicit-capture-clauses.html

## TL;DR

The idea itself is simple, within a closure (or future), we add the option to write `move($expr)`. This is a value expression ("rvalue") that desugars into a temporary value that is moved into the closure. So

```rust
|| something(&move($expr))
``` 

is roughly equivalent to something like:

```rust
{ 
    let tmp = $expr;
    || something(&{tmp})
}
```

## How it would look in practice

Let's go back to one of our running examples, the "Cloudflare example", which originated in [this excellent blog post by the Dioxus folks](https://dioxus.notion.site/Dioxus-Labs-High-level-Rust-5fe1f1c9c8334815ad488410d948f05e). As a reminder, this is how the code looks *today* -- note the `let _some_value = ...` lines for dealing with captures:

```rust
// task:  listen for dns connections
let _some_a = self.some_a.clone();
let _some_b = self.some_b.clone();
let _some_c = self.some_c.clone();
tokio::task::spawn(async move {
  	do_something_else_with(_some_a, _some_b, _some_c)
});
```

Under this proposal it would look something like this:

```rust
tokio::task::spawn(async {
    do_something_else_with(
        move(self.some_a.clone()),
        move(self.some_b.clone()),
        move(self.some_c.clone()),
    )
});
```

There are times when you would want multiple clones. For example, if you want to move something into a `FnMut` closure that will then give away a copy on each call, it might look like

```rust
data_source_iter
    .inspect(|item| {
        inspect_item(item, move(tx.clone()).clone())
        //                      ----------  -------
        //                           |         |
        //                   move a clone      |
        //                   into the closure  |
        //                                     |
        //                             clone the clone
        //                             on each iteration
    })
    .collect();

// some code that uses `tx` later...
```

## Credit for this idea

This idea is not mine. It's been floated a number of times. The first time I remember hearing it was at the RustConf Unconf, but I feel like it's come up before that. Most recently it was [proposed by Zachary Harrold on Zulip][z1], who has also created a prototype called [soupa](https://crates.io/crates/soupa). Zachary's proposal, like earlier proposals I've heard, used the `super` keyword. Later on [@simulacrum proposed using `move`][z2], which to me is a major improvement, and that's the version I ran with here.

[z1]: https://rust-lang.zulipchat.com/#narrow/channel/410673-t-lang.2Fmeetings/topic/Design.20meeting.202025-08-27.3A.20Ergonomic.20RC/near/555236763

[z2]: https://rust-lang.zulipchat.com/#narrow/channel/410673-t-lang.2Fmeetings/topic/Design.20meeting.202025-08-27.3A.20Ergonomic.20RC/near/555643180

## This proposal makes closures more "continuous"

The reason that I love the `move` variant of this proposal is that it makes closures more "continuous" and exposes their underlying model a bit more clearly. With this design, I would start by explaining closures with move expressions and just teach `move` closures at the end, as a convenient default:

> A Rust closure captures the places you use in the "minimal way that it can" -- so `|| vec.len()` will capture a shared reference to the `vec`, `|| vec.push(22)` will capture a mutable reference, and `|| drop(vec)` will take ownership of the vector.
>
> You can use `move` expressions to control exactly what is captured: so `|| move(vec).push(22)` will move the `vector` into the closure. A common pattern when you want to be fully explicit is to list all captures at the top of the closure, like so:
>
> ```rust
> || {
>     let vec = move(input.vec); // take full ownership of vec
>     let data = move(&cx.data); // take a reference to data
>     let output_tx = move(output_tx); // take ownership of the output channel
> 
>     process(&vec, &mut output_tx, data)
> }
> ```
>
> As a shorthand, you can write `move ||` at the top of the closure, which will change the default so that closures > take ownership of every captured variable. You can still mix-and-match with `move` expressions to get more control. > So the previous closure might be written more concisely like so:
> 
> ```rust
> move || {
>     process(&input.vec, &mut output_tx, move(&cx.data))
>     //       ---------       ---------       --------      
>     //           |               |               |         
>     //           |               |       closure still  
>     //           |               |       captures a ref
>     //           |               |       `&cx.data`        
>     //           |               |                         
>     //       because of the `move` keyword on the clsoure,
>     //       these two are captured "by move"
>     //       
> }
> ```

### This proposal makes `move` "fit in" for me

It's a bit ironic that I like this, because it's doubling down on part of Rust's design that I was recently complaining about. In my earlier post on [Explicit Capture Clauses][ecc] I wrote that:


> To be honest, I don't like the choice of `move` because it's so *operational*. I think if I could go back, I would try to refashion our closures around two concepts
>
> * *Attached* closures (what we now call `||`) would *always* be tied to the enclosing stack frame. They'd always have a lifetime even if they don't capture anything.
> * *Detached* closures (what we now call `move ||`) would capture by-value, like `move` today.
>
> I think this would help to build up the intuition of "use `detach ||` if you are going to return the closure from the current stack frame and use `||` otherwise".

`move` expressions are, I think, moving in the opposite direction. Rather than talking about attached and detached, they bring us to a more unified notion of closures, one where you don't have "ref closures" and "move closures" -- you just have closures that sometimes capture moves, and a "move" closure is just a shorthand for using `move` expressions everywhere. This is in fact how closures work in the compiler under the hood, and I think it's quite elegant.

## Conclusion

I'm going to wrap up this post here. To be honest, what this design really has going for it, above anything else, is its *simplicity* and the way it *generalizes Rust's existing design*. I love that. To me, it joins the set of "yep, we should clearly do that" pieces in this puzzle:

* Add a `Share` trait (I've gone back to preferring the name `share` :grin:)
* Add `move` expressions

These both seem like solid steps forward. I am not yet persuaded that they get us all the way to the goal that I articulated in [an earlier post][eeh]:

> "low-level enough for a Kernel, usable enough for a GUI"

but they are moving in the right direction.

[eeh]: {{< baseurl >}}/blog/2025/10/13/ergonomic-explicit-handles/


