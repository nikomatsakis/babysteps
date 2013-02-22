Lately I've been thinking about the ParallelArray API and I am
beginning to wonder if it is factored in the optimal way.  It is
trying to accommodate two very important, but very different, use
cases: that of the casual user who happens to have a loop that they
could parallelize, and that of the more advanced user who wants to
take some critical part of their game and make it run faster.

The casual user wants to have no annotation.  They almost certainly
want drop-in compatibility with the existing arrays that they are
using.  They don't care about multidimensionality.

The more advanced user probably wants a 2D or 3D array, but may want
more dimensions as well.  They probably prefer the output to be based
on typed arrays (or, better yet, [ES6 binary data][bd]) so that they
can blit the result directly onto a Canvas or WebGL, not to mention
for efficiency.  They care a lot about "predictable performance",
meaning that they don't want to upgrade their browser and discover
that they've fallen off the fast path and are not running 25% slower.
Finally, and this is the important but also speculative point, they
might be willing to tolerate a more complex API in exchange for these
factors.

Today both of these users would make use of the same ParallelArray API,
despite having different requirements and expectations.  The result is


<!-- more -->

### Credit where credit is due

To give credit where credit is due, I should note that a lot of the
ideas in this post originate with other members of the Parallel JS
team (Shu-yu Guo, Dave Herman, Felix Klock) and also with discussions
with the Intel team (Stephan Herhut, Rick Hudson, Jaswanth XXX).  But
I don't want to speak for them, since we seem to each have our own
opinions on the best arrangement, so I'm writing the post from the
first person singular ("I") and not a team perspective ("we").  This
does not imply "ownership" of the ideas within.

### The casual user



### The expert

#### Mutable views

#### Returning new arrays

[bd]: http://wiki.ecmascript.org/doku.php?id=harmony:binary_data

