class_name FootIkClipIndicator
extends RefCounted
## Live per-frame foot/geometry penetration indicator for the debug overlay: a big red marker
## plus a throttled log line whenever a foot's ankle/toe actually sinks into nearby stair
## geometry during ordinary manual play, not only an automated test sweep. Split out purely to
## keep foot_ik_debug_overlay.gd under the project's max-file-lines cap.

const MONITOR := preload("res://tools/foot_ik/foot_ik_live_penetration_monitor.gd")
const LOG_THRESHOLD_M := 0.005 # ignore boundary-epsilon noise, flag real clipping only

var _markers: Dictionary = {} # side -> MeshInstance3D
var _active: Dictionary = {} # side -> bool, last frame's state, for log throttling


func spawn(parent: Node3D, side: String) -> void:
	var marker := FootIkDebugMarkers.spawn_marker(parent, Color(1.0, 0.0, 0.0))
	marker.scale = Vector3.ONE * 3.0
	marker.visible = false
	_markers[side] = marker


func update(space: PhysicsDirectSpaceState3D, mask: int, side: String,
		points: PackedVector3Array, player: Player = null) -> void:
	var result := MONITOR.check(space, points, mask)
	var marker := _markers[side] as MeshInstance3D
	var penetrating: bool = result["penetrating"] and float(result["depth_m"]) > LOG_THRESHOLD_M
	marker.visible = penetrating
	if not penetrating:
		_active[side] = false
		return
	marker.global_position = result["point"]
	if not bool(_active.get(side, false)):
		var point_index := points.find(result["point"])
		var joint := "ankle" if point_index == 0 else "toe_tip"
		var context := ""
		if player != null:
			context = " actor=%s animation=%s time=%.4f root=%s yaw_deg=%.4f" % [
					player.get_path(), player.body.anim_player.current_animation,
					player.body.anim_player.current_animation_position, player.global_position,
					rad_to_deg(player.rotation.y)]
		print("[FOOT_IK_CLIP] frame=%d side=%s joint=%s depth_m=%.4f point=%s%s" % [
				Engine.get_physics_frames(), side, joint, result["depth_m"], result["point"], context])
	_active[side] = true
