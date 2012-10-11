## C++-Style references

I have been entertaining a thought experiment.  When designing the
region system, we opted to make `&T` basically the safe equivalent of
a C pointer.  That is, if you had an `&T` and you wanted a value of
type `T`, you have to dereference the pointer.  Similarly, if you want
to create an `&T`, you use the `&` operator to take the address of an
existing lvalue.

However, C++ references (the `T&` type in C++) work rather
differently.  Although they are pointers at runtime, they act exactly
like an instance of `T` in every other way.  There is no operator to
create a reference; instead, lvalues of type `T` actually have the
type `T&`.  `T&` can be assigned to `T` as needed, inducing a copy.

I haven't worked with C++ rvalue references (`T&&`) but I imagine that
they work similarly.  Every rvalue that used to be of type `T`
actually has type `T&&`, `T& <: T&&`, and `T&&` is assignable to `T`.

Many parts of the system could readily be converted to a C++-like
approach.  There are a few rough spots.  


For a brief while I entertained a "thought experiment"---what if we
made region pointers be more like C++ references.  That is, you
wouldn't have to "derefence" them.  The `&` operator would go away;
instead, you create a reference just by assigning to a variable with
reference type.  I think you can create a rather nice system in this
way, but there is a fly in the ointment: type inference.  Basically,
what this system amounts to, is something like applying "auto-ref" to
all function arguments.  And the problem is that we often don't know
the full type of function arguments, so you don't know when to
"auto-ref".  Now, to be fair, the current auto-borrow rules have the
same problem; in practice, it is minimal, both because we aren't doing
that much borrowing yet and because the type inferencer often knows
*enough* about the types in question to know whether a borrow is
needed or not. However, the auto-borrow rules have the advantage that
there is always an out.

