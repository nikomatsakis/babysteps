I've recently been toying around with an idea for a higher-level
variant of [asm.js][aj] based on typed objects. For those of you not
familiar with it, asm.js is a (very restrictive) subset of JS that is
intended to serve as a target for C-to-JS compilers like
[emscripten][e] or [mandreel][m]. Adhering to this subset means that
it is possible for the engine to fully deduce the types of all runtime
values, thus bypassing the normal JIT compilation process and jumping
directly to the generation of maximally efficient generated code.

asm.js is a great tool for [porting large games to the web][p], but it
has some limitations. For one, asm.js modules only have access to
a single typed array 

it uses a single large typed array as
its "memory" -- this means that all input, output, and temporary
storage takes place in this large array.

In
practice, it requires writing C code to do some specific task that is
highly performance sensitive, e.g. a codec. You can then compile this
C code to JS, yielding an asm.js "module". When you start this asm.js
code, you must provide a typed array that asm.js will use to store the
entire heap and memory of the C program -- this typed array should
contain the inputs, the output, as well as any temporary storage (like
the stack or space for calls to malloc) that the C program may
require.



[aj]: http://asmjs.org
[e]: https://github.com/kripken/emscripten
[m]: http://mandreel.com
[p]: http://www.engadget.com/2013/05/03/mozilla-firefox-epic-citadel/




