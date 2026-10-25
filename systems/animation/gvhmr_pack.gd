class_name GvhmrPack
## The animation pack made from generated video (AGENT_TASKS/089): GVHMR motion clips as json (tools/gvhmr/run_clip.py writes
## assets/animation/gvhmr_pack/json/<Name>.json and _contacts.json), retargeted at run time onto any humanoid skeleton.
## catalog.json (tools/gvhmr/make_catalog.py) lists the clips with their rating, category, loop and root-motion flags.

const DIR := "res://assets/animation/gvhmr_pack/"


## The catalog entries: {name, category, rating (ok|usable|weak|failed), loop, in_place, speed, hands}.
static func catalog() -> Array:
	var path := DIR + "catalog.json"
	if not FileAccess.file_exists(path):
		return []
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Adds the catalog clips with one of `ratings` to `library` as "gvhmr_<Name>", retargeted onto `target_skeleton`
## (`humanoid_map` is a catalog character's role -> bone name map). Returns how many were added.
static func add_to(library: AnimationLibrary, target_skeleton: Skeleton3D, humanoid_map: Dictionary,
		ratings: PackedStringArray = ["ok", "usable"]) -> int:
	var added := 0
	for entry: Dictionary in catalog():
		if not ratings.has(String(entry.get("rating", ""))):
			continue
		var clip := retarget(DIR + "json/%s.json" % entry["name"], target_skeleton, humanoid_map, {
			"contacts": DIR + "json/%s_contacts.json" % entry["name"],
			"speed": float(entry.get("speed", 0.0)), "inplace": bool(entry.get("in_place", false)),
			"hands": String(entry.get("hands", "relaxed")), "force_loop": bool(entry.get("loop", false)),
		})
		library.add_animation(StringName("gvhmr_" + String(entry["name"])), clip)
		added += 1
	return added


## One clip (a smplx_motion_to_json.py file) retargeted onto `target_skeleton`. options: speed (m/s, 0 keeps GVHMR's),
## inplace, hands ("relaxed" | "fist" | ""), contacts (foot_report.py's json path), force_loop.
static func retarget(source_json: String, target_skeleton: Skeleton3D, humanoid_map: Dictionary, options: Dictionary) -> Animation:
	var clip := SmplxJsonSource.load_clip(source_json)
	var source_skeleton: Skeleton3D = clip["skeleton"]
	var animation: Animation = clip["animation"]
	var map := humanoid_map
	var config := HumanoidRetargeter.build_bone_map_config(RetargetSmplx.ROLE_MAP, map)
	# parents before children; the fourth entry is the child bone the direction runs to
	var chains: Array = [
		["pelvis", "spine1", map["Hips"], map["Spine"]], ["spine1", "spine2", map["Spine"], map["Spine1"]],
		["spine2", "spine3", map["Spine1"], map["Spine2"]], ["spine3", "neck", map["Spine2"], map["Neck"]],
		["twist", "left_collar", "right_collar", map["LeftShoulder"], map["RightShoulder"], map["Spine2"], map["Neck"]],
		["neck", "head", map["Neck"], map["Head"]],
	]
	for side: Array in [["left", "Left"], ["right", "Right"]]:
		var lo: String = side[0]
		var hi: String = side[1]
		chains.append([lo + "_hip", lo + "_knee", map[hi + "UpLeg"], map[hi + "Leg"]])
		chains.append([lo + "_knee", lo + "_ankle", map[hi + "Leg"], map[hi + "Foot"]])
		chains.append([lo + "_collar", lo + "_shoulder", map[hi + "Shoulder"], map[hi + "Arm"]])
		chains.append([lo + "_shoulder", lo + "_elbow", map[hi + "Arm"], map[hi + "ForeArm"]])
		chains.append([lo + "_elbow", lo + "_wrist", map[hi + "ForeArm"], map[hi + "Hand"]])
	var foot_lock := {}
	var contacts_path := String(options.get("contacts", ""))
	if contacts_path != "" and FileAccess.file_exists(contacts_path):
		var contacts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(contacts_path))
		foot_lock = {"planted": contacts["planted"], "fps": contacts["fps"], "blend": 3, "legs": [
			[map["LeftUpLeg"], map["LeftLeg"], map["LeftFoot"]], [map["RightUpLeg"], map["RightLeg"], map["RightFoot"]]]}
	var hips_args := ["left_hip", "right_hip", map["LeftUpLeg"], map["RightUpLeg"]]
	var force_loop: bool = options.get("force_loop", false)
	var result := HumanoidRetargeter.retarget_clip(source_skeleton, animation, target_skeleton, config,
			force_loop, false, chains, hips_args, {})
	var wanted_speed := float(options.get("speed", 0.0))
	if wanted_speed > 0.0: # GVHMR's static-camera travel under-reads: rescale the hips' horizontal travel to a target m/s
		var measured := _hips_speed(result)
		if measured >= 0.05:
			_scale_source_travel(animation, wanted_speed / measured) # (the source track: the foot lock then sees the final motion)
	result = HumanoidRetargeter.retarget_clip(source_skeleton, animation, target_skeleton, config,
			force_loop, false, chains, hips_args, foot_lock)
	if options.get("inplace", false):
		HumanoidRetargeter.make_clip_in_place(result)
	var hands := String(options.get("hands", ""))
	if hands != "":
		HandPresets.apply(result, target_skeleton, map, hands)
	source_skeleton.free()
	return result


static func _hips_speed(animation: Animation) -> float:
	for track in animation.get_track_count():
		if animation.track_get_type(track) == Animation.TYPE_POSITION_3D and animation.track_get_key_count(track) >= 2:
			var first: Vector3 = animation.track_get_key_value(track, 0)
			var last: Vector3 = animation.track_get_key_value(track, animation.track_get_key_count(track) - 1)
			return Vector2(last.x - first.x, last.z - first.z).length() / maxf(animation.length, 0.001)
	return 0.0


## Scales the horizontal travel of the first position track (the pelvis) about its first key.
static func _scale_source_travel(animation: Animation, factor: float) -> void:
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		var first: Vector3 = animation.track_get_key_value(track, 0)
		for key in animation.track_get_key_count(track):
			var v: Vector3 = animation.track_get_key_value(track, key)
			animation.track_set_key_value(track, key, Vector3(first.x + (v.x - first.x) * factor, v.y,
					first.z + (v.z - first.z) * factor))
		return
