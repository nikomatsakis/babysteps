By now you may have heard that the Rust All Hands this year has been
cancelled. What's worse, it was cancelled after many people had
already booked travel. I am not proud of this outcome.

I wanted to write a post that talked about what exactly happened, from
my perspective, and what to learn from it.

### What happened

**Previous Rust All Hands.** There have been two previous Rust All
Hands events. They both took place in Mozilla's Berlin office. Mozilla
traditionally sponsored the event, providing the venue and catering,
and also paying for the flights and accommodation of volunteers who
didn't have a company or other person to pay for them. It was a good
way to bring the entire community together for a week of planning,
discussions, and comradarie.

Still, after the last All Hands, it was clear that we couldn't do a
third one in Mozilla's Berlin office. The Rust org was simply growing
too big. The Berlin office didn't really have the space to accommodate
us.

**Forming the All Hands group.** It was clear that organizing the All
Hands was going to be some work and we weren't sure how best to manage
it. In core team discussions, we decided to send mail to the mailing
list looking for volunteers.  We got a number of responses and we had
some meetings; from the core team, initially Florian, Manish and
myself were attending, but over time they were busy, so I was the
primary one involved.

I'll write more about this later, but I think this was our first
mistake. I think we clearly should have tried to find a way to hire
someone who would manage the process full time, rather than trying to
run it 'on the side'. Given the realities of how things are setup now,
this would have meant that Mozilla would have contracted with someone.
But we didn't do that.

**Finding a space.** As a group, our first step was to see if we could
find other companies to sponsor a space.  We followed a number of
leads but ultimately never found anyone that had a space to offer in a
suitable time frame. We started looking at other options, like private
hacker spaces and universities. The University of Macedona in
Thessaloniki, Greece offered us a quite attractice price, and they had
the right time available, so we decided to go for that.

**Budgeting and sponsorships.** We in the All Hands group did our best
to create a budget. We had a survey we could use to estimate the
number of attendees and a rough idea where they were coming from. We
knew the costs of the venue. We added fudge factors. We thought we'd
done a good job, though it would turn out that we were quite off in
our calculations.

Based on our estimated budget, it was clear that Mozilla was not going
to be able to cover the costs alone. It seemed like a good opportunity
to try and build relationships with some of the companies that have
started to use Rust by approaching them for sponsorships. We weren't
sure, though, how man sponsorships we'd be able to get, and so we hit
upon the idea of using paid tickets. The idea was that people could
purchase a ticket to the event, which would help to cover the costs,
but that it was also ok to not have a ticket. Tickets have the
advantage of being relatively easy for people to submit in their
expense report if they are traveling with a company. We also found a
number of companies who might be interested in a more traditional
sponsorship.

**Finding a bank account.** Still, we had another problem. The Rust
organization does not have a bank account we could use to collect and
distribute money, and we didn't have an obvious entity to sign legal
agreements. 

At this point, we spoke to a company that might serve as a bank
account.  We had a quick call and went over a plan that seemed
promising. Mozilla would contract with them for their services
managing and organizing the event, and this would serve as Mozilla's
sponsorship. The other sponsorships and proceeds from ticket sales
would collect in their bank account and we would manage distributions.

**Pulling the trigger.** At that point, we sent mail encouraging
people to book tickets, and we also started following up more with
sponsors. Our expectation was that we would soon have a bank account
for collecting funds, and we started collecting information to repay
people who had booked travel.

In retrospect, it's clear that this was premature. It **seemed** like
all the pieces were in place, and we knew that if people didn't start
booking tickets, they never would. But the pieces were **not** in
place, not actually, and we clearly should have taken this moment ask
whether we were really going to be able to pull this off.

**Realizing it won't work.** Finally, this all started to unravel in a
spectacularly stressful fashion during the Mozilla All Hands. In
short, we encountered some logistical hurdles, which I won't go into,
but which also prompted us to review the finances in more detail.
This revealed that our estimates were off. Thus, we were faced with a
tough decision:

* If we continue with the event, there was the chance that the logistics
  would just fail to come together. That would be a true disaster.
* Further, we might not be able to raise enough money to be able to
  pay for the entirety of people's travel and lodging as we had
  promised. This would be unfortunate, though perhaps something people
  could live with.
* On the other hand, if we cancel, we have to deal with the fact that
  people had already started booking travel.
  
After much analysis and discussion with the Rust core team, we
ultimately opted for the painful but ultimately safer route: cancel
the event.

### Thank you

At this point I want to offer many thanks. First of all, I want to
thank the volunteers who helped in trying to organize the Rust All
Hands. Things did not go to plan, but it's not because of their
efforts; they did great work.

Second, I want to thank the University of Macedonia (the venue) and
the sponsors who had offered sponsorship which (alas) we will never
use. They were ready to step up and support the Rust community and I
think they still deserve credit for it. Those sponsors were:

* Embark
* Facebook
* Fastly
* Mozilla

### The next Rust All Hands?

So what happens now, will we do another Rust All Hands? I don't really
think it's feasible to do one this year. I think we would have to be
thinking about the plan for next year (and see the next section for
some thoughts about that).

### What could we have done differently

So, what could we have done differently? 

**Know your limits.** I think this failure shares a root cause that is
typical for the Rust org: we try really, really hard. We want to do it
all and sometimes we don't recognize our limits.

In a way, it's not surprising. We are after all a community of people
who set out with the goal of displacing C and C++ as the systems
programming language of choice, which is a near impossible task.

Many people have said that the Rust 2018 edition was an example of
doing too much, and in some ways I agree (not all). But there is no
question that in 2019 there was a general feeling of exhaustion. We
chose to step back from a number of projects which we clearly didn't
have the energy to manage, however much we might want to.  In
retrospect, perhaps planning the Rust All Hands 2020 should have been
one of them.

**The importance of expertise and money.** In truth, I think that
there might have been a way to pull the All Hands off. What I could've
tried is to find a contractor or events company to run the event. I
thought about doing this, but for some reason opted against it. Here I
am writing that "I" could have done this because any such contractor
would ultimately have been contracting with Mozilla, since right now
the Rust org doesn't have any way to make contracts on its own.

It's pretty clear to me that running an event is best done with both
experience and full-time attention (like so many things, I suppose).
I think it should have been clear that attempting to organize and run
the All Hands as a side effort of a number of people was risky.

This isn't to say that there is no role for the Rust org. I think what
we probably would have wanted is to still have the All Hands group,
but to have the event coordinator interacting with them. The group
could then have been tasked with determining the agenda and topics,
for example.

**The need for a foundation and for investment.** Of course, people
reading my blog will have seen my post calling for a Rust
foundation. Clearly, some of my thinking in that post was already
influenced by the challenges we were facing in trying to organize the
All Hands.

Having a foundation would obviously have solved a number of practical
obstacles for us and it might've been enough to keep things working.

Still, I don't think a foundation is the whole story. Just having a
bank account doesn't make for a successful event. We would also still
need to have an event coordinator and people who can manage the tax
implications and all the rest. But it might give us the structure to
make hiring and working with such people much easier.

### Conclusion

I'll be honest, this was a low point of my time in Rust. I feel
terrible that we were not able to pull off this event. I feel bad for
the folks that purchased tickets and made plans only to have them
upended. I'm obviously going to do my best to help resolve the
financial implications, but it's still a disappointment on my part. I
don't like to let people down.

Still, at the end of the day, life goes on. Rust goes on. I know we
can put this behind us and focus on the coming year and the many
things we'd like to do.
