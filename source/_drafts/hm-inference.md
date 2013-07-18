I am debating what sort of type inference we ought to use for Rust.
Ideally, we would use something that is easily and precisely
specified,


is most appropriate I have implemented a branch of Rust that uses
"pure" Hindley-Milner inference rather than our current hybrid. This
branch compiles all of rustc with minimal changes (three tests
