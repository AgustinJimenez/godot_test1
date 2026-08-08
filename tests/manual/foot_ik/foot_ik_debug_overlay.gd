extends Node3D
## Live contact/target/bone markers + controls; probes expose the post-modifier pose.
const TOE_TIP_EXTRA_LENGTH := 0.035 # toe bone origin is at the base, not the mesh tip
const JOINT_HISTORY_GRAPH := preload(
		"res://tests/manual/foot_ik/foot_ik_joint_history_graph.gd")
const PANEL_OUTER_MARGIN := 20 # gap between screen edge and panel border
# Wide rows would render flush against the panel edge without this.
const PANEL_INNER_PADDING := 14
const PANEL_CONTENT_WIDTH := 460 # independent of padding, so it doesn't shrink the sliders/grid
const STAIR_FOLLOW_HEIGHT := 0.35
const ANIMATION_DISPLAY_FPS := 60.0
const STAIR_FOLLOW_ROOT_OFFSET := Vector3(-0.7034, 0.0967, -0.2845) # rel. to 0.35m walker's root
const STAIR_FOLLOW_ORBIT_SENSITIVITY := 0.006
const STAIR_FOLLOW_MIN_DISTANCE := 0.08
const STAIR_FOLLOW_MAX_DISTANCE := 4.0
const CONTROLLED_TRACE_FILE := "user://foot_ik_controlled.jsonl"
const CONTROLLED_TRACE_MAX_FRAMES := 1200 # 20s at 60fps - room to turn, wait, then grab it
var _player_body: PlayerBody
var _ik: PlayerFootIKModifier
var _skel: Skeleton3D
var _probes: Dictionary = {} # side -> Node3D (BoneAttachment3D child), foot bone
var _toe_probes: Dictionary = {} # side -> Node3D (BoneAttachment3D child), toe bone, or null
var _markers: Dictionary = {} # "side_kind" -> MeshInstance3D, kind in hit/target/actual/toe
var _angle_probes: Dictionary = {} # side -> {hip, knee, leaf: Node3D or null}
var _angle_labels: Dictionary = {} # side -> {segment: Label3D}, positioned at segment midpoint
# Ordered [key, column_header] pairs for the per-foot readout grid (Array,
# not Dictionary, since display order matters and needs to stay fixed).
const READOUT_FIELDS := [
	["hit", "Hit"],
	["target_y", "Target Y"],
	["actual_y", "Actual Y"],
	["gap", "Gap"],
	["lower_distance", "Foot→Lower"],
	["pitch", "Pitch°"],
	["toe_tip_y", "Toe Tip Y"],
	["toe_tip_gap", "Toe Gap"],
	["ground_weight", "IK Weight"],
	["is_floating", "Floating?"],
	["step_down", "StepDown"],
	["raw_weight", "RawWeight"],
	["contact_lost", "CtcLost"],
	["stuck_time", "StuckSec"],
	["vertical_velocity", "Anim VY"],
	["thigh_angle", "Thigh°"],
	["shin_angle", "Shin°"],
	["foot_angle", "Foot°"],
	["leaf_angle", "Leaf°"],
]
var _loop_reset_flash: Label
var _controlled_trace_buffer: Array[String] = []
var _contact_lost_flash: Label
## Marker-file toggle (same pattern as auto-spin) - a per-vertex raycast
## every frame is the right cost for a diagnostic session, not ordinary play.
var _live_penetration_check: RefCounted = (
		preload("res://tests/manual/foot_ik/foot_ik_live_penetration_check.gd").new()
		if FileAccess.file_exists("user://foot_ik_penetration_check_marker") else null)
const LOOP_RESET_FLASH_DURATION := 0.5
var _active_check: CheckButton
var _backend_option: OptionButton
var _pause_button: Button
var _keep_playing_check: CheckButton
var _paused_animation_process_modes: Dictionary = {}
var _animation_timeline: HSlider
var _animation_title: Label
var _animation_time_readout: Label
var _copy_data_button: Button
var _timeline_syncing := false
var _camera_readout: Label
var _joint_history_graph: FootIkJointHistoryGraph
var _readout_values: Dictionary = {} # side -> {field_key: Label}
var _sliders: Dictionary = {} # property name -> HSlider
var _slider_labels: Dictionary = {} # property name -> Label
var _stair_follow_probe: Node3D
var _stair_follow_character: Player
var _stair_follow_enabled := false
var _follow_was_detached := false
var _follow_previous_transform := Transform3D.IDENTITY
var _follow_previous_mouse_mode := Input.MOUSE_MODE_CAPTURED
var _follow_last_anchor := Vector3.ZERO
var _follow_has_anchor := false
var _follow_orbit_dragging := false
var _follow_orbit_last_mouse_position := Vector2.ZERO
func _ready() -> void:
	# This overlay must remain interactive while SceneTree.paused is true;
	# everything else in the harness inherits the ordinary pausable mode.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"foot_ik_camera_preset")
	FileAccess.open(CONTROLLED_TRACE_FILE, FileAccess.WRITE).close()
	call_deferred(&"set_stair_foot_follow_enabled", false)
	# Captured before any physics settling/movement, so it always reflects
	# foot_ik_preview.tscn's own authored Player transform regardless of
	# when in the scene's lifetime the close-up camera actually gets used.
	_player_spawn_position = (get_node("../Player") as Node3D).global_position
	await get_tree().process_frame
	await get_tree().process_frame
	var followed_player: Player = null if FileAccess.file_exists(
			"user://foot_ik_flat_forward_marker") else _find_stair_follow_player()
	_player_body = followed_player.body if followed_player != null \
			else get_node("../Player/Body") as PlayerBody
	if _player_body == null:
		push_warning("FootIkDebugOverlay: Player/Body not found, disabling.")
		set_physics_process(false)
		return
	_skel = _player_body.skeleton
	for child in _skel.get_children():
		if child is PlayerFootIKModifier:
			_ik = child
			break
	if _ik == null:
		push_warning("FootIkDebugOverlay: PlayerFootIKModifier not found, disabling.")
		set_physics_process(false)
		return

	for side: StringName in [&"left", &"right"]:
		var indices: Dictionary = _ik._bone_indices[side]
		var foot_idx: int = indices["foot"]
		var attach := BoneAttachment3D.new()
		_skel.add_child(attach)
		attach.bone_idx = foot_idx
		var probe := Node3D.new()
		attach.add_child(probe)
		_probes[side] = probe
		_markers[str(side) + "_hit"] = FootIkDebugMarkers.spawn_marker(self, Color.GREEN)
		_markers[str(side) + "_target"] = FootIkDebugMarkers.spawn_marker(self, Color.BLUE)
		_markers[str(side) + "_actual"] = FootIkDebugMarkers.spawn_marker(self, Color.RED)
		_markers[str(side) + "_ray"] = FootIkDebugMarkers.spawn_ray(self, Color.WHITE)
		# Separate probe/marker for the toe/ball bone specifically - the
		# ankle marker above can sit right at the target while the toe still
		# visibly pokes up, since it's a distinct bone with its own pose.
		var toe_idx: int = indices.get("toe", -1)
		if toe_idx >= 0:
			var toe_attach := BoneAttachment3D.new()
			_skel.add_child(toe_attach)
			toe_attach.bone_idx = toe_idx
			var toe_probe := Node3D.new()
			toe_attach.add_child(toe_probe)
			_toe_probes[side] = toe_probe
			_markers[str(side) + "_toe"] = FootIkDebugMarkers.spawn_marker(self, Color.YELLOW)

		_angle_probes[side] = {
			"hip": _make_probe(indices["hip"]),
			"knee": _make_probe(indices["knee"]),
			"leaf": _make_probe(indices.get("leaf", -1)) if indices.get("leaf", -1) >= 0 else null,
		}

		_angle_labels[side] = {}
		for segment: String in ["thigh", "shin", "foot", "leaf"]:
			(_angle_labels[side] as Dictionary)[segment] = FootIkDebugMarkers.spawn_angle_label(self)

	_build_panel()

	# Default-on for this scene only, same reasoning as the detached camera
	# default below - the whole point of foot_ik_preview.tscn is inspecting
	# joint placement, so the skeleton overlay should already be visible
	# without an extra menu trip every time the scene reloads.
	_player_body.set_skeleton_visible(true)

	# player.gd only rotates the camera from mouse motion while captured, and
	# stays captured by default on load (matching every other scene) so the
	# camera responds immediately instead of the pointer sitting idle.
	# Backtick frees the mouse on demand for the sliders. Deliberately NOT
	# Tab: Player is real and fully-wired, and Tab is already project-wide
	# "inventory" (see project.godot) - fighting this toggle otherwise.

## Positioning before settling drags the camera down by the fall distance.
func _wait_for_player_to_settle() -> void:
	var player := get_node("../Player") as Player
	if player == null:
		return
	for i in 120: # ~2s at 60Hz - generous, but bail out rather than hang forever
		if player.is_on_floor():
			return
		await get_tree().physics_frame

## Close-up-on-right-foot framing, offset from the player's spawn transform (not absolute).
const DEFAULT_CAMERA_OFFSET := Vector3(0.57, -0.85, 0.45)
const DEFAULT_CAMERA_ROTATION_DEG := Vector3(-27.8, 37.9, 0.0)
var _player_spawn_position: Vector3

## Not default-on now that foot placement is solved; kept on K keybind.
func _start_detached_camera_on_foot() -> void:
	var player := get_node("../Player") as Player
	if player == null:
		return
	player.set_detached_camera_active(true)
	var cam: Camera3D = player.detached_cam
	cam.global_position = _player_spawn_position + DEFAULT_CAMERA_OFFSET
	cam.rotation = Vector3(
			deg_to_rad(DEFAULT_CAMERA_ROTATION_DEG.x), deg_to_rad(DEFAULT_CAMERA_ROTATION_DEG.y),
			deg_to_rad(DEFAULT_CAMERA_ROTATION_DEG.z))
	# set_detached_camera_active() already synced these from the first-person
	# camera - re-sync from our override or the first mouse-look frame snaps
	# the camera back to that original orientation.
	player._detached_yaw = cam.rotation.y
	player._detached_pitch = cam.rotation.x

func _unhandled_input(event: InputEvent) -> void:
	if _stair_follow_enabled and event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			_follow_orbit_dragging = mouse_button.pressed
			_follow_orbit_last_mouse_position = mouse_button.position
			get_viewport().set_input_as_handled()
			return
		if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_stair_follow(0.86)
			get_viewport().set_input_as_handled()
			return
		if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_stair_follow(1.16)
			get_viewport().set_input_as_handled()
			return
	if (_stair_follow_enabled and _follow_orbit_dragging
			and event is InputEventMouseMotion):
		var mouse_motion := event as InputEventMouseMotion
		# MouseMotion.relative can contain a stale capture/window-focus jump on
		# the first click. Screen-position deltas start from the press itself, so
		# a click without a real drag leaves the calibrated camera untouched.
		var drag_delta := mouse_motion.position - _follow_orbit_last_mouse_position
		_follow_orbit_last_mouse_position = mouse_motion.position
		_orbit_stair_follow(drag_delta)
		get_viewport().set_input_as_handled()
		return
	if _stair_follow_enabled and event is InputEventMagnifyGesture:
		var gesture := event as InputEventMagnifyGesture
		_zoom_stair_follow(1.0 / maxf(gesture.factor, 0.01))
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_QUOTELEFT:
		if _stair_follow_enabled:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			return
		Input.mouse_mode = (
				Input.MOUSE_MODE_CAPTURED if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
				else Input.MOUSE_MODE_VISIBLE)
	elif event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_L:
		_log_leg_angles()
	elif event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_K:
		_activate_closeup_camera()

## Settles first, awaited internally since _unhandled_input can't await inline.
func _activate_closeup_camera() -> void:
	await _wait_for_player_to_settle()
	_start_detached_camera_on_foot()

## Same pattern as foot/toe - only reliable way to read a bone's post-modifier pose externally.
func _make_probe(bone_idx: int) -> Node3D:
	var attach := BoneAttachment3D.new()
	_skel.add_child(attach)
	attach.bone_idx = bone_idx
	var probe := Node3D.new()
	attach.add_child(probe)
	return probe

## Per-joint world position + rotation (Euler degrees), keyed by joint name -
## diagnostic output only, never fed back into a computation.
func _capture_joint_transforms(side: StringName) -> Dictionary:
	var angle_probes: Dictionary = _angle_probes.get(side, {})
	var probes := {
		"hip": angle_probes.get("hip"), "knee": angle_probes.get("knee"),
		"foot": _probes.get(side), "toe": _toe_probes.get(side),
		"leaf": angle_probes.get("leaf"),
	}
	var result := {}
	for joint: String in probes:
		var probe: Node3D = probes[joint]
		if probe == null:
			continue
		var xform := probe.global_transform
		result[joint] = {
			"position": xform.origin,
			"rotation_deg": xform.basis.get_euler() * (180.0 / PI),
		}
	return result


## Each segment's OWN absolute angle from world Vector3.DOWN, not the bend
## relative to the previous segment. Shared by readout + console dump.
func _compute_leg_angles(side: StringName) -> Dictionary:
	var angle_probes: Dictionary = _angle_probes.get(side, {})
	var hip_probe: Node3D = angle_probes.get("hip")
	var knee_probe: Node3D = angle_probes.get("knee")
	var leaf_probe: Node3D = angle_probes.get("leaf")
	var foot_probe: Node3D = _probes.get(side)
	var toe_probe: Node3D = _toe_probes.get(side)
	var result := {}
	if hip_probe == null or knee_probe == null or foot_probe == null:
		return result

	var hip_to_knee := knee_probe.global_position - hip_probe.global_position
	var knee_to_foot := foot_probe.global_position - knee_probe.global_position
	result["thigh"] = rad_to_deg(hip_to_knee.angle_to(Vector3.DOWN))
	result["shin"] = rad_to_deg(knee_to_foot.angle_to(Vector3.DOWN))

	if toe_probe != null:
		var foot_to_toe := toe_probe.global_position - foot_probe.global_position
		result["foot"] = rad_to_deg(foot_to_toe.angle_to(Vector3.DOWN))
		if leaf_probe != null:
			var toe_to_leaf := leaf_probe.global_position - toe_probe.global_position
			result["leaf"] = rad_to_deg(toe_to_leaf.angle_to(Vector3.DOWN))
	return result

## Moves each segment's Label3D to its own midpoint and refreshes its text.
func _update_angle_labels(side: String, angles: Dictionary) -> void:
	var labels: Dictionary = _angle_labels.get(side, {})
	var angle_probes: Dictionary = _angle_probes.get(side, {})
	var hip_probe: Node3D = angle_probes.get("hip")
	var knee_probe: Node3D = angle_probes.get("knee")
	var leaf_probe: Node3D = angle_probes.get("leaf")
	var foot_probe: Node3D = _probes.get(side)
	var toe_probe: Node3D = _toe_probes.get(side)

	var midpoints := {}
	if hip_probe != null and knee_probe != null:
		midpoints["thigh"] = (hip_probe.global_position + knee_probe.global_position) * 0.5
	if knee_probe != null and foot_probe != null:
		midpoints["shin"] = (knee_probe.global_position + foot_probe.global_position) * 0.5
	if foot_probe != null and toe_probe != null:
		midpoints["foot"] = (foot_probe.global_position + toe_probe.global_position) * 0.5
	if toe_probe != null and leaf_probe != null:
		midpoints["leaf"] = (toe_probe.global_position + leaf_probe.global_position) * 0.5

	for segment: String in ["thigh", "shin", "foot", "leaf"]:
		var label: Label3D = labels.get(segment)
		if label == null:
			continue
		if angles.has(segment) and midpoints.has(segment):
			label.text = "%.1f°" % angles[segment]
			label.global_position = midpoints[segment]
			label.visible = true
		else:
			label.visible = false

## Full-precision console snapshot; _physics_process shows the same numbers live, panel-sized.
func _log_leg_angles() -> void:
	for side: StringName in [&"left", &"right"]:
		var angles := _compute_leg_angles(side)
		var line := "[FootIK] %s world angles:" % side
		for segment: String in ["thigh", "shin", "foot", "leaf"]:
			if angles.has(segment):
				line += " %s=%.1f" % [segment, angles[segment]]
		print(line)
func _build_panel() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# Flashes each loop-reset frame (see foot_ik_leg_solver.gd's solve() doc).
	_loop_reset_flash = Label.new()
	_loop_reset_flash.text = "LOOP RESET"
	_loop_reset_flash.add_theme_font_size_override("font_size", 40)
	_loop_reset_flash.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	_loop_reset_flash.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_loop_reset_flash.position = Vector2(-70, 40)
	_loop_reset_flash.modulate.a = 0.0
	layer.add_child(_loop_reset_flash)

	# Flashes on contact_lost - ground_weight snapping toward 0, the moment
	# the blended target jumps from the held ground point to raw animation.
	_contact_lost_flash = Label.new()
	_contact_lost_flash.text = "CONTACT LOST"
	_contact_lost_flash.add_theme_font_size_override("font_size", 40)
	_contact_lost_flash.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25))
	_contact_lost_flash.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_contact_lost_flash.position = Vector2(-100, 90)
	_contact_lost_flash.modulate.a = 0.0
	layer.add_child(_contact_lost_flash)

	var panel_width := PANEL_CONTENT_WIDTH + PANEL_INNER_PADDING * 2
	var panel := PanelContainer.new()
	panel.add_theme_font_size_override("font_size", 21)
	panel.custom_minimum_size = Vector2(panel_width, 0)
	# Anchored to the top-right corner (not a fixed left-side position) so it
	# stays clear of the close-up foot view this scene starts you in, which
	# sits left-of-center in the default camera framing.
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-(panel_width + PANEL_OUTER_MARGIN), PANEL_OUTER_MARGIN)
	layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", PANEL_INNER_PADDING)
	margin.add_theme_constant_override("margin_right", PANEL_INNER_PADDING)
	margin.add_theme_constant_override("margin_top", PANEL_INNER_PADDING)
	margin.add_theme_constant_override("margin_bottom", PANEL_INNER_PADDING)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Foot IK Debug (this scene only)"
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = ("Mouse starts captured for normal camera look - ` (backtick) frees it to use " +
			"the sliders below.\n" +
			"Open the debug menu (P) for the \"Detached Camera\" toggle if you want to " +
			"look around without rotating the body at all.\n" +
			"Trust the numbers below over the spheres - toggle IK Active off/on and " +
			"compare the printed gap/pitch values directly.\n" +
			"Press L to print each leg's thigh/shin/foot/leaf world-space angles to the console.\n" +
			"Press K for a close-up detached camera on the right foot (not the default view " +
			"anymore now that foot placement itself is solved).")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(hint)

	_active_check = CheckButton.new()
	_active_check.add_theme_font_size_override("font_size", 28)
	_active_check.custom_minimum_size = Vector2(0, 44)
	_active_check.button_pressed = _ik.active
	_active_check.toggled.connect(func(pressed: bool) -> void:
		_ik.set_debug_enabled(pressed)
		_style_active_check(pressed)
		_refresh_paused_ik_pose())
	_style_active_check(_ik.active)
	vbox.add_child(_active_check)

	var backend_row := HBoxContainer.new()
	var backend_label := Label.new()
	backend_label.text = "Solver Backend"
	backend_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	backend_row.add_child(backend_label)
	_backend_option = OptionButton.new()
	_backend_option.add_item("Custom", PlayerFootIKModifier.SolverBackend.CUSTOM)
	_backend_option.add_item(
			"Native TwoBone", PlayerFootIKModifier.SolverBackend.NATIVE_TWO_BONE)
	_backend_option.select(_backend_option.get_item_index(_ik.solver_backend))
	_backend_option.item_selected.connect(func(index: int) -> void:
		_ik.set_solver_backend(_backend_option.get_item_id(index))
		_refresh_paused_ik_pose())
	backend_row.add_child(_backend_option)
	vbox.add_child(backend_row)

	_pause_button = Button.new()
	_pause_button.add_theme_font_size_override("font_size", 24)
	_pause_button.custom_minimum_size = Vector2(0, 44)
	_pause_button.text = "Pause All"
	_pause_button.pressed.connect(_toggle_scene_pause)
	vbox.add_child(_pause_button)

	_keep_playing_check = CheckButton.new()
	_keep_playing_check.text = "Keep Playing (ignore Esc/P menu pause)"
	_keep_playing_check.button_pressed = true ## On by default - this scene is for live testing.
	vbox.add_child(_keep_playing_check)

	_build_animation_timeline(vbox)

	_add_slider(vbox, "ankle_offset", "Ankle Offset", 0.0, 0.3, 0.005)
	_add_slider(vbox, "toe_tip_margin", "Toe Tip Margin", 0.0, 0.1, 0.005)
	_add_slider(vbox, "swing_speed_threshold", "Swing Speed", 0.05, 2.0, 0.05)
	_add_slider(vbox, "rising_penalty", "Rising Penalty", 1.0, 10.0, 0.5)
	_add_slider(vbox, "min_falling_streak", "Falling Streak", 1.0, 10.0, 1.0)
	_add_slider(vbox, "velocity_noise_floor", "Noise Floor", 0.0, 0.15, 0.005)
	_add_slider(vbox, "ground_weight_rise_time", "Weight Rise Time", 0.0, 0.5, 0.01)
	_add_slider(vbox, "ground_weight_fall_time", "Weight Fall Time", 0.0, 0.5, 0.01)
	_add_slider(vbox, "smooth_rate", "Smooth Rate", 1.0, 40.0, 0.5)
	_add_slider(vbox, "ray_up", "Ray Up", 0.1, 1.5, 0.05)
	_add_slider(vbox, "ray_down", "Ray Down", 0.1, 1.5, 0.05)

	vbox.add_child(HSeparator.new())
	_camera_readout = Label.new()
	_camera_readout.text = "..."
	vbox.add_child(_camera_readout)

	vbox.add_child(HSeparator.new())
	_build_readout_grid(vbox)
	_joint_history_graph = JOINT_HISTORY_GRAPH.new() as FootIkJointHistoryGraph
	_joint_history_graph.attach(layer, panel_width, PANEL_OUTER_MARGIN)

	_copy_data_button = Button.new()
	_copy_data_button.text = "Copy IK Data"
	_copy_data_button.custom_minimum_size = Vector2(0, 40)
	_copy_data_button.pressed.connect(_copy_ik_panel_data)
	vbox.add_child(_copy_data_button)

func _toggle_scene_pause() -> void:
	_set_scene_paused(not get_tree().paused)

func _set_scene_paused(paused: bool) -> void:
	if paused == get_tree().paused:
		return
	if paused:
		# PlayerBody intentionally runs its AnimationPlayer in ALWAYS mode for
		# ordinary gameplay overlays. Temporarily make every animation player
		# pausable before freezing the tree so the exact skeleton frame stops.
		_paused_animation_process_modes.clear()
		for node: Node in get_tree().root.find_children("*", "AnimationPlayer", true, false):
			_paused_animation_process_modes[node] = node.process_mode
			node.process_mode = Node.PROCESS_MODE_PAUSABLE
		get_tree().paused = true
	else:
		get_tree().paused = false
		_restore_animation_process_modes()
	_pause_button.text = "Resume All" if get_tree().paused else "Pause All"

func _build_animation_timeline(parent: VBoxContainer) -> void:
	_animation_title = Label.new()
	_animation_title.text = "Animation Timeline (60 FPS)"
	parent.add_child(_animation_title)

	var row := HBoxContainer.new()
	parent.add_child(row)

	_animation_timeline = HSlider.new()
	_animation_timeline.min_value = 0.0
	_animation_timeline.max_value = 1.0
	_animation_timeline.step = 1.0 / ANIMATION_DISPLAY_FPS
	_animation_timeline.custom_minimum_size = Vector2(245, 0)
	_animation_timeline.value_changed.connect(_on_animation_timeline_changed)
	_animation_timeline.drag_started.connect(_on_animation_scrub_started)
	_animation_timeline.drag_ended.connect(_on_animation_scrub_ended)
	row.add_child(_animation_timeline)

	_animation_time_readout = Label.new()
	_animation_time_readout.custom_minimum_size = Vector2(120, 0)
	_animation_time_readout.text = "Frame -  0.000s"
	row.add_child(_animation_time_readout)

func _on_animation_scrub_started() -> void:
	_set_scene_paused(true)

func _on_animation_scrub_ended(_value_changed: bool) -> void:
	# Deliberately remain paused on the selected frame. Resume All continues
	# the full stair sequence from that inspected pose.
	pass

func _on_animation_timeline_changed(position: float) -> void:
	if _timeline_syncing or _player_body == null or _player_body.anim_player == null:
		return
	var animation_player := _player_body.anim_player
	if animation_player.current_animation.is_empty():
		return
	_set_scene_paused(true)
	animation_player.seek(position, true)
	# Seeking a paused AnimationPlayer changes its stored time, but the
	# SkeletonModifier3D stack needs an explicit zero-time evaluation to make
	# that exact pose visible immediately.
	_skel.advance(0.0)
	_update_animation_timeline()

func _refresh_paused_ik_pose() -> void:
	if get_tree().paused and _skel != null:
		# A paused AnimationPlayer doesn't request another skeleton update when
		# only modifier tuning changes - advance(0.0) keeps the frame fixed
		# while rendering the new IK values immediately.
		_skel.advance(0.0)

func _update_animation_timeline() -> void:
	if (_animation_timeline == null or _player_body == null
			or _player_body.anim_player == null):
		return
	var animation_player := _player_body.anim_player
	var animation_name := animation_player.current_animation
	_animation_title.text = "Animation Timeline (60 FPS) - %s" % (
			animation_name if not animation_name.is_empty() else "-")
	if animation_name.is_empty():
		_animation_timeline.editable = false
		_animation_time_readout.text = "No animation"
		return
	var animation := animation_player.get_animation(animation_name)
	if animation == null:
		return
	_animation_timeline.editable = true
	# Guard max_value too - it can clamp value and emit value_changed, which
	# leaked into the scrub handler and paused the whole tree on clip switches.
	_timeline_syncing = true
	_animation_timeline.max_value = maxf(animation.length, 1.0 / ANIMATION_DISPLAY_FPS)
	var position := clampf(animation_player.current_animation_position, 0.0, animation.length)
	_animation_timeline.value = position
	_timeline_syncing = false
	var frame := mini(int(floor(position * ANIMATION_DISPLAY_FPS)),
			maxi(0, int(ceil(animation.length * ANIMATION_DISPLAY_FPS)) - 1))
	_animation_time_readout.text = "Frame %d  %.3fs / %.3fs" % [
			frame, position, animation.length]

func _restore_animation_process_modes() -> void:
	for node: Node in _paused_animation_process_modes:
		if is_instance_valid(node):
			node.process_mode = _paused_animation_process_modes[node]
	_paused_animation_process_modes.clear()

func _exit_tree() -> void:
	# Do not let stopping/reloading this manual harness leave a paused tree
	# behind for whatever scene the editor runs next.
	if _stair_follow_enabled:
		Input.mouse_mode = _follow_previous_mouse_mode
	if get_tree() != null:
		get_tree().paused = false
	_restore_animation_process_modes()
	if _live_penetration_check != null:
		print(_live_penetration_check.format_result())

## A field/left/right grid, not "key=value ..." per foot - the single-line version ran off-screen.
func _build_readout_grid(parent: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)

	grid.add_child(Label.new())
	var left_header := Label.new()
	left_header.text = "Left"
	grid.add_child(left_header)
	var right_header := Label.new()
	right_header.text = "Right"
	grid.add_child(right_header)

	_readout_values = {"left": {}, "right": {}}
	for field: Array in READOUT_FIELDS:
		var key: String = field[0]
		var header: String = field[1]
		var name_label := Label.new()
		name_label.text = header
		grid.add_child(name_label)
		for side: String in ["left", "right"]:
			var value_label := Label.new()
			value_label.text = "-"
			grid.add_child(value_label)
			(_readout_values[side] as Dictionary)[key] = value_label

func _copy_ik_panel_data() -> void:
	var lines: Array[String] = ["Foot IK Debug"]
	lines.append("paused=%s ik_active=%s" % [get_tree().paused, _ik.active])
	lines.append("player_pos=%s" % (_player_body.get_parent() as Node3D).global_position)
	var animation_player := _player_body.anim_player
	if animation_player != null and not animation_player.current_animation.is_empty():
		var position := animation_player.current_animation_position
		var animation := animation_player.get_animation(animation_player.current_animation)
		var frame := int(floor(position * ANIMATION_DISPLAY_FPS))
		lines.append("animation=%s frame=%d time=%.3f length=%.3f" % [
				animation_player.current_animation, frame, position, animation.length])
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var position := camera.global_position
		var rotation := camera.global_rotation_degrees
		lines.append("camera_position=(%.5f, %.5f, %.5f)" % [
				position.x, position.y, position.z])
		lines.append("camera_rotation_degrees=(%.2f, %.2f, %.2f)" % [
				rotation.x, rotation.y, rotation.z])
	lines.append("retracted: left=%s right=%s" % [
			_ik.debug_retracted.get("left", false), _ik.debug_retracted.get("right", false)])
	if _stair_follow_probe != null:
		var target := _stair_follow_probe.global_position
		lines.append("follow_target=(%.5f, %.5f, %.5f)" % [target.x, target.y, target.z])
	if _stair_follow_character != null:
		var root_position := _stair_follow_character.global_position
		lines.append("follow_root=(%.5f, %.5f, %.5f)" % [
				root_position.x, root_position.y, root_position.z])
	lines.append("IK values:")
	for prop: String in _sliders:
		lines.append("  %s=%.5f" % [prop, float((_sliders[prop] as HSlider).value)])
	for side: String in ["left", "right"]:
		lines.append("%s foot:" % side)
		var values: Dictionary = _readout_values[side]
		for field: Array in READOUT_FIELDS:
			var key: String = field[0]
			lines.append("  %s=%s" % [key, (values[key] as Label).text])
	DisplayServer.clipboard_set("\n".join(lines))
	_copy_data_button.text = "Copied IK Data"
	await get_tree().create_timer(1.0, true, false, true).timeout
	if is_instance_valid(_copy_data_button):
		_copy_data_button.text = "Copy IK Data"

## Text/color make "IK Active" readable at a glance - the built-in toggle glyph is easy to miss.
func _style_active_check(active: bool) -> void:
	_active_check.text = "IK ENABLED" if active else "IK DISABLED"
	var color := Color(0.3, 1.0, 0.4) if active else Color(1.0, 0.35, 0.3)
	_active_check.add_theme_color_override("font_color", color)
	_active_check.add_theme_color_override("font_hover_color", color)
	_active_check.add_theme_color_override("font_pressed_color", color)

func set_stair_foot_follow_enabled(enabled: bool) -> void:
	var player := get_node("../Player") as Player
	if player == null:
		return
	if enabled == _stair_follow_enabled:
		if enabled:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if enabled:
		_stair_follow_character = _find_stair_follow_player()
		if _stair_follow_character == null:
			_stair_follow_enabled = false
			return
		if _stair_follow_probe == null:
			_stair_follow_probe = _build_stair_follow_probe()
		if _stair_follow_probe == null:
			_stair_follow_enabled = false
			return
		_follow_was_detached = player.detached_cam_active
		_follow_previous_transform = player.detached_cam.global_transform
		_follow_previous_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		player.set_detached_camera_active(true)
		_follow_last_anchor = _stair_follow_character.global_position
		_follow_has_anchor = true
		player.detached_cam.global_position = \
				_follow_last_anchor + STAIR_FOLLOW_ROOT_OFFSET
		_focus_stair_follow_camera(player)
	else:
		_follow_orbit_dragging = false
		_follow_has_anchor = false
		Input.mouse_mode = _follow_previous_mouse_mode
		if _follow_was_detached:
			player.detached_cam.global_transform = _follow_previous_transform
			player._detached_yaw = player.detached_cam.rotation.y
			player._detached_pitch = player.detached_cam.rotation.x
		else:
			player.set_detached_camera_active(false)
	_stair_follow_enabled = enabled

func is_stair_foot_follow_enabled() -> bool:
	return _stair_follow_enabled

func _build_stair_follow_probe() -> Node3D:
	var candidate := _find_stair_follow_player()
	if candidate == null:
		return null
	for child in candidate.skeleton.get_children():
		if child is PlayerFootIKModifier:
			var foot_idx: int = child._bone_indices[&"right"]["foot"]
			var attach := BoneAttachment3D.new()
			candidate.skeleton.add_child(attach)
			attach.bone_idx = foot_idx
			var probe := Node3D.new()
			attach.add_child(probe)
			return probe
	return null

func _find_stair_follow_player() -> Player:
	return get_node("../Player") as Player

func _process(_delta: float) -> void:
	_update_animation_timeline()
	if not _stair_follow_enabled or _stair_follow_probe == null:
		return
	# Player/debug camera input can recapture the pointer after this overlay's
	# deferred initialization. Foot-follow is an interactive panel/orbit mode,
	# so keep the pointer available for its controls for the whole time it is on.
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var player := get_node("../Player") as Player
	var anchor := _stair_follow_character.global_position
	if _follow_has_anchor:
		# Follow stable character-root translation, not the animated foot itself.
		# The foot remains the look target below, so gait motion changes framing
		# naturally without dragging the camera through every swing arc.
		player.detached_cam.global_position += anchor - _follow_last_anchor
	else:
		player.detached_cam.global_position = anchor + STAIR_FOLLOW_ROOT_OFFSET
		_follow_has_anchor = true
	_follow_last_anchor = anchor
	if get_tree().paused:
		_move_paused_stair_follow_camera(player, _delta)
	_focus_stair_follow_camera(player)

func _focus_stair_follow_camera(player: Player) -> void:
	if _stair_follow_probe == null:
		return
	player.detached_cam.look_at(_stair_follow_probe.global_position + Vector3.UP * 0.04)

func _move_paused_stair_follow_camera(player: Player, delta: float) -> void:
	var input_dir := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var direction := player.detached_cam.global_basis * Vector3(input_dir.x, 0.0, input_dir.y)
	if Input.is_action_pressed(&"jump"):
		direction.y += 1.0
	if Input.is_action_pressed(&"crouch"):
		direction.y -= 1.0
	if direction.is_zero_approx():
		return
	var speed := player.detached_cam_speed
	if Input.is_action_pressed(&"sprint"):
		speed *= player.detached_cam_sprint_multiplier
	player.detached_cam.global_position += direction.normalized() * speed * delta

func _zoom_stair_follow(factor: float) -> void:
	if _stair_follow_probe == null:
		return
	var player := get_node("../Player") as Player
	var target := _stair_follow_probe.global_position + Vector3.UP * 0.04
	var offset := player.detached_cam.global_position - target
	var distance := clampf(
			offset.length() * factor, STAIR_FOLLOW_MIN_DISTANCE, STAIR_FOLLOW_MAX_DISTANCE)
	player.detached_cam.global_position = target + offset.normalized() * distance

func _orbit_stair_follow(relative: Vector2) -> void:
	if _stair_follow_probe == null:
		return
	var player := get_node("../Player") as Player
	var target := _stair_follow_probe.global_position + Vector3.UP * 0.04
	var camera := player.detached_cam
	var offset := camera.global_position - target
	var yaw := -relative.x * STAIR_FOLLOW_ORBIT_SENSITIVITY
	var yaw_rotation := Basis(Vector3.UP, yaw)
	offset = yaw_rotation * offset
	var right := offset.cross(Vector3.UP).normalized()
	if not right.is_zero_approx():
		var pitch := -relative.y * STAIR_FOLLOW_ORBIT_SENSITIVITY
		var proposed := offset.rotated(right, pitch)
		var vertical_ratio := absf(proposed.normalized().dot(Vector3.UP))
		if vertical_ratio < 0.98:
			offset = proposed
	camera.global_position = target + offset
	_focus_stair_follow_camera(player)

func _add_slider(
		parent: VBoxContainer, prop: String, label_text: String,
		min_value: float, max_value: float, step: float) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)

	var name_label := Label.new()
	name_label.text = label_text
	name_label.custom_minimum_size = Vector2(90, 0)
	row.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = _ik.get(prop)
	slider.custom_minimum_size = Vector2(140, 0)
	row.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(50, 0)
	row.add_child(value_label)

	slider.value_changed.connect(func(value: float) -> void:
		_ik.set(prop, value)
		value_label.text = "%.3f" % value
		_refresh_paused_ik_pose())
	value_label.text = "%.3f" % slider.value

	_sliders[prop] = slider
	_slider_labels[prop] = value_label

func _physics_process(delta: float) -> void:
	if _ik == null:
		return
	if get_tree().paused and _keep_playing_check.button_pressed:
		get_tree().paused = false ## Lets player.gd keep ticking while Esc/P's menu is still open.
	elif get_tree().paused:
		_refresh_paused_ik_pose() ## ui/hud.gd's P menu bypasses _set_scene_paused().
	# The checkbox only used to reflect the click that set it, not
	# set_character_grounded()'s own automatic on/off (airborne, landing) -
	# read as permanently "IK DISABLED" from a one-frame spawn-height dip
	# even after it self-corrected. Keep it honest every frame instead.
	if _active_check.button_pressed != _ik.active:
		_active_check.set_pressed_no_signal(_ik.active)
		_style_active_check(_ik.active)
	if _ik._animation_discontinuous:
		_loop_reset_flash.modulate.a = 1.0
	elif _loop_reset_flash.modulate.a > 0.0:
		var fade := delta / LOOP_RESET_FLASH_DURATION
		_loop_reset_flash.modulate.a = maxf(0.0, _loop_reset_flash.modulate.a - fade)
	if _ik.debug_contact_lost.get(&"left", false) or _ik.debug_contact_lost.get(&"right", false):
		_contact_lost_flash.modulate.a = 1.0
	elif _contact_lost_flash.modulate.a > 0.0:
		var lost_fade := delta / LOOP_RESET_FLASH_DURATION
		_contact_lost_flash.modulate.a = maxf(0.0, _contact_lost_flash.modulate.a - lost_fade)
	# Surface-to-surface ray distance (sole vs ground), from the controlled
	# character's own modifier, not the 0.35m walker's preview rays.
	# Whichever camera is actually rendering right now, not assuming it's
	# still the detached one this scene starts you in.
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var rot_deg := cam.global_rotation_degrees
		_camera_readout.text = (
				("camera pos=(%.2f, %.2f, %.2f) rot(deg)=(%.1f, %.1f, %.1f) [%s]"
				+ "\nplayer_pos=%s ik_active=%s retracted: left=%s right=%s")
				% [cam.global_position.x, cam.global_position.y, cam.global_position.z,
					rot_deg.x, rot_deg.y, rot_deg.z, cam.name,
					(_player_body.get_parent() as Node3D).global_position, _ik.active,
					_ik.debug_retracted.get("left", false), _ik.debug_retracted.get("right", false)])

	for side: String in ["left", "right"]:
		var values: Dictionary = _readout_values[side]
		var probe: Node3D = _probes[side]
		var actual_pos := probe.global_position
		var actual_basis := probe.global_transform.basis
		var sole_down_local: Vector3 = _ik._sole_down_local[side]
		var actual_sole_down := actual_basis * sole_down_local
		var pitch_deg := rad_to_deg(actual_sole_down.angle_to(Vector3.DOWN))

		var has_target: bool = _ik._smoothed_target.has(side)
		var target: Vector3 = _ik._smoothed_target.get(side, actual_pos)
		var normal: Vector3 = _ik._smoothed_normal.get(side, Vector3.UP)
		var ankle_target: Vector3 = target + normal * _ik.ankle_offset
		var gap := actual_pos.y - ankle_target.y

		(_markers[side + "_hit"] as MeshInstance3D).global_position = target
		(_markers[side + "_target"] as MeshInstance3D).global_position = ankle_target
		(_markers[side + "_actual"] as MeshInstance3D).global_position = actual_pos

		(values["hit"] as Label).text = str(has_target)
		(values["target_y"] as Label).text = "%.3f" % ankle_target.y
		(values["actual_y"] as Label).text = "%.3f" % actual_pos.y
		(values["gap"] as Label).text = "%.3f" % gap
		var contact_hit: bool = bool(_ik.debug_contact_hit.get(side, false))
		var contact_distance: float = float(_ik.debug_contact_distance.get(side, -1.0))
		var lower_distance: float = contact_distance if contact_hit else -1.0
		(values["lower_distance"] as Label).text = (
				"%.3f" % lower_distance if lower_distance >= 0.0 else "-")
		var ray_length := contact_distance if contact_hit else _ik.idle_settle_search_down
		FootIkDebugMarkers.update_ray_visual(_markers[side + "_ray"] as MeshInstance3D,
				actual_pos, actual_pos + Vector3.DOWN * ray_length, contact_hit)
		(values["pitch"] as Label).text = "%.1f" % pitch_deg
		var w: float = float(_ik._smoothed_ground_weight.get(side, 0.0))
		(values["ground_weight"] as Label).text = "%.3f" % w
		(values["is_floating"] as Label).text = str(w < 0.5)
		(values["step_down"] as Label).text = str(bool(_ik.debug_step_down.get(side, false)))
		(values["raw_weight"] as Label).text = "%.3f" % float(_ik.debug_raw_weight.get(side, 0.0))
		(values["contact_lost"] as Label).text = str(bool(_ik.debug_contact_lost.get(side, false)))
		(values["stuck_time"] as Label).text = "%.2f" % float(_ik._weight_stuck_time.get(side, 0.0))
		(values["vertical_velocity"] as Label).text = "%.3f" % float(
				_ik.debug_vertical_velocity.get(side, 0.0))

		if _toe_probes.has(side):
			var toe_probe: Node3D = _toe_probes[side]
			var toe_joint_pos := toe_probe.global_position
			var foot_to_toe := toe_joint_pos - actual_pos
			var tip_pos := toe_joint_pos + foot_to_toe.normalized() * TOE_TIP_EXTRA_LENGTH \
					if not foot_to_toe.is_zero_approx() else toe_joint_pos
			(_markers[side + "_toe"] as MeshInstance3D).global_position = tip_pos
			var toe_gap := tip_pos.y - target.y
			(values["toe_tip_y"] as Label).text = "%.3f" % tip_pos.y
			(values["toe_tip_gap"] as Label).text = "%.3f" % toe_gap

		var angles := _compute_leg_angles(side)
		_joint_history_graph.sample_side(side, angles, _angle_probes[side], probe,
				_player_body.get_parent() as Node3D)
		for segment: String in ["thigh", "shin", "foot", "leaf"]:
			if angles.has(segment):
					(values[segment + "_angle"] as Label).text = "%.1f" % angles[segment]
		_update_angle_labels(side, angles)
	_capture_controlled_foot_frame()
func _capture_controlled_foot_frame() -> void:
	if _ik == null or _player_body == null:
		return
	var animation_player := _player_body.anim_player
	var trace := {
		"frame": Engine.get_physics_frames(),
		"root": _player_body.global_position,
		"head_world_y": (_player_body.get_parent() as Player).head.global_position.y,
		"root_yaw_deg": rad_to_deg((_player_body.get_parent() as Node3D).rotation.y),
		"animation": animation_player.current_animation if animation_player != null else "",
		"time": animation_player.current_animation_position if animation_player != null else 0.0,
		"disc": _ik._animation_discontinuous,
		"active": _ik.active,
		"on_floor": _player_body.get_parent().is_on_floor(),
		"feet": {},
	}
	if _live_penetration_check != null:
		trace["penetration"] = _live_penetration_check.sample(
				get_node("../Player") as Player, _ik)
	for side: String in ["left", "right"]:
		var probe: Node3D = _probes[side]
		var actual_pos := probe.global_position
		var target: Vector3 = _ik._smoothed_target.get(side, actual_pos)
		var sole_down: Vector3 = probe.global_transform.basis * _ik._sole_down_local[side]
		var sole_depth := float(_ik._sole_depth_below_foot.get(side, _ik.ankle_offset))
		var sole: Vector3 = actual_pos + sole_down * sole_depth
		var toe_probe: Node3D = _toe_probes.get(side)
		var hip_probe: Node3D = (_angle_probes.get(side, {}) as Dictionary).get("hip")
		var normal: Vector3 = _ik._smoothed_normal.get(side, Vector3.UP)
		trace["feet"][side] = {
			"gap": actual_pos.y - target.y - sole_depth,
			"sole_clearance": sole.y - target.y,
			"pitch_deg": rad_to_deg(sole.normalized().angle_to(Vector3.DOWN)),
			"ground_weight": float(_ik._smoothed_ground_weight.get(side, 0.0)),
			"vertical_velocity": float(_ik.debug_vertical_velocity.get(side, 0.0)),
			"contact_hit": bool(_ik.debug_contact_hit.get(side, false)),
			"contact_distance": float(_ik.debug_contact_distance.get(side, -1.0)),
			"contact_lost": bool(_ik.debug_contact_lost.get(side, false)),
			"frozen": bool(_ik._idle_frozen.get(side, false)),
			"freeze_streak": int(_ik._idle_freeze_streak.get(side, 0)),
			"step_down": bool(_ik.debug_step_down.get(side, false)),
			"toe_tip_y": toe_probe.global_position.y if toe_probe != null else 0.0,
			"foot_pos": actual_pos,
			"hip_pos": hip_probe.global_position if hip_probe != null else Vector3.ZERO,
			"smoothed_target": target,
			# Absolute angle of the ground normal from world up - 0 on flat
			# floor, ~45 on the Ramp 45 platform - not a per-joint bend.
			"floor_angle_deg": rad_to_deg(normal.angle_to(Vector3.UP)),
			"leg_angles_deg": _compute_leg_angles(side),
			"joints": _capture_joint_transforms(side),
		}
	# Rolling window, not an ever-growing append: always holds the moment a
	# live shake just happened without a whole play session in the file.
	_controlled_trace_buffer.append(JSON.stringify(trace))
	if _controlled_trace_buffer.size() > CONTROLLED_TRACE_MAX_FRAMES:
		_controlled_trace_buffer.pop_front()
	var file := FileAccess.open(CONTROLLED_TRACE_FILE, FileAccess.WRITE)
	for line: String in _controlled_trace_buffer:
		file.store_line(line)
	file.close()
