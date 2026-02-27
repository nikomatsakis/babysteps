---
title: "How Dada enables internal references"
date: 2026-02-27T05:20:38-05:00
series:
  - Dada
dada_keywords:
  - "let"
  - "fn"
  - "class"
  - "given"
  - "give"
  - "shared"
  - "share"
  - "ref"
dada_types:
  - "String"
  - "Point"
  - "Vec"
  - "Map"
  - "Character"
  - "u32"
---

In my previous Dada blog post, I talked about how Dada enables composable sharing. Today I'm going to start diving into Dada's *permission* system; permissions are Dada's equivalent to Rust's borrow checker.

## Goal: richer, place-based permissions

Dada aims to exceed Rust's capabilities by using place-based permissions. Dada lets you write functions and types that capture both a *value* and *things borrowed from that value*.

As a fun example, imagine you are writing some Rust code to process a comma-separated list, just looking for entries of length 5 or more:

```rust
let list: String = format!("...something big, with commas...");
let items: Vec<&str> = list
    .split(",")
    .map(|s| s.trim()) // strip whitespace
    .filter(|s| s.len() > 5)
    .collect();
```

One of the cool things about Rust is how this code looks a lot like some high-level language like Python or JavaScript, but in those languages the `split` call is going to be doing a lot of work, since it will have to allocate tons of small strings, copying out the data. But in Rust the `&str` values are just pointers into the original string and so `split` is very cheap. I love this.

On the other hand, suppose you want to package up some of those values, along with the backing string, and send them to another thread to be processed. You might think you can just make a struct like so...

```rust
struct Message {
    list: String,
    items: Vec<&str>,
    //         ----
    // goal is to hold a reference
    // to strings from list
}
```

...and then create the list and items and store them into it:

```rust
let list: String = format!("...something big, with commas...");
let items: Vec<&str> = /* as before */;
let message = Message { list, items };
//                      ----
//                        |
// This *moves* `list` into the struct.
// That in turn invalidates `items`, which 
// is borrowed from `list`, so there is no
// way to construct `Message`.
```

But as experienced Rustaceans know, this will not work. When you have borrowed data like an `&str`, that data cannot be moved. If you want to handle a case like this, you need to convert from `&str` into sending indices, owned strings, or some other solution. Argh!

## Dada's permissions use *places*, not *lifetimes*

Dada does things a bit differently. The first thing is that, when you create a reference, the resulting type names the *place that the data was borrowed from*, not the *lifetime of the reference*. So the type annotation for `items` would say `ref[list] String`[^str] (at least, if you wanted to write out the full details rather than leaving it to the type inferencer):

[^str]: I'll note in passing that Dada unifies `str` and `String` into one type as well. I'll talk in detail about how that works in a future blog post.

```dada
let list: given String = "...something big, with commas..."
let items: given Vec[ref[list] String] = list
    .split(",")
    .map(_.trim()) // strip whitespace
    .filter(_.len() > 5)
    //      ------- I *think* this is the syntax I want for closures?
    //              I forget what I had in mind, it's not implemented.
    .collect()
```

I've blogged before about [how I would like to redefine lifetimes in Rust to be places](https://smallcultfollowing.com/babysteps/blog/2024/03/04/borrow-checking-without-lifetimes/) as I feel that a type like `ref[list] String` is much easier to teach and explain: instead of having to explain that a lifetime references some part of the code, or what have you, you can say that "this is a `String` that references the variable `list`".

But what's also cool is that named places open the door to more flexible borrows. In Dada, if you wanted to package up the list and the items, you could build a `Message` type like so:

```dada
class Message(
    list: String
    items: Vec[ref[self.list] String]
    //             ---------
    //   Borrowed from another field!
)

// As before:
let list: String = "...something big, with commas..."
let items: Vec[ref[list] String] = list
    .split(",")
    .map(_.strip()) // strip whitespace
    .filter(_.len() > 5)
    .collect()

// Create the message, this is the fun part!
let message = Message(list.give, items.give)
```

Note that last line -- `Message(list.give, items.give)`. We can create a new class and move `list` into it *along with* `items`, which borrows from list. Neat, right?

OK, so let's back up and talk about how this all works.

## References in Dada are the default

Let's start with syntax. Before we tackle the `Message` example, I want to go back to the `Character` example from previous posts, because it's a bit easier for explanatory purposes. Here is some Rust code that declares a struct `Character`, creates an owned copy of it, and then gets a few references into it.

```rust
struct Character {
    name: String,
    class: String,
    hp: u32,
}

let ch: Character = Character {
    name: format!("Ferris"),
    class: format!("Rustacean"),
    hp: 22
};

let p: &Character = &ch;
let q: &String = &p.name;
```

The Dada equivalent to this code is as follows:

```dada
class Character(
    name: String,
    klass: String,
    hp: u32,
)

let ch: Character = Character("Tzara", "Dadaist", 22)
let p: ref[ch] Character = ch
let q: ref[p] String = p.name
```

The first thing to note is that, in Dada, the **default** when you name a variable or a place is to create a reference. So `let p = ch` doesn't move `ch`, as it would in Rust, it creates a reference to the `Character` stored in `ch`. You could also explicitly write `let p = ch.ref`, but that is not preferred. Similarly, `let q = p.name` creates a reference to the value in the field `name`. (If you wanted to *move* the character, you would write `let ch2 = ch.give`, not `let ch2 = ch` as in Rust.)

Notice that I said `let p = ch` "creates a reference to the `Character` stored in `ch`". In particular, I did *not* say "creates a reference to `ch`". That's a subtle choice of wording, but it has big implications.

## References in Dada are not pointers

The reason I wrote that `let p = ch` "creates a reference to the `Character` stored in `ch`" and not "creates a reference to `ch`" is because, in Dada, *references are not pointers*. Rather, they are shallow copies of the value, very much like how we saw in the previous post that a `shared Character` *acts* like an `Arc<Character>` but is represented as a shallow copy.

So where in Rust the following code...

```rust
let ch = Character { ... };
let p = &ch;
let q = &ch.name;
```

...looks like this in memory...

```
        # Rust memory representation

            Stack                       Heap
            ─────                       ────

┌───► ch: Character {
│ ┌───► name: String {
│ │         buffer: ───────────► "Ferris"
│ │         length: 6
│ │         capacity: 12
│ │     },
│ │     ...
│ │   }
│ │   
└──── p
  │
  └── q
```

in Dada, code like this

```dada
let ch = Character(...)
let p = ch
let q = ch.name
```

would look like so

```
# Dada memory representation

Stack                       Heap
─────                       ────

ch: Character {
    name: String {
            buffer: ───────┬───► "Ferris"
            length: 6      │
            capacity: 12   │
    },                     │
    ..                     │
}                          │
                           │
p: Character {             │
    name: String {         │
            buffer: ───────┤
            length: 6      │
            capacity: 12   │
    ...                    │
}                          │
    }                      │
                           │
q: String {                │
    buffer: ───────────────┘
    length: 6
    capacity: 12
}
```

Clearly, the Dada representation takes up more memory on the stack. But note that it *doesn't* duplicate the memory in the heap, which tends to be where the vast majority of the data is found.

## Dada talks about *values* not *references*

This gets at something important. Rust, like C, makes pointers first-class. So given `x: &String`, `x` refers to *the pointer* and `*x` refers to its referent, the `String`.

Dada, like Java, goes another way. `x: ref String` *is* a `String` value -- including in memory representation! The difference between a `given String`, `shared String`, and `ref String` is not in their memory layout, all of them are the same, but they differ in whether they **own their contents**.[^vscpp]

So in Dada, there is no `*x` operation to go from "pointer" to "referent". That doesn't make sense. Your variable always contains a string, but the permissions you have to use that string will change.

In fact, the goal is that people *don't* have to learn the memory representation as they learn Dada, you are supposed to be able to think of Dada variables as if they were all objects on the heap, just like in Java or Python, even though in fact they are stored on the stack.[^dev]

[^dev]: This goal was in part inspired by a conversation I had early on within Amazon, where a (quite experienced) developer told me, "It took me months to understand what variables are in Rust".

[^vscpp]: This is *kind* of like C++ references (e.g., `String&`), which also act "as if" they were a value (i.e., you write `s.foo()`, not `s->foo()`), but a C++ reference is truly a pointer, unlike a Dada ref.

## Rust does not permit moves of borrowed data

In Rust, you cannot move values while they are borrowed. So if you have code like this that moves `ch` into `ch1`...

```rust
let ch = Character { ... };
let name = &ch.name; // create reference
let ch1 = ch;        // moves `ch`
```

...then this code only compiles if `name` is not used again:

```rust
let ch = Character { ... };
let name = &ch.name; // create reference
let ch1 = ch;        // ERROR: cannot move while borrowed
let name1 = name;    // use reference again
```

## ...but Dada can

There are two reasons that Rust forbids moves of borrowed data:

* References are pointers, so those pointers may become invalidated. In the example above, `name` points to the stack slot for `ch`, so if `ch` were to be moved into `ch1`, that makes the reference invalid.
* The type system would lose track of things. Internally, the Rust borrow checker has a kind of "indirection". It knows that `ch` is borrowed for some span of the code (a "lifetime"), and it knows that the lifetime in the type of `name` is related to that lifetime, but it doesn't really know that `name` is borrowed from `ch` in particular.[^polonius]

[^polonius]: I explained this some years back in a [talk on Polonius at Rust Belt Rust](https://www.youtube.com/watch?v=_agDeiWek8w), if you'd like more detail.

Neither of these apply to Dada:

* Because references are not pointers into the stack, but rather shallow copies, moving the borrowed value doesn't invalidate their contents. They remain valid.
* Because Dada's types reference actual variable names, we can modify them to reflect moves.

## Dada tracks moves in its types

OK, let's revisit that Rust example that was giving us an error. When we convert it to Dada, we find that it type checks just fine:

```dada
class Character(...) // as before
let ch: given Character = Character(...)
let name: ref[ch.name] String = ch.name
//            -- originally it was borrowed from `ch`
let ch1 = ch.give
//        ------- but `ch` was moved to `ch1`
let name1: ref[ch1.name] = name
//             --- now it is borrowed from `ch1`
```

Woah, neat! We can see that when we move from `ch` into `ch1`, the compiler updates the types of the variables around it. So actually the type of `name` changes to `ref[ch1.name] String`. And then when we move from `name` to `name1`, that's totally valid.

In PL land, updating the type of a variable from one thing to another is called a "strong update". Obviously things can get a bit complicated when control-flow is involved, e.g., in a situation like this:

```dada
let ch = Character(...)
let ch1 = Character(...)
let name = ch.name
if some_condition_is_true() {
    // On this path, the type of `name` changes
    // to `ref[ch1.name] String`, and so `ch`
    // is no longer considered borrowed.
    ch1 = ch.give
    ch = Character(...) // not borrowed, we can mutate
} else {
    // On this path, the type of `name`
    // remains unchanged, and `ch` is borrowed.
}
// Here, the types are merged, so the
// type of `name` is `ref[ch.name, ch1.name] String`.
// Therefore, `ch` is considered borrowed here.
```

## Renaming lets us call functions with borrowed values

OK, let's take the next step. Let's define a Dada function that takes an owned value and another value borrowed from it, like the name, and then call it:

```dada
fn character_and_name(
    ch1: given Character,
    name1: ref[ch1] String,
) {
    // ... does something ...
}
```

We could call this function like so, as you might expect:

```dada
let ch = Character(...)
let name = ch.name
character_and_name(ch.give, name)
```

So...how does this work? Internally, the type checker type-checks a function call by creating a simpler snippet of code, essentially, and then type-checking *that*. It's like desugaring but only at type-check time. In this simpler snippet, there are a series of `let` statements to create temporary variables for each argument. These temporaries always have an explicit type taken from the method signature, and they are initialized with the values of each argument:

```dada
// type checker "desugars" `character_and_name(ch.give, name)`
// into more primitive operations:
let tmp1: given Character = ch.give
    //    ---------------   -------
    //            |         taken from the call
    //    taken from fn sig
let tmp2: ref[tmp1.name] String = name
    //    ---------------------   ----
    //            |         taken from the call
    //    taken from fn sig,
    //    but rewritten to use the new
    //    temporaries
```

If this type checks, then the type checker knows you have supplied values of the required types, and so this is a valid call. Of course there are a few more steps, but that's the basic idea.

Notice what happens if you supply data borrowed from the wrong place:

```dada
let ch = Character(...)
let ch1 = Character(...)
character_and_name(ch, ch1.name)
//                     --- wrong place!
```

This will fail to type check because you get:

```dada
let tmp1: given Character = ch.give
let tmp2: ref[tmp1.name] String = ch1.name
    //                            --------
    //       has type `ref[ch1.name] String`,
    //       not `ref[tmp1.name] String`
```

## Class constructors are "just" special functions

So now, if we go all the way back to our original example, we can see how the `Message` example worked:

```dada
class Message(
    list: String
    items: Vec[ref[self.list] String]
)
```

Basically, when you construct a `Message(list, items)`, that's "just another function call" from the type system's perspective, except that `self` in the signature is handled carefully.

## This is modeled, not implemented

I should be clear, this system is modeled in the [dada-model](https://github.com/dada-lang/dada-model/) repository, which implements a kind of "mini Dada" that captures what I believe to be the most interesting bits. I'm working on fleshing out that model a bit more, but it's got most of what I showed you here.[^closures] For example, [here is a test](https://github.com/dada-lang/dada-model/blob/b6833b57af8f0b293755410760c240b75fbf4998/src/type_system/tests/new_with_self_references.rs#L61-L99) that you get an error when you give a reference to the wrong value.

[^closures]: No closures or iterator chains!

The "real implementation" is lagging quite a bit, and doesn't really handle the interesting bits yet. Scaling it up from model to real implementation involves solving type inference and some other thorny challenges, and I haven't gotten there yet -- though I have some pretty interesting experiments going on there too, in terms of the compiler architecture.[^async]

[^async]: As a teaser, I'm building it in async Rust, where each inference variable is a "future" and use "await" to find out when other parts of the code might have added constraints.

## This could apply to Rust

I believe we could apply most of this system to Rust. Obviously we'd have to rework the borrow checker to be based on places, but that's the straight-forward part. The harder bit is the fact that `&T` is a pointer in Rust, and that we cannot readily change. However, for many use cases of self-references, this isn't as important as it sounds. Often, the data you wish to reference is living in the heap, and so the pointer isn't actually invalidated when the original value is moved.

Consider our opening example. You might imagine Rust allowing something like this in Rust:

```rust
struct Message {
    list: String,
    items: Vec<&{self.list} str>,
}
```

In this case, the `str` data is heap-allocated, so moving the string doesn't actually invalidate the `&str` value (it *would* invalidate an `&String` value, interestingly).

In Rust today, the compiler doesn't know all the details of what's going on. `String` has a `Deref` impl and so it's quite opaque whether `str` is heap-allocated or not. But we are working on various changes to this system in the [Beyond the `&`](https://rust-lang.github.io/rust-project-goals/2026/roadmap-beyond-the-ampersand.html) goal, most notably the [Field Projections](https://rust-lang.github.io/rust-project-goals/2026/field-projections.html) work. There is likely some opportunity to address this in that context, though to be honest I'm behind in catching up on the details.



