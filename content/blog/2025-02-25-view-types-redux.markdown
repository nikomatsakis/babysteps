---
title: "View types redux and abstract fields"
date: 2025-02-25T16:04:46Z
---

A few years back I proposed [view types](https://smallcultfollowing.com/babysteps/blog/2021/11/05/view-types/) as an extension to Rust’s type system to let us address the problem of (false) inter-procedural borrow conflicts. The basic idea is to introduce a “view type” `{f1, f2} Type`[^syntax], meaning “an instance of `Type` where you can only access the fields `f1` or `f2`”. The main purpose is to let you write function signatures like `& {f1, f2} self` or `&mut {f1, f2} self` that define what fields a given type might access. I was thinking about this idea again and I wanted to try and explore it a bit more deeply, to see how it could actually work, and to address the common question of how to have places in types without exposing the names of private fields.

[^syntax]: I’m not really proposing this syntax—among other things, it is ambiguous in expression position. I’m not sure what the best syntax is, though! It’s an important question, but not one I will think hard about here.

## Example: the `Data` type

The `Data` type is going to be our running example. The `Data` type collects experiments, each of which has a name and a set of `f32` values. In addition to the experimental data, it has a counter, `successful`, which indicates how many measurements were successful.

```rust
struct Data {
    experiments: HashMap<String, Vec<f32>>,
    successful: u32,
}
```

There are some helper functions you can use to iterate over the list of experiments and read their data. All of these return data borrowed from self. Today in Rust I would typically leverage lifetime elision, where the `&` in the return type is automatically linked to the `&self` argument:

```rust
impl Data {
    pub fn experiment_names(
        &self,
    ) -> impl Iterator<Item = &String> {
       self.experiments.keys()
    }

    pub fn for_experiment(
        &self, 
        experiment: &str,
    ) -> &[f32] {
       experiments.get(experiment).unwrap_or(&[])
    }
}
```

## Tracking successful experiments

Now imagine that `Data` has methods for reading and modifying the counter of successful experiments:

```rust
impl Data {
    pub fn successful(&self) -> u32 {
        self.successful
    }

    pub fn add_successful(&mut self) {
        self.successful += 1;
    }
}
```

## Today, “aggregate” types like Data present a composition hazard

The `Data` type as presented thus far is pretty sensible, but it can actually be a pain to use. Suppose you wanted to iterate over the experiments, analyze their data, and adjust the successful counter as a result. You might try writing the following:

```rust
fn count_successful_experiments(data: &mut Data) {
    for n in data.experiment_names() {
        if is_successful(data.for_experiment(n)) {
            data.add_successful(); // ERROR: data is borrowed here
        }
    }
}
```

Experienced Rustaceans are likely shaking their head at this point—in fact, the previous code will not compile. What’s wrong? Well, the problem is that `experiment_names` returns data borrowed from `self` which then persists for the duration of the loop. Invoking `add_successful` then requires an `&mut Data` argument, which causes a conflict. 

The compiler is indeed flagging a reasonable concern here. The risk is that `add_successful` could mutate the `experiments` map while `experiment_names` is still iterating over it. Now, we as code authors know that this is unlikely — but let’s be honest, it may be unlikely *now*, but it’s not impossible that as `Data` evolves somebody might add some kind of logic into `add_successful` that would mutate the `experiments` map. This is precisely the kind of subtle interdependency that can make an innocuous “but it’s just one line!” PR cause a massive security breach. That’s all well and good, but it’s also very annoying that I can’t write this code.

## Using view types to flag what is happening

The right fix here is to have a way to express what fields may be accessed in the type system. If we do this, then we can get the code to compile today *and* prevent future PRs from introducing bugs. This is hard to do with Rust’s current system, though, as types do not have any way of talking about fields, only spans of execution-time (“lifetimes”). 

With view types, though, we can change the signature from `&self` to `&{experiments} self`. Just as `&self` is shorthand for `self: &Data`, this is actually shorthand for `self: & {experiments} Data`.

```rust
impl Data {
    pub fn experiment_names(
       & {experiments} self,
    ) -> impl Iterator<Item = &String> {
       self.experiments.keys()
    }


    pub fn for_experiment(
        & {experiments} self,
        experiment: &str,
    ) -> &[f32] {
        self.experiments.get(experiment).unwrap_or(&[])
    }
}
```

We would also modify the `add_successful` method to flag what field it needs:

```rust
impl Data {
    pub fn add_successful(
        self: &mut {successful} Self,
    ) -> impl Iterator<Item = &String> {
       self.successful += 1;
    }
}
```

## Getting a bit more formal

The idea of this post was to sketch out how view types could work in a slightly more detailed way. The basic idea is to extend Rust’s type grammar with a new type…

```
T = &’a mut? T
  | [T]
  | Struct<...>
  | …
  | {field-list} T // <— view types
```

We would also have some kind of expression for defining a view onto a place. This would be a place expression. For now I will write `E = {f1, f2} E` to define this expression, but that’s obviously ambiguous with Rust blocks. So for example you could write...

```rust
let mut x: (String, String) = (String::new(), String::new());
let p: &{0} (String, String) = & {0} x;
let q: &mut {1} (String, String) = &mut {1} x;
```

...to get a reference `p` that can only access the field `0` of the tuple and a reference `q` that can only access field `1`. Note the difference between `&{0}x`, which creates a reference to the entire tuple but with limited access, and `&x.0`, which creates a reference to the field itself. Both have their place.

## Checking field accesses against view types

Consider this function from our example:

```rust
impl Data {
    pub fn add_successful(
        self: &mut {successful} Self,
    ) -> impl Iterator<Item = &String> {
       self.successful += 1;
    }
}
```

How would we type check the `self.successful += 1` statement? Today, without view types, typing an expression like `self.successful` begins by getting the type of `self`, which is something like `&mut Data`. We then “auto-deref”, looking for the struct type within. That would bring us to `Data`, at which point we would check to see if `Data` defines a field `successful`.

To integrate view types, we have to track both the type of data being accessed and the set of allowed fields. Initially we have variable `self` with type `&mut {successful} Data` and allow set `*`. The deref would bring us to `{successful} Data` (allow-set remains `*`). Traversing a view type modifies the allow-set, so we go from `*` to `{successful}` (to be legal, every field in the view must be allowed). We now have the type `Data`. We would then identify the field `successful` as both a member of `Data` and a member of the allow-set, and so this code would be successful.

If however you tried to modify a function to access a field not declared as part of its view, e.g., 


```rust
impl Data {
    pub fn add_successful(
        self: &mut {successful} Self,
    ) -> impl Iterator<Item = &String> {
       assert!(!self.experiments.is_empty()); // <— modified to include this
       self.successful += 1;
    }
}
```

the `self.experiments` type-checking would now fail, because the field `experiments` would not be a member of the allow-set.

## We need to infer allow sets

A more interesting problem comes when we type-check a call to `add_successful()`. We had the following code:

```rust
fn count_successful_experiments(data: &mut Data) {
    for n in data.experiment_names() {
        if is_successful(data.for_experiment(n)) {
            data.add_successful(); // Was error, now ok.
        }
    }
}
```

Consider the call to `data.experiment_names()`. In the compiler today, method lookup begins by examining `data`, of type `&mut Data`, auto-deref’ing by one step to yield `Data`, and then auto-ref’ing to yield `&Data`. The result is this method call is desugared to a call like `Data::experiment_names(&*data)`.

With view types, when introducing the auto-ref, we would also introduce a view operation. So we would get `Data::experiment_names(& {?X} *data)`. What is this `{?X}`? That indicates that the set of allowed fields has to be inferred. A place-set variable `?X` can be inferred to a set of fields or to `*` (all fields).


We would integrate these place-set variables into inference, so that `{?A} Ta <: {?B} Tb` if `?B` is a subset of `?A` and `Ta <: Tb` (e.g., `[x, y] Foo <: [x] Foo`). We would also for dropping view types from subtypes, e.g., `{*} Ta <: Tb` if `Ta <: Tb`.

Place-set variables only appear as an internal inference detail, so users can’t (e.g.) write a function that is generic over a place-set, and the only kind of constraints you can get are subset (`P1 <= P2`) and inclusion (`f in P1`). I *think* it should be relatively straightforward to integrate these into HIR type check inference. When generalizing, we can replace each specific view set with a variable, just as we do for lifetimes. When we go to construct MIR, we would always know the precise set of fields we wish to include in the view. In the case where the set of fields is `*` we can also omit the view from the MIR.

## Abstract fields

So, view types allow us to address these sorts of conflicts by making it more explicit what sets of types we are going to access, but they introduce a new problem — does this mean that the names of our private fields become part of our interface? That seems obviously undesirable.


The solution is to introduce the idea of *abstract*[^ghost] fields. An *abstract* field is a kind of pretend field, one that doesn’t really exist, but which you can talk about “as if” it existed. It lets us give symbolic names to data.


[^ghost]: I prefer the name *ghost* fields, because it’s spooky, but *abstract* is already a reserved keyword.


Abstract fields would be defined as aliases for a set of fields, like `pub abstract field_name = (list-of-fields)`. An alias defines a public symbolic names for a set of fields.


We could therefore define two aliases for `Data`, one for the set of experiments and one for the count of successful experiments. I think it be useful to allow these names to alias actual field names, as I think that in practice the compiler can always tell which set to use, but I would require that *if* there is an alias, then the abstract field is aliased to the actual field with the same name.

```rust
struct Data {
    pub abstract experiments = experiments,
    experiments: HashMap<String, Vec<f32>>,

    pub abstract successful = successful,
    successful: u32,
}
```

Now the view types we wrote earlier (`& {experiments} self`, etc) are legal but they refer to the *abstract* fields and not the actual fields.

## Abstract fields permit refactoring

One nice property of abstract fields is that they permit refactoring. Imagine that we decide to change `Data` so that instead of storing experiments as a `Map<String, Vec<f32>>`, we put all the experimental data in one big vector and store a range of indices in the map, like `Map<String, (usize, usize)>`. We can do that no problem:

```rust
struct Data {
    pub abstract experiments = (experiment_names, experiment_data),
    experiment_indices: Map<String, (usize, usize)>,
    experiment_data: Vec<f32>,

    // ...
}
```

We would still declare methods like `&mut {experiments} self`, but the compiler now understands that the abstract field `experiments` can be expanded to the set of private fields.

## Frequently asked questions

### Can abstract fields be mapped to an empty set of fields?

Yes, I think it should be possible to define `pub abstract foo;` to indicate the empty set of fields.

### How do view types interact with traits and impls?

Good question. There is no *necessary* interaction, we could leave view types as simply a kind of type. You might do interesting things like implement `Deref` for a view on your struct:

```rust
struct AugmentedData {
    data: Vec<u32>,
    summary: u32,
}

impl Deref for {data} AugmentedData {
    type Target = [u32];

    fn deref(&self) -> &[u32] {
        // type of `self` is `&{data} AugmentedData`
        &self.data
    }
}
```

### OK, you don’t need to integrate abstract fields with traits, but could you?

Yes! And it’d be interesting. You could imagine declaring abstract fields as trait members that can appear in its interface:

```rust
trait Interface {
    abstract data1;
    abstract data2;


    fn get_data1(&{data1} self) -> u32;
    fn get_data2(&{data2} self) -> u32;
}
```

You could then define those fields in an impl. You can even map some of them to real fields and leave some as purely abstract:

```rust
struct OneCounter {
    counter: u32,
}

impl Interface for OneCounter {
    abstract data1 = counter;
    abstract data2;

    fn get_data1(&{counter} self) -> u32 {
        self.counter
    }

    fn get_data2(&{data2} self) -> u32 {
        0 // no fields needed
    }
}
```

### Could view types include more complex paths than just fields?

Although I wouldn’t want to at first, I think you could permit something like `{foo.bar} Baz` and then, given something like `&foo.bar`, you’d get the type `&{bar} Baz`, but I’ve not really thought it more deeply than that.

### Can view types be involved in moves?

Yes! You should be able to do something like


```rust
struct Strings {
    a: String,
    b: String,
    c: String,
}

fn play_games(s: Strings) {
    // Moves the struct `s` but only the fields `a` and `c`
    let t: {a, c} Strings = {a, c} s;

    println!(“{s.a}”); // ERROR: s.a has been moved
    println!(“{s.b}”); // OK.
    println!(“{s.c}”); // ERROR: s.a has been moved

    println!(“{t.a}”); // OK.
    println!(“{t.b}”); // ERROR: no access to field `b`.
    println!(“{t.c}”); // OK.
}
```

### Why did you have a subtyping rules to drop view types from sub- but not super-types?

I described the view type subtyping rules as two rules:

* `{?A} Ta <: {?B} Tb` if `?B` is a subset of `?A` and `Ta <: Tb`
* `{*} Ta <: Tb` if `Ta <: Tb`

In principle we could have a rule like `Ta <: {*} Tb` if `Ta <: Tb` — this rule would allow “introducing” a view type into the supertype. We may wind up needing such a rule but I didn’t want it because it meant that code like this really ought to compile (using the `Strings` type from the previous question):

```rust
fn play_games(s: Strings) {
   let t: {a, c} Strings = s; // <— just `= s`, not `= {a, c} s`.
}
```

I would expect this to compile because

```rust
{a, c} Strings <: {*} Strings <: Strings
```

but I kind of don’t want it to compile. 

### Are there other uses for abstract fields?

Yes! I think abstract fields would also be useful in two other ways (though we have to stretch their definition a bit). I believe it’s important for Rust to grow stronger integration with theorem provers; I don’t expect these to be widely used, but for certain key libraries (stdlib, zerocopy, maybe even tokio) it’d be great to be able to mathematically prove type safety. But mathematical proof systems often require a notion of *ghost fields* — basically logical state that doesn’t really exist at runtime but which you can talk about in a proof. A *ghost field* is essentially an abstract field that is mapped to an empty set of fields and which has a type. For example you might declare a `BeanCounter` struct with two abstract fields (`a`, `b`) and one real field that stores their sum:

```rust
struct BeanCounter {
    pub abstract a: u32,
    pub abstract b: u32,
    sum: u32, // <— at runtime, we only store the sum
}
```

then when you create `BeanCounter` you would specify a value for those fields. The value would perhaps be written using something like an abstract block, indicating that in fact the code within will not be executed (but must still be type checkable):

```rust
impl BeanCounter {
    pub fn new(a: u32, b: u32) -> Self {
        Self { a: abstract { a }, b: abstract { b }, sum: a + b }
    }
}
```

Providing abstract values is useful because it lets the theorem prover act “as if” the code was there for the purpose of checking pre- and post-conditions and other kinds of contracts.

### Could we use abstract fields to replace phantom data?

Yes! I imagine that instead of `a: PhantomData<T>` you could do `abstract a: T`, but that would mean we’d have to have some abstract initializer. So perhaps we permit an anonymous field `abstract _: T`, in which case you wouldn’t be required to provide an initializer, but you also couldn’t name it in contracts.

### So what are all the parts to an abstract field?

I would start with just the simplest form of abstract fields, which is an alias for a set of real fields. But to extend to cover ghost fields or `PhantomData`, you want to support the ability to declare a type for abstract fields (we could say that the default if `()`). For fields with non-`()` types, you would be expected to provide an abstract value in the struct constructor. To conveniently handle `PhantomData`, we could add anonymous abstract fields where no type is needed.

### Should we permit view types on other types?

I’ve shown view types attached to structs and tuples. Conceivably we could permit them elsewhere, e.g., `{0} &(String, String)` might be equivalent to `&{0} (String, String)`. I don’t think that’s needed for now and I’d make it ill-formed, but it could be reasonable to support at some point.

## Conclusion

This concludes my exploration through view types. The post actually changed as I wrote it — initially I expected to include place-based borrows, but it turns out we didn’t really need those. I also initially expected view types to be a special case of struct types, and that indeed might simplify things, but I wound up concluding that they are a useful type constructor on their own. In particular if we want to integrate them into traits it will be necessary for them to be applied to generics and the rest.≈g

In terms of next steps, I’m not sure, I want to think about this idea, but I do feel we need to address this gap in Rust, and so far view types seem like the most natural. I think what could be interesting is to prototype them in a-mir-formality as it evolves to see if there are other surprises that arise.
