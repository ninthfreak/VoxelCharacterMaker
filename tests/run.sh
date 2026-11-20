#!/usr/bin/env bash
# Acceptance checks for SPEC.md section 12.
#
# Usage:  tests/run.sh [path-to-godot]
# Set GODOT, or pass the binary as the first argument, if `godot` is not on PATH.
set -euo pipefail

cd "$(dirname "$0")/.."

GODOT_BIN="${1:-${GODOT:-godot}}"

if ! command -v "$GODOT_BIN" >/dev/null 2>&1 && [ ! -x "$GODOT_BIN" ]; then
  echo "Godot not found: $GODOT_BIN" >&2
  echo "Install Godot 4.7+, or: tests/run.sh /path/to/godot" >&2
  exit 127
fi

# Expected asset numbers are measured from the assets, not transcribed.
if command -v python3 >/dev/null 2>&1; then
  echo "== measuring assets =="
  python3 tools/verify_assets.py
fi

# Global class names (class_name) live in .godot/global_script_class_cache.cfg,
# which only an import pass writes. A fresh clone has no .godot at all, and
# adding a script with a new class_name leaves the cache stale.
#
# Both cases are worth avoiding automatically, because neither fails in a way
# that points at the cause: a missing cache reports "Identifier not declared"
# for every class in the suite, which reads as broken code, and a stale one
# makes Godot HANG on --script rather than report anything.
CACHE=.godot/global_script_class_cache.cfg
NEEDS_IMPORT=0
if [ ! -f "$CACHE" ]; then
  NEEDS_IMPORT=1
elif [ -n "$(find . -name '*.gd' -newer "$CACHE" -print -quit 2>/dev/null)" ]; then
  NEEDS_IMPORT=1
fi
if [ "$NEEDS_IMPORT" = "1" ]; then
  echo "== importing the project (script cache is missing or stale) =="
  "$GODOT_BIN" --headless --path . --import >/dev/null 2>&1 || true
  # Godot only rewrites the cache when the class list changes. After an edit
  # that adds no class, the file keeps its old time, stays "older than a
  # script", and every later run would import again. Mark it current.
  [ -f "$CACHE" ] && touch "$CACHE"
fi

# The low-poly bodies, heads and clothing (lowpoly/) are rebuilt and checked too, where numpy is installed to build
# them. Without it this step is skipped, not failed. It runs after the import above because its clothing checks
# ask Godot for the game's starter wardrobe and test poses, which needs the script cache.
if command -v python3 >/dev/null 2>&1 && python3 -c "import numpy" >/dev/null 2>&1; then
  echo "== checking the low-poly bodies, heads and clothing =="
  GODOT="$GODOT_BIN" python3 lowpoly/check.py
else
  echo "== low-poly: skipped (python3 with numpy not found) =="
fi

echo
echo "== acceptance checks =="
# A script error does not fail a check: it stops the suite it happens in, and
# every check after it silently does not run -- the tally can still say "0
# failed". So a script error anywhere in the output fails the run.
LOG="$(mktemp)"
set +e
"$GODOT_BIN" --headless --path . --script res://tests/run_tests.gd 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}
set -e
if grep -q "SCRIPT ERROR" "$LOG"; then
  echo >&2
  echo "FAILED: a script error stopped part of the suite; the checks after it did not run." >&2
  STATUS=1
fi
rm -f "$LOG"
exit "$STATUS"
