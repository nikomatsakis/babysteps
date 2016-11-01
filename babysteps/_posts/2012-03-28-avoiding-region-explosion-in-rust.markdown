---
layout: post
title: "Avoiding region explosion in Rust"
date: 2012-03-28 06:18
comments: true
categories: [Rust, PL]
---

pcwalton and I (but mostly pcwalton) have been hard at work
implementing regions in Rust.  We are hoping to use regions to avoid a
lot of memory allocation overhead in the compiler---the idea is to use
memory pools (a.k.a. arenas) so that we can cheaply allocate the data
needed to process a given function and then release it all in one
shot.  It is well known that arenas are great fit for the memory
allocation patterns of a compiler, which tend to produce a lot of data
that lives for the duration of a pass but is not needed afterwards.

In any case, recently we had a discussion about how we can use
regions in the `trans` pass of the compiler: this is the pass which
converts from our internal representation (IR) to the LLVM's IR.  I
thought it was worth sharing the result of this discussion.  The basic
summary is that we are able to make use of region subtyping to
accommodate a fairly complex pattern of lifetimes with very little
annotation overhead.

### The setting: contexts in trans

First, let me introduce the problem: during translation, we produce a
lot "contexts", which store needed data about the state of the
translation.  For our purposes, there are three contexts of note: the
*crate context*, or `ccx`, which stores crate-wide data such as
linkage information about top-level functions, constants, and so
forth; the *function context*, or `fcx`, which stores per-function
data such as references to the LLVM variables representing its
parameters and locals; and finally the *block context*, or `bcx`,
which stores information about a single basic block in the
[control-flow graph][cfg].

[cfg]: http://en.wikipedia.org/wiki/Control_flow_graph

What we would like to do is to create the crate context `ccx` on the
stack when we enter the translation phase for the crate as a whole.
Later, when we begin to translate a given function, we will allocate
its function context `fcx` on the stack as well.  The block contexts,
however, are a little different: they do not fully obey a stack
discipline.  That is, it is common for a function to create a new
block context and return it to its caller, perhaps with a signature
like the following:

    fn compile_if_then_else(bcx0: @block_ctxt,
                            cond: @expr,
                            then_blk: @code_block,
                            else_blk: @code_block) -> @block_ctxt

This function would presumably generate the
[diamond-shaped if-then-else pattern][ite].  The initial block is the
block represented by `bcx0`.  The function will compile the condition
`cond` and generate branch to one of two new basic blocks representing
the true and false paths.  The code might look something like this
(note: this is not the actual code in rustc, which is naturally much
messier):

    let (bcx1, val) = compile_expr(bcx0, cond);
    let mut bcx_true = new_bcx(bcx0.fcx);
    let mut bcx_false = new_bcx(bcx0.fcx);
    add_instr(bcx1, if(val, bcx_true, bcx_false));

The then and else blocks could then be compiled in the contexts of those
true and false blocks:

    bcx_true = compile_block(bcx_true, then_blk);
    bcx_false = compile_block(bcx_false, else_blk);
    
And finally the two paths can be merged into a new block, which is the block
that gets returned:

    let bcx_join = new_bcx();
    add_instr(bcx_true, goto(bcx_join));
    add_instr(bcx_false, goto(bcx_join));
    ret bcx_join;

[ite]: http://en.wikipedia.org/wiki/File:If-then-else-control-flow-graph.svg

### The problem: expressing context lifetimes with regions

Let's dig a bit more into the representation of these contexts.  The
details aren't too important but I want to focus on the region-related
aspects that describe their lifetimes.  Remember that there is a crate
context `ccx` that is valid for the translation of the entire crate.
Its contents are not important, so let's just assume it's some record:

    type crate_ctxt = {
         ...
    };
    
Then there is a function context.  It contains a pointer to the crate context,
along with some other stuff:

    type func_ctxt = {
        ccx: &crate_ctxt,
        ...
    };
    
Finally the block context, which contains a pointer to the function context:

    type block_ctxt = {
        fcx: &func_ctxt,
        ...
    };
    
Here I have shown the pointers as region pointers, but I haven't
written any explicit region annotations.  The question is, what
regions should we associate with those pointers?  

### The maximally expressive approach

If you wanted to take the maximally expressive approach, you would
wind up with a lot of region parameters.  For now I will show this in
a very explicit syntax in which types are given explicit Region
parameters, but this syntax is not valid Rust and (hopefully) never
will be:

    type crate_ctxt = {
         ...
    };
    
    type func_ctxt<&c> = {
        ccx: &c.crate_ctxt,
        ...
    };

    type block_ctxt<&f,&c> = {
        fcx: &f.func_ctxt<&c>,
        ...
    };
    
You can see the problem.  The type for the block context must be
annotated with two region parameters, one to describe the region of
the function context and one for the crate context.  

In this technique, if we have a variable `bcx` of type
`&b.bcx<&f,&c>`, then `bcx.fcx.ccx` will have type `&c.ccx`: the
precisely correct region, presumably.

For reference, the signature of `compile_if_then_else()` would become:

    fn compile_if_then_else(bcx0: &b.block_ctxt<&f,&c>,
                            cond: @expr,
                            then_blk: @code_block,
                            else_blk: @code_block) -> &b.block_ctxt<&f,&c>
                            
### The minimally expressive approach

The approach we plan to take is much simpler.  Types do not have
region parameters.  Instead, when we instantiate an `&T` type to a
specific region, the outermost `&` in a function prototype is assigned
a fresh region, but `&` which appear within that type are assigned to
this same fresh region.  This means that if we have a variable `bcx`
with type `&b.bcx`, then `bcx.fcx.ccx` will have type `&b.ccx`: this
is an underapproximation of the lifetime of the crate context.  The
true lifetime is `&c` which is some superset of `&b`.  The reason that
this whole scheme type checks is because of the subtyping
relationships between region pointers: a reference with a longer
lifetime (like `&c.ccx`) can be used wherever a reference with a
shorter lifetime (like `&b.ccx`) is expected.

Under this approach, the signature of `compile_if_then_else()` becomes:

    fn compile_if_then_else(bcx0: &b.block_ctxt,
                            cond: @expr,
                            then_blk: @code_block,
                            else_blk: @code_block) -> &b.block_ctxt
                            
Not so bad.                            
                            
### Arenas and placement new

One question remains: because the lifetime of block contexts is not
bound by the call stack, how can we manage their allocation without
resorting to heap allocation (the function context and crate context
can be allocated on the stack)? The answer is that we will use arenas. 

An arena is basically a pool of memory in which we can allocate lots
of data and then release the pool all in one shot.  This is very cheap
but only suitable for places where allocation follows a "phase-based"
pattern.  

We will use a memory pool which is allocated and released per-function.
Therefore, the pool itself will be stored in the function context:

    type func_ctxt = {
        ccx: &crate_ctxt,
        pool: &memory_pool,
        ...
    };
    
In the current Rust type system, anyhow, a memory pool can be any type
for which there exists an `impl` offering an `alloc(sz: uint, align:
uint) -> *()` method, which allocates `sz` bytes of memory at the
given alignment and returns a pointer.  An expression like `new (pool)
value` will cause `pool.alloc()` to be invoked and will then store the
value into the memory location that was returned.  The result is a
region pointer in the same region as the pool itself.

This means that allocating a new block context looks something like:

    fn new_bcx(fcx: &f.func_ctxt) -> &f.func_ctxt {
        new (fcx.pool) {fcx: fcx, ...}        
    }
    
### The Summary

The basic idea of the approach is to retain less information.  For a
given region pointer `p`, all you know is that any data reachable via
some path like `p.f.g.h` will be live as long as `p` is live.  It
*seems* that this is enough in practice for most real use cases. Time
will tell, I suppose.
