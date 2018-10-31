---
layout: post
title: 'Office Hours #1: Cyclic services'
categories: [Rust, OfficeHours]
---

This is a report on the second ["office hours"][oh], in which we
discussed how to setup a series of services or actors that communicate
with one another. This is a classic kind of problem in Rust: how to
deal with cyclic data. Usually, the answer is that the cycle is not
necessary (as in this case).

[oh]: https://github.com/nikomatsakis/office-hours

### The setup

To start, let's imagine that we were working in a GC'd language, like
JavaScript. We want to have various "services", each represented by an
object. These services may need to communicate with one another, so we
also create a **directory**, which stores pointers to all the
services. As each service is created, they add themselves to the
directory; when it's all setup, each service can access all other
services. The setup might look something like this:

```js
function setup() {
  var directory = {};
  var service1 = new Service1(directory);
  var service2 = new Service2(directory);
  return directory;
}

function Service1(directory) {
  this.directory = directory;
  directory.service1 = self;
  ...
}

function Service2(directory) {
  this.directory = directory;
  directory.service2 = self;
  ...
}
```

### "Transliterating" the setup to Rust directly

If you try to translate this to Rust, you will run into a big mess.
For one thing, Rust really prefers for you to have all the pieces of
your data structure ready when you create it, but in this case when we
make the directory, the services don't exist. So we'd have to make the
struct use `Option`, sort of like this:

```rust
struct Directory {
    service1: Option<Service1>,
    service2: Option<Service2>,
}
```

This is annoying though because, once the directory is initialized, these
fields will never be `None`.

And of course there is a deeper problem: who is the "owner" in this
cyclic setup? How are we going to manage the memory? With a GC, there
is no firm answer to this question: the entire cycle will be collected
at the end, but until then each service keeps every other service
alive.

You *could* setup something with [`Arc`] (atomic reference counting)
in Rust that has a similar flavor. For example, the directory might
have an [`Arc`] to each service and the services might have weak refs
back to the directory. But [`Arc`] really works best when the data is
immutable, and we want services to have state. We could solve *that*
with [atomics] and/or [locks], but at this point we might want to step
back and see if there is a better way. Turns out, there is!

[`Rc`]: https://doc.rust-lang.org/std/rc/struct.Rc.html
[`Arc`]: https://doc.rust-lang.org/std/sync/struct.Arc.html
[`Cell`]: https://doc.rust-lang.org/std/cell/struct.Cell.html
[`RefCell`]: https://doc.rust-lang.org/std/cell/struct.RefCell.html
[atomics]: https://doc.rust-lang.org/std/sync/atomic/struct.AtomicU32.html
[locks]: https://doc.rust-lang.org/std/sync/struct.RwLock.html

### Translating the setup to Rust without cycles

Our base assumption was that each service in the system needed access
to one another, since they will be communicating. But is that really
true? These services are actually going to be running on different
threads: all they really need to be able to do is to **send each other
messages**. In particular, they don't need access to the private bits
of state that belong to each service.

In other words, we could rework out directory so that -- instead of
having a handle to each **service** -- it only has a handle to a
**mailbox** for each service. It might look something like this:

```rust
#[derive(Clone)]
struct Directory {
  service1: Sender<Message1>,
  service2: Sender<Message2>,
}

/// Whatever kind of message service1 expects.
struct Message1 { .. }

/// Whatever kind of message service2 expects.
struct Message2 { .. }
```

What is this [`Sender`] type? It is part of the channels that ship in
Rust's standard library. The idea of a channel is that when you create
it, you get back two "entangled" values: a [`Sender`] and a [`Receiver`]. You
send values on the sender and then you read them from the receiver;
moreover, the sender can be cloned many times (the receiver cannot).

[`Sender`]: https://doc.rust-lang.org/std/sync/mpsc/struct.Sender.html
[`Receiver`]: https://doc.rust-lang.org/std/sync/mpsc/struct.Receiver.html

The idea here is that, when you start your actor, you create a channel
to communicate with it. The actor takes the [`Receiver`] and the
[`Sender`] goes into the directory for other servies to use.

Using channels, we can refactor our setup. We begin by making the
channels for each actor. Then we create the directory, once we have
all the pieces it needs. Finally, we can start the actors themselves:

```rust
fn make_directory() {
  use std::sync::mpsc::channel;

  // Create the channels
  let (sender1, receiver1) = channel();
  let (sender2, receiver2) = channel();

  // Create the directory
  let directory = Directory {
    service1: sender1,
    service2: sender2,
  };

  // Start the actors
  start_service1(&directory, receiver1);
  start_service2(&directory, receiver2);
}
```

Starting a service looks kind of like this:

```rust
fn start_service1(directory: &Directory, receiver: Receiver<Message1>) {
  // Get a handle to the directory for ourselves.
  // Note that cloning a sender just produces a second handle
  // to the same receiver.
  let mut directory = directory.clone();

  std::thread::spawn(move || {
    // For each message received on `receiver`...
    for message in receiver {
      // ... process the message. Along the way,
      // we might send a message to another service:
      match directory.service2(Message2 { .. }) {
        Ok(()) => /* message successfully sent */,
        Err(_) => /* service2 thread has crashed or otherwise stopped */,
      }
    }
  });
}
```

This example also shows off how Rust channels know when their
counterparts are valid (they use ref-counting internally to manage
this). So, for example, we can iterate over a `Receiver` to get every
incoming message: once all senders are gone, we will stop
iterating. Beware, though: in this case, the directory itself holds one of
the senders, so we need some sort of explicit message to stop the actor.

Similarly, when you send a message on a Rust channel, it knows if the
receiver has gone away. If so, `send` will return an `Err` value, so
you can recover (e.g., maybe by restarting the service).

### Implementing our own (very simple) channels

Maybe it's interesting to peer "beneath the hood" a bit into channels.
It also gives some insight into how to generalize what we just did
into a pattern. Let's implement a **very** simple channel, one with a fixed
length of 1 and without all the error recovery business of counting
channels and so forth. 

Note: If you'd like to just view the code, [click here to view the
complete example on the Rust playground][pg].

[pg]: https://play.rust-lang.org/?gist=9fc3d90b50e8af1470a0d488fb3993b9&version=stable&mode=debug&edition=2015

To start with, we need to create our `Sender` and `Receiver` types.
We see that each of them holds onto a `shared` value, which contains
the actual state (guarded by a mutex):

```rust
use std::sync::{Arc, Condvar, Mutex};

pub struct Sender<T: Send> {
  shared: Arc<SharedState<T>>
}

pub struct Receiver<T: Send> {
  shared: Arc<SharedState<T>>
}

// Hidden shared state, not exposed
// to end-users
struct SharedState<T: Send> {
  value: Mutex<Option<T>>,
  condvar: Condvar,
}
```

To create a channel, we make the shared state, and then give the
sender and receiver access to it:

```rust
fn channel<T: Send>() -> (Sender<T>, Receiver<T>) {
  let shared = Arc::new(SharedState {
    value: Mutex::new(None),
    condvar: Condvar::new(),
  });
  let sender = Sender { shared: shared.clone() };
  let receiver = Receiver { shared };
  (sender, receiver)
}
```

Finally, we can implement `send` on the sender. It will try to
store the value into the mutex, blocking so long as the mutex is `None`:

```rust
impl<T: Send> Sender<T> {
  pub fn send(&self, value: T) {
    let mut shared_value = self.shared.value.lock().unwrap();
    loop {
      if shared_value.is_none() {
        *shared_value = Some(value);
        self.shared.condvar.notify_all();
        return;
      }

      // wait until the receiver reads
      shared_value = self.shared.condvar.wait(shared_value).unwrap();
    }
  }
}
```

Finally, we can implement `receive` on the `Receiver`. This just waits
until the `shared.value` field is `Some`, in which case it overwrites
it with `None` and returns the inner value:

```rust
impl<T: Send> Receiver<T> {
  pub fn receive(&self) -> T {
    let mut shared_value = self.shared.value.lock().unwrap();
    loop {
      if let Some(value) = shared_value.take() {
        self.shared.condvar.notify_all();
        return value;
      }

      // wait until the sender sends
      shared_value = self.shared.condvar.wait(shared_value).unwrap();
    }
  }
}
```

Again, [here is a link to the complete example on the Rust playground][pg].

### Dynamic set of services

In our example thus far we used a static `Directory` struct with
fields. We might like to change to a more flexible setup, in which the
set of services grows and/or changes dynamically. To do that, I would
expect us to replace the directory with a `HashMap` mapping from kind
of service name to a `Sender` for that service. We might even want to
put that directory behind a mutex, so that if one service panics, we
can replace the `Sender` with a new one. But at that point we're
building up an entire actor infrastructure, and that's too much for
one post, so I'll stop here. =)

### Generalizing the pattern

So what was the general lesson here? In often happens that, when
writing in a GC'd language, we get accustomed to lumping together all
kinds of data together, and then knowing what data we should and
should not touch. In our original JS example, all the services had a
pointer to the complete state of one another -- but we expected them
to just leave messages and not to mutate the internal variables of
other services. Rust is not so trusting.

In Rust, it often pays to separate out the "one big struct" into
smaller pieces. In this case, we separated out the "message
processing" part of a service from the rest of the service state. Note
that when we implemented this message processing -- e.g., our channel
impl -- we still had to use some caution. We had to guard the data
with a lock, for example. But because we've separated the rest of the
service's state out, we don't need to use locks for that, because no
other service can reach it.

This case had the added complication of a cycle and the associated
memory management headaches. It's worth pointing out that even in our
actor implementation, the cycle hasn't gone away. It's just reduced in
scope. Each service has a reference to the directory, and the
directory has a reference to the `Sender` for each service. As an example
of where you can see this, if you have your service iterate over all
the messages from its receiver (as we did):

```rust
for msg in self.receiver { .. }
```

This loop will continue until all of the senders associated with this
`Receiver` go away. But the service itself has a reference to the
directory, and that directory contains a `Sender` for this receiver,
so this loop will never terminate -- unless we explicitly
`break`. This isn't too big a surprise: Actor lifetimes tend to
require "active management". Similar problems arise in GC systems when
you have big cycles of objects, as they can easily create leaks.

