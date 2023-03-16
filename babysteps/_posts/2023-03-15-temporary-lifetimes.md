---
layout: post
title: Temporary lifetimes
date: 2023-03-15 14:22 -0400
---
In [today's lang team design meeting][m], we reviewed a doc I wrote about temporary lifetimes in Rust. The current rules were [established in a blog post I wrote in 2014][rl]. Almost a decade later, we've seen that they have some rough edges, and in particular can be a common source of bugs for people. The Rust 2024 Edition gives us a chance to address some of those rough edges. This blog post is a copy of the document that the lang team reviewed. It's not a *proposal*, but it covers some of what works well and what doesn't, and includes a few sketchy ideas towards what we could do better.

[rl]: http://smallcultfollowing.com/babysteps/blog/2014/01/09/rvalue-lifetimes-in-rust/

[m]: https://github.com/rust-lang/lang-team/blob/master/design-meeting-minutes/2023-03-15-temporary-lifetimes.md

## Summary

Rust's rules on temporary lifetimes often work well but have some sharp edges. The 2024 edition offers us a chance to adjust these rules. Since those adjustments change the times when destructors run, they must be done over an edition.

## Design principles

I propose the following design principles to guide our decision.

* **Independent from borrow checker:** We need to be able to figure out when destructors run without consulting the borrow checker. This is a slight weakening of the original rules, which required that we knew when destructors would run without consulting results from name resolution or type check.
* **Shorter is more reliable and predictable:** In general, we should prefer shorter temporary lifetimes, as that results in more reliable and predictable programs.
    * *Editor's note:* A number of people in the lang questions this point. The reasoning is as follows. First, a lot of the problems in practice come from locks that are held longer than expected. Second, problems that come from temporaries being dropped too *early* tend to manifest as borrow check errors. Therefore, they don't cause reliability issues, but rather ergonomic ones.
* **Longer is more convenient:** Extending temporary lifetimes where we can do so safely gives more convenience and is key for some patterns.
    * *Editor's note:* As noted in the previous bullet, our current rules sometimes give temporary lifetimes that are shorter than what the code requires, but these generally surface as borrow check errors.

### Equivalences and anti-equivalences

The rules should ensure that `E` and `(E)`, for any expression `E`, result in temporaries with the same lifetimes.

Today, the rules *also* ensure that `E` and `{E}`, for any expression `E`, result in temporaries with the same lifetimes, but this document proposes dropping that equivalence as of Rust 2024.

## Current rules

### When are temporaries introduced?

Temporaries are introduced when there is a borrow of a *value-producing expression* (often called an "rvalue"). Consider an example like `&foo()`; in this case, the compiler needs to produce a reference to some memory somewhere, so it stores the result of `foo()` into a temporary local variable and returns a reference to that.

Often the borrows are implicit. Consider a function `get_data()` that returns a `Vec<T>` and a call `get_data().is_empty()`; because `is_empty()` is declared with `&self` on `[T]`, this will store the result of `get_data()` into a temporary, invoke `deref` to get a `&[T]`, and then call `is_empty`.

### Default temporary lifetime

Whenever a temporary is introduced, the default rule is that the temporary is dropped at the end of the innermost enclosing statement; this rule is sometimes summarized as "at the next semicolon". But the definition of *statement* involves some subtlety. 

**Block tail expressions.** Consider a Rust block:

```rust
{
    stmt[0];
    ...
    stmt[n];
    tail_expression
}
```

And temporaries created in a statement `stmt[i]` will be dropped once that statement completes. But the tail expression is not considered a statement, so temporaries produced *there* are dropped at the end of the statement that encloses the block. For example, given `get_data` and `is_empty` as defined in the previous section, and a statement `let x = foo({get_data().is_empty()});`, the vector will be freed at the end of the `let`. 

**Conditional scopes for `if` and `while`.** `if` and `while` expressions and `if guards` (but not `match` or `if let`) introduce a temporary scope around the condition. So any temporaries from `expr` in `if expr { ... }` would be dropped before the `{ ... }` executes. The reasoning here is that all of these contexts produce a boolean and hence it is not possible to have a reference into the temporary that is still live. For example, given `if get_data().is_empty()`, the vector must be safe to drop before entering the body of the `if`. This is not true for a case like `match get_data().last() { Some(x) => ..., None => ... }`, where the `x` would be a reference into the vector returned by `get_data()`.

**Function scope.** The tail expression of a function block (e.g., the expression `E` in `fn foo() { E }`) is not contained by *any* statement. In this case, we drop temporaries from `E` just before returning from the function, and thus `fn last() -> Option<&Datum> { get_data().last() }` fails the borrow check (because the temporary returned by `get_data()` is dropped before the function returns). Importantly, this function scope ends *after* local variables in the function are dropped. Therefore, this function...

```rust
fn foo() {
    let x = String::new();
    vec![].is_empty()
}
```

...is effectively desugared to this...

```rust
fn foo() {
    let tmp;
    {
        let x = String::new();
        { tmp = vec![]; &tmp }.is_empty()
    } // x dropped here
} // tmp dropped here
```

### Lifetime extension

In some cases, temporary lifetimes are extended from the innermost *statement* to the innermost *block*. The rules for this are currently defined *syntactically*, meaning that they do not consider types or name resolution. The intution is that we extend the lifetime of the temporary for an expression `E` if it is evident that this temporary will be stored into a local variable. Consider the trivial example:

```rust
let t = &foo();
```

Here, `foo()` is a value expression, and hence `&foo()` needs to create a temporary so that we can have a reference. But the resulting `&T` is going to be stored in the local variable `t`. If we were to free the temporary at the next `;`, this local variable would be immediately invalid. That doesn't seem to match the user intent. Therefore, we *extend* the lifetime of the temporary so that it is dropped at the end of the innermost block. This is the equivalent of:

```rust
let tmp;
let t = { tmp = foo(); &tmp };
```

We can extend this same logic to compound expressions. Consider:

```rust
let t = (&foo(), &bar());
```

we will expand this to


```rust
let tmp1;
let tmp2;
let t = { tmp1 = foo(); tmp2 = bar(); (&tmp1, &tmp2) };
```

The exact rules are given by a grammar in the code and also [covered in the reference](https://doc.rust-lang.org/nightly/reference/destructors.html#drop-scopes). Rather than define them here I'll just give some examples. In each case, the `&foo()` temporary is extended:

```rust
let t = &foo();

// Aggregates containing a reference that is stored into a local:
let t = Foo { x: &foo() };
let t = (&foo(), );
let t = [&foo()];

// Patterns that create a reference, rather than `&`:
let ref t = foo();
```

Here are some cases where temporaries are NOT extended:

```rust
let f = some_function(&foo()); // could be `fn some_function(x: &Vec<T>) -> bool`, may not need extension

struct SomeTupleStruct<T>(T);
let f = SomeTupleStruct(&foo()); // looks like a function call
```

## Patterns that work well in the current rules

### Storing temporary into a local

```rust
struct Data<'a> {
    data: &'a [u32] // use a slice to permit subslicing later
}

fn initialize() {
    let d = Data { x: &[1, 2, 3] };
    //                 ^^^^^^^^^ extended temporary
    d.process();
}

impl Data<'_> {
    fn process(&mut self) {
        ...
        self.data = &self.data[1..];
        ...
    }
}
```

### Reading values out of a lock/refcell

The current rules allow you to do atomic operations on locals/refcells conveniently, so long as they don't return references to the data. This works great in a `let` statement (there are other cases below where it works less well).

```rust
let result = cell.borrow_mut().do_something();
// `cell` is not borrowed here
...
```

## Error-prone cases with today's rules

Today's rules sometimes give lifetimes that are **too long**, resulting in bugs at runtime.

### Deadlocks because of temporary lifetimes in matches

One very common problem is deadlocks (or panics, for ref-cell) when mutex locks occur in a match scrutinee:

```rust
match lock.lock().data.clone() {
    //     ------ returns a temporary guard
    
    Data { ... } => {
        lock.lock(); // deadlock
    }
    
} // <-- lock() temporary dropped here
```

## Ergonomic problems with today's rules

Today's rules sometimes give lifetimes that are **too short**, resulting in ergonomic failures or confusing error messages.

### Call parameter temporary lifetime is too short (RFC66)

Somewhat surprisingly, the following code [does not compile](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=e7dde5d5b85500cd00af06c9b5d5acaf):

```rust
fn get_data() -> Vec<u32> { vec![1, 2, 3] }

fn main() {
    let last_elem = get_data().last();
    drop(last_elem); // just a dummy use
}
```

This fails because the `Vec` returned by `get_data()` is stored into a temporary so that we can invoke `last`, which requires `&self`, but that temporary is dropped at the `;` (as this case doesn't fall under the lifetime extension rules). 

[RFC 66][] proposed a rather underspecified extension to the temporary lifetime rules to cover this case; loosely speaking, the idea was to extend the lifetime extension rules to extend the lifetime of temporaries that appear in function arguments if the function's signature is going to return a reference from that argument. So, in this case, the signature of `last` indicates that it returns a reference from `self`:

[RFC 66]: https://rust-lang.github.io/rfcs/0066-better-temporary-lifetimes.html


```rust
impl<T> [T] {
    fn last(&self) -> Option<&T> {...}
}
```

and therefore, since `E.last()` is being assigned to `last_elem`, we would extend the lifetime of any temporaries in `E` (the value for `self`). Ding Xiang Fei has been exploring how to actually implement [RFC 66][] and has made some progress, but it's clear that we need to settle on the *exact* rules for when lifetime temporary extension should happen.

Even assuming we created some rules for RFC 66, there can be confusing cases that wouldn't be covered. Consider this statement:

```rust!
let l = get_data().last().unwrap();
drop(l); // ERROR
```

Here, the `unwrap` call has a signature `fn(Option<T>) -> T`, which doesn't contain any references. Therefore, it does not extend the lifetimes of temporaries in its arguments. The argument here is the expression `get_data().last()`, which creates a temporary to store `get_data()`. This temporary is then dropped at the end of the statement, and hence `l` winds up pointing to dead memory.

### Statement-like expressions in tail position

The original rules assumed that changing `E` to `{E}` should not change when temporaries are dropped. This has the counterintuitive behavior though that introducing a block doesn't constrain the stack lifetime of temporaries. It is also surprising for blocks that have tail expressions that are "statement-like" (e.g., `match`), because these can be used as statements without a `;`, and thus users may not have a clear picture of whether they are an expression producing a value or a statement.

**Example.** The following code [does not compile](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=f16625bcd6e35c988c5b9399b821b98b):

```rust
struct Identity<A>(A);
impl<A> Drop for Identity<A> {
    fn drop(&mut self) { }
}
fn main() {
    let x = 22;
    match Identity(&x) {
        //------------ creates a temporary that can be matched
        _ => {
            println!("");
        }
    } // <-- this is considered a trailing expression by the compiler
} // <-- temporary is dropped after this block executes
```

Because of the way that the implicit function scope works, and the fact that this match is actually the tail expression in the function body, this is effectively desugared to something like this:

```rust
struct Identity<A>(A);
impl<A> Drop for Identity<A> {
    fn drop(&mut self) { }
}
fn main() {
    let tmp;
    {
        let x = 22;
        match {tmp = Identity(&x); tmp} {
            _ => {
                println!("");
            }
        }
    }
}
```

### Lack of equivalence between if and match

The current rules distinguish temporary behavior for if/while from match/if-let. As a result, code like this compiles and executes fine:

```rust
if lock.lock().something { // grab lock, then release
    lock.lock(); // OK to grab lock again
}
```

but very similar code using a match gives a deadlock:

```rust
if let true = lock.lock().something {
    lock.lock(), // Deadlock lock.lock(), // Deadlock
}

// or

match lock.lock().something {
    true => lock.lock(), // Deadlock
    false => (),
}
```

Partly as a result of this lack of equivalence, we have had a lot of trouble doing desugarings for things like let-else and if-let expressions.

### Named block

Tail expressions aren't the only way to "escape" a value from a block, the same applies to breaking with a named label, but they don't benefit from lifetime extension. The following example, therefore, [fails to compile](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=3fe08dd173a4bbf18a4321b36bc74d50):

```rust!
fn main() {
    let x = 'a: {
        break 'a &vec![0]; // ERROR
    };
    
    drop(x);
}
```

Note that a tail-expression based version [does compile today](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=aacec04924b890d994abc2d1db67627b):

```rust
fn main() {
    let x = { &vec![0] };
    drop(x);
}
```

## Proposed properties to focus discussion

To focus discussion, here are some named examples we can use that capture key patterns.

Examples of behaviors we would ideally *preserve*:

* **read-locked-field**: `let x: Event = ref_cell.borrow_mut().get_event();` releases borrow at the end of the *statement* (as today)
* **obvious aggregate construction**: `let x: Event = Event { x: &[1, 2, 3] }` stores `[1, 2, 3]` in a temporary with block scope

Examples of behavior that we would like, but which we don't have today, resulting in bugs/confusion:

* **match-locked-field**: `match data.lock().unwrap().data { ... }` releases lock before match body executes
* **if-match-correspondence**: `if <expr> {}`, `if let true = <expr> {}`, and `match <expr> { true => .. }` all behave the same with respect to temporaries in `<expr>` (unlike today)
* **block containment**: `{<expr>}` must not create any temporaries that extend past the end of the block (unlike today)
* **tail-break-correspondence**: `{<expr>}` and `'a: { break 'a <expr> }` should be equivalent

Examples we behavior that we would like, but which we don't have today, resulting in ergonomic pain (these cases may not be achievable without violating the previous ones):

* **last**: `let x = get_data().last();` (the canonical RFC66 example) will extend lifetime of data to end of block; also covers (some) `new` methods like `let x: Event<'_> = Event::new(&[1, 2, 3])`
* **last-unwrap**: `let x = get_data().last().unwrap();` (extended form of the above) will extend lifetime of data to end of block
* **tuple struct construction**: `let x = Event(&[1, 2, 3])`

## Tightest proposal

The proposal with minimal confusion would be to remove syntactic lifetime extension and tighten default lifetimes in two ways:

*Tighten block tail expressions.* Have temporaries in the tail expression of a block be dropped when returning from the block. This ensures *block containment* and *tail-break-correspondence*.

*Tighten match scrutinees.* Drop temporaries from match/if-let scrutinees performing the match. This ensures *match-locked-field* and *if-match-correspondence.* To avoid footguns, we can tighten up the rules around match/if-let scrutinees so that temporaries are dropped before entering body of the match.

In short, temporaries would always be dropped at the innermost statement, match/if/if-let/while scrutinee, or block.

### Things that no longer build

There are three cases that build today which will no longer build with this minimal proposal:

* `let x = &vec![]` no longer builds, nor does `let x = Foo { x: &[1, 2, 3] }`. Both of them create temporaries that are dropped at the end of the let.
* `match &foo.borrow_mut().parent { Some(ref p) => .., None => ... }` no longer builds, since temporary from `borrow_mut()` is dropped before entering the match arms.
* `{let x = {&vec![0]}; ...}` no longer builds, as a result of tightening block tail expressions. Note however that other examples, e.g. the one from th section ["statement-like expressions in tail position"][sletp], would now build successfully.

[sletp]: #Statement-like-expressions-in-tail-position

The core proposal also does nothing to address RFC66-like patterns, tuple struct construction, etc.

### Extension option A: Do What I Mean

One way to overcome the concerns of the core proposal would be to extend with more "DWIM"-like options. For example, we could extend "lifetime extension rules" to cover match expressions.

*Lifetime extension for `let` statements, as today*. To allow `let x = &vec![]` to build, we can restore today's lifetime extension rules.

* Pro: things like this will build

```rust!
let x = Foo { 
    data: &get_data()
    //     ---------- stored in a temporary that outlives `x`
};)
```

* Con: the following example would build again, which leads to a (perhaps surprising) [panic]https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=2e9e4077c3558c3da5d9df9ba717c8af) -- that said, I've never seen a case like this in the wild, the confusion *always* occurs with match

```rust!
use std::cell::RefCell;

struct Foo<'a> {
    data: &'a u32
}

fn main() {
    let cell = RefCell::new(22);
    let x: Foo<'_> = Foo {
        data: &*cell.borrow_mut(),
    };
    *cell.borrow_mut() += 1; // <-- panic
    drop(x);
}
```

*Scope extension for match structinees*. To allow `match &foo.borrow_mut().parent { Some(ref x => ... }` to work, we could fix this by including similar scope extension rules to the ones used with `let` initializers (i.e., if we can see that a ref is taken into the temporary, then extend its lifetime, but otherwise do not).

* Pro: `match &foo.borrow_mut().parent { .. }` works as it does today.
* Con: Syntactic extension rules can be approximate, so e.g. `match (foo(), bar().baz()) { (Some(ref x), y) => .. }` would likely keep the temporary returned by `bar()`, even though it is not referenced.

*RFC66-like rules.* Use some heuristic rules to determine, from a function signature, when the return type includes data from the arguments. If the return type of a function `f` references a generic type or lifetime parameter that also appears in some argument `i`, and the function call `f(a0, ..., ai, ..., an)` appears in some position with an extended temporary lifetime, then `ai` will also have an extended temporary lifetime (i.e., any temporaries created in `ai` will persist until end of enclosing block / match expression). 

* Pro: Patterns like `let x = E` where `E` is `get_data().last()`, `get_data().last().unwrap()`, `TupleStruct(&get_data())`, or `SomeStruct::new(&get_data())` would all allocate a temporary for `get_data()` that persistent until the end of the enclosing block. This occurs because
* Con: Complex rules imply that `let x = locked_vec.lock().last()` would also extend lock lifetime to end-of-block, which users may not expect.

### Extension option B: "Anonymous lets" for extended temporary lifetimes

Allow `expr.let` as an operator that means "introduce a let to store this value inside the innermost block but before the current statement and replace this statement with a reference to it". So for example:

```rust!
let x = get_data().let.last();
```

would be equivalent to 

```rust!
let tmp = get_data();
let x = tmp.last();
```

*Question:* Do we keep some amount of implicit extension? For example, should `let x = &vec![]` keep compiling, or do you have to do `let x = &vec![].let`?

## Parting notes

*Editor's note:* As I wrote at the start, this was an early document to prompt discussion in a meeting ([you can see notes from the meeting here](https://github.com/rust-lang/lang-team/blob/master/design-meeting-minutes/2023-03-15-temporary-lifetimes.md#discussion-comments)) It's not a full proposal. That said, my position when I started writing was different than where I landed. Initially I was going to propose more of a "DWIM"-approach, tweaking the rules to be tighter in some places, more flexible in others. I'm still interested in exploring that, but I am worried that the end-result will just be people having very little idea when their destructors run. For the most part, you shouldn't have to care about that, but it is sometimes quite important. That leads me to: let's have some simple rules that can be explained on a postcard and work "pretty well", and some convenient way to extend lifetimes when you want it. The `.let` syntax is interesting but ultimately probably too confusing to play this role.

Oh, and a note on the edition: I didn't say it explicitly, but we can make changes to temporary lifetime rules over an edition by rewriting where necessary to use explicit lets, or (if we add one) some other explicit notation. The result would be code that runs on all editions with same semantics.