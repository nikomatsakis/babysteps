[Rust, Mutability]

I've been [wrestling with Rust's mutability][mut] rules for a while
now.  There's a kind of "common wisdom" among the Rust team that we
should make some tweaks to our current rules, particularly around
vectors, but as far as I know no one has tried to write those rules
up.  I wanted to do that.  I am not sure that these rules represent
the best way to treat mutability long term, but I think they are close
to what we have and they fix the biggest immediate pain points.

[mut]: blog/categories/mutability/

The basic idea is to limit the places where `mut` declarations can
appear.  They would no longer be legal following the `~` and `@`
qualifiers.  So our types would look something like this:

    type    := ~ mq type
            |  @ mq type
            |  & mq type
            |  ~[ type ]
            |  @[ type ]
            |  & [ mq type ]
            |  ~str
            |  @str
            |  &str
            |  id
            |  scalars, fn and trait types, ...
    struct :=  "struct" { field* }
    field  := mq id: type
    mq     := mut | const | (default)
    
### Why remove mutability from vectors?

Our current system does not permit you to have functions that are
parametric over mutability. This makes it hard to write higher-order
functions over vectors.  For example, you can do:

    fn each(v: &[T], f: fn(&T) -> bool) { ... }
    
But this function only works on immutable slices.  You'd like
`each` to work on `~[T]` and `~[mut T]`.  You might think we can
use `const` for this purpose... that would look something like this:

    fn each(v: &[const T], f: fn(&const T) -> bool) { ... }

And indeed you could do this.  The problem with this is that,
typically, your callback would prefer an `&T` to an `&const T`,
because the callback must assume that the `&const T` may be
overwritten.  If `T` is an enum type or contains unique pointers, this
means that we will not be able to take a pointer into the interior of
`T`.  For example, code like this would not be permitted:

    let v: ~[Option<T>] = ...;
    for v.each |o| {
      match *o {
        Some(ref x) => { ... }
        None => { ... }
      }
    }
    
The reason is that because `o` is a const pointer, the compiler must
assume that it might be overwritten.  If `*o` were to change from
`Some(_)` to `None`, then the pointer `x` would be invalidated.  All
of this is true despite the fact that `o` is deeply immutable!  But,
by using `const`, the signature of `each` "loses" that information.

### Why remove mutability from unique and managed pointers?

Mostly because unique pointers are "owned" values.  By default, they
inherit mutability from their owner.  Instead of having a field like
`x: ~mut T`, you can simply write `mut x: ~T` and the result is
exactly equivalent.

There is however another reason.  We would like to implement an
optimization such that if you allocate a variant of an enum into a
box, such as `~None` or `@None`, the system will only allocate
precisely as much memory as is needed fo that variant (in this case,
one word).  This works great for managed data (`@`), because a
`@T` is permanently immutable, but for a `~None` it wouldn't
work as you could potentially write code like:

    let mut x = ~None;
    *x = Some(3);
    
and therefore we have to reserve space for all possible variants.

### Is this the best we can do?

I still hold out hope that we will find a painless way to write
functions that are parametric over mutability.  My basic thought at
the moment is to say that the "value" of a type parameter is not just
a type but rather a mutability/type pair.  This is kind of a more
limited version to some of my earlier proposals that avoids some of
its weirdness.  But there are details to work out that I haven't had
time to think through: in particular, the interaction with borrowck
and its ability to temporarily make mutable things immutable and so
forth.  For all I know this is No Big Deal, but it might also be a
significant complication.

