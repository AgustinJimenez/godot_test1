extends RefCounted
## Lets several lab runs share ONE Godot process (one window, one movie): the lab asks `user_args()` instead of OS.get_cmdline_user_args(), and
## `finish()` instead of quitting. Outside a session both behave as before. See foot_ik_v2_session_runner.gd.

static var active := false
static var args: PackedStringArray = PackedStringArray()
static var finished := false
static var passed := true


static func user_args() -> PackedStringArray:
	return args if active else OS.get_cmdline_user_args()


static func finish(tree: SceneTree, ok: bool) -> void:
	if active:
		finished = true
		passed = ok
	else:
		tree.quit(0 if ok else 1)
