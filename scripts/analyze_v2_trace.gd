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
##   --slide           foot skating: horizontal travel of a planted foot per planted stretch
##   --vertical        does the body bob? root / hips height vs their smooth path, walking only
##   --track <side>    one foot frame by frame (with --from/--to): pose, ground, plant, lift
##   --snaps           per-frame foot/knee motion by surface + animation, spikes and reversals
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
	if opts.has("snaps"):
		_cmd_snaps(frames)
		ran = true
	if opts.has("landing"):
		_cmd_landing(frames)
		ran = true
	if opts.has("slide"):
		_cmd_slide(frames)
		ran = true
	if opts.has("vertical"):
		_cmd_vertical(frames)
		ran = true
	if opts.has("track"):
		_cmd_track(frames, str(opts["track"]))
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
			"--track":
				i += 1
				opts["track"] = raw[i] if i < raw.size() else "left"
			"--step":
				i += 1
				opts["step"] = maxi(1, raw[i].to_int() if i < raw.size() else 20)
			"--segments", "--tips", "--released", "--body", "--misses", "--snaps", "--vertical", \
			"--slide", "--landing":
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


# ── --snaps ───────────────────────────────────────────────────────────────────────────
## Frame-to-frame leg motion (only consecutive physics frames): how far the foot / knee moved and
## how much the knee and foot rotated, split by the surface under the foot (stairs vs floor vs
## ramp), plus the biggest spikes and back-and-forth reversals (foot moves > 1 cm one way, then
## the other).
func _cmd_snaps(frames: Array[Dictionary]) -> void:
	print("\nSNAPS (per-frame leg motion; frame gap 1 only)")
	var groups := {}
	var spikes: Array = []
	var reversals := {}
	for i in range(1, frames.size()):
		var prev := frames[i - 1]
		var cur := frames[i]
		if int(cur.get("frame", 0)) - int(prev.get("frame", 0)) != 1:
			continue
		# a teleport (the check scene moves the player between surfaces) is not leg motion
		if _dist(prev.get("root"), cur.get("root")) > 0.2:
			continue
		for side in SIDES:
			var a := _foot(prev, side)
			var b := _foot(cur, side)
			var group := "%s %s" % [_kind(str(b.get("surface", ""))), _anim(cur)]
			if not groups.has(group):
				groups[group] = {"foot": [] as Array[float], "knee": [] as Array[float],
						"knee_rot": [] as Array[float], "foot_rot": [] as Array[float],
						"hips": [] as Array[float], "drop": [] as Array[float]}
			var data: Dictionary = groups[group]
			var foot_move := _dist(a.get("foot_pos"), b.get("foot_pos"))
			var knee_move := _dist(_joint(a, "knee", "position"), _joint(b, "knee", "position"))
			var knee_rot := _rot_deg(_joint(a, "knee", "rotation_quaternion"),
					_joint(b, "knee", "rotation_quaternion"))
			var foot_rot := _rot_deg(_joint(a, "foot", "rotation_quaternion"),
					_joint(b, "foot", "rotation_quaternion"))
			(data["foot"] as Array[float]).append(foot_move)
			(data["knee"] as Array[float]).append(knee_move)
			(data["knee_rot"] as Array[float]).append(knee_rot)
			(data["foot_rot"] as Array[float]).append(foot_rot)
			var body_a: Dictionary = prev.get("body", {})
			var body_b: Dictionary = cur.get("body", {})
			if side == "left": # body values are per frame, not per foot
				(data["hips"] as Array[float]).append(absf(
						_num(body_b.get("hips_above_root"), 0.0)
						- _num(body_a.get("hips_above_root"), 0.0)))
				(data["drop"] as Array[float]).append(absf(
						_num(body_b.get("pelvis_drop"), 0.0) - _num(body_a.get("pelvis_drop"), 0.0)))
			spikes.append([foot_move, int(cur.get("frame", 0)), side, group,
					knee_rot, foot_rot, b.get("state"), b.get("skip_reason"), b.get("toe_lift")])
			if i >= 2:
				var before := frames[i - 2]
				var d1 := _delta(_foot(before, side).get("foot_pos"), a.get("foot_pos"))
				var d2 := _delta(a.get("foot_pos"), b.get("foot_pos"))
				if d1.length() > 0.01 and d2.length() > 0.01 and d1.dot(d2) < 0.0:
					reversals[group] = int(reversals.get(group, 0)) + 1
	var keys := groups.keys()
	keys.sort()
	print("%-34s %6s  foot m/frame med/p95/max   knee rot deg med/p95/max   reversals  "
			% ["surface animation", "n"] + "hips m/frame p95 | pelvis-drop m/frame p95")
	for key: String in keys:
		var data: Dictionary = groups[key]
		var foot: Array[float] = data["foot"]
		var knee_rot: Array[float] = data["knee_rot"]
		if foot.size() < 5:
			continue
		print("%-34s %6d  %.3f / %.3f / %.3f       %5.1f / %5.1f / %5.1f      %d          %.4f | %.4f" % [
				key, foot.size(), _median(foot), _percentile(foot, 0.95), _percentile(foot, 1.0),
				_median(knee_rot), _percentile(knee_rot, 0.95), _percentile(knee_rot, 1.0),
				int(reversals.get(key, 0)), _percentile(data["hips"], 0.95),
				_percentile(data["drop"], 0.95)])
	spikes.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print("\nBiggest foot jumps (m in one frame):")
	for row: Array in spikes.slice(0, 10):
		print("f%d %-5s %-30s foot=%.3f knee_rot=%.1f foot_rot=%.1f %s/%s toe_lift=%s" % [row[1],
				row[2], row[3], row[0], row[4], row[5], row[6], row[7], row[8]])


static func _kind(surface: String) -> String:
	if surface.begins_with("Stair"):
		return "stairs"
	if surface.begins_with("Ramp"):
		return "ramp"
	return "floor" if surface != "" else "none"


static func _joint(foot: Dictionary, name: String, key: String) -> Variant:
	return ((foot.get("joints", {}) as Dictionary).get(name, {}) as Dictionary).get(key)


static func _delta(a: Variant, b: Variant) -> Vector3:
	if a is Array and b is Array and (a as Array).size() >= 3 and (b as Array).size() >= 3:
		return Vector3(float(b[0]) - float(a[0]), float(b[1]) - float(a[1]),
				float(b[2]) - float(a[2]))
	return Vector3.ZERO


static func _dist(a: Variant, b: Variant) -> float:
	return _delta(a, b).length()


static func _rot_deg(a: Variant, b: Variant) -> float:
	if a is Array and b is Array and (a as Array).size() >= 4 and (b as Array).size() >= 4:
		var qa := Quaternion(float(a[0]), float(a[1]), float(a[2]), float(a[3])).normalized()
		var qb := Quaternion(float(b[0]), float(b[1]), float(b[2]), float(b[3])).normalized()
		return rad_to_deg(qa.angle_to(qb))
	return 0.0


static func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return NAN
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[mini(sorted.size() - 1, int(fraction * float(sorted.size() - 1) + 0.5))]


# ── --slide ───────────────────────────────────────────────────────────────────────────
## Foot skating. A planted foot (plant weight >= 0.95, on the floor) should stay where it landed
## until the animation lifts it. For each such stretch: how far the foot travelled horizontally
## between its first and last planted frame (`slide`), how long it lasted, and its mean sliding
## speed. By surface.
func _cmd_slide(frames: Array[Dictionary]) -> void:
	print("\nSLIDE (horizontal travel of a planted foot per planted stretch; walking only)")
	var groups := {}
	for side in SIDES:
		var start: Variant = null
		var last: Variant = null
		var length := 0
		var kind := ""
		var previous_frame := -10
		for record: Dictionary in frames:
			var foot := _foot(record, side)
			var consecutive := start == null or int(record.get("frame", 0)) - previous_frame == 1
			var planted: bool = (consecutive and _num(foot.get("plant_weight"), 1.0) >= 0.95
					and str(foot.get("state", "")) != "released"
					and _anim(record).begins_with("unarmed_walk"))
			previous_frame = int(record.get("frame", 0))
			if planted:
				var pos: Variant = foot.get("foot_pos")
				if start == null:
					start = pos
					kind = _kind(str(foot.get("surface", "")))
				last = pos
				length += 1
				continue
			if start != null and length >= 5:
				_add_slide(groups, kind, _horizontal(start, last), length)
			start = null
			length = 0
	var keys := groups.keys()
	keys.sort()
	print("%-8s %5s  slide m med/p95/max      stretch frames med   speed m/s (slide / time)" % [
			"surface", "n"])
	for key: String in keys:
		var data: Dictionary = groups[key]
		var slides: Array[float] = data["slide"]
		var lengths: Array[float] = data["length"]
		var speeds: Array[float] = data["speed"]
		print("%-8s %5d  %.3f / %.3f / %.3f     %5.0f                 %.2f (median)" % [key,
				slides.size(), _median(slides), _percentile(slides, 0.95),
				_percentile(slides, 1.0), _median(lengths), _median(speeds)])


func _add_slide(groups: Dictionary, kind: String, slide: float, length: int) -> void:
	if not groups.has(kind):
		groups[kind] = {"slide": [] as Array[float], "length": [] as Array[float],
				"speed": [] as Array[float]}
	(groups[kind]["slide"] as Array[float]).append(slide)
	(groups[kind]["length"] as Array[float]).append(float(length))
	(groups[kind]["speed"] as Array[float]).append(slide / (float(length) / 60.0))


static func _horizontal(a: Variant, b: Variant) -> float:
	var d := _delta(a, b)
	return Vector2(d.x, d.z).length()


# ── --landing ─────────────────────────────────────────────────────────────────────────
## How planted feet sit on the stairs: for every planted foot frame (plant weight >= 0.95, on a
## stair) is the whole sole on ONE flat tread (tip and heel both within a few cm of the surface
## under them), or only partly supported - the heel hanging over an edge (the surface under it much
## lower: heel clearance is null in the trace) or up in the air, or the tip over an edge.
func _cmd_landing(frames: Array[Dictionary]) -> void:
	print("\nLANDING (planted feet on stairs)")
	var counts := {}
	var examples := {}
	for record: Dictionary in frames:
		for side in SIDES:
			var foot := _foot(record, side)
			if _kind(str(foot.get("surface", ""))) != "stairs":
				continue
			if _num(foot.get("plant_weight"), 1.0) < 0.95 or str(foot.get("state", "")) == "released":
				continue
			var tip_clearance: Variant = foot.get("tip_clearance")
			var heel_clearance: Variant = foot.get("heel_clearance")
			var tip_text := "tip_over_edge" if tip_clearance == null else (
					"tip_up" if float(tip_clearance) > 0.04 else "tip_ok")
			var heel_text := "heel_over_edge" if heel_clearance == null else (
					"heel_up" if float(heel_clearance) > 0.04 else "heel_ok")
			var key := "%s + %s" % [tip_text, heel_text]
			counts[key] = int(counts.get(key, 0)) + 1
			if key != "tip_ok + heel_ok" and not examples.has(key):
				examples[key] = "f%d %s %s" % [int(record.get("frame", 0)), side,
						foot.get("surface")]
	var total := 0
	for key: String in counts:
		total += int(counts[key])
	var keys := counts.keys()
	keys.sort()
	for key: String in keys:
		print("%-32s %5d  (%4.1f%%)  %s" % [key, int(counts[key]),
				100.0 * float(counts[key]) / float(maxi(total, 1)), examples.get(key, "")])


# ── --vertical ────────────────────────────────────────────────────────────────────────
## Does the whole body bob? Height of the root (the capsule) and of the hips in the world, each
## minus its own moving average (+-10 frames, so the climb itself is removed): how far above /
## below the smooth path it wanders, per surface and animation. Walking only.
func _cmd_vertical(frames: Array[Dictionary]) -> void:
	print("\nVERTICAL (deviation from the smooth path, m; window +-10 frames, walking only)")
	var groups := {}
	var half := 10
	for i in range(half, frames.size() - half):
		var record := frames[i]
		if not _anim(record).begins_with("unarmed_walk"):
			continue
		var span := int(frames[i + half].get("frame", 0)) - int(frames[i - half].get("frame", 0))
		if span != 2 * half:
			continue
		var root_mean := 0.0
		var hips_mean := 0.0
		for j in range(i - half, i + half + 1):
			root_mean += _root_y(frames[j])
			hips_mean += _hips_y(frames[j])
		root_mean /= float(2 * half + 1)
		hips_mean /= float(2 * half + 1)
		var key := "%s %s" % [_kind(str(_foot(record, "left").get("surface", ""))), _anim(record)]
		if not groups.has(key):
			groups[key] = {"root": [] as Array[float], "hips": [] as Array[float]}
		(groups[key]["root"] as Array[float]).append(absf(_root_y(record) - root_mean))
		(groups[key]["hips"] as Array[float]).append(absf(_hips_y(record) - hips_mean))
	var keys := groups.keys()
	keys.sort()
	print("%-30s %6s  root dev med/p95/max      hips dev med/p95/max" % ["surface animation", "n"])
	for key: String in keys:
		var root: Array[float] = groups[key]["root"]
		var hips: Array[float] = groups[key]["hips"]
		if root.size() < 10:
			continue
		print("%-30s %6d  %.3f / %.3f / %.3f      %.3f / %.3f / %.3f" % [key, root.size(),
				_median(root), _percentile(root, 0.95), _percentile(root, 1.0),
				_median(hips), _percentile(hips, 0.95), _percentile(hips, 1.0)])


static func _root_y(record: Dictionary) -> float:
	var root: Variant = record.get("root")
	return float((root as Array)[1]) if root is Array else 0.0


static func _hips_y(record: Dictionary) -> float:
	var body: Dictionary = record.get("body", {})
	return _root_y(record) + _num(body.get("hips_above_root"), 0.0)


# ── --track ───────────────────────────────────────────────────────────────────────────
## One foot, frame by frame (use with --from / --to): position, the ground and target it chased,
## its state and how planted it is - for reading a jitter or a snap in detail.
func _cmd_track(frames: Array[Dictionary], side: String) -> void:
	print("\nTRACK %s: frame state foot(x,y,z) d_foot ground_y anim_y plant lift shift surface"
			% side)
	var previous: Variant = null
	for record: Dictionary in frames:
		var foot := _foot(record, side)
		var pos: Variant = foot.get("foot_pos")
		var moved := 0.0 if previous == null else _dist(previous, pos)
		previous = pos
		var ground: Variant = foot.get("ground")
		var anim: Variant = foot.get("animated_ankle")
		print("f%d %-22s %s %.3f  g=%.2f a=%.2f p=%.2f lift=%.3f sh=%.2f %s" % [
				int(record.get("frame", 0)),
				"%s/%s" % [foot.get("state", "?"), foot.get("skip_reason", "")], _v3(pos), moved,
				float((ground as Array)[1]) if ground is Array else 0.0,
				float((anim as Array)[1]) if anim is Array else 0.0,
				_num(foot.get("plant_weight"), 1.0), _num(foot.get("toe_lift"), 0.0),
				_num(foot.get("stance_shift"), 0.0), foot.get("surface")])


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
		print("f%d %-14s root_y=%.2f hips_y=%.3f hips_above_root=%.2f drop=%.3f lag=%.3f on=%s" % [
				int(record.get("frame", 0)), _anim(record), _root_y(record), _hips_y(record),
				_num(body.get("hips_above_root"), -1.0), _num(body.get("pelvis_drop"), 0.0),
				_num(body.get("body_lag"), 0.0), ",".join(on)])


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
