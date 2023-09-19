---
layout: post
title: 'Office Hours #0: Debugging with GDB'
categories: [Rust, OfficeHours]
---

This is a report on the first ["office hours"][oh], in which we
discussed debugging Rust programs with gdb. I'm very grateful to
Ramana Venkata for suggesting the topic, and to Tom Tromey, who joined
in. (Tom has been doing a lot of the work of integrating rustc into
gdb and lldb lately.)

This blog post is just going to be a quick summary of the basic
workflow of using Rust with gdb on the command line. I'm assuming you
are using Linux here, since I think otherwise you would prefer a
different debugger. There are probably also nifty graphical tools you
can use and maybe even IDE integrations, I'm not sure.

### The setting

We specifically wanted to debug some test failures in a cargo project
([esprit]).  When running `cargo test`, some of the tests would panic,
and we wanted to track down why. This particular crate is also nightly
only.

### How to launch gdb

The first is to find the executable that runs the tests. This can be
done by running `cargo test -v` and looking in the output for the
final `Running` line. In this particular project ([esprit]), we needed
to use nightly, so the command was something like:

```bash
> cargo +nightly test -v
...
     Running `/home/espirit/target/debug/deps/prettier_rs-7c95ceaface142a9`
```

Then one can invoke gdb with that executable. Note also that you need to be running
a version of gdb that is somewhat recent in order to get good Rust
support (ideally in the 8.x series). You can test your version of gdb
by running `gdb -v`:

```bash
> gdb -v
GNU gdb (GDB) Fedora 8.1-15.fc28
...
```

To run gdb, it is recommended that you use the `rust-gdb` wrapper,
which adds some Rust-specific pretty printers and other
configuration. This is installed by rustup, and hence it respects the
`+nightly` flag. In this case, we want to invoke it with the test
executable.  We are also going to set the environment variable
`RUST_TEST_THREADS` to `1`; this prevents the test runner from using
multiple threads, since that complicates the process of stepping
through the binary:

```bash
> RUST_TEST_THREADS=1 rust-gdb target/debug/deps/prettier_rs-7c95ceaface142a9
```

### Once you are in gdb

Once you are in gdb, you can run the program by typing `run` (or just
`r`). But in this case it will just run, find the test failure, and
then exit, which isn't exactly what we wanted: we wanted execution to
stop when the `panic!` occurs and let us inspect what's going on. To
do that, you will need to set a **breakpoint**. In this case, we want
to set it on the special function `rust_panic`, which is defined in
libstd for this exact purpose. We can do that with the `break`
command, as shown below. After setting the break, *then* we can run:

```bash
> break rust_panic
Breakpoint 1 at 0x55555564e273: file libstd/panicking.rs, line 525.
> run
```

Now when the panic occurs, we will trigger the breakpoint, and gdb
gives us back control. At this point, you can use the `bt` command to
get a backtrace, and the `up` command to move up and inspect the
callers' state. You may also enjoy the ["TUI mode"][tui]. Anyway, I'm
not really going to try to teach GDB here, I'm sure there are much
better tutorials available.

One thing I did not know: gdb even supports the ability to use a
limited subset of Rust expressions from within the debugger, so you
can do things like `p foo.0` to access the first field of a tuple. You
can even call functions and methods, but not through traits.

### Final note: use rr

Another option that is worth emphasizing is that you can use the [`rr`
tool][rr] to get **reversible debugging**. `rr` basically extends gdb
but allows you to not only step and move **forward** through your
program, but also **backward**. So -- for example -- after we break no
`rust_panic`, we could execute backwards and see what happened that
led us there. Using `rr` is pretty straightforward and is [explained
here][rruse].  (There is also [Huon's old blog post][huon], which
still seems fairly accurate.)  I could not, however, figure out how to
use `rust-gdb` with `rr replay`, but even just plain old gdb works ok
-- I filed [#54433] about using `rust-gdb` and `rr replay`, so maybe
the answer is in there.

### Ideas for the future

gdb support works pretty well. There were some rough edges we
encountered:

- Dumping hashmaps and btree-maps doesn't give useful output. It just shows their
  internal representation, which you don't care about.
- It'd be nice to be able to do `cargo test --gdb` (or, even better,
  `cargo test --rr`) and have it handle all the details of getting you
  into the debugger.

[tui]: https://sourceware.org/gdb/onlinedocs/gdb/TUI.html
[esprit]: https://github.com/vramana/esprit
[rr]: https://rr-project.org/
[rruse]: https://github.com/mozilla/rr/wiki/Usage
[huon]: https://huonw.github.io/blog/2015/10/rreverse-debugging/
[#54433]: https://github.com/rust-lang/rust/issues/54433
[oh]: https://github.com/nikomatsakis/office-hours
