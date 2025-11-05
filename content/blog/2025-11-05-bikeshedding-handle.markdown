---
title: "Bikeshedding `Handle` and other follow-up thoughts"
date: 2025-11-05T08:15:38-05:00
series:
- "Ergonomic RC"
---

There have been two major sets of responses to my proposal for a `Handle` trait. The first is that the `Handle` trait seems useful but doesn't over all the cases where one would like to be able to ergonomically clone things. The second is that the name doesn't seem to fit with our Rust conventions for trait names, which emphasize short verbs over nouns. The TL;DR of my response is that (1) I agree, this is why I think we should work to make `Clone` ergonomic as well as `Handle`; and (2) I agree with that too, which is why I think we should find another name. At the moment I prefer `Share`, with `Alias` coming in second.

[handle]: {{< baseurl >}}/blog/2025/10/07/the-handle-trait.html

## Handle doesn't cover everything

The first concern with the `Handle` trait is that, while it gives a clear semantic basis for when to implement the trait, it does not cover all the cases where calling `clone` is annoying. In other words, if we opt to use `Handle`, and then we make creating new handles very ergonomic, but calling `clone` remains painful, there will be a temptation to use the `Handle` when it is not appropriate.

In one of our lang team design meetings, TC raised the point that, for many applications, even an "expensive" clone isn't really a big deal. For example, when writing CLI tools and things, I regularly clone strings and vectors of strings and hashmaps and whatever else; I could put them in an Rc or Arc but I know it just doens't matter.

My solution here is simple: let's make solutions that apply to both `Clone` and `Handle`. Given that I think we need a proposal that allows for handles that are *both* ergonomic *and* explicit, it's not hard to say that we should extend that solution to include the option for clone.

The [explicit capture clause][ecc] post already fits this design. I explicitly chose a design that allowed for users to write `move(a.b.c.clone())` or `move(a.b.c.handle())`, and hence works equally well (or equally not well...) with both traits

[eae]: {{< baseurl >}}/blog/2025/10/13/ergonomic-explicit-handles.html 
[ecc]: {{< baseurl >}}/blog/2025/10/22/explicit-capture-clauses.html

## The name `Handle` doesn't fit the Rust conventions

A number of people have pointed out `Handle` doesn't fit the Rust naming conventions for traits like this, which aim for short verbs. You can interpret `handle` as a verb, but it doesn't mean what we want. Fair enough. I like the name `Handle` because it gives a *noun* we can use to talk about, well, *handles*, but I agree that the trait name doesn't seem right. There was a lot of bikeshedding on possible options but I think I've come back to preferring Jack Huey's original proposal, `Share` (with a method `share`). I think `Alias` and `alias` is my second favorite. Both of them are short, relatively common verbs.

I originally felt that `Share` was a bit too generic and overly associated with sharing across threads -- but then I at least always call `&T` a *shared reference*[^imm], and an `&T` would implement `Share`, so it all seems to work well. Hat tip to Ariel Ben-Yehuda for pushing me on this particular name.

[^imm]: A lot of people say *immutable reference* but that is simply accurate: an `&Mutex` is not immutable. I think that the term shared reference is better.

## Coming up next

The flurry of posts in this series have been an attempt to survey all the discussions that have taken place in this area. I'm not yet aiming to write a final proposal -- I think what will come out of this is a series of multiple RFCs.

My current feeling is that we should add the `Hand^H^H^H^H`, uh, `Share` trait. I also think we should add [explicit capture clauses][ecc]. However, while explicit capture clauses are clearly "low-level enough for a kernel", I don't really think they are "usable enough for a GUI" . The next post will explore another idea that I think might bring us closer to that ultimate [ergonomic and explicit][eae] goal. 
