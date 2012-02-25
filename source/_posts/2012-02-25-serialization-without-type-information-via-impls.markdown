---
layout: post
title: "Serialization without type information via impls"
date: 2012-02-25 07:40
comments: true
categories: [Rust]
---

My current implementation of the auto-serialization code generator
requires full type information.  This is a drag.  First, macros and
syntax extension currently run before the type checker, so requiring
full type information prevents the auto-serialization code from being
implemented in the compiler, as it should be.  At first I wanted to
change how the compiler works to provide type information, but after
numerous discussions with pcwalton and dherman, I've come to the
conclusion that this is a bad idea: it requires exposing an API for
the AST and for type information and introduces numerous other
complications.

I've come up with an alternative design that seems to solve this
problem.  It also addresses another concern I had: how do you allow
users to customize the (de)-serialization for a given type without
forcing them to customize (de)-serialization for all types?  One
interesting aspect of this plan, though, is that it requires
non-hygienic macros.

My basic plan is to allow type declarations to be decorated with a tag
like `#[auto_serialize]`, which will look something like this:

    #[auto_serialize]
    type spanned<T> = { node: T, span: span };
    
Here I have deliberately chosen a generic type declaration to use as
my running example because (as we shall see) they are particularly
complex.  Then a pass will run in the compiler which finds all types
annotated with `#[auto_serialize]` and generates serialization and
deserialization code that live alongside the declaration.  Let's look
first at serialization and then at deserialization: as we shall see,
the solution that we use for serialization doesn't quite work for
deserialization, so we have to handle them slightly differently.

## Serialization

My original concern was, without type information, how do I know how
to serialize the contents of the type?  After all, all I have is the
AST, so I know some names but that's it.  In the case of `spanned<T>`,
for example, I know there are two fields, one with the type `T` and
one with the type `span`.  I can figure out that `T` is a type
parameter, but I don't know that `span` is an import of
`syntax::codemap::span`, and I certainly don't know that
`syntax::codemap::span` is defined as a record itself.

So how do I generate code to serialize a type like `T` or `span`
without knowing anything about what that type is?  It turns out that we
have a nice language tool for doing that: ifaces and impls (a.k.a.,
typeclasses).

So, for `spanned<T>`, I will generate something like:

    impl of serializable<T: serializable> for spanned<T> {
        fn serialize<S: serialization::serializer>(s: S) {
            s.emit_rec {||
                s.emit_rec_field("node", 0u) {||
                    self.node.serialize(s);
                }
                s.emit_rec_field("span", 1) {||
                    self.span.serialize(s);
                }
            }
        }
    }

You can see that generating this code does not require any information
that is external to the type declaration.  It just assumes that, for
example, there will be a suitable implementation of the `serialize()`
method for the field `self.span`.  Similarly, by parameterizing the
`impl` with the type `T` and specifying that `T` must itself be
serializable, we can make the same assumption for the field
`self.node`.  Pretty nifty.

One very appealing aspect of this is that if I wanted to make custom
serialization code for the type `span`, say, I could just write my own
`impl` for the serialize method.  The auto-generated code for
serializing `spanned<T>` would then link to my custom code, no
problem.  Similarly, I can write custom code that uses auto-generated
code without difficulty.

## Deserialization

However, this approach does not work for deserialization.  After all,
we can't invoke something like `data.deserialize(d)`, as the data is
what we are trying to produce!

Therefore, we will generate a different pattern for deserialization.
It will look something like this:

    fn deserialize_spanned<D: serialization::deserializer,T>
       (d: D, t: fn(D) -> T) -> spanned<T> {
       
       d.read_rec {||
           {
               node: d.read_rec_field("node", 0u) {|| t() },
               span: d.read_rec_field("span", 1u) {|| deserialize_span(d) }
           }
       }
    }

Here, we generate a `deserialize_X()` function where `X` is the
(unqualified) name of the type being deserialized. The number of
arguments expected by this `deserialize_X()` function varies: the
first argument is always a deserializer, but then there are additional
arguments for any type arguments.  These parameters are dealt with
implicitly when using ifaces and impls, but since that machinery won't
work for us we have to thread it through manually now.

More interesting than the case of the field `node`, actually, is the
field `span`: here, we don't even *try* resolve the identifier, we
just generate a dangling reference to a function `deserialize_span()`
and we assume that the user has either imported this function or
defined it locally.  This is where the lack of hygiene is required.

Some other cases that don't appear here:

- if the type of a field is a path like `a::b::c`, then we generate a
  call to a function like `a::b::deserialize_c(d)`.
  
- if the type of a field is parameterized, like `spanned<item_>`, then
  we generate a call like `deserialize_spanned(d, {||
  deserialize_item_(d) })`, where the sugared closure `{||...}`
  represents the code to unpack the type argument.
  
## Feedback

I am 100% positive people have solved this problem before in a million
ways, no doubt including this one.  Am I missing something obvious?
Also, would it be better to avoid using iface/impl for serialization
and just generate functions named `serialize_X()` just as I do with
`deserialize_X()`? I thought it'd be nice if the serialization were as
natural to write as possible, but I guess that if you have to write
custom serialization code, you generally need custom deserialization
code too, so it doesn't help so much.

