class_name FootIKV2Modifier
extends SkeletonModifier3D
## v2 foot IK - flat ground first. For each leg: sample the ground under the animated foot, then
## solve the hip -> knee -> ankle chain analytically so the ankle sits on it.
##
## Deliberately small. v1 (actors/player/foot_ik/) grew to 20 modules and ~6.8k lines because every
## new symptom got its own layer; v2 adds one behaviour at a time, each with its own check, and the
## acceptance scene lives beside it. No stairs, no swing prediction, no validation/retry layers yet.

## Role names are the character's humanoid roles, resolved through PlayerBody (same as v1) so this
## works on any catalog character.
const LEGS := {
	&"left": {"hip": &"LeftUpLeg", "knee": &"LeftLeg", "foot": &"LeftFoot",
		"toe": &"LeftToeBase"},
	&"right": {"hip": &"RightUpLeg", "knee": &"RightLeg", "foot": &"RightFoot",
		"toe": &"RightToeBase"},
}

@export var enabled := true
## Physics layer the ground is on (1 = world).
@export_flags_3d_physics var ground_mask := 1
@export var ray_up := 0.5
@export var ray_down := 1.2
## How far the ankle sits above the sampled ground when the foot is planted. Negative means
## "derive it from the rig's own rest pose", which is the only value that is right for every
## character (this rig's ankle rest is 0.111 m above the floor).
@export var ankle_height := -1.0
## 0 = keep the authored pose, 1 = fully plant on the sampled ground.
@export_range(0.0, 1.0) var weight := 1.0
## A foot lifted more than this above the sampled ground is treated as mid-swing and left to the
## animation. A foot at or below that height is corrected - including onto a surface above it
## (stepping up a ramp), which the animation alone would clip straight through.
@export var max_lift := 0.25

var player_body: PlayerBody
## side -> the target this leg was last corrected toward, and why it was skipped. Exposed so the
## trace logs the REAL decision instead of re-deriving it (a restated condition is where that kind
## of bug hides - see v1's notes).
var debug_target: Dictionary = {}
var debug_skip_reason: Dictionary = {}
var debug_ground_normal: Dictionary = {}
## side -> the animated ankle, the sampled ground, and the reach check, so a trace can tell a
## skipped swing foot from a target the leg simply could not reach.
var debug_animated_ankle: Dictionary = {}
var debug_ground: Dictionary = {}
var debug_solve: Dictionary = {}
## side -> "released" (left to the animation), "at_target" (reached its sampled surface) or
## "stretched" (aimed at it but the leg could not get there). Lets a harness grade only feet that
## are actually meant to be down, without re-deriving that decision itself.
var debug_state: Dictionary = {}
## side -> {"before_deg", "after_deg", "applied"}: how far the sole was from the sampled surface
## normal before the align pass and after it, in the skeleton's own space.
var debug_align: Dictionary = {}

## side -> {"hip", "knee", "foot", "upper", "lower", "rest_pole"}
var _legs: Dictionary = {}
## Base animation poses, captured once per frame before anything is modified. The modifier can be
## evaluated more than once per tick (including delta == 0 refresh passes), so re-deriving from the
## live skeleton on a later pass would read our own output back as if it were the animation.
var _frame := -1
var _base: Dictionary = {}


func _ready() -> void:
	if player_body == null:
		player_body = get_skeleton().get_parent() as PlayerBody if get_skeleton() != null else null
	_build_legs()


func _build_legs() -> void:
	_legs.clear()
	var skel := get_skeleton()
	if skel == null or player_body == null:
		return
	for side: StringName in LEGS:
		var roles: Dictionary = LEGS[side]
		var hip := skel.find_bone(player_body.resolve_bone_name(roles["hip"]))
		var knee := skel.find_bone(player_body.resolve_bone_name(roles["knee"]))
		var foot := skel.find_bone(player_body.resolve_bone_name(roles["foot"]))
		if hip < 0 or knee < 0 or foot < 0:
			continue
		var hip_rest := skel.get_bone_global_rest(hip).origin
		var knee_rest := skel.get_bone_global_rest(knee).origin
		var foot_rest := skel.get_bone_global_rest(foot).origin
		if ankle_height < 0.0:
			# The rest pose stands on the scene floor, so the foot bone's rest height IS the
			# ankle's height above the sole for this rig.
			ankle_height = foot_rest.y
		# Knee bend plane at rest, so a leg whose bend direction is ambiguous still folds forward.
		var sole_depth := _measure_sole_depth(skel, foot,
				skel.find_bone(player_body.resolve_bone_name(roles["toe"])))
		print("[FootIKv2] %s sole_depth=%.4f bone_rest_y=%.4f" % [
				side, sole_depth, foot_rest.y])
		if ankle_height < 0.0:
			# The ankle must sit this high above the ground for the SOLE to touch it. The foot
			# bone's own rest height is not that value (0.111 vs a real sole depth of ~0.096), so
			# it is measured from the skinned foot mesh in the rest pose, which stands on the floor.
			ankle_height = sole_depth
		var rest_direction := (foot_rest - hip_rest).normalized()
		var rest_pole := knee_rest - hip_rest
		rest_pole -= rest_direction * rest_pole.dot(rest_direction)
		_legs[side] = {
			"hip": hip, "knee": knee, "foot": foot,
			"toe": skel.find_bone(player_body.resolve_bone_name(roles["toe"])),
			"upper": hip_rest.distance_to(knee_rest),
			"lower": knee_rest.distance_to(foot_rest),
			"rest_pole": rest_pole.normalized(),
			# The sole's downward direction in the foot bone's own space: the rest pose stands on
			# the floor, so world-down at rest IS the sole direction for this rig.
			"sole_local": (skel.get_bone_global_rest(foot).basis.inverse() * Vector3.DOWN).normalized(),
		}


func _process_modification_with_delta(_delta: float) -> void:
	if not enabled:
		return
	var skel := get_skeleton()
	if skel == null or _legs.is_empty():
		return
	_take_snapshot(skel)
	for side: StringName in _legs:
		_place_foot(skel, side, _legs[side])


func _take_snapshot(skel: Skeleton3D) -> void:
	var current := Engine.get_physics_frames()
	if current == _frame:
		return
	_frame = current
	_base.clear()
	for side: StringName in _legs:
		var leg: Dictionary = _legs[side]
		_base[side] = {
			"hip": skel.get_bone_global_pose(int(leg["hip"])),
			"knee": skel.get_bone_global_pose(int(leg["knee"])),
			"foot": skel.get_bone_global_pose(int(leg["foot"])),
		}


func _place_foot(skel: Skeleton3D, side: StringName, leg: Dictionary) -> void:
	var base: Dictionary = _base[side]
	# get_bone_global_pose() is relative to the SKELETON, not the world, so the ground query has to
	# go through the skeleton's own transform or it samples the wrong place as soon as the character
	# is off the origin. Positions are converted back before the solve, which works in skeleton space.
	var to_world := skel.global_transform
	var animated_ankle: Vector3 = (to_world * (base["foot"] as Transform3D)).origin
	var hip_world: Vector3 = (to_world * (base["hip"] as Transform3D)).origin
	var hit := _ground_hit(animated_ankle, hip_world)
	if hit.is_empty():
		debug_skip_reason[side] = "no_ground"
		debug_target.erase(side)
		debug_state[side] = "released"
		return
	var ground: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	var target := ground + normal * ankle_height
	# A foot well above the sampled ground is mid-swing; dragging it down to the floor would read
	# as an invisible floor. A foot at or below the expected height is corrected, even when the
	# sampled surface is ABOVE it (stepping onto a ramp) - that is the case the animation clips.
	if animated_ankle.y - ground.y > max_lift:
		debug_skip_reason[side] = "mid_swing"
		debug_target.erase(side)
		debug_state[side] = "released"
		return
	# A target the leg cannot reach is not this foot's floor (a tread edge, the floor far below a
	# raised stance): stretching toward it locks the knee straight and floats the shoe. Leave the
	# animation alone instead - it already knows where the foot is.
	var blended := to_world.affine_inverse() * animated_ankle.lerp(target, weight)
	var hip_local: Vector3 = (base["hip"] as Transform3D).origin
	var reach := float(leg["upper"]) + float(leg["lower"]) - 0.001
	if hip_local.distance_to(blended) > reach:
		debug_skip_reason[side] = "out_of_reach"
		debug_target.erase(side)
		debug_state[side] = "released"
		return
	debug_target[side] = target
	debug_skip_reason[side] = ""
	debug_animated_ankle[side] = animated_ankle
	debug_ground[side] = ground
	_solve(skel, leg, base, blended, side)
	_align_foot(skel, leg, normal, side)
	var landed: Vector3 = skel.get_bone_global_pose(int(leg["foot"])).origin
	debug_solve[side]["residual"] = landed.distance_to(blended)
	debug_state[side] = ("at_target" if landed.distance_to(blended) <= 0.02 else "stretched")
	debug_ground_normal[side] = normal


## Lay the sole on the sampled surface: rotate the foot so its sole points into the ground along
## the surface normal. Without it a ramp keeps the shoe level while the ground tilts under it, so
## the toe or heel cuts into the slope.
func _align_foot(skel: Skeleton3D, leg: Dictionary, normal: Vector3,
		side: StringName) -> void:
	var foot := int(leg["foot"])
	var pose := skel.get_bone_global_pose(foot)
	var sole_local := leg["sole_local"] as Vector3
	var sole := (pose.basis * sole_local).normalized()
	# The normal is a world direction and the pose is skeleton-relative; compare in skeleton space.
	var local_normal := (skel.global_transform.basis.orthonormalized().inverse() * normal).normalized()
	var want := -local_normal
	var record := {"before_deg": rad_to_deg(sole.angle_to(want)), "after_deg": -1.0, "applied": false,
			"reason": ""}
	if normal.dot(Vector3.UP) < 0.5:
		record["reason"] = "too_steep"
		debug_align[side] = record
		return
	if sole.dot(want) < -0.999:
		record["reason"] = "opposite"
		debug_align[side] = record
		return
	var blended := Quaternion.IDENTITY.slerp(Quaternion(sole, want), weight)
	if blended.get_angle() >= 0.0001:
		pose.basis = Basis(blended) * pose.basis
		skel.set_bone_global_pose(foot, pose)
		record["applied"] = true
	record["after_deg"] = rad_to_deg(
			(pose.basis * sole_local).normalized().angle_to(want))
	debug_align[side] = record


## Sample the surface this foot should stand on, looking DOWN FROM THE BODY - not from just above
## the animated foot. On a ramp that foot can sit below the slope, and a ray starting at its own
## height never reaches the ramp above it: it hits the floor instead, and the foot is aimed at the
## wrong surface (measured: both feet targeting y=0.086 while the body stood at y=0.95 on a ramp).
func _ground_hit(ankle: Vector3, hip: Vector3) -> Dictionary:
	var space := get_skeleton().get_world_3d().direct_space_state
	if space == null:
		return {}
	var top := Vector3(ankle.x, maxf(hip.y, ankle.y + ray_up), ankle.z)
	var query := PhysicsRayQueryParameters3D.create(
			top, ankle - Vector3.UP * ray_down, ground_mask)
	var body := player_body.get_parent() as CollisionObject3D
	if body != null:
		query.exclude = [body.get_rid()]
	return space.intersect_ray(query)


## Analytic two-bone solve: aim the upper bone at the knee position and the lower bone at the ankle
## target. The maths lives in FootIKV2Solver so it can be tested without a scene; this only turns
## the result into bone poses.
func _solve(skel: Skeleton3D, leg: Dictionary, base: Dictionary, target: Vector3,
		side: StringName) -> void:
	var hip_pos: Vector3 = (base["hip"] as Transform3D).origin
	debug_solve[side] = {
		"reach": float(leg["upper"]) + float(leg["lower"]) - 0.001,
		"needed": hip_pos.distance_to(target),
		"target_local": target,
	}
	var solved := FootIKV2Solver.solve(
			hip_pos, (base["knee"] as Transform3D).origin, target,
			float(leg["upper"]), float(leg["lower"]), leg["rest_pole"] as Vector3)
	_aim(skel, int(leg["hip"]), int(leg["knee"]), solved["knee"] as Vector3)
	_aim(skel, int(leg["knee"]), int(leg["foot"]), solved["ankle"] as Vector3)
	# What the solver asked for vs where the chain actually put the foot: a mismatch here is the
	# aim step, not the maths.
	debug_solve[side]["solved_ankle"] = solved["ankle"] as Vector3
	debug_solve[side]["knee_target"] = solved["knee"] as Vector3
	debug_solve[side]["landed"] = skel.get_bone_global_pose(int(leg["foot"])).origin
	debug_solve[side]["landed_knee"] = skel.get_bone_global_pose(int(leg["knee"])).origin


## How far the lowest foot-mesh vertex sits below the foot bone, in the rest pose. Falls back to the
## bone's own rest height when the mesh cannot be read, so the modifier still runs.
func _measure_sole_depth(skel: Skeleton3D, foot: int, toe: int) -> float:
	var foot_rest := skel.get_bone_global_rest(foot)
	if player_body == null or not is_instance_valid(player_body.character):
		return foot_rest.origin.y
	var lowest := INF
	for node: Node in player_body.character.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if part == null or part.mesh == null or part.get_skin_reference() == null:
			continue
		var skin := part.get_skin_reference().get_skin()
		if skin == null:
			continue
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var bones := arrays[Mesh.ARRAY_BONES] as PackedInt32Array
			var weights := arrays[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
			if vertices.is_empty() or bones.is_empty() or weights.is_empty():
				continue
			var influences := bones.size() / vertices.size()
			for vertex in vertices.size():
				var summed := Vector3.ZERO
				var total := 0.0
				for influence in influences:
					var slot := vertex * influences + influence
					var bind := bones[slot]
					var weight := weights[slot]
					if weight <= 0.0 or bind < 0 or bind >= skin.get_bind_count():
						continue
					var bone := skin.get_bind_bone(bind)
					if bone < 0:
						bone = skel.find_bone(skin.get_bind_name(bind))
					if bone < 0 or (bone != foot and bone != toe):
						continue
					summed += (skel.get_bone_global_rest(bone)
							* skin.get_bind_pose(bind) * vertices[vertex]) * weight
					total += weight
				if total > 0.5:
					lowest = minf(lowest, (summed / total).y)
	if not is_finite(lowest):
		return foot_rest.origin.y
	return foot_rest.origin.y - lowest


## Rotate `bone` about its own origin so the segment to `child` points at `target`.
func _aim(skel: Skeleton3D, bone: int, child: int, target: Vector3) -> void:
	var pose := skel.get_bone_global_pose(bone)
	var child_pos: Vector3 = skel.get_bone_global_pose(child).origin
	var from := child_pos - pose.origin
	var to := target - pose.origin
	if from.length_squared() < 0.0000001 or to.length_squared() < 0.0000001:
		return
	pose.basis = Basis(Quaternion(from.normalized(), to.normalized())) * pose.basis
	skel.set_bone_global_pose(bone, pose)
