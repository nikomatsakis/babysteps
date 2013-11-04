I think we have two warts in the making in Rust and I'd like to see if
we can correct them. The changes I have in mind are conceptually minor
but far-reaching in terms of the lines of code that would change. Let
me first describe the warts and then describe some options for fixing
one or both.

### Wart #1: Seemingly unnecessary `mut` declarations

In our current type system, an `&mut` pointer gives you both
mutability and uniqueness. I think wedding these two properties
together was a good decision: otherwise the combinatorics of
qualifiers becomes untenable. However, it does mean that sometimes one
must declare data as `mut` that will never be mutated -- and that
sends a misleading messages to readers of the code. It also gives me a
bad feeling when I'm writing functional-style code.

Seemingly unnecessary `mut` declarations come about for two reasons:

1. Implementing highly generic traits.
2. `&mut` pointers found within structs.

Let me illustrate these two examples by way of the `TypeFolder` trait
taken from the Rust compiler (actually a branch of mine).  The
`TypeFolder` trait is defined something like this:

    trait TypeFolder {
        // Simple query method for obtaining the type context.
        fn tcx(&self) -> ty::ctxt;
        
        // Folding methods.
        fn fold_type(&mut self, ty: ty::t) -> ty::t {
            super_fold_type(self, ty)
        }
        fn fold_region(&mut self, region: &ty::Region) -> ty::Region {
            super_fold_region(self, region)
        }
        ...
    }

The interesting thing here is that it defines most of its methods with
`&mut self`. I have come to believe that when defining a generic
trait, like a visitor or a folder, one should default to `&mut self`
rather than `&self`, except for obvious query methods like `tcx` (and
perhaps even there).

This was somewhat nonobvious to me. I think I initially thought of
`&self` as the default -- it is more general in the sense that it
permits aliasing. But of course for generic traits it is very
limiting, since it forbids mutation.

As an example of where mutation might be useful, I wrote a type folder
that substitutes fresh regions for bound regions and collects a map
of the results:

    struct SubstitutingFolder<'a> {
        tcx: ty::ctxt,
        map: &'a mut HashMap<ty::BoundRegion, ty::Region>
    }
    impl<'a> TypeFolder for SubstitutingFolder<'a> {
        fn tcx(&self) -> ty::ctxt { self.tcx }
        
        fn fold_region(&mut self, region: &ty::Region) -> ty::Region {
            match region {
                ty::BoundRegion(br) => {
                    map.find_or_insert_with(br, |br| {
                        create_fresh_region()
                    });
                }
                _ => {
                    super_fold_region(self, region)
                }
            }
        }
    }
    
Here I've chosen to have the map be a mutable borrowed pointer, you
could also write the type with the field `map` being an owned
hashmap. Either way, `&mut self` is required to mutate the map. In the
case of a borrowed pointer, this is because a `&mut` pointer is only
mutable if it is reachable via a unique path (i.e., not `&self`).

If I were to use an instance of this substituting folder, I would
write code like the following:

    let mut map = HashMap::new();
    let mut folder = SubstitutingFolder {tcx: tcx,
                                         map: &mut map};
    folder.fold_ty(...);
    
So far I think everything is working out great. But now let's look at
another example, this time of a more functional folder, one that
simply erases all region references and rewrites them to be `'static`:

    struct RegionEraser { tcx: ty::ctxt }
    impl TypeFolder for RegionEraser {
        fn tcx(&self) -> ty::ctxt { self.tcx }
        fn fold_region(&mut self, _: &ty::Region) -> ty::Region {
            ty::re_static
        }
    }
    
If I want to actually use this region eraser now, I write code like:

    let mut eraser = RegionEraser { tcx: tcx };
    let t = eraser.fold_ty(...);
    
Here it seems strange to me that I have to write a `mut` declaration
even though `RegionEraser` is purely functional code. Not a big deal,
but passing strange.

Given our communities oft expressed hostility to mutability, it is
unfortunate that we force people to declare things as mutable that
wouldn't otherwise be needed.

### Wart #2: Desugaring of closures can't be done cleanly

There are two situations where the borrow checker

### One solution: more mutability



### Another solution: different keywords




Now that I've built up a lot of dramatic suspense, let me just start
by summarizing the full set of changes that I have in mind, and
then I'll go on to explain the motivation:

- Rename our keywords that have to do with mutability into keywords
  that have to do with *ownership*. The most visible thing would be
  that the `mut` keyword becomes `my`, indicating that this is data
  that only you have access to, and no one else. The keyword `their`
  would be used for "const" and (perhaps?) `our` for aliasable, mutable.
- Make mutation require the data be yours all the way down:
  - Mutating an `&my` pointer requires that the pointer itself be declared `my`
  - (Optional) fields that will be mutated must be declared `my`
  
To some extent, these changes are independent from one another. The
change from `mut` to `my` is perhaps dearest to my heart and I'll
defend it first.  The other changes are in service of the goals that
(1) the borrowck doesn't have "special powers" that desugared code
lacks and (2) adding expressiveness to detect and prevent bugs around
accidental mutation.




### Why add `their`?

### Why require "ownership all the way down"?




