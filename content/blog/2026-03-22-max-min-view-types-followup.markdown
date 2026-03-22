---
title: "Maximally minimal view types, a follow-up"
date: 2026-03-22T12:52:52-04:00
series:
  - "view-types"
---

A short post to catalog two interesting suggestions that came in from my previous post, and some other related musings.

## Syntax with `.`

It was suggested to me via email that we could use `.` to eliminate the syntax ambiguity:

```rust
let place = &mut self.{statistics};
```

Conceivably we could do this for the type, like:

```rust
fn method(
    mp: &mut MessageProcessor.{statistics},
    ...
)
```

and in `self` position:

```rust
fn foo(&mut self.{statistics}) {}
```

I have to sit with it but...I kinda like it?

I'll use it in the next example to try it on for size.

## Coercion for calling public methods that name private types

In my post I said that if you hvae a public method whose `self` type references private fields, you would not be able to call it from another scope:

```rust
mod module {
    #[derive(Default)]
    pub struct MessageProcessor {
        messages: Vec<String>,
        statistics: Statistics,
    }
    
    pub struct Statistics { .. }

    impl MessageProcessor {
        pub fn push_message(
            &mut self.{messages},
            //         -------- private field
            message: String,
        ) {}
    }
}

pub fn main() {
    let mp = MessageProcessor::default();
    mp.push_message(format!("Hi"));
    // ------------ Error!
}
```

The error arises from desugaring `push_message` to a call that references private fields:

```rust
MessageProcessor::push_message(
    &mut mp.{messages},
    //       -------- not nameable here
    format!("Hi"),
)
```

I proposed we could lint to avoid this situation.

But an alternative was proposed where we would say that, when we introduce an auto-ref, if the callee references local variables not visible from this point in the program, we just borrow the entire struct rather than borrowing specific fields.

So then we would desugar to:

```rust
MessageProcessor::push_message(
    &mut mp,
    //   -- borrow the whole struct
    format!("Hi"),
)
```

If we then say that `&mut MessageProcessor` is coercable to a `&mut MessageProcessor.{messages}`, then the call would be legal.

Interestingly, the autoderef loop already considers visibility: if you do `a.foo`, we will deref until we see a *`foo` field visible to you at the current point*.

## Oh and a side note, assigning etc

This raises an interesting question I did not discuss. What happens when you write a value of a type like `MessageProcessor.{messages}`?

For example, what if I do this:

```rust
fn swap_fields(
    mp1: &mut MessageProcessor.{messages},
    mp2: &mut MessageProcessor.{messages},
) {
    std::mem::swap(mp1, mp2);
}
```

What I expect is that this would *just* swap the selected fields (`messages`, in this case) and leave the other fields untouched.

The basic idea is that a type `MessageProcessor.{messages}` indicates that the messages field is initialized and accessible and the other fields must be completely ignored.

## Another possible future extension: moved values

This represents another possible future extension. Today if you move out of a field in a struct, then you can no longer work with the value as a whole:

```rust
impl MessageProcessor {
    fn example(mut self) {
        // move from self.statistics
        std::mem::drop(self.statistics);
        
        // now I cannot call this method,
        // because I can't borrow `self`:
        self.push_message(format!("Hi again"));
    }
}
```

But with selective borrowing, we could allow this, and you could even return "partially initialized" values:

```rust
impl MessageProcessor {
    fn take_statistics(
        mut self,
    ) -> MessageProcessor.{messages} {
        std::mem::drop(self.statistics);
        self
    }
}
```

That'd be neat.
