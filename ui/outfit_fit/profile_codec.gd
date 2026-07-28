class_name OutfitFitProfileCodec
extends RefCounted
## Compact JSON conversion for the per-vertex contact-fit layer.


static func safe_id(value: String) -> String:
	var result := ""
	for character in value:
		result += character if character.is_valid_identifier() or character == "-" else "_"
	return result


static func encode_auto_offsets(
	auto_surface_offsets: Dictionary,
	mesh_states: Dictionary,
) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for mesh_key_variant in auto_surface_offsets:
		var mesh_key := String(mesh_key_variant)
		var mesh_offsets := auto_surface_offsets[mesh_key] as Array
		var surfaces: Array = mesh_states[mesh_key]["surfaces"]
		for surface_index in mesh_offsets.size():
			var offsets := mesh_offsets[surface_index] as PackedVector3Array
			var values := PackedFloat32Array()
			values.resize(offsets.size() * 3)
			var has_offset := false
			for vertex_index in offsets.size():
				var offset := offsets[vertex_index]
				values[vertex_index * 3] = offset.x
				values[vertex_index * 3 + 1] = offset.y
				values[vertex_index * 3 + 2] = offset.z
				has_offset = has_offset or not offset.is_zero_approx()
			if has_offset:
				records.append({
					"mesh": mesh_key,
					"surface": surface_index,
					"vertex_count": (surfaces[surface_index]["base_vertices"]
							as PackedVector3Array).size(),
					"xyz": values,
				})
	return records


static func decode_auto_offsets(
	records: Array,
	mesh_states: Dictionary,
	auto_surface_offsets: Dictionary,
) -> int:
	var loaded := 0
	for record_variant in records:
		var record := record_variant as Dictionary
		var mesh_key := String(record.get("mesh", ""))
		var surface_index := int(record.get("surface", -1))
		if not mesh_states.has(mesh_key) or not auto_surface_offsets.has(mesh_key):
			continue
		var mesh_offsets := auto_surface_offsets[mesh_key] as Array
		if surface_index < 0 or surface_index >= mesh_offsets.size():
			continue
		var offsets := mesh_offsets[surface_index] as PackedVector3Array
		var values: Array = record.get("xyz", [])
		if (int(record.get("vertex_count", -1)) != offsets.size()
				or values.size() != offsets.size() * 3):
			continue
		for vertex_index in offsets.size():
			offsets[vertex_index] = Vector3(
					float(values[vertex_index * 3]),
					float(values[vertex_index * 3 + 1]),
					float(values[vertex_index * 3 + 2]))
		mesh_offsets[surface_index] = offsets
		auto_surface_offsets[mesh_key] = mesh_offsets
		loaded += offsets.size()
	return loaded
