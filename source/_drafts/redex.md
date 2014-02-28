You may have noticed a distinct slowdown in the number of DST-related
posts. The reason is that I decided I couldn't make further progress
on the design until I was able to say with more specificity what the
full implications of the DST design was. To that end, I took some time
to develop a [Redex][redex] model of Rust, called
[Patina][patina]. Currently, the model includes only the operational
semantics.

### Modeling

The rough idea is to carve out a subset of Rust and model its expected
behavior mathematically. The subset should be small so as to keep it
tractable and easy to work with, but large enough to be representative
of Rust as a whole. Overtime, we can grow the model and add more
features.

The model I wrote includes the following Rust features:

- integers
- unique pointers
- borrowed pointers
- structures
- a hard-coded `Option<T>` type
- function calls and blocks

Note all the things the model does *not* include:

- enums and generalized matching -- too much tedious syntax to bother
  with, and `Option` is a fair representative of the interesting type
  theory problems.
- closures and function pointers -- these might be worth modeling at
  some point, though in principle they can be "desugared" into object
  types (and I am have [a branch][2202] which modifies the borrow
  checker to treat closures in a "desugared" way).
- generics -- eventually these would be worth it, but I'd want to study
  previous efforts at modeling monomorphization to make sure we do it
  right. For now, you expand out the types yourself (I had to do this to
  make examples of types like `RC<T>`).
  the interactions of monomorphization for now you can
  just "expand them out".
- module system -- actually very much worth modeling but orthogonal to
  my purpose at hand.
- floating point -- adds nothing compared to integers.
- ELF linkage format -- come on now. Let's move on.

### Syntax of the Rust model

Unlike real Rust programs, Rust programs in the model follow a fairly
rigid structure. They are in something similar to
[A-normal form][anorm], which means basically that we do not permit
nested expressions. Instead, we require that users introduce temporary
variables to contain the results of subexpressions.

In real Rust, there is no distinction between a statement and an
expression. In contrast, Patina draws a rigid distinction. Statements
are things that mutate the global store and program state. There are
four kinds of statements:

    st = lv = rv
       |  g<ℓ ...>(lv ...)
       |  match lv { Some(mode x) => bk None => bk }
       |  bk

The first statement `lv = rv` is an assignment. The next is a
function call (`g` is a function name, `ℓ` a lifetime. `lv` stands for an
lvalue, and it is defined as follows:

    lv = x
       | lv.f
       | lv[lv]
       | *lv

`rv` stands for rvalues:

    rv = copy lv
       | & ℓ mq lv
       | s<ℓs> { lv ... }
       
  (rv (cm lv)                      ;; copy lvalue
      (& ℓ mq lv)                  ;; take address of lvalue
      (struct s ℓs (lv ...))       ;; struct constant
      (new lv)                     ;; allocate memory
      number                       ;; constant number
      (lv + lv)                    ;; sum
      (Some lv)                    ;; create an Option with Some
      None                         ;; create an Option with None
      (vec lv ...)                 ;; create a fixed-length vector
      (vec-len lv)                 ;; extract length of a vector
      (pack lv ty)                 ;; convert fixed-length to DST


Expressions
produce new values from an existing state.


In the model, a Rust program `prog` consists of a series of structures
`srs` and functions `fns`:

    prog := srs fns
    
A structure `sr` contains lifetime parameters and a series of types
(one for each field; we omit the field names and use numbers instead):

    sr := "struct" s ℓs [ty ...]
    
A function `fn` contains a name `g`, lifetime parameters, variable
declarations `vdecls` for the parameters, and a block `bk` for the
body:

    fn     := `fun` g ℓs vdecls bk
    vdecls := [vdecl ...]
    vdecl  := x : ty

A block consists of a series of a lifetime label, local variable
declarations, and statements:


A statement can be one of four things: an assignment, a function call,
a match statement, or a block.

    mode := ref mq
         |  move
    mq   := mut
         |  imm






