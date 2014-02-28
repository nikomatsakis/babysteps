I have been working on making the borrow checker treat closures in a
sound way. I hope to land this patch very soon. I want to describe the
impact of these changes and summarize what we might do in the future.

<!-- more -->

### The high-level idea

The basic idea is that the borrow checker will treat a closure *as if*
it were constructing a record with one borrowed pointer for each
variable mentioned in the closure.

So if we had some silly function like the following:

    fn call_randomly(c: |int, int|) {
        c(1, 1);
        c(2, 2);
        ...
    }

Which I were then to use as follows:

    fn foo() {
        let mut map = HashMap::new();
        call_randomly(|k, v| map.insert(k, v));
    }

The borrow checker will treat the closure that appears in `foo()` as
it it borrows `map` mutably for its entire lifetime. It's kind of
roughly as if the code were written as shown below, where the closure
expression `|k, v| map.insert(k, v)` has been replaced with an
explicit pair `(&mut env, callback)` that combines the *environment*
env with a code pointer (this is of course what happens at runtime):

    fn foo() {
        struct Env {
            map: &mut HashMap<int, int>
        }
            
        fn callback(env: &mut Env, k: int, v: int) {
            env.map.insert(k, v);
        }
            
        let mut map = HashMap::new();
        let env = Env { map: &mut map };
        call_randomly((&mut env, callback));
    }

This has the nice property that the borrow checker's treatment of
closures is kind of a simple variation on its treatment of other kinds
of structures.

### Implications

There are all sorts of issues in the issue tracker showing how the
current treatment of closures is unsound. Clearly the most important
impact of these changes is fixing all of those issues. However, the
changes also cause some reasonable code that used to work to no longer
work. I encountered two major kinds of errors, which I will describe
here along with the workarounds.

#### Errors due to closures borrowing more than is necessary

The first arises because, as I currently wrote the analysis, closures
always borrow an entire local variable, but sometimes they only use a
subpath. Let me give an example to show what I mean:

    struct Context {
        ints: ~[int],
        chars: ~[char],
    }
    
    fn foo(cx: &mut Context) {
        let push_int = || cx.ints.push(1);
        let push_char = || cx.chars.push('a');
        ...
    }
    
The borrow checker treats both `push_int` and `push_char` 
as if they were borrowing the local variable `cx`, so they
get compile to something roughly like:

    let push_int = (&mut cx, push_int_fn);
    let push_char = (&mut cx, push_char_fn);
    
    fn push_int_fn(cx: &mut &mut Context) {
        cx.ints.push(1);
    }

    fn push_char_fn(cx: &mut &mut Context) {
        cx.chars.push('a');
    }

This results in an error because we cannot borrow the local variable
`cx` as mutable more than once at a time.

However, this error is spurious, because I could `push_int` and
`push_char` access different fields of `cx`. So I could rewrite the
code as follows and it will type check:
    
    fn foo(cx: &mut Context) {
        let cx_ints = &mut cx.ints;
        let push_int = || cx_ints.push(1);
        
        let cx_chars = &mut cx.chars;
        let push_char = || cx_chars.push('a');
        
        ...
    }

This version works because neither closure is borrowing `cx`; rather,
they are borrowing different local variables (`cx_ints` and
`cx_chars`). The borrows of `cx`, meanwhile, are taking place in the
main function body, and the borrow checker can see that they refer to
different fields and hence are legal.

It's quite possible that we could improve the safety analysis to
automatically consider when a closure only borrows specific fields of
a local variable. In other words, we could perhaps do a better rewrite
and thus avoid the need to introduce the extra local variables.

#### Errors due to closures sharing mutable and immutable data

Currently in Rust we only contain mutable and immutable borrows. Note
that these two things are mutually exclusive, because the same memory
cannot be both constant and changing at the same time. We used to have
`const` borrows, which meant "possibly mutable but not by me", but we
removed them in an effort to keep the language simple. This decision
impacts some closure patterns, most notably the `try_finally` pattern.

Here is a very simple and artifical example. Suppose you wanted to
read items and, at the end, send a message indicate how many items you
had read -- and this message *must* be sent, even if you fail
unexpectedly. You might write the code something like this:

    let mut total_read = 0;
    (||
        while more_to_read() {
            total_read += read_items();
        }
    ).finally(|| {
        chan.send(total_read);
    })

This is relying on the try-finally module, which adds a `finally`
method to closures. The main closure will be called and then the
finally closure will be called, regardless of the whether the main
closure failed.

Under the new rules, this code will not type-check. This is because
the main closure is borrowing `total_read` mutably (so that it can be
incremented) and the finally closure is borrowing `total_read`
immutably (so that it can be read). In general, I think this is a
pretty reasonable rule: if failure occurs in the try clause, chances
are that anything it is mutating is in a pretty messed up state, so
you probably don't want to be reading it (this is the same reasoning
behind Rust's general "fail fast" philosophy). Nonetheless, in this
case, since all we're talking about is an integer, it's clearly ok.

There are two ways we can rewrite this example so that it type checks.
Perhaps the simplest is to employ a `Cell` type, which is Rust's
general purpose tool for permitting mutability in aliasable data.  The
idea of `Cell` is that, given an immutabe pointer to a `Cell`, you can
*still* mutate the cell's contents using the `get()` and `set()`
methods. `Cell` is not well-suited to all types, but it works great
for integers and other scalars. Here is the example rewritten to use
`Cell`:

    let total_read = Cell::new(0);
    (||
        while more_to_read() {
            let nitems = read_items();
            total_read.set(total_read.get() + nitems);
        }
    ).finally(|| {
        chan.send(total_read.get());
    })

This code is a bit more awkward because to access the value of the
`total_read` value I must write `total_read.get()`, and to update the
value I write `total_read.set()`. However, it type checks, because
both closures can share access to the same `Cell`.

I also added a more "full-featured" variation on the `try-finally`
API.  The idea is that this signature takes two closures, as before,
but it also takes two additional bits of data: first, some shared
mutable state that both closures will have access to, and second, some
state that will be moved into the try closure for it to use as it
likes (this second parameter would not be needed if we added support
for once closures).

    pub fn try_finally<T,U,R>(mutate: &mut T,
                              drop: U,
                              try_fn: |&mut T, U| -> R,
                              finally_fn: |&mut T|)
                              -> R

Using this API, we can rewrite the example as follows:

    let mut total_read = 0;
    try_finally(
        &mut total_read, (),
        
        |total_read, ()| {
            while more_to_read() {
                *total_read += read_items();
            }
        },
        
        |total_read| {
            chan.send(*total_read);
        })

What happens here is that we borrow `total_read` once, mutably, and
pass it into `try_finally()`. `try_finally()` then takes this mutable
pointer and passes it to both the try and finally closure in turn. (In
this case, we don't need to move any state into the try closure, so we
just pass the unit value `()` as the second argument.)

#### Conclusions and future work

For now, I opted to keep the design simple, and this leads to some
spurious errors. I expect we will eventually improve the borrow
checker so that it considers full path borrows; this seems clearly
better (but also clearly an extension).

I am not so certain about the second class of error. In my original
design, I included `const` borrows so that simple scalar values like
`total_read` could be updated by one closure and read by another. I
removed this in order to make the semantics better match the kinds of
borrows we find elsewhere in the language. It turned up not to affect
much code -- only two or three functions -- in the current
codebase. Given the reasonable workarounds available, and limited
importance of this situation, I'm inclined to leave the rules as I
have described them. But if it proves that this kind of error arises
frequently "in the wild", we could consider adding const borrows back.

The branch with these changes is
[issue-6801-borrowck-closures][br]. It is currently passing tests and
I hope to clean it up a bit and open a pull request soon.

[br]: https://github.com/nikomatsakis/rust/tree/issue-6801-borrowck-closures/
