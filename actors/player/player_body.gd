class_name PlayerBody
extends Node3D
## First-person body: the MotusMan mesh attached under the player so you see
## your own torso/legs and cast a shadow. The scene this script sits on is the
## aim-idle clip FBX; the other clips share the same skeleton, so their
## animations are merged into this AnimationPlayer at runtime (same trick as
## levels/animation_preview.gd).

const CLIP_DIR := "res://assets/models/pistol_starter/Animation/In-Place/"
const CLIPS := {
	&"relaxed_idle": "W1_Stand_Relaxed_Idle_IPC",
	&"aim_idle": "W1_Stand_Aim_Idle_IPC",
	&"walk": "W1_Walk_Aim_F_Loop_IPC",
	&"jog": "W1_Jog_Aim_F_Loop_IPC",
	&"crouch_idle": "W1_Crouch_Aim_Idle_IPC",
	&"crouch_walk": "W1_CrouchWalk_Aim_F_Loop_IPC",
}
## MotusMan FBXs bake broken absolute texture paths; reapply the diffuse.
const SKIN_TEXTURE := "res://assets/models/pistol_starter/MotusMan/sourceimages/MCG_diff.jpg"

## pistol_starter only ships an aim-pose walk - no unarmed walk clip exists
## for MotusMan there. This one comes from the CC0 "Universal Animation
## Library" pack instead (Unreal Mannequin-style rig, own bone names, own
## mesh - not used, just the animation), retargeted onto MotusMan at runtime
## (see _retarget_clip). Already in-place (no baked root motion).
const UAL_PATH := "res://assets/models/universal_animation_library/UAL1_Standard.glb"
const UAL_WALK_ANIM := &"Walk"
## Unreal Mannequin bone names, not Mixamo's - no shared prefix to strip, so
## this is an explicit map instead. Fingers are left out (not load-bearing
## for a walk cycle, MotusMan's finger names don't line up anyway).
const BONE_MAP: Dictionary = {
	&"pelvis": &"Hips",
	&"spine_01": &"Spine",
	&"spine_02": &"Spine1",
	&"spine_03": &"Spine2",
	&"neck_01": &"Neck",
	&"Head": &"Head",
	&"clavicle_r": &"RightShoulder",
	&"upperarm_r": &"RightArm",
	&"lowerarm_r": &"RightForeArm",
	&"hand_r": &"RightHand",
	&"clavicle_l": &"LeftShoulder",
	&"upperarm_l": &"LeftArm",
	&"lowerarm_l": &"LeftForeArm",
	&"hand_l": &"LeftHand",
	&"thigh_r": &"RightUpLeg",
	&"calf_r": &"RightLeg",
	&"foot_r": &"RightFoot",
	&"ball_r": &"RightToeBase",
	&"thigh_l": &"LeftUpLeg",
	&"calf_l": &"LeftLeg",
	&"foot_l": &"LeftFoot",
	&"ball_l": &"LeftToeBase",
}
## Excluded from the retarget (see _retarget_clip's doc comment) and instead
## held at a fixed pose. The spine chain is included, not just the arms:
## holding the arms' local rotation constant only keeps them right relative
## to whatever Spine2 (their parent) is doing, and Spine2 is retargeted from
## the walk clip - different enough from relaxed_idle's own spine pose that
## the held arms still ended up looking wrong once cascaded through it.
## Holding the whole upper body keeps arms and spine mutually consistent,
## exactly as relaxed_idle poses them; only the legs actually animate.
const HELD_BONES: PackedStringArray = [
	"Spine", "Spine1", "Spine2",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
]

## Rough forward speeds (m/s) the clips were authored at, for foot matching.
const WALK_REF_SPEED := 1.6
const JOG_REF_SPEED := 3.0
const CROUCH_REF_SPEED := 1.1

## Camera pitch/yaw in radians, pushed by the player each physics tick.
var head_pitch := 0.0
var head_yaw := 0.0

@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var skeleton: Skeleton3D = $Skeleton3D
@onready var mesh: MeshInstance3D = $Skeleton3D/MotusMan_v55


func _ready() -> void:
	# Higher priority = processed later: our head-bend pass in _process must
	# run AFTER the AnimationPlayer has written this frame's pose.
	process_priority = 100
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(SKIN_TEXTURE)
	material.roughness = 0.85
	mesh.material_override = material

	var lib := AnimationLibrary.new()
	for key: StringName in CLIPS:
		var clip_root: Node = (load(CLIP_DIR + CLIPS[key] + ".fbx") as PackedScene).instantiate()
		var clip_ap := clip_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var anim := clip_ap.get_animation(CLIPS[key]).duplicate() as Animation
		anim.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(key, anim)
		clip_root.free()
	lib.add_animation(&"walk_relaxed",
			_retarget_clip(UAL_PATH, UAL_WALK_ANIM, lib.get_animation(&"relaxed_idle")))
	anim_player.add_animation_library(&"moves", lib)
	anim_player.play("moves/relaxed_idle")


## Copies a differently-rigged clip's tracks onto MotusMan's skeleton via
## BONE_MAP. The two rigs don't share a rest orientation (this pack points
## bones along local Y; MotusMan points them along local X), so the raw
## local rotation/position values aren't directly transferable - what DOES
## transfer is each bone's rotation/offset AWAY FROM ITS OWN rest pose,
## re-applied on top of MotusMan's own rest.
##
## HELD_BONES (the arm chain) are excluded from that and instead baked as a
## constant track holding held_pose's pose: their rest orientations differ
## too much between rigs for the "delta from rest" approach to resolve
## correctly (confirmed with actual delta values, not just a guess - it
## produces a mathematically consistent but anatomically wrong result,
## roughly a T-pose-like spread, every time, regardless of source rig).
## Simply omitting their tracks isn't enough either - once the crossfade
## from the previous animation finishes, an unanimated bone settles back to
## MotusMan's own rest (T-pose) rather than freezing where it was.
func _retarget_clip(fbx_path: String, anim_name: StringName, held_pose: Animation) -> Animation:
	var clip_root: Node = (load(fbx_path) as PackedScene).instantiate()
	var clip_ap := clip_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var src_skeleton := clip_root.find_child("Skeleton3D", true, false) as Skeleton3D
	# Not always in the default ("") library - UAL1_Standard.glb bundles all
	# its clips in one AnimationPlayer, so search whichever library has it.
	var src: Animation = null
	for lib_name in clip_ap.get_animation_library_list():
		var candidate_lib := clip_ap.get_animation_library(lib_name)
		if candidate_lib.has_animation(anim_name):
			src = candidate_lib.get_animation(anim_name)
			break
	var anim := Animation.new()
	anim.length = src.length
	anim.loop_mode = Animation.LOOP_LINEAR
	for t in src.get_track_count():
		var path := src.track_get_path(t)
		if path.get_subname_count() == 0:
			continue
		var bone_name := StringName(path.get_subname(0))
		if not BONE_MAP.has(bone_name):
			continue
		var mapped: StringName = BONE_MAP[bone_name]
		if mapped in HELD_BONES:
			continue
		var target_idx := skeleton.find_bone(mapped)
		var src_idx := src_skeleton.find_bone(bone_name)
		if target_idx < 0 or src_idx < 0:
			continue
		var track_type := src.track_get_type(t)
		var new_track := anim.add_track(track_type)
		anim.track_set_path(new_track, NodePath("Skeleton3D:" + String(mapped)))
		var src_rest := src_skeleton.get_bone_rest(src_idx)
		var target_rest := skeleton.get_bone_rest(target_idx)
		for k in src.track_get_key_count(t):
			var time := src.track_get_key_time(t, k)
			var value = src.track_get_key_value(t, k)
			if track_type == Animation.TYPE_ROTATION_3D:
				var delta := src_rest.basis.inverse() * Basis(value as Quaternion)
				value = (target_rest.basis * delta).get_rotation_quaternion()
			elif track_type == Animation.TYPE_POSITION_3D:
				var offset: Vector3 = (value as Vector3) - src_rest.origin
				if mapped == &"Hips":
					offset.x = 0.0
					offset.z = 0.0
				value = target_rest.origin + offset
			anim.track_insert_key(new_track, time, value)
	clip_root.free()
	for held_bone in HELD_BONES:
		_bake_held_track(anim, held_bone, held_pose, src.length)
	return anim


## Adds a rotation track for held_bone holding a single fixed pose (its
## value from held_pose's first keyframe) for the whole clip duration.
func _bake_held_track(
		anim: Animation, held_bone: StringName, held_pose: Animation, length: float) -> void:
	for t in held_pose.get_track_count():
		var path := held_pose.track_get_path(t)
		if (path.get_subname_count() > 0 and StringName(path.get_subname(0)) == held_bone
				and held_pose.track_get_type(t) == Animation.TYPE_ROTATION_3D):
			var value = held_pose.track_get_key_value(t, 0)
			var new_track := anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(new_track, NodePath("Skeleton3D:" + String(held_bone)))
			anim.track_insert_key(new_track, 0.0, value)
			anim.track_insert_key(new_track, length, value)
			return


func _process(_delta: float) -> void:
	# Torso first: Neck sits on Spine2, so leaning the spine forward moves
	# where the neck/head bend starts from, same as a real body would.
	_bend_torso()
	_bend_head_bones()


## Looking straight down would bend the neck/head further than a real neck
## can, folding the chin/hood into the chest - clamp well short of the
## camera's own pitch_limit_deg so the mesh stops before it clips.
##
## The up limit is lower than you'd expect from anatomy alone: past ~72-75
## the linear-blend skin between Neck and Head stretches visibly (the
## classic "candy wrapper" artifact large joint rotations cause on this kind
## of rig) - 60 leaves real margin below where that starts.
const MAX_BEND_DOWN_DEG := 40.0
const MAX_BEND_UP_DEG := 60.0

## Same clamp the mesh bend uses. The player reads this to keep the eye
## position locked to the actual bone pose - if the neck stops bending, the
## eye must stop moving with it instead of sliding on past the frozen mesh.
func clamp_head_pitch(p: float) -> float:
	return clampf(p, -deg_to_rad(MAX_BEND_DOWN_DEG), deg_to_rad(MAX_BEND_UP_DEG))


## A small forward lean when looking down - just enough to read as leaning
## to look rather than a rigid periscope neck. Pitch only (yaw already turns
## the body itself via the head-yaw-limit/catch-up system), and only for
## looking down, not up. Same clamped pitch as the neck/head bend so it
## eases back out at the same rate.
const TORSO_BEND: Dictionary = {
	&"Spine": 0.04,
	&"Spine1": 0.05,
	&"Spine2": 0.06,
}

func _bend_torso() -> void:
	var clamped_pitch := clamp_head_pitch(head_pitch)
	if clamped_pitch >= 0.0:
		return
	for bone_name: StringName in TORSO_BEND:
		var idx := skeleton.find_bone(bone_name)
		if idx < 0:
			continue
		var portion: float = TORSO_BEND[bone_name]
		var pose := skeleton.get_bone_global_pose(idx)
		pose.basis = Basis(Vector3.RIGHT, -clamped_pitch * portion) * pose.basis
		skeleton.set_bone_global_pose(idx, pose)


## Each axis is clamped on its own (MAX_BEND_*_DEG, head_yaw_limit_deg), but
## pitch and yaw near their limits *at the same time* compose into a larger
## rotation than either alone - large enough to hit the same skin-stretch
## artifact even though neither individual clamp was exceeded. Scale the
## (yaw, pitch) pair down together, as a single vector, so their combined
## magnitude never exceeds MAX_BEND_UP_DEG either - this only affects the
## visible bend, not the camera's actual look direction.
const MAX_COMBINED_BEND_DEG := MAX_BEND_UP_DEG

## Bend neck (35%) and head (65%) with the camera pitch/yaw so the skull
## rotates with the view instead of the camera diving through it. Runs
## after animation (process_priority), rotating the animated pose.
func _bend_head_bones() -> void:
	var split := {&"Neck": 0.35, &"Head": 0.65}
	var clamped_pitch := clamp_head_pitch(head_pitch)
	var yaw := head_yaw
	var combined := Vector2(yaw, clamped_pitch)
	var max_combined := deg_to_rad(MAX_COMBINED_BEND_DEG)
	if combined.length() > max_combined:
		combined = combined.normalized() * max_combined
		yaw = combined.x
		clamped_pitch = combined.y
	for bone_name: StringName in split:
		var idx := skeleton.find_bone(bone_name)
		if idx < 0:
			continue
		var portion: float = split[bone_name]
		var pose := skeleton.get_bone_global_pose(idx)
		pose.basis = (Basis(Vector3.UP, yaw * portion)
				* Basis(Vector3.RIGHT, -clamped_pitch * portion) * pose.basis)
		skeleton.set_bone_global_pose(idx, pose)


## Called by the player every physics tick (calls down, signals up).
func update_motion(crouched: bool, armed: bool, ground_speed: float,
		sprinting: bool) -> void:
	var target: StringName
	var rate := 1.0
	if ground_speed > 0.6:
		if crouched:
			target = &"crouch_walk"
			rate = ground_speed / CROUCH_REF_SPEED
		elif sprinting:
			target = &"jog"
			rate = ground_speed / JOG_REF_SPEED
		else:
			target = &"walk" if armed else &"walk_relaxed"
			rate = ground_speed / WALK_REF_SPEED
	elif crouched:
		target = &"crouch_idle"
	else:
		target = &"aim_idle" if armed else &"relaxed_idle"
	var full := "moves/" + target
	if anim_player.current_animation != full:
		anim_player.play(full, 0.3)
	anim_player.speed_scale = clampf(rate, 0.8, 2.2)
