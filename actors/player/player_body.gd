class_name PlayerBody
extends Node3D
## First-person body: the MotusMan mesh attached under the player so you see
## your own torso/legs and cast a shadow. The scene this script sits on is the
## aim-idle clip FBX, but gameplay locomotion is retargeted from UAL onto its
## skeleton. Native MotusMan clips remain loaded as debug references.

signal action_finished(animation_name: StringName)
signal action_contact(animation_name: StringName)

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
const FLASHLIGHT_MODEL := preload("res://assets/models/flashlight/flashlight.glb")
const HAND_GRIP_MODIFIER := preload("res://actors/player/player_hand_grip_modifier.gd")
const FLASHLIGHT_HAND := &"RightHand"
const FLASHLIGHT_MODEL_SCALE := 0.12
const FLASHLIGHT_GRIP_POSE_PATH := "res://actors/player/flashlight_grip_pose.json"

## pistol_starter only ships aim-pose locomotion. These unarmed gameplay
## states come from the CC0 Universal Animation Library instead (Unreal
## Mannequin-style rig, own bone names, own mesh - not used, just animation),
## retargeted onto MotusMan at startup. Dictionary keys are the local gameplay
## names and values are the raw UAL clip names.
const UAL_PATH := "res://assets/models/universal_animation_library/UAL1_Standard.glb"
const UAL2_PATH := "res://assets/models/universal_animation_library_2/UAL2_Standard.glb"
const UAL_GAMEPLAY_CLIPS: Dictionary = {
	&"unarmed_idle": &"Idle",
	&"unarmed_walk": &"Walk",
	&"unarmed_sprint": &"Sprint",
	&"unarmed_crouch_idle": &"Crouch_Idle",
	&"unarmed_crouch_walk": &"Crouch_Fwd",
	&"unarmed_jump_start": &"Jump_Start",
	&"unarmed_jump": &"Jump",
	&"unarmed_jump_land": &"Jump_Land",
	&"unarmed_roll": &"Roll",
	&"unarmed_punch_jab": &"Punch_Jab",
	&"unarmed_punch_cross": &"Punch_Cross",
	&"weapon_sword_attack": &"Sword_Attack",
	&"unarmed_interact": &"Interact",
	&"unarmed_pickup": &"PickUp_Table",
}
const UAL2_GAMEPLAY_CLIPS: Dictionary = {
	&"unarmed_torch_idle": &"Idle_Lantern",
}
const UAL_LOOPING_GAMEPLAY_CLIPS: PackedStringArray = [
	"unarmed_idle", "unarmed_walk", "unarmed_sprint",
	"unarmed_crouch_idle", "unarmed_crouch_walk", "unarmed_jump",
	"unarmed_torch_idle",
]
## UAL1_Standard.glb's raw clip names for the debug menu. Gameplay aliases
## above are baked eagerly; raw-name previews are still retargeted lazily so
## a normal play session does not pay for every unused clip.
const UAL_EXTRA_CLIPS: PackedStringArray = [
	"A_TPose", "Idle", "Idle_Talking", "Idle_Torch", "Walk_Formal", "Jog_Fwd", "Sprint",
	"Crouch_Idle", "Crouch_Fwd", "Jump", "Jump_Start", "Jump_Land", "Roll",
	"Pistol_Idle", "Pistol_Aim_Down", "Pistol_Aim_Neutral", "Pistol_Aim_Up",
	"Pistol_Reload", "Pistol_Shoot", "Punch_Jab", "Punch_Cross", "Hit_Chest", "Hit_Head",
	"Sword_Idle", "Sword_Attack", "Spell_Simple_Idle", "Spell_Simple_Enter",
	"Spell_Simple_Exit", "Spell_Simple_Shoot", "Interact", "PickUp_Table", "Push",
	"Fixing_Kneeling", "Sitting_Enter", "Sitting_Idle", "Sitting_Talking", "Sitting_Exit",
	"Driving", "Swim_Idle", "Swim_Fwd", "Dance", "Death01",
]
## UAL2 uses the same Unreal mannequin skeleton as UAL1, so the existing
## humanoid retarget map applies unchanged. A_TPose is omitted because that
## debug name already belongs to UAL1 in the shared target animation library.
const UAL2_EXTRA_CLIPS: PackedStringArray = [
	"Chest_Open", "ClimbUp_1m", "Consume", "Farm_Harvest", "Farm_PlantSeed",
	"Farm_Watering", "Hit_Knockback", "Idle_FoldArms", "Idle_Lantern", "Idle_No",
	"Idle_Rail", "Idle_Rail_Call", "Idle_Shield", "Idle_Shield_Break",
	"Idle_TalkingPhone", "LayToIdle", "Melee_Hook", "Melee_Hook_Rec",
	"NinjaJump_Idle", "NinjaJump_Land", "NinjaJump_Start", "OverhandThrow",
	"Shield_Dash", "Shield_OneShot", "Slide", "Slide_Exit", "Slide_Start",
	"Sword_Block", "Sword_Dash", "Sword_Heavy_Combo", "Sword_Regular_A",
	"Sword_Regular_A_Rec", "Sword_Regular_B", "Sword_Regular_B_Rec",
	"Sword_Regular_C", "Sword_Regular_Combo", "TreeChopping", "Walk_Carry", "Yes",
	"Zombie_Idle", "Zombie_Scratch", "Zombie_Walk_Fwd",
]
## Unreal Mannequin bone names, not Mixamo's - no shared prefix to strip, so
## this is an explicit map instead. Finger chains map joint-for-joint;
## without them every clip fell back to MotusMan's curled finger rest pose.
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
	&"index_01_r": &"RightHandIndex1",
	&"index_02_r": &"RightHandIndex2",
	&"index_03_r": &"RightHandIndex3",
	&"index_04_leaf_r": &"RightHandIndex4",
	&"middle_01_r": &"RightHandMiddle1",
	&"middle_02_r": &"RightHandMiddle2",
	&"middle_03_r": &"RightHandMiddle3",
	&"middle_04_leaf_r": &"RightHandMiddle4",
	&"pinky_01_r": &"RightHandPinky1",
	&"pinky_02_r": &"RightHandPinky2",
	&"pinky_03_r": &"RightHandPinky3",
	&"pinky_04_leaf_r": &"RightHandPinky4",
	&"ring_01_r": &"RightHandRing1",
	&"ring_02_r": &"RightHandRing2",
	&"ring_03_r": &"RightHandRing3",
	&"ring_04_leaf_r": &"RightHandRing4",
	&"thumb_01_r": &"RightHandThumb1",
	&"thumb_02_r": &"RightHandThumb2",
	&"thumb_03_r": &"RightHandThumb3",
	&"thumb_04_leaf_r": &"RightHandThumb4",
	&"clavicle_l": &"LeftShoulder",
	&"upperarm_l": &"LeftArm",
	&"lowerarm_l": &"LeftForeArm",
	&"hand_l": &"LeftHand",
	&"index_01_l": &"LeftHandIndex1",
	&"index_02_l": &"LeftHandIndex2",
	&"index_03_l": &"LeftHandIndex3",
	&"index_04_leaf_l": &"LeftHandIndex4",
	&"middle_01_l": &"LeftHandMiddle1",
	&"middle_02_l": &"LeftHandMiddle2",
	&"middle_03_l": &"LeftHandMiddle3",
	&"middle_04_leaf_l": &"LeftHandMiddle4",
	&"pinky_01_l": &"LeftHandPinky1",
	&"pinky_02_l": &"LeftHandPinky2",
	&"pinky_03_l": &"LeftHandPinky3",
	&"pinky_04_leaf_l": &"LeftHandPinky4",
	&"ring_01_l": &"LeftHandRing1",
	&"ring_02_l": &"LeftHandRing2",
	&"ring_03_l": &"LeftHandRing3",
	&"ring_04_leaf_l": &"LeftHandRing4",
	&"thumb_01_l": &"LeftHandThumb1",
	&"thumb_02_l": &"LeftHandThumb2",
	&"thumb_03_l": &"LeftHandThumb3",
	&"thumb_04_leaf_l": &"LeftHandThumb4",
	&"thigh_r": &"RightUpLeg",
	&"calf_r": &"RightLeg",
	&"foot_r": &"RightFoot",
	&"ball_r": &"RightToeBase",
	&"thigh_l": &"LeftUpLeg",
	&"calf_l": &"LeftLeg",
	&"foot_l": &"LeftFoot",
	&"ball_l": &"LeftToeBase",
}
## Arm bones retarget via position-based "swing" instead of the rotation
## delta every other bone uses (see _swing_retarget's doc comment) - full
## rotation transfer kept spreading the arms into a T-pose even with the
## delta computed in global space. Each entry names the child bone used to
## derive "which way is this bone currently pointing".
const SWING_BONES: Dictionary = {
	&"RightShoulder": &"RightArm",
	&"RightArm": &"RightForeArm",
	&"RightForeArm": &"RightHand",
	&"LeftShoulder": &"LeftArm",
	&"LeftArm": &"LeftForeArm",
	&"LeftForeArm": &"LeftHand",
}
## Legacy hand-mode comparison retained until the humanoid retarget work is
## manually accepted and the old delta/swing paths can be removed. The normal
## `use_humanoid_retarget` path ignores this mode and retargets hands/fingers
## through the same parent-rest conversion as the rest of the skeleton.
const HAND_BONES: PackedStringArray = ["RightHand", "LeftHand"]
enum HandRetarget {
	## Locked to relaxed_idle's wrist pose all clip long (original behavior -
	## loses aim/punch/hit direction entirely).
	FROZEN,
	## Same global rest-relative delta transfer the spine/legs use.
	DELTA_ROTATION,
	## Source hand's own LOCAL rotation applied directly under the target
	## forearm's retargeted global pose - no rest-delta math, assumes both
	## rigs' wrist axes are similarly oriented.
	LOCAL_COPY,
}
@export var hand_retarget_mode: HandRetarget = HandRetarget.DELTA_ROTATION

## Legs default to the same global rest-relative delta transfer as spine -
## fine for a walk cycle's shallow knee bend, but a deep crouch/hunch (e.g.
## Pistol_Aim_Down) exposes the same rig-axis-mismatch problem that pushed
## arms onto swing retargeting: a ~59 degree secondary-axis "twist" shows up
## on the knee for that clip, where a real hinge joint should show almost
## none - the leg swings out sideways instead of just bending forward.
## SWING reuses the exact same technique arms use, applied to the leg chain.
const LEG_SWING_MAP: Dictionary = {
	&"RightUpLeg": &"RightLeg",
	&"RightLeg": &"RightFoot",
	&"LeftUpLeg": &"LeftLeg",
	&"LeftLeg": &"LeftFoot",
}
enum LegRetarget {
	## Original behavior - full rest-relative delta, same as spine.
	DELTA_ROTATION,
	## Position-based swing, same technique/tradeoffs as arms (no twist, e.g.
	## foot-turn-out doesn't survive).
	SWING,
}
@export var leg_retarget_mode: LegRetarget = LegRetarget.DELTA_ROTATION

## Uses the same model-space local-pose conversion as Godot 4.6's
## RetargetModifier3D. The legacy swing/delta modes remain available only
## so the throwaway comparison scene can show the broken implementations
## beside this one; gameplay and normal debug previews use this path.
@export var use_humanoid_retarget := true

## Rough forward speeds (m/s) the clips were authored at, for foot matching.
const WALK_REF_SPEED := 1.6
const SPRINT_REF_SPEED := 5.8
const CROUCH_REF_SPEED := 1.1
const LOCOMOTION_BLEND_TIME := 0.5
const JUMP_PHASE_SPEED := 2.5

## Camera pitch/yaw in radians, pushed by the player each physics tick.
var head_pitch := 0.0
var head_yaw := 0.0

## The "moves" library and the pose UAL_EXTRA_CLIPS hold their spine/arms
## to (see _retarget_clip) - kept around so play_debug_anim can retarget
## and cache extra clips lazily, on first request, instead of upfront.
var _lib: AnimationLibrary
var _held_pose: Animation
var _look_pose_modifier: PlayerLookPoseModifier
var _hand_grip_modifier: PlayerHandGripModifier
var _flashlight_attachment: BoneAttachment3D
var _flashlight_model: Node3D
var _equipped_attachment: BoneAttachment3D
var _equipped_model: Node3D
var _airborne := false
var _landing_time_left := 0.0
var _action_animation := &""
var _action_contact_ratio := -1.0
var _action_contact_emitted := false

## True while a debug-menu clip is being previewed, so update_motion() doesn't
## immediately stomp it back to relaxed_idle on the next physics tick (e.g.
## right when the tree unpauses after closing the menu overlay). Cleared the
## moment the player actually does something that should visibly change the
## animation anyway (move, crouch, arm the weapon) - only suppressed while
## they're just standing still watching the preview.
var _debug_preview_active := false

@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var skeleton: Skeleton3D = $Skeleton3D
@onready var mesh: MeshInstance3D = $Skeleton3D/MotusMan_v55

## Tool instances can disable the gameplay idle so they initially expose the
## imported skeleton pose. Gameplay scenes retain the existing default.
var autoplay_default_animation := true


func _ready() -> void:
	# Lets the debug menu's animation preview keep looping while the pause
	# menu has the rest of the game (including this node's own parent,
	# Player, which is PAUSABLE by design) frozen.
	anim_player.process_mode = Node.PROCESS_MODE_ALWAYS
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(SKIN_TEXTURE)
	material.roughness = 0.85
	mesh.material_override = material
	_look_pose_modifier = PlayerLookPoseModifier.new()
	_look_pose_modifier.name = &"LookPoseModifier"
	_look_pose_modifier.player_body = self
	skeleton.add_child(_look_pose_modifier)
	_setup_held_flashlight()

	var lib := AnimationLibrary.new()
	for key: StringName in CLIPS:
		var clip_root: Node = (load(CLIP_DIR + CLIPS[key] + ".fbx") as PackedScene).instantiate()
		var clip_ap := clip_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var anim := clip_ap.get_animation(CLIPS[key]).duplicate() as Animation
		anim.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(key, anim)
		clip_root.free()
	_held_pose = lib.get_animation(&"relaxed_idle")
	for gameplay_name: StringName in UAL_GAMEPLAY_CLIPS:
		var source_name: StringName = UAL_GAMEPLAY_CLIPS[gameplay_name]
		lib.add_animation(gameplay_name,
				_retarget_clip(UAL_PATH, source_name, _held_pose,
						String(gameplay_name) in UAL_LOOPING_GAMEPLAY_CLIPS))
	for gameplay_name: StringName in UAL2_GAMEPLAY_CLIPS:
		var source_name: StringName = UAL2_GAMEPLAY_CLIPS[gameplay_name]
		lib.add_animation(gameplay_name,
				_retarget_clip(UAL2_PATH, source_name, _held_pose,
						String(gameplay_name) in UAL_LOOPING_GAMEPLAY_CLIPS))
	_lib = lib
	anim_player.add_animation_library(&"moves", lib)
	anim_player.animation_finished.connect(_on_animation_finished)
	if autoplay_default_animation:
		anim_player.play("moves/unarmed_idle")


## Copies a differently-rigged clip's tracks onto MotusMan's skeleton via
## BONE_MAP. Deltas are computed and reapplied in GLOBAL (skeleton-root)
## space, not each bone's parent-relative local space - see BONE_MAP's doc
## comment for why: a naive local-space "delta from own rest, reapplied to
## target's own rest" compounds the two rigs' differing bone-forward-axis
## conventions at every parent hop, and arms sit 6-7 hops deep (through the
## whole spine) versus 3-4 for legs, which is exactly why legs retargeted
## fine before while arms spread into a T-pose every time. Working in global
## space means each bone's delta is only ever relative to its OWN rest, with
## no compounding, regardless of chain depth.
##
## This requires resampling the source clip at fixed intervals (its own
## keyframe times aren't used directly) because a bone's global pose depends
## on its whole ANIMATED ancestor chain, not just its own track.
const RETARGET_SAMPLE_HZ := 30.0

func _retarget_clip(fbx_path: String, anim_name: StringName, held_pose: Animation,
		force_loop: bool = false) -> Animation:
	var clip_root: Node = (load(fbx_path) as PackedScene).instantiate()
	var clip_ap := clip_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var src_skeleton := clip_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var src: Animation = null
	for lib_name in clip_ap.get_animation_library_list():
		var candidate_lib := clip_ap.get_animation_library(lib_name)
		if candidate_lib.has_animation(anim_name):
			src = candidate_lib.get_animation(anim_name)
			break

	# Which source track (if any) drives each source bone's rotation/position.
	var bone_tracks: Dictionary = {}
	for t in src.get_track_count():
		var path := src.track_get_path(t)
		if path.get_subname_count() == 0:
			continue
		var bone_name := StringName(path.get_subname(0))
		if not bone_tracks.has(bone_name):
			bone_tracks[bone_name] = {}
		var track_type := src.track_get_type(t)
		if track_type == Animation.TYPE_ROTATION_3D:
			bone_tracks[bone_name]["rot"] = t
		elif track_type == Animation.TYPE_POSITION_3D:
			bone_tracks[bone_name]["pos"] = t

	var anim := Animation.new()
	anim.length = src.length
	anim.loop_mode = Animation.LOOP_LINEAR if force_loop else src.loop_mode

	var out_rot_track: Dictionary = {}
	for src_name in BONE_MAP:
		var target_name: StringName = BONE_MAP[src_name]
		if ((target_name in HAND_BONES and hand_retarget_mode == HandRetarget.FROZEN)
				or not bone_tracks.has(src_name)
				or skeleton.find_bone(target_name) < 0 or src_skeleton.find_bone(src_name) < 0):
			continue
		var track := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track, NodePath("Skeleton3D:" + String(target_name)))
		out_rot_track[target_name] = track
	var out_pos_track := -1
	if bone_tracks.has(&"pelvis"):
		out_pos_track = anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(out_pos_track, NodePath("Skeleton3D:Hips"))

	var reverse_map: Dictionary = {}
	for src_name in BONE_MAP:
		reverse_map[BONE_MAP[src_name]] = src_name
	var source_hips := src_skeleton.find_bone(&"pelvis")
	var target_hips := skeleton.find_bone(&"Hips")
	var position_scale := 1.0
	if source_hips >= 0 and target_hips >= 0:
		var source_height := src_skeleton.get_bone_global_rest(source_hips).origin.length()
		var target_height := skeleton.get_bone_global_rest(target_hips).origin.length()
		if source_height > 0.0001:
			position_scale = target_height / source_height
	var source_facing := PlayerBodyPoseMath.skeleton_rest_facing(
			src_skeleton, &"pelvis", &"Head", &"clavicle_l", &"clavicle_r")
	var target_facing := PlayerBodyPoseMath.skeleton_rest_facing(
			skeleton, &"Hips", &"Head", &"LeftShoulder", &"RightShoulder")
	var source_to_target_facing := Basis(Vector3.UP,
			source_facing.signed_angle_to(target_facing, Vector3.UP))
	var arm_position_scale := PlayerBodyPoseMath.skeleton_height(skeleton, &"Hips", &"Head") / maxf(
			PlayerBodyPoseMath.skeleton_height(src_skeleton, &"pelvis", &"Head"), 0.0001)
	var sample_count := int(ceil(src.length * RETARGET_SAMPLE_HZ)) + 1
	for i in sample_count:
		var time: float = minf(i / RETARGET_SAMPLE_HZ, src.length)

		# Pass 1: fully pose the SOURCE skeleton for this sample first, every
		# mapped bone at once - SWING_BONES needs to look ahead at its own
		# child's animated position, which only exists once the whole source
		# pose for this instant has actually been applied.
		for src_name in BONE_MAP:
			var src_idx := src_skeleton.find_bone(src_name)
			if src_idx < 0 or not bone_tracks.has(src_name):
				continue
			var tracks: Dictionary = bone_tracks[src_name]
			var local_rot := src_skeleton.get_bone_rest(src_idx).basis.get_rotation_quaternion()
			if tracks.has("rot"):
				local_rot = src.rotation_track_interpolate(tracks["rot"], time)
			src_skeleton.set_bone_pose_rotation(src_idx, local_rot)
			if tracks.has("pos"):
				src_skeleton.set_bone_pose_position(
						src_idx, src.position_track_interpolate(tracks["pos"], time))

		# Pass 2: compute each target bone's retargeted GLOBAL pose, parent
		# first (BONE_MAP lists each chain root-to-leaf), then convert down
		# to target-local for storage.
		var target_global: Dictionary = {}
		for src_name in BONE_MAP:
			var target_name: StringName = BONE_MAP[src_name]
			var target_idx := skeleton.find_bone(target_name)
			var src_idx := src_skeleton.find_bone(src_name)
			if target_idx < 0 or src_idx < 0 or not bone_tracks.has(src_name):
				continue
			var is_hand := target_name in HAND_BONES
			if is_hand and hand_retarget_mode == HandRetarget.FROZEN:
				continue
			if use_humanoid_retarget:
				var local := _humanoid_retarget_local_pose(
						src_skeleton, src_idx, skeleton, target_idx, position_scale)
				# Animation rotation tracks store quaternions. Compose descendants
				# from that serializable basis too; retaining FBX shear/scale here
				# makes offline global positions differ from runtime playback.
				local.basis = Basis(local.basis.get_rotation_quaternion())
				var parent_idx := skeleton.get_bone_parent(target_idx)
				var parent_global: Transform3D = target_global.get(
						parent_idx, skeleton.get_bone_global_rest(parent_idx)) if parent_idx >= 0 else Transform3D()
				target_global[target_idx] = parent_global * local
				skeleton.set_bone_pose_rotation(target_idx, local.basis.get_rotation_quaternion())
				skeleton.set_bone_pose_position(target_idx, local.origin)
				if out_rot_track.has(target_name):
					anim.track_insert_key(out_rot_track[target_name], time, local.basis.get_rotation_quaternion())
				if target_name == &"Hips" and out_pos_track >= 0:
					anim.track_insert_key(out_pos_track, time, local.origin)
				continue
			var target_rest := skeleton.get_bone_global_rest(target_idx)
			var target_basis: Basis
			var target_origin: Vector3 = target_rest.origin
			if is_hand and hand_retarget_mode == HandRetarget.LOCAL_COPY:
				var parent_idx := skeleton.get_bone_parent(target_idx)
				var target_parent_global: Transform3D = target_global.get(
						parent_idx, skeleton.get_bone_global_rest(parent_idx)) if parent_idx >= 0 else Transform3D()
				target_basis = target_parent_global.basis * src_skeleton.get_bone_pose(src_idx).basis
			elif SWING_BONES.has(target_name) and reverse_map.has(SWING_BONES[target_name]):
				target_basis = _swing_retarget(src_skeleton, src_idx, skeleton, target_idx,
						src_skeleton.find_bone(reverse_map[SWING_BONES[target_name]]),
						skeleton.find_bone(SWING_BONES[target_name]))
			elif (leg_retarget_mode == LegRetarget.SWING and LEG_SWING_MAP.has(target_name)
					and reverse_map.has(LEG_SWING_MAP[target_name])):
				target_basis = _swing_retarget(src_skeleton, src_idx, skeleton, target_idx,
						src_skeleton.find_bone(reverse_map[LEG_SWING_MAP[target_name]]),
						skeleton.find_bone(LEG_SWING_MAP[target_name]))
			else:
				var src_rest := src_skeleton.get_bone_global_rest(src_idx)
				var src_pose_global := PlayerBodyPoseMath.manual_global_pose(src_skeleton, src_idx)
				var delta := src_rest.basis.inverse() * src_pose_global.basis
				target_basis = target_rest.basis * delta
				if target_name == &"Hips":
					var offset: Vector3 = src_pose_global.origin - src_rest.origin
					offset.x = 0.0
					offset.z = 0.0
					target_origin = target_rest.origin + offset
			var pose_global := Transform3D(target_basis, target_origin)
			target_global[target_idx] = pose_global
			var parent_idx := skeleton.get_bone_parent(target_idx)
			var parent_global: Transform3D = target_global.get(
					parent_idx, skeleton.get_bone_global_rest(parent_idx)) if parent_idx >= 0 else Transform3D()
			var local := parent_global.affine_inverse() * pose_global
			if out_rot_track.has(target_name):
				anim.track_insert_key(out_rot_track[target_name], time, local.basis.get_rotation_quaternion())
			if target_name == &"Hips" and out_pos_track >= 0:
				anim.track_insert_key(out_pos_track, time, local.origin)
		if use_humanoid_retarget:
			_match_arm_skeleton_positions(anim, src_skeleton, target_global,
					out_rot_track, source_to_target_facing, arm_position_scale)
	clip_root.free()
	if hand_retarget_mode == HandRetarget.FROZEN:
		for hand_bone in HAND_BONES:
			PlayerBodyPoseMath.bake_held_track(anim, hand_bone, held_pose, src.length)
	return anim


## Retargets a bone by matching WHERE IT POINTS (its own to its child's
## global position, i.e. the direction of the bone itself in world space)
## rather than transferring its full rotation. Positions carry no "which
## local axis means forward" ambiguity at all, so this sidesteps the exact
## question full rotation transfer needs to get right - and gets wrong for
## the arms specifically, every attempt so far (spread into a T-pose).
## Trade-off: no roll/twist (e.g. forearm pronation) survives, only the
## swing - not very visible on this rig at typical camera distance for a
## walk cycle.
##
## This world-space version is known to overcorrect a bone low in a
## heavily-pre-rotated chain (e.g. a knee under a hip that's bent forward a
## lot - see docs/task_history/ual_animation_retargeting.md "Bug 3 update 3").
## A parent-relative rework was attempted twice and made things worse (see
## "Bug 3 update 4" in that history) - re-expressing the swing in the parent's
## own local
## axis convention reintroduces exactly the axis-mismatch problem this
## world-space approach was built to avoid in the first place. Reverted to
## this version deliberately; do not re-attempt the same parent-relative
## approach without a fundamentally different idea for avoiding that.
func _swing_retarget(src_skel: Skeleton3D, src_idx: int, target_skel: Skeleton3D, target_idx: int,
		src_child_idx: int, target_child_idx: int) -> Basis:
	var target_rest := target_skel.get_bone_global_rest(target_idx)
	if src_child_idx < 0 or target_child_idx < 0:
		return target_rest.basis
	var src_rest_dir := (src_skel.get_bone_global_rest(src_child_idx).origin
			- src_skel.get_bone_global_rest(src_idx).origin).normalized()
	var src_pose_dir := (PlayerBodyPoseMath.manual_global_pose(src_skel, src_child_idx).origin
			- PlayerBodyPoseMath.manual_global_pose(src_skel, src_idx).origin).normalized()
	var swing := PlayerBodyPoseMath.swing_between(src_rest_dir, src_pose_dir)
	return swing * target_rest.basis


## Synchronous equivalent of Godot 4.6 RetargetModifier3D's local-pose
## algorithm. It moves a source local pose into model space through the
## source parent's global rest, then into the target parent's rest frame.
## That parent-rest conversion is what the earlier delta and swing methods
## were missing, and it is independent of either rig's local bone axes.
func _humanoid_retarget_local_pose(src_skel: Skeleton3D, src_idx: int,
		target_skel: Skeleton3D, target_idx: int, position_scale: float) -> Transform3D:
	var src_parent_rest := Transform3D()
	var src_parent := src_skel.get_bone_parent(src_idx)
	if src_parent >= 0:
		src_parent_rest = src_skel.get_bone_global_rest(src_parent)
	var target_parent_rest := Transform3D()
	var target_parent := target_skel.get_bone_parent(target_idx)
	if target_parent >= 0:
		target_parent_rest = target_skel.get_bone_global_rest(target_parent)
	var src_rest := src_skel.get_bone_rest(src_idx)
	var target_rest := target_skel.get_bone_rest(target_idx)
	var src_pose := src_skel.get_bone_pose(src_idx)
	var pre_basis := target_parent_rest.basis.inverse() * src_parent_rest.basis
	var post_basis := (src_rest.basis.inverse() * src_parent_rest.basis.inverse()
			* target_parent_rest.basis * target_rest.basis)
	var origin := (pre_basis * ((src_pose.origin - src_rest.origin) * position_scale)
			+ target_rest.origin)
	return Transform3D(pre_basis * src_pose.basis * post_basis, origin)


## Match source wrist positions without changing MotusMan's bone lengths.
## A three-link FABRIK chain (shoulder, upper arm, forearm) reaches the source
## wrist endpoint, then each target bone is swung onto its solved segment while
## retaining the humanoid-retargeted twist as closely as possible.
func _match_arm_skeleton_positions(anim: Animation, src_skel: Skeleton3D,
		target_global: Dictionary, out_rot_track: Dictionary,
		direction_map: Basis, position_scale: float) -> void:
	var source_hips := PlayerBodyPoseMath.manual_global_pose(
			src_skel, src_skel.find_bone(&"pelvis")).origin
	var target_hips := PlayerBodyPoseMath.manual_global_pose(
			skeleton, skeleton.find_bone(&"Hips")).origin
	for side_data in [["l", "Left"], ["r", "Right"]]:
		var source_side: String = side_data[0]
		var target_side: String = side_data[1]
		var source_hand := src_skel.find_bone(StringName("hand_" + source_side))
		var shoulder_idx := skeleton.find_bone(StringName(target_side + "Shoulder"))
		var arm_idx := skeleton.find_bone(StringName(target_side + "Arm"))
		var forearm_idx := skeleton.find_bone(StringName(target_side + "ForeArm"))
		var hand_idx := skeleton.find_bone(StringName(target_side + "Hand"))
		if (source_hand < 0
				or shoulder_idx < 0 or arm_idx < 0 or forearm_idx < 0 or hand_idx < 0
				or not target_global.has(shoulder_idx) or not target_global.has(arm_idx)
				or not target_global.has(forearm_idx) or not target_global.has(hand_idx)):
			continue
		var joints: Array[Vector3] = [
			PlayerBodyPoseMath.manual_global_pose(skeleton, shoulder_idx).origin,
			PlayerBodyPoseMath.manual_global_pose(skeleton, arm_idx).origin,
			PlayerBodyPoseMath.manual_global_pose(skeleton, forearm_idx).origin,
			PlayerBodyPoseMath.manual_global_pose(skeleton, hand_idx).origin,
		]
		var lengths: Array[float] = [
			joints[0].distance_to(joints[1]),
			joints[1].distance_to(joints[2]),
			joints[2].distance_to(joints[3]),
		]
		var desired_wrist := target_hips + direction_map * (
				(PlayerBodyPoseMath.manual_global_pose(src_skel, source_hand).origin - source_hips)
				* position_scale)
		PlayerBodyPoseMath.solve_fabrik(joints, lengths, desired_wrist)
		var chain := [shoulder_idx, arm_idx, forearm_idx]
		for joint in chain.size():
			_aim_bone_at_direction(anim, target_global, out_rot_track,
					chain[joint], (joints[joint + 1] - joints[joint]).normalized())


func _aim_bone_at_direction(anim: Animation, target_global: Dictionary,
		out_rot_track: Dictionary, bone_idx: int, desired_direction: Vector3) -> void:
	var child_idx := skeleton.get_bone_children(bone_idx)[0]
	var parent_idx := skeleton.get_bone_parent(bone_idx)
	var parent_global := PlayerBodyPoseMath.manual_global_pose(skeleton, parent_idx)
	var bone_global := PlayerBodyPoseMath.manual_global_pose(skeleton, bone_idx)
	var child_global := PlayerBodyPoseMath.manual_global_pose(skeleton, child_idx)
	var current_direction := (child_global.origin - bone_global.origin).normalized()
	var desired_global_basis := PlayerBodyPoseMath.swing_between(
			current_direction, desired_direction) * bone_global.basis
	var local_rotation := (parent_global.basis.inverse()
			* desired_global_basis).get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(bone_idx, local_rotation)
	target_global[bone_idx] = PlayerBodyPoseMath.manual_global_pose(skeleton, bone_idx)
	PlayerBodyPoseMath.set_latest_rotation_key(
			anim, out_rot_track, skeleton.get_bone_name(bone_idx), local_rotation)


func _process(_delta: float) -> void:
	_update_action_contact()


func _update_action_contact() -> void:
	if (_action_animation == &"" or _action_contact_emitted
			or _action_contact_ratio < 0.0
			or anim_player.current_animation != _action_animation):
		return
	var animation := anim_player.get_animation(_action_animation)
	if animation == null or animation.length <= 0.0:
		return
	if anim_player.current_animation_position >= animation.length * _action_contact_ratio:
		_action_contact_emitted = true
		action_contact.emit(_action_animation)


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


## The modifier's cached pose is the one rendered this frame. Skeleton3D
## restores the base animation pose after modifiers finish, so camera and
## clearance consumers use this accessor instead of reading the reset pose.
func get_visual_bone_global_pose(bone_idx: int) -> Transform3D:
	if _look_pose_modifier != null:
		return _look_pose_modifier.get_adjusted_global_pose(bone_idx)
	return skeleton.get_bone_global_pose(bone_idx)


## Called by the player every physics tick (calls down, signals up).
func update_motion(crouched: bool, armed: bool, ground_speed: float,
		sprinting: bool, on_floor: bool, vertical_velocity: float, delta: float,
		torch_enabled: bool) -> void:
	set_held_flashlight_visible(torch_enabled)
	_hand_grip_modifier.active = false
	if _debug_preview_active:
		if ground_speed <= 0.6 and not crouched and not armed and on_floor:
			return
		_debug_preview_active = false
	if not on_floor:
		_action_animation = &""
		_action_contact_ratio = -1.0
		_action_contact_emitted = false
		_landing_time_left = 0.0
		if not _airborne:
			_airborne = true
			if vertical_velocity > 0.0:
				_play_motion(&"unarmed_jump_start", 0.1, JUMP_PHASE_SPEED)
			else:
				_play_motion(&"unarmed_jump", 0.1)
		elif vertical_velocity <= 0.0:
			_play_motion(&"unarmed_jump", 0.2)
		return
	if _airborne:
		_airborne = false
		var land_animation := _lib.get_animation(&"unarmed_jump_land")
		_landing_time_left = land_animation.length / JUMP_PHASE_SPEED
		_play_motion(&"unarmed_jump_land", 0.1, JUMP_PHASE_SPEED)
		return
	if _landing_time_left > 0.0:
		_landing_time_left = maxf(_landing_time_left - delta, 0.0)
		if _landing_time_left > 0.0:
			return
	if _action_animation != &"":
		return
	var target: StringName
	var rate := 1.0
	if ground_speed > 0.6:
		if crouched:
			target = &"unarmed_crouch_walk"
			rate = ground_speed / CROUCH_REF_SPEED
		elif sprinting:
			target = &"unarmed_sprint"
			rate = ground_speed / SPRINT_REF_SPEED
		else:
			target = &"unarmed_walk"
			rate = ground_speed / WALK_REF_SPEED
	elif crouched:
		target = &"unarmed_crouch_idle"
	else:
		target = &"unarmed_torch_idle" if torch_enabled else &"unarmed_idle"
	_hand_grip_modifier.active = target == &"unarmed_torch_idle"
	_play_motion(target, LOCOMOTION_BLEND_TIME, clampf(rate, 0.8, 2.2))


func _play_motion(target: StringName, blend_time: float, speed: float = 1.0) -> void:
	var full := "moves/" + target
	if anim_player.current_animation != full:
		anim_player.play(full, blend_time)
	anim_player.speed_scale = speed


func _setup_held_flashlight() -> void:
	var pose_data := _load_flashlight_grip_pose()
	_hand_grip_modifier = HAND_GRIP_MODIFIER.new() as PlayerHandGripModifier
	_hand_grip_modifier.name = &"FlashlightGripModifier"
	var bone_rotations: Dictionary = pose_data.get("bone_rotations_degrees", {})
	for bone_name: String in bone_rotations:
		var values: Array = bone_rotations[bone_name]
		if values.size() >= 3:
			_hand_grip_modifier.set_bone_rotation(StringName(bone_name), Vector3(
					float(values[0]), float(values[1]), float(values[2])))
	_hand_grip_modifier.active = false
	skeleton.add_child(_hand_grip_modifier)
	_flashlight_attachment = BoneAttachment3D.new()
	_flashlight_attachment.name = &"FlashlightAttachment"
	_flashlight_attachment.bone_name = StringName(pose_data.get(
			"attachment_bone", pose_data.get("hand", String(FLASHLIGHT_HAND))))
	skeleton.add_child(_flashlight_attachment)
	_flashlight_model = FLASHLIGHT_MODEL.instantiate() as Node3D
	_flashlight_model.name = &"FlashlightModel"
	var object_scale := float(pose_data.get("object_scale", FLASHLIGHT_MODEL_SCALE))
	_flashlight_model.scale = Vector3.ONE * object_scale
	var position_values: Array = pose_data.get(
			"object_position", pose_data.get("flashlight_position", [0.02, 0.0, 0.0]))
	var rotation_values: Array = pose_data.get(
			"object_rotation_degrees",
			pose_data.get("flashlight_rotation_degrees", [0.0, 0.0, 0.0]))
	if position_values.size() < 3:
		position_values = [0.02, 0.0, 0.0]
	if rotation_values.size() < 3:
		rotation_values = [0.0, 0.0, 0.0]
	_flashlight_model.position = Vector3(
			float(position_values[0]), float(position_values[1]), float(position_values[2]))
	_flashlight_model.rotation_degrees = Vector3(
			float(rotation_values[0]), float(rotation_values[1]), float(rotation_values[2]))
	_flashlight_model.visible = false
	_flashlight_attachment.add_child(_flashlight_model)


func _load_flashlight_grip_pose() -> Dictionary:
	var file := FileAccess.open(FLASHLIGHT_GRIP_POSE_PATH, FileAccess.READ)
	if file == null:
		push_warning("Could not load flashlight grip pose")
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	push_warning("Flashlight grip pose is not valid JSON")
	return {}


func set_held_flashlight_visible(enabled: bool) -> void:
	_flashlight_model.visible = enabled and _equipped_model == null


func set_equipped_item(item: Item) -> void:
	if _equipped_attachment != null:
		_equipped_attachment.free()
		_equipped_attachment = null
		_equipped_model = null
	if item == null or item.world_scene == null:
		return
	_equipped_attachment = BoneAttachment3D.new()
	_equipped_attachment.name = &"EquippedItemAttachment"
	_equipped_attachment.bone_name = item.held_bone
	skeleton.add_child(_equipped_attachment)
	_equipped_model = item.world_scene.instantiate() as Node3D
	if _equipped_model == null:
		_equipped_attachment.free()
		_equipped_attachment = null
		return
	_equipped_model.name = &"EquippedItemModel"
	_equipped_model.scale = Vector3.ONE * item.held_scale
	_equipped_model.position = item.held_position
	_equipped_model.rotation_degrees = item.held_rotation_degrees
	_equipped_attachment.add_child(_equipped_model)


## Starts a one-shot action that temporarily owns the body animation. An
## optional normalized contact point emits action_contact once, allowing
## gameplay effects to align with the motion without living in this visual
## component. Normal locomotion resumes from animation_finished; jumping can
## interrupt the action and therefore prevent its pending contact.
func play_action_animation(animation_name: StringName, speed: float = 1.0,
		blend_time: float = 0.12, contact_ratio: float = -1.0) -> bool:
	if _action_animation != &"" or not _lib.has_animation(animation_name):
		return false
	var animation := _lib.get_animation(animation_name)
	if animation.loop_mode != Animation.LOOP_NONE:
		return false
	_debug_preview_active = false
	_action_animation = StringName("moves/" + String(animation_name))
	_action_contact_ratio = clampf(contact_ratio, 0.0, 1.0) if contact_ratio >= 0.0 else -1.0
	_action_contact_emitted = false
	_play_motion(animation_name, blend_time, speed)
	return true


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == _action_animation:
		_action_animation = &""
		_action_contact_ratio = -1.0
		_action_contact_emitted = false
		action_finished.emit(animation_name)


func is_action_active() -> bool:
	return _action_animation != &""


## Every clip the debug menu's animation preview can play, grouped for
## display. Gameplay aliases come first, followed by the native MotusMan
## references and then all raw UAL clips. Dictionary preserves insertion
## order, so the active gameplay set is always the first group.
func get_animation_groups() -> Dictionary:
	var gameplay_group: Array[StringName] = []
	for key: StringName in UAL_GAMEPLAY_CLIPS:
		gameplay_group.append(key)
	for key: StringName in UAL2_GAMEPLAY_CLIPS:
		gameplay_group.append(key)
	var native_group: Array[StringName] = []
	for key: StringName in CLIPS:
		native_group.append(key)
	var ual_group: Array[StringName] = []
	for clip_name: String in UAL_EXTRA_CLIPS:
		ual_group.append(StringName(clip_name))
	var ual2_group: Array[StringName] = []
	for clip_name: String in UAL2_EXTRA_CLIPS:
		ual2_group.append(StringName(clip_name))
	return {
		&"Gameplay - Unarmed": gameplay_group,
		&"MotusMan References": native_group,
		&"Universal Animation Library": ual_group,
		&"Universal Animation Library 2": ual2_group,
	}


## Resolves a local gameplay alias to the untouched UAL clip it was baked
## from. Native MotusMan references return an empty name because there is no
## equivalent animation on the UAL comparison model.
func get_animation_source_clip(anim_name: StringName) -> StringName:
	if UAL_GAMEPLAY_CLIPS.has(anim_name):
		return UAL_GAMEPLAY_CLIPS[anim_name]
	if UAL2_GAMEPLAY_CLIPS.has(anim_name):
		return UAL2_GAMEPLAY_CLIPS[anim_name]
	if String(anim_name) in UAL_EXTRA_CLIPS:
		return anim_name
	if String(anim_name) in UAL2_EXTRA_CLIPS:
		return anim_name
	return &""


func get_animation_source_pack(anim_name: StringName) -> StringName:
	if UAL_GAMEPLAY_CLIPS.has(anim_name) or String(anim_name) in UAL_EXTRA_CLIPS:
		return &"ual1"
	if UAL2_GAMEPLAY_CLIPS.has(anim_name) or String(anim_name) in UAL2_EXTRA_CLIPS:
		return &"ual2"
	return &""


## Debug menu only: play a clip once, directly, bypassing update_motion's
## normal state machine. Sets _debug_preview_active so update_motion() leaves
## it alone while the player just stands there watching it loop (closing the
## menu unpauses the tree, and update_motion() runs every physics tick - it
## would otherwise stomp the preview back to relaxed_idle on the very next
## tick). The moment the player actually moves/crouches/arms up,
## update_motion() reclaims control immediately, same as normal.
## UAL_EXTRA_CLIPS entries retarget on this first request. Each gets its own
## AnimationLibrary added on demand, rather than being merged into the
## already-playing "moves" library - mutating a library the AnimationPlayer
## is actively mid-crossfade on corrupts its internal blend state and
## crashes the engine after a handful of distinct clips (reproduced: adding
## a 5th distinct clip to a live-blending library segfaults every time,
## regardless of which clips; a fresh per-clip library sidesteps it).
func play_debug_anim(anim_name: StringName, blend_time: float = 0.2) -> void:
	if not _lib.has_animation(anim_name) and (String(anim_name) in UAL_EXTRA_CLIPS
			or String(anim_name) in UAL2_EXTRA_CLIPS):
		anim_player.stop()
		var source_path := UAL2_PATH if String(anim_name) in UAL2_EXTRA_CLIPS else UAL_PATH
		_lib.add_animation(anim_name, _retarget_clip(source_path, anim_name, _held_pose))
	anim_player.play("moves/" + anim_name, blend_time)
	anim_player.speed_scale = 1.0
	_debug_preview_active = true
