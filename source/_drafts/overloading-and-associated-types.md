After some discussions with Jeremy Siek, pcwalton, and some time to
reflect, I am thinking that perhaps my original proposed rules for
trait resolution were too limiting.  The goal there was to strike a
balance that kept the implementation simple.  But I think that
ultimately we will find this to be unsatisfactory---worse, I think
that if we stick with this design, we will "lock in" certain
unsatisfactory aspects of the current trait system.

I am now thinking that we should add some form of "associated types"
to our trait system.  What this amounts to is the ability to add a
type declaration inside of a trait.  I will use the `Iterable` trait
as an example, since it would be a good place to apply this feature:

    trait Iterable {
        type Element
        
        fn each(&self, f: &fn(&Element) -> bool);
    }

