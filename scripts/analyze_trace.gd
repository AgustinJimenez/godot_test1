## Compact foot_ik trace analyzer — runs headless via:
##   godot --headless --path . --script res://scripts/analyze_trace.gd -- [flags]
##
## Flags:
##   --trace <path>     JSONL file (default: user://foot_ik_controlled.jsonl)
##   --last-n <N>       Only last N frames, 0 = all (default 40)
##   --anim <substr>    Filter frames by animation substring
##   --summary          One row per animation: frames + avg/max speed
##   --arrows           Blue (travel) vs Red (chest) angle table
##   --feet             Foot IK weight / target-Y / actual-Y table
##   --bones B1 B2 ...  rotation_deg XYZ for named bones (reads until next flag)
extends SceneTree

const DEFAULT_TRACE: String = "user://foot_ik_controlled.jsonl"

# ── output buffer (for token estimate) ────────────────────────────────────────
var _out: PackedStringArray = []

func _println(s: String = "") -> void:
	_out.append(s)
	print(s)


# ── helpers ────────────────────────────────────────────────────────────────────
static func _parse_vec3(s: String) -> Vector3:
	var clean := s.replace("(", "").replace(")", "").strip_edges()
	var parts := clean.split(",")
	if parts.size() < 3:
		return Vector3.ZERO
	return Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())


static func _h_angle_deg(v: Vector3) -> float:
	return rad_to_deg(atan2(v.x, -v.z))


# ── frame loading ──────────────────────────────────────────────────────────────
func _load_frames(path: String, last_n: int, anim_filter: String) -> Array:
	var resolved: String = path
	if not path.begins_with("/") and not path.begins_with("res://"):
		resolved = path  # absolute
	var f := FileAccess.open(resolved, FileAccess.READ)
	if f == null:
		push_error("Cannot open trace: " + resolved)
		return []
	var frames: Array = []
	var json_parser := JSON.new()
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.is_empty():
			continue
		if json_parser.parse(line) != OK:
			continue
		var parsed: Variant = json_parser.get_data()
		if parsed == null:
			continue
		frames.append(parsed)
	f.close()
	if not anim_filter.is_empty():
		frames = frames.filter(func(fr): return anim_filter in str(fr.get("animation", "")))
	if last_n > 0 and frames.size() > last_n:
		frames = frames.slice(frames.size() - last_n)
	return frames


# ── analysis modes ─────────────────────────────────────────────────────────────
func _cmd_summary(frames: Array) -> void:
	var buckets: Dictionary = {}
	for fr: Dictionary in frames:
		var anim: String = str(fr.get("animation", "?")).get_file()
		var vel: Vector3 = _parse_vec3(str(fr.get("velocity", "(0,0,0)")))
		var speed: float = Vector2(vel.x, vel.z).length()
		if not buckets.has(anim):
			buckets[anim] = [] as Array[float]
		buckets[anim].append(speed)
	_println("%-30s %6s  %8s  %8s" % ["Animation", "Frames", "AvgSpd", "MaxSpd"])
	_println("-".repeat(58))
	var keys: Array = buckets.keys()
	keys.sort()
	for anim: String in keys:
		var speeds: Array[float] = buckets[anim]
		var avg: float = 0.0
		for sp: float in speeds:
			avg += sp
		avg /= speeds.size()
		var mx: float = 0.0
		for sp: float in speeds:
			mx = maxf(mx, sp)
		_println("%-30s %6d  %8.3f  %8.3f" % [anim, speeds.size(), avg, mx])


func _cmd_arrows(frames: Array) -> void:
	_println("%5s  %-28s  %7s  %7s  %7s" % ["Fr", "Animation", "Blue°", "Red°(rel)", "Δ°"])
	_println("-".repeat(62))
	for fr: Dictionary in frames:
		var vel: Vector3 = _parse_vec3(str(fr.get("velocity", "(0,0,0)")))
		if Vector2(vel.x, vel.z).length() < 0.3:
			continue
		var blue_deg: float = _h_angle_deg(vel)
		# Use root_relative so we compare travel angle vs torso angle both in root space
		var root_yaw: float = float(fr.get("root_yaw_deg", 0.0))
		var blue_rel: float = blue_deg - root_yaw
		var bones: Dictionary = fr.get("bones", {})
		var s2: Dictionary = bones.get("Spine2", {})
		var rot: Vector3 = _parse_vec3(str(s2.get("root_relative_rotation_deg", "(0,0,0)")))
		var red_rel: float = rot.y
		var delta: float = fmod(blue_rel - red_rel + 180.0, 360.0) - 180.0
		var anim: String = str(fr.get("animation", "?")).get_file()
		_println("%5d  %-28s  %+7.1f  %+7.1f  %+7.1f" % [
			fr.get("frame", 0), anim, blue_rel, red_rel, delta])


func _cmd_feet(frames: Array) -> void:
	_println("%5s  %-22s  %5s  %7s  %7s  %5s  %7s  %7s  %8s" % [
		"Fr", "Animation", "Lw", "L_tgt", "L_sol", "Rw", "R_tgt", "R_sol", "on_floor"])
	_println("-".repeat(88))
	for fr: Dictionary in frames:
		var feet: Dictionary = fr.get("feet", {})
		var lf: Dictionary = feet.get("left", {})
		var rf: Dictionary = feet.get("right", {})
		var anim: String = str(fr.get("animation", "?")).get_file()
		# ground_weight: 0=swing 1=planted; smoothed_target.y = IK target; solved_foot_pos.y = result
		var l_tgt: Vector3 = _parse_vec3(str(lf.get("smoothed_target", "(0,0,0)")))
		var l_sol: Vector3 = _parse_vec3(str(lf.get("solved_foot_pos", "(0,0,0)")))
		var r_tgt: Vector3 = _parse_vec3(str(rf.get("smoothed_target", "(0,0,0)")))
		var r_sol: Vector3 = _parse_vec3(str(rf.get("solved_foot_pos", "(0,0,0)")))
		_println("%5d  %-22s  %5.2f  %7.3f  %7.3f  %5.2f  %7.3f  %7.3f  %8s" % [
			fr.get("frame", 0), anim,
			float(lf.get("ground_weight", 0.0)), l_tgt.y, l_sol.y,
			float(rf.get("ground_weight", 0.0)), r_tgt.y, r_sol.y,
			str(fr.get("on_floor", "?"))])


func _cmd_bones(frames: Array, bone_names: Array) -> void:
	var header: String = "%5s  %-22s" % ["Fr", "Anim"]
	for b: String in bone_names:
		header += "  %8s  %8s  %8s" % [b + " rx", b + " ry", b + " rz"]
	_println(header)
	_println("-".repeat(30 + 28 * bone_names.size()))
	for fr: Dictionary in frames:
		var row: String = "%5d  %-22s" % [fr.get("frame", 0),
				str(fr.get("animation", "?")).get_file()]
		var bones: Dictionary = fr.get("bones", {})
		for b: String in bone_names:
			var rot := _parse_vec3(str(bones.get(b, {}).get("rotation_deg", "(0,0,0)")))
			row += "  %8.2f  %8.2f  %8.2f" % [rot.x, rot.y, rot.z]
		_println(row)


# ── arg parsing ────────────────────────────────────────────────────────────────
func _parse_args() -> Dictionary:
	var raw := OS.get_cmdline_user_args()
	var opts: Dictionary = {
		"trace": DEFAULT_TRACE,
		"last_n": 40,
		"anim": "",
		"summary": false,
		"arrows": false,
		"feet": false,
		"bones": [],
	}
	var i := 0
	while i < raw.size():
		var tok: String = raw[i]
		match tok:
			"--trace":
				i += 1
				if i < raw.size():
					opts["trace"] = raw[i]
			"--last-n":
				i += 1
				if i < raw.size():
					opts["last_n"] = raw[i].to_int()
			"--anim":
				i += 1
				if i < raw.size():
					opts["anim"] = raw[i]
			"--summary":
				opts["summary"] = true
			"--arrows":
				opts["arrows"] = true
			"--feet":
				opts["feet"] = true
			"--bones":
				i += 1
				while i < raw.size() and not raw[i].begins_with("-"):
					(opts["bones"] as Array).append(raw[i])
					i += 1
				continue
		i += 1
	return opts


# ── entry point ────────────────────────────────────────────────────────────────
func _init() -> void:
	var opts := _parse_args()

	# Resolve user:// path to filesystem path when given as default
	var trace_path: String = opts["trace"]
	if trace_path.begins_with("user://"):
		trace_path = ProjectSettings.globalize_path(trace_path)

	var frames := _load_frames(trace_path, opts["last_n"], opts["anim"])
	if frames.is_empty():
		_println("No matching frames found in: " + trace_path)
		_token_footer()
		quit(1)
		return

	var ran_any := false
	if opts["summary"]:
		_cmd_summary(frames)
		ran_any = true
	if opts["arrows"]:
		_cmd_arrows(frames)
		ran_any = true
	if opts["feet"]:
		_cmd_feet(frames)
		ran_any = true
	if not (opts["bones"] as Array).is_empty():
		_cmd_bones(frames, opts["bones"])
		ran_any = true

	if not ran_any:
		_println("No mode selected. Use --summary, --arrows, --feet, or --bones BONE…")

	_token_footer()
	quit(0)


func _token_footer() -> void:
	var total_chars: int = 0
	for line: String in _out:
		total_chars += line.length() + 1  # +1 for newline
	var est_tokens: int = int(ceil(total_chars / 4.0))
	print("")
	print("── output stats: %d chars | ~%d tokens ──" % [total_chars, est_tokens])
