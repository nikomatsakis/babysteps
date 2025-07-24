---
layout: post
title: "Regions and let polymorphism"
date: 2012-04-20T20:19:00Z
comments: true
categories: [Rust]
draft: true
---

**Warning**: Brain dump post ahead.  This is kind of a "work in
progress" with regard to some of the problems that I am running into
with my work on regions.  I'd like to write a post about the system
I've been working on that gives proper background and context, but
this one is not that post, so I don't know that it'll be
understandable to those of you who are not named Nicholas D. Matsakis.
It's just helpful for me to write things out sometimes.

I just realized something today...region types are a fairly
non-trivial extension to our type system in the sense that they move
us from "let polymorphism" to something more complex.  This should
have been obvious sooner.  

In fact it was something I thought about, but I didn't consider its
implications until now. To be honest, I don't fully understand whether
these are large or small.  Right now they seem... medium.  I'm going
to have to go read up on my type theory a bit.

### Background on let polymorphism

A bit of background (more may be found in [this Wikipedia article][hm]
along with numerous other sources).  In ML and many languages, types
are divided between *monotypes* and *type schemas*.  A monotype is
so-called because it a single type.  For example, `int`, `str`,
`list<int>`, or `fn(int) -> int` are all monotypes (using Rust
notation).

[hm]: http://en.wikipedia.org/wiki/Hindley%E2%80%93Milner

Type schemas on the other hand allow for "bound variables".  Basically
it means they are a schema from which one can produce many types.  So,
something like `<T> fn(T) -> T` would be a type schema.  Here the
`<T>` indicates that the remainder of the type holds for any value of
`T`.  So the monotype `fn(int) -> int` is an instance of this schema,
as is `fn(str) -> str`.

Segregating types into type schemas and monotypes is somewhat less
general but is convenient.  Consider, for example, this function:

    fn identity<T>(t: T) -> T { t }
    
Now assume that I have some code which does the following:

    let id = identity;
    let x = id("str");
    let y = id(3);
    
In principle thie code should be fine.  The identity function, after
all, can be applied to any type, including both strings and integers.
However, if you try to write this in Rust (or in ML), you will get a
type error.  This is because the type of each variable must be a
monotype.  So the type of `id` could be `fn(str) -> str` or `fn(int)
-> int`, but cannot be both.  It cannot be `<T> fn(T) -> T`.

In practice, what happens is that when the compiler tries to determine
the type of the expression `identity` (that is, a generic function) it
creates type variables for each type parameter.  These variables are
used in inferencing.  So the type of the local variable `id` is
something like `fn($0) -> $0`, where `$0` is a type variable.  The
next line which applies `id` to a string would constrain `$0` to be a
string.  The next line would then try to constrain `$0` to be an int,
but this conflicts with prior constraints, and so an error is
reported.

Loosely speaking, this kind of polymorphism, in which the use of a
generic function yields a monotype, is called let polymorphism.  This
derives from the fact that in ML, the generic type parameters are not
declared as they are in Rust, and so when defining a function using a let:

    let identity t = t 
    
there would be a special "generalization" step that would end up
inferring a type schema for identity of `<T> fn(T) -> T`.  

At least this is how I understand it.  Inference is one of those
things I wish I understood better (there are so many such things, it
seems), so there may well be errors in this summary, which I'm sure
will surface in the comment section. :)

### What does this have to do with regions?

The way we've been envisioning it, a region type like:

    fn(&a.T)
    
defines a function which, for any region `a`, expects region pointer
to a type `T` in `a`.  In other words, it's not *precisely* a
monotype, it contains bound variables---but not type variables.  Using
the notation I was using in the prioir section, it might be written
like this:

    <&a> fn(&a.T)
    
Unlike type variables, which are instantiated whenever a generic
function is *referenced*, these region variables are instantiated each
time the function is *called*.  This means I could do something like:

    let x_t: &x.T = ...;
    let y_t: &y.T = ...
    
    let f: fn(&a.T) = ...;
    f(x_t);
    f(y_t);

Here the variable `f` was invoked twice with two different regions.
If you recall, this was not possible with two different types.

### Do we have do to it this way?

Actually, it's quite possible it does not.  I think we can almost
always get away with functions that do not, in fact, bind region
variables.  Quite often we know the region that will be used.  For
example, here is a function to map an option type:

    fn map<S,T>(opt: &a.option<S>, f: fn(&a.S) -> T) -> option<T> {
        alt *opt {
            none { none }
            some(s) { f(s) }
        }
    }

Here I have chosen to use an explicit region name `a`, which makes it
clear that the function `f` will be invoked with a pointer that
derives from the first parameter `opt` (in fact, this explicit region
name would not be needed).

However, there are a few cases where bound region parameters seem very
nice.  One is when you are placing functions into data structures.  If you
do something like:

    type rec = @{
        f: fn@(&X)
    };
    
You probably mean for the function stored in `f` to accept any `X`
instance.  Instead, if fields and variables are always monotypes, then
it would only accept `X` instances from some specific region (the
`self` region associated with this record... I know I haven't spelled
out the details of the region system I've been working on, so this
isn't well defined, sorry about that).

I had also hoped to make use of bound regions to allow us to do things
like send graphs of data (not just trees) around between processes.
The way I had thought to do this was to have a type kind of like
`msg<T>`, which would be a self-contained graph of objects which contains
a "head object" of type `T`.  You could construct such a message like so:

    fn mk_msg(f: fn(arena: &a.arena) -> &a.T) -> ~msg<T>
    
What `mk_msg` does is to create a new arena and then call `f()` with
that arena as argument.  `f` is then responsible for allocating data
in the arena and building up the graph of objects to send, finally
returning the head object.  `mk_msg` would then bundle up the head
object and the arena into this opaque type `~msg<T>`.

You could then send the message around.  If you wanted to work with
the message, you could use functions like `do_with_msg`:

    fn do_with_msg<T,U>(
        m: &msg<T>,
        f: fn(arena: &a.arena, head: &a.T) -> U) -> U
        
This function would unpack the message and invoke `f()` with the
contents.  

These `msg` functions really rely on the functions
being generic with respect to the regions of their arguments.

#### A possible workaround

However, there is actually a workaround that might prove re

### What does this all mean?

Is this the death knell of regions?  I don't think so.  But it will
complicate our inference and type-checking rules somewhat.  

With regard to inference, you have to be careful to avoid working
bound regions.  Consider a function like `two_fns()`, for example:

    fn two_fns<A>(x: fn(A), y: fn(A) { ... }
    
What might be less than obvious is that, with a signature like this, 
you cannot in fact pass a function that takes a bound region argument 
for `x` or `y`.  An example might help.  This code would be illegal

    fn identity(x: &int) -> &int { x }
    two_fns(identity, identity)
    
The key here is that the first argument to identity is an integer in
some region specified by the caller; there is no monotype that can
express that concept, and `A` must be instantiated to a monotype.

You could however rewrite two_fns as:

    fn two_fns<A>(x: fn(&A), y: fn(&A) { ... }
    
and now you could call `two_fns(identity, identity)` without problem.
This is because `A` would just be mapped to `int`.

There is also the question of subtyping.  We probably want these
two functions to be considered equivalent, for example:

    fn(x: &a.uint, y: &b.uint)
    fn(x: &b.uint, y: &a.uint)
    
And so forth.

### Oh.

Yes.

