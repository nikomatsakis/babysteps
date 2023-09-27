---
title: "Empathy in open source: be gentle with each other"
date: 2023-09-27T11:50:51-04:00
---

Over the last few weeks I had been preparing a talk on “Inclusive Mentoring: Mentoring Across Differences” with one of my good friends at Amazon. Unfortunately, that talk got canceled because I came down with COVID when we were supposed to be presenting. But the themes we covered in the talk have been rattling in my brain ever since, and suddenly I’m seeing them everywhere. One of the big ones was about *empathy* — what it is, what it isn’t, and how you can practice it. Now that I’m thinking about it, I see empathy so often in open source.

## What empathy is

In her book Atlas of the Heart[^bb], Brené Brown defines **empathy** as 

> an emotional skill set that allows us to understand what someone is experiencing and to reflect back that understanding.

[^bb]: I bought this book when it first came out, read a bit of it, and then thought of it more as a reference — a great book for getting clear, distinguished definitions that help to elucidate the subtleties of human emotion. But when I revisited it to prepare for this talk, I was surprised to find it was much more “front-to-back” readable than I thought, and carried a lot of hidden wisdom.

Empathy is not about being **nice** or making the other person feel good or even feel better[^se]. Being empathetic means **understanding what the other person feels** and then **showing them that you understand**.

Understanding what the other person feels doesn’t mean you have to feel the same way. It also doesn’t mean you have to agree with them, or feel that they are “justified” in those feelings. In fact, as I’ll explain in a second, strong feelings and emotion are *by design* limited in their viewpoints — they are always showing us something, and showing us something real, but they are never showing us the full picture.

Usually we feel multiple, seemingly contradictory things, which can leave everything feeling like a big muddle. The goal, from what I can see, is to be able to pull those multiple feelings apart, understand them, and then -- from a balanced place -- decide how we are going to react to them. Hopefully in real time. Pretty damn hard, in my experience, but something we can get better at.

[^se]: Though I think people feeling good and better is always a *consequence* of having encountered someone else empathetic. 

## People are not any one thing

Some time back, Aaron Turon introduced me to [Internal Family Systems][IFS] through the book [Self Therapy](https://www.amazon.com/Self-Therapy-Step-Step-Cutting-Edge-Psychotherapy/dp/0984392777)[^je]. It’s really had a big influence on how I think about things. The super short version of IFS is “[Inside Out][] is real”. We are each composites of a number of independent *parts* which capture pieces of our personality. When we are feeling balanced and whole, we are switching between these parts all the time in reaction to what is going on around us.

[^je]: By none other than [Jay Earley][], inventer of the [Earley parser][]! This guy is my hero.

[Jay Earley]: https://en.wikipedia.org/wiki/Jay_Earley
[IFS]: https://en.wikipedia.org/wiki/Internal_Family_Systems_Model
[Inside Out]: https://en.wikipedia.org/wiki/Inside_Out_(2015_film)
[Earley parser]: https://en.wikipedia.org/wiki/Earley_parser

But *sometimes* things go awry. Sometimes, one part will get very alarmed about what it perceives to be happening, and it will take complete control of you. This is called **blending**. While you are blended, the part is doing its best to help you in the ways that it knows: that might mean making you super anxious, so that you identify risks, or it might mean making you yell at people, so that they will go away and you don’t have to risk them letting you down. No matter which part you are blended with in the moment, though, you lose access to your whole self and your full range of capabilities. Even though the part will help you solve the immediate problem, it often does so in ways that create other problems down the line.

This concept of parts has really helped me to understand myself, but it has also helped me to understand what previously seemed like contradictory behavior in other people. The reason that people sometimes act in extreme ways, ways that seem so different from the person I know at other times, is because they’re *blended* — **they’re not the person I know at that time**, they’re just **one part** of that person. And probably a part that has helped them through some tough times in the past.

## Empathy as “holding space”

I’ve often heard the term ‘emotional labor’ and, to be honest, I had a hard time connecting to it. But in [Lama Rod Owen’s “Love and Rage”][L&R], he talks about emotional labor in terms of *“the work we do to help people process their emotions”* and, in particular, gives this list of examples:

[L&R]: https://www.penguinrandomhouse.com/books/608716/love-and-rage-by-lama-rod-owens/

> This includes actively listening to others, asking how people are feeling, checking in with them, letting them vent in front of you, and not reacting to someone when they are being rude or disrespectful.

Now this list struck a chord with me. To me, the hardest part of empathy is *holding space* — letting someone have a reaction or a feeling without turning away. When people are reacting in an extreme way — whether it’s venting or being rude — it makes us uncomfortable, and often we’ll try to make them stop. This can take many forms. It could mean changing the topic, dismissing it (“get over it”, “I’m sure they didn’t mean it like that”), or trying to fix it (“what you need to do is…”, “let’s go kick their ass!”) For me, when people do that, it makes me feel unseen and kind of upset. Even if the other person is getting righteously angry on my behalf, I feel like suddenly the situation isn’t about *me* and how *I* want to think about things.

## What does all this have to do with Github?

At this point you might be wondering “what do obscure therapeutic processes and buddhist philosophy have to do with Github issue threads?” Take another look at Lama Rod Owens’s list of examples of emotional labor, especially the last one:

> not reacting to someone when they are being rude or disrespectful

To be frank, being an open-source maintainer means taking a lot of shit[^bias]. In his insightful, and widely discussed, talk [“The Hard Parts of Open Source"][hp], Evan Czaplicki identified many of the “failure modes” of open source comment threads. One very memorable pattern is the “Why don’t you just…” comment, where somebody chimes in with an obvious alternative, as if you hadn’t thought of it. There is also my personal favorite, what I’ll call the “double agent” comment, where someone seems to feel that your goal is actually to ruin the project you’ve put so much effort into, and so comes in hot and angry.

[^bias]: And I say this as a cis white man, which means I don’t even have to deal with shit resulting from people’s conscious or unconscious bias. 

[hp]: https://www.youtube.com/watch?v=o_4EX4dPppA

My goal is always to respond to comments as if the commenter had been constructive and polite, or was my best friend. I don’t always achieve my goal, especially in forums where I have to respond quickly[^zulip]. But I honestly do try. One technique is to find the key points in their comment and rephrase them, to be sure you understand, and then give your take. When I do that, I usually learn things — even when I initially thought somebody was just a blowhard, there is often a strong point underlying their argument, and it may lead me to change course if I listen to it. If nothing else, it’s always good to know the counterarguments in depth.

[^zulip]: This is one reason I don’t personally like fast moving threads and discussions, and I often limit the venues where I will participate. I need a bit of time to sit with things and process them.

## Empathy as a maintainer

And this brings us to the role of *empathy* as an open-source maintainer. As I said, these days, I see it popping up everywhere. To start, the idea of responding to someone’s comment, even one that feels rude, by identifying the key points they are trying to make feels to me like empathy, even if those points are often highly technical[^nottech]. Fundamentally, empathy is all about *understanding the other person* and *letting them know you understand*, and that is what I am trying to do here.

[^nottech]: It’s worth highlighting that the key points they are trying to make are *not always* technical. Re-reading Aaron Turon’s [Listening and Trust][L&T] posts for this series, I was reminded of glaebhoerl’s [pivotal comment][pc] that articulated very well their frustration at the Rust maintainer’s sense of entitlement and superiority, and the reasons for it. As glaebhoerl identified so clearly, it wasn’t so much the technical decision that was the problem — though I think on balance it was the wrong call, it was a debatable point — as the manner of engagement.

But empathy comes into play in a more meta way as well. Trying to think how somebody feels — and *why* they might be feeling that way — can really help me to step back from feeling angry or injured by the tone of a comment and instead to refocus on what they are trying to communicate to me. Aaron Turon wrote a truly insightful and honest series of posts about his perspective on this called [Listening and Trust][L&T]. In [part 3][L&T3] of that series, he identified some of the key contributors to comment threads that go off the rails, what he called “momentum, urgency, and fatigue”. It’s worth reading that post, or reading it again if you already have. It’s a masterpiece of looking past the immediate reactions to understand better what’s going on, both within others and yourself.

[L&T]: http://aturon.github.io/tech/2018/05/25/listening-part-1/
[L&T3]: http://aturon.github.io/tech/2018/06/18/listening-part-3/
[pc]: https://www.reddit.com/r/rust/comments/2qmeeq/rfc_rename_intuint_to_intxuintx/cn8ugag/

## Empathy when we surprise people

When Apple is working on a new product, they keep it absolutely top secret until they are ready -- and then they tell the world, hoping for a big splash. This works for them. In *open source*, though, it's an anti-pattern. The last thing you want to do is to surprise people -- that's a great way to trigger those parts we were talking about.

The difference, I think, is that open source projects are community projects -- everybody feels some degree of ownership. That's a big part of what makes open source so great! But, at the same time, when somebody starts messing with *your stuff*, that's sure to get you upset. Paul Ford wrote an article identifying this feeling, which he called [“Why wasn’t I consulted?”][WWIC].

[WWIC]: https://www.ftrain.com/wwic


I find the phrase "Why wasn't I consulted?" a pretty useful reminder for how it feels, but to be honest I've never liked it. The problem is that to me it feels condescending. But I totally get the way that people feel. It doesn't always mean I think they're right, or even justified in that feeling. But I get it, and I respect it. Heck, I feel it too![^theme]

[^theme]: Like when Disney canceled Owl House without even **asking me**. WHAT GIVES DISNEY.

My personal creed these days is to be as open and transparent as I can with what I am doing and why. It's part of why I love having this blog, since it lets me post up early ideas while I am still thinking about them. This also means I can start to get input and feedback. I don't always listen to that feedback. A lot of times, people hate the things I am talking about, and they're not shy about saying so -- I try to take that as a signal, but just one signal of many. If people are upset, I'm probably doing something wrong, but it may not be the idea, it may be the way I am talking about it, or some particular aspect of it.

## Empathy when we design our project processes

As I prepared this blog post, I re-read Aaron's [Listening and Trust][L&T], and I was struck again by how many insights he had there. One of them was that by applying empathy, and looking at our processes from the lens of how it **feels** to be a participant -- what concerns get triggered -- we can make changes so that everyone feels more included and less worn down. The key part here is that we have to look not only as how things feel for ourselves, but also how they feel for the participants -- and for those who are not yet participating! There's a huge swath of people who do not join in on Rust discussions, and I think we're really missing out. This kind of design isn't easy, but it's crucial.

## Empathy as a contributor

I’ve focused a lot on the role of empathy as an open-source maintainer. But empathy absolutely comes into play as a contributor. There's a lot said on how people behave differently when commenting on the internet versus in person, and how the tone of a text comment can so easily be misread.

The fact is, when you contribute to an open-source project, the maintainers are going to come up short. They're going to overlook things. They may not respond promptly to your comment or PR -- they're likely going to hide their head in the sand because they're overwhemed.[^overwhelmed] Or they may snap at you.

[^overwhelmed]: For example, I've been ignoring messages in the Salsa Zulip for a bit, and feeling bad about how I just don't have the time to focus on that project right now. I'm sorry y'all and I do still expect to come back to Salsa 2022 (which, alas, will clearly not ship in 2022 -- ah well, I knew the risks when I put a year into the name).

So what do you do when people let you down? I think the best is to speak for your feelings, but to do so in an empathetic way. If you are feeling hurt, don't leave an angry comment. This doesn't mean you have to silence your feelings -- but just own them as your feelings. "Hey, I get that you are busy. Still, when I open a PR and nobody answers, it feels like this contribution is not wanted. If that's true, just tell me, I can go elsewhere."[^imessage]

[^imessage]: This structure, "when you do X, I feel Y", is called an [I-message][im]. It's surprisingly hard to do it right. It's easy to make something that sounds like an I-message, but isn't. For example, "When you closed this PR without commenting, it showed me I am not welcome here" is very different from "When you closed this PR without commenting, it made me feel like I am not welcome here". The first one is not an I-message. It's telling someone else how they feel. The second one is telling someone else how they made *you* feel. There's a very good chance those two statements would land quite differently.

[im]: https://en.wikipedia.org/wiki/I-message

I bet some of you, when you read that last comment, were like "oh, heck no". It's scary to talk about how you feel. It takes a lot of courage. But it's effective -- and it can help the maintainer get unblended from whatever part they are in and think about things from your perspective. Maybe they will answer, "No, I really want this change, but I am just super busy right now, can you give me 3 months?" Or maybe they will say, "Actually, you're right, I am not sure this is the right direction. I'm sorry that I didn't say so before you put so much work into it." Or **maybe** they won't answer at all, because they're hiding from the github issue thread -- but when they come back and read it much later, they'll reflect on how that made you feel, and try to be more prompt the next time. **Either way, you know that you spoke up for yourself, but did so in a way that they can hear.**

## Empathy for ourselves and our own parts

This brings me to my final topic. No matter what role we play in an open-source project, or in life, the most important person to have empathy for is **yourself**. Ironically, this is often the hardest. We usually have very high expectations for ourselves, and we don’t cut ourselves much slack. As a maintainer, this might manifest as feeling you have to respond to every comment or task, and feeling bad when you don’t keep up. As a contributor, it might be feeling . No matter who we are, it might be kicking ourselves and feeling shame when we overreact in a comment. 

In my view, shame is basically never good. Of course I make mistakes, and I regret them. But when I feel *shame* about them, I am actually focusing inward, focusing on my own mistakes instead of focusing on how I can make it up to the other person or resolve my predicament. It doesn’t actually do anyone any good. 

I think there are different ways to experience shame. I know how I experience it. It feels like one of my parts is kicking the crap out of itself. And that really hurts. It hurts so bad that it tends to cause other parts to rise up to try and make it stop. That might be by getting angry at others — “it’s *their* fault we screwed up!” — or, more common for me, it might be by feeling depressed, withdrawing, and perhaps focusing on some technical project that can make me feel good about myself.

In their classic and highly recommended blog post, [My FOSS Story][foss], Andrew Gallant talked about how they deal with an overflowing inbox full of issues, feature requests, and comments:

[foss]: https://blog.burntsushi.net/foss/

> The solution that I’ve adopted for this phenomenon is one that I’ve used extremely effectively in my personal life: establish boundaries. Courteously but firmly setting boundaries is one of those magical life hacks that pays dividends once you figure out how to do it. If you don’t know how to do it, then I’m not sure exactly how to learn how to do it unfortunately. But setting boundaries lets you focus on what’s important to you and not what’s important to others.

It can be really easy to overextend yourself in an open-source project. This could mean, as a maintainer, feeling you have to respond to every comment, fix every bug. Overextending yourself in turn is a great way to become blended with a part, and start acting out some of those older, defensive strategies you have for dealing with stress.

Also, I've got bad news. You are going to screw up in some way. It might be overextending yourself[^ag]. It might be responding poorly. Or pushing for an idea that turns out to be very deeply wrong. When you do that, you have a choice. You can feel shame, or you can extend compassion and empathy to yourself. **It's ok.** Mistakes happen. They are how we learn. 

[^ag]: Unless, perhaps, you are Andrew Gallant, who from what I can see is one supremely well balanced individual. :)

Once you've gotten past the shame, and realized that making mistakes doesn't make you bad, you can start to think about repair. OK, so you messed up. What can you do about it? Maybe nothing is needed. Or maybe you need to go and undo some of what you did. Or maybe you have to go and tell some people that what they are doing is not ok. Either way, compassion and empathy for yourself is how you will get there.

## On the limits of my own experience

Before I go, I want to take a moment to acknowledge the limits of my own experience. I am a cis, white male, and I think in this post it shows. When I encounter antipathy, it tends to be targeted at individual things I have done or ideas I am espousing. At most, it might come about because of the role I am playing. I don’t encounter conscious or unconscious bias on the basis of my race, gender, sexual orientation, or any other such thing. This gives me a lot of luxury. For example, for the most part, I can take a rude comment and I can usually find an underlying technical point to focus on in my response. This is not true for all maintainers. In writing this post, I thought a lot about how the dynamics of open source seem almost perfectly designed[^system] to be exclusive to people who are not from groups deemed “high status” by society. 

Rust has a pretty uneven track record here. There are projects that do better. Improving our processes to take better account of how they feel for participants is definitely a necessary step, along with other things. One thing I am convinced of: the more people that get involved in Rust -- **and especially the more distinct backgrounds and experiences those people have** -- the better it becomes. Rust is always trying to achieve 6 (previously) impossible things before breakfast, and we need all the ideas we can get.[^jlord]

[^system]: This of course is what people mean when they talk about systemic racism, or at least how I understand it: it’s not that open source or most other things were designed intentionally to reinforce bias, but the structures of our society are setup so that if you don’t *actively work to counteract bias*, you wind up playing into it.

[^jlord]: I always think of Jessica Lord's inspirational blog post [Privilege, Community, and Open source](http://jlord.us/blog/osos-talk.html), which sadly appears to be offline, but you can [read it on the web-archive](https://web.archive.org/web/20220201181735/https://jlord.us/blog/osos-talk.html).

## Be gentle with each other

If could I have just one wish, it would be this bastardized quote from the great Bill and Ted:

![Be gentle with each other][billandted]

[billandted]: {{< baseurl >}}/assets/2023-09-27-bill-and-ted.jpg

We’ve talked a lot about empathy and how it comes into play, but really, in my mind, it all boils down to being *gentle* when somebody slips up. Note that being gentle doesn't mean you can't also be real and authentic about how you felt. We talked earlier about [I-messages][im] -- by speaking plainly about how somebody made you feel, you can deliver a message that is both gentle and yet incredibly powerful. To me, the key is not to make assumptions about what's going on for other people. You can never know their motivations. You can make guesses, but they're always based on incomplete information. 

Does this mean I think we should all go running around saying "when you do X, I felt like you were trying to ruin the project?" Well, not really, although I think that would be an improvement. Even better though would be to stop and think, *wait, why would they be trying to ruin the project?* Instead of assuming what other people are doing, tell them how they are making you feel. Maybe say, "when you do X, I feel like you are saying my use case doesn't matter". Or, better yet, say "when you do X, I will no longer be able to do Y, which I find really valuable". I predict this is much more likely to lead to a constructive discussion.

It's important to remember that the choice of words can have strong impact, too. For me, words like *ruin* or phrases like *dumpster fire*, *shitshow*, etc, can be quite triggering all on their own. I'm not always consistent on this. I've noticed that I sometimes use strong, colorful language because I think it's funny. But I've also noticed that when other people do it, I can get pretty upset ("I know that code is not the best, but it's worked for the last 3 years dang it."). 

I think you can boil all of this down to **be precise and accurate when you communicate**. It's not accurate to say "you are trying to ruin the project". You can't know that. It is accurate to talk about what you feel and why you feel it. It's also not accurate to say something is a dumpster fire, but it is accurate to call out shortcomings and concerns.

Anyway, I'm done giving advice. I'm no expert here, just one more person trying to learn and do the best I can. What I can say with confidence is that the things I'm talking here have really helped me personally in approaching difficult situations in my life, and I hope that they'll help some of you too!
