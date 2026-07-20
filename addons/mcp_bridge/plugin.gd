@tool
extends EditorPlugin

## Lets tools/character_editor_mcp control the already-open editor instance
## (open a scene, select a node, read back current state) over a local TCP
## socket, so an agent and the human looking at the editor see the same
## thing - as opposed to the invocation-based MCP tools, which only ever
## talk to fresh, disposable headless Godot processes.
##
## Protocol: newline-delimited JSON, one request/response per connection.
## Request:  {"cmd": "open_scene", "path": "res://foo.tscn"}
## Response: {"ok": true, "result": ...} or {"ok": false, "error": "..."}
##
## Deliberately kept thin and rarely-changing: Godot instantiates an
## EditorPlugin's root script once and never re-reads it from disk, so any
## edit here needs an editor restart (or Project Settings > Plugins
## toggle-off/on) to take effect. All the actual command logic lives in
## commands.gd instead, which _handle_command() reloads fresh from disk on
## every single request via CACHE_MODE_REPLACE - so iterating on command
## behavior needs neither a restart nor a plugin toggle.

const PORT := 8791
const HOST := "127.0.0.1"
const COMMANDS_SCRIPT_PATH := "res://addons/mcp_bridge/commands.gd"
const POSE_DEBUGGER_SCRIPT_PATH := "res://addons/mcp_bridge/pose_debugger_plugin.gd"

var _server: TCPServer
var _peer: StreamPeerTCP
var _recv_buffer := PackedByteArray()
var _pose_debugger  # pose_debugger_plugin.gd instance; untyped since it has
                     # no class_name and extends the base EditorDebuggerPlugin,
                     # whose static type doesn't expose our custom members.


func _enter_tree() -> void:
	# The bridge exists for an agent sharing the visible editor. Headless import
	# and CI processes neither need it nor should contend with that editor's port.
	if DisplayServer.get_name() == "headless":
		return
	_server = TCPServer.new()
	var err := _server.listen(PORT, HOST)
	if err != OK:
		push_error("MCP bridge: failed to listen on %s:%d (%s)" % [HOST, PORT, error_string(err)])
		_server = null
		return
	_register_pose_debugger()
	set_process(true)
	print("MCP bridge: listening on %s:%d" % [HOST, PORT])


func _exit_tree() -> void:
	set_process(false)
	if _peer:
		_peer.disconnect_from_host()
		_peer = null
	if _server:
		_server.stop()
		_server = null
	_unregister_pose_debugger()


func _register_pose_debugger() -> void:
	# CACHE_MODE_REPLACE alone is not enough for GDScript specifically - see
	# _handle_command()'s identical comment for commands.gd. Without this
	# update_file() call, reload_editor_bridge silently keeps serving the
	# stale pre-edit pose_debugger_plugin.gd bytecode - confirmed by editing
	# _import_asset, calling reload_editor_bridge, and observing the editor's
	# own error log still cite the pre-edit line numbers.
	get_editor_interface().get_resource_filesystem().update_file(POSE_DEBUGGER_SCRIPT_PATH)
	var script := ResourceLoader.load(
			POSE_DEBUGGER_SCRIPT_PATH, "GDScript", ResourceLoader.CACHE_MODE_REPLACE)
	_pose_debugger = script.new()
	add_debugger_plugin(_pose_debugger)


func _unregister_pose_debugger() -> void:
	if _pose_debugger:
		remove_debugger_plugin(_pose_debugger)
		_pose_debugger = null


func _process(_delta: float) -> void:
	if _server == null:
		return
	if _peer == null and _server.is_connection_available():
		_peer = _server.take_connection()
		_recv_buffer.clear()
	if _peer == null:
		return
	_peer.poll()
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_peer = null
		return
	var available := _peer.get_available_bytes()
	if available <= 0:
		return
	var chunk := _peer.get_partial_data(available)
	if chunk[0] != OK:
		return
	_recv_buffer.append_array(chunk[1])
	_try_handle_buffered_line()


func _try_handle_buffered_line() -> void:
	var newline_index := _recv_buffer.find(10)  # "\n"
	if newline_index < 0:
		return
	var line := _recv_buffer.slice(0, newline_index).get_string_from_utf8()
	_recv_buffer = _recv_buffer.slice(newline_index + 1)
	# Hand the connection off to an async coroutine rather than handling it
	# inline here: command handling may need to await a debugger message from
	# the running scene (dump_live_pose), which can take multiple frames, and
	# _process() must not block while that's pending.
	var peer := _peer
	_peer = null
	_dispatch_command_async(line, peer)


func _dispatch_command_async(line: String, peer: StreamPeerTCP) -> void:
	var response = await _handle_command(line)
	peer.put_data((JSON.stringify(response) + "\n").to_utf8_buffer())
	peer.disconnect_from_host()


func _handle_command(line: String):
	var parsed = JSON.parse_string(line)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Request must be a JSON object"}
	var request: Dictionary = parsed
	if String(request.get("cmd", "")) == "reload_bridge":
		return _cmd_reload_bridge()
	# Reload fresh from disk on every call so edits to commands.gd take
	# effect on the very next request. CACHE_MODE_REPLACE alone isn't enough
	# for GDScript specifically - it appears to keep its own compiled-script
	# cache independent of ResourceLoader's cache mode, so update_file()
	# explicitly tells the editor's filesystem tracker the file changed
	# before the load.
	get_editor_interface().get_resource_filesystem().update_file(COMMANDS_SCRIPT_PATH)
	var commands := ResourceLoader.load(
			COMMANDS_SCRIPT_PATH, "GDScript", ResourceLoader.CACHE_MODE_REPLACE)
	return await commands.handle(request, get_editor_interface(), _pose_debugger)


func _cmd_reload_bridge() -> Dictionary:
	# pose_debugger_plugin.gd is registered once via add_debugger_plugin() and,
	# unlike commands.gd, can't just be reloaded per-call - the running
	# debugger session is bound to whichever instance was registered. This
	# re-registers a fresh instance on demand instead of requiring a full
	# editor restart or a Project Settings > Plugins toggle.
	_unregister_pose_debugger()
	_register_pose_debugger()
	return {"ok": true, "result": "Reloaded pose_debugger_plugin.gd"}
