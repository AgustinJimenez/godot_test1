extends Node3D
## Stair walk lab. Auto-walks the real Player from the floor up a staircase onto the top landing,
## RECORDS every frame (root transform + all bone poses + metrics), then lets you scrub that clip:
## play/pause, step, reverse, speed, with a feet-locked orbit camera and live metrics on screen.
## The step height is editable and rebuilds + re-records. Test-only; no gameplay.
## Launch: godot --path . res://tests/manual/foot_ik/foot_ik_stair_lab.tscn

const PLAYER_SCENE := preload("res://actors/player/player.tscn")
const MONITOR := preload("res://tools/foot_ik/foot_ik_live_penetration_monitor.gd")
const SURFACES := preload("res://tests/manual/foot_ik/foot_ik_stair_surfaces.gd")

const STEP_COUNT := 6
const TREAD_DEPTH := 0.6
const WIDTH := 3.0
const THICKNESS := 0.3
const START := Vector3(0.0, 0.05, -4.5)
const FORWARD := Vector2(0.0, -1.0)
const TOP_Z := STEP_COUNT * TREAD_DEPTH - 0.25
const MAX_RECORD_FRAMES := 1200
const TOE_TIP_EXTRA := 0.035
const LEG_JOINTS := ["hip", "knee", "foot", "toe", "leaf"]
const ORBIT_MIN := 0.4
const ORBIT_MAX := 5.0

var step_height := 0.35

var _world: Node3D
var _player: Player
var _modifier: PlayerFootIKModifier
var _camera: Camera3D

var _frames: Array = [] # {root: Transform3D, bones: Array[Transform3D], worst: float, clip: float}
var _recording := true
var _rec_done := false

var _playing := false
var _speed := 0.5
var _playhead := 0.0
var _reverse := false

var _orbit_yaw := 0.6
var _orbit_pitch := 0.25
var _orbit_distance := 1.8
var _dragging := false

var _metrics: Label
var _frame_slider: HSlider
var _speed_label: Label
var _height_box: SpinBox
var _clip_marker: MeshInstance3D
var _panel: VBoxContainer
var _log: FileAccess
const LOG_PATH := "user://foot_ik_stair_lab.jsonl"
var _trail := {} # side -> PackedVector3Array of foot world positions
var _trail_mesh := {} # side -> ImmediateMesh
var _toe_sphere := {} # side -> MeshInstance3D on the toe


func _ready() -> void:
	Engine.time_scale = 1.0
	_build_clip_marker()
	_build_trails()
	_build_ui()
	_rebuild()


## Persistent per-foot path lines (right = blue, left = purple) drawn over the whole recorded
## clip; cleared when a new recording starts.
func _build_trails() -> void:
	for side: StringName in [&"right", &"left"]:
		var color := (Color(0.2, 0.45, 1.0) if side == &"right" else Color(0.62, 0.2, 1.0))
		var mesh := ImmediateMesh.new()
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		inst.material_override = material
		add_child(inst)
		_trail[side] = PackedVector3Array()
		_trail_mesh[side] = mesh
		var sphere := SphereMesh.new()
		sphere.radius = 0.022
		sphere.height = 0.044
		var marker := MeshInstance3D.new()
		marker.mesh = sphere
		var smat := StandardMaterial3D.new()
		smat.albedo_color = color
		smat.no_depth_test = true
		marker.material_override = smat
		add_child(marker)
		_toe_sphere[side] = marker


func _update_foot_markers() -> void:
	if _player == null or _modifier == null:
		return
	var to_world := _player.skeleton.global_transform
	for side: StringName in _toe_sphere:
		var idx: int = int((_modifier._bone_indices.get(side, {}) as Dictionary).get("toe", -1))
		if idx < 0:
			continue
		(_toe_sphere[side] as MeshInstance3D).global_position = (
				to_world * _player.skeleton.get_bone_global_pose(idx).origin)


func _append_trail() -> void:
	for side: StringName in _trail_mesh:
		var idx: int = int((_modifier._bone_indices.get(side, {}) as Dictionary).get("toe", -1))
		if idx < 0:
			continue
		var points: PackedVector3Array = _trail[side]
		points.append((_toe_sphere[side] as MeshInstance3D).global_position)
		_trail[side] = points
	_rebuild_trail_mesh()


func _rebuild_trail_mesh() -> void:
	for side: StringName in _trail_mesh:
		var points: PackedVector3Array = _trail[side]
		var mesh: ImmediateMesh = _trail_mesh[side]
		mesh.clear_surfaces()
		if points.size() < 2:
			continue
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for i in range(1, points.size()):
			mesh.surface_add_vertex(points[i - 1])
			mesh.surface_add_vertex(points[i])
		mesh.surface_end()


func _clear_trails() -> void:
	for side: StringName in _trail_mesh:
		_trail[side] = PackedVector3Array()
		(_trail_mesh[side] as ImmediateMesh).clear_surfaces()


func _build_clip_marker() -> void:
	_clip_marker = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.1
	_clip_marker.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.05, 0.05)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.0, 0.0)
	# The clip point is inside the step geometry, so draw through it.
	material.no_depth_test = true
	_clip_marker.material_override = material
	_clip_marker.visible = false
	add_child(_clip_marker)


func _rebuild() -> void:
	if _log != null:
		_log.close()
	_log = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if _world != null:
		_world.queue_free()
		_world = null
		_frames.clear()
		_clear_trails()
		_recording = true
		_rec_done = false
		_playing = false
		_playhead = 0.0
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)
	_build_floor()
	_build_stairs()
	_spawn_player()
	_setup_camera()
	if _frame_slider != null:
		_frame_slider.max_value = 1
	if _panel != null:
		_panel.visible = false


func _build_floor() -> void:
	var floor_box := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var floor_back := START.z - 1.0
	var floor_front := -0.4 # reaches under the traversal ramp's own start
	box.size = Vector3(WIDTH * 3.0, THICKNESS, floor_front - floor_back)
	shape.shape = box
	floor_box.add_child(shape)
	floor_box.position = Vector3(0.0, -THICKNESS * 0.5, (floor_back + floor_front) * 0.5)
	floor_box.collision_layer = 1
	_world.add_child(floor_box)


func _build_stairs() -> void:
	var riser_mat := StandardMaterial3D.new()
	riser_mat.albedo_color = Color(0.25, 0.4, 0.75)
	var tread_mat := StandardMaterial3D.new()
	tread_mat.albedo_color = Color(0.85, 0.25, 0.2)
	var origin := Vector3.ZERO
	for step in STEP_COUNT:
		var rise := step_height * (step + 1)
		var tread_start := step * TREAD_DEPTH
		var stair := CSGBox3D.new()
		stair.size = Vector3(WIDTH, rise, TREAD_DEPTH)
		stair.material = riser_mat
		stair.use_collision = true
		SURFACES.configure_authored_stair(stair)
		stair.position = origin + Vector3(0.0, rise * 0.5, tread_start + TREAD_DEPTH * 0.5)
		SURFACES.finalize_authored_box(_world, stair)
		var cap := CSGBox3D.new()
		cap.size = Vector3(WIDTH, 0.02, TREAD_DEPTH)
		cap.material = tread_mat
		cap.use_collision = false
		cap.position = origin + Vector3(0.0, rise + 0.01, tread_start + TREAD_DEPTH * 0.5)
		_world.add_child(cap)
	SURFACES.build_traversal_ramp(
			_world, origin, WIDTH, THICKNESS, TREAD_DEPTH, STEP_COUNT, step_height)
	SURFACES.build_top_landing(
			_world, origin, WIDTH, TREAD_DEPTH, STEP_COUNT, step_height, riser_mat, tread_mat)


func _spawn_player() -> void:
	_player = PLAYER_SCENE.instantiate() as Player
	_player.global_position = START
	_player.rotation = Vector3(0.0, PI, 0.0)
	_player.velocity = Vector3.ZERO
	_player.movement_input_override = FORWARD
	_player.gameplay_action_input_enabled = false
	_world.add_child(_player)
	_player.camera.current = false
	_player.debug_cam.current = false
	_player.hud.visible = false
	SURFACES.configure_player(_player)
	_modifier = _find_modifier()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _find_modifier() -> PlayerFootIKModifier:
	for child in _player.skeleton.get_children():
		if child is PlayerFootIKModifier:
			return child
	return null


func _setup_camera() -> void:
	if _camera == null:
		_camera = Camera3D.new()
		add_child(_camera)
	_camera.current = true


func _physics_process(delta: float) -> void:
	if _recording:
		_record_frame()
		return
	if _frames.is_empty():
		return
	if _playing:
		var step := _speed * delta * Engine.physics_ticks_per_second * (1.0 if not _reverse else -1.0)
		_playhead = fposmod(_playhead + step, float(_frames.size()))
	_apply_frame(int(_playhead) % _frames.size())
	_update_metrics()


func _record_frame() -> void:
	_apply_playing_input()
	var bones := _capture_bones()
	var clip := _clip_result()
	var deltas := _joint_deltas(bones)
	var frame := {
		"root": _player.global_transform,
		"skel": _player.skeleton.global_transform,
		"bones": bones,
		"worst": deltas["local"],
		"worst_world": deltas["world"],
		"clip": clip["depth"],
		"clip_point": clip["point"],
	}
	_frames.append(frame)
	_log_line(_frames.size() - 1)
	_update_foot_markers()
	_append_trail()
	if _frame_slider != null:
		_frame_slider.max_value = maxf(1.0, float(_frames.size()))
	if _player.global_position.z >= TOP_Z or _frames.size() >= MAX_RECORD_FRAMES:
		_finish_recording()


func _apply_playing_input() -> void:
	_player.movement_input_override = FORWARD


func _finish_recording() -> void:
	var worst := 0.0
	var worst_world := 0.0
	var deepest := 0.0
	var worst_frame := -1
	var deepest_frame := -1
	for i in _frames.size():
		var frame: Dictionary = _frames[i]
		if float(frame.get("worst", 0.0)) > worst:
			worst = float(frame.get("worst", 0.0))
			worst_frame = i
		worst_world = maxf(worst_world, float(frame.get("worst_world", 0.0)))
		if float(frame.get("clip", 0.0)) > deepest:
			deepest = float(frame.get("clip", 0.0))
			deepest_frame = i
	var deep_z := 0.0
	if deepest_frame >= 0:
		deep_z = (_frames[deepest_frame]["root"] as Transform3D).origin.z
	var clip_frames := 0
	for frame: Dictionary in _frames:
		if float(frame.get("clip", 0.0)) > 0.005:
			clip_frames += 1
	print("[STAIR_LAB] recorded %d frames step_height=%.3f" % [_frames.size(), step_height])
	print("[STAIR_LAB] worstJoint local=%.1f (body-rel) world=%.1f (incl turn) @f%d" % [
			worst, worst_world, worst_frame])
	print("[STAIR_LAB] clip=%.4f m @f%d root_z=%.2f | clip_frames=%d" % [
			deepest, deepest_frame, deep_z, clip_frames])
	if _log != null:
		_log.flush()
		_log.close()
		_log = null
	print("[STAIR_LAB] log: %s" % ProjectSettings.globalize_path(LOG_PATH))
	_recording = false
	_rec_done = true
	_playing = true
	_playhead = 0.0
	if _panel != null:
		_panel.visible = true
	_player.set_physics_process(false)
	_player.movement_input_override = Vector2.ZERO
	if _player.body.anim_player != null:
		_player.body.anim_player.process_mode = Node.PROCESS_MODE_DISABLED
	if _modifier != null:
		_modifier.process_mode = Node.PROCESS_MODE_DISABLED


func _capture_bones() -> Array[Transform3D]:
	var bones: Array[Transform3D] = []
	var count := _player.skeleton.get_bone_count()
	for i in count:
		bones.append(_player.skeleton.get_bone_global_pose(i))
	return bones


func _apply_frame(index: int) -> void:
	var frame: Dictionary = _frames[index]
	_player.global_transform = frame["root"]
	var bones: Array[Transform3D] = frame["bones"]
	for i in bones.size():
		_player.skeleton.set_bone_global_pose(i, bones[i])


## Two per-frame joint-angle measures. `local` is skeleton space (the leg relative to the body, so
## a character turn does not count); `world` is the bone's world rotation (includes the root yaw,
## which is what the debug overlay trace probes measure). Comparing them separates "the leg snapped"
## from "the character turned".
func _joint_deltas(bones: Array[Transform3D]) -> Dictionary:
	if _frames.is_empty():
		return {"local": 0.0, "world": 0.0}
	var previous: Array[Transform3D] = _frames[-1]["bones"]
	var skel: Transform3D = _player.skeleton.global_transform
	var prev_skel: Transform3D = _frames[-1]["skel"]
	var local_worst := 0.0
	var world_worst := 0.0
	for side: StringName in _modifier._bone_indices:
		var indices: Dictionary = _modifier._bone_indices[side]
		for joint: String in LEG_JOINTS:
			var idx: int = int(indices.get(joint, -1))
			if idx < 0 or idx >= bones.size() or idx >= previous.size():
				continue
			var now := bones[idx].basis.get_rotation_quaternion()
			var before := previous[idx].basis.get_rotation_quaternion()
			local_worst = maxf(local_worst, rad_to_deg(now.angle_to(before)))
			var now_world := (skel * bones[idx]).basis.get_rotation_quaternion()
			var before_world := (prev_skel * previous[idx]).basis.get_rotation_quaternion()
			world_worst = maxf(world_worst, rad_to_deg(now_world.angle_to(before_world)))
	return {"local": local_worst, "world": world_worst}


func _clip_result() -> Dictionary:
	var space := get_world_3d().direct_space_state
	var to_world := _player.skeleton.global_transform
	var worst := 0.0
	var worst_point := Vector3.ZERO
	for side: StringName in _modifier._bone_indices:
		var indices: Dictionary = _modifier._bone_indices[side]
		var foot_idx: int = int(indices.get("foot", -1))
		var toe_idx: int = int(indices.get("toe", -1))
		if foot_idx < 0 or toe_idx < 0:
			continue
		var ankle: Vector3 = to_world * _player.skeleton.get_bone_global_pose(foot_idx).origin
		var toe: Vector3 = to_world * _player.skeleton.get_bone_global_pose(toe_idx).origin
		var tip := toe + (toe - ankle).normalized() * TOE_TIP_EXTRA
		var result := MONITOR.check(space, PackedVector3Array([ankle, tip]),
				FootIKGroundSampler.GROUND_COLLISION_MASK)
		if float(result["depth_m"]) > worst:
			worst = float(result["depth_m"])
			worst_point = result["point"]
	return {"depth": worst, "point": worst_point}


func _update_clip_marker() -> void:
	if _clip_marker == null or _frames.is_empty():
		return
	var index := _frames.size() - 1 if _recording else int(_playhead) % _frames.size()
	var frame: Dictionary = _frames[index]
	if float(frame.get("clip", 0.0)) > 0.005:
		_clip_marker.visible = true
		_clip_marker.global_position = frame["clip_point"]
	else:
		_clip_marker.visible = false


func _log_line(index: int) -> void:
	if _log == null:
		return
	var frame: Dictionary = _frames[index]
	var root: Transform3D = frame["root"]
	var entry := {
		"frame": index,
		"root": _vec(root.origin),
		"yaw": rad_to_deg(root.basis.get_euler().y),
		"worst_deg": frame["worst"],
		"worst_world_deg": frame["worst_world"],
		"clip": frame["clip"],
		"clip_point": _vec(frame["clip_point"]),
		"feet": {},
	}
	var to_world := _player.skeleton.global_transform
	for side: StringName in _modifier._bone_indices:
		var indices: Dictionary = _modifier._bone_indices[side]
		var foot := {}
		var foot_idx: int = int(indices.get("foot", -1))
		var toe_idx: int = int(indices.get("toe", -1))
		if foot_idx >= 0:
			foot["ankle"] = _vec(to_world * _player.skeleton.get_bone_global_pose(foot_idx).origin)
		if toe_idx >= 0:
			foot["toe"] = _vec(to_world * _player.skeleton.get_bone_global_pose(toe_idx).origin)
		var plan = _modifier._target_coordinator.get_plan(side)
		if plan != null:
			foot["owner"] = plan.owner
			foot["adj"] = plan.final_adjustment_reason
		entry["feet"][str(side)] = foot
	_log.store_line(JSON.stringify(entry))


func _vec(value: Vector3) -> Array:
	return [snappedf(value.x, 0.0001), snappedf(value.y, 0.0001), snappedf(value.z, 0.0001)]


func _foot_center() -> Vector3:
	if _player == null or _modifier == null:
		return Vector3.ZERO
	var to_world := _player.skeleton.global_transform
	var total := Vector3.ZERO
	var count := 0
	for side: StringName in _modifier._bone_indices:
		var idx: int = int(_modifier._bone_indices[side].get("foot", -1))
		if idx >= 0:
			total += to_world * _player.skeleton.get_bone_global_pose(idx).origin
			count += 1
	return total / maxf(1.0, float(count))


func _process(_delta: float) -> void:
	_update_camera()
	_update_foot_markers()
	_update_clip_marker()
	if not _recording:
		_update_metrics()


func _update_camera() -> void:
	if _camera == null:
		return
	var target := _foot_center()
	var offset := Vector3(
			cos(_orbit_yaw) * cos(_orbit_pitch),
			sin(_orbit_pitch),
			sin(_orbit_yaw) * cos(_orbit_pitch)) * _orbit_distance
	_camera.global_position = target + offset
	_camera.look_at(target, Vector3.UP)


func _update_metrics() -> void:
	if _metrics == null or _frames.is_empty():
		return
	var index := int(_playhead) % _frames.size()
	var frame: Dictionary = _frames[index]
	_metrics.text = ("frame %d/%d  %s  speed %.2fx | joint local %.1f / world %.1f deg/f | clip %.4f m"
			% [index + 1, _frames.size(), "REV" if _reverse else "FWD", _speed,
			float(frame.get("worst", 0.0)), float(frame.get("worst_world", 0.0)),
			float(frame.get("clip", 0.0))])
	if _frame_slider != null:
		_frame_slider.set_value_no_signal(index)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_panel = VBoxContainer.new()
	_panel.position = Vector2(16, 16)
	_panel.add_theme_constant_override("separation", 10)
	_panel.visible = false # hidden while recording; shown when the replay starts
	layer.add_child(_panel)
	_metrics = Label.new()
	_metrics.add_theme_font_size_override("font_size", 22)
	_panel.add_child(_metrics)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_panel.add_child(row)
	var play := Button.new()
	play.text = "Play/Pause"
	play.add_theme_font_size_override("font_size", 22)
	play.custom_minimum_size = Vector2(150, 44)
	play.pressed.connect(func() -> void: _playing = not _playing)
	row.add_child(play)
	var back := Button.new()
	back.text = "Step -"
	back.add_theme_font_size_override("font_size", 22)
	back.custom_minimum_size = Vector2(110, 44)
	back.pressed.connect(func() -> void: _step(-1))
	row.add_child(back)
	var fwd := Button.new()
	fwd.text = "Step +"
	fwd.add_theme_font_size_override("font_size", 22)
	fwd.custom_minimum_size = Vector2(110, 44)
	fwd.pressed.connect(func() -> void: _step(1))
	row.add_child(fwd)
	var rev := Button.new()
	rev.text = "Reverse"
	rev.toggle_mode = true
	rev.add_theme_font_size_override("font_size", 22)
	rev.custom_minimum_size = Vector2(140, 44)
	rev.toggled.connect(func(on: bool) -> void: _reverse = on)
	row.add_child(rev)
	_frame_slider = HSlider.new()
	_frame_slider.min_value = 0
	_frame_slider.max_value = 1
	_frame_slider.custom_minimum_size = Vector2(560, 34)
	_frame_slider.value_changed.connect(func(value: float) -> void: _playhead = value)
	_panel.add_child(_frame_slider)
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 12)
	_panel.add_child(speed_row)
	speed_row.add_child(_label("Speed"))
	var speed := HSlider.new()
	speed.min_value = 0.05
	speed.max_value = 2.0
	speed.step = 0.05
	speed.value = _speed
	speed.custom_minimum_size = Vector2(460, 34)
	speed.value_changed.connect(func(value: float) -> void: _set_speed(value))
	speed_row.add_child(speed)
	_speed_label = _label("%.2fx" % _speed)
	speed_row.add_child(_speed_label)
	var height_row := HBoxContainer.new()
	height_row.add_theme_constant_override("separation", 12)
	_panel.add_child(height_row)
	height_row.add_child(_label("Step height (m)"))
	_height_box = SpinBox.new()
	_height_box.min_value = 0.1
	_height_box.max_value = 0.9
	_height_box.step = 0.01
	_height_box.value = step_height
	_height_box.custom_minimum_size = Vector2(150, 44)
	_height_box.get_line_edit().add_theme_font_size_override("font_size", 22)
	height_row.add_child(_height_box)
	var rebuild := Button.new()
	rebuild.text = "Rebuild + Record"
	rebuild.add_theme_font_size_override("font_size", 22)
	rebuild.custom_minimum_size = Vector2(230, 44)
	rebuild.pressed.connect(func() -> void:
		step_height = float(_height_box.value)
		_rebuild())
	height_row.add_child(rebuild)
	_panel.add_child(_label("Left-drag orbit | wheel zoom | feet-locked camera"))


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	return label


func _step(direction: int) -> void:
	if _frames.is_empty():
		return
	_playing = false
	_playhead = fposmod(_playhead + float(direction), float(_frames.size()))
	_apply_frame(int(_playhead) % _frames.size())
	_update_metrics()


func _set_speed(value: float) -> void:
	_speed = value
	if _speed_label != null:
		_speed_label.text = "%.2fx" % value


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_distance = clampf(_orbit_distance - 0.15, ORBIT_MIN, ORBIT_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_distance = clampf(_orbit_distance + 0.15, ORBIT_MIN, ORBIT_MAX)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_orbit_yaw -= event.relative.x * 0.006
		_orbit_pitch = clampf(_orbit_pitch + event.relative.y * 0.006, -1.4, 1.4)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		_playing = not _playing
