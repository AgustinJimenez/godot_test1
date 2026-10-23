# AGENTS.md

Repository guidance for coding agents. Keep this file short and durable: do not append session
history, live coordinates, rejected experiments, or long feature specifications here. Put active
evidence in the relevant `AGENT_TASKS/NNN_name.md` file; Git preserves old revisions.

## Project and task workflow

This is a first-person experiment and learning sandbox (not a survival-horror game, despite the
project name) built with Godot 4.7 (Forward+, Jolt) and statically typed GDScript. Explain Godot ideas briefly in plain language when building systems.

The user is not a game or IK developer and judges Foot IK work only by whether the animation looks
smooth. For Foot IK discussion, lead with outcomes (smooth or not, fast or not, buggy or not) and
keep architecture/terminology out unless explicitly asked; save the technical detail for
`AGENT_TASKS/` files. A live-test verdict on a Foot IK fix only needs about 2-3 idle animation
loops, not an extended soak.

Active work lives directly in the `AGENT_TASKS/` folder, one independent `NNN_name.md` file per
task - there is no separate pointer file selecting a "current" one. Completed or parked work
remains in its own numbered file. Update `AGENTS.md` only for rules likely to prevent
rediscovery across several future tasks. There is no centralized planning document; numbered
tasks and the code/tests describe the current state.
Keep the active task a concise current handoff: replace superseded status instead of appending
session history, and move long investigation narratives to `AGENT_TASKS/archive/`.

Before editing, inspect the working tree. Existing changes belong to the user; preserve unrelated
work. Do not commit gameplay, animation, or visual changes until the user has tested them live and
explicitly confirmed the result.

**Same bug class three times = rethink, do not patch again.** When live logs show the same kind of
failure (foot flips, pelvis ratchet, snap on a mode switch) after two or more targeted fixes, or a fix
turns an unrelated regression check red, stop adding rules. Name the shared cause (usually one decision
made from one sample, redone every frame), write a short design note in `AGENT_TASKS/` (see `037`),
agree it with the user, then change the decision itself in small stages, each gated on the suite. Delete
the guards the new design makes redundant instead of keeping them.

Authenticate GitHub pushes for this repository as `AgustinJimenez`. Keep that selection
repository-local; do not change the globally active GitHub CLI account to make a push.

## Commands and validation

The `godot` command is the installed Godot 4.7 mono build.

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
scripts/check.sh
.venv/bin/pre-commit install
godot --headless --import
godot --headless --quit-after 10
godot --path . res://levels/<scene>.tscn
godot --doctool <path> --headless
```

`scripts/check.sh` is the canonical project-wide lint, import, and GDScript parse check used by the
pre-commit hook and CI. Keep `.gdlintrc`'s 1000-line ceiling and disabled
`class-definitions-order` unless deliberately changing the convention.

### Native planet crust (C++), once per machine

`native/planet_crust` is an optional GDExtension (the ground height, the rock colours, a tile's mesh, the
drainage and the river valleys of a planet in C++). The GDScript (`PlanetTectonics`, `PlanetNoise`,
`PlanetRock`, `PlanetTile`) stays the reference and the fallback, but without the library a planet is
about 5 times slower to build and has no river valleys, and the game prints one line saying so.

- **First thing on a new machine or clone** (Windows in Git Bash, a Mac in Terminal): `scripts/setup_native.sh`.
  It fetches godot-cpp and scons into `~/.cache/godot-native`, builds the library, and adds a line to the
  clone's post-merge and post-checkout hooks so that a pull or a checkout rebuilds it when the C++ changed
  (log: `native/planet_crust/build.log`). Needs git, python3 and a C++ compiler (Xcode command line tools on a
  Mac, MinGW on Windows). `scripts/build_native.sh [--force] [--release] [--double]` builds alone and does
  nothing when the library is up to date. The built libraries are not committed.
- **The user is on the Windows PC, sometimes by remote control from a Mac** (the game runs on the PC: the
  Windows libraries in `native/planet_crust/bin` are the ones that matter), and has a clone on a Mac too (the
  macOS build is written but not yet run there).
- **After any change to the C++, rebuild and compare**: `scripts/build_native.sh`, then
  `planet_lab.tscn -- --native-check --earth` (`NATIVE_CHECK PASS`, part of `scripts/planet_check.sh`). The
  library must match the engine's precision: the standard editor needs the single library, the custom
  double build in `E:\Godot\double` needs the double one (`--double`, see the folder's README: godot-cpp
  master and the engine's own API dump), or the engine crashes on load. Rebuild both after a C++ change.
- Keep the native and the GDScript maths the same: the numbers (noise settings, constants) are handed over
  from GDScript in `setup`, never copied. Planets must be the same on every engine build: do not use
  `randf` / `randf_range` for anything that shapes a planet (the double build draws other numbers; use
  `rng.randi()` as `PlanetTectonics._between` does).

- **Native first for the planet (the user's rule, 2026-10-19).** New computation for the planet and its plants (noise,
  grids, placement, meshes, selection, anything that loops over many points or builds arrays) is written in C++ in
  `native/planet_crust` from the start, not in GDScript: converting to native has repeatedly made planet code several
  times faster (plant meshes 7.5x, placement and selection, climate setup). GDScript stays for what only the engine can
  do: creating and freeing nodes, materials and shaders' parameters, UI and menus, input, and the orchestration that
  calls the native classes. Rules for doing it: measure first (`PLANET_TIMING=1`, the tile timings in
  `AGENT_TASKS/073`); hand numbers over from GDScript in `setup`, never copy constants; make the native method pure (no
  engine state, callable from worker threads); return packed arrays, not many small calls; keep a short script
  fallback only where the library may be missing (a machine that has not built it yet) and say so in a comment; add the
  class to `register_types.cpp`, rebuild both libraries (single and `--double`), and add or extend a check. Do not port
  scene/UI code, one-off tools or the flat world.

- **What the native conversion taught** (details in `docs/planet_lessons.md` section 10): measure first; the engine's
  `RandomNumberGenerator` is PCG32, so a native port with the same constants reproduces it exactly; the frame is GPU-bound
  in play, so the GPU is only for idle moments (the open map: `PlanetCloudGpu`, one thread owns the local
  `RenderingDevice` and warms the shader up after loading); a native crash prints nothing, so run the full
  `scripts/planet_check.sh` after every native change and bisect with `UtilityFunctions::print`; rename a locked
  `bin/*.dll` to `.dll.old` before rebuilding while the editor or a game runs; run `godot --headless --path . --import`
  after adding a `class_name` script; write multi-line edit scripts to a file instead of a shell heredoc; keep lab and
  check files under 1000 lines (`tests/manual/planet/planet_lab_checks.gd` takes the overflow).

There are no unit tests. Persistent acceptance scenes live under `tests/manual/<domain>/`.
Temporary capture scenes may use `tests/manual/_<name>_demo.tscn` but must be removed before commit.
After launching a verification scene, stop the game before handing control back to the user.

Use `godot --doctool` before web search for exact Godot APIs. This binary's XML has reliable class,
method, property, and inheritance data but empty prose descriptions; use primary web sources only
when explanatory prose is needed.

Use `rtk` (<https://github.com/rtk-ai/rtk>) for routine noisy Git/search output, but use raw output
for instruction files, exact numeric traces, failing checks, and final pre-commit diffs. Rerun any
filtered failure raw.

`codegraph` (<https://github.com/colbymchenry/codegraph>) is a local, pre-indexed code-graph MCP
that supports OpenCode and cuts discovery tool calls/tokens - candidate for token efficiency (see
`AGENT_TASKS/archive/026_token_efficiency_workflow.md`). Caveat before adopting: its supported
language list excludes GDScript, so it will not index this repo's gameplay code; re-check that list
before relying on it.

Every `godot ... >"$log_file" 2>&1` line in a `check_foot_ik*.sh` script must end with `|| true`
before its own `if rg -q ...` diagnostic block. Without it, a failing scene's nonzero exit trips
`set -e` and kills the whole script silently, before that check's own failure ever prints -
hiding the real suite status instead of reporting it. This bit an entire exhaustive run for
some time before being noticed and fixed; keep the pattern on any new check added to these
scripts.

## Logs and live debugging

Large traces must be redirected to files and summarized afterward; never print multi-megabyte JSONL
or full regression output into the conversation. Use `scripts/trace.sh`:

- `--summary` for totals;
- `--anomalies` for grouped defects;
- `--changes-only`, `--feet`, `--bones`, and `--arrows` for compact inspection;
- `--last-n 0` for the complete capture (the default final 40 frames can hide a recovered defect).

For schema-aware questions over a JSONL capture (worst frames, clip episodes, toe-in-tread,
a swing-state window, flat-vs-stair joint smoothness), use `scripts/trace_query.py` instead of
printing frames - it emits a few compact lines and never the raw trace. See
`AGENT_TASKS/archive/026_token_efficiency_workflow.md`.

Foot IK v2 traces (`user://foot_ik_v2.jsonl` live, `user://foot_ik_v2_check.jsonl` headless
checks - they never overwrite each other) are read with `scripts/trace_v2.sh` (GDScript, no
Python): `--segments`, `--tips`, `--released`, `--body`, `--frame N`, `--check`, `--from/--to`.
Do not write inline Python to analyze traces or edit files; if a field is missing, add a flag
to `scripts/analyze_v2_trace.gd`. A v2 trace line carries its `run_id`, wall-clock `time` and
`mode`, so copy a live trace out before running any headless check anyway.

`trace_query.py angular --compare B.jsonl` reports per-joint per-frame rotation change
(mean/p95/max/jerk in deg/frame) so flat vs stair can be A/B'd in one command. Capture the two
sides with the marker recipes: `user://foot_ik_flat_forward_marker` (flat 3.2 m/s walk) and
`user://foot_ik_stair_walk_marker` (0.35 m staircase), copying `user://foot_ik_controlled.jsonl`
to `/tmp` after each run. Do not rebuild a one-off joint-angle analyzer. Baseline: flat walk
tops out near 18 deg/frame; on stairs the *planted* leg's constraint-regime handoff
(`clamp_negative_knee` -> `constrain_knee_direction` -> `solve_to_support`) produces 40-180 deg
single-frame leg spikes - that handoff, not swing speed, is the stair jank to fix.

Before running any Foot IK harness after the user asks to inspect the latest live log, preserve
`user://foot_ik_controlled.jsonl` under a timestamped `/tmp` name. Harnesses share and overwrite this
rolling trace. Marker files under `user://` can also alter later headless runs; remove temporary Foot
IK walk/spin/stair markers before trusting regressions.

Treat compact anomaly output as a starting point, not proof of correctness. Inspect state changes and
the raw/smoothed/final values behind the visible symptom. Add state-invariant regressions when a
summary can look clean despite inconsistent ownership—for example, a released idle foot must not
retain the side-key target latch.

`foot_ik_preview.tscn`'s debug overlay runs a live foot/geometry penetration check every physics
frame during ordinary manual play (`foot_ik_clip_indicator.gd` +
`tools/foot_ik/foot_ik_live_penetration_monitor.gd`): a real clip (not automated-test-only) shows a
big red marker at the exact point and prints one throttled `[FOOT_IK_CLIP]` log line per episode.
Check this before building new clip-detection instrumentation from scratch for a live-reported
clipping bug. A separate, much more precise per-vertex-mesh-vs-floor checker already exists too
(`tests/manual/foot_ik/foot_ik_live_penetration_check.gd`, opt-in via the
`user://foot_ik_penetration_check_marker` file) - useful to cross-confirm a real finding is not a
box-approximation artifact, but it raycasts every skinned mesh vertex every physics frame and
**causes a severe FPS drop if left on during ordinary interactive play**. Only enable it for a
short, isolated (ideally headless) test, then remove the marker file immediately after.
Its ray-based `sample()` checks only the collider under the root; zero there does not clear a toe
inside a neighboring higher tread. Use `sample_box_transform()` against nearby real box colliders
for adjacent-riser evidence. Match clip events by their logged frame/joint, never nearest root.

The manual-test scene scripts under `tests/manual/foot_ik/` (`foot_ik_debug_overlay.gd` especially)
sit at the project's max-file-lines cap essentially permanently. When adding any non-trivial new
tool/gizmo to one, split it into its own small owned-object file from the start (see
`foot_ik_debug_markers.gd`/`foot_ik_clip_indicator.gd`) rather than inlining it and then discovering
the cap is blown.

`foot_ik_preview.tscn` runs several unrelated test characters/scenarios (automated stretch checks,
animation comparisons) in the same scene tree as the one manually-controlled player. Any live
`print()`-based instrumentation keyed only by `side` will interleave with all of them - filter by
frame/skeleton identity, or expect noisy, hard-to-read output, especially in the first ~100-150
frames before automated setup finishes. **Filtering by root x/z is not enough**: the 0.35m stair
walkers spawn at the same `x` as the controlled player (~15.0) and run the same code, so a
"two passes per frame" or "the monitor sees a clean pose" reading can silently be a *different
character*. Key every debug print on the skeleton instance id and/or the actor node path. On this
scene there are ~10 characters, one `_process_modification_with_delta` call each per physics frame -
it is not multi-pass.

Before trusting an A/B on the shared Godot user dir, know that it is **per project name** and shared
across every run: accumulated `user://` trace files contaminate later scenes (a fixture that fails
deterministically there can pass cleanly at committed HEAD). Reliable method: copy the tree to a
scratch dir, rename `application/config/name` in `project.godot` so Godot uses a fresh `user://`,
`--import`, then run. `git stash` A/B inside the shared dir gave misleading results (see 025).

Logging must be bounded and cheap. `foot_ik_trace_writer.gd` appends records and compacts
periodically; do not rewrite a multi-megabyte window every frame or emit unbounded editor output.
`foot_ik_controlled.jsonl.time` is animation time, while `render_fps` is the performance field.

## Repository conventions

- Use static typing, snake_case files/functions, PascalCase nodes/scenes, and `&"action"`
  `StringName`s for input actions. Never hardcode keys.
- Prefer composition: reusable behavior is a child node in `components/`; signals go up and calls
  go down.
- Keep scenes beside their scripts. For hand-edited `.tscn`/`.tres`, `load_steps` equals all external
  and subresources plus one.
- Environment scenes remain player-agnostic; game scenes compose environment plus `player.tscn`.
- Reusable authoring tools belong under `tools/`; durable acceptance harnesses under `tests/manual/`.
- Physics layers: 1 world, 2 player, 3 damageables, 4 interactables, 5 projectiles,
  6 AI perception. Player collides with world; interaction ray mask is world + interactables.

## Godot and animation gotchas

Godot 4.6.2 can segfault if an `AnimationLibrary` attached to a currently crossfading
`AnimationPlayer` is mutated. Stop the player immediately before adding lazy-baked animations.
Character Editor adapters must disable `PlayerBody.autoplay_default_animation` before the body enters
the tree; do not start gameplay idle and then stop/seek/deactivate it from the editor's `_ready()`.

`SkeletonIK3D` is a dead end in Godot 4: it is deprecated ("may be changed or removed") and can
silently do nothing - `is_running()` returns true and `influence` is 1.0 while it applies no
`bones_global_pose_override` at all, so an IK-driven pose never moves and the failure looks like a
frozen limb rather than an error. Do not start new leg/hand IK on it; solve the bones directly
(`Skeleton3D.set_bone_global_pose` + an analytic two-bone solve) or reuse the project's own solver.
When porting a Godot 3 project with `--convert-3to4`, the converter still leaves `intersect_ray(from,
to, [node])`, `get/set_bone_custom_pose`, and a user `var velocity` on a `CharacterBody3D` broken;
`CapsuleShape3D.height` also changes meaning (total height in 4.x vs cylinder-only in 3.x), which
silently sinks a character into the floor.

`SkeletonModifier3D` can evaluate more than once per physics tick, including `delta == 0` refreshes.
Do not skip the whole zero-delta pass: gate only time/history advancement, then reapply cached output
so whichever pass runs last still exposes the final pose. Headless and live call patterns can differ,
so changes in this area require live confirmation.

CSGBox3D collision (and other CSG shapes) is not registered on the very first physics frame after
scene load; a `PhysicsDirectSpaceState3D` raycast or `intersect_point` run at frame 1 silently
finds nothing even where solid geometry exists. A one-off diagnostic script that spawns a
character and immediately probes the physics space will get false "no collision" results -
settle at least ~30 frames first, or reproduce the same settle/hold history the real bug needs
anyway (see the Foot IK ownership rules below on why a cold spawn often doesn't match a live
repro's state either).

`CSGShape3D.use_collision = true` always bakes a concave `ConcavePolygonShape3D` trimesh for
its collider, even for a plain box - never a cheap convex primitive. This is invisible in
script-side timers (Foot IK's own `solve()` cost, `Performance.TIME_PROCESS`) because the extra
cost is inside the physics engine's own collision query; it shows up only as an elevated
`Performance.TIME_PHYSICS_PROCESS` (`physics_ms`), especially when many raycasts/character
controllers repeatedly query the same CSG box (e.g. every foot of every nearby Foot IK
character, every physics frame). If a CSG box exists purely to be a physical platform/ground
contact, give it a sibling `StaticBody3D` + `CollisionShape3D(BoxShape3D)` instead and set
`use_collision = false` on the CSG node - see `FootIKStairSurfaces.finalize_authored_box()` and
[012](AGENT_TASKS/012_foot_ik_ramp_cross_slope_penetration.md)'s "Preview-scene FPS drop" section
for a full writeup of the symptoms this produces (fps collapsing to single digits specifically
near the affected geometry, fully recovering elsewhere, with CPU-side process/solve timers
staying flat and misleadingly innocent throughout).

`HeightMapShape3D` (Jolt) splits every cell along one fixed diagonal (p10-p01, i.e. top-right to
bottom-left in x/z). A terrain mesh that picks its own diagonal per cell ("ridges stay crisp") disagrees
with it in about half the cells, 10-40 cm on rough ground, so the capsule and Foot IK stand on a surface
that is not the visible one and the feet look like they float or sink even when IK is perfect. Always
split the mesh (and any height lookup that places things) the same way; `world_surface_check.tscn`
guards it. When "IK looks bad on terrain", compare the visible mesh to the collider before touching IK.

Any retry/search loop that runs from `_process`/`_physics_process` needs a cooldown on failure,
not just a success-path exit. `FootIKGroundSampler._request_overheight_split_safe_zone` re-ran
a ~6500-raycast ring search every single physics tick whenever the search failed to find a
valid point, because the only gate was "do we already have a valid cached target" - a
perpetually-failing search never caches anything, so it re-triggers forever with zero backoff.
Symptom was identical in shape to the CSG-collision gotcha above (fps collapsing to single
digits near specific geometry, `process_ms` staying flat and innocent, only `physics_ms`
elevated) but persisted indefinitely instead of a few frames, and only during idle animation
near a support-height difference - see
[014](AGENT_TASKS/014_foot_ik_preview_scene_fps_collapse.md) for the full trace (a live A/B
- "disabling this system fixes it" / "changing animation state fixes it" - is what actually
found it; a GPU trace had earlier pointed at a real but much smaller, unrelated startup cost
and was wrongly treated as the whole answer). Any future search-with-fallback loop in this
codebase should cache an explicit "don't retry until frame N" cooldown on the failure path,
the same shape as `_landing_grace_time` or this fix's `split_safe_retry_after_frame`.

Procedural bone corrections belong in `SkeletonModifier3D`, not an ordinary node's `_process()`.
Snapshot all base animation poses before changing an ancestor chain. When a paused tuning UI changes
modifier data, call `Skeleton3D.advance(0.0)` to refresh the rendered result.

For animation-derived gaits, compare the **whole** final skeleton against the source across every
frame before replacing a leg chain: matching shoe rotation alone can still put the toe through the
floor or leave both feet floating. Test final skinned shoe vertices, not just foot/toe bone origins.
Build/retarget references on a private skeleton (the retargeter may pose its target). A flat-ground
pelvis clearance offset cannot rescue a stair clip whose phase, root travel, and tread geometry do
not align; measure the unmodified source against the intended terrain first. See
`docs/procedural_walk_experiment.md` for the lab evidence and checks.

`AnimationPlayer.play()` can select a clip before its pose is applied. Gameplay autoplay must publish
that first pose before a zero-delta modifier refresh can cache the imported pose as animation history.
Initial grounded placement must initialize pelvis, targets and legs together; borrowing a loop-seam
release or interpolating from an unrelated imported pose can drag feet through the starting terrain.

Animation loop resets are real discontinuities. Before fixing a periodic seam snap, read
`docs/known_issues/animation_loop_reset_seam.md` and use the existing discontinuity suppression.
Compare final bone quaternions, not Euler angles, which can jump between equivalent decompositions.

Retarget complete deforming chains, including fingers. Never copy raw local deltas or world-space
swings directly between rigs; convert through source and target parent rest frames. The synchronous
implementation is `_humanoid_retarget_local_pose()` in `player_body.gd`. Preserve source loop modes;
only explicit gameplay aliases may force looping. Make controller-driven clips in-place and keep
presentation-only comparison offsets out of gameplay animation data.

Godot actor forward is local `-Z`; horizontal yaw toward a direction uses
`atan2(-direction.x, -direction.z)`. Configure asset-facing offsets on visual children, not on AI,
collision, or navigation parents.

`AnimationNodeStateMachine` has no working `start_node` property in Godot 4.6.2 (assigning it errors
"Invalid assignment" for both `String` and `StringName` - only `states/Start/...` sub-properties
exist, found via property-list introspection). Node-add order does not determine the initial state
either; observed starting on the same state regardless of insertion order. A `Start`→state transition
with `ADVANCE_MODE_AUTO` also had no effect. What actually works: call
`(anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback).start(&"StateName")`
explicitly - but only after `AnimationTree` has processed at least one real frame (a physics frame if
using `_physics_process`); calling it synchronously right after building the tree (same call, before
any frame ran) silently does nothing since `parameters/playback` isn't live yet. Defer the forced
start to the first `_physics_process`/`_process` tick instead of doing it at tree-construction time.

**Retargeting a new source skeleton (ALS, other packs): check the bone names the map assumes, then check
a hand.** `HumanoidRetargeter` finds each rig's rest facing from the hips, head and clavicles by name;
`PlayerBody.BONE_MAP` says `Head`, ALS says `head`. A name that is not found gives a facing 180 degrees
wrong, and the arm IK then mirrors the arms (left hand on the right side) while the legs look fine.
After retargeting any clip, print the hands/feet relative to the hips at 4 phases and compare with the
source clip (left hand must keep the sign of its source side, opposite the same-side foot's swing);
`PlayerTempWalk` shows the fix (use `head` for ALS). `match_arm_positions=false` leaves the arms in a
T-pose, so it is not a workaround. Walk playback on the stairs is clamped into one band for every clip, so
clips with different loop lengths stepped at different rates; `stair_cadence_match` (Body node, 0..1)
scales the band by loop length. `scripts/check_foot_ik_v2.sh` has per-direction vibration checks (floor,
stairs up/down/backward/45/sideways) built on `trace_v2.sh --snaps`, whose "IK jerk" column is the
per-frame change of what the IK adds to the animated foot (judge the IK by that, not by raw foot speed:
strafe clips already swing the foot ~14 cm per frame).

**Mixamo (and other root-motion) clips: check the hips travel axis.** `HumanoidRetargeter.make_clip_in_place`
removes the hips' X/Z travel assuming local Y is up, but this rig's hips have Z up and Y forward, so a Mixamo
forward walk kept its travel: the body walked ahead then snapped back at the loop. `PlayerTempWalk._in_place`
finds the up axis from the parent's rest basis and removes the other two (and returns the clip's walking
speed in m/s). A forward walk is played at `ground_speed / WALK_REF_SPEED` (1.6), so a clip with shorter steps
looks fast at the game's 3.2 m/s: `PlayerTempWalk.PLAYBACK_SCALE` slows it (the user picked 0.575 for the
Mixamo walk, feet slide a little). **The player currently walks with the Action Pack Mixamo `walking.fbx`
(`player_temp_walk.gd`, CHOICE 4, not UAL1 `Walk`); headless checks still use the UAL walk on purpose
(`DisplayServer` is headless), so when this becomes permanent, move it into `UAL_GAMEPLAY_CLIPS`/the library
build properly and re-baseline the vibration and comparison limits in `scripts/check_foot_ik_v2.sh`.**
Tried and rated by the user: ALS `Walk_F` (arms need the `head` fix), UAL1 `Walk_Formal`, UAL2
`Walk_Carry` and zombie walk (all fine); the Mixamo walk was the pick.

**A foot must never hover (user rule, after playing Uncharted 4, 2026-10-11).** Uncharted 4's IK only
covers small steps; past that the character slides to a safe zone where both feet have ground (or falls if
pushed). v2 does the same: a resting foot with no ground within reach reports `FootIKV2Modifier.ledge_push()`
(horizontal, away from the void) and `PlayerLedgeNudge.nudge` (called from `player.gd` before the v1-driven
`_nudge_to_ledge_safe_zone`, which it replaces whenever v2 is installed) slides the capsule 1.2 m/s that way
until both feet are planted. Do not "fix" a hovering foot by squatting (the 0.40 m pelvis drop was the older
bug) or by letting the foot keep the animation height. The stairs-edge check now requires float <= 4 cm.

## Gameplay architecture

`playground.tscn` composes `test_room.tscn` plus `player.tscn`; the nature sandbox follows the same
environment-plus-player structure. `HumanoidActor.character_scene` configures visuals only; shared
collision, navigation, perception, health, and animation stay on the actor.

`NPCController` stores disposition and behavior but does not execute movement, perception, animation,
or attacks. Damageable actors expose a child named `Health`. Weapon components discover and damage
that component; animation owns timing, not health arithmetic.

Every interactable collider has a child node named exactly `Interactable`. The player ray selects it,
the HUD shows its prompt, and the owner handles its `interacted` signal. Do not add proximity-only
action labels that can disagree with the ray-selected action.

Items are `Resource`s shared by world pickups and inventory. Catalog definitions are authoring data,
not ownership. Held visuals use `BoneAttachment3D`; gameplay aim rays and flashlight illumination stay
camera-driven.

Actions keep priority until their animation finishes. Effects occur at explicit normalized contact
points and query the world then, not when input begins. Recovery begins from `action_finished`.
Actions that temporarily own velocity must explicitly return it at their state boundary.

## Character and outfit tools

Use `tools/character_editor/character_editor.tscn` for reusable pose, rig, attachment, and animation
inspection. The complete MCP/CLI contract and live bridge are in `docs/character_editor_mcp_plan.md`.
Inspect poses from several angles and let clips play through transition-in before judging them.

Do not evaluate an autogenerated rig from the isolated mesh alone. Compare it with the matching T/A
pose reference and anatomical landmarks. `Root` is a ground-level technical control, not the pelvis;
anatomy starts at `Hips`.

Pose presets use schema 3 with an ordered `attachments` array; schema 2 remains readable. A two-handed
item is one prop on its primary hand plus an off-hand contact/IK constraint, never two prop copies.

Outfit work is specialized and documented in `AGENT_TASKS/006_per_surface_outfit_fitting.md`.
Preserve its core boundaries: position-welded components are user-facing pieces; raw index islands
are internal topology detail; seams and thick shells must move coherently; rigid articulated garments
need bone-aware alignment rather than arbitrary per-vertex projection. Keep the source-backed compare
copy outside mutable editor mesh state. Do not revive rejected proximity body masks without a new
coverage model.

`tools/retarget_cli.gd` is a standalone, headless CLI for retargeting one animation clip from an
arbitrary source skeleton onto any catalog character via `HumanoidRetargeter` - no live editor/
`mcp_bridge` round trip needed, unlike `character_editor.gd`'s own "Import Character..." flow (that one
copies through the live MCP bridge specifically to trigger a real editor reimport). Useful whenever a
source FBX/GLB is already a plain imported `res://` resource. `HumanoidRetargeter`, `CharacterCatalog`,
and `CharacterEditorRigHandler.auto_map()`/`full_map_from_prefix()` are all plain `static`/UI-free
functions, safely callable from a bare `extends SceneTree` script - only the asset-copy-and-reimport
step actually needs the live editor.

A source rig sharing player_body.gd's `BONE_MAP` naming convention (`pelvis`, `clavicle_l`, ...) is not
guaranteed to match it bone-for-bone: one real UE-Mannequin export had a lowercase `head` bone where
`BONE_MAP` expects capitalized `Head`. A source bone simply missing from the map is skipped harmlessly
by `retarget_clip`'s per-bone loop, but `head`/`hips`/shoulder entries feed its *required* facing/height
computation and hard-crash with a `-1` bone index if they don't resolve - diff every `BONE_MAP` key
against the actual imported skeleton before trusting a new source works, rather than assuming the
existing map is complete for it.

Copying an `Animation`'s own track paths onto a *different* `AnimationPlayer` is not automatically safe
even when both share the same skeleton's bone names: paths are relative to the player's own `root_node`
(commonly `..`, its parent - not the player itself), and two different Unreal FBX exports of the "same"
character (a mesh-bearing export vs. an animation-only one) can nest `Skeleton3D` at different depths.
A path that resolves on the source silently fails to resolve on the target (a per-track console
warning, not an error, and the target simply doesn't animate) unless every track's path is rewritten
against `player.get_node(player.root_node).get_path_to(target_skeleton)` first - not
`player.get_path_to(target_skeleton)`, which is a subtly different and silently wrong path here.

## Foot IK and movement

**Foot IK v2 is the reduced, bug-free rewrite of v1 - prefer it.** The user judged v2 "so much better" than v1 on the procedural world terrain (2026-10-15). v1 has many special cases and known bugs; do not port v1 behaviour into v2, and new levels should install v2 (`FootIKV2Install.install(body, skeleton, body._foot_ik_modifier)`, preload the script). Debug any scene with `FootIkRecorder` (child of the Player): F10 records to `user://foot_ik_live.jsonl`, F11 marks a bad moment; it measures ankle/toe height above the real ground from outside, so it works for v1 and v2.

**Foot IK v2 lessons (runtime `actors/player/foot_ik_v2/`; the v2 lab AND the procedural world (`levels/procedural_world.gd`) install it, every other scene still runs v1; labs `tests/manual/foot_ik_v2/`, handoff `AGENT_TASKS/035`, open hard bug `036`).** Read bone poses
from the modifier's published `final_pose`, never from a node's `_process()` (stale by 12 cm+). v1
re-enables itself on every landing - use `set_debug_enabled(false)`. The player's ledge safety pushes
the root at 3 m/s while airborne (`landing_correction_speed`); the lab zeroes only that. The game pins
the body to the capsule, so the stair "hover" only moves the camera; smooth the body in the modifier.
Foot skating on stairs is a speed vs clip-step-rate mismatch (gameplay speed), not an IK bug. Stairs
sit at x = +5/+10/+15 in the lab; the 0.35 m stairs cannot be climbed at stair speed. `player.gd` and
the lab are both at the 1000-line lint cap.

**Foot IK v2, stair shake (walking UP was shaky, DOWN smooth) - what was actually wrong.** Compare
up vs down in the live trace before touching the IK: (1) the capsule snaps DOWN ~5 cm right after
each step-up climb (`apply_floor_snap` / `move_and_slide`) and the camera hover never absorbed it, so
the camera stepped back 3-6 cm per step: `player.gd` now feeds that snap into
`PlayerStairController.camera_snap_y` (camera arm only). Do NOT put it in `hover_offset_y`: that also
feeds `has_recent_transition()` / the body balance offset and re-timed the IK into a foot toe-lift
flicker at stair020 step 1 (suite fail). (2) the capsule velocity stalls to 0 for ~3 frames at every
step, so the modifier read "standing still" and dropped the pelvis at 2.5 cm/frame: `_moving_hold`
keeps "moving" for 0.3 s. (3) the moving pelvis drop grew slowly but was released fast (a 6 cm
sawtooth per step): while walking (not jumping) it now releases at `moving_pelvis_rate`; a slow
release on JUMPS breaks the "jump on the 45 deg ramp keeps the pelvis up" regression.
Other v2 lessons this session: the knee bend follows the FOOT (`KNEE_FOLLOWS_FOOT` 0.1), not the
animated knee (it swayed 11 cm side to side over a planted foot); 0.5+ breaks the `dz=-0.12` sweep.
A trailing foot out of reach now blends toward the reachable point (`foot_ik_v2_reach_blend.gd`)
instead of releasing in one frame (a 50-120 deg foot snap on a flat walk). A joint speed cap or an
eased release of the IK correction is NOT an option: it makes the foot lag its target and clips or
floats (tried at 6 and 12 deg/frame). Debug tools: `foot_ik_v2_joint_flash.gd` (red sphere on any
leg joint that turns more than the walk animation's own per-frame max x1.5, and on spine/shoulders/
arms over 6 deg; headless prints `[JointFlash]`), the trace has shoulders/arms and `camera_snap_y`.
The lab's `--foot-ik-v2-check` teleports the body: ignore turns across a > 0.5 m jump. macOS has no
`timeout`; `sed` cannot insert `\n`/`\t` in `c\`/`s` replacements - use the Edit tool.
v2 perf: measure with `--foot-ik-v2-perf` (per-part usec). The big costs were per-frame vertex work
and a fresh `PhysicsRayQueryParameters3D` per ray; the skinned sole lives in `foot_ik_v2_sole.gd`.

For stair-specific Foot IK iteration, use `tests/manual/foot_ik/foot_ik_stair_lab.tscn` - the
focused harness for the current stair work (see `AGENT_TASKS/030`). It records the real Player
walking floor -> stairs -> top landing, then lets you scrub/step/reverse/slow it, with per-foot toe
trails and toe spheres (blue right / purple left), a red clip sphere at any penetration, an editable
step height (Rebuild + Record), and a per-frame log at `user://foot_ik_stair_lab.jsonl` (frame,
root, yaw, worst joint delta local+world, clip, per-foot ankle/toe/owner/adj/swing). `foot_ik_preview.tscn`
remains the broad multi-character stress harness; the lab is the single-stair case - do not confuse them.

**The stair clip (025) and the stair joint jank (028) are one mechanism, not two** - proven this
session. On a stair step-up the support/swing foot's solve target steps up a full tread in one frame;
its planted toe/leaf then sits inside the riser, so the 025 toe-clearance retry fires, and the retry's
re-solve spikes the joints 40-180 deg. So *every* single-knob attempt trades the clip against the
jank: the retry rate, the constrained-bend-plane continuity, the solve-rate boost, a riser-based
landing, the support-transfer arc, the swing weight ramp and the boundary blend were all tried and
are all null/worse (details and numbers in `AGENT_TASKS/028` and `030`). **Do not re-try them
individually** - a fix must stop the *base pose/target* from producing the clip-worthy step, not
patch the correction. Two more load-bearing facts: the stair swing leg is **released** to the
authored animation (`owner == STAIR_SWING`, `leg["hit"] == false`), so no per-leg target shapes it,
and the predictor's `update_swing_lift` never runs for a no-contact leg. The deeper cause is
architectural: a *flat-ground* walk clip corrected by reactive IK is the wrong base for stairs
(the corrections fight the clip). The two ways out - an authored stair-walk clip, or a procedural
leg gait - are scoped in `AGENT_TASKS/031`; the 030 prototype (a solved swing arc) exists, gated off,
only as a live A/B in the lab.

The completed consolidation is archived at
`AGENT_TASKS/archive/010_foot_ik_target_coordinator_consolidation.md`
(migrating every target owner through one validated boundary); `009` holds the ownership-matrix
review behind that decision, `008` the still-open platform-edge bugs, `011`/`012` newer findings,
`013` the knee-bend-plane search instability (`_select_feasible_bend`, shared by every leg solve
on every surface—three of its own fix attempts and two other pipeline discontinuities before one
finally stuck), `014` an FPS-collapse investigation in `foot_ik_preview.tscn` (performance, not
correctness—closed for the split-safe-root retry cost and a CSG concave-collision fix, but see
its own "Open" section for a separate still-unresolved GPU-side mystery), `015`
an outside architectural assessment (coordinator isn't the actual final authority, implicit
time/coordinate-space contracts, "valid" conflating several distinct states) scoped into
incremental next steps rather than a rewrite, and `007` the earlier stair/locomotion
architecture. Put exact live frames,
coordinates, rejected attempts, and current pass/fail evidence in the relevant numbered task—not
here.

Ownership boundaries:

- `player_foot_ik_modifier.gd`: contact/gait policy and shared-pelvis coordination;
- `foot_ik_ground_sampler.gd`: collision sampling and target/normal smoothing;
- `foot_ik_gait_tracker.gd`: vertical motion, weights, phase, landing, and target locks;
- `foot_ik_stair_predictor.gd`: tread prediction and support transfer;
- `foot_ik_target_coordinator.gd` / `foot_ik_target_plan.gd`: the final arbitration boundary that
  validates a candidate target (stance zone, ground support, reach, toe/leaf envelope) before it
  reaches the solver—not every owner is routed through it yet, see `010`;
- `foot_ik_leg_solver.gd`: closed-form bone output only—no raycasts or support policy.

Foot targets retained across frames must be supported, reachable, on the correct surface, and inside
the rotated body-relative stance rectangle (0.06–0.56 m outward and ±0.40 m longitudinal). Collision
and full weight alone do not prove a valid rendered pose. Check final post-modifier soles, toe/lowest
points, knees, complete skinned leg volume, and intermediate frames.

Preserve authored poses on flat ground. IK should engage for meaningful terrain/contact differences,
not flatten ordinary gait. Unsupported unreachable limbs must return to animation with zero IK; aiming
at any invented point reads as an invisible floor.

Idle freeze, support latches, landing ownership, stair ownership, and locomotion stance locks are
separate state owners. Every release must clear the key used by downstream target locking. When adding
an override, inspect every cache/freeze/lock that can supersede it. A released foot retaining
`_idle_freeze_yaw[side]` is invalid even if the generic trace anomaly summary is clean.

A validated ankle target does not prove a clean pose. Check the toe/leaf's own forward reach (at
the current animated foot orientation) against real geometry too—an ankle plant can be perfectly
supported while the toe pokes into a neighboring riser/platform the ankle-only check never sees.
Verify with a direct `intersect_point` at the toe/leaf's own candidate position, not a raycast
height comparison from above the ankle's column: a downward scan flags any nearby taller surface
as an obstruction even when it is a separate platform with open air beneath it (a legitimate
split-height stance), and never confirms the toe's own point is actually embedded in solid ground.

A fallback plan must never be vetoed by the same check that rejected its primary candidate—that
defeats the fallback's purpose and can drop a leg to full unconstrained animation release instead
of a small, better-than-nothing correction. When migrating a target owner into coordinator
validation, a moving/interpolating target (e.g. an in-flight acquire transition) cannot be
validated the same way as a settled one: checking "is there real ground under this exact
in-flight waypoint" can fail correctly-converging transitions that never touch bad ground;
validate against the real destination instead, or validate once at acquisition start and trust
the interpolation. Migrate and full-suite-verify one owner at a time—two owners together can hide
which one caused a regression, and a single owner can still produce more than one distinct
regression across separate fix attempts.

A correction meant only for a specific recovery case (e.g. pulling a retracted/edge foot back
across the midline) must be scoped to that case, not evaluated unconditionally on every idle
frame—applied too broadly, it fights the authored animation's own ordinary stance/sway on
completely flat ground with no edge or retraction involved. Likewise, a "preserve the authored
pose" fast path must actually take effect whenever its own conditions say so; a separate
mechanism (e.g. pelvis recentering) that forces a full re-solve for unrelated reasons (a pure
lateral shift, not an actual vertical crouch) can silently override it and reintroduce
correction where none was wanted.

Use directional contact clearance: positive means a foot may be above support; negative means the
surface penetrates the foot and must engage IK. Noisy streak counters should decay on marginal noise,
not hard-reset, while genuine swing reversal must reset immediately.

Stairs and ramps have different ownership. Flat discontinuous treads may retain support; continuous
slopes follow current contact. Seamless traversal collision must bypass discrete stair stepping and
clear stale discrete presentation offsets. Keep short-fall movement allowance separate from the
smaller stationary Foot IK support depth.

Anatomical reach is not enough. Preserve side ordering, knee-above-ankle where appropriate, preferred
standing flexion, and a downward shin cone for flat upright idle/walk. Hard joint limits and preferred
standing poses are different constraints. Validate the final rate-limited pose, not only the ideal
two-bone result.

Landing prediction should use last stable grounded foot spacing; airborne poses can narrow before
`jump_land` widens. Validated support must survive brief landing-animation probe misses, but landing
grace and joint-rate continuity still prevent first-frame snaps. Moving landings go directly to the
matching locomotion state rather than translating a static landing pose.

Every newly escaped live Foot IK bug implies a missing regression. Reproduce the exact state or input
sequence and assert the visible symptom across time; final contact/weight checks are insufficient.
When the user's live repro and headless harness disagree, preserve the trace, investigate the call
pattern, and require manual confirmation. A fresh cold spawn at a suspect position/yaw often will
not reproduce a live bug that depends on accumulated state (latches, freezes, transition history);
replay the actual settle-then-move history that led there instead of jumping straight to the
end pose.

A fix that shows zero measurable effect on its target metric is not proof it is wrong. It can be
correct but masked by a separate, larger discontinuity elsewhere in the same pipeline that
dominates the exact measurement being checked—reverting on a null result is still the right
default (see `AGENT_TASKS/013`'s own three-attempt history), but if the null result is
surprising, look for another mechanism hitting the same metric before concluding the approach
itself was wrong. The same fix, unchanged, was confirmed correct once the two other
discontinuities masking it were found and fixed separately.

A shared search/selection function can have more than one independent call site. A fix threaded
through one call site's new parameters (e.g. an added `side`/`delta`) does not reach a different
caller still passing the old, shorter argument list—that caller silently takes whichever
default/early-return branch the new parameters fall back to. Grep every call site of a function
before concluding a fix "does nothing" against a metric; it may simply never execute on the path
that metric exercises.

Hysteresis/rate-limiting is not a universally safe correction to add to a per-frame
recomputation. It helps a value that should track a continuously drifting target (a rotating
body, an ordinary gait swing) but can actively hurt a correction whose entire purpose is to snap
quickly across a hard boundary (e.g. flipping a wrong-side knee back across its sign boundary)—
added lag there can render a visibly wrong intermediate pose for several frames, producing a
worse or differently-located discontinuity than the instant snap it replaced. Do not assume a
smoothing pattern that fixed one call site will help a structurally similar-looking but
functionally different one; verify each on its own terms.

A retry cooldown guarding an expensive per-frame recomputation (e.g. `014`'s ~6500-raycast
split-safe-root ring search) must cover the success path, not only failure. "The cached result is
stale" is often defined as "the caller is already at/satisfied by the last result"—which is
exactly as perpetually true on success as "still hasn't found anything" is on failure. A cooldown
armed only in the failure branch still lets a settled, arrived-at, no-longer-changing state
re-trigger the full expensive search every single frame forever. Confirmed live: this specific gap
was the actual cause of a real 60→35fps drop while idling on angled stairs, after `014`'s own
already-shipped failure-only cooldown had been believed to fully close this class of bug.

When a check's pass/fail is one long chain of `and`-ed conditions, read the exact boolean chain
before assuming which printed field is the blocker. A field that looks like the obvious
candidate (closest in spirit to what changed, or the largest-looking number) can be well under
its own limit while a completely different, unrelated field is the one actually failing.

An idle-pose position/rotation matrix does not need a dense spatial grid: an interior point on a
uniform surface (ramp, flat tread) is translation-invariant, so real bugs cluster at edges,
corners, and heading, not at extra interior samples. Prefer a handful of curated positions
(center plus each edge/corner) crossed with a fine rotation sweep over a full 2D position grid—
`foot_ik_ramp_matrix_check.gd`'s sweep mode cut from 6240 to 168 cases this way with no loss of
found failures (all failures were at edges; none were at center). The same applies to locomotion
coverage: walking only straight along/against a slope's grain and never at a diagonal or
cross-slope heading is a real, easy-to-miss gap—see `AGENT_TASKS/012`.

During Foot IK iteration, run the fast high-signal suite. It includes project checks, core pose and
stair checks, edge landing/safety, landing stability, split stance, idle seams, and planted-idle
stability while excluding the expensive known-red ramp matrices:

```sh
scripts/check_foot_ik_fast.sh
```

Before committing confirmed Foot IK/stair changes, and whenever shared solver or ramp behavior
changes materially, run every exhaustive entrypoint independently and report the complete map even
if one fails early:

```sh
scripts/check.sh
scripts/check_foot_ik.sh
scripts/check_foot_ik_ramp_locomotion.sh
scripts/check_foot_ik_stair_repeat.sh
scripts/check_foot_ik_locomotion.sh
scripts/check_foot_ik_ramps.sh
scripts/check_foot_ik_ramp_sweep.sh
```

Do not parallelize Godot scenes merely to make this suite faster: concurrent imports, shared
`user://` traces, and marker state can contaminate results. Redirect each run to a file and extract
only PASS/FAIL summaries. The multi-character preview is a stress case, not representative one-player
FPS; preserve performance regressions for support searches as well as pose regressions.

`check_foot_ik.sh` is `set -eu` with a hard `exit 1` per failing check (~39 sites), and it is not
run by any active CI workflow (`.github/workflows/project-checks.yml` is manual-trigger-only and
runs `scripts/check.sh` - lint only). This means a pre-existing failure anywhere in its sequence
silently prevents everything after it from ever running locally, including the sibling scripts it
chains at its tail (`check_foot_ik_ramp_locomotion.sh`, `check_foot_ik_stair_repeat.sh`,
`check_foot_ik_locomotion.sh`) and two more it never calls at all
(`check_foot_ik_ramps.sh`, `check_foot_ik_ramp_sweep.sh`) - always run
`scripts/check_foot_ik_all.sh` instead when you need the complete picture (see
[012](AGENT_TASKS/012_foot_ik_ramp_cross_slope_penetration.md)'s "Wired into a runnable
script" section and [015](AGENT_TASKS/015_foot_ik_architecture_direction.md), point 6): it runs
every entrypoint and sibling script in one pass, continuing past failures, and separates
`KNOWN_BASELINE_FAILURES` (edit that list by hand, with a reason, when a baseline genuinely
changes) from new/unexpected ones, which make it exit non-zero. `check_foot_ik.sh` itself stays
fail-fast on purpose for a quick single-issue check; use the `_all` script for anything you plan
to trust before committing.

`check_foot_ik_all.sh` itself used to grade the two ramp-matrix scripts by whole-script label, so
a worse run inside an already-red script could hide forever behind the same `FAIL known` line -
fixed by counting the actual `FOOT_IK_RAMP_CASE FAIL` lines and worst `max_depth_m` directly
instead of trusting `check_foot_ik_ramps.sh`'s own printed `failed_cases=`/`worst_depth_m=`
summary field, which was itself found to be unreliable (reported `0`/`0.0` in a run that actually
had 20 real per-case failures). Verify the harness's own bookkeeping the same way you'd verify
any other code - do not assume a passing/known-failing suite result is trustworthy just because
it has always been treated as the ground truth.

A `SkeletonModifier3D`'s "final pose" accessor is only truly final if it is captured after every
modifier in the chain has run, not just the one that built the cache. `PlayerFootIKModifier`
already computed a complete post-solve snapshot every frame, but `get_visual_bone_global_pose()`
still preferred `PlayerLookPoseModifier`'s own earlier cache unconditionally - correct for bones
only the look modifier ever touches, silently stale for the pelvis, which Foot IK moves
afterward. A new modifier added later in the chain (e.g. a balance/counter-lean layer) makes the
same class of snapshot stale again unless whichever modifier runs last publishes the canonical
one. Frame-stamp any such cache (`Engine.get_physics_frames()`) so a consumer can tell fresh from
stale rather than assuming "was populated at all" is enough.

When snapshotting "what value was already validated/accepted" to compare against later, capture
it inline at the exact site where the real value is selected - do not restate the same
field-priority logic in a second place. A live-tested fix compared a coordinator-validated
target against a re-derived snapshot that read `target` before `ground_target`, while the real
solve-time selection reads `ground_target` first whenever `preserve_idle`/`brace_upper` is true
(a very common idle-stance case) - the mismatch silently invalidated the flag almost always,
making an expensive guard run far more than intended (visible pose change plus a measurable FPS
cost). The fix was to snapshot the actual local variable at its real assignment site, not to
"fix" the restated condition to match; a supposedly-equivalent restatement of selection logic is
exactly where this kind of bug hides.

A brand-new script file's first appearance in a headless test run can produce multiple transient
false failures across unrelated scenes (Godot's script-class import cache still catching up,
observed the moment a `.gd.uid` file first appeared mid-run) - before treating a fresh run's
failures as a real regression from a newly-added file, rerun the full suite once more and rerun
the specific failing scenes individually; if they pass clean the second time, it was the cache,
not the code.

A pelvis/gait quantity gated behind a specific condition (e.g. `is_flat_idle`, `is_edge_asym`)
can read as exactly zero in a case that still looks visually asymmetric to a person watching -
an ordinary split stair stance, both feet individually flat on their own tread but at very
different heights, satisfies `is_flat_idle` and never triggers `_pelvis_lateral_shift`'s
non-zero branch at all. Do not reuse an existing gated signal for a new, differently-scoped
purpose (a cosmetic balance/counter-lean layer, say) without confirming its own gating actually
covers the case the new feature is meant to address; compute an independent signal instead if it
doesn't.

A straight-line `move_toward` between two world-space surface points at different heights (the
idiom this file uses throughout for idle repositioning) only ever checks its two endpoints
against geometry, never the path between them - it can visibly clip through a step's edge/riser
mid-transition even though both endpoints are individually valid, because interpolating X/Y/Z
together takes a shortcut that dips below the higher tread while still short of it horizontally.
A guessed fixed-height lift/arc over the path is not the fix (tried first, still clipped, and
separately needed shrinking once already after it silently ate into an unrelated per-frame joint-
step budget); check the actual swept path against real geometry each frame and hold at the
blocking point instead of pushing through - the character's own continued rotation re-aims next
frame's raw probe, so holding is not a stuck state. This is a different, smaller fix than the
general "deliberate recovery step" feature this project has also discussed; do not conflate them.

`FootClearanceEvaluator.evaluate_box()` (pure box-vs-points geometry, no physics query) is cheap
enough to run every frame for a handful of sample points and is the right tool for asserting "did
this point ever penetrate real geometry during a live replay," not just "is the settled pose
clean" - a repeated-rotation-on-stairs regression check found a real toe/leaf clip this way
(10cm deep, building up over many consecutive frames) that no existing check caught, because
every existing check only measured vertical clearance to whatever's directly below the *settled*
foot. Find the actually-relevant collider(s) generically at runtime (a small-sphere
`intersect_shape` query, then read each hit's `CollisionShape3D`/`BoxShape3D`) rather than
hardcoding tread coordinates, since the point may be near either the surface it's leaving or the
one it's approaching, not the one directly beneath it.

A validated candidate-pose safety check cannot protect a leg that exits earlier through an authored-
pose preservation/release fast path. Treat every pre-solve `continue`/release as a validation bypass:
if the preserved final toe/leaf is measurably inside real geometry, that fast path must yield to the
clearance solve while remaining unchanged for unobstructed flat gait. Confirm the failing frame
actually reaches the intended check before tuning the check itself.

An iterative toe/leaf clearance correction must resample the collider under the new deepest point
after every pitch/target adjustment. On discrete stairs, one correction can move the offender from a
lower tread into its neighboring higher tread; reusing the first hit's surface height makes later
retries identical or lifts against the wrong box. Also structure the loop so the final permitted
correction is evaluated, rather than updating the target once more and then exiting.

Foot IK regressions must pair root transforms and final bone poses from the same physics frame.
`SkeletonModifier3D` may publish after a test node's `_physics_process()`, so a current root plus the
previous frame's `_final_bone_poses` creates false clips at starts, stops, and direction changes. Use
`has_fresh_final_bone_poses()`, sample after modifier publication (often `_process()`), and deduplicate
by `Engine.get_physics_frames()`.

Foot IK's target-coordinator toe/leaf envelope check (`_toe_envelope_valid`,
[archived task 008](AGENT_TASKS/archive/008_foot_ik_platform_edge_safety.md))
only runs for an owner that reaches `_finish_validation` at all - `legacy_transition_active`
(true whenever *either* foot is mid lower-tread transition) silently disables coordinator
validation for every owner except the three lower-transition ones themselves, even for a
completely different, already-settled foot on a totally different owner (e.g. `LANDING_UPPER`)
that isn't transitioning at all. A real live toe-clip investigation initially "fixed" the toe-
envelope check itself (adding a retreat-toward-hip search) and saw zero effect, because the
clipping foot's owner never reached that check in the first place - always confirm which owner
governs the leg's target at the exact failing frame (`get_plan(side).owner`/`.reason`) before
assuming which validation path is responsible; a target can be governed by an entirely different
subsystem than the one being debugged, and two structurally-plausible fixes can both miss for
this reason before the actual gate is found.

Feeding the coordinator's fully-accepted/validated leg target into shared-pelvis centering
(`_apply_support_pelvis_and_legs`'s lateral-shift/reach-drop math) has independently regressed
twice, from two different substitution attempts, for two different reasons - treat this as a
load-bearing boundary, not an oversight to "finish migrating." (1) Pelvis centering can be
`ground_weight`-*weighted* when the two feet's weights differ; the 22cm stance-spacing proposal
adds a *symmetric* +/-11cm offset around the feet's midpoint, and a weighted average of
asymmetrically-weighted, symmetrically-offset points does not equal the original weighted
average - feeding pelvis the post-spacing target caused real body penetration. (2) When the
coordinator's own validation fails, `_raw_recovery_plan` supplies a fallback meant to give the
*leg solve* something reasonable that frame, not to serve as a stable reference; feeding pelvis
that same accepted-plan value inherited its per-frame validation-failure churn and produced a
real pose distortion during ordinary walk locomotion (`AGENT_TASKS/018`, "Shared-pelvis/reach
design"). Both attempts were individually reasoned, individually tested clean against the
existing fixtures, and both still broke something the fixtures didn't cover - use the *stable,
pre-selection* per-leg target for pelvis math, or a value that has deliberately never touched
spacing or the validation-recovery path, not "whatever the leg ultimately solves to."

`leg.get("target", leg.get("ground_target", fallback))` is not a real fallback chain when both
keys are *always* set on every leg every frame - it always resolves to `target`, silently
ignoring any later "prefer `ground_target`" decision made elsewhere (e.g. via a
`prefer_ground_target` flag the coordinator consumes). A `.get(key, fallback)` chain only means
what it looks like when the earlier key's *absence*, not merely a separate boolean elsewhere,
is what should trigger the fallback. This specific gap predates all of today's target-selection
work and was never touched by any of it - grep for the actual precedence flag before assuming
a `.get()` chain already encodes it.

`_gait_tracker.is_body_translating()` is **velocity-based** and reads 0 while the stair controller
moves the root by writing `global_position` (not `velocity`), so it is false during genuine stair
travel. Gating stair logic on it (a preserve-pose escape, a clearance retry) silently never fires
mid-climb. Use the predictor's `is_active()`/`is_descending_treads()`, a position-derived travel
signal, or the animation clip - and verify the gate actually turns on at the failing frame before
concluding the logic is wrong.

A clearance/safety check placed *inside* a `SkeletonModifier3D` pass reads the skeleton **before
that same pass writes its bones**, i.e. the previous pose, not the one it is about to publish
(`_final_bone_poses`). A check there can read "clean" while the harness reads a 1-3cm clip on the
published pose. Measure the pose that will actually be rendered (evaluate the candidate first, or
check after the write) - and remember the published pose is what the regression tests read.

Debug toggles + per-part timing live in `actors/player/foot_ik/foot_ik_debug.gd` (`FootIKDebug`)
and the preview's F6 feature panel ("Debug: subsystem switches + profiler"): one on/off switch per
subsystem (toe clearance, stair support, swing lift, balance, idle stance) plus a profiler that
prints a `[FOOT_IK_PERF]` per-part table. Off by default = zero cost. First measured result: the
`support` (pelvis/support/leg-solve) pipeline is ~78% of the IK frame cost, the clearance retry
~0 - see `AGENT_TASKS/027`. Engine-wide counters remain in `foot_ik_perf_probe.gd` (`FOOT_IK_PERF_LOG=1`).

## Procedural world, plants and planet

Code-only worlds: the flat streaming world (`systems/world_gen/`, `AGENT_TASKS/040`), the plants
(`systems/world_gen/flora/`, one `TreeGrower` for every plant but mushrooms, reference
`docs/tree_builder.md`) and a round walkable planet (`systems/planet/`, reference
`docs/planet_generation.md`, handoff `AGENT_TASKS/043`). Durable rules: the planet never changes the
player (it turns the planet under the player, `PlanetFrame`); ground and water are built before plants
and nothing grows in water; do not assign `HeightMapShape3D.map_data` directly (use `set()`, it is a
float64 array in a double precision build); planets above ~1,000 km need the double precision editor
(build notes in the planet doc). The planet follows real causes (orbit, spin and tilt give the sun, day and seasons; do not fake an effect that
has a cause: `AGENT_TASKS/043`). Checks: `species_check.tscn`, `world_lab.tscn -- --world-check`,
`planet_lab.tscn -- --planet-check` and `-- --walk-check --fixed-fps 60`.
Planet generation is an active experiment and changes often: expect to rewrite it, keep no compatibility code for old
approaches, and write new planet computation in native C++ (see "Native first" above).
What we learned (how to measure frames and hitches, where the frame went, clouds, the air, saves,
engine traps): `docs/planet_lessons.md`; read it before changing planet rendering or streaming.

### Measuring planet performance and looking at results

All of it runs through the lab, `godot --path . res://tests/manual/planet/planet_lab.tscn -- <args>`
(every argument is listed in the comment at the top of `tests/manual/planet/planet_lab.gd`; with no
arguments the lab now starts an Earth with a random seed at a tenth of the size (`PLANET_SCALE=1` for the whole
Earth, `--start-menu` for the menu) with the map open first; scripted runs always pass some arguments). Needs a window
(not `--headless`) for anything about frames, shaders or pictures; stop the game after a verification run.
- **Where the time goes:** `PLANET_TIMING=1` prints the laps of making a planet (plates, sea level, climate,
  drainage, river network) and `ground ready after N s, T tiles built`; `--map-first --close-map=N` tests the
  map-first loading. Heavy native calls spread over threads by themselves (above 16 k points), so a run on a
  busy machine is slower than the numbers in docs/planet_generation.md.
- **Frames:** `-- --fps` prints every 300 physics frames: fps (uncapped), draw calls, primitives, tiles and
  the triangles by kind of node (draw calls and primitives are the main pass; shadows are not in them).
  Read the *last* lines: plants and tiles stream in for ~900 frames after the loading screen.
- **What a kind costs:** `--hide=trees|plants|ground|water|grass|full|light` (one kind not drawn),
  `--no-shadow`; the fps difference against a plain run is the cost.
- **Altitude:** `--climb=N` lifts the real player N metres looking down (`--view-alt=N` is a camera
  without a player and does not refresh the tile detail: not for performance).
- **Hitches (streaming):** `--walk-check` and `--fly-check` print `HITCH worst_frame=... frames over 33 ms`
  after the loading; it is noisy (4-38 slow frames between identical runs): run it three times and compare
  the middle values.
- **A person walking round the forest (the real-use performance test):** `-- --plants --grounded --forest-walk=45
  --fixed-fps 60` (add `--run` to jog, `--calm` for no wind). The player walks with the real physics, steers
  round trunks with rays, wanders, unsticks itself, in a gusty wind; after a warm-up it prints `FOREST_WALK`:
  average fps and 1 % low, frame ms p50/p95/p99/worst, slow frames, GPU ms, render CPU ms, draw calls,
  primitives. Counts rendered frames (not physics steps). Run it three times and compare the middle values.
- **Where the GPU time goes (by taking things away):** `scripts/gpu_breakdown.sh [SECONDS]` runs that walk once per
  switched-off thing (trees, ground, plants, water, clouds, sun glow, impostors, bark parallax, bark photos) and
  prints each one's GPU ms and share. One run per line is noisy (about 0.4 ms); never run two at once (one GPU).
  Per-pass GPU times are not readable from scripts: use the editor's Debugger > Visual Profiler.
- **Pictures:** `-- --shot-frame=N --shot=E:/path/x.png` saves the screen at frame N and quits; read the PNG
  to look at it. Set the scene with `--hour=`, `--year=`, `--weather=rain|snow|storm`, `--view-alt=`,
  `--view-pitch=`, `--radius=`, `--seed=`, `--planet-page`, `--start-menu`. Take one before and one after a
  change at the same arguments.
- **Pass/fail checks** (no window needed): `--planet-check` (also runs `SAVE_CHECK`), `--walk-check`,
  `--swim-check`, `--fly-check` (slow, run in the background), `species_check.tscn`,
  `world_lab.tscn -- --world-check`.
- **Native planet crust (optional C++):** `scripts/setup_native.sh` once per machine builds `native/planet_crust` 
  (godot-cpp and scons are fetched into `~/.cache/godot-native`) and hooks a pull or a checkout to rebuild it
  when the C++ changes; `scripts/build_native.sh` alone builds if needed. Without the library the planet runs
  on the GDScript (the reference, about 5 times slower, no river valleys). `planet_check.sh` checks it
  (`NATIVE_CHECK`). A library must match the engine's precision (the double build has its own, see the
  README of the folder).
- **All checks in one go:** `scripts/planet_check.sh [--quick] [--lint-only]` (lint, import, universe, species, world,
  planet, save, walk, swim and, without `--quick`, fly; one PASS/FAIL line each, exit 1 on a failure; set `GODOT=` if
  `godot` is not on PATH; logs in `$LOG_DIR`).
- Record the numbers in the doc or task you are working on (`planet_lessons.md` has the measured history),
  and keep new measuring tools as lab arguments. A single script that runs everything and compares to a
  budget is planned: `AGENT_TASKS/046`.

### Surface relief from photographs (parallax occlusion, "SPOM")

Real surfaces beat procedural ones: a photographed height map read by the parallax march looks far more
natural than any plate or noise we wrote, and a texture read is cheaper than the procedural height (the
bark change made the forest lab view about 1 ms faster). The recipe, first used for tree bark
(`AGENT_TASKS/084`, findings in `AGENT_TASKS/083_findings.md`), works for anything with a surface:
- **Source:** CC0 maps from Poly Haven (`polyhaven.com`, API `api.polyhaven.com/assets?t=textures`,
  `/files/<name>` for direct links, `/info/<name>` for the real size in mm). Diffuse + displacement at 1k.
  Download to a scratch folder, never commit the downloads, only the packed result.
- **Pack:** one atlas, colour in rgb and the height in alpha, built by a script in `tools/` (see
  `tools/build_bark_atlas.gd`: stretches the height to the full range, lifts dark photos to a real albedo
  of about 0.1 linear luminance). Import it as a Texture2DArray by writing the `.import` with
  `importer="2d_array_texture"` and `slices/horizontal` / `slices/vertical`, then run `godot --headless
  --import`. Sample it as `sampler2DArray ... : source_color`; use `textureLod` inside the march with a
  mip level worked out from the distance (a varying), never derivatives in a loop.
- **Map:** keep the real size of the picture in metres (a table next to the sampler); tile a WHOLE number
  of times round a closed shape so no seam shows; shift each object its own way (a per-object hash) so
  neighbours do not match; gate the march by distance (one step beyond the fade range: every loop needs a
  distance gate, check `--fps` after the change).
- **Use:** the height drives the parallax march, the self shadow, the slope normal and the cavity ambient
  occlusion; the colour is the albedo. Keep a procedural fallback for what has no photo.
- **Where it applies, not yet done:** rocks and cliffs (`AGENT_TASKS/084`), the terrain's scans in
  `planet_ground.gdshader` (it has its own parallax already), buildings and props, ground litter, and
  characters (skin, cloth, leather: needs a UV unwrap that is not stretched; check the seams first).
- **Look at it:** `tests/manual/world/bark_view.tscn -- --species=0 --kind=N --dist=1.4 --shot=PATH`;
  compare a render with the photograph side by side before calling it good.

### Procedural surfaces fitted to photographs ("photo-to-procedural", bark first)

A generator copies a real material's look so the image files can go, every tree can differ, and the
look can change with species, age or weather. Built for bark (`AGENT_TASKS/085`, files in `tools/bark/`);
the same pipeline is meant for rock, soil, leaf litter, cliffs and buildings. The loop:
1. **Reference:** Poly Haven CC0 diffuse + displacement, real size from `/info/<name>`. Keep the downloads
   out of the repo (scratch folder).
2. **Measure:** `analyze_flakes.py` cuts the height map into flakes (local threshold + watershed) and reports
   size, aspect, direction, coverage in centimetres. Python is `E:\anaconda3\python.exe` (numpy, scipy,
   cv2, numba, torch + CUDA, `cma`; scikit-image is broken there).
3. **Generator:** `procedural_bark.py` (reference maths, 27 parameters) and `bark_fast.py` (the same in numba,
   20 times faster, identical output). Design it like the real thing (shingled, overlapping flakes with
   ragged edges, grooves, splits), with a few parameters that span the real variety.
4. **Fit:** `bark_perceptual.py`: CMA-ES over the parameters; the loss is the VGG19 Gram matrices of a LIT view of the
   generated height picture (hillshade from two sides + the height; raw heights let the search drift to smooth blobs)
   against the photo's (the look) plus a cheap size term (the Gram matrices do
   not see scale). A statistics-only loss (sizes, spreads) does NOT work: the search finds shapes with
   the right numbers that look wrong. Judge every fit with your own eyes: render generator and photo side
   by side (`gen_vs_photo*.png`) before trusting a loss.
5. **Colour:** `export_fit.py` takes from the photo the mean colour, a ramp by height, how brightness follows
   the cavity and a slow mottling, and writes `systems/world_gen/bark_fits.gd` (generated, never edit).
6. **Game:** `shaders/world/bark_bake.gdshader` is the generator in GLSL (it tiles: every scale a whole number
   of repeats, cell hashes wrapped); `BarkBaker` draws it once into a tile at load (5 to 20 ms a bark) and
   builds the texture array the plant shader samples (`BarkBaker.make_array`, called by
   `PlanetWorld._bake_the_bark`). Bake once and sample: do NOT run the generator inside the parallax march
   (about 30 calls a pixel).
7. **Check:** `bark_view.tscn` (F6 in the editor: photographs left, baked procedural right; `--kind=N`,
   `--rise=M` for an angled view, `--species=N`); `--fps` forest view must not get slower; planet_check and
   visual check.
Status: oak (willow) is procedural in the game; pine reads as leaves and ash is too rough with a tile seam,
both stay photographs; maple, palm and cedar have no fit yet. Tool scripts must `quit()` on every path
(a script that errors in `_init` hangs).
Resource limits for the tools: `tools/bark/limits.py` (imported first by the fit scripts) caps the CPU cores
(`BARK_CORES`, default 3 of 6) and lowers the priority; a fit of 10 generations took 24 s at 3 cores. The Godot
runs of the lab use the GPU; no cap there (run one at a time).

Lessons from fitting bark, rock, soil and litter (2026-10-23):
- **Which generator family:** flaky barks (willow/oak) and soft mottled barks (maple) work with the flake generator
  (`procedural_bark.py`, 37 parameters: flakes, swelling + flakes, fibres); leaf litter works with the SAME generator
  turned isotropic (`fit_litter.py`: small cells, flakes turned in any direction); the rock generator (`rock_gen.py`:
  blocks, cracks, strata, rubble) fits rocks numerically but baked it shows a pixel mosaic and a turtle-shell crack
  network, so the game keeps the rock photographs (`PLANET_PROCEDURAL_ROCKS=1` to try). Fibres (cedar) and rings
  (palm) and fine soil speckle still need their own families. Pick the family by LOOKING at the photo first.
- **Loss:** the style loss must see a lit view of the height (hillshade): raw heights drift to smooth blobs. An outlier
  term in the loss made things worse (grey fog).
- **Always** write and look at the side-by-side picture; every statistics-only or number-only success so far looked wrong.
- **Ash:** `fit_ash.py` refits the ash with flakes turned both ways (diagonal criss-cross ridges) into `fits/tree_bark_03_ridges.json`; judged against the photo: still bristling spikes, not criss-cross ridges (the photo is long vertical ridges with cross cuts), so NOT used; the ash stays a photograph. A ridge family was tried (`ridge_gen.py`, long wandering ridges + cross cuts): too clean and blocky (smooth tubes with square cuts), also not used. The photo needs ragged ridge edges and tapered tips; next try: ridges whose edges are broken by the flake generator.
- **Pine (square refit):** `fit_pine.py` (blunt tips, block share up) gives blunter plates but still stacked, overlapping, with black gaps and drip-like lower edges; the photo has flat plates side by side with thin cracks. Kept as `fits/pine_bark_square.json`, not used. Next idea: a plate-tiling (Voronoi-like cells with thin cracks) family instead of overlapping flakes.
- **Pine as plates (best so far):** `plate_gen.py` + `fit_pine_plate.py` (Voronoi plates stretched along the trunk, thin cracks, ragged edges) gives flat plates side by side, the right structure (`fits/pine_bark_plate_vs.png`); a try with more plate height variety (z_var 0.4-1.0, lip up to 0.45) was worse (loss 2.8, black and white plates), so the photo variety is small and the missing depth is at the edges; still too uniform: the photo has deeper steps between plates and more height variety. Not ported to GLSL yet; next: raise plate height variety + a step at overlapping edges, then port to `bark_bake.gdshader` as a kind.
- **Pine plates in the viewer:** `plate_bake.gdshader` + `PlateBaker` + `plate_fits.gd` (`export_plate.py`) bake the plate fit; `bark_view` (all fits) shows it in the pine slot. It tiles and has the right crack network; with the per-plate palette (`PALETTE_MIX` 0.85) it now has orange, tan and grey plates like the photo, but an edge shadow (`rim`, 45 %) helps a little; cell size capped at 3-6 cm in `fit_pine_plate.py` (loss 2.09, worse than the 8 cm fit at 1.87, but the picture is closer: plate size matches the photo, another case of best loss != best picture). The baked height is stretched x1.6 around 0.5 for a deeper relief (reads better). The palette matches the photo (mean 0.40,0.33,0.25 both), so the greener look is the shader's lichen paint, not the bake. Remaining difference: relief and plate shape, still lighter than the photo (the photo is browner/orange) so not in the game. Not in the game.
- **Palm (ring family):** `ring_gen.py` + `fit_palm.py`: a thin bright edge line with a slow dark ramp below it, repeated every ring (the profile of the photo), over vertical streaks. Lessons: the photo is 2048 x 1024 px at 0.063 cm/px so the rings are only 11-16 cm apart; the free fit chose 50 cm (global statistics cannot see spacing), so `ring_cm` is capped to 11-16 cm; the loss got worse (2.33) while the picture got right. Now reads as a palm trunk (`fits/palm_tree_bark_ring_vs.png`); ported: `ring_bake.gdshader` + `RingBaker` + `ring_fits.gd` (`export_ring.py`), shown in `bark_view` (all fits) in the palm slot: rings tile and read as a palm trunk but too clean (no ring-to-ring variation, scratches or cracks); not in the game.
- **Litter as ground scan maps (groundwork):** `GroundBaker` bakes the litter fit (`LitterFits`, `export_fit.py` from `forest_leaves_03` at 2.3 m, `BarkBaker.bake(name, seed, source)`) and `ground_maps.gdshader` turns the tile into the ground shader's scan maps (colour + occlusion, normal + roughness); `litter_bake_view.tscn` saves them (200 ms). Compared with the shipped `scans/leaf_c.png` (ambientCG Ground106, which is bare brown dirt, not leaf litter): compared with the real litter photograph (forest_leaves_03) the first bake was far too bright with white blobs (bark colour model, gain 4.9). Now: gain 0.6, mottle 0, palette mix 0.9, darken 0.6 and a refit with base/split/groove blotches capped: leaf hues and tone are close, but the leaves are too thin and small and big dark patches remain (not yet traced; the first suspects are the generator's `base`/`crown` terms). Opt-in in the game: `PLANET_PROCEDURAL_LITTER=1` replaces the `scan_leaf_*` maps with the bake (the shader now takes the scan's mean colour and tile size as uniforms `scan_leaf_mean` and `scan_leaf_size`; the opt-in sets them from the bake. Looked at in the lab at seed 1337: that ground is the red soil, so the leaf scan hardly shows and the two pictures are the same; the litter still needs a view of a dark forest floor). The refit that worked: `cell_cm` 0.8-2.2, `len` 1.0-2.4, `wid` 0.3-0.8, `flake_cover` 1.15-1.25, `base_amp` <= 0.02 (every wider range let the search make huge leaves or huge dark blobs).
- **Checks (2026-10-23):** `planet_check` 21 of 21 pass (its lint step needs `gdlint` on PATH) and `visual_check` passes after the plate, ring, litter and ground-shader changes (all of them viewer-only or opt-in).
- **Leaves:** the plant shader already draws its leaves procedurally (`leaf_cluster`: outline, midrib, side veins, ripple; `frond` for palm and fern leaflets), no leaf photograph is used anywhere in the game, so there is nothing to replace; a photo-fitted leaf (Poly Haven leaf maps) would only be a way to tune those numbers, left for later.
- **Rock face refit (tried):** `fit_rock_face.py` (pits off, rubble forced) gave a lower loss (1.195) but a worse picture: three huge smooth blocks and one black slit, nothing like the photo's pockets of rubble and crevices. The rock generator needs a rubble-pocket term of its own (clusters of small plates inside crevices) rather than range tweaks; rocks stay photographs.
- **Measure the scale first:** `tools/bark/measure_scale.py <folder> <name> <tile m>` prints the correlation length across and along, and the strongest repeat along y of a photographed height map. It found a scale bug: the palm photo is 1024 x 2048 px but the fit took `cm_per_px` from the longer side, so the palm rings were 2x too close (11-16 cm; the photo is 26 cm). `fit_palm.py` now uses tile 2.6 m and rings 20-32 cm and the rendered rings match the photo spacing (loss 1.86 vs 2.33 before). Non-square photos: pass the tile size of the LONG side. Checked all fits: every one is 1024 px square except the cedar (1024 x 2048, tile 1.0 m on the long side, already handled by `tall_slot` and visually matched) and the palm (fixed).
- **Palm photo is squeezed in the atlas:** in `bark_view` the photographed palm (left) shows rings about 13 cm apart, the baked ring bark (right, correctly 26 cm) half as dense. The palm photograph is 1024 x 2048 px, squeezed into a square atlas slot like the cedar was, so its rings and scratches are 2x too close in the game (the cedar got `tall_slot`; the palm did not). Fixed for the photograph: `tall_palm` (uniform, 2.0; the viewer sets 1.0 for the baked rings) stretches the palm slot like the cedar's `tall_slot`; the photographed palm now shows its scratches and rings at the right shape in `bark_view`. The baked rings are faint in the game (low relief): raise `ring_amp` before using them.
- **Palm rings baked, deeper:** `ring_bake.gdshader` stretches the height x1.8; in `bark_view` the rings and streaks read stronger the pixel mosaic came from the finest speckle (cells of 0.3-1 cm, 2-8 px): the speckle is now kept to cells of 1.6 cm or more in `ring_bake.gdshader` and the mosaic is gone. The baked palm is a smooth trunk with soft rings and streaks but lacks the photograph's pits and scratches; the photograph stays. General rule: parallax-mapped bakes need no height detail finer than about 8 px per cell. `planet_check` (22 of 22) and `visual_check` pass with `tall_palm`.
- **Pine plates, speckle floor:** the plate bake keeps its fine speckle to cells of 1.6 cm or more (the same rule as the palm); the plates now read clean with no mosaic, the closest pine so far, still not in the game (relief and plate-edge steps shallower than the photograph).
- **Pine plates, deeper:** edge shadow 0.7 and height x2.0 give clear plate steps; the plates are still softer and rounder than the photograph's craggy ones the lip is now a step (ramp width x0.3, base 0.55): crisper edges, a modest gain; what remains is the photograph's cragginess (plate surfaces are blobby from `tilt` and the soft noise).
- **Opt-in in the game:** `PLANET_PROCEDURAL_PINE=1` and `PLANET_PROCEDURAL_PALM=1` bake the plated pine and the ringed palm into their bark slots (the palm also sets `tall_palm` 1.0); `PLANET_PROCEDURAL_LITTER=1` the litter. Defaults stay the photographs. Cost: the forest walk (30 s, `planet_lab.tscn -- --plants --grounded --forest-walk=30 --fixed-fps 60`) gives GPU 14.3 ms avg with the photographs and 14.6 ms with both opt-ins (fps 51.3 vs 51.7: the same within noise; this machine was also busy).
- **Rock lumps (new family, best rock so far):** `lump_gen.py` + `fit_rock_lump.py` (smooth lumps from a warped low-frequency noise, creased valleys `1-|noise|`, sharp rubble fragments inside the creases, fine grain) on rock_face_04: the picture (`fits/rock_face_04_lump_vs.png`) has the right character (smooth faces, a winding crease carrying rubble) where every blocks-and-cracks fit looked like a polygon map. The loss is HIGH (4.7, the style loss cannot see this either way): judge by the picture. With free ranges the fit made blurry blobs; the creases only came with `crease_depth` 0.4-1, `crease_w` 0.03-0.09, `crease_cm` 22-45, `grain_cm` <= 3. Ported: `lump_bake.gdshader` + `LumpBaker` + `LumpFits` (`export_lump.py`); `lump_bake_view.tscn` saves the tile; the height matches the Python reference and tiles. Colour model added in the shader (a tone per lump, dark creases, lighter varied rubble, pulled towards the mean 70 %, x0.7 darker): reads as rock with a rubble crack, paler and cleaner than the photograph (dark brown with leaves in the rubble). Next: more creases of different widths, thin secondary cracks, then the rock slots.
- **Opt-in rock lumps:** `PLANET_PROCEDURAL_LUMPS=1` bakes the lump rock face into rock slot 1 (rock_face_04, 2 m tile) in the game and in `rock_view.tscn -- --baked`; `PLANET_PROCEDURAL_ROCKS=1` bakes the older blocks-and-cracks fits for the other slots. `rock_view` photograph vs lumps: only a few rocks use slot 1 and they look the same at 7 m (a close view is needed to judge).
- **Lumps on the other rock slots: no.** The forced ranges (crease depth 0.4-1, width 0.03-0.09) made all five other rock photographs (boulder, rock_08, rock_06, pitted mossy, dark_rock_02) converge on the SAME winding crease with rubble, which only rock_face_04 has; the others are mottled with no crease (boulder, rock_08), webbed with fine cracks (rock_06) or layered with straight joints (dark_rock_02). Forcing a feature that the photograph lacks is the same cheat as free ranges. `fit_rock_lump.py` is now generic (`<folder> <name> <tile m>`) but each rock needs its own choice of ranges (and probably a second family: mottled boulders = lumps without creases; layered rock = the blocks model with long joints). The five fits were deleted.
- **Plain lumps for mottled boulders (`fit_rock_lump.py ... plain`):** rock_boulder_dry and rock_08 fits (`fits/<name>_lump.json`) give cloudy lumps of the right size and tone range, but a thin dark crease still shows (the crease width range is not low enough to remove it, set `crease_depth` to 0) and the mid-scale cloud detail is smoother than the photographs (the generator has only two lump octaves; add octaves). Not exported or used.
- **Mottled boulders as lumps (works):** a middle noise octave (`mid_cm`, `mid_amp`, two noises, the second turned) in `lump_gen.py` and `lump_bake.gdshader` (15 numbers now), `plain` fits with `crease_depth` 0 for rock_boulder_dry (slot 0) and rock_08 (slot 2), colour crease/rubble only where the height has them. `PLANET_PROCEDURAL_LUMPS=1` bakes slots 0-2 as lumps; `rock_view.tscn -- --baked` shows natural mottled stone, with the lighter colour (no x0.7 darkening for faces without a crease) the set is close to the photographed one in tone; the cloud shapes are still larger and the grain softer than the photographs. Slots 3-5 (rock_06 webbed, pitted mossy, dark_rock_02 layered) still photographs.
- **Layered rock (dark_rock_02), blocks model with horizontal strata forced:** `fit_rock_layers.py`: loss 0.82 (the lowest of any rock) but the picture is a few huge blocks with fat black joint bars, worse than the unconstrained fit; deleted. The photograph has horizontal ledges with overhanging lips and small rubble in the joints; a ledge generator (stacked horizontal slabs with an overhang step, like `plate_gen` turned on its side) is the next family to try. Slots 3-5 stay photographs.
- **Ledge family (layered rock, tried):** `ledge_gen.py` + `fit_rock_ledge.py` (stacked horizontal ledges with a sharp lip, vertical joints, rubble in the joints, wavy): it makes the layered structure (`fits/dark_rock_02_ledge_vs.png`) but too regular and mechanical: even bands with a dark and light tone per ledge, none of the photograph's broken, irregular lips and rubble. Unconstrained it gave giant ledges (loss 1.12), constrained to the photograph's 6-14 cm rows it gave busy swooping bands (loss 7.0), with moderate caps (8-22 cm, tilt <= 0.3) the version kept (loss 2.4). Not used; slot 5 stays a photograph.
- **Research (2026-10-23):** `AGENT_TASKS/086_research_texture_fitting_alternatives.md`: MATch/DiffMat (differentiable node graphs), the sliced Wasserstein loss (replaces the Gram loss that keeps rewarding bigger and simpler features) and histogram-preserving randomized tiling (shrinks the atlas). First step planned: a sliced Wasserstein term in `bark_perceptual.py`.
- **Stochastic tiling test:** `PLANET_STOCH_BARK=1` / `bark_view --stoch` (see `AGENT_TASKS/086`): +1.1 ms GPU (13.6 to 14.7 ms) in the forest walk; the naive blend breaks the colour (needs the Gaussianised atlas + LUT first).
- **Pine plates with the sliced Wasserstein term (best pine so far):** `SW_WEIGHT=0.5 ZVAR_MAX=0.3 python fit_pine_plate.py ...` (plate tone spread capped, shape from SW) gives tall plates in vertical columns with wavy edges, close to the photograph's layout (`fits/pine_bark_plate_sw2_vs.png`); it replaces `pine_bark_plate.json` and `plate_fits.gd` (the Gram-only fit is in git history). Still opt-in (`PLANET_PROCEDURAL_PINE=1`). Lesson: the SW term needs a cap on the tone parameters, measured from the photograph (its plates are nearly equal in tone).
- **In the game now:** the oak, maple and cedar barks are procedural (baked at load from `bark_fits.gd`, fitted with the detail-profile loss; `PLANET_PHOTO_BARK=1` returns to the photographs); every other bark and all rocks are photographs (`PLANET_PROCEDURAL_ROCKS=1` bakes the rocks). Always compare with `bark_view.tscn` (same lichen on both trees).
