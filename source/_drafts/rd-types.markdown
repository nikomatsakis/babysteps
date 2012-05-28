Can we get read-by-default?  It seems like it requires a big change
from the existing Rust mutability system.

### Rethinking mutability

Let's focus on a simplified view of the Rust type system:

    T = id | mut T | @T | {fs: Ts}

Here the type `id` refers to some nominal type.


