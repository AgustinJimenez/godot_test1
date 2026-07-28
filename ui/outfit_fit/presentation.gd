class_name OutfitFitPresentation
extends RefCounted
## Character Creator material overrides for outfit fitting and clipping inspection.

const OUTFIT_COMPONENTS := preload("res://ui/outfit_fit/components.gd")


static func apply_body_debug_material(
	mesh_instance: MeshInstance3D,
	debug_colors: bool,
	show_clipping: bool,
	has_selection: bool,
) -> void:
	if not debug_colors:
		mesh_instance.material_override = null
		return
	if show_clipping and has_selection:
		# The rebuilt body mesh uses its authored material with per-vertex debug
		# tinting, allowing unaffected body areas to remain visually unchanged.
		mesh_instance.material_override = null
		return
	var material := debug_material(
			Color.WHITE if show_clipping else Color(0.9, 0.04, 0.04))
	material.vertex_color_use_as_albedo = show_clipping
	mesh_instance.material_override = material


## Outfit meshes include duplicate exposed skin. Hide those surfaces so the complete base body is
## the only skin source; color only clothing blue in diagnostic mode.
static func apply_outfit_materials(
	root: Node3D,
	discard_surface_shader: Shader,
	debug_colors: bool,
	show_clipping: bool,
	selected: Dictionary,
) -> void:
	var hidden_skin_material := ShaderMaterial.new()
	hidden_skin_material.shader = discard_surface_shader
	var clothes_material := debug_material(
			Color.WHITE if show_clipping else Color(0.03, 0.18, 0.95))
	clothes_material.vertex_color_use_as_albedo = show_clipping
	var filter_debug_surface := show_clipping and not selected.is_empty()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var mesh_key := String(root.get_path_to(mesh_instance))
		for rendered_surface_index in mesh_instance.mesh.get_surface_count():
			var source_surface_index := OUTFIT_COMPONENTS.source_surface_index(
					mesh_instance.mesh, rendered_surface_index)
			var source_material := mesh_instance.mesh.surface_get_material(
					rendered_surface_index)
			var material_name := ""
			if source_material != null:
				material_name = source_material.resource_name.to_lower()
			var is_skin := (
					"regular_male" in material_name or "regular_female" in material_name)
			if is_skin:
				mesh_instance.set_surface_override_material(
						rendered_surface_index, hidden_skin_material)
			elif debug_colors:
				var is_selected: bool = (
					not filter_debug_surface
					or (
						selected["mesh_key"] == mesh_key
						and selected["surface_index"] == source_surface_index
					)
				)
				mesh_instance.set_surface_override_material(
						rendered_surface_index,
						clothes_material if is_selected else null)
			else:
				mesh_instance.set_surface_override_material(rendered_surface_index, null)


static func debug_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.0
	material.roughness = 0.9
	return material
