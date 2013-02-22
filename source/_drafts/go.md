I generally try to avoid comparing Rust to other languages, as such
comparisons are very difficult to do properly, and besides we aim to
be a polite, respectful community.  But I basically can't say a word
about Rust without being asked to compare it to Go, so I thought it
was worthwhile to try and compare the two languages.

There is an important caveat that I should add: to do these sorts of
comparisons correctly, you should really be an expert in both
languages, and I do not claim to be any sort of expert in Go.  I've
never written more than a few short programs in it.  The sad reality
is that working on Rust leaves me little enough time to experiment
with building programs in other languages.  Oh well.  My comments here
are therefore high-level impressions.

Anyway, it is natural for people to want to compare Rust and Go.
After all, both languages have been billed as modern systems
languages, though of course nobody really defines what they mean by
"systems".  It seems clear, in fact, that Go and Rust mean somewhat
different things.  The Go team, I think, is thinking mostly of the
server. The Rust team, in contrast, is thinking mostly of the client.
This stems naturally from the fact that Go is primarily developed by
Google employees---who, you know, do a lot with servers---and Rust is
primarily developed by Mozilla employees---who, you know, do a lot
with clients.  Although I think some of the technical differences
between Go and Rust probably stem from this different viewpoint, I
don't think it really gets at the heart of what separates them.

Let me come right out and say it: I think Go is a pretty awesome
design.  I am not just being politic, either.  Designing a language is
hard work, and making something coherent and simple is crucial.
Knowing when to say no to complexity is crucial, and the Go designers
made an art of saying "no".

That said, I don't think I would ever have designed Go.  In fact, it's
hard for me to imagine a design more different.  Rust has
