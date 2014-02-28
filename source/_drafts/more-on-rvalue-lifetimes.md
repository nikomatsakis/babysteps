So I recently landed my work on Rvalue Lifetimes. In the end, I opted
for an approach that eschews inference. The rules governing how long a
temporary will live are entirely based on syntax. I was able to
compile the vast majority of existing code without changes, and modulo
some small modifications I have in mind, I am happy with the alorithm,
though I expect we may wind up generalizing to one based on inference
at some point. I wanted to write up a blog post spelling out the
rules. This text is a kind of rough draft for what should appear in
the Rust manual.

<!-- more -->

### Summary of the rules

The basic idea of the rule is that most temporaries live until the
innermost enclosing *statement* or *conditional expression* (a
conditional expression is one that does not always execute; so, for
example, `rhs` in `lhs && rhs` is considered conditional, since it
only executes if `lhs` is false).

However, there are some exceptions to this rule. The most notable
is that temporaries in `let` initializers may live until the
innermost enclosing block. The precise rules for this are somewhat
complicated, but intuitively they cover two cases:

1. Rvalues that are assigned to `ref` patterns (e.g., `bar()` in `let
   ref foo = bar()`).
2. Explicitly borrowed rvalues, where the resulting borrow is stored
   into a local variable (e.g., `bar` in `let foo = bar()`).
   
The idea here is that, in both cases, the user is clearly creating a
pointer to the rvalue that will live as long as the innermost
enclosing block, and hence using the default lifetime (just the `let`
statement) is a guaranteed compilation error.

Another exception is that the temporaries created in the condition
expression in an `if` or `while` loop are freed immediately. In other
words, if one writes code like:

    if some_test(&foo()) { ... } else { ... }
    while some_test(&foo()) { ... }
    
Then the temporary resulting from `&foo()` will be freed before
entering then/else blocks or the while loop body. Note that this
condition expression is not *itself* conditional. FIXME

### Design goals

The design was attempting to meet several design goals:

1. **Predictable.** When asked, most users said that they did not want
   the results of region inference to decide when destructors would
   execute. This is certainly the most limiting (and perhaps
   controversial) of the various design criteria; luckily, it can also
   be lifted in a backwards compatible way.
2. **Intermediate temporaries should not outlive the enclosing
   statement.** Some smart pointer types, notably `RefCell`, monitor
   correct usage patterns via temporary values whose destructors are
   used to update usage flags. It is important that such temporaries
   do not live too long. For example, a common use of the `RefCell`
   type might resemble the following:
   
       let v = my_map.borrow().get().find_copy(...)
       //      ^~~~~~~~~~~~~~^ Temporary of interest
   
   In this case, `borrow()` returns a temporary object whose
   destructor will reset the borrow flags. This temporary object is
   implicitly borrowed by `get()` and hence the compiler must decide
   its lifetime. I think it's important that in cases like this the
   destructor runs before the next statement begins, since otherwise
   the table `my_map` would remain borrowed for the entire block,
   which is both surprising and inconvenient.
3. **But temporaries assigned into variables should live as long as
   the block.** Whenever possible, though, we should identify
   temporaries that are unquestionably being stored into a variable on
   the stack and make them live as long as the enclosing block. This
   permits code like `let foo = &HashMap::new()` or `let ref foo =
   HashMap::new()` and so on. You might wonder why anyone would do
   this, rather than writing `let foo = HashMap::new()` and just
   taking ownership of the hashmap. There are a variety of reasons,
   but one of the important uses turns out to be in macros like
   `assert_eq!($l, $r)`, where the arguments `$l` and `$r` could be
   either lvalues or rvalues. If `assert_eq` had a `let` statement
   like `let left = $l` and `$l` wound up being an lvalue, that might
   move from the lvalue, which is unexpected. Writing `let left = &
   $l` allows us to borrow lvalues and produce temporary stack slots
   for rvalues.
4. **Translatable without zeroing or infinite stack space.** One more
   subtle requirement is that the compiler should be able to determine
   what destructors need to run without the use of any runtime checks
   and with finite stack space. Without some caution, both of these
   rules can be violated. In particular, imagine that we said that all
   temporaries are destroyed upon exit of the enclosing statement.
   Now consider the following expression 
   
       some_cond && my_map.borrow().get().find_copy(...)
       //           ^~~~~~~~~~~~~~^ Temporary of interest
   
   As before, the `borrow()` method returns an object whose address is
   taken by the `get()` routine. Therefore, we must decide when its
   destructor runs. The difference is that here this code only runs
   *conditionally* -- if `some_cond` is true, it will never run at
   all. That means that, when we exit the statement, we do not know
   whether there is a temporary that we need to destroy or not, unless
   we keep some sort of flag and check it. In a similar vein, we have
   to be sure that temporaries never outlive any repeating block
   (i.e., a loop body), since that would mean that the number of
   temporaries to be freed would not be known statically.
   

This
expression is not, strictly speaking, conditional, 

However, temporaries in `let` initializers may live until the
innermost enclosing block. Informally, the 

However, some temporaries in `let` initializers may live until
the innermost enclosing block. 

However, there are some notable exceptions. Most importantly, rvalue
temporaries that appear in `let` initializer expressions may be
assigned the lifetime of the innermost enclosing *block*

1. Rvalues that appear after an explicit borrow expression 
2. Rvalues assigned to a `let` whose pattern includes `ref`
   bindings are 

I did some experimentation with different algorithms to determine
rvalue lifetimes, and I think I've settled on the one I prefer.  The
algorithm can be summarized, at a high level, as:

> The lifetime of an rvalue temporary is the innermost enclosing
> statement, unless the temporary is a `let` initializer, in which
> case it is the innermost enclosing block.

This is more-or-less the C++ rule, at least in spirit, if not in the
particulars. Of course, the real trick lies in
deciding when a temporary is "being assigned into a variable". It took
me a while to stumble on the proper definition.

The definition I am currently using can be defined using a grammar:

    let <pattern> = E
    E = &E
      | *E
      | E[...]
      | {...; E}
      | E.f
      | (E)
      | <expr>
      
Let initializers are the (largest applicable) set of expressions
`E`. This always includes the outermost expression, but may also
include subexpressions in particular cases. Let me give a few examples
that will hopefully clarify matters. In the examples that follow, I'll
use underlines to indicate temporaries whose lifetimes are the
enclosing block, not the enclosing statement:

0. `let v = foo()`. This is kind of a "trick example", because in fact
   there is no temporary created here at all. In this case, the rvalue
   `foo()` is simply stored into `v` by value.
   
1. `let ref v = foo()`. Here, we have a ref binding, and so we must
   introduce a temporary to store the value `foo()` so that we can take
   its address. Since `foo()` is the outermost expression, it is considered
   a let initializer, and hence the lifetime of this temporary is the
   innermost enclosing block.

2. `let v = &foo()`. In this case, the outermost enclosing expression is
   the borrow expression `&foo()`. Since the `&` operator is being applied
   to an rvalue, a temporary will be created. The grammar above includes
   the case `E = &E`, so `foo()` is considered a "let initializer"
   as well, and thus the lifetime of its temporary will be the enclosing
   block.

3. `let v = bar(&foo())`. Here the `&foo()` expression will again
   create a temporary, but the lifetime of this temporary will only be
   the enclosing statement. The reason for this is that there is no
   case `E = f(..., E, ...)` in the grammar above (i.e., there is no
   way to expand out `E` such that includes the `&foo()` in this
   example).
   
4. `let v = &foo().x`. If `foo()` returns a by-value structure or
   owned pointer, a temporary will be needed so that we can keep this
   value live while we take the address of its field `x`. Such a
   temporary would have the lifetime of the entire block because `E`
   can be expanded as follows:
   
       E_0 = &E_1
       E_1 = E_2.f
       E_2 = foo()
       
5. `let v = { let a = ...; &foo(a).x }`. This example highlights that
   a block can be introduced to create intermediate values; temporaries
   that are needed in the tail expression of that block still have increased
   lifetime.
   
6. 

**Some counterintuitive examples.** The way I've written the code
there are a few examples I consider counterintuitive. I'm not yet sure
how best to resolve these problems:

1. `let v = foo().f`. 

Actually, maybe the real question is how to interpret a pattern
binding applied to an rvalue. I have so far rationalized it by only
defining pattern bindings applied to lvalues, and then saying binding
against an rvalue is as if you introduced a temporary. But maybe this
is not the best rule. Maybe we should say that bindings applied to
rvalues introduce new temporaries.

    let ref x = <rvalue>;   <-- lifetime of `x` always innermost block?
    let ref x = <rvalue>.x; <-- this would just be an error??
    let x = &<rvalue>.x;
    
    
ALSO:

  opt_shard is creepy


LET INITIALIZER TEMPORARY:

  - Given the following grammars:
    - E& = &ET
         | &E&j
         | StructName { ..., f: E&, ... }
         | [ ..., E&, ... ]
         | ( ..., E&, ... )
         | {...; E&}
    - P& = ref X
         | StructName { ..., P&, ... }
         | [ ..., P&, ... ]
         | ( ..., P&, ... )
         | ~P&
         | box P&
    - ET = <rvalue>
         | *ET
         | ET[...]
         | ET.f
         | (ET)
  - If P& matches pattern and ET matches initializer, or if `E&`
    matches initializer, then `<rvalue>` has an extended temporary
    lifetime. Note that these two cases are mutually exclusive.
  - Note that `[]` patterns work more smoothly post-DST.

An
rvalue is considered to be a "let initializer" if it either:

1. Appears *directly* as the right-hand side of a let statement.
   For example, the expression `E` in `let pat = E`.
2. The expression `E` is a subexpression of some other
   expression meeting one of the following forms:

       *E
       E[...]
       {...; E}
       E.f
       (E)
   

I arrived at the rule after some amount of trial-and-error,
essentially: I implemented many variations, and saw what kinds of
compilations errors I got when building












I was thinking more about rvalue lifetimes. I still think that one of
the variations of the C++ rule that I proposed is probably the way to
go, but I am beginning to change my opinion about which one it should
be. In particular, I am thinking that maybe Variation A makes the most
sense: we treat the lifetimes introduced for `let` bindings specially,
but otherwise all temporaries are parented to the innermost enclosing
statement or conditional block. This introduces an asymmetry between
borrow expressions and `let ref` that I initially found displeasing.
However, I was thinking of more examples and I started to think that
the asymmetry may actually make sense.

In particular, imagine some code like the following:

    {
        ...
        let value = map.find(&create_key());
        ...
    }
    
Reading this code, I intuitively expect the temporary created for
`create_key()` to be freed at the end of the statement. However, if we
treat explicit `&` expressions specially, it will not be. This seems
surprising.

Using this interpretation also helps to avoid one particular oddness
concerning tail expressions. In particular, `let` statements cannot
appear in tail position of a block, but `&` expressions can. As a result,
I was finding it tricky to decide what the lifetime of an `&` temporary
ought to be given a bit of code like the following:

    {
        ...
        let value = map.find({ { { &create_key() } } });
        ...
    }
    
    
If `&` expressions are not special, then this temporary will be freed
at the end of the call to `map()`. Otherwise, though, I guess that the
right result would be for it to be freed at the end of the block that
encloses `value`. Defining this formally proved a bit thorny, though:
you basically have to walk up the scopes until you find an enclosing
statement, and then use the block that encloses that statement, unless
you find a conditional block, in which case you should use that:

    {
        ...
        if cond { &create_key() } else { ... }
        ...
    }

It occurs to me that in my previous post I didn't describe the
situation with "conditional blocks" correctly or in sufficient
detail. The situation is that when we generate a temporary

There are two kinds of blocks that can cause trouble at code
generation time. The first is a loop block:

    loop {
         ... &create_key() // type error, but never mind
    }

In this case, 
