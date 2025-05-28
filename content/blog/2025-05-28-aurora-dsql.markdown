---
title: "Using Rust to build Aurora DSQL"
date: 2025-05-28T18:00:36Z
---

Just yesterday, AWS [announced] General Availability for a cool new service called [Aurora DSQL] -- from the outside, it looks like a SQL database, but it is fully serverless, meaning that you never have to think about managing database instances, you pay for what you use, and it scales automatically and seamlessly. That's cool, but what's even cooler? It's written 100% in Rust -- and how it go to be that way turns out to be a pretty interesting story. If you'd like to read more about that, Marc Bowes and I have a [guest post on Werner Vogel's All Things Distributed blog][blog].

[blog]: https://www.allthingsdistributed.com/2025/05/just-make-it-scale-an-aurora-dsql-story.html

[announced]: https://aws.amazon.com/about-aws/whats-new/2025/05/amazon-aurora-dsql-generally-available/

[Aurora DSQL]: https://aws.amazon.com/rds/aurora/dsql/

Besides telling a cool story of Rust adoption, I have an ulterior motive with this blog post. And it's not advertising for AWS, even if they are my employer. Rather, what I've found at conferences is that people have no idea how much Rust is in use at AWS. People seem to have the impression that Rust is just used for a few utilities, or something. When I tell them that Rust is at the heart of many of services AWS customers use every day (S3, EC2, Lambda, etc), I can tell that they are re-estimating how practical it would be to use Rust themselves. So when I heard about Aurora DSQL and how it was developed, I knew this was a story I wanted to make public. [Go take a look!][blog]