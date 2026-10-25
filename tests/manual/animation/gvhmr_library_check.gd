extends Node
## Builds the whole GVHMR pack as an AnimationLibrary on two characters (GvhmrPack.add_to) and checks every ok/usable clip arrived
## with tracks, a sane length and a hips position track near the floor; prints GVHMR_LIBRARY_CHECK PASS/FAIL and the time taken.
##   godot --headless --path . res://tests/manual/animation/gvhmr_library_check.tscn

const TARGETS := [
	"res://assets/models/mixamo_characters/Brute.character.json",
	"res://assets/models/pistol_starter/MotusMan/MotusMan_v55.character.json",
]


func _ready() -> void:
	var failures := 0
	for path: String in TARGETS:
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var root: Node = (load(manifest["model_path"]) as PackedScene).instantiate()
		add_child(root)
		var skeleton := root.find_child("Skeleton3D", true, false) as Skeleton3D
		var started := Time.get_ticks_msec()
		var library := AnimationLibrary.new()
		var added := GvhmrPack.add_to(library, skeleton, manifest["humanoid_map"])
		var seconds := (Time.get_ticks_msec() - started) / 1000.0
		var wanted := 0
		for entry: Dictionary in GvhmrPack.catalog():
			if entry["rating"] in ["ok", "usable"]:
				wanted += 1
		var bad := 0
		for name in library.get_animation_list():
			var animation := library.get_animation(name)
			var hips_height := -1.0
			for track in animation.get_track_count():
				if animation.track_get_type(track) == Animation.TYPE_POSITION_3D:
					hips_height = (animation.track_get_key_value(track, animation.track_get_key_count(track) / 2) as Vector3).y
					break
			if animation.length < 1.0 or animation.get_track_count() < 20 or hips_height < 0.3 or hips_height > 2.5:
				bad += 1
				print("  BAD ", name, " length ", animation.length, " tracks ", animation.get_track_count(), " hips y ", hips_height)
		print("%s: %d/%d clips in %.1f s, %d bad" % [manifest.get("display_name", path), added, wanted, seconds, bad])
		if added != wanted or bad > 0:
			failures += 1
		root.queue_free()
	print("GVHMR_LIBRARY_CHECK ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit()
