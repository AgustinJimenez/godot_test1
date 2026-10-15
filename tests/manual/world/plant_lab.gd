extends Node3D
## Generates plants at random and shows the results: one growth form at a time, a row per species,
## a column per random individual. Run the scene and use the keys:
##   F / Shift+F  next / previous growth form      G  a new random set of species (new seed)
##   V  new random individuals (same species)      D  low-poly / realistic meshes
##   A  autumn on / off     C  close-up of one row at eye level (Left / Right pick the individual,
##   Up / Down the species)
## Command line (after --): --form=CACTUS  --seed=N  --detailed

const PLANT_SCALE := {
	PlantSpecies.Form.CONIFER: 1.0, PlantSpecies.Form.BROADLEAF: 1.0, PlantSpecies.Form.PALM: 1.0,
	PlantSpecies.Form.BARE_TREE: 1.0, PlantSpecies.Form.SHRUB: 1.6, PlantSpecies.Form.CACTUS: 1.6,
	PlantSpecies.Form.GRASS: 2.0, PlantSpecies.Form.TALL_GRASS: 2.0, PlantSpecies.Form.REED: 2.0,
	PlantSpecies.Form.FLOWER: 2.2, PlantSpecies.Form.FERN: 2.2, PlantSpecies.Form.MUSHROOM: 2.2,
}
const COLUMNS := 6
const MAX_ROWS := 5

var form := PlantSpecies.Form.CACTUS
var world_seed := 1337
var detailed := false
var autumn := false
var closeup := false
var focus_row := 0
var focus_column := 0
var _species: Array[PlantSpecies] = []
var _variants: Array[int] = []
var _plants: Node3D
var _camera: Camera3D
var _label: Label
var _rows: Array[Node3D] = []


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
	_build_stage()
	_generate_species()
	_roll_variants()
	_show()


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
	focus_row = clampi(focus_row, 0, maxi(_species.size() - 1, 0))


func _roll_variants() -> void:
	_variants.clear()
	for index in COLUMNS:
		_variants.append(randi() % 1000000)


func _show() -> void:
	if _plants != null:
		_plants.queue_free()
	WorldWind.set_realism(1.0 if detailed else 0.0)
	WorldWind.set_autumn(1.0 if autumn else 0.0)
	_plants = Node3D.new()
	add_child(_plants)
	_rows.clear()
	var scale: float = PLANT_SCALE[form]
	var gap := 3.0 * scale if scale > 1.0 else 7.0
	var row_gap := gap * 1.4
	var tallest := 1.0
	for row in _species.size():
		var holder := Node3D.new()
		_plants.add_child(holder)
		_rows.append(holder)
		var one := _species[row]
		for column in COLUMNS:
			var instance := MeshInstance3D.new()
			instance.mesh = PlantMeshes.build(one, _variants[column], detailed)
			instance.material_override = FloraMeshes.material()
			instance.scale = Vector3.ONE * scale
			instance.position = _cell(row, column, gap, row_gap)
			holder.add_child(instance)
		var tag := Label3D.new()
		tag.text = "%s  (species %d)" % [one.common_name, one.id]
		tag.font_size = 48
		tag.pixel_size = 0.0016 * gap
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.position = _cell(row, -1, gap, row_gap) + Vector3(0.0, 0.3, 0.0)
		holder.add_child(tag)
		tallest = maxf(tallest, one.height * scale)
	_frame_camera(gap, row_gap, scale, tallest)
	_update_label()


func _cell(row: int, column: int, gap: float, row_gap: float) -> Vector3:
	return Vector3((float(column) - float(COLUMNS - 1) * 0.5) * gap, 0.0, -float(row) * row_gap)


func _frame_camera(gap: float, row_gap: float, scale: float, tallest: float) -> void:
	if closeup and not _species.is_empty():
		for row in _rows.size():
			_rows[row].visible = row == focus_row
		var at := _cell(focus_row, focus_column, gap, row_gap)
		_camera.position = at + Vector3(0.0, 1.5 * scale, 5.0 * scale)
		_camera.look_at(at + Vector3(0.0, 1.6 * scale, 0.0), Vector3.UP)
		return
	# from above and in front, so every row shows over the one before it
	var width := float(COLUMNS - 1) * gap
	var centre := Vector3(0.0, tallest * 0.3, -float(maxi(_species.size() - 1, 0)) * row_gap * 0.5)
	var back := maxf(width * 0.62, tallest * 2.4) + float(_species.size()) * row_gap * 0.35
	_camera.position = centre + Vector3(0.0, back * 0.55, back * 0.85)
	_camera.look_at(centre, Vector3.UP)


func _update_label() -> void:
	var where := "  close-up %d/%d" % [focus_row + 1, focus_column + 1] if closeup else ""
	_label.text = ("%s  world seed %d  %s%s  %d species%s\n[F] form  [G] new species  "
			+ "[V] new individuals  [D] realistic  [A] autumn  [C] close-up (arrows)") % [
			PlantSpecies.Form.keys()[form], world_seed, "realistic" if detailed else "low-poly",
			"  autumn" if autumn else "", _species.size(), where]


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var forms := PlantSpecies.Form.size()
	match key.keycode:
		KEY_F:
			form = ((form + (forms - 1 if key.shift_pressed else 1)) % forms) as PlantSpecies.Form
			_generate_species()
		KEY_G:
			world_seed = randi() % 100000
			_generate_species()
		KEY_V:
			_roll_variants()
		KEY_D:
			detailed = not detailed
		KEY_A:
			autumn = not autumn
		KEY_C:
			closeup = not closeup
		KEY_LEFT:
			focus_column = maxi(focus_column - 1, 0)
		KEY_RIGHT:
			focus_column = mini(focus_column + 1, COLUMNS - 1)
		KEY_UP:
			focus_row = maxi(focus_row - 1, 0)
		KEY_DOWN:
			focus_row = mini(focus_row + 1, maxi(_species.size() - 1, 0))
		_:
			return
	_show()
