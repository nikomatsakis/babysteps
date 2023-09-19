---
layout: post
title: Fix my blog, please
date: 2023-04-03 08:38 -0400
---

It's well known that my blog has some issues. The category links don't work. It renders oddly on mobile. And maybe Safari, too? The Rust snippets are not colored. The RSS feed is apparently not advertised properly in the metadata. It's published via a makefile instead of some hot-rod CI/CD script, and it uses jekyll instead of whatever the new hotness is.[^but] Being a programmer, you'd think I could fix this, but I am intimidated by HTML, CSS, and Github Actions. Hence this call for help: **I'd like to hire someone to "tune up" the blog, a combination of fixing the underlying setup and also the visual layout.** This post will be a rough set of things I have in mind, but I'm open to suggestions. If you think you'd be up for the job, read on.

[^but]: On the other hand, it has that super cute picture of my daughter (from around a decade ago, but still...). And the content, I like to think, is decent.

## Desiderata[^coolword]

In short, I am looking for a rad visual designer who also can do the technical side of fixing up my jekyll and CI/CD setup.

Specific works item I have in mind:

* Syntax highlighting 
* Make it look great on mobile and safari
* Fix the category links
* Add RSS feed into metadata and link it, whatever is normal
* CI/CD setup so that when I push or land a PR, it deploys automatically
* "Tune up" the layout, but keep the cute picture![^tables]

[^tables]: Ooooh, I always want nice looking tables like those wizards who style github have. How come my tables are always so ugly?

[^coolword]: I have a soft spot for wacky plurals, and "desiderata" might be my fave.  I heard it first from a Dave Herman presentation to TC39 and it's been rattling in my brain ever since, wanting to be used.

Bonus points if you can make the setup easier to duplicate. Installing and upgrading Ruby is a horrible pain and I always forget whether I like rbenv or rubyenv or whatever better. Porting over to Hugo or Zola would likely be awesome, so long as links and content can be preserved. I do use some funky jekyll plugins, though I kind of forgot why. Alternatively maybe something with docker?

## Current blog implementation

The blog is a jekyll blog with a custom theme. Sources are here:

* https://github.com/nikomatsakis/babysteps
* https://github.com/nikomatsakis/nikomatsakis-babysteps-theme

Deployment is done via rsync [at present](https://github.com/nikomatsakis/babysteps/blob/8820df7df4ac5b888ea8adec95c5449750709d7b/babysteps/Makefile#L18).

## Interested?

Send me an [email] with your name, some examples of past work, any recommendations etc, and the rate you charge. Thanks!

[email]: mailto:niko@alum.mit.edu?subject=babysteps+to+beauty



