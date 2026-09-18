extends Node3D
## Standalone MotusMan procedural walk experiment. Does not spawn Player.

const MODEL := preload(
		"res://assets/models/pistol_starter/Animation/In-Place/W1_Stand_Relaxed_Idle_IPC.fbx")
const MODIFIER := preload("res://tests/manual/procedural_walk/procedural_walk_modifier.gd")
const REFERENCE_BANK := preload(
		"res://tests/manual/procedural_walk/procedural_walk_reference_bank.gd")
const METRICS := preload("res://tests/manual/procedural_walk/procedural_walk_metrics.gd")
const MESH_CLEARANCE := preload(
		"res://tests/manual/procedural_walk/procedural_walk_mesh_clearance.gd")
const POSE_CHECK := preload(
		"res://tests/manual/procedural_walk/procedural_walk_pose_match_check.gd")
const FLAT_MESH_CHECK := preload(
		"res://tests/manual/procedural_walk/procedural_walk_flat_mesh_check.gd")
const STAIR_SOURCE_REPORT := preload(
		"res://tests/manual/procedural_walk/procedural_walk_stair_source_report.gd")
const INFINITE_CHECK := preload(
		"res://tests/manual/procedural_walk/procedural_walk_infinite_check.gd")
const CYCLE_FRAMES := 120 # Two complete steps at a 60 fps reference rate.
const MAX_STAIR_CYCLES := 8.0
const METRIC_BONES := [
	&"Hips", &"Spine", &"Spine1", &"Spine2", &"Head",
	&"LeftShoulder", &"LeftArm", &"LeftForeArm", &"LeftHand",
	&"RightShoulder", &"RightArm", &"RightForeArm", &"RightHand",
	&"LeftUpLeg", &"LeftLeg", &"LeftFoot", &"LeftToeBase",
	&"RightUpLeg", &"RightLeg", &"RightFoot", &"RightToeBase",
]

var _modifier: ProceduralWalkLabModifier
var _skeleton: Skeleton3D
var _character: Node3D
var _reference_character: Node3D
var _reference_skeleton: Skeleton3D
var _reference_player: AnimationPlayer
var _reference_bank: ProceduralWalkReferenceBank
var _metrics: ProceduralWalkMetrics
var _reference_mode := &""
var _show_reference := false
var _speed_slider: HSlider
var _camera: Camera3D
var _speed := 1.0
var _playing := true
var _frame_position := 0.0
var _yaw := PI * 0.5
var _pitch := 0.12
var _distance := 3.7
var _dragging := false
var _info: Label
var _frame_slider: HSlider
var _joint_label: Label
var _metric_label: Label
var _joint_lines: ImmediateMesh
var _joint_markers: Dictionary = {}
var _joint_materials: Dictionary = {}
var _show_joints := true
var _moving_mode := false
var _moving_checkbox: CheckBox
var _stair_stage: Node3D
var _floor_stage: Node3D
var _travel_cycles := 0.0
var _back_button: Button


func _ready() -> void:
	_build_stage()
	_build_character()
	_build_reference()
	_build_joint_overlay()
	_build_ui()
	_metrics = METRICS.new() as ProceduralWalkMetrics
	_metrics.start(&"")
	if "--lab-check" in OS.get_cmdline_user_args():
		_run_lab_check()
	elif "--moving-check" in OS.get_cmdline_user_args():
		_run_moving_check()
	elif "--reference-check" in OS.get_cmdline_user_args():
		_run_reference_check()
	elif "--profile-check" in OS.get_cmdline_user_args():
		_run_profile_check()
	elif "--pose-match-check" in OS.get_cmdline_user_args():
		_run_pose_match_check()
	elif "--flat-mesh-check" in OS.get_cmdline_user_args():
		_run_flat_mesh_check()
	elif "--stair-source-report" in OS.get_cmdline_user_args():
		_run_stair_source_report()
	elif "--infinite-check" in OS.get_cmdline_user_args():
		_run_infinite_check()
	elif "--stair-check" in OS.get_cmdline_user_args():
		_run_stair_check()
	elif "--toe-check" in OS.get_cmdline_user_args() \
			or "--toe-report" in OS.get_cmdline_user_args():
		_run_toe_report()
	elif "--contact-report" in OS.get_cmdline_user_args():
		_contact_report()
	else:
		_moving_checkbox.set_pressed_no_signal(true)
		_set_moving_mode(true)


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
	_update_metrics()


func _exit_tree() -> void:
	if _metrics != null:
		_metrics.close()


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
	_modifier.neutral_ankle_targets = [
		skel.get_bone_global_pose(skel.find_bone(&"LeftFoot")).origin,
		skel.get_bone_global_pose(skel.find_bone(&"RightFoot")).origin,
	]
	skel.add_child(_modifier)
	skel.set_modifier_callback_mode_process(Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS)
	# Force the initial frame so the model is not shown in bind pose on load.
	skel.advance(0.0)


func _build_reference() -> void:
	_reference_bank = REFERENCE_BANK.new() as ProceduralWalkReferenceBank
	if not _reference_bank.build(self, _skeleton):
		push_error("Procedural walk lab: could not build reference pose bank")
		return
	_reference_character = MODEL.instantiate() as Node3D
	_reference_character.name = &"ReferenceMotusMan"
	_reference_character.rotation.y = PI
	_reference_character.position.x = 1.4
	add_child(_reference_character)
	_reference_skeleton = _reference_character.find_child(
			"Skeleton3D", true, false) as Skeleton3D
	_reference_player = _reference_character.find_child(
			"AnimationPlayer", true, false) as AnimationPlayer
	_reference_player.stop()
	_reference_player.root_node = _reference_player.get_path_to(
			_reference_skeleton.get_parent())
	var library := AnimationLibrary.new()
	for mode: StringName in ProceduralWalkReferenceBank.MODE_ORDER:
		library.add_animation(mode, _reference_bank.clip(mode))
	_reference_player.add_animation_library(&"references", library)
	_reference_character.visible = false
	_modifier.reference_bank = _reference_bank
	var label := Label3D.new()
	label.text = "REFERENCE"
	label.position = Vector3(0.0, 2.15, 0.0)
	label.font_size = 48
	_reference_character.add_child(label)


func _set_frame(value: float) -> void:
	_frame_position = fposmod(value, float(CYCLE_FRAMES))
	_modifier.phase = fposmod(_frame_position * TAU / 60.0, TAU)
	_sync_reference()
	if _frame_slider != null:
		_frame_slider.set_value_no_signal(roundf(_frame_position))
	_update_info()
	if not _playing and _skeleton != null:
		_skeleton.advance(0.0)


func _sync_reference() -> void:
	if _reference_player == null or _reference_mode == &"":
		return
	var animation_name := "references/" + String(_reference_mode)
	if _reference_player.current_animation != animation_name:
		_reference_player.stop()
		_reference_player.play(animation_name)
		_reference_player.pause()
	var clip := _reference_bank.clip(_reference_mode)
	_reference_player.seek(clip.length * fposmod(_modifier.phase / TAU, 1.0), true)
	_reference_player.advance(0.0)
	_reference_skeleton.advance(0.0)


func _select_reference_mode(index: int) -> void:
	_reference_mode = (
			&"" if index == 0 else ProceduralWalkReferenceBank.MODE_ORDER[index - 1])
	_modifier.reference_mode = _reference_mode
	if _moving_checkbox != null:
		_moving_checkbox.text = ("Move forward (source pose; no foot lock)"
				if _reference_mode != &"" and _reference_mode not in [&"stair_up", &"stair_down"]
				else
				"Move forward + lock planted feet")
	_modifier.stair_direction = (1 if _reference_mode == &"stair_up" else
			-1 if _reference_mode == &"stair_down" else 0)
	_stair_stage.visible = _modifier.stair_direction != 0
	_rebuild_stair_stage()
	if _metrics != null:
		_metrics.start(_reference_mode)
	if _reference_mode == &"":
		_modifier.bob = 0.025
		_reference_player.stop()
	else:
		_modifier.bob = 0.0 # Source pose already carries its own body motion.
		_speed = 1.0 / _reference_bank.clip(_reference_mode).length
		if _speed_slider != null:
			_speed_slider.set_value_no_signal(_speed)
	_sync_reference()
	if _modifier.stair_direction != 0:
		if _moving_checkbox != null:
			_moving_checkbox.set_pressed_no_signal(true)
		_set_moving_mode(true)
	elif _moving_mode:
		_set_moving_mode(true)
	_update_reference_visibility()
	_update_info()


func _update_reference_visibility() -> void:
	if _reference_character == null:
		return
	_reference_character.visible = _show_reference and _reference_mode != &""
	_update_camera()


func _advance_moving(delta: float) -> void:
	var next_cycles := _travel_cycles + delta * _speed
	if _modifier.stair_direction != 0:
		next_cycles = minf(MAX_STAIR_CYCLES, next_cycles)
	var advanced_cycles := next_cycles - _travel_cycles
	_travel_cycles = next_cycles
	var travel_per_cycle := 2.0 * _modifier.stride * _modifier.amount / (
			1.0 - ProceduralWalkLabModifier.SWING_FRACTION)
	if _modifier.stair_direction == 0 and _reference_mode != &"":
		travel_per_cycle = _reference_bank.flat_travel_per_cycle[_reference_mode]
	_character.global_position.z -= advanced_cycles * travel_per_cycle
	_sync_floor_stage()
	var desired_height := _modifier.stair_root_height(_character.global_position.z)
	if _modifier.stair_direction > 0:
		# Keep the trailing planted ankle reachable while climbing.
		for side in 2:
			if _modifier.has_plant(side):
				desired_height = minf(desired_height,
						_modifier.plant_world(side).y
						- _modifier.neutral_ankle_targets[side].y + 0.02)
	_character.global_position.y = move_toward(
			_character.global_position.y, desired_height, delta * 1.5)
	if _reference_character != null:
		_reference_character.global_position = (
				_character.global_position + Vector3(1.4, 0.0, 0.0))
	_set_frame(_travel_cycles * 60.0)
	_update_camera()
	if _modifier.stair_direction != 0 and _travel_cycles >= MAX_STAIR_CYCLES:
		_playing = false
		_update_info()

func _sync_floor_stage() -> void:
	if _floor_stage != null and _character != null:
		_floor_stage.position.z = roundf(_character.global_position.z)


func _set_moving_mode(enabled: bool) -> void:
	_moving_mode = enabled
	_travel_cycles = 0.0
	_character.global_position = Vector3(
			0.0, _modifier.stair_root_height(1.4),
			1.4 if _modifier.stair_direction != 0 else 0.0)
	_sync_floor_stage()
	if _reference_character != null:
		_reference_character.global_position = (
				_character.global_position + Vector3(1.4, 0.0, 0.0))
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
	_floor_stage = Node3D.new()
	_floor_stage.name = &"RecycledFlatFloor"
	add_child(_floor_stage)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	floor_mesh.mesh.size = Vector2(80.0, 80.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.18, 0.20, 0.23)
	floor_mesh.material_override = floor_material
	_floor_stage.add_child(floor_mesh)
	var grid_mesh := ImmediateMesh.new()
	var grid_material := StandardMaterial3D.new()
	grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_material.albedo_color = Color(0.38, 0.41, 0.45)
	grid_mesh.surface_begin(Mesh.PRIMITIVE_LINES, grid_material)
	for line in range(-40, 41):
		var coordinate := float(line)
		grid_mesh.surface_add_vertex(Vector3(coordinate, 0.003, -40.0))
		grid_mesh.surface_add_vertex(Vector3(coordinate, 0.003, 40.0))
		grid_mesh.surface_add_vertex(Vector3(-40.0, 0.003, coordinate))
		grid_mesh.surface_add_vertex(Vector3(40.0, 0.003, coordinate))
	grid_mesh.surface_end()
	var grid := MeshInstance3D.new()
	grid.mesh = grid_mesh
	_floor_stage.add_child(grid)
	_stair_stage = Node3D.new()
	_stair_stage.name = &"StairStage"
	_stair_stage.visible = false
	add_child(_stair_stage)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_energy = 1.5
	add_child(sun)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 50.0
	add_child(_camera)
	_update_camera()


func _rebuild_stair_stage() -> void:
	for child: Node in _stair_stage.get_children():
		child.free()
	if _modifier.stair_direction == 0:
		return
	for x in [0.0, 1.4]:
		_build_stair_lane(x, _modifier.stair_direction > 0)


func _build_stair_lane(x: float, up: bool) -> void:
	# Visual support surfaces match the modifier's discrete height function.
	var high := float(ProceduralWalkLabModifier.STAIR_STEPS) * (
			ProceduralWalkLabModifier.STAIR_HEIGHT)
	if not up:
		_add_stair_box(x, 2.75, 3.5, high, up)
	for step in ProceduralWalkLabModifier.STAIR_STEPS:
		var z := ProceduralWalkLabModifier.STAIR_START_Z - (
				float(step) + 0.5) * ProceduralWalkLabModifier.STAIR_DEPTH
		_add_stair_box(x, z, ProceduralWalkLabModifier.STAIR_DEPTH,
				(float(step) if up else float(ProceduralWalkLabModifier.STAIR_STEPS - step))
				* ProceduralWalkLabModifier.STAIR_HEIGHT, up)
	if up:
		_add_stair_box(x, -2.15, 3.5, high, up)


func _add_stair_box(x: float, z: float, depth: float,
		height: float, up: bool) -> MeshInstance3D:
	var block := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.2, maxf(height, 0.01), depth)
	block.mesh = box
	block.position = Vector3(x, height * 0.5, z)
	var material := StandardMaterial3D.new()
	material.albedo_color = (Color(0.35, 0.38, 0.42) if up
			else Color(0.44, 0.39, 0.36))
	block.material_override = material
	_stair_stage.add_child(block)
	return block


func _update_camera() -> void:
	var target := (
			_character.global_position if _character != null else Vector3.ZERO)
	target.y += 1.0
	if _reference_character != null and _reference_character.visible:
		target.x += 0.7
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


func _update_metrics() -> void:
	if _metrics == null or _modifier == null or _skeleton == null:
		return
	var reference: Skeleton3D = (
			_reference_skeleton if _reference_mode != &"" else null)
	var sample := _metrics.observe(int(_frame_position), _modifier.phase,
			_moving_mode, _character.global_position.z, _modifier, _skeleton, reference)
	if _metric_label == null or sample.is_empty():
		return
	_metric_label.text = ("Frame joint step: %.1f° %s  |  source %.1f°\n"
			+ "Pose difference: %.1f° %s  |  JSONL: first 240 frames/mode") % [
			sample["worst_procedural_step_deg"], sample["worst_procedural_step_joint"],
			sample["worst_reference_step_deg"], sample["worst_pose_deg"],
			sample["worst_pose_joint"]]


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


func _run_reference_check() -> void:
	await get_tree().physics_frame
	var passed := true
	for mode: StringName in ProceduralWalkReferenceBank.MODE_ORDER:
		var clip := _reference_bank.clip(mode)
		var pose_a := _reference_bank.sample_pose(mode, 0.0)
		var pose_b := _reference_bank.sample_pose(mode, PI * 0.5)
		var arm := _skeleton.find_bone(&"RightArm")
		var arm_change := rad_to_deg(pose_a[arm].basis.get_rotation_quaternion().angle_to(
				pose_b[arm].basis.get_rotation_quaternion()))
		var okay := (clip != null and pose_a.size() == _skeleton.get_bone_count()
				and arm_change > 0.5)
		passed = passed and okay
		print("PROCEDURAL_REFERENCE %s %s len=%.3f arm_change=%.2fdeg" % [
				mode, "PASS" if okay else "FAIL", clip.length, arm_change])
	get_tree().quit(0 if passed else 1)


func _run_profile_check() -> void:
	await get_tree().physics_frame
	var all_valid := true
	for mode_index in ProceduralWalkReferenceBank.MODE_ORDER.size():
		_select_reference_mode(mode_index + 1)
		_playing = false
		var previous: Array[Transform3D] = []
		var worst_joint := 0.0
		var worst_step_name := &""
		var worst_step_frame := -1
		var worst_pose := 0.0
		var worst_name := &""
		var worst_upper_pose := 0.0
		var worst_upper_name := &""
		for frame in range(CYCLE_FRAMES + 1):
			_set_frame(float(frame))
			await get_tree().physics_frame
			var poses: Array[Transform3D] = _modifier.debug_bone_poses
			if poses.size() != _skeleton.get_bone_count():
				all_valid = false
				continue
			for name: StringName in METRIC_BONES:
				var bone := _skeleton.find_bone(name)
				var now := poses[bone].basis.get_rotation_quaternion()
				var reference := _reference_skeleton.get_bone_global_pose(
						bone).basis.get_rotation_quaternion()
				var pose_diff := rad_to_deg(now.angle_to(reference))
				if pose_diff > worst_pose:
					worst_pose = pose_diff
					worst_name = name
				if not String(name).contains("Leg") and not String(name).contains("Foot") \
						and not String(name).contains("Toe") and pose_diff > worst_upper_pose:
					worst_upper_pose = pose_diff
					worst_upper_name = name
				if not previous.is_empty():
					var step := rad_to_deg(now.angle_to(
							previous[bone].basis.get_rotation_quaternion()))
					if step > worst_joint:
						worst_joint = step
						worst_step_name = name
						worst_step_frame = frame
			previous = poses.duplicate()
		var smooth := worst_joint < 20.0 and worst_upper_pose < 2.0
		all_valid = all_valid and smooth
		print(("PROCEDURAL_PROFILE %s %s max_step=%.2fdeg %s@f%d "
				+ "max_pose_diff=%.2fdeg %s upper_diff=%.2fdeg %s") % [
				_reference_mode, "PASS" if smooth else "FAIL",
				worst_joint, worst_step_name, worst_step_frame,
				worst_pose, worst_name, worst_upper_pose, worst_upper_name])
	get_tree().quit(0 if all_valid else 1)


func _run_pose_match_check() -> void:
	var check := POSE_CHECK.new() as ProceduralWalkPoseMatchCheck
	var passed: bool = await check.run(self, _skeleton, _modifier, _reference_skeleton)
	get_tree().quit(0 if passed else 1)


func _run_flat_mesh_check() -> void:
	var check := FLAT_MESH_CHECK.new() as ProceduralWalkFlatMeshCheck
	var passed: bool = await check.run(self, _character, _skeleton, _modifier)
	get_tree().quit(0 if passed else 1)


func _run_stair_source_report() -> void:
	var report := STAIR_SOURCE_REPORT.new() as ProceduralWalkStairSourceReport
	await report.run(self, _character, _skeleton, _modifier,
			_reference_character, _reference_skeleton)
	get_tree().quit()


func _run_infinite_check() -> void:
	var check := INFINITE_CHECK.new() as ProceduralWalkInfiniteCheck
	var passed: bool = await check.run(self, _character, _reference_character, _floor_stage)
	get_tree().quit(0 if passed else 1)


func _run_stair_check() -> void:
	await get_tree().physics_frame
	var all_passed := true
	for mode in [4, 5]:
		_select_reference_mode(mode + 1)
		var start_y := _character.global_position.y
		var worst_plant_error := 0.0
		var worst_plant_frame := -1
		var worst_plant_side := -1
		var planted_samples := 0
		var worst_step := 0.0
		var previous: Dictionary = {}
		for frame in 240:
			await get_tree().physics_frame
			var rotations: Dictionary = _modifier.debug_joint_rotations
			for side in 2:
				if not _modifier.has_plant(side):
					continue
				var name := &"LeftFoot" if side == 0 else &"RightFoot"
				var error := (_modifier.debug_joint_positions[name] as Vector3).distance_to(
						_modifier.plant_world(side))
				if error > worst_plant_error:
					worst_plant_error = error
					worst_plant_frame = frame
					worst_plant_side = side
				planted_samples += 1
			if not previous.is_empty():
				for name: StringName in rotations:
					worst_step = maxf(worst_step, rad_to_deg(
							(rotations[name] as Quaternion).angle_to(previous[name])))
			previous = rotations.duplicate()
		var climbed := absf(_character.global_position.y - start_y)
		var passed := climbed > 0.6 and planted_samples > 100 \
				and worst_plant_error < 0.03 and worst_step < 30.0
		all_passed = all_passed and passed
		print(("PROCEDURAL_STAIR %s %s elevation=%.2fm planted=%d "
				+ "plant_error=%.3fm@f%d/side%d max_joint_step=%.1fdeg") % [
				_reference_mode, "PASS" if passed else "FAIL", climbed,
				planted_samples, worst_plant_error, worst_plant_frame,
				worst_plant_side, worst_step])
	get_tree().quit(0 if all_passed else 1)


func _run_toe_report() -> void:
	await get_tree().physics_frame
	_select_reference_mode(1)
	var mesh_check := MESH_CLEARANCE.new() as ProceduralWalkMeshClearance
	mesh_check.prepare(_character, _skeleton)
	var source_mesh_check := MESH_CLEARANCE.new() as ProceduralWalkMeshClearance
	source_mesh_check.prepare(_reference_character, _reference_skeleton)
	print("TOE_MESH foot_vertices=%d source_vertices=%d" % [
			mesh_check.vertex_count, source_mesh_check.vertex_count])
	var all_passed := true
	for moving in [false, true]:
		_set_moving_mode(moving)
		_playing = moving
		var worst: Array[Dictionary] = []
		var min_toe_y := INF
		var worst_stance_gap := 0.0
		var worst_foot_rotation := 0.0
		var min_mesh_y := INF
		var min_source_mesh_y := INF
		var source_low: Array[float] = []
		var procedural_low: Array[float] = []
		for frame in 120:
			if not moving:
				_set_frame(float(frame))
			await get_tree().physics_frame
			var mesh_min := mesh_check.sample(_skeleton, _modifier.debug_bone_poses)
			min_mesh_y = minf(min_mesh_y, minf(mesh_min[0], mesh_min[1]))
			procedural_low.append(minf(mesh_min[0], mesh_min[1]))
			var source_poses: Array[Transform3D] = []
			for bone in _reference_skeleton.get_bone_count():
				source_poses.append(_reference_skeleton.get_bone_global_pose(bone))
			var source_mesh_min := source_mesh_check.sample(
					_reference_skeleton, source_poses)
			min_source_mesh_y = minf(min_source_mesh_y,
					minf(source_mesh_min[0], source_mesh_min[1]))
			source_low.append(minf(source_mesh_min[0], source_mesh_min[1]))
			for side: String in ["Left", "Right"]:
				var name := StringName(side + "ToeBase")
				var toe: Vector3 = _modifier.debug_joint_positions[name]
				var bone := _reference_skeleton.find_bone(name)
				var source_toe := _reference_skeleton.global_transform * (
						_reference_skeleton.get_bone_global_pose(bone).origin)
				min_toe_y = minf(min_toe_y, toe.y)
				var side_offset := 0.0 if side == "Left" else PI
				var side_cycle := fposmod(
						(_modifier.phase + side_offset) / TAU, 1.0)
				if side_cycle >= ProceduralWalkLabModifier.SWING_FRACTION:
					worst_stance_gap = maxf(worst_stance_gap,
							absf(toe.y - source_toe.y))
				var foot := _skeleton.find_bone(StringName(side + "Foot"))
				worst_foot_rotation = maxf(worst_foot_rotation, rad_to_deg(
						_modifier.debug_bone_poses[foot].basis.get_rotation_quaternion()
						.angle_to(_reference_skeleton.get_bone_global_pose(
								foot).basis.get_rotation_quaternion())))
				worst.append({"frame": frame, "side": side,
						"toe_y": toe.y, "source_y": source_toe.y,
						"gap": toe.y - source_toe.y})
		worst.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a["toe_y"] < b["toe_y"])
		for index in mini(8, worst.size()):
			var row: Dictionary = worst[index]
			print("TOE %s f%d %s procedural=%.3f source=%.3f gap=%.3f" % [
					"moving" if moving else "in_place", row["frame"], row["side"],
					row["toe_y"], row["source_y"], row["gap"]])
		var passed := (min_toe_y >= 0.013 and min_mesh_y >= 0.004
				and mesh_check.vertex_count > 100 and worst_stance_gap < 0.06
				and worst_foot_rotation < 1.0)
		all_passed = all_passed and passed
		print(("TOE_CHECK %s %s min_y=%.3f min_mesh_y=%.3f source_mesh=%.3f "
				+ "stance_gap=%.3f foot_rotation=%.2fdeg") % [
				"moving" if moving else "in_place", "PASS" if passed else "FAIL",
				min_toe_y, min_mesh_y, min_source_mesh_y,
				worst_stance_gap, worst_foot_rotation])
		if not moving:
			source_low.sort()
			procedural_low.sort()
			print(("MESH_DISTRIBUTION source p50=%.3f p90=%.3f max=%.3f "
					+ "procedural p50=%.3f p90=%.3f max=%.3f") % [
				source_low[60], source_low[108], source_low[119],
				procedural_low[60], procedural_low[108], procedural_low[119]])
	get_tree().quit(0 if all_passed else 1)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16.0, 16.0)
	panel.custom_minimum_size = Vector2(720.0, 0.0)
	layer.add_child(panel)
	var controls := VBoxContainer.new()
	panel.add_child(controls)
	_info = Label.new()
	controls.add_child(_info)
	_update_info()
	var mode_label := Label.new()
	mode_label.text = "Gait source"
	controls.add_child(mode_label)
	var modes := OptionButton.new()
	modes.add_item("Original procedural walk")
	for mode: StringName in ProceduralWalkReferenceBank.MODE_ORDER:
		modes.add_item(ProceduralWalkReferenceBank.MODE_LABELS[mode])
	modes.item_selected.connect(_select_reference_mode)
	controls.add_child(modes)
	var show_reference := CheckBox.new()
	show_reference.text = "Show source animation beside procedural"
	show_reference.toggled.connect(func(value: bool) -> void:
		_show_reference = value
		_update_reference_visibility())
	controls.add_child(show_reference)
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
	_moving_checkbox = CheckBox.new()
	_moving_checkbox.text = "Move forward + lock planted feet"
	_moving_checkbox.toggled.connect(_set_moving_mode)
	controls.add_child(_moving_checkbox)
	var reset := Button.new()
	reset.text = "Reset walk"
	reset.pressed.connect(_reset_walk)
	controls.add_child(reset)
	_speed_slider = _add_slider(controls, "Steps / second", 0.2, 2.0, _speed,
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
	_joint_label.custom_minimum_size.y = 52.0
	controls.add_child(_joint_label)
	_metric_label = Label.new()
	_metric_label.custom_minimum_size.y = 52.0
	controls.add_child(_metric_label)
	var hint := Label.new()
	hint.text = ("Drag empty space: orbit   Wheel: zoom   Space: pause\n"
			+ "In-place: scrub/step both ways   Moving: step forward/reset")
	controls.add_child(hint)


func _update_info() -> void:
	if _info == null:
		return
	_info.text = "Procedural walk | %s | %s | frame %03d/%03d | %s" % [
			"original" if _reference_mode == &"" else String(_reference_mode),
			"moving %.1fm" % absf(_character.global_position.z)
			if _moving_mode and _character != null else "in place",
			int(_frame_position) + 1, CYCLE_FRAMES,
			"Playing" if _playing else "Paused"]


func _add_slider(parent: VBoxContainer, title: String, minimum: float,
		maximum: float, initial: float, callback: Callable) -> HSlider:
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
	return slider
