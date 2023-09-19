---
layout: post
title: 'Project idea: datalog output from rustc'
---

I want to have a tool that would enable us to answer all kinds of queries about the structure of Rust code that exists in the wild. This should cover everything from synctactic queries like "How often do people write `let x = if { ... } else { match foo { ... } }`?" to semantic queries like "How often do people call unsafe functions in another module?"  I have some ideas about how to build such a tool, but (I suspect) not enough time to pursue them. I'm looking for people who might be interested in working on it!

The basic idea is to build on [Datalog](https://en.wikipedia.org/wiki/Datalog). Datalog, if you're not familiar with it, is a very simple scheme for relating facts and then performing analyses on them. It has a bunch of high-performance implementations, notably [souffle](https://github.com/oracle/souffle), which is also available on GitHub. (Sadly, it generates C++ code, but maybe we'll fix that another day.)

Let me work through a simple example of how I see this working. Perhaps we would like to answer the question: How often do people write tests in a separate file (`foo/test.rs`) versus an inline module (`mod test { ... }`)?

We would (to start) have some hacked up version of rustc that serializes the HIR in Datalog form. This can include as much information as we would like. To start, we can stick to the syntactic structures. So perhaps we would encode the module tree via a series of facts like so:

```
// links a module with the id `id` to its parent `parent_id`
ModuleParent(id, parent_id).
ModuleName(id, name).

// specifies the file where a given `id` is located
File(id, filename).
```

So for a module structure like:

```
// foo/mod.rs:
mod test;

// foo/test.rs:
#[test] 
fn test() { }
```

we might generate the following facts:

```
// module with id 0 has name "" and is in foo/mod.rs
ModuleName(0, "").
File(0, "foo/mod.rs").

// module with id 1 is in foo/test.rs,
// and its parent is module with id 0.
ModuleName(1, "test").
ModuleParent(1, 0).
File(1, "foo/test.rs").
```

Then we can write a query to find all the modules named test which are in a different file from their parent module:

```
// module T is a test module in a separate file if...
TestModuleInSeparateFile(T) :-
    // ...the name of module T is test, and...
    ModuleName(T, "test"),
    // ...it is in the file T_File... 
    File(T, T_File),
    // ...it has a parent module P, and...
    ModuleParent(T, P),
    // ...the parent module P is in the file P_File... 
    File(P, P_File),
    // ...and file of the parent is not the same as the file of the child.
    T_File != P_File.
```

Anyway, I'm waving my hands here, and probably getting datalog syntax all wrong, but you get the idea!

Obviously my encoding here is highly specific for my particular query. But eventually we can start to encode all kinds of information this way. For example, we could encode the types of every expression, and what definition each path resolved to. Then we can use this to answer all kinds of interesting queries. For example, some things I would like to use this for right now (or in the recent past):

- Evaluating new lifetime elision rules.
- Checking what kinds of unsafe code patterns exist in real life and how frequently.
- Checking how much might benefit from [accepting the `else match { ... }` RFC](https://github.com/rust-lang/rfcs/pull/1712)
- Testing how much code in the wild might be affected by [deprecating `Trait` in favor of `dyn Trait`](https://github.com/rust-lang/rfcs/pull/1603)

So, you interested? If so, contact me -- either privmsg over IRC
(`nmatsakis`) or
[over on the internals threads I created](https://internals.rust-lang.org/t/project-idea-datalog-output-from-rustc/4805).
