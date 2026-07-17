extends RefCounted

## All actual mcp_bridge command logic lives here, not in plugin.gd, and is
## reloaded fresh from disk on every request via
## ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) - see
## plugin.gd's _handle_command(). Editing this file takes effect on the very
## next bridge call, no editor restart or plugin toggle required. Contrast
## with plugin.gd itself and pose_debugger_plugin.gd, which Godot only ever
## instantiates once (via _enter_tree()/add_debugger_plugin()) and so do
## need a restart or explicit reload_bridge to pick up changes.


static func handle(request: Dictionary, editor_interface: EditorInterface, pose_debugger):
	match String(request.get("cmd", "")):
		"open_scene":
			return _cmd_open_scene(request, editor_interface)
		"select_node":
			return _cmd_select_node(request, editor_interface)
		"get_state":
			return _cmd_get_state(editor_interface)
		"play_scene":
			return _cmd_play_scene(editor_interface)
		"stop_scene":
			return _cmd_stop_scene(editor_interface)
		"dump_live_pose":
			return await _cmd_dump_live_pose(request, editor_interface, pose_debugger)
		"set_bone_rotation":
			return await _cmd_set_bone_rotation(request, editor_interface, pose_debugger)
		"set_object":
			return await _cmd_set_object(request, editor_interface, pose_debugger)
		"capture_live_pose":
			return await _cmd_capture_live_pose(request, editor_interface, pose_debugger)
		var other:
			return {"ok": false, "error": "Unknown cmd: %s" % other}


static func _cmd_open_scene(request: Dictionary, editor_interface: EditorInterface) -> Dictionary:
	var path := String(request.get("path", ""))
	if path.is_empty():
		return {"ok": false, "error": "Missing 'path'"}
	if not ResourceLoader.exists(path):
		return {"ok": false, "error": "No resource at %s" % path}
	editor_interface.open_scene_from_path(path)
	editor_interface.set_main_screen_editor("3D")
	return {"ok": true, "result": "Opened %s" % path}


static func _cmd_select_node(request: Dictionary, editor_interface: EditorInterface) -> Dictionary:
	var node_path := String(request.get("node_path", ""))
	if node_path.is_empty():
		return {"ok": false, "error": "Missing 'node_path'"}
	var root := editor_interface.get_edited_scene_root()
	if root == null:
		return {"ok": false, "error": "No scene is currently open in the editor"}
	var node := root.get_node_or_null(NodePath(node_path))
	if node == null:
		return {"ok": false, "error": "No node at %s in the current edited scene" % node_path}
	var selection := editor_interface.get_selection()
	selection.clear()
	selection.add_node(node)
	return {"ok": true, "result": "Selected %s" % String(node.get_path())}


static func _cmd_play_scene(editor_interface: EditorInterface) -> Dictionary:
	var root := editor_interface.get_edited_scene_root()
	if root == null:
		return {"ok": false, "error": "No scene is currently open in the editor"}
	editor_interface.play_current_scene()
	return {"ok": true, "result": "Playing %s" % root.scene_file_path}


static func _cmd_stop_scene(editor_interface: EditorInterface) -> Dictionary:
	editor_interface.stop_playing_scene()
	return {"ok": true, "result": "Stopped"}


static func _cmd_dump_live_pose(request: Dictionary, editor_interface: EditorInterface, pose_debugger) -> Dictionary:
	if pose_debugger == null:
		return {"ok": false, "error": "Pose debugger plugin not initialized"}
	if not editor_interface.is_playing_scene():
		return {"ok": false, "error": "No scene is currently playing - call play_scene first"}
	var name_filter := String(request.get("name_filter", ""))
	if not pose_debugger.send_to_runtime("mcp:request_pose_dump", [name_filter]):
		return {"ok": false, "error": "No active debugger session to query"}
	var data = await _wait_for_message(pose_debugger, "mcp:pose_dump", 5.0)
	if data == null:
		return {"ok": false, "error": "Timed out waiting for a pose dump from the running scene"}
	var payload: String = data[0] if data.size() > 0 else "{}"
	var parsed = JSON.parse_string(payload)
	return {"ok": true, "result": (parsed if typeof(parsed) == TYPE_DICTIONARY else {})}


static func _cmd_set_bone_rotation(request: Dictionary, editor_interface: EditorInterface, pose_debugger) -> Dictionary:
	if pose_debugger == null:
		return {"ok": false, "error": "Pose debugger plugin not initialized"}
	if not editor_interface.is_playing_scene():
		return {"ok": false, "error": "No scene is currently playing - call play_scene first"}
	var bone := String(request.get("bone", ""))
	if bone.is_empty():
		return {"ok": false, "error": "Missing 'bone'"}
	var args := [
		bone,
		float(request.get("x", 0.0)),
		float(request.get("y", 0.0)),
		float(request.get("z", 0.0)),
	]
	if not pose_debugger.send_to_runtime("mcp:set_bone_rotation", args):
		return {"ok": false, "error": "No active debugger session to query"}
	return await _wait_for_command_result(pose_debugger, 5.0)


static func _cmd_set_object(request: Dictionary, editor_interface: EditorInterface, pose_debugger) -> Dictionary:
	if pose_debugger == null:
		return {"ok": false, "error": "Pose debugger plugin not initialized"}
	if not editor_interface.is_playing_scene():
		return {"ok": false, "error": "No scene is currently playing - call play_scene first"}
	var payload := {
		"position": request.get("position"),
		"rotation": request.get("rotation"),
		"scale": request.get("scale"),
	}
	if not pose_debugger.send_to_runtime("mcp:set_object_transform", [JSON.stringify(payload)]):
		return {"ok": false, "error": "No active debugger session to query"}
	return await _wait_for_command_result(pose_debugger, 5.0)


static func _cmd_capture_live_pose(request: Dictionary, editor_interface: EditorInterface, pose_debugger) -> Dictionary:
	if pose_debugger == null:
		return {"ok": false, "error": "Pose debugger plugin not initialized"}
	if not editor_interface.is_playing_scene():
		return {"ok": false, "error": "No scene is currently playing - call play_scene first"}
	var path := String(request.get("path", ""))
	if path.is_empty():
		return {"ok": false, "error": "Missing 'path'"}
	if not pose_debugger.send_to_runtime("mcp:capture_screenshot", [path]):
		return {"ok": false, "error": "No active debugger session to query"}
	return await _wait_for_command_result(pose_debugger, 8.0)


static func _wait_for_command_result(pose_debugger, timeout_seconds: float) -> Dictionary:
	var data = await _wait_for_message(pose_debugger, "mcp:command_result", timeout_seconds)
	if data == null:
		return {"ok": false, "error": "Timed out waiting for confirmation from the running scene"}
	var payload: String = data[0] if data.size() > 0 else "{}"
	var parsed = JSON.parse_string(payload)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Malformed command_result payload"}
	return parsed


static func _wait_for_message(pose_debugger, expected_message: String, timeout_seconds: float):
	# See plugin.gd's history: GDScript lambdas capture local value-type
	# variables by value at creation time, not by reference - use a
	# Dictionary (reference type) to carry state across the closure.
	var state := {"data": null, "done": false}
	var callback := func(message: String, data: Array) -> void:
		if message == expected_message:
			state["data"] = data
			state["done"] = true
	pose_debugger.message_received.connect(callback)
	var tree := Engine.get_main_loop() as SceneTree
	var start_msec := Time.get_ticks_msec()
	while not state["done"] and (Time.get_ticks_msec() - start_msec) < timeout_seconds * 1000.0:
		await tree.process_frame
	if pose_debugger.message_received.is_connected(callback):
		pose_debugger.message_received.disconnect(callback)
	return state["data"]


static func _cmd_get_state(editor_interface: EditorInterface) -> Dictionary:
	var root := editor_interface.get_edited_scene_root()
	var selection := editor_interface.get_selection()
	var selected_paths: Array = []
	for node in selection.get_selected_nodes():
		selected_paths.append(String(node.get_path()))
	return {
		"ok": true,
		"result": {
			"current_scene": (root.scene_file_path if root else null),
			"edited_scene_root": (root.name if root else null),
			"selected_nodes": selected_paths,
			"is_playing_scene": editor_interface.is_playing_scene(),
		},
	}
