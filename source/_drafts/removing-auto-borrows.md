I have decided that I dislike the automatic borrowing that occurs for
function call arguments---or, at least, I think we should apply it in
fewer cases. This is a bit ironic, since I initially put it in, and I
have argued for it in the past. However, having spent some time using
it, I have come to think that it can be harmful to understand what is
happening.

One of the things I've always hated about C++ was that references can
hide both mutation and pointers (a particularly unfortunate
combination). Consider a function call like `foo(*bar)`. Without
knowing anything about the declaration of `foo`, we cannot say whether
`*bar` is reading the value found at the other end of the pointer bar
and then passing it to `foo`, or instead converting the pointer `bar`
into a reference (this is ignoring operator overloading, of course).
Basically, it always seemed very surprising to me that one would write
`*bar` and then get a pointer as a result. This is compounded by the
fact that C++ references are mutable, and hence not only do I not know
if I am passing a pointer to `foo` or a value, I also don't know
whether `foo` plans to modify that pointer/value!

Unfortunately, the same situation can arise in Rust. This was exactly
by design.
