extends Node3D
## Side-by-side stair A/B harness: two real Players walk the same staircase in parallel lanes - one
## with the Foot IK enabled, one with it disabled (pure authored animation) - each drawing its own
## toe trails, so "does the IK help or hurt?" is visible and measurable at the same time.
## Live metrics (toe jerk = foot discontinuity, grounded-foot slip) sit on screen and go to
## user://foot_ik_stair_ab.jsonl. Test-only; no gameplay.
## Launch: godot --path . res://tests/manual/foot_ik/foot_ik_stair_ab.tscn

const PLAYER_SCENE := preload("res://actors/player/player.tscn")
const SURFACES := preload("res://tests/manual/foot_ik/foot_ik_stair_surfaces.gd")
const TOE_TRACER := preload("res://tests/manual/foot_ik/foot_ik_toe_tracer.gd")

const STEP_COUNT := 6
const TREAD_DEPTH := 0.26
const WIDTH := 3.0
const THICKNESS := 0.3
const START := Vector3(0.0, 0.05, -4.5)
const FORWARD := Vector2(0.0, -1.0)
const LANE_X := 0.62 # lateral offset of each lane from the staircase centre
const STEP_HEIGHT := 0.23
const TOP_Z := STEP_COUNT * TREAD_DEPTH - 0.25
const LOG_PATH := "user://foot_ik_stair_ab.jsonl"
const ORBIT_MIN := 0.5
const ORBIT_MAX := 6.0

var _world: Node3D
var _camera: Camera3D
var _label: Label
var _log: FileAccess
var _lanes: Array[Dictionary] = []
var _frame := 0

var _orbit_yaw := 0.0
var _orbit_pitch := 0.32
var _orbit_distance := 6.0
var _orbit_target := Vector3(0.0, 1.0, 1.4)
var _dragging := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Engine.time_scale = 1.0
	_log = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	_build_world()
	_spawn_lane("IK ON", -LANE_X, true)
	_spawn_lane("IK OFF", LANE_X, false)
	_build_camera()
	_build_label()
	# The Player captures the mouse during setup; reclaim it so the scene is usable, then let
	# Esc toggle it back and forth.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build_world() -> void:
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)
	var floor_box := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var floor_back := START.z - 1.0
	var floor_front := -0.4
	box.size = Vector3(WIDTH * 3.0, THICKNESS, floor_front - floor_back)
	shape.shape = box
	floor_box.add_child(shape)
	floor_box.position = Vector3(0.0, -THICKNESS * 0.5, (floor_back + floor_front) * 0.5)
	floor_box.collision_layer = 1
	_world.add_child(floor_box)
	var riser_mat := StandardMaterial3D.new()
	riser_mat.albedo_color = Color(0.25, 0.4, 0.75)
	var tread_mat := StandardMaterial3D.new()
	tread_mat.albedo_color = Color(0.85, 0.25, 0.2)
	for step in STEP_COUNT:
		var rise := STEP_HEIGHT * (step + 1)
		var tread_start := step * TREAD_DEPTH
		var stair := CSGBox3D.new()
		stair.size = Vector3(WIDTH, rise, TREAD_DEPTH)
		stair.material = riser_mat
		stair.use_collision = true
		SURFACES.configure_authored_stair(stair)
		stair.position = Vector3(0.0, rise * 0.5, tread_start + TREAD_DEPTH * 0.5)
		SURFACES.finalize_authored_box(_world, stair)
		var cap := CSGBox3D.new()
		cap.size = Vector3(WIDTH, 0.02, TREAD_DEPTH)
		cap.material = tread_mat
		cap.use_collision = false
		cap.position = Vector3(0.0, rise + 0.01, tread_start + TREAD_DEPTH * 0.5)
		_world.add_child(cap)
	SURFACES.build_traversal_ramp(
			_world, Vector3.ZERO, WIDTH, THICKNESS, TREAD_DEPTH, STEP_COUNT, STEP_HEIGHT)
	SURFACES.build_top_landing(
			_world, Vector3.ZERO, WIDTH, TREAD_DEPTH, STEP_COUNT, STEP_HEIGHT, riser_mat, tread_mat)


## One walker lane. Both lanes share speed/input so the only difference is the Foot IK switch.
func _spawn_lane(lane_name: String, x_offset: float, ik_enabled: bool) -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	_world.add_child(player) # position must be set after entering the tree, or it is dropped
	player.global_position = START + Vector3(x_offset, 0.0, 0.0)
	player.rotation = Vector3(0.0, PI, 0.0)
	player.velocity = Vector3.ZERO
	player.movement_input_override = FORWARD
	player.gameplay_action_input_enabled = false
	player.ledge_safety_enabled = false
	player.stair_walk_speed_scale = 1.0 # fixtures keep fixed speed
	player.walk_speed = 0.85 # a human stair pace; 3.2 m/s is a sprint the authored clip can't match
	player.camera.current = false
	player.debug_cam.current = false
	player.detached_cam.current = false
	player.hud.visible = false
	player.hud.set_process_unhandled_input(false)
	player.set_process_unhandled_input(false)
	SURFACES.configure_player(player)
	var ik := _find_ik(player)
	if ik != null:
		ik.set_debug_enabled(ik_enabled)
		ik.ray_up = maxf(ik.ray_up, STEP_HEIGHT + 0.2)
		ik.ray_down = maxf(ik.ray_down, STEP_HEIGHT + 0.2)
	var tracer := TOE_TRACER.new()
	tracer.spawn(_world, player.skeleton, ik)
	_lanes.append({
		"name": lane_name, "player": player, "ik": ik, "tracer": tracer, "x": x_offset,
		"ik_enabled": ik_enabled, "prev": {}, "toe_jerk": [], "grounded_speed": [],
		"toe_prev_delta": {}, "loops": 0,
	})


func _find_ik(player: Player) -> PlayerFootIKModifier:
	for child in player.skeleton.get_children():
		if child is PlayerFootIKModifier:
			return child
	return null


func _build_camera() -> void:
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.current = true
	_update_camera()


func _update_camera() -> void:
	var offset := Vector3(
			sin(_orbit_yaw) * cos(_orbit_pitch),
			sin(_orbit_pitch),
			cos(_orbit_yaw) * cos(_orbit_pitch)) * _orbit_distance
	_camera.global_position = _orbit_target + offset
	_camera.look_at(_orbit_target)


func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventKey and event.pressed and not event.echo
			and (event as InputEventKey).keycode == KEY_ESCAPE):
		Input.mouse_mode = (Input.MOUSE_MODE_VISIBLE
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
				else Input.MOUSE_MODE_CAPTURED)
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_distance = clampf(_orbit_distance * 0.88, ORBIT_MIN, ORBIT_MAX)
			_update_camera()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_distance = clampf(_orbit_distance * 1.14, ORBIT_MIN, ORBIT_MAX)
			_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_orbit_yaw -= motion.relative.x * 0.006
		_orbit_pitch = clampf(_orbit_pitch + motion.relative.y * 0.006, -0.1, 1.3)
		_update_camera()


func _build_label() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 20)
	_label.position = Vector2(20, 20)
	layer.add_child(_label)


## Sample after the modifiers publish (see AGENTS.md): _process, not _physics_process.
func _process(_delta: float) -> void:
	for lane: Dictionary in _lanes:
		_sample_lane(lane)
	_frame += 1
	if _frame % 30 == 0:
		_update_label()
	if _log != null:
		_write_log_frame()
	if _frame > 0 and _frame % 1200 == 0:
		print("[STAIR_AB] frame %d - %s" % [_frame, _summary_line()])


func _sample_lane(lane: Dictionary) -> void:
	var player: Player = lane["player"]
	var ik: PlayerFootIKModifier = lane["ik"]
	if ik == null:
		return
	var skeleton := player.skeleton
	var use_final := bool(lane["ik_enabled"])
	var positions := {}
	for side: StringName in [&"left", &"right"]:
		var toe_idx := int((ik._bone_indices.get(side, {}) as Dictionary).get("toe", -1))
		var foot_idx := int((ik._bone_indices.get(side, {}) as Dictionary).get("foot", -1))
		if toe_idx < 0 or foot_idx < 0:
			continue
		var toe := _bone_world(skeleton, ik, toe_idx, use_final)
		var ankle := _bone_world(skeleton, ik, foot_idx, use_final)
		positions[side] = {"toe": toe, "ankle": ankle}
		var previous: Dictionary = lane["prev"].get(side, {})
		if not previous.is_empty():
			var step: float = toe.distance_to(previous["toe"])
			var previous_step: float = float(lane["toe_prev_delta"].get(side, -1.0))
			if previous_step >= 0.0:
				(lane["toe_jerk"] as Array).append(absf(step - previous_step))
			lane["toe_prev_delta"][side] = step
	# Grounded foot = the lower ankle this frame; its horizontal world speed is the slip.
	if positions.size() == 2:
		var sides := positions.keys()
		var lower: StringName = sides[0]
		if float((positions[sides[1]] as Dictionary)["ankle"].y) < float(
				(positions[lower] as Dictionary)["ankle"].y):
			lower = sides[1]
		var previous: Dictionary = lane["prev"].get(lower, {})
		if not previous.is_empty():
			var here: Vector3 = (positions[lower] as Dictionary)["ankle"]
			var before: Vector3 = previous["ankle"]
			(lane["grounded_speed"] as Array).append(
					Vector2(here.x - before.x, here.z - before.z).length()
					* Engine.physics_ticks_per_second)
	lane["prev"] = positions
	if lane["tracer"] != null:
		(lane["tracer"] as RefCounted).append(skeleton, ik, use_final)
	var position := player.global_position
	if position.z >= TOP_Z or position.y < -1.0:
		_reset_lane(lane)


## Loop the walk: send the lane back to the start with clean runtime state and a clean trail, so the
## stair walk repeats forever instead of the walkers strolling off the top and falling.
func _reset_lane(lane: Dictionary) -> void:
	var player: Player = lane["player"]
	player.global_position = START + Vector3(float(lane["x"]), 0.0, 0.0)
	player.rotation = Vector3(0.0, PI, 0.0)
	player.velocity = Vector3.ZERO
	player.movement_input_override = FORWARD
	if player.has_method("_reset_stair_hover"):
		player._reset_stair_hover()
	var ik: PlayerFootIKModifier = lane["ik"]
	if ik != null:
		ik.reset_runtime_state()
	lane["prev"] = {}
	lane["toe_prev_delta"] = {}
	if lane["tracer"] != null:
		(lane["tracer"] as RefCounted).clear()
	lane["loops"] = int(lane["loops"]) + 1


func _bone_world(skeleton: Skeleton3D, ik: PlayerFootIKModifier, bone_idx: int,
		use_final: bool) -> Vector3:
	var local := (ik.get_final_bone_global_pose(bone_idx).origin if use_final
			else skeleton.get_bone_global_pose(bone_idx).origin)
	return skeleton.global_transform * local


## Per-lane animation + per-foot IK state, the "where in the walk is it stuck" view: the clip and
## its phase, and for each foot the plan owner, target vs actual height, swing lift and weight.
func _lane_state(lane: Dictionary) -> Dictionary:
	var player: Player = lane["player"]
	var ik: PlayerFootIKModifier = lane["ik"]
	var state := {"animation": "", "phase": 0.0, "feet": {}}
	var anim := player.body.anim_player
	if anim != null and not anim.current_animation.is_empty():
		var clip := anim.get_animation(anim.current_animation)
		state["animation"] = anim.current_animation.get_file()
		if clip != null and clip.length > 0.0:
			state["phase"] = snappedf(anim.current_animation_position / clip.length, 0.001)
	if ik == null:
		return state
	for side: StringName in [&"left", &"right"]:
		var foot := {
			"weight": snappedf(float(ik._smoothed_ground_weight.get(side, 0.0)), 0.001),
			"lift": snappedf(float(ik._smoothed_step_lift.get(side, 0.0)), 0.001),
			"contact": snappedf(float(ik.debug_contact_distance.get(side, -1.0)), 0.001),
			"retracted": bool(ik.debug_retracted.get(side, false)),
			"step_down": bool(ik.debug_step_down.get(side, false)),
			"swing": ik._stair_predictor.get_swing_state(side) if ik._stair_predictor != null else {},
			"transfer": ik._stair_predictor.debug_transfer_blocked if ik._stair_predictor != null else {},
		}
		var plan = ik._target_coordinator.get_plan(side) if ik._target_coordinator != null else null
		if plan != null:
			foot["owner"] = plan.owner_name()
			foot["adj"] = plan.final_adjustment_reason
			foot["reason"] = plan.reason
			foot["observed"] = plan.solve_target_observed
		var previous: Dictionary = lane["prev"].get(side, {})
		if not previous.is_empty():
			foot["toe_y"] = snappedf(float((previous["toe"] as Vector3).y), 0.001)
			foot["ankle_y"] = snappedf(float((previous["ankle"] as Vector3).y), 0.001)
		state["feet"][str(side)] = foot
	return state


func _update_label() -> void:
	var lines: Array[String] = ["Stair IK A/B - toe jerk (mm) / grounded slip (m/s)"]
	for lane: Dictionary in _lanes:
		var jerk: Array = lane["toe_jerk"]
		var slip: Array = lane["grounded_speed"]
		jerk.sort()
		slip.sort()
		var jerk_p95: float = float(jerk[int(jerk.size() * 0.95)]) if jerk.size() > 20 else 0.0
		var slip_median: float = float(slip[slip.size() / 2]) if slip.size() > 20 else 0.0
		var jerk_max: float = float(jerk.back()) if not jerk.is_empty() else 0.0
		lines.append("%s: jerk p95 %.0f  max %.0f  | slip median %.2f" % [
				lane["name"], jerk_p95 * 1000.0, jerk_max * 1000.0, slip_median])
		var state := _lane_state(lane)
		lines.append("  anim %s phase %.2f" % [state["animation"], float(state["phase"])])
		for side: String in state["feet"]:
			var foot: Dictionary = state["feet"][side]
			lines.append("    %s w=%.2f lift=%.2f toey=%.3f ankley=%.3f %s/%s" % [
					side, float(foot["weight"]), float(foot["lift"]),
					float(foot.get("toe_y", 0.0)), float(foot.get("ankle_y", 0.0)),
					foot.get("owner", "?"), str(foot.get("adj", ""))])
	_label.text = "\n".join(lines)


func _write_log_frame() -> void:
	var record := {"frame": _frame, "lanes": {}}
	for lane: Dictionary in _lanes:
		var entry := {"state": _lane_state(lane)}
		for side: StringName in lane["prev"]:
			var data: Dictionary = lane["prev"][side]
			entry[side] = {
				"toe": _vec(data["toe"]), "ankle": _vec(data["ankle"]),
			}
		record["lanes"][lane["name"]] = entry
	_log.store_line(JSON.stringify(record))


## One compact comparison line for the periodic report.
func _vec(value: Vector3) -> Array:
	return [snappedf(value.x, 0.0001), snappedf(value.y, 0.0001), snappedf(value.z, 0.0001)]


func _summary_line() -> String:
	var parts: Array[String] = []
	for lane: Dictionary in _lanes:
		var jerk: Array = lane["toe_jerk"]
		var slip: Array = lane["grounded_speed"]
		if jerk.size() < 5:
			continue
		jerk.sort()
		slip.sort()
		var slip_median: float = float(slip[slip.size() / 2]) if not slip.is_empty() else 0.0
		parts.append("%s loop=%d jerk p95=%.0fmm max=%.0fmm slip=%.2fm/s" % [
			lane["name"], int(lane["loops"]),
			float(jerk[int(jerk.size() * 0.95)]) * 1000.0, float(jerk.back()) * 1000.0,
			slip_median])
	return " | ".join(parts)
