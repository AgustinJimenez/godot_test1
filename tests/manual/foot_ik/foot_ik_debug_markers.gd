class_name FootIkDebugMarkers
extends RefCounted
## Pure mesh-construction helpers for foot_ik_debug_overlay.gd's world-space
## gizmos (spheres, rays) - split out purely to keep the overlay itself under
## the project's max-file-lines cap; owns no state of its own.

const MARKER_RADIUS := 0.015


static func signed_knee_flexion(hip: Vector3, knee: Vector3, foot: Vector3,
		forward: Vector3) -> float:
	var upper := knee - hip
	var lower := foot - knee
	var flexion := rad_to_deg(upper.angle_to(lower))
	var line := foot - hip
	var along := clampf((knee - hip).dot(line) / line.length_squared(), 0.0, 1.0)
	var pole := knee - (hip + line * along)
	return flexion if pole.dot(forward) >= 0.0 else -flexion


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


## A trailing world-space tube (GPU-instanced cylinder segments, not a plain
## ImmediateMesh line strip - line width isn't controllable in Godot's
## renderer) showing the recent PATH a bone took, so a real shake reads as a
## visible zigzag instead of needing frame-by-frame log comparison.
## no_depth_test so it stays visible through the mesh.
const TRACE_RADIUS := 0.012

static func spawn_trace(parent: Node) -> MultiMeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.height = 1.0
	cylinder.material = mat
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = cylinder
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = multimesh
	parent.add_child(inst)
	return inst


## Per-frame turn angle sharp enough to read as fully red (a real snap, not
## ordinary gait sway).
const TRACE_ANGLE_MAX_DEG := 15.0


## points must be world-space (inst itself stays at identity transform). One
## cylinder segment per point pair, scaled from a unit cylinder via its own
## Basis (a shared MultiMesh mesh can't vary per-instance height/radius any
## other way). Color encodes how sharply the path bent AT each point
## (yellow = smooth, red = a sharp direction change), so a shake reads as a
## red spike right where it happened - not just a uniform-tint trail. Alpha
## still fades older points toward transparent so it reads as motion.
static func update_trace(inst: MultiMeshInstance3D, points: Array) -> void:
	var multimesh := inst.multimesh
	var segment_count := maxi(0, points.size() - 1)
	multimesh.instance_count = segment_count
	for i in segment_count:
		var from: Vector3 = points[i]
		var to: Vector3 = points[i + 1]
		var diff := to - from
		var length := diff.length()
		if length < 0.0001:
			multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), from))
			multimesh.set_instance_color(i, Color(0.0, 0.0, 0.0, 0.0))
			continue
		var up := diff.normalized()
		var arbitrary := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
		var basis_x := up.cross(arbitrary).normalized()
		var basis_z := basis_x.cross(up).normalized()
		var basis := Basis(basis_x * TRACE_RADIUS, up * length, basis_z * TRACE_RADIUS)
		multimesh.set_instance_transform(i, Transform3D(basis, (from + to) * 0.5))
		var age := float(i) / float(segment_count - 1) if segment_count > 1 else 1.0
		var rgb := _turn_color(points, i + 1)
		multimesh.set_instance_color(i, Color(rgb.r, rgb.g, rgb.b, age))


static func _turn_color(points: Array, i: int) -> Color:
	if i <= 0 or i >= points.size() - 1:
		return Color.YELLOW
	var incoming: Vector3 = points[i] - points[i - 1]
	var outgoing: Vector3 = points[i + 1] - points[i]
	if incoming.length_squared() < 0.000001 or outgoing.length_squared() < 0.000001:
		return Color.YELLOW
	var t := clampf(rad_to_deg(incoming.angle_to(outgoing)) / TRACE_ANGLE_MAX_DEG, 0.0, 1.0)
	return Color.YELLOW.lerp(Color.RED, t)


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


static func spawn_direction_arrow(parent: Node, color: Color) -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true

	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.012
	shaft_mesh.bottom_radius = 0.012
	shaft_mesh.height = 0.28
	shaft_mesh.material = mat
	shaft.mesh = shaft_mesh
	shaft.rotation.x = deg_to_rad(-90.0)
	shaft.position.z = -0.14
	root.add_child(shaft)

	var tip := MeshInstance3D.new()
	var tip_mesh := CylinderMesh.new()
	tip_mesh.top_radius = 0.0
	tip_mesh.bottom_radius = 0.04
	tip_mesh.height = 0.12
	tip_mesh.material = mat
	tip.mesh = tip_mesh
	tip.rotation.x = deg_to_rad(-90.0)
	tip.position.z = -0.34
	root.add_child(tip)

	parent.add_child(root)
	return root


static func update_direction_arrow(arrow: Node3D, base_pos: Vector3,
		velocity: Vector3, player_facing: Vector3, is_chest: bool = false) -> void:
	if arrow == null:
		return
	var h_vel := Vector3(velocity.x, 0.0, velocity.z)
	var dir := (h_vel.normalized() if (h_vel.length() > 0.1 and not is_chest)
			else player_facing)
	arrow.global_position = (base_pos + dir * 0.15) if is_chest else (base_pos + Vector3.UP * 0.28)
	if dir.length_squared() > 0.001:
		var target := arrow.global_position + dir
		arrow.look_at(target, Vector3.UP)


static func spawn_zone_quad(parent: Node, color: Color, size: Vector2) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	var mesh := QuadMesh.new()
	mesh.size = size
	mesh.orientation = PlaneMesh.FACE_Y
	mesh.material = mat
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	parent.add_child(inst)
	return inst
