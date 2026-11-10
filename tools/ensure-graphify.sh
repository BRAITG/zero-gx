#!/bin/sh
# Install the Graphify build that generates graphify-out/graph.json: the pfBlockerNG fork's
# integration head, which adds GDScript and Godot scene support (Graphify-Labs/graphify#4484).
# The pre-commit hook and CI must run the same build, or CI reports the committed graph stale.
# The integration deploy bumps this pin.
set -eu
uv tool install --upgrade 'graphifyy[leiden,gdscript] @ git+https://github.com/pfBlockerNG/graphify@e43f5678716cf68a7888412c99b081697932a309' >&2
