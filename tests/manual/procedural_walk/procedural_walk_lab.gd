extends Node3D
## Standalone MotusMan procedural walk experiment. Does not spawn Player.

const MODEL := preload(
		"res://assets/models/pistol_starter/Animation/In-Place/W1_Stand_Relaxed_Idle_IPC.fbx")
const MODIFIER := preload("res://tests/manual/procedural_walk/procedural_walk_modifier.gd")
const CYCLE_FRAMES := 120 # Two complete steps at a 60 fps reference rate.
const MAX_MOVING_CYCLES := 8.0

var _modifier: ProceduralWalkLabModifier
var _skeleton: Skeleton3D
var _character: Node3D
var _camera: Camera3D
var _speed := 1.0
var _playing := true
var _frame_position := 0.0
var _yaw := PI
var _pitch := 0.12
var _distance := 3.7
var _dragging := false
var _info: Label
var _frame_slider: HSlider
var _joint_label: Label
var _joint_lines: ImmediateMesh
var _joint_markers: Dictionary = {}
var _joint_materials: Dictionary = {}
var _show_joints := true
var _moving_mode := false
var _travel_cycles := 0.0
var _back_button: Button


func _ready() -> void:
	_build_stage()
	_build_character()
	_build_joint_overlay()
	_build_ui()
	if "--lab-check" in OS.get_cmdline_user_args():
		_run_lab_check()
	elif "--moving-check" in OS.get_cmdline_user_args():
		_run_moving_check()
	elif "--contact-report" in OS.get_cmdline_user_args():
		_contact_report()


func _physics_process(delta: float) -> void:
	if _modifier == null:
		return
	if _playing:
		if _moving_mode:
			_advance_moving(delta)
		else:
			_frame_position = fposmod(_frame_position + delta * 60.0 * _speed,
					float(CYCLE_FRAMES))
			_set_frame(_frame_position)


func _process(_delta: float) -> void:
	_update_joint_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = clampf(_distance - 0.3, 1.0, 8.0)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = clampf(_distance + 0.3, 1.0, 8.0)
			_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x * 0.007
		_pitch = clampf(_pitch + event.relative.y * 0.007, -0.7, 1.2)
		_update_camera()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_playing = not _playing
			_update_info()
		elif event.keycode == KEY_LEFT:
			_step_frame(-1)
		elif event.keycode == KEY_RIGHT:
			_step_frame(1)


func _build_character() -> void:
	_character = MODEL.instantiate() as Node3D
	_character.name = &"MotusMan"
	_character.rotation.y = PI # Same asset-facing correction used by player.tscn.
	add_child(_character)
	var skel := _character.find_child("Skeleton3D", true, false) as Skeleton3D
	var player := _character.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if skel == null or player == null:
		push_error("Procedural walk lab: source model needs Skeleton3D and AnimationPlayer")
		return
	if _character.find_children("*", "MeshInstance3D", true, false).is_empty():
		push_error("Procedural walk lab: source model has no visible mesh")
		return
	player.play(&"W1_Stand_Relaxed_Idle_IPC")
	player.advance(0.0)
	player.pause() # Fixed base pose makes frame N reproducible while scrubbing.
	_skeleton = skel
	_modifier = MODIFIER.new() as ProceduralWalkLabModifier
	_modifier.name = &"ProceduralWalk"
	skel.add_child(_modifier)
	skel.set_modifier_callback_mode_process(Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS)
	# Force the initial frame so the model is not shown in bind pose on load.
	skel.advance(0.0)


func _set_frame(value: float) -> void:
	_frame_position = fposmod(value, float(CYCLE_FRAMES))
	_modifier.phase = fposmod(_frame_position * TAU / 60.0, TAU)
	if _frame_slider != null:
		_frame_slider.set_value_no_signal(roundf(_frame_position))
	_update_info()
	if not _playing and _skeleton != null:
		_skeleton.advance(0.0)


func _advance_moving(delta: float) -> void:
	var next_cycles := minf(MAX_MOVING_CYCLES, _travel_cycles + delta * _speed)
	var advanced_cycles := next_cycles - _travel_cycles
	_travel_cycles = next_cycles
	var travel_per_cycle := (
			2.0 * _modifier.stride * _modifier.amount
			/ (1.0 - ProceduralWalkLabModifier.SWING_FRACTION))
	_character.global_position.z -= advanced_cycles * travel_per_cycle
	_set_frame(_travel_cycles * 60.0)
	_update_camera()
	if _travel_cycles >= MAX_MOVING_CYCLES:
		_playing = false
		_update_info()


func _set_moving_mode(enabled: bool) -> void:
	_moving_mode = enabled
	_travel_cycles = 0.0
	_character.global_position = Vector3.ZERO
	_modifier.moving_mode = enabled
	_modifier.reset_moving_state()
	_playing = true
	_set_frame(0.0)
	if _frame_slider != null:
		_frame_slider.editable = not enabled
	if _back_button != null:
		_back_button.disabled = enabled
	_update_camera()


func _reset_walk() -> void:
	_set_moving_mode(_moving_mode)


func _step_frame(direction: int) -> void:
	_playing = false
	if _moving_mode:
		if direction > 0:
			_advance_moving(1.0 / 60.0)
		return
	_set_frame(roundf(_frame_position) + float(direction))


func _build_stage() -> void:
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	floor_mesh.mesh.size = Vector2(20.0, 20.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.18, 0.20, 0.23)
	floor_mesh.material_override = floor_material
	add_child(floor_mesh)
	var grid_mesh := ImmediateMesh.new()
	var grid_material := StandardMaterial3D.new()
	grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_material.albedo_color = Color(0.38, 0.41, 0.45)
	grid_mesh.surface_begin(Mesh.PRIMITIVE_LINES, grid_material)
	for line in range(-10, 11):
		var coordinate := float(line)
		grid_mesh.surface_add_vertex(Vector3(coordinate, 0.003, -10.0))
		grid_mesh.surface_add_vertex(Vector3(coordinate, 0.003, 10.0))
		grid_mesh.surface_add_vertex(Vector3(-10.0, 0.003, coordinate))
		grid_mesh.surface_add_vertex(Vector3(10.0, 0.003, coordinate))
	grid_mesh.surface_end()
	var grid := MeshInstance3D.new()
	grid.mesh = grid_mesh
	add_child(grid)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_energy = 1.5
	add_child(sun)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 50.0
	add_child(_camera)
	_update_camera()


func _update_camera() -> void:
	var target := (
			_character.global_position if _character != null else Vector3.ZERO)
	target.y += 1.0
	_camera.position = target + Vector3(
			sin(_yaw) * cos(_pitch) * _distance,
			sin(_pitch) * _distance,
			cos(_yaw) * cos(_pitch) * _distance)
	_camera.look_at(target)


func _build_joint_overlay() -> void:
	_joint_lines = ImmediateMesh.new()
	_joint_materials["Left"] = _joint_material(&"LeftLeg")
	_joint_materials["Right"] = _joint_material(&"RightLeg")
	var lines := MeshInstance3D.new()
	lines.mesh = _joint_lines
	add_child(lines)
	var sphere := SphereMesh.new()
	sphere.radius = 0.026
	sphere.height = 0.052
	for name: StringName in ProceduralWalkLabModifier.DEBUG_JOINTS:
		var marker := MeshInstance3D.new()
		marker.mesh = sphere
		marker.material_override = _joint_materials[
				"Left" if String(name).begins_with("Left") else "Right"]
		add_child(marker)
		_joint_markers[name] = marker


func _joint_material(name: StringName) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = (
			Color(0.9, 0.25, 1.0) if String(name).begins_with("Left")
			else Color(0.25, 0.65, 1.0))
	return material


func _update_joint_overlay() -> void:
	if _modifier == null or _joint_lines == null:
		return
	var joints: Dictionary = _modifier.debug_joint_positions
	_joint_lines.clear_surfaces()
	for side: String in ["Left", "Right"]:
		var names: Array[StringName] = [
			StringName(side + "UpLeg"), StringName(side + "Leg"),
			StringName(side + "Foot"), StringName(side + "ToeBase"),
		]
		if not _show_joints:
			continue
		_joint_lines.surface_begin(Mesh.PRIMITIVE_LINES, _joint_materials[side])
		for index in 3:
			if joints.has(names[index]) and joints.has(names[index + 1]):
				_joint_lines.surface_add_vertex(joints[names[index]])
				_joint_lines.surface_add_vertex(joints[names[index + 1]])
		_joint_lines.surface_end()
	for name: StringName in _joint_markers:
		var marker: MeshInstance3D = _joint_markers[name]
		marker.visible = _show_joints and joints.has(name)
		if marker.visible:
			marker.global_position = joints[name]
	if _joint_label != null:
		_joint_label.text = _joint_text(joints)


func _joint_text(joints: Dictionary) -> String:
	if joints.is_empty():
		return "Joint data waiting for first frame"
	var rows: Array[String] = []
	for side: String in ["Left", "Right"]:
		var knee_name := StringName(side + "Leg")
		var ankle_name := StringName(side + "Foot")
		if joints.has(knee_name) and joints.has(ankle_name):
			var knee: Vector3 = joints[knee_name]
			var ankle: Vector3 = joints[ankle_name]
			var flex: float = _modifier.debug_knee_flex.get(side, 0.0)
			rows.append("%s knee %.1f deg (%.2f, %.2f, %.2f)  ankle (%.2f, %.2f, %.2f)" % [
				side, flex, knee.x, knee.y, knee.z, ankle.x, ankle.y, ankle.z])
	return "\n".join(rows)


func _run_lab_check() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_playing = false
	_set_frame(15.0)
	await get_tree().physics_frame
	var first: Dictionary = _modifier.debug_joint_positions.duplicate()
	_set_frame(45.0)
	await get_tree().physics_frame
	var second: Dictionary = _modifier.debug_joint_positions.duplicate()
	var moved := (first.has(&"LeftFoot") and second.has(&"LeftFoot")
			and (first[&"LeftFoot"] as Vector3).distance_to(second[&"LeftFoot"]) > 0.02)
	_set_frame(0.0)
	await get_tree().physics_frame
	var rear: Vector3 = _modifier.debug_joint_positions.get(&"LeftFoot", Vector3.ZERO)
	_set_frame(30.0)
	await get_tree().physics_frame
	var front: Vector3 = _modifier.debug_joint_positions.get(&"LeftFoot", Vector3.ZERO)
	var forward := front.z < rear.z - 0.05 # Model faces world -Z.
	var previous: Dictionary = {}
	var worst_degrees := 0.0
	var worst_frame := -1
	var worst_joint := &""
	var previous_flex: Dictionary = {}
	var worst_flex_change := 0.0
	var left_contact_flex := 0.0
	var right_contact_flex := 0.0
	var left_contact_y := 0.0
	var right_contact_y := 0.0
	var left_contact_error := 0.0
	var right_contact_error := 0.0
	var left_precontact_y := 0.0
	var right_precontact_y := 0.0
	var left_stance_y := 0.0
	var right_stance_y := 0.0
	for frame in range(CYCLE_FRAMES + 1):
		_set_frame(float(frame))
		await get_tree().physics_frame
		var rotations: Dictionary = _modifier.debug_joint_rotations.duplicate()
		var flex: Dictionary = _modifier.debug_knee_flex.duplicate()
		var joints: Dictionary = _modifier.debug_joint_positions
		if frame == 20:
			left_precontact_y = (joints[&"LeftToeBase"] as Vector3).y
		if frame == 24:
			left_contact_flex = flex["Left"]
			left_contact_y = (joints[&"LeftToeBase"] as Vector3).y
			left_contact_error = _modifier.debug_target_error["Left"]
		if frame == 30:
			left_stance_y = (joints[&"LeftToeBase"] as Vector3).y
		if frame == 50:
			right_precontact_y = (joints[&"RightToeBase"] as Vector3).y
		if frame == 54:
			right_contact_flex = flex["Right"]
			right_contact_y = (joints[&"RightToeBase"] as Vector3).y
			right_contact_error = _modifier.debug_target_error["Right"]
		if frame == 60:
			right_stance_y = (joints[&"RightToeBase"] as Vector3).y
		for side: String in flex:
			if previous_flex.has(side):
				worst_flex_change = maxf(worst_flex_change,
						absf(float(flex[side]) - float(previous_flex[side])))
		if not previous.is_empty():
			for name: StringName in rotations:
				var degrees := rad_to_deg(
						(rotations[name] as Quaternion).angle_to(previous[name]))
				if degrees > worst_degrees:
					worst_degrees = degrees
					worst_frame = frame
					worst_joint = name
		previous = rotations
		previous_flex = flex
	var passed := (moved and forward and first.size() == 8 and second.size() == 8
			and worst_degrees < 6.0 and worst_flex_change < 8.0
			and left_contact_flex > 20.0 and right_contact_flex > 20.0
			and left_contact_error < 0.005 and right_contact_error < 0.005
			and left_precontact_y > left_stance_y + 0.02
			and right_precontact_y > right_stance_y + 0.02
			and absf(left_contact_y - left_stance_y) < 0.002
			and absf(right_contact_y - right_stance_y) < 0.002)
	print(("PROCEDURAL_WALK_LAB_CHECK %s joints=%d moved=%s forward=%s "
			+ "worst_joint=%.2fdeg@f%d %s knee_change=%.2fdeg "
			+ "contact_flex=%.1f/%.1fdeg contact_y=%.3f/%.3f")
			% ["PASS" if passed else "FAIL", second.size(), str(moved), str(forward),
			worst_degrees, worst_frame, worst_joint, worst_flex_change,
			left_contact_flex, right_contact_flex, left_contact_y, right_contact_y])
	get_tree().quit(0 if passed else 1)


func _contact_report() -> void:
	await get_tree().physics_frame
	_playing = false
	for frame in range(0, 76):
		_set_frame(float(frame))
		await get_tree().physics_frame
		if frame % 5 != 0 and frame not in [27, 28, 29, 31, 32, 57, 58, 59, 61, 62]:
			continue
		var joints: Dictionary = _modifier.debug_joint_positions
		print(("CONTACT f%d L toe=%.3f ankle=%.3f knee=%.1f err=%.3f "
				+ "R toe=%.3f ankle=%.3f knee=%.1f err=%.3f") % [frame,
				(joints[&"LeftToeBase"] as Vector3).y,
				(joints[&"LeftFoot"] as Vector3).y,
				_modifier.debug_knee_flex["Left"], _modifier.debug_target_error["Left"],
				(joints[&"RightToeBase"] as Vector3).y,
				(joints[&"RightFoot"] as Vector3).y,
				_modifier.debug_knee_flex["Right"], _modifier.debug_target_error["Right"]])
	get_tree().quit()


func _run_moving_check() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_set_moving_mode(true)
	var max_plant_error := 0.0
	var planted_samples := 0
	var worst_joint := 0.0
	var previous: Dictionary = {}
	for frame in 180:
		await get_tree().physics_frame
		var joints: Dictionary = _modifier.debug_joint_positions
		var rotations: Dictionary = _modifier.debug_joint_rotations
		if frame > 60:
			for side in 2:
				if not _modifier.has_plant(side):
					continue
				var name := &"LeftFoot" if side == 0 else &"RightFoot"
				var ankle: Vector3 = joints[name]
				max_plant_error = maxf(max_plant_error,
						ankle.distance_to(_modifier.plant_world(side)))
				planted_samples += 1
		if not previous.is_empty():
			for name: StringName in rotations:
				worst_joint = maxf(worst_joint, rad_to_deg(
						(rotations[name] as Quaternion).angle_to(previous[name])))
		previous = rotations.duplicate()
	var passed := (_character.global_position.z < -1.5
			and planted_samples > 60 and max_plant_error < 0.02
			and worst_joint < 12.0)
	print(("PROCEDURAL_WALK_MOVING_CHECK %s distance=%.2fm samples=%d "
			+ "plant_error=%.4fm worst_joint=%.2fdeg") % [
			"PASS" if passed else "FAIL", absf(_character.global_position.z),
			planted_samples, max_plant_error, worst_joint])
	get_tree().quit(0 if passed else 1)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16.0, 16.0)
	panel.custom_minimum_size = Vector2(270.0, 0.0)
	layer.add_child(panel)
	var controls := VBoxContainer.new()
	panel.add_child(controls)
	_info = Label.new()
	controls.add_child(_info)
	_update_info()
	var timeline := HBoxContainer.new()
	controls.add_child(timeline)
	_back_button = Button.new()
	_back_button.text = "<"
	_back_button.pressed.connect(func() -> void: _step_frame(-1))
	timeline.add_child(_back_button)
	var play := Button.new()
	play.text = "Play / Pause"
	play.pressed.connect(func() -> void:
		_playing = not _playing
		_update_info())
	timeline.add_child(play)
	var forward := Button.new()
	forward.text = ">"
	forward.pressed.connect(func() -> void: _step_frame(1))
	timeline.add_child(forward)
	_frame_slider = HSlider.new()
	_frame_slider.min_value = 0.0
	_frame_slider.max_value = CYCLE_FRAMES - 1
	_frame_slider.step = 1.0
	_frame_slider.custom_minimum_size = Vector2(270.0, 20.0)
	_frame_slider.value_changed.connect(func(value: float) -> void:
		_playing = false
		_set_frame(value))
	controls.add_child(_frame_slider)
	var moving := CheckBox.new()
	moving.text = "Move forward + lock planted feet"
	moving.toggled.connect(_set_moving_mode)
	controls.add_child(moving)
	var reset := Button.new()
	reset.text = "Reset walk"
	reset.pressed.connect(_reset_walk)
	controls.add_child(reset)
	_add_slider(controls, "Steps / second", 0.2, 2.0, _speed,
			func(value: float) -> void: _speed = value)
	_add_slider(controls, "Stride (m)", 0.0, 0.45, _modifier.stride,
			func(value: float) -> void: _modifier.stride = value)
	_add_slider(controls, "Foot lift (m)", 0.0, 0.30, _modifier.lift,
			func(value: float) -> void: _modifier.lift = value)
	_add_slider(controls, "Walk blend", 0.0, 1.0, _modifier.amount,
			func(value: float) -> void: _modifier.amount = value)
	_add_slider(controls, "Arm swing", 0.0, 0.6, _modifier.arm_swing,
			func(value: float) -> void: _modifier.arm_swing = value)
	var show := CheckBox.new()
	show.text = "Show leg joints (purple left / blue right)"
	show.button_pressed = true
	show.toggled.connect(func(value: bool) -> void: _show_joints = value)
	controls.add_child(show)
	_joint_label = Label.new()
	controls.add_child(_joint_label)
	var hint := Label.new()
	hint.text = ("Drag empty space: orbit   Wheel: zoom   Space: pause\n"
			+ "In-place: scrub/step both ways   Moving: step forward/reset")
	controls.add_child(hint)


func _update_info() -> void:
	if _info == null:
		return
	_info.text = "Procedural walk | %s | frame %03d/%03d | %s" % [
			"moving %.1fm" % absf(_character.global_position.z)
			if _moving_mode and _character != null else "in place",
			int(_frame_position) + 1, CYCLE_FRAMES,
			"Playing" if _playing else "Paused"]


func _add_slider(parent: VBoxContainer, title: String, minimum: float,
		maximum: float, initial: float, callback: Callable) -> void:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 0.01
	slider.value = initial
	slider.value_changed.connect(callback)
	parent.add_child(slider)
