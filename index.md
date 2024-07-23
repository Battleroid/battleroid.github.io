---
title: Posts
---
<ul class="posts">
    {% for post in site.posts -%}
        <li>
            <time pubdate="pubdate" datetime="{{ post.date | date: "%Y-%m-%d" }}">{{ post.date | date: "%Y-%m-%d" }}</time>
            <a href="{{ post.url | prepend: site.baseurl }}">{{ post.title }}</a>
            {% if post.fragment %}<sup class="fragment">†</sup>{% endif %}
        </li>
    {% endfor -%}
</ul>
<span class="explanation">† = a short, "fragment" post</span>
