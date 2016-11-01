---
layout: post
title: "Thoughts on trusting types and unsafe code"
date: 2016-09-12 05:39:52 -0400
comments: false
categories: [Rust, Unsafe]
---

I've been thinking about the unsafe code guidelines a lot in the back
of my mind. In particular, I've been trying to think through what it
means to "trust types" -- if you recall from the
[Tootsie Pop Model][tpm] (TPM) blog post, one of the *key* examples
that I was wrestling with was the `RefCell-Ref` example. I want to
revisit a variation on that example now, but from a different
angle. (This by the way is one of those "Niko thinks out loud" blog
posts, not one of those "Niko writes up a proposal" blog posts.)

<!-- more -->

#### Setup

Let's start with a little safe function:

```rust
fn patsy(v: &usize) -> usize {
    let l = *v;
    collaborator();
    use(l);
}
```

The question is, should the compiler ever be able to optimize this
function as follows:

```rust
fn patsy(v: &usize) -> usize {
    collaborator();
    use(*v);
}
```

By moving the load from `v` after the call to `collaborator()`, we
avoided the need for a temporary variable. This might reduce stack
size or register pressure. It is also an example of the kind of
optimizations we are considering doing for MIR (you can think of it as
an aggressive form of copy-propagation). **In case it's not clear, I
really want the answer to this question be yes -- at least most of the
time.** More specifically, I am interested in examining when we can do
this **without doing any interprocedural analysis**.

Now, the question of "is this legal?" is not necessarily a yes or no
question. For example, the Tootsie Pop Model answer was "it
depends". In a safe code context, this transformation was legal. In an
unsafe context, it was not.

#### What could go wrong?

The concern here is that the function `collaborator()` might invalidate `*v` in
some way.  There are two ways that this could potentially happen:

- unsafe code could mutate `*v`,
- unsafe code could invalidate the memory that `v` refers to.

Here is some unsafe code that does the first thing:

```rust
static mut data: usize = 0;

fn instigator() {
    patsy(unsafe { &data });
}

fn collaborator() {
    unsafe { data = 1; }
}
```

Here is some unsafe code that invalidates `*v` using an option (you
can also write code that makes it get freed, of course). Here, when we
start, `data` is `Some(22)`, and we take a reference to that `22`. But
then `collaborator()` reassigns data to `None`, and hence the memory
that we were referring to is now uninitialized.

```rust
static mut data: Option<usize> = Some(22);

fn instigator() {
    patsy(unsafe { data.as_ref().unwrap() })
}

fn collaborator() {
    unsafe { data = None; }
}
```

So, when we ask whether it is legal to optimize `patsy` move the `*v`
load after the call to `collaborator()`, our answer affects whether
this unsafe code is legal.

#### The Tootsie Pop Model

Just for fun, let's look at how this plays out in the Tootsie Pop
model (TPM). As I wrote before, whether this code is legal will
ultimately depend on whether `patsy` is located in an unsafe
context. The way I described the model, unsafe contexs are tied to
modules, so I'll stick with that, but there might also be other ways
of defining what an unsafe context is.

First let's imagine that all three functions are in the same module:

```rust
mod foo {
  static mut data: Option<usize> = Some(22);
  pub fn instigator() {...}
  fn patsy(v: &usize) -> usize {..}
  fn collaborator() {...}
}
```

Here, because `instigator` and `collaborator` contain unsafe blocks,
the module `foo` is considered to be an unsafe context, and thus
`patsy` is also located within the unsafe context. This means that the
unsafe code would be legal and the optimization would not. This is
because the TPM does not allow us to "trust types" within an unsafe
context.

**However,** it's worth pointing out one other interesting
detail. Just because the TPM model does not authorize the
optimization, that doesn't mean that it could not be performed. It
just means that to perform the optimization would require detailed
interprocedural alias analysis. That is, a highly optimizing compile
might analyze `instigator`, `patsy`, and `collaborator` and determine
whether or not the writes in `collaborator` can affect `patsy` (of
course here they can, but in more reasonable code they likely would
not). Put another way, the TPM basically tells you "here are
optimizations you can do without doing anything sophisticated"; it
doesn't put an upper limit on what you can do given sufficient extra
analysis.

OK, so now here is another recasting where the functions are spread between
modules:

```rust
mod foo {
  use bar::patsy;
  static mut data: Option<usize> = Some(22);
  pub fn instigator() {...}
  pub fn collaborator() {...}
}

mod bar {
  use foo::collaborator;
  pub fn patsy(v: &usize) -> usize {..}
}
```

In this case, the module `bar` does not contain `unsafe` blocks, and
hence it is not an unsafe context. That means that we **can** optimize
`patsy`. It **also means** that `instigator` is illegal:

```rust
fn instigator() {
    patsy(unsafe { &data });
}
```

The problem here is that `instigator` is calling `patsy`, which is
defined in a safe context (and hence must also be a safe
function). That implies that `instigator` must fulfill all of Rust's
basic permissions for the arguments that `patsy` expects. In this
case, the argument is a `&usize`, which means that the `usize` must be
accessible **and** immutable for the entire lifetime of the reference;
that lifetime encloses the call to `patsy`. And yet the data in
question **can** be mutated (by `collaborator`). So `instigator` is
failing to live up to its obligations.

TPM has interesting implications for the Rust optimizer. Basically,
whether or not a given statement can "trust" the types of its
arguments ultimately depends on where it appeared in the original
source. This means we have to track some info when inlining unsafe
code into safe code (or else 'taint' the safe code in some way). This
is not unique to TPM, though: Similar capabilities seem to be required
for handling e.g. the C99 `restrict` keyword, and we'll see that they
are also important when trusting types.

#### What if we fully trusted types everywhere?

Of course, the TPM has the downside that it hinders optimization in
[unchecked-get] use case. I've been pondering various ways to address
that. One thing that I find intuitively appealing is the idea of
trusting Rust types everywhere. For example, the idea might be that
**whenever** you create a shared reference like `&usize`, you must
ensure that its associated permissions hold. If we took this approach,
then we could perform the optimization on `patsy`, and we could say
that `instigator` is illegal, for the same reasons that it was illegal
under TPM when `patsy` was in a distinct module.

**However, trusting types everywhere -- even in unsafe code --
potentially interacts in a rather nasty way with lifetime inference.**
Here is another example function to consider, `alloc_free`:

```rust
fn alloc_free() {
    unsafe {
        // allocates and initializes an integer
        let p: *mut i32 = allocate_an_integer();

        // create a safe reference to `*p` and read from it
        let q: &i32 = &*p;
        let r = *q;

        // free `p`
        free(p);

        // use the value we loaded
        use(r); // but could we move the load down to here?
    }
}
```

What is happening here is that we allocate some memory containing an
integer, create a reference that refers to it, read from that
reference, and then free the original memory. We then use the value
that we read from the reference. The question is: can the compiler
"copy-propagate" that read down to the call to `use()`?

If this were C code, the answer would pretty clearly be **no** (I
presume, anyway). The compiler would see that `free(p)` may invalidate
`q` and hence it act as a kind of barrier.

But if we were to go "all in" on trusting Rust types, the answer would
be ([at least currently][nll]) **yes**. Remember that the purpose of this
model is to let us do optimizations **without** doing fancy
analysis. Here what happens is that we create a reference `q` whose
lifetime will stretch from the point of creation until the end of its
scope:

```rust
fn alloc_free() {
    unsafe {
        let p: *mut i32 = allocate_an_integer();

        let q: &i32 = &*p; // --+ lifetime of the reference
        let r = *q;        //   | as defined today
                           //   |
        free(p);           //   |
                           //   |
        use(r); // <------------+
    }
}
```

If this seems like a bad idea, it is. The idea that writing unsafe
Rust code might be **even more subtle** than writing C seems like a
non-starter to me. =)

Now, you might be tempted to think that this problem is an artifact of
how Rust lifetimes are currently tied to scoping. After all, `q` is
not used after the `let r = *q` statement, and if we adopted the
[non-lexical lifetimes][nll] approach, that would mean the lifetime
would end there. But really this problem could still occur in a
NLL-based system, though you have to work a bit harder:

```rust
fn alloc_free2() {
    unsafe {
        let p: *mut i32 = allocate_an_integer();
        let q: &i32 = &*p; // --------+
        let r = *q;            //     |
        if condition1() {      //     |
            free(p);           //     |
        }                      //     |
        if condition2() {      //     |
            use(r);            //     |
            if condition3() {  //     |
                use_again(*q); // <---+
            }
        }
    }
}
```

Here the problem is that, from the compiler's point of view, the
reference `q` is live at the point where we call `free`. This is
because it looks like we might need it to call `use_again`.  But in
fact the *programmer* knows that `condition1()` and `condition3()` are
mutually exclusive, and so she may reason that the lifetime of `q`
ends earlier when `condition1()` holds than when it doesn't.

So I think it seems clear from these examples that we can't really
fully trust types everywhere.

#### Trust types, not lifetimes?

**I think that whatever guidelines we wind up with, we will not be
able to fully trust lifetimes, at least not around unsafe code.** We
have to assume that memory may be invalidated early. Put another way,
the validity of some unsafe code ought not to be determined by the
results of lifetime inference, since mere mortals (including its
authors) cannot always predict what it will do.

But there is a more subtle reason that we should not "trust
lifetimes". **The Rust type system is a conservative analysis that
guarantees safety -- but there are many notions of a reference's
"lifetime" that go beyond its capabilities.** We saw this in the
previous section: today we have lexical lifetimes. Tomorrow we may
have non-lexical lifetimes. But humans can go beyond that and think
about conditional control-flow and other factors that the compiler is
not aware of. We should not expect humans to limit themselves to what
the Rust type system can express when writing unsafe code!

The idea here is that lifetimes are *sometimes* significant to the
model -- in particular, in safe code, the compiler's lifetimes can be
used to aid optimization. But in unsafe code, we are required to
assume that the user gets to pick the lifetimes for each reference,
but those choices must still be valid choices that would type check. I
think that in practice this would roughly amount to "trust lifetimes
in safe contexts, but not in unsafe contexts.

#### Impact of ignoring lifetimes altogether

This implies that the compiler will have to use the loads that the
user wrote to guide it. For example, you might imagine that the the
compiler can move a load from `x` down in the control-flow graph,
**but only if it can see that `x` was going to be loaded anyway**. So
if you consider this variant of `alloc_free`:

```rust
fn alloc_free3() {
    unsafe {
        let p: *mut i32 = allocate_an_integer();
        let q: &i32 = &*p;
        let r = *q; // load but do not use
        free(p);
        use(*q); // not `use(r)` but `use(*q)` instead
    }
}
```

Here we can choose to either eliminate the first load (`let r = *q`)
or else replace `use(*q)` with `use(r)`. Either is ok: we have
evidence that the *user* believes the lifetime of `q` to enclose
`free`. (The fact that it doesn't is their fault.)

But now lets return to our `patsy()` function. Can we still optimize
that?

```rust
fn patsy(v: &usize) -> usize {
    let l = *v;
    collaborator();
    use(l);
}
```

If we are just ignoring the lifetime of `v`, then we can't -- at least
not on the basis of the type of `v`. For all we know, the user
considers the lifetime of `v` to end right after `let l = *v`. That's
not so unreasonable as it might sound; after all, the code looks to
have been deliberately written to load `*v` early. And after all, we
are trying to enable more advanced notions of lifetimes than those
that the Rust type system supports today.

It's interesting that if we inlined `patsy` into its caller, we might
learn new information about its arguments that lets us optimize more
aggressively. For example, imagine a (benevolent, this time) caller
like this:

```rust
fn kindly_fn() {
    let x = &1;
    patsy(x);
    use(*x);
}
```

If we inlined `patsy` into `kindly_fn`, we get this:

```rust
fn kindly_fn() {
    let x = &1;
    {
        let l = *x;
        collaborator();
        use(l);
    }
    use(*x);
}
```

Here we can see that `*x` must be valid after `collaborator()`, and so
we can optimize the function as follows (we are moving the load of
`*x` down, and then applying CSE to eliminate the double load):

```rust
fn kindly_fn() {
    let x = &1;
    {
        collaborator();
        let l = *x;
        use(l);
    }
    use(l);
}
```

**There is a certain appeal to "trust types, not lifetimes", but
ultimately I think it is not living up to Rust's potential**: as you
can see above, we will still be fairly reliant on inlining to recover
needed context for optimizing. Given that the vast majority of Rust is
safe code, where these sorts of operations are harmless, this seems
like a shame.

#### Trust lifetimes only in safe code?

An alternative to the TPM is the
["Asserting-Conflicting Access" model][aca] (ACA), which was proposed
by arielb1 and ubsan. I don't claim to be precisely representing their
model here: I'm trying to (somewhat separately) work through those
rules and apply them formally. So what I write here is more "inspired
by" those rules than reflective of it.

That caveat aside, the idea in their model is that lifetimes are
significant to the model, but you can't trust the compiler's inference
in unsafe code. There, we have to assume that the unsafe code author
is free to pick any valid lifetime, so long as it would still *type
check* (not "borrow check" -- i.e., it only has to ensure that no data
outlives its owning scope). **Note the similarities to the Tootsie Pop
Model here -- we still need to define what an "unsafe context" is, and
when we enter such a context, the compiler will be less aggressive in
optimizing (though more aggressive than in the TPM).** (This has
implications for the [unchecked-get] example.)

Nonetheless, I have concerns about this formulation because it seems
to assume that the logic for unsafe code *can* be expressed in terms
of Rust's lifetimes -- but as I wrote above Rust's lifetimes are
really a conservative approximation. As we improve our type system,
they can change and become more precise -- and users might have in
mind more precise and flow-dependent lifetimes still. In particular,
it seems like the "ACA" would disallow my `alloc_free2` example:

```rust
fn alloc_free2() {
    unsafe {
        let p: *mut i32 = allocate_an_integer();
        let q: &i32 = &*p;
        let r = *q; // (1)
        if condition1() {
            free(p); // (2)
        }
        if condition2() {
            use(r); // (3)
            if condition3() {
                use_again(*q); // (4)
            }
        }
    }
}
```

Intuitively, the problem is that the lifetime of `q` must enclose the
points (1), (2), (3), and (4) that are commented above. But the user
knows that `condition1()` and `condition3()` are mutually exclusive,
so in their mind, the lifetime ends either when we reach point (2),
since they know that this means that point (4) is unreachable.

In terms of their model, the *conflicting access* would be (2) and the
*asserting access* would be (1). But I might be misunderstanding how
this whole thing works.

#### Trust lifetimes at safe fn boundaries 

Nonetheless, perhaps we can do something *similar* to the ACA model
and say that: we can trust lifetimes in "safe code" but totally
disregard them in "unsafe code" (however we define that). If we
adopted these definitions, would that allow us to optimize `patsy()`?

```rust
fn patsy<'a>(v: &'a usize) -> usize {
    let l = *v;
    collaborator();
    use(l);
}
```

Presuming `patsy()` is considered to be "safe code", then the answer is
yes. This in turn implies that any unsafe callers are obligated to 
consider `patsy()` as a "block box" in terms of what it might do with `'a`.

This flows quite naturally from a "permissions" perspective --- giving
a reference to a safe fn implies giving it permission to use that
reference *any time during its execution*. I have been (separately) 
trying to elaborate this notion, but it'll have to wait for a separate post.

### Conclusion

**One takeaway from this meandering walk is that, if we want to make
it easy to optimize Rust code aggressively, there *is* something
special about the fn boundary.** In retrospect, this is really not
that surprising: we are trying to enable intraprocedural optimization,
and hence the fn boundary is the boundary beyond which we cannot
analyze -- within the fn body we can see more.

Put another way, if we want to optimize `patsy()` without doing any
interprocedural analysis, it seems clear that we *need* the caller to
guarantee that `v` will be valid for the entire call to `patsy`:

```rust
fn patsy(v: &usize) -> usize {
    let l = *v;
    collaborator();
    use(l);
}
```

I think this is an interesting conclusion, even if I'm not quite sure
where it leads yet.

**Another takeaway is that we have to be very careful trusting
lifetimes around unsafe code.** Lifetimes of references are a tool
designed for use by the borrow checker: we should not use them to
limit the clever things that unsafe code authors can do.

### Note on comments

Comments are closed on this post. Please post any questions or
comments on [the internals thread] I'm about to start. =)

Also, I'm collecting unsafe-related posts into the [unsafe category].

[tpm]: http://smallcultfollowing.com/babysteps/blog/2016/05/27/the-tootsie-pop-model-for-unsafe-code/
[unchecked-get]: http://smallcultfollowing.com/babysteps/blog/2016/08/18/tootsie-pop-followup/
[nll]: http://smallcultfollowing.com/babysteps/blog/2016/04/27/non-lexical-lifetimes-introduction/
[aca]: https://github.com/nikomatsakis/rust-memory-model/issues/26
[the internals thread]: https://internals.rust-lang.org/t/blog-post-thoughts-on-trusting-types-and-unsafe-code/4059
[unsafe category]: http://smallcultfollowing.com/babysteps/blog/categories/unsafe/
