class_name WorldSettings
extends Resource
## Every number the procedural world is made from. Same seed + same settings = same world.

@export var world_seed := 1337
@export var chunk_size := 64.0 ## m, one terrain tile
@export var cell_size := 2.0 ## m, one terrain quad (the low-poly facet size)
@export var view_chunks := 3 ## radius of fine tiles (colliders, plants) around the target
@export var far_chunks := 10 ## radius of coarse scenery tiles out to the horizon
@export var sea_level := 0.0
@export var height_scale := 64.0 ## m from the deepest basin to the highest peak, roughly
@export var spawn_flat_radius := 36.0 ## m around the origin kept gentle, so a player can land
@export var tree_density := 1.0
@export var rock_density := 1.0
@export var grass_density := 1.0
