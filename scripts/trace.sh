#!/usr/bin/env bash
set -euo pipefail

# Compact trace analyzer wrapper for token-efficient logging
# Usage:
#   scripts/trace.sh --summary
#   scripts/trace.sh --feet --step 5 --last-n 50
#   scripts/trace.sh --changes-only --feet
#   scripts/trace.sh --anomalies

cd "$(dirname "$0")/.."
godot --headless --path . --script res://scripts/analyze_trace.gd -- "$@" 2>&1 | grep -v -E "(WARNING|GDScript backtrace|at: built_in_strtod|\[[0-9]+\])"
