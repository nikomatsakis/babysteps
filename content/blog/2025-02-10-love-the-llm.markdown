---
title: "How I learned to stop worrying and love the LLM"
date: 2025-02-10T15:56:19Z
---

I believe that AI-powered development tools can be a game changer for Rust---and vice versa. At its core, my argument is simple: AI's ability to explain and diagnose problems with rich context can help people get over the initial bump of learning Rust in a way that canned diagnostics never could, no matter how hard we try. At the same time, rich type systems like Rust's give AIs a lot to work with, which could be used to help them avoid hallucinations and validate their output. This post elaborates on this premise and sketches out some of the places where I think AI could be a powerful boost.

## Perceived learning curve is challenge #1 for Rust

Is Rust good for every project? No, of course not. But it's absolutely **great** for some things---specifically, building reliable, robust software that performs well at scale. This is no accident. Rust's design is intended to surface important design questions (often in the form of type errors) and to give users the control to fix them in whatever way is best.

But this same strength is also Rust's biggest challenge. Talking to people within Amazon about adopting Rust, perceived complexity and fear of its learning curve is the biggest hurdle. Most people will say, *"Rust seems interesting, but I don't need it for this problem"*. And you know, they're right! They don't *need* it. But that doesn't mean they wouldn't benefit from it.

One of Rust's big surprises is that, once you get used to it, it's "surprisingly decent" at very large number of things beyond what it was designed for. Simple business logic and scripts can be very pleasant in Rust. But the phase "once you get used to it" in that sentence is key, since most people's initial experience with Rust is **confusion and frustration**.

## Rust likes to tell you *no* (but it's for your own good)

Some languages are geared to say *yes*---that is, given any program, they aim to run it and do *something*. JavaScript is of course the most extreme example (no semicolons? no problem!) but every language does this to some degree. It's often quite elegant. Consider how, in Python, you write `vec[-1]` to get the last element in the list: super handy! 

Rust is not (usually) like this. Rust is geared to say *no*. The compiler is just *itching* for a reason to reject your program. It's not that Rust is mean: Rust just wants your program to be as good as it can be. So we try to make sure that your program will do what you *want* (and not just what you asked for). This is why `vec[-1]`, in Rust, will panic: sure, giving you the last element might be convenient, but how do we know you didn't have an off-by-one bug that resulted in that negative index?[^zip]

[^zip]: We don't always get this right. For example, I find the `zip` combinator of iterators annoying because it takes the shortest of the two iterators, which is occasionally nice but far more often hides bugs.

But that tendency to say *no* means that early learning can be pretty frustrating. For most people, the reward from programming comes from seeing their program run---and with Rust, there's a *lot* of niggling details to get right before your program will run. What's worse, while those details are often motivated by deep properties of your program (like data races), the way they are *presented* is as the violation of obscure rules, and the solution ("add a `*`") can feel random.

Once you get the hang of it, Rust feels great, but getting there can be a pain. I heard a great phrase from someone at Amazon to describe this: "Rust: the language where you get the hangover first".[^source]

[^source]: I think they told me they heard it somewhere on the internet? Not sure the original source.

## AI today helps soften the learning curve

My favorite thing about working at Amazon is getting the chance to talk to developers early in their Rust journey. Lately I've noticed an increasing trend---most are using Q Developer. Over the last year, Amazon has been doing a lot of internal promotion of Q Developer, so that in and of itself is no surprise, but what did surprise me a bit is hearing from developers the *way* that they use it.

For most of them, the most valuable part of Q Dev is authoring code but rather **explaining** it. They ask it questions like "why does this function take an `&T` and not an `Arc<T>`?" or "what happens when I move a value from one place to another?". Effectively, the LLM becomes an ever-present, ever-patient teacher.[^toopolite]

[^toopolite]: Personally, the thing I find most annoying about LLMs is the way they are trained to respond like groveling serveants. "Oh, that's a good idea! Let me help you with that" or "I'm sorry, you're right I did make a mistake, here is a version that is better". Come on, I don't need flattery. The idea is fine but I'm aware it's not earth-shattering. Just help me already.

## Scaling up the Rust expert

Some time back I sat down with an engineer learning Rust at Amazon. They asked me about an error they were getting that they didn't understand. "The compiler is telling me something about `‘static`, what does that mean?" Their code looked something like this:

```rust
async fn log_request_in_background(message: &str) {
    tokio::spawn(async move {
        log_request(message);
    });
}
```

And the [compiler was telling them](https://play.rust-lang.org/?version=stable&mode=debug&edition=2021&gist=0985ec4502f7ca148cc8919f2081ad02):

```
error[E0521]: borrowed data escapes outside of function
 --> src/lib.rs:2:5
  |
1 |   async fn log_request_in_background(message: &str) {
  |                                      -------  - let's call the lifetime of this reference `'1`
  |                                      |
  |                                      `message` is a reference that is only valid in the function body
2 | /     tokio::spawn(async move {
3 | |         log_request(message);
4 | |     });
  | |      ^
  | |      |
  | |______`message` escapes the function body here
  |        argument requires that `'1` must outlive `'static`
```

This is a pretty good error message! And yet it requires significant context to understand it (not to mention scrolling horizontally, sheesh). For example, what is "borrowed data"? What does it mean for said data to "escape"? What is a "lifetime" and what does it mean that "`'1` must outlive `'static`"? Even assuming you get the basic point of the message, what should you **do** about it?

## The fix is easy... *if* you know what to do

Ultimately, the answer to the engineer's problem was just to insert a call to `clone`[^subtle]. But deciding on that fix requires a surprisingly large amount of context. In order to figure out the right next step, I first explained to the engineer that this confusing error is, in fact, [what it feels like when Rust saves your bacon](https://smallcultfollowing.com/babysteps/blog/2022/06/15/what-it-feels-like-when-rust-saves-your-bacon/), and talked them through how the ownership model works and what it means to free memory. We then discussed why they were spawning a task in the first place (the answer: to avoid the latency of logging)---after all, the right fix might be to just not spawn at all, or to use something like rayon to block the function until the work is done.

Once we established that the task needed to run asynchronously from its parent, and hence had to own the data, we looked into changing the `log_request_in_background` function to take an `Arc<String>` so that it could avoid a deep clone. This would be more efficient, but only if the caller themselves could cache the `Arc<String>` somewhere. It turned out that the origin of this string was in another team's code and that this code only returned an `&str`. Refactoring that code would probably be the best long term fix, but given that the strings were expected to be quite short, we opted to just clone the string.


[^subtle]: Inserting a call to `clone` is actually a bit more subtle than you might think, given the interaction of the `async` future here. 


## You can learn a lot from a Rust error


> An error message is often your first and best chance to teach somebody something.---Esteban Küber (paraphrased)

Working through this error was valuable. It gave me a chance to teach this engineer a number of concepts. I think it demonstrates a bit of Rust's promise---the idea that learning Rust will make you a better programmer overall, regardless of whether you are using Rust or not.

Despite all the work we have put into our compiler error messages, this kind of detailed discussion is clearly something that we could never achieve. It's not because we don't want to! The original concept for `--explain`, for example, was to present a customized explanation of each error was tailored to the user's code. But we could never figure out how to implement that.

**And yet tailored, in-depth explanation is *absolutely* something an LLM could do.** In fact, it's something they already do, at least some of the time---though in my experience the existing code assistants don't do nearly as good a job with Rust as they could.

## What makes a good AI opportunity?

[Emery Berger](https://emeryberger.com) is a professor at UMass Amherst who has been exploring how LLMs can improve the software development experience. Emery emphasizes how AI can help **close the gap** from "tool to goal". In short, today's tools (error messages, debuggers, profilers) tell us things about our program, but they stop there. Except in simple cases, they can't help us figure out what to do about it---and this is where AI comes in.


When I say AI, I am not talking (just) about chatbots. I am talking about programs that weave LLMs into the process, using them to make heuristic choices or proffer explanations and guidance to the user. Modern LLMs can also do more than just rely on their training and the prompt: they can be given access to APIs that let them query and get up-to-date data.


I think AI will be most useful in cases where solving the problem requires external context not available within the program itself. Think back to my explanation of the `'static` error, where knowing the right answer depended on how easy/hard it would be to change other APIs.


## Where I think Rust should leverage AI


I've thought about a lot of places I think AI could help make working in Rust more pleasant. Here is a selection.


### Deciding whether to change the function body or its signature


Consider this code:


```rust
fn get_first_name(&self, alias: &str) -> &str {
    alias
}
```


This function will give a type error, because the signature (thanks to lifetime elision) promises to return a string borrowed from `self` but actually returns a string borrowed from `alias`. Now...what is the right fix? It's very hard to tell in isolation! It may be that in fact the code was meant to be `&self.name` (in which case the current signature is correct). Or perhaps it was meant to be something that sometimes returns `&self.name` and sometimes returns `alias`, in which case the signature of the function was wrong. Today, we take our best guess. But AI could help us offer more nuanced guidance.


### Translating idioms from one language to another


People often ask me questions like "how do I make a visitor in Rust?" The answer, of course, is "it depends on what you are trying to do". Much of the time, a Java visitor is better implemented as a Rust enum and match statements, but there is a time and a place for something more like a visitor. Guiding folks through the decision tree for how to do non-trivial mappings is a great place for LLMs.


### Figuring out the right type structure


When I start writing a Rust program, I start by authoring type declarations. As I do this, I tend to think ahead to how I expect the data to be accessed. Am I going to need to iterate over one data structure while writing to another? Will I want to move this data to another thread? The setup of my structures will depend on the answer to these questions.


I think a lot of the frustration beginners feel comes from not having a "feel" yet for the right way to structure their programs. The structure they would use in Java or some other language often won't work in Rust.


I think an LLM-based assistant could help here by asking them some questions about the kinds of data they need and how it will be accessed. Based on this it could generate type definitions, or alter the definitions that exist. 


### Complex refactorings like splitting structs


A follow-on to the previous point is that, in Rust, when your data access patterns change as a result of refactorings, it often means you need to do more wholesale updates to your code.[^goodbad] A common example for me is that I want to split out some of the fields of a struct into a substruct, so that they can be borrowed separately.[^lang] This can be quite non-local and sometimes involves some heuristic choices, like "should I move this method to be defined on the new substruct or keep it where it is?".


[^lang]: I also think we should add a feature like [View Types][] to make this less necessary. In this case instead of refactoring the type structure, AI could help by generating the correct type annotations, which might be non-obvious.


[View Types]: https://smallcultfollowing.com/babysteps/blog/2021/11/05/view-types/


[^goodbad]: Garbage Collection allows you to make all kinds of refactorings in ownership structure without changing your interface at all. This is convenient, but---as we discussed early on---it can hide bugs. Overall I prefer having that information be explicit in the interface, but that comes with the downside that changes have to be refactored.


### Migrating consumers over a breaking change


When you run the `cargo fix` command today it will automatically apply various code suggestions to cleanup your code. With the [upcoming Rust 2024 edition][2024], `cargo fix---edition` will do the same but for edition-related changes. All of the logic for these changes is hardcoded in the compiler and it can get a bit tricky. 


[2024]: https://doc.rust-lang.org/nightly/edition-guide/rust-2024/index.html


[ts]: https://doc.rust-lang.org/nightly/edition-guide/rust-2024/temporary-if-let-scope.html


For editions, we intentionally limit ourselves to local changes, so the coding for these migrations is usually not *too* bad, but there are some edge cases where it'd be really useful to have heuristics. For example, [one of the changes we are making in Rust 2024][ts] affects "temporary lifetimes". It can affect when destructors run. This almost never matters (your vector will get freed a bit earlier or whatever) but it *can* matter quite a bit, if the destructor happens to be a lock guard or something with side effects. In practice when I as a human work with changes like this, I can usually tell at a glance whether something is likely to be a problem---but the heuristics I use to make that judgment are a combination of knowing the name of the types involved, knowing something about the way the program works, and perhaps skimming the destructor code itself. We could hand-code these heuristics, but an LLM could do it and better, and if could ask questions if it was feeling unsure.


Now imagine you are releasing the 2.x version of your library. Maybe your API has changed in significant ways. Maybe one API call has been broken into two, and the right one to use depends a bit on what you are trying to do. Well, an LLM can help here, just like it can help in translating idioms from Java to Rust. 


I imagine the idea of having an LLM help you migrate makes some folks uncomfortable. I get that. There's no reason it has to be mandatory---I expect we could always have a more limited, precise migration available.[^hottake]


[^hottake]: My hot take here is that if the idea of an LLM doing migrations in your code makes you uncomfortable, you are likely (a) overestimating the quality of your code and (b) underinvesting in tests and QA infrastructure[^irony]. I tend to view an LLM like a "inconsistently talented contributor", and I am perfectly happy having contributors hack away on projects I own.


[^irony]: The irony, of course, is that AI can help you to improve your woeful lack of tests by auto-generating them based on code coverage and current behavior.


### Optimize your Rust code to eliminate hot spots


Premature optimization is the root of all evil, or so Donald Knuth is said to have said. I'm not sure about *all* evil, but I have definitely seen people rathole on microoptimizing a piece of code before they know if it's even expensive (or, for that matter, correct). This is doubly true in Rust, where cloning a small data structure (or reference counting it) can often make your life a lot simpler. Llogiq's great talks on [Easy Mode Rust](https://llogiq.github.io/2024/03/28/easy.html) make exactly this point. But here's a question, suppose you've been taking this advice to heart, inserting clones and the like, and you find that your program *is* running kind of slow? How do you make it faster? Or, even worse, suppose that you are trying to turn our network service. You are looking at the [blizzard of available metrics](https://docs.rs/tokio-metrics/0.3.1/tokio_metrics/struct.TaskMetrics.html) and trying to figure out what changes to make. What do you do? To get some idea of what is possible, check out [Scalene](https://github.com/plasma-umass/scalene), a Python profiler that is also able to offer suggestions as well (from Emery Berger's group at UMass, the professor I talked about earlier). 


### Diagnose and explain miri and sanitizer errors


Let's look a bit to the future. I want us to get to a place where the "minimum bar" for writing unsafe code is that you test that unsafe code with some kind of sanitizer that checks for both C and Rust UB---something like miri today, except one that works "at scale" for code that invokes FFI or does other arbitrary things. I expect a smaller set of people will go further, leveraging automated reasoning tools like Kani or Verus to prove statically that their unsafe code is correct[^paradox]. 


[^paradox]: The student asks, "When unsafe code is proven free of UB, does that make it safe?" The master says, "Yes." The student asks, "And is it then still unsafe?" The master says, "Yes." Then, a minute later, "Well, sort of." (We may need new vocabulary.)

From my experience using miri today, I can tell you two things. (1) Every bit of unsafe code I write has some trivial bug or other. (2) If you enjoy puzzling out the occasionally inscrutable error messages you get from Rust, you're gonna *love* miri! To be fair, miri has a much harder job---the (still experimental) rules that govern Rust aliasing are intended to be flexible enough to allow all the things people want to do that the borrow checker doesn't permit. This means they are much more complex. It also means that explaining why you violated them (or may violate them) is that much more complicated.


Just as an AI can help novices understand the borrow checker, it can help advanced Rustaceans understand [tree borrows](https://perso.crans.org/vanille/treebor/) (or whatever aliasing model we wind up adopting). And just as it can make smarter suggestions for whether to modify the function body or its signature, it can likely help you puzzle out a good fix.


## Rust's emphasis on "reliability" makes it a great target for AI


Anyone who has used an LLM-based tool has encountered hallucinations, where the AI just makes up APIs that "seem like they ought to exist".[^favorite] And yet anyone who has used *Rust* knows that "if it compiles, it works" is true may more often than it has a right to be.[^functional] This suggests to me that any attempt to use the Rust compiler to validate AI-generated code or solutions is going to also help ensure that the code is correct.

AI-based code assistants right now don't really have this property. I've noticed that I kind of have to pick between "shallow but correct" or "deep but hallucinating". A good example is `match` statements. I can use rust-analyzer to fill in the match arms and it will do a perfect job, but the body of each arm is `todo!`. Or I can let the LLM fill them in and it tends to cover most-but-not-all of the arms but it generates bodies. I would love to see us doing deeper integration, so that the tool is talking to the compiler to get perfect answers to questions like "what variants does this enum have" while leveraging the LLM for open-ended questions like "what is the body of this arm".[^distract]

[^favorite]: My personal favorite story of this is when I asked ChatGPT to generate me a list of "real words and their true definition along with 2 or 3 humorous fake definitions" for use in a birthday party game. I told it that "I know you like to hallucinate so please include links where I can verify the real definition". It generated a great list of words along with plausible looking URLs for merriamwebster.com and so forth---but when I clicked the URLs, they turned out to all be 404s (the words, it turned out, were real---just not the URLs).

[^functional]: This is not a unique property of Rust, it is shared by other languages with rich type systems, like Haskell or ML. Rust happens to be the most widespread such language.

[^distract]: I'd also like it if the LLM could be a bit less interrupt-y sometimes. Especially when I'm writing type-system code or similar things, it can be distracting when it keeps trying to author stuff it clearly doesn't understand. I expect this too will improve over time---and I've noticed that while, in the beginning, it tends to guess very wrong, over time it tends to guess better. I'm not sure what inputs and context are being fed by the LLM in the background but it's evident that it can come to see patterns even for relatively subtle things.

## Conclusion


Overall AI reminds me a lot of the web around the year 2000. It's clearly overhyped. It's clearly being used for all kinds of things where it is not needed. And it's clearly going to change everything. 


If you want to see examples of what is possible, take a look at the [ChatDBG][] videos published by Emery Berger's group. You can see how the AI sends commands to the debugger to explore the program state before explaining the root cause. I love the video [debugging bootstrap.py](https://asciinema.org/a/qulxiJTqwVRJPaMZ1hcBs6Clu), as it shows the AI applying domain knowledge about statistics to debug and explain the problem.


[ChatDBG]: https://github.com/plasma-umass/ChatDBG


My expectation is that compilers of the future will not contain nearly so much code geared around authoring diagnostics. They'll present the basic error, sure, but for more detailed explanations they'll turn to AI. It won't be just a plain old foundation model, they'll use RAG techniques and APIs to let the AI query the compiler state, digest what it finds, and explain it to users. Like a good human tutor, the AI will tailor its explanations to the user, leveraging the user's past experience and intuitions (oh, and in the user's chosen language).


I am aware that AI has some serious downsides. The most serious to me is its prodigous energy use, but there are also good questions to be asked about the way that training works and the possibility of not respecting licenses. The issues are real but avoiding AI is not the way to solve them. Just in the course of writing this post, DeepSeek was announced, demonstrating that there is a lot of potential to lower the costs of training. As far as the ethics and legality, that is a very complex space. Agents are already doing a lot to get better there, but note also that most of the applications I am excited about do not involve writing code so much as helping people understand and alter the code they've written.






