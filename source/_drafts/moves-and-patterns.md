Rust patterns are somewhat in migration.  We are making more explicit
but also more powerful.  It used to be that a match statement always
created implicit pointers into the value being matched.  The new way
will only create pointers if you label the binding as a `ref` binding.
By default, values will be *extracted* from the value being matched.
The problem is that there are two ways to do extractions: copying and
moving.  Right now the language is in an uncomfortable and
inconsistent state with regard to whether a binding moves or copies
the value it is bound to.  What I'd like to discuss here is a proposal
to simplify and consolidate these rules.  Actually I'm going to
describe two possibilities, both consistent.  I am not sure which is
preferable.

### Proposal #1: Lvalues vs Rvalues

This first idea is closer to what we have today.  Matching an lvalue,
(an assignable location, like `a`, `*a.b`, or `a.b[c]`), would have
distinct semantics from matching an rvalue (something like `a + b` or
`a(b)`).

When matching an lvalue, default bindings (no label) would *copy* the
value being bound.  When matching an rvalue, default bindings would
*move* the value being bound.  However, in both cases, if the pattern
crosses into the contents of an `@T` or `&T` pointer, by-value matches
would have to be moves.

One open question is what to do with `ref` bindings.  When matching an
lvalue, the answer is fairly straightforward.  `ref` bindings can
reach into the value being matched.  When matching an rvalue, however,
the question is less clear.  `ref` bindings in that case could be
forbidden altogether, or we could permit them.  If `ref` bindings are
permitted, that implies that the semantics of the match are "as if"
the rvalue being matched is first stored into a temporary, and there
is an interesting question as to
[how long that temporary should live][rvlt].

So, here is an example of matching an lvalue expression, and its
semantics.  For the purposes of illustration, I gave two patterns,
though only the first would ever match in pratice:

    let x = Foo { f: ... };
    match x { // an lvalue
        Foo {f: v} => { /* equivalent to v = x.f */ }
        Foo {f: ref v} => { /* equivalent to v = &x.f */ }
    }

Here is the same example, but matching against an rvalue:
    
    match mk_foo() { // an rvalue
        Foo {f: v} => { /* moves `v`, does not copy */ }
        Foo {f: ref v} => { /* if permitted, equiv. to &mk_foo().f */ }
    }

Interestingly, an expression like `mk_foo().f` would always copy, so
moving out of a field like that requires a pattern.  This means
that the following two lets are not equivalent:

    let Foo {f: v} = mk_foo();
    let v = mk_foo().f;
    
I find this somewhat unfortunate.    

### Proposal #2: Matching only rvalues

### Proposal #3: Matching only lvalues
