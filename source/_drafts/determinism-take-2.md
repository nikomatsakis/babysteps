I have gotten a fair amount of thoughtful feedback on my last post
regarding determinism and I wanted to write out some response.

Thoughts:

- A difference in perspective:
  - There will be apps where parallel operations MUST WORK or the app
    is unuseable (notably games)
    - this seems like a debugging issue exactly akin to ensuring that
      you don't fall off the jitted path
    - I think there is a space for a separate spec a la asm.js
    - browsers which support that spec can then give hard guarantees
  - but I also see a role for parallel operations as a "nice to have"
    sort of thing, particularly in the beginning
    - can we mine examples from V8's benchmark suite?
  - forced parallel exec seems to me to be very threatening to portability
    - hard to implement
    - what is parallelizable will vary from engine to engine depending
      on internal details
    - as new specs come on the scene and new APIs appear, how do they fit in?
- On the other hand
  - I am sympathetic to the debugging challenges of nondeterminism
  - I am VERY sympathetic to the idea that impls will be, in practice,
    stuck emulating a particular implementation
    - HOWEVER---
      - this has not happened for Array.sort(), granted a limited example
    - Experiment with XORSHIFT?
      - can execute chunks in a random order
      - for each exec, within a chunk use a random order
      - worth measuring the perf hit
      - *certainly* this can be a debug mode, maybe even an all the time thing?
- 
