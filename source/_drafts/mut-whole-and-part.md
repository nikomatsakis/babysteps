I am still thinking about mutability and the Rust type system, but I
want to focus on a different aspect of it than what I have been
talking about.  One of the distinguishing feature of Rust is the
presence of *interior types*.  This means that Rust, like C++, allows
the programmer to control whether an aggregate value---such as a
record---is embedded directly within another record or whether it is
accessed by pointer.  In this regard Rust is quite different from
languages like Scala, Java, Ceylon, and so forth.

While interior types seem straight-forward, they actually bring a host
of complications.  One example of such complications center on
*mutability*.  I have discussed some of these issues in prior posts.
The bottom line is this: Rust allows you to declare a field of a
record as immutable.  But if that record is then embedded in a mutable
context, the field is not truly immutable, because the record as a
whole can be replaced.

To see what I mean, consider this example function.  Here we have a
type `point` which is a record with two non-mutable fields.  We then
create an instance of such a record in a mutable local variable `p`
and let the local variable `q` be the address of the `x` field.  If
`x` were truly immutable, then `*q` could never change.  But in fact
the value of `*q` *can* change:

    type point = {x: int, y: int}; // x, y immutable
    
    fn foo() {
        let mut p = {x: 3, y: 4};
        let q = &p.x; // Note: not actually legal, see below
        // Here: *q == 3
        p = {x: -3, y: -4};
        // Here: *q == -3!
    }

This program is actually not currently legal.  The line `let q = &p.x`
would have to be: `let q = &mut p.x`, thus creating a pointer of type
`&mut int`, and thus acknowleding that `q` is pointing at mutable
memory.

What this program shows is that it is incorrect to think of fields as
being declared as mutable or immutable.  It is more correct to think
of fields as being declared as definitely mutable or possibly mutable.
This rule may not be for the best but it has some interesting
implications.  I want to discuss some of those implications and then a
quick nore about possible alternative rules.

# Good implication: small mutable records.

One *good* implication of the current setup is that it is possible to
work efficiently with simple types like:

    type size = {width: int, height: int};
    type point = {x: int, y: int};
    type rect = {origin: point, size: size};
    
As you might imagine, in Servo there are quite a number of such types.
The current mutability rules allow us to do things like make the
rectangle in a box mutable:

    type layout_box = {mut rect: rect, ...};
    
but still have the idea of immutable rectangles and so forth. 

# Good implication: larval types are easy.

# Bad impliciation: public fields with invariants are hard.

# Alternatives.


