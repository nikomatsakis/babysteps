---
layout: post
title: "More on fns"
date: 2013-06-03T13:40:00Z
comments: true
categories: [Rust]
---
I have been thinking about my previous proposal for fn types. I wanted
to offer some refinements and further thoughts. 

<!-- more -->

### On Thunks

I proposed a trait `Task` for encapsulating a function and the
parameters it needs to run. I don't like this name because this
concept could be used in other places beyond just tasks. I was
thinking that the proper name is probably `Thunk`. I quote [Wikipedia]
for the definition of Thunk: "In computer science, a thunk (also
suspension, suspended computation or delayed computation) is a
parameterless closure created to prevent the evaluation of an
expression until forced at a later time." (There are, admittedly,
other [contrary uses] for the term)

[Wikipedia]: http://en.wikipedia.org/wiki/Thunk_%28functional_programming%29
[contrary uses]: http://en.wikipedia.org/wiki/Thunk_%28object-oriented_programming%29

#### Sugar for thunks

One of the most common criticisms that I heard of the proposal was
that people did not like the idea of having to name the variables that
are copying into a thunk. I can understand this, though I personally
value the clarity of saying "spawn a task, taking these values out of
the containing environment and into the task". That said, if this is
the stumbling block, we could integrate thunks a bit deeper into the
language's surface syntax, if not the type system, to avoid this
issue.

Basically, you could imagine a keyword `thunk { ... }` that does
precisely what my `thunk!(...)` macro did, except that it
automatically determines the captured variables, rather than requiring
they be listed.

Similarly, the `do` syntax could be extended to so that it can be used
with a function that expects either a `fn` or a `[sigil] Thunk`
object. If the function expects a `fn`, then `do func { ... }` would
be equivalent to `func(|| ...)`. If the function expects a `[sigil]
Thunk`, then `do func { ... }` would be equivalent to
`func([sigil]thunk { ... })`. This would be that we could continue to
write the "pleasingly ambiguous" `do spawn { ... }` syntax, which is
popular despite hiding allocations and makes the meaning of code
dependent on the type of the callee (`/me pouts`).

### Once functions

I haven't made up my mind whether it makes sense to include `once fn`
or not.  On the one hand, as I showed, you can workaround it in a
mechanical fashion, and I think it's wise to avoid "mission creep" in
the type system. On the other, the workaround is somewhat clumsy, and
probably not something you want to do all that often.

To try and get a better feeling for how often once fns would be
needed, I did a survey of all closures that appear in the core
library. I found that the vast majority were executed multiple
times. There were however a couple of common patterns where once fns
appeared.

The pattern I had most in mind with once fns is setup/teardown
functions, like `task::unkillable`, which use a closure to indicate
what should be done between the setup and teardown. At least in the
standard library, these functions are not *that* common, but they do
occur.

Another common example is the `with` pattern, where you have a
callback that is invoked with a reference to the data inside your
object. This is relatively unusual now that we have lifetimes, it only
occurs in a few specialized cases like locks, where extra action is
needed before and after the `with`.

There was one example where `once fn` would be useful that stood out
to me, however. Ironically, it is something that I myself proposed in
a [recent e-mail to rust-dev][defaults], where I suggested that we
should encode "default" arguments using closures. So, for example, a
function like Option's `get_or_default`, which is currently written:

    fn get_or_default<T>(opt: Option<T>, default: T) -> T
    
would take a closure instead:

    fn get_or_default<T>(opt: Option<T>, default: fn() -> T) -> T

However, without once fns, this is in fact somewhat less flexible. To
see what I mean, imagine trying to implement the old behavior (taking
a value) on top of the proposed behavior (taking a closure):

    fn get_or_default_value<T>(opt: Option<T>, default: T) -> T {
        get_or_default(opt, || default)
    }
    
If you try to compile this, the compiler will signal an error because
the `|| default` closure is *moving* the argument default, and this is
not legal within a closure because the closure may execute multiple
times. Therefore, to write this wrapper, one would have to either copy
the default value or use a cell, which is very unsatisfying. I only
realized this problem would occur when
[kballard encountered it][kballard] when refactoring the methods on
hashmap.

Of course, it would be possible to write `get_or_default` using the 
pattern I proposed, in which we pass an extra argument to carry any
moved values:

    fn get_or_default<T,A>(opt: Option<T>, arg: A, default: fn(A) -> T) -> T

In that case, one could write the wrapper easily enough, although it
is a bit repetitive:

    fn get_or_default_value<T>(opt: Option<T>, default: T) -> T {
        get_or_default(opt, default, |default| default)
    }
    
This would however mean that the common case, where nothing is moved,
gets more verbose:

    get_or_default(opt, (), |()| do_something())

So I find myself unsure about whether to include once fns or not.  I
don't mind having to write this "pass an extra argument" pattern once
in a while, but I do expect the default pattern to come up somewhat
regularly in the standard library (certainly it occurs with options
and maps, not sure where else). Ideally I'd prefer to defer once fns
for "post Rust 1.0", but it might be a bit unfortunate if we wound up
with standard interfaces that include extra argument parameters that
later became unnecessary. This is particularly true since `once fn`
aren't complicated to implement.

[kballard]: https://github.com/mozilla/rust/pull/6815#issuecomment-18781051

#### Expressing once fns with thunks

You might think that you could replace `once fns` with thunks, since
they too are run-once. This is particularly appealing if we opted for
thunk sugar. However, the main problem here is the question of a
*copying* vs *by reference* closure. The way I described thunks, they
were always copying the values they close over. So if you wrote:

    get_or_default(opt, &thunk { do_something(a, b) })
    
This would copy/move `a` and `b` from the enclosing stack frame into
the thunk. Of course, you can make a thunk that takes a reference into
the enclosing stack frame, just by capturing a reference:

    let r_a = &a;
    let r_b = &b;
    get_or_default(opt, &thunk { do_something(r_a, r_b) })
    
But this is rather inconvenient. So we'd presumably want to extend our
`thunk` sugar to do this automatically. But then we'd need to
distinguish between by reference thunks and copying thunks. We'd
probably use the `&` sigil here, which would in turn mean that if you
use the `do` syntax it's not clear whether references are copying or
by reference. This is all...tolerable, but it winds up feeling a lot
*more* complicated to me than saying "`thunk`s copy/move the values
they close over, `fn`s takes them by reference, a `once fn` can only
be called once."

[defaults]: https://mail.mozilla.org/pipermail/rust-dev/2013-May/004281.html

### Type names bikeshed

I mentioned in passing that I am not a fan of the `extern fn` name.
It was suggested that perhaps raw function pointers should be `fn` and
closures should be something else, such as `closure(S) -> T`, `proc(S)
-> T`, or even `|S| -> T`. This is pure bikeshedding, but it has some
appeal, since the type of a fn item would be `fn(S) -> T`, the type of
an extern fn would be `extern "C" fn(S) -> T`, and the type of a
closure would be, well, whatever it is. The main downside is that
closure types are what you want most of the type, and `fn(S) -> T` is
so nice and concise. Also, we'd need to find a place to put the
closure bounds.

