class_name FootIKV2Debug
extends RefCounted
## Opt-in per-part CPU timing for the v2 modifier - same technique as v1's foot_ik_debug.gd
## (begin()/end() around a part, a periodic report), scoped down since v2 has far fewer switches.
## Off by default: with `enabled` false, begin() returns -1 and end() early-outs for free.
## Enable with `FootIKV2Debug.enabled = true` (the lab does this via `--foot-ik-v2-perf`).

static var enabled := false
static var report_every := 300 # physics frames between automatic reports
static var _usec: Dictionary = {} # part name -> total microseconds this window
static var _calls: Dictionary = {}
static var _frames := 0


static func begin() -> int:
	return Time.get_ticks_usec() if enabled else -1


static func end(part: StringName, start: int) -> void:
	if start < 0:
		return
	_usec[part] = int(_usec.get(part, 0)) + (Time.get_ticks_usec() - start)
	_calls[part] = int(_calls.get(part, 0)) + 1


## Call once per physics frame (the modifier's own pass). Prints a report every `report_every`
## frames while enabled.
static func frame_tick() -> void:
	if not enabled:
		return
	_frames += 1
	if report_every > 0 and _frames % report_every == 0:
		print(report())


static func report() -> String:
	if _usec.is_empty():
		return "[FOOT_IK_V2_PERF] no samples yet"
	var parts: Array = _usec.keys()
	parts.sort_custom(func(a, b): return int(_usec[a]) > int(_usec[b]))
	var lines := PackedStringArray()
	lines.append("[FOOT_IK_V2_PERF] frames=%d  part: usec_total  usec/frame  calls" % _frames)
	for part: String in parts:
		var usec := int(_usec[part])
		lines.append("  %-14s %8d  %8.1f  %6d" % [
				part, usec, float(usec) / maxf(_frames, 1), int(_calls.get(part, 0))])
	return "\n".join(lines)


static func reset() -> void:
	_usec.clear()
	_calls.clear()
	_frames = 0
