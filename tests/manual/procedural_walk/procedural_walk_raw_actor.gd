class_name ProceduralWalkRawActor
extends RefCounted
## Raw (un-retargeted) source actor for the procedural gait lab: instantiates a Mixamo FBX with its
## own skeleton, skinned mesh and AnimationPlayer - no HumanoidRetargeter - beside the retargeted
## reference and the procedural output, so the three can be compared directly. Also exposes per-role
## world pose change from each rig's own rest pose (what a retarget must preserve) so "which limb is
## off" is a number. Owned-object file; it creates its own show switch and view, because the lab
## already sits at the line cap.

## The Mixamo stair FBXs are rig+animation only (no skinned mesh, verified 0 MeshInstance3D), so the
## raw clip is played on a project Mixamo character that does have a body. Same rig, so only the
## clip's bone prefix differs.
const CHARACTER := "res://assets/models/mixamo_characters/Y Bot.fbx"
const SOURCE_PREFIX := "mixamorig10_"
const STEP_PREDICTOR := preload(
		"res://tests/manual/procedural_walk/procedural_walk_step_predictor.gd")
const SOURCES: Dictionary = {
	&"stair_up": "res://assets/models/stair_clips/Walking Up The Stairs.fbx",
}
## Roles whose world-space pose change a retarget must carry over. Target-rig names (MotusMan's own
## names equal the canonical roles; the raw skeleton spells them prefixed).
const ROLES: Array[StringName] = [
	&"Spine2", &"Head", &"LeftArm", &"LeftForeArm", &"LeftHand",
	&"RightArm", &"RightForeArm", &"RightHand",
	&"LeftUpLeg", &"LeftLeg", &"LeftFoot", &"RightUpLeg", &"RightLeg", &"RightFoot",
]
const TARGET_HEIGHT := 1.7
const LANE_X := 2.8 # right of the retargeted reference, clear of the UI panel
## The tread under a toe jumps a whole step (0.18m) at each edge, so the clearance lift must ramp
## instead of snapping - measured as visible up/down popping without this.
const LIFT_RATE := 1.2

var root: Node3D
var skeleton: Skeleton3D
var player: AnimationPlayer
var clip_length := 0.0
var _raw_indices := {} # role -> raw bone index
var _parent: Node3D
var _built_mode := &""
var _shown := false
var _lift := 0.0
var _predictor = null
var _predictor_shown := true
var _check: CheckBox


## The show switch lives here so the lab does not need extra lines for it.
func build_ui(parent: VBoxContainer) -> void:
	_check = CheckBox.new()
	_check.text = "Show raw source (un-retargeted)"
	_check.toggled.connect(func(value: bool) -> void:
		_shown = value
		_apply_visibility())
	parent.add_child(_check)
	var predict := CheckBox.new()
	predict.text = "Show step plan (next 3 per foot)"
	predict.button_pressed = _predictor_shown
	predict.toggled.connect(func(value: bool) -> void:
		_predictor_shown = value
		_predictor.set_shown(value))
	parent.add_child(predict)


func attach_step_debug(character: Node3D, modifier: ProceduralWalkLabModifier) -> void:
	_predictor = STEP_PREDICTOR.new()
	_predictor.name = &"FootstepPlanDebug"
	character.add_child(_predictor)
	_predictor.bind(modifier.footstep_plan(), modifier.ground_height)
	_predictor.set_shown(_predictor_shown)


## Each mode is a different FBX, so rebuild when the mode changes, put the clip at the same point of
## its cycle as the lab, then apply the show switch.
func update(parent: Node3D, mode: StringName, anchor := Vector3.ZERO, modifier = null,
		delta := 0.0) -> void:
	_parent = parent
	if mode != _built_mode:
		_built_mode = mode
		if _predictor != null:
			_predictor.reset_validation()
		_clear()
		if SOURCES.has(mode):
			_build(mode)
		if _check != null:
			_check.disabled = root == null
			_check.text = ("Show raw source (un-retargeted)" if root != null
					else "Show raw source (no raw clip for this mode)")
		print("[RAW_ACTOR] mode=%s built=%s" % [mode, root != null])
	if root != null:
		_lift = move_toward(_lift, foot_lift(skeleton, modifier), LIFT_RATE * delta)
		root.global_position = anchor + Vector3(LANE_X, _lift, 0.0)
	var phase_radians := float(modifier.phase) if modifier != null else 0.0
	_sync(fposmod(phase_radians / TAU, 1.0))
	_apply_visibility()


func step_plan_is_stable() -> bool:
	return _predictor != null and _predictor.plan_is_stable()


## How far a rig that only plays a clip (no IK) must be raised so its toe sits on the tread under
## it. Only the toe joint is used: the ankle sits ~10cm higher and would over-lift.
static func foot_lift(rig: Skeleton3D, modifier) -> float:
	if rig == null or modifier == null:
		return 0.0
	var lift := 0.0
	for side: String in ["Left", "Right"]:
		var index := _rig_bone_static(rig, StringName(side + "ToeBase"))
		if index < 0:
			continue
		var world := rig.global_transform * rig.get_bone_global_pose(index).origin
		lift = maxf(lift, float(modifier.stair_support_height(world.z)) - world.y)
	return lift


## role -> world rotation relative to that role's own rest world rotation. A correct retarget makes
## this match the target rig's value for the same role.
func pose_deltas() -> Dictionary:
	var result := {}
	if skeleton == null:
		return result
	for role: StringName in _raw_indices:
		var index: int = _raw_indices[role]
		var rest := skeleton.get_bone_global_rest(index).basis
		var pose := skeleton.get_bone_global_pose(index).basis
		result[role] = (pose * rest.inverse()).get_rotation_quaternion()
	return result


## Per-role world pose difference (degrees) against a rig holding the target pose: a good retarget
## keeps these near zero, so the worst role names the broken limb.
func compare(target: Skeleton3D) -> Dictionary:
	var result := {}
	if target == null:
		return result
	var mine := pose_deltas()
	for role: StringName in mine:
		var index := target.find_bone(role)
		if index < 0:
			continue
		var rest := target.get_bone_global_rest(index).basis
		var pose := target.get_bone_global_pose(index).basis
		var theirs: Quaternion = (pose * rest.inverse()).get_rotation_quaternion()
		result[role] = rad_to_deg((mine[role] as Quaternion).angle_to(theirs))
	return result


func is_visible() -> bool:
	return root != null and root.visible


## Raw-vs-retarget summary plus the three-way foot row (ankle/toe height, tread under the foot and
## the gap, and each rig's foot rotation difference against the raw). The procedural rig needs its
## own modifier's published joint positions: reading its skeleton directly sees the animation pose,
## not the IK output.
func append_summary(label: Label, target: Skeleton3D, procedural: Skeleton3D,
		modifier) -> void:
	_ensure_label(target, "RETARGETED")
	_ensure_label(procedural, "PROCEDURAL")
	if root != null:
		_ensure_label(skeleton, "RAW")
	if root == null or not _shown:
		return
	var diffs := compare(target)
	if diffs.is_empty():
		return
	var worst := &""
	var worst_deg := 0.0
	var total := 0.0
	for role: StringName in diffs:
		total += float(diffs[role])
		if float(diffs[role]) > worst_deg:
			worst_deg = float(diffs[role])
			worst = role
	label.text += "\nraw vs retarget: mean %.1f deg, worst %s %.1f deg" % [
			total / float(diffs.size()), worst, worst_deg]
	label.text += "\n" + _foot_line("raw", {}, skeleton, null)
	label.text += "\n" + _foot_line("retargeted", diffs, target, null)
	label.text += "\n" + _foot_line("procedural", compare(procedural), procedural, modifier)


## One row: per side the ankle/toe world height, the tread height under that foot, the toe-to-tread
## gap, and the foot's rotation difference against the raw source.
func _foot_line(name: String, diffs: Dictionary, rig: Skeleton3D, modifier) -> String:
	var parts: Array[String] = []
	for side: String in ["Left", "Right"]:
		var ankle := _foot_position(StringName(side + "Foot"), rig, modifier)
		var toe := _foot_position(StringName(side + "ToeBase"), rig, modifier)
		var tread := float(modifier.stair_support_height(ankle.z)) if modifier != null else 0.0
		var delta: float = float(diffs.get(StringName(side + "Foot"), 0.0))
		parts.append("%s a%.3f t%.3f tread%.3f gap%+.3f d%.0f" % [
				side.substr(0, 1), ankle.y, toe.y, tread, toe.y - tread, delta])
	return "foot %-11s %s" % [name, " | ".join(parts)]


## One floating name per rig, so the three bodies are identifiable in the scene.
func _ensure_label(rig: Skeleton3D, text: String) -> void:
	if rig == null:
		return
	var parent := rig.get_parent() as Node3D
	if parent == null or parent.has_node("ActorLabel"):
		return
	var label := Label3D.new()
	label.name = &"ActorLabel"
	label.text = text
	label.font_size = 24 # half the old overlay size
	label.position = Vector3(0.0, 2.15, 0.0)
	parent.add_child(label)


func _foot_position(bone: StringName, rig: Skeleton3D, modifier) -> Vector3:
	if modifier != null and modifier.debug_joint_positions.has(bone):
		return modifier.debug_joint_positions[bone]
	var index := _rig_bone(rig, bone)
	if index < 0:
		return Vector3.ZERO
	return rig.global_transform * rig.get_bone_global_pose(index).origin


## Role -> bone index on an arbitrary rig: the raw skeleton is prefixed (mixamorig_LeftFoot) while
## the MotusMan ribs spell the roles directly (LeftFoot).
func _rig_bone(rig: Skeleton3D, role: StringName) -> int:
	return _rig_bone_static(rig, role)


static func _rig_bone_static(rig: Skeleton3D, role: StringName) -> int:
	var text := String(role)
	for i in rig.get_bone_count():
		var name := String(rig.get_bone_name(i))
		if name == text or name.ends_with("_" + text):
			return i
	return -1


func _build(mode: StringName) -> void:
	var packed := load(CHARACTER) as PackedScene
	if packed == null:
		return
	root = packed.instantiate() as Node3D
	root.rotation.y = PI
	root.position.x = LANE_X
	_parent.add_child(root)
	skeleton = _find_skeleton(root)
	player = _find_anim(root)
	if skeleton == null or player == null:
		_clear()
		return
	_scale_to_height()
	_map_roles()
	var clip := _load_remapped_clip(mode)
	if clip == null:
		return
	clip_length = clip.length
	var library := AnimationLibrary.new()
	library.add_animation(&"raw", clip)
	player.add_animation_library(&"raw", library)
	player.play(&"raw/raw")


## The source FBX's own clip, copied with every bone path renamed onto this character's skeleton.
func _load_remapped_clip(mode: StringName) -> Animation:
	var packed := load(SOURCES[mode]) as PackedScene
	if packed == null:
		return null
	var source := packed.instantiate() as Node3D
	var source_player := _find_anim(source)
	if source_player == null:
		source.free()
		return null
	var names := source_player.get_animation_list()
	var clip: Animation = (source_player.get_animation(names[0]).duplicate() as Animation
			if not names.is_empty() else null)
	source.free()
	if clip == null:
		return null
	# Backwards so removals do not shift the indices still to visit. A source bone this character
	# does not have is dropped, as is any position track that is not the root's: the dae source
	# carries positions on many bones from its own rig, and only the Hips position transfers (the
	# same single position track the retargeted .res clips have).
	for i in range(clip.get_track_count() - 1, -1, -1):
		var path := clip.track_get_path(i)
		if path.get_subname_count() == 0:
			continue
		var target := _character_bone(String(path.get_subname(0)))
		var is_hips := target != &"" and String(target).ends_with("Hips")
		if target == &"" or (clip.track_get_type(i) == Animation.TYPE_POSITION_3D
				and not is_hips):
			clip.remove_track(i)
		elif String(target) != String(path.get_subname(0)):
			clip.track_set_path(i, NodePath(String(skeleton.name) + ":" + String(target)))
	_make_in_place(clip)
	clip.loop_mode = Animation.LOOP_LINEAR
	return clip


## The Mixamo sources bake their own root travel into the Hips position track, so a looping raw
## playback walked forward and snapped back at the loop. Remove the linear drift (the same transform
## the shipped .res clips got) to keep only the oscillating bob, matching the in-place others.
func _make_in_place(clip: Animation) -> void:
	if clip.length <= 0.0:
		return
	for i in clip.get_track_count():
		if clip.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		var count := clip.track_get_key_count(i)
		if count < 2:
			continue
		var first: Vector3 = clip.track_get_key_value(i, 0)
		var drift: Vector3 = (clip.track_get_key_value(i, count - 1) as Vector3) - first
		for k in count:
			var u := clip.track_get_key_time(i, k) / clip.length
			clip.track_set_key_value(i, k, (clip.track_get_key_value(i, k) as Vector3) - drift * u)


## Map a source bone name (e.g. mixamorig10_RightArm) to this character's own bone name.
func _character_bone(source_bone: String) -> StringName:
	# Source prefixes vary per export (mixamorig10_, mixamorig9_, ...); the role name never has an
	# underscore, so dropping everything through the first one works for all of them.
	var role := (source_bone.substr(source_bone.find("_") + 1)
			if source_bone.contains("_") else source_bone)
	var index := _rig_bone_static(skeleton, StringName(role))
	return StringName(skeleton.get_bone_name(index)) if index >= 0 else &""


func _clear() -> void:
	if root != null:
		root.queue_free()
	root = null
	skeleton = null
	player = null
	clip_length = 0.0
	_raw_indices.clear()


func _sync(phase_fraction: float) -> void:
	if player == null or clip_length <= 0.0:
		return
	player.seek(fposmod(phase_fraction, 1.0) * clip_length, true)
	player.advance(0.0)


func _apply_visibility() -> void:
	if root != null:
		root.visible = _shown


func _scale_to_height() -> void:
	var top := 0.0
	for i in skeleton.get_bone_count():
		top = maxf(top, skeleton.get_bone_global_rest(i).origin.y)
	if top > 0.0001:
		root.scale = Vector3.ONE * (TARGET_HEIGHT / top)


func _map_roles() -> void:
	var prefix := ""
	for i in skeleton.get_bone_count():
		var bone_name := String(skeleton.get_bone_name(i))
		if bone_name.ends_with("Hips"):
			prefix = bone_name.trim_suffix("Hips")
			break
	for role: StringName in ROLES:
		var index := skeleton.find_bone(prefix + String(role))
		if index >= 0:
			_raw_indices[role] = index


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_anim(child)
		if found != null:
			return found
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null
