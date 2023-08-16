---
categories:
- Rust
- NLL
date: "2018-10-31T00:00:00Z"
slug: mir-based-borrowck-is-almost-here
title: MIR-based borrowck is almost here
---

Now that [the final Rust 2018 Release Candidate has
shipped][rust-blog], I thought it would be a good idea to do another
update on the state of the MIR-based borrow check (aka NLL). The [last
update][] was in June, when we were still hard at work on getting
things to work.

[rust-blog]: https://blog.rust-lang.org/2018/10/30/help-test-rust-2018.html
[last update]: {{ site.baseurl }}/blog/2018/06/15/mir-based-borrow-check-nll-status-update/

## Rust 2018 will use NLL now

Let's get the highlights out of the way. Most importantly, **Rust 2018
crates will use NLL by default**. Once the Rust 2018 release candidate
becomes stable, **we plan to switch Rust 2015 crates to use NLL as
well**, but we're holding off until we have some more experience with
people using it in the wild.

## NLL is awesome

I've been using NLL in practice for quite some time now, and I can't
imagine going back. Recently I've been working in my spare time on
[the salsa crate][salsa][^plug], which uses Rust 2018, and I've really
noticed how NLL makes a lot of "complex" borrowing interactions work
out quite smoothly. These are all instances of the [problem cases #1
and #2][pc12] I highlighted way back when[^pc3], but they interact in
interesting ways I did not fully anticipate.

[pc12]: {{ site.baseurl }}/blog/2016/04/27/non-lexical-lifetimes-introduction/
[salsa]: https://github.com/salsa-rs/salsa
[^plug]: Did you see how smoothly I worked in that plug for [salsa][]? I'll write a post about it soon, I promise.
[^pc3]: Note that the current NLL implementation does not solve Problem Case #3. See [the "What Next?" section][wn] for more.
[wn]: #what-next

Let me give you a hypothetical example. Imagine I am writing some bit
of code that routes messages, which look like this:

```rust
enum Message {
    Letter { recipient: String, data: String },
    // ... maybe other cases here ...
}
```

When I receive a letter, I want to inspect its recipient. If that matches my name,
I will process the data using `process`:

```rust
fn process(data: &str) { .. }
```

but otherwise I'll forward it along to the next person in the
chain. Using NLL, I can write this code like so ([playground][pg1]):

[pg1]: https://play.rust-lang.org/?version=nightly&mode=debug&edition=2018&gist=b8dfafd14113f2933c1b5127c861df44

```rust
fn router(me: &str, rx: Receiver<Message>, tx: Sender<Message>) {
  for message in rx {
    match &message {
      Message::Letter { recipient, data } => {
        if recipient != me {
          tx.send(message).unwrap();
        } else {
          process(data);
        }
      }

      // ... maybe other cases here ...
    }
  }
}
```

What's interesting about this code is how uninteresting it is -- it
basically just does what you expect, and didn't require any special
action to please the borrow checker[^intern]. But the borrowing
patterns are actually sort of complex: it starts as we enter the match
(`match &message`) and continues into the match arm. On the `else`
branch of the match, the borrow is still in use (in the form of the
`data` variable), but in the `if` branch, it is not (and hence we can
call `tx.send(message)` and move the message). Before NLL, this would
have required some significant contortions to achieve ([try it
yourself if you
like](https://play.rust-lang.org/?version=nightly&mode=debug&edition=2015&gist=ee86bacf163aab324692f0297fc05eee)
-- that's a link to the same code, but with Rust 2015 edition set).

[^intern]: Interestingly, I remember an example almost exactly like this being shown to me by a Servo intern -- I forget which one -- many years ago. At the time, it didn't seem like a big deal to do the workarounds, but I realize now I was wrong about that. Ah well.

### Diagnostics, migration, and performance

We've also put a lot of effort into NLL diagnostics and I think that
by and large they are even better than the old borrow checker (which
were already quite good). This is particularly true for the 'lifetime
error messages'.  Unfortunately, you won't see *all* of those
improvements yet on Rust 2018 -- the reason has to do with
**migration**.

What is this migration you ask? Well, it's our way of dealing with the
fact that the new MIR-based borrow checker has fixed a ton of
soundness bugs from the old checker. Unfortuantely, in practice, that
means that some existing code will not compile anymore (because it
never should have compiled in the first place!). To give people time
to make that transition, we are running the NLL code in "migration
mode", which means that if you have code that used to compile, but no
longer does, we issue **warnings** instead of **errors**. This
migration mode will eventually change to issue **hard errors** instead
(probably in a few releases, but that depends a bit on what we find in
the wild).

One downside of migration mode is that it requires keeping around the
older code. In some cases, this older code can produce errors that
wind up masking the newer, nicer errors that are produced by the
MIR-based checker. The good news is that once we finish the migration,
this means that errors will just get better.

<a name="what-next"></a>

Finally, those of you who read the previous posts may remember that
compilation times when using the NLL checker was a big stumbling
block. I'm happy to report that the performance issues were largely
addressed: there remains some slight overhead to using NLL, but it is
largely not noticeable in practice, and I expect we'll continue to
improve it over time.

### What next?

So, now that NLL is shipping, what is next for ownership and borrowing
in Rust? That's a big question, and it has a few different answers,
depending on the "scale" of time we are looking at. The **immediate
answer** is that we've still got some bugs to nail down (small ones)
and of course we expect that once more people start banging on the new
code, they'll encounter new problems that have to be fixed. In
addition, we've got to put some energy into writing up documentation
for how the new checker works and similar things (we wound up
deviating from the RFC analysis in various ways, and it'd be nice to
document those).

In the **medium term**, the plan is to push more on the [Polonius]
formulation of NLL that [I described here][alias-based]. In addition
to offering a crisp formalization of our analysis, Polonius promises
to fix the [Problem Case #3][pc3-link] that I identified in the
original NLL introduction, along with some other cases where the
current analysis falls short.

In the **longer term**, well, that's an open question, and one where I
would like to hear from you, dear reader. Over the next week or so, I
am planning to write up a series of blog posts. Each will describe
what I consider to be a common "tricky scenario" where people hit
problems with the borrow checker, and none of which are solved by NLL.
I'll also describe the current fixes required. Then I hope to do a
survey, trying to get a picture of which of these challenges cause the
most problems for folks, so that we can try to decide how to
prioritize future improvements to Rust.

### Footnotes

[Polonius]: https://github.com/rust-lang-nursery/polonius/
[alias-based]: {{ site.baseurl }}/blog/2018/04/27/an-alias-based-formulation-of-the-borrow-checker/
[pc3-link]: {{ site.baseurl }}/blog/2016/04/27/non-lexical-lifetimes-introduction/#problem-case-3-conditional-control-flow-across-functions
