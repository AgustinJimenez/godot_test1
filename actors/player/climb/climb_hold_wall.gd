class_name ClimbHoldWall
extends Node3D
## A patch of climbing holds generated from a brick pattern: `columns` x `rows` small blocks in the
## group `climb_hold`, every other row shifted half a column. Its +Z is the way out of the wall; put
## it on the wall face (the holds sit `depth` out from it). Place and rotate it in the level.

@export var columns := 9
@export var rows := 9
@export var spacing := Vector2(0.45, 0.4) ## m between holds, sideways and up
@export var hold_size := Vector3(0.14, 0.08, 0.1)
@export var depth := 0.05 ## m the holds stand out of the wall


func _ready() -> void:
	var mesh := BoxMesh.new()
	mesh.size = hold_size
	for row in rows:
		for column in columns:
			var x := (float(column) - float(columns - 1) * 0.5) * spacing.x \
					+ (spacing.x * 0.5 if row % 2 == 1 else 0.0) - spacing.x * 0.25
			var hold := MeshInstance3D.new()
			hold.mesh = mesh
			hold.add_to_group(&"climb_hold")
			add_child(hold)
			hold.position = Vector3(x, float(row) * spacing.y, depth)
