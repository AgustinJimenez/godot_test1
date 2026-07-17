"""TCP client for the addons/mcp_bridge EditorPlugin.

Talks to an already-running Godot editor instance (if the plugin is enabled
and loaded) over a local, newline-delimited JSON protocol - see
addons/mcp_bridge/plugin.gd for the wire format and the matching server
side. This is a separate path from server.py's _run_godot(): it controls
the live editor UI itself, not a disposable headless/movie-render
subprocess, so the human looking at the editor and the agent see the same
scene.
"""

import json
import socket

HOST = "127.0.0.1"
PORT = 8791
TIMEOUT_SECONDS = 5.0


class EditorBridgeError(RuntimeError):
    pass


def send_command(payload: dict, timeout: float = TIMEOUT_SECONDS) -> object:
    try:
        with socket.create_connection((HOST, PORT), timeout=timeout) as sock:
            sock.sendall((json.dumps(payload) + "\n").encode("utf-8"))
            buffer = b""
            while b"\n" not in buffer:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                buffer += chunk
    except OSError as exc:
        raise EditorBridgeError(
            f"Could not reach the editor bridge at {HOST}:{PORT} - is the Godot "
            f"editor running with the mcp_bridge plugin enabled? ({exc})"
        ) from exc

    if not buffer:
        raise EditorBridgeError("Editor bridge closed the connection with no response")

    line, _, _ = buffer.partition(b"\n")
    response = json.loads(line.decode("utf-8"))
    if not response.get("ok", False):
        raise EditorBridgeError(response.get("error", "Unknown editor bridge error"))
    return response.get("result")
