---
categories:
- Rust
comments: true
date: "2013-01-16T00:00:00Z"
slug: revised-for-loop-protocol
title: Revised for loop protocol
---

In Rust today, there is a
[special `for` syntax designed to support interruptible loops][for].
Since we introduced it, this has proven to be a remarkable success.
However, I think we can improve it very slightly.

### Current for protocol

The current "for protocol" is best explained by giving an example of
how to implement it for slices:

    fn each<E>(v: &[E], f: &fn(&E) -> bool) {
        let mut i = 0;
        let n = v.len();
        while i < n {
            if !f(&v[i]) {
                return;
            }
            i += 1
        }
    }

As you can see, the idea is that the last parameter to the `each()`
method is a function of type `&fn(&E) -> bool`, which means that it is
given a pointer to an element in the collection and it returns true or
false.  The return value indicates whether we should continue
iterating.

A little known fact is that the `for` statement returns whatever the
`each()` method returns.  This means that `each()` methods typically
have unit return type so that the Rust compiler doesn't require a
semicolon, which would be used to disregard the result of the `for`
expression.

### Problems

The biggest problem with this protocol is that it is not easily
composable.  In particular, imagine that I have a simple tree like
this:

    struct Tree<E> {
        elem: E,
        children: ~[Tree<E>]
    }
    
Now let's try to implement the pre-order traversal method for such a
tree.  You might think you could do it like this:

    fn each<E>(t: &Tree<E>, f: &fn(&E) -> bool) {
        if !f(&t.elem) {
            return;
        }
        
        for t.children.each |child| { each(child, f); }
    }
    
While this will compile, it will not work as expected. For example, this
program:

    fn main() {
        let t = Tree {
            elem: 0,
            children: ~[
                Tree { elem: 1, children: ~[
                    Tree { elem: 2, children: ~[] }
                ] },
                Tree { elem: 3, children: ~[] }
            ]
        };
    
        for each(&t) |e| {
            io::println(fmt!("%d", *e));
            if *e == 1 { break; }
        }
    }
    
should print "0" and "1", but it prints "0", "1", and "3".  The reason
is that while `each()` does indeed return early when the iteration
function returns false, it doesn't abort the entire iteration, only
the current subtree.

One way to fix this is to wrap the `each()` function with an inner
each function that returns a bool to indicate whether execution should
stop:

    fn each1<E>(t: &Tree<E>, f: &fn(&E) -> bool) {
        each_inner(t, f);
    
        fn each_inner<E>(t: &Tree<E>, f: &fn(&E) -> bool) -> bool {
            if !f(&t.elem) {
                return false;
            }
    
            for t.children.each |child| {
                if !each_inner(child, f) {
                    return false;
                }
            }
    
            return true;
        }
    }

### Making `each()` composable

I think that we should change the standard `each` signature to:

    fn each<E>(c: &Coll<E>, f: &fn(&E) -> bool) -> bool
   
Here the return value of `each` is always a boolean, and it will be false
if the last call to `f()` returned false, and true otherwise.  This
makes it easier to write composed `each()` methods.  We would also
adjust `for` statements so that they always return unit and do not
return the result of `each()`.

Under this definition, we could write the tree iterator as follows:

    fn each2<E>(t: &Tree<E>, f: &fn(&E) -> bool) -> bool {
        f(&t.elem) && t.children.each(|c| each2(c, f))
    }

This is clearly an improvement over `each1()`!
    
[for]: http://brson.github.com/rust/2012/04/05/new-for-loops/
