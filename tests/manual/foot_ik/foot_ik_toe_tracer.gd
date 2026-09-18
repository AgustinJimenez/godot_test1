extends RefCounted
## Per-foot toe path trails + side-coloured toe spheres for the manual IK preview, mirroring the
## stair lab's tracer (foot_ik_stair_lab.gd). Kept in its own file because foot_ik_debug_overlay.gd
## sits at the project's max-file-lines cap.
##
## The trail is drawn as a camera-facing ribbon, not a PRIMITIVE_LINES strip: Godot's primitive
## lines are always 1px with no material-line-width property (checked against StandardMaterial3D),
## so a ribbon is the only way to get a real, tunable thickness.
const MAX_POINTS := 1200 # 20s at 60fps, rolling window
const TRAIL_WIDTH := 0.02 # metres, half-width either side of the path
const SPHERE_RADIUS := 0.044
const SIDE_COLORS := {&"right": Color(1.0, 0.5, 0.0), &"left": Color(1.0, 0.9, 0.1)}
var _trail := {} # side -> PackedVector3Array
var _trail_mesh := {} # side -> ImmediateMesh
var _toe_sphere := {} # side -> MeshInstance3D, rigidly attached to the toe bone
var _parent: Node3D


func spawn(parent: Node3D, skeleton: Skeleton3D, ik: PlayerFootIKModifier) -> void:
	_parent = parent
	for side: StringName in SIDE_COLORS:
		var mesh := ImmediateMesh.new()
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		inst.material_override = _material(SIDE_COLORS[side], false)
		parent.add_child(inst)
		_trail[side] = PackedVector3Array()
		_trail_mesh[side] = mesh
		var toe_idx := _toe_index(ik, side)
		if toe_idx < 0:
			continue
		# Rigidly attached to the toe bone, so the sphere cannot lag the mesh the way a per-frame
		# position copy can.
		var attach := BoneAttachment3D.new()
		skeleton.add_child(attach)
		attach.bone_idx = toe_idx
		var sphere := SphereMesh.new()
		sphere.radius = SPHERE_RADIUS
		sphere.height = SPHERE_RADIUS * 2.0
		var marker := MeshInstance3D.new()
		marker.mesh = sphere
		marker.material_override = _material(SIDE_COLORS[side], true)
		attach.add_child(marker)
		_toe_sphere[side] = marker


## Append this frame's toe positions and redraw the ribbons. use_final_pose picks the modifier's
## published post-IK cache (a live IK leg); pass false for an IK-disabled character, whose modifier
## cache would be stale and whose animation pose is the skeleton's own. The spheres need no
## per-frame update - they ride the toe bone directly.
func append(skeleton: Skeleton3D, ik: PlayerFootIKModifier, use_final_pose := true) -> void:
	for side: StringName in _trail_mesh:
		var toe_idx := _toe_index(ik, side)
		if toe_idx < 0:
			continue
		var local := (ik.get_final_bone_global_pose(toe_idx).origin if use_final_pose
				else skeleton.get_bone_global_pose(toe_idx).origin)
		var points: PackedVector3Array = _trail[side]
		points.append(skeleton.global_transform * local)
		_trail[side] = points if points.size() <= MAX_POINTS else points.slice(-MAX_POINTS)
	_rebuild()


func clear() -> void:
	for side: StringName in _trail_mesh:
		_trail[side] = PackedVector3Array()
		(_trail_mesh[side] as ImmediateMesh).clear_surfaces()


func _rebuild() -> void:
	var eye := _camera_position()
	for side: StringName in _trail_mesh:
		var points: PackedVector3Array = _trail[side]
		var mesh: ImmediateMesh = _trail_mesh[side]
		mesh.clear_surfaces()
		if points.size() < 2:
			continue
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(1, points.size()):
			_add_ribbon_segment(mesh, points[i - 1], points[i], eye)
		mesh.surface_end()


## A quad per segment, widened perpendicular to both the segment and the view direction so it always
## faces the camera.
func _add_ribbon_segment(mesh: ImmediateMesh, a: Vector3, b: Vector3, eye: Vector3) -> void:
	var along := b - a
	if along.length_squared() < 0.0000001:
		return
	var to_eye := eye - a
	var width_axis := along.cross(to_eye)
	if width_axis.length_squared() < 0.0000001:
		width_axis = along.cross(Vector3.UP)
	if width_axis.length_squared() < 0.0000001:
		return
	var offset := width_axis.normalized() * TRAIL_WIDTH
	mesh.surface_add_vertex(a - offset)
	mesh.surface_add_vertex(a + offset)
	mesh.surface_add_vertex(b + offset)
	mesh.surface_add_vertex(a - offset)
	mesh.surface_add_vertex(b + offset)
	mesh.surface_add_vertex(b - offset)


func _camera_position() -> Vector3:
	if _parent != null and _parent.is_inside_tree():
		var camera := _parent.get_viewport().get_camera_3d()
		if camera != null:
			return camera.global_position
	return Vector3.UP * 100.0 # no camera (headless): widens against world up instead


func _toe_index(ik: PlayerFootIKModifier, side: StringName) -> int:
	return int((ik._bone_indices.get(side, {}) as Dictionary).get("toe", -1))


func _material(color: Color, no_depth: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = no_depth
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
