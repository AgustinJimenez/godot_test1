extends NavigationRegion3D
## Bakes the navmesh from the room's own geometry at startup, since there's
## no pre-baked NavigationMesh resource checked in. The room's CSGBox3D
## walls/crates/pillar live under the sibling "Geometry" node rather than
## as children of this region, so baking needs the GROUPS_WITH_CHILDREN
## source mode pointed at those nodes - hand-authoring `groups=[...]` in the
## .tscn was silently ignored (Godot 4.6), so the groups are joined here in
## code instead, right before baking.

@export var source_paths: Array[NodePath] = [NodePath("Geometry")]

func _ready() -> void:
	for path in source_paths:
		var source := get_parent().get_node_or_null(path)
		if source != null:
			source.add_to_group(&"navmesh_source")
	# Give CSG shapes time to build their deferred collision bodies before
	# the parser reads them. A fixed physics-frame count isn't reliable here
	# - the deferred work is wall-clock/load bound, not tied to the physics
	# tick rate, so a real-time wait is what actually needs to elapse.
	await get_tree().create_timer(0.5).timeout
	bake_navigation_mesh(false)
