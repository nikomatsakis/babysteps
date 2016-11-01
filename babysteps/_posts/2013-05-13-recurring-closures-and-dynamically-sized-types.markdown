---
layout: post
title: "Recurring closures and dynamically sized types"
date: 2013-05-13 10:35
comments: true
categories: [Rust]
---
I realized today that there is an unfortunate interaction between the
proposal for [dynamically sized types][dst] and closure types. In
particular, in the [case of the recurring closure][crc], I described
the soundness issues that arise in our language when closures are able
to recurse.

My solution for this was to make the type system treat a `&fn()` value
the same way it treats `&mut T` pointers: they would be non-copyable,
and when you invoke them, that would be effectively like a "mutable
borrow", meaning that for the duration of the call the original value
would become inaccessible. So in short the type system would guarantee
that when you call a closure, that same closure is not accessible from
any other path in the system, just as we now guarantee that when you
mutate a value, that same value is not accessible from any other path
in the system.

This is all well and good, and I think this treatment would be largely
invisible to the user under common access patterns. However, it does
not play well with the proposal for [dynamically sized types][dst],
because under this proposal all things written `&T` must behave the
same, no matter what `T` is. This is in fact *the whole point* of the
proposal! But here I want to treat `&fn` specially.

I've been pondering various solutions this morning. I have come up
with two possible avenues:

1. Instead of writing `&fn()` you could write `&mut fn()`. This is
perhaps the "principled" solution, but I consider it rather a
non-starter.  Writing `&fn()` for a closure is...tolerable, but `&mut
fn()` is not. It's verbose and it seems sort of nonsensical (although
there is some logic to it, when you consider that calls to the
function may mutate the environment and so forth).

2. We go back to the older notation and move sigils for closures
*after* the fn. This actually has some notational perks. For example,
rather than writing `&fn()` we can just write `fn()` (if there is no
sigil, we can default to `&`). On the minus side, a sendable closure
would be written `fn~()`---but, then again, under the dynamically
sized types proposal, sendable closures were going to be written
`~fn:Owned()`, so is `fn~()` really so bad?

More details after the fold.

<!-- more -->

OK, let's dig into the details a bit more. As anyone who has been
following my blog posts probably knows by now, there are many, many
use cases for closures. I want to dive into the use cases that are on
my mind and elaborate on them. I also want to take this case to write
up a bit more thoroughly how I think closures should work, including a
few unrelated issues.

### Syntax and use cases

Here is a list of use cases to be accommodated:

1. "Higher-order functions": simple functions like `map`, `fold`
   and so forth. By far the most common use case.
2. "Once functions": functions that can only execute once. This means
   that they can move values out of their environment.
3. "Sendable functions": functions that can be sent between tasks.
   This means that they only close over "sendable" values (no
   garbage-collected data or borrowed pointers).
4. "Sendable once functions": sendable functions that can only execute
   once. This is what a task body will be.
5. "Const functions": functions that do not close over mutable state.
   We don't make much use of this yet, but I plan to do so in order to
   achieve lightweight fork-join parallelism a la [PJS][pjs].
   
The use cases above seem to me to be the "bread and butter" cases that
will arise frequently. I will go over the syntax and give an example
for each of those use cases shortly. Interestingly, I think that all
of them actually read reasonably well if the sigils are moved after
the `fn` keyword, and in some cases the examples read much better.

However, there are two additional use cases that I have considered in
the past which I left out. These use cases become significantly harder
to read under the new proposal (though they were always hard to read).
Interestingly, I realized while writing this blog post that I think
these use cases are no longer terribly important, since both of them
can be expressed equally well using objects instead of closures, as I
will explain shortly. The two use cases are:

1. "Sendable const functions": functions that can be sent between tasks
   *and* do not close over mutable state. You could safely share such
   functions between tasks in an ARC (atomically referenced counted
   container) and execute them multiple times in parallel.
2. "Combinators": combinator libraries create *and return* closures that
   closure over their arguments, which may include borrowed values.

#### Higher-order functions

Here is an example of a simple higher-order function (with the closure
type highlighted):

    impl<T:Sized> for [T] {
        pub fn map<U:Sized>(f: fn(&T) -> U) -> ~[U] { ... }
                            // ^~~~~~~~~~~
    }

For contrast, this is `&fn(&T) -> U` today.

#### Once functions

Here is an example of a higher-order function that executes at most
once:

    impl<T:Sized> for Option<T> {
        pub fn each(f: once fn(&T) -> bool) -> bool { ... }
                    // ^~~~~~~~~~~~~~~~~~~
        }
    }

For contrast, this is `&once fn(&T) -> U` today.

#### Sendable functions and sendable once functions

Here is an example of a sendable once function:

    fn spawn(f: once fn~()) {...}
             // ^~~~~~~~~~

The `~` after the `fn` tells the type system that the environment for
this function is allocated using an owned pointer. It also implies a
default bound of `Owned`. The `once` tells the type system that the
function will only execute once.

For contrast, this is `~once fn()` today.

#### Const functions

Here is an example of how I would use a const function to achieve
lightweight parallelism:

    impl<T:Sized> for [T] {
        pub fn par_map<U:Sized>(f: fn:Const(&T) -> U) -> bool { ... }
                                // ^~~~~~~~~~~~~~~~~
    }

This is a parallel map function. It is similar to the regular map
except that its iterations execute in parallel. As a consequence, it
demands a `fn:Const` rather than a `fn`---the `Const` bound specifies
that all the environmental state must be immutable. This is exactly
the "patient parent" or "parallel closures" model that is used in
[PJS][pjs] and described in [this HotPar paper I wrote][epc].

For contrast, this is `&fn:Const()` today.

#### Sendable const functions

Sendable const functions are one of the two cases that I said would
become less attractive under the new proposal. They would look
something like `fn~:Const` (vs `~fn:Const` today). The newer syntax
works and should be available, but it's hard to read, due I think to
the juxtaposition of `~` (which specifies the kind of pointer used for
the environment) and the `:` that begins the bound specifier `:Const`.
If this use case were important, I might be worried that the syntax is
too ugly, but when I tried to come up with an example for where this
use case would be needed, I realize that time has left the use case
behind to some extent.

The primary use case for a sendable const function initially was to
allow hashtables to be placed in ARCs---the reason for this was that a
`HashMap` requires closures for for computing the hash function of its
argument, and those to share the hashmap (and perform parallel
lookups) we had to be sure that the closures would not mutate any
state. However, this is somewhat outdated, because hashing and
equality comparison today is based on traits rather than closures.

Now, using traits is somewhat limited, because due to coherence it
means that any one type can only be hashed in one way, and sometimes
you would like to have specialized hashing for specific circumstances.
But these use cases can easily be accommodated in three ways:

1. Using newtyped keys (`struct MyKey(key)`) and defining different
   implementations for the hashing and equality traits on `MyKey`.
2. If a newtyped key is not acceptable, you can write a hash table
   that takes a simple function pointer (`extern "Rust" fn`) rather
   than a closure. Function pointers carry no state, but state is
   rarely needed for equality comparisons.
3. If you really need state, then you can write a specialized trait
   in lieu of a closure:
   
       trait HashFuncs<K> {
           fn hash(&self, k: &K) -> uint;
           fn eq(&self, k1: &K, k2: &K) -> bool;
       }
       
   Now your hashtable can either take a `~HashFuncs` object to use
   for hashing and equality comparison or, if you wish to avoid 
   dynamic dispatch for performance reasons, you can parameterize
   your hashtable type by the instance of `HashFuncs` that it should use:
   
       struct MyHashMap<K,V,F:HashFuncs<K>> {
           f: F,
           ...
       }

#### Combinators

General purpose combinators are the other case that (might) get less
attractive. This is less clear cut. The idea of a combinator library
is that you have functions that return functions, and then you can
compose these functions into bigger functions. The most common example
is a [parser combinator][pc], which is a simple way to create
inefficient and buggy parsers (ok, that's unfair, but I couldn't
resist; I've had some bad experiences trying to scale up parser
combinators---truth is, they are super nice to work with, at least
until things go wrong).

*Anyway,* a typical parser combinator library would begin with a primitive
like the following:

    fn expect(c: char) -> fn@(&mut ParseState) -> Result<(), Err> { ... }
                       // ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Note that the function returns a closure. We used `fn@` because this
closure must be allocated on some heap in order for us to return it,
and because using the type `fn@` (vs say `fn~`) would allow us to
close over managed and other task-local data. So far, I think this
example works out fine.

Where things get more complex is if we want to close over borrowed
pointers.  For example, imagine an `expect` function that takes a
slice:

    fn expect_string<'a>(s: &'a str)
                         -> fn@:'a(&mut ParseState) -> Result<(), Err> {...}
                         // ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Here the type system will require that the lifetime `'a` of the input
slice `s` appear in the resulting function type, so that it can be
sure that the function is not used after the slice is no longer valid.
This makes the type more complicated: `fn@:'a` (vs the
also-not-especially-intuitive notation of `@'a fn` today).

Of course, one could address this problem by having `expect_string`
take a `~str` or `@str` instead of a borrowed string, but in some use
cases borrowed pointers may perfect sense. For example, I had once
thought to use this pattern to create a combinator library for
expressing iteration primitives like `enumerate` and so forth
(similar, experimental work is now underway in the `iter` module).

Interestingly, just as with sendable const closures, objects and
traits can provide an alternative that is ultimately (I think) a
better and more readable design anyway. We could rewrite the return
type from a closure into a trait:

    trait Parser<R> {
        fn parse(&mut ParseState) -> Result<R,Error>;
    }
    
    fn expect(c: char) -> @Parser<()>;
    fn expect_string<'a>(s: &'a str) -> @Parser:'a<()>;
    
Here in the `expect_string` case I have taken advantage of the fact
that object types will also carry bounds similar to closure types.  An
advantage of this design is that using a trait allows the `Parser`
objects to carry more methods as well.

If we were to extend the example to include an actual *combinator*,
I imagine it would look something like this:

    fn or<'a, R>(p1: @Parser:'a<R>, p2: @Parser:'a<R>) -> @Parser:'a<R> {...}
    
Of course, for maximum efficiency, one would avoid using object types
altogether. Then you would just implement `Parser` directly on
the `char` and `&str` types, and perhaps write the `or` combinator
like so:

    struct or<P1,P2>(P1, P2);
    
    impl<R,P1:Parser<R>,P2:Parser<R>> Parser for or<P1,P2> {
      fn parse(&self, state: &mut ParseState) -> Result<R,Error> {
        let (ref p1, ref p2) = *self;
        state.try(); // (*)
        match p1.parse(state) {
          Ok(r) => { state.confirm(); Ok(r) }
          Err(_) => { state.backtrack(); p2.parse() }
        }
      }
    }
    
    // (*) Here you see my imperative roots. A true functional
    // programmer would not use in-place mutation here but rather
    // clone and return a new parser state.

### Summary

Another long post mostly targeted at rust devs and myself. Sorry about
that. I think the bottom line is that we should move sigils for
closures and have them appear after the `fn` keyword. This makes me
sad, because this is how things used to be, and in fact one of the
main goals of the [dynamically sized types (DST)][dst] proposal was to
move the sigils in closure types in front. But of course soundness
comes first, and I think the general wins of the DST proposal
(consistent behavior for all `&T`, `@T`, `~T` etc) outweigh the need
to write `fn~` on occasion (I don't really see much use for `fn@`).

There is also one final solution I didn't mention in my initial
paragraphs. We could adopt the "principled" solution of using `&mut`
for closures but change the way we notate `&mut`. I have largely
avoided thinking about because I want to avoid destabilizing syntax
changes. However, I have toyed around occasion with an idea for
reorganizing our types to emphasize ownership and de-emphasize
mutability, which goes in this direction.  I may indulge myself and
write it up at some point. Still, I largely consider this a
non-starter.

Adopting the "move sigils in back" proposal does have another
casualty, though. There has been some talk of figuring out ways to
make `@` and `~` less special (as in, allowing user-defined pointer
types like `RefCounted<T>` that are on equal footing). The DST
proposal is clearly a step in that direction. Moving the sigils
backwards on `fn` types is, well, a step backward, because closures
would always be allocated using a limited set of allocators (stack,
`~`, or `@`).

In an odd way, finding this interaction makes me feel good. I've been
concerned that the DST proposal seemed too easy, which meant we
weren't thinking hard enough about it. But there is another reason as
well: I have also been concerned that closure types were becoming a
bit too...  special, particularly with regard to
copyability. Basically I've been concerned that although the syntax
for a borrowed closure was `&fn`, borrowed closures didn't really
behave like `&` pointers---without the DST proposal, this was something
that we could safely enforce as part of the type system, but it's
still confusing for users. So I think the DST proposal forces us to be
more honest, and that's a good thing all around.

[dst]: /blog/2013/04/30/dynamically-sized-types/
[crc]: /blog/2013/04/30/the-case-of-the-recurring-closure/
[pjs]: /blog/categories/pjs
[epc]: https://www.usenix.org/conference/hotpar12/parallel-closures-new-twist-old-idea
[pc]: http://en.wikipedia.org/wiki/Parser_combinator
