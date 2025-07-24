---
layout: post
title: "Removing procs"
date: 2013-05-30T09:38:00Z
comments: true
categories: [Rust]
---

I've been thinking more about my proposal to split the current `fn`
type into `fn` and `proc`. I have come to the conclusion that
we just don't need `proc` at all. I think we can get by with two types:

1. `fn(S) -> T`: closures that always reference an enclosing scope
2. `extern "ABI" fn(S) -> t`: raw function pointer, no environment

Code that uses `@fn` or `~fn` today could be rewritten to either use a
boxed trait or to use a pair of a user-data struct and an `extern fn`.

Today the two main consumers of such functions that I could find in
the standard library are task spawning and futures, so I will look at
those; rustc also makes heavy use of `@fn` within the visitor and AST
folding cold, but those are legacy uses that would be better written
with traits.

<!-- more -->

### Task spawning

Right now to spawn a task one writes some code like the following:

    let vec = ~[1, 2, 3];
    let (port, chan) = stream();
    do spawn {
        vec.push(computation());
        chan.send(vec.clone()); // (*)
    }
    let v = port.recv();
    // v == ~[1, 2, 3, 4]

This code creates a vector and a port/channel pair. A task is then
spawned which takes ownership of `vec` and `chan` (implicitly, because
it references them; as I [argued before][pp], I find this potentially
confusing). This task then pushes the result of `computation()` onto
the vector and sends the vector back.

Interestingly, it has to send back a *clone* of the vector, even
though it doesn't need the vector anymore. The reason for this is
because spawn is defined as taking a general `~fn` closure:

    fn spawn(body: ~fn());

This closure, `body`, defines the task body. *We* know that the closure
will be invoked at most once, but the type system doesn't. Therefore,
it will not permit `vec` to be moved out of the environment, for fear that
`body` will be re-invoked and then try to use this vector again.

Under my proposal, we would modify this definition to be as follows:    

    fn spawn<T:Send>(arg: T, body: extern fn(T));
    
The idea is that spawn will invoke `body` with `arg` as argument.
You could then rewrite the previous example as follows:

    let vec = ~[1, 2, 3];
    let (port, chan) = stream();
    do spawn((vec, chan)) |(vec, chan)| {
        vec.push(computation());
        chan.send(vec); // (*)
    }
    let v = port.recv();
    
Here I am assuming that we extend the `||` syntax to allow it to be
used to define raw functions with no environment, which is something
that has [already been requested for other reasons][request] and which
I plan to do.

What this code does, then, is to "capture" `vec` and `chan` by moving
them into a tuple and passing that tuple to spawn as an
argument. The task body then unpacks the tuple. This pattern is very
general, but not very DRY of course, since we must repeat the names of
the variables. One nice aspect, from my point of view, is that by
enumerating the things you capture, you make clear what is being moved
into the closure and what is not.

Another benefit is that we are able to move the vector `vec` out of
the task body (see the line marked `(*)`---no call to clone). The
reason that this works is that there is no implicit environment. It is
of course possible to reinvoke the task body, but the caller would
have to supply a fresh `(vec, chan)` tuple, so there would be no
access to uninitialized memory.

#### Macros to the rescue

One obvious way to solve the DRY problem is to encapsulate `spawn` in
a macro. So, if you write something like (strawman):

    spawn!(a, b, c => 
        ...
    );
    
It would expand to the tuple passing code I showed earlier.  Clearly
here a more flexible macro invocation syntax might be desirable, in
that it'd be nice to use braces not parentheses.

It turns out, in fact, that we wanted to convert calls to spawn into
macros anyway, so that we could easily trace the filename /
line-number information of the task, which makes debugging much easier.

Futures, incidentally, could work in a similar fashion:

    let task = future!(a, b, c => process(a, b, c))

### But wait, there's more

It may seem surprising that we could do away with closures so easily.
In fact, there is one important difference between the two
versions of spawn I showed you, besides whether they take a function/closure:

    fn spawn(body: ~fn());                        // Today
    fn spawn<A:Send>(arg: A, body: extern fn(A)); // Tomorrow?
    
Namely, the `spawn` of today is not generic: the argument to the
closure is hidden, in the environment. This means that you only need
to generate one copy of `spawn`, whereas we would need to generate one
copy of the proposed `spawn` for every different kind of argument that
a task may expect.

As I've mentioned a few times, object types can provide the same sort
of existential encapsulation that closures provide. If we were to
recast the `spawn` and `future` function using objects, they might look like:
    
    fn spawn(body: ~Task:Send<()>);
    fn future<R>(body: ~Task:Send<R>) -> Future<R>;

where the trait `Task` is defined as follows:

    trait Task<R> {
        // Consumes the receiver, and hence it can only be invoked once.
        fn run(self) -> R;
        
        // Add these metadata functions for good measure.
        fn filename(&self) -> &'static str;
        fn line_number(&self) -> uint;
        fn column(&self) -> uint;
    }
    
If we took this approach, we could just define a macro `task!` that
closed over a set of variables. In that case, spawn and future
could be regular functions again, and we could invoke them as follows:

    spawn(task!(a, b, c => ...))
    future(task!(a, b => ...))

What would this macro expand to? First, I imagine that we'd have a
generic implementation in the standard library, looking something like:

    struct TaskStruct<A, R> {
        argument: A,
        func: extern fn(A) -> R,
        filename: &'static str,
        line_number: uint,
        column: uint
    }
    
    impl<A, R> Task<R> for TaskStruct<A, R> {
        fn run(self) -> R {
            let TaskStruct {argument, func, _} = self;
            func(argument)
        }
        
        fn filename(&self) -> &'static str {
            self.filename
        }
        
        fn line_number(&self) -> uint {
            self.line_number
        }

        fn column(&self) -> uint {
            self.column
        }
    }

Now the `task!(a...z => ...)` macro can expand to the following
expression:

    ~TaskStruct {argument: (a...z),
                 func: |(a...z)| { ... },
                 filename: "some_file.rs",
                 line_number: 22,
                 column: 44}
                 
When this expression is used in argument position, it can be converted
into an `~Task<R>` object using the standard coercion rules . This same
pattern can be extended to other kinds of "capturing functions" that
we might want.

### Further simplification

If we adopt this trick, I think we can probably just remove the idea
of `once fn`s. The *main* use of those was task bodies and futures,
which are basically solved by the two ideas above.  There are other
use cases, but they are rare and I think it's acceptable to rewrite
them using a `fn` that takes arguments.  Here is an example:

    fn do_once<A, R>(arg: A, op: fn(A) -> R) { op(arg) }
    
    fn something() {
        let mut borrowed = ~[1, 2, 3];
        let moved = ~[1, 2, 3];
        do do_once(moved) |moved| {
            borrowed.push(1, 2, 3);
            move_it(moved);
        }
    }

### Why keep closures at all?

I think it's worth keeping `fn` closures that implicitly borrow their
environment. They are basically sugar for a trait whose fields are `&`
and `&mut` borrowed pointers, but it is a *very* sweet sugar that we
build on all over the place. All of our control structures, after all,
are built on closures. Plus, it avoids the need to give "capture
clauses" for this common case.

### Where does that leave us?

If we adopted this proposal then the menagerie of function types
has become quite tamed. In practice, the two types I imagine one
would see commonly are:

- Closures like `fn(T) -> U`
- Sendable task bodies like `~Task:Send`

More advanced use cases, such as the data parallelism API I am planning
and also brson's work on the scheduler, will expect closures with bounds
on their arguments:

- `fn:Share(T) -> U`, indicating a closure that only closes over
  "shareable" things (roughly speaking, that is the same as Freeze,
  but not quite; I'll discuss this idea more in a future post)
- `fn:Send(T) -> U`, indicating a closure that only closes over sendable things

The full type scheme would be as follows (`[]` denotes something
optional, `*` denotes repeating):

    Closures:
      fn [:K] (T*) -> T
        where K  = K0 [(+ K0)*]
              K0 = 'lifetime
                 | Trait (must be a built-in trait, like Freeze, Shared, Send)
    
    Function pointers:
      extern ["ABI"] fn(T*) -> T
        where ABI defaults to "Rust" if unspecified.
      
As an alternative to the `extern fn` syntax, I would personally prefer
something like `fnptr`, but I'm not sure where the ABI goes then. I
also considered `fn:"ABI"`, but that makes the ABI mandatory, and it
kind of looks ugly. So I think I like `extern fn`, even though it is a
bit odd since it is in fact the type of all fn items, not only
external functions.

### Hat tip

I want to tip my hat to bblum and the various IRC commentators, who
forced me to think about this issue a bit more. I don't know if they
will like this proposal, but I like it more than what I had.

[pp]: http://smallcultfollowing.com/babysteps/blog/2013/05/14/procedures/
[request]: https://github.com/mozilla/rust/issues/3678#issuecomment-16092916    
    

