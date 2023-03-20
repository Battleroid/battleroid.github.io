#!/bin/bash
echo "website will be available on http://localhost:5000"
tmux new-session -d -s "jekyll" 'bundle exec jekyll serve -b "" -P 5000 -H 0.0.0.0 -w -l -D --future'
