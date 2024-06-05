---
title: "The borrow checker within"
date: 2024-06-02T08:33:48-04:00
---

This post lays out a 4-part roadmap for the borrow checker that I call "the borrow checker within". These changes are meant to help Rust become a better version of itself, enabling patterns of code which feel like they fit within Rust's *spirit*, but run afoul of the letter of its *law*. I feel fairly comfortable with the design for each of these items, though work remains to scope out the details. My belief is that a-mir-formality will make a perfect place to do that work.

## Rust's *spirit* is *mutation xor sharing*

When I refer to the *spirit* of the borrow checker, I mean the rules of *mutation xor sharing* that I see as Rust's core design ethos. This basic rule&mdash;that when you are mutating a value using the variable `x`, you should not also be reading that data through a variable `y`&mdash;is what enables Rust's memory safety guarantees and also, I think, contributes to its overall sense of "if it compiles, it works". 

*Mutation xor sharing* is, in some sense, neither necessary nor sufficient. It's not *necessary* because there are many programs (like every program written in Java) that share data like crazy and yet still work fine[^every]. It's also not *sufficient* in that there are many problems that demand some amount of sharing -- which is why Rust has "backdoors" like `Arc<Mutex<T>>`, `AtomicU32`, and&mdash;the ultimate backdoor of them all&mdash;`unsafe`.

[^every]: Well, every program written in Java *does* share data like crazy, but they do not all work fine. But you get what I mean.

But to me the biggest surprise from working on Rust is how often this *mutation xor sharing* pattern is "just right", once you learn how to work with it[^learning]. The other surprise has been seeing the benefits over time: programs written in this style are fundamentally "less surprising" which, in turn, means they are more maintainable over time.

[^learning]: And I think learning how to work with *mutation xor sharing* is a big part of what it means to learn Rust.

In Rust today though there are a number of patterns that are rejected by the borrow checker despite fitting the *mutation xor sharing* pattern. Chipping away at this gap, helping to make the borrow checker's rules a more perfect reflection of *mutation xor sharing*, is what I mean by *the borrow checker within*.

> I saw the angel in the marble and carved until I set him free. — Michelangelo

## OK, enough inspirational rhetoric, let's get to the code.

Ahem, right. Let's do that.

## Step 1: Conditionally return references easily with “Polonius”

Rust 2018 introduced [“non-lexical lifetimes”][nll] — this rather cryptic name refers to an extension of the borrow checker so that it understood the control flow within functions much more deeply. This change made using Rust a much more “fluid” experience, since the borrow checker was able to accept a lot more code.

But NLL does not handle one important case[^asimpl]: conditionally returning references. Here is the canonical example, taken from Remy's [Polonius update blog post][PBP]:

[^asimpl]: NLL as implemented, anyway. The original design was meant to cover conditionally returning references, but the proposed type system was not feasible to implement. Moreover, and I say this as the one who designed it, the formulation in the NLL RFC was not good. It was mind-bending and hard to comprehend. Polonius is much better.

[nll]: https://rust-lang.github.io/rfcs/2094-nll.html

```rust
fn get_default<'r, K: Hash + Eq + Copy, V: Default>(
    map: &'r mut HashMap<K, V>,
    key: K,
) -> &'r mut V {
    match map.get_mut(&key) {
        Some(value) => value,
        None => {
            map.insert(key, V::default());
            //  ------ 💥 Gets an error today,
            //            but not with polonius
            map.get_mut(&key).unwrap()
        }
    }
}  
```

[Remy’s post][PBP] gives more details about why this occurs and how we plan to fix it. It's mostly accurate except that the timeline has  stretched on more than I’d like (of course). But we are making steady progress these days.

[PBP]: https://blog.rust-lang.org/inside-rust/2023/10/06/polonius-update.html

## Step 2: A syntax for lifetimes based on places

The next step is to add an explicit syntax for lifetimes based on “place expressions” (e.g., `x` or `x.y`). I wrote about this in my post [Borrow checking without lifetimes][BCWL]. This is basically taking the formulation that underlies Polonius and adding a syntax. 

The idea would be that, in addition to the abstract lifetime parameters we have today, you could reference program variables and even fields as the “lifetime” of a reference. So you could write `’x` to indicate a value that is “borrowed from the variable `x`”. You could also write `’x.y` to indicate that it was borrowed from the field `y` of `x`, and even `'(x.y, z)` to mean borrowed from *either* `x.y` or `z`. For example:

```rust
struct WidgetFactory {
    manufacturer: String,
    model: String,
}

impl WidgetFactory {
    fn new_widget(&self, name: String) -> Widget {
        let name_suffix: &’name str = &name[3..];
                       // ——- borrowed from “name”
        let model_prefix: &’self.model str = &self.model[..2];
                         // —————- borrowed from “self.model”
    }
}
```

This would make many of lifetime parameters we write today unnecessary. For example, the classic Polonius example where the function takes a parameter `map: &mut Hashmap<K, V>` and returns a reference into the map can be written as follows:

```rust
fn get_default<K: Hash + Eq + Copy, V: Default>(
    map: &mut HashMap<K, V>,
    key: K,
) -> &'map mut V {
    //---- "borrowed from the parameter map"
    ...
}
```

This syntax is more convenient — but I think its bigger impact will be to make Rust more teachable and learnable. Right now, lifetimes are in a tricky place, because

* they represent a concept (spans of code) that isn’t normal for users to think explicitly about and
* they don’t have any kind of syntax.

Syntax is useful when learning because it allows you to make everything explicit, which is a critical intermediate step to really internalizing a concept — what boats memorably called the [dialectical ratchet](https://github.com/rust-lang/rfcs/pull/2071#issuecomment-329026602). Anecdotally I’ve been using a “place-based” syntax when teaching people Rust and I’ve found it is much quicker for them to grasp it.

[BCWL]: https://smallcultfollowing.com/babysteps/blog/2024/03/04/borrow-checking-without-lifetimes/

## Step 3: View types and interprocedural borrows

The next piece of the plan is [view types][VT], which are a way to have functions declare which fields they access. Consider a struct like `WidgetFactory`...

[VT]: https://smallcultfollowing.com/babysteps/blog/2021/11/05/view-types/

```rust
struct WidgetFactory {
    counter: usize,
    widgets: Vec<Widget>,
}
```

...which has a helper function `increment_counter`...

```rust
impl WidgetFactory {
    fn increment_counter(&mut self) {
        self.counter += 1;
    }
}
```

Today, if we want to iterate over the widgets and occasionally increment the counter with `increment_counter`, [we will encounter an error](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=afeb1a8021ab1abf73639ffea0bbcae3):

```rust
impl WidgetFactory {
    fn increment_counter(&mut self) {...}
    
    pub fn count_widgets(&mut self) {
        for widget in &self.widgets {
            if widget.should_be_counted() {
                self.increment_counter();
                // ^ 💥 Can't borrow self as mutable
                //      while iterating over `self.widgets`
            }
        }    
    }
}
```

The problem is that the borrow checker operates one function at a time. It doesn't know precisely which fields `increment_counter` is going to mutate. So it conservatively assumes that `self.widgets` may be changed, and that's not allowed. There are a number of workarounds today, such as writing a "free function" that doesn't take `&mut self` but rather takes references to the individual fields (e.g., `counter: &mut usize`) or even collecting those references into a "view struct" (e.g., `struct WidgetFactoryView<'a> { widgets: &'a [Widget], counter: &'a mut usize }`) but these are non-obvious, annoying, and non-local (they require changing significant parts of your code)

[View types][VT] extend struct types so that instead of just having a type like `WidgetFactory`, you can have a "view" on that type that included only a subset of the fields, like `{counter} WidgetFactory`. We can use this to modify `increment_counter` so that it declares that it will only access the field `counter`:

```rust
impl WidgetFactory {
    fn increment_counter(&mut {counter} self) {
        //               -------------------
        // Equivalent to `self: &mut {counter} WidgetFactory`
        self.counter += 1;
    }
}
```

This allows the compiler to compile `count_widgets` just fine, since it can see that iterating over `self.widgets` while modifying `self.counter` is not a problem.[^2229]

[^2229]: In fact, view types will also allow us to implement the "disjoint closure capture" rules from [RFC 2229][] in a more efficient way. Currently a closure using `self.widgets` and `self.counter` will store 2 references, kind of an implicit "view struct". Although [we found this doesn't really affect much code in practice](https://rust-lang.zulipchat.com/#narrow/stream/189812-t-compiler.2Fwg-rfc-2229/topic/measure.20closure.20sizes), it still bothers me. With view types they could store 1. 

[RFC 2229]: https://rust-lang.github.io/rfcs/2229-capture-disjoint-fields.html

### View types also address phased initialization

There is another place where the borrow checker's rules fall short: *phased initialization*. Rust today follows the functional programming language style of requiring values for all the fields of a struct when it is created. Mostly this is fine, but sometimes you have structs where you want to initialize some of the fields and then invoke helper functions, much like `increment_counter`, to create the remainder. In this scenario you are stuck, because those helper functions cannot take a reference to the struct since you haven't created the struct yet. The workarounds (free functions, intermediate struct types) are very similar.

### Start with private functions, consider scaling to public functions

View types as described here have limitations. Because the types involve the names of fields, they are not really suitable for public interfaces. They could also be annoying to use in practice because one will have sets of fields that go together that have to be manually copied and pasted. All of this is true but I think something that can be addressed later (e.g., with named groups of fields).

What I've found is that the majority of times that I want to use view types, it is in *private* functions. Private methods often do little bits of logic and make use of the struct's internal structure. Public methods in contrast tend to do larger operations and to hide that internal structure from users. This isn't a universal law -- sometimes I have public functions that should be callable concurrently -- but it happens less.

There is also an advantage to the current behavior for public functions in particular: it preserves forward compatibilty. Taking `&mut self` (versus some subset of fields) means that the function can change the set of fields that it uses without affecting its clients. This is not a concern for private functions.

## Step 4: Internal references

Rust today cannot support structs whose fields refer to data owned by another. This gap is partially closed through crates like [rental][] (no longer maintained), though more often by [modeling internal references with indices](https://smallcultfollowing.com/babysteps/blog/2015/04/06/modeling-graphs-in-rust-using-vector-indices/). We also have `Pin`, which covers the related (but even harder) problem of immobile data.

[rental]: https://crates.io/crates/rental

I've been chipping away at a solution to this problem for some time. I won't be able to lay it out in full in this post, but I can sketch what I have in mind, and lay out more details in future posts (I have done some formalization of this, enough to convince myself it works).

As an example, imagine that we have some kind of `Message` struct consisting of a big string along with several references into that string. You could model that like so:

```rust
struct Message {
    text: String,
    headers: Vec<(&'self.text str, &'self.text str)>,
    body: &'self.text str,
}
```

This message would be constructed in the usual way:

```rust
let text: String = parse_text();
let (headers, body) = parse_message(&text);
let message = Message { text, headers, body };
```

where `parse_message` is some function like

```rust
fn parse_message(text: &str) -> (
    Vec<(&'text str, &'text str)>,
    &'text str
) {
    let mut headers = vec![];
    // ...
    (headers, body)
}
```

Note that `Message` doesn't have any lifetime parameters -- it doesn't need any, because it doesn't borrow from anything outside of itself. In fact, `Message: 'static` is true, which means that I could send this `Message` to another thread:

```rust
// A channel of `Message` values:
let (tx, rx) = std::sync::mpsc::channel();

// A thread to consume those values:
std::thread::spawn(move || {
    for message in rx {
        // `message` here has type `Message`
        process(message.body);
    }
});

// Produce them:
loop {
    let message: Message = next_message();
    tx.send(message);
}
```

## How far along are each of these ideas?

Roughly speaking...

* Polonius -- 'just' engineering
* Syntax -- 'just' bikeshedding
* View types -- needs modeling, one or two open questions in my mind[^strongupdate]
* Internal references -- modeled in some detail for a simplified variant of Rust, have to port to Rust and explain the assumptions I made along the way[^egderef]

...in other words, I've done enough work to to convince myself that these designs are practical, but plenty of work remains. :)

[^strongupdate]: To me, the biggest open question for view types is how to accommodate "strong updates" to types. I'd like to be able to do `let mut wf: {} WidgetFactory = WidgetFactory {}` to create a `WidgetFactory` value that is completely uninitialized and then permit writing (for example) `wf.counter = 0`. This should update the type of `wf` to `{counter} WidgetFactory`. Basically I want to link the information found in types with the borrow checker's notion of what is initialized, but I haven't worked that out in detail.

[^egderef]: As an example, to make this work I'm assuming some kind of "true deref" trait that indicates that `Deref` yields a reference that remains valid even as the value being deref'd moves from place to place. We need a trait much like this for other reasons too.

## How do we prioritize this work?

Whenever I think about investing in borrow checker ergonomics and usability, I feel a bit guilty. Surely something so fun to think about must be a bad use of my time.

Conversations at RustNL shifted my perspective. When I asked people about pain points, I kept hearing the same few themes arise, especially from people trying building applications or GUIs. 

I now think I had fallen victim to the dreaded “curse of knowledge”, forgetting how frustrating it can be to run into a limitation of the borrow checker and not know how to resolve it.

## Conclusion

This post proposes four changes attacking some very long-standing problems:

* **Conditionally returned references**, solved by [Polonius][PBP]
* **No or awkward syntax for lifetimes**, solved by an [explicit lifetime syntax][BCWL]
* **Helper methods whose body must be inlined**, solved by [view types][VT]
* **Can't "package up" a value and references into that value**, solved by interior references

You may have noticed that these changes build on one another. Polonius remodels borrowing in terms of "place expressions" (variables, fields). This enables an explicit lifetime syntax, which in turn is a key building block for interior references. View types in turn let us expose helper methods that can operate on 'partially borrowed' (or even partially initialized!) values.

### Why these changes won't make Rust "more complex" (or, if they do, it's worth it)

You might wonder about the impact of these changes on Rust's complexity. Certainly they grow the set of things the type system can express. But in my mind they, like [NLL][] before them, fall into that category of changes that will actually make using Rust feel *simpler* overall.

To see why, put yourself in the shoes of a user today who has written any one of the "obviously correct" programs we've seen in this post -- for example, [the `WidgetFactory` code we saw in view types](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=c9f5902084a631a8af5b769c094b69b6). Compiling this code today gives an error:

```
error[E0502]: cannot borrow `*self` as mutable
              because it is also borrowed as immutable
  --> src/lib.rs:14:17
   |
12 | for widget in &self.widgets {
   |               -------------
   |               |
   |               immutable borrow occurs here
   |               immutable borrow later used here
13 |     if widget.should_be_counted() {
14 |         self.increment_counter();
   |         ^^^^^^^^^^^^^^^^^^^^^^^^
   |         |
   |         mutable borrow occurs here
```

Despite all our efforts to render it well, this error is **inherently confusing**. It is not possible to explain why `WidgetFactory` doesn't work from an "intuitive" point-of-view because **conceptually it *ought* to work**, it just runs up against a limit of our type system.

The only way to understand why `WidgetFactory` doesn't compile is to dive deeper into the engineering details of how the Rust type system functions, and that is precisely the kind of thing people *don't* want to learn. Moreover, once you've done that deep dive, what is your reward? At best you can devise an awkward workaround. Yay 🥳.[^sarcasm]

[^sarcasm]: That's a sarcastic "Yay 🥳", in case you couldn't tell.

Now imagine what happens with view types. You still get an error, but now that error can come with a suggestion:

```
help: consider declaring the fields
      accessed by `increment_counter` so that
      other functions can rely on that
 7 | fn increment_counter(&mut self) {
   |                      ---------
   |                      |
   |      help: annotate with accessed fields: `&mut {counter} self`
```

You now have two choices. First, you can apply the suggestion and move on -- your code works! Next, at your leisure, you can dig in a bit deeper and understand what's going on. You can learn about the semver hazards that motivate an explicit declaration here.

Yes, you've learned a new detail of the type system, but you did so **on your schedule** and, where extra annotations were required, they were well-motivated. Yay 🥳![^genuine]

[^genuine]: This "Yay 🥳" is genuine.

### Reifying the borrow checker into types

There is another theme running through here: moving the borrow checker analysis out from the compiler's mind and into types that can be expressed. Right now, all types always represent fully initialized, unborrowed values. There is no way to express a type that captures the state of being in the midst of iterating over something or having moved one or two fields but not all of them. These changes address that gap.[^academic]

[^academic]: I remember years ago presenting Rust at some academic conference and a friendly professor telling me, "In my experience, you always want to get that state into the type system". I think that professor was right, though I don't regret not prioritizing it (always a million things to do, better to ask what is the right next step *now* than to worry about what step might've been better in the past). Anyway, I wish I could remember *who* that was!

### This conclusion is too long

I know, I'm like Peter Jackson trying to end "The Return of the King", I just can't do it! I keep coming up with more things to say. Well, I'll stop now. Have a nice weekend y'all.


