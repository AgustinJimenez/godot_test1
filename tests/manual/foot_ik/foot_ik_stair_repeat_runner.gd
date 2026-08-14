extends "res://tests/manual/foot_ik/foot_ik_preview.gd"

var _repeat_check := preload(
		"res://tests/manual/foot_ik/foot_ik_stair_repeat_check.gd").new()


func _ready() -> void:
	super()
	_repeat_check.setup($Player)


func _physics_process(delta: float) -> void:
	super(delta)
	_repeat_check.drive()
	Callable(_repeat_check, &"sample_post_solve").call_deferred()


func _exit_tree() -> void:
	print(_repeat_check.format_result())
	print(_repeat_check.format_idle_freeze_result())
	super()
