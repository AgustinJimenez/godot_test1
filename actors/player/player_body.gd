class_name PlayerBody
extends Node3D
## First-person body: the MotusMan mesh attached under the player so you see
## your own torso/legs and cast a shadow. The scene this script sits on is the
## aim-idle clip FBX, but gameplay locomotion is retargeted from UAL onto its
## skeleton. Native MotusMan clips remain loaded as debug references.

signal action_finished(animation_name: StringName)
signal action_contact(animation_name: StringName)
## Emitted after swap_character() rebuilds around a new skeleton - anything that cached a bone
## index or the skeleton reference itself needs this to recompute rather than keep pointing stale.
signal character_changed

const CLIP_DIR := "res://assets/models/pistol_starter/Animation/In-Place/"
const CLIPS := {
	&"relaxed_idle": "W1_Stand_Relaxed_Idle_IPC",
	&"aim_idle": "W1_Stand_Aim_Idle_IPC",
	&"walk": "W1_Walk_Aim_F_Loop_IPC",
	&"jog": "W1_Jog_Aim_F_Loop_IPC",
	&"crouch_idle": "W1_Crouch_Aim_Idle_IPC",
	&"crouch_walk": "W1_CrouchWalk_Aim_F_Loop_IPC",
}
## Some MotusMan FBX exports (the animation-bundled clip files under MotusMan_MODEL_DIR
## specifically - confirmed live via a mesh-material inspection: W1_Stand_Aim_Idle_IPC.fbx's
## own material has a null albedo_texture, while MotusMan_v55.fbx's own material already has
## a correct one) bake a broken absolute texture path, leaving Godot's FBX importer with no
## usable albedo. _apply_skin_texture_fallback() reapplies this diffuse - but only for
## MotusMan specifically, and only when the imported mesh doesn't already have its own
## working texture. Applying it unconditionally to every character_scene (the pre-swap-
## character behavior, when only MotusMan could ever be loaded) paints MotusMan's own
## diffuse across whatever UV layout a *different* skin's mesh actually has, looking like
## scrambled/mixed textures - a real bug a user found by testing X Bot through the debug
## menu's character swap.
const SKIN_TEXTURE := "res://assets/models/pistol_starter/MotusMan/sourceimages/MCG_diff.jpg"
const MOTUSMAN_MODEL_DIR := "res://assets/models/pistol_starter/"
const FLASHLIGHT_MODEL := preload("res://assets/models/flashlight/flashlight.glb")
const HAND_GRIP_MODIFIER := preload("res://actors/player/player_hand_grip_modifier.gd")
const FOOT_IK_MODIFIER := preload("res://actors/player/player_foot_ik_modifier.gd")
const SKELETON_VISUALIZER := preload("res://actors/player/player_skeleton_debug_visualizer.gd")
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

## Legs default to the same global rest-relative delta transfer as spine - fine for a walk
## cycle's shallow knee bend, but a deep crouch/hunch (e.g. Pistol_Aim_Down) exposes the same
## rig-axis-mismatch problem that pushed arms onto swing retargeting: a ~59 degree secondary-axis
## "twist" shows up on the knee for that clip, where a real hinge joint should show almost none -
## the leg swings out sideways instead of just bending forward. SWING reuses the exact same
## technique arms use, on the leg chain.
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
var _foot_ik_modifier: PlayerFootIKModifier
var _skeleton_visualizer: PlayerSkeletonDebugVisualizer
var _flashlight_attachment: BoneAttachment3D
var _flashlight_model: Node3D
var _equipped_attachment: BoneAttachment3D
var _equipped_model: Node3D
## Remembered purely so swap_character() can restore it after rebuilding
## around a new skeleton - the attachment/model themselves don't survive
## the swap (they're children of the old skeleton, freed with it).
var _equipped_item: Item
var _airborne := false
var _landing_time_left := 0.0
var _action_animation := &""
var _action_contact_ratio := -1.0
var _action_contact_emitted := false

## True while a debug-menu clip is being previewed, so update_motion() doesn't immediately stomp
## it back to relaxed_idle on the next physics tick (e.g. right when the tree unpauses after
## closing the menu overlay). Cleared the moment the player actually does something that should
## visibly change the animation anyway (move, crouch, arm the weapon) - only suppressed while
## they're just standing still watching the preview.
var _debug_preview_active := false

## The visual skin - defaults to MotusMan so a plain player.tscn instance needs zero config, same
## as before this became configurable. Instantiated as a child in _setup_character_scene() rather
## than being the node this script itself sits on (which is what a direct FBX-instance node/scene
## like player.tscn's old "Body" node used to be) - mirrors HumanoidActor._setup_character()'s
## existing pattern for NPCs, the already-proven way to keep body execution independent of the
## visual skin.
@export var character_scene: PackedScene = preload(
		"res://assets/models/pistol_starter/Animation/In-Place/W1_Stand_Aim_Idle_IPC.fbx")

## The instantiated character_scene root. Not @onready - it has to exist
## before skeleton/anim_player/mesh can be found as its descendants, so
## _setup_character_scene() builds all four together, explicitly, first
## thing in _ready().
var character: Node3D
var anim_player: AnimationPlayer
var skeleton: Skeleton3D
var mesh: MeshInstance3D

## Computed once in _setup_character_scene() and reused for every clip
## _retarget_clip() bakes (~15 calls during _ready() alone) - detecting the
## skeleton's bone convention and building a full humanoid_map on every
## single call would be redundant, avoidable work.
var _retarget_config: HumanoidRetargeter.BoneMapConfig

## role name (the same canonical names BONE_MAP's values and player.gd's TORSO_CLEARANCE keys
## use, e.g. "Head"/"Spine2"/"LeftShoulder") -> the *current* skeleton's own real bone name.
## Identity for MotusMan (its bones already use these names literally) but not for a prefixed
## skin like x_bot ("mixamorig_Head") - anything outside this script that looks up a bone by its
## canonical role name (player.gd's head/torso-clearance tracking) must resolve through
## resolve_bone_name() rather than assuming the plain role name is also the real bone name.
var _target_humanoid_map: Dictionary

## Tool instances can disable the gameplay idle so they initially expose the
## imported skeleton pose. Gameplay scenes retain the existing default.
var autoplay_default_animation := true


## Instantiates character_scene and finds its Skeleton3D/AnimationPlayer/mesh generically - mesh
## is "the first MeshInstance3D found", matching MotusMan's own single-mesh shape today.
func _setup_character_scene() -> void:
	character = character_scene.instantiate() as Node3D
	character.name = &"Character"
	add_child(character)
	skeleton = character.find_child("Skeleton3D", true, false) as Skeleton3D
	anim_player = character.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim_player == null:
		anim_player = AnimationPlayer.new()
		anim_player.name = &"AnimationPlayer"
		character.add_child(anim_player)
	# "Skeleton3D:bone" tracks resolve via root_node; Blender's Armature wrapper nests it deeper.
	anim_player.root_node = anim_player.get_path_to(skeleton.get_parent())
	var meshes := character.find_children("*", "MeshInstance3D", true, false)
	mesh = meshes[0] as MeshInstance3D if not meshes.is_empty() else null
	_target_humanoid_map = _detect_target_humanoid_map(skeleton, character_scene.resource_path)
	_retarget_config = HumanoidRetargeter.build_bone_map_config(BONE_MAP, _target_humanoid_map)


func _ready() -> void:
	_apply_stored_profile_character()
	_setup_character_scene()
	_build_character_visuals()

## Spawns as the Creator's chosen catalog character (ui/character_creator.gd via PlayerProfile).
func _apply_stored_profile_character() -> void:
	if not PlayerProfile.has_profile:
		return
	var model_path: String = _stored_profile_info().get("model_path", "")
	var scene: Variant = load(model_path) if not model_path.is_empty() else null
	if scene is PackedScene:
		character_scene = scene

func _stored_profile_info() -> Dictionary:
	return CharacterCatalog.list_all().get(PlayerProfile.character_kind, {})

var _cosmetic_attachments: Dictionary = {}

## Applies the Creator's cosmetic choices if character_scene matches the stored kind_id.
func _apply_stored_profile_cosmetics() -> void:
	var info := _stored_profile_info()
	if String(info.get("model_path", "")) != character_scene.resource_path:
		return
	PlayerBodyCosmetics.apply_skin_tone(
			character, PlayerProfile.character_kind, PlayerProfile.skin_tone)
	PlayerBodyCosmetics.apply_eye_color(
			character, PlayerProfile.character_kind, PlayerProfile.eye_color_id)
	_cosmetic_attachments = PlayerBodyCosmetics.apply_head_attachments(
			skeleton, resolve_bone_name(&"Head"), PlayerProfile.character_kind,
			PlayerProfile.hairstyle_id, PlayerProfile.facial_hair_id, PlayerProfile.eyebrows_id,
			PlayerProfile.hair_color_id, _cosmetic_attachments)

## Rebuilds everything _ready() built around the skeleton - material, the
## look/hand-grip/foot-IK modifiers, the held flashlight attachment, and
## the full retargeted "moves" library - all of which reference the specific
## Skeleton3D/AnimationPlayer _setup_character_scene() just found and can't outlive it.
## Shared by _ready() (first setup) and swap_character() (a later runtime re-skin,
## e.g. from the debug menu's character list) so there is exactly one place this
## construction happens, not two versions that can drift.
func _build_character_visuals() -> void:
	# Lets the debug menu's animation preview keep looping while the pause
	# menu has the rest of the game (including this node's own parent,
	# Player, which is PAUSABLE by design) frozen.
	anim_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_skin_texture_fallback()
	_look_pose_modifier = PlayerLookPoseModifier.new()
	_look_pose_modifier.name = &"LookPoseModifier"
	_look_pose_modifier.player_body = self
	skeleton.add_child(_look_pose_modifier)
	skeleton.set_modifier_callback_mode_process(Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS)
	_foot_ik_modifier = FOOT_IK_MODIFIER.new() as PlayerFootIKModifier
	_foot_ik_modifier.player_body = self
	skeleton.add_child(_foot_ik_modifier)
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
	_apply_stored_profile_cosmetics()


## Swaps the live player's visible skin at runtime - the debug menu's character list
## (ui/hud.gd) calls this so a player can become any catalog character mid-session
## without a scene reload, the concrete proof this project's player-swappable-skin
## plan set out for (see CURRENT_TASK.md Phase 5). Frees the whole old character
## subtree (skeleton and everything attached to it - look/hand-grip/foot-IK
## modifiers, flashlight/held-item attachments) and rebuilds fresh around the new
## one, then restores whatever was equipped/visible so the swap is invisible to
## inventory state. Not free: rebaking ~15 retargeted clips is the same synchronous
## cost _ready() already pays once at scene start - callers on a paused debug menu
## should let a frame render a loading message first (see ui/hud.gd's character
## panel) rather than call this directly off a button's pressed signal.
func swap_character(new_character_scene: PackedScene) -> void:
	var previous_torch_visible := is_instance_valid(_flashlight_model) and _flashlight_model.visible
	var previous_item := _equipped_item
	if character != null:
		character.free()
	# character.free() already destroyed all of these (they're children of
	# the old skeleton, which was itself a child of character) - null them
	# out rather than leave stale references to freed instances. Without
	# this, set_equipped_item()/_setup_held_flashlight() below would call
	# .free() a second time on an already-freed object.
	_look_pose_modifier = null
	_hand_grip_modifier = null
	_foot_ik_modifier = null
	_skeleton_visualizer = null
	_flashlight_attachment = null
	_flashlight_model = null
	_equipped_attachment = null
	_equipped_model = null
	_cosmetic_attachments = {}
	character_scene = new_character_scene
	_setup_character_scene()
	_build_character_visuals()
	set_equipped_item(previous_item)
	set_held_flashlight_visible(previous_torch_visible)
	character_changed.emit()


## Resolves a canonical role name (BONE_MAP's values, and the same names
## player.gd's TORSO_CLEARANCE keys use - "Head", "Spine2", "LeftShoulder",
## etc.) to the *current* skeleton's own real bone name. Identity for
## MotusMan (its bones already use these names literally); not for a
## prefixed skin ("Head" -> "mixamorig_Head" on x_bot). Falls back to the
## role name itself if unmapped, matching the old hardcoded-name behavior
## for any role a target skeleton's humanoid_map doesn't cover.
func resolve_bone_name(role: StringName) -> StringName:
	return StringName(_target_humanoid_map.get(role, role))


## Debug menu "Show Skeleton" toggle - lazily builds the visualizer on
## first use so a player who never opens the debug menu never pays for it.
func set_skeleton_visible(enabled: bool) -> void:
	if _skeleton_visualizer == null:
		if not enabled:
			return
		_skeleton_visualizer = SKELETON_VISUALIZER.new() as PlayerSkeletonDebugVisualizer
		skeleton.add_child(_skeleton_visualizer)
	_skeleton_visualizer.mesh_instance.visible = enabled


## Copies a differently-rigged clip's tracks onto MotusMan's skeleton via BONE_MAP. Deltas are
## computed and reapplied in GLOBAL (skeleton-root) space, not each bone's parent-relative local
## space - see BONE_MAP's doc comment for why: a naive local-space "delta from own rest,
## reapplied to target's own rest" compounds the two rigs' differing bone-forward-axis
## conventions at every parent hop, and arms sit 6-7 hops deep (through the whole spine) versus
## 3-4 for legs, which is exactly why legs retargeted fine before while arms spread into a T-pose
## every time. Working in global space means each bone's delta is only ever relative to its OWN
## rest, with no compounding, regardless of chain depth.
##
## This requires resampling the source clip at fixed intervals (its own keyframe times aren't
## used directly) because a bone's global pose depends on its whole ANIMATED ancestor chain, not
## just its own track.
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

	# The real gameplay path (use_humanoid_retarget defaults true) delegates entirely to
	# HumanoidRetargeter - proven bit-for-bit equivalent to this function's own former inline copy
	# of the same algorithm (see CURRENT_TASK.md's Phase 1: verified live via test_retarget_parity
	# against this exact "moves" library, across two different clips, with the only divergence
	# being the arm FABRIK step's inherent redundant-DOF sensitivity - present even when this
	# function's old code retargeted the same clip twice in a row against itself). Everything
	# below this early return is debug-only scaffolding for the throwaway hand/leg retarget-mode
	# comparison scene and is never reached in real gameplay.
	if use_humanoid_retarget:
		var anim := HumanoidRetargeter.retarget_clip(
				src_skeleton, src, skeleton, _retarget_config, force_loop)
		clip_root.free()
		return anim

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
	clip_root.free()
	if hand_retarget_mode == HandRetarget.FROZEN:
		for hand_bone in HAND_BONES:
			PlayerBodyPoseMath.bake_held_track(anim, hand_bone, held_pose, src.length)
	return anim


## Detects target_skeleton's own bone-naming convention (MotusMan by default, but not assumed -
## see CURRENT_TASK.md's Phase 4) and returns its role-name -> real-bone-name table (role names
## being BONE_MAP's target-side convention, e.g. "Hips"/"Head"/"LeftShoulder"). Used both to
## build this skeleton's BoneMapConfig (see _setup_character_scene()) and, via
## resolve_bone_name(), by anything outside the retargeter that needs to look up one specific
## bone by its canonical role (held-item/flashlight attachment points, player.gd's head/torso-
## clearance tracking). Mirrors the same null/"B-" special case
## character_editor_import_handler.gd's _import_character already uses (those skeletons don't
## follow the simple "prefix + role" pattern reliably enough for full_map_from_prefix). Prefers
## a catalog manifest's own humanoid_map (curated, already verified complete by the character
## editor's Rig tab when it was set up) over re-detecting one from the skeleton -
## detect_bone_prefix() only recognizes "<prefix>Hips"/"B-hips" conventions, not every bone
## naming a catalog character might use (e.g. Universal Base Characters' UE-Mannequin
## "pelvis"/"clavicle_l" names, which have no prefix to detect at all). Falls back to the
## original re-detection for anything not in the catalog (raw test scenes, characters added
## before this existed).
static func _detect_target_humanoid_map(
		target_skeleton: Skeleton3D, model_path: String) -> Dictionary:
	for info: Dictionary in CharacterCatalog.list_all().values():
		if String(info.get("model_path", "")) == model_path:
			var humanoid_map: Dictionary = info.get("humanoid_map", {})
			if not humanoid_map.is_empty():
				return humanoid_map
	var prefix = HumanoidRetargeter.detect_bone_prefix(target_skeleton)
	return (
			CharacterEditorRigHandler.auto_map(target_skeleton)
			if prefix == null or prefix == "B-"
			else CharacterEditorRigHandler.full_map_from_prefix(target_skeleton, prefix))


## Retargets a bone by matching WHERE IT POINTS (its own to its child's global position, i.e.
## the direction of the bone itself in world space) rather than transferring its full rotation.
## Positions carry no "which local axis means forward" ambiguity at all, so this sidesteps the
## exact question full rotation transfer needs to get right - and gets wrong for the arms
## specifically, every attempt so far (spread into a T-pose). Trade-off: no roll/twist (e.g.
## forearm pronation) survives, only the swing - not very visible on this rig at typical camera
## distance for a walk cycle.
##
## This world-space version is known to overcorrect a bone low in a heavily-pre-rotated chain
## (e.g. a knee under a hip that's bent forward a lot - see
## docs/task_history/ual_animation_retargeting.md "Bug 3 update 3"). A parent-relative rework was
## attempted twice and made things worse (see "Bug 3 update 4" in that history) - re-expressing
## the swing in the parent's own local axis convention reintroduces exactly the axis-mismatch
## problem this world-space approach was built to avoid in the first place. Reverted to this
## version deliberately; do not re-attempt the same parent-relative approach without a
## fundamentally different idea for avoiding that.
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


## See SKIN_TEXTURE's doc comment for why this only reapplies MotusMan's own
## diffuse, and only when the mesh's own imported material genuinely has no
## texture of its own - most other catalog characters (x_bot/y_bot
## included) import with either a real texture or an intentional flat
## preview color (Mixamo's "Beta" material), and should be left alone.
func _apply_skin_texture_fallback() -> void:
	if mesh == null:
		return
	var existing := mesh.get_active_material(0) as BaseMaterial3D
	if existing != null and existing.albedo_texture != null:
		return
	if not character_scene.resource_path.begins_with(MOTUSMAN_MODEL_DIR):
		return
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(SKIN_TEXTURE)
	material.roughness = 0.85
	mesh.material_override = material


func _setup_held_flashlight() -> void:
	var pose_data := _load_flashlight_grip_pose()
	_hand_grip_modifier = HAND_GRIP_MODIFIER.new() as PlayerHandGripModifier
	_hand_grip_modifier.name = &"FlashlightGripModifier"
	# bone_rotations_degrees/attachment_bone are authored against MotusMan's
	# canonical role names (matching BONE_MAP's target-side convention) -
	# resolve_bone_name() translates that to whatever the *current* skeleton
	# actually calls that bone (identity for MotusMan, "mixamorig_"-prefixed
	# for x_bot/y_bot) so the grip pose still lands on the right joint after
	# a runtime skin swap.
	var bone_rotations: Dictionary = pose_data.get("bone_rotations_degrees", {})
	for bone_name: String in bone_rotations:
		var values: Array = bone_rotations[bone_name]
		if values.size() >= 3:
			_hand_grip_modifier.set_bone_rotation(resolve_bone_name(StringName(bone_name)), Vector3(
					float(values[0]), float(values[1]), float(values[2])))
	_hand_grip_modifier.active = false
	skeleton.add_child(_hand_grip_modifier)
	_flashlight_attachment = BoneAttachment3D.new()
	_flashlight_attachment.name = &"FlashlightAttachment"
	_flashlight_attachment.bone_name = resolve_bone_name(StringName(pose_data.get(
			"attachment_bone", pose_data.get("hand", String(FLASHLIGHT_HAND)))))
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
	_equipped_item = item
	if _equipped_attachment != null:
		_equipped_attachment.free()
		_equipped_attachment = null
		_equipped_model = null
	if item == null or item.world_scene == null:
		return
	_equipped_attachment = BoneAttachment3D.new()
	_equipped_attachment.name = &"EquippedItemAttachment"
	# item.held_bone is authored as a canonical role name too - see
	# _setup_held_flashlight()'s comment on resolve_bone_name().
	_equipped_attachment.bone_name = resolve_bone_name(item.held_bone)
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
