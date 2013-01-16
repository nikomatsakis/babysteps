I received some [questions on twitter][mraleph] regarding why we do
not offer an API that makes guarantees about parallel execution.
While I think that defining a subset of JS for which parallelization
is guaranteed to succeed would indeed be a great idea, I don't think
it is something that belongs in the core `ParallelArray`
specification.  Such a subset would be difficult to maintain and would
impose a very high burden on implementors.

The reality is that all existing JavaScript engines are
single-threaded.  They contain lots of code that is heavily optimized
and specialized to single-threaded scenarios.  Porting this code takes
time.  I would prefer to make it possible for each browser to carve
out a (hopefully substantially overlapping) subset of JS that can
execute in parallel and gradually increase the size of this subset,
rather than forcing them to implement a specific subset.

As a simple example, SpiderMonkey sometimes uses a rope data structure
to represent strings.  The code which does string comparison works by
first serializing the rope into a simple string and then comparing
that result.  This serialization makes use of non-thread-safe GC APIs
to allocate memory.  When ropes are not used, however, string
comparison is trivial.  In our parallel code, therefore, we will
bailout of a string comparison that involves ropes.  Is this optimal?
No, clearly not! But, so far at least, string comparison is not a high
priority for parallel code, so being able to bailout and use a
sequential fallback lets us focus on what's important.  Presuming the
`ParallelArray` specification is popular, eventually we'll come back
and mop up string comparisons.  There is a similar story for any
number of small features that are theoretically safe but which wind up
being unsafe in practice.

This is the same strategy that has been used quite successfully by
JITs over time: optimize the common and most important cases first,
then expand the set of code that you support.  It can sometimes be
frustrating for users, of course, when they encounter surprising
performance cliffs due to seemingly arbitrary changes that cause you
to leave the blessed performance path.  (To be fair to JITs, sudden
performance cliffs are endemic to computing.  They occur in all
optimizing compilers and even in the *hardware itself*, as anyone who
has unwittingly caused false sharing or other cache conflicts will
know all too well.)

I think part of the concern about guaranteed parallelization stems
from a different mindset.  I often hear talk of applications like
games where a failure to parallelize may well result in unacceptable
performance.  I am sympathetic to this concern, of course, and I think
we should provide excellent developer tools to help developers get the
the most out of the engine, including both the JIT and the parallel
execution facilities.  I envision developer tools that inform you when
your code bails out and why.

But I also hope that `ParallelArray` will be used in places where a
performance gain would be nice but is not mandatory.  
the API would likely be polyfill'd for compatibility with older
browsers.  In such cases, I suspect the last thing the developer wants
is for exceptions to be thrown because, on an user's computer, the JIT
wound up deoptimizing and causing a parallel bailout.  I am sure
they'd much rather that the program fell back to sequential and
continued to execute, albeit more slowly.  It is possible that the
user could manage such rollbacks themselves by catching exceptions,
but it'd be inconvenient and less efficient.  This would seem
comparable to having a manual JIT function that throws an exception
on failure.
