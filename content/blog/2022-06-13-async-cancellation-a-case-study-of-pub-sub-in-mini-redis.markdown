---
layout: post
title: 'Async cancellation: a case study of pub-sub in mini-redis'
date: 2022-06-13T15:15:00-0400
---

Lately I’ve been diving deep into tokio’s [mini-redis] example. The mini-redis example is a great one to look at because it's a realistic piece of quality async Rust code that is both self-contained and very well documented. Digging into mini-redis, I found that it exemplifies the best and worst of async Rust. On the one hand, the code itself is clean, efficient, and high-level. On the *other hand*, it relies on a number of subtle async conventions that can easily be done wrong -- worse, if you do them wrong, you won't get a compilation error, and your code will "mostly work", breaking only in unpredictable timing conditions that are unlikely to occur in unit tests. Just the kind of thing Rust tries to avoid! This isn't the fault of mini-redis -- to my knowledge, there aren't great alterantive patterns available in async Rust today (I go through some of the alternatives in this post, and their downsides).

## Context: evaluating [moro]

We've heard from many users that async Rust has a number of pitfalls where things can break in subtle ways. In the Async Vision Doc, for example, the [Barbara battles buffered streams](https://rust-lang.github.io/wg-async/vision/submitted_stories/status_quo/barbara_battles_buffered_streams.html) and [solving a deadlock](https://rust-lang.github.io/wg-async/vision/submitted_stories/status_quo/aws_engineer/solving_a_deadlock.html) stories discuss challenges with `FuturesUnordered` (wrapped in the `buffered` combinator); the [Barbara gets burned by select](https://rust-lang.github.io/wg-async/vision/submitted_stories/status_quo/barbara_gets_burned_by_select.html) and [Alan tries to cache requests, which doesn't always happen](https://rust-lang.github.io/wg-async/vision/submitted_stories/status_quo/alan_builds_a_cache.html) stories talk about cancellation hazards and the `select!` or race combinators.

In response to these stories, I created an experimental project called [moro] that explores structured concurrency in Rust. I've not yet blogged about moro, and that's intentional. I've been holding off until I gain more confidence in [moro]'s APIs. In the meantime, various people (including myself) have been porting different bits of code to [moro] to get a better sense for what works and what doesn't. [GusWynn], for example, started changing bits of the [materialize.io codebase] to use moro and to have a safer alternative to cancellation. I've been poking at mini-redis, and I've also been working with some folks within AWS with some internal codebases.

[GusWynn]: https://github.com/guswynn/
[moro]: https://github.com/nikomatsakis/moro/
[materialize.io codebase]: https://github.com/MaterializeInc/

**What I've found so far is that [moro] absolutely helps, but it's not enough.** Therefore, instead of the triumphant blog post I had hoped for, I'm writing this one, which does a kind of deep-dive into the patterns that [mini-redis] uses: both how they work well when done right, but also how they are tedious and error-prone. I'll be posting some follow-up blog posts that explore some of the ways that moro can help.

[mini-redis]: https://github.com/tokio-rs/mini-redis

## What is mini-redis?

If you’ve not seen it, [mini-redis] is a really cool bit of example code from the [tokio] project. It implements a “miniature” version of the [redis] in-memory data store, focusing on the key-value and pub-sub aspects of redis. Specifically, clients can connect to mini-redis and issue a subset of the redis commands. In this post, I’m going to focus on the “pub-sub” aspect of redis, in which clients can **publish** messages to a topic which are then broadcast to everyone who has **subscribed** to that topic. Whenever a client publishes a message, it receives in response the number of other clients that are currently subscribed to that topic.

Here is an example workflow involving two clients. Client 1 is subscribing to things, and Client 2 is publishing messages.

```mermaid
sequenceDiagram
    Client1 ->> Server: subscribe `A`
    Client2 ->> Server: publish `foo` to `A`
    Server -->> Client2: 1 client is subscribed to `A`
    Server -->> Client1: `foo` was published to `A`
    Client1 ->> Server: subscribe `B`
    Client2 ->> Server: publish `bar` to `B`
    Server -->> Client2: 1 client is subscribed to `B`
    Server -->> Client1: `bar` was published to `B`
    Client1 ->> Server: unsubscribe A
    Client2 ->> Server: publish `baz` to `A`
    Server -->> Client2: 0 clients are subscribed to `A`
```

[tokio]: https://tokio.rs

[redis]: https://redis.io

## Core data structures

To implement this, the redis server maintains a struct `State` that is shared across all active clients. Since it is shared across all clients, it is maintained in a `Mutex` ([source](https://github.com/tokio-rs/mini-redis/blob/cf1e4e465eceaaddd9497353e809fe6b814d7b19/src/db.rs#L52)):

```rust
struct Shared {
    /// The shared state is guarded by a mutex. […]
    state: Mutex<State>,
    …
}
```

Within this `State` struct, there is a `pub_sub` field ([source](https://github.com/tokio-rs/mini-redis/blob/cf1e4e465eceaaddd9497353e809fe6b814d7b19/src/db.rs#L66-L68)):

```rust
pub_sub: HashMap<String, broadcast::Sender<Bytes>>,
```

The `pub_sub` field stores a big hashmap. The key is the *topic* and the *value* is the [`broadcast::Sender`](https://docs.rs/tokio/latest/tokio/sync/broadcast/struct.Sender.html), which is the “sender half” of a tokio broadcast channel. Whenever a client issues a `publish` command, it ultimately calls [`Db::publish`](https://github.com/tokio-rs/mini-redis/blob/cf1e4e465eceaaddd9497353e809fe6b814d7b19/src/db.rs#L265-L278), which winds up invoking `send` on this broadcast channel:

```rust
pub(crate) fn publish(&self, key: &str, value: Bytes) -> usize {
        let state = self.shared.state.lock().unwrap();
        state
            .pub_sub
            .get(key)
            // On a successful message send on the broadcast channel, the number
            // of subscribers is returned. An error indicates there are no
            // receivers, in which case, `0` should be returned.
            .map(|tx| tx.send(value).unwrap_or(0))
            // If there is no entry for the channel key, then there are no
            // subscribers. In this case, return `0`.
            .unwrap_or(0)
}
```

## The subscriber loop

We just saw how, when clients publish data to a channel, that winds up invoking `send` on a broadcast channel. But how do the clients who are subscribed to that channel receive those messages? The answer lies in the [`Subscribe`](https://github.com/tokio-rs/mini-redis/blob/cf1e4e465eceaaddd9497353e809fe6b814d7b19/src/cmd/subscribe.rs) command.

The idea is that the server has a set `subscriptions` of subscribed channels for the client ([source](https://github.com/tokio-rs/mini-redis/blob/cf1e4e465eceaaddd9497353e809fe6b814d7b19/src/cmd/subscribe.rs#L117)):

```rust
let mut subscriptions = StreamMap::new();
```

This is implemented using a tokio [`StreamMap`](https://docs.rs/tokio-stream/latest/tokio_stream/struct.StreamMap.html), which is a neato data structure that takes multiple streams which each yield up values of type `V`, gives each of them a key `K`, and combines them into one stream that yields up `(K, V)` pairs. In this case, the streams are the “receiver half” of those broadcast channels, and the keys are the channel names. 

When it receives a subscribe command, then, the server wants to do the following:

* Add the receivers for each subscribed channel into `subscriptions`.
* Loop:
	* If a message is published to `subscriptions`, then send it to the client.
	* If the client subscribes to new channels, add those to `subscriptions`  and send an acknowledgement to client.
	* If the client unsubscribes from some channels, remove them from `subscriptions` and send an acknowledgement to client.
	* If the client terminates, end the loop and close the connection.

## “Show me the state”

Learning to write Rust code is basically an exercise in asking “show me the state” — i.e., the key to making Rust code work is knowing what data is going to be modified and when[^benefit]. In this case, there are a few key pieces of state…

* The set `subscriptions` of “broadcast receivers” from each subscribed stream
	* There is also a set `self.channels` of “pending channel names” that ought to be subscribed to, though this is kind of an implementation detail and not essential.
* The connection `connection` used to communicate with the client (a TCP socket)

And there are three concurrent tasks going on, each of which access that same state…

* Looking for published messages from `subscriptions` and forwarding to `connection` (reads `subscriptions`, writes to `connection`)
* Reading client commands from `connection` and then either…
	* subscribing to new channels (writes to `subscriptions`) and sending a confirmation (writes to `connection`);
	* or unsubscribing from channels (writes to `subscriptions`) and sending a confirmation (writes to `connection`).
* Watching for termination and then cancelling everything (drops the broadcast handles in `connections`).

[^benefit]: My experience is that being forced to get a clear picture on this is part of what makes Rust code reliable in practice.

You can start to see that this is going to be a challenge. There are three conceptual tasks, but they are each needing mutable access to the same data:

```mermaid
flowchart LR
    forward["Forward published messages to client"]
    client["Process subscribe/unsubscribe messages from client"]
    terminate["Watch for termination"]
    
    subscriptions[("subscriptions:\nHandles from\nsubscribed channels")]
    connection[("connection:\nTCP stream\nto/from\nclient")]
    
    forward -- reads --> subscriptions
    forward -- writes --> connection
    
    client -- reads --> connection
    client -- writes --> subscriptions
    
    terminate -- drops --> subscriptions
    
    style forward fill:oldlace
    style client fill:oldlace
    style terminate fill:oldlace
    
    style subscriptions fill:pink
    style connection fill:pink
    
```

If you tried to do this with normal threads, it just plain wouldn’t work…

```rust
let mut subscriptions = vec![]; // close enough to a StreamMap for now
std::thread::scope(|s| {
   s.spawn(|| subscriptions.push("key1"));
   s.spawn(|| subscriptions.push("key2"));
});
```

If you [try this on the playground](https://play.rust-lang.org/?version=nightly&mode=debug&edition=2021&gist=9737c0cab49437ae45dbef27b80a9619), you’ll see it gets an error because both closures are trying to access the same mutable state. No good. So how does it work in mini-redis?

## Enter [`select!`], our dark knight

Mini-redis is able to juggle these three threads through careful use of the [`select!`] macro. This is pretty cool, but also pretty error-prone — as we’ll see, there are a number of subtle points in the way that [`select!`] is being used here, and it’s easy to write the code wrong and have surprising bugs. At the same time, it’s pretty neat that we can use [`select!`] in this way, and it begs the question of whether we can find safer patterns to achieve the same thing. I think right now you can find safer ones, but they require less efficiency, which isn’t really living up to Rust’s promise (though it might be a good idea). I’ll cover that in a follow-up post, though, for now I just want to focus on explaining what mini-redis is doing and the pros and cons of this approach.

The main loop looks like this ([source](https://github.com/tokio-rs/mini-redis/blob/cf1e4e465eceaaddd9497353e809fe6b814d7b19/src/cmd/subscribe.rs#L119-L155)):

```rust
let mut subscriptions = StreamMap::new();
loop {
    …
    select! {
        Some((channel_name, msg)) = subscriptions.next() => ...
        //                          -------------------- future 1
        res = dst.read_frame() => ...
        //    ---------------- future 2
        _ = shutdown.recv() => ...
        //  --------------- future 3
    }
}
```

[`select!`]: https://docs.rs/tokio/latest/tokio/macro.select.html

[`select!`] is kind of like a match statement. It takes multiple futures (underlined in the code above) and continues executing them until one of them completes. Since the `select!` is in a loop, and in this case each of the features are producing a series of events, this setup effectively runs the three futures concurrently, processing events as they arrive:

* `subscriptions.next()` -- the future waiting for the next message to arise to the `StreamMap`
* `dst.read_frame()` -- the async method `read_frame` is defined on the conection, `dst`. It reads data from the client, parses it into a complete command, and returns that command. We'll dive into this function in a bit -- it turns out that it is written in a very careful way to account 
* `shutdown.recv()` -- the mini-redis server signals a global shutdown by threading a tokio channel to every connection; when a message is sent to that channel, all the loops cleanup and stop.

## How [`select!`] works

So, [`select!`] runs multiple futures concurrently until one of them completes. In practice, this means that it iterates down the futures, one after the other. Each future gets awoken and runs until it either *yields* (meaning, awaits on something that isn't ready yet) or *completes*. If the future yields, then [`select!`] goes to the next future and tries that one. 

Once a future *completes*, though, the [`select!`] gets ready to complete. It begins by dropping all the other futures that were selected. This means that they immediately stop executing at whatever `await` point they reached, running any destructors for things on the stack. [As I described in a previous blog post](https://smallcultfollowing.com/babysteps/blog/2022/01/27/panics-vs-cancellation-part-1/), in practice this feels a lot like a `panic!` that is injected at the `await` point. And, just like any other case of recovering from an exception, it requires that code is written carefully to avoid introducing bugs -- [tomaka describes one such example](https://tomaka.medium.com/a-look-back-at-asynchronous-rust-d54d63934a1c) in his blog post. These bugs are what gives async cancellation in Rust a reputation for being difficult.

## Cancellation and mini-redis

Let's talk through what cancellation means for mini-redis. As we saw, the `select!` here is effectively running two distinct tasks (as well as waiting for shutdown):

* Waiting on `subscriptions.next()` for a message to arrive from subscribed channels, so it can be forwarded to the client.
* Waiting on `dst.read_frame()` for the next comand from the client, so that we can modify the set of subscribed channels.

We'll see that mini-redis is coded carefully so that, whichever of these events occurs first, everything keeps working correctly. We'll also see that this setup is fragile -- it would be easy to introduce subtle bugs, and the compiler would not help you find them.

Take a look back at the sample subscription workflow at the start of this post. After `Client1` has subscribed to `A`, the server is effectively waiting for `Client1` to send further messages, or for other clients to publish. 

The code that checks for further messages from `Client1` is an async function called [`read_frame`]. It has to read the raw bytes sent by the client and assemble them into a "frame" (a single command). The [`read_frame`] in mini-redis is written in particular way:

* It loops and, for each iteration...
    * tries to parse from a complete frame from `self.buffer`,
    * if `self.buffer` doesn't contain a complete frame, then it reads more data from the stream into the buffer.

[`read_frame`]: https://github.com/tokio-rs/mini-redis/blob/cf1e4e465eceaaddd9497353e809fe6b814d7b19/src/connection.rs#L56

In pseudocode, it looks like ([source](https://github.com/tokio-rs/mini-redis/blob/cf1e4e465eceaaddd9497353e809fe6b814d7b19/src/connection.rs#L56-L81)):

```rust
impl Connection {
    async fn read_frame(&mut self) -> Result<Option<Frame>> {
        loop {
            if let Some(f) = parse_frame(&self.buffer) {
                return Ok(Some(f));
            }
            
            read_more_data_into_buffer(&mut self.buffer).await;
        }
    }
}
```

The key idea is that the function buffers up data until it can read an entire frame (i.e., successfully complete) and then it removes that entire frame at once. It never removes *part* of a frame from the buffer. This ensures that if the `read_frame` function is canceled while awaiting more data, nothing gets lost.

## Ways to write a broken [`read_frame`]

There are many ways to a version of [`read_frame`] that is NOT cancel-safe. For example, instead of storing the buffer in `self`, one could put the buffer on the stack:

```rust
impl Connection {
    async fn read_frame(&mut self) -> Result<Option<Frame>> {
        let mut buffer = vec![];
        
        loop {
            if let Some(f) = parse_frame(&buffer) {
                return Ok(Some(f));
            }
            
            read_more_data_into_buffer(&mut buffer).await;
            //                                      -----
            //                If future is canceled here,
            //                buffer is lost.
        }
    }
}
```

This setup is broken because, if the future is canceled when awaiting more data, the buffered data is lost. 

Alternatively, [`read_frame`] could intersperse reading from the stream and parsing the frame itself:

```rust
impl Connection {
    async fn read_frame(&mut self) -> Result<Option<Frame>> {
        let mut buffer = vec![];
        
        let command_name = self.read_command_name().await 
        match command_name {
            "subscribe" => self.parse_subscribe_command().await,
            "unsubscribe" => self.parse_unsubscribe_command().await,
            "publish" => self.parse_publish_command().await,
            ...
        }
    }
}
```

The problem here is similar: if we are canceled while awaiting one of the `parse_foo_command` futures, then we will forget the fact that we read the `command_name` already.

## Comparison with JavaScript

It is interesting to compare Rust's `Future` model with Javascript's `Promise` model. In JavaScript, when an async function is called, it implicitly creates a new task. This task has "independent life", and it keeps executing even if nobody ever awaits it. In Rust, invoking an `async fn` returns a `Future`, but that is inert. A `Future` only executes when some task *awaits* it. (You can create a task by invoking a suitable `spawn` method your runtime, and then it will execute on its own.) 

There are really good reasons for Rust's model: in particular, it is a zero-cost abstraction (or very close to it). In JavaScript, if you have one async function, and you factor out a helper function, you just went from one task to two tasks, meaning twice as much load on the scheduler. In Rust, if you have an async fn and you factor out a helper, you still have one task; you also still allocate basically the same amount of stack space. This is a good example of the ["performant"](https://rustacean-principles.netlify.app/how_rust_empowers/performant.html) ("idiomatic code runs efficiently") Rust design principle in action.

[^relatively]: Naturally compiler and runtime heroics can make it cheaper, but it'll never be anywhere near as cheap as a function call.

**However,** at least as we've currently set things up, the Rust model does have some sharp edges. We've seen three ways to write `read_frame`, and only one of them works. **Interestingly, all three of them would work in JavaScript**, because in the JS model, an async function always starts a task and hence maintains its context.

I would argue that this represents a serious problem for Rust, because it represents a failure to maintain the ["reliability"](https://rustacean-principles.netlify.app/how_rust_empowers/reliable.html) principle ("if it compiles, it works"), whigh ought to come first and foremost for us. The result is that async Rust feels a bit more like C or C++, where performant and versatile take top rank, and one has to have a lot of experience to know how to avoid sharp edges.

Now, I am not arguing Rust should adopt the "Promises" model -- I think the Future model is better. But I think we need to tweak *something* to recover that reliability.

## Comparison with threads

It's interesting to compare how mini-redis with async Rust would compare to a mini-redis implemented with threads. It turns out that it would also be challenging, but in different ways. To start, let's write up some pseudocode for what we are trying to do:

```rust
let mut subscriptions = StreamMap::new();

spawn(async move {
    while let Some((channel_name, msg)) = subscriptions.next().await {
        connection.send_message(channel_name, msg);
    }
});

spawn(async move {
    while let Some(frame) = connection.read_frame().await {
        match frame {
            Subscribe(new_channel) => subscribe(&mut connection, new_channel),
            Unsubscribe(channel) => unsubscribe(&mut connection, channel),
            _ => ...,
        }
    }
});
```

Here we have spawned out two threads, one of which is waiting for new messages from the `subscriptions`, and one of which is processing incoming client messages (which may involve adding channels the `subscriptions` map).

There are two problems here. First, you may have noticed I didn't handle server shutdown! That turns out to be kind of a pain in this setup, because tearing down those spawns tasks is harder than you might think. For simplicity, I'm going to skip that for the rest of the post -- it turns out that [moro]'s APIs solve this problem in a really nice way by allowing shutdown to be imposed externally without any deep changes.

Second, those two threads are both accessing `subscriptions` and `connection` in a mutable way, which the Rust compiler will not accept. **This is a key problem.** Rust's type system works really well when you can breakdown your data such that every task accesses distinct data (i.e., "spatially disjoint"), either because each task owns the data or because they have `&mut` references to different parts of it. We have a much harder time dealing with multiple tasks accessing the *same data* but at *different points in time* (i.e., "temporally disjoint"). 

## Use an arc-mutex?

The main way to manage multiple tasks sharing access to the same data is with some kind of interior mutability, typically an `Arc<Mutex<T>>`. One problem with this is that it fails Rust's [*performant*](https://rustacean-principles.netlify.app/how_rust_empowers/performant.html) design principle ("idiomatic code runs efficiently"), because there is runtime overhead (even if it is minimal in practice, it doesn't feel good). Another problem with `Arc<Mutex<T>>` is that it hits on a lot of Rust's ergonomic weak points, failing our ["supportive"](https://rustacean-principles.netlify.app/how_rust_empowers/supportive.html) principle ("the language, tools, and community are here to help"):

* You have to allocate the arcs and clone references explicitly, which is annoying;
* You have to invoke methods like `lock`, get back lock guards, and understand how destructors and lock guards interact;
* In Async code in particular, thanks to [#57478](https://github.com/rust-lang/rust/issues/57478), the compiler doesn't understand very well when a lock guard has been dropped, resulting in annoying compiler errors -- though [Eric Holk](https://github.com/eholk/) is close to landing a fix for this one! :tada: 

Of course, people who remember the "bad old days" of async Rust before async-await are very familiar with this dynamic. In fact, one of the big selling points of adding async await sugar into Rust was [getting rid of the need to use arc-mutex](http://aturon.github.io/tech/2018/04/24/async-borrowing/).

## Deeper problems

But the ergonomic pitfalls of `Arc<Mutex>` are only the beginning. It's also just really hard to get `Arc<Mutex>` to actually work for this setup. To see what I mean, let's dive a bit deeper into the state for mini-redis. There are two main bits of state we have to think about:

* the tcp-stream to the client
* the `StreamMap` of active connections

Managing access to the tcp-stream for the client is actually relatively easy. For one thing, tokio streams support a [`split`](https://docs.rs/tokio/latest/tokio/io/fn.split.html) operation, so it is possible to take the stream and split out the "sending half" (for sending messages to the client) and the "receiving half" (for receiving messages from the client). All the active threads can send data to the client, so they all need the sending half, and presumably it'll be have to be wrapped in an (async aware) mutex. But only one active thread needs the receiving half, so it can own that, and avoid any locks.

Managing access to the `StreamMap` of active connections, though, is quite a bit more difficult. Imagine we were to put that `StreamMap` itself into a `Arc<Mutex>`, so that both tasks can access it. Now one of the tasks is going to be waiting for new messages to arrive. It's going to look something like this:

```rust
let mut subscriptions = Arc::new(Mutex::new(StreamMap::new()));

spawn(async move {
    while let Some((channel_name, msg)) = subscriptions.lock().unwrap().next().await {
        connection.send_message(channel_name, msg);
    }
});
```

However, this code won't compile (thankfully!). The problem is that we are acquiring a lock but we are trying to hold onto that lock while we `await`, which means we might switch to other tasks with the lock being held. This can easily lead to deadlock if those other tasks try to acquire the lock, since the tokio scheduler and the O/S scheduler are not cooprerating with one another. 

An alternative would be to use an async-aware mutex like [tokio::sync::Mutex](https://docs.rs/tokio/latest/tokio/sync/struct.Mutex.html), but that is also not great: we can still wind up with a deadlock, but for another reason. The server is now prevented from adding a new subscription to the list until the lock is released, which means that if Client1 is trying to subscribe to a new channel, it has to wait for some other client to send a message to an existing channel to do so (because that is when the lock is released). Not great.

Actually, this whole saga is covered under another async vision doc "status quo" story, [Alan thinks he needs async locks](https://rust-lang.github.io/wg-async/vision/submitted_stories/status_quo/alan_thinks_he_needs_async_locks.html).

## A third alternative: actors

Recognizing the problems with locks, Alice Ryhl some time ago wrote a nice blog post, ["Actors with Tokio"](https://ryhl.io/blog/actors-with-tokio/), that explains how to setup actors. This problem actually helps to address both our problems around mutable state. The idea is to move the connections array so that it belongs solely to one actor. Instead of directly modifying `collections`, the other tasks will communicate with this actor by exchanging messages.

So basically there could be two actors, or even three:

* Actor A, which owns the `connections` (list of subscribed streams). It receives messages that are either publishing new messages to the streams or messages that say "add this stream" to the list.
* Actor B, which owns the "read half" of the client's TCP stream. It reads bytes and parses new frames, then sends out requests to the other actors in response. For example, when a subscribe message comes in, it can send a message to Actor A saying "subscribe the client to this channel".
* Actor C, which owns the "write half" of the client's TCP stream. Both actors A and B will send messages to it when there are things to be sent to client.

To see how this would be implemented, take a look at [Alice's post](https://ryhl.io/blog/actors-with-tokio/). The TL;DR is that you would model connections between actors as tokio channels. Each actor is either spawned or otherwise setup to run independently. You still wind up using `select!`, but you only use it to receive messages from multiple channels at once. This doesn't present any cancelation hazards because the channel code is carefully written to avoid them.

This setup works fine, and is even elegant in its own way, but it's also not living up to Rust's concept of [performant](https://rustacean-principles.netlify.app/how_rust_empowers/performant.html) or the goal of "zero-cost abstractions" (ZCA). In particular, the idea with ZCA is that it is supposed to give you a model that says "if you wrote this by hand, you couldn't do any better". But if you wrote a mini-redis server in C, by hand, you probably wouldn't adopt actors. In some sense, this is just adopting something much closer to the `Promise` model. (Plus, the most obvious way to implement actors in tokio is largely to use `tokio::spawn`, which definitely adds overhead, or to use `FuturesUnordered`, which can be a bit subtle as well -- [moro] does address these problems by adding a nice API here.)

(The other challenge with actors implemented this way is coordinating shutdown, though it can certainly be done: you just have to remember to thread the shutdown handler around everywhere.)

## Cancellation as the "dark knight": looking again at `select!`

Taking a step back, we've now seen that trying to use distinct tasks introduces this interesting problem that we have shared data being accessed by all the tasks. That either pushes us to locks (broken) or actors (works), but either way, it raises the question: **why wasn't this a problem with [`select!`]?** After all, [`select!`] is still combining various logical tasks, and those tasks are still touching the same variables, so why is the compiler ok with it?

The answer is closely tied to cancellation: the [`select!`] setup works because

* the things running concurrently are not touching overlapping state:
    * one of them is looking at `subscriptions` (waiting for a message);
    * another is looking at `connection`;
    * and the last one is receiving the termination message.
* and once we decide which one of these paths to take, **we cancel all the others**.

This last part is key: if we receive an incoming message from the client, for example, we drop the future that was looking at `subscriptions`, canceling it. That means `subscriptions` is no longer in use, so we can push new subscriptions into it, or remove things from it.

So, cancellation is both what enables the mini-redis example to be performant and a zero-cost abstraction, but it is **also** the cause of our reliability hazards. That's a pickle!

## Conclusions

We've seen a lot of information, so let me try to sum it all up for you:

* Fine-grained cancellation in `select!` is what enables async Rust to be a zero-cost abstraction and to avoid the need to create either locks or actors all over the place.
* Fine-grained cancellation in `select` is the root cause for a LOT of reliability problems.

You'll note that I wrote *fine-grained* cancellation. What I mean by that is specifically things like how `select!` will cancel the other futures. This is very different from *coarse-grained* cancellation like having the entire server shutdown, for which I think structured concurrency solves the problem very well.

So what can we do about fine-grained cancellation? Well, the answer depends.

In the short term, I value reliability above all, so I think adopting an actor-like pattern is a good idea. This setup can be a nice architecture for a lot of reasons[^rdp], and while I've described it as "not performant", that assumes you are running a really high-scale server that has to handle a ton of load. For most applications, it will perform very well indeed.

[^rdp]: It'd be fun to take a look at [Reactive Design Patterns](https://www.manning.com/books/reactive-design-patterns) and examine how many of them apply to Rust. I enjoyed that book a lot.

I think it makes sense to be very judiciouis in what you [`select!`]! In the context of Materialize, [GusWynn] was [experimenting with a `Selectable` trait](https://github.com/MaterializeInc/materialize/pull/12796/) for precisely this reason; that trait just permits select from a few sources, like channels. It'd be nice to support some convenient way of declaring that an `async fn` is cancel-safe, e.g. only allowing it to be used in `select!` if it is tagged with `#[cancel_safe]`. (This might be something one could author as a proc macro.)

But in the longer term, I'm interested if we can come up with a mechanism that will allow the compiler to *get smarter*. For example, I think it'd be cool if we could share one `&mut` across two `async fn` that are running concurrently, so long as that `&mut` is not borrowed across an `await` point. I have thoughts on that but...not for this post.


