class_name CharacterEditorGizmoHandler
extends RefCounted

## Bone gizmo and object-transform interaction: rotation rings, bone
## sliders, mesh visibility/skeleton refresh, mouse-drag bone picking.
## Holds a back-reference to the main CharacterEditor - extracted purely
## to keep character_editor.gd under a manageable size.

const BONE_DEBUG_COLORS := {
	&"root": Color(1.0, 0.47, 0.16, 0.82),
	&"hips": Color(1.0, 0.72, 0.12, 0.82),
	&"spine": Color(0.22, 0.78, 1.0, 0.78),
	&"head": Color(1.0, 0.78, 0.24, 0.82),
	&"arm": Color(0.2, 0.58, 1.0, 0.78),
	&"finger": Color(1.0, 0.5, 0.18, 0.82),
	&"leg": Color(0.63, 0.42, 1.0, 0.78),
	&"other": Color(0.12, 0.72, 0.95, 0.78),
}

var editor: CharacterEditor


func _init(editor_ref: CharacterEditor) -> void:
	editor = editor_ref


func make_bone_segment_mesh() -> ArrayMesh:
	const RADIAL_SEGMENTS := 12
	# Y is normalized to one unit so each instance can scale to its bone length.
	# Narrow tips disappear into the joint spheres; the flared shoulders and
	# slim center make the overlay read as an anatomical bone instead of a pipe.
	var profile: Array[Vector2] = [
		Vector2(-0.5, 0.55),
		Vector2(-0.46, 1.6),
		Vector2(-0.38, 2.1),
		Vector2(-0.2, 0.85),
		Vector2(0.2, 0.85),
		Vector2(0.38, 2.1),
		Vector2(0.46, 1.6),
		Vector2(0.5, 0.55),
	]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for ring: Vector2 in profile:
		for radial_index in RADIAL_SEGMENTS:
			var angle := TAU * float(radial_index) / float(RADIAL_SEGMENTS)
			var radial := Vector3(cos(angle), 0.0, sin(angle))
			vertices.append(Vector3(
					radial.x * editor.BONE_RADIUS * ring.y,
					ring.x,
					radial.z * editor.BONE_RADIUS * ring.y))
			normals.append(radial)
	for ring_index in profile.size() - 1:
		var current_start := ring_index * RADIAL_SEGMENTS
		var next_start := (ring_index + 1) * RADIAL_SEGMENTS
		for radial_index in RADIAL_SEGMENTS:
			var following := (radial_index + 1) % RADIAL_SEGMENTS
			indices.append_array(PackedInt32Array([
				current_start + radial_index,
				next_start + radial_index,
				current_start + following,
				current_start + following,
				next_start + radial_index,
				next_start + following,
			]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_debug_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _make_debug_mesh_instance(mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _setup_bone_debug_materials() -> void:
	editor._bone_section_materials.clear()
	editor._joint_section_materials.clear()
	for section: StringName in BONE_DEBUG_COLORS:
		var color: Color = BONE_DEBUG_COLORS[section]
		editor._bone_section_materials[section] = _make_debug_material(color)
		editor._joint_section_materials[section] = _make_debug_material(
				Color(color.r, color.g, color.b, 0.96))


func _on_bone_slider_changed(value: float, bone_name: StringName, axis: int,
		value_label: Label) -> void:
	var rotation := editor._modifier.get_bone_rotation(bone_name)
	rotation[axis] = value
	editor._modifier.set_bone_rotation(bone_name, rotation)
	value_label.text = "%s  %+.0f" % ["XYZ"[axis], value]
	_refresh_skeleton()
	_update_bone_gizmo()


func _on_bone_row_gui_input(event: InputEvent, bone_name: StringName) -> void:
	if (event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed):
		if not editor.show_bones_toggle.button_pressed:
			editor.show_bones_toggle.set_pressed_no_signal(true)
			_on_show_bones_toggled(true)
		_select_bone(bone_name, true)
		editor.status_label.text = "%s selected; drag an X, Y, or Z ring" % (
				editor._bone_controls_handler._display_bone_name(bone_name))
		editor.get_viewport().set_input_as_handled()


func _select_bone(bone_name: StringName, focus_joint: bool) -> void:
	editor._selected_bone = bone_name
	editor._rig_handler.on_bone_selected(bone_name)
	editor._bone_controls_handler._expand_section_for_bone(bone_name)
	if bone_name in [&"RightHand", &"LeftHand"]:
		editor._bone_controls_handler._expand_finger_sections(String(bone_name).trim_suffix("Hand"))
	editor._bone_controls_handler._update_selected_bone_ui()
	editor._bone_controls_handler._update_pose_helpers()
	_update_bone_gizmo()
	if focus_joint:
		editor._joint_focus_active = true
		if not editor.free_camera_toggle.button_pressed:
			editor._camera_handler._frame_selected_joint()
	var controls: Dictionary = editor._bone_slider_controls.get(bone_name, {})
	if not controls.is_empty():
		editor.bone_scroll.call_deferred(&"ensure_control_visible", controls["row"])


func _set_bone_axis_from_gizmo(bone_name: StringName, axis: int, value: float) -> void:
	var rotation := editor._modifier.get_bone_rotation(bone_name)
	rotation[axis] = wrapf(value, -180.0, 180.0)
	editor._modifier.set_bone_rotation(bone_name, rotation)
	var controls: Dictionary = editor._bone_slider_controls.get(bone_name, {})
	if not controls.is_empty():
		var sliders: Array = controls["sliders"]
		var labels: Array = controls["labels"]
		(sliders[axis] as HSlider).set_value_no_signal(rotation[axis])
		(labels[axis] as Label).text = "%s  %+.0f" % ["XYZ"[axis], rotation[axis]]
	_refresh_skeleton()
	_update_bone_gizmo()


func _on_show_bones_toggled(enabled: bool) -> void:
	editor._bone_debug_root.visible = enabled
	if enabled:
		_update_bone_gizmo()


func _on_axis_ring_toggled(_enabled: bool, axis: int) -> void:
	if editor._drag_axis == axis and not editor.axis_ring_toggles[axis].button_pressed:
		editor._drag_axis = -1
	_update_bone_gizmo()


func _rebuild_bone_gizmo() -> void:
	if editor._bone_debug_root == null:
		return
	for instance: MeshInstance3D in editor._joint_instances.values():
		instance.queue_free()
	for instance: MeshInstance3D in editor._bone_segments.values():
		instance.queue_free()
	editor._joint_instances.clear()
	editor._bone_segments.clear()
	editor._visible_bone_indices.clear()
	var visible_set := {}
	for bone_index in editor.body.skeleton.get_bone_count():
		editor._visible_bone_indices.append(bone_index)
		visible_set[bone_index] = true
	for bone_index in editor._visible_bone_indices:
		var bone_name := editor.body.skeleton.get_bone_name(bone_index)
		var group := _bone_visual_group(bone_name)
		var joint_material: Material = editor._joint_section_materials.get(
				group, editor._joint_material)
		var joint := _make_debug_mesh_instance(editor._joint_mesh, joint_material)
		joint.name = StringName("Joint_%s" % bone_name)
		editor._joint_instances[bone_index] = joint
		editor._bone_debug_root.add_child(joint)
		var parent_index := editor.body.skeleton.get_bone_parent(bone_index)
		if visible_set.has(parent_index) and not _is_technical_root(parent_index):
			var segment_material: Material = editor._bone_section_materials.get(
					group, editor._bone_segment_material)
			var segment := _make_debug_mesh_instance(
					editor._bone_segment_mesh, segment_material)
			segment.name = StringName("Bone_%s" % bone_name)
			editor._bone_segments[bone_index] = segment
			editor._bone_debug_root.add_child(segment)
	_update_bone_gizmo()


func _update_bone_gizmo() -> void:
	if editor._bone_debug_root == null or not editor.show_bones_toggle.button_pressed:
		return
	var selected_index := editor.body.skeleton.find_bone(editor._selected_bone)
	for bone_index in editor._visible_bone_indices:
		var pose := editor.body.skeleton.get_bone_global_pose(bone_index)
		var bone_name := editor.body.skeleton.get_bone_name(bone_index)
		var group := _bone_visual_group(bone_name)
		var joint: MeshInstance3D = editor._joint_instances[bone_index]
		joint.position = pose.origin
		var selected := bone_index == selected_index
		joint.material_override = (
				editor._selected_joint_material
				if selected
				else editor._joint_section_materials.get(group, editor._joint_material)
		)
		var radius_scale := editor.SELECTED_JOINT_RADIUS / editor.JOINT_RADIUS if selected else 1.0
		if _is_technical_root(bone_index):
			joint.scale = Vector3(2.4, 0.22, 2.4) * radius_scale
		else:
			joint.scale = Vector3.ONE * radius_scale * _joint_visual_scale(bone_name)
		if editor._bone_segments.has(bone_index):
			var parent_index := editor.body.skeleton.get_bone_parent(bone_index)
			var parent_position := editor.body.skeleton.get_bone_global_pose(parent_index).origin
			var offset := pose.origin - parent_position
			var segment: MeshInstance3D = editor._bone_segments[bone_index]
			segment.material_override = (
					editor._selected_bone_material
					if selected
					else editor._bone_section_materials.get(group, editor._bone_segment_material)
			)
			segment.position = parent_position + offset * 0.5
			if offset.length_squared() > 0.000001:
				var width_scale := _bone_visual_scale(bone_name)
				segment.basis = Basis(Quaternion(Vector3.UP, offset.normalized())).scaled_local(
						Vector3(width_scale, offset.length(), width_scale))
	_update_rotation_rings(selected_index)


func _bone_visual_group(bone_name: StringName) -> StringName:
	var normalized := String(bone_name).to_lower().replace("_", "")
	var group := &"other"
	for finger_name: String in ["thumb", "index", "middle", "ring", "pinky", "little"]:
		if normalized.contains(finger_name):
			group = &"finger"
			break
	if group == &"other":
		if normalized.ends_with("root"):
			group = &"root"
		elif normalized.contains("hips") or normalized.contains("pelvis"):
			group = &"hips"
		elif normalized.contains("neck") or normalized.contains("head"):
			group = &"head"
		elif normalized.contains("spine") or normalized.contains("chest"):
			group = &"spine"
		elif _contains_any(normalized, ["upleg", "thigh", "leg", "calf", "foot", "toe"]):
			group = &"leg"
		elif _contains_any(normalized, ["shoulder", "arm", "forearm", "hand", "wrist"]):
			group = &"arm"
	return group


func _is_technical_root(bone_index: int) -> bool:
	if bone_index < 0 or editor.body.skeleton.get_bone_parent(bone_index) >= 0:
		return false
	var normalized := String(editor.body.skeleton.get_bone_name(bone_index)).to_lower()
	if not normalized.ends_with("root"):
		return false
	for child_index in editor.body.skeleton.get_bone_count():
		if editor.body.skeleton.get_bone_parent(child_index) != bone_index:
			continue
		var child_name := String(editor.body.skeleton.get_bone_name(child_index)).to_lower()
		if child_name.contains("hips") or child_name.contains("pelvis"):
			return true
	return false


func _contains_any(value: String, candidates: Array[String]) -> bool:
	for candidate: String in candidates:
		if value.contains(candidate):
			return true
	return false


func _joint_visual_scale(bone_name: StringName) -> float:
	var group := _bone_visual_group(bone_name)
	if group == &"finger":
		return 0.48
	if String(bone_name).to_lower().contains("toe"):
		return 0.62
	if group in [&"root", &"hips"]:
		return 1.0
	return 1.0


func _bone_visual_scale(bone_name: StringName) -> float:
	var group := _bone_visual_group(bone_name)
	if group == &"finger":
		return 0.48
	if String(bone_name).to_lower().contains("toe"):
		return 0.62
	return 1.0


func _rotation_ring_scale(bone_name: StringName) -> float:
	var normalized := String(bone_name).to_lower().replace("_", "")
	var group := _bone_visual_group(bone_name)
	var ring_scale := 0.68
	if group == &"finger":
		ring_scale = 0.28
	elif normalized.contains("hand") or normalized.contains("wrist"):
		ring_scale = 0.45
	elif normalized.contains("foot") or normalized.contains("toe"):
		ring_scale = 0.45
	elif group == &"root":
		ring_scale = 0.8
	elif group == &"hips":
		ring_scale = 0.7
	elif group in [&"arm", &"leg", &"head"]:
		ring_scale = 0.58
	return ring_scale


func _update_rotation_rings(selected_index: int) -> void:
	var rings_visible := selected_index >= 0 and selected_index in editor._visible_bone_indices
	for axis in 3:
		editor._rotation_rings[axis].visible = (
				rings_visible and editor.axis_ring_toggles[axis].button_pressed)
	if not rings_visible:
		return
	var pose := editor.body.skeleton.get_bone_global_pose(selected_index)
	var bone_name := editor.body.skeleton.get_bone_name(selected_index)
	var bone_basis := pose.basis.orthonormalized()
	var ring_scale := _rotation_ring_scale(bone_name)
	var axis_rotations := [
		Basis.from_euler(Vector3(0.0, 0.0, -PI * 0.5)),
		Basis.IDENTITY,
		Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)),
	]
	for axis in 3:
		editor._rotation_rings[axis].position = pose.origin
		editor._rotation_rings[axis].basis = bone_basis * axis_rotations[axis]
		editor._rotation_rings[axis].scale = Vector3.ONE * ring_scale


func _on_object_position_changed(value: float, axis: int) -> void:
	if editor._syncing_controls:
		return
	var position := editor._held_object.position
	position[axis] = value
	editor._held_object.position = position
	editor.position_values[axis].text = "%+.3f" % value
	_refresh_skeleton()


func _on_object_rotation_changed(value: float, axis: int) -> void:
	if editor._syncing_controls:
		return
	var rotation := editor._held_object.rotation_degrees
	rotation[axis] = value
	editor._held_object.rotation_degrees = rotation
	editor.rotation_values[axis].text = "%+.1f" % value
	_refresh_skeleton()


func _on_object_scale_changed(value: float) -> void:
	if editor._syncing_controls:
		return
	editor._held_object.scale = Vector3.ONE * value
	editor.scale_value.text = "%.3f" % value


func _refresh_skeleton() -> void:
	# The preview animation is deliberately paused. Explicitly advance the
	# modifier stack so UI edits update the skinned mesh immediately.
	editor.body.skeleton.advance(0.0)


func _sync_object_controls() -> void:
	editor._syncing_controls = true
	for axis in 3:
		editor.position_sliders[axis].value = editor._held_object.position[axis]
		editor.position_values[axis].text = "%+.3f" % editor._held_object.position[axis]
		editor.rotation_sliders[axis].value = editor._held_object.rotation_degrees[axis]
		editor.rotation_values[axis].text = "%+.1f" % editor._held_object.rotation_degrees[axis]
	editor.scale_slider.value = editor._held_object.scale.x
	editor.scale_value.text = "%.3f" % editor._held_object.scale.x
	editor.object_path_field.text = editor._current_object_path
	editor.preset_path_field.text = editor._current_pose_path
	editor._syncing_controls = false


## Finds the closest bone gizmo dot/segment to a screen position, among the
## currently visible bones - the pure picking logic behind
## _select_character_bone_at (which additionally applies pose-stage
## selection side effects below: editor._selected_bone, a
## pose-editing-specific status message). Returns "" if nothing is within
## CHARACTER_PICK_RADIUS_PIXELS - used as-is (no side effects) by Build
## Custom Rig mode's "click an existing bone to set its parent" picking.
func _bone_at_screen_position(mouse_position: Vector2) -> StringName:
	var closest_index := -1
	var closest_distance := editor.CHARACTER_PICK_RADIUS_PIXELS
	for bone_index in editor._visible_bone_indices:
		var world_position := editor.body.skeleton.to_global(
				editor.body.skeleton.get_bone_global_pose(bone_index).origin)
		if editor.camera.is_position_behind(world_position):
			continue
		var distance := editor.camera.unproject_position(world_position).distance_to(mouse_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_index = bone_index
		var parent_index := editor.body.skeleton.get_bone_parent(bone_index)
		if parent_index < 0 or parent_index not in editor._visible_bone_indices:
			continue
		var parent_world_position := editor.body.skeleton.to_global(
				editor.body.skeleton.get_bone_global_pose(parent_index).origin)
		if editor.camera.is_position_behind(parent_world_position):
			continue
		var segment_distance := _screen_point_segment_distance(
				mouse_position,
				editor.camera.unproject_position(parent_world_position),
				editor.camera.unproject_position(world_position))
		if segment_distance < closest_distance:
			closest_distance = segment_distance
			closest_index = bone_index
	if closest_index < 0:
		return &""
	return editor.body.skeleton.get_bone_name(closest_index)


func _select_character_bone_at(mouse_position: Vector2) -> bool:
	var bone_name := _bone_at_screen_position(mouse_position)
	if bone_name == &"":
		return false
	_select_bone(bone_name, true)
	editor.status_label.text = "%s selected; drag an X, Y, or Z ring" % (
			editor._bone_controls_handler._display_bone_name(editor._selected_bone))
	return true


func _screen_point_segment_distance(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment := end - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(start)
	var amount := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * amount)


func _begin_ring_drag(mouse_position: Vector2) -> bool:
	var selected_index := editor.body.skeleton.find_bone(editor._selected_bone)
	if selected_index < 0 or selected_index not in editor._visible_bone_indices:
		return false
	var pose := editor.body.skeleton.get_bone_global_pose(selected_index)
	var center := editor.body.skeleton.to_global(pose.origin)
	var bone_basis := pose.basis.orthonormalized()
	var ring_scale := _rotation_ring_scale(editor._selected_bone)
	var ring_radius := editor.ROTATION_RING_RADIUS * ring_scale
	var ray_origin := editor.camera.project_ray_origin(mouse_position)
	var ray_direction := editor.camera.project_ray_normal(mouse_position)
	var best_axis := -1
	var best_error := editor.RING_PICK_TOLERANCE * maxf(ring_scale, 0.6)
	var best_hit := Vector3.ZERO
	var best_normal := Vector3.ZERO
	for axis in 3:
		if not editor.axis_ring_toggles[axis].button_pressed:
			continue
		var local_axis: Vector3 = bone_basis[axis]
		var world_axis := (editor.body.skeleton.global_basis * local_axis).normalized()
		var hit = Plane(world_axis, center).intersects_ray(ray_origin, ray_direction)
		if hit == null:
			continue
		var hit_position: Vector3 = hit
		var radius_error := absf(hit_position.distance_to(center) - ring_radius)
		if radius_error < best_error:
			best_error = radius_error
			best_axis = axis
			best_hit = hit_position
			best_normal = world_axis
	if best_axis < 0:
		return false
	editor._drag_axis = best_axis
	editor._drag_center = center
	editor._drag_plane_normal = best_normal
	editor._drag_start_vector = (best_hit - center).normalized()
	editor._drag_start_rotation = editor._modifier.get_bone_rotation(editor._selected_bone)
	editor.status_label.text = "Dragging %s %s axis" % [
		editor._bone_controls_handler._display_bone_name(editor._selected_bone), "XYZ"[editor._drag_axis]]
	return true


func _drag_rotation_ring(mouse_position: Vector2) -> void:
	var ray_origin := editor.camera.project_ray_origin(mouse_position)
	var ray_direction := editor.camera.project_ray_normal(mouse_position)
	var hit = Plane(editor._drag_plane_normal, editor._drag_center).intersects_ray(
			ray_origin, ray_direction)
	if hit == null:
		return
	var current_vector := ((hit as Vector3) - editor._drag_center).normalized()
	if current_vector.is_zero_approx():
		return
	var angle_delta := editor._drag_start_vector.signed_angle_to(
			current_vector, editor._drag_plane_normal)
	_set_bone_axis_from_gizmo(editor._selected_bone, editor._drag_axis,
			editor._drag_start_rotation[editor._drag_axis] + rad_to_deg(angle_delta))
