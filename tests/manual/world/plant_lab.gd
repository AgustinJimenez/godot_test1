extends Node3D
## Generates plants at random and shows the results: one growth form at a time, a row per species,
## a column per random individual. It opens on ONE plant: the mouse turns the camera around it.
## Keys:
##   Left / Right  the previous / next individual (through every plant of every row)
##   Up / Down     the previous / next species (same column)
##   Mouse         turns the camera around the plant (it is captured; M gives it back, Esc too;
##                 with it free, hold the left button to turn); wheel = zoom
##   C             the view: individual, trunk, crown, branches (all orbit the plant) and overview
##                 (every plant of the form at once)
##   F / Shift+F   next / previous growth form      G  a new random set of species (new seed)
##   V             new random individuals           L (or D)  low-poly / realistic meshes
##   U (or A)      autumn on / off                  T  wind: calm, breeze, gale
##   H             hide / show the leaves (bare trunk and branches; trees only)
##   K             what kind of tree the leafy species are: as drawn, or Oak, Maple, Beech, Elm,
##                 Ash, Linden, Poplar, Birch, Willow (their leaf shape, size, branching)
##   R             put the camera back on the view's own angle and distance
##   X             free camera on / off: W A S D fly (Q down, E up, Shift fast, wheel = speed) and
##                 the right mouse button held looks around (D and A fly then; L and U still work)
## Command line (after --): --form=CACTUS  --seed=N  --detailed  --view=overview

enum View { INDIVIDUAL, TRUNK, CROWN, BRANCHES, OVERVIEW }

const PLANT_SCALE := {
	PlantSpecies.Form.CONIFER: 1.0, PlantSpecies.Form.BROADLEAF: 1.0, PlantSpecies.Form.PALM: 1.0,
	PlantSpecies.Form.BARE_TREE: 1.0, PlantSpecies.Form.SHRUB: 1.6, PlantSpecies.Form.CACTUS: 1.6,
	PlantSpecies.Form.GRASS: 2.0, PlantSpecies.Form.TALL_GRASS: 2.0, PlantSpecies.Form.REED: 2.0,
	PlantSpecies.Form.FLOWER: 2.2, PlantSpecies.Form.FERN: 2.2, PlantSpecies.Form.MUSHROOM: 2.2,
}
const COLUMNS := 6
const MAX_ROWS := 5
const TURN_SPEED := 0.005 ## radians per pixel of mouse movement

var form := PlantSpecies.Form.BROADLEAF
var world_seed := 1337
var detailed := false
var autumn := false
var view := View.INDIVIDUAL
var free_camera := false
var wind := 0 ## 0 calm, 1 breeze, 2 gale
var leafless := false ## trees without their leaves
const KINDS := ["Oak", "Maple", "Beech", "Elm", "Ash", "Linden", "Poplar", "Birch", "Willow"]
var kind := -1 ## -1: the leafy species as the seed drew them; else an index into KINDS
var focus_row := 0
var focus_column := 0
var _species: Array[PlantSpecies] = []
var _variants: Array[int] = []
var _plants: Node3D
var _camera: Camera3D
var _label: Label
var _instances: Dictionary = {} ## row * COLUMNS + column -> MeshInstance3D
var _tags: Array[Label3D] = []
var _gap := 7.0
var _row_gap := 9.8
var _scale := 1.0
var _tallest := 1.0
var _mouse_turns := true ## the mouse is captured and turns the camera around the plant
var _orbit_yaw := 0.4
var _orbit_pitch := 0.15
var _zoom := 1.0 ## the wheel, on top of the view's own distance
var _frame_pose := Transform3D.IDENTITY ## where the current view puts the camera
var _free_pose := Transform3D.IDENTITY ## where the free camera is
var _flying := false ## the right mouse button is held in free mode
var _yaw := 0.0
var _pitch := 0.0
var _fly_speed := 6.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			world_seed = int(arg.get_slice("=", 1))
		elif arg.begins_with("--form="):
			var index := PlantSpecies.Form.keys().find(arg.get_slice("=", 1).to_upper())
			if index >= 0:
				form = PlantSpecies.Form.values()[index]
		elif arg == "--detailed":
			detailed = true
		elif arg == "--view=overview":
			view = View.OVERVIEW
	_build_stage()
	_generate_species()
	_roll_variants()
	_rebuild()


func _build_stage() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	environment.sky.sky_material = ProceduralSkyMaterial.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(300.0, 300.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.5, 0.5, 0.42)
	ground.material_override = ground_material
	add_child(ground)
	_camera = Camera3D.new()
	_camera.fov = 45.0
	add_child(_camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16, 12)
	layer.add_child(_label)


## The species of this form from the registry of `world_seed`; seeds are tried one after the other
## until a few species of the form have been found (a seed holds only a handful of each form).
func _generate_species() -> void:
	_species.clear()
	var seed_try := world_seed
	for attempt in 40:
		var registry := SpeciesRegistry.new(seed_try, 36)
		for one in registry.species:
			if one.form == form and _species.size() < MAX_ROWS:
				_species.append(one)
		if _species.size() >= MAX_ROWS:
			break
		seed_try += 1
	if kind >= 0:
		for one in _species:
			if one.form == PlantSpecies.Form.BROADLEAF:
				var dice := RandomNumberGenerator.new()
				dice.seed = one.seed ^ 0x1EAF
				SpeciesGenerator.apply_leaf_traits(one, KINDS[kind], dice)
	focus_row = clampi(focus_row, 0, maxi(_species.size() - 1, 0))
	for row in _species.size(): # start on a tree that has the branch-and-leaf crown
		if form == PlantSpecies.Form.BROADLEAF and PlantCrownBuilders.supports(_species[row]):
			focus_row = row
			break


func _roll_variants() -> void:
	_variants.clear()
	for index in COLUMNS:
		_variants.append(randi() % 1000000)


## Builds every plant (the meshes) for the current species, individuals and look.
func _rebuild() -> void:
	if _plants != null:
		_plants.queue_free()
	_plants = Node3D.new()
	add_child(_plants)
	_instances.clear()
	_tags.clear()
	_scale = PLANT_SCALE[form]
	_gap = 3.0 * _scale if _scale > 1.0 else 7.0
	_row_gap = _gap * 1.4
	_tallest = 1.0
	for row in _species.size():
		var one := _species[row]
		for column in COLUMNS:
			var instance := MeshInstance3D.new()
			instance.mesh = PlantMeshes.build(one, _variants[column], detailed, leafless)
			instance.material_override = FloraMeshes.material()
			instance.scale = Vector3.ONE * _scale
			instance.position = _cell(row, column)
			_plants.add_child(instance)
			_instances[row * COLUMNS + column] = instance
		var tag := Label3D.new()
		tag.text = "%s  (species %d)" % [one.common_name, one.id]
		if one.form == PlantSpecies.Form.BROADLEAF:
			tag.text += "\n%s leaf, %d limbs" % [
					PlantSpecies.LeafShape.keys()[one.leaf_shape].to_lower(), one.limb_count]
		tag.font_size = 48
		tag.pixel_size = 0.0016 * _gap
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.position = _cell(row, -1) + Vector3(0.0, 0.3, 0.0)
		_plants.add_child(tag)
		_tags.append(tag)
		_tallest = maxf(_tallest, one.height * _scale)
	_show_view()


func _cell(row: int, column: int) -> Vector3:
	return Vector3((float(column) - float(COLUMNS - 1) * 0.5) * _gap, 0.0, -float(row) * _row_gap)


func _orbiting() -> bool:
	return view != View.OVERVIEW and not _species.is_empty()


## The globals the plants read (look, autumn, wind), the visibility and the camera, the label.
func _show_view() -> void:
	WorldWind.set_realism(1.0 if detailed else 0.0)
	WorldWind.set_autumn(1.0 if autumn else 0.0)
	WorldWind.set_wind([0.0, 0.5, 1.0][wind], Vector2(1.0, 0.3).normalized())
	var orbit := _orbiting()
	for key: int in _instances:
		(_instances[key] as MeshInstance3D).visible = (
				not orbit or key == focus_row * COLUMNS + focus_column)
	for tag in _tags:
		tag.visible = not orbit
	if orbit:
		_place_orbit_camera()
	else:
		_place_overview_camera()
	_finish_framing()
	_sync_mouse()
	_update_label()


## What the camera looks at and from how far, for the current view: [target height, distance,
## pitch]. Heights and distances follow the size of the plant (a mushroom is a few centimetres).
func _view_framing() -> Array[float]:
	var one := _species[focus_row]
	var plant_height := one.height * _scale
	match view:
		View.TRUNK:
			var eye := clampf(plant_height * 0.35, 0.12, 1.5 * _scale)
			return [eye, clampf(plant_height * 4.0, 1.5, 5.0 * _scale), 0.0]
		View.CROWN:
			return [plant_height * 0.68, maxf(plant_height * 1.6, 2.0), 0.05]
		View.BRANCHES:
			var join := one.height * one.bare * _scale # where the limbs leave the trunk
			var near := maxf(plant_height * 0.28, 1.5)
			return [join + near * 0.1, near * 1.5, 0.0]
	return [plant_height * 0.45, maxf(plant_height * 1.8, 1.2), 0.15]


func _place_orbit_camera() -> void:
	var framing := _view_framing()
	var target := _cell(focus_row, focus_column) + Vector3(0.0, framing[0], 0.0)
	var distance := framing[1] * _zoom
	var offset := Vector3(sin(_orbit_yaw) * cos(_orbit_pitch), sin(_orbit_pitch),
			cos(_orbit_yaw) * cos(_orbit_pitch)) * distance
	_camera.position = target + offset
	_camera.position.y = maxf(_camera.position.y, 0.05) # not under the ground
	_camera.look_at(target, Vector3.UP)


func _place_overview_camera() -> void:
	# from above and in front, so every row shows over the one before it
	var width := float(COLUMNS - 1) * _gap
	var centre := Vector3(0.0, _tallest * 0.3,
			-float(maxi(_species.size() - 1, 0)) * _row_gap * 0.5)
	var back := maxf(width * 0.62, _tallest * 2.4) + float(_species.size()) * _row_gap * 0.35
	_camera.position = centre + Vector3(0.0, back * 0.55, back * 0.85)
	_camera.look_at(centre, Vector3.UP)


## Remembers where this view puts the camera; a free camera stays where it is.
func _finish_framing() -> void:
	_frame_pose = _camera.global_transform
	if free_camera:
		_camera.global_transform = _free_pose


func _sync_mouse() -> void:
	var captured := _orbiting() and _mouse_turns and not free_camera
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


func _set_free_camera(on: bool) -> void:
	free_camera = on
	_flying = false
	if on:
		_free_pose = _camera.global_transform
		_yaw = _camera.rotation.y
		_pitch = _camera.rotation.x
	else:
		_camera.global_transform = _frame_pose
	_sync_mouse()


## The view's own angle and distance again (and the free camera back on the view).
func _reset_camera() -> void:
	_orbit_yaw = 0.4
	_orbit_pitch = _view_framing()[2] if _orbiting() else 0.15
	_zoom = 1.0
	_show_view()
	_free_pose = _frame_pose
	_camera.global_transform = _frame_pose
	_yaw = _camera.rotation.y
	_pitch = _camera.rotation.x


## Steps to the previous / next individual through every plant of every row.
func _step_individual(step: int) -> void:
	var count := _species.size() * COLUMNS
	if count == 0:
		return
	var index := posmod(focus_row * COLUMNS + focus_column + step, count)
	focus_row = index / COLUMNS
	focus_column = index % COLUMNS


func _process(delta: float) -> void:
	if not free_camera:
		return
	var move := Vector3(
			float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
			float(Input.is_key_pressed(KEY_E)) - float(Input.is_key_pressed(KEY_Q)),
			float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
	if move == Vector3.ZERO:
		return
	var fast := 3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
	var world_move := _camera.global_basis * Vector3(move.x, 0.0, move.z) + Vector3.UP * move.y
	_camera.global_position += world_move.normalized() * _fly_speed * fast * delta
	_free_pose = _camera.global_transform


func _unhandled_input(event: InputEvent) -> void:
	if free_camera:
		_free_camera_input(event)
	elif _orbiting():
		_orbit_input(event)


func _orbit_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = maxf(_zoom * 0.9, 0.15)
			_show_view()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = minf(_zoom * 1.1, 5.0)
			_show_view()
	var motion := event as InputEventMouseMotion
	if motion != null and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		_orbit_yaw -= motion.relative.x * TURN_SPEED
		_orbit_pitch = clampf(_orbit_pitch + motion.relative.y * TURN_SPEED, -0.3, 1.45)
		_place_orbit_camera()
		_finish_framing()


func _free_camera_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		if button.button_index == MOUSE_BUTTON_RIGHT:
			_flying = button.pressed
			Input.mouse_mode = (Input.MOUSE_MODE_CAPTURED if _flying
					else Input.MOUSE_MODE_VISIBLE)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_fly_speed = minf(_fly_speed * 1.25, 200.0)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_fly_speed = maxf(_fly_speed / 1.25, 0.2)
	var motion := event as InputEventMouseMotion
	if motion != null and _flying:
		_yaw -= motion.relative.x * 0.003
		_pitch = clampf(_pitch - motion.relative.y * 0.003, -1.5, 1.5)
		_camera.rotation = Vector3(_pitch, _yaw, 0.0)
		_free_pose = _camera.global_transform


func _update_label() -> void:
	var where := ""
	if _orbiting():
		var one := _species[focus_row]
		var crown := ""
		if form == PlantSpecies.Form.BROADLEAF:
			crown = " (new crown)" if PlantCrownBuilders.supports(one) else " (old crown)"
			crown += " leaf: %s" % PlantSpecies.LeafShape.keys()[one.leaf_shape].to_lower()
			if kind >= 0:
				crown += " as %s" % KINDS[kind]
		where = "  %s: %s%s  plant %d of %d" % [View.keys()[view].to_lower(), one.common_name, crown,
				focus_row * COLUMNS + focus_column + 1, _species.size() * COLUMNS]
	_label.text = ("%s  world seed %d  %s%s  %d species  wind: %s%s%s\n"
			+ "[Left / Right] plant  [Up / Down] species  [mouse] turn around it  [wheel] zoom  "
			+ "[M] mouse free\n"
			+ "[C] view  [F] form  [G] new species  [V] new individuals  [L] realistic  [U] autumn"
			+ "  [T] wind  [H] leaves  [R] reset camera\n"
			+ "[X] free camera: W A S D fly, Q down, E up, Shift fast, wheel speed, "
			+ "hold right mouse to look") % [
			PlantSpecies.Form.keys()[form], world_seed, "realistic" if detailed else "low-poly",
			"  autumn" if autumn else "", _species.size(), ["calm", "breeze", "gale"][wind],
			"  FREE CAMERA" if free_camera else "", where]


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if free_camera and key.keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E]:
		return # these fly the camera in free mode (the lab's A and D wait; L and U do the same)
	var forms := PlantSpecies.Form.size()
	var rebuild := false
	match key.keycode:
		KEY_F:
			form = ((form + (forms - 1 if key.shift_pressed else 1)) % forms) as PlantSpecies.Form
			_generate_species()
			rebuild = true
		KEY_G:
			world_seed = randi() % 100000
			_generate_species()
			rebuild = true
		KEY_V:
			_roll_variants()
			rebuild = true
		KEY_D, KEY_L:
			detailed = not detailed
			rebuild = true
		KEY_A, KEY_U:
			autumn = not autumn
		KEY_T:
			wind = (wind + 1) % 3
		KEY_H:
			leafless = not leafless
			rebuild = true
		KEY_K:
			kind = (kind + 2) % (KINDS.size() + 1) - 1
			_generate_species()
			rebuild = true
		KEY_C:
			view = ((view + 1) % View.size()) as View
		KEY_X:
			_set_free_camera(not free_camera)
		KEY_R:
			_reset_camera()
			return
		KEY_M, KEY_ESCAPE:
			_mouse_turns = key.keycode == KEY_M and not _mouse_turns
		KEY_LEFT:
			_step_individual(-1)
		KEY_RIGHT:
			_step_individual(1)
		KEY_UP:
			focus_row = maxi(focus_row - 1, 0)
		KEY_DOWN:
			focus_row = mini(focus_row + 1, maxi(_species.size() - 1, 0))
		_:
			return
	if rebuild:
		_rebuild()
	else:
		_show_view()
