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
const MARKS_DIR := "user://planet_marks" ## a copy of the file for every F9 (the live file is overwritten by the next run)
const MAX_MARKS := 20

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
		_keep_a_copy()


## The world this file is about, the first line: without it a position means nothing (the seed and the size make the planet).
func _world_line() -> String:
	var settings := planet.settings if planet != null else null
	if settings == null:
		return ""
	var here := planet.planet_position() if planet.target() != null else Vector3.ZERO
	return JSON.stringify({"kind": "world", "seed": settings.world_seed, "radius": settings.radius,
			"drainage_cells": settings.drainage_cells, "plants": settings.plants_on,
			"direction": [snappedf(here.normalized().x, 0.0000001), snappedf(here.normalized().y, 0.0000001),
			snappedf(here.normalized().z, 0.0000001)], "scene": get_tree().current_scene.scene_file_path})


## F9: the file as it is now, kept under its own name (`planet_marks/mark_<when>.jsonl`), the oldest of 20 dropped.
func _keep_a_copy() -> void:
	if _in_a_lab():
		return
	DirAccess.make_dir_recursive_absolute(MARKS_DIR)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "%s/mark_%s_%d.jsonl" % [MARKS_DIR, stamp, _marks]
	DirAccess.copy_absolute(PATH, path)
	var files: Array[String] = []
	for file in DirAccess.get_files_at(MARKS_DIR):
		files.append(file)
	files.sort()
	for index in maxi(files.size() - MAX_MARKS, 0):
		DirAccess.remove_absolute("%s/%s" % [MARKS_DIR, files[index]])


## The lab and the checks (tests/...) run the same planet: they must not overwrite the file of a real session.
func _in_a_lab() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path.begins_with("res://tests/")


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
	var environment := atmosphere.environment
	sample["fog"] = {"on": environment.fog_enabled, "mode": environment.fog_mode,
			"density": snappedf(environment.fog_density, 0.00001),
			"begin": environment.fog_depth_begin, "end": environment.fog_depth_end,
			"curve": environment.fog_depth_curve, "sky": environment.fog_sky_affect,
			"height": environment.fog_height_density}
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
	if _in_a_lab():
		return
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return
	var world := _world_line()
	if world != "":
		file.store_line(world)
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
