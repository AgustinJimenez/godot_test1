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
	echo "godot 4.6.2 is required and must be available on PATH." >&2
	exit 1
fi

echo "==> Linting GDScript"
"${GDLINT}" .

echo "==> Importing Godot resources"
godot --headless --path . --import

echo "==> Parsing GDScript"
while IFS= read -r script_path; do
	if ! godot --headless --path . --check-only --script "${script_path}" \
			>"${PARSE_LOG}" 2>&1; then
		echo "GDScript parse failed: ${script_path}" >&2
		cat "${PARSE_LOG}" >&2
		exit 1
	fi
done < <(find . -type f -name '*.gd' \
	-not -path './.godot/*' \
	-not -path './tools/character_editor_mcp/.venv/*' \
	| LC_ALL=C sort)

echo "Project checks passed."
