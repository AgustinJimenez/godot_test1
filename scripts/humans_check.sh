#!/usr/bin/env bash
# The parametric-humans checks (task 102): the native head hair on both base bodies (HumanHair: shape, blend shapes follow the head, deterministic, thread-safe, curls),
# the rig (HumanRig: the skeleton follows the sliders, the skin binds follow it, clothes and head items are skinned, an adopted hair follows) and the hair's spring (HairSway).
# Needs the native library built for the engine's precision (the double engine needs the --double one). Godot is $GODOT, else the STOCK 4.7.2 console exe (the custom double engine cannot load addons/tressfx: exit 127 with no message); the single-precision native library must be built.
# `--render` also draws the rig lab once in a window (second monitor, no focus) and fails on a shader or script error: nothing else compiles the shaders.
# Prints HUMAN_HAIR_CHECK PASS, HUMAN_RIG_CHECK PASS and HUMAN_SWAY_CHECK PASS and exits 0, or the failed lines and exits 1.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/e/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe}"
render=0
[[ "${1:-}" == "--render" ]] && render=1
status=0

out="$(timeout 300 "${GODOT}" --headless --path . -s res://tests/manual/humans/human_hair_check.gd 2>&1)"
echo "${out}" | grep -a "HUMAN_HAIR_CHECK\|build times|beard 0"
echo "${out}" | grep -aq "HUMAN_HAIR_CHECK PASS" || status=1

out="$(timeout 300 "${GODOT}" --headless --path . -s res://tests/manual/humans/human_rig_check.gd 2>&1)"
echo "${out}" | grep -a "HUMAN_RIG_CHECK"
echo "${out}" | grep -aq "HUMAN_RIG_CHECK PASS" || status=1

out="$(timeout 120 "${GODOT}" --headless --path . -s res://tests/manual/humans/hair_style_store_check.gd 2>&1)"
echo "${out}" | grep -a "HAIR_STYLE_STORE_CHECK"
echo "${out}" | grep -aq "HAIR_STYLE_STORE_CHECK PASS" || status=1

out="$(timeout 120 "${GODOT}" --headless --path . -s res://tests/manual/humans/human_body_hair_check.gd 2>&1)"
echo "${out}" | grep -a "HUMAN_BODY_HAIR_CHECK"
echo "${out}" | grep -aq "HUMAN_BODY_HAIR_CHECK PASS" || status=1

out="$(timeout 120 "${GODOT}" --headless --path . -s res://tests/manual/humans/character_store_check.gd 2>&1)"
echo "${out}" | grep -a "CHARACTER_STORE_CHECK"
echo "${out}" | grep -aq "CHARACTER_STORE_CHECK PASS" || status=1

out="$(timeout 120 "${GODOT}" --headless --fixed-fps 60 --path . -s res://tests/manual/humans/human_sway_check.gd 2>&1)"
echo "${out}" | grep -a "HUMAN_SWAY_CHECK"
echo "${out}" | grep -aq "HUMAN_SWAY_CHECK PASS" || status=1

if [[ ${render} -eq 1 ]]; then
	printf '[display]\nwindow/size/no_focus=true\n' > override.cfg
	out="$(timeout 180 "${GODOT}" --path . --rendering-driver vulkan --screen 1 --resolution 900x900 res://tests/manual/humans/human_rig_lab.tscn -- --capture=/tmp/human_rig_check.png --pose=walk 2>&1)"
	# the body lab too: the skin shader (procedural face zones) is only compiled there
	out+="$(timeout 180 "${GODOT}" --path . --rendering-driver vulkan --screen 1 --resolution 900x900 res://tests/manual/humans/human_body_lab.tscn -- --capture=/tmp/human_body_check.png --close --face --nopanel --skin-set=freckles:0.5,age:0.6 2>&1)"
	# a gender switch while the lab runs (male to female): it must neither crash nor hang (an old bug freed the scene's root when the brows were swapped), and the new hair must arrive
	switch_out="$(timeout 120 "${GODOT}" --path . --rendering-driver vulkan --screen 1 --resolution 900x900 --quit-after 600 res://tests/manual/humans/human_body_lab.tscn -- --switch-gender=Female 2>&1)"
	switch_code=$?
	rm -f override.cfg
	if [[ ${switch_code} -ne 0 ]] || ! echo "${switch_out}" | grep -aq "GENDER_SWITCH hair ready"; then
		echo "HUMAN_GENDER_SWITCH_CHECK FAIL (exit ${switch_code})"
		echo "${switch_out}" | grep -a "GENDER_SWITCH\|SCRIPT ERROR" | head -5
		status=1
	else
		echo "HUMAN_GENDER_SWITCH_CHECK PASS"
	fi
	out+="${switch_out}"
	if echo "${out}" | grep -aq "SHADER ERROR\|SCRIPT ERROR\|setup failed"; then
		echo "HUMAN_RENDER_CHECK FAIL"
		echo "${out}" | grep -a "SHADER ERROR\|SCRIPT ERROR\|setup failed" | head -5
		status=1
	else
		echo "HUMAN_RENDER_CHECK PASS"
	fi
fi
exit "${status}"
