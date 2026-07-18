# Character Editor MCP — Investigation & Plan

Status: **built and registered**. Option A (invocation-based) is implemented
in `tools/character_editor_mcp/server.py` (FastMCP, 13 tools including
`describe_pose`'s posecode summary), all tools verified end-to-end both
in-process and over real MCP stdio protocol (via the Inspector CLI), and
registered with Claude Code as `character-editor` (`claude mcp add`).

A second, complementary path was added on top: `addons/mcp_bridge/` is a
Godot EditorPlugin that lets the same MCP server control an
**already-running editor instance** instead of only spawning disposable
headless processes - open a scene, select a node, play/stop the scene, and
read the *actually playing* scene's live bone poses (via
`EngineDebugger`/`EditorDebuggerPlugin` messages, not a screenshot). This
means a human watching the editor and the agent see the same thing. See
"Editor bridge" below for the architecture and its live-reload design
(most of it needs neither an editor restart nor a plugin toggle to pick up
code changes).

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
view mode, optionally enable raw-source comparison (`comparison=true`),
resize/collapse the side panel, seek/pause both animations, select
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

### Option C: native GDScript MCP server, no external process at all

Discovered while checking "is there another MCP SDK besides Python?" -
answer to that question is yes, MCP has **7 official-tier SDKs** (Python,
TypeScript, Go, Java, Kotlin, C#, Rust), but the more relevant discovery
for this project specifically: **native GDScript MCP implementations
already exist** -
[Godot-MCP-Native (yurineko73)](https://github.com/yurineko73/Godot-MCP-Native)
and [VberAI's Godot Native MCP](https://mcpservers.org/servers/vberai/godot-mcp)
both implement the MCP server *inside Godot itself*, no Python/Node
process, speaking **streamable HTTP** (not stdio) on loopback
(`http://localhost:9080/mcp` for yurineko73's). This works specifically
because Godot has no built-in `HTTPServer` class (confirmed via local
`--doctool` - only `HTTPClient`/`HTTPRequest`, both for making *outgoing*
requests), so both addons hand-roll HTTP request/response parsing on top
of the same `TCPServer`/`StreamPeerTCP` primitives Option B would use -
the "no external process" win comes from the *transport choice* (HTTP,
which an MCP client connects *to* an independently-running server rather
than *spawning*), not from avoiding low-level socket code entirely.

**Why this is genuinely a different tradeoff than Option B**, not just a
variant: stdio transport requires the MCP client to spawn the server as a
subprocess and pipe its stdio directly - awkward for Godot specifically,
since Godot's own stdout is already used for engine/game logging, and
mixing that with a JSON-RPC protocol stream risks exactly the corruption
failure mode called out in the general MCP-building research ("forgetting
that stderr is reserved for logs - print to it and you'll corrupt the
protocol stream"). HTTP transport sidesteps this entirely: Claude Code
*connects to* an already-running Godot process instead of spawning and
piping it, so console logging and the MCP protocol never share a stream.

**Checked directly whether either existing addon could just be adopted
as-is - they can't, for this specific need**: neither README describes an
API for registering custom project-specific tools (both ship a fixed,
if large, built-in tool set - 155 tools for yurineko73's), and
yurineko73's server explicitly runs as an **editor plugin operating on the
editor context**, not against a *running scene* like
`character_editor.tscn` needs to be. Their value here is as a **reference
implementation of the pattern** (native GDScript + hand-rolled HTTP +
`TCPServer`), not as a dependency to install - a from-scratch, much
smaller HTTP/JSON-RPC responder built directly into `character_editor.gd`
(exposing only the handful of tools this project actually needs, per the
draft tool list below) would be the real Option C, not adopting either
existing addon wholesale.

**Pros**: no external process or dependency at all (no Python venv, no
`npm install`) - genuinely the least moving parts once built. Same "no
per-call relaunch" latency win as Option B. Avoids the stdio/logging
collision risk entirely.

**Cons**: requires hand-rolling real (if minimal) HTTP request/response
parsing in GDScript - more implementation surface than Option B's raw
TCP+JSONRPC framing (which needs no HTTP semantics at all, just
Godot's own built-in `JSONRPC` class over a plain socket). No existing
addon directly reusable for this project's specific need, confirmed by
checking rather than assuming. Streamable-HTTP MCP transport specifics
(chunked/SSE framing for streaming responses, if ever needed) add further
surface beyond a one-shot request/response.

### Recommendation: start with Option A, treat Options B and C as alternative deliberate phase-2 paths

Build the invocation-based wrapper first. It requires zero changes to
`character_editor.gd`, ships something usable immediately, and directly
validates whether process-launch latency is actually a problem in practice
before spending effort building and maintaining a socket listener to solve
a latency problem that might turn out not to matter much for how this tool
actually gets used (batch-style "set up a pose, look at it, adjust,
look again" - not a tight real-time loop, going by how every other
throwaway testing harness in this project's history has actually been
used per `AGENTS.md`/`docs/task_history/`). If invocation overhead proves
genuinely limiting once used for real, both B and C dispatch to the exact
same internal functions Option A's CLI-arg path already exercises, so
either is a scoped, additive follow-up, not a redesign - the choice
between B and C at that point becomes "is avoiding a Python dependency
worth hand-rolling HTTP parsing in GDScript," which isn't answerable
until Option A reveals whether phase 2 is even needed.

## MCP server implementation

- **SDK**: official Python `mcp` package with `FastMCP` (`pip install
  "mcp[cli]"`, `mcp>=1.27,<2` pinned until the 2.x stable release ships).
  Tools are plain type-hinted Python functions with docstrings - the SDK
  generates the JSON schema from type hints, no manual schema-writing.
  Chosen from among **7 official-tier MCP SDKs** (Python, TypeScript, Go,
  Java, Kotlin, C#, Rust - see Option C above for why GDScript itself is
  also a real, if more work-intensive, option): Python fits this specific
  use case because the tool is a thin subprocess-spawning wrapper around
  `godot --path . ... -- <args>`, and Python's subprocess handling +
  FastMCP's near-zero-boilerplate tool registration is a good match for
  that - TypeScript would work equally well if a Node-based toolchain were
  otherwise preferred, no strong reason to pick one over the other for
  this specific project beyond Python already being used for this
  session's own image/data processing (contact sheets, etc. - see
  `docs/task_history/ual_animation_retargeting.md`).
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
- `set_comparison(enabled: bool)` — show the retargeted target beside its
  synchronized untouched UAL1/UAL2 source when one exists.
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
- `describe_pose(...) -> dict` — **new, see below** - a categorical,
  human-readable pose summary instead of (or alongside) raw numbers.

Each of these (in the Option A design) independently spawns Godot with the
full set of args needed to reach that state from scratch - the server
needs to track "current desired state" itself (pose path + any bone
overrides + view + object, etc.) and re-supply all of it on every call, not
just the one thing that changed, since each launch starts from the tool's
default state otherwise.

## A third way to read a pose: posecodes (not screenshot, not raw numbers)

Investigated directly: besides a screenshot (vision) and a raw
`POSE_DUMP` of quaternions/Euler angles (precise but hard to spatially
reason about without mentally rendering it), there's a real, established
middle ground from pose-to-text research -
**[PoseScript](https://europe.naverlabs.com/research/publications/posescript-3d-human-poses-from-natural-language/)**
and its follow-up
**[MotionScript](https://arxiv.org/html/2312.12634)** - that converts raw
joint data into categorical, human-readable descriptions. Checked directly
(not assumed): **this is fully deterministic geometry, not a trained
model** - "the architecture is entirely reimplementable as geometry code:
compute angle between joint direction vectors (dot product/arccos), compute
L2 distances between joint pairs, compare axis-aligned coordinates for
relative positions, apply if/elif bucketing." No ML needed for the
extraction step itself (only the *fluent-sentence-generation* step in the
original papers uses a model, and this project doesn't need that part - a
structured dict of categories is more directly useful to an agent than a
prose sentence anyway).

The three posecode types, and why each is directly implementable here:

- **Angle posecodes** - bucket a joint's bend into named categories
  (paper's own labels: `straight`, `slightly bent`, `partially bent`,
  `bent at a right angle`, `almost completely bent`, `completely bent`).
  The underlying computation - angle between two bone direction vectors -
  is **the exact same primitive already used and proven this session**
  for the knee-bend diagnosis in
  `docs/task_history/ual_animation_retargeting.md` (`upper_dir.angle_to(lower_dir)`).
  Exact degree thresholds aren't published in the paper; would need
  picking reasonable ones (e.g. straight <15°, slightly bent 15-45°,
  partially bent 45-90°, right angle ~90°±15°, almost completely bent
  90-135°, completely bent >135°) rather than copying an unavailable
  reference implementation.
- **Distance posecodes** - bucket the distance between two bone positions
  (`close`/`shoulder width`/`spread`/`wide apart`) - e.g. hand-to-hand
  distance, useful for questions like "are the hands together on the
  weapon grip."
- **Relative-position posecodes** - pure sign comparisons on bone global
  origin coordinates (`left of`/`right of`, `above`/`below`,
  `in front of`/`behind`) relative to another bone (e.g. "is the right
  hand above the hips") - the simplest of the three, just axis-aligned
  coordinate comparison, no trig needed at all.

**Proposed `describe_pose()` tool**: run these three computations over a
curated set of anatomically meaningful joint pairs (elbows, knees,
shoulders, hand-to-hand distance, hand-relative-to-hips, etc. - not
exhaustively every bone, which would be as unreadable as the raw dump) and
return a small dict of category strings, e.g.
`{"right_elbow": "bent at a right angle", "hands_distance": "close",
"right_hand_relative_to_hips": "above"}`. This is genuinely a third
distinct modality - not vision, not raw numbers, but a compact categorical
summary an agent (or a human skimming logs) can read directly without
mentally reconstructing 3D geometry from Euler angles or parsing an image.
Implemented as `_describe_from_bones()` in server.py, shared by both
`describe_pose()` (headless invocation) and `describe_live_pose()` (editor
bridge, below).

## Editor bridge (`addons/mcp_bridge/`)

Everything above (Option A) spawns a fresh, disposable Godot process per
call. This is a second path: an `EditorPlugin` that runs *inside an
already-open editor instance* and exposes a local TCP socket
(`127.0.0.1:8791`, newline-delimited JSON, one request/response per
connection) so the same MCP server can drive the editor a human is actually
looking at - open a scene, select a node, play/stop the scene, and read the
*live* playing scene's bone poses.

**Files:**
- `plugin.gd` - thin, stable shell: owns the `TCPServer`, accepts one
  connection at a time, and dispatches each request. Deliberately kept
  small because Godot instantiates an `EditorPlugin`'s root script once and
  never re-reads it from disk - changing this file needs a real editor
  restart (or a Project Settings > Plugins toggle-off/on).
- `commands.gd` - all actual command logic (`open_scene`, `select_node`,
  `play_scene`, `stop_scene`, `get_state`, `dump_live_pose`), as `static
  func`s on a plain `RefCounted` script. `plugin.gd` reloads this file
  fresh from disk on **every single request** (see "Live reload" below),
  so editing command behavior takes effect on the next call - no restart,
  no toggle.
- `pose_debugger_plugin.gd` - an `EditorDebuggerPlugin` that captures
  `"mcp:pose_dump"` messages from the actually-playing scene. Registered
  once via `add_debugger_plugin()` in `plugin.gd`'s `_enter_tree()`, so
  (unlike commands.gd) it can't just be reloaded per-call - the debugger
  session is bound to whichever instance was registered. A
  `reload_bridge` command (exposed as the `reload_editor_bridge()` MCP
  tool) re-registers a fresh instance on demand, still without an editor
  restart.
- `tools/character_editor/character_editor.gd` - registers
  `EngineDebugger.register_message_capture("mcp", ...)` in `_ready()` (only
  when `EngineDebugger.is_active()`, i.e. only when actually launched from
  the editor's Play button) and answers `request_pose_dump` by building the
  same dict `_build_bone_pose_dump()` also used by the `dump_bones=`
  automation arg. This script needs **no restart at all** for changes -
  `play_scene_in_editor` always spawns a fresh subprocess that reads it
  from disk fresh.

**Live reload mechanism** (why editing `commands.gd` doesn't need a
restart): `ResourceLoader.load(path, "GDScript", CACHE_MODE_REPLACE)`
alone was *not* sufficient - empirically verified by editing the file and
observing the old behavior persist. GDScript appears to keep its own
compiled-script cache independent of `ResourceLoader`'s cache mode
argument. The fix, also empirically verified: call
`EditorInterface.get_resource_filesystem().update_file(path)` immediately
before the `ResourceLoader.load()` call, which explicitly tells the
editor's filesystem tracker the file changed on disk before loading it.

**Two Godot API quirks hit and fixed while building this** (both confirmed
by adding temporary trace logging and observing actual values, not
guessed):
- `EngineDebugger.register_message_capture(name, callback)` strips the
  `"name:"` prefix before invoking the runtime-side callback - a message
  sent as `EngineDebugger.send_message("mcp:request_pose_dump", ...)`
  arrives at the callback as just `"request_pose_dump"`. The editor-side
  `EditorDebuggerPlugin._capture(message, ...)` does **not** strip it -
  `message` there is the full `"mcp:pose_dump"`. This asymmetry isn't
  documented anywhere found; only confirmed by tracing actual received
  values on both sides.
- GDScript lambdas capture local **value-type** variables (bool, int,
  etc.) by value at creation time, not by reference. A polling loop that
  connects a one-shot lambda callback and checks a local `var done := false`
  set inside that lambda will never see it change - the lambda mutates its
  own private copy. Fixed by using a `Dictionary` (a reference type) to
  carry state across the closure boundary instead.

**MCP tools on this path**: `open_scene_in_editor`, `select_node_in_editor`,
`play_scene_in_editor`, `stop_scene_in_editor`, `get_editor_state`,
`reload_editor_bridge`, `dump_live_bone_poses`, `describe_live_pose`.
Complements `dump_bone_poses()` rather than replacing it - `describe_pose`
for a quick "does this look roughly right" check, `dump_bone_poses` when
exact numbers are actually needed (e.g. comparing against the RAW SOURCE
reference the way this session did for the leg-retargeting bug).

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
- [Official MCP SDK list — modelcontextprotocol.io](https://modelcontextprotocol.io/docs/sdk) —
  confirms 7 official-tier language SDKs.
- [Godot-MCP-Native (yurineko73)](https://github.com/yurineko73/Godot-MCP-Native) —
  checked directly for extensibility/transport/editor-vs-runtime scope
  (Option C); MIT licensed, not extensible with custom tools, editor
  plugin not runtime-scene-driving, streamable HTTP transport.
- [VberAI's Godot Native MCP](https://mcpservers.org/servers/vberai/godot-mcp) —
  logged as a second native-GDScript reference implementation, not
  independently deep-dived beyond its listing.
- [PoseScript — NAVER LABS Europe](https://europe.naverlabs.com/research/publications/posescript-3d-human-poses-from-natural-language/)
  and [MotionScript (arXiv 2312.12634)](https://arxiv.org/html/2312.12634) —
  posecode/posebit technique for `describe_pose()`; confirmed directly
  (fetched the paper) that posecode extraction is rule-based geometry, not
  a trained model. Exact bucket thresholds not published - would need
  choosing our own or finding them in the paper's linked codebase
  (`pjyazdian.github.io/MotionScript`) if closer fidelity to the paper's
  own values is wanted.
