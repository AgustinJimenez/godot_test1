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
	# the parser reads them. A fixed physics-frame count isn't reliable here
	# - the deferred work is wall-clock/load bound, not tied to the physics
	# tick rate, so a real-time wait is what actually needs to elapse.
	await get_tree().create_timer(0.5).timeout
	bake_navigation_mesh(false)
