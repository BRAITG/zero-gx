#!/bin/sh
# Install the Graphify build that generates graphify-out/graph.json: the pfBlockerNG fork's
# integration head, which adds GDScript and Godot scene support (Graphify-Labs/graphify#4484).
# The pre-commit hook and CI must run the same build, or CI reports the committed graph stale.
# The integration deploy bumps this pin.
set -eu
uv tool install --upgrade 'graphifyy[leiden,gdscript] @ git+https://github.com/pfBlockerNG/graphify@1a48d67367aae8d75116c161778266cc4ebcb80b' >&2
