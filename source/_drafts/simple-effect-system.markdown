Currently, Rust has an effect system but refuses to admit it.  In an
effort to broaden the set of things that can be safely done in the
face of extant aliases into the heap, I have been experimenting with a
lightweight extension to Rust's system.  So far I think it is
promising but also no magic bullet.

### Background

For those who aren't familiar with the term, an "effect system" is
basically just a fancy name for tagging functions with some extra
information beyond the types of their arguments and their return type.

Effect systems vary wildly in their complexity and in their purpose.
Probably the most widely deployed---and perhaps least popular---effect
system is Java's system of checked exceptions.  In that system, the
"effect" is the list of exceptions that may get thrown during the
execution of the function.  (In the research literature, effects are
used for everything from ensuring [consistent lock use][SafeJava] to
[bridging functional and imperative software][FX] to
[supporting safe, live updates of running software][rs], and that's
just getting started).

[SafeJava]: http://pmg.csail.mit.edu/pubs/boyapati04safejava-abstract.html
[FX]: http://citeseerx.ist.psu.edu/viewdoc/summary?doi=10.1.1.62.534
[rs]: foo

The truth is, though, that effect systems as commonly envisioned do
not scale, and every Java programmers already knows this very well.
The problem is that language designers face an annoying choice.  They
can take the Java route and keep the system very simple.  Things work
pretty well as long as your classes are all very concrete.  But when
you get to a highly abstract interface like `Runnable`, you start to
run into trouble: what exceptions should the `run()` method of
`Runnable` *throw*, anyhow?  Obviously it's impossible to say, as the
interface can be used for any number of things.

The traditional solution to this problem is to allow *effect
parameterization*. If you're not careful, though, the sickness can
easily be worse than the disease.  Effect parameterization is
basically like generic types, except that instead of defining your
class in terms of an unknown type, you are defining it in terms of an
unknown set of effects.  To continue with the Java example, this would
mean that `Runnable` does not declare the set of types that the
`run()` method may throw but rather is defined something like this:

    interface Runnable<throws E> {
        void run() throws E;
    }

Now, this is a bit confusing, because it looks like `E` is a type (and
in fact you can define Java like this where `E` is a type).  But I
added the extra `throws` keyword to try and make it clear that `E`
here is *not* a type parameter, but an effect parameter: its value, so
to speak, is not a single type, but rather a set of exception types
that may be thrown.  So perhaps I might define a concrete `Runnable`
like (this syntax is again imaginary, and even ambiguous to boot, but
hopefully you get the idea):

    class RunnableThatUsesFilesAndJoinsThreads
    implements Runnable<throws IOException, InterruptedException>
    {
        void run() throws IOException, InterruptedException {
            ...
        }
    }
    
Obviously I think both of these solutions are unacceptable.  The first
(Java as it is today) because it is too inexpressive and the second
(hypothetical, parametric Java) because it is a pain.

### Rust today



### Rust tomorrow, perhaps?

### Going even further
