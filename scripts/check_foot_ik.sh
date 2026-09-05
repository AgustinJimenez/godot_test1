#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
log_file=$(mktemp "${TMPDIR:-/tmp}/foot-ik-check.XXXXXX")
trap 'rm -f "$log_file"' EXIT

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_toe_riser_check.tscn \
	--quit-after 560 >"$log_file" 2>&1 || true
if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_TOE_RISER_CHECK PASS" "$log_file"; then
	cat "$log_file"
	exit 1
fi
rg "FOOT_IK_TOE_RISER_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_idle_support_owner_check.tscn \
	--quit-after 500 >"$log_file" 2>&1 || true
if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_IDLE_SUPPORT_OWNER_CHECK PASS" "$log_file"; then
	cat "$log_file"
	exit 1
fi
rg "FOOT_IK_IDLE_SUPPORT_OWNER_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_preview.tscn --quit-after 400 \
	-- --animation-comparison-check >"$log_file" 2>&1 || true
if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_ANIMATION_COMPARISON_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK animation comparison check did not pass."
	exit 1
fi
rg "FOOT_IK_ANIMATION_COMPARISON_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --quit-after 360 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_preview.tscn \
	-- --foot-ik-check >"$log_file" 2>&1 || true

if rg -q "FOOT_IK_(STRETCH|AIRBORNE|STAIR_(LOCOMOTION|SETTLE))_CHECK FAIL|SCRIPT ERROR" "$log_file"; then
	cat "$log_file"
	exit 1
fi

if ! rg -q "FOOT_IK_STRETCH_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK stretch check did not produce a result."
	exit 1
fi

if ! rg -q "FOOT_IK_AIRBORNE_CHECK PASS samples=[1-9]" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK airborne release check did not run."
	exit 1
fi

if ! rg -q "FOOT_IK_BODY_PENETRATION_CHECK PASS samples=[1-9]" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK rendered-body stair penetration check did not pass."
	exit 1
fi

if ! rg -q "FOOT_IK_POSE_CONTINUITY_CHECK PASS samples=[1-9]" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK idle pose-continuity check did not pass."
	exit 1
fi

if ! rg -q "FOOT_IK_STAIR_LOCOMOTION_CHECK PASS steps=[1-9]" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK stair locomotion continuity check did not pass."
	exit 1
fi

if ! rg -q "FOOT_IK_STAIR_SETTLE_CHECK PASS samples=[1-9]" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK post-stair settling check did not pass."
	exit 1
fi

rg "FOOT_IK_(STRETCH|AIRBORNE)_CHECK PASS|FOOT_IK_BODY_PENETRATION_CHECK PASS" \
	"$log_file"
rg "FOOT_IK_POSE_CONTINUITY_CHECK PASS" "$log_file"
rg "FOOT_IK_STAIR_LOCOMOTION_CHECK PASS" "$log_file"
rg "FOOT_IK_STAIR_SETTLE_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_edge_landing_sweep_check.tscn \
	--quit-after 10000 >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_EDGE_LANDING_SWEEP_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK randomized edge-landing sweep did not pass."
	exit 1
fi
rg "FOOT_IK_EDGE_LANDING_SWEEP_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_ledge_safety_check.tscn \
	--quit-after 3300 >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_LEDGE_SAFETY_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK ledge safety check did not pass."
	exit 1
fi
rg "FOOT_IK_LEDGE_SAFETY_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_landing_stability_check.tscn \
	--quit-after 240 >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_LANDING_STABILITY_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK landing stability check did not pass."
	exit 1
fi
rg "FOOT_IK_LANDING_STABILITY_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_split_stance_walk_check.tscn \
	--quit-after 320 >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_SPLIT_STANCE_WALK_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK split-stance walk support check did not pass."
	exit 1
fi
rg "FOOT_IK_SPLIT_STANCE_WALK_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	--quit-after 400 >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK split-height knee flexion check did not pass."
	exit 1
fi
rg "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_preview.tscn \
	--quit-after 400 -- --idle-ik-seam-check >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_IDLE_SEAM_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK idle loop left-leg seam check did not pass."
	exit 1
fi
rg "FOOT_IK_IDLE_SEAM_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	--quit-after 400 -- replay_weight_oscillation=true >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK over-height weight-oscillation check did not pass."
	exit 1
fi
rg "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	--quit-after 400 -- replay_grounded_commit_mismatch=true >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK mismatched grounded landing commitment check did not pass."
	exit 1
fi
rg "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	--quit-after 400 -- replay_stale_grounded_commit=true >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK stale grounded landing commitment check did not pass."
	exit 1
fi
rg "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	--quit-after 400 -- replay_shallow_split_pose=true >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK shallow split-height pose check did not pass."
	exit 1
fi
rg "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	--quit-after 400 -- replay_committed_edge_landing=true >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK committed edge-landing check did not pass."
	exit 1
fi
rg "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	--quit-after 400 -- replay_delayed_support_restore=true >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK delayed landing support restore check did not pass."
	exit 1
fi
rg "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	--quit-after 400 -- replay_delayed_lower_snap=true >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK delayed lower-support snap check did not pass."
	exit 1
fi
rg "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	--quit-after 400 -- replay_idle_loop=true >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK idle-loop knee continuity check did not pass."
	exit 1
fi
rg "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	--quit-after 400 -- replay_negative_knee=true >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK negative rendered-knee check did not pass."
	exit 1
fi
rg "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	--quit-after 400 -- replay_unreachable_acquisition=true >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK unreachable acquisition check did not pass."
	exit 1
fi
rg "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"

# The second live pose is reached by turning across the platform corner; a
# direct spawn does not recreate its retained split-height support ownership.
godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	--quit-after 400 -- start=8.649,0.575,4.231 turn_from=89.2 \
	yaw=-47.1210208763382 >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK turning corner knee flexion check did not pass."
	exit 1
fi
rg "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	--quit-after 400 -- start=8.602571,0.600571,3.860138 \
	yaw=91.1223801700297 replay_landing_clearance_jump=true \
	require_prelanding_move=true >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK landing contact-clearance check did not pass."
	exit 1
fi
rg "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	--quit-after 400 -- start=9.053116,0.6001,3.915929 \
	yaw=-88.3279926862266 replay_late_landing_input=true \
	require_prelanding_move=true >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK late-input predictive landing check did not pass."
	exit 1
fi
rg "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	--quit-after 400 -- start=9.636244,0.600522,3.98567 \
	yaw=-101.164602401024 require_lowest_support=true >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK partial upper-foot support check did not pass."
	exit 1
fi
rg "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	--quit-after 400 -- start=9.219313,0.6001,3.865484 \
	yaw=92.7266550022823 replay_edge_push=true >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK edge-push target reversal check did not pass."
	exit 1
fi
rg "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	--quit-after 400 -- start=8.549901,0.6001,3.960056 \
	yaw=-54.9599094584513 >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK forward-shin standing limit check did not pass."
	exit 1
fi
rg "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	--quit-after 400 -- start=9.053116,0.6001,3.915929 \
	yaw=-88.3279926862266 replay_prelanding_jump=true \
	require_prelanding_move=true >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK predictive landing safe-zone check did not pass."
	exit 1
fi
rg "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	--quit-after 400 -- start=8.758182,0.600149,4.085211 \
	yaw=73.7044620505809 time=1.86666666666666 >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK mirrored upper-leg deformation check did not pass."
	exit 1
fi
rg "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_knee_flex_check.tscn \
	--quit-after 400 -- start=8.769,0.551,4.278 turn_from=89.6 \
	yaw=-24.6610895549845 >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK shallow-corner knee flexion check did not pass."
	exit 1
fi
rg "FOOT_IK_KNEE_FLEX_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_edge_stance_check.tscn \
	--quit-after 6200 >"$log_file" 2>&1 || true

if ! rg -q "FOOT_IK_EDGE_STANCE_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK edge stance check did not pass."
	exit 1
fi
rg "FOOT_IK_EDGE_STANCE_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_walk_idle_stance_check.tscn \
	--quit-after 5500 >"$log_file" 2>&1 || true

if ! rg -q "FOOT_IK_WALK_IDLE_STANCE_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK walk-to-idle stance check did not pass."
	exit 1
fi
rg "FOOT_IK_WALK_IDLE_STANCE_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_idle_plant_stability_check.tscn \
	--quit-after 2750 >"$log_file" 2>&1 || true

if rg -q "SCRIPT ERROR" "$log_file" \
		|| ! rg -q "FOOT_IK_IDLE_PLANT_STABILITY_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK stationary planted-foot stability check did not pass."
	exit 1
fi
rg "FOOT_IK_IDLE_PLANT_STABILITY_CHECK PASS" "$log_file"

godot --headless --fixed-fps 60 --path "$project_dir" \
	res://tests/manual/foot_ik/foot_ik_ramp_locomotion_check.tscn \
	--quit-after 13000 >"$log_file" 2>&1 || true

if ! rg -q "FOOT_IK_RAMP_LOCOMOTION_CHECK PASS" "$log_file"; then
	cat "$log_file"
	printf '%s\n' "Foot IK ramp locomotion check did not pass."
	exit 1
fi
rg "FOOT_IK_RAMP_LOCOMOTION_(CASES|CHECK)" "$log_file"

"$project_dir/scripts/check_foot_ik_stair_repeat.sh"
"$project_dir/scripts/check_foot_ik_locomotion.sh"
