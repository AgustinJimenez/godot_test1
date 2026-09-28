#!/usr/bin/env bash
set -euo pipefail

# Compact analyzer for the Foot IK v2 lab trace (GDScript, no Python). See analyze_v2_trace.gd.
cd "$(dirname "$0")/.."
godot --headless --path . --script res://scripts/analyze_v2_trace.gd -- "$@" 2>&1 \
	| grep -v -E "(WARNING|GDScript backtrace|at: built_in_strtod|\[[0-9]+\])"
