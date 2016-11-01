---
layout: post
title: "Implementing unique closures"
date: 2011-12-16 10:32
comments: true
categories: [Rust]
---

I landed a preliminary version of unique closures (which I am currently calling 
sendable fns) on the trunk last night.  I wanted to briefly document what I did
to alter the design of closures to get this working (of course there is a comment
in the code too, but who reads that?).

Closures in Rust are represented as two words. The first is the function pointer
and the second is a pointer to the closure, which is the captured environment that
stores the data that was closed over.  Because of how Rust is implemented, the 
closure must also store any type descriptors that were in scope at the point where
the closure was created.

Prior to my changes, the closure was represented by a structure roughly
equivalent to this C++ struct (actually I will use a hybrid of C++ and Java 
syntax):


    struct closure<class BD, unsigned n_tds> {
		type_desc *bound_data_td;
		BD bound_data;
		type_desc *bound_tds[n_tds];
	};

Here, the initial type descriptor `bound_data_td` is a type descriptor
that describes the struct `BD`.  It contains, among other things, the
size and alignment of `BD` etc, as well as pointers to the "take" and "drop"
functions, which copy and release the value respectively.

This layout had a few downsides.  One was that we could not load the type
descriptors from the `bound_tds` array without knowing the type of `bound_data`.
It's possible, however, that we do not know the precise type of `bound_data`
for any specific closure instance.  The reason is that the closure might come
from a generic function, something like:

    fn make_closure<copy T>(t: T) -> (lambda() -> T) {
		ret lambda() -> T { t };
	}
	
Now, this closure is going to result in a bound_data that is *itself* generic!
It would look something like:

    struct make_closure_bound_data<class T> {
		T t;
	};

The problem is that when we are generating code for this closure, we have to generate
one set of code that works for *any value of `T`*. In other words, we know that 
we have a closure whose type is something like `closure<make_closure_bound_data<?>, 1>`,
where `?` represents an unknown type.  Expanded that would look like:

    // closure<make_closure_bound_data<?>, 1>
    struct make_closure_closure { 
		type_desc *bound_data_td;
		make_closure_bound_data<?> bound_data;
		type_desc *bound_tds[1];
	};

The problem now is that because we do not know the precise type of `bound_data`,
we also do not know the offset of the field `bound_tds`!  The way we generally
handle this sort of situation is to use a type descriptor for the unknown type
`T` tells us how big a value of type `T` is and so forth.  Indeed, we have that
type descriptor, but it is stored in the `bound_tds`
array above.  But now you see a certain chicken-and-egg problem: to know how big the
bound data is, we have to load the type descriptor for `T`, but to load the type
descriptor, we have to know how big the bound data is.

The solution to this in the past was that we also had the `bound_data_td`, a type
descriptor for the entire set of bound data, and we could use its size field to
skip past the bound data to the type descriptor array.  But this was kludgy and
also dangerous: the code had to use a different code path (for various reasons
not worth getting into) than the other code that does these sort of dynamic
calculations, and I am not sure that it was correctly considering things like
alignment restrictions and so forth.

Therefore, I made some slight changes to the structure that eased these problems.
It is now represented like so:

	template<class BD, unsigned n_tds>
    struct closure {
		type_desc *closure_td;
		type_desc *bound_tds[n_tds];
		BD bound_data;
	};

There are two changes of note. First, the `closure_td` represents the *entire 
closure* and not just the bound data.  Second, the set of bound type descriptors
is stored at a *statically known offset*, regardless of what data is closed over.
What's more, while it may not be obvious at first, the offset of the bound_data
is also statically known: the reason is that when we are looking at one of these
structures, we know the number of bound type descriptors (i.e., we know `n_tds` in
the template above), and they are always of fixed size (a pointer). So that's 
good.

Now the other nice thing is that because `closure_td` represents the closure as a whole,
we can re-use the existing type copying routines.  Basically we are able to say:
"copy the object whose type is described by `closure_td`" and the code will do
the right thing.  If `closure_td` does not involve generic types, it will generate
purely static code, otherwise it will generate hybrid static/dynamic code.
So basically I use these standard routines to generate the glue functions that take
and drop a closure.

Now, if you have a sendable fn in your rust code and want to do a deep copy, you
can use these glue functions.  You may be wondering why have to use the glue functions,
why not just copy it directly? The reason is that when you have a sendable fn, you
don't know the precise closure type: it's equivalent to a type like `closure<?,?>`. 
However, even that very imprecise type is enough to find the field `closure_td`,
which is always first, so we can copy any kind of closure by doing:

    closure<?,?> *copied_closure = closure;
	closure->closure_td->take_glue(&copied_closure);

(That is more-or-less the signature that our take functions have). There are a 
few other minor changes, but that's the gist of it.
