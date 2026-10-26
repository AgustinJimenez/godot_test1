extends RefCounted
## Poses a humanoid Skeleton3D from a BVH pose by matching where each bone points (its own origin to its child's), so
## the BVH's own rest pose (bones along +Z) does not have to match the skeleton's. Twist about a bone is not carried
## (the rest roll is kept); the hips carry the position and a frame from the spine and the two thighs.
## `role_map` is the player's humanoid map: role (Hips, LeftArm, ...) -> bone name on the skeleton.

## [target role, source joint, child role-or-"", source child joint]; an empty source child means "follow the parent".
const CHAINS := [
	["Spine", "spinea", "Spine1", "spineb"],
	["Spine1", "spineb", "Spine2", "spinec"],
	["Spine2", "spinec", "Neck", "neck"],
	["Neck", "neck", "Head", "heada"],
	["LeftShoulder", "l_clavicle", "LeftArm", "l_shoulder"],
	["LeftArm", "l_shoulder", "LeftForeArm", "l_elbow"],
	["LeftForeArm", "l_elbow", "LeftHand", "l_wrist"],
	["LeftHand", "l_wrist", "LeftHandMiddle1", "l_middlea"],
	["RightShoulder", "r_clavicle", "RightArm", "r_shoulder"],
	["RightArm", "r_shoulder", "RightForeArm", "r_elbow"],
	["RightForeArm", "r_elbow", "RightHand", "r_wrist"],
	["RightHand", "r_wrist", "RightHandMiddle1", "r_middlea"],
	["LeftUpLeg", "l_upper_leg", "LeftLeg", "l_knee"],
	["LeftLeg", "l_knee", "LeftFoot", "l_ankle"],
	["LeftFoot", "l_ankle", "LeftToeBase", "l_ball"],
	["LeftToeBase", "l_ball", "", "l_toe"],
	["RightUpLeg", "r_upper_leg", "RightLeg", "r_knee"],
	["RightLeg", "r_knee", "RightFoot", "r_ankle"],
	["RightFoot", "r_ankle", "RightToeBase", "r_ball"],
	["RightToeBase", "r_ball", "", "r_toe"],
]

var skeleton: Skeleton3D
var role_map: Dictionary
var yaw := Basis.IDENTITY ## source world -> the skeleton's world (turns the clip to face where the player faces)
var scale := 1.0
var origin := Vector3.ZERO ## source model-space point placed on the skeleton's origin
var tilt := 0.0 ## radians the body swings back (feet away from where it faces) about `pivot`
var pivot := Vector3.ZERO ## world-aligned, relative to `origin`: where the hands are (they stay put)
var _bone_of: Dictionary = {} ## role -> bone index
var _drive: Dictionary = {} ## bone index -> [source joint, child bone index, source child joint]


func _init(target: Skeleton3D, humanoid_map: Dictionary) -> void:
	skeleton = target
	role_map = humanoid_map
	for role: String in humanoid_map:
		var bone := skeleton.find_bone(String(humanoid_map[role]))
		if bone >= 0:
			_bone_of[role] = bone
	for chain: Array in CHAINS:
		var bone: int = _bone_of.get(chain[0], -1)
		if bone < 0:
			continue
		var child: int = _bone_of.get(chain[2], -1) if chain[2] != "" else -1
		_drive[bone] = [chain[1], child, chain[3]]


func has_roles() -> bool:
	return _bone_of.has("Hips") and _bone_of.has("LeftUpLeg") and _bone_of.has("RightUpLeg") and _bone_of.has("Spine")


## Where the skeleton's own feet point, flat, in world space: the direction the player faces.
func target_forward() -> Vector3:
	var total := Vector3.ZERO
	for pair in [["LeftFoot", "LeftToeBase"], ["RightFoot", "RightToeBase"]]:
		if _bone_of.has(pair[0]) and _bone_of.has(pair[1]):
			var a := skeleton.global_transform * skeleton.get_bone_global_rest(_bone_of[pair[0]]).origin
			var b := skeleton.global_transform * skeleton.get_bone_global_rest(_bone_of[pair[1]]).origin
			total += b - a
	total.y = 0.0
	return total.normalized()


## Source rest leg length over the skeleton's: how much to shrink the clip's positions.
func fit_scale(clip) -> float:
	var upper: int = clip.names.find("l_knee")
	var lower: int = clip.names.find("l_ankle")
	var source_leg: float = clip.offsets[upper].length() + clip.offsets[lower].length()
	var target_leg := 0.0
	if _bone_of.has("LeftUpLeg") and _bone_of.has("LeftLeg") and _bone_of.has("LeftFoot"):
		var up := skeleton.get_bone_global_rest(_bone_of["LeftUpLeg"]).origin
		var knee := skeleton.get_bone_global_rest(_bone_of["LeftLeg"]).origin
		var foot := skeleton.get_bone_global_rest(_bone_of["LeftFoot"]).origin
		target_leg = up.distance_to(knee) + knee.distance_to(foot)
	return target_leg / maxf(source_leg, 0.0001)


## The skeleton-space point of a source (BVH, model space) point. `origin` is the source point that lands on the
## skeleton's own origin (the clip's mover, or wherever the capsule should sit).
func to_skeleton(point: Vector3) -> Vector3:
	var moved: Vector3 = yaw * (point - origin)
	if tilt != 0.0:
		var right := target_forward().cross(Vector3.UP)
		moved = pivot + Basis(right, -tilt) * (moved - pivot)
	return skeleton.global_basis.inverse() * (moved * scale)


## The turn that makes the clip's body face where the skeleton faces at `time` (from the hips: up x right).
func facing_yaw(clip, time: float) -> Basis:
	var source: Array[Transform3D] = clip.pose(time, false)
	var side: Vector3 = source[clip.names.find("r_upper_leg")].origin - source[clip.names.find("l_upper_leg")].origin
	var forward := side.cross(Vector3.UP)
	forward.y = 0.0
	return Basis(Vector3.UP, forward.signed_angle_to(target_forward(), Vector3.UP))


func apply(clip, time: float, loop := true) -> void:
	var source: Array[Transform3D] = clip.pose(time, loop)
	var p := func(joint: String) -> Vector3:
		var i: int = clip.names.find(joint)
		return to_skeleton(source[i].origin) if i >= 0 else Vector3.ZERO
	var globals: Array[Basis] = []
	globals.resize(skeleton.get_bone_count())
	var hips: int = _bone_of["Hips"]
	for bone in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(bone)
		var parent_basis := globals[parent] if parent >= 0 else Basis.IDENTITY
		var rest_global := skeleton.get_bone_global_rest(bone)
		var rest_local := skeleton.get_bone_rest(bone)
		var global := parent_basis * rest_local.basis # not driven: it just follows its parent
		if bone == hips:
			global = _hips_basis(p, rest_global.basis)
			var parent_rest := skeleton.get_bone_global_rest(parent) if parent >= 0 else Transform3D.IDENTITY
			skeleton.set_bone_pose_position(bone, parent_rest.affine_inverse() * p.call("pelvis"))
		elif _drive.has(bone):
			var drive: Array = _drive[bone]
			var child: int = drive[1]
			var from_joint := String(drive[0])
			var to_joint := String(drive[2])
			var wanted: Vector3 = p.call(to_joint) - p.call(from_joint)
			var rest_dir := Vector3.ZERO
			if child >= 0:
				rest_dir = skeleton.get_bone_global_rest(child).origin - rest_global.origin
			else:
				rest_dir = rest_global.origin - skeleton.get_bone_global_rest(skeleton.get_bone_parent(bone)).origin
			if wanted.length() > 0.0001 and rest_dir.length() > 0.0001:
				global = _swing(rest_dir.normalized(), wanted.normalized()) * rest_global.basis
		globals[bone] = global
		skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * global).get_rotation_quaternion())


func _hips_basis(p: Callable, rest: Basis) -> Basis:
	var up: Vector3 = p.call("spinea") - p.call("pelvis")
	var side: Vector3 = p.call("r_upper_leg") - p.call("l_upper_leg")
	var rest_up := skeleton.get_bone_global_rest(_bone_of["Spine"]).origin - skeleton.get_bone_global_rest(_bone_of["Hips"]).origin
	var rest_side := skeleton.get_bone_global_rest(_bone_of["RightUpLeg"]).origin - skeleton.get_bone_global_rest(_bone_of["LeftUpLeg"]).origin
	return _frame(up, side) * _frame(rest_up, rest_side).inverse() * rest


## An orthonormal basis with `up` as Y and `side` (made perpendicular) as X.
func _frame(up: Vector3, side: Vector3) -> Basis:
	var y := up.normalized()
	var x := (side - y * side.dot(y)).normalized()
	return Basis(x, y, x.cross(y))


func _swing(from: Vector3, to: Vector3) -> Basis:
	var axis := from.cross(to)
	if axis.length() < 0.00001:
		return Basis.IDENTITY if from.dot(to) > 0.0 else Basis(from.cross(Vector3.UP if absf(from.y) < 0.9 else Vector3.RIGHT).normalized(), PI)
	return Basis(axis.normalized(), from.angle_to(to))
