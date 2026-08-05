class_name FootIkDebugMarkers
extends RefCounted
## Pure mesh-construction helpers for foot_ik_debug_overlay.gd's world-space
## gizmos (spheres, rays) - split out purely to keep the overlay itself under
## the project's max-file-lines cap; owns no state of its own.

const MARKER_RADIUS := 0.015


static func spawn_marker(parent: Node, color: Color) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := SphereMesh.new()
	mesh.radius = MARKER_RADIUS
	mesh.height = MARKER_RADIUS * 2.0
	mesh.material = mat
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	parent.add_child(inst)
	return inst


## A visible line for the downward ground probe itself, not just its
## endpoints - the sphere markers alone don't show whether a miss searched
## the full idle_settle_search_down range or gave up early. no_depth_test so
## it stays visible through the leg/floor mesh, like the overlay's own angle
## labels.
static func spawn_ray(parent: Node, color: Color) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.008
	mesh.bottom_radius = 0.008
	mesh.height = 1.0
	mesh.material = mat
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	parent.add_child(inst)
	return inst


## Floating world-space text for one segment's angle - billboarded (always
## faces the camera) and depth-test disabled like the ray/skeleton ribbons,
## so the number stays readable through the mesh instead of disappearing
## behind it whenever the camera orbits to the far side.
static func spawn_angle_label(parent: Node) -> Label3D:
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
	parent.add_child(label)
	return label


static func update_ray_visual(inst: MeshInstance3D, from: Vector3, to: Vector3, hit: bool) -> void:
	var diff := to - from
	var length := diff.length()
	if length < 0.001:
		inst.visible = false
		return
	inst.visible = true
	var up := diff.normalized()
	var arbitrary := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var basis_x := up.cross(arbitrary).normalized()
	var basis_z := basis_x.cross(up).normalized()
	var mesh := inst.mesh as CylinderMesh
	mesh.height = length
	(mesh.material as StandardMaterial3D).albedo_color = Color.GREEN if hit else Color.RED
	inst.global_transform = Transform3D(Basis(basis_x, up, basis_z), (from + to) * 0.5)
