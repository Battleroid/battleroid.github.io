---
title: Squiggler and its evolution
date: 2023-03-28
---

# Some context

When I started as a brand new intern at Mailchimp, we had a handful of clusters. We had one for delivery data, logging, sandbox and a couple extras meant for customer account data. One of my first projects involved the pipeline for getting developers' soon-to-be-logged data templated; so it could transition from pull request to feature with logging ready to go for aggregations and debugging.

The old process was somewhat handheld and gatekept, not by design, that's just how it seemed to evolve. First, developers would need to ready their feature or pull request with the appropriate logging methods. Easy enough. Second, they'd have to convene with us, the (at the time) data engineering team, to get them set up so they can then feed their data to our sandbox cluster, pull the mapping, fix up types, etc. Then finally get it approved and finally create the pattern in Kibana. **This process kinda sucked for everyone.**

So as a fresh intern (or maybe I was a junior?) with some Elasticsearch exposure behind my belt, my task was to streamline that process. The original project named "Cartographer" was a way to not only automate the entire mapping piece, but also provide basic linting that conformed to our standards, as well as apply the templates; thus providing a one stop shop for developers to check our their data, fix it up, and get it finalized without involving us. Then once they were ready, they could have us do a final review, and we'd get them squared away.

We were still living on 2.x for a good while with time based indices so occasionally we'd get a monstrously huge index that would cause us issues. Well into my junior tenure we managed to move early and upgrade to Elasticsearch 5.x. We also made the major decision to begin splitting up our old faithful logging cluster due to the new introduction of cross cluster search. This would ease the burden on the logging cluster(s) and allow us to keep people happy if a cluster underneath died, as practically everyone in the company used the data we logged.

My memory is fuzzy (it's been awhile!), but I know for a fact we split off at least a handful of clusters, the biggest of the few being those that dealt with both apache, nginx, container (docker, k8s, etc) and the monolith logs. Splitting these up helped tremendously, but we still had an issue, time based indices for all of these kinda suck for fast moving data. They offer no flexible way to mitigate spikes and allow slower hours to bloat up the cluster with unnecessary indices for less active hours.

With the upgrade, we decided to take full advantage of dynamic mapping as well. Before, we'd require strict, explicit mappings for _every single pattern of indices_. Our radical new way was entirely hands off, we'll map just a handful of known things, everything else gets treated as it comes according to some rules with some extra subfields. Convenient and it makes everyone happy!

Lastly, with 5.x came the concept of "rollover" indices. Rollover indices at the time were simple, you could rollover purely based on doc count and maximum age of the index, nothing more. Not exactly useful, but with some simple math you could get pretty close to the approximate number of docs per index however. So, with some proof of concept examples in the sandbox cluster, newly obtained kubernetes cluster access and some back and forth between Sam and I, I set out to create what we dubbed ["Squiggler"](https://github.com/Battleroid/squiggler-v1).

# Enter squiggler 1.0!

Squiggler 1.0 was a major shift from our old dated processes and was a stepping stone to where we are today. To quote my own readme:

> To use the rollover API within Elasticsearch a call needs to be made to each alias with the given max age & max doc count. Before Squiggler we would measure this by hand, make the alias, make the rollover call, add the index, index pattern, etc.
>
> Instead, Squiggler will handle all of these steps. It will by default look for non-suffix'd indexes (e.g. 'sample', 'fiddle', 'sample-thing') and automate the process of creating an alias and the approximate max doc count to reach the tipping point (default of 10 GiB).

Truly, we were living in the future! Flawed as much as it was, it changed much. We went from gatekeeping indices to opening the floodgates. Gone was the old process of walking developers through mapping, whitelisting and creating their pattern. Instead, developers would merge their PR and minutes later, _poof_ brand new link right to their index within Kibana appeared in Slack (and Hipchat for just a brief time).

It wasn't all great however, like I mentioned, the OG squiggler had its own flaws. Just as we were embracing the new world of non-vomit-inducing index management, we somewhat failed to anticipate just how much we actually would log without the gatekeeping factor. Not the worst problem to have!

Squiggler's own order of operations was simple, but had two steps that caused the bulk of our issues:

1. **Lock allocation while it reindexes data**
2. Starts reindex for new unmigrated indices, waits for completion
3. **Deletes old indices once the reindex tasks finish**
4. Creates aliases for the rollover indices
5. Unlocks allocation
6. Creates Kibana patterns and posts the links

Our major problems were with steps 1 & 3. 1 bit us now and then during high traffic times. With allocation locked, we'd have issues creating new patterns, lag would build up on incoming events as we'd be unable to progress until Squiggler completed its migrations. The third didn't bite us so much as it was an inherent flaw. Due to how the migration process worked there was definitive data loss. Not exactly a "good" feature, and unfortunately one that we simply dealt with for a time.

Since it wasn't all that smart enough at the time, this usually meant we'd be stuck with a "concrete" index --- a half migrated index that would require a restart of the entire process. To combat this we'd have to stop Squiggler and manually intervene generally. Fortunately, it didn't happen that often, but it was always awful to fix.

It wasn't until ES 6.x and 7.x that I took to rewriting Squiggler once more to fix its issues and implement new features.

# Squiggler Deuce

Once more, we pushed forward, consumed more of our internal Kubernetes clusters' hardware, more ES servers in colo and upgraded to ES 6.x. Amazing stuff!

As part of the upgrade we further split our clusters further according to the internal shard. From the original handful to a functional spaghetti mess of clusters, our original issues have now multiplied. Squiggler 1 worked well for the couple of rollover based clusters, but with so many in the mix, we needed something better, and a better iteration that could take advantage of all the new bells and whistles.

So enter Squiggler Deuce (2.0), the new and improved squiggler experience! This time around Squiggler was set up to be a bit more modular. Opting for ["actions"](https://github.com/Battleroid/squiggler-v2/blob/master/sample.yaml#L82-L138) that can be selectively toggled, supporting both local/remote Kibana instances and more flexible methods of excluding indices.

Coupled with a [custom fork](https://github.com/logstash-plugins/logstash-output-elasticsearch/compare/main...Battleroid:logstash-output-elasticsearch:ilm_substitution_10.8.6?expand=1) of the Elasticsearch output for Logstash, we achieve the same functionality that data streams would later provide us. For example, dynamic rollover aliases set up as the write index for their respective pattern. Surprisingly, the forked output didn't have any significant performance issues and still continues to serve us while we migrate off to data streams.

Initially we only had the few actions: the creation and update of rollover aliases, as well as Kibana patterns. During our transition to 7.x we added a few more, again, coinciding with some updates to the Logstash output changes. Eventually Squiggler's role shifted more from creating and updating aliases, to more of just checking if patterns exist within Kibana which is what led us to the current iteration of Squiggler.

Most of the functionality that was implemented in the second version was eventually toggled off as we upgraded, leaving just the recreation of patterns within Kibana on. This worked until recently when we hit an ugly milestone, **10,000 individual index patterns!** At least 8-9k of which were legitimate, but unfortunately due to a bug with Squiggler and a quirk of the Kibana API, it resulted in an explosion of patterns.

Squiggler at one point would attempt to create the same few patterns multiple times over, generally succeeding[^1]. Once the objects extended over 10k it basically became unusable. It had no idea how to handle the supposedly missing objects and would continue to try recreating them. We'd have to kill Squiggler jobs and I'd have to manually intervene, removing unused duplicates or miscellaneous patterns that obviously did not exist. _If you're at all curious, our normal number of patterns hovers currently around ~8.5k, a few more every day. Which means more problems later on, ha!_

Regrettably, this version of Squiggler just had too much shoehorned into it. We had to squeeze functionality that was never envisioned into it with the addition of data streams, so with that in mind, we came to the final version of Squiggler.

# Squiggler 3, keeping it simple

After some frustration and the third instance of Kibana imploding, I spent a day boiling down and rewriting Squiggler.

Unlike the second iteration, this time around Squiggler only had one role to fill. It creates patterns within Kibana that don't exist. It supports either ILM or data stream (method meaning how it locates the write aliases), similar exclusion methods and a teeny bit of customization for the prefixes or index templates. If you peek at the [sample config](https://github.com/Battleroid/squiggler-v3/blob/master/sample.yaml) you can see for yourself. It effectively recreates the recreate pattern action that the second version had, and nothing else.

There were some extra safeguards that needed to be added such as once we're over the 10k per page limit we no longer submit new patterns, it also creates patterns just up to that limit and warning if we'll go over. It's possible to up that limit within Kibana but it appears to break some functionality, so as far as adding to ability to paginate through the API is concerned it seemed like a pointless endeavor.

More importantly, it works! We use it currently for the large majority of our colocated clusters, eventually it will replace Squiggler everywhere as we migrate to data streams from basic rollover & ILM indices.

[^1]: I say "generally" because we did not use UUIDs prior, so all of these new patterns simply created new randomly generated UUIDs. Squiggler v3 instead uses the pattern name itself as the ID, preventing this.