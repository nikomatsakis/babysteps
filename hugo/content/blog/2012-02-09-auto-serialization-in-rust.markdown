---
categories:
- Rust
comments: true
date: "2012-02-09T00:00:00Z"
slug: auto-serialization-in-rust
title: Auto-serialization in Rust
---

I've been working on implementing [Cross-Crate Inlining][cci].  The
major task here is to serialize the AST.  This is conceptually trivial
but in practice a major pain.  It's an interesting fact that the more
tightly you type your data, the more of a pain it (generally) is to
work with in a generic fashion.  Of functional-ish languages that I've
used, Scala actually makes things relatively easy by using a
combination of reflection and dynamic typing (interfaces like
[`Product`][product] come to mind). 

Anyway, Rust does not (yet?) have reflection, but I have been working
on a program which will autogenerate the serialization code for our
AST based on the type definitions itself.  Normally, I would probably
do this with some Python program and a bunch of hacky regular
expressions.  But instead I am taking advantage of one of Rust's nicer
(and somewhat unusual, although becoming less so) features: the fact
that the Rust compiler is itself a library. *(An aside: I plan to
implement this serialization code as a syntax extension or macro once
those systems mature.)*

To use `serializer`, you provide it with a crate file and a set of
type names.  It will then generate Rust code that serializes instances
of those types. Internally, it invokes the compiler to parse and type
check the crate, using the `compile_upto()` function, which allows you
to compile a given input up until a certain point (in this case, up
until the type checking phase has completed).

*An aside:* This is the point where the beauty of crate files becomes more
apparent: a crate is a self-contained specification that not only
contains a listing of the source modules and so forth, but also the
external crates that are required, default compilation options, etc.
Having all of this mess encapsulated in a crate means that it is
trivial for a tool like `serializer` to recreate the compilation
environment for your package: just provide it with a crate file.  If
this were a C program, you'd also have to supply a random smattering
of gcc options, which you would in turn have to figure out how to
extract from your makefile, not to mention the makefiles from external
packages that you are using.  Ugh.

Once `serializer` has parsed and type-checked your source, it is
provided with a crate AST and a type context (`ty::ctxt`).  Using
these two things, it's fairly straightforward to locate the
definitions for the types we are supposed to serialize and walk over
them, generating code as we go.

The actual code works by walking `ty::t` instances.  `ty::t` is the
type used in the Rust compiler to represent types.  This is distinct
from `ast::ty`, which is the syntax tree that represents a type.
`ty::t` is modeled after the type system in the abstract, which makes
it easier to work with.  The other reason to walk `ty::t` instances
and not `ast::ty` is that there is no AST available for types defined
in external crates (such as `option::t`, defined in `libcore`).

Basically, for each unique `ty::t` that we encounter we generate a function
of the form:

    fn serialize<C: serialization::ctxt>(cx: C, t: T) {
        ...
    }

Here `T` is the type represented by the `ty::t`.  The variable `cx` is
a serialization context.  This is defined using an interface
`serialization::ctxt`, which looks like so:

    mod serialization {
        iface ctxt {
            fn emit_u64(x: u64);
            fn emit_i64(x: i64);
        
            fn emit_record(f: fn());
            fn emit_field(f_name: str, f_id: uint, f: fn());

            fn emit_enum(e_name: str, f: fn());
            fn emit_variant(v_name: str, v_id: uint, f: fn());
            
            ...
        }
    }

So, for example, the serialization function for a type `{x: uint, y: uint}`
would look something like:

    fn serialize1<C: serialization::ctxt>(cx: C, &&v: {x: uint, y: uint}) {
        cx.emit_record {||
            cx.emit_field("x", 0) {||
                cx.emit_u64(v.x as u64);
            }
            cx.emit_field("y", 1) {||
                cx.emit_u64(v.y as u64);
            }
        }
    }

Now, to deserialize, we generate similar code for a deserialization interface:

    fn deserialize1<C: deserialization::ctxt>(cx: C) -> {x: uint, y: uint} {
        cx.read_record {||
            let x = cx.read_field("x", 0) {||
                cx.read_u64() as uint
            }
            let y = cx.read_field("y", 1) {||
                cx.read_u64() as uint
            }
            {x: x, y: y}
        }
    }

The deserialization interface looks like:

    mod deserialization {
        iface ctxt {
            fn read_u64() -> u64;
            fn read_i64() -> i64;
        
            fn read_record<T>(f: fn() -> T) -> T;
            fn read_field<T>(f_name: str, f_id: uint, f: fn() -> T) -> T;

            fn read_enum<T>(f: fn(uint) -> T);
            
            ...
        }
    }

A somewhat more interesting case concerns enums.  Let's consider the
enum `option<R>` where `R` is the record type we've been working with.
It would be serialized as:

    type R = {x: uint, y: uint};
    fn serialize2<C: serialization::ctxt>(cx: C, &&v: option<R>) {
        cx.emit_enum("std::option::t<R>") {||
            alt v {
                none {
                    cx.emit_variant("std::option::none", 0u) {||
                    }
                }
                some(r) {
                    cx.emit_variant("std::option::some, 1u) {||
                        serialize1(cx, r); // link to the previous code we saw
                    }
                }
            }
        }
    }

The deserializer meanwhile would look like:

    fn deserialize2<C: deserialization::ctxt>(cx: C) -> option<uint> {
        cx.read_enum {|v_id|
            alt v_id {
                0u { // std::option::none
                    std::option::none
                }
                
                1u { // std::option::some
                    std::option::some(deserialize1(cx))
                }
                
                _ {
                    fail #fmt["Unexpected discriminant %u for option::option",
                        v_id];
                }
            }
        }
    }

[cci]: https://github.com/mozilla/rust/issues/1765
[product]: http://www.scala-lang.org/api/current/index.html#scala.Product
