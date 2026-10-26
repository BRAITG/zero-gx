#!/bin/sh
# One-time setup after cloning: install Graphify, enable the tracked hooks in .githooks/ and
# register the merge driver that unions parallel changes to graphify-out/graph.json.
set -eu
root=$(git rev-parse --show-toplevel)
sh "$root/tools/ensure-graphify.sh"
git -C "$root" config core.hooksPath .githooks
# Registered directly: `graphify hook install` would also write post-commit hooks into .githooks/.
git -C "$root" config merge.graphify.name 'graphify graph.json union merge'
git -C "$root" config merge.graphify.driver "\"$(uv tool dir)/graphifyy/bin/python\" -m graphify merge-driver %O %A %B"
