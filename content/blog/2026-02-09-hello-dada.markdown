---
title: "Hello, Dada!"
date: 2026-02-09T06:03:21-05:00
series:
- "Dada"
dada_keywords:
  - "let"
dada_types:
  - "String"
---

<img src="{{< baseurl >}}/assets/2026-fun-with-dada/dada-logo.svg" width="20%" style="float: right; margin-right: 1em; margin-bottom: 0.5em;" />

Following on my [Fun with Dada](https://smallcultfollowing.com/babysteps/blog/2026/02/08/fun-with-dada/) post, this post is going to start teaching Dada. I'm going to keep each post short -- basically just what I can write while having my morning coffee.[^5am]

<!--more-->

[^5am]: My habit is to wake around 5am and spend the first hour of the day doing "fun side projects". But for the last N months I've actually been doing Rust stuff, like [symposium.dev](https://symposium.dev/) and [preparing the 2026 Rust Project Goals](https://rust-lang.github.io/rust-project-goals/2026/). Both of these are super engaging, but all Rust and no play makes Niko a dull boy. Also a grouchy boy.

## You have the right to write code

Here is a very first Dada program

```dada
println("Hello, Dada!")
```

I think all of you will be able to guess what it does. Still, there is something worth noting even in this simple program:

**"You have the right to write code. If you don't write a `main` function explicitly, one will be provided for you."** Early on I made the change to let users omit the `main` function and I was surprised by what a difference it made in how *light* the language felt. Easy change, easy win.

## Convenient is the default

Here is another Dada program

```dada
let name = "Dada"
println("Hello, {name}!")
```

Unsurprisingly, this program does the same thing as the last one.

**"Convenient is the default."** Strings support interpolation (i.e., `{name}`) by default. In fact, that's not all they support, you can also break them across lines very conveniently. This program does the same thing as the others we've seen:

```dada
let name = "Dada"
println("
    Hello, {name}!
")
```

When you have a `"` immediately followed by a newline, the leading and trailing newline are stripped, along with the "whitespace prefix" from the subsequent lines. Internal newlines are kept, so something like this:

```dada
let name = "Dada"
println("
    Hello, {name}!
    
    How are you doing?
")
```

would print

```text
Hello, Dada!

How are you doing?
```

## Just one familiar `String`

Of course you could also annotate the type of the `name` variable explicitly:

```dada
let name: String = "Dada"
println("Hello, {name}!")
```

You will find that it is `String`. This in and of itself is not notable, unless you are accustomed to Rust, where the type would be `&'static str`. This is of course a perennial stumbling block for new Rust users, but more than that, I find it to be a big *annoyance* -- I hate that I have to write `"Foo".to_string()` or `format!("Foo")` everywhere that I mix constant strings with strings that are constructed.

Similar to most modern languages, strings in Dada are immutable. So you can create them and copy them around:

```dada
let name: String = "Dada"
let greeting: String = "Hello, {name}"
let name2: String = name
```

## Next up: mutation, permissions

OK, we really just scratched the surface here! This is just the "friendly veneer" of Dada, which looks and feels like a million other languages. Next time I'll start getting into the permission system and mutation, where things get a bit more interesting.