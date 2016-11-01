---
layout: post
title: "Breaking out is hard to do"
date: 2012-02-02 11:23
comments: true
categories: [Rust]
---

One of the things I'd like to do for the iteration library is settle
on a convention for breaking and continuing within loops.  There is a
bug on this issue ([#1619][1619]) and it seems like the general
approach is clear but some of the particulars are less so.  So I
thought I'd try to enumerate how code will look under the various
alternatives and then maybe we can settle on one: they're all fairly
similar.  Who knows, maybe just writing things out will settle my
mind.

### Alternative #1: The `loop_ctl` type.

This was my original proposal.  Basically, there will be a type
called `iter::loop_ctl` defined as so:

    enum loop_ctl { lc_break, lc_cont }

I wanted to design something that felt as much like normal loops as
possible.  So my thought was that, for sugared closures where the
return type was `loop_ctl`, the compiler could insert `lc_cont` as the
tail expression should there not be one already.

The idea then was to change `vec::iter()` from a function with the signature:

    fn iter<T>(v: [T], f: fn(T))
    
to the following:    

    fn iter<T>(v: [T], f: fn(T) -> loop_ctl)

In other words, the function supplied to `iter` would be allowed to
break the loop in the middle if it wanted to.  Due to the default
rules, this is mostly invisible, except that you can say `break` and
`cont` and things work as you expect.

Unfortunately, as I think more about it, I realize that the default
rules aren't quite subtle enough.  It's only *mostly* invisible.  For example:

    vec::iter(v) {
        while cond { }
    }
    
This would fail because while loops have a result type of `()`, and in
this case the `while` loop occupies the tail expression slot.  So you would
have to write:

    vec::iter(v) {
        while cond { }
        cont;
    }
    
This makes me unhappy.  I'm happy with smart rules but only if they
really work all the time or have a consistent story.  You could extend
the rule to say "if the tail expression has unit type, still insert a
default `cont`", but now it's starting to sound really magical.

### Alternative #2: 

We can keep the `loop_ctl` type but just not make it special.  Iterable
types define two methods, `iter` and `iter_brk` (not sure about those names),
with signatures as shown (these are for vectors:

    iface iterable<T> {
        fn iter(f: fn(T)) /* as today */
        fn iter_brk(f: fn(T) -> loop_ctl)
    }
    
Now when you want to break, you have to end the loop explicitly with `cont`.

For most types, you need only define `iter_brk`: the `iter` function
itself can be defined generically as shown (this assumes traits are
implemented):

    trait base_iter<T> {
        req fn iter_brk(f: fn(T) -> loop_ctl);
        
        fn iter(f: fn(A)) {
            self.iter_brk {|e|
                f(e);
                cont; 
            }
        }
    }
    
### Alternative #3:

Same as #2, but we replace the `loop_ctl` type with boolean.  This is
appealing because it's so minimalistic.  `break` would effectively
return `false` and `cont` would return `true`.  This makes `iter_brk`
effectively the same as the predicate test `all()`, which returns true
if the block returns true for all members.

Of course, if we actually *used* `all()` instead of `iter_brk` that'd be
ok too, except that the return type of all is `bool`, so a semicolon would
be required:

    v.all {|i|
        ...
    };

We could of course have both `all` and `iter_brk` (as we would in
alternative #2).

### My preference?

I started out liking alternative #1, but writing this blog post has
more-or-less persuaded me that I prefer alternative #2.  Less compiler
magic is good, and compiler magic that fails is bad.  Between
alternatives #2 and #3, I tend to slightly prefer an explicit
`loop_ctl` type over a boolean for a couple of reasons:

- the types more closely reflect the intention.  To me, testing
  whether a predicate holds on all members is not the same as
  interrupting a loop early.
- you can't use `break` and `cont` to return out of arbitrary blocks
  that happen to return boolean.
- you can always write helpers like

      fn break_if(b: bool) -> loop_ctl { if b { lc_break } else { lc_cont } }
      fn cont_if(b: bool) -> loop_ctl { break_if(!b) }
      
  to convert between `bool` and `loop_ctl` when convenient.
  
But obviously there is no substantive difference between alternatives
#2 and #3.
  
[1619]: https://github.com/mozilla/rust/issues/1619
