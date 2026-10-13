#!/bin/sh
# Worst poses of the last `-- --spawn=ramp-edge-turn` lab run (turning in place at the ramp side),
# from the check trace. Prints one line: hip drop, foot yaw against the body, hip swing, knee bend
# beyond the idle animation's, and how far apart the feet are.
trace="${HOME}/Library/Application Support/Godot/app_userdata/SurvivalHorrorFps/foot_ik_v2_check.jsonl"
jq -c '[.body.pelvis_drop, (.feet.left.pose.final.foot_yaw_vs_facing_deg | fabs),
	(.feet.right.pose.final.foot_yaw_vs_facing_deg | fabs),
	(.feet.left.pose.final.hip_abduction_deg | fabs), (.feet.right.pose.final.hip_abduction_deg | fabs),
	(.feet.left.pose.final.knee_flexion_deg - .feet.left.pose.animated.knee_flexion_deg),
	(.feet.right.pose.final.knee_flexion_deg - .feet.right.pose.animated.knee_flexion_deg),
	(((.feet.left.foot_pos[0] - .feet.right.foot_pos[0]) | . * .)
	+ ((.feet.left.foot_pos[2] - .feet.right.foot_pos[2]) | . * .) | sqrt),
	([.feet.left.state, .feet.right.state] | map(select(startswith("released"))) | length)]' "$trace" | jq -s -r '
	.[200:] | "EDGE_TURN drop_max=\(map(.[0]) | max * 100 | round / 100) foot_yaw_max=\(map(.[1], .[2]) | max | round) hip_swing_max=\(map(.[3], .[4]) | max | round) knee_excess_max=\(map(.[5], .[6]) | max | round) feet_apart=\(map(.[7]) | min * 100 | round / 100)..\(map(.[7]) | max * 100 | round / 100) released_foot_frames=\(map(.[8]) | add)"'
