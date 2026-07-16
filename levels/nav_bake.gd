extends NavigationRegion3D
## Bakes the navmesh from the room's own geometry at startup, since there's
## no pre-baked NavigationMesh resource checked in. The room's CSGBox3D
## walls/crates/pillar live under the sibling "Geometry" node rather than
## as children of this region, so baking needs the GROUPS_WITH_CHILDREN
## source mode pointed at that node - hand-authoring `groups=[...]` in the
## .tscn was silently ignored (Godot 4.6), so the group is joined here in
## code instead, right before baking.

func _ready() -> void:
	get_parent().get_node(^"Geometry").add_to_group(&"navmesh_source")
	# Give CSG shapes time to build their deferred collision bodies before
	# the parser reads them.
	for i in 10:
		await get_tree().physics_frame
	bake_navigation_mesh(false)
