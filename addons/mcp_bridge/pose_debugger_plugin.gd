extends EditorDebuggerPlugin

## Captures "mcp:*" debugger messages sent by
## tools/character_editor/character_editor.gd (see its
## _on_mcp_debugger_message) from the scene actually playing in the editor,
## and lets commands.gd send commands down to it. This is the live
## counterpart to server.py's invocation-based tools, which only ever read
## or configure a fresh, disposable headless process instead of the
## playing instance.
##
## Also handles "mcp:import_asset_request" ambiently (not through
## commands.gd's request/response cycle, which only ever runs in response
## to an external MCP tool call) - the character editor's own "Import
## Character.../Import Animation..." buttons need to copy a file into the
## project AND trigger Godot's importer on it, and only the actual editor
## process can run the importer. The played scene can't call
## EditorInterface itself, so it asks the editor side to do it via this
## same debugger-message channel, just initiated from the runtime instead
## of from an external tool.

signal message_received(message: String, data: Array)


func _init() -> void:
	message_received.connect(_on_message_received)


func _has_capture(capture: String) -> bool:
	return capture == "mcp"


func _capture(message: String, data: Array, _session_id: int) -> bool:
	message_received.emit(message, data)
	return true


func send_to_runtime(message: String, data: Array) -> bool:
	var sent := false
	for session in get_sessions():
		if session.is_active():
			session.send_message(message, data)
			sent = true
	return sent


func _on_message_received(message: String, data: Array) -> void:
	if message == "mcp:import_asset_request":
		var source_path := String(data[0]) if data.size() > 0 else ""
		var dest_res_path := String(data[1]) if data.size() > 1 else ""
		var result := _import_asset(source_path, dest_res_path)
		send_to_runtime("mcp:import_asset_result", [JSON.stringify(result)])


## Copies source_path (an absolute OS filesystem path, from the runtime's
## native file dialog) to dest_res_path (a res:// path) and forces Godot's
## importer to run on it immediately - update_file() alone only registers
## the file with the filesystem cache, reimport_files() is what actually
## generates the .import metadata new files need before they're loadable.
func _import_asset(source_path: String, dest_res_path: String) -> Dictionary:
	if source_path.is_empty() or dest_res_path.is_empty():
		return {"ok": false, "error": "Missing source or destination path"}
	if not FileAccess.file_exists(source_path):
		return {"ok": false, "error": "Source file not found: %s" % source_path}
	var dest_absolute := ProjectSettings.globalize_path(dest_res_path)
	DirAccess.make_dir_recursive_absolute(dest_absolute.get_base_dir())
	var copy_err := DirAccess.copy_absolute(source_path, dest_absolute)
	if copy_err != OK:
		return {"ok": false, "error": "Copy failed: %s" % error_string(copy_err)}
	var efs := EditorInterface.get_resource_filesystem()
	efs.update_file(dest_res_path)
	efs.reimport_files(PackedStringArray([dest_res_path]))
	return {"ok": true, "path": dest_res_path}
