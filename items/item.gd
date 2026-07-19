class_name Item
extends Resource
## Data definition for anything that can sit in the inventory.
## Concrete items live as .tres files in res://items/.

enum Kind { CONSUMABLE, KEY, AMMO, WEAPON, MISC }

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var kind: Kind = Kind.MISC
@export var max_stack: int = 1
@export var icon: Texture2D
## For CONSUMABLE items: HP restored on use (0 = no healing effect).
@export var heal_amount: int = 0

@export_group("World Pickup")
@export var world_scene: PackedScene
@export var world_scale: float = 1.0
@export var world_rotation_degrees := Vector3.ZERO
@export var world_offset := Vector3.ZERO

@export_group("Held Visual")
@export var held_bone: StringName = &"RightHand"
@export var held_scale: float = 1.0
@export var held_position := Vector3.ZERO
@export var held_rotation_degrees := Vector3.ZERO

@export_group("Melee Combat")
@export var melee_damage: float = 0.0
@export var melee_range: float = 1.35
