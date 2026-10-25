extends Node3D
## How much the feet of a retargeted GVHMR clip slide on the floor while the source says they are planted.
##   godot --headless --path . res://tests/manual/animation/gvhmr_feet.tscn -- manifest=res://x.character.json \
##       clip=res://y.res contacts=res://z_contacts.json   (tools/gvhmr/foot_report.py writes the contacts)
## Prints per foot: stretches planted, the world drift of the toe over each stretch (cm), and its height above the floor.

func _ready() -> void:
	var options := {}
	for argument in OS.get_cmdline_user_args():
		var pair := argument.split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(options["manifest"]))
	var contacts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(options["contacts"]))
	var character: Node3D = (load(manifest["model_path"]) as PackedScene).instantiate()
	add_child(character)
	var player := character.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var library: AnimationLibrary = player.get_animation_library(&"")
	library.add_animation(&"clip", load(options["clip"]))
	player.play(&"clip")
	var skeleton := character.find_child("Skeleton3D", true, false) as Skeleton3D
	var map: Dictionary = manifest["humanoid_map"]
	var toes := [skeleton.find_bone(map.get("LeftToeBase", map["LeftFoot"])), skeleton.find_bone(map.get("RightToeBase", map["RightFoot"]))]
	if options.get("bone", "toe") == "ankle": # the ankle is what the foot lock pins
		toes = [skeleton.find_bone(map["LeftFoot"]), skeleton.find_bone(map["RightFoot"])]
	var planted: Array = contacts["planted"]
	var fps: float = contacts["fps"]
	var drift := [[], []]
	var heights := [[], []]
	var start := [Vector3.ZERO, Vector3.ZERO]
	var last := [Vector3.ZERO, Vector3.ZERO]
	var inside := [false, false]
	var lowest := 1e9
	for frame in planted.size():
		player.seek(minf(float(frame) / fps, player.current_animation_length - 0.001), true) # (not past the end: a looping clip would wrap)
		await get_tree().process_frame
		for side in 2:
			var toe := (skeleton.global_transform * skeleton.get_bone_global_pose(toes[side])).origin
			lowest = minf(lowest, toe.y)
			var on: bool = int((planted[frame] as Array)[side]) == 1
			if on and not inside[side]:
				start[side] = toe
			if on:
				last[side] = toe
				heights[side].append(toe.y)
			if (not on and inside[side]) or (on and frame == planted.size() - 1):
				drift[side].append(Vector2(last[side].x - start[side].x, last[side].z - start[side].z).length() * 100.0)
			inside[side] = on
	for side in 2:
		var d: Array = drift[side]
		var mean := 0.0
		for value in d:
			mean += value
		print("%s toe: %d stretches, drift per stretch %s cm (mean %.1f), planted height mean %.1f cm above the lowest point of the clip" % [
				["left", "right"][side], d.size(), str(d.map(func(v: float) -> float: return snappedf(v, 0.1))),
				mean / maxf(d.size(), 1.0), _mean(heights[side]) * 100.0 - lowest * 100.0])
	get_tree().quit()


func _mean(values: Array) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / maxf(values.size(), 1.0)
