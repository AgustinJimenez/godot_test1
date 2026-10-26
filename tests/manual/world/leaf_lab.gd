extends Node3D
## Leaf lab: one leaf (or one card of leaves) of a broadleaf species, big and close, to judge and improve
## how a single leaf looks. Run it in a window (`--screen 1 --windowed`), it needs the renderer.
##   Mouse: left drag orbits, wheel zooms, middle/right drag moves.   Left / Right: species   Up / Down: variant
##   1 one mesh leaf   2 one leaf card (the shader draws a dozen leaves on it)   3 the whole crown, close
##   W wireframe   D low-poly / realistic   A autumn   B backlight (sun behind the leaf)   L sun moves round
##   T top / front view   R new seed   P save a picture to user://leaf_lab_<n>.png
## Command line (after --): --species=N --mode=1|2|3 --seed=N --low --autumn --backlight --wire
##   --view=top|front|angle --shot=PATH (save the picture, then quit) --all=DIR (one picture per species)

enum Mode { LEAF, CARD, CROWN }

var seed_value := 1337
var mode := Mode.LEAF
var detailed := true
var autumn := false
var backlight := false
var wire := false
var no_shadow := false
var no_sun := false
var top_view := false
var species_index := 0
var variant := 0
var _registry: SpeciesRegistry
var _species: Array[PlantSpecies] = []
var _stage: Node3D
var _camera: Camera3D
var _sun: DirectionalLight3D
var _label: Label
var _yaw := 25.0
var _pitch := -35.0
var _distance := 1.6
var _distance_given := false
var _target := Vector3(0.0, 0.5, 0.0)
var _drag := 0
var _shot_path := ""
var _all_dir := ""
var _pictures := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.get_slice("=", 1))
		elif arg.begins_with("--species="):
			species_index = int(arg.get_slice("=", 1))
		elif arg.begins_with("--mode="):
			mode = clampi(int(arg.get_slice("=", 1)) - 1, 0, 2) as Mode
		elif arg == "--low":
			detailed = false
		elif arg == "--autumn":
			autumn = true
		elif arg == "--backlight":
			backlight = true
		elif arg == "--wire":
			wire = true
		elif arg.begins_with("--distance="):
			_distance = float(arg.get_slice("=", 1))
			_distance_given = true
		elif arg == "--nosun":
			no_sun = true
		elif arg == "--noshadow":
			no_shadow = true
		elif arg.begins_with("--view="):
			top_view = arg.get_slice("=", 1) == "top"
			if arg.get_slice("=", 1) == "front":
				_pitch = -5.0
				_yaw = 0.0
		elif arg.begins_with("--shot="):
			_shot_path = arg.substr(7)
		elif arg.begins_with("--all="):
			_all_dir = arg.substr(6)
	_build_stage()
	_load_species()
	_show()
	if _all_dir != "":
		_shoot_all.call_deferred()
	elif _shot_path != "":
		_shoot.call_deferred(_shot_path)


func _build_stage() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.46, 0.62, 0.82)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.6, 0.7)
	environment.ambient_light_energy = 0.7
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = not no_shadow
	_sun.visible = not no_sun
	add_child(_sun)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	_camera.near = 0.01
	add_child(_camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16, 12)
	_label.add_theme_color_override(&"font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override(&"shadow_offset_x", 1)
	_label.add_theme_constant_override(&"shadow_offset_y", 1)
	layer.add_child(_label)


func _load_species() -> void:
	_registry = SpeciesRegistry.new(seed_value, 60)
	_species.clear()
	for one in _registry.species:
		if one.form == PlantSpecies.Form.BROADLEAF or one.form == PlantSpecies.Form.SHRUB:
			_species.append(one)
	species_index = posmod(species_index, maxi(_species.size(), 1))


func _show() -> void:
	if _stage != null:
		_stage.queue_free()
	WorldWind.set_realism(1.0 if detailed else 0.0)
	WorldWind.set_autumn(1.0 if autumn else 0.0)
	_stage = Node3D.new()
	add_child(_stage)
	if _species.is_empty():
		_label.text = "no broadleaf species for this seed"
		return
	var one := _species[species_index]
	var instance := MeshInstance3D.new()
	instance.material_override = FloraMeshes.material()
	match mode:
		Mode.LEAF:
			instance.mesh = _leaf_mesh(one)
			_target = Vector3(0.0, 0.05, -0.5)
		Mode.CARD:
			instance.mesh = _card_mesh(one)
			_target = Vector3(0.0, 0.05, -0.5)
		Mode.CROWN:
			instance.mesh = _registry.mesh(one.id, variant, detailed)
			_target = Vector3(0.0, 4.0, 0.0)
	_stage.add_child(instance)
	_sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	if backlight:
		_sun.rotation_degrees = Vector3(-12.0, 150.0, 0.0) # low, behind the leaf
	_label.text = _describe(one)
	_apply_wire()
	_place_camera()


## One leaf of the species at a big size, standing up and facing the camera a little tilted.
func _leaf_mesh(one: PlantSpecies) -> ArrayMesh:
	var builder := MeshBuilder.new()
	builder.detailed = detailed
	var outline := PlantLeafShapes.outline(one, detailed)
	var base := one.leaf.darkened(0.3)
	base.a = 0.0
	var tip := one.leaf_tip.lerp(one.leaf, 0.4)
	tip.a = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + variant
	var axis := Vector3(0.0, 0.1, -1.0).normalized()
	var normal := Vector3(0.0, 1.0, 0.1).normalized()
	PlantLeafShapes.add_leaf(builder, outline, Vector3.ZERO, axis, normal, 1.0, 0.1, -0.12, base, tip,
			rng.randf_range(-0.2, 0.2), rng.randf_range(-0.14, 0.14), 1.0, Vector2(rng.randf(), rng.randf()))
	return builder.commit()


func _card_mesh(one: PlantSpecies) -> ArrayMesh:
	var builder := MeshBuilder.new()
	builder.detailed = detailed
	var base := one.leaf.darkened(0.3)
	base.a = 0.0
	var tip := one.leaf_tip.lerp(one.leaf, 0.4)
	tip.a = 0.0
	var axis := Vector3(0.0, 0.1, -1.0).normalized()
	var normal := Vector3(0.0, 1.0, 0.1).normalized()
	PlantLeafShapes.add_leaf_card(builder, Vector3.ZERO, axis, normal, 1.35, base, tip,
			fmod(float(variant) * 0.37 + 0.11, 1.0),
			PlantLeafShapes.card_look(one.leaf_shape, one.leaf_aspect, one.leaf_lobes, one.leaf_edge))
	return builder.commit()


func _describe(one: PlantSpecies) -> String:
	return ("%s   species %d / %d  (id %d)   variant %d   seed %d\nshape %s  aspect %.2f  lobes %d  edge %s\n"
			+ "%s   %s%s%s%s\n[1] leaf [2] card [3] crown  [W] wire [D] realistic [A] autumn [B] backlight [L] sun [T] top [R] seed [P] picture") % [
			one.name if "name" in one else "species", species_index + 1, _species.size(), one.id, variant,
			seed_value, PlantSpecies.LeafShape.keys()[one.leaf_shape], one.leaf_aspect, one.leaf_lobes,
			PlantSpecies.LeafEdge.keys()[one.leaf_edge], Mode.keys()[mode],
			"realistic" if detailed else "low-poly", "  autumn" if autumn else "", "  backlight" if backlight else "",
			"  wire" if wire else ""]


func _apply_wire() -> void:
	get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME if wire else Viewport.DEBUG_DRAW_DISABLED


func _place_camera() -> void:
	var yaw := deg_to_rad(_yaw)
	var pitch := deg_to_rad(-90.0 if top_view else _pitch)
	var offset := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)) * _distance
	_camera.position = _target + offset
	_camera.look_at(_target, Vector3.BACK if top_view else Vector3.UP)


func _process(_delta: float) -> void:
	_place_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(_distance * 0.9, 0.1)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(_distance * 1.1, 60.0)
		else:
			_drag = button.button_index if button.pressed else 0
	elif event is InputEventMouseMotion and _drag != 0:
		var motion := event as InputEventMouseMotion
		if _drag == MOUSE_BUTTON_LEFT:
			_yaw -= motion.relative.x * 0.4
			_pitch = clampf(_pitch - motion.relative.y * 0.4, -89.0, 89.0)
		else:
			var right := _camera.global_transform.basis.x
			var up := _camera.global_transform.basis.y
			_target += (-right * motion.relative.x + up * motion.relative.y) * _distance * 0.0016
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		_key((event as InputEventKey).keycode)


func _key(code: Key) -> void:
	match code:
		KEY_LEFT:
			species_index = posmod(species_index - 1, maxi(_species.size(), 1))
			variant = 0
		KEY_RIGHT:
			species_index = posmod(species_index + 1, maxi(_species.size(), 1))
			variant = 0
		KEY_UP:
			variant += 1
		KEY_DOWN:
			variant = maxi(variant - 1, 0)
		KEY_1:
			mode = Mode.LEAF
			_distance = 1.6
		KEY_2:
			mode = Mode.CARD
			_distance = 1.8
		KEY_3:
			mode = Mode.CROWN
			_distance = 12.0
		KEY_W:
			wire = not wire
		KEY_D:
			detailed = not detailed
		KEY_A:
			autumn = not autumn
		KEY_B:
			backlight = not backlight
		KEY_T:
			top_view = not top_view
		KEY_L:
			_sun.rotation_degrees.y += 30.0
			return
		KEY_R:
			seed_value = randi() % 100000
			_load_species()
		KEY_P:
			_save("user://leaf_lab_%d.png" % _pictures)
			_pictures += 1
			return
		_:
			return
	_show()


func _save(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("LEAF_LAB picture ", ProjectSettings.globalize_path(path))


func _shoot(path: String) -> void:
	for _frame in 20:
		await get_tree().process_frame
	_save(path)
	get_tree().quit()


func _shoot_all(): # one picture per species, leaf and card
	for _frame in 10:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(_all_dir)
	for index in _species.size():
		species_index = index
		for pick in [Mode.LEAF, Mode.CARD]:
			mode = pick
			_show()
			for _frame in 8:
				await get_tree().process_frame
			_save("%s/species_%02d_%s.png" % [_all_dir, index, Mode.keys()[pick].to_lower()])
	get_tree().quit()
