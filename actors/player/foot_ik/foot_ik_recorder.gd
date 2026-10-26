class_name FootIkRecorder
extends Node
## Debug recorder for how the feet meet the ground, in any scene. Off by default: F10 (or the
## "Record foot IK" switch of the Esc debug page) starts and stops it, F11 marks "this looks wrong
## right now". While on, every frame writes one JSON line to user://foot_ik_live.jsonl (a rolling
## window of the last WINDOW_FRAMES frames). It measures from the outside, with its own rays, so
## it works the same whichever Foot IK (v1 or v2) is running.

const TOGGLE_KEY := KEY_F10
const MARK_KEY := KEY_F11
const PATH := "user://foot_ik_live.jsonl"
const WINDOW_FRAMES := 6000
const RAY_UP := 0.6 ## m above the bone where the ground ray starts
const RAY_DOWN := 1.2 ## m below the bone where it ends
const SIDES: Dictionary[StringName, Array] = {
	&"left": [&"LeftUpLeg", &"LeftLeg", &"LeftFoot", &"LeftToeBase"],
	&"right": [&"RightUpLeg", &"RightLeg", &"RightFoot", &"RightToeBase"],
}

var recording := false:
	set(value):
		if value == recording:
			return
		recording = value
		set_process(value)
		if value:
			_start()
		else:
			_stop()

var _player: Player
var _writer: FootIkTraceWriter
var _run_id := ""
var _frames := 0
var _marks := 0


func _ready() -> void:
	_player = get_parent() as Player
	process_priority = 1000 # after the skeleton and the Foot IK modifiers did their work
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(false)
	add_to_group(&"foot_ik_recorder")


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == TOGGLE_KEY:
		recording = not recording
	elif key.keycode == MARK_KEY and recording:
		mark()


## Flags the current moment ("it looks wrong now"); look for "mark" lines in the file.
func mark() -> void:
	_marks += 1
	_write({"kind": "mark", "mark": _marks, "frame": Engine.get_process_frames(),
			"run_id": _run_id, "root": _v3(_player.global_position)})
	_say("Foot IK mark %d" % _marks)


func _start() -> void:
	_run_id = "%s_%d" % [Time.get_datetime_string_from_system(false, true).replace(" ", "T"),
			Time.get_ticks_msec()]
	_writer = FootIkTraceWriter.new(PATH, WINDOW_FRAMES)
	_frames = 0
	_marks = 0
	_say("Foot IK recording ON (F10 stop, F11 mark)")


func _stop() -> void:
	_say("Foot IK recording OFF: %d frames, %d marks -> %s" % [_frames, _marks,
			ProjectSettings.globalize_path(PATH)])
	print("[FootIkRecorder] %d frames, %d marks -> %s" % [_frames, _marks,
			ProjectSettings.globalize_path(PATH)])


func _process(_delta: float) -> void:
	var body := _player.body
	if body == null or body.skeleton == null:
		return
	var space := _player.get_world_3d().direct_space_state
	var frame := {
		"kind": "foot_ik_live",
		"run_id": _run_id,
		"frame": Engine.get_process_frames(),
		"time": snappedf(Time.get_ticks_msec() / 1000.0, 0.001),
		"root": _v3(_player.global_position),
		"velocity": _v3(_player.velocity),
		"speed": snappedf(Vector2(_player.velocity.x, _player.velocity.z).length(), 0.001),
		"on_floor": _player.is_on_floor(),
		"floor_angle_deg": snappedf(rad_to_deg(_player.get_floor_angle()), 0.1),
		"animation": String(body.anim_player.current_animation) if body.anim_player else "",
		"ik": _ik_state(body),
		"feet": {},
	}
	var facing := -_player.global_basis.z
	for side: StringName in SIDES:
		var foot := _bone_world(body, SIDES[side][2])
		var toe := _bone_world(body, SIDES[side][3])
		if foot.is_empty() or toe.is_empty():
			continue
		frame["feet"][String(side)] = _foot(space, foot["position"], toe["position"], facing)
	_frames += 1
	_write(frame)


func _foot(space: PhysicsDirectSpaceState3D, ankle: Vector3, toe: Vector3,
		facing: Vector3) -> Dictionary:
	var under_ankle := _ground(space, ankle)
	var under_toe := _ground(space, toe)
	var out := {
		"ankle": _v3(ankle),
		"toe": _v3(toe),
		"ankle_above_ground": _round(ankle.y - under_ankle["y"]) if under_ankle["hit"] else null,
		"toe_above_ground": _round(toe.y - under_toe["y"]) if under_toe["hit"] else null,
		"ground_normal": under_ankle["normal"],
		"ground_collider": under_ankle["collider"],
		"toe_ground_collider": under_toe["collider"],
	}
	if under_ankle["hit"] and under_toe["hit"]:
		# the ground's own rise under the foot, against how the foot itself points
		var along := toe - ankle
		var run := Vector2(along.x, along.z).length()
		if run > 0.01:
			out["foot_pitch_deg"] = snappedf(rad_to_deg(atan2(along.y, run)), 0.1)
			var ground_along := Vector3(along.x, under_toe["y"] - under_ankle["y"], along.z)
			out["ground_pitch_deg"] = snappedf(rad_to_deg(atan2(ground_along.y, run)), 0.1)
			# the ankle-to-toe bone points down about 27 deg on flat ground (the skeleton's rest
			# shape), so compare foot - ground against that flat-ground baseline, not against 0
	out["ankle_forward"] = _round((ankle - _player.global_position).dot(facing))
	return out


func _ground(space: PhysicsDirectSpaceState3D, at: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * RAY_UP,
			at + Vector3.DOWN * RAY_DOWN, _player.collision_mask, [_player.get_rid()])
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return {"hit": false, "y": 0.0, "normal": null, "collider": ""}
	var collider := hit["collider"] as Node
	return {"hit": true, "y": (hit["position"] as Vector3).y, "normal": _v3(hit["normal"]),
			"collider": "%s/%s" % [collider.get_class(), collider.name] if collider else ""}


func _bone_world(body: PlayerBody, role: StringName) -> Dictionary:
	var index := body.skeleton.find_bone(body.resolve_bone_name(role))
	if index < 0:
		return {}
	var pose := body.global_transform * body.get_visual_bone_global_pose(index)
	return {"position": pose.origin}


func _ik_state(body: PlayerBody) -> Dictionary:
	var v2_on := false
	var v2_present := false
	for child: Node in body.skeleton.get_children():
		if child is FootIKV2Modifier:
			v2_present = true
			v2_on = (child as FootIKV2Modifier).enabled
	return {
		"v2_present": v2_present,
		"v2_enabled": v2_on,
	}


func _write(frame: Dictionary) -> void:
	if _writer != null:
		_writer.capture(JSON.stringify(frame))


func _say(message: String) -> void:
	print("[FootIkRecorder] ", message)
	if _player != null and _player.hud != null and _player.hud.has_method(&"toast"):
		_player.hud.call(&"toast", message)


static func _round(value: float) -> float:
	return snappedf(value, 0.001)


static func _v3(value: Vector3) -> Array:
	return [snappedf(value.x, 0.001), snappedf(value.y, 0.001), snappedf(value.z, 0.001)]
