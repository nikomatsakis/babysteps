I have been doing some interesting investigation into the matter of
sendable data structures, particularly hashmaps.  To be "sendable" in
Rust, a data structure must avoid all managed pointers (that's the
name de jour for `@T` types in Rust).  In short that means that the
only kind of pointer that can be used is a unique pointer.  

I've realized that with some simple generalizations of the current
Rust type system rules, sendable data structures become a very
powerful tool.  For example, using the sendable map I wrote, it is
possible to obtain a borrowed pointer to the internal of the map or to
support efficient, copy-less iteration.

The actual coding of the hashmap isn't that interesting.  I chose to
implement a (for the moment) simple
[open-addressed hashmap using linear probing][oa].  At first I thought
this would be necessary to make the map sendable; in fact this is not
the case.  One can easily build a hashmap based on chaining that only
uses unique pointers (and this may be worth doing).


XXX


Dual mode:

    type T;
    enum borrowable_mode<T: const> {
        bm_owned(T),
        bm_mutbl(*T),  // unsafe.  what you gonna do.
        bm_imm(*T),
        bm_temp,
    }
    impl<T> for &mut borrowable<T> {
        fn as_mutable(op: fn(&mut T)) {
            alt *self {
                bm_temp {fail}
                bm_imm(_) {fail}
                bm_mutbl(ptr) {op(unsafe{reinterpret_cast(ptr)})}
                bm_owned(_) {
                    let mut bm = bm_temp;
                    bm <-> *self;
                    let mut v = alt check move bm { bm_owned(v) { move v } };
                    {
                        let v: &mut T = &mut v;
                        bm <- bm_mutbl(v as *mut T)
                        op(&mut v);
                    }
                    bm <- bm_owned(move v);
                }
            }
        }

        fn as_imm(op: fn(&T)) {
            alt *self {
                bm_temp {fail}
                bm_imm(ptr) {op(unsafe{reinterpret_cast(ptr)})}
                bm_mutbl(ptr) {
                    bm <- bm_imm(ptr);
                    op(unsafe{reinterpret_cast(ptr)})
                    bm <- bm_mutbl(ptr);
                }
                bm_owned(_) {
                    let mut bm = bm_temp;
                    bm <-> *self;
                    let mut v = alt check move bm { bm_owned(v) { move v } };
                    {
                        let v: &mut T = &mut v;
                        bm <- bm_mutbl(v as *mut T)
                        op(&mut v);
                    }
                    bm <- bm_owned(move v);
                }
            }
        }
    }
