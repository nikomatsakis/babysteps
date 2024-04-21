---
title: "Ownership in Rust"
date: 2024-04-05T12:22:59-04:00
---
Ownership is an important concept in Rust — but I’m not talking about the type system. I’m talking about in our open source project. One of the big failure modes I’ve seen in the Rust community, especially lately, is the feeling that it’s unclear who is entitled to make decisions. Over the last six months or so, I’ve been developing a [project goals proposal][pg], which is an attempt to reinvigorate Rust’s roadmap process — and a key part of this is the idea of giving each goal an **owner**. I wanted to write a post just exploring this idea of being an owner: what it means and what it doesn’t.

[pg]: https://hackmd.io/@nikomatsakis/ByFkzn_10

## Every goal needs an owner

Under my proposal, the project will identify its top priority goals, and every goal will have a designated **owner**. This is ideally a single, concrete person, though it *can* be a small group. Owners are the ones who, well, own the design being proposed. Just like in Rust, when they own something, they have the power to change it.[^jh]

[^jh]: Hat tip to Jack Huey for this turn of phrase. Clever guy.

Just because owners own the design does not mean they work alone. Like any good Rustacean, they should [treasure dissent][], making sure that when a concern is raised, the owner fully understands it and does what they can to mitigate or address it. But there always comes a point where the tradeoffs have been laid on the table, [the space has been mapped][aic], and somebody just has to make a call about what to do. This is where the owner comes in. Under project goals, the owner is the one we’ve chosen to do that job, and they should feel free to make decisions in order to keep things moving.

[aic]: https://smallcultfollowing.com/babysteps/blog/2019/04/19/aic-adventures-in-consensus/

[treasure dissent]: https://lang-team.rust-lang.org/decision_process.html?highlight=treasure%20dissent#prioritized-principles-of-rust-team-consensus-decision-making

## Teams make the final decision

Owners own the **proposal**, but they don’t decide whether the proposal gets accepted. That is the job of the **team**. So, if e.g. the goal in question requires making a change to the language, the language design team is the one that ultimately decides whether to accept the proposal. 

Teams can ultimately overrule an owner: they can ask the owner to come back with a modified proposal that weighs the tradeoffs differently. This is right and appropriate, because teams are the ones we recognize as having the best broad understanding of the domain they maintain.[^roleofateam] But teams should use their power judiciously, because the owner is typically the one who understands the tradeoffs for this particular goal most deeply.

[^roleofateam]: There is a common misunderstanding that being on a Rust team for a project X means you are the one authoring code for X. That’s not the role of a team member. Team members hold the overall design of X in their heads. They review changes and mentor contributors who are looking to make a change. Of course, team members do sometimes write code, too, but in that case they are playing the role of a (particularly knowledgable) contributor.

## Ownership is empowerment

Rust’s primary goal is *empowerment* — and that is as true for the open-source org as it is for the language itself. Our goal should be to **empower people to improve Rust**. That does not mean giving them unfettered ability to make changes — that would result in chaos, not an improved version of Rust — but when their vision is aligned with Rust’s values, we should ensure they have the capability and support they need to realize it.

## Ownership requires trust

There is an interesting tension around ownership. Giving someone ownership of a goal is an act of faith — it means that we consider them to be an individual of high judgment who understands Rust and its values and will act accordingly. This implies to me that we are unlikely to take a goal if the owner is not known to the project. They don’t necessarily have to have worked on Rust, but they have to have enough of a reputation that we can evaluate whether they’re going to do a good job.’

The design of project goal proposals includes steps designed to increase trust. Each goal includes a set of **design axioms** identifying the key tradeoffs that are expected and how they will be weighed against one another. The goal also identifies **milestones**, which shows that the author has thought about how to breakup and approach the work incrementally.

It’s also worth highlighting that while the project has to trust the owner, the reverse is also true: the project hasn’t always done a good job of making good on its commitments. Sometimes we’ve asked for a proposal on a given feature and then not responded when it arrives.[^delegation] Or we set up [unbounded queues][uq] that wind up getting overfull, resulting in long delays.

[^delegation]: [I still feel bad about delegation.](https://github.com/rust-lang/rfcs/pull/2393#issuecomment-810421388)

[uq]: https://smallcultfollowing.com/babysteps/blog/2019/07/10/aic-unbounded-queues-and-lang-design/

The project goal system has steps to build that kind of trust too: the owner identifies exactly the kind of support they expect to require from the team, and the team commits to provide it. Moreover, the general expectation is that any project goal represents an important priority, and so teams should prioritize nominated issues and the like that are related.

## Trust requires accountability

Trust is something that has to be maintained over time. The primary mechanism for that in the project goal system is **regular reporting**. The idea is that, once we’ve identified a goal, we will create a tracking issue. Bots will prompt owners to give regular status updates on the issue. Then, periodically, we will post a blog post that aggregates these status updates. This gives us a chance to identify goals that haven’t been moving — or at least where no status update has been provided — and take a look as to see why.

In my view, it’s **expected and normal that we will not make all our goals**. Things happen. Sometimes owners get busy with other things. Other times, priorities change and what was once a goal no longer seems relevant. That’s fine, but we do want to be explicit about noticing it has happened. The problem is when we let things live in the dark, so that if you want to really know what’s going on, you have to conduct an exhaustive archaeological expedition through github comments, zulip threads, emails, and sometimes random chats and minutes.

## Conclusion

Rust has strong values of being an open, participatory language. This is a good thing and a key part of how Rust has gotten as good as it is. [Rust’s design does not belong to any one person.](https://nikomatsakis.github.io/rust-latam-2019/#98) A key part of how we enforce that is by making decisions by **consensus**.

But people sometimes get confused and think consensus means that everyone has to agree. This is wrong on two levels:

* **The team must be in consensus, not the RFC thread**: in Rust’s system, it’s the teams that ultimately make the decision. There have been plenty of RFCs that the team decided to accept despite strong opposition from the RFC thread (e.g., the `?` operator comes to mind). This is right and good. The team has the most context, but the team also gets input from many other sources beyond the people that come to participate in the RFC thread.
* **[Consensus doesn't mean unanimity:][cnotu]** Being in consensus means that a majority agrees with the proposal and nobody thinks that it is definitely wrong. Plenty of proposals are decided where team members have significant, even grave, doubts. But ultimately tradeoffs must be made, and the team members trust one another’s judgment, so sometimes proposals go forward that aren’t made the way you would do it.

[cnotu]: https://lang-team.rust-lang.org/decision_process.html?highlight=consensus%20doesn%27t%20mean%20unanimity#prioritized-principles-of-rust-team-consensus-decision-making

The reality is that every good thing that ever got done in Rust had an owner -- somebody driving the work to completion. But we've never named those owners explicitly or given them a formal place in our structure. I think it's time we fixed that!
