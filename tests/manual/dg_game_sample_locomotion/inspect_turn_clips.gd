extends SceneTree
## Inspection helper for the locomotion lab's animation clips.
##
## Answers the question the visual driver depends on: does a retargeted
## turn-in-place clip rotate the skeleton itself (root motion) or is it in
## place? If the hips quaternion is identical at both ends, it is in place and
## safe to layer on top of the capsule yaw the state machine applies.
##
## Run: godot --headless --path . \
##   --script res://tests/manual/dg_game_sample_locomotion/inspect_turn_clips.gd

const TURN_CLIPS := [
	"res://assets/models/als_retarget_test/ALS_N_TurnIP_L90_on_ybot.res",
	"res://assets/models/als_retarget_test/ALS_N_TurnIP_R90_on_ybot.res",
	"res://assets/models/als_retarget_test/ALS_N_TurnIP_L180_on_ybot.res",
	"res://assets/models/als_retarget_test/ALS_N_TurnIP_R180_on_ybot.res",
]


func _init() -> void:
	for path in TURN_CLIPS:
		_inspect(path)
	quit(0)


func _inspect(path: String) -> void:
	var animation := load(path) as Animation
	if animation == null:
		print("MISSING ", path)
		return
	print("\n== %s  length=%.3fs tracks=%d" % [
		path.get_file(), animation.length, animation.get_track_count()])
	for track in animation.get_track_count():
		var track_path := str(animation.track_get_path(track))
		if not track_path.contains("Hips"):
			continue
		var keys := animation.track_get_key_count(track)
		if keys < 2:
			continue
		var first: Variant = animation.track_get_key_value(track, 0)
		var last: Variant = animation.track_get_key_value(track, keys - 1)
		print("   %s type=%d keys=%d" % [track_path.get_slice(":", 1),
				animation.track_get_type(track), keys])
		print("      t0   = %s" % str(first))
		print("      tend = %s" % str(last))
