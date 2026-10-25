class_name PlanetImpostors
extends Node
## Bakes the far trees' impostors (task 081, step 1). For each tree variant the lighter tree mesh is
## drawn from VIEWS angles round it, in turn, by a small orthographic camera into one atlas
## (planet_impostor.gdshader shows the nearest two). A tile built after a variant is baked hangs
## quads where it used to hang the lighter trees (PlanetScatter._light_trees). Needs a renderer.

const VIEWS := 8
const CELL := 160 ## pixels across one view
const VARIANTS := 2 ## the lighter versions a scatter uses (variant % 2)

var _registry: SpeciesRegistry
var _viewport: SubViewport
var _camera: Camera3D
var _holder: MeshInstance3D


## Starts baking every tree of `registry`, one view a frame.
func start(registry: SpeciesRegistry) -> void:
	if DisplayServer.get_name() == "headless" or OS.get_environment("NO_IMPOSTORS") != "":
		return
	_registry = registry
	_registry.impostors_expected = true
	if OS.get_environment("IMPOSTOR_DEBUG") != "":
		print("IMPOSTORS start ", registry.species.size())
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(CELL, CELL)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.positional_shadow_atlas_size = 0
	add_child(_viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.66, 0.72)
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.05
	_camera.far = 400.0
	_camera.environment = environment
	_viewport.add_child(_camera)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.9
	sun.shadow_enabled = false
	_viewport.add_child(sun)
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	_holder = MeshInstance3D.new()
	_holder.material_override = FloraMeshes.material()
	_viewport.add_child(_holder)
	_run.call_deferred()


func _run() -> void:
	for one in _registry.species:
		if not one.is_tree():
			continue
		for variant in VARIANTS:
			await _bake(one.id, variant)
	if OS.get_environment("IMPOSTOR_DEBUG") != "":
		print("IMPOSTORS baked at ", Time.get_ticks_msec(), " ms")


func _bake(id: int, variant: int) -> void:
	var mesh := _registry.mesh(id, variant, FloraMeshes.detailed, 1)
	var box := mesh.get_aabb()
	if box.size.y <= 0.1:
		return
	var reach := maxf(absf(box.position.x), absf(box.end.x))
	reach = maxf(reach, maxf(absf(box.position.z), absf(box.end.z)))
	var side := maxf(box.size.y, reach * 2.0) * 1.06
	var middle := box.position.y + box.size.y * 0.5
	_holder.mesh = mesh
	_camera.size = side
	var atlas := Image.create(CELL * (VIEWS + 1), CELL, false, Image.FORMAT_RGBA8) # (the last picture: from straight above)
	for view in VIEWS + 1:
		var angle := TAU * float(view) / float(VIEWS)
		var eye := Vector3(cos(angle), 0.0, sin(angle)) * 200.0 + Vector3(0.0, middle, 0.0)
		if view == VIEWS:
			_camera.look_at_from_position(Vector3(0.0, box.end.y + 200.0, 0.0), Vector3(0.0, middle, 0.0), Vector3(0.0, 0.0, -1.0))
		else:
			_camera.look_at_from_position(eye, Vector3(0.0, middle, 0.0))
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var picture := _viewport.get_texture().get_image()
		picture.convert(Image.FORMAT_RGBA8)
		atlas.blit_rect(picture, Rect2i(0, 0, CELL, CELL), Vector2i(view * CELL, 0))
	var maker: Object = ClassDB.instantiate(&"PlanetImprintNative")
	# (the see-through texels take the colour of the solid ones: no dark fringe when filtered)
	atlas = Image.create_from_data(atlas.get_width(), atlas.get_height(), false, Image.FORMAT_RGBA8,
			maker.call(&"bleed", atlas.get_data(), atlas.get_width(), atlas.get_height(), 3))
	atlas.generate_mipmaps()
	var quad := QuadMesh.new()
	quad.size = Vector2(side, side)
	quad.center_offset = Vector3(0.0, middle, 0.0)
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/world/planet_impostor.gdshader")
	material.set_shader_parameter(&"atlas", ImageTexture.create_from_image(atlas))
	material.set_shader_parameter(&"views", float(VIEWS))
	material.set_shader_parameter(&"middle", middle)
	_registry.set_impostor(id, variant, {"mesh": quad, "material": material})
	_swap(id, variant)
	if OS.get_environment("IMPOSTOR_DEBUG") != "":
		print("IMPOSTOR baked ", id, " ", variant, " at ", Time.get_ticks_msec())




## Replaces the lighter meshes that tiles hung before this variant was baked with impostor quads.
func _swap(id: int, variant: int) -> void:
	var baked := _registry.impostor(id, variant)
	if baked.is_empty():
		return
	for entry: Dictionary in _registry.take_waiting(id, variant):
		var old := instance_from_id(int(entry["instance"])) as MultiMeshInstance3D
		if old == null or old.get_parent() == null:
			continue
		var buffer: PackedFloat32Array = entry["buffer"]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = baked["mesh"] as Mesh
		multi.instance_count = buffer.size() / 16
		multi.buffer = buffer
		var quads := MultiMeshInstance3D.new()
		quads.multimesh = multi
		quads.material_override = baked["material"] as Material
		quads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		quads.visibility_range_begin = old.visibility_range_begin
		quads.visibility_range_end = old.visibility_range_end
		old.get_parent().add_child(quads)
		old.queue_free()
