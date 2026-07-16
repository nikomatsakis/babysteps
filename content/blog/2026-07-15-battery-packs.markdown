---
title: "Battery packs: Let's talk about crates, baby"
date: 2026-07-15T11:24:22-04:00
---

<img class="float-right" src="{{< baseurl >}}/assets/2026-07-15-battery-packs.png" alt="Battery pack logo">

This blog post describes an idea I've been kicking around called **battery packs**. Battery packs are a curated set of crates arranged around a common theme. For example, there's a CLI battery pack that has [everything you need to build a great CLI][clibp], an opinionated pack for [creating a backend web service][bsbp], and [one for embedded development](https://crates.io/crates/embedded-battery-pack) (based on the Embedded Working Group's [Awesome Rust repository](https://github.com/rust-embedded/awesome-embedded-rust)). We've also got some smaller ones, such as the [error-handling battery pack](https://crates.io/crates/error-battery-pack) that shows how to handle errors in Rust. But this is just the beginning -- a key part of the battery pack design is that anybody can create one.

[clibp]: https://crates.io/crates/cli-battery-pack
[bsbp]: https://crates.io/crates/backend-service-battery-pack

Battery packs are meant to address one of the most common things I hear from new Rust adopters. Everyone loves the wealth of high-quality crates available on crates.io. And everyone hates having to spend a bunch of time researching and comparing alternatives. Battery packs can serve as a good set of default choices. And they don't lock you in. At heart, they're basically just a list of recommended crates, so you can always swap something out if you find an alternative.

<!-- more -->

We've got a prototype of the battery pack tool working today, so you can try it out if you're curious. Just run `cargo install cargo-bp` and then try a few commands! For example,

```bash
> cargo bp list
```

will show you the set of available battery packs, based on a crates.io search (as I'll explain below, a battery pack is itself packaged and distributed as a crate, but not one that you take a direct dependency on). And `cargo bp add` will add batteries from a battery pack into your crate, so e.g.

```bash
> cargo bp add cli
```

would let you select and add common CLI libraries. If you want to see a more involved demo, try out `cargo bp add embedded`, which is derived from the [Awesome Embedded Rust](https://github.com/rust-embedded/awesome-embedded-rust) repository.

## Let's talk about you and me

One of the key ideas from battery packs is that **anybody can publish one**. They are just a crate named `X-battery-pack`; the dependencies of that crate are your recommendations. Features are designations of common sets of crates frequently used together. The examples are your templates. And so forth.

Letting anybody create a battery pack is in contrast to the previous ideas for an "extended standard library for Rust"[^platform], and it is intended to address some of Rust's unique challenges. For one thing, it lets people publish battery packs that are tailored to specific requirements. For example, the [CLI][clibp] and [backend service][bsbp] battery packs are targeting a "typical computer". But I could imagine the [Rust embedded working group](https://rust-embedded.org/) publishing a battery pack with libraries focused on no-std and binary size optimization.

[^platform]: My first recollection of it was the [Rust Platform](https://internals.rust-lang.org/t/proposal-the-rust-platform/3745) idea we floated in 2016!

Being open-ended also addresses the *"who decides?"* question. To my mind, the best people to recommend what libraries you ought to use are **other people building systems like yours**. This is why I mentioned the Embedded Working Group publishing an Embedded battery pack, for example, as I think they are clearly a set of people who know their space well. But even within the embedded space there are yet smaller groups, and I imagine that sometimes it'll make sense to get narrower. For example, perhaps a battery pack targeted [embassy](https://embassy.dev/) and its associated ecosystem? Unclear.

### Creating a battery pack

If you wanted to create a battery pack, how do you do it? One answer is that you just create a new crate. But a better approach is to use the "battery-pack battery pack"[^yo], which bundles a template:

[^yo]: Yo dawg...

```bash
cargo bp new battery-pack
```

This will prompt you for the name of the battery pack you want to create and a few other things and make your crate. Then you can just use `cargo add` dependencies to represent the libraries you want to recommend and publish.

### "Batteries" are more than dependencies

The "batteries" that you can add to your project aren't always dependencies. They can also be "recipes" or templates. For example, the CI battery pack[^jess] can configure your project with the kind of "super neat-o" github actions you've always wanted but never wanted to bother configuring. To use it, select one or more of the templates to install:

[^jess]: Hat tip to Jess Izen, who proposed and developed the CI battery pack. Neat idea.

```bash
cargo bp add ci
```

I expect this kind of "actions to improve your crate" to become a rich source of things. Right now we're using a relatively lightweight template system built on [minijinja](https://github.com/mitsuhiko/minijinja), but I think we're going to want to expand on this.

### Giving it some structure

Battery Packs also support more than just a flat listing of dependencies/features/templates. You can group dependencies and features into *categories* and then, for each category, distinguish between "pick at most one" or "pick any number". For a fun example, try `cargo bp add embedded`, which is derived from the [Awesome Embedded Rust](https://github.com/rust-embedded/awesome-embedded-rust) repository. If you run it, you'll see something like this, which groups the choices thematically and, in some areas like "concurrency framework", makes it clear that you want to pick one:

```
──────────────────────────────────────────────────────────────────
 ▼ Concurrency Framework (pick at most one)
 > ○ ✦ embassy [embassy-executor, embassy-sync, embassy-time]
   ○ ✦ rtic [cortex-m, rtic]    RTIC — interrupt-driven real-time

 ▼ Display & Graphics (pick any number)
   [ ] ✦ display-ssd1306 [embedded-graphics, ssd1306]    SSD1306
   [ ] ✦ display-st7789 [embedded-graphics, st7789]    ST7789 col

 ▼ Popular Drivers (pick any number)
   [ ] ✦ display-ssd1306 [embedded-graphics, ssd1306]    SSD1306
   [ ] ✦ display-st7789 [embedded-graphics, st7789]    ST7789 col
   [ ] ✦ sensor-bme280 [bme280]    BME280 temperature/humidity/pr
   [ ] ✦ sensor-lis3dh [lis3dh]    LIS3DH 3-axis accelerometer (I
   [ ] ✦ usb-device [usb-device, usbd-serial]    USB device stack

 ▼ Hardware Abstraction Layer (pick at most one)
   ○ ✦ atsamd [atsamd-hal, cortex-m-rt, critical-section-impl, co
   ○ ✦ esp32 [embedded-hal, esp-hal]    ESP32 (Xtensa, WiFi + BT,
   ○ ✦ esp32c3 [embedded-hal, esp-hal]    ESP32-C3 (RISC-V, WiFi
   ○ ✦ esp32s3 [embedded-hal, esp-hal]    ESP32-S3 (Xtensa, WiFi
   ○ ✦ nrf52832 [cortex-m-rt, critical-section-impl, cortex-m, em
   ○ ✦ nrf52840 [cortex-m-rt, critical-section-impl, cortex-m, em
   ○ ✦ nrf9160 [cortex-m-rt, critical-section-impl, cortex-m, emb
   ○ ✦ rp2040 [cortex-m-rt, critical-section-impl, cortex-m, embe
   ○ ✦ stm32f0 [cortex-m-rt, critical-section-impl, cortex-m, emb
 embedded-battery-pack v0.1.0  ↑↓/jk Navigate | Space Toggle | ←/→
```


## Let's talk about all the good things...

So why am I so keen on battery packs? It's largely because I've heard so many would-be or recent Rust adopters talk about picking crates as a challenge. But I feel they would help with some other problems as well.

What I really want to see is working groups in the [Rust Commercial Network][rcn] banding together to publish battery packs and recommendations. These would cover the dependencies that they're actually using.

[rcn]: https://rustfoundation.org/rust-commercial-network/

### Supporting maintainers

One of the reasons I want to have RCN-recognized battery packs is that they are a natural focal point to then prompt RCN members to fund the maintenance of those crates. I am imagining that for each sponsored battery pack vended within the RCN, there is an associated "ecosystem fund". Companies or individuals could sponsor this fund to get access to early patches, security disclosures, etc or other perks. The money would be used to support the maintainers of those crates, to implement missing features, and so forth.

### Fostering interoperability

Another value-add from battery packs is the ability to drive interop efforts. I think that as soon as we start talking about standardizing, we're also going to recognize that there are some places where standardization is hard. For example, early conversations within the [network service working group][nswg] (unsurprisingly) immediately identified that while most people are using [tokio](https://tokio.rs), some major companies are using their own runtimes internally. It's not like the need for "async runtime interop" is [news](https://rust-lang.github.io/wg-async/vision/submitted_stories/status_quo/barbara_wishes_for_easy_runtime_switch.html). But right now, every crate winds up effectively implementing their own set of little traits to make it work. Sponsored battery packs offer the possibility of a neutral home for that sort of thing.

[nswg]: https://rust-commercial-network.github.io/rcn/network-services-wg.html

## ...and the bad things that could be

There are some risks to people using battery packs. The most obvious is that the fact that anybody can publish a battery pack may mean that you just get a ton of battery packs, which doesn't really help anybody! I'm not so worried about this because I think that there will be a few obvious places that most people go first, and then I think once people are oriented, they'll get excited to explore what crates.io has to offer and start discovering more niche battery packs.

### Avoiding stagnation

Battery packs are designed to evolve. I've seen it happen a number of times that there is a dominant crate for something, often taking a "traditional approach", but then somebody else comes along and presents an interesting alternative that gradually takes off. I love that and I don't want to put it at risk.

One example of evolution around CLI argument parsing. For a time, [docopt](https://crates.io/crates/docopt) was a popular way to parse command-line options. Then [clap](https://crates.io/crates/clap) came along and presented a more structured alternative; that was nice, but then structopt came along and connected clap to an auto-derive, so you could just write your data structure and be done. And *that* was awesome. (That is now the standard in clap.) I want to be sure that, even if there is a CLI battery pack, there's room for the next clap to come along. 

There are a few things about battery pack that I think will help us deal with this. First, they are a "thin abstraction". You don't "depend on" a battery pack, you depend on the crates within it. So if a new version comes out that uses clap instead of docopt, that doesn't impact you at all. Your code keeps working same as it ever did. And of course it helps that *anybody* can publish a battery pack. You can now have variations on battery packs that are focused around a new approach to help it get started.

Done right, I think that standardized battery packs can also *help* the ecosystem evolve and pivot. As it is now, knowledge of new crates has to spread by word-of-mouth. But if everybody is aligned around a new approach, adopting that new approach within a battery packs sends a clear signal that your group is aligned that something is the new hotness.

## ...Let's talk about crates[^sp]

[^sp]: Oh, and: my apologies to [Salt-N-Peppa](https://en.wikipedia.org/wiki/Let's_Talk_About_Sex).

### "Always bet on the ecosystem"

I see **always bet on the ecosystem** as a key Rust design axiom. It's the reason we chose a small standard library and a package manager in the first place. It's also why battery packs are designed to be published by anyone. 

But just like plants sometimes need a trellis to grow taller, any successful ecosystem reaches a point where it needs another layer of structure to help it keep growing. Without that, you have this "layer of tacic knowledge" (in [the words of a Rust Vision Doc interviewee](https://blog.rust-lang.org/2025/12/19/what-do-people-love-about-rust/#example-the-wealth-of-crates-on-crates-io-are-a-key-enabler-but-can-be-an-obstacle)) that becomes an obstacle for folks. And I think we've reached that point with `crates.io`.

I am hopeful that battery packs can provide that next layer of structure. But at the end of the day, if there's a better approach, that's fine too, so long as we find a way to help people find (*and fund!*) the crates they need. So let's talk about it!