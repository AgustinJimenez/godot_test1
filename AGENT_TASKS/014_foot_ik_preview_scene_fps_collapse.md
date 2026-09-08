# 014: `foot_ik_preview.tscn` FPS collapse near ramps/stairs

## Status and scope

Open, unsolved. User manually played `foot_ik_preview.tscn` (the scene "we always work with")
and observed severe FPS drops - 60fps down to single digits - specifically near the ramp/stair
platform cluster, reproducible on repeat visits, fully recovering when standing elsewhere. One
real contributing bug was found and fixed along the way (concave CSG collision on authored
ramp/stair boxes, see "Fixed: CSG concave-collision cost" below) but it only had a marginal
effect - **the crash still happens after that fix**. The true dominant cause is still unknown.
This is scoped as its own task because it is a performance investigation, unrelated in kind to
every other numbered Foot IK task (all correctness/pose bugs), and because the CSG-collision
fix, while worth keeping, turned out not to be the answer.

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
