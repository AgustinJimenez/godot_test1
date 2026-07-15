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

## Rough forward speeds (m/s) the clips were authored at, for foot matching.
const WALK_REF_SPEED := 1.6
const JOG_REF_SPEED := 3.0
const CROUCH_REF_SPEED := 1.1

## Shrunk to nothing AND pulled down inside the chest every frame, so the
## first-person camera never sees the head and the collapsed vertices hide
## inside the torso instead of spiking at the neck. The drop is authored in
## skeleton space (straight down) and converted to the parent bone's local
## space per frame — bone pose positions live in parent-bone space.
const HIDDEN_BONES: PackedStringArray = ["Neck", "Head"]
const HIDDEN_BONE_DROP := Vector3(0, -0.35, 0)

## Experiment toggle: keep the full head and rely on the camera near plane
## to clip the skull from the inside. In this mode the neck/head bones follow
## the camera pitch (set via head_pitch) so looking down moves the skull too.
@export var hide_head := true

## Camera pitch in radians, pushed by the player each physics tick.
var head_pitch := 0.0

var _hidden_indices: PackedInt32Array = []

@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var skeleton: Skeleton3D = $Skeleton3D
@onready var mesh: MeshInstance3D = $Skeleton3D/MotusMan_v55


func _ready() -> void:
	# Higher priority = processed later: our bone-hiding pass in _process must
	# run AFTER the AnimationPlayer has written this frame's pose.
	process_priority = 100
	for bone_name in HIDDEN_BONES:
		var idx := skeleton.find_bone(bone_name)
		if idx >= 0:
			_hidden_indices.append(idx)
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
	anim_player.add_animation_library(&"moves", lib)
	anim_player.play("moves/relaxed_idle")


func _process(_delta: float) -> void:
	if not hide_head:
		_pitch_head_bones()
		return
	for idx in _hidden_indices:
		skeleton.set_bone_pose_scale(idx, Vector3(0.001, 0.001, 0.001))
		var parent := skeleton.get_bone_parent(idx)
		var parent_basis := skeleton.get_bone_global_pose(parent).basis
		skeleton.set_bone_pose_position(idx,
				skeleton.get_bone_rest(idx).origin
				+ parent_basis.inverse() * HIDDEN_BONE_DROP)


## Full-head mode: bend neck (35%) and head (65%) with the camera pitch so
## the skull rotates with the view instead of the camera diving through it.
## Runs after animation (process_priority), rotating the animated pose.
func _pitch_head_bones() -> void:
	var split := {&"Neck": 0.35, &"Head": 0.65}
	for bone_name: StringName in split:
		var idx := skeleton.find_bone(bone_name)
		if idx < 0:
			continue
		var pose := skeleton.get_bone_global_pose(idx)
		pose.basis = Basis(Vector3.RIGHT, head_pitch * split[bone_name]) * pose.basis
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
			target = &"walk"
			rate = ground_speed / WALK_REF_SPEED
	elif crouched:
		target = &"crouch_idle"
	else:
		target = &"aim_idle" if armed else &"relaxed_idle"
	var full := "moves/" + target
	if anim_player.current_animation != full:
		anim_player.play(full, 0.3)
	anim_player.speed_scale = clampf(rate, 0.8, 2.2)
