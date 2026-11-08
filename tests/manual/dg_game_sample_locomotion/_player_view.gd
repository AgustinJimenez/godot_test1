extends Node3D
## Model viewer for the DG_GAME_SAMPLE locomotion asset.
##
## Loads `assets/models/dg_game_sample/player_locomotion.glb` (547-bone rig, 14 clips) and plays
## one clip in a fixed 3/4 view. Handy for eyeballing a bake without running the lab.

const MODEL := "res://assets/models/dg_game_sample/player_locomotion.glb"
const CLIP_NAME := "idle"


func _ready() -> void:
	var packed := load(MODEL) as PackedScene
	if packed == null:
		push_error("viewer: could not load %s" % MODEL)
		return
	var scene := packed.instantiate()
	add_child(scene)
	var skeleton := scene.find_child("Skeleton3D", true, false) as Skeleton3D
	print("bones=", skeleton.get_bone_count() if skeleton != null else -1)

	var own := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if own != null and own.has_animation(CLIP_NAME):
		own.play(CLIP_NAME)
		own.seek(0.45, true)
		print("playing ", CLIP_NAME, " tracks=", own.get_animation(CLIP_NAME).get_track_count())
	else:
		push_warning("viewer: clip %s missing" % CLIP_NAME)

	var rig := _make_light_and_env()
	add_child(rig)


func _make_light_and_env() -> Node3D:
	var root_node := Node3D.new()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, 35.0, 0.0)
	light.light_energy = 0.5
	root_node.add_child(light)

	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.fov = 45.0
	root_node.add_child(camera)
	camera.position = Vector3(0.0, 1.05, 2.4)
	camera.look_at(Vector3(0.0, 0.95, 0.0))

	var env := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.15, 0.17, 0.2)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.55, 0.6, 0.65)
	settings.ambient_light_energy = 0.3
	env.environment = settings
	root_node.add_child(env)
	return root_node
