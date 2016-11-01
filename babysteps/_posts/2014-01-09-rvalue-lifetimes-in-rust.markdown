---
layout: post
title: "Rvalue lifetimes in Rust"
date: 2014-01-09 01:04
comments: true
categories: [Rust]
---
I've been working on [Issue #3511][3511], which is an effort to
rationalize the lifetimes of temporary values in Rust. This issue has
been a thorn in the side of Rust users for a while, because the
current lifetimes are rather haphazard and frequently too short. Some
time ago, I did [some thinking on this issue][pp] and then let it lie
while other things took priority.

Part of the reason that this issue has lasted so long is that the
current trans cleanup scheme is very inflexible. I have a
[branch now][branch] that rewrites the cleanup system so that it can
handle any rules we would like. The problem I am encountering now, of
course, is that it's unclear what the rules should be. I want to lay
out the options I see.

<!-- more -->

### The problem

There are numerous situations in which Rust users borrow temporary
values; the tricky part is deciding what the *lifetime* of these
temporary values ought to be. Put another way, when should we run the
destructor for these temporaries? To see what I mean, let me show a
few examples: I'll focus on three use cases that I think are fairly
representative, and which I see appearing in the code base a lot.
It's possible though that I'm missing some good examples.

**Example 1: borrowing an rvalue.** Here is the first example:

    let map = &mut HashMap::new(); // (1)
    
The effect of this expression is to create a temporary stack variable
and create a pointer to it. It is *roughly* equivalent to something
like this:

    let _temp = HashMap::new();
    let map = &mut _temp;

The question that I want to consider in this post is what the lifetime
of this temporary ought to be. In the explicit expansion, the lifetime
of the temporary is clear: it will live as long as the explicit
variable `_temp`. But the correct semantics for the first example
are less clear (as we'll see).

Applying the `&` operator to an rvalue might seem a bit silly at
first.  Why not write it using an explicit temporary, after all? There
are a couple of reasons though that it's worth supporting, but the
most crucial one is in macros. In macros, it's useful to be able to
apply the borrow operator to any expression in order to avoid moving
or copying values when you don't want to. For example, the expansion
of `assert_eq!($a, $b)` is something like:

    {
        let _a = & $a;
        let _b = & $b;
        if _a != _b {
            fail!(...)
        }
    }

If we didn't use the `&` operator, then the first two lines might
cause inapprorpriate moves. For example, if I wrote `assert_eq!(x.a,
y.b)`, and the type of `x.a` was affine, then `assert_eq!` would move
from both `x.a` and `y.b`. Not so good.

**Example 2: ref bindings and rvalues.** The second example is in some
way just a different syntax for the same thing (or, I should say,
somethign which probably ought to be the same, though some of the
rules I describe do not treat it the same way):

    let ref mut map = HashMap::new();
    
**Example 3: Autoref in method calls.** Method calls in Rust typically
take borrowed pointers to their receivers, but one rarely writes this
explicitly. Instead, the receiver is implicitly borrowed via a
mechanism called "autoref" (this is actually the same as in C++,
except that in C++ all method calls are autoref'd, whereas in Rust you
can also have method calls that take the receiver by value and not by
reference).

One example that is becoming rather common in the `rustc` code base is
the `RefCell` type. `RefCell` is a standard library type that allows
some of the Rust compiler's static checks to be converted into dynamic
checks; it replaces `@mut`, which bundled together dynamic checks with
managed data, and just isolates out the dynamic check portion so that
it can be reused with other smart pointer types.

The way that `RefCell` works is that you invoke the `borrow` or
`borrow_mut` methods:

    let map: RefCell<HashMap<K,V>> = ...;
    let mut r = map.borrow_mut();

These methods check some bits to ensure that the value is not borrowed
in an incompatible way already (basically: a mutable borrow must not
overlap with any other borrows). These methods then toggle some bits
and return a special `Ref` type (`r` in the example above). This `Ref`
type has a destructor which resets the bit, effectively ending the
borrow.  In the meantime, the `Ref` type can be used to get access to
the data itself:

    let data = r.get();

Note that there is an implicit borrow of the variable `r` occurring here.
In a sense, that method call could be expanded to:

    let data = (&mut r).get();
    
The key point here is that the lifetime of the variable `r` exactly
corresponds to the lifetime of the dynamic borrow of `map`. Therefore,
having a good understanding of when the destructor for `r` will run is
crucial to know how long your map is borrowed for. For example, if you
write code like the following, you will get a fatal error:

    let map: RefCell<HashMap<K,V>> = ...;
    let mut r1 = map.borrow_mut();
    let mut r2 = map.borrow();     // Error: already borrowed!

The problem is that the second borrow (`r2`) occurs before the first
borrow has completed; more operationally, the second borrow occurs
before the destructor for `r` executes.

The lifetime of a borrow is relatively clear so long as explicit
temporaries are used, as I showed so far. But it's kind of verbose.
For example, to insert an item into a map, I have to write something
like:

    let mut r = map.borrow_mut();
    r.get().insert(k, v);

It'd be nicer if we could remove the temporary:

    map.borrow_mut().get().insert(k, v);
    // temporary:   ^~~~^

But this gets right back to the issue were talking about, because the
call to `get()` in fact takes the address of the receiver, and in this
case the receiver is an rvalue `map.borrow_mut()`.

### Some solutions

OK, so we have three examples where rvalue temporaries are borrowed:

    let map = &mut HashMap::new();       // (1)
    let ref mut map = HashMap::new();    // (2)
    map.borrow_mut().get().insert(k, v); // (3)
    
I want to explore various rules we could use to decide when the
destructors run, and see what the effect would be on each example.

### Solution 0: Innermost enclosing statement.

My first attempt (what is currently written on the branch) was to make
all temporaries tied to the innermost enclosing statement (roughly,
see Appendix B for full details). I think this does the right thing
for example 3, in that it releases the borrow at the of the statement:

    map.borrow_mut().get().insert(k, v); // (3)

However, examples 1 and 2 both fail to compile:

    let map = &mut HashMap::new();       // (1)
    let ref mut map = HashMap::new();    // (2)

The reason for this is that, if the hashmap only lives as long as the
statement, the value in `map` gets destructored as soon as it is assigned,
and thus cannot safely be used by the following statements. That is,
the following code would access freed memory:

    let map = &mut HashMap::new();
    map.insert(...);

I think this solution is **not workable** because one cannot write the
`assert_eq` macro above.

### Solution 1: Innermost enclosing block.

To address the problem with solution 0, we might try to use the innermost
enclosing block. This makes examples 1 and 2 work find, but example 3
doesn't work so well:

    map.borrow_mut().get().insert(k, v); // (3)

The problem is that here the borrow isn't released until the end of the
enclosing block, rather than the enclosing statement. This probably
way too late. For example, code like the following would fail dynamically:

    {
      ref_map.borrow_mut().get().insert(key1, value);
      let v = *ref_map.borrow().get().find(key2);
      ...
    }

I think this solution is **not workable** because it is too painful
to work with `RefCell`.

### Solution 2: Variations on the C++ rule (roughly).

Interestingly, C++ has a similar problem concerning temporaries, and
they have a rather custom rule that attempts to address exactly the
issue I encountered with solution 0. The C++ rule, as I understand it,
is that temporaries live as long as the innermost enclosing statement,
unless the temporary is assigned to an (reference) variable, in which
case it lives as long as that variable.

So, for example, if I had a call to a function that took a map rvalue
reference, as follows:

    V& find(const map<K,V>& m) { ... }
    
    use(find(map(...)));

then the map will be freed after `use()` returns. This is true even
though the temporary was created as an argument to `find()`. Basically
the temporary will live until the next semicolon, roughly speaking.

Now there is one exception to this rule. If I asssign the temporary to
a variable, then it lives as long as the variable:

    const map<K,V>& m = map(...);
    
In this case, the destructor for `map` will run once `m` goes out of
scope.

It is a bit challenging to make a direct equivalent to this rule in
Rust. For one thing, we have explicit borrows (the `&` operator) and
also `ref` bindings. For another, assignments can be more complicated,
e.g.:

    let Foo { a: ref a, b: b } = create_foo();
    
In this case, one of the fields is bound by reference, but the other
is moved.

**Variation A.** Still, we could make a rule that says something like this:
`let` bindings where the initializer is an rvalue first store the initializer
into a temporary with the lifetime of the innermost block, and then assign
from that temporary into the pattern. So effectively `let pat = rvalue` becomes:

    let _temp = rvalue;
    let pat = temp;
    
This rule treats examples 1 and 2 rather differently:

    let m = &mut HashMap::new();     // (1) Error
    let ref mut m2 = HashMap::new(); // (2) OK
    
Example 1 is unaffected by the rule and hence still an error for the
same reasons as Solution 0: the temporary created by the explicit
borrow goes out of scope at the end of the `let` statement, rather
than the block. Example 2 would work, though, because the temporary in
that case would have an extended lifetime. In the case of Example 3
(the `RefCell`), the borrow would terminate at the end of the
statement, as desired.

**Variation B.** Another option would be to say that the borrow
operator `&` uses the lifetime of the innermost enclosing block, but
all other temporaries use the innermost enclosing statement. This rule
is easier to explain than variation A, and it has the opposite effect
on examples 1 and 2:
    
    let m = &mut HashMap::new();     // (1) OK
    let ref mut m2 = HashMap::new(); // (2) Error
    
In Example 2, the temporary used for `let` initializers only lives
until the end of the statement, so we get a compilation error.

**Variation C.** We could extend the lifetime of both explicit `&` uses
as well as `let` initializers. In that case, both examples 1 and 2 work
the same way:

    let m = &mut HashMap::new();     // (1) OK
    let ref mut m2 = HashMap::new(); // (2) OK

**Summary.** I think variations A, B, or C would all be potentially
workable.

### Solution 3: Inference.

Finally, we can rely on inference. Essentially the compiler would
decide the smallest lifetime that makes the program legal. This makes
all of the examples I've given work, but at a cost in predictability
-- it's hard to know when your destructors run. For things like
`RefCell`, this is of course a potential problem. Overall, while I
think inference is workable, it is almost universally unpopular,
simply because people do not like the idea of an ill-defined lifetime
inference algorithm dictating when their destructor will execute.

### Conclusions

All in all I guess I leans towards some variation of Solution 2.  I
like Variation B (make the lifetime of the explicit `&` operator be
the innermost enclosing block; otherwise, innermost enclosing
statement) because it's easy to express and implement, but I also like
Variation C because it treats examples 1 and 2 the same way. Whatever
we do, having an explicit option seems like a good idea (see Appendix
A).

### Appendix A. Explicit annotation

Regardless of what rule we pick, it is possible to permit users to
explicitly annotation temporary lifetimes. One of the motivations for
the current lifetime syntax was to permit users to annotate blocks
(and perhaps statements/expressions) with lifetime names and then
refer to those later. For example, one might create a temporary and
explicitly state that it should be destructed in an outer block:

    'a: {
        {
            let m = &'a mut HashMap::new();
            ...
        }
    }

There would be some limits to these explicit temporaries. For example,
you could not create a temporary in an outer block if you are within
an `if` or `loop` statement (this is needed to ensure fixed size
stacks and to ensure we know what values to run destructors on
statically).

### Appendix B. Tail expressions in block.

In many of the rules above, I've referenced the innermost enclosing
block or statement. But what is the innermost enclosing block or
statement in a situation like:

    let v = {
        &mut HashMap::new()
    };

It might be nice to make the tail expression in a block belong,
effectively, to its parent.

In my existing code (which implements Solution 0), the actual rule is
not ""innermost enclosing statement" but rather "innermost enclosing
statement, loop body, or function". I do not consider the tail
expression of a block to be in a statement. This means that
temporaries in the tail expression effectively have the lifetime of
the statement (or loop body, or function body) in which the block
appears.

### Appendix C. Match expressions.

Ref bindings can also appear in match expressions, of course.
Regardless, I think the semantics of match on an rvalue probably ought
to be that the temporary value lives as long as the enclosing
statement, regardless of what bindings it contains; that seems to be
what most people expect.

[3511]: https://github.com/mozilla/rust/issues/3511
[8861]: https://github.com/mozilla/rust/issues/8861
[pp]: {{ site.baseurl }}/blog/2012/09/15/rvalue-lifetimes/
[branch]: https://github.com/nikomatsakis/rust/tree/issue-3511-rvalue-lifetimes
