In a previous post I outlined some of the options for updating our
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
        fn new(value: &self/str) -> StringReader<self> {
                                 //              ^~~~
                                 // Interpreted as a lifetime reference due to
                                 // the declaration of StringReader, which states
                                 // that first parameter is a lifetime.
            StringReader { value: value, count: 0 }
        }
    }
    
    fn value(s: &v/StringReader<v>) -> &v/str {
              // ^~~~~~~~~~~~~~~~~     ^~~~~~
              // As today, lifetime names that appear in a function declaration
              // do not have to be declared anywhere.
        return s.value;
    }

    fn remaining(s: &StringReader<&> -> uint {
                 // ^~~~~~~~~~~~~~~~
                 // A bare &`in a fn decl means "use a fresh name",
                 // so this is equivalent to &x/StringReader<&y>.
        return s.value.len() - s.count;
    }
    
What follows are miscellaneous notes and thoughts.  There are a few
options that could be tweaked, which I have noted.
    
### Considerations

There was only one option from my previous post which was visually appealing
*and* which distinguished lifetime names purely in the parser, and that
was using braces.  As a remind, the impl of `StringReader` would look like:

    impl StringReader {
        fn new(value: &{self} str) -> StringReader{self} {
            StringReader { value: value, count: 0 }
        }
    }

The major problem here is that, as bstrie pointed out on IRC, it's
ambiguous: the `{self}` which appears in the return type could be
interpreted as the function body.  His proposed fix was to use
whitespace sensitivity, so that `StringReader{self}` and `StringReader
{self}` are parsed differently.

I personally find it appealing to use `<>` both for lifetime and type
parameters, because I think it gives the right intution.  A
lifetime-parameterized declaration is just like a type-parameted
declaration with regard to how it works in the type system.

**OPTION:** I opted not to include `&` in the lifetime parameters to
type because they seemed visually quite heavy and unnecessary.  So you
have `&v/StringReader<v>` and `StringReader<self>` and not
`&v/StringReader<&v>` and `StringReader<&self>`.  Perhaps this is
confusing, though, because lifetime names are otherwise always
preceded by an `&` (note that regardless of whether we include `&` or
not, it is always ambiguous at parse time whether it refers to a type
or a lifetime name).

### The default lifetime &

In this proposal, the "default lifetime" `&` would only be usable
inside a function declaration or function body.  In a function
declaration, it means "use a fresh lifetime.  In the function body it
means "use inference".

**OPTION:** It would be possible to make `&` a little smarter, as it
is today.  Today it means "use a fresh name unless `&` appears on a
nested type, then use the lifetime you are nested within".  If we took
that interpretation, then `&StringReader<&>` would be equivalent to
`&x/StringReader<&x>` and not `&x/StringReader<&y>`.  This is more
likely to be what the user wanted, though I don't think it makes much
difference in practice.  I'd probably just want to experiment a bit
here: start with the simpler version, as I proposed here, and then see
how many type errors we get

**OPTION:** We could also allow users to leave off the `<>` if the
only parameter is a lifetime parameter, in which case it would be
equivalent to `<&>`.  This means that you could write `&StringReader`
instead of `&StringReader<&>`.

**OPTION:** The one place that I opted to eschew explicit declarations
is on functions.  If we wanted, we could always require that all named
lifetimes be declared, which would mean that the function `value()`
above would be written:

    fn value<&v>(s: &v/StringReader<v>) -> &v/str {
        return s.value;
    }

I can't decide about this option.  It strikes me as a reasonably
simple story, which appeals to me, but it's also fairly heavyweight.


