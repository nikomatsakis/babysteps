---
categories:
- Rust
comments: true
date: "2012-04-17T00:00:00Z"
published: false
slug: instance-coherence
title: Instance coherence
---

After yesterday's dalliance in
[Matters of a Truly Trivial Nature][trivial], I'd like to return to
[Matters Most Deep and Profound][ros].  That is, I want to dive a bit
more into Rust's object system and in particular our treatment of the
instance coherence problem.  This is basically the same idea as is
contained in an [e-mail I sent to the rust-dev mailing list][email],
but perhaps with a bit more commentary and with updated syntax.

[trivial]: blog/2012/04/15/syntax-matters-dot-dot-dot/
[ros]: blog/2012/04/09/rusts-object-system/
[email]: https://mail.mozilla.org/pipermail/rust-dev/2011-December/001036.html

### Lexically scoped impls

In the previous post, I mentioned that you can use `impl` declarations
to extend a class with new methods.  What may not have been entirely
clear is that an `impl` declaration can, in fact, apply to *any* type.
So, if I wanted to make an absolute value method for integers, I might
write:

    impl methods for int {
        fn abs() -> int {
            if self >= 0 {self} else {-self}
        }
    }
    
Note that this declaration did not mention any interface.  Instead, I
just deeclared an impl named `methods` for the type `int`.  So long as
this impl is in scope, I can then write code like `5.abs()` or
`i.abs()` where `i` has type `int`.

But wait, what do I mean by "as long as this impl is in scope"?
Basically, impls follow the usual lexical scoping rules: in effect,
this means that an impl is in scope within the module where it is
declared and any submodules, along with any other modules that
explicitly import it.

So, suppose I make a module util containing that impl I just showed you:

    mod util {
        impl methods for int {
            fn abs() -> int { ... }
        }
    }

Now, if I off in some other unrelated modula `X`, and I write
`i.abs()`, I will get an error, because the `methods` impl is in scope
in the `util` module but not in `X`.  To use the `abs()` method, I must
import it:

    mod X {
        import util::methods;
        
        fn compute(i: int) -> int {
            ... i.abs() ...
        }
    }

The import declaration brings the method into scope.  

### Comparison between Rust and other languages

For those familiar with other languages, I thought people might want
to understand better how Rust's impls compare to, say, Haskell's
typeclasses or C#'s extension methods.  

The impl mechanism is modeled on Haskell's typeclasses, though we
chose to use more standard OOP terminology (in general, we tried to
integrate typeclasses with the standard OOP approach, as we I
described in my [previous post][ros]).  Our interfaces are roughly
comparable to Haskell's typeclasses (though less powerful in some
regards) and an impl is roughly comparable to an instance of a
typeclass.

Haskell, however, has no mechanism for scoping of typeclass instances.
A given typeclass can only have a single instance for any given type.
As a result, if two libraries both define instances of the same
typeclass for the same type, they cannot be combined into one program.
This is a serious limitation.

Impls are similar to C#'s [extension methods][csharp] but
significantly more powerful.  The difference in power derives from the
fact that impls can implement an interface on behalf of a type, and
thus integrate fully with dynamic dispatch based on interfaces.
Basically, using impls, there is no real difference between the
methods defined on a class and those defined on any other type (like,
say, `int`), except that the latter must be imported.  In C#, in
contrast, a call to an extension method is always resolved statically;
it's basically syntactic sugar for a static function call.

Of course, many other languages offer methods to extend classes:
Objective-C has [categories][cat]; Ruby, Python, and JavaScript let
you do just about anything by mucking about with the class objects or
prototypes themselves; [Kotlin][kotlin] has extension methods that
appear to be modeled on C#; Scala has its implicit conversion
wrappers; etc.  There are also research approaches like
[MultiJava][mj]. I won't go into detailed comparisons against all of
them, they each have their strengths and weaknesses.  

[csharp]: http://msdn.microsoft.com/en-us/library/bb383977.aspx
[cat]: http://developer.apple.com/library/ios/#documentation/cocoa/conceptual/objectivec/chapters/occategories.html
[mj]: http://multijava.sourceforge.net/
[kotlin]: http://confluence.jetbrains.net/display/Kotlin/Extension+functions
[defender]: http://cr.openjdk.java.net/~briangoetz/lambda/Defender%20Methods%20v3.pdf

### Potential pitfalls

I mentioned that Haskell only allows one implementation of a given
instance per type per typeclass.  This is not an accident or
oversight, of course, but a deliberate design decision.  It avoids
certain nasty scenarios.  One particularly important one is what I've
been calling the Hashtable Problem, but which is more traditionally
referred to as "instance coherence".

To see what the problem is, imagine that we had an interface `hash`
which can be used for the keys in structures based on hashing:

    iface hash {
        fn eq(s: self) -> bool;
        fn hash() -> uint;
    }

The interface consists of two methods.  The first, `eq()`, defines
equality of two keys.  It makes use of the `self` type to assert that
the other key must also be of the same type as the receiver (the
`self` type will get a post of its own, never fear).  The second,
`hash()`, hashes the receiver and returns the result.  The implementor
must naturally ensure that any two values which are equal also have
the same hash code.


