---
date: "2022-08-18T00:00:00Z"
slug: come-contribute-to-salsa-2022
title: Come contribute to Salsa 2022!
---

Have you heard of the [Salsa] project? **Salsa** is a library for incremental computation -- it's used by rust-analyzer, for example, to stay responsive as you type into your IDE (we have also [discussed using it in rustc][use-in-rustc], though more work is needed there). We are in the midst of a big push right now to develop and release **Salsa 2022**, a major new revision to the API that will make Salsa far more natural to use. I'm writing this blog post both to advertise that ongoing work and to put out a **call for contribution**. Salsa doesn't yet have a large group of maintainers, and I would like to fix that. If you've been looking for an open source project to try and get involved in, maybe take a look at our [Salsa 2022 tracking issue](https://github.com/salsa-rs/salsa/issues/305) and see if there is an issue you'd like to tackle?

[Salsa]: https://github.com/salsa-rs/salsa

[use-in-rustc]: https://rust-lang.zulipchat.com/#narrow/stream/238009-t-compiler.2Fmeetings/topic/.5Bsteering.20meeting.5D.202022-04-15.20compiler-team.23507/near/279082491

### So wait, *what* does Salsa do?

Salsa is designed to help you build programs that respond to rapidly changing inputs. The prototypical example is a compiler, especially an IDE. You'd like to be able to do things like "jump to definition" and keep those results up-to-date even as the user is actively typing. Salsa can help you build programs that manage that.

The key way that Salsa achieves reuse is through memoization. The idea is that you define a function that does some specific computation, let's say it has the job of parsing the input and creating the Abstract Syntax Tree (AST):

```rust
fn parse_program(input: &str) -> AST { }
```

Then later I have other functions that might take parts of that AST and operate on them, such as type-checking:

```rust
fn type_check(function: &AstFunction) { }
```

In a setup like this, I would like to have it so that when my base input changes, I do have to re-parse but I don't necessarily have to run the type checker. For example, if the only change to my progam was to add a comment, then maybe my AST is not affected, and so I don't need to run the type checker again. Or perhaps the AST contains many functions, and only one of them changed, so while I have to type check that function, I don't want to type check the others. Salsa can help you manage this sort of thing automatically.

## What is Salsa 2022 and how is it different?

The original salsa system was modeled very closely on the [rustc query system]. As such, it required you to structure your program entirely in terms of functions and queries that called one another. All data was passed through return values. This is a very powerful and flexible system, but it can also be kind of mind-bending sometimes to figure out how to "close the loop", particularly if you wanted to get effective re-use, or do lazy computation.

Just looking at the `parse_program` function we saw before, it was defined to return a complete AST:

```rust
fn parse_program(input: &str) -> AST { }
```

But that AST has, internally, a lot of structure. For example, perhaps an AST looks like a set of functions:

```rust
struct Ast {
    functions: Vec<AstFunction>
}

struct AstFunction {
    name: Name,
    body: AstFunctionBody,
}

struct AstFunctionBody {
    ...
}
```

Under the old Salsa, changes were tracked at a pretty coarse-grained level. So if your input changed, and the content of *any* function body changed, then your entire AST was considered to have changed. If you were naive about it, this would mean that everything would have to be type-checked again. In order to get good reuse, you had to change the structure of your program pretty dramatically from the "natural structure" that you started with.

## Enter: tracked structs

The newer Salsa introduces **tracked structs**, which makes this a lot easier. The idea is that you can label a struct as tracked, and now its fields become managed by the database:

```rust
#[salsa::tracked]
struct AstFunction {
    name: Name,
    body: AstFunctionBody,
}
```

When a struct is declared as tracked, then we also track accesses to its fields. This means that if the parser produces the same *set* of functions, then its output is considered not to have changed, even if the function bodies are different. When the type checker reads the function body, we'll track that read independently. So if just one function has changed, only that function will be type checked again.

## Goal: relatively natural

The goal of Salsa 2022 is that you should be able to convert a program to use Salsa without dramatically restructuring it. It should still feel quite similar to the 'natural structure' that you would have used if you didn't care about incremental reuse.

Using techniques like tracked structs, you can keep the pattern of a compiler as a kind of "big function" that passes the input through many phases, while still getting pretty good re-use:

```rust
fn typical_compiler(input: &str) -> Result {
    let ast = parse_ast(input);
    for function in &ast.functions {
        type_check(function);
    }
    ...
}
```

Salsa 2022 also has other nice features, such as [accumulators](https://salsa-rs.github.io/salsa/overview.html#accumulators) for managing diagnostics and [built-in interning](https://salsa-rs.github.io/salsa/overview.html#interned-structs).

If you'd like to learn more about how Salsa works, check out the [overview page](https://salsa-rs.github.io/salsa/overview.html) or read through the (WIP) [tutorial](https://salsa-rs.github.io/salsa/tutorial.html), which covers the design of a complete compiler and interpreter.

## How to get involved

As I mentioned, the purpose of this blog post is to serve as a **call for contribution**. Salsa is a cool project but it doesn't have a lot of active maintainers, and we are actively looking to recruit new people.

The [Salsa 2022 tracking issue](https://github.com/salsa-rs/salsa/issues/305) contains a list of possible items to work on. Many of those items have mentoring instructions, just search for things tagged with [good first issue](https://github.com/salsa-rs/salsa/issues?q=is%3Aopen+is%3Aissue+label%3A%22good+first+issue%22+label%3Asalsa-2022). There is also [documentation of salsa's internal structure on the main web page](https://salsa-rs.github.io/salsa/plumbing.html) that can help you navigate the code base. Finally, we have a [Zulip instance](https://salsa.zulipchat.com/) where we hang out and chat (the [`#good-first-issue` stream](https://salsa.zulipchat.com/#narrow/stream/146365-good-first-issue) is a good place to ask for help!)

