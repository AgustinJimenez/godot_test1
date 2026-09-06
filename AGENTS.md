# AGENTS.md

Repository guidance for coding agents. Keep this file short and durable: do not append session
history, live coordinates, rejected experiments, or long feature specifications here. Put active
evidence in the numbered task named by `CURRENT_TASK.md`; Git preserves old revisions.

## Project and task workflow

This is a first-person survival-horror learning sandbox built with Godot 4.6 (Forward+, Jolt) and
statically typed GDScript. Explain Godot ideas briefly in plain language when building systems.

Active work lives in one independent `AGENT_TASKS/NNN_name.md` file selected by `CURRENT_TASK.md`.
Completed or parked work remains in its own numbered file. Update `AGENTS.md` only for rules likely
to prevent rediscovery across several future tasks. There is no centralized planning document;
numbered tasks and the code/tests describe the current state.
Keep the active task a concise current handoff: replace superseded status instead of appending
session history, and move long investigation narratives to `AGENT_TASKS/archive/`.

Before editing, inspect the working tree. Existing changes belong to the user; preserve unrelated
work. Do not commit gameplay, animation, or visual changes until the user has tested them live and
explicitly confirmed the result.

Authenticate GitHub pushes for this repository as `AgustinJimenez`. Keep that selection
repository-local; do not change the globally active GitHub CLI account to make a push.

## Commands and validation

The `godot` command is the installed Godot 4.6 mono build.

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

There are no unit tests. Persistent acceptance scenes live under `tests/manual/<domain>/`.
Temporary capture scenes may use `tests/manual/_<name>_demo.tscn` but must be removed before commit.
After launching a verification scene, stop the game before handing control back to the user.

Use `godot --doctool` before web search for exact Godot APIs. This binary's XML has reliable class,
method, property, and inheritance data but empty prose descriptions; use primary web sources only
when explanatory prose is needed.

Use `rtk` for routine noisy Git/search output, but use raw output for instruction files, exact
numeric traces, failing checks, and final pre-commit diffs. Rerun any filtered failure raw.

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

Before running any Foot IK harness after the user asks to inspect the latest live log, preserve
`user://foot_ik_controlled.jsonl` under a timestamped `/tmp` name. Harnesses share and overwrite this
rolling trace. Marker files under `user://` can also alter later headless runs; remove temporary Foot
IK walk/spin/stair markers before trusting regressions.

Treat compact anomaly output as a starting point, not proof of correctness. Inspect state changes and
the raw/smoothed/final values behind the visible symptom. Add state-invariant regressions when a
summary can look clean despite inconsistent ownership—for example, a released idle foot must not
retain the side-key target latch.

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

Procedural bone corrections belong in `SkeletonModifier3D`, not an ordinary node's `_process()`.
Snapshot all base animation poses before changing an ancestor chain. When a paused tuning UI changes
modifier data, call `Skeleton3D.advance(0.0)` to refresh the rendered result.

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

## Foot IK and movement

The active consolidation is `AGENT_TASKS/010_foot_ik_target_coordinator_consolidation.md`
(migrating every target owner through one validated boundary); `009` holds the ownership-matrix
review behind that decision, `008` the still-open platform-edge bugs, `011`/`012` newer findings,
`013` the knee-bend-plane search instability (`_select_feasible_bend`, shared by every leg solve
on every surface—three of its own fix attempts and two other pipeline discontinuities before one
finally stuck), and `007` the earlier stair/locomotion architecture. Put exact live frames,
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
`check_foot_ik_locomotion.sh`) - always run those three directly too, not just via
`check_foot_ik.sh`, or you will believe coverage ran when it did not (see
[012](AGENT_TASKS/012_foot_ik_ramp_cross_slope_penetration.md)'s "Wired into a runnable
script" section). There is no committed way to run the whole suite past a known failure and see
every result - only an ad-hoc local workaround (strip `set -e`, replace each `exit 1` with a
no-op) has been used for this so far.
