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
const PANEL_CONTENT_WIDTH := 380

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
	["pitch", "Pitch°"],
	["toe_tip_y", "Toe Tip Y"],
	["toe_tip_gap", "Toe Gap"],
	["thigh_angle", "Thigh°"],
	["shin_angle", "Shin°"],
	["foot_angle", "Foot°"],
	["leaf_angle", "Leaf°"],
]

var _active_check: CheckButton
var _camera_readout: Label
var _readout_values: Dictionary = {} # side -> {field_key: Label}
var _sliders: Dictionary = {} # property name -> HSlider
var _slider_labels: Dictionary = {} # property name -> Label


func _ready() -> void:
	# Captured before any physics settling/movement, so it always reflects
	# foot_ik_preview.tscn's own authored Player transform regardless of
	# when in the scene's lifetime the close-up camera actually gets used.
	_player_spawn_position = (get_node("../Player") as Node3D).global_position

	await get_tree().process_frame
	await get_tree().process_frame
	_player_body = get_node("../Player/Body") as PlayerBody
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
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_QUOTELEFT:
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
		_style_active_check(pressed))
	_style_active_check(_ik.active)
	vbox.add_child(_active_check)

	_add_slider(vbox, "ankle_offset", "Ankle Offset", 0.0, 0.3, 0.005)
	_add_slider(vbox, "toe_tip_margin", "Toe Tip Margin", 0.0, 0.1, 0.005)
	_add_slider(vbox, "swing_speed_threshold", "Swing Speed", 0.05, 2.0, 0.05)
	_add_slider(vbox, "rising_penalty", "Rising Penalty", 1.0, 10.0, 0.5)
	_add_slider(vbox, "ground_weight_rise_time", "Weight Rise Time", 0.0, 0.5, 0.01)
	_add_slider(vbox, "smooth_rate", "Smooth Rate", 1.0, 40.0, 0.5)
	_add_slider(vbox, "ray_up", "Ray Up", 0.1, 1.5, 0.05)
	_add_slider(vbox, "ray_down", "Ray Down", 0.1, 1.5, 0.05)

	vbox.add_child(HSeparator.new())
	_camera_readout = Label.new()
	_camera_readout.text = "..."
	vbox.add_child(_camera_readout)

	vbox.add_child(HSeparator.new())
	_build_readout_grid(vbox)


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
		value_label.text = "%.3f" % value)
	value_label.text = "%.3f" % slider.value

	_sliders[prop] = slider
	_slider_labels[prop] = value_label


func _physics_process(_delta: float) -> void:
	if _ik == null:
		return
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
		(values["pitch"] as Label).text = "%.1f" % pitch_deg

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
