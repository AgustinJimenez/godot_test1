## Compact analyzer for the Foot IK v2 lab trace (`user://foot_ik_v2.jsonl`), headless GDScript:
##   scripts/trace_v2.sh [flags]
## Use this instead of ad-hoc scripts: it knows the v2 fields (tip clearance, reach decision, hips,
## pelvis drop, animation, modifiers) that scripts/trace.sh does not.
##
## Flags:
##   --trace <path>    JSONL file (default user://foot_ik_v2.jsonl)
##   --check           read user://foot_ik_v2_check.jsonl (the headless checks' trace) instead
##   --from <F> --to <F>   frame window (physics frame numbers); default whole file
##   --segments        one row per contiguous animation run: frames, per-foot state / release
##                     reasons, tip clip / float counts + worst, hips-above-root min, drop max
##   --tips            tip clip / float episodes per foot: frames, animation, worst clearance, state
##   --released        released feet by animation and reason, with median hip-to-target vs reach
##   --misses          corrected feet that ended > 3 cm from their final target (worst 12)
##   --body            hips above root, pelvis drop, modifiers; every --step frames (default 20)
##   --frame <F>       one frame in full compact form
##   --step <N>        downsample for --body (default 20)
extends SceneTree

const DEFAULT_TRACE := "user://foot_ik_v2.jsonl"
const CHECK_TRACE := "user://foot_ik_v2_check.jsonl"
const SIDES: Array[String] = ["left", "right"]
## Heel grading for --segments (same band as the sphere colours: -1.5 cm .. +3 cm is touching).
const HEEL_CLIP_TOLERANCE := 0.015
const HEEL_FLOAT_TOLERANCE := 0.06


func _init() -> void:
	var opts := _parse_args()
	var frames := _load(str(opts["trace"]), int(opts["from"]), int(opts["to"]))
	if frames.is_empty():
		print("No frames in ", opts["trace"])
		quit(1)
		return
	print("%d frames, %s .. %s, mode=%s, physics frames %d..%d" % [frames.size(),
			frames[0].get("time", "?"), frames[-1].get("time", "?"), frames[0].get("mode", "?"),
			int(frames[0].get("frame", 0)), int(frames[-1].get("frame", 0))])
	var ran := false
	if opts.has("frame"):
		_cmd_frame(frames, int(opts["frame"]))
		ran = true
	if opts.has("segments"):
		_cmd_segments(frames)
		ran = true
	if opts.has("tips"):
		_cmd_tips(frames)
		ran = true
	if opts.has("released"):
		_cmd_released(frames)
		ran = true
	if opts.has("misses"):
		_cmd_misses(frames)
		ran = true
	if opts.has("body"):
		_cmd_body(frames, int(opts["step"]))
		ran = true
	if not ran:
		print("No mode. Use --segments, --tips, --released, --body or --frame N.")
	quit(0)


func _parse_args() -> Dictionary:
	var raw := OS.get_cmdline_user_args()
	var opts := {"trace": DEFAULT_TRACE, "from": -1, "to": -1, "step": 20}
	var i := 0
	while i < raw.size():
		match raw[i]:
			"--trace":
				i += 1
				opts["trace"] = raw[i] if i < raw.size() else DEFAULT_TRACE
			"--check":
				opts["trace"] = CHECK_TRACE
			"--from":
				i += 1
				opts["from"] = raw[i].to_int() if i < raw.size() else -1
			"--to":
				i += 1
				opts["to"] = raw[i].to_int() if i < raw.size() else -1
			"--frame":
				i += 1
				opts["frame"] = raw[i].to_int() if i < raw.size() else -1
			"--step":
				i += 1
				opts["step"] = maxi(1, raw[i].to_int() if i < raw.size() else 20)
			"--segments", "--tips", "--released", "--body", "--misses":
				opts[String(raw[i]).trim_prefix("--")] = true
		i += 1
	return opts


func _load(path: String, from_frame: int, to_frame: int) -> Array[Dictionary]:
	var real := ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	var file := FileAccess.open(real, FileAccess.READ)
	var out: Array[Dictionary] = []
	if file == null:
		return out
	var parser := JSON.new()
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or parser.parse(line) != OK or not parser.data is Dictionary:
			continue
		var record: Dictionary = parser.data
		var frame := int(record.get("frame", 0))
		if (from_frame >= 0 and frame < from_frame) or (to_frame >= 0 and frame > to_frame):
			continue
		out.append(record)
	return out


static func _anim(record: Dictionary) -> String:
	return str(record.get("animation", "?")).trim_prefix("moves/")


static func _foot(record: Dictionary, side: String) -> Dictionary:
	return (record.get("feet", {}) as Dictionary).get(side, {})


static func _num(value: Variant, fallback: float = NAN) -> float:
	return float(value) if value is float or value is int else fallback


static func _median(values: Array[float]) -> float:
	if values.is_empty():
		return NAN
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


static func _v3(value: Variant) -> String:
	if value is Array and (value as Array).size() >= 3:
		var a: Array = value
		return "(%.2f,%.2f,%.2f)" % [float(a[0]), float(a[1]), float(a[2])]
	return "-"


# ── --segments ────────────────────────────────────────────────────────────────────────
func _cmd_segments(frames: Array[Dictionary]) -> void:
	print("\nSEGMENTS (contiguous animation runs)")
	var start := 0
	for i in range(1, frames.size() + 1):
		if i < frames.size() and _anim(frames[i]) == _anim(frames[start]):
			continue
		_print_segment(frames.slice(start, i))
		start = i


func _print_segment(segment: Array) -> void:
	var first: Dictionary = segment[0]
	var last: Dictionary = segment[-1]
	var hips_min := INF
	var drop_max := 0.0
	for record: Dictionary in segment:
		var body: Dictionary = record.get("body", {})
		hips_min = minf(hips_min, _num(body.get("hips_above_root"), INF))
		drop_max = maxf(drop_max, _num(body.get("pelvis_drop"), 0.0))
	var parts: PackedStringArray = []
	for side in SIDES:
		var states := {}
		var clip_n := 0
		var float_n := 0
		var clip_max := 0.0
		var float_max := 0.0
		var heel_clip_n := 0
		var heel_float_n := 0
		var heel_clip_max := 0.0
		var heel_float_max := 0.0
		for record: Dictionary in segment:
			var foot := _foot(record, side)
			var key := str(foot.get("state", "?"))
			if str(foot.get("skip_reason", "")) != "":
				key += "/" + str(foot["skip_reason"])
			states[key] = int(states.get(key, 0)) + 1
			var clearance := _num(foot.get("tip_clearance"))
			match str(foot.get("tip_event", "")):
				"TIP_CLIP":
					clip_n += 1
					clip_max = maxf(clip_max, -clearance)
				"TIP_FLOAT":
					float_n += 1
					float_max = maxf(float_max, clearance)
			var heel := _num(foot.get("heel_clearance"))
			if bool(foot.get("grounded", false)) and not is_nan(heel):
				if heel < -HEEL_CLIP_TOLERANCE:
					heel_clip_n += 1
					heel_clip_max = maxf(heel_clip_max, -heel)
				elif heel > HEEL_FLOAT_TOLERANCE:
					heel_float_n += 1
					heel_float_max = maxf(heel_float_max, heel)
		parts.append(("%s[%s toe clip=%d(%.3f) float=%d(%.3f) | heel clip=%d(%.3f) "
				+ "float=%d(%.3f)]") % [side[0].to_upper(), _states_text(states), clip_n,
				clip_max, float_n, float_max, heel_clip_n, heel_clip_max, heel_float_n,
				heel_float_max])
	print("f%d-%d %-14s n=%d hips_min=%.2f drop_max=%.3f %s" % [int(first.get("frame", 0)),
			int(last.get("frame", 0)), _anim(first), segment.size(),
			hips_min if hips_min < INF else -1.0, drop_max, " ".join(parts)])


static func _states_text(states: Dictionary) -> String:
	var keys := states.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for key: String in keys:
		parts.append("%s:%d" % [key, int(states[key])])
	return ",".join(parts)


# ── --tips ────────────────────────────────────────────────────────────────────────────
func _cmd_tips(frames: Array[Dictionary]) -> void:
	print("\nTIP EPISODES (clip / float, per foot; consecutive frames merged)")
	for side in SIDES:
		var episode: Dictionary = {}
		for record: Dictionary in frames:
			var foot := _foot(record, side)
			var kind := str(foot.get("tip_event", ""))
			var frame := int(record.get("frame", 0))
			if kind != "" and not episode.is_empty() and episode["kind"] == kind \
					and frame - int(episode["last"]) <= 2:
				_extend_episode(episode, frame, foot)
				continue
			if not episode.is_empty():
				_print_episode(side, episode)
				episode = {}
			if kind != "":
				episode = {"kind": kind, "first": frame, "last": frame, "anim": _anim(record),
						"worst": _num(foot.get("tip_clearance"), 0.0), "n": 1,
						"state": "%s/%s" % [foot.get("state", "?"), foot.get("skip_reason", "")]}
		if not episode.is_empty():
			_print_episode(side, episode)


static func _extend_episode(episode: Dictionary, frame: int, foot: Dictionary) -> void:
	episode["last"] = frame
	episode["n"] = int(episode["n"]) + 1
	var clearance := _num(foot.get("tip_clearance"), 0.0)
	if absf(clearance) > absf(float(episode["worst"])):
		episode["worst"] = clearance


static func _print_episode(side: String, episode: Dictionary) -> void:
	print("%-5s %-9s f%d-%d n=%d %-13s worst=%+.3f %s" % [side, episode["kind"],
			int(episode["first"]), int(episode["last"]), int(episode["n"]), episode["anim"],
			float(episode["worst"]), episode["state"]])


# ── --released ────────────────────────────────────────────────────────────────────────
func _cmd_released(frames: Array[Dictionary]) -> void:
	print("\nRELEASED FEET (animation, side, reason -> frames, median hip_to_target vs reach)")
	var groups := {}
	for record: Dictionary in frames:
		for side in SIDES:
			var foot := _foot(record, side)
			if str(foot.get("state", "")) != "released":
				continue
			var key := "%s %s %s" % [_anim(record), side, foot.get("skip_reason", "?")]
			if not groups.has(key):
				groups[key] = {"n": 0, "dist": [] as Array[float], "reach": [] as Array[float],
						"clr": [] as Array[float]}
			var group: Dictionary = groups[key]
			group["n"] = int(group["n"]) + 1
			var check: Dictionary = foot.get("reach_check", {})
			if check.has("hip_to_target"):
				(group["dist"] as Array[float]).append(float(check["hip_to_target"]))
				(group["reach"] as Array[float]).append(float(check["reach"]))
			var clearance := _num(foot.get("tip_clearance"))
			if not is_nan(clearance):
				(group["clr"] as Array[float]).append(clearance)
	var keys := groups.keys()
	keys.sort()
	for key: String in keys:
		var group: Dictionary = groups[key]
		print("%-40s n=%3d hip_to_target=%.3f reach=%.3f tip_clr_median=%+.3f" % [key,
				int(group["n"]), _median(group["dist"]), _median(group["reach"]),
				_median(group["clr"])])


# ── --misses ──────────────────────────────────────────────────────────────────────────
## Corrected feet that ended more than 3 cm from the target they finally chased (clamped feet are
## short of their floor by design and are left out).
func _cmd_misses(frames: Array[Dictionary]) -> void:
	print("\nMISSES (residual > 0.03 m, not clamped): worst 12")
	var rows: Array = []
	for record: Dictionary in frames:
		for side in SIDES:
			var solve: Dictionary = _foot(record, side).get("reach", {})
			var residual := _num(solve.get("residual"), 0.0)
			if residual > 0.03 and not bool(solve.get("clamped", false)):
				rows.append([residual, int(record.get("frame", 0)), side, _anim(record),
						_foot(record, side).get("toe_lift"), _foot(record, side).get("surface")])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print("%d misses" % rows.size())
	for row: Array in rows.slice(0, 12):
		print("f%d %-5s %-13s residual=%.3f toe_lift=%s surface=%s" % [row[1], row[2], row[3],
				row[0], row[4], row[5]])


# ── --body ────────────────────────────────────────────────────────────────────────────
func _cmd_body(frames: Array[Dictionary], step: int) -> void:
	print("\nBODY every %d frames (hips_above_root normal ~0.90)" % step)
	for i in range(0, frames.size(), step):
		var record := frames[i]
		var body: Dictionary = record.get("body", {})
		var mods: Dictionary = body.get("modifiers_active", {})
		var on: PackedStringArray = []
		for key: String in mods:
			if bool(mods[key]):
				on.append(key.replace("Modifier", ""))
		print("f%d %-14s root_y=%.2f hips_above_root=%.2f pelvis_drop=%.3f hover=%.3f on=%s" % [
				int(record.get("frame", 0)), _anim(record), float((record.get("root", [0, 0, 0])
				as Array)[1]), _num(body.get("hips_above_root"), -1.0),
				_num(body.get("pelvis_drop"), 0.0), _num(body.get("stair_hover_y"), 0.0),
				",".join(on)])


# ── --frame ───────────────────────────────────────────────────────────────────────────
func _cmd_frame(frames: Array[Dictionary], target: int) -> void:
	var record := frames[-1]
	for candidate: Dictionary in frames:
		if int(candidate.get("frame", -1)) == target:
			record = candidate
			break
	print("\nFRAME %d %s %s yaw=%.1f move_angle=%s root=%s v=%s" % [
			int(record.get("frame", 0)), record.get("time", ""), _anim(record),
			_num(record.get("facing_yaw_deg"), 0.0), record.get("move_angle_deg"),
			_v3(record.get("root")), _v3(record.get("velocity"))])
	var body: Dictionary = record.get("body", {})
	print("  v2_enabled=%s pelvis_drop=%.3f hips_above_root=%.2f modifiers=%s" % [
			record.get("v2_enabled"), _num(body.get("pelvis_drop"), 0.0),
			_num(body.get("hips_above_root"), -1.0), body.get("modifiers_active")])
	for side in SIDES:
		var foot := _foot(record, side)
		print("  %-5s %s/%s grounded=%s tip_clr=%s tip_event=%s surface=%s" % [side,
				foot.get("state"), foot.get("skip_reason"), foot.get("grounded"),
				foot.get("tip_clearance"), foot.get("tip_event"), foot.get("surface")])
		print("        foot=%s tip=%s heel=%s heel_clr=%s" % [
				_v3(foot.get("foot_pos")), _v3(foot.get("tip")), _v3(foot.get("heel")),
				foot.get("heel_clearance")])
		print("        anim_ankle=%s ground=%s reach_check=%s stance_shift=%s toe_lift=%s" % [
				_v3(foot.get("animated_ankle")), _v3(foot.get("ground")), foot.get("reach_check"),
				foot.get("stance_shift"), foot.get("toe_lift")])
		print("        stance_plan [shift, drop needed]: %s" % [foot.get("stance_plan")])
		var solve: Dictionary = foot.get("reach", {})
		print("        solve: needed=%s reach=%s residual=%s target_local=%s solved=%s landed=%s" % [
				solve.get("needed"), solve.get("reach"), solve.get("residual"),
				_v3(solve.get("target_local")), _v3(solve.get("solved_ankle")),
				_v3(solve.get("landed"))])
