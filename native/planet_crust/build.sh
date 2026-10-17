#!/usr/bin/env bash
# Builds the planet crust library for the standard (single) and the double precision engine.
# godot-cpp is built once per configuration (minutes); the library itself takes seconds.
set -euo pipefail
export PATH="/c/ProgramData/mingw64/mingw64/bin:$PATH"
SCONS="${SCONS:-/e/Godot/cpp/venv/Scripts/scons.exe}"
cd "$(dirname "${BASH_SOURCE[0]}")"
for precision in single double; do
	for target in template_debug template_release; do
		"${SCONS}" platform=windows use_mingw=yes arch=x86_64 target="${target}" precision="${precision}" -j6
	done
done
