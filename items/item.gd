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
