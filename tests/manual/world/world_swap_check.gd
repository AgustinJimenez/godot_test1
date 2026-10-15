extends Node
## Foot IK v2 must survive a character swap in the procedural world. Run headless:
##   godot --headless --path . res://tests/manual/world/world_swap_check.tscn
## Prints WORLD_SWAP_CHECK PASS / FAIL.

const LEVEL := preload("res://levels/procedural_world.tscn")
const CATALOG := preload("res://characters/character_catalog.gd")


func _ready() -> void:
	_run.call_deferred()


func _v2_count(player: Player) -> int:
	var count := 0
	for child: Node in player.skeleton.get_children():
		if child is FootIKV2Modifier and (child as FootIKV2Modifier).enabled:
			count += 1
	return count


func _run() -> void:
	var level := LEVEL.instantiate()
	add_child(level)
	for frame in 20:
		await get_tree().physics_frame
	var player: Player = level.player
	var before := _v2_count(player)
	var swaps := 0
	var after := before
	for info: Dictionary in CATALOG.list_all().values():
		var path: String = info.get("model_path", "")
		if not ResourceLoader.exists(path):
			continue
		var scene := load(path) as PackedScene
		var probe := scene.instantiate()
		var has_skeleton := probe.find_child("Skeleton3D", true, false) != null
		probe.free()
		if not has_skeleton:
			print("  skipped %s (no Skeleton3D)" % info.get("display_name", path))
			continue
		player.body.swap_character(scene)
		for frame in 10:
			await get_tree().physics_frame
		swaps += 1
		after = _v2_count(player)
		print("  swapped to %s: v2 modifiers %d" % [info.get("display_name", path), after])
		if after != 1:
			break
	var ok := before == 1 and swaps > 0 and after == 1
	print("WORLD_SWAP_CHECK %s (v2 before %d, after %d, %d swaps)" % [
			"PASS" if ok else "FAIL", before, after, swaps])
	get_tree().quit(0 if ok else 1)
