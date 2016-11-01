---
layout: page
title: "regions tradeoffs"
date: 2012-02-17 05:55
comments: true
sharing: true
footer: true
---

## Notation

I am using the notation of `& M T` for a reference, where `M` is the
mutability (`mut`, `const`, or default) and `T` is a type.  When a
specific region must be named, I use the notation `{p} & M T` where
`{p}` is the region name.  

Region names are implicitly scoped to the narrowest scope that
contains all uses of the same identifier.  So:

    fn foo(x: {p} &T, y: {p} &T) -> {p} &T { ... }
    
defines a function with one region parameter (`p`).  

But:

    fn bar(x: fn({p} &T) -> {p} &T) { ... }
    
defines a function that has no region parameter but whose argument is
a function with one region parameter.  Written more explicitly (this
is not an actual notation that we would support), the two examples
would look like:

    fn foo<{p}>(x: {p} &T, y: {p} &T) -> {p} &T { ... }
    fn bar(x: fn<{p}>({p} &T) -> {p} &T) { ... }
    
Note that, currently, we do not support this kind of polymorphism in
our types, but I think we have to to use regions.  That is, you must
be able to define a function pointer that is polymorphic over regions.
Because regions are fully erased, this is safe even when
monomorphizing, unlike function pointers that are polymorphic over
types.

## Table

Along the top are the various region-like systems.  Click on an
acronym to get a description of what that system might look like.
Along the side are the various use cases.  Click on a use case to see
some example code.  If there is a check-mark, then the given region
system supports that use case.  For the most part, the systems are
subset of one another, with the exception of tracing garbage
collection (TGC) and memory pools (MP), which are orthogonal: you
could have one or the other or both.  For cases that rely on TGC or
MP, therefore, I have placed a "(*)" to indicate that it could be
supported if the appropriate subsystem is in place.

<table id="regions">
    <thead>
    <tr>
        <th>Use Case</th>
        <th><a href="#Now">Now</a></th>
        <th><a href="#PRT">PRT</a></th>
        <th><a href="#RT">RT</a></th>
        <th><a href="#AR">AR</a></th>
        <th><a href="#NR">NR</a></th>
        <th><a href="#TGC">TGC</a></th>
        <th><a href="#MP">MP</a></th>
    </tr>
    </thead>
    <tbody>
    <tr>
        <th><a href="#param">Refs in params</a></th>
        <td>&#x2713;</td> <!-- rust today    -->
        <td>&#x2713;</td> <!-- param ref type-->
        <td>&#x2713;</td> <!-- ref types     -->
        <td>&#x2713;</td> <!-- anon regions  -->
        <td>&#x2713;</td> <!-- named regions -->
        <td>&#x2713;</td> <!-- non-rc gc     -->
        <td>&#x2713;</td> <!-- memory pools  -->
    </tr>
    <tr>
        <th><a href="#sound">Sound</a></th>
        <td></td>    <!-- rust today    -->
        <td>&#x2713;</td> <!-- param ref type-->
        <td>&#x2713;</td> <!-- ref types     -->
        <td>&#x2713;</td> <!-- anon regions  -->
        <td>&#x2713;</td> <!-- named regions -->
        <td>&#x2713;</td> <!-- non-rc gc     -->
        <td>&#x2713;</td> <!-- memory pools  -->
    </tr>
    <tr>
        <th><a href="#rec-with-ref">Refs in types</a></th>
        <td></td>    <!-- rust today    -->
        <td></td>    <!-- param ref types     -->
        <td>&#x2713;</td> <!-- ref type-->
        <td>&#x2713;</td> <!-- anon regions  -->
        <td>&#x2713;</td> <!-- named regions -->
        <td>&#x2713;</td> <!-- non-rc gc     -->
        <td>&#x2713;</td> <!-- memory pools  -->
    </tr>
    <tr>
        <th><a href="#ptr-stack">Ptr into local stack</a></th>
        <td></td>    <!-- rust today    -->
        <td></td> <!-- param ref type-->
        <td></td>    <!-- ref types     -->
        <td>&#x2713;</td> <!-- anon regions  -->
        <td>&#x2713;</td> <!-- named regions -->
        <td>&#x2713;</td> <!-- non-rc gc     -->
        <td>&#x2713;</td> <!-- memory pools  -->
    </tr>
    <tr>
        <th><a href="#ret-ref">Ret refs</a></th>
        <td></td>    <!-- rust today    -->
        <td></td>    <!-- param ref type-->
        <td></td>    <!-- ref types     -->
        <td></td>    <!-- anon regions  -->
        <td>&#x2713;</td> <!-- named regions -->
        <td>&#x2713;</td> <!-- non-rc gc     -->
        <td>&#x2713;</td> <!-- memory pools  -->
    </tr>
    <tr>
        <th><a href="#reparent">Repar. coercion</a></th>
        <td></td>    <!-- rust today    -->
        <td></td>    <!-- param ref type-->
        <td></td>    <!-- ref types     -->
        <td></td>    <!-- anon regions  -->
        <td>&#x2713;</td> <!-- named regions -->
        <td>&#x2713;</td> <!-- non-rc gc     -->
        <td>&#x2713;</td> <!-- memory pools  -->
    </tr>
    <tr>
        <th><a href="#at-reg"><code>@</code> as "just another region"</a></th>
        <td></td>    <!-- rust today    -->
        <td></td>    <!-- param ref type-->
        <td></td>    <!-- ref types     -->
        <td></td>    <!-- anon regions  -->
        <td></td> <!-- named regions -->
        <td>&#x2713;</td> <!-- non-rc gc     -->
        <td>(*)</td> <!-- memory pools  -->
    </tr>
    <tr>
        <th><a href="#marijn">Marijn's <code>ty::t</code> hack</a></th>
        <td></td>    <!-- rust today    -->
        <td></td>    <!-- param ref type-->
        <td></td>    <!-- ref types     -->
        <td></td>    <!-- anon regions  -->
        <td></td> <!-- named regions -->
        <td>(*)</td> <!-- non-rc gc     -->
        <td>&#x2713;</td> <!-- memory pools  -->
    </tr>
    <tr>
        <th><a href="#gr-msg">Graph-shaped msgs</a></th>
        <td></td>    <!-- rust today    -->
        <td></td>    <!-- param ref type-->
        <td></td>    <!-- ref types     -->
        <td></td>    <!-- anon regions  -->
        <td></td> <!-- named regions -->
        <td>(*)</td> <!-- non-rc gc     -->
        <td>&#x2713;</td> <!-- memory pools  -->
    </tr>
    </tbody>
</table>

## Type system summaries

<a name="Now></a>
### Now: Rust Today

What is currenly implemented.

<a name="PRT"></a>
### PRT: Parameter reference types

Replace reference modes `&` and `&&` with types like `&`, `&const`,
and `&mut`.  The use of these types would be limited to parameters,
much like `fn&` today.

Note that in this system, the type checker does not internally have
names for regions.  Instead, an `&T` pointer *always* refers to data
in some parent stack frame.  This means that the `&` operator cannot
be used to acquire pointers to data on the *current* stack frame.

One difference that would have to be addressed is the mismatch between
the type of reference parameters (e.g., `&T`) and the type of the
local variables they refer to (e.g., `T`).  Using modes sidesteps this
issue today.  

One way to address this problem would be to allow `T` to be implicitly
coerced to `&T`, or to allow a `&` operator that can only appear in calls:

    fn foo() {
        let cx = {a: 1, b: 2};
        bar(&cx);
    }
    fn bar(cx: &{a: int, b: int}) { ... }

<a name="RT"></a>
### RT: Reference types

As in the previous system, but `&` types are not restricted to
appearing only in parameters.  The use of these types would be allow
in most cases: however, the appearance of an `&` infects the container
to be of `ref` kind. Values whose type is of `ref` kind cannot be
closed over in `fn@` or `fn~` nor can they be returned.  The intention
is to ensure that an `&` pointer always refers to data in some parent
stack frame.

To prevent data from escaping, a kind of ad-hoc rule is needed: values
of reference type cannot be assigned through pointers (the intention:
it must be impossible to moify values of reference type that appear in
outer stack frames).  This is needed because the type checker does not
internally have names for regions and so cannot distinguish lifetimes.
This rule is described in more detail in <a
href="#leak-through-mut-field">this anti-example</a>.

<a name="AR"></a>
### AR: Anonymous regions

Replace reference modes `&` and `&&` with types like `&`, `&const`,
and `&mut`.  The use of these types would not be limited to
parameters.  In this system, the alias checker internally represents a
reference type `&T` with a region name: `{r} &T`, but that region `r` is
*never* named explicitly by the user and in fact cannot be.

This gives the type checker the ability to reason about multiple
regions within the same function.  For example, by assigning a
distinct region to each block within the function.

<a name="NR"></a>
### NR: Named regions

Just as with anonymous regions, but users are able to explicitly name
a region using some syntax (e.g., `{r} &T`).

<a name="TGC"></a>
### TGC: Tracing garbage collection

A garbage collection scheme that does not require special action on
stores *and* which can accommodate interior pointers.  In practice,
this means a tracing-based system rather than an RC-based system.

<a name="MP"></a>
### MP: Memory pools

The ability for the user to create a memory pool and allocate data
within it.  Typically this data would be freed in one shot when the
pool is released but we could also allow the data to be GC'd.

I think there are a lot of details to be filled in before this could
work within a region system.  But the high-level sketch looks
something like this.  There are memory pool objects of type
`memory_pool` (we could allow user-defined types too via an iface,
that's not terribly important).  

You create a memory pool using the function `memory_pool::create` which
is defined something like:

    fn create<T>(f: fn(&memory_pool) -> T) -> T {
        let pool = ... create fresh memory pool somehow ...;
        let result = f(pool);
        ... free pool ...
        ret result;
    }

Note that the function `f` must accept *any* memory_pool and it
returns a type `T`.  By the rules of the region type system, `T`
cannot have any references to data in the memory pool, so it is safe
to free the pool after `f` returns.

Using a memory pool looks like:

    fn foo() {
        memory_pool::create {|pool: {p} &memory_pool|
            // Note: the region `p` is fresh.
            let x = {p} &{....}; // create some data in `p`
        }
    }

In the section on [handling `ty::t` types](#marijn), I expand on how
we could use this API to handle our treatment of `ty::t` today.  In
the section on [graph-shaped messages](#gr-msg), I show how this API
can be expanded a bit to support other use-cases.

## Examples

<a name="param"></a>
### Parameters that point into stack frame

This just refers to the basic reference-mode arguments we have today:

    type ctxt = { ... };
    fn foo(&&c: ctxt) {
        // here, c is some instance of ctxt which is "guaranteed"
        // by an outer stack frame.  
    }
    
However, these references cannot appear in non-parameter position
(excluding the `let &x` form, which I confess I do not fully
understand) and in particular cannot appear as a part of data structures:

    type ctxt = { ... };
    type inner_ctxt = { c: ctxt, ... };
    fn bar(&&c: ctxt) { // `c` is a pointer here
        // this causes a copy of ctxt, rather than storing the pointer
        // into `inner_ctxt`
        let ic: inner_ctxt = { c: c, ... };
    }

<a name="sound></a>
### Sound

The current system is unsound because it does not distinguish between
const and immutable memory, essentially.  

<a name="rec-with-ref"></a>
### Records and other types containing references

As [described above](#param), the current system cannot store a
reference into a field.  Under most any region proposal, this should
be possible:

    type ctxt = { ... };
    type inner_ctxt = { c: &ctxt, ... };
    fn bar(c: &ctxt) { // `c` is a pointer here
        let ic: inner_ctxt = { c: c, ... };
    }

This comes up pretty often, particularly when refactoring or expanding
existing code that uses references.  One example that recently bit me
had to do with visitors.  I wanted to write a visitor like:

    type ctxt = { ... };
    fn visit(cx: ctxt, item: @ast::item) {
        let v = visit::mk_vt({
            visit_item: fn@(...) {
                ... code that uses cx ...
            });
        v.visit_item(item, (), v);
    }

This compiles, but has the unfortunate side effect of copying `cx`
into the closure rather than using it by reference.  In a region scenario,
the type of the visitor could be written using `fn&` instead of `fn@`:

    type vt = {
        visit_item: fn&(...) { ... }
    };

This would also fit more closely with how the visitors are intended to
be used, I think.

<a name="ptr-stack"></a>
### Pointers into local stack frame

This refers to the ability to take the address of a local variable or
to store an rvalue onto the stack (the latter is shown here):

    fn foo() {
        let cx = &{a: 1, b: 2};
        bar(cx);
    }
    fn bar(cx: &{a: int, b: int}) { ... }

<a name="ret-ref"></a>
### Returning references

This refers to the ability to return a reference:

    fn pick(a: a&T, b: a&T) -> a&T {
        if ... { a } else { b }
    }
    
This ability and some of its limitations are discussed in more detail
in [this blog post][rr].

<a name="reparent"></a>
### Reparented coercion

Reparenting also applies when coercing an `@T` pointer into a `{r} &T`
pointer.  The idea is that, when performing such a coercion, we
increment the ref count of the `@T` value and assign it the region of
the innermost block.  The ref will be released upon exit from the
block.  This implies that the reference is only valid during the block
where the reparenting occurred, and hence the region `r` assigned to
the pointer is that of the innermost block.

This approach is simple and compatible with any garbage collecting
system.  However, it has the side effect that it is not safe to return
references to the caller. 

<a name="at-reg"></a>
### `@` is "just another region"

In contrast to a [reparenting](#rep-ref) scheme, the "just another
region" approach treats `@` as a region itself.  This means that no
coersion from `@T` to `{r} &T` is necessary: instead, `@T` is just
shorthand for `{@} &T` (i.e., the region `r` is `@`).  This requires
appropriate garbage collection support.  In particular, a tracing
technique is necessary and interior pointers must be supported.
However, it makes for a very flexible end system.

The reason that RC cannot be used is that we must be able to treat
pointers to data on the stack and pointers to data in the heap
uniformly, both in local variables but also within data structures
themselves.  For example, under such a scheme we might have a routine
like `set_f()` below:

    fn set_f(o: {mut f: {r} &T}, v: {r} &T) {
        o.f = v;
    }
    
Here the trick is that `set_f()` may be legally invoked with `@`
pointers or with data on the stack, and in both cases it would have to
perform the same operations.

> Actually, I suppose, a RC technique could be used if we were willing
> to add RC operations to data that lives on the stack.  It is however
> less than obvious how to adjust RC to account for interior pointers:
> I mean, it could be done, but the overhead would be high.

<a name="marijn"></a>
### Marijn's `ty::t` hack

To avoid RC and GC overhead, Marijn made the compiler use unsafe
pointers for `ty::t` instances.  This is a good hack for now but a
safer (and more efficient) solution would be to use a memory pool.  I
am not 100% sure how this would look, but I think it is something like
this.  

First, you can create a type context something like this:

    mod ty {
      type t = &{...};
      type ctxt = {
          pool: &memory_pool,
          interned_types: map<..., t>,
          node_types: map<ast::node_id, t>
      };
      fn make_tcx(pool: {p} &memory_pool) -> {p} &ctxt {
          ret {pool} &{
              pool: pool,
              interned_types: mk_hash(),
              node_types: mk_hash()
          };
      }
    }
    
Then you can create types like:

    fn make_ty(pool: {p} &ctxt) -> {p} t {
        ...
    }
    
You can write functions that work with existing types just like today:

    fn check(t1: ty::t) { ... }
    
If you wanted to insert the type into the expression table, it will
often 'just work':

    fn check_expr(tcx: &ty::ctxt, e: @ast::expr) {
        // implicitly: tcx is assigned a fresh region variable r
        alt e {
            ast::expr_field(...) {
                let t = make_ty(tcx, foo);
                // here: t has type {r} ty::t
                tcx.insert(node_types, t);
            }
        }
    }
    
But whenever you want to return a `ty::t`, you have to be a bit more explicit:

    fn check_expr(tcx: &ty::ctxt, e: @ast::expr) {
    
        fn call_helper(tcx: {t} &ty::ctxt, e: @ast::expr) -> {t} ty::t {
        }
        
        alt e {
            ast::expr_field(...) { ... }
            ast::expr_call(...) {
                let t = call_helper(tcx, e);
                tcx.insert(node_types, t);
            }
        }
    }

Here, the `call_helper()` function had to specify explicitly the
region of the return value, linking it to the `ty::ctxt`.

<a name="gr-msg"></a>
### Graph messages

Right now we can only send tree-shaped data between tasks.  Graph
messages would allow an arbitrary data structure to be built up in a
custom memory pool and then allow the entire memory pool (and hence
the entire data structure) to be transferred in one shot.  Such
structures would still be prohibited from containing `@T` types or
pointers that reach out from the memory pool.

My guess for the best way to do this in an API perspective would
be to have a type like `msg<T>` which is sendable.  It contains the
pair of a pool and a root object in that pool.  You could work with
this object by doing:

    msg.process {|t| // t has type &T
        ...
    }
    
To create a message, you would use a convenient method on the memory
pool class that looks something like:

    fn make_msg() {
        let msg = memory_pool::create {|pool|
            ... result value must be of type {pool} &T ...
        };
    }
    
This API is rather block-scoped; this is somewhat restrictive but I
think in practice it'd be quite flexible.  After all, if you need to return
data from inside a message we could define a map method like:

    fn foo(port: comm::port<msg<T>>) -> msg<S> {
        let m: msg<T> = comm::recv(port);
        m.map {|pool, t|
            ... return a value of type {pool} &S ...
        }
    }
    
## Anti-examples

Here are things that should not work in each system and an explanation
of why they do not.  In some cases, the explanation varies depending
on the region system.

<a name="leak-through-mut-field"></a>
### Leak `&` through a mutable field

**The danger:** a mutable field could point to a reference with
shorter lifetime than the container.

    type ctxt = { mut a: &A, mut b: &B };
    fn foo(c: &ctxt, a: &A) {
        c.a = a;
    }
    
Here, there is no guarantee that the lifetime of `a` is greater than
the lifetime of `c`.
    
**Why doesn't it work?** 

- Reference types: Requires an ad-hoc rule (no assigning to lvalues of
  reference type through a pointer).

- Anonymous regions: Variance rules would actually prevent a record
  with mutable fields from being passed in.  So, the above program
  might type-check, but the method `foo()` could never be called.  This
  is subtle.  The reason is that the callee expects a type like:
  
      {mut a: {r} &A, mut b: {r} &B}
      
  where `r` is a narrow region representing the call itself.
  The caller then has a context with a type like:
  
      {mut a: {s} &A, mut b: {s} &B}
      
  where `s` is some broader region, perhaps the body of the caller.
  Because the types will be invariant due to the mutable fields, the
  one type is not a subtype of the other even though `r` is a
  subregion of `s`.
  
  To make it more concrete, the caller would look something like:
  
      fn bar(a: &A, b: &B) {
          // --> internally, a and b have type `x&A` and `x&B` where
          // `x` is a region representing this call
          
          let c = {mut a: a, mut b: b};
          // --> c has type `{mut a: x&A, mut b: x&B}`
          
          foo(c);
          // --> type error. `foo()` expects a type
          // `{mut a: y&A, mut b: y&B}` where `y` is a region
          // representing just this call.  If the fields `a` and `b`
          // were not mutable, this would be fine, because `y` is a 
          // subregion of `x` so `y&A` is a supertype of `x&A` and
          // therefore `{a: y&A,...}` is a supertype of `{a: x&A,...}`.
          // But the fields *are* mutable and so `{mut a: y&A,...}` 
          // is only a supertype of `{mut a: y&A, ...}` (i.e., the
          // regions must match exactly, which they never could).
      }
  
  In effect, this restriction will prevent records with mutable fields
  of reference type from being passed to a callee or stored into an
  existing structure.  Basically it has the effect of isolating such
  types within the stack frame that created them, though the rule does
  not directly impose that restriction: there is just no way for a
  callee to name a type that can match the caller's type.  This may be
  too inexpressive and/or lead to confusing error messages if we are
  not careful.

- Named regions: Similar to above, except that conceivably the user could
  express `foo()` in such a way as to be correctly type-checked:
  
      fn foo(c: {mut a: x&A, mut b: y&B}, a: x&A) {
          c.a = a; //OK
      }


[rl]: /blog/2012/02/15/regions-lite-dot-dot-dot-ish/
[rr]: /blog/2012/02/16/returning-refs/
