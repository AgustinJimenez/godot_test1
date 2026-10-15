class_name PlayerHandHoldIKModifier
extends SkeletonModifier3D
## Reaches the hands (and feet) to world-space hold points (a ledge, wall bricks, balance arms): the
## same two-bone solve as the legs (FootIKV2Solver) on shoulder - elbow - wrist, or hip - knee -
## ankle. `targets` / `foot_targets` map &"left" / &"right" to a world position, `weight` /
## `foot_weight` 0..1 fade them. Runs after the animation, so it works with whatever the limbs were
## doing; the elbow points out and down, the knee away from `knee_way` (a world direction).

const ARMS := {
	&"left": [&"LeftArm", &"LeftForeArm", &"LeftHand"],
	&"right": [&"RightArm", &"RightForeArm", &"RightHand"],
}
const LEGS := {
	&"left": [&"LeftUpLeg", &"LeftLeg", &"LeftFoot"],
	&"right": [&"RightUpLeg", &"RightLeg", &"RightFoot"],
}
const ELBOW_OUT := 0.9 # how far the elbow points sideways (vs down) when the arm is reaching up

var player_body: PlayerBody
var targets: Dictionary = {}
var weight := 0.0
var foot_targets: Dictionary = {}
var foot_weight := 0.0
var knee_way := Vector3.BACK # world direction the knees point (away from a wall)
var debug_wrist: Dictionary = {} # side -> wrist (world) as left by the last pass, for the labs
var debug_ankle: Dictionary = {}
var _bones: Dictionary = {}
var _leg_bones: Dictionary = {}


func arm_reach() -> float:
	_find_bones()
	var skel := get_skeleton()
	if skel == null or not _bones.has(&"left"):
		return 0.0
	var bones: Array = _bones[&"left"]
	return (skel.get_bone_global_rest(bones[0]).origin.distance_to(
			skel.get_bone_global_rest(bones[1]).origin)
			+ skel.get_bone_global_rest(bones[1]).origin.distance_to(
			skel.get_bone_global_rest(bones[2]).origin))


## Height of the shoulders above the skeleton origin in the rest pose.
func shoulder_height() -> float:
	_find_bones()
	var skel := get_skeleton()
	if skel == null or not _bones.has(&"left"):
		return 0.0
	return skel.get_bone_global_rest((_bones[&"left"] as Array)[0]).origin.y


func _find_bones() -> void:
	var skel := get_skeleton()
	if skel == null or player_body == null or not _bones.is_empty():
		return
	for pair: Array in [[ARMS, _bones], [LEGS, _leg_bones]]:
		for side: StringName in pair[0]:
			var found: Array[int] = []
			for role: StringName in (pair[0] as Dictionary)[side]:
				found.append(skel.find_bone(player_body.resolve_bone_name(role)))
			if not found.has(-1):
				(pair[1] as Dictionary)[side] = found


func _process_modification_with_delta(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or (weight <= 0.0 and foot_weight <= 0.0):
		return
	_find_bones()
	var to_local := skel.global_transform.affine_inverse()
	for side: StringName in targets:
		if weight > 0.0 and _bones.has(side):
			var outward := Vector3(signf(skel.get_bone_global_pose(_bones[side][0]).origin.x), 0.0, 0.0)
			if is_zero_approx(outward.x):
				outward.x = 1.0 if side == &"right" else -1.0
			var way := (outward * ELBOW_OUT + Vector3.DOWN * (1.0 - ELBOW_OUT)).normalized()
			debug_wrist[side] = _reach(skel, _bones[side], to_local * (targets[side] as Vector3),
					weight, way, outward + Vector3.DOWN * 0.2)
	for side: StringName in foot_targets:
		if foot_weight > 0.0 and _leg_bones.has(side):
			var way := (to_local.basis * knee_way).normalized()
			debug_ankle[side] = _reach(skel, _leg_bones[side],
					to_local * (foot_targets[side] as Vector3), foot_weight, way, way)


## Two-bone reach of `bones` (root, mid, end) toward `target` (skeleton space); the mid joint
## bends toward `way`. Returns the end joint's world position afterwards.
func _reach(skel: Skeleton3D, bones: Array, target: Vector3, amount: float, way: Vector3,
		rest_pole: Vector3) -> Vector3:
	var root := skel.get_bone_global_pose(bones[0]).origin
	var mid := skel.get_bone_global_pose(bones[1]).origin
	var end := skel.get_bone_global_pose(bones[2]).origin
	var solved := FootIKV2Solver.solve(root, root + way, end.lerp(target, amount),
			root.distance_to(mid), mid.distance_to(end), rest_pole)
	_aim(skel, bones[0], bones[1], solved["knee"] as Vector3)
	_aim(skel, bones[1], bones[2], solved["ankle"] as Vector3)
	return skel.global_transform * skel.get_bone_global_pose(bones[2]).origin


func _aim(skel: Skeleton3D, bone: int, child: int, target: Vector3) -> void:
	var pose := skel.get_bone_global_pose(bone)
	var from := skel.get_bone_global_pose(child).origin - pose.origin
	var to := target - pose.origin
	if from.length_squared() < 0.0000001 or to.length_squared() < 0.0000001:
		return
	pose.basis = Basis(Quaternion(from.normalized(), to.normalized())) * pose.basis
	skel.set_bone_global_pose(bone, pose)
