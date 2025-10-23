---
title: "Explicit capture clauses"
date: 2025-10-22T06:08:27-04:00
series:
- "Ergonomic RC"
---

In my previous post about Ergonomic Ref Counting, I talked about how, whatever else we do, we need a way to have explicit handle creation that is ergonomic. The next few posts are going to explore a few options for how we might do that.

This post focuses on **explicit capture clauses**, which would permit closures to be annotated with an explicit set of captured places. My take is that explicit capture clauses are a no brainer, for reasons that I'll cover below, and we should definitely do them; but they may not be enough to be considered *ergonomic*, so I'll explore more proposals afterwards.

## Motivation

Rust closures today work quite well but I see a few problems:

* Teaching and understanding closure desugaring is difficult because it lacks an explicit form. Users have to learn to desugar in their heads to understand what's going on.
* Capturing the "clone" of a value (or possibly other transformations) has no concise syntax.
* For long closure bodies, it is hard to determine precisely which values are captured and how; you have to search the closure body for references to external variables, account for shadowing, etc. 
* It is hard to develop an intuition for when `move` is required. I find myself adding it when the compiler tells me to, but that's annoying.

## Let's look at a strawperson proposal

Some time ago, I wrote a proposal for explicit capture clauses. I actually see a lot of flaws with this proposal, but I'm still going to explain it: right now it's the only solid proposal I know of, and it's good enough to explain how an explicit capture clause *could be seen* as a solution to the "explicit *and* ergonomic" goal. I'll then cover some of the things I like about the proposal and what I don't.

## Begin with `move`

The proposal begins by extending the `move` keyword with a list of places to capture:

```rust
let closure = move(a.b.c, x.y) || {
    do_something(a.b.c.d, x.y)
};
```

The closure will then take ownership of those two places; references to those places in the closure body will be replaced by accesses to these captured fields. So that example would desugar to something like

```rust
let closure = {
    struct MyClosure {
        a_b_c: Foo,
        x_y: Bar,
    }

    impl FnOnce<()> for MyClosure {
        fn call_once(self) -> Baz {
            do_something(self.a_b_c.d, self.x_y)
            //           ----------    --------
            //   The place `a.b.c` is      |
            //   rewritten to the field    |
            //   `self.a_b_c`              |
            //                  Same here but for `x.y`
        }
    }

    MyClosure {
        a_b_c: self.a.b.c,
        x_y: self.x.y,
    }
};
```

When using a simple list like this, attempts to reference other places that were not captured result in an error:


```rust
let closure = move(a.b.c, x.y) || {
    do_something(a.b.c.d, x.z)
    //           -------  ---
    //           OK       Error: `x.z` not captured
};
```

## Capturing with rewrites

It is also possible to capture a custom expression by using an `=` sign. So for example, you could rewrite the above closure as follows:

```rust
let closure = move(
    a.b.c = a.b.c.clone(),
    x.y,
) || {
    do_something(a.b.c.d, x.z)
};
```

and it would desugar to:

```rust
let closure = {
    struct MyClosure { /* as before */ }
    impl FnOnce<()> for MyClosure { /* as before */ }

    MyClosure {
        a_b_c: self.a.b.c.clone(),
        //     ------------------
        x_y: self.x.y,
    }
};
```

When using this form, the expression assigned to `a.b.c` must have the same type as `a.b.c` in the surrounding scope. So this would be an error:


```rust
let closure = move(
    a.b.c = 22, // Error: `i32` is not `Foo`
    x.y,
) || {
    /* ... */
};
```

## Shorthands and capturing by reference

You can understand `move(a.b)` as sugar for `move(a.b = a.b)`. We support other convenient shorthands too, such as 

```rust
move(a.b.clone()) || {...}
// == anything that ends in a method call becomes ==>
move(a.b = a.b.clone()) || {...}
```

and two kinda special shorthands:

```rust
move(&a.b) || { ... }
move(&mut a.b) || { ... }
```

These are special because the captured value is indeed `&a.b` and `&mut a.b` -- but that by itself wouldn't work, because the type doesn't match. So we rewrite each access to `a.b` to desugar to a dereference of the `a_b` field, like `*self.a_b`:

```rust
move(&a.b) || { foo(a.b) }

// desugars to

struct MyStruct<'l> {
    a_b: &'l Foo
}

impl FnOnce for MyStruct<'_> {
    fn call_once(self) {
        foo(*self.a_b)
        //  ---------
        //  we insert the `*` too
    }
}

MyStruct {
    a_b: &a.b,
}

move(&a.b) || { foo(*a.b) }
```

There's a lot of precedence for this sort of transform: it's precisely what we do for the `Deref` trait and for existing closure captures.

## Fresh variables

We should also allow you to define fresh variables. These can have arbitrary types. The values are evaluated at closure creation time and stored in the closure metadata:

```rust
move(
    data = load_data(),
    y,
) || {
    take(&data, y)
}
```

## Open-ended captures

All of our examples so far fully enumerated the captured variables. But Rust closures today infer the set of captures (and the style of capture) based on the paths that are used. We should permit that as well. I'd permit that with a `..` sugar, so these two closures are equivalent:

```rust
let c2 = move || /* closure */;
//       ---- capture anything that is used,
//            taking ownership

let c1 = move(..) || /* closure */;
//           ---- capture anything else that is used,
//                taking ownership
```

Of course you can combine:

```rust
let c = move(x.y.clone(), ..) || {

};
```

And you could write `ref` to get the equivalent of `||` closures:


```rust
let c2 = || /* closure */;
//       -- capture anything that is used,
//          using references if possible
let c1 = move(ref) || /* closure */;
//            --- capture anything else that is used,
//                using references if possible
```

This lets you 

```rust
let c = move(
    a.b.clone(), 
    c,
    ref
) || {
    combine(&a.b, &c, &z)
    //       ---   -   -
    //        |    |   |
    //        |    | This will be captured by reference
    //        |    | since it is used by reference
    //        |    | and is not explicitly named.
    //        |    |
    //        |   This will be captured by value
    //        |   since it is explicitly named.
    //        |
    // We will capture a clone of this because
    // the user wrote `a.b.clone()`
}
```


## Frequently asked questions

### How does this help with our motivation?

Let's look at the motivations I named:

#### Teaching and understanding closure desugaring is difficult

There's a lot of syntax there, but it also gives you an explicit form that you can use to do explanations. To see what I mean, consider the difference between these two closures ([playground]()).

The first closure uses `||`:

```rust
fn main() {
    let mut i = 3;
    let mut c_attached = || {
        let j = i + 1;
        std::mem::replace(&mut i, j)
    };
    ...
}
```

While the second closure uses `move`:

```rust
fn main() {
    let mut i = 3;
    let mut c_detached = move || {
        let j = i + 1;
        std::mem::replace(&mut i, j)
    };
```

These are in fact pretty different, [as you can see in this playground](https://play.rust-lang.org/?version=stable&mode=debug&edition=2024&gist=fec374e4055a99aa3dda9e66a5c03495). But why? Well, the first closure desugars to capture a reference:

```rust
let mut i = 3;
let mut c_attached = move(&i) || {...};
```

and the second captures by value:

```rust
let mut i = 3;
let mut c_attached = move(i) || {...};
```

Before, to explain that, I had to resort to desugaring to structs.

#### Capturing a clone is painful

If you have a closure that wants to capture the clone of something today, you have to introduce a fresh variable. So something like this:

```rust
let closure = move || {
    begin_actor(data, self.tx.clone())
};
```

becomes

```rust
let closure = {
    let self_tx = self.tx.clone();
    move || {
        begin_actor(data, self_tx.clone())
    }
};
```

This is awkward. Under this proposal, it's possible to point-wise replace specific items:

```rust
let closure = move(self.tx.clone(), ..) || {
    begin_actor(data, self.tx.clone())
};
```

#### For long closure bodies, it is hard to determine precisely which values are captured and how

Quick! What variables does this closure use from the environment?

```rust
.flat_map(move |(severity, lints)| {
    parse_tt_as_comma_sep_paths(lints, edition)
    .into_iter()
    .flat_map(move |lints| {
        // Rejoin the idents with `::`, so we have no spaces in between.
        lints.into_iter().map(move |lint| {
            (
                lint.segments().filter_map(
                    |segment| segment.name_ref()
                ).join("::").into(),
                severity,
            )
        })
    })
})
```

No idea? Me either. What about this one?

```rust
.flat_map(move(edition) |(severity, lints)| {
    /* same as above */
})
```

Ah, pretty clear! I find that once a closure moves beyond a couple of lines, it can make a function kind of hard to read, because it's hard to tell what variables it may be accessing. I've had functions where it's important to correctness for one reason or another that a particular closure only accesses a subset of the values around it, but I have no way to indicate that right now. Sometimes I make separate functions, but it'd be nicer if I could annotate the closure's captures explicitly.

#### It is hard to develop an intuition for when `move` is required

Hmm, actually, I don't think this notation helps with that at all! More about this below.

Let me cover some of the questions you may have about this design.

### Why allow the "capture clause" to specify an entire place, like `a.b.c`?

Today you can write closures that capture places, like `self.context` below:

```rust
let closure = move || {
    send_data(self.context, self.other_field)
};
```

My goal was to be able to take such a closure and to add annotations that change how particular places are captured, without having to do deep rewrites in the body:

```rust
let closure = move(self.context.clone(), ..) || {
    //            --------------------------
    //            the only change
    send_data(self.context, self.other_field)
};
```

This definitely adds some complexity, because it means we have to be able to "remap" a place like `a.b.c` that has multiple parts. But it makes the explicit capture syntax far more powerful and convenient.

### Why do you keep the type the same for places like `a.b.c`?

I want to ensure that the type of `a.b.c` is the same wherever it is type-checked, it'll simplify the compiler somewhat and just generally makes it easier to move code into and out of a closure.

### Why the move keyword?

Because it's there? To be honest, I don't like the choice of `move` because it's so *operational*. I think if I could go back, I would try to refashion our closures around two concepts

* *Attached* closures (what we now call `||`) would *always* be tied to the enclosing stack frame. They'd always have a lifetime even if they don't capture anything.
* *Detached* closures (what we now call `move ||`) would capture by-value, like `move` today.

I think this would help to build up the intuition of "use `detach ||` if you are going to return the closure from the current stack frame and use `||` otherwise".

### What would a max-min explicit capture proposal look like?

A maximally minimal explicit capture close proposal would probably *just* let you name specific variables and not "subplaces":

```rust
move(
    a_b_c = a.b.c,
    x_y = &x.y
) || {
    *x_y + a_b_c
}
```

I think you can see though that this makes introducing an explicit form a lot less pleasant to use and hence isn't really going to do anything to support ergonomic RC.

## Conclusion: Explicit closure clauses make things better, but not great

I think doing explicit capture clauses is a good idea -- I generally think we should have explicit syntax for everything in Rust, for teaching and explanatory purposes if nothing else; I didn't always think this way, but it's something I've come to appreciate over time.

I'm not sold on this specific proposal -- but I think working through it is useful, because it (a) gives you an idea of what the benefits would be and (b) gives you an idea of how much hidden complexity there is.

I think the proposal shows that adding explicit capture clauses goes *some* way towards making things explicit *and* ergonomic. Writing `move(a.b.c.clone())` is definitely better than having to create a new binding.

But for me, it's not really nice *enough*. It's still quite a mental distraction to have to find the start of the closure, insert the `a.b.c.clone()` call, and it makes the closure header very long and unwieldy. Particularly for short closures the overhead is very high.

This is why I'd like to look into other options. Nonetheless, it's useful to have discussed a proposal for an explicit form: if nothing else, it'll be useful to explain the precise semantics of other proposals later on.
