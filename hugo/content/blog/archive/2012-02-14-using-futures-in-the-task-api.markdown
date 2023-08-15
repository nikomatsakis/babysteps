---
categories:
- Rust
- PL
comments: true
date: "2012-02-14T00:00:00Z"
slug: using-futures-in-the-task-api
title: Using futures in the task API
---

Brian pointed out to me a nice solution to the Task API problem that I
have overlooked, though it's fairly obvious.  Basically, I had
rejected a "builder" style API for tasks because there is often a need
for the child task to be able to send some data back to its parent
after it has been spawned, and a builder API cannot easily accommodate
this.  Brian's idea was to encapsulate these using futures.  It's
still not perfect but it's better I think and more composable than my
first, limited proposal.  It still requires that the actor pattern be
a separate module.

For those of you who don't care about the intimate details of Rust
task generation, sorry, this is a kind of a "document the idea" sort
of post.  I'm sure I'm also brushing over some of the Rust-specific
context that might be needed to make the examples easy to understand.

### Builder-based idea

Our basic task builder data types looks like:

    type task_builder = ~{
        stack_size: uint,
        notify_chan: comm::chan<result>,
        ... various options ...
        gen_task_body: fn@(fn~()) -> fn~
    };
    type task_id = uint;
    enum task_result { tr_success, tr_failure };
    
Basically it's a struct with a bunch of options.  The most interesting
part is the `gen_task_body()` field, which contains a closure
that---given the user's task body---will return the real task body.
This allows us to accumulate transformations on the body.

Creating a builder implicitly sets it up with the default options:
    
    fn mk_task_builder() -> task_builder {
         fn identity(f: fn~()) { f }
         
         ret ~{ ... default_options ..., gen_task_body: identity };
    }
    
Then people can add `impl` methods to configure the builder.  Here is
one simple example:

    impl task_builder for task_builder {
        fn set_stack_size(ss: uint) {
            self.stack_size = ss;
        }
    }
    
Here is an example of how we could make tasks that send a message to
a channel when they fail:

    impl task_builder for task_builder {
        fn notify_chan_on_failure(ch: chan<task_result>) {
            self.gen_task_body = fn@(body: fn~()) {
                fn~[copy ch, move body]() {
                    let _ = resource send_final_msg {
                        comm::send(
                            ch,
                            if rt::is_failing {tr_failure} else {tr_success})
                    }
                    body();
                    rt::await_all_children();
                }
            };
        }
    }

The effect of this code is to replace the `gen_task_body` closure with
one that will wrap the user's supplied body.  The wrapper will await
all children created by the body and send a message at the end.  The
message will indicate whether it failed or not.  The final message
send is written using an inline resource (no syntax exists for this,
but I just didn't want to write out the full resource declaration that
is currently required).

This is a pretty basic mechanism.  It could be wrapped up to be a bit
more widely applicable using wrappers like so:

    impl task_builder for task_builder {
        fn make_joinable() -> future<task_result> {
            let port = comm::port();
            self.notify_port_on_failure(port);
            future::from_port(port)
        }

        fn notify_port_on_failure(p: port<task_result>) {
            notify_chan_on_failure(comm::chan(ch));
        }
     }
     
Finally, the spawn method looks like this:    

    fn spawn(-builder: task_builder, body: fn~()) -> task_id {
        let body = builder.gen_task_body(body);
        ret rt::spawn(self, body); // do the *actual* spawn
    }
    
One interesting design choice was to make the `task_builder` unique
and have it be consumed by spawn.  The idea was to prevent people from
using the same configuration to launch multiple tasks.  This is not
safe in general though it may be in some cases: people can still
explicitly `copy` the builder if desired.

### Wrapping spawn: The actor module

Sometimes there are cases, like the actor module, where you want to
spawn the task using a different sort of body than a `fn~()`.  The
actor module, for example, expects a body `fn~(port<A>)` that is
provided with a port.  The idea is that you will spawn a task that
creates a port for itself and then sends a channel to that port back
to its creator.  This is effectively a wrapper around `task::spawn`:

    mod actor {
        enum actor<A> = { t_id: task::task_id, ch: chan<A> };
        fn spawn<A>(-builder: task_builder, body: fn~(port<A>)) -> actor<A> {
            let tmp_port = comm::port();
            let tmp_chan = comm::chan(port);
            let t_id = task::spawn(builder, fn~[copy tmp_chan; move body]() {
                let port = comm::port();
                comm::send(tmp_chan, port);
                actor_body(port);
                body();
            };
            let ch = comm::recv(tmp_port);
            actor({ch: ch, t_id: t_id})
        }
    }
    
It would actually be *possible* to move the actor body stuff into the
builder, but the resulting module is a little weird and error-prone to
use.  Basically it ends up being another kind of thing that wraps
`gen_task_body()`, and the danger is that if the user doesn't invoke
the notify wrappers first, you get in a situation where the actor code
is executing before the notification wrappers get setup.  Probably not
what you wanted.  So we decided it's better to separate out spawn
functions, which provide the real body of the task, from configuration
wrappers.  There may still be ordering dependencies between wrappers but
it's no doubt fewer.

### The future module

All of this kind of assumes a simple future module which I think looks like:

    mod future {
        enum future<A> = {
            mutable v: either<A,port<A>>
        };
        
        impl future<A> for future<A> {
            fn get() -> A {
                alt self.v {
                    either::left(v) { v }
                    either::right(p) {
                        let v = comm::recv(p);
                        self.v = either::left(v);
                        ret v;
                    }
                }
            }
        }
        
        fn from_port<A>(p: port<A>) -> future<A> {
            future({v: left(p)})
        }
        
        fn from_value<A>(v: A) -> future<A> {
            future({v: right(p)})
        }
    }

To make futures more convenient to use, a function like

    mod future {
        fn spawn<A>(f: fn~() -> A) -> future<A> {
            let port = comm::port();
            let chan = comm::chan(port);
            let builder = task::mk_task_builder();
            task::spawn(builder, fn~[move f, chan]() {
                let v = f();
                comm::send(chan, v);
            });
            from_port(port)
        }
    }

would let you write code like:

    let f = future::spawn {|| some_expensive_computation() };
    ...
    let r = f.get();

Horray.
