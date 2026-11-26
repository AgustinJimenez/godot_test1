#!/usr/bin/env bash
# Task 103: real GPU checks; run sequentially with no other game running.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/e/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe}"
log_dir="$(mktemp -d)"
had_override=0
if [[ -f override.cfg ]]; then
	had_override=1
	cp override.cfg "${log_dir}/override.cfg"
fi
cleanup() {
	if [[ ${had_override} -eq 1 ]]; then
		cp "${log_dir}/override.cfg" override.cfg
	else
		rm -f override.cfg
	fi
	if [[ ${status:-1} -eq 0 ]]; then
		rm -f "${log_dir}/normals.log" "${log_dir}/lifecycle.log" "${log_dir}/override.cfg" \
			"${log_dir}/sleeves_male.log" "${log_dir}/sleeves_female.log" \
			"${log_dir}/motion_male.log" "${log_dir}/motion_female.log" \
			"${log_dir}/motion_male_150.log" "${log_dir}/motion_female_150.log"
		rmdir "${log_dir}"
	fi
}
trap cleanup EXIT
printf '[display]\nwindow/size/no_focus=true\n' > override.cfg
status=0
for check in normals lifecycle sleeves_male sleeves_female \
		motion_male motion_female motion_male_150 motion_female_150; do
	args=(-s res://tests/manual/humans/cloth_normals_check.gd)
	marker="CLOTH_NORMALS_CHECK PASS"
	if [[ "${check}" == lifecycle ]]; then
		args=(res://tests/manual/humans/human_cloth_check.tscn)
		marker="HUMAN_CLOTH_CHECK PASS"
	fi
	if [[ "${check}" == motion_* ]]; then
		gender=Male
		[[ "${check}" == motion_female* ]] && gender=Female
		frame=90
		[[ "${check}" == *_150 ]] && frame=150
		args=(--fixed-fps 60 -s res://tests/manual/humans/cloth_sleeve_motion_check.gd --
			--pose=walk --sweep=40 "--gender=${gender}" "--sample-frame=${frame}")
		marker="CLOTH_MOTION_CHECK PASS"
	fi
	if [[ "${check}" == sleeves_* ]]; then
		gender=Male
		[[ "${check}" == sleeves_female ]] && gender=Female
		args=(--fixed-fps 60 res://tests/manual/humans/cloth_sleeve_probe.tscn -- "--gender=${gender}")
		marker="CLOTH_SLEEVE_CHECK PASS"
	fi
	log="${log_dir}/${check}.log"
	code=0
	timeout 180 "${GODOT}" --path . --rendering-driver vulkan --screen 1 --windowed \
		--resolution 900x900 "${args[@]}" >"${log}" 2>&1 || code=$?
	if [[ ${code} -ne 0 ]] || ! grep -aq "${marker}" "${log}" \
		|| grep -aq 'ERROR:\|CHECK FAIL' "${log}"; then
		echo "CLOTH_CHECK FAIL ${check} (exit ${code}, log ${log})"
		# Failures stay raw; keep large traces out of the terminal.
		tail -60 "${log}"
		status=1
	else
		grep -a "${marker}" "${log}"
	fi
done
exit "${status}"
