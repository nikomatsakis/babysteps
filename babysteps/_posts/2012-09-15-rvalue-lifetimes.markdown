---
layout: post
title: "Rvalue lifetimes"
date: 2012-09-15 13:27
comments: true
categories: [Rust]
---

We need to clarify our story on rvalue lifetimes.  This is related to
[issue #3387][3387] and also various recent and not-so-recent
discussions on IRC.

[3387]: https://github.com/mozilla/rust/issues/3387

The basic question is how long an rvalue lives when the program creates
pointers into it.  To understand the rough issues, first consider this
program:

    let x = foo();
    match x {
        Some(ref y) => {...}
        None => {...}
    }
    
Here, the result of `foo()` is stored into a local variable.  The
`match` clause then creates a pointer to the interior of this local
variable (i.e., into the stack) called `y`.  But what if we eliminated
the variable `x`:

    match foo() {
        Some(ref y) => {...}
        None => {...}
    }
    
This seems to read fine, but when you think about it it's a little
strange.  Where does the result of `foo()` live, after all?

The answer is that `rustc` creates a temporary home on the stack.
Basically, it transforms the second example into the first.  Now, the
question at hand is, how long does this temporary live?

Actually, there are a number of related questions.  It turns out it's
pretty hard to come up with a system that seems to address all the
desired use cases.

Here are some related scenarios where this question comes up:

- An expression like `&foo()`: the desired semantics is basically the
  same as above: introduce a temporary on the stack, write the result
  of `foo()` into this temporary, and then return a pointer to
  it. Again we must decide how long this temporary lives.
- An expression like `&[1, 2, 3]`: this allocates a temporary vector
  on the stack and returns a slice.  How long should it live?
  
In all of these cases, there is a sort of hard limit: the value cannot
live longer than the innermost enclosing loop or function.  That would
require dynamically sized stack frames, which we do not want.
However, there is a range of other possible answers.

One time when it becomes very important to have a good answer to this
question is when destructors come into play.  It is nice if we can
make a rule that makes it very predictable when a destructor will
execute.

There are two basic approaches we can take:

- Come up with a rule for how long rvalues live, hopefully a simple
  one, and enforce it in the region checker.
- Using the region checker, infer the liftime of any pointers into
  the rvalue temporary, and make it live as long as those pointers
  but no longer.  It is an error if that would cause the rvalue's
  lifetime to exceed the innermost enclosing loop or function.

### A simple rule?

It turns out to be hard to find a rule that both matches intution and
covers the various use cases.  Our first thought was "rvalues
temporaries live as long as the innermost enclosing statement".  This
works well for the match statement given above, for example.  However,
it doesn't work well for examples like:

    let foo = &bar();
    let foo = &[1, 2, 3];
    
Because, in these cases, the value would only live as long as the
`let` statement iself, you could never use `foo` at all, as it would
point into deallocated memory.  We could say, well, in a let statement,
the value lives as long as the enclosing block.  OK, then what about this:

    let foo = if cond { &bar() } else { &qux() };

Well, maybe we say that a tail expression is not a statement (it's not, after all)
and is sort of a part of the enclosing statement, so this example would mean
that `&bar()` and `&qux()` would live as long as the enclosing block.

OK, then what about if we wrote it this way:

    let foo;
    if cond {
        foo = Some(&bar());
    } else {
        foo = None;
    }

Hmm, this is more troublesome.  We'd have to look at the assignee, see that is
a variable, and decide that the lifetime of any rvalue temporaries will be
the lifetime of that variable.

OK, then what about *this*:

    let foo = { mut f: None };
    if cond {
        foo.f = Some(&bar());
    }
    
Hmm, to accommodate this, we have to do a borrowck style analysis to
figure out what the rvalue lifetime is, because we have to consider
where the field `f` resides.  Of course we have the code to do this,
but this rule is looking more and more complex!

Not only that, but such a rule can lead to some pretty counterintuitive results.
For example:

    let foo;
    if cond {
       foo = match bar() {
           Some(x) => x * x,
           None => 0
       };
    }
    
Now, here, the result of `match bar()` is being assigned to `foo`, so
I guess the lifetime of the temporary rvalue for `bar()` ought to be
the same as the block enclosing `foo`.  But that means that this
rvalue will live much longer than we expect, and much longer than it
needs to.  So perhaps we "reset" to the enclosing statement when we
descend into a match statement---and perhaps other statements too,
like calls.  That seems to more-or-less yield what I intuitively
expect.

In these situations, it is perhaps instructive to consider what C++
does.  Near as I can tell from reading the spec, the C++ rule is that
"a temporary lives as long as the outermost enclosing expression,
unless it is assigned to an rvalue reference, in which case it may
live longer".  This is basically the rule I just described.  This is
not, in my opinion, a simple rule: it's a "do what I mean" (DWIM) rule
that tries to approximate what it thinks you wanted.  One advantage
we'd have over C++, of course, is that with regions we could report an
error if you thought that the rvalue would live longer than it will.

### A simple rule!

Well, there is one rule we could say.  We can just assign rvalue
temporaries the *maximal* lifetime.  They can all live as long as the
innermost enclosing loop or function body.  In that case, all of the
prior examples will work just fine.  The price we pay is that (1) the
stack space (and any uniques/other variables within) lives longer than
you might expect and (2) destructors run rather late, probably much
later than the user anticipated.  

So, if you have something like this:

    loop {
    
        if cond {
            let foo = a_function();
            let bar = &a_function();
            
            // foo is dropped here
        }
        
        // bar is dropped here
    }
    
It might be surprising that `foo` and `bar` would have different
lifetimes here.

### Give up on rules?

An alternative then is to drop the idea of a rule and to basically say
that we use inference to decide how long to keep a temporary around.
Basically, we will infer a suitable lifetime (subject to the maximal
constraint) such that the rvalue outlives all existing pointers, and
free it after that lifetime expires.  From a user's point of view, I
think this means that you don't get a hard guarantee about when the
dtor runs.  Essentially, values will get dropped sometime between when
the last reference to them goes out of scope and the maximal
constraint of the innermost enclosing loop/function body.

The main difference between using inference and using the "DWIM" rule
from the first section is that inferences makes certain code forms
possible that the DWIM rule does not support.  For example, you could
write:

    let x = match foo() {
        Some(ref y) => y,
        None => &0
    };

Here, the call to `foo()` yields a result which will be stashed on the
stack.  Under the DWIM rule, this result would live only as long as
the `let` statement itself.  Under inference, though, we can see that
the user creates a reference into this value and that it is assigned
to `x`, so the rvalue would live at least until `x` goes out of scope
(same with the `&0` rvalue that occurs in the `None` case).

### So what should we do?

I don't know.  To be honest, any one of these alternatives seems
viable.  The DWIM rule is probably the most work, because we already
have to do region inference anyhow.  The simple rule is probably too
simple and will end up being more surprising than either of the
others, despite its simplicity.  Inference is the most flexible but
gives the weakest *guarantees* (though in practice I think it would be
fairly predictable).  I lean towards inference.

There is a related question.  Right now, if you create a pointer into
the interior of a managed box, borrowck will ensure that this box
remains rooted for the lifetime of that pointer.  This seems to be
more-or-less the same thing as ensuring that an rvalue's stack slot
lives long enough to outlive any pointers into it.  So perhaps we can
subject such "auto-rooting" to a similar rule as rvalue references; or
maybe managed data is different.  It is called "managed" for a reason,
after all.


