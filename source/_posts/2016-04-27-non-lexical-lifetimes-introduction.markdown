---
layout: post
title: "Non-lexical lifetimes: introduction"
date: 2016-04-27 07:52:05 -0700
comments: true
categories: [Rust, NLL]
---

Over the last few weeks, I've been devoting my free time to fleshing
out the theory behind **non-lexical lifetimes** (NLL). I think I've
arrived at a pretty good point and I plan to write various posts
talking about it. Before getting into the details, though, I wanted to
start out with a post that lays out roughly how today's *lexical
lifetimes* work and gives several examples of problem cases that we
would like to solve.

<!-- more -->

The basic idea of the borrow checker is that values may not be mutated
or moved while they are borrowed. But how do we know whether a value
is borrowed? The idea is quite simple: whenever you create a borrow,
the compiler assigns the resulting reference a **lifetime**. This
lifetime corresponds to the span of the code where the reference may
be used. The compiler will infer this lifetime to be the smallest
lifetime that it can that still encompasses all the uses of the
reference.

Note that Rust uses the term lifetime in a very particular way.  In
everyday speech, the word lifetime can be used in two distinct -- but
similar -- ways:

1. The lifetime of a **reference**, corresponding to the span of time in
   which that reference is **used**.
2. The lifetime of a **value**, corresponding to the span of time
   before that value gets **freed** (or, put another way, before the
   destructor for the value runs).

This second span of time, which describes how long a value is valid,
is of course very important. We refer to that span of time as the
value's **scope**. Naturally, lifetimes and scopes are linked to one
another. Specifically, if you make a reference to a value, the
lifetime of that reference cannot outlive the scope of that value,
Otherwise your reference would be pointing into free memory.

To better see the distinction between lifetime and scope, let's
consider a simple example. In this example, the vector `data` is
borrowed (mutably) and the resulting reference is passed to a function
`capitalize`. Since `capitalize` does not return the reference back,
the *lifetime* of this borrow will be confined to just that call. The
*scope* of data, in contrast, is much larger, and corresponds to a
suffix of the fn body, stretching from the `let` until the end of the
enclosing scope.

```rust
fn foo() {
    let mut data = vec!['a', 'b', 'c']; // --+ 'scope
    capitalize(&mut data[..]);          //   |
//  ^~~~~~~~~~~~~~~~~~~~~~~~~ 'lifetime //   |
    data.push('d');                     //   |
    data.push('e');                     //   |
    data.push('f');                     //   |
} // <---------------------------------------+

fn capitalize(data: &mut [char]) {
    // do something
}
```

This example also demonstrates something else. Lifetimes in Rust today
are quite a bit more flexible than scopes (if not as flexible as we
might like, hence this RFC):

- A scope generally corresponds to some block (or, more specifically,
  a *suffix* of a block that stretches from the `let` until the end of
  the enclosing block) \[[1](#temporaries)\].
- A lifetime, in contrast, can also span an individual expression, as
  this example demonstrates. The lifetime of the borrow in the example
  is confined to just the call to `capitalize`, and doesn't extend
  into the rest of the block. This is why the calls to `data.push`
  that come below are legal.

So long as a reference is only used within one statement, today's
lifetimes are typically adequate. Problems arise however when you have
a reference that spans multiple statements. In that case, the compiler
requires the lifetime to be the innermost expression (which is often a
block) that encloses both statements, and that is typically much
bigger than is really necessary or desired. Let's look at some example
problem cases. Later on, we'll see how non-lexical lifetimes fixes
these cases.

#### Problem case #1: references assigned into a variable

One common problem case is when a reference is assigned into a
variable. Consider this trivial variation of the previous example,
where the `&mut data[..]` slice is not passed directly to
`capitalize`, but is instead stored into a local variable:

```rust
fn bar() {
    let mut data = vec!['a', 'b', 'c'];
    let slice = &mut data[..]; // <-+ 'lifetime
    capitalize(slice);         //   |
    data.push('d'); // ERROR!  //   |
    data.push('e'); // ERROR!  //   |
    data.push('f'); // ERROR!  //   |
} // <------------------------------+
```

The way that the compiler currently works, assigning a reference into
a variable means that its lifetime must be as large as the entire
scope of that variable. In this case, that means the lifetime is now
extended all the way until the end of the block. This in turn means
that the calls to `data.push` are now in error, because they occur
during the lifetime of `slice`. It's logical, but it's annoying.

In this particular case, you could resolve the problem by putting
`slice` into its own block:

```rust
fn bar() {
    let mut data = vec!['a', 'b', 'c'];
    {
        let slice = &mut data[..]; // <-+ 'lifetime
        capitalize(slice);         //   |
    } // <------------------------------+
    data.push('d'); // OK
    data.push('e'); // OK
    data.push('f'); // OK
}
```

Since we introduced a new block, the scope of `slice` is now smaller,
and hence the resulting lifetime is smaller. Of course, introducing a
block like this is kind of artificial and also not an entirely obvious
solution.

#### Problem case #2: conditional control flow

Another common problem case is when references are used in only match
arm. This most commonly arises around maps. Consider this function,
which, given some `key`, processes the value found in `map[key]` if it
exists, or else inserts a default value:

```rust
fn process_or_default<K,V:Default>(map: &mut HashMap<K,V>,
                                   key: K) {
    match map.get_mut(&key) { // -------------+ 'lifetime
        Some(value) => process(value),     // |
        None => {                          // |
            map.insert(key, V::default()); // |
            //  ^~~~~~ ERROR.              // |
        }                                  // |
    } // <------------------------------------+
}
```

This code will not compile today. The reason is that the `map` is
borrowed as part of the call to `get_mut`, and that borrow must
encompass not only the call to `get_mut`, but also the `Some` branch
of the match. The innermost expression that encloses both of these
expressions is the match itself (as depicted above), and hence the
borrow is considered to extend until the end of the
match. Unfortunately, the match encloses not only the `Some` branch,
but also the `None` branch, and hence when we go to insert into the
map in the `None` branch, we get an error that the `map` is still
borrowed.

This *particular* example is relatively easy to workaround. One can
(frequently) move the code for `None` out from the `match` like so:

```rust
fn process_or_default1<K,V:Default>(map: &mut HashMap<K,V>,
                                    key: K) {
    match map.get_mut(&key) { // -------------+ 'lifetime
        Some(value) => {                   // |
            process(value);                // |
            return;                        // |
        }                                  // |
        None => {                          // |
        }                                  // |
    } // <------------------------------------+
    map.insert(key, V::default());
}
```

When the code is adjusted this way, the call to `map.insert` is not
part of the match, and hence it is not part of the borrow.  While this
works, it is of course unfortunate to require these sorts of
manipulations, just as it was when we introduced an artificial block
in the previous example.

#### Problem case #3: conditional control flow across functions

While we were able to work around problem case #2 in a relatively
simple, if irritating, fashion. there are other variations of
conditional control flow that cannot be so easily resolved. This is
particularly true when you are returning a reference out of a
function. Consider the following function, which returns the value for
a key if it exists, and inserts a new value otherwise (for the
purposes of this section, assume that the `entry` API for maps does
not exist):

```rust
fn get_default<'m,K,V:Default>(map: &'m mut HashMap<K,V>,
                               key: K)
                               -> &'m mut V {
    match map.get_mut(&key) { // -------------+ 'm
        Some(value) => value,              // |
        None => {                          // |
            map.insert(key, V::default()); // |
            //  ^~~~~~ ERROR               // |
            map.get_mut(&key).unwrap()     // |
        }                                  // |
    }                                      // |
}                                          // v
```

At first glance, this code appears quite similar the code we saw
before. And indeed, just as before, it will not compile. But in fact
the lifetimes at play are quite different. The reason is that, in the
`Some` branch, the value is being **returned out** to the caller.
Since `value` is a reference into the map, this implies that the `map`
will remain borrowed **until some point in the caller** (the point
`'m`, to be exact). To get a better intuition for what this lifetime
parameter `'m` represents, consider some hypothetical caller of
`get_default`: the lifetime `'m` then represents the span of code in
which that caller will use the resulting reference:

```rust
fn caller() {
    let mut map = HashMap::new();
    ...
    {
        let v = get_default(&mut map, key); // -+ 'm
          // +-- get_default() -----------+ //  |
          // | match map.get_mut(&key) {  | //  |
          // |   Some(value) => value,    | //  |
          // |   None => {                | //  |
          // |     ..                     | //  |
          // |   }                        | //  |
          // +----------------------------+ //  |
        process(v);                         //  |
    } // <--------------------------------------+
    ...
}
```

If we attempt the same workaround for this case that we tried
in the previous example, we will find that it does not work:

```rust
fn get_default1<'m,K,V:Default>(map: &'m mut HashMap<K,V>,
                                key: K)
                                -> &'m mut V {
    match map.get_mut(&key) { // -------------+ 'm
        Some(value) => return value,       // |
        None => { }                        // |
    }                                      // |
    map.insert(key, V::default());         // |
    //  ^~~~~~ ERROR (still)                  |
    map.get_mut(&key).unwrap()             // |
}                                          // v
```

Whereas before the lifetime of `value` was confined to the match, this
new lifetime extends out into the caller, and therefore the borrow
does not end just because we exited the match. Hence it is still in
scope when we attempt to call `insert` after the match.

The workaround for this problem is a bit more involved. It relies on
the fact that the borrow checker uses the precise control-flow of the
function to determine what borrows are in scope.

```rust
fn get_default2<'m,K,V:Default>(map: &'m mut HashMap<K,V>,
                                key: K)
                                -> &'m mut V {
    if map.contains(&key) {
    // ^~~~~~~~~~~~~~~~~~ 'n
        return match map.get_mut(&key) { // + 'm
            Some(value) => value,        // |
            None => unreachable!()       // |
        };                               // v
    }

    // At this point, `map.get_mut` was never
    // called! (As opposed to having been called,
    // but its result no longer being in use.)
    map.insert(key, V::default()); // OK now.
    map.get_mut(&key).unwrap()
}
```

What has changed here is that we moved the call to `map.get_mut`
inside of an `if`, and we have set things up so that the if body
unconditionally returns. What this means is that a borrow begins at
the point of `get_mut`, and that borrow lasts until the point `'m` in
the caller, but the borrow checker can see that this borrow *will not
have even started* outside of the `if`. So it does not consider the
borrow in scope at the point where we call `map.insert`.

This workaround is more troublesome than the others, because the
resulting code is actually less efficient at runtime, since it must do
multiple lookups.

It's worth noting that Rust's hashmaps include an `entry` API that
one could use to implement this function today. The resulting code is
both nicer to read and more efficient even than the original version,
since it avoids extra lookups on the "not present" path as well:

```rust
fn get_default3<'m,K,V:Default>(map: &'m mut HashMap<K,V>,
                                key: K)
                                -> &'m mut V {
    map.entry(key)
       .or_insert_with(|| V::default())
}
```

Regardless, the problem exists for other data structures besides
`HashMap`, so it would be nice if the original code passed the borrow
checker, even if in practice using the `entry` API would be
preferable. (Interestingly, the limitation of the borrow checker here
was one of the motivations for developing the `entry` API in the first
place!)

### Conclusion

This post looked at various examples of Rust code that do not compile
today, and showed how they can be fixed using today's system. While
it's good that workarounds exist, it'd be better if the code just
compiled as is. In an upcoming post, I will outline my plan for how to
modify the compiler to achieve just that.

## Endnotes

<a name="temporaries"></a>

**1.** Scopes always correspond to blocks with one exception: the
scope of a temporary value is sometimes the enclosing
statement.

