class_name ProceduralWalkMetrics
extends RefCounted
## Bounded, per-physics-frame comparison of procedural and source poses.

const MAX_SAMPLES := 240

var _stream: FileAccess
var _mode := &""
var _sample_count := 0
var _last_tick := -1
var _previous_procedural: Array[Transform3D] = []
var _previous_reference: Array[Transform3D] = []
var latest: Dictionary = {}


func start(mode: StringName) -> void:
	close()
	_mode = mode
	_sample_count = 0
	_last_tick = -1
	_previous_procedural.clear()
	_previous_reference.clear()
	latest.clear()
	var name := "original" if mode == &"" else String(mode)
	_stream = FileAccess.open("user://procedural_walk_metrics_%s.jsonl" % name,
			FileAccess.WRITE)
	if _stream == null:
		push_error("Procedural walk lab: could not open metrics log for %s" % name)


func close() -> void:
	if _stream != null:
		_stream.flush()
		_stream.close()
		_stream = null


func observe(frame: int, phase: float, moving: bool, root_z: float,
		procedural: ProceduralWalkLabModifier, skeleton: Skeleton3D,
		reference: Skeleton3D) -> Dictionary:
	var tick := Engine.get_physics_frames()
	if tick == _last_tick or procedural.debug_bone_poses.size() != skeleton.get_bone_count():
		return latest
	_last_tick = tick
	var output := {
		"frame": frame,
		"phase": snappedf(phase, 0.0001),
		"mode": "original" if _mode == &"" else String(_mode),
		"moving": moving,
		"root_z": snappedf(root_z, 0.0001),
		"worst_pose_deg": 0.0,
		"worst_pose_joint": "",
		"worst_procedural_step_deg": 0.0,
		"worst_procedural_step_joint": "",
		"worst_reference_step_deg": 0.0,
		"joints": {},
		"knee_flex": procedural.debug_knee_flex.duplicate(),
		"ankle_target_error": procedural.debug_target_error.duplicate(),
	}
	var current_reference: Array[Transform3D] = []
	for index in skeleton.get_bone_count():
		current_reference.append(
				reference.get_bone_global_pose(index) if reference != null
				else Transform3D.IDENTITY)
	for index in skeleton.get_bone_count():
		var name := skeleton.get_bone_name(index)
		var pose: Transform3D = procedural.debug_bone_poses[index]
		var proc_rotation := pose.basis.get_rotation_quaternion()
		var ref_rotation := current_reference[index].basis.get_rotation_quaternion()
		var pose_error := (
				rad_to_deg(proc_rotation.angle_to(ref_rotation)) if reference != null else 0.0)
		var proc_step := 0.0
		var ref_step := 0.0
		if _previous_procedural.size() == skeleton.get_bone_count():
			proc_step = rad_to_deg(proc_rotation.angle_to(
					_previous_procedural[index].basis.get_rotation_quaternion()))
		if reference != null and _previous_reference.size() == skeleton.get_bone_count():
			ref_step = rad_to_deg(ref_rotation.angle_to(
					_previous_reference[index].basis.get_rotation_quaternion()))
		output["joints"][String(name)] = {
			"pose_deg": snappedf(pose_error, 0.01),
			"procedural_step_deg": snappedf(proc_step, 0.01),
			"reference_step_deg": snappedf(ref_step, 0.01),
		}
		if pose_error > output["worst_pose_deg"]:
			output["worst_pose_deg"] = pose_error
			output["worst_pose_joint"] = String(name)
		if proc_step > output["worst_procedural_step_deg"]:
			output["worst_procedural_step_deg"] = proc_step
			output["worst_procedural_step_joint"] = String(name)
		output["worst_reference_step_deg"] = maxf(
				output["worst_reference_step_deg"], ref_step)
	_previous_procedural = procedural.debug_bone_poses.duplicate()
	_previous_reference = current_reference
	latest = output
	if _stream != null and _sample_count < MAX_SAMPLES:
		_stream.store_line(JSON.stringify(output))
		_sample_count += 1
		if _sample_count == MAX_SAMPLES:
			close()
	return output
