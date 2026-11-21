class_name PlayerSlopeClips
extends RefCounted
## Uphill / downhill walk cycles for ramps, built from the DG sample's PSA walks (task 095; game-derived, NOT redistributable:
## stays uncommitted). tools/dg_slope/psa_joints.py turns a PSA into joint positions per frame (a right-handed Y-up space, x = left,
## z = forward); this retargets by DIRECTION, so no source rest pose is needed: every bone is swung from its rest direction onto
## the direction its source segment points, the pelvis from the source pelvis frame, and the hips follow the source height scaled
## by the leg length.

const DIR := "res://assets/models/dg_slope/"
## direction -> [source file, slope (deg) the source walk was authored on (+ uphill), height (m) of its ground under the hips above its origin]. Each is rebuilt for every ANGLES entry by tilting the whole
## clip about the left axis, so the feet meet a ramp of that grade (a 45 deg walk on a 30 deg ramp holds its feet 0.3 m above it).
const SOURCES: Dictionary = {
	&"uphill": ["walk_uphill", 40.0, 0.23],
	&"downhill": ["walk_downhill", -18.0, -0.09],
}
const ANGLES: Array = [15, 30, 45]
const SOURCE_LEG := 0.864 ## thigh + shin of the DG rig (m)
## target role -> [source joint of this bone, source joint it points at] (empty = keeps its rest pose)
const AIMS: Array = [
	["Spine", "spine", "spine2"], ["Spine1", "spine2", "spine4"], ["Spine2", "spine4", "Neck"], ["Neck", "Neck", "Head"],
	["LeftShoulder", "LeftShoulder", "LeftArm"], ["LeftArm", "LeftArm", "LeftForeArm"], ["LeftForeArm", "LeftForeArm", "LeftHand"],
	["RightShoulder", "RightShoulder", "RightArm"], ["RightArm", "RightArm", "RightForeArm"], ["RightForeArm", "RightForeArm", "RightHand"],
	["LeftUpLeg", "LeftUpLeg", "LeftLeg"], ["LeftLeg", "LeftLeg", "LeftFoot"], ["LeftFoot", "LeftFoot", "LeftToeBase"],
	["RightUpLeg", "RightUpLeg", "RightLeg"], ["RightLeg", "RightLeg", "RightFoot"], ["RightFoot", "RightFoot", "RightToeBase"],
]
## target role -> the role that bone points at in the target's rest pose
const REST_CHILD: Dictionary = {
	"Spine": "Spine1", "Spine1": "Spine2", "Spine2": "Neck", "Neck": "Head",
	"LeftShoulder": "LeftArm", "LeftArm": "LeftForeArm", "LeftForeArm": "LeftHand",
	"RightShoulder": "RightArm", "RightArm": "RightForeArm", "RightForeArm": "RightHand",
	"LeftUpLeg": "LeftLeg", "LeftLeg": "LeftFoot", "LeftFoot": "LeftToeBase",
	"RightUpLeg": "RightLeg", "RightLeg": "RightFoot", "RightFoot": "RightToeBase",
}
const KEPT: PackedStringArray = ["Head", "LeftHand", "RightHand", "LeftToeBase", "RightToeBase"]
static var _speeds: Dictionary = {}


static func add_to(library: AnimationLibrary, body: PlayerBody) -> void:
	if body.skeleton == null or body.skeleton.find_bone(&"Hips") >= 0 or not library.has_animation(&"unarmed_walk"):
		return
	for direction: StringName in SOURCES:
		var source: Array = SOURCES[direction]
		var file := FileAccess.open(DIR + String(source[0]) + ".json", FileAccess.READ)
		if file == null:
			continue
		var data := JSON.parse_string(file.get_as_text()) as Dictionary
		for angle: int in ANGLES:
			var target_deg := float(angle) * (1.0 if direction == &"uphill" else -1.0)
			var gameplay_name := clip_name(direction, angle)
			var clip := _build(data, body, gameplay_name, target_deg - float(source[1]), float(source[2]))
			if clip != null:
				library.add_animation(gameplay_name, clip)


static func clip_name(direction: StringName, angle: int) -> StringName:
	return StringName("unarmed_walk_%s_%d" % [direction, angle])


static func is_slope_clip(name: StringName) -> bool:
	return String(name).begins_with("unarmed_walk_uphill_") or String(name).begins_with("unarmed_walk_downhill_")


## The clip whose grade is nearest slope_deg (+ uphill); `current` is kept while it is within 4 deg of the slope (no flapping between grades).
static func clip_for(slope_deg: float, current: StringName) -> StringName:
	var direction := &"uphill" if slope_deg > 0.0 else &"downhill"
	var best := 0
	var best_gap := INF
	for angle: int in ANGLES:
		var gap := absf(absf(slope_deg) - float(angle))
		if current == clip_name(direction, angle) and gap <= 4.0:
			return current
		if gap < best_gap:
			best_gap = gap
			best = angle
	return clip_name(direction, best)


## Ground speed (m/s at 1x) the clip's steps cover.
static func ref_speed(target: StringName) -> float:
	return maxf(float(_speeds.get(target, 1.0)), 0.1)


static func _build(data: Dictionary, body: PlayerBody, gameplay_name: StringName, tilt_deg: float, ground_y: float) -> Animation:
	var skeleton := body.skeleton
	var frames: int = int(data["frames"])
	var fps: float = float(data["fps"])
	var joints := _tilted(data["joints"] as Dictionary, tilt_deg, ground_y)
	var bone := func(role: String) -> int: return skeleton.find_bone(body.resolve_bone_name(StringName(role)))
	var hips: int = bone.call("Hips")
	var left_leg: int = bone.call("LeftUpLeg")
	var right_leg: int = bone.call("RightUpLeg")
	var left_foot: int = bone.call("LeftFoot")
	var left_toe: int = bone.call("LeftToeBase")
	if hips < 0 or left_leg < 0 or right_leg < 0 or left_foot < 0:
		return null
	# the target's own frame: x = its left, y = up, z = forward (a right-handed basis, like the source's)
	var across := skeleton.get_bone_global_rest(left_leg).origin - skeleton.get_bone_global_rest(right_leg).origin
	across.y = 0.0
	var left_t := across.normalized()
	var frame_t := Basis(left_t, Vector3.UP, left_t.cross(Vector3.UP))
	var leg_t := (skeleton.get_bone_global_rest(left_leg).origin - skeleton.get_bone_global_rest(left_foot).origin).length()
	var scale := leg_t / SOURCE_LEG

	var rest_global := {}
	for role: String in REST_CHILD:
		rest_global[role] = skeleton.get_bone_global_rest(bone.call(role)).basis
	var hips_rest := skeleton.get_bone_global_rest(hips)
	var parent := skeleton.get_bone_parent(hips)
	var parent_global := skeleton.get_bone_global_rest(parent) if parent >= 0 else Transform3D.IDENTITY

	var clip := Animation.new()
	clip.length = float(frames - 1) / fps
	clip.loop_mode = Animation.LOOP_LINEAR
	var tracks := {}
	var names: Array = []
	for aim: Array in AIMS:
		names.append(aim[0])
	for role: String in KEPT:
		names.append(role)
	names.append("Hips")
	for role: String in names:
		var track := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(track, NodePath(String(skeleton.name) + ":" + String(body.resolve_bone_name(StringName(role)))))
		tracks[role] = track
	var position_track := clip.add_track(Animation.TYPE_POSITION_3D)
	clip.track_set_path(position_track, NodePath(String(skeleton.name) + ":" + String(body.resolve_bone_name(&"Hips"))))

	var mean_x := 0.0
	for f in frames:
		mean_x += _joint(joints, "Hips", f).x
	mean_x /= frames
	var rest_hips_world := hips_rest.origin
	for f in frames:
		var time := float(f) / fps
		# pelvis: the source frame (left across the hips, up toward the chest) swung into the target's
		var lateral := (_joint(joints, "LeftUpLeg", f) - _joint(joints, "RightUpLeg", f)).normalized()
		var up_s := (_joint(joints, "spine4", f) - _joint(joints, "Hips", f)).normalized()
		var forward_s := lateral.cross(up_s).normalized()
		var pelvis_s := Basis(lateral, forward_s.cross(lateral).normalized(), forward_s)
		var global := {}
		global["Hips"] = frame_t * pelvis_s * frame_t.inverse() * hips_rest.basis
		var hips_origin: Vector3 = _joint(joints, "Hips", f)
		var world := Vector3(rest_hips_world.x, hips_origin.y * scale, rest_hips_world.z) \
				+ frame_t * Vector3(hips_origin.x - mean_x, 0.0, hips_origin.z) * scale
		clip.position_track_insert_key(position_track, time, parent_global.affine_inverse() * world)
		clip.rotation_track_insert_key(tracks["Hips"], time, (parent_global.basis.inverse() * (global["Hips"] as Basis)).get_rotation_quaternion())
		for aim: Array in AIMS:
			var role: String = aim[0]
			var direction_s := (_joint(joints, aim[2], f) - _joint(joints, aim[1], f)).normalized()
			var rest_dir := _rest_direction(skeleton, body, role, REST_CHILD[role])
			var swing := Quaternion(rest_dir, frame_t * direction_s)
			global[role] = Basis(swing) * (rest_global[role] as Basis)
			var bone_index: int = bone.call(role)
			var parent_basis := _global_basis(skeleton, body, skeleton.get_bone_parent(bone_index), global)
			clip.rotation_track_insert_key(tracks[role], time, (parent_basis.inverse() * (global[role] as Basis)).get_rotation_quaternion())
		for role: String in KEPT:
			clip.rotation_track_insert_key(tracks[role], time, skeleton.get_bone_rest(bone.call(role)).basis.get_rotation_quaternion())
	_speeds[gameplay_name] = _ground_speed(joints, frames, clip.length) * scale
	return clip


## The joints with the hips' mean z and the ground height taken out, then pitched by tilt_deg about the ground point under them (the left axis).
static func _tilted(joints: Dictionary, tilt_deg: float, ground_y: float) -> Dictionary:
	var mean_z := 0.0
	var hips: Array = joints["Hips"]
	for p: Array in hips:
		mean_z += float(p[2])
	mean_z /= hips.size()
	var c := cos(deg_to_rad(tilt_deg))
	var s := sin(deg_to_rad(tilt_deg))
	var out := {}
	for joint_name: String in joints:
		var rotated: Array = []
		for p: Array in joints[joint_name]:
			var y := float(p[1]) - ground_y
			var z := float(p[2]) - mean_z
			rotated.append([float(p[0]), y * c + z * s, z * c - y * s])
		out[joint_name] = rotated
	return out


static func _joint(joints: Dictionary, name: String, frame: int) -> Vector3:
	var p: Array = (joints[name] as Array)[frame]
	return Vector3(p[0], p[1], p[2])


static func _rest_direction(skeleton: Skeleton3D, body: PlayerBody, role: String, child_role: String) -> Vector3:
	var from := skeleton.get_bone_global_rest(skeleton.find_bone(body.resolve_bone_name(StringName(role)))).origin
	var to := skeleton.get_bone_global_rest(skeleton.find_bone(body.resolve_bone_name(StringName(child_role)))).origin
	return (to - from).normalized()


## A bone's global basis in the clip being built: an aimed bone's own, else its parent's with its rest.
static func _global_basis(skeleton: Skeleton3D, body: PlayerBody, bone: int, built: Dictionary) -> Basis:
	if bone < 0:
		return Basis.IDENTITY
	for role: String in built:
		if skeleton.find_bone(body.resolve_bone_name(StringName(role))) == bone:
			return built[role]
	return _global_basis(skeleton, body, skeleton.get_bone_parent(bone), built) * skeleton.get_bone_rest(bone).basis


## How fast the body goes: each foot's travel along z relative to the hips, covered four times per clip (two strides, two steps each).
static func _ground_speed(joints: Dictionary, frames: int, length: float) -> float:
	var total := 0.0
	for side: String in ["Left", "Right"]:
		var low := INF
		var high := -INF
		for f in frames:
			var z := _joint(joints, side + "Foot", f).z - _joint(joints, "Hips", f).z
			low = minf(low, z)
			high = maxf(high, z)
		total += (high - low) * 4.0 / length # the DG clips hold two strides: each foot covers its excursion twice
	return total / 2.0
