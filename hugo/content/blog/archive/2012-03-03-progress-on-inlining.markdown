---
categories:
- Rust
comments: true
date: "2012-03-03T00:00:00Z"
slug: progress-on-inlining
title: Progress on inlining
---

Cross-crate inlining has come a long way and is now basically
functional (I have yet to write a comprehensive test suite, so I'm
sure it will fail when exercising various corners of the language).

Just for fun, I did some preliminary micro-benchmarks.  The results
are not that surprising: removing method call overhead makes programs
run faster! But it's still nice to see things go faster.  We'll look
at the benchmarks, see the results, and then dive into the generated
assembly.  In all cases, I found LLVM doing optimizations that rather
surprised me.

### How to use it

Actually, `rustc` has been doing inlining without any special
annotations for a long time---but only within one crate.  If you want
to enable a function to be inlined when called from another crate, you
simply have to add an `#[inline]` annotation to it, like so:

    #[inline]
    fn range(lo: uint, hi: uint, it: fn(uint)) {
        let i = lo;
        while i < hi { it(i); i += 1u; }
    }

This is the `uint::range()` function, which simply invokes its
argument on every integer in a particular range.  

The reason that an annotation is required to inline calls to functions
in other crates is that cross-crate inlining complicates the
recompilation model.  Normally, crates are dynamically linked, so if
you change the implementation of a function but not its type
signature, then there is no need to recompile dependent crates or
programs.  However, if an *inlined* function is changed, then every
caller *must* be recompiled in order to observe that change, as the
source of that function will have been inlined into their local
compilation units (of course, if the inlined function is not exported
or not used, then there is again no need to recompile dependent
crates).

The `#[inline]` directive currently takes one option: you can write
`#[inline(always)]`.  The difference is that the former is a hint,
which the compiler may choose to ignore.  The `always` directive makes
the hint stronger, causing the compiler to ignore the typical
heuristics and thresholds that it uses to decide when to inline.
Currently, these hints are passed on directly to LLVM; unfortunately,
I have found that if you do not write `#[inline(always)]`, LLVM almost
always chooses not to inline, so probably we have to adjust the
heuristics somewhat for Rust code.

### Benchmark #1: `uint::range`

`uint::range` is Rust's way of iterating over a range of integers.
The following simple program simply sums up the integers from `0`
to `N`, where `N` is provided on the command line:

    fn main(args: [str]) {
        let r = option::get(uint::from_str(args[1]));
        let sum = 0u;
        uint::range(0u, r) {|i|
            sum += i;
        }
        io::print(#fmt["Sum from 0 to %u is %u\n", r, sum]);
    }

Before inlining, this program would literally create a stack closure
for the body of the loop and pass it to the library function range
(the source of which was shown above).  Range would then iterate and
invoke the closure on every iteration.

We'll look at the generated assembly shortly.  But first, let's see
some simple performance measurements:

    ; rustc -O --inline --monomorphize ~/tmp/iterator.rs
    ; time ~/tmp/iterator 10000000000
    Sum from 0 to 10000000000 is 13106511847580896768
    
    real	0m0.016s
    user	0m0.010s
    sys	0m0.006s
    ; rustc -O ~/tmp/iterator.rs -o ~/tmp/iterator-no-inline
    ; time ~/tmp/iterator-no-inline 10000000000
    Sum from 0 to 10000000000 is 13106511847580896768
    
    real	0m48.217s
    user	0m48.203s
    sys	0m0.014s
    
As you can see, the inlining optimizations are still not enabled by
default (at least on my machine, compilation does succeed with
inlining enabled (or it did when I last tested it), but I am still not
happy with the auto-generation of the serialization code and so I did
not want to have the main build of the compiler depend on it yet).
However, there is a big difference between the inlined and non-inlined
version of this benchmark!  The non-inlined form took about 3013 times
as long!  We'll see why this is when we dig into the generated
assembly.  The reasons surprised me a bit.

#### Generated assembly

A (somewhat simplified and annotated) extract of the generated
assembly for the `uint::range()` example is below.  Actually, LLVM is
amusingly both *extremely* smart and kind of dumb here.  The actual
computation of the sum has been removed and turned into an algebraic
formula.  After that formula is computed, then there is a useless
little while loop that just iterates from 0 to n doing nothing:

      ...
    Ltmp3:
      ; initialize sum to 0u
      ; and branch out if `r` is 0
      movq    $0, -56(%rbp)
      movq    -48(%rbp), %rcx
      testq   %rcx, %rcx
      je      LBB0_9
      
      ; compute (r*(r-1)) / 2
      ; (closed form of summation)
      ; and store into %rdx
      leaq    -1(%rcx), %rax
      leaq    -2(%rcx), %rdx
      mulq    %rdx
      shldq   $63, %rax, %rdx
      addq    %rcx, %rdx
      
      ; loop r times doing nothing
    LBB0_7:
      decq    %rcx
      jne     LBB0_7
      
      ; store final result of summation
      ; and move on
      decq    %rdx
      movq    %rdx, -56(%rbp)
      
    LBB0_9:
      ...
      
### Benchmark #2: `vec::iter`

Well, that benchmark was fun but since LLVM got so smart it's not as
interesting as I'd like.  So I wrote up another one that uses
`vec::iter()`.  This will also have the added benefit of showing off
Marijn's work on monomorphization, which optimizes our treatment of
generic functions.  The example is basically the same as the previous
one, but it uses vectors:

    fn main(args: [str]) {
        let r = option::get(uint::from_str(args[1]));
        let v = vec::enum_uints(0u, r);
    
        let start = std::time::precise_time_s();
    
        let sum = 0u;
        vec::iter(v) {|i|
            sum += i;
        }
    
        let end = std::time::precise_time_s();
        io::print(#fmt["Sum from 0 to %u is %u\n", r, sum]);
        io::print(#fmt["time: %3.3f s\n", end - start]);
    }

Unfortunately, the time to execute is largely dominated by building up
the vector of integers we're going to iterate over, so I added some
measurements of the time spent iterating to get a better idea of the
effects of inlining.

Before we dig into the generated assembly, let's look at the measurements:

    ;rustc -O --inline --monomorphize ~/tmp/iterator_vec.rs
    ;~/tmp/iterator_vec 100000000
    Sum from 0 to 100000000 is 5000000050000000
    time: 0.140 s
    ;rustc -O ~/tmp/iterator_vec.rs -o ~/tmp/iterator_vec-no-inline
    ;~/tmp/iterator_vec-no-inline 100000000
    Sum from 0 to 100000000 is 5000000050000000
    time: 1.183 s

Woohoo, the non-inlined version took 8 times longer.  That's
satisfying.  More satisfying, in a way, than the 3000x improvement
from before, since it suggests we're doing things better but not
just winning by a kind of trick.  

(Sharp-eyed readers may have noticed that the results of the summation
are different than before.  This is because `vec::enum_uints()`
generates a vector of `i` such that `0 <= i <= N` whereas
`uint::range()` explores the range `0 <= i < N`.  Yay for
consistency.)

#### Defining `vec::iter`

Before we look at the assembly, let's see how `vec::iter()` is defined:

    #[inline(always)]
    fn iter<T>(v: [const T], f: fn(T)) {
        unsafe {
            let mut n = vec::len(v);
            let mut p = unsafe::to_ptr(v);
            while n > 0u {
                f(*p);
                p = ptr::offset(p, 1u);
                n -= 1u;
            }
        }
    }

This implementation makes use of pointer arithmetic
contained within an unsafe block.  It's basically
equivalent to the following C++-ish code:

    template<class T>
    void iter(vec<T> vec, void (*f)(T&)) {
        n = len(vec);
        T *p = data(vec);
        while (n > 0) {
           f(*p);
           p += 1;
           n -= 1;
        }
    }

#### Generated assembly

OK, now let's look at the assembly.  We'll see that we're generating
pretty decent code.  One thing that could perhaps be improved is that
the call to `unsafe::to_ptr()` does not appear to have been inlined
despite the fact that its definition is marked as `#[inline(always)]`.
Note sure why that is.  Another thing (which may be related) is that
`p` is not stored in a register but rather loaded on each iteration
from the loop.  But I'm not sure how significant that is when the
effects of caching and so forth are taken into account.

One interesting thing is that LLVM converts the loop from one which
counts down to a loop which counts up.  It does this by first negating
`n`.  I'm not sure why this should be faster, I guess that it lets you
generate more compact instructions somehow or perhaps enables other
optimizations later on.  Can't say I've ever looked into these kind of
micro-optimizations around loop counters in detail.

    Ltmp7:
    	; Initialize sum to 0:
    	movq	$0, -80(%rbp)
        
    	; let n = vec::len(v);
    	movq	-64(%rbp), %rdx
    	movq	(%rdx), %rbx
        
        ; Compute p and store it into -48(%rbp)
        ; (Note: first argument to `unsafe::to_ptr()`
        ;  is the location to write the output)
    	leaq	-48(%rbp), %rdi
    	callq	__ZN3vec6unsafe8to_ptr1217_f332097e13dd07e5E
        
    Ltmp9:
        ; Convert size from bytes into indices:
    	shrq	$3, %rbx
    	testq	%rbx, %rbx
    	je	LBB0_12
        
        ; Convert counter to -n:
    	negq	%rbx
        
        ; Zero out the sum, which will be held in %eax:
    	xorl	%eax, %eax
        
    LBB0_10:
        ; Load *p and add to the sum:
    	movq	-48(%rbp), %rcx
    	addq	(%rcx), %rax
        
        ; p++
    	addq	$8, -48(%rbp)
        
        ; n++, stop when we reach zero:
    	incq	%rbx
    	jne	LBB0_10
        
        ; Move sum from %rax into its home on the stack:
    	movq	%rax, -80(%rbp)
        
    LBB0_12:
        ...
        
### Goodbye!

I hope you enjoyed this little dive into our code generation.
