class_name ProceduralWalkLabModifier
extends SkeletonModifier3D
## Experimental walk generated from an idle pose. No gameplay Foot IK is involved.

const STEP_PLAN := preload(
		"res://tests/manual/procedural_walk/procedural_footstep_plan.gd")

const SIDES := [
	[&"LeftUpLeg", &"LeftLeg", &"LeftFoot", &"LeftArm", 0.0],
	[&"RightUpLeg", &"RightLeg", &"RightFoot", &"RightArm", PI],
]
const DEBUG_JOINTS := [
	&"LeftUpLeg", &"LeftLeg", &"LeftFoot", &"LeftToeBase",
	&"RightUpLeg", &"RightLeg", &"RightFoot", &"RightToeBase",
]
const STANDING_FLEX_DROP := 0.04
const SWING_FRACTION := 0.4
const STAIR_START_Z := 1.0
const STAIR_DEPTH := 0.35
const STAIR_HEIGHT := 0.18
const STAIR_STEPS := 12 # long enough that the looping walk never reaches a flat top
## The moving stair shoe reaches about 0.233 m ahead of the ankle at some swing
## phases. Reserve 0.24 m so the forward mesh stays clear of the next riser.
const STAIR_TOE_REACH := 0.24
const STAIR_HEEL_REACH := 0.10

var phase := 0.0
var amount := 1.0
var stride := 0.20
var lift := 0.13
var bob := 0.025
var arm_swing := 0.22
var moving_mode := false
var stair_direction := 0 # 1 up, -1 down, 0 flat
var stair_course: ProceduralWalkStairCourse
var reference_bank: ProceduralWalkReferenceBank
var reference_mode := &""
var neutral_ankle_targets: Array[Vector3] = []
## Standalone contact correction (lab-only): clamp each generated ankle target to the real surface
## under it, so a procedurally placed foot plants on the actual tread instead of the hand-authored
## height. 0 disables, 1 fully applies - lets the lab A/B it.
var contact_ik := 1.0
## Clearance a swinging foot keeps above the surface it will land on. Analogue of the game IK's
## ground sampler + contact policy, without any of its Player-coupled subsystem stack.
const CONTACT_CLEARANCE := 0.02
const CONTACT_RATE := 1.5
const PLANNED_STEPS_PER_SIDE := 3
const PLANNED_STEP_COUNT := PLANNED_STEPS_PER_SIDE * 2

var _indices: Array[Array] = []
var _hips := -1
var _spine := -1
var _debug_indices: Dictionary = {}
var debug_joint_positions: Dictionary = {}
var debug_joint_rotations: Dictionary = {}
var debug_knee_flex: Dictionary = {}
var debug_target_error: Dictionary = {}
var debug_contact_weight: Dictionary = {}
var debug_source_knee: Dictionary = {}
var debug_shoe_corrections: Dictionary = {}
var debug_shoe_required_y: Dictionary = {}
var debug_bone_poses: Array[Transform3D] = []
var debug_root_position := Vector3.ZERO
var debug_pose_frame := -1
var debug_reference_hips_y := 0.0
var debug_floor_clearance := 0.0
var debug_pelvis_drop := 0.0
var trace_capture: RefCounted
var trace_character: Node3D
var _gait_anchor_x: Array[float] = [0.0, 0.0]
var _contact_y: Array[float] = [0.0, 0.0]
var _contact_ready: Array[bool] = [false, false]
var _delta := 1.0 / 60.0
var _has_plant: Array[bool] = [false, false]
var _was_swinging: Array[bool] = [false, false]
var _plant_world: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _swing_from_world: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _swing_to_world: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _step_plan: RefCounted = STEP_PLAN.new()
var _source_plan_ready := false
var _source_plan_last_phase := 0.0
var _source_contact_targets: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _source_contact_anchor_y: Array[float] = [0.0, 0.0]
var _source_contact_valid: Array[bool] = [false, false]


func reset_moving_state() -> void:
	_step_plan.reset()
	_source_plan_ready = false
	for side in 2:
		_source_contact_valid[side] = false
		_has_plant[side] = false
		_was_swinging[side] = false
		_plant_world[side] = Vector3.ZERO
		_swing_from_world[side] = Vector3.ZERO
		_swing_to_world[side] = Vector3.ZERO


func has_plant(side: int) -> bool:
	return _has_plant[side]


func plant_world(side: int) -> Vector3:
	return _plant_world[side]


## Lateral offset the gait actually anchors this side's steps on, relative to the character. The
## neutral targets are only one of two possible anchors (Original mode uses the idle pose's foot),
## so a predictor overlay must read this rather than assume the neutral.
func gait_anchor_x(side: int) -> float:
	return _gait_anchor_x[side]


## The gait's own predicted touchdown for the leg currently swinging (fixed for the whole swing),
## so a lab overlay can mark where the foot will really land, not an analytic approximation.
func footstep_plan() -> RefCounted:
	return _step_plan


func stair_support_height(world_z: float) -> float:
	if stair_course != null:
		return stair_course.support_height(world_z)
	if stair_direction == 0:
		return 0.0
	var step := clampi(int(floorf((STAIR_START_Z - world_z) / STAIR_DEPTH)),
			0, STAIR_STEPS)
	return float(step if stair_direction > 0 else STAIR_STEPS - step) * STAIR_HEIGHT


func stair_safe_ankle(target: Vector3) -> Vector3:
	if stair_course != null:
		return stair_course.safe_ankle(target,
				reference_mode in [&"walk", &"sprint"])
	if stair_direction == 0:
		return target
	var step := clampi(int(floorf((STAIR_START_Z - target.z) / STAIR_DEPTH)),
			0, STAIR_STEPS)
	if step > 0 and step < STAIR_STEPS:
		var rear_edge := STAIR_START_Z - float(step) * STAIR_DEPTH
		var front_edge := rear_edge - STAIR_DEPTH
		target.z = clampf(target.z, front_edge + STAIR_TOE_REACH,
				rear_edge - STAIR_HEEL_REACH)
	return target


## The far end of the authored staircase (climb direction), where the looping walk must restart.
func stair_top_z() -> float:
	return STAIR_START_Z - float(STAIR_STEPS) * STAIR_DEPTH


func stair_root_height(world_z: float) -> float:
	if stair_course != null:
		return stair_course.root_height(world_z)
	if stair_direction == 0:
		return 0.0
	var progress := clampf((STAIR_START_Z - world_z) /
			(STAIR_DEPTH * float(STAIR_STEPS)), 0.0, 1.0)
	var up_height := progress * float(STAIR_STEPS) * STAIR_HEIGHT
	return up_height if stair_direction > 0 else (
			float(STAIR_STEPS) * STAIR_HEIGHT - up_height)


func _ready() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	_hips = skel.find_bone(&"Hips")
	_spine = skel.find_bone(&"Spine")
	for name: StringName in DEBUG_JOINTS:
		_debug_indices[name] = skel.find_bone(name)
	for names: Array in SIDES:
		var chain: Array[int] = []
		for name: StringName in names.slice(0, 4):
			chain.append(skel.find_bone(name))
		if chain.has(-1):
			push_error("Procedural walk lab: MotusMan leg/arm bones are missing")
			return
		_indices.append(chain)
	if _hips < 0:
		push_error("Procedural walk lab: Hips bone is missing")


func _process_modification_with_delta(delta: float) -> void:
	_delta = delta if delta > 0.0 else _delta
	debug_pelvis_drop = 0.0
	var skel := get_skeleton()
	if skel == null or _indices.size() != 2 or _hips < 0:
		return
	if reference_bank != null and reference_mode != &"":
		_apply_reference_pose(skel)
		if reference_mode != &"stair_up" and reference_mode != &"stair_down":
			_apply_flat_source_floor_clearance(skel)
			if moving_mode:
				_update_source_step_plan(skel)
			if moving_mode and reference_mode in [&"walk", &"walk_aim", &"crouch", &"sprint"]:
				if stair_course != null and reference_mode == &"walk":
					_lower_pelvis_for_course_reach(skel)
				_apply_source_contact_ik(skel)
			else:
				debug_target_error["Left"] = 0.0
				debug_target_error["Right"] = 0.0
				debug_contact_weight["Left"] = 0.0
				debug_contact_weight["Right"] = 0.0
			_cache_debug_joints(skel)
			return
	if amount <= 0.001:
		_cache_debug_joints(skel)
		return
	# Capture the animation pose before changing its parent chain. The modifier's
	# input is the idle clip, never a previously generated walk frame.
	var bases: Array[Array] = []
	for chain: Array in _indices:
		var poses: Array[Transform3D] = []
		for index: int in chain:
			poses.append(skel.get_bone_global_pose(index))
		bases.append(poses)
	var hip_pose := skel.get_bone_global_pose(_hips)
	# A small shared crouch keeps both knees flexed at foot contact. Without it,
	# the landing leg reaches full extension before the shoe reaches the floor.
	hip_pose.origin.y += amount * (-STANDING_FLEX_DROP
			+ bob * (1.0 - cos(phase * 2.0)) * 0.5)
	skel.set_bone_global_pose(_hips, hip_pose)
	for side in 2:
		_solve_side(skel, _indices[side], bases[side], side,
				phase + SIDES[side][4])
	if _spine >= 0 and reference_mode == &"":
		var spine_pose := skel.get_bone_global_pose(_spine)
		spine_pose.basis = Basis(Vector3.UP, sin(phase) * 0.035 * amount) * spine_pose.basis
		skel.set_bone_global_pose(_spine, spine_pose)
	_cache_debug_joints(skel)


func _apply_reference_pose(skel: Skeleton3D) -> void:
	var poses := reference_bank.sample_pose(reference_mode, phase)
	if poses.size() != skel.get_bone_count():
		return
	for index in poses.size():
		var pose: Transform3D = poses[index]
		skel.set_bone_pose_position(index, pose.origin)
		skel.set_bone_pose_rotation(index, pose.basis.get_rotation_quaternion())
		skel.set_bone_pose_scale(index, pose.basis.get_scale())
	debug_reference_hips_y = skel.get_bone_pose_position(_hips).y


func _apply_flat_source_floor_clearance(skel: Skeleton3D) -> void:
	# Preserve every source joint rotation and relative pose. Imported clips
	# can place their skinned soles below the lab plane, so move only Hips by
	# the minimum amount needed to clear the lowest shoe vertex.
	var hips_pose := skel.get_bone_pose_position(_hips)
	debug_floor_clearance = reference_bank.floor_clearance(reference_mode, phase)
	hips_pose.y += debug_floor_clearance
	skel.set_bone_pose_position(_hips, hips_pose)


func _solve_side(skel: Skeleton3D, chain: Array, base: Array,
		side: int, side_phase: float) -> void:
	var upper: int = chain[0]
	var lower: int = chain[1]
	var foot: int = chain[2]
	var arm: int = chain[3]
	var base_upper: Transform3D = base[0]
	var base_lower: Transform3D = base[1]
	var base_foot: Transform3D = base[2]
	var base_arm: Transform3D = base[3]
	# Swing occupies the first 40% of the cycle. The foot reaches the floor
	# before the body passes over it, then stays planted through the remaining
	# 60%. Cubic travel and a squared-sine lift give zero speed at touchdown.
	var cycle := fposmod(side_phase / TAU, 1.0)
	var foot_z := 0.0
	var swing_height := 0.0
	if cycle < SWING_FRACTION:
		var t := cycle / SWING_FRACTION
		var eased := t * t * (3.0 - 2.0 * t)
		foot_z = lerpf(-stride, stride, eased)
		swing_height = pow(sin(PI * t), 2.0) * lift
	else:
		var t := (cycle - SWING_FRACTION) / (1.0 - SWING_FRACTION)
		var eased := t * t * (3.0 - 2.0 * t)
		foot_z = lerpf(stride, -stride, eased)
	# MotusMan's native +Z becomes world -Z after the scene-facing correction.
	# The lifted foot must travel from native -Z (rear) to +Z (front).
	var anchor := base_foot.origin
	if reference_mode != &"" and neutral_ankle_targets.size() == 2:
		anchor = neutral_ankle_targets[side]
	_gait_anchor_x[side] = anchor.x
	var ankle_target := anchor + Vector3(
			0.0, swing_height * amount, foot_z * amount)
	if moving_mode:
		ankle_target = _moving_ankle_target(
				skel, side, anchor, cycle, foot_z, swing_height)
	else:
		# The moving path's plant lock already lands stair feet on the tread (same
		# stair_support_height math), so correcting there would fight the lock.
		ankle_target.y = _contact_corrected_y(side, cycle, ankle_target)
	var hip_pos := skel.get_bone_global_pose(upper).origin
	var upper_len := base_upper.origin.distance_to(base_lower.origin)
	var lower_len := base_lower.origin.distance_to(base_foot.origin)
	var to_ankle := ankle_target - hip_pos
	var distance := clampf(to_ankle.length(),
			absf(upper_len - lower_len) + 0.001, upper_len + lower_len - 0.001)
	var direction := to_ankle.normalized()
	var solved_ankle := hip_pos + direction * distance
	var along := (upper_len * upper_len - lower_len * lower_len + distance * distance) / (
			2.0 * distance)
	var outward := sqrt(maxf(0.0, upper_len * upper_len - along * along))
	# The idle knee sits almost on the hip-to-ankle line. Projecting that tiny
	# animated offset flips sign as the ankle crosses it, causing a 50-degree
	# one-frame knee reversal. MotusMan faces native +Z, so use its stable
	# anatomical forward direction for the bend plane throughout the cycle.
	var pole := Vector3.BACK - direction * direction.dot(Vector3.BACK)
	if pole.length_squared() < 0.000001:
		pole = Vector3.RIGHT - direction * Vector3.RIGHT.dot(direction)
	var knee_target := hip_pos + direction * along + pole.normalized() * outward
	_aim(skel, upper, skel.get_bone_global_pose(lower).origin, knee_target)
	_aim(skel, lower, skel.get_bone_global_pose(foot).origin, solved_ankle)
	# Counter-rotate the shoe after the chain moves, so the sole remains level.
	var foot_pose := skel.get_bone_global_pose(foot)
	foot_pose.basis = (reference_bank.foot_basis(reference_mode, phase, side)
			if reference_mode != &"" and reference_bank != null
			else base_foot.basis)
	skel.set_bone_global_pose(foot, foot_pose)
	debug_target_error["Left" if side == 0 else "Right"] = (
			foot_pose.origin.distance_to(ankle_target))
	if reference_mode == &"":
		var arm_pose := skel.get_bone_global_pose(arm)
		arm_pose.basis = Basis(Vector3.RIGHT, sin(side_phase) * arm_swing * amount) * base_arm.basis
		skel.set_bone_global_pose(arm, arm_pose)


## Ground height under a world point: the authored tread on stairs, the flat floor otherwise. The
## lab's stair boxes are visual-only (no colliders), but the same function already drives their
## heights, so this stays exact without adding physics geometry.
func ground_height(world_pos: Vector3) -> float:
	return stair_support_height(world_pos.z) if stair_direction != 0 or stair_course != null else 0.0


## The generated ankle height corrected onto the real surface: planted feet sit at surface +
## ankle height, swinging feet keep CONTACT_CLEARANCE above it. Rate-limited, because the tread
## steps a whole 0.18m at each edge and the raw snap is visible.
func _contact_corrected_y(side: int, cycle: float, ankle_target: Vector3) -> float:
	var ankle_height := (neutral_ankle_targets[side].y
			if neutral_ankle_targets.size() == 2 else ankle_target.y)
	var surface := ground_height(ankle_target) + ankle_height
	var wanted := (surface if cycle >= SWING_FRACTION
			else maxf(ankle_target.y, surface + CONTACT_CLEARANCE))
	if not _contact_ready[side]:
		_contact_ready[side] = true
		_contact_y[side] = wanted
	_contact_y[side] = move_toward(_contact_y[side], wanted, CONTACT_RATE * maxf(_delta, 0.0001))
	return lerpf(ankle_target.y, _contact_y[side], contact_ik)


func _moving_ankle_target(skel: Skeleton3D, side: int,
		base_ankle: Vector3, cycle: float, foot_z: float, swing_height: float) -> Vector3:
	var world_from_local := skel.global_transform
	var local_from_world := world_from_local.affine_inverse()
	if cycle < SWING_FRACTION:
		if not _was_swinging[side]:
			_swing_from_world[side] = (
					_plant_world[side] if _has_plant[side]
					else world_from_local * (base_ankle + Vector3(0.0, 0.0, -stride * amount)))
			# Predict where the root will be at touchdown, then place the
			# front foot relative to that future root position.
			var remaining_cycles := SWING_FRACTION - cycle
			var root_travel := 2.0 * stride * amount / (1.0 - SWING_FRACTION)
			var proposed := (world_from_local
					* (base_ankle + Vector3(0.0, 0.0, stride * amount))
					+ Vector3.FORWARD * root_travel * remaining_cycles)
			if stair_direction != 0 or stair_course != null:
				proposed = stair_safe_ankle(proposed)
				proposed.y = (stair_support_height(proposed.z)
						+ base_ankle.y)
			_ensure_step_plan(side, proposed, world_from_local)
			_swing_to_world[side] = _step_plan.target(0)
			_has_plant[side] = false
			_was_swinging[side] = true
		var t := cycle / SWING_FRACTION
		var eased := t * t * (3.0 - 2.0 * t)
		var world_target := _swing_from_world[side].lerp(_swing_to_world[side], eased)
		world_target.y += swing_height * amount * (
				1.8 if stair_direction > 0 or stair_course != null else 1.0)
		world_target = _clear_stair_shoe(side, world_target)
		return local_from_world * world_target
	if _was_swinging[side]:
		_plant_world[side] = _swing_to_world[side]
		_has_plant[side] = true
		_was_swinging[side] = false
		_complete_planned_step(side, world_from_local)
	elif not _has_plant[side]:
		# One leg begins mid-stance when the moving demo starts.
		_plant_world[side] = world_from_local * (
				base_ankle + Vector3(0.0, 0.0, foot_z * amount))
		if stair_direction != 0 or stair_course != null:
			_plant_world[side] = stair_safe_ankle(_plant_world[side])
			_plant_world[side].y = (stair_support_height(_plant_world[side].z)
					+ base_ankle.y)
		_has_plant[side] = true
	if stair_direction > 0 or stair_course != null:
		# Re-evaluate from the accepted tread height every stance frame. Feeding last
		# frame's clearance lift back into maxf() made the planted shoe ratchet upward.
		_plant_world[side].y = stair_support_height(_plant_world[side].z) + base_ankle.y
	_plant_world[side] = _clear_stair_shoe(side, _plant_world[side])
	return local_from_world * _plant_world[side]


func _clear_stair_shoe(side: int, world_ankle: Vector3) -> Vector3:
	if (stair_direction <= 0 and stair_course == null) or reference_bank == null:
		return world_ankle
	if stair_course != null:
		var course_y := reference_bank.shoe_clearance_ankle_y(
				reference_mode, phase, side, world_ankle.z,
				stair_course.support_height) + 0.006
		world_ankle.y = (course_y if _has_plant[side]
				else maxf(world_ankle.y, course_y))
		return world_ankle
	# A level ankle is not a level shoe: the sampled stair pose bends the toe down
	# by up to 12 cm. Look under its forward envelope, including the next riser.
	var toe_z := world_ankle.z - STAIR_TOE_REACH + 0.0005
	var shoe_drop := reference_bank.foot_mesh_drop(reference_mode, phase, side)
	var support := stair_support_height(toe_z)
	if stair_course != null:
		support = maxf(maxf(support, stair_support_height(world_ankle.z)),
				stair_support_height(world_ankle.z + ProceduralWalkStairCourse.HEEL_REACH))
	world_ankle.y = maxf(world_ankle.y,
			support + shoe_drop + 0.006)
	return world_ankle


func _ensure_step_plan(side: int, proposed: Vector3, world_from_local: Transform3D) -> void:
	if _step_plan.size() > 0 and _step_plan.first_side() == side:
		return
	# A mismatch only occurs after a reset or external phase seek. Re-seed once;
	# during ordinary playback accepted entries are never recomputed.
	_step_plan.reset()
	_step_plan.append(proposed, side)
	while _step_plan.size() < PLANNED_STEP_COUNT:
		_append_planned_step(world_from_local)


func _complete_planned_step(side: int, world_from_local: Transform3D) -> void:
	if not _step_plan.consume(side):
		return
	_append_planned_step(world_from_local)


func _append_planned_step(world_from_local: Transform3D) -> void:
	if _step_plan.size() == 0:
		return
	var side: int = 1 - int(_step_plan.last_side())
	var step := stride * amount / (1.0 - SWING_FRACTION)
	var target: Vector3 = _step_plan.last_target() + Vector3.FORWARD * step
	var local_anchor := (neutral_ankle_targets[side]
			if neutral_ankle_targets.size() == 2 else Vector3(_gait_anchor_x[side], 0.0, 0.0))
	target.x = (world_from_local * local_anchor).x
	if stair_direction != 0 or stair_course != null:
		target = stair_safe_ankle(target)
		target.y = stair_support_height(target.z) + local_anchor.y
	_step_plan.append(target, side)


func _update_source_step_plan(skel: Skeleton3D) -> void:
	var current_phase := fposmod(phase / TAU, 1.0)
	if not _source_plan_ready or _step_plan.size() != PLANNED_STEP_COUNT:
		_seed_source_step_plan(skel.global_transform, current_phase)
		for side in 2:
			if reference_bank.contact_weight(reference_mode, side, current_phase) > 0.001:
				var foot: int = _indices[side][2]
				_source_contact_targets[side] = (skel.global_transform
						* skel.get_bone_global_pose(foot).origin)
				if stair_course != null:
					_source_contact_targets[side] = stair_safe_ankle(
							_source_contact_targets[side])
				_source_contact_anchor_y[side] = _source_contact_targets[side].y
				_source_contact_valid[side] = true
		_source_plan_last_phase = current_phase
		_source_plan_ready = true
		return
	var next_side: int = int(_step_plan.first_side())
	var touchdown := reference_bank.touchdown_phase(reference_mode, next_side)
	if _phase_crossed(_source_plan_last_phase, current_phase, touchdown):
		_source_contact_targets[next_side] = _step_plan.target(0)
		_source_contact_anchor_y[next_side] = _source_contact_targets[next_side].y
		_source_contact_valid[next_side] = true
		_complete_source_step(next_side)
	_source_plan_last_phase = current_phase


func _seed_source_step_plan(world_from_local: Transform3D, current_phase: float) -> void:
	_step_plan.reset()
	var events: Array[Dictionary] = []
	for side in 2:
		var until := fposmod(reference_bank.touchdown_phase(reference_mode, side)
				- current_phase, 1.0)
		if until < 0.001:
			until += 1.0
		for cycle in PLANNED_STEPS_PER_SIDE:
			events.append({"until": until + float(cycle), "side": side})
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["until"]) < float(b["until"]))
	var travel := float(reference_bank.flat_travel_per_cycle[reference_mode])
	for event: Dictionary in events:
		var side := int(event["side"])
		var target: Vector3 = world_from_local * reference_bank.touchdown_ankle(
				reference_mode, side)
		# Plans use the same floor-safe pose contract as the rendered source.
		# The imported ankle alone predates the mesh-clearance Hips lift and can
		# otherwise put the accepted plant below the ankle's reachable floor pose.
		target.y += reference_bank.floor_clearance(reference_mode,
				reference_bank.touchdown_phase(reference_mode, side) * TAU)
		target += Vector3.FORWARD * travel * float(event["until"])
		if stair_course != null:
			target = stair_safe_ankle(target)
			target.y = (target.y - world_from_local.origin.y
					+ stair_support_height(target.z))
		_step_plan.append(target, side)


func _complete_source_step(side: int) -> void:
	if not _step_plan.consume(side):
		return
	var previous := Vector3.ZERO
	for index in range(_step_plan.size() - 1, -1, -1):
		if _step_plan.side(index) == side:
			previous = _step_plan.target(index)
			break
	var travel := float(reference_bank.flat_travel_per_cycle[reference_mode])
	var next_target := previous + Vector3.FORWARD * travel
	if stair_course != null:
		next_target = stair_safe_ankle(next_target)
		next_target.y += (stair_support_height(next_target.z)
				- stair_support_height(previous.z))
	_step_plan.append(next_target, side)


func _phase_crossed(before: float, after: float, event: float) -> bool:
	return (event > before and event <= after) if after >= before else (
			event > before or event <= after)


func _apply_source_contact_ik(skel: Skeleton3D) -> void:
	var normalized_phase := fposmod(phase / TAU, 1.0)
	for side in 2:
		var name := "Left" if side == 0 else "Right"
		debug_source_knee[name] = (skel.global_transform
				* skel.get_bone_global_pose(_indices[side][1]).origin)
		debug_shoe_corrections[name] = 0
		var weight := (reference_bank.contact_weight(reference_mode, side, normalized_phase)
				* clampf(contact_ik, 0.0, 1.0))
		debug_contact_weight[name] = weight
		if not _source_contact_valid[side] or weight <= 0.001:
			debug_target_error[name] = 0.0
			if stair_course != null:
				_clear_source_shoe(skel, side, weight)
			continue
		var pose_target := _source_pose_contact_target(skel, side)
		_solve_source_leg(skel, side, pose_target, weight)
		if stair_course != null:
			_clear_source_shoe(skel, side, weight)
		var foot: int = _indices[side][2]
		var solved_world := skel.global_transform * skel.get_bone_global_pose(foot).origin
		debug_target_error[name] = solved_world.distance_to(pose_target)


func _source_pose_contact_target(skel: Skeleton3D, side: int) -> Vector3:
	# A planted shoe still rolls from heel to toe. Preserve that source style,
	# but lift/lower its ankle by the source pose's already floor-safe vertical
	# offset so the rotating mesh cannot cut through the floor.
	var foot: int = _indices[side][2]
	var source_ankle := skel.global_transform * skel.get_bone_global_pose(foot).origin
	var target: Vector3 = _source_contact_targets[side]
	if stair_course != null:
		target.y = reference_bank.shoe_clearance_ankle_y(
				reference_mode, phase, side, target.z,
				stair_course.support_height) + 0.006
		return target
	target.y += source_ankle.y - _source_contact_anchor_y[side]
	return target


func _lower_pelvis_for_course_reach(skel: Skeleton3D) -> void:
	# A safe target on a narrow tread is useless if the source pelvis leaves the
	# planted leg short of it: the shoe then lands across the neighboring riser.
	# Lower the shared Hips only as far as the current contact geometry requires.
	var drop := 0.0
	var normalized_phase := fposmod(phase / TAU, 1.0)
	for side in 2:
		if not _source_contact_valid[side]:
			continue
		var weight := reference_bank.contact_weight(reference_mode, side, normalized_phase)
		if weight <= 0.001:
			continue
		var chain: Array = _indices[side]
		var hip := skel.global_transform * skel.get_bone_global_pose(chain[0]).origin
		var knee := skel.global_transform * skel.get_bone_global_pose(chain[1]).origin
		var ankle := skel.global_transform * skel.get_bone_global_pose(chain[2]).origin
		var target: Vector3 = _source_contact_targets[side]
		target.y = reference_bank.shoe_clearance_ankle_y(
				reference_mode, phase, side, target.z,
				stair_course.support_height) + 0.006
		# The solve blends the animated ankle toward the plant by contact
		# weight. Check reach to that same *effective* target; the distant
		# settled plant is not the current target during acquire/release.
		target = ankle.lerp(target, weight)
		# Match the solver's preferred knee-flex reach (0.012 m short of
		# full extension), with a small reserve for the skinned toe envelope.
		var reach := hip.distance_to(knee) + knee.distance_to(ankle) - 0.017
		var horizontal := Vector2(hip.x - target.x, hip.z - target.z).length()
		if horizontal >= reach:
			continue # A vertical change cannot rescue this horizontal miss.
		var high_limit := target.y + sqrt(reach * reach - horizontal * horizontal)
		drop = maxf(drop, maxf(0.0, hip.y - high_limit))
	if drop <= 0.0:
		return
	var hips_pose := skel.get_bone_pose_position(_hips)
	hips_pose.y -= minf(drop, 0.25)
	debug_pelvis_drop = minf(drop, 0.25)
	skel.set_bone_pose_position(_hips, hips_pose)


func _clear_source_shoe(skel: Skeleton3D, side: int, weight: float) -> void:
	var foot: int = _indices[side][2]
	var name := "Left" if side == 0 else "Right"
	for attempt in 10:
		var ankle := skel.global_transform * skel.get_bone_global_pose(foot).origin
		var required_y := reference_bank.shoe_clearance_ankle_y(
				reference_mode, phase, side, ankle.z,
				stair_course.support_height) + 0.006
		debug_shoe_required_y[name] = required_y
		if weight < 0.8 and ankle.y >= required_y - 0.001:
			break
		if absf(ankle.y - required_y) < 0.001:
			break
		ankle.y = required_y
		debug_shoe_corrections[name] = int(debug_shoe_corrections.get(name, 0)) + 1
		_solve_source_leg(skel, side, ankle, 1.0)


func _solve_source_leg(skel: Skeleton3D, side: int,
		world_target: Vector3, weight: float) -> void:
	var chain: Array = _indices[side]
	var upper: int = chain[0]
	var lower: int = chain[1]
	var foot: int = chain[2]
	var upper_pose := skel.get_bone_global_pose(upper)
	var lower_pose := skel.get_bone_global_pose(lower)
	var foot_pose := skel.get_bone_global_pose(foot)
	var source_foot_basis := foot_pose.basis
	var local_target := skel.global_transform.affine_inverse() * world_target
	var ankle_target := foot_pose.origin.lerp(local_target, weight)
	var upper_len := upper_pose.origin.distance_to(lower_pose.origin)
	var lower_len := lower_pose.origin.distance_to(foot_pose.origin)
	var to_ankle := ankle_target - upper_pose.origin
	var reach_margin := 0.012 if reference_mode == &"walk" and stair_course != null else 0.001
	var distance := clampf(to_ankle.length(),
			absf(upper_len - lower_len) + 0.001, upper_len + lower_len - reach_margin)
	var direction := to_ankle.normalized()
	var solved_ankle := upper_pose.origin + direction * distance
	var along := (upper_len * upper_len - lower_len * lower_len + distance * distance) / (
			2.0 * distance)
	var outward := sqrt(maxf(0.0, upper_len * upper_len - along * along))
	var source_along := direction * (lower_pose.origin - upper_pose.origin).dot(direction)
	var pole := lower_pose.origin - upper_pose.origin - source_along
	if reference_mode == &"sprint" or (reference_mode == &"walk" and stair_course != null):
		# Sprint and stair-course Walk cross near-full extension; a pole
		# sampled from the knee can reverse through the hip-to-ankle line.
		# Keep its anatomical bend side through the contact handoff.
		pole = Vector3.BACK - direction * direction.dot(Vector3.BACK)
	if pole.length_squared() < 0.000001:
		pole = Vector3.RIGHT - direction * direction.dot(Vector3.RIGHT)
	var knee_target := upper_pose.origin + direction * along + pole.normalized() * outward
	_aim(skel, upper, lower_pose.origin, knee_target)
	_aim(skel, lower, skel.get_bone_global_pose(foot).origin, solved_ankle)
	foot_pose = skel.get_bone_global_pose(foot)
	foot_pose.basis = source_foot_basis
	skel.set_bone_global_pose(foot, foot_pose)


func _aim(skel: Skeleton3D, bone: int, child_pos: Vector3, target: Vector3) -> void:
	var pose := skel.get_bone_global_pose(bone)
	var from := child_pos - pose.origin
	var to := target - pose.origin
	if from.length_squared() < 0.000001 or to.length_squared() < 0.000001:
		return
	pose.basis = Basis(Quaternion(from.normalized(), to.normalized())) * pose.basis
	skel.set_bone_global_pose(bone, pose)


func _cache_debug_joints(skel: Skeleton3D) -> void:
	debug_pose_frame = Engine.get_physics_frames()
	debug_root_position = skel.global_position
	debug_bone_poses.clear()
	for bone in skel.get_bone_count():
		debug_bone_poses.append(skel.get_bone_global_pose(bone))
	debug_joint_positions.clear()
	debug_joint_rotations.clear()
	debug_knee_flex.clear()
	for name: StringName in _debug_indices:
		var index: int = _debug_indices[name]
		if index >= 0:
			var pose := skel.get_bone_global_pose(index)
			debug_joint_positions[name] = skel.global_transform * pose.origin
			debug_joint_rotations[name] = pose.basis.get_rotation_quaternion()
	for side: String in ["Left", "Right"]:
		var hip: Vector3 = debug_joint_positions[StringName(side + "UpLeg")]
		var knee: Vector3 = debug_joint_positions[StringName(side + "Leg")]
		var ankle: Vector3 = debug_joint_positions[StringName(side + "Foot")]
		debug_knee_flex[side] = rad_to_deg((knee - hip).angle_to(ankle - knee))
	if trace_capture != null and stair_course != null:
		trace_capture.call(&"capture", trace_character, skel, self,
				stair_course, reference_mode)
