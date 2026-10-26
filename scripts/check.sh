#!/usr/bin/env bash
set -euo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PARSE_LOG="$(mktemp)"
trap 'rm -f "${PARSE_LOG}"' EXIT

cd "${PROJECT_ROOT}"

if [[ -x "${PROJECT_ROOT}/.venv/bin/gdlint" ]]; then
	readonly GDLINT="${PROJECT_ROOT}/.venv/bin/gdlint"
elif command -v gdlint >/dev/null 2>&1; then
	readonly GDLINT="$(command -v gdlint)"
else
	echo "gdlint is required. Install development tools with:" >&2
	echo "  python3 -m venv .venv" >&2
	echo "  .venv/bin/python -m pip install -r requirements-dev.txt" >&2
	exit 1
fi

if ! command -v godot >/dev/null 2>&1; then
	echo "godot 4.7.2 is required and must be available on PATH." >&2
	exit 1
fi

echo "==> Linting GDScript"
"${GDLINT}" .

echo "==> Parsing Python"
# One run as a scene, so the autoloads (PlayerProfile, GraphicsSettings...) exist: `--check-only --script`
# per file cannot resolve them and failed on every script that names one.
if ! godot --headless --path . res://scripts/parse_all.tscn >"${PARSE_LOG}" 2>&1; then
	echo "GDScript parse failed:" >&2
	grep -a "PARSEFAIL\|SCRIPT ERROR" "${PARSE_LOG}" >&2
	exit 1
fi

echo "Project checks passed."
