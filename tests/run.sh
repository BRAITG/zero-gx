#!/usr/bin/env bash
# Headless test run at a fixed 60 FPS. Exit 0 only when every test passes and no script error was logged.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
log=$(mktemp)
"$GODOT" --headless --path . --fixed-fps 60 -s res://tests/run_tests.gd 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
# Expected noise: test_corrupt_file_is_no_progress makes Godot log a parse error for the test
# progress file on purpose, and Godot's headless audio keeps Ogg playbacks alive past quit.
if grep -E "SCRIPT ERROR|^ERROR:|Parse Error" "$log" | grep -v "test_progress.cfg" | grep -qv "resources still in use at exit"; then
  echo "run.sh: script errors were logged (see above)" >&2
  status=1
fi
rm -f "$log"
exit "$status"
