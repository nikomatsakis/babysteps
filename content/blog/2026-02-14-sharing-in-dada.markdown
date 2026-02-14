---
title: "Sharing in Dada"
date: 2026-02-14T06:49:35-05:00
series:
  - "Dada"
dada_keywords:
  - "let"
  - "fn"
  - "class"
  - "given"
  - "give"
dada_types:
  - "String"
  - "Point"
  - "Vec"
  - "Map"
  - "Character"
  - "u32"
---

OK, let's talk about *sharing*. This is the first of Dada blog posts where things start to diverge from Rust in a deep way and I think the first where we start to see some real advantages to the Dada way of doing things (and some of the tradeoffs I made to achieve those advantages).

## We are shooting for a GC-like experience without GC

Let's start with the goal: earlier, I said that Dada was like "Rust where you never have to type `as_ref`". But what I really meant is that I want a *GC-like* experience--without the GC.

## We are shooting for a "composable" experience

I also often use the word "composable" to describe the Dada experience I am shooting for. *Composable* means that you can take different things and put them together to achieve something new.

Obviously Rust has many composable patterns -- the `Iterator` APIs, for example. But what I have found is that Rust code is often very brittle: there are many choices when it comes to how you declare your data structures and the choices you make will inform how those data structures can be consumed.

## Running example: `Character` 

### Defining the `Character` type

Let's create a type that we can use as a running example throughout the post: `Character`. In Rust, we might define a `Character` like so:

```rust
#[derive(Default)]
struct Character {
    name: String,
    class: String,
    hp: u32,
}
```

### Creating and Arc'ing the `Character`

Now, suppose that, for whatever reason, we are going to build up a character programmatically:

```rust
let mut ch = Character::default();
ch.name.push_str("Ferris");
ch.class.push_str("Rustacean");
ch.hp = 44;
```

So far, so good. Now suppose I want to share that same `Character` struct so it can be referenced from a lot of places without deep copying. To do that, I am going to put it in an `Arc`:

```rust
let mut ch = Character::default();
ch.name.push_str("Ferris");
// ...
let ch1 = Arc::new(ch);
let ch2 = ch1.clone();
```

OK, cool! Now I have a `Character` that is readily sharable. That's great.

### Rust is composable here, which is cool, we like that

Side note but this is an example of where Rust *is* composable: we defined `Character` once in a fully-owned way and we were able to use it mutably (to build it up imperatively over time) and then able to "freeze" it and get a read-only, shared copy of `Character`. This gives us the advantages of an imperative programming language (easy data construction and manipulation) and the advantages of a functional language (immutability prevents bugs when things are referenced from many disjoint places). Nice!

### Creating and Arc'ing the `Character`

*Now*, suppose that I have some other code, written independently, that *just* needs to store the character's *name*. That code winds up copying the name into a lot of different places. So, just like we used `Arc` to let us cheaply reference a single character from multiple places, it uses `Arc` so it can cheaply reference the character's *name* from multiple places:

```rust
struct CharacterSheetWidget {
    // Use `Arc<String>` and not `String` because
    // we wind up copying this into name different
    // places and we don't want to deep clone
    // the string each time.
    name: Arc<String>,

    // ... assume more fields here ...
}
```

OK. Now comes the rub. I want to create a character-sheet widget from our shared character:

```rust
fn create_character_sheet_widget(ch: Arc<Character>) -> CharacterSheetWidget {
    CharacterSheetWidget {
        // FIXME: Huh, how do I bridge this gap?
        // I guess I have to do this.
        name: Arc::new(ch.name.clone()),

        // ... assume more fields here ...
    }
}
```

Shoot, that's frustrating! What I would *like* to do is to write `name: ch.name.clone()` or something similar (actually I'd probably *like* to just write `ch.name`, but anyhow) and get back an `Arc<String>`. But I can't do that. Instead, I have to deeply clone the string *and* allocate a *new* `Arc`. Of course any subsequent clones will be cheap. But it's not great.

### Rust often gives rise to these kind of "impedance mismatches"

I often find patterns like this arise in Rust: there's a bit of an "impedance mismatch" between one piece of code and another. The *solution* varies, but it's generally something like

* *clone some data* -- it's not so big anyway, screw it (that's what happened here).
* *refactor one piece of code* -- e.g., modify the `Character` class to store an `Arc<String>`. Of course, that has ripple effects, e.g., we can no longer write `ch.name.push_str(...)` anymore, but have to use `Arc::get_mut` or something.
* *invoke some annoying helper* -- e.g., write `opt.as_ref()` to convert from an `&Option<String>` to a `Option<&String>` or write a `&**r` to convert from a `&Arc<String>` to a `&str`.

The goal with Dada is that we don't have that kind of thing.

## Sharing is how Dada copies

So let's walk through how that same `Character` example would play out in Dada. We'll start by defining the `Character` class:

```dada
class Character(
    name: String,
    klass: String,  # Oh dang, the perils of a class keyword!
    hp: u32,
)
```

Just as in Rust, we can create the character and then modify it afterwards:
```dada
class Character(name: String, klass: String, hp: u32)

let ch: given Character = Character("", "", 22)
      # ----- remember, the "given" permission
      #       means that `ch` is fully owned
ch.name!.push("Tzara")
ch.klass!.push("Dadaist")
   #    - and the `!` signals mutation
```

## The `.share` operator creates a `shared` object

Cool. Now, I want to share the character so it can be referenced from many places. In Rust, we created an `Arc`, but in Dada, sharing is "built-in". We use the `.share` operator, which will convert the `given Character` (i.e., fully owned character) into a `shared Character`:

```dada
class Character(name: String, klass: String, hp: u32)

let ch = Character("", "", 22)
ch!.push("Tzara")
ch!.push("Dadaist")

let ch1: shared Character = ch.share
      #  ------                -----
      # The `share` operator consumes `ch`
      # and returns the same object, but now
      # with *shared* permissions.
```

## `shared` objects can be copied freely

Now that we have a `shared` character, we can copy it around:

```dada
class Character(name: String, klass: String, hp: u32)

# Create a shared character to start
let ch1 = Character("Tzara", "Dadaist", 22).share
    #                                       -----

# Create another shared character
let ch2 = ch1
```

## Sharing propagates from owner to field

When you have a shared object and you access its field, what you get back is a **shared (shallow) copy of the field**:

```dada
class Character(...)

# Create a `shared Character`
let ch: shared Character = Character("Tristan Tzara", "Dadaist", 22).share
      # ------                                                       -----

# Extracting the `name` field gives a `shared String`
let name: shared String = ch1.name
        # ------
```

This would be as if, in Rust, when I accessed the field of an `Arc<Character>` I got back an `Arc<Name>`. Obviously this is not the case, and it wouldn't work, but that's the idea.

## Propagation using a `Vec`

To drill home how cool and convenient this is, imagine that I have a `Vec[String]` that I share with `.share`:

```dada
let v: shared Vec[String] = ["Hello", "Dada"].share
```

and then I share it with `v.share`. What I get back is a `shared Vec[String]`. And when I access the elements of that, I get back a `shared String`:

```dada
let v = ["Hello", "Dada"].share
let s: shared String = v[0]
```

This is as if one could take a `Arc<Vec<String>>` in Rust and get out a `Arc<String>`.

## How sharing is implemented

So how is sharing implemented? The answer lies in a not-entirely-obvious memory layout. To see how it works, let's walk how a `Character` would be laid out in memory:

```dada
# Character type we saw earlier.
class Character(name: String, klass: String, hp: u32)

# String type would be something like this.
class String {
    buffer: Pointer[char]
    initialized: usize
    length: usize
}
```

Here `Pointer` is a built-in type that is the basis for Dada's unsafe code system.[^caveat]

[^caveat]: Remember that I have not implemented all this, I am drawing on my memory and notes from my notebooks. I reserve the right to change any and everything as I go about implementing.

### Layout of a `given Character` in memory

Now imagine we have a `Character` like this:

```dada
let ch = Character("Duchamp", "Dadaist", 22)
```

The character `ch` would be laid out in memory something like this (focusing just on the `name` field):

```
[Stack frame]              [Heap]         
ch: Character {                           
    _flag: 1                              
    name: String {                        
        _flag: 1         { _ref_count: 1  
        buffer: ──────────►'D'            
        initialized: 7     ...            
        capacity: 8        'p' }          
    }                                     
    klass: ...                            
    hp: 22                                
}                                         
```

Let's talk this through. First, every object is laid out flat in memory, just like you would see in Rust. So the fields of `ch` are stored on the stack, and the `name` field is laid out flat within that.

Each object that owns other objects begins with a hidden field, `_flag`. This field indicates whether the object is shared or not (in the future we'll add more values to account for other permissions). If the field is 1, the object is not shared. If it is 2, then it is shared.

Heap-allocated objects (i.e., using `Pointer[]`) begin with a ref-count before the actual data (actually this is at the offset of -4). In this case we have a `Pointer[char]` so the actual data that follows are just simple characters.

### Layout of a `shared Character` in memory

If I were to instead create a *shared* character:

```dada
let ch1 = Character("Duchamp", "Dadaist", 22).share
          #                                   -----
```

The memory layout would be the same, but the flag field on the character is now 2:

```
[Stack frame]              [Heap]         
ch: Character {                           
    _flag: 2 👈 (This is 2 now!)                             
    name: String {                        
        _flag: 1         { _ref_count: 1  
        buffer: ──────────►'D'            
        initialized: 7     ...            
        capacity: 8        'p' }          
    }                                     
    klass: ...                            
    hp: 22                                
}                                         
```

### Copying a `shared Character`

Now imagine that we created two copies of the same shared character:

```dada
let ch1 = Character("Duchamp", "Dadaist", 22).share
let ch2 = ch1
```

What happens is that we will copy all the fields of `_ch1` and then, because `_flag` is 2, we will increment the ref-counts for the heap-allocated data within:

```
[Stack frame]              [Heap]            
ch1: Character {                             
    _flag: 2                                 
    name: String {                           
        _flag: 1         { _ref_count: 2     
        buffer: ────────┬─►'D'        👆     
        initialized: 7  │  ...      (This is 
        capacity: 8     │  'p' }     2 now!) 
    }                   │                    
    class: ...          │                    
    hp: 22              │                    
}                       │                    
                        │                    
ch2: Character {        │                    
    _flag: 2            │                    
    name: String {      │                    
        _flag: 1        │                    
        buffer: ────────┘                    
        initialized: 7                       
        capacity: 8                          
    }                                        
    class: ...                               
    hp: 22                                   
}                                            
```

### Copying out the name field

Now imagine we were to copy out the *name* field, instead of the entire character:

```dada
let ch1 = Character("Duchamp", "Dadaist", 22).share
let name = ch1.name
```

...what happens is that:

1. traversing `ch1`, we observe that the `_flag` field is 2 and therefore `ch1` is shared
2. we copy out the `String` fields from `name`. Because the character is shared:
    - we modify the `_flag` field on the new string to 2
    - we increment the ref-count for any heap values

The result is that you get:

```
[Stack frame]              [Heap]       
ch1: Character {                        
    _flag: 2                            
    name: String {                      
        _flag: 1         { _ref_count: 2
        buffer: ────────┬─►'D'          
        initialized: 7  │  ...          
        capacity: 8     │  'p' }        
    }                   │               
    class: ...          │               
    hp: 22              │               
}                       │               
                        │               
name: String {          │               
    _flag: 2            │               
    buffer: ────────────┘               
    initialized: 7                      
    capacity: 8                         
}                                       
```

## "Sharing propagation" is one example of permission propagation

This post showed how `shared` values in Dada work and showed how the `shared` permission *propagates* when you access a field. *Permissions* are how Dada manages object lifetimes. We've seen two so far

* the `given` permission indicates a uniquely owned value (`T`, in Rust-speak);
* the `shared` permission indicates a copyable value (`Arc<T>` is the closest Rust equivalent).

In future posts we'll see the `ref` and `mut` permissions, which roughly correspond to `&` and `&mut`, and talk out how the whole thing fits together.

## Dada is more than a pretty face

This is the first post where we started to see a bit more of Dada's character. Reading over the previous few posts, you could be forgiven for thinking Dada was just a cute syntax atop familiar Rust semantics. But as you can see from how `shared` works, Dada is quite a bit more than that.

I like to think of Dada as "opinionated Rust" in some sense. Unlike Rust, it imposes some standards on how things are done. For example, every object (at least every object with a heap-allocated field) has a `_flag` field. And every heap allocation has a ref-count.

These conventions come at some modest runtime cost. My rule is that basic operations are allowed to do "shallow" operations, e.g., toggling the `_flag` or adjusting the ref-counts on every field. But they cannot do "deep" operations that require traversing heap structures.

In exchange for adopting conventions nad paying that cost, you get "composability", by which I mean that permissions in Dada (like `shared`) flow much more naturally, and types that are semantically equivalent (i.e., you can do the same things with them) generally have the same layout in memory.



