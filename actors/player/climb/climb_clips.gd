class_name ClimbClips
extends RefCounted
## The hang clips (Mixamo FBX in assets/models/imported_animations/, retargeted at start-up onto
## the player's skeleton the way the other Mixamo clips are): `climb_hang_idle` hanging from a
## ledge, `climb_hang_grab` the jump that catches it, `climb_up` the pull-up from a hang to
## standing on top (played backwards it is the lowering into a hang).
## The source clips carry the whole body travel in the hips track; here the travel is moved out of
## the pose and into `path()`, the way the capsule has to move, so the capsule and the camera
## follow the body. The world pose stays the clip's own: capsule + pose hips = clip hips.

const DIR := "res://assets/models/imported_animations/"
const IDLE := &"climb_hang_idle"
const GRAB := &"climb_hang_grab"
const UP := &"climb_up"
const FILES := {IDLE: "hanging_idle", GRAB: "jumping_to_hanging", UP: "freehang_climb"}
## Where in the clip (0..1) the pose hips settle from the hanging height to the standing height.
const SETTLE_FROM := 0.45
const SETTLE_TO := 0.95

static var _paths: Dictionary = {} # clip -> [times, offsets]


## Adds the clips to `library`. `stand_hips` is the pose's hips position while standing idle.
static func add_to(library: AnimationLibrary, skeleton: Skeleton3D, humanoid_map: Dictionary,
		stand_hips: Vector3, owner: Node3D) -> bool:
	var retargeted := {}
	for clip: StringName in FILES:
		var anim := _retarget(DIR + FILES[clip] + ".fbx", skeleton, humanoid_map, clip == IDLE)
		if anim == null or hips_track(anim) < 0:
			return false
		retargeted[clip] = anim
	var idle: Animation = retargeted[IDLE]
	var hang_hips: Vector3 = idle.track_get_key_value(hips_track(idle), 0)
	var pelvis := skeleton.find_bone(String(idle.track_get_path(hips_track(idle))).get_slice(":", 1))
	var parent := skeleton.get_bone_parent(pelvis)
	var frame := owner.global_basis.inverse() * skeleton.global_basis
	if parent >= 0:
		frame *= skeleton.get_bone_global_rest(parent).basis
	for clip: StringName in FILES:
		var anim: Animation = retargeted[clip]
		if clip != IDLE:
			_move_travel(clip, anim, stand_hips, hang_hips, frame)
		if library.has_animation(clip):
			library.remove_animation(clip)
		library.add_animation(clip, anim)
	return true


static func _retarget(path: String, skeleton: Skeleton3D, humanoid_map: Dictionary,
		looping: bool) -> Animation:
	var root := (load(path) as PackedScene).instantiate()
	var player := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var source_skeleton := root.find_child("Skeleton3D", true, false) as Skeleton3D
	var result: Animation = null
	if player != null and source_skeleton != null and not player.get_animation_list().is_empty():
		var prefix = HumanoidRetargeter.detect_bone_prefix(source_skeleton)
		var config := UniversalAnimationPools.mixamo_to_target_map_config(
				prefix if prefix is String else "mixamorig_", humanoid_map)
		result = HumanoidRetargeter.retarget_clip(source_skeleton,
				player.get_animation(player.get_animation_list()[0]), skeleton, config, looping, false)
		result.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	root.free()
	return result


static func hips_track(anim: Animation) -> int:
	for track in anim.get_track_count():
		var path := String(anim.track_get_path(track))
		if anim.track_get_type(track) == Animation.TYPE_POSITION_3D \
				and (path.ends_with(":Hips") or path.ends_with(":pelvis")):
			return track
	return -1


## How far the capsule has to be from where it started when the clip is at `time` (clip frame).
static func path(clip: StringName, time: float) -> Vector3:
	if not _paths.has(clip):
		return Vector3.ZERO
	var times: PackedFloat32Array = _paths[clip][0]
	var offsets: PackedVector3Array = _paths[clip][1]
	if time <= times[0]:
		return offsets[0]
	for index in range(1, times.size()):
		if time <= times[index]:
			var span := times[index] - times[index - 1]
			return offsets[index - 1].lerp(offsets[index], (time - times[index - 1]) / maxf(span, 0.0001))
	return offsets[offsets.size() - 1]


## Pose hips: GRAB holds the hanging height; UP slides from the clip's first hips to `stand_hips`
## (height only) as the body stands up. The difference goes to the capsule path. Track values live
## in the pelvis parent's own space, whose axes are not the world's: `frame` takes them to the
## player's frame (x right, y up, -z forward) and `frame.inverse()` back.
static func _move_travel(clip: StringName, anim: Animation, stand_hips: Vector3,
		hang_hips: Vector3, frame: Basis) -> void:
	var track := hips_track(anim)
	var first: Vector3 = frame * (anim.track_get_key_value(track, 0) as Vector3)
	var stand: Vector3 = frame * stand_hips
	var hang: Vector3 = frame * hang_hips
	var times := PackedFloat32Array()
	var offsets := PackedVector3Array()
	for key in anim.track_get_key_count(track):
		var time := anim.track_get_key_time(track, key)
		var real: Vector3 = frame * (anim.track_get_key_value(track, key) as Vector3)
		var pose := hang
		if clip == UP:
			var settle := smoothstep(SETTLE_FROM, SETTLE_TO, time / anim.length)
			pose = Vector3(first.x, lerpf(first.y, stand.y, settle), first.z)
		anim.track_set_key_value(track, key, frame.inverse() * pose)
		times.append(time)
		offsets.append(real - pose - (first - (hang if clip == GRAB else first)))
	_paths[clip] = [times, offsets]


## Length of a clip (s).
static func length(clip: StringName) -> float:
	if not _paths.has(clip):
		return 0.0
	var times: PackedFloat32Array = _paths[clip][0]
	return times[times.size() - 1]
