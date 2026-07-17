extends EditorDebuggerPlugin

## Captures "mcp:*" debugger messages sent by
## tools/character_editor/character_editor.gd (see its
## _on_mcp_debugger_message) from the scene actually playing in the editor,
## and lets commands.gd send commands down to it. This is the live
## counterpart to server.py's invocation-based tools, which only ever read
## or configure a fresh, disposable headless process instead of the
## playing instance.

signal message_received(message: String, data: Array)


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
