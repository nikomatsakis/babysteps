I would like to get something off my chest. I have been contemplating
some changes to Rust, the sort of changes that can only be done *now*
(before 1.0). These are not massive conceptual changes but they are
pervasive syntax changes. The idea is basically not to change course
with respect to our type system but to tweak various aspects of it
that grate on me. I am increasingly of the opinion that if we fail to
make some tweaks, we have some (non-fatal) warts in the making, and I
would rather avoid that fate.

I would like to propose a change to Rust that is simultaneously small
and massive. I think it's late in the language development to do a
change like this. But not yet too late. I wouldn't propose a big
change frivilously; I have the feeling that our current setup is
suboptimal for reasons I will explain, and that with some minor
adjustment we will be much better prepared for the future.

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

### Why change from `mut` to `my`?

In our current type rules, an `&mut` pointer gives you two things:

- mutability;
- uniqueness.

I think this is a good combination: in particular, it's not generally
safe to go about mutating without some guarantee of uniqueness.
However, it turns out that there are many examples where one wants
uniqueness but not necessarily mutability. There are two primary reasons
that this comes about:

1. You are implementing a general trait, such as `Visitor`, which is
   coded up to require `&mut` so as to be more general.
2. You have an `&mut` pointer within a struct and while you do not
   plan on changing the struct itself, you do wish to mutate what the
   pointer references.
   
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

There are two reasons for this: first and foremost, of course, the
visitor may wish to mutate its own fields. For example, a visitor that
counted expressions might look like:

    struct ExprCountingVisitor { count: uint }
    impl Visitor for ExprCountingVisitor {
        fn visit_expression(&mut self, expression: &ast::Expr) {
            self.count += 1; // Requires &mut self, naturally.
            visit::super_visit_statement(self, expression);
        }
    }
    
Another good reason is that the visitor might contain an `&mut` that
it would like to update. For example, a visitor that buit up an array
of the ids of all expressions might look like:

    struct ExprCollectingVisitor<'a> { expression_ids: &'a mut ~[uint]  }
    impl Visitor for ExprCountingVisitor {
        fn visit_expression(&mut self, expression: &ast::Expr) {
            self.expression_ids.push(expression.id); // Requires &mut self
            visit::super_visit_statement(self, expression);
        }
    }

It may not be obvious but mutating `&mut self` data is only legal if
the path leading up to the `&mut self` pointer is *unique*. That is
why a method using `&self` in this instance would lead to an error,
because then `self.expression_ids` would be located in aliasable
memory.

Now, using `&mut self` works out just dandy because visiting the AST
is a "serial" activity. There is no need to alias the visitor
itself. (I claim this is no accident: any common pattern that performs
mutation will share similar characteristics).

However, there are also visitors that do not require `&mut
self`. Given that visitors cannot return values, this occurs most
frequently because they are mutating `@mut self` data and hence their
correctness is dynamically, not statically, checked. Here is a variant
of the `ExprCollectingVisitor` that shows what I mean:

    struct GCExprCollectingVisitor<'a> { expression_ids: @mut ~[uint]  }
    impl Visitor for GCExprCountingVisitor {
        fn visit_expression(&mut self, expression: &ast::Expr) {
            self.expression_ids.push(expression.id);
            visit::super_visit_statement(self, expression);
        }
    }
    
In cases like this, it is somewhat unfortunate that `&mut self` is
required.  The reason is that now when I create a visitor I must write
`let mut` rather than `let`, so that the `&mut` borrow is legal:

    let mut visitor = GCExprCountingVisitor { ... };
    visitor.visit_expression(...);





### Why add `their`?

### Why require "ownership all the way down"?




