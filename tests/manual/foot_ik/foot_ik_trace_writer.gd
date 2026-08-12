class_name FootIkTraceWriter
extends RefCounted
## Maintains a recent JSONL window without rewriting the whole file each frame.

const COMPACT_INTERVAL := 300

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
