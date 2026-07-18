"""MCP server wrapping tools/character_editor/character_editor.tscn.

Invocation-based (Option A from docs/character_editor_mcp_plan.md): every
tool call spawns a fresh Godot process with the full set of CLI arguments
needed to reach the desired state, reusing character_editor.gd's existing
`_run_automation_args()` automation interface as-is - no changes to the
Godot project. This module tracks "current desired state" itself and
re-supplies all of it on every call, since each Godot launch starts from
the tool's own defaults otherwise.

See docs/character_editor_mcp_plan.md for the full investigation this
implements.
"""

import json
import math
import re
import shutil
import subprocess
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal

from fastmcp import FastMCP
from fastmcp.utilities.types import Image

import editor_bridge

PROJECT_PATH = Path(__file__).resolve().parents[2]
SCENE_PATH = "res://tools/character_editor/character_editor.tscn"
GODOT_TIMEOUT_SECONDS = 45.0
CAPTURE_RESOLUTION = "960x540"

SCRATCH_DIR = Path(tempfile.gettempdir()) / "character_editor_mcp"
SCRATCH_DIR.mkdir(exist_ok=True)

mcp = FastMCP("character-editor")


# ---------------------------------------------------------------------------
# State tracked across calls - each Godot launch is stateless, so this is
# what makes "adjust one thing, look again" work without the caller having
# to re-specify everything by hand each time.
# ---------------------------------------------------------------------------

@dataclass
class EditorState:
	character: Literal["player", "shambler"] = "player"
	pose: str | None = None
	animation: str | None = None
	object_scene: str | None = None
	attachment_bone: str | None = None
	object_position: tuple[float, float, float] | None = None
	object_rotation: tuple[float, float, float] | None = None
	object_scale: float | None = None
	bone_overrides: dict[str, tuple[float, float, float]] = field(default_factory=dict)
	view: Literal["full", "hand", "isolated"] = "full"
	camera_angle: str | None = None
	selected_bone: str | None = None


_state = EditorState()


def _fmt_vec(v: tuple[float, float, float]) -> str:
	return f"{v[0]},{v[1]},{v[2]}"


def _build_state_args() -> list[str]:
	args: list[str] = [f"character={_state.character}"]
	if _state.pose:
		args.append(f"pose={_state.pose}")
	if _state.animation:
		args.append(f"animation={_state.animation}")
	if _state.object_scene:
		args.append(f"object={_state.object_scene}")
	if _state.attachment_bone:
		args.append(f"attachment={_state.attachment_bone}")
	if _state.object_position:
		args.append(f"object_position={_fmt_vec(_state.object_position)}")
	if _state.object_rotation:
		args.append(f"object_rotation={_fmt_vec(_state.object_rotation)}")
	if _state.object_scale is not None:
		args.append(f"object_scale={_state.object_scale}")
	if _state.bone_overrides:
		overrides = ";".join(
			f"{bone}:{_fmt_vec(rot)}" for bone, rot in _state.bone_overrides.items()
		)
		args.append(f"bones={overrides}")
	args.append(f"view={_state.view}")
	if _state.selected_bone:
		args.append(f"bone={_state.selected_bone}")
	if _state.camera_angle:
		args.append(f"angle={_state.camera_angle}")
	return args


class GodotInvocationError(RuntimeError):
	pass


def _run_godot(extra_args: list[str], want_render: bool) -> str:
	"""Spawns a fresh Godot process with current state + extra_args, returns stdout.

	want_render=True uses --write-movie for a real rendering context (needed
	for anything that reads back pixels); False uses --headless (faster, no
	GPU work, fine for pure data queries like dump_bones).
	"""
	cmd = ["godot", "--path", str(PROJECT_PATH)]
	movie_scratch = None
	if want_render:
		movie_scratch = SCRATCH_DIR / f"movie_{int(time.time() * 1000)}"
		movie_scratch.mkdir(exist_ok=True)
		cmd += [
			"--write-movie", str(movie_scratch / "frame.png"),
			"--fixed-fps", "24",
			"--resolution", CAPTURE_RESOLUTION,
		]
	else:
		cmd += ["--headless"]
	cmd += [SCENE_PATH, "--"] + _build_state_args() + extra_args

	try:
		result = subprocess.run(
			cmd, capture_output=True, text=True, timeout=GODOT_TIMEOUT_SECONDS,
		)
	except subprocess.TimeoutExpired as exc:
		raise GodotInvocationError(
			f"Godot did not exit within {GODOT_TIMEOUT_SECONDS}s "
			f"(cmd: {' '.join(cmd)})"
		) from exc
	finally:
		if movie_scratch is not None:
			# --write-movie also writes a frame.wav audio track alongside the
			# PNG frames, not just the frames themselves - remove the whole
			# scratch dir rather than assuming we know every file it wrote.
			shutil.rmtree(movie_scratch, ignore_errors=True)

	if result.returncode != 0:
		raise GodotInvocationError(
			f"Godot exited {result.returncode}.\nstdout:\n{result.stdout}\n"
			f"stderr:\n{result.stderr}"
		)
	return result.stdout


# ---------------------------------------------------------------------------
# State-mutating tools - no Godot invocation, just update what the next
# capture/dump/pick call will use.
# ---------------------------------------------------------------------------

@mcp.tool()
def select_character(kind: Literal["player", "shambler"]) -> str:
	"""Choose which character subsequent invocation-based tool calls (capture_pose, dump_bone_poses, etc.) operate on. shambler has no held-object/hand-grip/compare-mode support - those tools error against it. Clears bone overrides since they're bone-name-specific and the two characters use different skeletons (PlayerBody's MotusMan names vs Shambler's mixamorig_-prefixed Mixamo names)."""
	_state.character = kind
	_state.bone_overrides.clear()
	return f"Character set to {kind} (bone overrides cleared)"


@mcp.tool()
def load_pose(path: str) -> str:
	"""Load a saved character pose preset (res:// path to a JSON preset).

	Clears any ad-hoc bone rotation overrides from a previous call, since a
	freshly loaded preset should start clean.
	"""
	_state.pose = path
	_state.bone_overrides.clear()
	return f"Pose set to {path} (bone overrides cleared)"


@mcp.tool()
def set_animation(name: str) -> str:
	"""Select the base animation to pose from (any name PlayerBody.get_animation_groups() exposes)."""
	_state.animation = name
	return f"Animation set to {name}"


@mcp.tool()
def set_bone_rotation(bone: str, x: float, y: float, z: float) -> str:
	"""Apply an additive rotation (degrees) to one bone, layered on top of the current pose/animation."""
	_state.bone_overrides[bone] = (x, y, z)
	return f"{bone} rotation override set to ({x}, {y}, {z}) degrees"


@mcp.tool()
def clear_bone_rotation(bone: str) -> str:
	"""Remove a previously set bone rotation override."""
	_state.bone_overrides.pop(bone, None)
	return f"{bone} rotation override cleared"


@mcp.tool()
def select_bone(name: str) -> str:
	"""Select a bone by name (affects camera focus for subsequent set_camera_angle calls)."""
	_state.selected_bone = name
	return f"Selected bone: {name}"


@mcp.tool()
def set_view(mode: Literal["full", "hand", "isolated"]) -> str:
	"""Switch the editor's camera framing preset."""
	_state.view = mode
	return f"View set to {mode}"


@mcp.tool()
def set_camera_angle(
	angle: Literal["front", "back", "left", "right", "top", "bottom"],
) -> str:
	"""Orbit the focused camera to a named angle. Only has an effect once a joint has focus (see select_bone/pick_bone)."""
	_state.camera_angle = angle
	return f"Camera angle set to {angle}"


@mcp.tool()
def set_object(
	scene_path: str | None = None,
	attachment_bone: str | None = None,
	position: tuple[float, float, float] | None = None,
	rotation: tuple[float, float, float] | None = None,
	scale: float | None = None,
) -> str:
	"""Attach and position a held object (e.g. the flashlight) on a skeleton bone. Pass only the fields you want to change."""
	if scene_path is not None:
		_state.object_scene = scene_path
	if attachment_bone is not None:
		_state.attachment_bone = attachment_bone
	if position is not None:
		_state.object_position = position
	if rotation is not None:
		_state.object_rotation = rotation
	if scale is not None:
		_state.object_scale = scale
	return "Object state updated"


@mcp.tool()
def reset_state() -> str:
	"""Clear all tracked state back to defaults (does not affect saved preset files)."""
	global _state
	_state = EditorState()
	return "State reset to defaults"


# ---------------------------------------------------------------------------
# Godot-invoking tools - these actually spawn a process.
# ---------------------------------------------------------------------------

@mcp.tool()
def pick_bone(screen_x: float, screen_y: float) -> str:
	"""Simulate a click at a screen position (in the capture resolution's coordinate space) and select whichever bone is nearest."""
	# character_editor.gd only calls get_tree().quit() when `capture=` or
	# `dump_bones=` is present in the automation args - `pick=` alone leaves
	# the process open for human interaction and the invocation would hang
	# until GODOT_TIMEOUT_SECONDS. Tack on a dump_bones filter that matches
	# no bone purely to reach the quit path; we don't need its output.
	stdout = _run_godot(
		[f"pick={screen_x},{screen_y}", "dump_bones=__no_match__"], want_render=True
	)
	match = re.search(r"CHARACTER_EDITOR_PICKED:(\S+)", stdout)
	if not match:
		return "No bone was picked at that position (selection unchanged)"
	_state.selected_bone = match.group(1)
	return f"Picked bone: {_state.selected_bone}"


@mcp.tool()
def capture_pose(include_ui: bool = False) -> Image:
	"""Render the current pose/view/camera state and return a screenshot. include_ui=True also renders the editor panel (animation/object/preset pickers, bone sliders, mode toggles) instead of just the 3D viewport."""
	capture_path = SCRATCH_DIR / f"capture_{int(time.time() * 1000)}.png"
	extra_args = [f"capture={capture_path}"]
	if include_ui:
		extra_args.append("capture_ui=true")
	_run_godot(extra_args, want_render=True)
	if not capture_path.exists():
		raise GodotInvocationError("Capture completed but no image file was produced")
	# Image(path=...) reads the file lazily when FastMCP serializes the result,
	# not at construction time - deleting the scratch file right after
	# constructing it would leave Image pointing at nothing. Read the bytes
	# ourselves so the scratch file can be cleaned up immediately.
	data = capture_path.read_bytes()
	capture_path.unlink(missing_ok=True)
	return Image(data=data, format="png")


@mcp.tool()
def dump_bone_poses(name_filter: str = "") -> dict:
	"""Return every bone's local/global rotation (degrees) and global position for the current pose, optionally filtered by a substring of the bone name."""
	stdout = _run_godot([f"dump_bones={name_filter}"], want_render=False)
	match = re.search(r"POSE_DUMP:(\{.*\})", stdout)
	if not match:
		raise GodotInvocationError(f"No POSE_DUMP found in output:\n{stdout}")
	return json.loads(match.group(1))


# ---------------------------------------------------------------------------
# describe_pose - posecode-style categorical summary, computed here in
# Python from dump_bone_poses()'s raw data. See docs/tooling_research.md's
# ninth pass and docs/character_editor_mcp_plan.md for the technique
# (PoseScript/MotionScript posecodes - confirmed rule-based geometry, no
# ML). Thresholds below are our own reasonable choices; the source papers
# don't publish theirs.
# ---------------------------------------------------------------------------

def _vec_sub(a: list[float], b: list[float]) -> tuple[float, float, float]:
	return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _vec_length(v: tuple[float, float, float]) -> float:
	return math.sqrt(v[0] ** 2 + v[1] ** 2 + v[2] ** 2)


def _angle_between_deg(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
	la, lb = _vec_length(a), _vec_length(b)
	if la < 1e-6 or lb < 1e-6:
		return 0.0
	dot = (a[0] * b[0] + a[1] * b[1] + a[2] * b[2]) / (la * lb)
	return math.degrees(math.acos(max(-1.0, min(1.0, dot))))


def _bucket_angle(deg: float) -> str:
	if deg < 15:
		return "straight"
	if deg < 45:
		return "slightly bent"
	if deg < 75:
		return "partially bent"
	if deg < 105:
		return "bent at a right angle"
	if deg < 150:
		return "almost completely bent"
	return "completely bent"


def _bucket_distance(meters: float) -> str:
	if meters < 0.15:
		return "close"
	if meters < 0.40:
		return "shoulder width"
	if meters < 0.70:
		return "spread"
	return "wide apart"


# (parent_bone, joint_bone, child_bone) triples - the angle posecode is the
# angle between (joint - parent) and (child - joint), i.e. how much the
# limb folds at the middle joint.
_ANGLE_JOINTS = {
	"right_elbow": ("RightArm", "RightForeArm", "RightHand"),
	"left_elbow": ("LeftArm", "LeftForeArm", "LeftHand"),
	"right_knee": ("RightUpLeg", "RightLeg", "RightFoot"),
	"left_knee": ("LeftUpLeg", "LeftLeg", "LeftFoot"),
}


def _describe_from_bones(bones: dict) -> dict:
	origins = {name: data["global_origin"] for name, data in bones.items()}

	result: dict[str, str] = {}
	for label, (parent, joint, child) in _ANGLE_JOINTS.items():
		if parent not in origins or joint not in origins or child not in origins:
			continue
		upper = _vec_sub(origins[joint], origins[parent])
		lower = _vec_sub(origins[child], origins[joint])
		result[label] = _bucket_angle(_angle_between_deg(upper, lower))

	if "RightHand" in origins and "LeftHand" in origins:
		hands_dist = _vec_length(_vec_sub(origins["RightHand"], origins["LeftHand"]))
		result["hands_distance"] = _bucket_distance(hands_dist)

	if "Hips" in origins:
		hips_y = origins["Hips"][1]
		for hand in ("RightHand", "LeftHand"):
			if hand not in origins:
				continue
			delta = origins[hand][1] - hips_y
			key = f"{hand.lower()}_relative_to_hips"
			if delta > 0.08:
				result[key] = "above"
			elif delta < -0.08:
				result[key] = "below"
			else:
				result[key] = "at hip level"

	return result


@mcp.tool()
def describe_pose() -> dict:
	"""Categorical, human-readable summary of the current pose (elbow/knee bend, hand distance, hand-vs-hips position) - a quicker sanity check than dump_bone_poses' raw numbers or a screenshot."""
	return _describe_from_bones(dump_bone_poses())


@mcp.tool()
def dump_live_bone_poses(name_filter: str = "") -> dict:
	"""Same data as dump_bone_poses, but read from the scene actually playing in the already-running editor (via the mcp_bridge EditorPlugin's debugger message channel) instead of a fresh headless process. Requires play_scene_in_editor to have been called first."""
	result = editor_bridge.send_command(
		{"cmd": "dump_live_pose", "name_filter": name_filter}, timeout=8.0
	)
	return result


@mcp.tool()
def describe_live_pose() -> dict:
	"""Same as describe_pose, but for the scene actually playing in the already-running editor - see dump_live_bone_poses."""
	return _describe_from_bones(dump_live_bone_poses())


@mcp.tool()
def open_scene_in_editor(path: str) -> str:
	"""Open a scene in the already-running Godot editor (via the addons/mcp_bridge EditorPlugin), so a human looking at the editor sees the same scene as the agent. Requires the editor to be running with that plugin enabled - unlike every other tool here, this does not spawn its own Godot process."""
	result = editor_bridge.send_command({"cmd": "open_scene", "path": path})
	return str(result)


@mcp.tool()
def select_node_in_editor(node_path: str) -> str:
	"""Select a node (by path relative to the currently edited scene's root, e.g. "PlayerBody/Skeleton3D") in the already-running editor's scene tree and inspector."""
	result = editor_bridge.send_command({"cmd": "select_node", "node_path": node_path})
	return str(result)


@mcp.tool()
def get_editor_state() -> dict:
	"""Read back what's currently open and selected in the already-running editor - the current scene path, any selected node paths, and whether the scene is currently playing."""
	result = editor_bridge.send_command({"cmd": "get_state"})
	return result


@mcp.tool()
def play_scene_in_editor() -> str:
	"""Run the currently open scene in the already-running editor (equivalent to pressing F6 / 'Run Current Scene'), so it becomes an interactive window instead of just the static editor viewport."""
	result = editor_bridge.send_command({"cmd": "play_scene"})
	return str(result)


@mcp.tool()
def stop_scene_in_editor() -> str:
	"""Stop the currently running scene in the already-running editor."""
	result = editor_bridge.send_command({"cmd": "stop_scene"})
	return str(result)


@mcp.tool()
def set_live_view(mode: Literal["full", "hand", "isolated"]) -> str:
	"""Switch the camera framing preset in the scene actually playing in the already-running editor - the live counterpart to set_view. Requires play_scene_in_editor first."""
	result = editor_bridge.send_command({"cmd": "set_live_view", "mode": mode}, timeout=8.0)
	return str(result)


@mcp.tool()
def select_live_bone(name: str) -> str:
	"""Select a bone (by name) in the scene actually playing in the already-running editor - the live counterpart to select_bone. Focuses the camera on it the same way clicking its slider row in the UI would. Requires play_scene_in_editor first."""
	result = editor_bridge.send_command({"cmd": "select_live_bone", "name": name}, timeout=8.0)
	return str(result)


@mcp.tool()
def set_live_camera_angle(
	angle: Literal["front", "back", "left", "right", "top", "bottom"],
) -> str:
	"""Orbit the focused camera to a named angle in the scene actually playing in the already-running editor - the live counterpart to set_camera_angle. Only has an effect once a bone has focus (see select_live_bone). Requires play_scene_in_editor first."""
	result = editor_bridge.send_command({"cmd": "set_live_camera_angle", "angle": angle}, timeout=8.0)
	return str(result)


@mcp.tool()
def load_live_pose(path: str) -> str:
	"""Load a saved pose preset (res:// path) into the scene actually playing in the already-running editor - the live counterpart to load_pose. Requires play_scene_in_editor first."""
	result = editor_bridge.send_command({"cmd": "load_live_pose", "path": path}, timeout=8.0)
	return str(result)


@mcp.tool()
def save_live_pose(path: str) -> str:
	"""Save the current pose of the scene actually playing in the already-running editor to a res:// path - the live counterpart to the UI's Save/Save As buttons (no invocation-based equivalent exists). Requires play_scene_in_editor first."""
	result = editor_bridge.send_command({"cmd": "save_live_pose", "path": path}, timeout=8.0)
	return str(result)


@mcp.tool()
def set_live_animation(name: str) -> str:
	"""Select the base animation to pose from in the scene actually playing in the already-running editor - the live counterpart to set_animation. Requires play_scene_in_editor first."""
	result = editor_bridge.send_command({"cmd": "set_live_animation", "name": name}, timeout=8.0)
	return str(result)


@mcp.tool()
def set_live_hand_openness(value: float) -> str:
	"""Set the hand-openness slider (-1 to 1) in the scene actually playing in the already-running editor. Only has an effect once a hand-side bone is focused (see select_live_bone). Requires play_scene_in_editor first."""
	result = editor_bridge.send_command({"cmd": "set_live_hand_openness", "value": value}, timeout=8.0)
	return str(result)


@mcp.tool()
def pick_live_bone(screen_x: float, screen_y: float) -> str:
	"""Simulate a click at a screen position (in the capture resolution's coordinate space) in the scene actually playing in the already-running editor, selecting whichever bone is nearest - the live counterpart to pick_bone. Requires play_scene_in_editor first."""
	result = editor_bridge.send_command(
		{"cmd": "pick_live_bone", "screen_x": screen_x, "screen_y": screen_y}, timeout=8.0
	)
	return str(result)


@mcp.tool()
def get_live_object_state() -> dict:
	"""Read back the held object's current scene path, attachment bone, and position/rotation/scale from the scene actually playing in the already-running editor - there's no invocation-based equivalent since set_object's Python-tracked state can drift from what a human has since changed live in the editor. Requires play_scene_in_editor first."""
	result = editor_bridge.send_command({"cmd": "get_live_object_state"}, timeout=8.0)
	return result


@mcp.tool()
def check_live_penetration() -> dict:
	"""Exact mesh-vs-mesh penetration check between the held object and the character body in the scene actually playing in the already-running editor - answers "is it actually clipping" instead of relying on judging a screenshot. Bakes the body's real currently-deformed skin geometry via MeshInstance3D.bake_mesh_from_current_skeleton_pose() (not a bone-position approximation) and tests it against the held object's real mesh triangles two ways: surface-crossing (Geometry3D edge-vs-triangle tests) and full-containment (even-odd ray casting from each object vertex, since a small object fully swallowed inside the hand has no edges crossing the surface to detect). Returns any_penetrating, surface_crossing_count/points, and contained_vertex_count/points. Requires play_scene_in_editor first; can take a few seconds."""
	result = editor_bridge.send_command({"cmd": "check_live_penetration"}, timeout=20.0)
	return result


@mcp.tool()
def set_live_mesh_visible(visible: bool) -> str:
	"""Show/hide the character's skinned mesh in the scene actually playing in the already-running editor, independent of the bone overlay (set_live_show_bones) - useful to see the bare skeleton without the mesh in the way. Requires play_scene_in_editor first."""
	result = editor_bridge.send_command({"cmd": "set_live_mesh_visible", "visible": visible}, timeout=8.0)
	return str(result)


@mcp.tool()
def set_live_show_bones(enabled: bool) -> str:
	"""Toggle the bone-link/joint-sphere overlay in the scene actually playing in the already-running editor - the live counterpart to the UI's "Show bones" checkbox. Requires play_scene_in_editor first."""
	result = editor_bridge.send_command({"cmd": "set_live_show_bones", "enabled": enabled}, timeout=8.0)
	return str(result)


@mcp.tool()
def set_live_character(kind: Literal["player", "shambler"]) -> str:
	"""Switch which character is loaded in the scene actually playing in the already-running editor - the live counterpart to the character= automation arg / the UI's Character dropdown. Tears down and rebuilds character-specific state (held object, hand-grip modifier, bone-debug overlay), so anything set via set_object/set_bone_rotation/etc. needs to be reapplied afterward. shambler has no held-object/hand-grip/compare-mode support - those tools return errors when it's loaded. Requires play_scene_in_editor first."""
	result = editor_bridge.send_command({"cmd": "set_live_character", "kind": kind}, timeout=15.0)
	return str(result)


@mcp.tool()
def reload_editor_bridge() -> str:
	"""Re-register addons/mcp_bridge/pose_debugger_plugin.gd fresh from disk in the already-running editor, without an editor restart. Only needed after editing pose_debugger_plugin.gd itself - commands.gd (open_scene, play_scene, dump_live_pose, etc.) already reloads fresh on every call and never needs this."""
	result = editor_bridge.send_command({"cmd": "reload_bridge"})
	return str(result)


@mcp.tool()
def set_live_bone_rotation(bone: str, x: float, y: float, z: float) -> str:
	"""Apply an additive rotation (degrees) to one bone in the scene actually playing in the already-running editor - the live counterpart to set_bone_rotation, visible immediately in the editor window instead of only on the next capture_pose of a fresh process. Requires play_scene_in_editor first."""
	result = editor_bridge.send_command(
		{"cmd": "set_bone_rotation", "bone": bone, "x": x, "y": y, "z": z}, timeout=8.0
	)
	return str(result)


@mcp.tool()
def set_live_object(
	position: tuple[float, float, float] | None = None,
	rotation: tuple[float, float, float] | None = None,
	scale: float | None = None,
) -> str:
	"""Reposition/rotate/scale the held object (e.g. the flashlight) in the scene actually playing in the already-running editor - the live counterpart to set_object. Pass only the fields you want to change; values are relative to the attachment bone, matching the character editor UI's position/rotation/scale sliders. Requires play_scene_in_editor first."""
	result = editor_bridge.send_command(
		{"cmd": "set_object", "position": position, "rotation": rotation, "scale": scale},
		timeout=8.0,
	)
	return str(result)


@mcp.tool()
def capture_live_pose(include_ui: bool = False) -> Image:
	"""Screenshot of the scene actually playing in the already-running editor (the embedded Game view) - the live counterpart to capture_pose, which only ever renders a fresh disposable process. Requires play_scene_in_editor first."""
	capture_path = SCRATCH_DIR / f"live_capture_{int(time.time() * 1000)}.png"
	editor_bridge.send_command(
		{"cmd": "capture_live_pose", "path": str(capture_path), "include_ui": include_ui},
		timeout=10.0,
	)
	if not capture_path.exists():
		raise editor_bridge.EditorBridgeError("Capture completed but no image file was produced")
	data = capture_path.read_bytes()
	capture_path.unlink(missing_ok=True)
	return Image(data=data, format="png")


if __name__ == "__main__":
	mcp.run()
