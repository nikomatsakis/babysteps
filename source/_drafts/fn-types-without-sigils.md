I have been considering a simplified approach to function types.
The current system can be summarized as something like this:

- `fn&()`: "Closures you will only call for a limited time"
- `fn@()`: "Task-local closures"
- `fn~()`: "Closures that are sendable between tasks"

This mapping is appealing but insufficient. There are many use
cases for closures that are not covered well by the current system:

- Distinguishing between closures that will only run once;
- Distinguishing between closures that only close over deeply immutable data;
- Distinguishing between closures that permit deep cloning and those
  that do not;
- Smoothly incorporating region data into closures.

Brilliant intern Ben Blum and I sat down earlier today and worked out
a scheme to extend closures to cover all of these use cases.  However,
as I tried to write it up, I realized it seemed... complicated.  More
complicated than I would like.  In particular, it had a lot of
orthogonal combinations of types, but only a few made sense.  So I've
been thinking about a way to rework all these closures into a single
function type.

The idea is that the type of a closure would be written `fn:C(T) -> U`
where the `C` is a set of "capabilities".  That is, basically, things
you plan to do with the type.  The capabitilies fall into three
categories: kind bounds, a lifetime, and a use bound.

The kind bounds are things like `copy`, `send`, or `const`.  They
indicate the kind of the closure.  So, a `fn:send()` is a sendable
closure, and a `fn:send const()` is a sendable, deeply immutable
closure.  These are the same kind bounds you can use on generic
functions to restrain the types to which they apply.  These bounds
will ultimately limit the kind of data that can be captured in the
closure's environment.

The closure lifetime indicates whether the closure contains borrowed
pointers.  All borrowed pointers in the environment must live at least
as long as the closure lifetime; if the lifetime is `&static`, as
often happens (see the defaults below), then the environment contains
only pointers into static data.

    fn[once send](

In full detail:

    [effect] [once] fn : &region kinds (T*) -> U

However, it turns

fn()
fn:once()
fn:send()       --> sendable, not copyable
fn:const send() --> 
fn:copy()       --> @fn

optional `once` "bound":
    - non-copyable
    
optional region bound:
    - defaults to & unless `send` 

problem:
    - all actions are effectively "virtual"
    - kind of "different" from the rest of the system, no sigils
    
advantage:
    - 
