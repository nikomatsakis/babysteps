I've noticed that the ideas that I post on my blog are getting much
more "well rounded". That is a problem. It means I'm waiting too long
to write about things. So I want to post about something that's a bit
more half-baked -- it's an idea that I've been kicking around to
create a kind of informal "analysis API" for rustc.

### The problem statement

I am interested in finding better ways to support advanced analyses
that "layer on" to rustc. I am thinking of projects like Prusti,
Facebook's XXX, or the work to extend Galois's Sawzall. Most of these
projects are attempting to analyze **safe Rust code** and prove useful
properties about it. So, for example, they might try to show that a
certain piece of code will never panic, or to show that it meets
certain functional contracts specified in comments.

### Rust gives an edge

You'll notice that all of the tools I mentioned above are pre-existing
tools. They were built, by and large, to analyze languages like C++ or
Java.

### The challenge today


