OK, after writing the
[post on iterators that yield mutable references][pp], and discussing
with some folk on IRC, I remembered something I had forgotten. There
is actually a way to phrase the mutable vector iterator differently
such that it is...almost safe. The end result still has some unsafe
code, but it is much narrower in scope, and it's also quite plausible
to imagine that code becoming safe eventually. Even better, the
approach generalizes to other data structures.

### Rephrasing the mutable vector iterator

Here is another implementation of an iterator over mutable references.
It works differently than the previous one. Rather than tracking an
index into a slice, it works by keeping an ever-shrinking slice.  Each
time we invoke `next()`, the slice `self.data` is rewritten to exclude
the value that was just returned.

    struct VecMutIterator<'v, T> {
        data: &'v mut [T],
    }
    
    impl<'v, T> Iterator<&'v mut T> for VecMutIterator<'v, T> {
        fn next<'n>(&'n mut self) -> Option<&'v mut T> {
            pop_mut_ref(&mut self.data)
        }
    }

    fn pop_mut_ref<'v, T>(data: &mut &'v mut [T]) -> &'v mut T {
        // Get a pointer to the 0th element. Borrow checker
        // would limit the lifetime of this pointer to the current
        // fn body, for the reasons discussed in my previous post,
        // but we can cheat and extend it further.
        //
        // This temporarily creates an unsafe situation, since there
        // are two paths to the same data: `result` and `(*data)[0]`
        let result = unsafe {
            unsafe::copy_mut_lifetime(*data, &mut (*data)[0])
        };
        
        // Now adjust `*data` in place so that it no longer includes
        // the 0th element. Now there is no more overlap.
        *data = data.slice(1, data.len());
        
        result
    }
    
As you can see, you do still require an `unsafe` keyword to implement
the iterator. However, the scope of the unsafety is much more limited:
the invariant that there be only one mut pointer to a given piece of
memory is restore when `next()` returns, and hence we do not need to
concern ourselves with privacy. This is the kind of unsafe fn I prefer.

What's somewhat amusing is that this "mutate in place" approach is
precisely what the actual vector iterators do -- but they do it using
raw, unsafe pointers. This is primarily for performance. But it's nice
to see that there is a safe -- or almost, almost safe -- equivalent in
plain old Rust.

### Extending the approach

What's kind of funny is that I thought of this approach a while back
[when we were initially discussing iterators][iter]. In that context,
I was looking for a safe way to implement iterators on trees. The post
includes a code example, but it is in terms of a `MutIterator` trait,
so I wanted to generalize it here.

First, imagine a simple binary tree:

    struct BinaryTree<T> {
        value: T,
        left: Option<~BinaryTree<T>>,
        right: Option<~BinaryTree<T>>,
    }
    
Now, we wish to implement a preorder iterator for this
binary tree type, yielding mutable references. The iterator
will look like:

    struct MutTreeIterator<'tree,T> {
        stack: ~[&'tree mut BinaryTree<T>],
    }
    
    impl<'tree,T> Iterator<&'tree mut T> for MutTreeIterator<'tree,T> {
        fn next<'a>(&'a mut self) -> Option<&'a mut T> {
            if self.stack.is_empty() {
                return None;
            }

            // Pop the top-most node from the stack and break it into
            // its three component fields:
            let current = self.stack.pop();
            let BinaryTree { value: ref mut value,
                             left: ref mut left,
                             right: ref mut right } = *current;

            // Push any children back onto the stack.
            match right {
                None => {}
                Some(~ref mut r) => {
                    self.stack.push(r);
                }
            }
            match left {
                None => {}
                Some(~ref mut l) => {
                    self.stack.push(l);
                }
            }

            // Return value from the top-most stack.
            Some(value)
        }
    }

We need to maintain the the invariant that there is never more than
one pointer to the same data. The way we do this is that each time we
pop a node off the stack, we immediately decompose it into three
distinct pointers (`value`, `left`, and `right`), none of which
overlap. Now we can push `left` and `right` back onto the stack for
the future and return `value`. So the code operates on the same
principle as the iterator from the first section: destructively mutate
the iterator in place so that *it no longer contains a way to reach
the value you just returned*.

This is a pre-order iterator. With a little bit of effort, it should
be possible to adapt the approach to do a (safe) post-order iterator,
but I leave that as an exercise to the reader.

*Side note:* It is not necessary to use the pattern matching let
assignment to break apart the current node into its three fields.  You
could rewrite the code above and replace references to `left` with
`current.left`, `right` with `current.right`, and so on. The borrow
checker is smart enough to handle paths like this as long as they are
contained within a single function. However, I thought the code read
more clearly if we did the decomposition into three parts in one
atomic step.

### Conclusions

With respect to the question I posed in [my previous post][pp], this
pushes me squarely into the "keep iterators the way they are" camp.

[pp]: http://smallcultfollowing.com/babysteps/blog/2013/10/24/iterators-yielding-mutable-references/
[iter]: https://mail.mozilla.org/pipermail/rust-dev/2013-June/004428.html
