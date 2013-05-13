I was talking to Dave Herman about some of the latest developments in
the Rust world an we were thinking that it'd be useful to survey the
state of the Rust type system. In particular, I'd like to look at the
various features that we are currently considering, and try to
classify which of those belong to Rust 1.0 and which are something
that will wait till afterwards.

Here is a brief summary of the upcoming work for the Rust type
system. I've classified the entries as *bugs* (fixing functionality
that largely works today but is broken in some way) or *features*
(adding new capabilities that do not exist today).

<p><table class="hor-minimalist-a">
<tr><th>Description</th><th>Classification</th><th>Timeline</th><th>Milestone</th></tr>
<tr><td>New borrowck ([#5074][borrowckbug])</td><td>Bug</td><td>Short-term</td><td>1.0</td></tr>
<tr><td>Lifetime hierarchy ([#XXX][hierarchybug])</td><td>Bug</td><td>Short-term</td><td>1.0</td></tr>
<tr><td> ([#5074][borrowckbug])</td><td>Bug</td><td>Short-term</td><td>1.0</td></tr>
<tr><td>Extern fn reform ([#XXX][externfnbug])</td><td>Feature</td><td>Short-term</td><td>1.0</td></tr>
<tr><td>Once fns ([#XXX][oncefnbug])</td><td>Feature</td><td>Medium-term</td><td>1.0</td></tr>
<tr><td>Mutable closure state ([#XXX][oncefnbug])</td><td>Feature</td><td>Medium-term</td><td>1.0</td></tr>
<tr><td>Default trait methods</td><td>Feature</td><td>Short-term</td><td>1.0</td></tr>
<tr><td>Associated items ([#XXX][associtemsbug])</td><td>Feature</td><td>?</td><td>?</td></tr>
<tr><td>Struct inheritance</td><td>Feature</td><td>Long-term</td><td>post-1.0?</td></tr>
<tr><td>Higher-kinded types</td><td>Feature</td><td>Long-term</td><td>post-1.0?</td></tr>
<tr><td>Refinement types</td><td>Feature</td><td>Long-term</td><td>post-1.0?</td></tr>
</table></p>

I'll explain the various things in that table briefly and where they
would be useful.

<!-- more -->

## New borrowck rules

I am currently working hard on a
[reformulation of the borrowck rules][borrowckbug]. Actually, the
intended rules are not changing, but the current implementation is
buggy in a number of ways, and my patch will fix them up. It it also a
reformulation of the current borrowck implementation, which I think
makes it much easier to understand. I'll leave the details of that for
another post. This is not technically a new feature, but I included it
because it is work on the type system that is underway.

[borrowckbug]: https://github.com/mozilla/rust/issues/5074

## Once fns

A "once fn" is a function that can only be called once. This is needed

## Mutable closure state

## Extern fn reform

## 



