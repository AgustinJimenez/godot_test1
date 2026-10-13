extends Node
## Turn in place at the side of the 15 degree ramp (`-- --spawn=ramp-edge-turn`): settle (the
## character slides in off the edge), then two smooth full circles (like the mouse) and eight 45
## degree snaps. Look at the legs: foot yaw against the body, hip swing, knee bend, hip drop.
## `scripts/check_foot_ik_v2.sh` grades the trace with `scripts/edge_turn_report.sh`.

const SETTLE := 150
const SMOOTH_DEG_PER_FRAME := 1.5
const SMOOTH_FRAMES := 240
const HOLD := 60
const SNAP_DEG := 45.0
const SNAP_HOLD := 40
const SNAPS := 8

var _player: Node3D
var _frame := 0


func setup(player: Node3D) -> Node:
	_player = player
	return self


func _physics_process(_delta: float) -> void:
	_frame += 1
	var at := _frame - SETTLE
	if at <= 0:
		return
	if at <= SMOOTH_FRAMES:
		_player.rotation.y += deg_to_rad(SMOOTH_DEG_PER_FRAME)
		return
	at -= SMOOTH_FRAMES + HOLD
	if at > 0 and at <= SMOOTH_FRAMES:
		_player.rotation.y -= deg_to_rad(SMOOTH_DEG_PER_FRAME)
		return
	at -= SMOOTH_FRAMES + HOLD
	if at > 0 and at <= SNAPS * SNAP_HOLD and (at - 1) % SNAP_HOLD == 0:
		_player.rotation.y += deg_to_rad(SNAP_DEG)
