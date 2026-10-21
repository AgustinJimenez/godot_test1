class_name PlanetImprinter
extends Node
## Takes the shape of whatever touches the sand from the real meshes (task 078). A small camera sits
## just under the ground, looks UP, and sees only a thin slab of the world above it (the ground
## itself is not seen from below: its faces turn away). What it sees there is the underside of the
## foot (or a shoe, a paw, a crate: any mesh, skinned or not). A depth quad turns each pixel into
## how high that underside is (planet_imprint_depth.gdshader); here the lowest point is found and
## every spot is given how deep it presses: the lowest 255, SINK higher 0. That picture is a PROFILE
## (PlanetDents keeps it, the ground shader works the print out of it).

const SLAB := 0.1 ## m of the world above the ground the camera sees
const SINK := 0.04 ## m: the part of the object within this of its lowest point presses the sand
const LAYER := 20 ## the visual layer of the depth quad (the main cameras do not draw it)
const NOTHING := 250 ## a grey level from here up is empty space
const REACH := 70 ## the lowest point must be within 2.7 cm of the ground (grey levels)

var _viewport: SubViewport
var _camera: Camera3D
var _busy := false


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(PlanetDents.TILE, PlanetDents.TILE)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.positional_shadow_atlas_size = 0
	add_child(_viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.WHITE
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = PlanetDents.SPAN
	_camera.near = 0.001
	_camera.far = SLAB
	_camera.environment = environment
	_viewport.add_child(_camera)
	var quad := MeshInstance3D.new()
	quad.mesh = QuadMesh.new()
	quad.layers = 1 << (LAYER - 1)
	quad.extra_cull_margin = 16384.0
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/world/planet_imprint_depth.gdshader")
	material.set_shader_parameter(&"slab", SLAB)
	quad.material_override = material
	quad.position = Vector3(0.0, 0.0, -SLAB * 0.5)
	_camera.add_child(quad)


## The profile of what touches the ground at world position `at` (its toe along `forward`, the
## ground's `up`): TILE x TILE bytes, or empty when nothing is within the slab above the ground (or
## another is being taken). A coroutine: it takes a frame.
func take(at: Vector3, forward: Vector3, up: Vector3) -> PackedByteArray:
	if _busy:
		return PackedByteArray()
	_busy = true
	var main := get_viewport().get_camera_3d()
	if main != null:
		main.set_cull_mask_value(LAYER, false) # (the depth quad is for the small camera only)
	_camera.global_transform = Transform3D(Basis.looking_at(up, forward), at - up * 0.004)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var picture := _viewport.get_texture().get_image()
	_busy = false
	if picture == null or picture.is_empty():
		return PackedByteArray()
	picture.convert(Image.FORMAT_RGBA8)
	return profile_of(picture.get_data())


## natively (PlanetImprintNative): the lowest point is the level the lowest few percent of pixels
## reach (a speck of a stray pixel does not count), and anything lower is left out.
## reach (a speck of a stray pixel does not count), and anything lower than that is left out.
static func profile_of(levels: PackedByteArray) -> PackedByteArray:
	var maker: Object = ClassDB.instantiate(&"PlanetImprintNative")
	return maker.call(&"profile_of", levels, PlanetDents.TILE, NOTHING, REACH,
			SINK / SLAB * 255.0)
