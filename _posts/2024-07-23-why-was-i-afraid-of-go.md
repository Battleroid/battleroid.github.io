---
title: Why was I so afraid of Go?
date: 2023-07-24
fragment: true
---

At work I've gone through the effort to setup a nice little pipeline that takes new objects in S3, gunzips them then bulks them to our OS cluster(s) (and optionally feeds them to a separate DLQ bucket in the case of any lambda or OS bulk errors). Originally, to feed data into the pipeline we were using elasticdump along with a secondary container within the pod to sign HTTP requests off to AWS with an obnoxious rolesanywhere setup. The problem with elasticdump was it seemed to just have a slow memory leak of sorts.

![Pipeline]({{ site.baseurl }}/assets/graph1.svg)

{: .caption}
The gist of the pipeline.

Deploying it with an upper limit of 4GB or even 20GB sometimes wouldn't be enough to scroll through an entire index before Kubernetes would end up OOM killing it. I had some downtime this last week and thought, you know I could probably write something to replicate the existing functionality, but in Go. I'll admit I have never really written much Go outside of anything aside from a couple one-off things to translate corpus material for Elastic's Rally, so it sounded like a fun little excursion from my norms.

Anyhow, I ended up just asking ChatGPT what would the basic structure of the program would look like which is my weakness. I have a hard time gauging _how to start_. That was my problem with Python when I started as well; I could grasp how I might do something, but not how to _structure_ it itself. Go itself isn't that hard to write, even for someone like me (haha), but how to structure it is something that still makes my head spin.

I ended up finding the nice example repo and coupled with ChatGPT I was able to get a decent handle on how the structure should look. First iterations of it worked well, but still uploaded files in serial, so during a scroll over an index it'd have to stop and wait for each file to be uploaded before moving on. I read up on how `sync.WaitGroup` worked, had a few unsuccessful tries before I ended up with something that worked.

The first couple iterations I tried had some wonkiness; sometimes it'd exit before uploading anything, other times it'd upload files, but only if it had more than one file to submit. Turns out I was just working with the `WaitGroup` entirely wrong. I revisited it and restarted from scratch. Now it's functional! It's able to scroll through, properly upload objects in the background as the scroll progresses.

The entire experience was relatively painless and it felt nice to put something together that just worked™ that _wasn't_ Python for once. I think from now on I'll definitely be more open to using Go if I have the time. Even using goroutines and channels wasn't too bad for a novice like me.

If you'd like to look at the code itself, it's here at [github.com/battleroid/es-to-s3-dumper](https://github.com/Battleroid/es-to-s3-dumper). It's not the best code quality wise since it's my first real attempt at something, but it is functional.

I think at the end of this I'm left with just a couple questions that I'll need to do some more reading on:
1. What's the ideal way to handle logging? What is appropriate to log and where should I log it?
    * e.g. when I'm uploading an S3 object, should I log that at the top most level, or log within the function(s) itself at the lowest level possible?
2. Should I avoid doing most of my logic within main? Would it have been more appropriate to shove the contents of main into `cmd/`?

*[OS]: OpenSearch
*[DLQ]: Dead Letter Queue
