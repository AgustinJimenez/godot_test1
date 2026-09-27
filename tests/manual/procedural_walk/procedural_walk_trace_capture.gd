class_name ProceduralWalkTraceCapture
extends RefCounted
## Bounded, one-record-per-physics-frame trace of the course's published final pose.

const LOG_PATH := "user://procedural_walk_course.jsonl"
const MAX_FRAMES := 1800
const JOINTS: Array[StringName] = [
	&"LeftUpLeg", &"LeftLeg", &"LeftFoot", &"LeftToeBase",
	&"RightUpLeg", &"RightLeg", &"RightFoot", &"RightToeBase",
]

var _writer: FootIkTraceWriter
var _course_id := 0
var _last_tick := -1
var _frame := 0
var _last_root := Vector3.ZERO
var _last_rotations: Dictionary = {}
var _last_contacts: Dictionary = {}
var _last_targets: Dictionary = {}
var _last_section := ""
var _pending: Dictionary = {}
var _pending_rotations: Dictionary = {}
var _pending_contacts: Dictionary = {}
var _pending_targets: Dictionary = {}
var _pending_section := ""
var _pending_root := Vector3.ZERO
var _finished := false


func capture(character: Node3D, skeleton: Skeleton3D,
		modifier: ProceduralWalkLabModifier, course: ProceduralWalkStairCourse,
		mode: StringName) -> void:
	if course == null or character == null or skeleton == null or modifier == null:
		return
	var tick := Engine.get_physics_frames()
	if modifier.debug_pose_frame != tick:
		return
	if _course_id != course.get_instance_id():
		_start(course)
	if _finished:
		return
	if _last_tick != tick:
		flush()
		if course.is_finished(_last_root.z):
			_finished = true
			return
		_last_tick = tick
	if _frame >= MAX_FRAMES:
		return
	var root := character.global_position
	var distance := course.start_z - root.z
	var section := _section(distance)
	var events: Array[String] = []
	if section != _last_section:
		events.append("section:%s" % section)
	var joint_deltas := {}
	var joint_rotations := {}
	var next_rotations := {}
	var worst_joint := ""
	var worst_deg := 0.0
	for name: StringName in JOINTS:
		var rotation: Quaternion = modifier.debug_joint_rotations.get(name, Quaternion.IDENTITY)
		var key := String(name)
		joint_rotations[key] = _quat(rotation)
		if _last_rotations.has(key):
			var prior: Quaternion = _last_rotations[key]
			var delta := rad_to_deg(prior.angle_to(rotation))
			joint_deltas[key] = snappedf(delta, 0.01)
			if delta > worst_deg:
				worst_deg = delta
				worst_joint = key
		next_rotations[key] = rotation
	var feet := {}
	var next_contacts := _last_contacts.duplicate()
	var next_targets := _last_targets.duplicate()
	for side in 2:
		var label := "Left" if side == 0 else "Right"
		var ankle: Vector3 = modifier.debug_joint_positions.get(
				StringName(label + "Foot"), Vector3.ZERO)
		var toe: Vector3 = modifier.debug_joint_positions.get(
				StringName(label + "ToeBase"), Vector3.ZERO)
		var planted := modifier.has_plant(side)
		var weight := float(modifier.debug_contact_weight.get(label, 0.0))
		var in_contact := planted if mode in [&"", &"stair_up"] else weight >= 0.8
		var target := _contact_target(modifier, mode, side)
		var target_valid := target != Vector3.INF
		var target_key := label + "_target"
		var contact_key := label + "_contact"
		if _last_contacts.has(contact_key) and _last_contacts[contact_key] != in_contact:
			events.append("%s:%s" % [label.to_lower(),
					"plant" if in_contact else "release"])
		if target_valid and _last_targets.has(target_key) \
				and (_last_targets[target_key] as Vector3).distance_to(target) > 0.05:
			events.append("%s:target_changed" % label.to_lower())
		next_contacts[contact_key] = in_contact
		if target_valid:
			next_targets[target_key] = target
		feet[label.to_lower()] = {
			"source_knee": _vec(modifier.debug_source_knee.get(label, Vector3.ZERO)),
			"hip": _vec(modifier.debug_joint_positions.get(
					StringName(label + "UpLeg"), Vector3.ZERO)),
			"knee": _vec(modifier.debug_joint_positions.get(
					StringName(label + "Leg"), Vector3.ZERO)),
			"ankle": _vec(ankle), "toe": _vec(toe),
			"target": _vec(target) if target_valid else null,
			"contact": in_contact, "plant": planted,
			"contact_weight": snappedf(weight, 0.001),
			"target_error": snappedf(float(modifier.debug_target_error.get(label, 0.0)), 0.0001),
			"shoe_corrections": int(modifier.debug_shoe_corrections.get(label, 0)),
			"shoe_required_y": snappedf(float(modifier.debug_shoe_required_y.get(
					label, 0.0)), 0.0001),
			"knee_flex_deg": snappedf(float(modifier.debug_knee_flex.get(label, 0.0)), 0.01),
			"ankle_support": snappedf(course.support_height(ankle.z), 0.0001),
			"toe_support": snappedf(course.support_height(toe.z), 0.0001),
		}
	_pending = {
		"frame": _frame, "physics_frame": tick, "mode": String(mode),
		"phase": snappedf(fposmod(modifier.phase / TAU, 1.0), 0.0001),
		"root": _vec(root), "root_delta": _vec(root - _last_root) if _frame > 0 else null,
		"pose_root": _vec(modifier.debug_root_position),
		"reference_hips_y": snappedf(modifier.debug_reference_hips_y, 0.0001),
		"floor_clearance": snappedf(modifier.debug_floor_clearance, 0.0001),
		"pelvis_drop": snappedf(modifier.debug_pelvis_drop, 0.0001),
		"course_distance": snappedf(distance, 0.0001), "section": section,
		"worst_joint": worst_joint, "worst_joint_deg": snappedf(worst_deg, 0.01),
		"joint_delta_deg": joint_deltas, "joint_rotations": joint_rotations,
		"feet": feet, "events": events,
	}
	_pending_rotations = next_rotations
	_pending_contacts = next_contacts
	_pending_targets = next_targets
	_pending_section = section
	_pending_root = root


func flush() -> void:
	if _pending.is_empty() or _writer == null:
		return
	_writer.capture(JSON.stringify(_pending))
	_frame += 1
	_last_root = _pending_root
	_last_rotations = _pending_rotations
	_last_contacts = _pending_contacts
	_last_targets = _pending_targets
	_last_section = _pending_section
	_pending = {}


func _start(course: ProceduralWalkStairCourse) -> void:
	_course_id = course.get_instance_id()
	_writer = FootIkTraceWriter.new(LOG_PATH, MAX_FRAMES)
	_frame = 0
	_last_tick = -1
	_last_root = Vector3.ZERO
	_last_rotations.clear()
	_last_contacts.clear()
	_last_targets.clear()
	_last_section = ""
	_pending = {}
	_finished = false
	print("[PROCEDURAL_TRACE] %s" % ProjectSettings.globalize_path(LOG_PATH))


func _contact_target(modifier: ProceduralWalkLabModifier,
		mode: StringName, side: int) -> Vector3:
	if mode in [&"walk", &"walk_aim", &"sprint", &"crouch"]:
		var valid: Array[bool] = modifier.get("_source_contact_valid")
		var targets: Array[Vector3] = modifier.get("_source_contact_targets")
		return targets[side] if valid[side] else Vector3.INF
	return modifier.plant_world(side) if modifier.has_plant(side) else Vector3.INF


func _section(distance: float) -> String:
	var run := float(ProceduralWalkStairCourse.STEP_COUNT) \
			* ProceduralWalkStairCourse.STEP_DEPTH
	if distance < 0.0:
		return "approach"
	if distance < run:
		return "up"
	if distance < run + ProceduralWalkStairCourse.TOP_LENGTH:
		return "top"
	if distance < run * 2.0 + ProceduralWalkStairCourse.TOP_LENGTH:
		return "down"
	return "exit"


func _vec(value: Vector3) -> Array[float]:
	return [snappedf(value.x, 0.0001), snappedf(value.y, 0.0001),
			snappedf(value.z, 0.0001)]


func _quat(value: Quaternion) -> Array[float]:
	return [snappedf(value.x, 0.00001), snappedf(value.y, 0.00001),
			snappedf(value.z, 0.00001), snappedf(value.w, 0.00001)]
