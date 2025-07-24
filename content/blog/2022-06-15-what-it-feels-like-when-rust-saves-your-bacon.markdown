---
layout: post
title: What it feels like when Rust saves your bacon
date: 2022-06-15T19:34:00-0400
---

You've probably heard that the Rust type checker can be a great "co-pilot", helping you to avoid subtle bugs that would have been a royal pain in the !@#!$! to debug. This is truly awesome! But what you may not realize is how it feels *in the moment* when this happens. The answer typically is: **really, really frustrating!** Usually, you are trying to get some code to compile and you find you just can't do it. 

As you come to learn Rust better, and especially to gain a bit of a deeper understanding of what is happening when your code runs, you can start to see when you are getting a type-check error because you have a typo versus because you are trying to do something fundamentally flawed. 

A couple of days back, I had a moment where the compiler caught a really subtle bug that would've been horrible had it been allowd to compile. I thought it would be fun to narrate a bit how it played out, and also take the moment to explain a bit more about temporaries in Rust (a common source of confusion, in my observations).

## Code available in this repository

All the code for this blog post is available in a [github repository][repo].

[repo]: https://github.com/nikomatsakis/2022-06-15-blogpost/

## Setting the scene: lowering the AST

[snippet-before]: https://github.com/nikomatsakis/2022-06-15-blogpost/blob/f280f91e9be03d37f273acf13502ef7dc1015db8/examples/a.rs
[a-ast-mod]: https://github.com/nikomatsakis/2022-06-15-blogpost/blob/f280f91e9be03d37f273acf13502ef7dc1015db8/examples/a.rs#L4
[a-traitref]: https://github.com/nikomatsakis/2022-06-15-blogpost/blob/f280f91e9be03d37f273acf13502ef7dc1015db8/examples/a.rs#L12-L15

In the compiler, we first represent Rust programs using an [Abstract Syntax Tree (AST)](https://doc.rust-lang.org/nightly/nightly-rustc/rustc_ast/ast/index.html). I've prepared a [standalone example][snippet-before] that shows roughly how the code looks today (of course the real thing is a lot more complex). The AST in particular is found in the [ast module][a-ast-mod] containing various data structures that map closely to Rust syntax. So for example we have a `Ty` type that represents Rust types:

```rust
pub enum Ty {
    ImplTrait(TraitRef),
    NamedType(String, Vec<Ty>),
    // ...
}

pub struct Lifetime {
    // ...
}
```

The `impl Trait` notation references a [`TraitRef`][a-traitref], which stores the `Trait` part of things:

```rust
pub struct TraitRef {
    pub trait_name: String,
    pub parameters: Parameters,
}

pub enum Parameters {
    AngleBracket(Vec<Parameter>),
    Parenthesized(Vec<Ty>),
}

pub enum Parameter {
    Ty(Ty),
    Lifetime(Lifetime),
}
```

Note that the parameters of the trait come in two varieties, angle-bracket (e.g., `impl PartialEq<T>` or `impl MyTrait<'a, U>`) and parenthesized (e.g., `impl FnOnce(String, u32)`). These two are slightly different -- parenthesized parameters, for example, only accept types, whereas angle-bracket accept types or lifetimes.

After parsing, this AST gets translated to something called [High-level Intermediate Representation (HIR)](https://doc.rust-lang.org/nightly/nightly-rustc/rustc_middle/hir/index.html) through a process called *lowering*. The snippet doesn't include the HIR, but it includes a number of methods like [`lower_ty`][a_lower_ty] that take as input an AST type and produce the HIR type:

[a_lower_ty]: https://github.com/nikomatsakis/2022-06-15-blogpost/blob/8232a6ee30e92faa2117dd23ee28d5c145509d92/examples/a.rs#L98-L116

```rust
impl Context {
    fn lower_ty(&mut self, ty: &ast::Ty) -> hir::Ty {
        match ty {
            // ... lots of stuff here
            // A type like `impl Trait`
            ast::Ty::ImplTrait(trait_ref) => {
                do_something_with(trait_ref);
            }

            // A type like `Vec<T>`, where `Vec` is the name and
            // `[T]` are the `parameters`
            ast::Ty::NamedType(name, parameters) => {
                for parameter in parameters {
                    self.lower_ty(parameter);
                }
            }
        }
        // ...
    }
}
```

Each method is defined on this `Context` type that carries some common state, and the methods tend to call one another. For example, [`lower_signature`][a_lower_signature] invokes [`lower_ty`][a_lower_ty] on all of the input (argument) types and on the output (return) type:

[a_lower_signature]: https://github.com/nikomatsakis/2022-06-15-blogpost/blob/f280f91e9be03d37f273acf13502ef7dc1015db8/examples/a.rs#L57-L65

```rust
impl Context {
    fn lower_signature(&mut self, sig: &ast::Signature) -> hir::Signature {
        for input in &sig.inputs {
            self.lower_ty(input);
        }

        self.lower_ty(&sig.output);

        ...
    }
}
```

## Our story begins

[Santiago Pastorino](https://github.com/spastorino/) is working on a refactoring to make it easier to support returning `impl Trait` values from trait functions. As part of that, he needs to collect all the `impl Trait` types that appear in the function arguments. The challenge is that these types can appear anywhere, and not just at the top level. In other words, you might have `fn foo(x: impl Debug)`, but you might also have `fn foo(x: Box<(impl Debug, impl Debug)>)`. Therefore, we decided it would make sense to add a vector to `Context` and have `lower_ty` collect the `impl Trait` types into it. That way, we can find the complete set. 

To do this, we started by adding the vector into this `Context`. We'll store the `TraitRef` from each `impl Trait` type:


```rust
struct Context<'ast> {
    saved_impl_trait_types: Vec<&'ast ast::TraitRef>,
    // ...
}
```

To do this, we had to add a new lifetime parameter, `'ast`, which is meant to represent the lifetime of the AST structure itself. In other words, `saved_impl_trait_types` stores references into the AST. Of course, once we did this, the compiler got upset and we had to go modify the `impl` block that references `Context`:

```rust
impl<'ast> Context<'ast> {
    ...
}
```

Now we can modify the `lower_ty` to push the trait ref into the vector:

```rust
impl<'ast> Context<'ast> {
    fn lower_ty(&mut self, ty: &ast::Ty) {
        match ty {
            ...
            
            ast::Ty::ImplTrait(...) => {
                // 👇 push the types into the vector 👇
                self.saved_impl_trait_types.push(ty);
                do_something();
            }

            ast::Ty::NamedType(name, parameters) => {
                ... // just like before
            }
            
            ...
        }
    }
}
```

At this point, the compiler gives us an error:

```
error[E0621]: explicit lifetime required in the type of `ty`
   --> examples/b.rs:125:42
    |
119 |     fn lower_ty(&mut self, ty: &ast::Ty) -> hir::Ty {
    |                                -------- help: add explicit lifetime `'ast` to the type of `ty`: `&'ast ast::Ty`
...
125 |                 self.impl_trait_tys.push(trait_ref);
    |                                          ^^^^^^^^^ lifetime `'ast` required
```

Pretty nice error, actually! It's pointing out that we are pushing into this vector which needs references into "the AST", but we haven't declared in our signature that the `ast::Ty` must actually from "the AST". OK, let's fix this:


```rust
impl<'ast> Context<'ast> {
    fn lower_ty(&mut self, ty: &'ast ast::Ty) {
        // had to add 'ast here 👆, just like the error message said
        ...
    }
}
```

## Propagating lifetimes everywhere

Of course, now we start getting errors in the functions that *call* `lower_ty`. For example, `lower_signature` says:

```
error[E0621]: explicit lifetime required in the type of `sig`
  --> examples/b.rs:71:18
   |
65 |     fn lower_signature(&mut self, sig: &ast::Signature) -> hir::Signature {
   |                                        --------------- help: add explicit lifetime `'ast` to the type of `sig`: `&'ast ast::Signature`
...
71 |             self.lower_ty(input);
   |                  ^^^^^^^^ lifetime `'ast` required
```

The fix is the same. We tell the compiler that the `ast::Signature` is part of "the AST", and that implies that the `ast::Ty` values owned by the `ast::Signature` are also part of "the AST":

```rust
impl<'ast> Context<'ast> {
    fn lower_signature(&mut self, sig: &'ast ast::Signature) -> hir::Signature {
        //        had to add 'ast here 👆, just like the error message said
        ...
    }
}
```

Great. This continues for a bit. But then... we hit this error:

```
error[E0597]: `parameters` does not live long enough
  --> examples/b.rs:92:53
   |
58 | impl<'ast> Context<'ast> {
   |      ---- lifetime `'ast` defined here
...
92 |                 self.lower_angle_bracket_parameters(&parameters);
   |                 ------------------------------------^^^^^^^^^^^-
   |                 |                                   |
   |                 |                                   borrowed value does not live long enough
   |                 argument requires that `parameters` is borrowed for `'ast`
93 |             }
   |             - `parameters` dropped here while still borrowed
```

What's this about?

## Uh oh...

Jumping to that line, we see this function [`lower_trait_ref`][b_lower_trait_ref]:

[b_lower_trait_ref]: https://github.com/nikomatsakis/2022-06-15-blogpost/blob/f280f91e9be03d37f273acf13502ef7dc1015db8/examples/b.rs#L85-L97

```rust
impl Context<'ast> {
    // ...
    fn lower_trait_ref(&mut self, trait_ref: &'ast ast::TraitRef) -> hir::TraitRef {
        match &trait_ref.parameters {
            ast::Parameters::AngleBracket(parameters) => {
                self.lower_angle_bracket_parameters(&parameters);
            }
            ast::Parameters::Parenthesized(types) => {
                let parameters: Vec<_> = types.iter().cloned().map(ast::Parameter::Ty).collect();
                self.lower_angle_bracket_parameters(&parameters); // 👈 error is on this line
                
            }
        }

        hir::TraitRef
    }
    // ...
}
```

So what's this about? Well, the *purpose* of this code is a bit clever. As we saw before, Rust has two syntaxes for trait-refs, you can use parentheses like `FnOnce(u32)`, in which case you only have types, or you can use angle brackets like `Foo<'a, u32>`, in which case you could have either lifetimes *or* types. So this code is normalizing to the angle-bracket notation, which is more general, and then using the same lowering helper function.

## Wait! Right there! That was the moment!

What?

## That was the moment that Rust saved you a world of pain!

It was? It just kind of seemed like an annoying, and I will say, kind of confusing compilation error. What the heck is going on? The problem here is that `parameters` is a local variable. It is going to be freed as soon as `lower_trait_ref` returns. But it could happen that `lower_trait_ref` calls `lower_ty` which takes a reference to the type and stores it into the `saved_impl_trait_types` vector. Then, later, some code would try to use that reference, and access freed memory. That would sometimes work, but often not -- and if you forgot to test with parenthesized trait refs, the code would work fine for ever, so you'd never even notice.

## How to fix it

Maybe you're wondering: great, Rust saved me a world of pain, but how do I fix it? Do I just have to copy the `lower_angle_bracket_parameters` and have two copies? 'Cause that's kind of unfortunate.

Well, there are a variety of ways you *might* fix it. One of them is to use an *arena*, like the [`typed-arena`](https://crates.io/crates/typed-arena) crate. An arena is a memory pool. Instead of storing the temporary `Vec<Parameter>` vector on the stack, we'll put it in an arena, and that way it will live for the entire time that we are lowering things. [Example C] in the repo takes this approach. It starts by adding the `arena` field to the [`Context`][c_context]:

[c_context]: https://github.com/nikomatsakis/2022-06-15-blogpost/blob/f280f91e9be03d37f273acf13502ef7dc1015db8/examples/c.rs#L54-L60
[Example C]: https://github.com/nikomatsakis/2022-06-15-blogpost/blob/f280f91e9be03d37f273acf13502ef7dc1015db8/examples/c.rs

```rust
struct Context<'ast> {
    impl_trait_tys: Vec<&'ast ast::TraitRef>,

    // Holds temporary AST nodes that we create during lowering;
    // this can be dropped once lowering is complete.
    arena: &'ast typed_arena::Arena<Vec<ast::Parameter>>,
}
```

This actually makes a subtle change to the meaning of `'ast`. It used to be that the only things with `'ast` lifetime were "the AST" itself, so having that lifetime implied being a part of the AST. But now that same lifetime is being used to tag the arena, too, so if we hae `&'ast Foo` it means the data comes is owned by *either* the arena or the AST itself. 

**Side note:** despite the name lifetimes, which I now rather regret, more and more I tend to think of *lifetimes* like `'ast` in terms of "who owns the data", which you can see in my description in the previous paragraph. You could instead think of `'ast` as a span of time (a "lifetime"), in which case it refers to the time that the `Context` type is valid, really, which must be a subset of the time that the arena is valid and the time that the AST itself is valid, since `Context` stores references to data owned by both of those.

Now we can rewrite `lower_trait_ref`  to call `self.arena.alloc()`:

```rust
impl Context<'ast> {
    fn lower_trait_ref(&mut self, trait_ref: &'ast ast::TraitRef) -> hir::TraitRef {
        match &trait_ref.parameters {
            // ...
            ast::Parameters::Parenthesized(types) => {
                let parameters: Vec<_> = types.iter().cloned().map(ast::Parameter::Ty).collect();
                let parameters = self.arena.alloc(parameters); // 👈 added this line!
                self.lower_angle_bracket_parameters(parameters);
            }
        }
        // ...
    }
}
```

Now the `parameters` variable is not stored on the stack but allocated in the arena; the arena has `'ast` lifetime, so that's fine, and everything works! 

## Calling the lowering code and creating the context

Now that we added, the arena, creating the context will look a bit different. It'll look something like:

```rust
let arena = TypedArena::new();
let context = Context::new(&arena);
let hir_signature = context.lower_signature(&signature);
```

The nice thing about this is that, once we are done with lowering, the `context` will be dropped and all those temporary nodes will be freed.

## Another way to fix it

The other obvious option is to avoid lifetimes altogether and just "clone all the things". Given that the AST is immutable once constructed, you can just clone them into the vector:

```rust
struct Context {
    impl_trait_tys: Vec<ast::TraitRef>, // just clone it!
}
```

If that clone is too expensive (possible), then use `Rc<ast::TraitRef>` or `Arc<ast::TraitRef>` (this will require deep-ish changes to the AST to put all the things into `Rc` or `Arc` that might need to be individually referenced). At this point you've got a feeling a lot like garbage collection (if less ergonomic).

## Yet another way

The way I tend to write compilers these days is to use the "indices as pointers". In this approach, all the data in the AST is stored in vectors, and references between things use indices, kind of like [I described here](http://smallcultfollowing.com/babysteps/blog/2015/04/06/modeling-graphs-in-rust-using-vector-indices/).

## Conclusion

Compilation errors are pretty frustrating, but they may also be a sign that the compiler is protecting us from ourselves. In this case, when we embarked on this refactoring, I was totally sure it was going to work fine, because I didn't realize we ever created "temporary AST" nodes, so I assumed that all the data was owned by the original AST. In a language like C or C++, it would have been *very* easy to have a bug here, and it would have been a horrible pain to find. With Rust, that's not a problem.

Of course, not everything is great. For me, doing these kinds of lifetime transformations is old-hat. But for many people it's pretty non-obvious how to start when the compiler is giving you error messages. When people come to me for help, the first thing I try to do is to suss out: what are the ownership relationships, and where do we expect these references to be coming form? There's also various heuristics that I use to decide: do we need a new lifetime parameter? Can we re-use an existing one? I'll try to write up more stories like this to clarify that side of things. Honestly, my main point here was that I was just so grateful that Rust prevented us from spending hours and hours debugging a subtle crash!

Looking forward a bit, I see a lot of potential to improve things about our notation and terminology. I think we should be able to make cases like this one much slicker, hopefully without requiring named lifetime parameters and so forth, or as many edits. But I admit I don't yet know how to do it! :) My plan for now is to keep an eye out for the tricks I am using and the kinds of analysis I am doing in my head and write out blog posts like this one to capture those narratives. I encourage those of you who know Rust well (or who don't!) to do the same.

## Appendix: why not have `Context` *own* the `TypedArena`?

You may have noticed that using the arena had a kind of annoying consequence: people who called `Context::new` now had to create and supply an area:

```rust
let arena = TypedArena::new();
let context = Context::new(&arena);
let hir_signature = context.lower_signature(&signature);
```

This is because `Context<'ast>` stores a `&'ast TypedArena<_>`, and so the caller must create the arena. If we modified `Context` to *own* the arena, then the API could be better. So why didn't I do that? To see why, check out [example D] (which doesn't build). In that example, the `Context` looks like...

[example D]: https://github.com/nikomatsakis/2022-06-15-blogpost/blob/f280f91e9be03d37f273acf13502ef7dc1015db8/examples/c.rs

```rust
struct Context<'ast> {
    impl_trait_tys: Vec<&'ast ast::TraitRef>,

    // Holds temporary AST nodes that we create during lowering;
    // this can be dropped once lowering is complete.
    arena: typed_arena::Arena<Vec<ast::Parameter>>,
}
```

You then have to change the signatures of each function to take an `&'ast mut self`:

```rust
impl Context<'ast> {
    fn lower_signature(&'ast mut self, sig: &'ast ast::Signature) -> hir::Signature {...}
}
```

This is saying: the `'ast` parameter might refer to data owned by self, or maybe by sig. Seems sensible, but if you try to build [Example D], though, you get lots of errors. Here is one of the most interesting to me:

```
error[E0502]: cannot borrow `*self` as mutable because it is also borrowed as immutable
  --> examples/d.rs:98:17
   |
62 | impl<'ast> Context<'ast> {
   |      ---- lifetime `'ast` defined here
...
97 |                 let parameters = self.arena.alloc(parameters);
   |                                  ----------------------------
   |                                  |
   |                                  immutable borrow occurs here
   |                                  argument requires that `self.arena` is borrowed for `'ast`
98 |                 self.lower_angle_bracket_parameters(parameters);
   |                 ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ mutable borrow occurs here
```

What is this all about? This is actually pretty subtle! This is saying that `parameters` was allocated from `self.arena`. That means that `parameters` will be valid **as long as `self.arena` is valid**. 

But `self` is an `&mut Context`, which means it can mutate any of the fields of the `Context`. When we call `self.lower_angle_bracket_parameters()`, it's entirely possible that `lower_angle_bracket_parameters` could mutate the arena:

```rust
fn lower_angle_bracket_parameters(&'ast mut self, parameters: &'ast [ast::Parameter]) {
    self.arena = TypedArena::new(); // what if we did this?
    // ...
}
```

Of course, the code doesn't do that now, but what if it did? The answer is that the parameters would be freed, because the arena that owns them is freed, and so we'd have dead code. D'oh!

All things considered, I'd like to make it possible for `Context` to own the arena, but right now it's pretty challenging. This is a good example of code patterns we could enable, but it'll require language extensions.
