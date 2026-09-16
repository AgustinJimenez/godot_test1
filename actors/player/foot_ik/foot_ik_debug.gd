class_name FootIKDebug
extends RefCounted
## Opt-in, debug-only controls for the Foot IK stack: one on/off switch per major subsystem for
## live A/B ("turn it off and see if the bug/FPS issue goes away"), plus per-part CPU timing so the
## expensive step is visible instead of guessed.
##
## Off by default: with `settings.master` false every subsystem behaves exactly as before, and with
## `settings.profiling` false the timers cost nothing (begin() returns -1 and end() early-outs).
##
## Toggle combinations are NOT all validated - flip one at a time. The switches are deliberately
## coarse (whole subsystems), not one per micro-behaviour: they interact, and a switch per line
## would create untestable combinations (see AGENT_TASKS/025 and AGENTS.md's Foot IK notes).
##
## The live values live on a plain object (`settings`) so the preview's F6 feature panel can bind
## checkboxes/sliders to them - GDScript static vars are not object properties, so `_add_toggle`
## could not read them directly.

class Settings extends RefCounted:
	var master := false # false = every subsystem on (shipping behaviour)
	var toe_clearance := true # solve_leg_candidate's same-frame clearance retry
	var stair_support := true # stair predictor's support ownership
	var swing_lift := true # predicted step-up swing lift
	var balance := true # shared-pelvis lateral shift / counter-lean
	var idle_stance := true # idle stance rehome
	var profiling := false # per-part CPU timing
	var report_every := 300 # frames between automatic profiler reports


static var settings := Settings.new()
static var _usec: Dictionary = {}
static var _calls: Dictionary = {}
static var _frames := 0


static func subsystem_on(which: StringName) -> bool:
	if not settings.master:
		return true
	match which:
		&"toe_clearance":
			return settings.toe_clearance
		&"stair_support":
			return settings.stair_support
		&"swing_lift":
			return settings.swing_lift
		&"balance":
			return settings.balance
		&"idle_stance":
			return settings.idle_stance
	return true


static func begin() -> int:
	return Time.get_ticks_usec() if settings.profiling else -1


static func end(part: StringName, start: int) -> void:
	if start < 0:
		return
	_usec[part] = int(_usec.get(part, 0)) + (Time.get_ticks_usec() - start)
	_calls[part] = int(_calls.get(part, 0)) + 1


## Call once per physics frame (foot_ik_modifier). Prints a report every `settings.report_every`
## frames while profiling.
static func frame_tick() -> void:
	if not settings.profiling:
		return
	_frames += 1
	if settings.report_every > 0 and _frames % settings.report_every == 0:
		print(report())


static func report() -> String:
	if _usec.is_empty():
		return "[FOOT_IK_PERF] no samples yet (enable profiling and let it run)"
	var parts: Array = _usec.keys()
	parts.sort_custom(func(a, b): return int(_usec[a]) > int(_usec[b]))
	# NOTE: no percentage column - parts can nest (e.g. "support" runs inside "total"), so read the
	# absolute usec/frame numbers instead.
	var lines := PackedStringArray()
	lines.append("[FOOT_IK_PERF] frames=%d  part: usec_total  usec/frame  calls" % _frames)
	for part: String in parts:
		var usec := int(_usec[part])
		lines.append("  %-12s %8d  %8.1f  %6d" % [
				part, usec, float(usec) / maxf(_frames, 1), int(_calls.get(part, 0))])
	return "\n".join(lines)


static func reset() -> void:
	_usec.clear()
	_calls.clear()
	_frames = 0


## One-line summary of the current toggles, for logs/overlays.
static func toggle_summary() -> String:
	if not settings.master:
		return "all-on"
	return "toe=%s stair=%s swing=%s balance=%s idle=%s" % [
			_on_off(settings.toe_clearance), _on_off(settings.stair_support),
			_on_off(settings.swing_lift), _on_off(settings.balance),
			_on_off(settings.idle_stance)]


static func _on_off(value: bool) -> String:
	return "on" if value else "off"
