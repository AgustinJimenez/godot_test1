extends Node3D
## Playable lab for the DG_GAME_SAMPLE locomotion port.
##
## Builds a small course (flat ground, a 20 deg ramp, stairs, a low tunnel for
## crouch and a few pillars for turn-in-place), spawns the ported body and a
## third-person camera, and shows the live locomotion state.
##
## Controls: WASD move, Shift sprint, Ctrl crouch, Space jump, mouse look,
## Escape releases the cursor. F3 toggles the HUD.

const BODY_SCRIPT := preload(
	"res://tests/manual/dg_game_sample_locomotion/dg_game_sample_locomotion_body.gd"
)
const VISUAL_SCRIPT := preload(
	"res://tests/manual/dg_game_sample_locomotion/dg_game_sample_locomotion_visual.gd"
)
const PLAYER_VISUAL_SCRIPT := preload(
	"res://tests/manual/dg_game_sample_locomotion/dg_player_visual.gd"
)
## Use the player's own mesh, skeleton and clips instead of the Y Bot fallback.
const USE_PLAYER_MODEL := true
const TUNING_SCRIPT := preload(
	"res://tests/manual/dg_game_sample_locomotion/dg_game_sample_locomotion_tuning.gd"
)

const GROUND_COLOR := Color(0.24, 0.27, 0.24)
const PROP_COLOR := Color(0.33, 0.30, 0.27)
const RAMP_COLOR := Color(0.30, 0.34, 0.40)

var body: DGGameSampleLocomotionBody
var visual: DGGameSampleLocomotionVisual
var player_visual: Node3D
var camera_pivot: Node3D
var spring_arm: SpringArm3D
var hud: Label

var _camera_yaw := 0.0
var _camera_pitch := -0.18
var _hud_visible := true
## `-- --demo-walk` drives forward input without a keyboard, for movie renders.
var _demo_walk := false


func _ready() -> void:
	_demo_walk = OS.get_cmdline_user_args().has("--demo-walk")
	_build_environment()
	_build_player()
	_build_camera()
	_build_hud()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(_delta: float) -> void:
	if body == null:
		return
	camera_pivot.global_position = body.global_position + Vector3(0.0, 1.55, 0.0)
	camera_pivot.rotation.y = _camera_yaw
	camera_pivot.rotation.x = _camera_pitch
	if _hud_visible:
		hud.text = _hud_text()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_camera_yaw = wrapf(_camera_yaw - motion.relative.x * 0.0025, -PI, PI)
		_camera_pitch = clampf(_camera_pitch - motion.relative.y * 0.0022, -1.15, 0.55)
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE:
			_toggle_mouse()
		elif key.keycode == KEY_F3:
			_hud_visible = not _hud_visible
			hud.visible = _hud_visible


func _physics_process(_delta: float) -> void:
	if body == null:
		return
	var input := Vector2(
		Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
		Input.get_action_strength(&"move_forward") - Input.get_action_strength(&"move_back")
	)
	if _demo_walk:
		input = Vector2(0.0, 1.0)
	input = input.limit_length(1.0)
	var yaw_basis := Basis(Vector3.UP, _camera_yaw)
	var direction := yaw_basis * Vector3(input.x, 0.0, -input.y)
	body.set_move_input(direction, input.length())
	body.set_sprint(Input.is_action_pressed(&"sprint"))
	body.set_crouch(Input.is_action_pressed(&"crouch"))
	if Input.is_action_just_pressed(&"jump"):
		body.request_jump()
	if player_visual != null:
		player_visual.sync(_delta)
	elif visual != null:
		visual.sync(_delta)


# -------------------------------------------------------------------- hud --

func _hud_text() -> String:
	var state := body.get_state_name()
	var speed := body.get_planar_speed()
	var heading := rad_to_deg(body.facing_yaw)
	return "\n".join([
		"DG_GAME_SAMPLE locomotion port - recovered UBendCharacterMovementComponent model",
		"",
		"state        %s" % state,
		"speed        %5.2f m/s   (ratio %.2f)" % [speed, body.get_speed_ratio()],
		"heading      %6.1f deg" % heading,
		"capsule      %4.2f m" % body.get_capsule_height(),
		"grounded     %s" % ("yes" if body.is_on_floor() else "no"),
		"",
		"WASD move | Shift sprint | Ctrl crouch | Space jump | F3 hud | Esc cursor",
	])


func _toggle_mouse() -> void:
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# ----------------------------------------------------------------- builder --

func _build_player() -> void:
	body = BODY_SCRIPT.new()
	body.name = "LocomotionBody"
	body.tuning = TUNING_SCRIPT.new()
	body.position = Vector3(0.0, 0.1, 2.0)
	add_child(body)
	body.set_placeholder_visible(false)
	if USE_PLAYER_MODEL:
		var model_visual := PLAYER_VISUAL_SCRIPT.new()
		model_visual.name = "LocomotionVisual"
		model_visual.body = body
		body.add_child(model_visual)
		visual = null
		player_visual = model_visual
	else:
		visual = VISUAL_SCRIPT.new()
		visual.name = "LocomotionVisual"
		visual.body = body
		body.add_child(visual)


func _build_camera() -> void:
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	add_child(camera_pivot)
	spring_arm = SpringArm3D.new()
	spring_arm.name = "SpringArm"
	spring_arm.spring_length = 4.4
	spring_arm.margin = 0.2
	spring_arm.collision_mask = 1
	camera_pivot.add_child(spring_arm)
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.current = true
	camera.fov = 72.0
	spring_arm.add_child(camera)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HudLayer"
	add_child(layer)
	var canvas_root := Control.new()
	canvas_root.name = "HudRoot"
	canvas_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(canvas_root)
	hud = Label.new()
	hud.name = "StateLabel"
	hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	hud.offset_left = 24.0
	hud.offset_top = 18.0
	hud.offset_right = 24.0 + 1500.0
	hud.offset_bottom = 18.0 + 420.0
	hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hud.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_theme_font_size_override("font_size", 16)
	hud.add_theme_color_override("font_color", Color(0.92, 0.95, 0.98))
	hud.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	hud.add_theme_constant_override("shadow_offset_x", 1)
	hud.add_theme_constant_override("shadow_offset_y", 1)
	canvas_root.add_child(hud)


func _build_environment() -> void:
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	light.light_energy = 1.15
	light.shadow_enabled = true
	add_child(light)

	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	settings.sky = sky
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	settings.ambient_light_energy = 0.55
	environment.environment = settings
	add_child(environment)

	_add_box(Vector3(60.0, 0.4, 60.0), Vector3(0.0, -0.2, 0.0), 0.0, GROUND_COLOR)
	# 20 deg ramp.
	_add_box(Vector3(6.0, 0.4, 8.0), Vector3(8.0, 0.95, -2.0), -20.0, RAMP_COLOR)
	# Four stairs, 0.2 m rise each.
	for step in 4:
		var height := 0.2 * float(step + 1)
		_add_box(
			Vector3(3.0, height, 0.6),
			Vector3(-7.0, height * 0.5, -2.0 - 0.6 * float(step)),
			0.0,
			PROP_COLOR
		)
	# Low tunnel: a ceiling at 1.4 m forces a crouch.
	_add_box(Vector3(3.2, 0.3, 4.0), Vector3(0.0, 1.55, -9.0), 0.0, PROP_COLOR)
	_add_box(Vector3(0.3, 1.4, 4.0), Vector3(-1.6, 0.7, -9.0), 0.0, PROP_COLOR)
	_add_box(Vector3(0.3, 1.4, 4.0), Vector3(1.6, 0.7, -9.0), 0.0, PROP_COLOR)
	# Pillars: turn-in-place landmarks.
	for index in 6:
		var angle := TAU * float(index) / 6.0
		var position := Vector3(sin(angle) * 7.0, 1.0, 6.0 + cos(angle) * 7.0)
		_add_box(Vector3(0.5, 2.0, 0.5), position, 0.0, PROP_COLOR)


func _add_box(size: Vector3, position: Vector3, rotation_deg: float, color: Color) -> void:
	var static_body := StaticBody3D.new()
	static_body.position = position
	static_body.rotation_degrees.z = rotation_deg
	add_child(static_body)

	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	instance.material_override = material
	static_body.add_child(instance)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	static_body.add_child(shape)
