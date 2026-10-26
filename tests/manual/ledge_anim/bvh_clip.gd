extends RefCounted
## Reads a BVH file (the game's exported traversal clips). Every joint has six channels
## (Xposition Yposition Zposition Zrotation Xrotation Yrotation), Y up, metres, degrees.

var names: PackedStringArray = []
var parents: PackedInt32Array = []
var offsets: Array[Vector3] = []
var frame_time := 1.0 / 30.0
var frames: Array[PackedFloat64Array] = [] ## six floats per joint, per frame
var title := ""


static func load_file(path: String) -> RefCounted:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return null
	var clip: RefCounted = load("res://tests/manual/ledge_anim/bvh_clip.gd").new()
	clip.title = path.get_file().get_basename()
	var lines := text.split("\n")
	var stack: Array[int] = []
	var pending := -1
	var index := 0
	while index < lines.size():
		var line := lines[index].strip_edges()
		index += 1
		if line.begins_with("ROOT") or line.begins_with("JOINT"):
			clip.names.append(line.get_slice(" ", 1))
			clip.parents.append(stack.back() if not stack.is_empty() else -1)
			clip.offsets.append(Vector3.ZERO)
			pending = clip.names.size() - 1
		elif line.begins_with("End Site"):
			pending = -1
		elif line == "{":
			stack.append(pending if pending >= 0 else -2)
		elif line == "}":
			stack.pop_back()
		elif line.begins_with("OFFSET") and pending >= 0:
			var part := line.split(" ", false)
			clip.offsets[pending] = Vector3(part[1].to_float(), part[2].to_float(), part[3].to_float())
		elif line.begins_with("Frame Time:"):
			clip.frame_time = line.get_slice(":", 1).strip_edges().to_float()
			break
	while index < lines.size():
		var row := lines[index].strip_edges()
		index += 1
		if row.is_empty():
			continue
		clip.frames.append(row.split_floats(" ", false))
	return clip


func duration() -> float:
	return frame_time * maxi(frames.size() - 1, 1)


## Model-space transform of every joint at `time` (seconds; frames are blended).
func pose(time: float, loop := true) -> Array[Transform3D]:
	var count := frames.size()
	var position := time / frame_time
	var first := 0
	var second := 0
	var mix := 0.0
	if loop and count > 1:
		position = fposmod(position, float(count))
		first = int(position) % count
		second = (first + 1) % count
		mix = position - floorf(position)
	else:
		position = clampf(position, 0.0, float(count - 1))
		first = int(position)
		second = mini(first + 1, count - 1)
		mix = position - float(first)
	var a := frames[first]
	var b := frames[second]
	var out: Array[Transform3D] = []
	out.resize(names.size())
	for joint in names.size():
		var base := joint * 6
		var move := Vector3(
				lerpf(a[base], b[base], mix), lerpf(a[base + 1], b[base + 1], mix), lerpf(a[base + 2], b[base + 2], mix))
		var rotation := _rotation(a, base).slerp(_rotation(b, base), mix)
		var local := Transform3D(Basis(rotation), move) # the position channels are the whole local translation (they repeat the OFFSET)
		var parent := parents[joint]
		out[joint] = local if parent < 0 else out[parent] * local
	return out


func _rotation(values: PackedFloat64Array, base: int) -> Quaternion:
	var z := deg_to_rad(values[base + 3])
	var x := deg_to_rad(values[base + 4])
	var y := deg_to_rad(values[base + 5])
	return Quaternion(Basis(Vector3.BACK, z) * Basis(Vector3.RIGHT, x) * Basis(Vector3.UP, y))
