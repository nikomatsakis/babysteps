---
categories:
- Rust
comments: true
date: "2012-05-08T00:00:00Z"
slug: iface-types
title: Iface types
---
Yesterday I wrote about my scheme for paring down our set of function
types to one type, `fn:kind(S) -> T`.  When I finished writing the
post, I was feeling somewhat uncertain about the merits of the idea,
but I'm feeling somewhat better about it today.  I really like the
idea that top-level items have the type `fn:kind(S) -> T` and that you
therefore give them an explicit sigil to use them in an expression;
this allows us to remove the "bare function" type altogether without
any complex hacks in the inference scheme.

Anyway, I didn't talk at all about iface types yesterday, but they
have a place in this scheme too.  An iface type, also called a boxed
iface, is basically the pair of a vtable with a `self` pointer.  Today
this is hard-coded to be a GC'd ptr (`@`), but I want to change this
as it is very limited: iface types are relatively expensive to
construct (requiring allocation, RC overhead, etc) and they cannot be
sent between tasks.

Under my proposal, an iface type would be written `id:kind` where `id`
is the name of the interface and `kind` is an optional kind bound that
applies to the receiver.  The type is dynamically sized, because the
value that is represented is something like:

    struct iface_instance {
        void *vtable;
        type_desc *td;
        ... // self data is represented inline
    }
    
This proposal therefore allows you to construct things like:

    @id      (today's "boxed iface")
    &id      (an iface instance allocated on the stack)
    ~id:send (a sendable iface instance)

#### New interface instance construction syntax

There is one other change I'd like to make, which is independent but
seems to fit.  Today, iface types are constructed using `as`.  I am
not crazy about this because `as` is normally our type cast operator,
but iface type construction is not a type cast.  It may perform
allocation etc.  The `as` construction is also very wordy, requiring
one to specify the desired iface rather than having it inferred, and
it has an awkward requirement that `::` be used for any type
parameters on the type.

As a replacement I propose we make use of the `iface` keyword in
expressions, so that `iface::<T>(v)` would construct an instance of
the iface type `T` for the value `v`.  Like all type parameters, `T`
may be left off and inferred from context.  So typically you would
just write `iface(v)`, as in this example (here I assume the current
iface types, rather than the ones I will describe shortly):

    iface an_iface<T> { ... }
    impl of an_iface<int> for int { ... }
    fn foo(i: an_iface<int>>) { ... }
    fn bar(i: int) { foo(iface(i)) {

In contrast, the fn `bar` in the old syntax looks like:

    fn bar(i: int) { foo(i as an_iface::<int>) }
    
At first I wanted to make ifaces into constructor functions with a signature
like:

    fn an_iface<I:an_iface>(i: I) -> an_iface
    
but this doesn't fit with my proposal above, as if the type an_iface
is a type of dynamic size, as it cannot be returned (also, how does
one specify the sendability bounds?  They would have to be added as
bounds to the type `I`, etc)
