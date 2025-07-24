---
layout: post
title: "Why not modes?"
date: 2011-12-08T19:54:00Z
comments: true
categories: [Rust,PL]
---

[Marijn][marijn] asked me what it is that I dislike about parameter
modes.  I thought I might as well explain here.  

For background, today in Rust a function can declare each parameter in
one of several modes:

- By value (`++`): No pointer is used but the value is not owned by the
  callee.  Therefore, the callee does not need to free it, for example, or
  decrement a ref count.
- By immutable reference (`&&`): a pointer to the variable in the caller's
  stack frame is passed, but the callee cannot use it to make changes.
  Can be passed an lvalue or an rvalue.
- By mutable reference (`&`): a pointer to the variable in the caller's
  stack frame is passed, and the callee can use it to reassign the variable.
  Can only be passed an lvalue.
- By copy (`+`): A fresh copy of the value is created and the callee must
  dispose of it.
- By move (`-`): The value is moved from the caller's stack frame and the
  callee must dispose of it.
  
So what don't I like about modes?

#### Modes are invisible for the caller

The caller of a function cannot tell whether the parameter that is being
passed is being passed by reference or by value.  For example, quick, what
does this function (from `linux_os.rs`) return:

    fn waitpid(pid: pid_t) -> i32 {
        let status = 0i32;
        os::libc::waitpid(pid, status, 0i32);
        ret status;
    }

When I first read it, I thought it must always return `0`.  But in
fact the function `os::libc::waitpid()` is defined with its second
parameter as a mutable reference, and so it can modify the value of
status.

I much prefer the C convention of passing a pointer.  In that case,
the function above would be written:

    fn waitpid(pid: pid_t) -> i32 {
        let status = 0i32;
        os::libc::waitpid(pid, &status, 0i32);
        ret status;
    }
    
Now it is clear that `status` might be modified by `waitpid()`.    

#### Copy and move modes divide responsibility in a strange way

Both the copy and move modes specify that the callee is responsible
for disposing of the argument.  It makes good sense for the callee to
declare that it will free the value provided as an argument.  However,
I do not understand why it is any of the callee's business, however,
whether the caller chose to provide the value by copying or moving it.
This seems like a decision the caller is better suited to make.

#### Modes do not compose

Finally, having extra information about how the parameter is passed
that is not part of the type makes it impossible to write generic
functions that operate over functions with any argument.  Consider a
generic function timer:

    fn timer<A>(f: fn(A), arg: A) {
        let t_start = get_current_time();
        f(arg);
        let t_stop = get_current_time();
        log (t_stop - t_start);
    }
    
Seems simple enough.  Now, you might ask, what if I wanted to use
`timer()` with a function that takes two arguments, like `foo()`:

    type T = {...}; // some record type
    fn foo(&t1: T, &t2: T) { ... }
    
This won't work, because `timer()` expects a function of only one
argument.  But wait, with generic types we could write a little
wrapper:
    
    fn wrap2<A,B>(f: fn(A,B)) -> fn((A,B)) {
        ret lambda (pair: (A,B)) {
            let (a, b) = pair;
            f(a, b);
        };
    }

And now we can replace a call like `foo(v1, v2)` with
`timer(wrap2(foo), (v1, v2))`, right? Well, that's true, but the
behavior is slightly different. In the original, `t1` was passed
pointers to `v1` and `v2`, whereas now it is being passed pointers to
the `a` and `b` temporaries.  Not only that, but copies of `v1` and
`v1` are occurring!

If we had used something like regions, then `foo()` would be defined:

    fn foo(t1: &T, t2: &T) { ... }

and we could replace the call `foo(&v1, &v2)` with `timer(wrap2(foo),
(&v1, &v2))` with no change in the semantics.

[marijn]: http://marijnhaverbeke.nl/

#### So what could we do instead?

I'd rather see modes move into types.  For example, by-reference (both
mutable and immutable) can become pointer types, as in C.  By value is
basically unnecessary.  To handle move and copy mode, you say that
types like `~T` or resources are always owned by the callee, then let
the caller decide whether to move its value or copy it.
