extends Node
## Standalone engine-wide perf probe for the v2 lab - same design as v1's foot_ik_perf_probe.gd.
## Opt-in: set FOOT_IK_V2_PERF_LOG=1. Prints engine-wide counters once per second so a real FPS
## drop can be attributed to render/physics/object growth instead of guessed at.
const DEBUG_TIMER := preload("res://actors/player/foot_ik_v2/foot_ik_v2_debug.gd")
var _enabled := OS.get_environment("FOOT_IK_V2_PERF_LOG") == "1"
var _window_start_frame := 0
var _known_node_paths: Dictionary = {} # NodePath (as string) -> true, snapshot from last window


func _physics_process(_delta: float) -> void:
	if not _enabled:
		set_physics_process(false)
		return
	var frame := Engine.get_physics_frames()
	if frame - _window_start_frame < 60:
		return
	_window_start_frame = frame
	print(("[FOOT_IK_V2_ENGINE_PERF] frame=%d fps=%.1f process_ms=%.2f physics_ms=%.2f " +
			"objects=%d nodes=%d orphan_nodes=%d static_mem_mb=%.2f draw_calls=%d " +
			"primitives=%d video_mem_mb=%.2f") % [
			frame,
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.OBJECT_COUNT),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	_diff_node_tree()
	if DEBUG_TIMER.enabled:
		print(DEBUG_TIMER.report())


func _diff_node_tree() -> void:
	var root := get_tree().root
	var current: Dictionary = {}
	_collect_paths(root, current)
	if not _known_node_paths.is_empty():
		var added: Array[String] = []
		for path in current:
			if not _known_node_paths.has(path):
				added.append(path)
		if not added.is_empty():
			var by_parent_class: Dictionary = {} # "parent_path|ClassName" -> count
			for path in added:
				var node := root.get_node_or_null(NodePath(path))
				var parent_path := String(node.get_parent().get_path()) if node and node.get_parent() else "?"
				var class_name_str := node.get_class() if node else "?"
				var key := "%s|%s" % [parent_path, class_name_str]
				by_parent_class[key] = int(by_parent_class.get(key, 0)) + 1
			print("[FOOT_IK_V2_NODE_SPAWN] +%d nodes this window:" % added.size())
			for key in by_parent_class:
				var parts: PackedStringArray = key.split("|")
				print("    parent=%s class=%s count=%d" % [parts[0], parts[1], by_parent_class[key]])
	_known_node_paths = current


func _collect_paths(node: Node, out: Dictionary) -> void:
	out[String(node.get_path())] = true
	for child in node.get_children():
		_collect_paths(child, out)
