class_name ObjectDefinition
extends Resource
## Catalog metadata for one reusable 3D object.

@export var id: StringName
@export var display_name: String
@export var category: StringName = &"Uncategorized"
@export var tags: PackedStringArray
@export var scene: PackedScene
@export var preview_scale: float = 1.0
@export var preview_rotation_degrees := Vector3.ZERO
@export var preview_offset := Vector3.ZERO


func matches(query: String, category_filter: StringName = &"") -> bool:
	if category_filter != &"" and category != category_filter:
		return false
	var normalized_query := query.strip_edges().to_lower()
	if normalized_query.is_empty():
		return true
	if normalized_query in display_name.to_lower() or normalized_query in String(id).to_lower():
		return true
	for tag in tags:
		if normalized_query in tag.to_lower():
			return true
	return false
