class_name PlanetRecorder
extends Node
## A flight recorder for play: always on in the planet, it keeps the last WINDOW seconds (a sample
## every INTERVAL seconds and every error or warning the engine prints) and rewrites them to
## user://planet_live.jsonl once a second, on a mark and on exit. After something looks wrong, the
## file already holds the moments before it. F9 marks "this looks wrong now" (a "mark" line).
## Cheap on purpose: a few dozen small lines, one short file write a second.

const PATH := "user://planet_live.jsonl"
const WINDOW := 10.0 ## seconds kept
const INTERVAL := 0.2 ## seconds between samples
const WRITE_EVERY := 1.0 ## seconds between file writes
const MARK_KEY := KEY_F9

var planet: PlanetWorld

var _lines: Array[Array] = [] # [time, json line], oldest first
var _since_sample := 0.0
var _since_write := 0.0
var _marks := 0
var _logger := RecorderLogger.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_logger.recorder = self
	OS.add_logger(_logger)


func _exit_tree() -> void:
	OS.remove_logger(_logger)
	_write()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == MARK_KEY:
		_marks += 1
		_add({"kind": "mark", "mark": _marks})
		_write()


func _process(delta: float) -> void:
	_since_sample += delta
	_since_write += delta
	if _since_sample >= INTERVAL:
		_since_sample = 0.0
		_add(_sample())
	if _since_write >= WRITE_EVERY:
		_since_write = 0.0
		_write()


func _sample() -> Dictionary:
	var sample := {"kind": "sample", "fps": Engine.get_frames_per_second(),
			"frame": Engine.get_process_frames()}
	if planet == null or planet.target() == null:
		return sample
	var target := planet.target()
	var here := planet.planet_position()
	sample["altitude"] = snappedf(here.length() - planet.settings.radius, 0.1)
	sample["position"] = [snappedf(here.x, 0.1), snappedf(here.y, 0.1), snappedf(here.z, 0.1)]
	sample["local_hour"] = snappedf(planet.clock.local_hour(here.normalized()), 0.01)
	sample["tiles"] = planet.surface.tiles.size()
	sample["weather"] = planet.weather_text
	var atmosphere := planet.atmosphere
	sample["fog_extra"] = snappedf(atmosphere.fog_extra, 0.0001)
	sample["cloud_on"] = snappedf(atmosphere.cloud_on, 0.01)
	sample["overcast"] = snappedf(atmosphere.overcast, 0.01)
	sample["underwater"] = atmosphere.underwater
	if target is Player:
		sample["speed"] = snappedf((target as Player).velocity.length(), 0.1)
		sample["free_mode"] = (target as Player).free_mode_enabled
		sample["on_floor"] = (target as Player).is_on_floor()
	return sample


## Adds a line (stamped with the time) and drops what is older than the window.
func _add(entry: Dictionary) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	entry["time"] = snappedf(now, 0.001)
	_lines.append([now, JSON.stringify(entry)])
	while not _lines.is_empty() and now - float(_lines[0][0]) > WINDOW:
		_lines.pop_front()


func _write() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return
	for entry in _lines:
		file.store_line(entry[1] as String)
	file.close()


## Called by the logger, possibly from another thread.
func note_message(kind: String, text: String) -> void:
	call_deferred(&"_add", {"kind": kind, "text": text.left(300)})


## Hears what the engine prints (errors and warnings) and passes it to the recorder.
class RecorderLogger extends Logger:
	var recorder: PlanetRecorder

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if recorder == null:
			return
		var kind := "warning" if error_type == Logger.ERROR_TYPE_WARNING else "error"
		recorder.note_message(kind, "%s (%s:%d %s) %s" % [rationale if rationale != "" else code,
				file.get_file(), line, function, code])
