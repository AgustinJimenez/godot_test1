extends Node
## The climbing course inside the Foot IK v2 lab, south of the ramps (z 15..42): a 2.5 m ledge
## (jump to grab it, shimmy, W climbs, crouch drops), a 4 m tower beside it (leap across with jump),
## a 6 m wall of generated holds, and a 0.3 m beam on a 1 m platform. Not built headless, so the
## regression suite is unaffected. In a window it also switches climbing on (F8 toggles it).

const INSTALL_CLIMB := preload("res://actors/player/climb/player_climb_install.gd")
const WALL_Z := 20.0 # centre of the walls; their faces (toward the ramps) are at z 19
const GALS_CLIPS := preload("res://tests/manual/ledge_anim/gals_ledge_clips.gd")

var _gals := false


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
	if player != null and "--gals-ledge" in OS.get_cmdline_user_args():
		_use_gals_clips.call_deferred(true)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F9:
		_use_gals_clips(not _gals)


## F9: the hang, grab and pull-up clips of the reverse-engineered game in place of the Mixamo ones.
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
