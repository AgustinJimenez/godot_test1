class_name PlayerBalanceCounterLeanModifier
extends SkeletonModifier3D
## Torso counter-lean toward the loaded leg (017/018 follow-up): a split stair stance today
## shifts the pelvis but never counter-tilts the spine, reading as "gravity center not
## calculated." Modeled on PrototypeSpineTwistModifier's shape (weighted per-bone offsets from
## a shared snapshot, applied in skeleton space) but for lean instead of yaw twist, and on real
## contrapposto: pelvis toward the loaded hip, spine/shoulders counter-tilt the other way, neck
## gets an explicit opposite correction to keep the head roughly level.
##
## Runs after PlayerFootIKModifier in child order so it reads this same tick's final leg poses,
## not stale ones (018 finding E's same reasoning). Computes its own load-weighted foot midpoint
## from each leg's already-computed ground_weight/target instead of reusing Foot IK's own pelvis-
## shift value - that value is gated behind is_flat_idle/is_edge_asym and stays zero for an
## ordinary split stair stance (both feet individually flat, just at different heights), which
## is exactly the case this exists for. Disabled by default - a new, tunable, live-iterated
## visual, not a correctness fix; turn it on via the Foot IK feature panel to dial in
## lean_degrees_per_meter/max_lean_degrees before it becomes a real default.

const SPINE_LEAN_WEIGHTS: Dictionary = {
	&"Spine": 0.3,
	&"Spine1": 0.65,
	&"Spine2": 1.0,
}
const NECK_LEVEL_WEIGHTS: Dictionary = {
	&"Neck": -0.5,
	&"Head": -0.85,
}

var player_body: PlayerBody
@export var enabled := false
# Signed range, not just positive - the actual lean direction depends on this project's
# Forward/right bone-axis conventions and needs live confirmation; a negative value flips it
# without a code change if the first guess below leans the wrong way.
@export_range(-60.0, 60.0, 1.0) var lean_degrees_per_meter := 20.0
@export_range(0.0, 30.0, 1.0) var max_lean_degrees := 12.0


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or player_body == null or not enabled:
		return
	var ik := player_body._foot_ik_modifier
	if ik == null:
		return
	var lateral := _load_weighted_lateral_offset(ik, skel)
	var lean_angle := clampf(deg_to_rad(lateral * lean_degrees_per_meter),
			-deg_to_rad(max_lean_degrees), deg_to_rad(max_lean_degrees))
	if is_zero_approx(lean_angle):
		return
	var forward := -player_body.global_transform.basis.z.normalized()
	# Snapshot every target bone's pose first - weights are absolute offsets from one shared
	# pose, so a child must not stack its correction on an already-corrected parent.
	var targets: Array = []
	for role: StringName in SPINE_LEAN_WEIGHTS:
		var idx := skel.find_bone(player_body.resolve_bone_name(role))
		if idx >= 0:
			targets.append([idx, skel.get_bone_global_pose(idx), SPINE_LEAN_WEIGHTS[role]])
	for role: StringName in NECK_LEVEL_WEIGHTS:
		var idx := skel.find_bone(player_body.resolve_bone_name(role))
		if idx >= 0:
			targets.append([idx, skel.get_bone_global_pose(idx), NECK_LEVEL_WEIGHTS[role]])
	for target: Array in targets:
		var pose: Transform3D = target[1]
		pose.basis = Basis(forward, lean_angle * float(target[2])) * pose.basis
		skel.set_bone_global_pose(target[0], pose)


## Weighted foot midpoint minus hip midpoint, projected onto the character's right axis - same
## formula 017 already uses for its own pelvis-shift, computed independently here so it isn't
## gated by Foot IK's is_flat_idle/is_edge_asym (both true for an ordinary split stair stance).
func _load_weighted_lateral_offset(ik: PlayerFootIKModifier, skel: Skeleton3D) -> float:
	var indices: Dictionary = ik._bone_indices
	var left_indices: Dictionary = indices.get(&"left", {})
	var right_indices: Dictionary = indices.get(&"right", {})
	if left_indices.is_empty() or right_indices.is_empty():
		return 0.0
	var to_world := skel.global_transform
	var l_hip := to_world * skel.get_bone_global_pose(int(left_indices["hip"])).origin
	var r_hip := to_world * skel.get_bone_global_pose(int(right_indices["hip"])).origin
	var l_gw: float = float(ik._smoothed_ground_weight.get(&"left", 0.0))
	var r_gw: float = float(ik._smoothed_ground_weight.get(&"right", 0.0))
	var total_w := l_gw + r_gw
	if total_w <= 0.001:
		return 0.0
	var l_tgt: Vector3 = ik._smoothed_target.get(&"left", l_hip)
	var r_tgt: Vector3 = ik._smoothed_target.get(&"right", r_hip)
	var feet_mid := (l_tgt * l_gw + r_tgt * r_gw) / total_w
	var hip_mid := (l_hip + r_hip) * 0.5
	var right := player_body.global_transform.basis.x.normalized()
	return (feet_mid - hip_mid).dot(right)
