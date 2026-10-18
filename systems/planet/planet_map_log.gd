class_name PlanetMapLog
extends RefCounted
## What the map does, written to `user://planet_map.log` while it is open: every move, zoom,
## layer, chart that starts, finishes or is given up, and what the view waits for. The file is
## emptied each time the map is opened (`begin`) and stops growing at `MAX_BYTES`, so it never
## keeps an old session and never gets big. Safe to call from the chart threads.

const PATH := "user://planet_map.log"
const MAX_BYTES := 120000

static var _file: FileAccess
static var _started_ms := 0
static var _bytes := 0
static var _full := false
static var _mutex := Mutex.new()
static var _last := {} # key -> the time (ms) its last throttled line was written


## Starts a fresh log (the old one is gone): the map has just been opened.
static func begin(note: String) -> void:
	_mutex.lock()
	if _file != null:
		_file.close()
	_file = FileAccess.open(PATH, FileAccess.WRITE)
	_started_ms = Time.get_ticks_msec()
	_bytes = 0
	_full = false
	_last.clear()
	_mutex.unlock()
	line("map opened: " + note)


## The map was closed: the last line, and the file is let go.
static func end() -> void:
	line("map closed")
	_mutex.lock()
	if _file != null:
		_file.close()
		_file = null
	_mutex.unlock()


## One line with the time since the map opened (seconds).
static func line(text: String) -> void:
	_mutex.lock()
	if _file != null and not _full:
		var stamp := "%7.3f  " % (float(Time.get_ticks_msec() - _started_ms) / 1000.0)
		var out := stamp + text + "\n"
		_bytes += out.length()
		if _bytes > MAX_BYTES:
			_full = true
			out = stamp + "-- the log is full: the rest is dropped --\n"
		_file.store_string(out)
		_file.flush()
	_mutex.unlock()


## Like `line`, but at most one every `seconds` for the same `key` (a drag or a wheel makes many).
static func line_every(key: String, seconds: float, text: String) -> void:
	var now := Time.get_ticks_msec()
	_mutex.lock()
	var last: int = _last.get(key, -1000000)
	var due := float(now - last) >= seconds * 1000.0
	if due:
		_last[key] = now
	_mutex.unlock()
	if due:
		line(text)


## Where the file is on this machine.
static func where() -> String:
	return ProjectSettings.globalize_path(PATH)
