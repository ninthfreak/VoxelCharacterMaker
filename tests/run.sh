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
# which only an import pass writes. Without it every class in the suite fails to
# resolve with "Identifier not declared", which looks like broken code rather
# than a missing cache. A fresh clone has no .godot at all.
if [ ! -f .godot/global_script_class_cache.cfg ]; then
  echo "== first run: importing the project =="
  "$GODOT_BIN" --headless --path . --import >/dev/null 2>&1 || true
fi

echo
echo "== acceptance checks =="
"$GODOT_BIN" --headless --path . --script res://tests/run_tests.gd
