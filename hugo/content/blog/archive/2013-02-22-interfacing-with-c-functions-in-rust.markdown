---
categories:
- Rust
comments: true
date: "2013-02-22T00:00:00Z"
slug: interfacing-with-c-functions-in-rust
title: Interfacing with C functions in Rust
---

One of the things that I've been working on for some time now is the
proper integration of C functions.  As with virtually every other
facet of the design of Rust, we've been slowly moving from a model
where Rust tried to hide low-level details for you to one where Rust
offers tight control over what's going on, with the type system
intervening only as needed to prevent segfaults or other strange
behavior.  This blog post details what I consider to be the best
proposal so far; some of the finer points are a bit vague, however.

### Extern Function Types

One thing we need is a type for a simple function pointer.  Rust's
function types to date have always been closure types, meaning that
they referred to the combination of a function pointer and some
environment.  So we have added an "extern fn" type, which is written
as follows:

    extern "ABI" fn(T) -> U
    
Here the `"ABI"` string must be some ABI that is supported by the Rust
compiler.  The most common values will be either `C` or `Rust`, I
imagine, but `stdcall` (or `pascal`) may be used occasionally as well,
and who knows what we'll support in the future.

I imagine that the default for "ABI" should be "C", as it will be the
most common thing people really want to use. Calls to any extern
function with non-Rust ABI is an unsafe action.

### Extern Blocks and Function Declarations

We are moving towards a model where function declarations are placed 
within extern blocks.  This looks something like:

    extern "C" {
        fn foo();
        fn bar();
    }

In this case, the type of `foo` and `bar` would be `extern "C" fn()`.

The reason that we declare extern functions in extern blocks, as
opposed to individually, is that on some platforms it is necessary to
load blocks of functions that are defined by a common library
together.

### "crust" functions

In addition to being able to call C functions from within Rust, it is
useful to be able to call Rust functions from within C.  To this end
the compiler will permit Rust fns to be declared with a specific ABI
like so:

    extern "C" fn crust(t: T) -> U {
    }
    
If you declare a function as having a non-Rust ABI, then this implies
a few things:

- A reference to `crust()` will have type `extern "C" fn(T) -> U`.
- We cannot catch and process failure for you, since the propagation
  of failure results is ABI specific.  Thus is the Rust code within an
  external function fails, it will cause the process to abort.  We may
  later add some way to catch failure so that you can propagate it
  yourself (perhaps by returning false, etc).

### Stack Switching

Now we come to the interesting (and tricky) part.  Internally, Rust
makes use of a split stack approach where stack segments are allocated
dynamically as the stack grows.  This allows us to have a very large
number of threads without exhausting our address space (particularly
on 32-bit systems).  This also allows your programs to recurse as long
as there is memory available, which is sometimes useful.  It is not,
however, what C expects.  C functions just expect to have a big chunk
of stack available.  Hopefully infinite.

Therefore, whenever we recurse into C code, we must make sure that a
lot of stack is available.  The way we do this today is somewhat
magical: functions declared as extern are not in fact the raw C
function, but rather a wrapper around the C function that will switch
over from the Rust stack (which may be small) to a very big stack.
This was more-or-less an ok solution back before we had the idea of
getting a raw pointer to a C function and so forth but it's not very
appealing now.  Also it can be a performance bottleneck.

The new proposal is to say that when you call an `extern "C"` fn,
nothing magical happens.  The stack stays just as it was.  To perform
the stack switching, we offer a function in the runtime (perhaps a
number of functions) called `prepare_extern_call()`, which can be
used like so:

    let my_c_function: extern "C" fn() = ...;
    do prepare_extern_call {
        my_c_function()
    }

Of course, it would be easy to forget to use this function, which
would be a recipe for stackfaults.  Therefore, we will also offer a
lint-mode check that defaults to error.  This check will trigger if we
see a call to a function of non-Rust ABI that is not lexically
enclosing within a call to `prepare_extern_call`.

There will be variants of `prepare_extern_call` that allow you to
specify the amount of stack size to guarantee more precisely if you
prefer, along with other options as those arise.

### Auto-generating wrappers

It is our expectation that most people will not directly call C
functions.  Instead, you will wrap them in a Rust-friendly wrapper
that performs some sanity checking, converts from Rust types, etc.
This wrapper will also perform the stack switching shown above.

In some cases, though, writing such wrappers can be tedious, so we can
supply some annotations in the compiler that will autogenerate these
wrappers.  This is basically a macro.  I am envisioning something like
this:

    #[auto_wrap] // autogenerate wrappers for enclosing functions
    extern "C" {
        #[no_wrap] // ...not this one, I'll do it by hand
        fn my_func1(x: *char) -> bool;
        
        fn my_func2();
    }
    
    fn my_func1(x: ~str) -> bool {
        do x.as_c_string |p| {
            do prepare_extern_call {
            }
        }
    }
 
which would then expand into:

    extern "C" {
        fn my_func1(x: *char) -> bool;
        fn my_func2();
    }
    
    fn my_func2() -> bool {
       do prepare_extern_call {
           my_func2()
       }
    }

One issue that is obvious here is the name collisions.  I'm not sure
how to resolve that.  It seems like the older way of native functions
within their own module (`extern "C" mod foo`) would solve it.  Well,
we'll do something.  And the precise details of this auto-generation
remain to be resolved.  But you get the idea.
