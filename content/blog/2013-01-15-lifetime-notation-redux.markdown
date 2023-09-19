---
layout: post
title: "Lifetime notation redux"
date: 2013-01-15 08:34
comments: true
categories: [Rust]
---

In a [previous post][pp] I outlined some of the options for updating our
lifetime syntax.  I want to revist those examples after having given
the matter more thought, and also after some discussions in the
comments and on IRC.

My newest proposal is that we use `<>` to designate lifetime
parameters on types and we lean on semantic analysis (the resolve
pass, more precisely) to handle the ambiguity between a lifetime name
and a type name.  Before I always wanted to have the distinction
between lifetimes and types be made in the parser itself, but I think
this is untenable.  This proposal has the advantage that the most
common cases are still written as they are today.

Here is the example from the previous post in my proposed notation:

    struct StringReader<&self> {
                     // ^~~~~ Lifetime parameter designated with &
        value: &self/str,
            // ^~~~~~~~~ Same as today.
        count: uint
    }
    
    impl StringReader {
        fn new(value: &self/str) -> StringReader<&self> {
                                 //              ^~~~~
                                 // Interpreted as a lifetime reference due to
                                 // the declaration of StringReader, which states
                                 // that first parameter is a lifetime.
            StringReader { value: value, count: 0 }
        }
    }
    
    fn value(s: &v/StringReader<&v>) -> &v/str {
             // ^~~~~~~~~~~~~~~~~~~     ^~~~~~
             // As today, lifetime names that appear in a function declaration
             // do not have to be declared anywhere and are implicitly scoped
             // to the containing function declaration.
        return s.value;
    }

    fn remaining(s: &StringReader<&> -> uint {
                 // ^~~~~~~~~~~~~~~~
                 // A bare & in a fn decl means "use a fresh name",
                 // so this is equivalent to &x/StringReader<&y>.
                 // This may be the right thing, see Option 2 below.
        return s.value.len() - s.count;
    }
    
What follows are miscellaneous notes and thoughts.  There are a few
options that could be tweaked, which I have noted.
    
### Considerations

The only way I have found to distinguish lifetime names purely in the
parser that is also visually appealing is to use braces to designate
lifetimes (options 7 and 8 in my [previous post][pp]).  As a reminder,
the impl of `StringReader` would look like:

    impl StringReader {
        fn new(value: &{self} str) -> StringReader{self} {
            StringReader { value: value, count: 0 }
        }
    }

The major problem here is that, as bstrie pointed out on IRC, it's
ambiguous: the `{self}` which appears in the return type could be
interpreted as the function body.  His proposed fix was to use
whitespace sensitivity, so that `StringReader{self}` and `StringReader
{self}` are parsed differently, but whitespace sensitivity is
something we have always tried to avoid.

I personally find it appealing to use `<>` both for lifetime and type
parameters, because I think it gives the right intution.  A
lifetime-parameterized declaration is just like a type-parameted
declaration with regard to how it works in the type system.

**OPTION 1:** I opted to include `&` in the lifetime parameters to a
type for consistency (this way, a lifetime name is always preceded by
`&`).  However, they are not strictly necessary and they are visually
heavy.  We could remove them, which would mean you have
`&v/StringReader<v>` and `StringReader<self>` and not
`&v/StringReader<&v>` and `StringReader<&self>`.  However, the default
would still have to be written `&`, so you'd still have
`StringReader<&>`.

### The default lifetime &

In this proposal, the "default lifetime" `&` would only be usable
inside a function declaration or function body.  In a function
declaration, it means "use a fresh lifetime.  In the function body it
means "use inference".

**OPTION 2:** It would be possible to make `&` a little smarter, as it
is today.  Today it means "use a fresh name unless `&` appears on a
nested type, then use the lifetime you are nested within".  If we took
that interpretation, then `&StringReader<&>` would be equivalent to
`&x/StringReader<&x>` and not `&x/StringReader<&y>`.  This is more
likely to be what the user wanted, though I don't think it makes much
difference in practice.  I'd probably just want to experiment a bit
here: start with the simpler version, as I proposed here, and then see
how many type errors we get

**OPTION 3:** We could also allow users to leave off the `<>` if the
only parameter is a lifetime parameter, in which case it would be
equivalent to `<&>`.  This means that you could write `&StringReader`
instead of `&StringReader<&>`.

**OPTION 4:** The one place that I opted to eschew explicit declarations
is on functions.  If we wanted, we could always require that all named
lifetimes be declared, which would mean that the function `value()`
above would be written:

    fn value<&v>(s: &v/StringReader<v>) -> &v/str {
        return s.value;
    }

I can't decide about this option.  It strikes me as a reasonably
simple story, which appeals to me, but it's also fairly heavyweight.

### How complex can it get?

**UPDATE**: Per bstrie's request, here is an example of a type that
uses both lifetime and type parameters with trait bounds:

    struct Foo<&self, T: Reader+Eq> {
        value: &self/T,
        count: uint
    }
    
    fn operate<R: Reader+Eq>(f: Foo<&, R>)
    {
        ...
    }


[pp]: {{< baseurl >}}/blog/2012/12/30/lifetime-notation/
