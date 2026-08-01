class_name PlayerSkeletonDebugVisualizer
extends SkeletonModifier3D
## Debug-menu "Show Skeleton" toggle: draws a distinctly-colored ribbon from
## every bone to its parent (see HUE_STEP), redrawn every frame from the
## *current* pose (after animation and every other modifier - hand grip, look
## pose, foot IK - have already run, same ordering trick those rely on:
## reading get_bone_global_pose() from inside a modifier's own
## _process_modification() sees the live, fully-corrected pose, unlike
## reading it from outside the modifier stack). The mesh renders with depth
## test disabled, so bones show up through the character's own mesh instead
## of being hidden behind it.

## Golden-ratio hue step so consecutive bone indices (usually parent/child
## down one chain) land on visually distinct hues instead of a smooth,
## hard-to-tell-apart gradient - the standard trick for deterministic,
## well-spread color sequences from a plain incrementing index.
const HUE_STEP := 0.6180339887
## Godot's Forward+ renderer doesn't honor GL-style line width, so a plain
## PRIMITIVE_LINES draw is always exactly 1px regardless of any material
## setting - too thin to read at a normal gameplay camera distance. Each bone
## segment is drawn as a camera-facing ribbon (a thin quad) instead, giving
## it a real, constant world-space width from any viewing angle.
const LINE_WIDTH := 0.008

var mesh_instance: MeshInstance3D
var _immediate_mesh: ImmediateMesh


func _ready() -> void:
	_immediate_mesh = ImmediateMesh.new()
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = &"SkeletonDebugLines"
	mesh_instance.mesh = _immediate_mesh
	# World-space vertices are fed directly each frame (see
	# _process_modification_with_delta()), so this node's own transform
	# should never move it - top_level plus leaving it at the scene
	# origin makes local space and world space the same thing here.
	mesh_instance.top_level = true
	mesh_instance.global_transform = Transform3D.IDENTITY
	mesh_instance.visible = false

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	# Each ribbon quad's winding order depends on the camera-relative side
	# vector computed per segment (see _add_ribbon_segment), so it isn't
	# consistently front-facing - disable culling rather than fight for a
	# winding convention that would still flip as the camera orbits.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = mat

	# A plain child of this modifier (not e.g. the scene root) - top_level
	# already makes its transform independent of the parent, and keeping it
	# a real child means it's freed automatically along with this modifier
	# (e.g. when swap_character() frees the old character subtree) instead
	# of needing separate cleanup tracking.
	add_child(mesh_instance)


func _process_modification_with_delta(_delta: float) -> void:
	if mesh_instance == null or not mesh_instance.visible:
		return
	var skel := get_skeleton()
	if skel == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var cam_pos := camera.global_position
	var to_world := skel.global_transform

	_immediate_mesh.clear_surfaces()
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for bone_idx in skel.get_bone_count():
		var parent_idx := skel.get_bone_parent(bone_idx)
		if parent_idx < 0:
			continue
		var bone_pos: Vector3 = to_world * skel.get_bone_global_pose(bone_idx).origin
		var parent_pos: Vector3 = to_world * skel.get_bone_global_pose(parent_idx).origin
		var color := Color.from_hsv(fmod(bone_idx * HUE_STEP, 1.0), 0.85, 1.0)
		_add_ribbon_segment(parent_pos, bone_pos, cam_pos, color)
	_immediate_mesh.surface_end()


## Two triangles forming a thin quad between `a` and `b`, offset sideways by
## half LINE_WIDTH along an axis perpendicular to both the segment itself and
## the direction to the camera - i.e. facing the camera, like a classic
## billboarded line/ribbon. Each bone gets its own deterministic color (see
## HUE_STEP) so adjacent segments in a chain are visually distinguishable -
## useful for spotting exactly which joint a kink/offset belongs to instead
## of a solid, undifferentiated skeleton outline.
func _add_ribbon_segment(a: Vector3, b: Vector3, cam_pos: Vector3, color: Color) -> void:
	var segment_dir := b - a
	if segment_dir.is_zero_approx():
		return
	segment_dir = segment_dir.normalized()
	var view_dir := ((a + b) * 0.5 - cam_pos).normalized()
	var side := segment_dir.cross(view_dir)
	if side.length_squared() < 0.0001:
		side = segment_dir.cross(Vector3.UP)
	side = side.normalized() * (LINE_WIDTH * 0.5)

	var a0 := a - side
	var a1 := a + side
	var b0 := b - side
	var b1 := b + side

	_immediate_mesh.surface_set_color(color)
	_immediate_mesh.surface_add_vertex(a0)
	_immediate_mesh.surface_add_vertex(b0)
	_immediate_mesh.surface_add_vertex(b1)
	_immediate_mesh.surface_add_vertex(a0)
	_immediate_mesh.surface_add_vertex(b1)
	_immediate_mesh.surface_add_vertex(a1)
