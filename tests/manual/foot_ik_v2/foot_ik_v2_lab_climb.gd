extends Node
## The climbing course inside the Foot IK v2 lab, south of the ramps (z 15..42): a 2.5 m ledge
## (jump to grab it, shimmy, W climbs, crouch drops), a 4 m tower beside it (leap across with jump),
## a 6 m wall of generated holds, and a 0.3 m beam on a 1 m platform. Not built headless, so the
## regression suite is unaffected. In a window it also switches climbing on (F8 toggles it).

const INSTALL_CLIMB := preload("res://actors/player/climb/player_climb_install.gd")
const WALL_Z := 20.0 # centre of the walls; their faces (toward the ramps) are at z 19
const GALS_CLIPS := preload("res://tests/manual/ledge_anim/gals_ledge_clips.gd")

var _gals := false
var _demo_dir := ""
var _demo_frame := 0
var _demo_hold := "--demo-hold" in OS.get_cmdline_user_args() # stay in the hang for a whole idle cycle


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var lab := get_parent()
	_wall(lab, Vector3(-10.0, 0.0, WALL_Z), Vector3(6.0, 2.5, 2.0), "Ledge 2.5 m: jump at it")
	_wall(lab, Vector3(-3.0, 0.0, WALL_Z), Vector3(4.0, 4.0, 2.0), "Tower 4 m: leap from the ledge")
	_wall(lab, Vector3(6.0, 0.0, WALL_Z), Vector3(8.0, 6.0, 2.0), "Hold wall 6 m: jump on")
	var holds := ClimbHoldWall.new()
	holds.rows = 9
	lab.add_child.call_deferred(holds)
	holds.position = Vector3(6.0, 2.2, WALL_Z - 1.0)
	holds.rotation.y = PI # +Z is out of the wall: the face looks toward the ramps
	_beam(lab)
	var player := lab.get_node_or_null("Player") as Player
	if player != null and player.climb == null:
		INSTALL_CLIMB.install(player)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--climb-demo="):
			_demo_dir = arg.substr(13)
	if player != null and not "--mixamo-ledge" in OS.get_cmdline_user_args():
		_use_gals_clips.call_deferred(true)


## `--climb-demo=DIR`: drop at the 2.5 m ledge, hang, and save pictures (the player's own camera, then a side one).
func _physics_process(_delta: float) -> void:
	if _demo_dir == "":
		return
	var player := get_parent().get_node_or_null("Player") as Player
	_demo_frame += 1
	if player == null or player.climb == null:
		return
	if _demo_frame == 60:
		player.global_position = Vector3(-10.0, 1.7, WALL_Z - 1.6)
		player.rotation = Vector3(0.0, PI, 0.0)
		player.velocity = Vector3.ZERO
	if _demo_frame > 270 and _demo_frame < 620 and _demo_frame % 5 == 0:
		var deep := ""
		var map2: Dictionary = player.body._target_humanoid_map
		for role: String in ["Hips", "Spine2", "Head", "LeftArm", "LeftHand", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightLeg", "RightFoot", "RightToeBase"]:
			var bone2 := player.skeleton.find_bone(String(map2.get(role, "")))
			if bone2 >= 0:
				var at2 := player.skeleton.global_transform * player.skeleton.get_bone_global_pose(bone2).origin
				deep += " %s %+.2f" % [role.left(8), at2.z - (WALL_Z - 1.0)]
		print("CLIMB_TRACE f%d st%d y%.2f%s" % [_demo_frame, player.climb.state, player.global_position.y, deep])
	if _demo_frame > 60 and _demo_frame < 620:
		for role: String in ["LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase", "Hips", "Spine2"]:
			var b := player.skeleton.find_bone(String(player.body._target_humanoid_map.get(role, "")))
			if b >= 0:
				var w := player.skeleton.global_transform * player.skeleton.get_bone_global_pose(b).origin
				if w.y < 2.45 and w.z - (WALL_Z - 1.0) > 0.02 and w.z < WALL_Z + 1.0 and player.climb.state != 0:
					print("CLIMB_VIOL f%d st%d %s y%.2f in wall %.2f" % [_demo_frame, player.climb.state, role, w.y, w.z - (WALL_Z - 1.0)])
	if _demo_frame in [200] or (_demo_hold and _demo_frame in [86, 92, 98, 104, 110, 116, 122, 130, 140, 160]):
		get_viewport().get_texture().get_image().save_png("%s/demo_%d.png" % [_demo_dir, _demo_frame])
		print("CLIMB_DEMO state ", player.climb.state, " at ", player.global_position)
		var map: Dictionary = player.body._target_humanoid_map
		for role: String in ["Hips", "Spine2", "Head", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase"]:
			var bone := player.skeleton.find_bone(String(map.get(role, "")))
			if bone >= 0:
				var at := player.skeleton.global_transform * player.skeleton.get_bone_global_pose(bone).origin
				print("CLIMB_DEMO bone %-12s y %.2f  z past wall %+.2f" % [role, at.y, at.z - (WALL_Z - 1.0)])
		for side: StringName in [&"left", &"right"]:
			if player.climb.hands.targets.has(side) and player.climb.hands.debug_wrist.has(side):
				var target: Vector3 = player.climb.hands.targets[side]
				var wrist: Vector3 = player.climb.hands.debug_wrist[side]
				print("CLIMB_DEMO ", side, " target ", target, " wrist ", wrist, " off ", wrist - target)
	if _demo_frame == (62 if _demo_hold else 150):
		if true:
			var camera := Camera3D.new()
			get_parent().add_child(camera)
			camera.look_at_from_position(Vector3(-10.0, 1.9, WALL_Z - 4.2), Vector3(-10.0, 1.6, WALL_Z - 1.0))
			camera.make_current()
	if _demo_frame == 270 and not _demo_hold:
		player.movement_input_override = Vector2(0.0, -1.0) # W: pull up
	elif _demo_frame == 271:
		player.movement_input_override = Vector2.ZERO
	elif _demo_frame == 420: # on top: step back to the edge facing off it and crouch into a hang
		player.global_position = Vector3(-10.0, 2.5, WALL_Z - 0.7)
		player.rotation = Vector3.ZERO
		player.velocity = Vector3.ZERO
	elif _demo_frame == 440:
		Input.action_press(&"crouch")
	elif _demo_frame == 442:
		Input.action_release(&"crouch")
	if _demo_frame in [300, 330, 360, 390, 460, 490, 520, 550]:
		get_viewport().get_texture().get_image().save_png("%s/demo_%d.png" % [_demo_dir, _demo_frame])
	if _demo_frame == (170 if _demo_hold else 620):
		get_tree().quit()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F9:
		_use_gals_clips(not _gals)


## The hang, grab and pull-up clips are the reverse-engineered game's (needs its folder; else Mixamo). `--mixamo-ledge`
## starts on the Mixamo ones; F9 swaps.
func _use_gals_clips(on: bool) -> void:
	var player := get_parent().get_node_or_null("Player") as Player
	if GALS_CLIPS.apply(player, on):
		_gals = on


func _wall(lab: Node, base: Vector3, size: Vector3, text: String) -> void:
	_box(lab, base + Vector3(0.0, size.y * 0.5, 0.0), size)
	_sign(lab, base + Vector3(0.0, size.y + 0.6, -size.z * 0.5), text)


func _beam(lab: Node) -> void:
	var x := -22.0
	for step in 3: # three 0.25 m steps up to the 1 m platform
		var height := 0.25 * float(step + 1)
		_box(lab, Vector3(x, height * 0.5, 23.75 + 0.5 * float(step)), Vector3(3.0, height, 0.5))
	_box(lab, Vector3(x, 0.5, 26.5), Vector3(4.0, 1.0, 3.0))
	_box(lab, Vector3(x, 0.5, 33.0), Vector3(0.3, 1.0, 10.0))
	_box(lab, Vector3(x, 0.5, 39.5), Vector3(4.0, 1.0, 3.0))
	_sign(lab, Vector3(x, 2.2, 24.0), "Beam 0.3 m: walk carefully")


func _box(lab: Node, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	body.add_child(mesh)
	lab.add_child.call_deferred(body)
	body.position = at


func _sign(lab: Node, at: Vector3, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.pixel_size = 0.01
	label.font_size = 48
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.add_child.call_deferred(label)
	label.position = at
