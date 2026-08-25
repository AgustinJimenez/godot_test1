#!/usr/bin/env bash
set -euo pipefail

# Compact trace analyzer wrapper for token-efficient logging via Godot GDScript
cd "$(dirname "$0")/.."
godot --headless --path . --script res://scripts/analyze_trace.gd -- "$@" 2>&1 | grep -v -E "(WARNING|GDScript backtrace|at: built_in_strtod|\[[0-9]+\])"
