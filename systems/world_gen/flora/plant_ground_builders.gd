class_name PlantGroundBuilders
extends RefCounted
## Mushrooms (every other plant is grown by TreeGrower). Each draws one
## mesh of a PlantSpecies from its numbers (see the field notes in plant_species.gd).


static func _still(color: Color) -> Color:
	return Color(color.r, color.g, color.b, 0.0)


## A cluster of stalks under domed or flat caps.
## Where the mushrooms of one clump stand: a clump grows around the first one, each next one beside
## an earlier one at least as far as the two caps are wide, so no caps cut into each other (a clump
## with no free spot for a mushroom just has one less). Each entry: at, height, radius (the cap's).
static func mushroom_layout(s: PlantSpecies, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var spots: Array[Dictionary] = []
	for index in s.count:
		var height := s.height * rng.randf_range(0.7, 1.2)
		var radius := height * s.crown
		var at := Vector3.ZERO
		if index > 0:
			var found := false
			for attempt in 24:
				var beside: Dictionary = spots[rng.randi() % spots.size()]
				var angle := rng.randf() * TAU
				var distance: float = radius + float(beside["radius"]) + rng.randf_range(0.04, 0.1)
				at = (beside["at"] as Vector3) + Vector3(cos(angle), 0.0, sin(angle)) * distance
				found = true
				for other: Dictionary in spots:
					var apart := Vector2(at.x - (other["at"] as Vector3).x,
							at.z - (other["at"] as Vector3).z).length()
					if apart < radius + float(other["radius"]) + 0.03:
						found = false
						break
				if found:
					break
			if not found:
				continue
		spots.append({"at": at, "height": height, "radius": radius})
	return spots


static func mushroom(builder: MeshBuilder, s: PlantSpecies, rng: RandomNumberGenerator) -> void:
	for spot in mushroom_layout(s, rng):
		var at: Vector3 = spot["at"]
		var height: float = spot["height"]
		builder.add_frustum(at, height, 0.035, 0.03, 5, _still(Color(0.9, 0.88, 0.8)),
				_still(Color(0.92, 0.9, 0.84)))
		builder.add_frustum(at + Vector3(0.0, height, 0.0), height * lerpf(0.3, 0.9, s.droop),
				height * s.crown, 0.02, 7, _still(s.accent.darkened(0.15)), _still(s.accent), rng, 0.05)
