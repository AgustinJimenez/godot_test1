extends Node
## Runs the lab scenarios of scripts/check_foot_ik_v2.sh one after the other in ONE process (so a recording opens one window, once, and is one video).
## Each scenario is the lab scene with the same user args the suite passes, ended when the lab reports its result or after `frames` frames.
## Run: godot --path . [--write-movie X.avi] res://tests/manual/foot_ik_v2/foot_ik_v2_session.tscn [-- --only=text --from=N]

const SESSION := preload("res://tests/manual/foot_ik_v2/foot_ik_v2_session.gd")
const LAB := "res://tests/manual/foot_ik_v2/foot_ik_v2_lab.tscn"

## [label, frame limit (0 = until the lab reports), args]
const SCENARIOS := [
	["flat floor, every surface", 0, ["--foot-ik-v2-check"]],
	["idle replay at 30 Hz", 0, ["--foot-ik-v2-idle-check", "--ticks=30"]],
	["idle replay at 120 Hz", 0, ["--foot-ik-v2-idle-check", "--ticks=120"]],
	["stairs walk up", 600, ["--foot-ik-v2-idle-check", "--stairs-walk=0"]],
	["stairs walk down", 600, ["--foot-ik-v2-idle-check", "--stairs-walk=0:down"]],
	["stairs walk backward", 700, ["--foot-ik-v2-idle-check", "--stairs-walk=0:back:0.05"]],
	["stairs walk sideways left", 900, ["--foot-ik-v2-idle-check", "--stairs-walk=0:sidel"]],
	["stairs walk sideways right", 900, ["--foot-ik-v2-idle-check", "--stairs-walk=0:sider"]],
	["stairs walk diagonal left", 900, ["--foot-ik-v2-idle-check", "--stairs-walk=0:diagl"]],
	["stairs walk diagonal right", 900, ["--foot-ik-v2-idle-check", "--stairs-walk=0:diagr"]],
	["stairs sideways up", 900, ["--foot-ik-v2-idle-check", "--stairs-walk=0:sideup"]],
	["stairs sideways down", 900, ["--foot-ik-v2-idle-check", "--stairs-walk=0:sidedown"]],
	["standing at the ramp side", 400, ["--spawn=ramp-edge"]],
	["ramp strafe", 1200, ["--foot-ik-v2-ramp-check"]],
	["idle across the ramp slope", 1600, ["--foot-ik-v2-idle-check"]],
	["idle across the 30 degree ramp", 1600, ["--foot-ik-v2-idle-check", "--ramp-index=1"]],
	["idle across the 45 degree ramp", 1600, ["--foot-ik-v2-idle-check", "--ramp-index=2", "--start-on-ramp"]],
	["idle facing up the 45 degree ramp", 1600, ["--foot-ik-v2-idle-check", "--ramp-index=2", "--uphill"]],
	["idle on stairs, tip against a riser", 900, ["--foot-ik-v2-idle-check", "--stairs"]],
	["idle on the stairs' edge", 900, ["--foot-ik-v2-idle-check", "--stairs-edge"]],
	["jump on the 45 degree ramp", 900, ["--foot-ik-v2-idle-check", "--jump45"]],
	["turn in place on the stairs, dz 0", 2800, ["--foot-ik-v2-idle-check", "--stairs-turn=0"]],
	["turn in place on the stairs, dz 0.12", 2800, ["--foot-ik-v2-idle-check", "--stairs-turn=0.12"]],
	["turn in place on the stairs, dz -0.12", 2800, ["--foot-ik-v2-idle-check", "--stairs-turn=-0.12"]],
	["turn in place on the stairs, dz -1.41", 2800, ["--foot-ik-v2-idle-check", "--stairs-turn=-1.41:-0.39"]],
	["idle on stairs (leg pop)", 700, []],
	["flat floor turns", 1300, ["--spawn=flat-turn"]],
	["ramp edge turns", 1300, ["--spawn=ramp-edge-turn"]],
]

var _index := -1
var _frames := 0
var _limit := 0
var _label: Label
var _from := 1
var _only := ""
var _results: PackedStringArray = PackedStringArray()
var _gap := 0
var _repeat := 1 ## --repeat=N: each scenario plays N times in a row before the next one (to watch every case over and over)
var _pass := 0
var _loop := false ## --loop: start again after the last scenario (to watch one scenario over and over)


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--from="):
			_from = arg.trim_prefix("--from=").to_int()
		if arg.begins_with("--repeat="):
			_repeat = maxi(arg.trim_prefix("--repeat=").to_int(), 1)
		if arg == "--loop":
			_loop = true
		if arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=")
	var layer := CanvasLayer.new()
	layer.layer = 100
	_label = Label.new()
	_label.position = Vector2(12.0, 8.0)
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4))
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)
	add_child(layer)
	SESSION.active = true
	_index = _from - 2
	_adopt.call_deferred()


# The lab scenes replace the current scene, so this node moves under the root to survive them.
func _adopt() -> void:
	var tree := get_tree()
	reparent(tree.root)
	tree.current_scene = null
	_next()


func _next() -> void:
	if _index >= 0 and _index < SCENARIOS.size() and _pass < _repeat:
		_pass += 1 # the same scenario again
	else:
		_pass = 1
		_index += 1
	while _index < SCENARIOS.size() and _only != "" and not String(SCENARIOS[_index][0]).contains(_only):
		_index += 1
	if _index >= SCENARIOS.size() and _loop:
		_index = _from - 1
		while _index < SCENARIOS.size() and _only != "" and not String(SCENARIOS[_index][0]).contains(_only):
			_index += 1
	if _index >= SCENARIOS.size():
		print("SESSION_DONE ", " | ".join(_results))
		get_tree().quit(0)
		return
	var scenario: Array = SCENARIOS[_index]
	SESSION.args = PackedStringArray(scenario[2])
	SESSION.finished = false
	SESSION.passed = true
	Engine.physics_ticks_per_second = 60
	_limit = scenario[1]
	_frames = 0
	_label.text = "%d/%d  %s%s" % [_index + 1, SCENARIOS.size(), scenario[0], ("   (pass %d/%d)" % [_pass, _repeat]) if _repeat > 1 else ""]
	print("SESSION_START ", _label.text)
	get_tree().change_scene_to_file(LAB)


func _process(_delta: float) -> void:
	if _index < 0 or _index >= SCENARIOS.size() or _gap > 0:
		_gap = maxi(_gap - 1, 0)
		return
	_frames += 1
	if SESSION.finished or (_limit > 0 and _frames >= _limit):
		var verdict := ("PASS" if SESSION.passed else "FAIL") if SESSION.finished else "timed"
		_results.append("%s: %s" % [SCENARIOS[_index][0], verdict])
		print("SESSION_END ", SCENARIOS[_index][0], " ", verdict)
		_gap = 5 # let the old scene settle before the next one loads
		_next.call_deferred()
