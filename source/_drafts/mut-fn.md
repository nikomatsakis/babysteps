I've been thinking about what I wrote in my last post regarding
closures and I am beginning to change my opinion about the correct
solution. So, besides writing `fn~`, what are the other options?  I
just thought I'd write down the other ideas I've come up with.  Not
saying any of the ideas in this post are good yet.

### Just write `&mut fn()`

Maybe it's not so bad. It is advertising the possibility that the
closure may mutate its environment. This would mean that while `&fn()`
is a valid type, it is a type that does not permit the function to be
called, much as `&&mut` (pointer to a mutable borrowed pointer) does
not permit the mutable borrowed pointer to be used.

At first I was thinking that there is also a valid interpretation for
`&fn`, meaning a function that does not mutate the variable in its
environment, but then I realize that per the DST proposal any `&mut
fn` could be borrowed to `&fn`, and so that would not be sound.

### Remove everything but borrowed closures

We could just *only have* borrowed closures. The type would be written
`fn[:bounds]()` or `once fn[:bounds]()`. There'd be no need to notate
the kind of environment pointer: it's always a borrowed pointer. All
other uses of closures would be expressed using traits and impls.

Mainly this means that code which spawns traits would get somewhat
verbose, because you would need to create a struct or some other type
to capture all of the upvars. For larger tasks, this is not a big
deal, but for some code it could be rather annoying. I imagine futures
in particular would become much more verbose; enough so as to be
nearly unusable.

On the upside, there'd be no more confusion about whether a closure
copies its environment or not (no, it never does). Closure types would
be simpler (no need to worry about sigils). You'd write `fn()` or
`once fn()` in all but the most esoteric cases. The code to manage
closures would become much simpler.

### Add a new keyword for what is now called an "owned closure"

This is basically the `fn~` solution with another name. Rather than
writing `fn~` to indicate a closure value that owns its environment,
we could write `proc` (for procedure) or something like that.  This
avoids the annoying "sigil after the name", at the cost of a new
keyword.

Procedures could probably *always* be single-shot (that is, `once`).
Almost all use cases for them (futures, tasks, etc) are single-shot,
and the others could probably be accommodated with traits instead. But
we could also distinguish between a `proc` and a `once proc` if we
wanted.

Procedures would probably be less interoperable with functions, since
the name does not particularly suggest interoperability. For example,
I imagine you could not use a `proc` where a `fn` is expected. I don't
know of any time that this is actually important.

Using a different name also helps to draw a clear line between between
"closures" (which reference the variables in the stack frame that
created them) and "procedures" (which copy out from that stack frame).
I personally would prefer to designate procedures with a different
syntax, e.g., `proc(x, y) { ... }` in place of `|x, y| ...`, but this
is not *necessary* (as an aside, I had hoped to write some today about
why I think our current use of `||` to designate any kind of closure
is troublesome and should be changed, before I realized that we'd have
to address this problem I'm thinking over instead).

### More ideas?

Ok, that's most of the more radical ideas I've had so far. I'll have
to keep thinking on it.
