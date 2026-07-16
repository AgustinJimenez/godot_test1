@tool
extends Node3D
## Cheap "fake mirror": instead of rendering a live reflection (SubViewport
## textures are unreliable in Godot 4.6 once this scene is instanced inside
## another one - see godotengine/godot#115402), a second copy of the player's
## body stands behind the glass and is puppeted every frame to mirror the
## real player's position, rotation and animation. Classic survival-horror
## trick (Resident Evil's mirrors work the same way).

@onready var mirror_body: PlayerBody = $MirrorBody

var _mirror_z: float


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_mirror_z = global_position.z
	# Seen from outside, so show the full head instead of the FP collapse.
	mirror_body.hide_head = false


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var player := get_tree().get_first_node_in_group(&"player")
	if not player:
		return
	var body: PlayerBody = player.body
	var src := body.global_transform
	# Mirror the position across the glass, and turn the double to face back
	# out at the viewer (reflected_yaw = PI - yaw). We deliberately don't
	# true-mirror the whole basis (that needs a negative-determinant
	# transform) - on a skinned mesh that flips triangle winding and breaks
	# backface culling/normals, so left/right stays unswapped as a trade-off.
	var yaw := src.basis.get_euler().y
	mirror_body.global_transform = Transform3D(
			Basis(Vector3.UP, PI - yaw),
			Vector3(src.origin.x, src.origin.y, 2.0 * _mirror_z - src.origin.z))
	mirror_body.head_pitch = body.head_pitch

	# Copy the real body's animation state 1:1 so the double never drifts
	# out of sync with what the player is actually doing.
	var src_anim := body.anim_player
	var dst_anim := mirror_body.anim_player
	if dst_anim.current_animation != src_anim.current_animation:
		dst_anim.play(src_anim.current_animation, 0.0)
	dst_anim.speed_scale = src_anim.speed_scale
	dst_anim.seek(src_anim.current_animation_position, true)
