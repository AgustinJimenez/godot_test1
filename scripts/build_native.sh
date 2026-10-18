#!/usr/bin/env bash
# Builds the native planet crust library (native/planet_crust) for this machine: Windows (Git Bash,
# MinGW), macOS (universal) or Linux. It gets what it needs by itself the first time (godot-cpp and
# scons, kept in a cache folder outside the project) and does nothing when the library is already
# built from the current sources, so it is safe to run as often as you like (the git hooks do).
#
#   scripts/build_native.sh             build if the sources changed (debug library, what the editor loads)
#   scripts/build_native.sh --force     build again anyway
#   scripts/build_native.sh --release   the release library too (an exported game)
#   scripts/build_native.sh --double    the double precision library (needs GODOT_CPP_DOUBLE, the
#                                       godot-cpp master clone, and GODOT_API_DOUBLE, the engine's
#                                       own `--dump-extension-api` file; see native/planet_crust/README.md)
#
# Environment: GODOT_NATIVE_CACHE (default ~/.cache/godot-native), GODOT_CPP (a godot-cpp clone to
# use instead of the cached one), SCONS (the scons program to use).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ext="${root}/native/planet_crust"
cache="${GODOT_NATIVE_CACHE:-${HOME}/.cache/godot-native}"
force=0
release=0
double=0
for arg in "$@"; do
	case "${arg}" in
		--force) force=1 ;;
		--release) release=1 ;;
		--double) double=1 ;;
		*) echo "unknown argument ${arg}" >&2; exit 2 ;;
	esac
done

case "$(uname -s)" in
	Darwin) platform="macos"; extra=("arch=universal") ;;
	MINGW* | MSYS* | CYGWIN*)
		platform="windows"; extra=("arch=x86_64" "use_mingw=yes")
		for dir in /c/ProgramData/mingw64/mingw64/bin /mingw64/bin /c/msys64/mingw64/bin; do
			[[ -d "${dir}" ]] && export PATH="${dir}:${PATH}"
		done ;;
	Linux) platform="linux"; extra=("arch=x86_64") ;;
	*) echo "this platform is not supported" >&2; exit 1 ;;
esac

# godot-cpp 4.5 works with every 4.5+ engine on single precision; the double build needs master
godot_cpp="${GODOT_CPP:-${cache}/godot-cpp}"
if [[ ! -d "${godot_cpp}" ]]; then
	echo "getting godot-cpp into ${godot_cpp}"
	git clone --depth 1 --branch godot-4.5-stable https://github.com/godotengine/godot-cpp "${godot_cpp}"
fi

# scons, in a virtual environment of its own
scons="${SCONS:-}"
if [[ -z "${scons}" ]]; then
	venv="${cache}/venv"
	if [[ ! -d "${venv}" ]]; then
		echo "making the scons environment in ${venv}"
		python3 -m venv "${venv}" 2>/dev/null || python -m venv "${venv}"
		if [[ -x "${venv}/bin/pip" ]]; then "${venv}/bin/pip" install scons; else "${venv}/Scripts/pip" install scons; fi
	fi
	if [[ -x "${venv}/bin/scons" ]]; then scons="${venv}/bin/scons"; else scons="${venv}/Scripts/scons.exe"; fi
fi

hash_of() {
	if command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -c1-16; else sha256sum | cut -c1-16; fi
}
# what the library is made from: the sources, the build file and the godot-cpp version
sources="$(cat "${ext}"/src/*.cpp "${ext}"/src/*.h "${ext}"/SConstruct | hash_of)"
cpp_version="$(git -C "${godot_cpp}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
stamp="${sources}-${cpp_version}-${platform}"

build() { # target precision
	local target="$1" precision="$2" mark="${ext}/bin/.built-${1}-${2}"
	if [[ ${force} -eq 0 && -f "${mark}" && "$(cat "${mark}")" == "${stamp}" ]]; then
		echo "planet crust (${target}, ${precision}): up to date"
		return
	fi
	echo "building the planet crust (${target}, ${precision})..."
	local more=()
	if [[ "${precision}" == "double" ]]; then
		: "${GODOT_CPP_DOUBLE:?set GODOT_CPP_DOUBLE to a godot-cpp master clone for the double build}"
		: "${GODOT_API_DOUBLE:?set GODOT_API_DOUBLE to the extension_api.json of the engine for the double build}"
		more=("custom_api_file=${GODOT_API_DOUBLE}")
		export GODOT_CPP="${GODOT_CPP_DOUBLE}"
	else
		export GODOT_CPP="${godot_cpp}"
	fi
	(cd "${ext}" && "${scons}" "platform=${platform}" "${extra[@]}" "target=${target}" \
		"precision=${precision}" ${more[@]+"${more[@]}"} -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)")
	mkdir -p "${ext}/bin"
	echo "${stamp}" > "${mark}"
}

build template_debug single
[[ ${release} -eq 1 ]] && build template_release single
[[ ${double} -eq 1 ]] && build template_debug double
echo "the native planet crust is ready"
