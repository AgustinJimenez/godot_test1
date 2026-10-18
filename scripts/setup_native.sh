#!/usr/bin/env bash
# One time on a machine: makes a pull or a checkout build the native planet crust library by itself
# (it adds a line to this clone's post-merge and post-checkout git hooks, keeping what they already do,
# for example Git LFS's), and builds the library now. Needs git, python3 and a C++ compiler (Xcode's
# command line tools on a Mac, MinGW on Windows). Safe to run again.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hooks="$(git -C "${root}" rev-parse --git-path hooks)"
[[ "${hooks}" == /* || "${hooks}" == [A-Za-z]:* ]] || hooks="${root}/${hooks}"
mkdir -p "${hooks}"
chmod +x "${root}"/.githooks/* "${root}/scripts/build_native.sh"

marker="# planet crust native library"
for name in post-merge post-checkout; do
	file="${hooks}/${name}"
	if [[ -f "${file}" ]] && grep -q "${marker}" "${file}"; then
		continue
	fi
	line='"$(git rev-parse --show-toplevel)/.githooks/'"${name}"'" "$@" || true'
	{
		echo "#!/bin/sh"
		echo "${marker}"
		echo "${line}"
		if [[ -f "${file}" ]]; then tail -n +2 "${file}"; fi
	} > "${file}.new"
	mv "${file}.new" "${file}"
	chmod +x "${file}"
done

"${root}/scripts/build_native.sh"
echo "done: from now on a pull or a checkout keeps the native library up to date"
