class_name ProceduralWalkLabModifier
extends SkeletonModifier3D
## Experimental walk generated from an idle pose. No gameplay Foot IK is involved.

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

var phase := 0.0
var amount := 1.0
var stride := 0.20
var lift := 0.13
var bob := 0.025
var arm_swing := 0.22
var moving_mode := false

var _indices: Array[Array] = []
var _hips := -1
var _spine := -1
var _debug_indices: Dictionary = {}
var debug_joint_positions: Dictionary = {}
var debug_joint_rotations: Dictionary = {}
var debug_knee_flex: Dictionary = {}
var debug_target_error: Dictionary = {}
var _has_plant: Array[bool] = [false, false]
var _was_swinging: Array[bool] = [false, false]
var _plant_world: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _swing_from_world: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _swing_to_world: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]


func reset_moving_state() -> void:
	for side in 2:
		_has_plant[side] = false
		_was_swinging[side] = false
		_plant_world[side] = Vector3.ZERO
		_swing_from_world[side] = Vector3.ZERO
		_swing_to_world[side] = Vector3.ZERO


func has_plant(side: int) -> bool:
	return _has_plant[side]


func plant_world(side: int) -> Vector3:
	return _plant_world[side]


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


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or _indices.size() != 2 or _hips < 0:
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
	if _spine >= 0:
		var spine_pose := skel.get_bone_global_pose(_spine)
		spine_pose.basis = Basis(Vector3.UP, sin(phase) * 0.035 * amount) * spine_pose.basis
		skel.set_bone_global_pose(_spine, spine_pose)
	_cache_debug_joints(skel)


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
	var ankle_target := base_foot.origin + Vector3(
			0.0, swing_height * amount, foot_z * amount)
	if moving_mode:
		ankle_target = _moving_ankle_target(
				skel, side, base_foot.origin, cycle, foot_z, swing_height)
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
	foot_pose.basis = base_foot.basis
	skel.set_bone_global_pose(foot, foot_pose)
	debug_target_error["Left" if side == 0 else "Right"] = (
			foot_pose.origin.distance_to(ankle_target))
	var arm_pose := skel.get_bone_global_pose(arm)
	arm_pose.basis = Basis(Vector3.RIGHT, sin(side_phase) * arm_swing * amount) * base_arm.basis
	skel.set_bone_global_pose(arm, arm_pose)


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
			_swing_to_world[side] = (world_from_local
					* (base_ankle + Vector3(0.0, 0.0, stride * amount))
					+ Vector3.FORWARD * root_travel * remaining_cycles)
			_has_plant[side] = false
			_was_swinging[side] = true
		var t := cycle / SWING_FRACTION
		var eased := t * t * (3.0 - 2.0 * t)
		var world_target := _swing_from_world[side].lerp(_swing_to_world[side], eased)
		world_target.y += swing_height * amount
		return local_from_world * world_target
	if _was_swinging[side]:
		_plant_world[side] = _swing_to_world[side]
		_has_plant[side] = true
		_was_swinging[side] = false
	elif not _has_plant[side]:
		# One leg begins mid-stance when the moving demo starts.
		_plant_world[side] = world_from_local * (
				base_ankle + Vector3(0.0, 0.0, foot_z * amount))
		_has_plant[side] = true
	return local_from_world * _plant_world[side]


func _aim(skel: Skeleton3D, bone: int, child_pos: Vector3, target: Vector3) -> void:
	var pose := skel.get_bone_global_pose(bone)
	var from := child_pos - pose.origin
	var to := target - pose.origin
	if from.length_squared() < 0.000001 or to.length_squared() < 0.000001:
		return
	pose.basis = Basis(Quaternion(from.normalized(), to.normalized())) * pose.basis
	skel.set_bone_global_pose(bone, pose)


func _cache_debug_joints(skel: Skeleton3D) -> void:
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
