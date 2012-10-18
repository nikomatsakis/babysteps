My big goal for 0.5 is to straighten out our function types.



Guess what: we're looking at fn types again.  Ben Blum and I sat down
and thought this over and we think we have a design that is at once
reasonable to use but also offers a lot of power.

### Goals

We use closures a lot in Rust to build up new control-flow
abstractions.  However, they have many shortcomings:

- They are not integrated with lifetimes and hence not as flexible as
  they can be.
- You cannot move out of a closure.
- You need to be able to limit the kind of data that a closure closes
  over in a more fine-grained way; today's `fn~()`, for example, can
  only close over "sendable" data.  This means we can safely send them
  to other tasks without fear of data-races; but it doesn't indicate
  whether the data is *immutable* or not, so they can't be shared
  between threads.  Also, sendability no longer implies copyability,
  so the current system can violate linearity, as all `fn~()` are
  considered copyable.

### What is the problem with the current system

The single biggest problem with the current system is the inability to
move out of a closure.  Here is one example of where such a thing
might come up.  Imagine I had a piece of code like this:

    fn validate_and_send(chan: Channel<Message>,
                         msg: ~Message) {
        validate_msg(msg);
        chan.send(move msg);
    }

This function takes a message of type `~Message`, validates it, and
finally sends it along the channel.  Presume that this message is big
and copying it is expensive.

Now, imagine we are profiling and we want to insert a little closure
to measure and print out how long this validation takes.  So we write
something like:

    fn validate_and_send(chan: Channel<Message>,
                         msg: ~Message) {
        do time_and_print {
            validate_msg(msg);
            chan.send(move msg);
        }
    }
    
where `time_and_print()` is a function which executes its closure
argument and then prints out the elapsed time.  This looks good.

But wait, there is a problem!  If we try to compile this, the compiler
will object because the `move msg` command tries to move out of the
closure environment.  The reason that the compiler is concerned is
that it is possible that the closure may be invoked twice; in that
case, the message would already have been sent.  That's bad!

Similar problems arise when you try to hand off data to tasks using
the task spawn function:

    do task::spawn {
        ...
    }
    
This function may well want to take data that it owns and move it
along.

### Proposed solution: high level

The proposed fn types are rather general and can cover a large number
of scenarios.  However, in practice, I think people will use one of
the following:

- `once fn(T) -> U`: "A function I will call once"
- `&fn(T) -> U`: "A function I will call some number of times"
- `once fn:send(T) -> U`: "A sendable function that will be called at
  most once"
- `~fn:send const(T) -> U`: "A sendable function that only closes over
  immutable state (and hence can be executed many times in parallel)"

You can see here that function types will begin with either one of the
standard ownership sigils (`&`, `~`, or `@`) or the keyword `once`.
A `once fn` is statically guaranteed to be called at most once.



In general, function types will be equipped with constraints on the
things that they close over.  So you can write `fn:send const` to
indicate a function that only closes over sendable, immutable data.

Function types cannot be referenced directly (so `fn(int)` is not a
type) but must include an appropriate sigil prefix, or else the keyword
`once`.  So `&fn(T) -> U` is a borrowed function that you can call any
number of types, and `once fn(T) -> U` is a function you can only call once.

Any type of function can be coerced to a `once fn(T) -> U`, presuming
that the bounds and argument types are compatible.  `@fn` and `~fn`
can also be borrowed as a `&fn`.

The most common uses of functions will look like:


### Proposed solution: nitty-gritty details

The basic of all function types will be a pseudo-type "F".  Here is
the grammar, omitting all defaults

    T := ...
       | @F
       | ~F
       | &r/F
       | once F
    F := fn:B(T) -> U;
    B := &r' K1 ... Kn
    K := copy
       | send
       | const
       | ...

The bound `B` of a function includes a lifetime bound `&r'` and any
number of kind bounds. Kinds are built-in selectors like `copy`,
`send`, and so forth.

The precise details of how a function type can be used and allocated
will depend on how it is 
