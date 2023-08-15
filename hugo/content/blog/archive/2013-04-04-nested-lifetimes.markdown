---
categories:
- Rust
comments: true
date: "2013-04-04T00:00:00Z"
slug: nested-lifetimes
title: Nested lifetimes
---

While working on [issue #5656][5656] I encountered an interesting
problem that I had not anticipated.  The result is a neat little
extension to the region type system that increases its expressive
power.  The change is completely internal to the type rules and
involves no user-visible syntax or anything like that, though there
are some (basically nonsensical) programs that will no longer compile.
Anyway I found it interesting and thought I would share.

<!--more-->

### Background: Issue #5656 and the case of the many cursors

To explain the problem I encountered, consider this running example
(written as one would write it after my patch):

    struct OwnedCursor<T> {
        buffer: ~[T],
        position: uint
    }
    
    pub impl<T> OwnedCursor<T> {
        fn get<'c>(&'c self) -> &'c T {
            &self.buffer[self.position]
        }
        
        fn move(&mut self, by: int) -> bool {
            if (by > 0) {
                self.position += by as uint;
            } else {
                self.position -= by as uint;
            }
            self.position < self.buffer.len()
        }
    }
    
This defines a type `OwnedCursor` that owns a vector and a position within
that buffer.  The type offers two methods, `get()` and `move()`.  The
method definitions themselves should be fairly
self-explanatory. `get()` returns a pointer to the current item and
`move()` modifies the current position.

What is interesting is the lifetimes on the function `get()`. The
signature indicates that it takes a borrowed pointer to an
`OwnedCursor` with lifetime `'c` and returns a pointer with that same
lifetime.  In other words, the `&'c self` declaration means that the
method `get()` is roughly equivalent to a function written as follows:

    fn get<'self, T>(self: &'c OwnedCursor<T>) -> &'c T {
        &self.buffer[self.position]
    }

The reason that we can say that the returned value has the same
lifetime as the input is that (1) we know that the pointer `self` will
be valid for the entirety of the lifetime `'c` and (2) `self` is an
immutable pointer, so the field `buffer` will not be mutated.  So we
can say that, for the lifetime `'c`, the `OwnedCursor` object will not
be freed and it is immutable, therefore we can take a pointer into
`self.buffer` and know that this memory is also valid.

Now let's suppose that we wanted to develop many kinds of cursors.
We might introduce a generic trait and convert the impl to use it:

    trait Cursor<T> {
        fn get<'c>(&'c self) -> &'c T;
        fn move(&mut self, by: int) -> bool;
    }
    
    impl<T> Cursor<T> for OwnedCursor<T> {
        // as before
    }
    
Now we can introduce a second kind of cursor, one that doesn't *own*
the vector that it iterates over:

    struct BorrowedCursor<'b, T> {
        buffer: &'b [T],
        position: uint
    }
    
    impl<'b, T> Cursor<T> for BorrowedCursor<'b, T> {
        fn get<'c>(&'c self) -> &'c T {
            &self.buffer[self.position]
        }
        
        fn move(&mut self, by: int) -> bool {...}
    }
    
This definition is very similar, except that the type and impl are
parameterized by a lifetime `'b`, representing the lifetime of the
*b*uffer.  Everything seems fine, but when I tried running this
example through the compiler with my patch, I encountered a type error
on the `get()` routine.  The compiler reported that the lifetime of
`&self.buffer[self.position]` was not `'c` but rather `'b`---the
lifetime of the buffer, and so the return type of the function was
invalid.

Unfortunately, the compiler is quite correct!  The function signature
states that we return a pointer with the lifetime `'c`, but here `'c`
is the lifetime of the *cursor*.  Our pointer is a pointer into the
*buffer*, so it will have the lifetime `'b`.

In the original `OwnedCursor` type, the buffer was owned by the
cursor, so the result had identical lifetimes.  But in the case of
`BorrowedCursor`, the lifetime of the buffer is not tied to the cursor
object, which after all is only borrowing the buffer.

Of course, it's kind of nonsensical to have a cursor that outlives the
buffer it's working with.  But there is in fact nothing in the type
system that would prevent you from doing that---it's just that once
your buffer became invalid you would be prevented from actually
*using* the cursor anymore.

### The solution

This problem was quite vexing at first.  The example I just gave is
perfectly reasonable and it really should work (and, in fact, the old
system I am attempting to replace allowed it, though in a kind of
roundabout and possibly unsound way).  The solution I decided on was
just to formalize the common sense rule that a pointer should not have
a longer lifetime than any other pointers it points at.  In other words,
if I create a pointer to a `BorrowedCursor<'b, T>`, my pointer cannot
have a lifetime that exceeds the lifetime `'b` of the buffer.

If we assume this rule holds, then when you have a function that takes
an argument of type `&'c BorrowedCursor<'b, T>` (such as the `self`
argument to `get()`), the compiler can deduce that `'c` must be a
smaller lifetime than `'b`, because otherwise the caller would have
encountered a type error.  This means that the `get()` method for
`BorrowedCursor<'b, T>` is permitted to return a pointer with lifetime
`'c`---the largest possible lifetime is still `'b`, but `'c` is a
sound approximation (it can only be shorter than `'b`, after all).

I wonder if this problem arises in other similar type systems. I
remember Safe Java had a rule that the "main owner" of an object must
own all the other owners, or something like that, but I think this was
a soundness concern having to do with downcasting. I'll have to go and
re-read the various papers. Anyway, I've been debating whether to
allow types like `&'a &'b uint` where `'a` outlives `'b` for a while.
They would seem to have no practical use but I couldn't think of a
reason to add extra rules to prohibit them...  until now, anyway.

[5656]: https://github.com/mozilla/rust/issues/5656
