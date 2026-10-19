class_name PlanetChartProfile
extends RefCounted
## Where the time of a map picture goes: every part of the process adds the microseconds it took (summed over the chart's
## threads: the CPU time, more than the wall time when several threads work), and when the picture is done the chart
## writes them to the map log (`user://planet_map.log`) and, with PLANET_CHART_PROFILE=1 in the environment, to the
## output. Safe to use from the chart threads.

static var _mutex := Mutex.new()
static var _phases := {} # phase -> microseconds
static var _order: Array[String] = [] # the phases in the order they first appeared


## Adds the time since `since` (a Time.get_ticks_usec value) to `phase`; returns now, for the next phase.
static func lap(phase: String, since: int) -> int:
	var now := Time.get_ticks_usec()
	_mutex.lock()
	if not _phases.has(phase):
		_phases[phase] = 0
		_order.append(phase)
	_phases[phase] += now - since
	_mutex.unlock()
	return now


## The phases so far (name -> ms) in the order they appeared; they are cleared.
static func take() -> Array:
	_mutex.lock()
	var out: Array = []
	for phase in _order:
		out.append([phase, float(_phases[phase]) / 1000.0])
	_phases.clear()
	_order.clear()
	_mutex.unlock()
	return out


## The report of a picture: its wall time and every phase's CPU time (and the native parts inside the rows).
static func report(title: String, wall_ms: float, native: Object) -> void:
	var lines: Array[String] = ["chart %s: %.0f ms wall" % [title, wall_ms]]
	for entry: Array in take():
		lines.append("    %-22s %8.1f ms cpu" % [entry[0], entry[1]])
	if native != null and native.has_method(&"profile_take"):
		var inside: Dictionary = native.call(&"profile_take")
		for key: String in inside:
			if float(inside[key]) > 0.0:
				lines.append("      in the rows: %-14s %8.1f ms cpu" % [key, inside[key]])
	for text in lines:
		PlanetMapLog.line(text)
		if OS.has_environment("PLANET_CHART_PROFILE"):
			print("CHART_PROFILE ", text)
