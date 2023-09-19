---
layout: post
title: Rust lang team working groups
categories: [Rust]
---

Now that the Rust 2018 edition has shipped, the language design team
has been thinking a lot about what to do in 2019 and over the next
few years. I think we've got a lot of exciting stuff on the horizon,
and I wanted to write about it.

## Theme for this edition

In 2015, our overall theme was **stability**. For the 2018 Edition, we adopted
**productivity**. For Rust 2021[^2021], we are thinking of **maturity** as the theme.
Our goal is finish up a number of in-flight features -- such as specialization,
generic associated types, and const generics -- that have emerged as key enablers
for future work. In tandem, we aim to start improving our reference material,
both through continuing the great work that's been done on the Rust reference
but also through more specialized efforts like the Grammar and Unsafe Code Guidelines
working groups.

[^2021]: Assuming we do a Rust 2021 edition, which I expect we will.

## Working groups

Actually, the thing I'm most excited about has nothing to do with the
language at all, but rather a change to how we operate. We are planning
to start focusing our operations on a series of **lang team working groups**.
Each working group is focusing on a specific goal. This can be as narrow
as a single RFC, or it might be a family of related RFCs ("async code", "FFI").

The plan is to repurpose our weekly meeting. Each week we will do some amount
of triage, but also check in with one working group. In the days leading up to the meeting,
**the WG will post a written report describing the agenda**: this report should
review what happened since the last chat, discuss thorny questions, help assess priorities, and
plan the upcoming roadmap. **These meetings will be
recorded and open to anyone who wants to attend.** Our hope in particular is that
active working group participants will join the meeting.

Finally, as part of this move, we are creating a [lang team repository](https://github.com/rust-lang/lang-team/) which will serve as the "home" for the lang team. It'll describe our process,
list the active working groups, and also show the ideas that are on the "shortlist" -- basically,
things we expect to start doing once we wrap some of our ongoing work. The repository will
also have advice for how to get involved.

## Initial set of active working groups

We've also outlined what we expect to be our initial set of active working groups.
This isn't a final list: we might add a thing or two, or take something away. The list
more or less maps to the "high priority" endeavors that are already in progress.

For each working group, we also have a rough idea for who the "leads" will be. The
leads of a working group are those helping to keep it organized and functonal. Note that
some leads are not members of the lang team. In fact, helping to co-lead a working group
is a great way to get involved with language design, and also a good stepping stone to full team
membership if desired.

- **Traits working group:**
    - Focused on working out remaining design details of specialization, GATs,
      `impl Trait`, and other trait-focused features.
    - Working closely with the compiler traits working group on implementation.
    - Likely leads: aturon, nmatsakis, centril
- **Grammar working group:**
    - Focused on developing a canonical grammar, following roughly the process
      laid out in [RFC 1331](https://rust-lang.github.io/rfcs/1331-grammar-is-canonical.html).
    - Likely leads: qmx, centril, eddyb
- **Async: Foundations**
    - Focused on core language features like async-await or the `Futures` trait
      that enable async I/O.
      - Distinct from the "Async: Ecosystem" domain working group, which will focus on 
        bolstering the ecosystem for async code through new crates and documentation.
    - Likely leads: cramertj, boats
- **Unsafe code guidelines**
    - Focused on developing rules for unsafe code: what is allowed, what is not.
    - Likely leads: avacadavara, nikomatsakis, pnkfelix
- **Foreign function interface**
    - Focused on ensuring that Rust and C programs can seamlessly and ergonomically
      interact. The goal is to permit Rust code to call or be called by any C function
      and handle any C data structure, as well as all common systems code scenarios
      and supporting inline assembly.
    - Likely leads: joshtriplett
    
## Bootstrapping the working groups

Over the next few weeks, we expect to be "bootstrapping" these working groups.
(In some cases, like grammar and the unsafe code guidelines, these groups
are already quite active, but in others they are not or have not been
formally organized.) For each group, we'll be putting out a call to get involved,
and trying to draw up an initial roadmap laying out where we are now and what the
next few steps we'll be. **If something on that list looks like something you'd
like to help with, stay tuned!**

## Looking to 2019 and beyond

The set of roadmaps listed there aren't meant to be an exhaustive list of the
things we plan to do. Rather, they are meant to be a starting point: these are
largely the activites we are currently doing, and we plan to focus on those and
see them to completion (though the FFI working group is something of a new focus).

The idea is that, as those working groups wind down and bandwidth becomes available,
we will turn out focus to new things. To that end, we aim to draw up a shortlist
and post it on the website, so that you have some idea the range of things we are considering
for the future. Note that the mere presence of an idea on the shortlist is not a guarantee
that it will come to pass: it may be that in working through the proposed idea, we decide
we don't want it, and so forth.

## Conclusion

2019 is going to be a big year for the lang team -- not only because of the work
we plan to do, but because of the way we plan to do it. I'm really looking forward
to it, and I hope to see you all soon at a WG meeting!
