extends Node3D

const BODY_SCENE := preload(
		"res://assets/models/imported_characters/8bcc06df-6c6e-42f0-b2c1-5f37ccf2b28b/"
		+ "Superhero_Male_FullBody.gltf")
const OUTFIT_SCENE := preload(
		"res://assets/models/modular_outfits_fantasy/Male_Peasant.gltf")
const DISCARD_SURFACE_SHADER := preload("res://shaders/discard_surface.gdshader")

const COLUMN_SPACING := 2.2
const ORBIT_SENSITIVITY := 0.008
const ZOOM_STEP := 0.6
const MIN_DISTANCE := 4.0
const MAX_DISTANCE := 14.0

@onready var camera: Camera3D = $Camera

var _orbit_yaw := 0.0
var _orbit_pitch := -0.05
var _orbit_distance := 4.2
var _orbiting := false


func _ready() -> void:
	_build_column(
			Vector3(-COLUMN_SPACING, 0.0, 0.0),
			"FULL BODY",
			true,
			false)
	_build_column(Vector3.ZERO, "CLOTHES ONLY", false, true)
	_build_column(
			Vector3(COLUMN_SPACING, 0.0, 0.0),
			"FULL BODY + CLOTHES",
			true,
			true)
	_update_camera()


func _build_column(
		position: Vector3,
	label_text: String,
	include_body: bool,
	include_outfit: bool,
) -> void:
	var column := Node3D.new()
	column.position = position
	$Models.add_child(column)
	if include_body:
		var body := BODY_SCENE.instantiate() as Node3D
		column.add_child(body)
		var body_mesh := body.find_child("SuperHero_Male", true, false) as MeshInstance3D
		body_mesh.material_override = _debug_material(Color(0.9, 0.04, 0.04))
	if include_outfit:
		var outfit := OUTFIT_SCENE.instantiate() as Node3D
		column.add_child(outfit)
		_apply_outfit_debug_materials(outfit)
	var label := Label3D.new()
	label.text = label_text
	label.position = Vector3(0.0, 2.25, 0.0)
	label.font_size = 34
	label.outline_size = 8
	label.modulate = Color.WHITE
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	column.add_child(label)


func _apply_outfit_debug_materials(root: Node3D) -> void:
	var hidden_skin_material := ShaderMaterial.new()
	hidden_skin_material.shader = DISCARD_SURFACE_SHADER
	var clothes_material := _debug_material(Color(0.03, 0.18, 0.95))
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for surface_index in mesh_instance.mesh.get_surface_count():
			var source_material := mesh_instance.mesh.surface_get_material(surface_index)
			var material_name := (
					source_material.resource_name.to_lower()
					if source_material != null else "")
			var is_skin := "regular_male" in material_name or "regular_female" in material_name
			mesh_instance.set_surface_override_material(
					surface_index, hidden_skin_material if is_skin else clothes_material)


func _debug_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_orbiting = button.pressed
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_distance = maxf(MIN_DISTANCE, _orbit_distance - ZOOM_STEP)
			_update_camera()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_distance = minf(MAX_DISTANCE, _orbit_distance + ZOOM_STEP)
			_update_camera()
	elif event is InputEventMouseMotion and _orbiting:
		var motion := event as InputEventMouseMotion
		_orbit_yaw -= motion.relative.x * ORBIT_SENSITIVITY
		_orbit_pitch = clampf(
				_orbit_pitch + motion.relative.y * ORBIT_SENSITIVITY,
				-deg_to_rad(55.0),
				deg_to_rad(55.0))
		_update_camera()


func _update_camera() -> void:
	var horizontal := cos(_orbit_pitch)
	camera.position = Vector3(
			sin(_orbit_yaw) * horizontal,
			sin(_orbit_pitch),
			cos(_orbit_yaw) * horizontal) * _orbit_distance + Vector3(0.0, 1.1, 0.0)
	camera.look_at(Vector3(0.0, 1.1, 0.0))
