---
title: "Maximally minimal view types"
date: 2026-03-21T12:37:13-04:00
series:
  - "view-types"
---
This blog post describes a *maximally minimal proposal* for [view types]({{< baseurl >}}/blog/2021/11/05/view-types/). It comes out of a converastion at RustNation I had with lcnr and Jack Huey, where we talking about various improvements to the language that are "in the ether", that basically everybody wants to do, and what it would take to get them over the line.

<!--more-->

## Example: MessageProcessor

Let's start with a simple example. Suppose we have a struct `MessageProcessor` which gets created with a set of messages. It will process them and, along the way, gather up some simple statistics:

```rust
pub struct MessageProcessor {
    messages: Vec<String>,
    statistics: Statistics,
}

#[non_exhaustive] // Not relevant to the example, just good practice!
pub struct Statistics {
    pub message_count: usize,
    pub total_bytes: usize,
}
```

The basic workflow for a message processor is that you

* accumulate messages by `push`ing them into the `self.messages` vector
* drain the accumulate messages and process them
* reuse the backing buffer to push future messages

### Accumulating messages

Accumulating messages is easy:

```rust
impl MessageProcessor {
    pub fn push_message(&mut self, message: String) {
        self.messages.push(message);
    }
}
```

### Processing a single message

The function to process a single message takes ownership of the message string because it will send it to another thread. Before doing so, it updates the statistics:

```rust
impl MessageProcessor {
    fn process_message(&mut self, message: String) {
        self.statistics.message_count += 1;
        self.statistics.total_bytes += message.len();
        // ... plus something to send the message somewhere
    }
}
```

### Draining the accumulated messages

The final function you need is one that will drain the accumulated messages and process them. Writing this *ought* to be straightforward, but it isn't:

```rust
impl MessageProcessor {
    pub fn process_pushed_messages(&mut self) {
        for message in self.messages.drain(..) {
            self.process_message(message); // <-- ERROR: `self` is borrowed
        }
    }
}
```

The problem is that `self.messages.drain(..)` takes a mutable borrow on `self.messages`. When you call `self.process_message`, the compiler assumes you might modify any field, including `self.messages`. It therefore reports an error. This is logical, but frustrating.

Experienced Rust programmers know a number of workarounds. For example, you could swap the `messages` field for an empty vector. Or you could invoke `self.messages.pop()`. Or you could rewrite `process_message` to be a method on the `Statistics` type. But all of them are, let's be honest, suboptimal. The code above is really quite reasonable, it would be nice if you could make it work in a straightforward way, without needing to restructure it.

## What's needed: a way for the borrow checker to know what fields a method may access

The core problem is that the borrow checker does not know that `process_message` will *only* access the `statistics` field. In this post, I'm going to focus on an explicit, and rather limited, notation, but I'll also talk about how we might extend it in the future.

## View types extend struct types with a list of fields

The basic idea of a view type is to extend the grammar of a struct type to optionally include a list of accessible fields:

```
RustType := StructName<...>
         |  StructName<...> { .. }         // <-- what we are adding
         |  StructName<...> { (fields),* } // <-- what we are adding
```

A type like `MessageProcessor { statistics }` would mean "a `MessageProcessor` struct where only the `statistics` field can be accessed". You could also include a `..`, like `MessageProcessor { .. }`, which would mean that all fields can be accessed, which is equivalent to today's struct type `MessageProcessor`.

## View types respect privacy

View types would respect privacy, which means you could only write `MessageProcessor { messages }` in a context where you can name the field `messages` in the first place.

## View types can be named on `self` arguments and elsewhere

You could use this to define that `process_message` only needs to access the field `statistics`:

```rust
impl MessageProcessor {
    fn process_message(&mut self {statistics}, message: String) {
        //             ----------------------
        //             Shorthand for: `self: &mut MessageProcessor {statistics}`
        
        // ... as before ...
    }
}
```

Of course you could use this notation in other arguments as well:

```rust
fn silly_example(.., mp: &mut MessageProcessor {statistics}, ..) {
}
```

## Explicit view-limited borrows

We would also extend borrow expressions so that it is possible to specify precisely which fields will be accessible from the borrow:

```rust
let messages = &mut some_variable {messages}; // Ambiguous grammar? See below.
```

When you do this, the borrow checker produces a value of type `&mut MessageProcessor {messages}`.

Sharp-eyed readers will note that this is ambiguous. The above could be parsed today as a borrow of a struct expression like `some_variable { messages }` or, more verbosely, `some_variable { messages: messages }`. I'm not sure what to do about that. I'll note some alternative syntaxes below, but I'll also note that it would be *possible* for the compiler to parse the AST in an ambiguous fashion and disambiguate later on once name resolution results are known.

## We automatically introduce view borrows in an auto-ref

In our example, though, the user never writes the `&mut` borrow explicitly. It results from the auto-ref added by the compiler as part of the method call:

```rust
pub fn process_pushed_messages(&mut self) {
    for message in self.messages.drain(..) {
        self.process_message(message); // <-- auto-ref occurs here
    }
}
```

The compiler internally rewrites method calls like `self.process_message(message)` to fully qualified form based on the signature declared in `process_message`. Today that results in code like this:

```rust
MessageProcessor::process_message(&mut *self, message)
```

But because `process_message` would now declare `&mut self { statistics }`, we can instead desugar to a borrow that specifies a field set:

```rust
MessageProcessor::process_message(&mut *self { statistics }, message)
```

## The borrow checker would respect views

Integrating views into the borrow checker is fairly trivial. The way the borrow checker works is that, when it sees a borrow expression, it records a "loan" internally that tracks the *place* that was borrowed, the *way* it was borrowed (mut, shared), and the *lifetime* for which it was borrowed. All we have to do is to record, for each borrow using a view, multiple loans instead of a single loan.

For example, if we have `&mut self`, we would record one `mut`-loan of `self`. But if we have `&mut self {field1, field2}`, we would two `mut`-loans, one of `self.field1` and one of `self.field2`.

## Example: putting it all together

OK, let's put it all together. This was our original example, collected:

```rust
pub struct MessageProcessor {
    messages: Vec<String>,
    statistics: Statistics,
}

#[non_exhaustive]
pub struct Statistics {
    pub message_count: usize,
    pub total_bytes: usize,
}

impl MessageProcessor {
    pub fn push_message(&mut self, message: String) {
        self.messages.push(message);
    }

    pub fn process_pushed_messages(&mut self) {
        for message in self.messages.drain(..) {
            self.process_message(message); // <-- ERROR: `self` is borrowed
        }
    }

    fn process_message(&mut self, message: String) {
        self.statistics.message_count += 1;
        self.statistics.total_bytes += message.len();
        // ... plus something to send the message somewhere
    }
}
```

Today, `process_pushed_messages` results in an error:

```rust
pub fn process_pushed_messages(&mut self) {
    for message in self.messages.drain(..) {
        //         ------------- borrows `self.messages`
        self.process_message(message); // <-- ERROR!
        //   --------------- borrows `self`
    }
}
```

The error arises from a conflict between two borrows:

* `self.messages.drain(..)` desugars to `Iterator::drain(&mut self.messages, ..)` which, as you can see, `mut`-borrows `self.messages`;
* then `self.process_message(..)` desugars to `MessageProcessor::process_message(&mut self, ..)` which, as you can see, `mut`-borrows all of `self`, which overlaps `self.messages`.

But in the "brave new world", we'll modify the program in one place:

```diff
-    fn process_message(&mut self, message: String) {
+    fn process_message(&mut self {statistics}, message: String) {
```

and as a result, the `process_pushed_messages` function will now borrow check successfully. This is because the two loans are now issued for different places:

* as before, `self.messages.drain(..)` desugars to `Iterator::drain(&mut self.messages, ..)` which `mut`-borrows `self.messages`;
* but now, `self.process_message(..)` desugars to `MessageProcessor::process_message(&mut self {statistics}, ..)` which `mut`-borrows `self.statistics`, which doesn't overlap `self.messages`.

## At runtime, this is still just a pointer

One thing I want to emphasize is that "view types" are a purely static construct and do not change how things are compiled. They simply give the borrow checker more information about what data will be accessed through which references. The `process_message` method, for example, still takes a single pointer to `self`.

This is in contrast with the workarounds that exist today. For example, if I were writing the above code, I might well rewrite `process_message` into an associated fn that takes a `&mut Statistics`:

```rust
impl MessageProcessor {
    fn process_message(statistics: &mut Statistics, message: String) {
        statistics.message_count += 1;
        statistics.total_bytes += message.len();
        // ... plus something to send the message somewhere
    }
}
```

This would be annoying, of course, since I'd have to write `Self::process_message(&mut self.statistics, ..)` instead of `self.process_message()`, but it would avoid the borrow check error.

Beyond being annoying, it would change the way the code is compiled. Instead of taking a reference to the `MessageProcessor` it now takes a reference to the `Statistics`.

In this example, the change from one type to another is harmless, but there are other examples where you need access to mulitple fields, in which case it is less efficient to pass them individually.

## Frequently asked questions

### How hard would this be to implement?

Honestly, not very hard. I think we could ship it this year if we found a good contributor who wanted to take it on.

### What about privacy?

I would require that the fields that appear in view types are 'visible' to the code that is naming them (this includes in view types that are inserted via auto-ref). So the following would be an error:

```rust
mod m {
    #[derive(Default)]
    pub struct MessageProcessor {
        messages: Vec<String>,
        ...
    }
    
    impl MessageProcessor {
        pub fn process_message(&mut self {messages}, message: String) {
            //                           ----------
            //   It's *legal* to reference a private field here, but it
            //   results in a lint, just as it is currently *legal*
            //   (but linted) for a public method to take an argument of
            //   private type. The lint is because doing this is effectively
            //   going to make the method uncallable from outside this module.
            self.messages.push(message);
        }
    }
}

fn main() {
    let mut mp = m::MessageProcessor::default();    
    mp.process_message(format!("Hello, world!"));
    // --------------- ERROR: field `messages` is not accessible here
    //
    // This desugars to:
    // 
    // ```
    // MessageProcessor::process_message(
    //     &mut mp {messages},        // <-- names a private field!
    //     format!("Hello, world!"),
    // )
    // ```
    // 
    // which names the private field `messages`. That is an error.
}
```

### Does this mean that view types can't be used in public methods?

More-or-less. You can use them if the view types reference public fields:

```rust
#[non_exhaustive]
pub Statistics {
    pub message_count: usize,
    pub average_bytes: usize,
    // ... maybe more fields will be added later ...
}

impl Statistics {
    pub fn total_bytes(&self {message_count, average_bytes}) -> usize {
        //                    ----------------------------
        //             Declare that we only read these two fields.
        self.message_count * self.average_bytes
    }
}
```

### Won't it be limited that view types more-or-less only work for private methods?

Yes! But it's a good starting point. And my experience is that this problem occurs *most often* with private helper methods like the one I showed here. It can occur in public contexts, but much more rarely, and in those circumstances it's often more acceptable to refactor the types to better expose the groupings to the user. This doesn't mean I don't want to fix the public case too, it just means it's a good use-case to cut from the MVP. In the future I would address public fields via [abstract fields][], as I described in the past.

[abstract fields]: {{< baseurl >}}/blog/2025/02/25/view-types-redux/

### What if I am borrowing the same sets of fields over and over? That sounds repititive!

That's true! It will be! I think in the future I'd like to see some kind of 'ghost' or 'abstract' fields, like I described in my [abstract fields][] blog post. But again, that seems like a "post-MVP" sort of problem to me.

### Must we specify the field sets being borrowed explicitly? Can't they be inferred?

In the syntax I described, you have to write `&mut place {field1, field2}` explicitly. But there are many approaches in the literature to inferring this sort of thing, with [row polymorphism](https://en.wikipedia.org/wiki/Row_polymorphism) perhaps being the most directly applicable. I think we could absolutely introduce this sort of inference, and in fact I'd *probably* make it the default, so that `&mut place` *always* introduces a view type, but it is typically inferred to "all fields" in practice. But that is a non-trivial extension to Rust's inference system, introducing a new kind of inference we don't do today. For the MVP, I think I would just lean on auto-ref covering by far the most common case, and have explicit syntax for the rest.

### Man, I have to write the fields that my method uses in the signature? That sucks! It should be automatic!

I get that for many applications, particularly with *private* methods, writing out the list fields that will be accessed seems a bit silly: the compiler ought to be able to figure it out.

On the flip side, this is the kind of inter-procedural inference we try to avoid in Rust, for a number of reasons:

* it introduces dependecies between methods which makes inference more difficult (even undecidable, in extreme cases);
* it makes for 'non-local errors' that can be really confusing as a user, where modifying the body of one method causes errors in another (think of the confusion we get around futures and `Send`, for example);
* it makes the compiler more complex, we would not be able to parallelize as easily (not that we parallelize today, but [that work is underway](https://github.com/rust-lang/rust-project-goals/issues/121)!)

The bottom line for me is one of *staging*: whatever we do, I think we will want a way to be explicit about exactly what fields are being accessed and where. Therefore, we should add that first. We can add the inference later on.

### Why does this need to be added to the borrow checker? Why not desugar?

Another common alternative (and one I considered for a while...) is to add some kind of "desugaring" that passes references to fields instead of a single reference. I don't like this for two reasons. One, I think it's frankly more complex! This is a fairly straightforward change to the borrow checker, but that desugaring would leave code all over the compiler, and it would make diagnostics etc much more complex.

But second, it would require changes to what happens at runtime, and I don't see why that is needed in this example. Passing a single reference feels right to me.
### What about the ambiguous grammar? What other syntax options are there?

Oh, right, the ambiguous grammar. To be honest I've not thought too deeply about the syntax. I was trying to have the type `Struct { field1, field 2 }` reflect struct constructor syntax, since we generally try to make types reflect expressions, but of course that leads to the ambiguity in borrow expressions that causes the problem:

```rust
let foo = &mut some_variable { field1 };
            // ------------- is this a variable or a field name?
```

Options I see:

* *Make it work.* It's not truly ambiguous, but it does require some semantic diambiguation, i.e., in at least some cases, we have to delay resolving this until name resolution can complete. That's unusual for Rust. We do it in some small areas, most notably around the interpretation of a pattern like `None` (is it a binding to a variable `None` or an enum variant?).
* *New syntax for borrows only.* We could keep the type syntax but make the borrow syntax different, maybe `&mut {field1} in some_variable` or something. Given that you would rarely type the explicit borrow form, that seems good?
* *Some new syntax altogether.* Perhaps we want to try something different, or introduce a keyword everywhere? I'd be curious to hear options there. The current one feels nice to me but it occupies a "crowded syntactic space", so I can see it being confusing to readers who won't be sure how to interpret it.

## Conclusion: this is a good MVP, let's ship it!

In short, I don't really see anything *blocking* us from moving forward here, at least with a [lang experiment](https://lang-team.rust-lang.org/how_to/experiment.html).
