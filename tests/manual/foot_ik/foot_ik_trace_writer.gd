class_name FootIkTraceWriter
extends RefCounted
## Maintains a recent JSONL window without rewriting the whole file each frame.

const COMPACT_INTERVAL := 300
const BODY_CHAIN_ROLES: Array[StringName] = [
	&"Hips", &"Spine", &"Spine1", &"Spine2", &"Neck", &"Head",
	&"LeftShoulder", &"LeftArm", &"LeftForeArm", &"LeftHand",
	&"RightShoulder", &"RightArm", &"RightForeArm", &"RightHand",
]

var _path: String
var _maximum_lines: int
var _lines: Array[String] = []
var _capture_count := 0


func _init(path: String, maximum_lines: int) -> void:
	_path = path
	_maximum_lines = maximum_lines


func capture(line: String) -> void:
	_lines.append(line)
	if _lines.size() > _maximum_lines:
		_lines.pop_front()
	_capture_count += 1
	var compact := _lines.size() == _maximum_lines and _capture_count % COMPACT_INTERVAL == 0
	var mode := FileAccess.WRITE if _capture_count == 1 or compact else FileAccess.READ_WRITE
	var file := FileAccess.open(_path, mode)
	if file == null:
		return
	if mode == FileAccess.READ_WRITE:
		file.seek_end()
		file.store_line(line)
	else:
		for recent_line: String in _lines:
			file.store_line(recent_line)
	file.close()


static func capture_joint_transforms(probes: Dictionary) -> Dictionary:
	var result := {}
	for joint: String in probes:
		var probe: Node3D = probes[joint]
		if probe == null:
			continue
		var xform := probe.global_transform
		result[joint] = {
			"position": xform.origin, "scale": xform.basis.get_scale(),
			"rotation_deg": xform.basis.get_euler() * (180.0 / PI),
			"rotation_quaternion": xform.basis.orthonormalized().get_rotation_quaternion(),
		}
	return result


static func measure_bone_lengths(joints: Dictionary, references: Dictionary) -> Dictionary:
	var upper_reference := float(references.get("upper", 0.0))
	var lower_reference := float(references.get("lower", 0.0))
	var upper := 0.0
	var lower := 0.0
	if joints.has("hip") and joints.has("knee") and joints.has("foot"):
		var hip := joints["hip"] as Dictionary
		var knee := joints["knee"] as Dictionary
		var foot := joints["foot"] as Dictionary
		upper = (hip["position"] as Vector3).distance_to(knee["position"] as Vector3)
		lower = (knee["position"] as Vector3).distance_to(foot["position"] as Vector3)
	return {
		"upper": upper, "upper_reference": upper_reference,
		"upper_ratio": upper / upper_reference if upper_reference > 0.0 else 0.0,
		"lower": lower, "lower_reference": lower_reference,
		"lower_ratio": lower / lower_reference if lower_reference > 0.0 else 0.0,
	}


## Captures the connected center/arm chains around the already detailed leg
## trace. PlayerLookPoseModifier caches this same complete chain so no sample
## mixes a final modified child with a Skeleton3D-restored parent. Root-relative
## poses separate skeletal motion from travel; parent ratios expose stretch.
static func capture_body_chain(player_body: PlayerBody) -> Dictionary:
	var skeleton := player_body.skeleton
	if skeleton == null:
		return {}
	var result := {}
	var body_inverse := player_body.global_transform.affine_inverse()
	for role: StringName in BODY_CHAIN_ROLES:
		var bone_idx := skeleton.find_bone(player_body.resolve_bone_name(role))
		if bone_idx < 0:
			continue
		var visual_pose := player_body.get_visual_bone_global_pose(bone_idx)
		var world_pose := player_body.global_transform * visual_pose
		var relative_basis := (body_inverse.basis * world_pose.basis).orthonormalized()
		var parent_idx := skeleton.get_bone_parent(bone_idx)
		var parent_length := 0.0
		var parent_rest_length := 0.0
		var parent_name := StringName()
		if parent_idx >= 0:
			parent_name = skeleton.get_bone_name(parent_idx)
			var parent_pose := player_body.get_visual_bone_global_pose(parent_idx)
			parent_length = visual_pose.origin.distance_to(parent_pose.origin)
			parent_rest_length = skeleton.get_bone_global_rest(bone_idx).origin.distance_to(
					skeleton.get_bone_global_rest(parent_idx).origin)
		result[String(role)] = {
			"position": world_pose.origin,
			"root_relative_position": body_inverse * world_pose.origin,
			"scale": world_pose.basis.get_scale(),
			"rotation_deg": world_pose.basis.get_euler() * (180.0 / PI),
			"rotation_quaternion": world_pose.basis.orthonormalized().get_rotation_quaternion(),
			"root_relative_rotation_deg": relative_basis.get_euler() * (180.0 / PI),
			"root_relative_rotation_quaternion": relative_basis.get_rotation_quaternion(),
			"parent_bone": parent_name,
			"parent_length": parent_length,
			"parent_rest_length": parent_rest_length,
			"parent_length_ratio": (
					parent_length / parent_rest_length if parent_rest_length > 0.0 else 0.0),
		}
	return result
