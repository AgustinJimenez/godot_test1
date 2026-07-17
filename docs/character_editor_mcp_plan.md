# Character Editor MCP — Investigation & Plan

Status: **investigation only, no code written yet**, per explicit instruction
to research the best approach before implementing anything. This is a plan
to be reviewed and agreed on, not a decision already made.

## Goal

Let an AI agent (Claude Code or another MCP client) drive
`tools/character_editor/character_editor.tscn` interactively — set poses,
select bones, move the camera, capture what it looks like, and see the
result — instead of relying on a third-party generic Godot MCP server (see
`docs/tooling_research.md`'s eighth pass for why a custom server is
preferable here: the tool already speaks an agent-shaped protocol, and a
generic Godot MCP would have to re-learn that from scratch through raw
scene-tree manipulation instead of just calling it directly).

## What the tool already does (read directly from source, not assumed)

`character_editor.gd`'s `_ready()` calls `_run_automation_args()` once,
which parses `OS.get_cmdline_user_args()` into `key=value` pairs and
applies them in this order: load a pose preset, select an animation, load
an attached object, set the attachment bone, set object position/rotation/
scale, apply per-bone rotation overrides (`bones=Bone:x,y,z;...`), switch
view mode, resize/collapse the side panel, seek/pause the animation, select
a bone by name, **pick a bone by simulating a double-click at a screen
position** (`pick=x,y`, prints `CHARACTER_EDITOR_PICKED:<bone>` if the
selection changed), adjust hand-openness, orbit the focused camera to a
named angle, and finally **either** capture a screenshot (`capture=<path>`,
optional `capture_ui=true`) **or** dump every bone's local/global rotation
and global position as JSON (`dump_bones=<name filter>`, prints
`POSE_DUMP:<json>`) — whichever of those two is present, the process quits
immediately after. If neither is present, the scene stays open (this is
the path a human uses interactively).

**This confirms the current interface is one-shot-per-process**: every
invocation launches a fresh Godot process, applies a complete set of
arguments, and either captures/dumps-then-quits or stays open for a human.
There is currently no way to send a second command to an already-running
instance - each "turn" needs its own full process launch, which means
re-specifying the *entire* desired state each time (this is fine, since
presets are just JSON files, and `bones=` overrides layer additively on
top of a loaded preset in a single invocation - but it does mean no
"nudge this one bone slightly from wherever it currently is" without the
caller tracking state itself between calls).

## Architecture options considered

### Option A: invocation-based (wrap the CLI interface exactly as it is)

Each MCP tool call constructs the appropriate `--` arguments and spawns
`godot --path . res://tools/character_editor/character_editor.tscn -- <args>`,
waits for it to exit (since `capture=`/`dump_bones=` both call
`get_tree().quit()` when done), and parses stdout for `POSE_DUMP:`/
`CHARACTER_EDITOR_PICKED:` or reads back the captured PNG.

**Pros**: zero changes to `character_editor.gd` - the MCP server is purely
a translation layer sitting outside the existing, already-working
automation interface. Fast to build and easy to reason about (each call is
fully self-contained and stateless from Godot's perspective). Matches this
project's own established testing pattern of driving throwaway/tool scenes
via CLI args and inspecting output (`AGENTS.md`'s Commands section).

**Cons**: pays a full Godot process-launch cost on *every* tool call - not
free, and not instant. No true "live" interaction (e.g. watching a drag
gizmo move in real time isn't possible; each call is snapshot in, snapshot
out). The caller (the MCP server) has to track "current state" itself
across calls if it wants to build on a previous pose rather than
re-specifying everything from scratch each time.

### Option B: persistent live socket (add a listener inside the scene)

Add a small, additive piece to `character_editor.gd`: when a
`mcp_listen=<port>` argument is present, instead of running
`_run_automation_args()` once and possibly quitting, start a `TCPServer`
(confirmed available via local `--doctool` dump - see `AGENTS.md`),
`take_connection()` it, and loop reading JSON-RPC-framed messages using
Godot's own built-in **`JSONRPC`** class (also confirmed present locally -
`make_request`/`make_response`/`process_action`/`process_string`), routing
each request to the same internal functions `_run_automation_args()`
already calls (`_select_bone`, `_capture_pose_image`, `_dump_bone_poses`,
etc. - these already exist and work, this reuses them rather than
duplicating logic). The Python MCP server keeps one long-lived Godot
process open and forwards each tool call over that socket instead of
relaunching Godot every time.

**Pros**: no per-call process-launch overhead - a tool call becomes a
socket round-trip instead of a multi-second Godot boot. Enables genuinely
interactive workflows (many small adjustments in quick succession,
building on live state). Reuses `character_editor.gd`'s existing internal
functions rather than re-deriving behavior through CLI-arg parsing each
time.

**Cons**: requires actually modifying `character_editor.gd` (a small,
additive change - a new branch in `_ready()`/a new listener loop - not a
rewrite, but real engine-side code, not zero-touch). Introduces a
long-running local TCP listener that needs lifecycle management (start/
stop/crash recovery) the invocation-based option doesn't need at all.
More moving parts to test and get wrong.

### Recommendation: start with Option A, treat Option B as a deliberate phase 2

Build the invocation-based wrapper first. It requires zero changes to
`character_editor.gd`, ships something usable immediately, and directly
validates whether process-launch latency is actually a problem in practice
before spending effort building and maintaining a socket listener to solve
a latency problem that might turn out not to matter much for how this tool
actually gets used (batch-style "set up a pose, look at it, adjust,
look again" - not a tight real-time loop, going by how every other
throwaway testing harness in this project's history has actually been
used per `AGENTS.md`/`docs/task_history/`). If invocation overhead proves
genuinely limiting once used for real, Option B is a scoped, additive
follow-up - not a redesign - since the socket listener would dispatch to
the exact same internal functions Option A's CLI-arg path already
exercises.

## MCP server implementation

- **SDK**: official Python `mcp` package with `FastMCP` (`pip install
  "mcp[cli]"`, `mcp>=1.27,<2` pinned until the 2.x stable release ships).
  Tools are plain type-hinted Python functions with docstrings - the SDK
  generates the JSON schema from type hints, no manual schema-writing.
- **Transport**: stdio (the default for local, single-user Claude Code
  use - no need for HTTP/SSE here, this isn't a multi-client remote
  service).
- **Registration**: `claude mcp add character-editor <path-to-venv-python>
  <path-to-server-script>` (same pattern already confirmed for GDAI MCP in
  the tooling research doc).
- **Image return**: FastMCP's `fastmcp.utilities.types.Image(path=...)`
  helper - return it directly (or in a list) from a tool function and
  FastMCP handles base64-encoding and MIME-type tagging automatically, no
  manual `ImageContent` construction needed. Matches exactly what
  `_capture_pose_image()` already produces (a PNG file path) - the MCP
  tool just calls Godot with `capture=<tmp path>`, waits for exit, then
  returns `Image(path=<tmp path>)`.
- **Known limitation to watch for**: community reports mention a practical
  size ceiling on images returned through `ImageContent` - if this becomes
  an issue, capture at a smaller resolution/`panel_size` rather than
  downscaling after the fact, since `character_editor.gd` doesn't
  currently expose a resolution argument separate from the actual Godot
  window resolution (would need a `--resolution` launch flag, already used
  elsewhere in this project's `--write-movie` capture pattern).

## Proposed tool list (draft, for review - not final)

Mapped directly to arguments `_run_automation_args()` already handles, so
each tool is a thin, obviously-correct wrapper rather than new design:

- `load_pose(path: str)` — load a saved preset.
- `set_animation(name: str)`
- `set_bone_rotation(bone: str, x: float, y: float, z: float)` — maps to a
  single `bones=Bone:x,y,z` override layered on the current/loaded pose.
- `select_bone(name: str)` / `pick_bone(screen_x: float, screen_y: float)`
  — the latter returns whichever bone got picked (parsed from
  `CHARACTER_EDITOR_PICKED:`).
- `set_view(mode: Literal["full", "hand", "isolated"])`
- `set_camera_angle(angle: Literal["front","back","left","right","top","bottom"])`
  (only meaningful once a joint has focus, matching current behavior)
- `set_object(scene_path: str, attachment_bone: str, position, rotation, scale)`
- `capture_pose(...) -> Image` — the main "show me what this looks like"
  tool, bundling whichever of the above options are relevant into one call
  plus `capture=`.
- `dump_bone_poses(name_filter: str = "") -> dict` — structured
  local/global rotation + position per bone, parsed from `POSE_DUMP:`.

Each of these (in the Option A design) independently spawns Godot with the
full set of args needed to reach that state from scratch - the server
needs to track "current desired state" itself (pose path + any bone
overrides + view + object, etc.) and re-supply all of it on every call, not
just the one thing that changed, since each launch starts from the tool's
default state otherwise.

## Testing strategy before wiring into Claude Code

1. Use the MCP Inspector (`mcp dev <server.py>`, included in `mcp[cli]`)
   to call tools directly and confirm image/JSON responses look right,
   without needing Claude Code in the loop yet.
2. Cross-check each tool's Godot invocation manually first (the exact same
   `godot --path . res://tools/character_editor/character_editor.tscn --
   ...` commands this project has already been running by hand all
   session) before wrapping it in Python, so any bug is obviously "the
   Godot side" or "the Python wrapper side," not both at once.
3. Only after that: register with `claude mcp add` and try it from an
   actual Claude Code session.

## Open questions to resolve before writing code

1. Does the MCP server need to manage the Godot process's working
   directory/`--path .` itself, or should that be a fixed config value
   set once at server startup? (Fixed value is simpler and this project
   only has one Godot project to point at - leaning toward fixed.)
2. Should `capture_pose` clean up its temp PNG after reading it back, or
   leave a trail in a scratch directory for later inspection? (Leaning
   toward a dedicated scratch subfolder, cleaned per-server-run, not
   per-call - matches how this session's own throwaway `/tmp/anim_survey*`
   captures were handled.)
3. Timeout handling: what should the MCP tool do if the Godot process
   hangs (e.g. waiting on a frame that never renders)? Needs a hard
   subprocess timeout with a clear error back to the caller, not an
   indefinite hang - not yet designed.
4. Whether to build Option B at all, or treat Option A as sufficient
   indefinitely - deliberately left open per the recommendation above
   until Option A is actually in use and its latency is felt to be a real
   problem, not assumed to be one.

## Sources

- [MCP Python SDK](https://github.com/modelcontextprotocol/python-sdk)
- [Build an MCP server — official docs](https://modelcontextprotocol.io/docs/develop/build-server)
- [FastMCP tools guide (image return helpers)](https://gofastmcp.com/servers/tools)
- Godot `TCPServer`/`StreamPeerTCP`/`JSONRPC` — verified via local
  `godot --doctool` dump (see `AGENTS.md`), not web search.
- `tools/character_editor/character_editor.gd` — read directly, current
  automation-argument handling as of this investigation.
