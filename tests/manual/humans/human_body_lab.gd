extends Node3D
## Human body lab: the two base bodies (female, male) with Height and Weight sliders.
##
## The bodies come from MPFB in Blender (see docs/blender_workflow.md): one mesh each with six
## blend shapes (height_short/tall, weight_light/heavy, muscle_low/high). A blend shape is a stored "move every vertex
## by this much" shape; the slider just sets how much of it to apply, so no mesh is rebuilt.
## Drag with the right mouse button to turn the body; mouse wheel zooms.
## Capture mode: `-- --capture=<png path>` saves one frame and quits.

const BODY_SCENES: Dictionary = {
	"Female": "res://assets/models/humans/female_body.glb",
	"Male": "res://assets/models/humans/male_body.glb",
}
const UNDERWEAR_SCENES: Dictionary = {
	"Female": "res://assets/models/humans/female_underwear.glb",
	"Male": "res://assets/models/humans/male_underwear.glb",
}
## Starting points for the head hair; every entry is a HumanHair parameter (the native class documents them).
const HAIR_PRESETS: Dictionary = {
	"Buzz": {&"side_trim": 0.0, &"length": 0.025, &"volume": 0.2, &"curl": 0.0, &"fringe": 0.3, &"sweep": 0.0, &"gravity": 0.2, &"parting": 0.0},
	"Short": {&"side_trim": 0.55, &"length": 0.07, &"volume": 1.0, &"curl": 0.0, &"fringe": 0.35, &"sweep": 0.0, &"gravity": 0.7, &"parting": 0.2},
	"Bob": {&"side_trim": 0.0, &"length": 0.17, &"volume": 1.0, &"curl": 0.0, &"fringe": 0.3, &"sweep": 0.0, &"gravity": 1.0, &"parting": 0.0},
	"Long": {&"side_trim": 0.0, &"length": 0.32, &"volume": 0.9, &"curl": 0.2, &"fringe": 0.2, &"sweep": 0.0, &"gravity": 1.0, &"parting": 0.0},
	"Slick back": {&"side_trim": 0.85, &"length": 0.15, &"volume": 0.8, &"curl": 0.0, &"fringe": 0.0, &"sweep": 1.0, &"gravity": 0.8, &"parting": 0.0},
	"Curly": {&"side_trim": 0.1, &"length": 0.12, &"volume": 1.3, &"curl": 0.9, &"fringe": 0.6, &"sweep": 0.0, &"gravity": 0.6, &"parting": 0.0},
}
const EYE_SCENES: Dictionary = {
	"Female": "res://assets/models/humans/female_eyes.glb",
	"Male": "res://assets/models/humans/male_eyes.glb",
}
## Height slider -1..1 maps to blend-shape weight -HEIGHT_RANGE..HEIGHT_RANGE (full 1.0 is about
## 1.4 m taller than the base, far too much).
const HEIGHT_RANGE: float = 0.6
## The baked weight shapes move the waist by about 3 cm at weight 1.0, so the heavy side is exaggerated to be visible.
const WEIGHT_GAIN_HEAVY: float = 3.0
## The light shape is already at its designed size at 1.0; pushed to 3.0 it folds the waist and hips of the
## female body, so it only goes a little past.
const WEIGHT_GAIN_LIGHT: float = 1.25
## Muscle shapes move the body about 2-4 cm at 1.0; same split as weight (more on the high side, little past
## the designed range on the low side). Starting values, to be checked at the extremes.
const MUSCLE_GAIN_HIGH: float = 2.0
const MUSCLE_GAIN_LOW: float = 1.25

## Metres, measured on the exported meshes: base height, and how much a full height_tall shape adds / a full
## height_short shape removes.
const BASE_HEIGHT: Dictionary = {"Female": 1.61, "Male": 1.75}
const HEIGHT_TALL_M: float = 0.70
const HEIGHT_SHORT_M: float = 0.36

var _body: Node3D
var _mesh: MeshInstance3D
var _underwear_mesh: MeshInstance3D
var _cloth_material: ShaderMaterial
var _eyes_mesh: MeshInstance3D
var _brows_mesh: MeshInstance3D
var _lashes_mesh: MeshInstance3D
var _hair_mesh: MeshInstance3D
var _head_hair_material: ShaderMaterial
var _hair_style: Dictionary = {}
var _hair_sliders: Dictionary = {}
var _head_hair_color: Color = Color(0.13, 0.08, 0.045)
var _head_hair_density: float = 1.0
var _hair_dirty: bool = false
var _hair_friction: float = 0.2   # friction on small movements (Motion tab): 0 = none, higher = small wiggles die out faster
var _hair_bend: float = 0.5   # bending stiffness (Motion section): how firmly a hair keeps its shape along its length
var _hair_root_stiffness: float = 0.22   # how firmly the roots hold the style (the tips are left free)
var _hair_weight: float = 1.0   # how heavy the hair is (Motion tab): the simulation sags more and swings longer when heavy
var _hair_build_ms: float = 0.0   # how long the last hair build took
var _hair_next_build_ms: int = 0   # not before this time (Time.get_ticks_msec)
var _hair_enabled: bool = true
var _sim: HairSim   # the real hair simulation (native HairSim): guide strands with gravity, inertia and collisions
var _sim_enabled: bool = true
var _solo: bool = false      # --solo: grow exactly one hair and put the camera on it
var _solo_root: bool = false # --solo-root: ... and go in close on its root
var _aim: Vector3 = Vector3.ZERO
var _use_aim: bool = false
var _spin: bool = false      # --spin: hide the panel, hold still 3 s, then turn the body once in 4 s (for recording a video)
var _spin_time: float = 0.0
var _osc_period: float = 0.0   # --osc=<seconds a half turn (180 degrees) takes>: random turns of 90..180 degrees either way with short pauses (the same sequence every run), panel hidden, to watch the hair swing
var _hide_panel: bool = false   # --nopanel: no control panel in the picture
var _osc_rng := RandomNumberGenerator.new()
var _osc_from: float = 0.3
var _osc_to: float = 0.3
var _osc_t: float = 0.0
var _osc_dur: float = 0.0
var _osc_pause: float = 1.0
var _ui_layer: CanvasLayer
var _panel: Control   # the control panel: the mouse wheel over it scrolls it instead of zooming the camera
# hair motion: wind (metres of bend at the tips) and a small spring that swings the hair when the head turns
var _wind: float = 0.0
var _shake_side: float = 1.0
var _hair_sway: HairSway
var _tip_color: Color = Color(0.8, 0.2, 0.45)
var _tip_mix: float = 0.0
var _shake_on_capture: bool = false
var _shine_override: float = -1.0
var _brow_material: ShaderMaterial
var _lash_material: ShaderMaterial
var _hair_color: Color = Color(0.16, 0.1, 0.06)
var _brow_density: float = 0.8
var _eye_material: ShaderMaterial
var _eye_color: Color = Color(0.32, 0.2, 0.1)
var _eye_color_other: Color = Color(0.25, 0.45, 0.7)
var _different_eyes: bool = false
var _iris_deg: float = 26.0
var _pupil: float = 0.38
var _sclera_tint: float = 0.0
var _veins: float = 0.25
var _second_eye_row: Control
var _gender: String = "Male"
var _height: float = 0.0
var _weight: float = 0.0
var _muscle: float = 0.0
var _yaw: float = 0.3
const FACE_DISTANCE := 0.35        # camera distance (m) for the eyes and brows close-up
const FACE_DISTANCE_HAIR := 0.55   # ... and for the hair tab: a little farther back
const FACE_HAIR_LIFT := 0.0        # ... (extra camera height for the hair tab: none, the eyes stay in the centre and the hair fits above them)
var _face_hair: bool = false
var _settle_override: int = -1   # --settle=N: steps the hair simulation runs at start (default: the native default)
var _start_tab: String = ""   # --tab=Hair: start on that tab (Body, Eyes, Brows, Hair)
var _distance: float = 3.6
var _look_y: float = 0.95
var _cam_y: float = 1.0
var _face_mode: bool = false
var _camera: Camera3D
var _readout: Label
var _fps_label: Label
var _fps_accum: float = 0.0
var _fps_frames: int = 0
var _fps_label_fps: float = 0.0
var _bench_seconds: float = 0.0   # --bench=<seconds>: measure fps and GPU/CPU frame time for that long (after 3 s warm-up), print it and quit
var _bench_time: float = 0.0
var _bench_n: int = 0
var _bench_rebuilds: int = 0
var _bench_since: float = 0.0
var _bench_spike: float = 0.0
var _bench_gpu: float = 0.0
var _bench_cpu: float = 0.0
var _bench_fps: float = 0.0
var _hair_info: String = "" # how much hair there is (shown under the readout)
var _material: StandardMaterial3D
var _capture_path: String = ""
var _capture_frames: int = 0


func _ready() -> void:
	get_viewport().msaa_3d = Viewport.MSAA_4X   # hair-thin strands alias into dots without it
	_hair_style = HumanHair.default_params()
	for key: StringName in HAIR_PRESETS["Short"]:
		_hair_style[key] = HAIR_PRESETS["Short"][key]
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_capture_path = arg.trim_prefix("--capture=")
		elif arg == "--close":
			_distance = 1.3
			_look_y = 0.85
		elif arg.begins_with("--height="):
			_height = float(arg.trim_prefix("--height="))
		elif arg.begins_with("--weight="):
			_weight = float(arg.trim_prefix("--weight="))
		elif arg.begins_with("--muscle="):
			_muscle = float(arg.trim_prefix("--muscle="))
		elif arg == "--face":
			_distance = 0.8
			_look_y = 1.58
			_cam_y = 1.58
			_face_mode = true
		elif arg.begins_with("--eye="):
			_eye_color = Color.html(arg.trim_prefix("--eye="))
		elif arg.begins_with("--distance="):
			_distance = float(arg.trim_prefix("--distance="))
		elif arg.begins_with("--brow="):
			_hair_color = Color.html(arg.trim_prefix("--brow="))
		elif arg.begins_with("--density="):
			_brow_density = float(arg.trim_prefix("--density="))
		elif arg == "--solo":
			_solo = true
			_hair_style[&"locks"] = 1
			_hair_style[&"strands"] = 1
		elif arg == "--solo-root":
			_solo = true
			_solo_root = true
			_yaw = 0.0
			_hair_style[&"locks"] = 1
			_hair_style[&"strands"] = 1
		elif arg == "--nopanel":
			_hide_panel = true
		elif arg.begins_with("--osc="):
			_osc_period = float(arg.trim_prefix("--osc="))
		elif arg.begins_with("--weight="):
			_hair_weight = float(arg.trim_prefix("--weight="))
		elif arg.begins_with("--friction="):
			_hair_friction = float(arg.trim_prefix("--friction="))
		elif arg.begins_with("--settle="):
			_settle_override = int(arg.trim_prefix("--settle="))
		elif arg.begins_with("--tab="):
			_start_tab = arg.trim_prefix("--tab=")
		elif arg.begins_with("--bench="):
			_bench_seconds = float(arg.trim_prefix("--bench="))
		elif arg == "--nosim":
			_sim_enabled = false
		elif arg == "--spin":
			_spin = true
		elif arg == "--nohair":
			_hair_enabled = false
		elif arg.begins_with("--hair-preset="):
			var preset: Dictionary = HAIR_PRESETS[arg.trim_prefix("--hair-preset=")]
			for key: StringName in preset:
				_hair_style[key] = preset[key]
		elif arg.begins_with("--tip="):
			_tip_color = Color.html(arg.trim_prefix("--tip="))
		elif arg.begins_with("--tip-amount="):
			_tip_mix = float(arg.trim_prefix("--tip-amount="))
		elif arg.begins_with("--yaw="):
			_yaw = deg_to_rad(float(arg.trim_prefix("--yaw=")))
		elif arg.begins_with("--shine="):
			_shine_override = float(arg.trim_prefix("--shine="))
		elif arg == "--shake":
			_shake_on_capture = true
		elif arg.begins_with("--wind="):
			_wind = float(arg.trim_prefix("--wind="))
		elif arg.begins_with("--hair-colour="):
			_head_hair_color = Color.html(arg.trim_prefix("--hair-colour="))
		elif arg.begins_with("--strands="):
			_hair_style[&"strands"] = float(arg.trim_prefix("--strands="))
		elif arg.begins_with("--hair-set="):
			# --hair-set=key:value (any HumanHair parameter), e.g. --hair-set=length:0.2
			var pair: PackedStringArray = arg.trim_prefix("--hair-set=").split(":")
			_hair_style[StringName(pair[0])] = float(pair[1])
		elif arg.begins_with("--eye2="):
			_eye_color_other = Color.html(arg.trim_prefix("--eye2="))
			_different_eyes = true
		elif arg.begins_with("--iris="):
			_iris_deg = float(arg.trim_prefix("--iris="))
		elif arg.begins_with("--pupil="):
			_pupil = float(arg.trim_prefix("--pupil="))
		elif arg.begins_with("--sclera="):
			_sclera_tint = float(arg.trim_prefix("--sclera="))
		elif arg.begins_with("--veins="):
			_veins = float(arg.trim_prefix("--veins="))
		elif arg.begins_with("--gender="):
			_gender = arg.trim_prefix("--gender=")
	_build_environment()
	_build_material()
	_build_ui()
	_set_gender(_gender)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.22, 0.23, 0.26)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.ambient_light_energy = 0.35
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 35.0, 0.0)
	sun.light_energy = 0.8
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10.0, -140.0, 0.0)
	fill.light_energy = 0.25
	add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.1
	disc.bottom_radius = 1.1
	disc.height = 0.02
	floor_mesh.mesh = disc
	floor_mesh.position.y = -0.011
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.3, 0.3, 0.33)
	floor_mesh.material_override = floor_mat
	add_child(floor_mesh)
	_camera = Camera3D.new()
	_camera.fov = 38.0
	add_child(_camera)
	_update_camera()


func _build_material() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.6, 0.4, 0.32)
	_material.roughness = 0.55
	_material.subsurf_scatter_enabled = true
	_material.subsurf_scatter_strength = 0.2
	_cloth_material = ShaderMaterial.new()
	_cloth_material.shader = load("res://shaders/human_underwear_fabric.gdshader")
	_eye_material = ShaderMaterial.new()
	_eye_material.shader = load("res://shaders/human_eye.gdshader")
	_apply_eye_parameters()
	var hair_shader: Shader = load("res://shaders/human_face_hair.gdshader")
	_brow_material = ShaderMaterial.new()
	_brow_material.shader = hair_shader
	_lash_material = ShaderMaterial.new()
	_lash_material.shader = hair_shader
	_lash_material.set_shader_parameter(&"is_lash", true)
	_apply_hair_parameters()
	_head_hair_material = ShaderMaterial.new()
	_head_hair_material.shader = load("res://shaders/human_hair.gdshader")
	_head_hair_material.set_shader_parameter(&"hair_color", _head_hair_color)
	_head_hair_material.set_shader_parameter(&"density", _head_hair_density)
	_head_hair_material.set_shader_parameter(&"tip_color", _tip_color)
	_head_hair_material.set_shader_parameter(&"tip_mix", _tip_mix)
	if _shine_override >= 0.0:
		_head_hair_material.set_shader_parameter(&"shine", _shine_override)
	_head_hair_material.set_shader_parameter(&"wind", Vector3(1.0, 0.0, 0.35) * _wind)
	_hair_sway = HairSway.new()
	add_child(_hair_sway)


func _build_ui() -> void:
	_make_fps_label()
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui_layer = layer
	layer.visible = not (_spin or _osc_period > 0.0 or _hide_panel)
	var panel := PanelContainer.new()
	panel.position = Vector2(16.0, 16.0)
	layer.add_child(panel)
	_panel = panel
	# many controls: the panel scrolls
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440.0, 840.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(410.0, 0.0)
	scroll.add_child(box)
	var title := Label.new()
	title.text = "Human body lab"
	box.add_child(title)
	var gender_row := HBoxContainer.new()
	box.add_child(gender_row)
	for gender_name: String in BODY_SCENES:
		var button := Button.new()
		button.text = gender_name
		button.toggle_mode = true
		button.button_pressed = gender_name == _gender
		button.pressed.connect(_set_gender.bind(gender_name))
		button.name = gender_name
		button.add_to_group(&"gender_buttons")
		gender_row.add_child(button)
	# one tab per part of the character, so the list stays short
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(410.0, 0.0)
	box.add_child(tabs)
	var start_face := _face_mode # (adding the first tab fires tab_changed, which would turn the close-up off)
	tabs.tab_changed.connect(_on_tab_changed.bind(tabs))
	var body_tab := _add_tab(tabs, "Body")
	_add_slider(body_tab, "Height", _on_height_changed)
	_add_slider(body_tab, "Weight", _on_weight_changed)
	_add_slider(body_tab, "Muscle", _on_muscle_changed)
	var eyes_tab := _add_tab(tabs, "Eyes")
	_add_color_row(eyes_tab, "Eye colour", _eye_color, _on_eye_color_changed)
	var different := CheckBox.new()
	different.text = "Different colour per eye"
	different.button_pressed = _different_eyes
	different.toggled.connect(_on_different_eyes_toggled)
	eyes_tab.add_child(different)
	_second_eye_row = _add_color_row(eyes_tab, "Second eye colour", _eye_color_other, _on_eye_color_other_changed)
	_second_eye_row.visible = _different_eyes
	_add_range_slider(eyes_tab, "Iris size", 18.0, 34.0, _iris_deg, _on_iris_changed)
	_add_range_slider(eyes_tab, "Pupil size", 0.15, 0.7, _pupil, _on_pupil_changed)
	_add_range_slider(eyes_tab, "Sclera tint (yellowing)", 0.0, 1.0, _sclera_tint, _on_sclera_changed)
	_add_range_slider(eyes_tab, "Visible veins", 0.0, 1.0, _veins, _on_veins_changed)
	var brows_tab := _add_tab(tabs, "Brows")
	_add_color_row(brows_tab, "Brow and lash colour", _hair_color, _on_hair_color_changed)
	_add_range_slider(brows_tab, "Brow density", 0.2, 1.0, _brow_density, _on_brow_density_changed)
	# head hair (the native HumanHair class): the style and look in one tab, the amount of hair (and its cost) in another
	var hair_tab := _add_tab(tabs, "Hair")
	var presets := HBoxContainer.new()
	hair_tab.add_child(presets)
	for preset_name: String in HAIR_PRESETS:
		var preset_button := Button.new()
		preset_button.text = preset_name
		preset_button.pressed.connect(_on_hair_preset.bind(preset_name))
		presets.add_child(preset_button)
	_add_color_row(hair_tab, "Hair colour", _head_hair_color, _on_head_hair_color_changed)
	_add_hair_slider(hair_tab, "Length", &"length", 0.0, 0.35)
	_add_hair_slider(hair_tab, "Volume", &"volume", 0.0, 1.5)
	_add_hair_slider(hair_tab, "Curl", &"curl", 0.0, 1.0)
	_add_hair_slider(hair_tab, "Fringe (front falls forward)", &"fringe", 0.0, 1.0)
	_add_hair_slider(hair_tab, "Combed back (0 = away from the crown)", &"sweep", 0.0, 1.0)
	_add_hair_slider(hair_tab, "Parting", &"parting", -1.0, 1.0)
	_add_hair_slider(hair_tab, "Fall (gravity)", &"gravity", 0.0, 2.0)
	_add_hair_slider(hair_tab, "Sides and back shorter", &"side_trim", 0.0, 1.0)
	_add_color_row(hair_tab, "Dyed ends colour", _tip_color, _on_tip_color_changed)
	_add_range_slider(hair_tab, "Dyed ends amount", 0.0, 1.0, _tip_mix, _on_tip_mix_changed)
	_add_range_slider(hair_tab, "Hair shine", 0.0, 1.0, 0.4, _on_hair_shine_changed)
	var new_seed := Button.new()
	new_seed.text = "New hair (other dice)"
	new_seed.pressed.connect(_on_new_hair_seed)
	hair_tab.add_child(new_seed)
	_add_section_label(hair_tab, "Amount of hair")
	var amount_tab: Control = hair_tab
	_add_hair_slider(amount_tab, "Guide locks (how many places hair grows from)", &"locks", 200.0, 6000.0)
	_add_hair_slider(amount_tab, "Individual hairs per lock (0 = ribbons)", &"strands", 0.0, 24.0)
	_add_hair_slider(amount_tab, "Points per hair (0 = auto; fewer = cheaper)", &"points", 0.0, 16.0)
	_add_hair_slider(amount_tab, "Hair spread (clump)", &"clump", 0.0, 0.02)
	_add_range_slider(amount_tab, "Hair density", 0.3, 1.0, _head_hair_density, _on_head_hair_density_changed)
	_add_section_label(hair_tab, "Motion")
	var motion_tab: Control = hair_tab
	_add_range_slider(motion_tab, "Wind", 0.0, 0.08, _wind, _on_wind_changed)
	_add_range_slider(motion_tab, "Hair weight (1 = normal)", 0.5, 2.0, _hair_weight, _on_hair_weight_changed)
	_add_range_slider(motion_tab, "Friction on small movements", 0.0, 0.5, _hair_friction, _on_hair_friction_changed)
	_add_range_slider(motion_tab, "Bending stiffness (keeps its shape)", 0.0, 1.0, _hair_bend, _on_hair_bend_changed)
	_add_range_slider(motion_tab, "Root stiffness (less swing near the head)", 0.1, 0.9, _hair_root_stiffness, _on_hair_root_stiffness_changed)
	var shake := Button.new()
	shake.text = "Shake head (swing the hair)"
	shake.pressed.connect(_on_shake_pressed)
	motion_tab.add_child(shake)
	for i in tabs.get_child_count():
		if tabs.get_child(i).name == _start_tab:
			tabs.current_tab = i
	if start_face and _start_tab == "":
		tabs.current_tab = 1 # --face: start on the Eyes tab (the close-up follows the tab)
	_readout = Label.new()
	box.add_child(_readout)


func _add_section_label(parent: Control, text: String) -> void:
	parent.add_child(HSeparator.new())
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", Color(0.75, 0.85, 1.0))
	parent.add_child(label)


func _add_tab(tabs: TabContainer, tab_name: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = tab_name
	tabs.add_child(page)
	return page


func _add_slider(parent: Control, label_text: String, callback: Callable) -> void:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var slider := HSlider.new()
	slider.scrollable = false
	slider.min_value = -1.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = 0.0
	slider.name = label_text
	slider.value_changed.connect(callback)
	parent.add_child(slider)


func _set_gender(gender_name: String) -> void:
	_gender = gender_name
	if _body != null:
		_body.queue_free()
	var packed: PackedScene = load(BODY_SCENES[gender_name])
	_body = packed.instantiate() as Node3D
	add_child(_body)
	_hair_sway.target = _body
	_mesh = _find_mesh(_body)
	_mesh.material_override = _material
	# The underwear has the same blend shapes as the body, so the same weights fit it.
	var underwear_packed: PackedScene = load(UNDERWEAR_SCENES[gender_name])
	var underwear: Node3D = underwear_packed.instantiate() as Node3D
	_body.add_child(underwear)
	_underwear_mesh = _find_mesh(underwear)
	_underwear_mesh.material_override = _cloth_material
	# The eyes too: two spheres that move with the head under the same shape weights.
	var eyes_packed: PackedScene = load(EYE_SCENES[gender_name])
	var eyes: Node3D = eyes_packed.instantiate() as Node3D
	_body.add_child(eyes)
	_eyes_mesh = _find_mesh(eyes)
	_eyes_mesh.material_override = _eye_material
	# Brows and lashes: hair cards bound to the face, same shape names again.
	var base_path: String = "res://assets/models/humans/%s_" % gender_name.to_lower()
	var brows: Node3D = (load(base_path + "brows.glb") as PackedScene).instantiate() as Node3D
	_body.add_child(brows)
	_brows_mesh = _find_mesh(brows)
	_brows_mesh.material_override = _brow_material
	var lashes: Node3D = (load(base_path + "lashes.glb") as PackedScene).instantiate() as Node3D
	_body.add_child(lashes)
	_lashes_mesh = _find_mesh(lashes)
	_lashes_mesh.material_override = _lash_material
	_hair_mesh = null
	_rebuild_hair()
	_apply()
	for button: Node in get_tree().get_nodes_in_group(&"gender_buttons"):
		(button as Button).button_pressed = button.name == gender_name
	_body.rotation.y = _yaw


func _find_mesh(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root as MeshInstance3D
	for child: Node in root.get_children():
		var found: MeshInstance3D = _find_mesh(child)
		if found != null:
			return found
	return null


func _on_height_changed(value: float) -> void:
	_height = value
	_apply()


func _add_color_row(parent: Control, label_text: String, color: Color, callback: Callable) -> Control:
	var row := VBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	row.add_child(label)
	var picker := ColorPickerButton.new()
	picker.color = color
	picker.custom_minimum_size = Vector2(0.0, 28.0)
	picker.color_changed.connect(callback)
	row.add_child(picker)
	return row


func _add_range_slider(parent: Control, label_text: String, low: float, high: float, value: float, callback: Callable) -> void:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var slider := HSlider.new()
	slider.scrollable = false
	slider.min_value = low
	slider.max_value = high
	slider.step = (high - low) / 100.0
	slider.value = value
	slider.value_changed.connect(callback)
	parent.add_child(slider)


func _apply_eye_parameters() -> void:
	_eye_material.set_shader_parameter(&"iris_color", _eye_color)
	_eye_material.set_shader_parameter(&"iris_color_other", _eye_color_other)
	_eye_material.set_shader_parameter(&"different_eyes", _different_eyes)
	_eye_material.set_shader_parameter(&"iris_radius_deg", _iris_deg)
	_eye_material.set_shader_parameter(&"pupil_size", _pupil)
	_eye_material.set_shader_parameter(&"sclera_tint", _sclera_tint)
	_eye_material.set_shader_parameter(&"vein_amount", _veins)


func _apply_hair_parameters() -> void:
	for material: ShaderMaterial in [_brow_material, _lash_material]:
		material.set_shader_parameter(&"hair_color", _hair_color)
	_brow_material.set_shader_parameter(&"brow_density", _brow_density)


# The Eyes, Brows and Hair tabs are about the head: the camera goes to the face; the other tabs show the whole body.
func _on_tab_changed(index: int, tabs: TabContainer) -> void:
	var tab_name: String = tabs.get_child(index).name
	var wants_face: bool = tab_name in ["Eyes", "Brows", "Hair"]
	# Eyes and Brows keep the tight framing; Hair stands back a little and looks higher so the whole head of hair is in the picture
	var wants_hair: bool = tab_name == "Hair"
	if wants_face != _face_mode:
		_face_hair = wants_hair
		_on_face_toggled(wants_face)
	elif wants_face and wants_hair != _face_hair:
		_face_hair = wants_hair
		_distance = FACE_DISTANCE_HAIR if wants_hair else FACE_DISTANCE
		_apply()
		_update_camera()


func _on_face_toggled(pressed: bool) -> void:
	_face_mode = pressed
	if pressed:
		_distance = FACE_DISTANCE_HAIR if _face_hair else FACE_DISTANCE
	else:
		_distance = 3.6
		_cam_y = 1.0
		_look_y = 0.95
	_apply()
	_update_camera()


func _add_hair_slider(parent: Control, label_text: String, key: StringName, low: float, high: float) -> void:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var slider := HSlider.new()
	slider.scrollable = false
	slider.min_value = low
	slider.max_value = high
	slider.step = (high - low) / 100.0
	slider.value = float(_hair_style[key])
	slider.value_changed.connect(_on_hair_param.bind(key))
	parent.add_child(slider)
	_hair_sliders[key] = slider


func _on_hair_param(value: float, key: StringName) -> void:
	_hair_style[key] = value
	_hair_dirty = true


func _on_hair_preset(preset_name: String) -> void:
	var preset: Dictionary = HAIR_PRESETS[preset_name]
	for key: StringName in preset:
		_hair_style[key] = preset[key]
		if _hair_sliders.has(key):
			(_hair_sliders[key] as HSlider).set_value_no_signal(float(preset[key]))
	_hair_dirty = true


func _on_tip_color_changed(color: Color) -> void:
	_tip_color = color
	_head_hair_material.set_shader_parameter(&"tip_color", color)


func _on_tip_mix_changed(value: float) -> void:
	_tip_mix = value
	_head_hair_material.set_shader_parameter(&"tip_mix", value)


func _on_hair_shine_changed(value: float) -> void:
	_head_hair_material.set_shader_parameter(&"shine", value)


# The wind pushes the simulated hair (so the head stops it); without the simulation it is the old vertex-shader bend.
func _apply_wind() -> void:
	var direction := Vector3(1.0, 0.0, 0.35)
	if _sim_enabled and _sim != null and _hair_mesh != null:
		_sim.wind = direction * _wind * 100.0   # 0.08 -> about 8 m/s2, near gravity
		_head_hair_material.set_shader_parameter(&"wind", Vector3.ZERO)
	else:
		_head_hair_material.set_shader_parameter(&"wind", direction * _wind)


func _on_hair_bend_changed(value: float) -> void:
	_hair_bend = value
	if _sim != null:
		_sim.bend_stiffness = value


func _on_hair_root_stiffness_changed(value: float) -> void:
	_hair_root_stiffness = value
	if _sim != null:
		_sim.root_stiffness = value


func _on_hair_friction_changed(value: float) -> void:
	_hair_friction = value
	if _sim != null:
		_sim.calm_damping = 1.0 - value


func _on_hair_weight_changed(value: float) -> void:
	_hair_weight = value
	if _sim != null:
		_sim.weight = value


func _on_wind_changed(value: float) -> void:
	_wind = value
	# the wind blows from the character's right, a little from the front, in the body's own space
	_apply_wind()


func _on_shake_pressed() -> void:
	_hair_sway.kick(Vector3(0.9 * _shake_side, 0.25, 0.5))
	_shake_side = -_shake_side




func _on_new_hair_seed() -> void:
	_hair_style[&"seed"] = int(_hair_style[&"seed"]) + 1
	_hair_dirty = true


func _on_head_hair_color_changed(color: Color) -> void:
	_head_hair_color = color
	_head_hair_material.set_shader_parameter(&"hair_color", color)


func _on_head_hair_density_changed(value: float) -> void:
	_head_hair_density = value
	_head_hair_material.set_shader_parameter(&"density", value)


# Builds the head hair from the body's own mesh in native code (a few ms), as a sibling of the body mesh with the same blend shapes.
# --solo: look at the one hair from close by (the real width is about 1 mm, so it is thin; the camera goes to about 25 cm from it).
func _frame_solo_hair(built: ArrayMesh) -> void:
	var vertices: PackedVector3Array = built.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = built.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for i: int in vertices.size():
		if colors[i].b < 0.5:   # the hair itself, not the scalp layer
			low = low.min(vertices[i])
			high = high.max(vertices[i])
	if low.x == INF:
		print("SOLO no hair grown (the one lock was dropped); try another --hair-set=seed:N")
		return
	var centre: Vector3 = (low + high) * 0.5
	print("SOLO hair: %.1f cm long, root at y %.3f" % [(high - low).length() * 100.0, high.y])
	_face_mode = false
	_cam_y = centre.y
	_look_y = centre.y
	_distance = maxf(0.22, (high - low).length() * 2.2)
	if _solo_root:
		# the root is the end of the hair that is nearest the scalp (its first points: lowest strand position in the UV)
		var uvs: PackedVector2Array = built.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		var root: Vector3 = Vector3.ZERO
		var best: float = INF
		for i: int in vertices.size():
			if colors[i].b < 0.5 and uvs[i].y < best:
				best = uvs[i].y
				root = vertices[i]
		_aim = root + Vector3(0.0, -0.004, 0.0)
		_use_aim = true
		_distance = 0.15
		print("SOLO root at ", root)
	_update_camera()


# The simulation drives the hair through the texture `sim_tex` of its material (the shader moves every hair by its guide).
func _attach_sim() -> void:
	if _sim == null:
		_sim = HairSim.new()
		add_child(_sim)
	if _sim_enabled:
		# looser than the defaults: the pull back to the style is what makes hair look stiff
		_sim.root_stiffness = _hair_root_stiffness
		_sim.bend_stiffness = _hair_bend
		_sim.tip_stiffness = 0.004
		_sim.damping = 0.99
		_sim.weight = _hair_weight
		_apply_wind()
		_sim.calm_damping = 1.0 - _hair_friction
		if _settle_override >= 0:
			_sim.settle_steps = _settle_override
		_sim.hair = _hair_mesh
		_sim.material = _head_hair_material
	else:
		_sim.hair = null
		_head_hair_material.set_shader_parameter(&"use_sim", false)


func _thousands(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _rebuild_hair() -> void:
	var build_started := Time.get_ticks_usec()
	_rebuild_hair_now()
	_hair_build_ms = (Time.get_ticks_usec() - build_started) / 1000.0


func _rebuild_hair_now() -> void:
	_hair_dirty = false
	if _hair_mesh != null:
		_hair_mesh.queue_free()
		_hair_mesh = null
	if not _hair_enabled or _mesh == null or not (_mesh.mesh is ArrayMesh):
		return
	var params: Dictionary = _hair_style.duplicate()
	params["eye_drop"] = HumanHair.default_params_for(_gender)["eye_drop"]
	_head_hair_material.set_shader_parameter(&"single_hairs", int(_hair_style.get(&"strands", 0)) > 0)
	var built: ArrayMesh = HumanHair.build(_mesh.mesh as ArrayMesh, params)
	if built == null:
		_hair_info = "Hair: none (bald)"
		if _sim != null:
			_sim.hair = null
		return
	var strands: int = int(_hair_style.get(&"strands", 0))
	var guides: int = int(built.get_meta(&"hair_guide_count", 0))
	var verts: int = built.surface_get_array_len(0) if built.get_surface_count() > 0 else 0
	if strands > 0 and guides > 0:
		_hair_info = "Hair: %s hairs (%s guides x %d)   %s vertices" % [_thousands(guides * strands), _thousands(guides), strands, _thousands(verts)]
	else:
		_hair_info = "Hair: ribbon locks, %s vertices" % _thousands(verts)
	_hair_mesh = MeshInstance3D.new()
	_hair_mesh.mesh = built
	if _solo:
		_frame_solo_hair(built)
	_hair_mesh.material_override = _head_hair_material
	_attach_sim()
	_body.add_child(_hair_mesh)
	_hair_sway.hair = _hair_mesh # (the swing goes to this mesh's own `sway` instance uniform)
	_apply()


func _on_hair_color_changed(color: Color) -> void:
	_hair_color = color
	_apply_hair_parameters()


func _on_brow_density_changed(value: float) -> void:
	_brow_density = value
	_apply_hair_parameters()


func _on_eye_color_changed(color: Color) -> void:
	_eye_color = color
	_apply_eye_parameters()


func _on_eye_color_other_changed(color: Color) -> void:
	_eye_color_other = color
	_apply_eye_parameters()


func _on_different_eyes_toggled(pressed: bool) -> void:
	_different_eyes = pressed
	_second_eye_row.visible = pressed
	_apply_eye_parameters()


func _on_iris_changed(value: float) -> void:
	_iris_deg = value
	_apply_eye_parameters()


func _on_pupil_changed(value: float) -> void:
	_pupil = value
	_apply_eye_parameters()


func _on_sclera_changed(value: float) -> void:
	_sclera_tint = value
	_apply_eye_parameters()


func _on_veins_changed(value: float) -> void:
	_veins = value
	_apply_eye_parameters()


func _on_muscle_changed(value: float) -> void:
	_muscle = value
	_apply()


func _on_weight_changed(value: float) -> void:
	_weight = value
	_apply()


func _apply() -> void:
	if _mesh == null:
		return
	var tall: float = maxf(_height, 0.0) * HEIGHT_RANGE
	var short: float = maxf(-_height, 0.0) * HEIGHT_RANGE
	var heavy: float = maxf(_weight, 0.0) * WEIGHT_GAIN_HEAVY
	var light: float = maxf(-_weight, 0.0) * WEIGHT_GAIN_LIGHT
	_set_shape(&"height_tall", tall)
	_set_shape(&"height_short", short)
	_set_shape(&"weight_heavy", heavy)
	_set_shape(&"weight_light", light)
	_set_shape(&"muscle_high", maxf(_muscle, 0.0) * MUSCLE_GAIN_HIGH)
	_set_shape(&"muscle_low", maxf(-_muscle, 0.0) * MUSCLE_GAIN_LOW)
	# The mesh's own bounding box spans every blend shape, so work the height out from the
	# base height and how far each height shape moves the head (measured in Blender).
	var height_m: float = float(BASE_HEIGHT[_gender]) + tall * HEIGHT_TALL_M + short * -HEIGHT_SHORT_M
	_readout.text = "%s   height %.2f m" % [_gender, height_m]
	if _hair_enabled and _hair_info != "":
		_readout.text += "\n" + _hair_info
	if _face_mode:
		# keep the camera on the eyes: eye height is 0.937 of the base height and moves with the head shapes
		_cam_y = float(BASE_HEIGHT[_gender]) * 0.937 + tall * 0.67 - short * 0.343 + (FACE_HAIR_LIFT if _face_hair else 0.0)
		_look_y = _cam_y
		_update_camera()


func _set_shape(shape_name: StringName, value: float) -> void:
	for target: MeshInstance3D in [_mesh, _underwear_mesh, _eyes_mesh, _brows_mesh, _lashes_mesh, _hair_mesh]:
		if target == null:
			continue
		var index: int = target.find_blend_shape_by_name(shape_name)
		if index < 0:
			push_error("missing blend shape " + String(shape_name))
			continue
		target.set_blend_shape_value(index, value)


func _update_camera() -> void:
	if _use_aim:
		# in close on a point: a little above and in front of it, looking at it
		_camera.position = _aim + Vector3(0.0, 0.035, 0.05) * (_distance / 0.06)
		_camera.look_at(_aim)
		return
	_camera.position = Vector3(0.0, _cam_y, _distance)
	_camera.look_at(Vector3(0.0, _look_y, 0.0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if (motion.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0 and _body != null:
			_yaw += motion.relative.x * 0.01
			_body.rotation.y = _yaw
	elif event is InputEventMouseButton:
		var wheel := event as InputEventMouseButton
		if _panel != null and _panel.get_global_rect().has_point(wheel.position):
			return
		if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = clampf(_distance * 0.9, 0.2, 8.0)
			_update_camera()
		elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = clampf(_distance / 0.9, 0.2, 8.0)
			_update_camera()


func _make_fps_label() -> void:
	# frames per second and the time the GPU and CPU spend on a frame: always visible (top right), even with the panel hidden
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_fps_label = Label.new()
	_fps_label.anchor_left = 1.0
	_fps_label.anchor_right = 1.0
	_fps_label.offset_left = -330.0
	_fps_label.offset_right = -12.0
	_fps_label.offset_top = 8.0
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.add_theme_color_override(&"font_color", Color(1, 1, 0.6))
	_fps_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0))
	_fps_label.add_theme_constant_override(&"outline_size", 5)
	layer.add_child(_fps_label)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _update_fps_label(delta: float) -> void:
	_fps_accum += delta
	_fps_frames += 1
	if _fps_accum < 0.5:
		return
	var vp := get_viewport().get_viewport_rid()
	var gpu_ms: float = RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var cpu_ms: float = RenderingServer.viewport_get_measured_render_time_cpu(vp)
	_fps_label_fps = _fps_frames / _fps_accum
	_fps_label.text = "%d fps  (%.1f ms)\nGPU %.1f ms   CPU %.1f ms" % [roundi(_fps_frames / _fps_accum), 1000.0 * _fps_accum / _fps_frames, gpu_ms, cpu_ms]
	_fps_accum = 0.0
	_fps_frames = 0
	if _bench_seconds > 0.0:
		_bench_time += 0.5
		if _bench_time > 3.0: # skip the first 3 s (shader compile, hair build)
			_bench_n += 1
			_bench_gpu += gpu_ms
			_bench_cpu += cpu_ms
			_bench_fps += _fps_label_fps
		if _bench_time >= 3.0 + _bench_seconds:
			print("HUMAN_LAB bench: %s | tip offset %.4f m | build %.0f ms | longest frame %.0f ms | avg %.0f fps  GPU %.2f ms  CPU %.2f ms" % [_hair_info, (_sim.get_mean_tip_offset() if _sim != null else -1.0), _hair_build_ms, _bench_spike, _bench_fps / maxi(_bench_n, 1), _bench_gpu / maxi(_bench_n, 1), _bench_cpu / maxi(_bench_n, 1)])
			get_tree().quit()


func _process(delta: float) -> void:
	_update_fps_label(delta)
	if _bench_seconds > 0.0 and _bench_time > 2.0 and _bench_rebuilds < 6:
		# --bench: change the hair a few times (like dragging a slider) and keep the longest frame
		_bench_spike = maxf(_bench_spike, delta * 1000.0) if _bench_rebuilds > 0 else 0.0
		_bench_since += delta
		if _bench_since > 0.5:
			_bench_since = 0.0
			_bench_rebuilds += 1
			_hair_style[&"length"] = float(_hair_style[&"length"]) + 0.01
			_hair_dirty = true
	if _osc_period > 0.0 and _body != null:
		_spin_time += delta
		if _spin_time == delta:
			_osc_rng.seed = 7
		if _osc_pause > 0.0:
			_osc_pause -= delta
		elif _osc_t >= _osc_dur:
			# the next turn: 90 to 180 degrees, either way (a little more often to the right), speed set by --osc
			_osc_from = _osc_to
			var angle := _osc_rng.randf_range(PI * 0.5, PI) * (1.0 if _osc_rng.randf() < 0.55 else -1.0)
			_osc_to = _osc_from + angle
			_osc_dur = maxf(absf(angle) / PI * _osc_period, 0.05)
			_osc_t = 0.0
		if _osc_pause <= 0.0 and _osc_t < _osc_dur:
			_osc_t = minf(_osc_t + delta, _osc_dur)
			var k := _osc_t / _osc_dur
			_yaw = lerpf(_osc_from, _osc_to, k * k * (3.0 - 2.0 * k))
			_body.rotation.y = _yaw
			if _osc_t >= _osc_dur:
				_osc_pause = _osc_rng.randf_range(0.0, 0.5) # a short rest before the next turn
	if _spin and _body != null:
		_spin_time += delta
		if _spin_time > 3.0 and _spin_time <= 7.0:
			_yaw = 0.3 + TAU * (_spin_time - 3.0) / 4.0
			_body.rotation.y = _yaw
	# while a hair slider is dragged, rebuild at most as often as the last build allows (it waits 4x as long as the build took), so the frame rate stays up; the last value is always built
	if _hair_dirty and Time.get_ticks_msec() >= _hair_next_build_ms:
		_rebuild_hair()
		_hair_next_build_ms = Time.get_ticks_msec() + int(_hair_build_ms * 4.0)
	if _capture_path == "":
		return
	_capture_frames += 1
	if _shake_on_capture and _capture_frames == 3:
		_on_shake_pressed()
	if _capture_frames == 20:
		get_viewport().get_texture().get_image().save_png(_capture_path)
		print("HUMAN_LAB readout: ", _readout.text.replace("\n", " | "))
		if _sim != null:
			print("HUMAN_LAB sim: guides ", _sim.get_guide_count(), " use_sim ", _head_hair_material.get_shader_parameter(&"use_sim"), " tex ", _head_hair_material.get_shader_parameter(&"sim_tex"), " hair ", _sim.hair, " material ", _sim.material, " tip ", _sim.get_mean_tip_vector())
		get_tree().quit()
