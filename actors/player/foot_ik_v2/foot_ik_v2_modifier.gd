class_name FootIKV2Modifier
extends SkeletonModifier3D
## v2 foot IK. The pass itself runs in C++ (FootIKV2CoreNative, native/planet_crust/src/foot_ik_core_native.cpp, AGENT_TASKS/091): this node is the shell the rest of
## the project talks to. It keeps the exported settings (the core reads them every pass), the debug_* / final_* members the lab, the traces and the checks read (the core
## writes into the SAME Dictionaries), the leg set-up and the native ledge (the sole and the ledge are native classes too). The GDScript pass it replaced is in git history (commit 8e07f4c and before).
const DEBUG_TIMER := preload("res://actors/player/foot_ik_v2/foot_ik_v2_debug.gd")
const LEGS := { # humanoid roles, resolved through PlayerBody for any character
	&"left": {"hip": &"LeftUpLeg", "knee": &"LeftLeg", "foot": &"LeftFoot",
		"toe": &"LeftToeBase"},
	&"right": {"hip": &"RightUpLeg", "knee": &"RightLeg", "foot": &"RightFoot",
		"toe": &"RightToeBase"},
}

@export var enabled := true
@export var foot_lock := false # EXPERIMENT: a resting foot stays planted while the body turns
@export_range(0.0, 170.0, 1.0) var max_knee_flexion_deg := 150.0 # v1 defaults; 0 = off
@export_range(0.0, 170.0, 1.0) var max_hip_swing_deg := 140.0 # cone from down; a crouch needs >100
@export var joint_speed_deg := 60.0 # joint correction change cap per frame at rest: a flip guard
@export_flags_3d_physics var ground_mask := 1 | (1 << 5)
@export var fallback_floor_max_angle_deg := 46.0
@export var max_surface_drop := 0.45
@export var ray_up := 0.5
@export var ray_down := 1.2
## How far the ankle sits above ground when planted. Negative derives it from the rig's rest pose.
@export var ankle_height := -1.0
## 0 = keep the authored pose, 1 = fully plant on the sampled ground.
@export_range(0.0, 1.0) var weight := 1.0
## When a foot's target is past the leg's reach, lower the pelvis by the shortfall, up to this.
@export var max_pelvis_drop := 0.40
@export var moving_pelvis_drop := 0.06
@export var still_speed := 0.5
@export var jump_counts_as_moving := true
## Let the body follow the capsule's height smoothly instead of popping a whole tread per step.
@export var body_smooth := true
@export var body_follow_rate := 12.0
@export var body_max_lag := 0.18
@export var support_snap := true
@export var support_search := 0.16
const BODY_ROLES: Array[StringName] = [&"Hips", &"Spine", &"Spine1", &"Spine2", &"LeftShoulder",
		&"RightShoulder", &"LeftArm", &"RightArm"]

@export var pelvis_attack_speed := 1.5
## How fast the pelvis drop may GROW (m/s) while moving or jumping (release stays normal).
@export var moving_pelvis_rate := 0.25
@export var pelvis_release_speed := 0.6
## At rest, a foot whose floor is out of reach may be brought this far toward the body first.
@export var max_stance_shift := 0.30
## At rest, a foot still out of reach reaches as far as the leg allows instead of releasing.
@export var reach_when_still := true
## The same while walking: a foot briefly out of reach reaches as far as it can instead of popping.
@export var reach_when_moving := true
## Fade the correction out smoothly as a foot lifts, instead of snapping it the frame it swings.
@export var plant_fade := true
## Planted at least this much may still clamp toward an out-of-reach surface; below it, releases.
@export_range(0.0, 1.0, 0.05) var reach_clamp_plant_min := 0.85
## Filter the sampled floor height so a foot at a tread edge does not chase the ray flip-flopping.
@export var ground_filter := true
## Lifted more than this above the sampled ground = mid-swing, left to the animation.
@export var max_lift := 0.25
var player_body: PlayerBody
## side -> the target last corrected toward, and why skipped (the trace logs the REAL decision).
var debug_target: Dictionary = {}
var debug_skip_reason: Dictionary = {}
var debug_ground_normal: Dictionary = {}
## side -> animated ankle, sampled ground and reach check (swing skip vs out of reach, in traces).
var debug_animated_ankle: Dictionary = {}
var debug_ground: Dictionary = {}
## side -> name of the collider the ground ray hit (which surface owns the contact).
var debug_surface: Dictionary = {}
var debug_last_frame := -1
var debug_passes := 0
## bone index -> world Transform3D as published at the end of the last pass, and its physics frame.
var final_pose: Dictionary = {}
var final_frame := -1
var final_basis := Basis.IDENTITY
var debug_pelvis_drop := 0.0 # the pelvis drop applied this frame (m), for the trace
var debug_solve: Dictionary = {}
## side -> {hip_to_target, reach}: the reach decision every frame, released or not (trace).
var debug_reach_check: Dictionary = {}
## side -> "released", "at_target", or "stretched" (out of reach): grades only feet meant down.
var debug_state: Dictionary = {}
var debug_stepping: Dictionary = {} # side -> walking a step (a graded float is expected)
## side -> {"before_deg", "after_deg", "applied"}: sole vs surface normal before/after the align.
var debug_align: Dictionary = {}
var debug_support_shift: Dictionary = {} # side -> how far the foot was slid along its length to sit on one surface (trace)
var debug_body_lag := 0.0
var debug_plant_weight: Dictionary = {} # side -> how planted the animation has this foot, 1 down .. 0 swinging (trace)
var debug_stance_shift: Dictionary = {} # side -> metres the foot is currently brought in toward the body (trace)
var debug_stance_plan: Dictionary = {} # side -> [[shift, drop needed], ...] tried by the last stance plan (trace)
var debug_toe_lift: Dictionary = {} # side -> how far the toe/tip/heel clearance pass lifted the ankle target this frame (trace)
var ledge = ClassDB.instantiate(&"FootIKV2LedgeNative") # public: the player reads its step (FootIKV2LedgeNative)
## side -> {"hip", "knee", "foot", "upper", "lower", "rest_pole", ...}
var _legs: Dictionary = {}
var _sole: Dictionary = {} # side -> the cached skinned sole (FootIKV2SoleNative)
var _base: Dictionary = {} # side -> the animated hip / knee / foot poses captured once per frame (written by the core)
var _hips_bone := -1
var _is_moving := false # written by the core
var _core: RefCounted = null # FootIKV2CoreNative


func _ready() -> void:
	if player_body == null:
		player_body = get_skeleton().get_parent() as PlayerBody if get_skeleton() != null else null
	ledge.call(&"bind", self)
	_build_legs()
	if ClassDB.class_exists(&"FootIKV2CoreNative") and not OS.has_environment("PLANET_NO_NATIVE"):
		_core = ClassDB.instantiate(&"FootIKV2CoreNative")
		_core.call(&"reset")
	else:
		push_error("Foot IK v2 needs the native library (scripts/build_native.sh): the foot IK is off")


func _build_legs() -> void:
	_legs.clear()
	var skel := get_skeleton()
	if skel == null or player_body == null:
		return
	_hips_bone = skel.find_bone(player_body.resolve_bone_name(&"Hips"))
	for side: StringName in LEGS:
		var roles: Dictionary = LEGS[side]
		var hip := skel.find_bone(player_body.resolve_bone_name(roles["hip"]))
		var knee := skel.find_bone(player_body.resolve_bone_name(roles["knee"]))
		var foot := skel.find_bone(player_body.resolve_bone_name(roles["foot"]))
		if hip < 0 or knee < 0 or foot < 0:
			continue
		var hip_rest := skel.get_bone_global_rest(hip).origin
		var knee_rest := skel.get_bone_global_rest(knee).origin
		var foot_rest := skel.get_bone_global_rest(foot).origin
		var toe_bone := skel.find_bone(player_body.resolve_bone_name(roles["toe"]))
		var sole: RefCounted = ClassDB.instantiate(&"FootIKV2SoleNative")
		sole.call(&"build", skel, player_body.character, foot, toe_bone)
		_sole[side] = sole
		var sole_depth: float = sole.call(&"depth", skel)
		if ankle_height < 0.0:
			ankle_height = sole_depth
		var rest_direction := (foot_rest - hip_rest).normalized()
		var rest_pole := knee_rest - hip_rest
		rest_pole -= rest_direction * rest_pole.dot(rest_direction)
		_legs[side] = {
			"hip": hip, "knee": knee, "foot": foot,
			"toe": toe_bone,
			"toe_depth": maxf(0.0, skel.get_bone_global_rest(toe_bone).origin.y),
			"upper": hip_rest.distance_to(knee_rest),
			"lower": knee_rest.distance_to(foot_rest),
			"rest_pole": rest_pole.normalized(),
			"sole_local": (skel.get_bone_global_rest(foot).basis.inverse() * Vector3.DOWN).normalized(),
			"heel_local": sole.call(&"heel_local", skel),
		}


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or _legs.is_empty() or _core == null:
		return
	var t0 := DEBUG_TIMER.begin()
	_core.call(&"process", skel, self, delta)
	DEBUG_TIMER.end(&"total", t0)
	DEBUG_TIMER.frame_tick()


## The horizontal way the body should walk so both feet have ground (safe zone); ZERO when they do.
func ledge_push() -> Vector3:
	return ledge.call(&"push") if enabled and (not _is_moving or ledge.get(&"stepping")) else Vector3.ZERO
