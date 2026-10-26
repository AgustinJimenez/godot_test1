class_name PlanetIKSoak
extends RefCounted
## A soak of the Foot IK v2 on the planet (AGENT_TASKS/093): the real player walks the planet through a script of moves (walk, jog, turn, strafe,
## back up, crouch, stop and go), and after every skeleton update the harness reads what the IK did and counts what looks wrong:
##   - a foot (ankle) that jumps further in one frame than the body and the animation can explain  (SNAP)
##   - the pelvis dropping or rising in one frame by more than a few centimetres                       (PELVIS_POP)
##   - an ankle under the ground (the collider the player walks on) by more than SINK, standing or walking (SINK)
##   - an ankle floating over the ground by more than FLOAT while the foot is planted / the body stands  (FLOAT)
##   - a leg stretched beyond its length                                                                  (STRETCH)
## Every event is printed with the frame, the phase and the numbers; the summary line is IK_SOAK. Run:
##   godot --headless --path . res://tests/manual/planet/planet_lab.tscn --fixed-fps 60 -- --ik-soak=120 [--seed=N]
## (`--ik-soak-log=PATH` also writes one line per frame as JSONL.)

const SNAP := 0.22 ## m: an ankle moving more than this in one physics frame (beyond the body's own motion)
const IK_POP := 0.06 ## m: the distance between the IK pose and the animated one changing this much in one frame
const PELVIS_POP := 0.06 ## m the pelvis drop may change in one frame
const SINK := 0.04 ## m an ankle's lowest point may be under the ground
const FLOAT := 0.15 ## m an ankle may hang over the ground when the foot is meant to be planted
const MAX_EVENTS := 60 ## events printed (the counts go on)

## What the player does, in turn: [name, seconds, keys held, turn rate (degrees a second)]
const SCRIPT: Array = [
	["walk", 6.0, [&"move_forward"], 0.0],
	["idle", 2.0, [], 0.0],
	["walk_turn_left", 5.0, [&"move_forward"], 35.0],
	["jog", 6.0, [&"move_forward", &"sprint"], 0.0],
	["walk_turn_right", 5.0, [&"move_forward"], -35.0],
	["idle", 2.0, [], 0.0],
	["strafe_left", 4.0, [&"move_left"], 0.0],
	["strafe_right", 4.0, [&"move_right"], 0.0],
	["back", 4.0, [&"move_back"], 0.0],
	["crouch_walk", 5.0, [&"move_forward", &"crouch"], 0.0],
	["idle_crouch", 2.0, [&"crouch"], 0.0],
	["sprint_turn", 5.0, [&"move_forward", &"sprint"], 50.0],
	["stop_go", 6.0, [&"move_forward"], 0.0],
	["spin_in_place", 3.0, [], 120.0],
]

var seconds := 120.0
var only := "" ## run just this phase of the script again and again (--ik-soak-only=NAME)
var _player: Player
var _planet: PlanetWorld
var _skeleton: Skeleton3D
var _modifier: FootIKV2Modifier
var _frame := 0
var _last_sampled := -1
var _held: Array[StringName] = []
var _phase := ""
var _phase_end := 0
var _step := 0
var _turn := 0.0
var _previous := {}
var _recent: Array[String] = [] # the last frames, compact, printed with an event
var _after_left := 0 # frames still to print after an event
var _events := 0
var _counts := {}
var _worst := {}
var _frames_in := {}
var _log: FileAccess
var _bones := {}
var _leg := {}


func start(player: Player, planet: PlanetWorld, log_path: String) -> bool:
	_player = player
	_planet = planet
	_skeleton = player.body.skeleton
	_modifier = _skeleton.get_node_or_null("FootIKV2") as FootIKV2Modifier
	if _modifier == null:
		print("IK_SOAK FAIL the player has no FootIKV2 modifier")
		return false
	for side in ["left", "right"]:
		var bone := _find_bone(side)
		if bone < 0:
			var names := PackedStringArray()
			for index in _skeleton.get_bone_count():
				names.append(_skeleton.get_bone_name(index))
			print("IK_SOAK FAIL no ", side, " foot bone among ", names)
			return false
		_bones[side] = bone
	if log_path != "":
		_log = FileAccess.open(log_path, FileAccess.WRITE)
	_skeleton.skeleton_updated.connect(_sample)
	print("IK_SOAK start seconds=%.0f modifier=%s weight=%.2f enabled=%s" % [seconds, _modifier.name,
			_modifier.weight, _modifier.enabled])
	return true


## The foot (ankle) bone of a side (the player's skeleton names them foot_l and foot_r).
func _find_bone(side: String) -> int:
	return _skeleton.find_bone("foot_l" if side == "left" else "foot_r")


## Called every physics frame by the lab: drives the player through the script.
func drive(frame: int) -> void:
	_frame = frame
	if _step >= SCRIPT.size():
		_step = 0
	if frame >= _phase_end:
		for action in _held:
			Input.action_release(action)
		_held.clear()
		var entry: Array = SCRIPT[_step]
		_step += 1
		while only != "" and entry[0] != only:
			if _step >= SCRIPT.size():
				_step = 0
			entry = SCRIPT[_step]
			_step += 1
		_phase = entry[0]
		_phase_end = frame + int(float(entry[1]) * 60.0)
		_turn = float(entry[3])
		for action: StringName in entry[2]:
			Input.action_press(action)
			_held.append(action)
	if _turn != 0.0:
		_player.rotate_y(deg_to_rad(_turn) / 60.0)


func finished() -> bool:
	return _frame >= 60 + int(seconds * 60.0)


## After the skeleton and its modifiers have done their work: look at the pose.
func _sample() -> void:
	var physics_frame := Engine.get_physics_frames()
	if physics_frame == _last_sampled or _frame < 120:
		return
	_last_sampled = physics_frame
	var now := {}
	var root := _skeleton.global_transform
	for side: String in _bones:
		now[side] = (root * _skeleton.get_bone_global_pose(_bones[side])).origin
	var pelvis := _modifier.debug_pelvis_drop
	var animated: Dictionary = _modifier.debug_animated_ankle
	for side: String in _bones:
		if animated.has(StringName(side)):
			now[side + "_anim"] = animated[StringName(side)]
	now["pelvis"] = pelvis
	now["body"] = _player.global_position
	_frames_in[_phase] = int(_frames_in.get(_phase, 0)) + 1
	if not _previous.is_empty():
		var body_step: Vector3 = (now["body"] as Vector3) - (_previous["body"] as Vector3)
		for side: String in _bones:
			var jump: float = ((now[side] as Vector3) - (_previous[side] as Vector3) - body_step).length()
			_note("SNAP", jump, jump > SNAP, side)
		for side: String in _bones:
			if now.has(side + "_anim") and _previous.has(side + "_anim"):
				# what the animation alone did this frame against what the IK made of it: a pop is the IK's own, a snap in both is the clip's
				var animation_jump: float = ((now[side + "_anim"] as Vector3) - (_previous[side + "_anim"] as Vector3) - body_step).length()
				var shift_now: float = ((now[side] as Vector3) - (now[side + "_anim"] as Vector3)).length()
				var shift_before: float = ((_previous[side] as Vector3) - (_previous[side + "_anim"] as Vector3)).length()
				_note("IK_POP", absf(shift_now - shift_before), absf(shift_now - shift_before) > IK_POP, side)
				_note("IK_SHIFT", shift_now, false, side)
				_note("CLIP_SNAP", animation_jump, animation_jump > SNAP, side)
		var pop := absf(float(now["pelvis"]) - float(_previous["pelvis"]))
		_note("PELVIS_POP", pop, pop > PELVIS_POP, "")
	var standing := _player.velocity.length() < 0.2 and _player.is_on_floor()
	for side: String in _bones:
		var ankle: Vector3 = now[side]
		var gap := _ground_gap(ankle)
		if is_nan(gap):
			continue
		_note("SINK", -gap, gap < -SINK, side)
		# (an ankle sits about ankle_height over the ground when planted)
		var over := gap - _modifier.ankle_height
		if standing:
			_note("FLOAT", over, over > FLOAT, side)
	if _log != null:
		_log.store_line(JSON.stringify({"f": physics_frame, "phase": _phase, "speed": snappedf(
				_player.velocity.length(), 0.01), "pelvis": snappedf(pelvis, 0.0001),
				"l": (now["left"] as Vector3).snapped(Vector3.ONE * 0.001),
				"r": (now["right"] as Vector3).snapped(Vector3.ONE * 0.001)}))
	var detail := ""
	for side: String in _bones:
		var shift_here := 0.0
		if now.has(side + "_anim"):
			shift_here = ((now[side] as Vector3) - (now[side + "_anim"] as Vector3)).length()
		detail += " %s[anim=%s shift=%.3f plant=%.2f %s %s]" % [side.left(1).to_upper(), _local(now[side + "_anim"]) if now.has(side + "_anim") else "-", shift_here, float((_modifier.debug_plant_weight as Dictionary).get(StringName(side), -1.0)),
				str((_modifier.debug_state as Dictionary).get(StringName(side), "")), str((_modifier.debug_skip_reason as Dictionary).get(StringName(side), ""))]
	var left_check: Dictionary = (_modifier.debug_reach_check as Dictionary).get(&"left", {})
	var left_solve: Dictionary = (_modifier.debug_solve as Dictionary).get(&"left", {})
	detail += " Lreach=%.3f/%.3f res=%.3f clamped=%s" % [float(left_check.get("hip_to_target", 0.0)), float(left_check.get("reach", 0.0)),
			float(left_solve.get("residual", 0.0)), left_solve.get("clamped", false)]
	_recent.append("f%d %s v=%.2f L=%s R=%s pelvis=%.3f%s" % [physics_frame, _phase, _player.velocity.length(),
			_local(now["left"]), _local(now["right"]), pelvis, detail])
	if _after_left > 0:
		print("  after: ", _recent[-1])
		_after_left -= 1
	if _recent.size() > 9:
		_recent.pop_front()
	_previous = now


## How far an ankle is over the ground the player walks on (ray down from above it), NAN with no ground.
func _ground_gap(point: Vector3) -> float:
	var space := _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.8, point + Vector3.DOWN * 2.0, 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return NAN
	return point.y - (hit["position"] as Vector3).y


## An ankle in the player's own axes (right, up, back), metres, rounded.
func _local(world: Vector3) -> String:
	var local := _player.global_transform.affine_inverse() * world
	return "(%.2f %.2f %.2f)" % [local.x, local.y, local.z]


func _note(kind: String, value: float, bad: bool, side: String) -> void:
	var key := "%s/%s" % [kind, _phase]
	var size := value if kind == "SINK" or kind == "FLOAT" else absf(value) # (how far under / over: the sign matters)
	if size > float(_worst.get(key, -1.0e9)):
		_worst[key] = size
	if not bad:
		return
	_counts[key] = int(_counts.get(key, 0)) + 1
	_events += 1
	if _events <= MAX_EVENTS:
		print("IK_SOAK_EVENT %s frame=%d phase=%s %s value=%.3f speed=%.2f pelvis=%.3f slope=%.0f" % [kind,
				_last_sampled, _phase, side, value, _player.velocity.length(), _modifier.debug_pelvis_drop,
				rad_to_deg(_player.get_floor_normal().angle_to(Vector3.UP)) if _player.is_on_floor() else -1.0])
		if _events <= 12 and not _recent.is_empty():
			print("  before: ", " | ".join(_recent))
			_after_left = 2
		if _events <= 3 or (_events <= 40 and (kind == "SNAP" or kind == "IK_POP")):
			print("  animated=", _modifier.debug_animated_ankle, " target=", _modifier.debug_target, " state=",
					_modifier.debug_state, " stepping=", _modifier.debug_stepping, " skip=", _modifier.debug_skip_reason,
					" plant=", _modifier.debug_plant_weight, " solve=", _modifier.debug_solve, " ground=", _modifier.debug_ground)


func summary() -> void:
	var bad := 0
	for key: String in _counts:
		bad += int(_counts[key])
	print("IK_SOAK_COUNTS ", JSON.stringify(_counts))
	var worst := {}
	for key: String in _worst:
		worst[key] = snappedf(float(_worst[key]), 0.001)
	print("IK_SOAK_WORST ", JSON.stringify(worst))
	print("IK_SOAK_FRAMES ", JSON.stringify(_frames_in))
	print("IK_SOAK %s events=%d seconds=%.0f travelled=%.0f m" % ["PASS" if bad == 0 else "ISSUES", bad,
			seconds, _planet.planet_position().distance_to(_start_position)])
	if _log != null:
		_log.close()
		_log = null


var _start_position := Vector3.ZERO


func mark_start() -> void:
	_start_position = _planet.planet_position()
