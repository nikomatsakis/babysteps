Oh boy do I have a lot of things to write about!  Last week was the
Mozilla Research work week. We all came together in Vancouver and
spent a week hard at work on our various projects. I split my time
between Parallel JS and Rust. A lot of productive discussion was had,
and over the next few posts I expect I'll pick my way through it.

To begin with, I want to look at an interesting topic: what subset of
JavaScript do we intend to support for parallel execution, and how
long will it take to get that working? As my dear and loyal readers
already know, our current engine supports a simple subset of
JavaScript but we will want to expand it and make the result more
predictable.

<!-- more -->

### The subset

- `a.b`: Property access
  - If `a` is a standard JavaScript object
- `a[e]`: Element access
  - If `a` is a standard JavaScript object or a TypedArray
- `f()` and `a.m(...)`: Function and method calls
  - If the function being called a user-implemented function, or one of the
    functions in the following list:
    - `Array.push` (presuming the receiver is writable)
    - `Math.*`
    - (more to come)

