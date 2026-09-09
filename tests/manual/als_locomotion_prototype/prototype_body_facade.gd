class_name PrototypeBodyFacade
extends PlayerBody
## Minimal PlayerFootIKModifier-compatible facade. PlayerFootIKModifier only
## reads 6 members off its `player_body` (confirmed via grep over
## actors/player/player_foot_ik_modifier.gd, not assumed): `character`,
## `anim_player`, `locomotion_playback_scale`, `resolve_bone_name()`, plus
## the inherited Node methods `get_parent()`/`get_world_3d()`.
##
## `player_body` is statically typed `PlayerBody` on the modifier, and
## Godot's own `set()` silently no-ops (not even an error) when the runtime
## type doesn't match a script-declared property type - confirmed the hard
## way: a plain Node3D duck-type compiled fine but left `player_body` null
## at the modifier's `_ready()`, crashing on the very first bone lookup.
## Extending PlayerBody directly satisfies the type check and, as a bonus,
## reuses PlayerBody's own real `resolve_bone_name()`/`character`/
## `anim_player`/`locomotion_playback_scale` members for free instead of
## re-declaring them - the only thing overridden is `_ready()`, turned into
## a no-op so none of PlayerBody's own heavy setup (character_scene
## instantiation, retargeting, cosmetics, CharacterCatalog/PlayerProfile
## lookups) ever runs. This node doubles as the prototype's own facing
## wrapper (als_locomotion_prototype.gd's `_character`), which sets
## `character`/`anim_player`/`_target_humanoid_map` directly itself instead
## of going through PlayerBody's normal `_setup_character_scene()` path.


func _ready() -> void:
	pass
