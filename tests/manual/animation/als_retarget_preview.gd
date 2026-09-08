extends Node3D
## Side-by-side comparison: the ALS mannequin's own animations played on its
## own standalone skeleton (left) versus the same source clips retargeted
## onto Y Bot (a candidate character for AGENT_TASKS/016's locomotion
## prototype, being evaluated here before swapping the prototype scene over -
## X Bot was tried first but looks visibly feminine/androgynous, not a good
## match for the muscular ALS reference mesh shown on the left) via
## tools/retarget_cli.gd (right). Each source FBX under
## assets/models/als_mannequin_standalone/ carries exactly one animation of
## its own, named "Unreal Take" by Unreal's FBX exporter - collected here
## into one AnimationLibrary per character, same pattern as
## tests/manual/animation/animation_preview.gd.
## Previously compared against MotusMan (see git history for that variant) -
## repointed to X Bot rather than kept as a third column, since this scene's
## purpose is spot-checking whatever retarget target is currently in
## question, not maintaining a permanent gallery.

const STANDALONE_CLIPS: Dictionary = {
	&"walk": "res://assets/models/als_mannequin_standalone/ALS_N_Walk_F.fbx",
	&"sword_a": "res://assets/models/als_mannequin_standalone/AS_Sword_A.fbx",
	&"sword_b": "res://assets/models/als_mannequin_standalone/AS_Sword_B.fbx",
	&"sword_c": "res://assets/models/als_mannequin_standalone/AS_Sword_C.fbx",
}

const RETARGETED_CLIPS: Dictionary = {
	&"walk": "res://assets/models/als_retarget_test/ALS_N_Walk_F_on_ybot.res",
	&"sword_a": "res://assets/models/als_retarget_test/AS_Sword_A_on_ybot.res",
	&"sword_b": "res://assets/models/als_retarget_test/AS_Sword_B_on_ybot.res",
	&"sword_c": "res://assets/models/als_retarget_test/AS_Sword_C_on_ybot.res",
}

const CLIP_ORDER: PackedStringArray = ["walk", "sword_a", "sword_b", "sword_c"]
const SECONDS_PER_CLIP := 2.5

var _clip_index := 0
var _standalone_player: AnimationPlayer
var _motusman_player: AnimationPlayer

@onready var _label: Label = $UI/CurrentClipLabel


func _ready() -> void:
	_standalone_player = _setup_standalone()
	_motusman_player = _setup_motusman_retarget()
	_play_current_clip()
	var timer := Timer.new()
	timer.wait_time = SECONDS_PER_CLIP
	timer.autostart = true
	timer.timeout.connect(_on_clip_timer_timeout)
	add_child(timer)


## Each source FBX under als_mannequin_standalone/ is its own standalone
## Unreal export with its own internal node layout: AnimMan.fbx (carries the
## skinned mesh) nests its Skeleton3D one level deeper ("AnimMan/Skeleton3D")
## than the animation-only clip exports like AS_Sword_A.fbx ("Skeleton3D"
## directly) - confirmed by dumping both hierarchies directly, not assumed.
## A clip's own baked track paths are only valid relative to ITS OWN
## AnimationPlayer's root_node, so copying one verbatim onto a different
## AnimationPlayer silently fails to resolve every track (Godot logs a
## per-track warning and animates nothing). Every track is rewritten here to
## point at the TARGET skeleton's real path instead of trusting the source's.
func _setup_standalone() -> AnimationPlayer:
	var ap: AnimationPlayer = $AlsStandalone.find_child("AnimationPlayer", true, false)
	var target_skeleton: Node = $AlsStandalone.find_child("Skeleton3D", true, false)
	# Track paths are relative to the AnimationPlayer's own root_node, not to
	# the AnimationPlayer itself - resolving root_node first (rather than
	# using ap.get_path_to() directly) was the actual bug the first version
	# of this fix had: it produced "../AnimMan/Skeleton3D" (relative to ap)
	# instead of "AnimMan/Skeleton3D" (relative to ap's root_node, which is
	# ap's own parent here), so every track still failed to resolve.
	var anim_root: Node = ap.get_node(ap.root_node)
	var skeleton_path := anim_root.get_path_to(target_skeleton)
	var lib := AnimationLibrary.new()
	for clip_name: StringName in STANDALONE_CLIPS:
		var inst: Node = (load(STANDALONE_CLIPS[clip_name]) as PackedScene).instantiate()
		var src_ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
		var anim: Animation = _find_animation(src_ap, &"Unreal Take").duplicate()
		anim.loop_mode = Animation.LOOP_LINEAR
		_retarget_track_paths(anim, skeleton_path)
		lib.add_animation(clip_name, anim)
		inst.free()
	ap.add_animation_library(&"clips", lib)
	return ap


## Rewrites every track's NodePath to point at new_skeleton_path, keeping
## each track's own bone-name subname (e.g. ":pelvis") intact.
func _retarget_track_paths(anim: Animation, new_skeleton_path: NodePath) -> void:
	for t in anim.get_track_count():
		var old_path := anim.track_get_path(t)
		if old_path.get_subname_count() == 0:
			continue
		var bone_name := old_path.get_subname(0)
		anim.track_set_path(t, NodePath(String(new_skeleton_path) + ":" + String(bone_name)))


## Y Bot's own embedded material loads correctly out of the box (no stale
## author-machine texture path to fix, unlike MotusMan's FBX - see git
## history for the material-reapply workaround this used to need).
func _setup_motusman_retarget() -> AnimationPlayer:
	var ap: AnimationPlayer = $MotusManRetargeted.find_child("AnimationPlayer", true, false)
	var lib := AnimationLibrary.new()
	for clip_name: StringName in RETARGETED_CLIPS:
		var anim: Animation = (load(RETARGETED_CLIPS[clip_name]) as Animation).duplicate()
		anim.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(clip_name, anim)
	ap.add_animation_library(&"clips", lib)
	return ap


func _find_animation(anim_player: AnimationPlayer, requested_name: StringName) -> Animation:
	for lib_name in anim_player.get_animation_library_list():
		var lib := anim_player.get_animation_library(lib_name)
		if lib.has_animation(requested_name):
			return lib.get_animation(requested_name)
	return null


func _on_clip_timer_timeout() -> void:
	_clip_index = (_clip_index + 1) % CLIP_ORDER.size()
	_play_current_clip()


func _play_current_clip() -> void:
	var clip_name := CLIP_ORDER[_clip_index]
	_standalone_player.play("clips/" + clip_name)
	_motusman_player.play("clips/" + clip_name)
	_label.text = "Clip: %s  (left: ALS standalone · right: retargeted onto MotusMan)" % clip_name
