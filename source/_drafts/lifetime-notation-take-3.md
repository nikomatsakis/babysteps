There has been a [very interesting thread][thread] about lifetimes on
rust-dev recently, and it has inspired a new idea for how to approach
the lifetime notation that I've been wrestling with lately.  I wanted
to sketch out this approach in more detail and highlight some of its
potential advantages.

The key idea is to use a consistent lexical scheme for identifying
lifetimes.  I currently favor the notation `'lt`, borrowed from ML's
typenames or LISP symbols, to mean "a lifetime named `lt`".  This
means that a borrowed pointer with an explicit lifetime would be
written `&'lt Foo` instead of `&lt/Foo`.  Lifetime parameters would be
placed in `<>` along with other type parameters, so you'd write
`StringReader<'lt>` to mean "a `StringReader which contains borrowed
pointers whose lifetime is 'lt`.

There are several advantages to using a distinct lexical symbol.  It's
easier to syntax highlight, for one thing.  It's easier 
