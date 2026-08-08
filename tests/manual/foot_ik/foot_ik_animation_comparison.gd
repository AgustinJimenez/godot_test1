extends Node3D
## Compact A/B reference group for seeing what Foot IK changes during locomotion.
## All four bodies remain stationary so animation and IK pose differences can be
## inspected without chasing a moving reference or observing harness-reset artifacts.

const PLAYER_BODY := preload("res://actors/player/player_body.gd")
const GROUP_CENTER := Vector3(8.75, 0.0, -7.0)
const DUMMY_SPACING := 2.5
const PAD_SIZE := Vector3(11.5, 0.1, 9.0)
const LABEL_HEIGHT := 2.25
const CASES: Array[Dictionary] = [
	{"label": "WALK IN PLACE\nIK OFF", "animation": &"unarmed_walk", "ik": false},
	{"label": "WALK IN PLACE\nIK ON", "animation": &"unarmed_walk", "ik": true},
	{"label": "RUN IN PLACE\nIK OFF", "animation": &"unarmed_sprint", "ik": false},
	{"label": "RUN IN PLACE\nIK ON", "animation": &"unarmed_sprint", "ik": true},
]


func _ready() -> void:
	_build_comparison_pad()
	for index in CASES.size():
		_build_dummy(index, CASES[index])


func _build_comparison_pad() -> void:
	var pad := CSGBox3D.new()
	pad.name = &"ComparisonPad"
	pad.size = PAD_SIZE
	pad.position = GROUP_CENTER + Vector3(0.0, -PAD_SIZE.y * 0.5, 0.0)
	pad.use_collision = true
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.19, 0.23, 0.2)
	material.roughness = 0.9
	pad.material = material
	add_child(pad)


func _build_dummy(index: int, data: Dictionary) -> void:
	var lane_x := GROUP_CENTER.x + (index - (CASES.size() - 1) * 0.5) * DUMMY_SPACING
	var motion_root := Node3D.new()
	motion_root.name = StringName("ComparisonDummy%d" % index)
	motion_root.position = Vector3(lane_x, 0.0, GROUP_CENTER.z)
	add_child(motion_root)

	var body := PLAYER_BODY.new() as PlayerBody
	body.name = &"Body"
	motion_root.add_child(body)
	body.play_debug_anim(data["animation"] as StringName, 0.0)
	_set_ik_active(body, data["ik"])
	_build_label(str(data["label"]), Vector3(lane_x, LABEL_HEIGHT, GROUP_CENTER.z))


func _set_ik_active(body: PlayerBody, enabled: bool) -> void:
	for child in body.skeleton.get_children():
		if child is PlayerFootIKModifier:
			child.active = enabled
			return


func _build_label(text: String, world_position: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 36
	label.outline_size = 8
	label.modulate = Color.WHITE
	label.outline_modulate = Color.BLACK
	label.position = world_position
	add_child(label)
