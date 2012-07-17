I have started work on implementing [Rivertrail][rt], Intel's proposal
for data parallelism in JS.  I am excited about this project, it seems
like it's going to be great fun.  The initial version that we produce
is going to be focused on Intel's [specification][spec], but I hope we
can eventually combine it with the more general stuff I've been doing
as part of PJs.  There is an awful lot of overlap between the two,
though also a few minor differences that will need to be ironed out.

[rt]: https://github.com/RiverTrail/RiverTrail/
[spec]: http://wiki.ecmascript.org/doku.php?id=strawman:data_parallelism

## Rivertrail for dummies

For those of you who don't know what it is, RiverTrail is a specification
that enables parallel array processing.  The core idea is to add a new
class, `ParallelArray`.  Parallel arrays have some key differences
from JavaScript arrays:

- They are immutable
- They never have holes
- They can be multidimensional but always in a regular way (e.g., in a
  two-dimensional matrix, each row has the same number of columns)

Parallel arrays support a wide variety of higher-order operations,
such as `map()` and `reduce()` but also others.  See the
[Rivertrail specification][spec] for the full list.  For example, you might



