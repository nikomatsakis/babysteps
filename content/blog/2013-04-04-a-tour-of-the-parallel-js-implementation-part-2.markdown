---
layout: post
title: "A tour of the Parallel JS implementation (Part 2)"
date: 2013-04-04T10:17:00Z
comments: true
categories: [PJs, JS]
---

In my [last post about ParallelJS][pp], I discussed the `ForkJoin()`
intrinsic and showed how it was used to implement the parallel map
operation.  Today I want to write about the high-level changes to
IonMonkey that are needed to support `ForkJoin()`.  IonMonkey, of
course, is our JavaScript engine.

### Parallel execution mode

To support ParallelJS, we introduce a second mode of compilation
called *parallel execution mode*. JavaScript compiled in this mode
produces executable code that is suitable to be run in parallel.  To
accommodate this new mode, each `JSScript*` potentially contains
pointers to two `IonScript*` data structures, one for standard
sequential mode and one for parallel mode. 

Execution normally stays confined within one mode.  So if you are
running a function `f` in sequential mode and it invokes another
function `g`, then we will run the sequential mode version of `g`.
But if you are running `f` in *parallel mode*, it will call the
parallel version of `g`.  The only place where we move between modes
is in the `ForkJoin` intrinsic, which invokes the parallel mode script
for the first time.

You may wonder why we permit each script to be compiled in both modes
simultaneously. The reason is that it is possible to have helper
functions and code that runs in both sequential and parallel mode.
Imagine, for example, that you have a helper function for searching
an array to find the object with a given name:

    function findObject(list, name) {
        for (var i = 0; i < list.length; i++) {
            if (list[i].name === name)
                return list[i];
        }
        throw Error("No object with name " + name + " found!");
    }
    
It is perfectly reasonable to want to invoke this helper function both
from sequential and from parallel code. If we only permitted a
function to be compiled in one mode or the other, we would always be
recompiling `findObject` each time we started or finished a parallel
operation.

### Differences between parallel and sequential execution mode

The biggest difference between parallel and sequential mode is that
code executing in parallel mode is guaranteed to be *pure*.  That is,
it can never write to any shared state that might be visible from
other threads. This purity requirement generally includes not only
user-visible JavaScript state but also internal engine details. For
example, in sequential mode code, after we have done several property
lookups on an object that has a large number of properties, we will
"hashify" the property chain, meaning that we convert it from an array
into a dictionary to make later lookups faster. This hashification
operation is not visible to the JavaScript user (except insofar as
subsequent property lookups are faster), but it is still disallowed in
parallel execution mode because it would cause data races.

There are some exceptions to the purity requirement.  The first and
most obvious is the `UnsafeSetElement` intrinsic I discussed in
[part one][pp], which is used to track the progress of parallel
work. The second exception is that it is ok to modify internal engine
details so long as those modifications are threadsafe. For example, in
[bug 846111][846111], Shu has implemented threadsafe inline-caching, which is of
course a mutation to shared state.

Generally speaking, though, when you call a parallel mode function you
can be sure that it will either complete successfully or bailout.  In
either case, you know that it has no lasting effects that are visible
to end-user JavaScript code, except those that might have occurred via
the `UnsafeSetElement` intrinsic (which of course is only usable from
self-hosted code and which must be carefully audited).

### Changes to the Ion compilation process

There are two major changes when compiling in `ParallelExecutionMode`:
The first change is the so-called "parallel array analysis", which
analyzes the actions that the scripts take and modifies them as needed
to ensure that each action is either threadsafe (and pure) or else
that the script bails out. The second change is that do not compile a
single script in isolation but rather attempt to compile the
transitive closure of a starting script and all scripts that it may
call.

#### Parallel array analysis

The parallel array analysis can be found in
[`js/src/ion/ParallelArrayAnalysis.cpp`][paacpp], in the function
`ParallelCompileContext::analyzeAndGrowWorklist()`.  It runs after the
normal suite of optimizations have taken place.  Its primary goal is
to ensure that the parallel code will be pure and threadsafe.

To that end, it performs a walk of the control-flow graph and examines
each MIR instruction using a visitor. The MIR instructions are
[categorized into one of several categories][paacat], as follows:

- *Safe operations* are operations that can be safely executed in parallel
  without changes, such as `Constant` or `Box`.
- *Write-guarded operations* are operations that are safe as long as
  the value being modified is not shared.  To verify this, we insert a
  write guard before the operation in question.  The write guard will
  cause a bailout should the object be shared (more on the details of
  this check to come in a later post). N.B.---write guards are not to
  be confused with write *barriers*, which have to do with incremental
  and generational garbage collection.
- *Specialized operations* are numeric operations that are safe so long
  as they are operating over scalar data, such as `Add`, `Mul`, etc.
- *Unsafe operations* are operations that are just plain disallowed in
  parallel execution, generally because we have not made an
  equivalent threadsafe path.  An example is `RegExp`.
- *Custom operations* are, well, everything else.  Generally speaking
  these are operations that are not safe by default in parallel mode,
  but where there exists an alternative version that *is* safe,
  such as `NewArray` or `NewObject`.
  
The categorization of instructions is [done using macros][paamacros]. The
visitor expects one method per MIR instruction type. There are various
macros for each of the above categories, and the macro expands into a
pre-canned method definition (in the case of custom operations, the
macro expands to an out-of-line method, and the method body appears
later in the file).

I'll talk a little bit more about the safe and unsafe operations now,
and I'll cover the other cases (write guards, memory allocation, etc)
in later posts. 

Safe operations are simply left unchanged, and they execute just as
they would in sequential mode (though in some cases there are checks
in the `CodeGenerator` so that the MIR behaves somewhat differently).

When an unsafe operation is encountered, the basic block in which it
resides is removed from the graph along with its dominated subtree.
In its place, we add a bailout block that will cause parallel
execution to bailout should it ever execute. This ensures that unsafe
operations that never execute do not prohibit safe code from running.

#### Transitive compilation

In normal sequential mode, if we encounter a call to a script that is
not compiled, we just invoke the interpreter. In parallel mode this
option is not available. So what we do instead is to take advantage of
the information that TI makes available and, when compiling a script
*x*, collect all scripts that *x* might call. Then, once we have
compiled *x*, we go on and compile those scripts. The process is
transitive, meaning that we will then continue on to compile the
scripts that *x*'s callees might call and so forth until we reach a
fixed point.

Note that we do not monitor for hot paths, as we do in sequential
mode.  That is, we don't care if the script has been called 10 times
or 100 times before.  This is for two reasons: one, we assume that
parallel paths are going to be hot, since they are going to be called
over all the entries in a large array.  Two, seeing as we will have to
bailout if we encounter a call to an uncompiled script, it's worth
erring on the side of more compilation rather than less. We do however
check that the use count of the script is at least *one*, so as to
avoid compiling things that never run.

At runtime, when we see a call to a JavaScript function, we check
whether it has been compiled for parallel execution.  If so, we can
simply call it as normal and carry on.  This is the expected case, of
course.

If we encounter a call to an uncompiled script, which can happen
either because our transitive compilation was incomplete or because
the callee was invalidated or garbage-collected in the mean-time, we
bailout with an "uncompiled script" error.  At this point, control
returns to
[the `ForkJoin` function I described in my previous post][pp].
Presuming that we haven't encountered too many bailouts yet,
`ForkJoin` will cycle around and try to compile the uncompiled script.

When compiling an uncompiled script, we also set a flag on all the
currently executing scripts in the stack trace.  This flag is a
warning that execution of that script is likely to encounter an
uncompiled script.  The purpose for this flag is to notify later
callers that while the script itself is valid, it likely has callees
that have not been compiled, so before running the script in parallel
we should re-walk the transitive closure of things it might call and
check for anything that is missing.

<!-- LINKS -->

[pp]: {{< baseurl >}}/blog/2013/03/20/a-tour-of-the-parallel-js-implementation
[paacpp]: http://hg.mozilla.org/mozilla-central/file/c232bec6974d/js/src/ion/ParallelArrayAnalysis.cpp
[paacat]: http://hg.mozilla.org/mozilla-central/file/c232bec6974d/js/src/ion/ParallelArrayAnalysis.cpp#l121
[paamacros]: http://hg.mozilla.org/mozilla-central/file/c232bec6974d/js/src/ion/ParallelArrayAnalysis.cpp#l29
[846111]: https://bugzilla.mozilla.org/show_bug.cgi?id=846111
