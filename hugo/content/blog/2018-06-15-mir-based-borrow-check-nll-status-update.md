---
categories:
- Rust
- NLL
date: "2018-06-15T00:00:00Z"
slug: mir-based-borrow-check-nll-status-update
title: MIR-based borrow check (NLL) status update
---

I've been getting a lot of questions about the status of "Non-lexical
lifetimes" (NLL) -- or, as I prefer to call it these days, the
MIR-based borrow checker -- so I wanted to post a status
update.

**The single most important fact is that the MIR-based borrow check is
feature complete and available on nightly. What this means is that
the behavior of `#![feature(nll)]` is roughly what we intend to ship
for "version 1", except that (a) the performance needs work and (b) we
are still improving the diagnostics.** (More on those points later.)

The MIR-based borrow check as currently implemented represents a huge
step forward from the existing borrow checker, for two reasons.
First, it eliminates a ton of borrow check errors, resulting in a much
smoother compilation experience. Second, it has a lot less bugs. More
on this point later too.

You may be wondering how this all relates to the "alias-based borrow
check" that I outlined in [my previous post][pp], which we have since
dubbed [Polonius]. We have implemented that analysis and solved the
performance hurdles that it used to have, but it will still take some
effort to get it fully ready to ship. The plan is to defer that work
and ultimately ship Polonius as a second step: it will basically be a
"MIR-based borrow check 2.0", offering even fewer errors.

[pp]: {{ site.baseurl }}/blog/2018/04/27/an-alias-based-formulation-of-the-borrow-checker/

[Polonius]: https://github.com/rust-lang-nursery/polonius/

### Would you like to help?

If you'd like to be involved, we'd love to have you! The NLL working
group hangs out [on the `#wg-nll` stream in Zulip][zulip]. We have
weekly meetings on Tuesdays (3:30pm Eastern time) where we discuss the
priorities for the week and try to dole out tasks. If that time
doesn't work for you, you can of course pop in any time and
communicate asynchronously. You can also always go look for work to do
amongst [the list of GitHub issues][ghi] -- probably the [diagnostics
issues][diag] are the best place to start.

[zulip]: https://rust-lang.zulipchat.com/#narrow/stream/122657-wg-nll
[ghi]: https://github.com/rust-lang/rust/issues?utf8=%E2%9C%93&q=is%3Aopen+label%3AWG-compiler-nll+-label%3ANLL-deferred
[diag]: https://github.com/rust-lang/rust/labels/NLL-diagnostics

### Transition period

As I mentioned earlier, the MIR-based borrow checker [fixes a lot of
bugs] -- this is largely a side effect of making the check operate
over the [MIR]. This is great! However, as a result, we can't just
"flip the switch" and enable the MIR-based borrow checker by default,
since that would break existing crates (I don't really know how many
yet). The plan therefore is to have a transition period. 

[fixes a lot of bugs]: https://github.com/rust-lang/rust/labels/NLL-fixed-by-NLL
[MIR]: https://blog.rust-lang.org/2016/04/19/MIR.html

During the transition period, we will issue warnings if your program
*used* to compile with the old borrow checker but doesn't with the new
checker (because we fixed a bug in the borrow check). The way we do
this is to run *both* the old and the new borrow checker. If the new
checker would report an error, we first check if the old check would
*also* report an error. If so, we can issue the error as normal. If
not, we issue only a warning, since that represents a case that used
to compile but no longer does.

The good news is that while the MIR-based checker fixes a lot of bugs,
it also accepts a lot more code. This lessens the overall impact. That
is, there is a lot of code which ought to have gotten errors from the
old borrow check (but never did), but most of that code won't get any
errors at all under the new check. No harm, no foul. =)

### Performance

One of the main things we are working on is the performance of the
MIR-based checker, since enabling the MIR-based borrow checker
currently implies significant overhead during compilation. Take a look
at this chart, which plots rustc build times for the [`clap`
crate](https://crates.io/crates/clap):

![clap-rs performance](https://i.imgur.com/kyqmx4I.png)

The black line ("clean") represents the "from scratch" build time with
rustc today. The orange line ("nll") represents "from scratch" build
times when NLL is enabled. (The other lines represent incremental
build times in various combinations.) You can see we've come a long
way, but there is still plenty of work to do. 

[51460]: https://github.com/rust-lang/rust/pull/51460
[20%]: http://perf.rust-lang.org/compare.html?start=61d88318aa66669fba061e9af529365172d63cd0&end=757cd050fc1ef84d7235d6f4d9228189eed878cc&stat=instructions%3Au
[NLL dashboard]: http://perf.rust-lang.org/nll-dashboard.html

The biggest problem at this point is that we effectively have to
"re-run" the type check a second time on the MIR, in order to compute
all the lifetimes. This means we are doing two type-checks, and that
is expensive.  However, this second type check can be significantly
simpler than the original: most of the "heavy lifting" has been
done. Moreover, there are lots of opportunities to cache work between
them so that it only has to be done once. So I'm confident we'll make
big strides here. (For example, I've got a [PR up right now][51460]
that [adds some simple memoization for a 20% win][20%], and I'm
working on follow-ups that add much more aggressive memoization.)

(There is an interesting corollary to this: after the transition
period, the first type check will have no need to consider lifetimes
*at all*, which I think means we should be able to make it run quite a
bit faster as well, which should mean a shorter "time till first
error" and also help things like computing autocompletion information
for the RLS.)

### Diagnostics

It's not enough to point out problems in the code, we also have to
explain the error in an understandable way. We've put a lot of effort
into our existing borrow checker's error message. In some cases, the
MIR-based borrow checker actually does better here.  It has access to
more information, which means it can be more specific than the older
checker. As an example[^sk], consider this error that the old borrow
checker gives:

[^sk]: Hat tip to steveklabnik for providing this example!

```
error[E0597]: `json` does not live long enough
  --> src\main.rs:38:17
   |
38 |         let v = json["data"]["search"]["edges"].as_array();
   |                 ^^^^ borrowed value does not live long enough
...
52 |     }
   |     - `json` dropped here while still borrowed
...
90 | }
   | - borrowed value needs to live until here
```

The error isn't bad, but you'll note that while it says "borrowed
value needs to live until here" it doesn't tell you *why* the borrowed
value needs to live that long -- only that it does. Compare that to the
new error you get from the same code:

```
error[E0597]: `json` does not live long enough
  --> src\main.rs:39:17
   |
39 |         let v = json["data"]["search"]["edges"].as_array();
   |                 ^^^^ borrowed value does not live long enough
...
53 |     }
   |     - borrowed value only lives until here
...
70 |             ", last_cursor))
   |                ----------- borrow later used here
```

The new error doesn't tell you "how long" the borrow must last, it
points to a concrete use. That's great.

Other times, though, the errors from the new checker are not as good.
This is particularly true when it comes to suggestions and tips for
how to fix things. We've gone through all of our internal diagnostic
tests and drawn up a [list of about 37
issues][diag],
documenting each point where the checker's message is not as good as
the old one, and we're working now on drilling through this list.

### Polonius

In my [previous blog post][pp], I described a new version of the
borrow check, which we have since dubbed [Polonius]. That analysis
further improves on the MIR-based borrow check that is in Nightly
now. The most significant improvement that Polonius brings has to do
with "conditional returns".  Consider this example:

```rust
fn foo<T>(vec: &mut Vec<T>) -> &T {
  let r = &vec[0];
  if some_condition(r) {
    return r;
  }
  
  // Question: can we mutate `vec` here? On Nightly,
  // you get an error, because a reference that is returned (like `r`)
  // is considered to be in scope until the end of the function,
  // even if that return only happens conditionally. Polonius can
  // accept this code.
  vec.push(...);
}
```

In this example, `vec` is borrowed to produce `r`, and `r` is then
returned -- but only *sometimes*. In the MIR borrowck on nightly, this
will give an error -- when `r` is returned, the borrow is forced to
last until the end of `foo`, no matter what path we take. The Polonius
analysis is more precise, and understands that, outside of the `if`,
`vec` is no longer referenced by any live references.

We originally intended for NLL to accept examples like this: in [the
RFC], this was called [Problem Case #3][pc3]. However, we had to
remove that support because it was simply killing compilation times,
and there were also cases where it wasn't as precise as we wanted.  Of
course, some of you may recall that in my [previous post about
Polonius][pp] I wrote:

> ...the performance has a long way to go (\[Polonius\] is currently
> slower than existing analysis).

I'm happy to report that this problem is basically solved. Despite the
increased precision, the Polonius analysis is now easily as fast as
the existing Nightly analysis, thanks some smarter encoding of the
rules as well as the move to use
[datafrog](https://github.com/frankmcsherry/blog/blob/master/posts/2018-05-19.md).
We've not done detailed comparisons, but I consider this problem
essentially solved.

[the RFC]: https://rust-lang.github.io/rfcs/2094-nll.html
[pc3]: https://rust-lang.github.io/rfcs/2094-nll.html#problem-case-3-conditional-control-flow-across-functions

If you'd like, you can try Polonius today using the `-Zpolonius`
switch to Nightly. However, keep in mind that this would be a
'pre-alpha' state: there are still some known bugs that we have not
prioritized fixing and so forth.

### Conclusion

The key take-aways here:

- NLL is in a "feature complete" state on Nightly.
- We are doing a focused push on diagnostics and performance, primarily.
- Even once it ships, we can expect further improvements in the
  future, as we bring in the Polonius analysis.
