class_name CeilingTileGrid
extends Node3D
## Real physical ceiling tile panels sitting in a distinct grid-colored
## backing, instead of a painted-on seam line: the backing (a genuinely
## different material, like a drop ceiling's metal T-bar grid) peeks through
## the small gap around every panel. The height difference between panel and
## backing is kept to ~1cm on purpose - just enough to be real geometry, not
## enough to draw a noticeable raking-light shadow line at typical viewing
## distance. Panels are placed via MultiMesh since a full room can need
## thousands of them (3600 for the 36x36m main hall) - individual CSG/Mesh
## nodes per tile would bloat the scene tree and draw calls.
##
## Local origin is the flush mount point against the room's structural
## ceiling (a separate solid CSG box elsewhere provides collision); both the
## backing and the tile panels hang below it (-Y), matching the convention
## used by ceiling_vent.tscn and the light fixture panels, since anything
## placed above local Y=0 would be buried inside that solid collision box
## and invisible from below.

@export var width: float = 36.0
@export var depth: float = 36.0
@export var tile_size: float = 1.2
@export var tile_gap: float = 0.04
@export var tile_thickness: float = 0.004
@export var backing_thickness: float = 0.006
@export var tile_material: Material
@export var grid_material: Material


func _ready() -> void:
	_build_backing()
	_build_tiles()


func _build_backing() -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, backing_thickness, depth)
	mesh_instance.mesh = box
	mesh_instance.material_override = grid_material
	mesh_instance.position = Vector3(0.0, -backing_thickness * 0.5, 0.0)
	add_child(mesh_instance)


func _build_tiles() -> void:
	var panel_size := tile_size - tile_gap
	var box := BoxMesh.new()
	box.size = Vector3(panel_size, tile_thickness, panel_size)

	var cols := int(round(width / tile_size))
	var rows := int(round(depth / tile_size))

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = box
	multimesh.instance_count = cols * rows

	var start_x := -width * 0.5 + tile_size * 0.5
	var start_z := -depth * 0.5 + tile_size * 0.5
	var y := -backing_thickness - tile_thickness * 0.5

	var index := 0
	for row in rows:
		for col in cols:
			var x := start_x + col * tile_size
			var z := start_z + row * tile_size
			multimesh.set_instance_transform(index, Transform3D(Basis(), Vector3(x, y, z)))
			index += 1

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = multimesh
	mmi.material_override = tile_material
	add_child(mmi)
