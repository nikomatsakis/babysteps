---
layout: post
title: "Composing blocks"
date: 2011-12-29 21:19
comments: true
categories: [Rust, PL]
---

The original Rust design included iterators very similar to Python's
generators.  As I understand it, these were stripped out in favor of
Ruby-esque blocks, partially because nobody could agree on the best
way to implement iterators.  I like blocks, but it seems like it's
more natural to compose iterators, so I wanted to think a bit about
how one might use blocks to achieve similar things.  I'm sure this is
nothing new; there must be hundreds of libraries in Haskell that do
the same things I'm talking about here.

A very simple example of what I mean by iterator composition is
Python's `enumerate()` function, which converts an iterator over `T`
items into an iterator over `(uint, T)` pairs, where the `uint`
represents the index.  This handy little function allows any loop to
easily track the index, no matter what it is iterating over.  So I can
write:

    for (idx, elem) in enumerate(list): ...
    for (idx, elem) in enumerate(dict.keys()): ...
    for (idx, elem) in enumerate(dict.values()): ...
    for (idx, elem) in enumerate(anything at all): ...

This is very useful.  

Now, in Rust, we have a function `vec::iter()`, defined like so:

    fn iter<T>(v: [T], blk: block(T)) {
        uint::range(0, vec::len(v)) { |i|
            blk(v[i]);
        }
    }
    
Suppose that we wanted to write some kind of generic `enumerate()`
style function that would convert a function like `iter` into one
that provides indices.  I think the only way to do this in Rust is
to write something like:

    fn enumerate<S,T>(iter_fn: block(block(T)), blk: block(uint, T)) {
        let i = 0u;
        iter_fn() { |t|
            blk(i, t);
            i += 1u;
        }
    }
    
This would then be used like so:

    enumerate(bind vec::iter(v, _)) { |i, e| ... }
    enumerate(bind m.keys(_)) { |i, e| ... }
    enumerate(bind m.values(_)) { |i, e| ... }
    
Overall, this is not too bad.  A lighterweight curry syntax would make
it somewhat more pleasant, but I rather like `bind` as it is, so I
don't have any concrete suggestions.  Besides, after my foray into
expanding the possibilities of block sugar in expressions, I am done
with thinking about syntax for a little while!
