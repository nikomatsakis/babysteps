---
title: "Dada: moves and mutation"
date: 2026-02-10T19:29:44-05:00
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
---

Let's continue with working through Dada. In my [previous post][pp], I introduced some string manipulation. Let's start talking about permissions. This is where Dada will start to resemble Rust a bit more.

[pp]: https://smallcultfollowing.com/babysteps/blog/2026/02/09/hello-dada/

<!--more-->

## Class struggle

**Classes** in Dada are one of the basic ways that we declare new types (there are also enums, we'll get to that later).

The most convenient way to declare a class is to put the fields in parentheses. This implicitly declares a constructor at the same time:

```dada
class Point(x: u32, y: u32) {}
```

This is in fact sugar for a more Rust like form:

```dada
class Point {
    x: u32
    y: u32
    fn new() -> Point {
        Point { x, y }
    }
}
```

And you can create an instance of a class by calling the constructor:

```dada
let p = Point(22, 44) // sugar for Point.new(22, 44)
```

## Mutating fields

I can mutate the fields of `p` as you would expect:

```dada
p.x += 1
p.x = p.y
```

## Read by default

In Dada, the default when you declare a parameter is that you are getting read-only access:

```dada
fn print_point(p: Point) {
    print("The point is {p.x}, {p.y}")
}

let p = Point(22, 44)
print_point(p)
```

If you attempt to mutate the fields of a parameter, that would get you an error:

```dada
fn print_point(p: Point) {
    p.x += 1 # <-- ERROR!
}
```

## Use `!` to mutate

If you declare a parameter with `!`, then it becomes a mutable reference to a class instance from your caller:

```dada
fn translate_point(point!: Point, x: u32, y: u32) {
    point.x += x
    point.y += y
}
```

In Rust, this would be like `point: &mut Point`. When you call `translate_point`, you also put a `!` to indicate that you are *passing* a mutable reference:

```dada
let p = Point(22, 44)     # Create point
print_point(p)            # Prints 22, 44
translate_point(p!, 2, 2) # Mutate point
print_point(p)            # Prints 24, 46 
```

As you can see, when `translate_point` modifies `p.x`, that changes `p` in place.

## Moves are explicit

If you're familiar with Rust, that last example may be a bit surprising. In Rust, a call like `print_point(p)` would *move* `p`, giving ownership away. Trying to use it later would give an error. That's because the default in Dada is to give a read-only reference, like `&x` in Rust (this gives the right *intuition* but is also misleading; we'll see in a future post that *references* in Dada are different from Rust in one very important way).

If you have a function that needs ownership of its parameter, you declare that with `given`:

```dada
fn take_point(p: given Point) {
    // ...
}
```

And on the caller's side, you call such a function with `.give`:

```dada
let p = Point(22, 44)
take_point(p.give)
take_point(p.give) # <-- Error! Can't give twice.
```

## Comparing with Rust

It's interesting to compare some Rust and Dada code side-by-side:

| Rust | Dada |
| ---  | ---  |
| `vec.len()` | `vec.len()` |
| `map.get(&key)` | `map.get(key)` |
| `vec.push(element)` | `vec!.push(element.give)`
| `vec.append(&mut other)` | `vec!.append(other!)` |
| `message.send_to(&channel)` | `message.give.send_to(channel)`

## Design rationale and objectives

### Convenient is the default

The most convenient things are the shortest and most common. So we make reads the default.

### Everything is explicit but unobtrusive

The `.` operator in Rust can do a wide variety of things depending on the method being called. It might mutate, move, create a temporary, etc. In Dada, these things are all visible at the callsite-- but they are unobtrusive. 

This actually dates from Dada's "gradual programming" days -- after all, if you don't have type annotations on the method, then you can't decide `foo.bar()` should take a shared or mutable borrow of `foo`. So we needed a notation where everything is visible at the call-site and explicit.

### Postfix operators play more nicely with others

Dada tries hard to avoid prefix operators like `&mut`, since they don't compose well with `.` notation.
