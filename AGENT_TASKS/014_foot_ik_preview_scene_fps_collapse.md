# 014: `foot_ik_preview.tscn` FPS collapse near ramps/stairs

## Status and scope

**Fixed and verified.** `foot_ik_ground_sampler.gd`'s `_request_overheight_split_safe_zone`
now caches a failure cooldown (`split_safe_retry_after_frame`, `SPLIT_SAFE_RETRY_COOLDOWN_FRAMES
:= 30`) instead of re-running the ~6500-raycast split-safe-root search on every single physics
tick when the search keeps failing. Verified at the exact repro that previously stayed crashed
for the full 17+ second measured window (Ramp 45 platform, camera turned ~150 degrees off
spawn): fps now dips only to 10 for the first second (the separate, minor GPU-governor cost,
see below) then holds a solid 60 for the rest of a 20-second run. Full `check_foot_ik_fast.sh`
suite passes with no regressions.

**Correction: the GPU-governor finding below is real but was wrongly declared "the" root
cause - it explains a real, separate, ~2-second one-time startup cost, but not the actual bug.**
The real, dominant, *sustained* (does not self-recover, ever, while conditions hold) cause is
`_request_overheight_split_safe_zone`'s uncapped retry - see "Real root cause: uncapped
split-safe-root retry, no cooldown on failure" below. That section supersedes the GPU-governor
one as the primary finding; the GPU-governor section is kept because it's still real and
worth knowing about as a separate, secondary contributor to the first ~2 seconds specifically.
This was found by testing the user's own live discovery ("disable IK -> fps recovers", "jump ->
fps recovers") in a controlled, automated A/B, which the earlier GPU-only investigation had not
actually attempted - always re-verify a "solved" conclusion against new counter-evidence rather
than defending it.

User manually played `foot_ik_preview.tscn` (the scene "we always work with") and observed
severe FPS drops - 60fps down to single digits - specifically near the ramp/stair platform
cluster, reproducible on repeat visits. One
real contributing bug was found and fixed along the way (concave CSG collision on authored
ramp/stair boxes, see "Fixed: CSG concave-collision cost" below), worth keeping but not the
dominant cause. This is scoped as its own task because it is a performance investigation,
unrelated in kind to every other numbered Foot IK task (all correctness/pose bugs).

## Diagnostics added (kept, gated, safe to leave in)

- `[FOOT_IK_PERF]` - per-leg-solver `solve()` timing, in
  `actors/player/foot_ik/foot_ik_leg_solver.gd`. Wraps the real `solve()` body (renamed to
  `_solve_impl`) with a `Time.get_ticks_usec()` timer, printing once per second per solver
  instance: call count, average/total time.
- `[FOOT_IK_ENGINE_PERF]` and `[FOOT_IK_NODE_SPAWN]` -
  `tests/manual/foot_ik/foot_ik_perf_probe.gd`, a standalone `Node` attached as a child of
  `foot_ik_preview.tscn`. Prints `Engine.get_frames_per_second()`,
  `Performance.get_monitor()` counters (`TIME_PROCESS`, `TIME_PHYSICS_PROCESS`, `OBJECT_COUNT`,
  `OBJECT_NODE_COUNT`, `MEMORY_STATIC`, `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`,
  `RENDER_TOTAL_PRIMITIVES_IN_FRAME`, `RENDER_VIDEO_MEM_USED`) once per second, plus a node-tree
  diff (walks the whole tree from `get_tree().root`, diffs node paths against the previous
  window's snapshot, groups newly-added nodes by `parent path | class name`).
- Both gate on `FOOT_IK_PERF_LOG` - **on by default** (`!= "0"`) while this investigation is
  active, so no env var setup is needed; pass `FOOT_IK_PERF_LOG=0` to silence them. Flip the
  default back to opt-in (`== "1"`) once this task is closed, so normal runs stay quiet.

## Ruled out

- **Foot IK's own `solve()` cost.** 2-9ms total per second, summed across every active
  leg-solver instance (this scene runs ~25 simultaneous idle/walking characters). Negligible
  next to a ~16.6ms (60fps) or ~166ms (6fps) frame budget.
- **Node/object count growth.** Bounded. The one real spike found -
  `ui/hud.gd`'s debug Animation panel building ~105 `Button`/`Label` nodes in one synchronous
  frame - is old (2026-07-16, unrelated to any Foot IK work) and only cost ~3fps (60 -> 57), not
  the crash. Not reliably reproducible on demand (fired once in some runs, twice in one "debug
  menu always open" run, and not at all in others); not pursued further since its cost is too
  small to be the culprit.
- **Static memory growth.** Climbs steadily during initial load (asset/shader caching) then
  plateaus (~340-390MB) after roughly the first 15-20 seconds in every run tested so far.
- **View-dependence / "more characters entering frame."** Directly tested: stood completely
  still (no camera or player movement) for ~16 seconds. `primitives` still climbed at the same
  rate as when moving, but fps stayed a rock-solid 60 throughout. This proves rendered-primitive
  growth is not itself sufficient to cause the crash, and rules out "camera looking at a denser
  part of the scene" as the explanation by itself.
- **CSG concave-collision query cost (partially - see below).** Real, fixed, but not sufficient
  on its own; the crash still reproduces after this fix.

## Fixed: CSG concave-collision cost (real bug, kept, but not the main answer)

Every authored tread/riser/platform box on ramps and stairs
(`tests/manual/foot_ik/foot_ik_preview.gd`'s `_build_flat`/`_build_ramp`/`_build_stairs`, and
`foot_ik_stair_surfaces.gd`'s `build_top_landing`) was a `CSGBox3D` with `use_collision = true`.
`CSGShape3D` always bakes its own collision as a concave `ConcavePolygonShape3D` trimesh, even
for a plain box - markedly more expensive to raycast/query than a convex primitive, and Foot
IK's ground sampler raycasts every nearby box every physics frame for every character's foot.
`physics_ms` spiked 3-5x baseline (up to 53ms vs ~10ms normal) exactly during crash windows
while `process_ms` (script/logic cost) stayed flat - the extra cost was inside the physics
engine's own collision query, invisible to any Foot IK-side timer.

**Fix applied**: `FootIKStairSurfaces.finalize_authored_box(parent, box)` adds the box under
`parent`, gives it a sibling `StaticBody3D` + `CollisionShape3D(BoxShape3D)` matching its
transform/size, and sets `box.use_collision = false`. Wired into all four authored-box call
sites. Verified behavior-neutral against the full exhaustive suite (identical failure set
stashed vs. applied). Regression test added:
`tests/manual/foot_ik/foot_ik_authored_collider_shape_check.gd`/`.tscn`, wired into
`check_foot_ik.sh` and `check_foot_ik_fast.sh` - confirmed it actually catches the regression
(fails to even parse when `foot_ik_stair_surfaces.gd` is reverted alone).

**Why this isn't the answer**: re-tested after the fix with the same repro (walk to ramp, stay
a while). The crash still happens, at similar or only slightly reduced magnitude
(`physics_ms` peak ~45ms post-fix vs. ~53ms pre-fix - a modest reduction, not a fix). This fix
is still worth keeping (it's strictly cheaper and now has regression coverage), but the
dominant cause of the crash is something else.

## New: a fast, reliable 2-5s repro, and a precise pipeline-compile measurement

Found a much tighter repro than "walk around and wait": stand still on the **Ramp 45°**
platform, facing roughly 120 degrees off the default spawn heading (`_apply_yaw`'d there, the
same head-then-body turn a real mouse-look produces, camera unchanged - the normal
`ThirdPersonArm/DebugCam`). The crash reproduces in 2-5 seconds from a fresh scene load, every
time - far faster and more reliable than the original "walk to the ramp/stair cluster and wait"
repro this task was opened with.

Also added `Performance.PIPELINE_COMPILATIONS_CANVAS/MESH/SURFACE/DRAW/SPECIALIZATION` to
`foot_ik_perf_probe.gd` (these are cumulative-since-engine-start counters, so the probe now
tracks the previous window's totals and logs the per-window delta) - Godot 4.3's own
hitch-reduction counters for exactly the "lazy shader/pipeline compilation" hypothesis this
task's "Open" section already listed as the strongest untested lead.

**Result, from the fast repro's first 5 seconds**: the very first window (`frame=60`, the
first second) shows `pipeline_compiles_mesh=1279` alongside `fps=4.0` and `process_ms=45.94`
(the only window where `process_ms` is elevated too - `_ready()`/first-draw setup cost
overlapping). Every window after that (`frame=120` through `frame=300`, the next four seconds)
shows **all five pipeline-compile counters at zero**, while `physics_ms` sits at 21-27ms and
`process_ms` is back to a normal ~1.9ms - yet `fps` stays crashed at 5-7 the entire time.

**This confirms real pipeline-compile activity for the first time this session (previously
only theorized), but disproves it as the sustained cause.** A one-time compile burst
right at the start plausibly explains the very first stuttered frame, but it cannot explain
why the crash persists for 4+ more seconds after compile activity has already dropped to zero
and every other `Performance` counter has returned to baseline. Something the compile burst
triggers - GPU driver stall recovery, thermal/clock-frequency throttling, or a render-thread
command backlog invisible to any `Performance` monitor - most plausibly outlasts the
compilation work itself. Still needs a real GPU frame capture to see directly, but the fast
repro means that capture is now a 5-second exercise instead of an open-ended wait.

## Four more hypotheses tested and disproven; angle-dependence confirmed, unexplained

Used the fast Ramp 45 repro to bisect four more candidates, each isolated with a
temporary marker-file toggle in `foot_ik_preview.gd` (added, tested, then fully reverted -
`git checkout --` after every result was captured, nothing kept in the shipped file):

- **`AnimationComparisonDummies` hidden** (a second full set of ~16-18 `Player.tscn`
  instances this scene spawns for A/B animation comparison, previously never examined as a
  perf contributor): `draw_calls` dropped (632->531) confirming the hide worked, but
  `frame=60`/`frame=120` fps (5.0/9.0) were statistically the same as baseline (5.0/8.0).
  **Disproven.**
- **`FootIkDebugOverlay` hidden** (all the world-space gizmos/labels/rays this preview scene
  draws): `primitives` went flat at ~389-390k across the crash window (confirming the hide
  worked - normally primitives climb every window), but the fps crash signature was
  identical (6.0/8.0/43/60). **Disproven.**
- **`DirectionalLight3D.shadow_enabled = false`**: `draw_calls` dropped sharply (591-650 ->
  449, confirming shadows were really off), fps crash signature unchanged (5.0/8.0/39/60).
  **Disproven.**
- **Camera clipping into the ramp's own collision via `SpringArm3D` collapse** (the
  third-person arm shortens its own length when a raycast hits geometry - plausible if
  standing on/near the ramp surface pushes the camera into the mesh): measured
  `third_person_arm.spring_length` every 60 physics frames across a full angle sweep -
  **always exactly 4.0, the unmodified default, at every angle and every frame measured**.
  The camera never gets close to colliding with anything here. **Disproven.**

**New, confirmed, unexplained signal - camera facing angle changes crash severity, inversely
correlated with visible geometry.** Swept `_apply_yaw` turn angle at the identical Ramp 45
position (0/30/60/90/150/180 degrees from spawn heading):

| angle | frame 60 fps | frame 120 | frame 180 | frame 240 | draw_calls @60 | primitives @60 |
|---|---|---|---|---|---|---|
| 0   | 23 | 60 | 60 | 60 | 494 | 870953 |
| 30  | 24 | 60 | 60 | 60 | 441 | 609483 |
| 60  | 5  | 56 | 60 | 60 | 346 | 306466 |
| 90  | 4  | 6  | 6  | 6  | 387 | 494488 |
| 150 | 4  | 5  | 6  | 7  | 570 | 481415 |
| 180 | 3  | 6  | 7  | 6  | 704 | 706687 |

0/30 degrees recover almost immediately (mild, matches the plain default-spawn baseline
which only dips to fps=27 for one window); 90/150/180 stay crashed for the entire
measured window. **This does not track `draw_calls` or `primitives` at all** - angle 90 has
the *fewest* draw calls of the whole sweep (387) yet is among the worst, while angle 180 has
far more draw calls (704, close to the mild angle-0 case's 494) and is still bad. Whatever is
expensive at the bad angles is not "more visible stuff," which rules out simple
frustum-culling-driven geometry cost as the explanation.

**This narrows the remaining candidates to something render-thread/GPU-internal that CPU-side
`Performance` monitors and simple node/light/shadow toggles cannot see or control from
GDScript** - most plausibly Forward+'s internal clustering/light-binning cost, shadow-atlas
cascade fitting against the *scene's full shadow-caster bounds* (not just what's on-screen,
so independent of visible draw calls - though this was tested indirectly by disabling shadows
entirely above, which didn't help, so if cascade fitting is involved it isn't the whole
story), or genuinely GPU-driver-side state (pipeline barrier stalls, descriptor/root-signature
rebinding cost) tied to which specific camera transform gets submitted. Five real,
independently-verified hypotheses are now exhausted from the GDScript/`Performance`-monitor
side. The next step is unambiguously a GPU frame capture (Xcode Metal capture or RenderDoc)
at one of the reliably-bad angles (90, 150, or 180 degrees, Ramp 45 platform) - there is
nothing further to learn by adding more prints.

## Real root cause: uncapped split-safe-root retry, no cooldown on failure

User's own live A/B testing (while standing in the crash, not from a log) found the actual
mechanism directly: **jumping recovers fps**, and **disabling Foot IK recovers fps**. Both
were reproduced under a controlled, automated A/B at the same fast Ramp 45/turned-camera repro
this task already established, before investigating further:

- IK enabled, same position/camera: fps stayed at 3-7 for the **entire measured 17-second
  window** (frame 60 through frame 1020) - never recovering on its own. This directly
  contradicts the earlier GPU-governor conclusion, which predicted recovery within ~2 seconds
  regardless of game code. The earlier tests that "confirmed" GPU-governor-only recovery had
  simply not been run long enough.
- `user://foot_ik_disabled_marker` (disables only the *interactive player's* own Foot IK,
  the other ~24 idle characters' IK stays untouched in both conditions) - fps recovered to 60
  within ~2 seconds, every time.

Instrumented the player's own `FootIKGroundSampler` with a per-call-site tally (temporary,
fully reverted after capturing evidence) and confirmed:

- `modification_call_count` (how many times the engine invokes
  `_process_modification_with_delta` per physics tick): exactly 60 per 60-physics-frame
  window - completely normal, once per tick as expected. This isn't a re-entrancy bug.
- `raycast_debug_count`: **~360,000-390,000 raycasts in that same 60-tick window** - roughly
  6500 raycasts *per single tick*, versus ~6/tick once the crash clears. All of it attributed
  to `_find_split_safe_root` (called ~330-360 times/window, i.e. ~6/tick - `_request_..._zone`
  calls `_find_nearest_split_safe_root`, which calls `_find_split_safe_root` twice, twice per
  leg) and `straighten_compressed_upper_target` (~120/window, normal - 1/leg/tick, not
  implicated).

Read `_find_split_safe_root` (`foot_ik_ground_sampler.gd`): it does a ring search out from a
root point - `for ring in range(1, SPLIT_SAFE_SEARCH_RINGS + 1): samples := ring * 8; for
sample_index in samples: ...` (`SPLIT_SAFE_SEARCH_RINGS := 16`). If it never finds a point
satisfying all three `_has_surface_at_height` checks, it exhausts **every** ring:
`sum(ring*8 for ring in 1..16) = 1088` samples, up to 3 raycasts each (each
`_has_surface_at_height` call is one `raycast_ground`) = up to **3264 raycasts for one
call**, and it's called twice per real invocation (upper_y and lower_y via
`_find_nearest_split_safe_root`) = up to **6528** - matches the measured ~6500-6535/tick
almost exactly. This is the actual, complete answer.

**The real bug** is in the caller, `_request_overheight_split_safe_zone`: 

```gdscript
if not split_safe_root_target.is_finite() or root.distance_to(split_safe_root_target) <= 0.03:
    var safe := _find_nearest_split_safe_root(...)
    split_safe_root_target = safe["root"]
    ...
```

When the search finds nothing, `safe["root"]` stays `Vector3(INF, INF, INF)` -
`split_safe_root_target` stays non-finite - the *very next physics tick's* `if not
split_safe_root_target.is_finite()` is true again, and the full expensive search re-runs.
**There is no cooldown, backoff, or "this position is hopeless, stop asking" cache** - if the
search keeps failing (as it does at this specific ramp/turned-camera repro spot, and evidently
at whatever real spot the user stood near in the real level), it re-runs this ~6500-raycast
search on literally every single physics tick, forever, for as long as the character stays put.

This single mechanism explains every piece of evidence gathered, cleanly, with no loose ends:

- **Only triggers during idle animation** (`_request_overheight_split_safe_zone`'s own early
  gate: `not animation_name.contains("idle") and not landing_recovery` bails out otherwise) -
  matches both the user's real manual playtest (almost certainly standing still) and the
  automated repro (which stands still by construction).
- **Jump fixes it** - jumping leaves the idle animation immediately, which is exactly this
  function's own bail-out condition. Nothing mysterious about airborne state specifically; it's
  this one gate.
- **Disabling Foot IK fixes it** - the whole call chain is skipped.
- **Sustained indefinitely, not a one-time startup cost** - matches the just-corrected 17-second
  test far better than the GPU-governor theory ever did.
- **Not fixed by hiding `AnimationComparisonDummies`/`FootIkDebugOverlay`/shadows** - none of
  those change the ground geometry the split-safe search is querying against.
- **Angle-dependent severity from the earlier sweep** is now also explained differently than
  originally guessed: different camera *turn* angles don't change the *character's* position at
  all (only camera yaw was varied, player position was fixed) in that sweep - so the real
  variable across those angle tests was probably incidental frame-timing/scheduling, not a
  genuine render-angle effect. That sweep's "inverse correlation with draw calls" conclusion
  should be treated as a red herring now that the true mechanism is known to be CPU/physics-side
  (physics_ms), not GPU-side.

**Fixed** - this is real production Foot IK code (the platform-edge-safety system from task
008), not test/debug scaffolding, and this codebase has repeatedly punished seemingly-safe
changes with regressions (see 008/010/012's own histories), so this was proposed and confirmed
with the user before implementing. Applied fix, in `foot_ik_ground_sampler.gd`:

- A failure cooldown alongside `split_safe_root_target`: `split_safe_retry_after_frame: int`,
  reset to 0 in `reset()` and `reject_split_safe_root()` (an explicit reject should retry
  immediately), set to `Engine.get_physics_frames() + SPLIT_SAFE_RETRY_COOLDOWN_FRAMES` (30
  frames, 0.5s at 60fps) in `_request_overheight_split_safe_zone` whenever
  `_find_nearest_split_safe_root` returns non-finite. Same shape as other cooldown/backoff state
  already used elsewhere in this file (e.g. `_landing_grace_time`).
- While on cooldown and no valid target has ever been found, behavior is unchanged from
  today's existing `if not split_safe_root_target.is_finite(): return false` path - no new
  visual fallback needed, since that path already handles "no split-safe target available."
- Verified against `check_foot_ik_fast.sh`'s full suite (all checks pass, including
  `FOOT_IK_LEDGE_SAFETY_CHECK`/`FOOT_IK_EDGE_LANDING_SWEEP_CHECK`, which specifically exercise
  this platform-edge-safety path) and against the synthetic Ramp 45/150-degree-turn repro
  (previously crashed for the full 17+ second measured window, now recovers to 60fps by ~2
  seconds and holds). Not yet verified at the real in-game spot the user originally saw this -
  worth a live manual check there too when convenient.

## Root cause found: Apple Silicon GPU frequency governor startup ramp

Captured a real GPU trace via Xcode's Instruments CLI front-end (`xctrace`, no GUI needed -
it can attach to a running process by PID from the command line):

```
xcrun xctrace record --template "Metal System Trace" --attach <godot_pid> \
    --time-limit 5s --output gputrace.trace
xcrun xctrace export --input gputrace.trace --xpath \
    '/trace-toc/run[@number="1"]/data/table[@schema="gpu-performance-state-intervals"]'
```

Recorded during the fast Ramp 45 / 150-degree-turn repro. Two tables settle this:

- **`device-thermal-state-intervals`**: `Nominal` for the entire capture. Not thermal
  throttling.
- **`gpu-performance-state-intervals`**: the GPU sits in **`Minimum`** performance state,
  narrated as `"Minimum GPU Performance state due to active device conditions"`, continuously
  from **473ms to 2055ms** into the run - then jumps straight to **`Maximum`** at exactly
  **2055ms** and stays there for the rest of the capture.

That 2055ms ramp-up timestamp lines up almost exactly with the fps recovery point in every
`FOOT_IK_ENGINE_PERF` log captured this session (crashed through the 1-2s marks, recovering by
the ~3s mark). **This is Apple Silicon's own GPU frequency/power governor**: a fresh process
starts the GPU clocked at its minimum performance state and needs roughly 1.5-2 seconds of
sustained load to ramp up to maximum - a macOS/Apple-Silicon power-management characteristic,
not a bug in this project's rendering code.

This single mechanism now explains every previously-confirmed, previously-unexplained
observation in this task:

- **Self-recovers on its own** after a few seconds, every time - the governor always
  eventually ramps up. Matches every log captured, including the very first ones from before
  this task even isolated a fast repro.
- **Not fixed by disabling `AnimationComparisonDummies`, `FootIkDebugOverlay`, or shadows** -
  none of those change how fast the OS governor decides to ramp GPU clock speed.
- **Not fixed by disabling shadows specifically**, despite that being the strongest
  a-priori suspect (shadow cascade cost) - irrelevant, since the constraint is clock speed,
  not which pass is running.
- **The pipeline-compile burst (`pipeline_compiles_mesh=1279`) is a coincidental
  neighbor, not the cause** - it also happens right at launch, but is a fixed, one-time CPU
  submission-side event, unrelated to the several-additional-seconds the GPU then spends
  clocked down while draining that (and all other) submitted work slowly.
- **Camera-angle dependence, inversely correlated with draw calls/primitives** - different
  views submit different per-frame GPU utilization *patterns* during the governor's ramp-up
  window. A view whose workload sits at a lower, spikier utilization can plausibly delay the
  governor's decision to ramp up longer than a view with more (but steadier) work, even though
  the total amount of work is smaller - consistent with the angles that stayed crashed longest
  (90/150/180 degrees) also having fewer draw calls than the angles that recovered fastest.

**This is not a bug to fix in Foot IK, the preview scene, or this project's rendering code at
all.** It is an inherent one-time cost every fresh Metal process pays on this hardware. The
actionable mitigation is the standard one for this exact situation: give the GPU 1-2 seconds
of real rendering work to chew on *before* the player gains control/camera movement - i.e. a
brief warm-up/loading pass (even just holding the initial loading screen a beat longer while
the scene renders a few hidden frames) so the governor's ramp-up happens during a controlled
loading moment instead of during live gameplay. This only matters for real gameplay scenes
that spawn player-controlled cameras immediately on load; `foot_ik_preview.tscn` itself doing
this is expected and low-stakes (it's a debug/test scene), but the same mechanism would explain
a similar hitch in the real game right after a level loads, if one is ever reported - worth
remembering as a reference case ([015](015_foot_ik_architecture_direction.md) is the right home
for a general "warm up the GPU during loading" note, since it's not Foot IK-specific).

## Open: the real cause is still unknown

The most consistent, unexplained signal across every real (non-headless) run: `primitives`
(`RENDER_TOTAL_PRIMITIVES_IN_FRAME`, i.e. triangles actually submitted to the GPU that frame)
**never plateaus** over a long-enough session - in the longest run captured so far (35 seconds,
post-collider-fix), it climbed continuously and roughly linearly from ~982K to ~8.2M (over 8x),
while `nodes`/`objects` stayed essentially flat (~4150-4270) the entire time. Shorter runs
earlier in the investigation showed it eventually leveling off, but the longer run shows no
ceiling at all. This does not correlate cleanly with the fps crashes either - there is at least
one window (frame 1980-2100 in the fix-applied log) where fps recovers to 60 even as
`primitives` keeps climbing.

Every crash window measured so far shows the same signature: `process_ms` stays low
(1.6-1.9ms, i.e. script/logic cost is cheap) and `physics_ms` is elevated but nowhere near
enough (20-45ms) to account for the actual frame time implied by a 6-7fps reading (~140-166ms).
That gap - well over 100ms per frame unaccounted for by any `Performance` monitor read so far -
points at something GPU-bound or render-thread-bound: most likely candidates, none confirmed:

- Shader/render-pipeline compilation happening lazily the first time a specific
  material/mesh/pass combination is drawn (a known Forward+ hitch source), though a genuine
  compile stutter is normally a handful of frames, not many consecutive seconds - doesn't fully
  fit on its own.
- Growing GPU-side work tied to whatever is driving the unexplained `primitives` climb (shadow
  cascade re-splitting, some form of increasing tessellation/subdivision, or a duplicate-draw
  bug) - the strongest lead, but not yet traced to a mechanism.
- Something entirely outside anything a `Performance` monitor captures (driver-level state,
  thermal throttling combined with cumulative sustained load, or a vsync/present wait that
  `TIME_PROCESS` doesn't include).

CPU-side `Performance` monitors and node-tree diffing have been exhausted as a diagnostic
avenue - every lead they could produce has been chased. The next step that could actually
resolve this needs a real GPU frame capture (Xcode's Metal frame capture, or RenderDoc) taken
during a crash window, to see what the GPU is actually spending time on. That is beyond what
log-based diagnosis from this side can drive; it needs to be done interactively by whoever has
the machine in front of them.

## Verification plan for whichever direction is chosen

- Re-run the same repro (open `foot_ik_preview.tscn`, walk to the ramp cluster, wait through at
  least one full crash-and-recover cycle) with `FOOT_IK_ENGINE_PERF` logging (on by default) and
  confirm `fps` stays near 60 and `primitives` plateaus or grows much more slowly than before.
- Whatever fix is found, re-run the full exhaustive suite
  (`bash scripts/check_foot_ik.sh`, or the continue-past-failures variant for a full picture)
  to confirm the existing pre-existing baseline failure set
  (`FOOT_IK_KNEE_FLEX_CHECK`, `FOOT_IK_LOCOMOTION_CHECK`, `FOOT_IK_IDLE_PLANT_STABILITY_CHECK`,
  `FOOT_IK_RAMP_LOCOMOTION_CHECK`, `FOOT_IK_WALK_IDLE_STANCE_CHECK`) is unchanged - this is a
  performance investigation and should not touch Foot IK correctness.
- Once resolved, flip `FOOT_IK_PERF_LOG`'s default in both
  `actors/player/foot_ik/foot_ik_leg_solver.gd` and `tests/manual/foot_ik/foot_ik_perf_probe.gd`
  back to opt-in (`== "1"`) so normal runs stay quiet by default.

## References

- [012](012_foot_ik_ramp_cross_slope_penetration.md) - "Preview-scene FPS drop near
  ramps/stairs" section has the same writeup in condensed form, plus the ramp/stair-specific
  Foot IK correctness context this task doesn't touch.
- `AGENTS.md`'s "Godot and animation gotchas" section - the `CSGShape3D.use_collision` concave
  trimesh gotcha, generalized for reuse outside this scene.
- `tests/manual/foot_ik/foot_ik_perf_probe.gd`, `actors/player/foot_ik/foot_ik_leg_solver.gd`
  (`solve()`/`_solve_impl` split) - the diagnostics.
- `tests/manual/foot_ik/foot_ik_authored_collider_shape_check.gd`/`.tscn` - regression coverage
  for the CSG-collision fix (not for the still-open FPS crash itself).
