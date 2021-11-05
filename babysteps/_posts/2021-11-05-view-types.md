---
layout: post
title: "View types for Rust"
date: 2021-11-05 11:37 -0400
---

I wanted to write about an idea that's been kicking around in the back of my mind for some time. I call it *view types*. The basic idea is to give a way for an `&mut` or `&` reference to identify which fields it is actually going to access. The main use case for this is having "disjoint" methods that don't interfere with one another.

### This is not a propsoal (yet?)

To be clear, this isn't an RFC or a proposal, at least not yet. It's some early stage ideas that I wanted to document. I'd love to hear reactions and thoughts, as I discuss in the conclusion.

### Running example

As a running example, consider this struct `WonkaChoclateShipment`. It combines a vector `bars` of `ChocolateBars` and a list `golden_tickets` of indices for bars that should receive a ticket.

```rust
struct WonkaShipmentManifest {
    bars: Vec<ChocolateBar>,
    golden_tickets: Vec<usize>,
}
```

Now suppose we want to iterate over those bars and put them into their packaging. Along the way, we'll insert a golden ticket. To start, we write a 
little function that checks whether a given bar should receive a golden ticket:

```rust
impl WonkaShipmentManifest {
    fn should_insert_ticket(&self, index: usize) -> bool {
        self.golden_tickets.contains(&index)
    }
}
```

Next, we write the loop that iterates over the chocolate bars and prepares them for shipment:

```rust
impl WonkaShipmentManifest {
    fn prepare_shipment(self) -> Vec<WrappedChocolateBar> {
        let mut result = vec![];
        for (bar, i) in self.bars.into_iter().zip(0..) {
            let opt_ticket = if self.should_insert_ticket(i) {
                Some(GoldenTicket::new())
            } else {
                None
            };
            result.push(bar.into_wrapped(opt_ticket));
        }
        result
    }
}
```

Satisfied with [our code](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=a6622a8e4dc3a47576035b848b2cf3ef), we sit back and fire up the compiler and, wait... what's this?

```
error[E0382]: borrow of partially moved value: `self`
   --> src/lib.rs:16:33
    |
15  |         for (bar, i) in self.bars.into_iter().zip(0..) {
    |                                   ----------- `self.bars` partially moved due to this method call
16  |             let opt_ticket = if self.should_insert_ticket(i) {
    |                                 ^^^^ value borrowed here after partial move
    |
   ```

Well, the message makes *sense*, but it's unnecessary! The compiler is concerned because we are borrowing `self` when we've already moved out of the field `self.bars`, but we know that `should_insert_ticket` is only going to look at `self.golden_tickets`, and that value is still intact. So there's not a real conflict here.

Still, thinking on it more, you can see why the compiler is complaining. It only looks at one function at a time, so how would it know what fields `should_insert_ticket` is going to read? And, even if were to look at the body of `should_insert_ticket`, maybe it's reasonable to give a warning for future-proofing. Without knowing more about our plans here at Wonka Inc., it's reasonable to assume that future code authors may modify `should_insert_ticket` to look at `self.bars` or any other field. This is part of the reason that Rust does its analysis on a per-function basis: checking each function independently gives room for other functions to change, so long as they don't change their signature, without disturbing their callers.

What we need, then, is a way for `should_insert_ticket` to describe to its callers which fields it may use and which ones it won't. Then the caller could permit invoking `should_insert_ticket` whenever the field `self.golden_tickets` is accessible, even if other fields are borrowed or have been moved.

### An idea

When I've thought about this problem in the past, I've usually imagined that the list of "fields that may be accessed" would be attached to the *reference*. But that's a bit odd, because a reference type `&mut T` doesn't itself have an fields. The fields come from `T`.

So recently I was thinking, what if we had a *view* type? I'll write it `{place1, ..., placeN} T` for now. What it means is "an instance of `T`, but where only the paths `place1...placeN` are accessible". Like other types, view types can be borrowed. In our example, then, `&{golden_tickets} WonkaShipmentManifest` would describe a reference to `WonkaShipmentManifest` which only gives access to the `golden_tickets` field. 

### Creating a view

We could use some syntax like `{place1..placeN} expr` to create a view type[^bikeshed]. This would be a *place expression*, which means that it refers to a specific place in memory. This means that it can be directly borrowed without creating a temporary. So I can create a view onto `self` that only has access to `bars_counter` like so:

```rust
impl WonkaShipmentManifest {
    fn example_a(&mut self) {
        let self1 = &{golden_tickets} self;
        println!("tickets = {:#?}", self1.golden_tickets);
    }
}
```

Notice the distinction between `&self.golden_tickets` and `&{golden_tickets} self`. The former borrows the field directly. The latter borrows the entire struct, but only gives access to one field. What happens if you try to access another field? An error, of course:

```rust
impl WonkaShipmentManifest {
    fn example_b(&mut self) {
        let self1 = &{golden_tickets} self;
        println!("tickets = {:#?}", self1.golden_tickets);
        for bar in &self1.bars {
            //      ^^^^^^^^^^
            // Error: self1 does not have access to `bars`
        }
    }
}
```

Of course, when a view is active, you can still access other fields through the original path, without disturbing the borrow:

```rust
impl WonkaShipmentManifest {
    fn example_c(&mut self) {
        let self1 = &{golden_tickets) self;
        
        for bar in &mut self.bars {
            println!("tickets = {:#?}", self1.golden_tickets);
        }
    }
}
```

And, naturally, that access includes the ability to create multiple views at once, so long as they have disjoint paths:

```rust
impl WonkaShipmentManifest {
    fn example_d(&mut self) {
        let self1 = &{golden_tickets) self;
        let self2 = &mut {bars} self;
        
        for bar in &mut self2.bars {
            println!("tickets = {:#?}", self1.golden_tickets);
            bar.modify();
        }
    }
}
```

[^bikeshed]: Yes, this is ambiguous. Think of it as my way of encouraging you to bikeshed something better.

### View types in methods

As example C in the previous section suggested, we can use a view type in our definition of `should_insert_ticket` to specify which fields it will use:

```rust
impl WonkaChocolateFactory {
    fn should_insert_ticket(&{golden_tickets} self, index: usize) -> bool {
        self.golden_tickets.contains(&index)
    }
}
```

As a result of doing this, we can successfully compile the `prepare_shipment` function:

```rust
impl WonkaShipmentManifest {
    fn prepare_shipment(self) -> Vec<WrappedChocolateBar> {
        let mut result = vec![];
        for (bar, i) in self.bars.into_iter().zip(0..) {
            //          ^^^^^^^^^^^^^^^^^^^^^
            // Moving out of `self.bars` here....
            let opt_ticket = if self.should_insert_ticket(i) {
                //              ^^^^
                // ...does not conflict with borrowing a
                // view of `{golden_tickets}` from `self` here.
                Some(GoldenTicket::new())
            } else {
                None
            };
            result.push(bar.into_wrapped(opt_ticket));
        }
        result
    }
}
```

### View types with access modes

All my examples so far were with "shared" views through `&` references. We could of course say that `&mut {bars} WonkaShipmentManifest` gives mutable access to the field `bars`, but it might also be nice to have an explicit `mut` mode, such that you write `&mut {mut bars} WonkaShipmentManifest`. This is more verbose, but it permits one to give away a mix of "shared" and "mut" access:

```rust
impl WonkaShipmentManifest {
    fn add_ticket(&mut {bars, mut golden_tickets} self, index: usize) {
        //              ^^^^  ^^^^^^^^^^^^^^^^^^^
        //              |     mut access to golden-tickets
        //              shared access to bars
        assert!(index < self.bars.len());
        self.golden_tickets.push(index);
    }
}
```

One could invoke `add_ticket` even if you had existing borrows to `bars`:

```rust
fn foo() {
    let manifest = WonkaShipmentManifest { bars, golden_tickets };
    let bar0 = &manifest.bars[0];
    //         ^^^^^^^^^^^^^^ shared borrow of `manifest.bars`...
    manifest.add_ticket(22);
    //      ^ borrows `self` mutably, but with view
    //        `{bars, mut golden_tickets}`
    println!("debug: {:?}", bar0);
}
```

### View types and ownership

I've always shown view types with references, but combining them with ownership makes for other interesting possibilities. For example, suppose I wanted to extend `GoldenTicket` with some kind of unique `serial_number` that should never change, along with a `owner` field that will be mutated over time. For various reasons[^convenience], I might like to make the fields of `GoldenTicket` public:

[^convenience]: 

```rust
pub struct GoldenTicket {
    pub serial_number: usize,
    pub owner: Option<String>,
}

impl GoldenTicket {
    pub fn new() -> Self {
        Self { .. }
    }
}
```

However, if I do that, then nothing stops future owners of a `GoldenTicket` from altering its `serial_number`:

```rust
let mut t = GoldenTicket::new();
t.serial_number += 1; // uh-oh!
```

The best answer today is to use a private field and an accessor:

```rust
pub struct GoldenTicket {
    pub serial_number: usize,
    pub owner: Option<String>,
}

impl GoldenTicket {
    pub fn new() -> Self {
        
    }
    
    pub fn serial_number(&self) -> usize {
        self.serial_number
    }
}

```

However, Rust's design kind of discourages accessors. For one thing, the borrow checker doesn't know which fields are used by an accessor, so you have code like this, you will now get annoying errors (this has been the theme of this whole post, of course):

```rust
let mut t = GoldenTicket::new();
let n = &mut t.owner;
compute_new_owner(n, t.serial_number());
```

Furthermore, accessors can be kind of unergonomic, particularly for things that are not copy types. Returning (say) an `&T` from a `get` can be super annoying.

Using a view type, we have some interesting other options. I could define a type alias `GoldenTicket` that is a limited view onto the underlying data:

```rust
pub type GoldenTicket = {serial_number, mut owner} GoldenTicketData;

pub struct GoldenTicketData {
    pub serial_number: usize,
    pub owner: Option<String>,
    dummy: (),
}
```

Now if my constructor function only ever creates this view, we know that nobody will be able to modify the `serial_number` for a `GoldenTicket`:

```rust
impl GoldenTicket {
    pub fn new() -> GoldenTicket {
        
    }
}
```

Obviously, this is not ergonomic to write, but it's interesting that it is possible.

### View types vs privacy

As you may have noticed in the previous example, view types interact with traditional privacy in interesting ways. It seems like there may be room for some sort of unification, but the two are also different. Traditional privacy (`pub` fields and so on) is like a view type in that, if you are outside the module, you can't access private fields. *Unlike* a view, though, you can call methods on the type that *do* access those fields. In other words, traditional privacy denies you *direct* access, but permits *intermediated* access.

View types, in contrast, are "transitive" and apply both to direct and intermediated actions. If I have a view `{serial_number} GoldenTicketData`, I cannot access the `owner` field at all, even by invoking methods on the type.

### Longer places

My examples so far have only shown views onto individual fields, but there is no reason we can't have a view onto an arbitrary place. For example, one could write:

```rust
struct Point { x: u32, y: u32 }
struct Square { upper_left: Point, lower_right: Point }

let mut s: Square = Square { upper_left: Point { x: 22, y: 44 }, lower_right: Point { x: 66, y: 88 } };
let s_x = &{upper_left.x} s;
```

to get a view of type `&{upper_left.x} Square`. Paths like `s.upper_left.y` and `s.lower_right` would then still be mutable and not considered borrowed.

### View types and named groups

There is another interaction with view types and privacy: view types name fields, but if you have private fields, you probably don't want people outside your module typing their names, since that would prevent you from renaming them. At the same time, you might like to be able to let users refer to "groups of data" more abstractly. For example, for a `WonkaChocolateShipment`, I might like users to know they can iterate the bars *and* check if they have a golden ticket at once:

```rust
impl WonkaShipmentManifest {
    pub fn should_insert_ticket(&{golden_tickets} self, index: usize) -> bool {
        self.golden_tickets.contains(&index)
    }
    pub fn iter_bars_mut(&mut {bars} self) -> impl Iterator<Item = &mut Bar> {
        &mut self.bars
    }
}
```

But how should we express that to users without having them name fields directly? The obvious extension is to have some kind of "logical" fields that represent groups of data that can change over time. I don't know how to declare those groups though.

### Groups could be more DRY 

Another reason to want named groups is to avoid repeating the names of common sets of fields over and over. It's easy to imagine that there might be a few fields that some cluster of methods all want to access, and that repeating those names will be annoying and make the code harder to edit.

One positive thing from Rust's current restrictions is that it has sometimes encouraged me to factor a single large type into multiple smaller ones, where the smaller ones encapsulate a group of logically related fields that are accessed together.[^ex] On the other hand, I've also encountered situations where such refactorings feel quite arbitrary -- I have groups of fields that, yes, are accessed together, but which don't form a logical unit on their own. 

As an example of both why this sort of refactoring can be good and bad at the same time, I introduced the [`cfg`] field of the MIR [`Builder`](https://doc.rust-lang.org/nightly/nightly-rustc/rustc_mir_build/build/struct.Builder.html) type to resolve errors where some methods only accessed a subset of fields. On the one hand, the CFG-related data is indeed conceptually distinct from the rest. On the other, the CFG type isn't something you would use independently of the `Builder` itself, and I don't feel that writing `self.cfg.foo` instead of `self.foo` made the code particularly clearer.

### View types and fields in traits

Some time back, I had a draft RFC for [fields in traits](https://github.com/nikomatsakis/fields-in-traits-rfc/blob/master/0000-fields-in-traits.md). That RFC was "postponed" and moved to a repo to iterate, but I have never had the time to invest in bringing it back. It has some obvious overlap with this idea of views, and (iirc) I had at some point considered using "fields in traits" as the basis for declaring views. I think I rather like this more "structural" approach, but perhaps traits with fields might be a way to give names to groups of fields that public users can reference. Have to mull on that.

### How does this affect learning?

I'm always way about extending "core Rust" because I don't want to make Rust harder to learn. However, I also tend to feel that extensions like this one can have the opposite effect: I think that what throws people the *most* when learning Rust is trying to get a feel for what they can and cannot do. When they hit "arbitrary" restrictions like "cannot say that my helper function only uses a subset of my fields"[^eg] that can often be the most confusing thing of all, because at first people think that they just don't understand the system. "Surely there must be some way to do this!"

Going a bit further, one of the other challenges with Rust's borrow checker is that so much of its reasoning is invisible and lacks explicit syntax. There is no way to "hand annotate" the value of lifetime parameters, for example, so as to explore how they work. Similarly, the borrow checker is currently tracking fine-grained state about which paths are borrowed in your program, but you have no way to *talk* about that logic explicitly. Adding explicit types may indeed prove *helpful* for learning.

[^eg]: Another example is that there is no way to have a struct that has references to its own fields.

### But there must be some risks?

Yes, for sure. One of the best and worst things about Rust is that your public API docs force you to make decisions like "do I want `&self` or `&mut self` access for this function?" It pushes a lot of design up front (raising the risk of [premature commitment][cdn]) and makes things harder to change (more [viscous][cdn]). If it became "the norm" for people to document fine-grained information about which methods use which groups of fields, I worry that it would create more opportunities for semver-hazards, and also just make the docs harder to read.

On the other side, one of my observations it that **public-facing** types don't want views that often; the main exception is that sometimes it'd be nice small accessors (for example, a `Vec` might like to document that one can read `len` even when iterating). Most of the time I find myself frustrated with this particular limitation of Rust, it has to do with private helper functions (similar to the initial example). In those cases, I think that the documentation is actually *helpful*, since it guides people who are reading and helps them know what to expect from the function.

[cdn]: https://en.wikipedia.org/wiki/Cognitive_dimensions_of_notations

### Conclusion

This concludes our tour of "view types", a proto-proposal. I hope you enjoyed your ride. Curious to hear what people think! I've opened an [thread on internals](https://internals.rust-lang.org/t/blog-post-view-types-for-rust/15556) for feedback. I'd love to know if you feel this would solve problems for you, but also how you think it would affect Rust learning -- not to mention better syntax ideas.

I'd also be interested to read about related work. The idea here seems likely to have been invented and re-invented numerous times. What other languages, either in academic or industry, have similar mechanisms? How do they work? Educate me!

### Footnotes

