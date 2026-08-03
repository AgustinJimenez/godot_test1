extends Node3D
## Live foot-IK debug tool for foot_ik_preview.tscn only - finds the real,
## player-controlled PlayerFootIKModifier (not the static test dummies) and
## exposes it two ways at once, since neither alone was enough to diagnose
## why the static-preview renders kept looking right while real gameplay
## didn't:
##   1. In-world gizmo spheres (green = raw raycast hit, blue = IK target
##      i.e. hit + ankle offset, red = actual foot bone position, yellow =
##      actual toe/ball bone position - all tracked via BoneAttachment3D
##      since Skeleton3D.get_bone_global_pose() does not reflect modifier
##      results when read from outside the modifier stack) for both feet,
##      updated every physics frame so they follow the player while walking.
##   2. An on-screen panel: toggle IK on/off and live-tune ankle
##      offset/smooth rate/ray up/ray down against real movement, plus a
##      numeric per-foot readout (hit, target Y, actual Y, gap, sole pitch,
##      toe Y, toe gap) - this is the reliable source of truth; screenshots
##      of the spheres are easy to misjudge, the printed numbers aren't.
## The detached spectator camera used to live here too - moved to
## Player.set_detached_camera_active()/the debug menu's "Detached Camera"
## toggle instead, since that's useful in every scene, not just this one.

const MARKER_RADIUS := 0.015
## The toe/ball bone's own origin sits at the base of the toes, not the
## visual tip of the foot mesh - extending a bit further past it along the
## same foot-to-toe direction approximates where the actual toe tip is, so
## the yellow marker reflects what you'd see poking up, not just the joint.
const TOE_TIP_EXTRA_LENGTH := 0.035

## Gap between the screen edge and the panel's own border.
const PANEL_OUTER_MARGIN := 20
## Gap between the panel's border and its contents (title/sliders/grid) -
## without this, wide rows (like the "IK Active" checkbox, whose toggle
## glyph sits at the row's far right) could render flush against the panel
## edge and get clipped by the viewport border beyond it.
const PANEL_INNER_PADDING := 14
## The content area's own width, independent of padding - the panel's own
## custom_minimum_size adds PANEL_INNER_PADDING on both sides on top of this
## so growing the padding doesn't silently shrink the sliders/grid.
const PANEL_CONTENT_WIDTH := 460
const STAIR_FOLLOW_HEIGHT := 0.35
const ANIMATION_DISPLAY_FPS := 60.0
## User-calibrated camera position relative to the 0.35m walker's stable root
## at the bottom spawn (15.0, 0.05, -0.8). The root carries the camera through
## stair movement; the animated foot controls only where the camera looks.
const STAIR_FOLLOW_ROOT_OFFSET := Vector3(-0.7034, 0.0967, -0.2845)
const STAIR_FOLLOW_ORBIT_SENSITIVITY := 0.006
const STAIR_FOLLOW_MIN_DISTANCE := 0.08
const STAIR_FOLLOW_MAX_DISTANCE := 4.0

var _player_body: PlayerBody
var _ik: PlayerFootIKModifier
var _skel: Skeleton3D
var _probes: Dictionary = {} # side -> Node3D (BoneAttachment3D child), foot bone
var _toe_probes: Dictionary = {} # side -> Node3D (BoneAttachment3D child), toe bone, or null
var _markers: Dictionary = {} # "side_kind" -> MeshInstance3D, kind in hit/target/actual/toe
## side -> {hip, knee, leaf: Node3D or null} - only used by _log_leg_angles(),
## kept separate from _probes/_toe_probes above since those two are read
## every physics frame for the on-screen readout and this one isn't.
var _angle_probes: Dictionary = {}
## side -> {segment: Label3D}, one floating label per segment (thigh/shin/
## foot/leaf), positioned at that segment's midpoint each physics frame -
## puts the same numbers the readout grid shows directly on the bone they
## describe, instead of only off in the corner panel.
var _angle_labels: Dictionary = {}

## Ordered [key, column_header] pairs for the per-foot readout grid (see
## _build_panel()/_physics_process()) - an Array, not a Dictionary, since the
## display order matters and needs to stay fixed.
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
	["vertical_velocity", "Anim VY"],
	["thigh_angle", "Thigh°"],
	["shin_angle", "Shin°"],
	["foot_angle", "Foot°"],
	["leaf_angle", "Leaf°"],
]

var _active_check: CheckButton
var _pause_button: Button
var _paused_animation_process_modes: Dictionary = {}
var _animation_timeline: HSlider
var _animation_time_readout: Label
var _copy_data_button: Button
var _timeline_syncing := false
var _camera_readout: Label
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
	call_deferred(&"set_stair_foot_follow_enabled", true)
	# Captured before any physics settling/movement, so it always reflects
	# foot_ik_preview.tscn's own authored Player transform regardless of
	# when in the scene's lifetime the close-up camera actually gets used.
	_player_spawn_position = (get_node("../Player") as Node3D).global_position

	await get_tree().process_frame
	await get_tree().process_frame
	var followed_player := _find_stair_follow_player()
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
		_markers[str(side) + "_hit"] = _spawn_marker(Color.GREEN)
		_markers[str(side) + "_target"] = _spawn_marker(Color.BLUE)
		_markers[str(side) + "_actual"] = _spawn_marker(Color.RED)

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
			_markers[str(side) + "_toe"] = _spawn_marker(Color.YELLOW)

		_angle_probes[side] = {
			"hip": _make_probe(indices["hip"]),
			"knee": _make_probe(indices["knee"]),
			"leaf": _make_probe(indices.get("leaf", -1)) if indices.get("leaf", -1) >= 0 else null,
		}

		_angle_labels[side] = {}
		for segment: String in ["thigh", "shin", "foot", "leaf"]:
			(_angle_labels[side] as Dictionary)[segment] = _spawn_angle_label()

	_build_panel()

	# Default-on for this scene only, same reasoning as the detached camera
	# default below - the whole point of foot_ik_preview.tscn is inspecting
	# joint placement, so the skeleton overlay should already be visible
	# without an extra menu trip every time the scene reloads.
	_player_body.set_skeleton_visible(true)

	# player.gd only rotates the camera from mouse motion while the mouse is
	# captured (see actors/player/player.gd's _unhandled_input). Left
	# captured (player.gd's own default) on load, matching every other scene
	# in the project, so the camera actually responds to the mouse the
	# moment you spawn instead of the pointer just sitting there doing
	# nothing - an earlier version freed the mouse by default specifically
	# so slider drags wouldn't double as camera-look drags, but that traded
	# "sliders need one keypress first" for "camera looks broken on spawn,"
	# a worse default for a scene most people open just to look around.
	# Backtick still frees the mouse on demand for the sliders.
	# Deliberately NOT Tab: this scene's Player is a real, fully-wired player
	# instance, and Tab is already bound project-wide to the "inventory"
	# action (see project.godot) - player.gd's own _unhandled_input handles
	# that action too and would open/pause the inventory overlay on the same
	# keypress, fighting this toggle instead of complementing it.


## DetachedCam is a child of Player (see player.tscn) - positioning it
## before the player has finished falling/settling onto the floor from its
## spawn height means the settle-fall that happens over the next several
## physics frames drags the camera down by the same amount afterward (found
## by comparing the readout label against the intended camera offset - Y was
## off by almost exactly the player's own fall distance). Poll is_on_floor()
## instead of a fixed wait, since exactly how long the fall takes isn't
## fixed - only settle-then-position gives a Y that actually matches.
func _wait_for_player_to_settle() -> void:
	var player := get_node("../Player") as Player
	if player == null:
		return
	for i in 120: # ~2s at 60Hz - generous, but bail out rather than hang forever
		if player.is_on_floor():
			return
		await get_tree().physics_frame


## A specific close-up-on-the-right-foot framing, read off the camera
## readout label after manually flying to a good spot - stored as an offset
## from the player's own authored spawn transform (captured once in _ready()
## as _player_spawn_position), not an absolute world position, so moving
## Player's start position in foot_ik_preview.tscn (e.g. to stand near the
## walking dummies) doesn't silently leave this framing pointed at empty
## space - it was an absolute world position originally, and that's exactly
## what happened the first time the spawn point moved.
const DEFAULT_CAMERA_OFFSET := Vector3(0.57, -0.85, 0.45)
const DEFAULT_CAMERA_ROTATION_DEG := Vector3(-27.8, 37.9, 0.0)
var _player_spawn_position: Vector3


## Not default-on anymore - now that foot placement itself is solved, the
## close-up-on-the-foot framing this scene forced on load stopped being the
## most useful starting view (e.g. it's cropped wrong for the walking
## dummies added later). Kept available on demand instead (see the K
## keybind in _unhandled_input()) rather than deleted outright, since it's
## still the fastest way to get a tight, reproducible framing on the real
## player's own foot for close numeric/visual inspection.
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
	# set_detached_camera_active() already synced these from the camera it
	# copied from (the player's own first-person view) - re-sync from our
	# override instead, or the first mouse-look frame would snap the camera
	# straight back to that original orientation.
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


## Settles first in case this is pressed very soon after the scene loads
## (see _wait_for_player_to_settle's own doc comment for why positioning the
## camera before the player has finished its spawn-height fall would throw
## the framing off) - awaited internally here since _unhandled_input can't
## await inline; a fire-and-forget call is fine since nothing needs to run
## after it completes.
func _activate_closeup_camera() -> void:
	await _wait_for_player_to_settle()
	_start_detached_camera_on_foot()


## BoneAttachment3D + a plain Node3D child, same probe pattern _ready() uses
## for the foot/toe bones above - the only reliable way to read a bone's
## actual post-modifier pose from outside the modifier stack (see this
## script's own top-of-file doc comment).
func _make_probe(bone_idx: int) -> Node3D:
	var attach := BoneAttachment3D.new()
	_skel.add_child(attach)
	attach.bone_idx = bone_idx
	var probe := Node3D.new()
	attach.add_child(probe)
	return probe


## Each segment's OWN absolute angle from world Vector3.DOWN (0 = pointing
## straight down, 90 = horizontal, 180 = pointing straight up) - not the bend
## relative to the previous segment. A relative/bend angle stays constant
## across totally different poses whenever a chain segment (e.g. toe->leaf)
## is rigidly rebuilt from a fixed rest-pose offset relative to its parent's
## corrected basis - it only measures the rig's own fixed rest geometry, not
## anything the current correction is doing (confirmed by comparing two very
## different IK states: knee/ankle bend swung widely, but the bend-relative
## toe angle stayed pinned at exactly the same value both times). An absolute
## world angle actually reflects the live, corrected pose instead. Shared by
## the on-screen readout (every physics frame) and the console dump below
## (on demand).
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


## Moves each segment's floating Label3D (see _angle_labels/_spawn_angle_label)
## to that segment's own midpoint and refreshes its text - puts the exact
## same numbers the readout grid shows directly on the bone in the 3D view,
## so a kink is readable at a glance instead of requiring a panel lookup.
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


## Prints each leg's segment angles (world-space, from Vector3.DOWN) to the
## console, for a full-precision snapshot on demand - the on-screen readout
## (see _physics_process) shows the same numbers live, but at a size/
## precision tuned for the panel.
func _log_leg_angles() -> void:
	for side: StringName in [&"left", &"right"]:
		var angles := _compute_leg_angles(side)
		var line := "[FootIK] %s world angles:" % side
		for segment: String in ["thigh", "shin", "foot", "leaf"]:
			if angles.has(segment):
				line += " %s=%.1f" % [segment, angles[segment]]
		print(line)


func _spawn_marker(color: Color) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := SphereMesh.new()
	mesh.radius = MARKER_RADIUS
	mesh.height = MARKER_RADIUS * 2.0
	mesh.material = mat
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	add_child(inst)
	return inst


## Floating world-space text for one segment's angle - billboarded (always
## faces the camera) and depth-test disabled like the skeleton ribbons
## themselves, so the number stays readable through the mesh instead of
## disappearing behind it whenever the camera orbits to the far side.
func _spawn_angle_label() -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 28
	label.outline_size = 10
	# Label3D's default pixel_size (0.01) sizes text for room-scale scenes -
	# at this character's ~2m scale, font_size 28 would render nearly 0.3m
	# tall (bigger than the whole foot). Scaled down to a legible few
	# centimeters instead.
	label.pixel_size = 0.0007
	label.modulate = Color.WHITE
	label.text = "-"
	add_child(label)
	return label


func _build_panel() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

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
		_ik.active = pressed
		_style_active_check(pressed)
		_refresh_paused_ik_pose())
	_style_active_check(_ik.active)
	vbox.add_child(_active_check)

	_pause_button = Button.new()
	_pause_button.add_theme_font_size_override("font_size", 24)
	_pause_button.custom_minimum_size = Vector2(0, 44)
	_pause_button.text = "Pause All"
	_pause_button.pressed.connect(_toggle_scene_pause)
	vbox.add_child(_pause_button)

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
	var title := Label.new()
	title.text = "Animation Timeline (60 FPS)"
	parent.add_child(title)

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
		# A paused AnimationPlayer does not request another skeleton update when
		# only modifier tuning data changes. Evaluate with zero elapsed time so
		# the selected animation frame stays fixed while the new IK values are
		# rendered immediately.
		_skel.advance(0.0)


func _update_animation_timeline() -> void:
	if (_animation_timeline == null or _player_body == null
			or _player_body.anim_player == null):
		return
	var animation_player := _player_body.anim_player
	var animation_name := animation_player.current_animation
	if animation_name.is_empty():
		_animation_timeline.editable = false
		_animation_time_readout.text = "No animation"
		return
	var animation := animation_player.get_animation(animation_name)
	if animation == null:
		return
	_animation_timeline.editable = true
	_animation_timeline.max_value = maxf(animation.length, 1.0 / ANIMATION_DISPLAY_FPS)
	var position := clampf(animation_player.current_animation_position, 0.0, animation.length)
	_timeline_syncing = true
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


## A field/left/right grid instead of one long "key=value key=value ..."
## line per foot - once the leg-angle fields were added the single-line
## version ran well past the panel width and off the edge of the screen.
## Padding (h/v separation) keeps columns from crowding together now that
## values sit in their own cells instead of being visually separated by
## the "key=" text.
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


## Text and font color make the "IK Active" state readable at a glance
## instead of relying on the small built-in toggle glyph, which is easy to
## miss (and, per one headless-capture investigation this session, doesn't
## even render in movie-maker mode at all).
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
	for node: Node in get_tree().get_nodes_in_group(&"foot_ik_stair_walkers"):
		var candidate := node as Player
		if candidate != null and is_equal_approx(
				float(candidate.get_meta(&"stair_height", -1.0)), STAIR_FOLLOW_HEIGHT):
			return candidate
	return null


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


func _physics_process(_delta: float) -> void:
	if _ik == null:
		return
	# The preview harness casts this ray from its estimate of the rendered
	# sole's lowest point to the first collider below it. Show that direct
	# surface-to-surface measurement separately from `Gap`, which compares
	# the ankle bone against the IK ankle target and is therefore offset by
	# ankle_offset.
	var contact_debug_state: Dictionary = {}
	var preview_contact_state: Variant = get_parent().get("_contact_debug_state")
	if preview_contact_state is Dictionary:
		contact_debug_state = preview_contact_state
	# Whichever camera the viewport is actually rendering through right now -
	# detached, first-person, or third-person - rather than assuming it's
	# still the detached one this scene starts you in, since the debug menu
	# or `/V can switch it at any time.
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var rot_deg := cam.global_rotation_degrees
		_camera_readout.text = "camera pos=(%.2f, %.2f, %.2f) rot(deg)=(%.1f, %.1f, %.1f) [%s]" % [
			cam.global_position.x, cam.global_position.y, cam.global_position.z,
			rot_deg.x, rot_deg.y, rot_deg.z, cam.name]

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
		var contact: Dictionary = contact_debug_state.get(side, {})
		var lower_distance: float = float(contact.get("distance", -1.0))
		(values["lower_distance"] as Label).text = (
				"%.3f" % lower_distance if lower_distance >= 0.0 else "-")
		(values["pitch"] as Label).text = "%.1f" % pitch_deg
		(values["ground_weight"] as Label).text = "%.3f" % float(
				_ik._smoothed_ground_weight.get(side, 0.0))
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
		for segment: String in ["thigh", "shin", "foot", "leaf"]:
			if angles.has(segment):
				(values[segment + "_angle"] as Label).text = "%.1f" % angles[segment]
		_update_angle_labels(side, angles)
