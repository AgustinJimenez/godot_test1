class_name ObjectCatalog
extends Resource
## Explicit collection of reusable object definitions.

@export var id: StringName
@export var display_name: String
@export var entries: Array[ObjectDefinition] = []


func categories() -> PackedStringArray:
	var unique: Dictionary[StringName, bool] = {}
	for entry in entries:
		if entry != null and entry.category != &"":
			unique[entry.category] = true
	var result := PackedStringArray()
	for category in unique:
		result.append(String(category))
	result.sort()
	return result


func filtered(query: String = "", category_filter: StringName = &"") -> Array[ObjectDefinition]:
	var result: Array[ObjectDefinition] = []
	for entry in entries:
		if entry != null and entry.matches(query, category_filter):
			result.append(entry)
	return result


func find_by_id(object_id: StringName) -> ObjectDefinition:
	for entry in entries:
		if entry != null and entry.id == object_id:
			return entry
	return null
