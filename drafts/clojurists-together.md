In [January], I wrote a blog post about the possibility of creating a Rust foundation. Since publishing that blog post, I've been talking to a number of folks involved various open source foundations and projects to get a better idea of the 'prior art' in this area. I am going to start posting summaries of these conversations in a series of blog posts. Also, if people have suggestions for other organizations that I should be talking to, I'd love to hear them.

Today's blog post is summarizing a conversation that I had with Daniel Compton and Laurens Van Houtven from [Clojurists Together].

[Clojurists Together]: https://www.clojuriststogether.org/team/

## History of Clojurists Together

[Clojurists Together] started around two years ago. Inspired by [Ruby Together], it had two goals:

* To be a legal entity behind the [Clojars project](https://clojars.org/).
* To help fund the development and maintainance of projects in the Clojure ecosystem.

[Ruby Together]: https://rubytogether.org/

## Deciding which projects to fund

Projects are funded on a quarterly basis. Each quarter, people make applications to receive funding. Those applications are reviewed by the 7-member *Clojurists Together Committee* which makes the ultimate decisions of which projects to fund.

Decisions are also informed by a survey that the committee sends out to the Clojurists Together membership. This survey asks about the kinds of projects that their members would like to see funded. It's not binding, but it's a helpful guide.

## Applying for funding

You can see the [details of the Clojurists Together application process](https://www.clojuriststogether.org/open-source/) here.  

Some details that I noted which seemed interesting:

* The application is pretty lightweight, and their example consist of only a few paragraphs of text.
* Projects are all funded at the same, fixed rate. In 2018, that rate was $1800 per month, but in 2019 it was $3000 per month. Two projects were funded each quarter.
* Projects are always funded for a 3 month term.
* While they prefer not to judge by 'number of hours', the expectation is that projects will take more than 15 hours/month, but less than 80 hours/month.
* The criteria are listed publicly, and they include the sort of things you would expect: the history of funding, the prominence of the project, comments from members, as well as the track record of the applicants.

They said they've been considering adding in the ability to request smaller grants.

## Membership and voting

I mentioned that the decisions about which projects to fund are made by the [Clojurists Together] committee. This committee is elected. Each year, half the seats are up for re-election. 

The voters in the election are the **members** of Clojurists Together. Every person or corporation who donates to Clojurists Together is a member, and every member gets one vote, regardless of the amount that they donate.

Besides participating in the election, members also receive the quarterly survey that I mentioned earlier, which asks after the sort of projects that they would like to see funded.

## Legal structure

Clojurists Together began its life as a member of the [Software Freedom Conservancy][SFC], but they are currently in the process of moving to an independent company.

As a member of the SF Convervancy, Clojurists Together was a 501(c)3. This means that it is a "non-profit corporation" that is working for the public good, basically, and it also means that donations to Clojurists Together are tax deductible in the United States.

[SFC]: https://sfconservancy.org/

The new corporation will be a 501(c)6, which is a different variation of a non-profit corporation.  As Daniel and Laurens explained it (along with suitable "IANAL" caveats, which I will pass along):

* Each 501(c)6 is associated with some sort of community, and is limited to doing the "sorts of actions that lift all boats" for that community. 
* Donations to a 501(c)6 can still be tax deductible, but everyone is not automatically eligible. Donations can only be deducated by people are members of the "target community" that the 501(c)6 serves, and it is the responsibility of each person who donates to show that they are a member of the community. In other words, if you choose to write-off donations on your taxes, you would have to defend that choice if you were audited. But the rules for who is a member are fairly loose.
* In the case of Clojurists Together, this means that Clojure programmers could definitely write-off donations. Folks working in a clojure shop, but who are not themselves programmers, could also write-off their donations. But someone with no connection to clojure at all could not (but then, are they likely to be donating)?

## Why choose a 501(c)6?

So why did Clojurists Together opt for a 501(c)6? There were two reasons:

* First, forming a 501(c)6 is much, much simpler than forming a 501(c)3. When you form a 501(c)3, you have to go through a lengthy and uncertain approval process where you justify why you are serving the public good (moreover, lately, it has become harder for software companies to get that sort of status, although there are rumors that this is changing back again lately).
* Second, for Clojurists Together at least, this distinction doesn't make much difference. Most anyone who donates to Clojurists Together would still be able to deduct donations. And, for people outside the US, or for those who don't file an itemized deduction, they wouldn't be able to deduct donations in any case.

## Transitioning from a 501(c)3 to a 501(c)6

One interesting wrinkle: when Clojurists Together was housed at the SF Conservancy, it was a 501(c)3, but its new home is a 501(c)6. For tax reasons, it is not legally possible to transfer money from a 501(c)3 to a 501(c)6, so they are basically having to "spend out" the remaining funds from their old bank account, while accruing new funds in the new account. This hasn't proved to be a major hurdle.

## Employees

Serving on the Clojurists Together Committee is an unpaid position. They do hire a part-time admin to help follow-up on the payments and generally tackle adminstrative duties.

## Incorporating in the US

They chose to incorporate in the US. This does mean that they cannot fund members in countries under US Sanctions. They do have board members from Europe and they haven't really found that being based in the US has caused any particular issues.

## The process of forming the group

When they were first getting started, they formed the initial board by reaching out to people that they knew and trusted. Most of those terms were set to expire after one year, at which point the board elections kicked in. This scheme worked out pretty well.

When forming the 501(c)6, they did send out messages to their members requesting feedback on their decisions along the way, but they didn't get much response. They interpreted this to mean that most folks trusted them to handle the details.

One thing to keep in mind is that, even with relatively few people involved, the process of forming a new company still took quite a long time (about 9 months) and involved a fair amount of back and forth. It's definitely wise to have a few "key people" driving it forward.

In terms of what details make sense to focus on, they suggested that it would be wise to keep conversation focused on higher-level questions about the jobs that the foundation should take on. 

They felt that many of the decisions along the way, such as which state to base the corporation in[^DE], are not ultimately that interesting and don't really require community discussion. Details like the drafting of the by-laws are generally handled by the lawyers involved.

[^DE]: Answer: Delaware.

## Conclusion

I enjoyed talking to Daniel and Laurens. It was, in a way, quite relaxing. Clojurists Together seems to have a simple structure and it seems to be working well for them.

## Footnotes