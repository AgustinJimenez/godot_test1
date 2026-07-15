extends Node3D
## Hinged door. The root node is the hinge; the panel hangs off it on +X.

@export var open_angle_deg: float = 100.0
@export var swing_time: float = 0.8

var _open := false
var _busy := false

@onready var interactable: Interactable = $Body/Interactable


func _on_interactable_interacted(_player: Node3D) -> void:
	if _busy:
		return
	_busy = true
	_open = not _open
	interactable.prompt = "Close door" if _open else "Open door"
	var target_y := deg_to_rad(open_angle_deg) if _open else 0.0
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "rotation:y", target_y, swing_time)
	tween.finished.connect(func() -> void: _busy = false)
