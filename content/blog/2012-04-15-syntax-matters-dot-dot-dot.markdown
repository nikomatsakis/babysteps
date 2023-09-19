---
layout: post
title: "Syntax matters...?"
date: 2012-04-15 19:55
comments: true
categories: [PL]
---

For a long time, it was considered fairly obvious, I think, that
syntax didn't really matter.  It was just the surface skin over the
underlying ideas.  In recent times, though, the prevailing wisdom has
reversed, and it is now quite common to hear people talk about how
["syntax matters"][sm].  

While I don't exactly disagree, I think that the importance of trivial
syntactic matters is generally overemphasized.  It is not a matter of
life and death whether or not semicolons are required to end a line,
for example, or whether parentheses are required in making a call.

Naturally, like all programmers, I have strong opinions on these
topics myself---or at least I used to.  But I've found over time that
one gets used to these matters quickly enough, for the most part.  But
I think there is a deeper sense in which syntax *can* matter.

[sm]: https://www.google.com/search?q=syntax%20matters

Basically, there are some languages whose syntax is so distinctive
that it makes a qualitative difference to the experience of
programming.  In this case, having a different syntax can enable
something otherwise very challenging---or sometimes make simple things
extremely difficult.  Three examples come immediately to mind, I'm sure
there are more.

### Lisp

Lisp (and its derivatives: scheme, clojure, etc) is a common example.
The Lisp family of languages is fairly unique in that the syntax of
programs is also the same syntax of the data structures in the
language (oddly, XSLT is the only other example I can think of; but
I'm sure there are more).  This is sometimes, and somewhat
grandiously, referred to as the ["homoiconic"][hi] property.

[hi]: http://en.wikipedia.org/wiki/Homoiconicity

Homoiconicity makes it possible to have a very simple macro system
which can seamlessly integrate with the language.  This is simply
very, very challenging to do with a more traditional C-like syntax.
So, in this case, syntax really matters.

### Smalltalk

Most languages pass the parameters to a method using a position
notation.  This may be written with parentheses (`foo(a, b, c)`) or
without (`foo a b c`) but the idea is basically the same.  Smalltalk
took a different approach.  In Smalltalk, each parameter is labeled,
and the name of the method as a whole is the concatenation of all of
these labels.  So you don't write `foo.open("abc", true, false)` but
rather `foo open:"abc" read:true write:false`.  This may seem like a
small change, but it is not.  It has far-reaching consequences;
consequences which I think are not fully appreciated.  For example, it
is no accident that Smalltalk pioneered most of the powerful
refactorings we associate with Java and other statically typed
languages today---method names in Smalltalk are long and generally
unique, so you don't need full type information for the compiler to
reliably trace them.

Another effect of this convention is to make certain classes of errors
impossible.  For example, one simply cannot provide the wrong number
of parameters to a method (the method name would not match).
Similarly, it is obvious what each parameter means and in what order
they should go.  With a call like `foo.open("abc", true, false)`, the
reader has no idea what `true` and `false` signify.  When the call
looks like this, `foo.open("abc", write, read)`, the reader *thinks*
they know what `write` and `read` signify, but without seeing the
source of the method, they can't know for sure.  In fact, here, I
reversed the order.  This kind of error is surprisingly common, as an
old colleague of mine [described in a paper][pradel].  But this error
is unthinkable in Smalltalk, as you would have to write `foo
openFile:"abc" read:write write:read`, making it quite clear that
something was amiss.

[pradel]: http://mp.binaervarianz.de/issta2011.pdf

### Fortress

I had the good fortune of talking to some of the guys on the Fortress
team a while back.  Fortress is home to some very interesting
ideas---parallel evaluation by default, for example!---and one of them
is that mathematical programs ought to be written in mathematical
notation, or something very close to it.  I can see that this is a
very appealing notion for mathematicians and physicists, as it will
help to lower the impedance barrier between the program and the theory
it models.  But it is also interesting for the developers of Fortress,
since mathematical notation is incredibly overloaded---meaning that
they are developing all manner of interesting new dynamic overloading
resolution techniques to make this whole thing work.  So in this case,
the syntax is a mixed bag: it makes some things easier (translating
math) and some things harder (defining the language semantics).

### The siren call of pretty syntax

So yes, I do think syntax can matter.  But most of the time it
doesn't.  This is not to say I am immune to the appeal of pretty
syntax (I'm as guilty as everyone else), nor that prettiness doesn't
matter at all.  But mostly it's a matter of *familiarity*.  Like
anything else, a new language will look a bit different, and you have
to get used to it. (Even Objective C looks pretty good to me now, for
crying out loud!)  Sometimes, though, things still seem hard to read
even after you've been hacking in the language for a while: these are
things that need changing.

It is important, however, to distinguish between *syntax* and
*expressiveness*.  I don't care (too much) whether you write
`function(x) { ... }`, `\x -> ...` or `{ |x| ... }` to denote a
closure, but there had better be a way to write a closure somehow!
(Java, I'm looking at you here)

It makes me a bit sad that there is so much focus these days on the
surface side of syntax---making indentation significant, omitting a
semicolon---but rather little on how a change in syntax can actually
change the experience of programming in a deeper way.

*Aside #1:* It is too bad that the genuine advantages of
Lisp and Smalltalk syntax do not seem to have been sufficient to win
over the familiarity of a generally C-like look-and-feel.

*Aside #2:* In case you can't tell, I'm partially responding to the
fact that every time somebody posts a link about Rust, somebody else
makes some comment about the length of our keywords.  My personal
favorite is [this one][hn], which seems to imply that we Rust
developers are involved in some kind of conspiracy---as if we *prefer*
endlessly defending our choice of `ret` over `return` rather than,
say, our choice of sendable unique pointers over shared memory.
Please.

*Aside #3:* To be clear, I don't think Rust's syntax is anything
revolutionary.  It is basically a C derivative, like so many languages
these days.

[hn]: http://news.ycombinator.com/item?id=3826528

