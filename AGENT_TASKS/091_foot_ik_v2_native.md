# 091 - Foot IK v2 in native C++ (GDExtension)

Status (2026-10-25): PLAN ONLY. User: "I know the performance is gonna be better if we turn it into native cpp, can we do that?" (asked after confirming
v2 is all GDScript: `actors/player/foot_ik_v2/`, 16 `.gd` files, 1,649 lines, of which `foot_ik_v2_modifier.gd` is 1,000). Related: 035 (v2), 036 (tread-change step,
open), 037 (plant-once design, nothing built), `native/planet_crust/README.md` (the existing GDExtension: same build, same accelerator pattern).

## Verdict

Yes, it can be done and the infrastructure exists: `native/planet_crust` is a godot-cpp GDExtension with `scripts/build_native.sh` (MinGW on this machine,
godot-cpp at `E:/Godot/cpp/godot-cpp` and `godot-cpp-double`, API dump in `E:/Godot/cpp/dump`), debug and double-precision libraries, a `--native-check` that compares
native and GDScript, and `PLANET_NO_NATIVE=1` to fall back. The foot IK is a `SkeletonModifier3D`, which godot-cpp can subclass (`_process_modification`), and
`PhysicsDirectSpaceState3D` ray queries are callable from C++.

What a port will and will not buy (honest): no measurement exists yet of where v2's frame time goes (the lab has `--foot-ik-v2-perf`, per-part microseconds,
`foot_ik_v2_debug.gd`). GDScript cost in a per-frame modifier is mostly the interpreter on vector maths and Dictionary results; the physics rays cost the
same in C++. Expect a clear gain on the maths and on allocation (the solver returns a Dictionary per call), little on the ray queries. The user chose the port
without the measurement; it is still the cheapest first step to record the baseline so the gain can be stated.

## Risk to manage

v2's DECISION logic is still moving: 036 (tread-change step) is open and 037 (plant once, delete the stacked guards, inertialization) is a redesign that would
delete code. Porting 1,000 lines of rules that are about to be reshaped doubles the work. So: port in layers, from the stable pure maths outward, keep the GDScript as
the reference (like the crust), and do the decision layer last (or after 037 stage 1-2).

## Plan (each stage ends with the suite green and a timing)

0. Baseline (30 min): run `scripts/check_foot_ik_v2.sh` and `scripts/fuzz_foot_ik_v2.sh 12 7`, record which are red today; run the lab with `--foot-ik-v2-perf`
   and record per-part microseconds and frame time. This is the number the port must beat and the check it must not break.
1. New extension `native/foot_ik/` (copy the planet_crust layout: SConstruct, `.gdextension`, `src/`, entry symbol `foot_ik_init`), built by
   `scripts/build_native.sh` (extend it to loop over both extensions). Class `FootIKV2NativeMath` (RefCounted, static-style methods): the solver
   (`solve` -> a small result object or PackedVector3Array instead of a Dictionary), the joint limiter, knee hint, reach blend, body smoother. Pure maths, ~200
   lines of GDScript. GDScript callers switch to it when the class exists (`ClassDB.class_exists`), else the old code. Test: `foot_ik_v2_solver_check.gd` runs against
   both and compares to 1e-5; the suite stays green.
2. Ground side: ground filter, sole (skinned sole sampling: `foot_ik_v2_sole.gd`, 169 lines), ledge/safe-zone, stepper, stretch hold, lock. Still called from the
   GDScript modifier. Ray casts stay through `PhysicsDirectSpaceState3D` (one reused `PhysicsRayQueryParameters3D`, as the notes already say).
3. The modifier itself: `FootIKV2NativeModifier : SkeletonModifier3D` with the same `@export` tunables (as `GDVIRTUAL`/properties), `_process_modification`,
   the debug trace (jsonl) and the perf counters. Switch `foot_ik_v2_install.gd` to it behind a flag (`FOOT_IK_V2_NATIVE=1`, default on once the suite is green),
   GDScript modifier kept as the reference and for `PLANET_NO_NATIVE=1`.
4. Compare: a `--foot-ik-v2-native-check` lab flag runs the same walk/ramp/stairs sequences with both implementations and reports the largest ankle/knee
   difference per frame (target < 1 mm) and the per-frame time of each.
5. Release/double builds (`planet_crust.gdextension` has the matrix); document in `AGENTS.md`; hooks build it after a pull.

Order of value: stage 1 (solver and friends) is the cheap part and the likely bulk of the saving if the time is in vector maths; stage 3 is the expensive one (1,000
lines of rules) and should wait for 037.

## Decisions / open questions

- Keep the GDScript as the reference implementation (a bug fixed in one must be fixed in the other until the GDScript is deleted: say when).
- Where does the time actually go? Unknown until stage 0.
- Double-precision engine: the project uses a double-precision editor build for some runs: both libraries must be built (the crust already does this).

## Progress 2026-10-25 (user: "yes" to the baseline and the maths layer)

Decision: the native class lives INSIDE the existing `native/planet_crust` extension (one library, one build, one `.gdextension`, `scripts/build_native.sh` unchanged), as
`FootIKV2Native` (`src/foot_ik_native.{h,cpp}`, registered in `register_types.cpp`). `PLANET_NO_NATIVE=1` turns it off (same switch as the crust).

Stage 0, baseline (old GDScript code, headless, this machine):
- `scripts/check_foot_ik_v2.sh` (needs a `godot` on PATH: `E:/Temp/bin/godot` wrapper to the 4.7.2 console exe; 3.5 minutes): RED today: project checks (no `gdlint` here),
  floor-walk vibration (ik_jerk max 0.209 against a 0.20 limit: marginal), ramp strafe (known old), turn in place on the stairs dz=0 (tip_clip_max 0.049 against 0.020: the 036 bug). Everything
  else PASS (stairs walks, same-as-animation, foot turn, pelvis drop, idle leg pop).
- `scripts/fuzz_foot_ik_v2.sh 12 7`: 8 of 12 poses fail (036: the notes had 12/12 with older settings).
- `--foot-ik-v2-perf` (1,800 frames, lab, headless): total 1.01 ms/frame; `sink` 0.55 ms (of which `level_points` 0.29 ms, the 16 sole rays 0.22 ms); the other ~0.45 ms is not
  instrumented. So the time was NOT mostly in the rays: the per-vertex GDScript loop was the biggest single part.

Stage 1 (done): `FootIKV2Native` has `set_sole`, `points`, `level_points`, `lowest_world_y` (the sole replay and the lowest-point queries) and static `solve` (the two-bone leg).
`foot_ik_v2_sole.gd` builds the native object after `_prune` and delegates (the cached arrays are copied once); `FootIKV2Solver.solve` calls the native one and rebuilds the
same Dictionary (the GDScript kept as `solve_script`, the reference); `_lowest_sole_offset` in the modifier now calls `Sole.lowest_world_y` (modifier 1,000 -> 998 lines).
- Result: total 1.01 -> 0.77 ms/frame (-24 %), `sink` 0.55 -> 0.31 ms. The full suite gives the SAME PASS/FAIL set as the baseline and the same measured numbers
  (floor-walk jerk 0.209 etc.), so behaviour is unchanged.
- New check `tests/manual/foot_ik_v2/foot_ik_v2_native_check.gd` (in the suite; SKIP when the library is not built): 4,000 random legs and 200 random poses of a random
  sole; worst difference solve 6e-7 m, points / level_points / lowest 0.
- Left in stage 1: the knee hint, joint limiter, reach blend, body smoother (small); the rays themselves (physics: no gain expected); the uninstrumented 0.45 ms.

## Progress 2026-10-25 (later): where the rest of the time goes, and the sole ray loop in C++

Per-part timing with temporary timers (inclusive, headless lab, per frame; total 0.82 ms with the timers): `_clear_toe` 0.39 (it contains the sink: 0.31, of which the sole's 16-40 rays ~0.22),
`_solve` 0.17 (8,000 calls per 900 frames = 4.4 per foot per frame, ~21 us each: bone pose get/set in GDScript, not the maths), `_flatten_support` 0.11, `_align_foot` 0.035, `_resample_and_correct` 0.033,
`snapshot` 0.086, ground rays 0.017, `_limit_step` 0.012, `_ease_correction` 0.008, publish 0.015. So the remaining cost is spread over the bone-pose traffic of the many `_solve` / `_align_foot`
calls and the sole rays; no single big GDScript loop is left.

Done: `FootIKV2Native.min_gap` (static): the sole-level ray loop of `_sink_to_true_sole` in C++ (reused ray query, `PhysicsDirectSpaceState3D::intersect_ray`), called through
`foot_ik_v2_sole_gap.gd` (`gap()`, with the GDScript loop as the fallback / reference); `_ray_params()` in the modifier builds the one reused query. Modifier stays at the 1,000-line cap.
Result: total 0.77 -> 0.72 ms/frame, `sink` 0.31 -> 0.25 ms (the physics ray queries themselves do not get faster). Full suite: SAME PASS/FAIL set and numbers as the baseline.
Total so far 1.01 -> 0.72 ms (-29 %).

Next (biggest remaining): move the bone-pose heavy parts (`_solve` + `_align_foot`, ~0.2 ms; `_flatten_support`, 0.11) into C++ with direct `Skeleton3D` access (`get_bone_global_pose` /
`set_bone_global_pose` from godot-cpp), the solver already being native. That is the first step INTO the decision layer (it keeps the rules in GDScript and moves only the repeated
leg-placement primitive), so it is safe to do before 037.

## DECISION 2026-10-25 (user: "right now i'm not gonna test it manually, so I'd rather turn it ALL to C++ and then do 037")

Scope is now the whole of v2 in C++, then 037 on top of the native code. The headless suite + the trace comparison are the only guard (no manual testing), so the port is staged and
every stage must keep the SAME PASS/FAIL set and the same measured numbers as the baseline (`/e/Temp/tx/ik_suite_base.log`: red = project checks, floor-walk jerk 0.209, ramp strafe, stairs turn dz=0).

Stages:
- A (done): the small state machines native: `FootIKV2{Limiter,Stepper,Lock,BodySmoother,GroundFilter,KneeHint,StretchHold}Native` (`src/foot_ik_helpers_native.{h,cpp}`) + `FootIKV2Native.reachable`;
  the GDScript modifier makes them through `foot_ik_v2_native.gd` `make()` (GDScript fallback kept). Suite: same set, same numbers; frame 0.72 -> 0.695 ms.
- B: `FootIKV2NativeModifier : SkeletonModifier3D` skeleton in C++: the same `@export` properties, `player_body` / `ledge` / all `debug_*` and `final_*` members as bound properties (the lab,
  trace tools, checks and the player read them by name), `_process_modification_with_delta`, `_build_legs`, `_take_snapshot`, `_publish_final_poses`.
- C: the decision layer in C++, function by function from the GDScript (pelvis drop, stance plan, `_place_foot`, `_clear_toe`, `_flatten_support`, `_resample_and_correct`, `_solve`, `_align_foot`, `_aim`,
  `_ease_correction`, sink), the ledge class, with the GDScript modifier still the reference.
- D: switch `foot_ik_v2_install.gd` to the native modifier (flag `FOOT_IK_V2_NATIVE`, default on when the library is loaded), then COMPARE: a lab flag that runs the same sequences with both and reports the per-frame
  ankle/knee difference from the traces (`foot_ik_v2_check.jsonl`), target < 1 mm; the suite must give the baseline set.
- E: delete the GDScript logic only after D is green for the whole suite and the fuzz gives the same failures; keep tiny GDScript wrappers for names the other scripts use. Then 037 stage 1 in C++.

## Progress 2026-10-25 (stage B+C done): the whole pass in C++ (`FootIKV2CoreNative`)

Design change from the plan above: the GDScript `FootIKV2Modifier` stays as a THIN SHELL (class_name, the `@export` settings, every `debug_*` / `final_*` / `_legs` / `_base` / `_sole` member, `_build_legs`, the ledge, `_ray`),
because ~15 scripts type their variables `FootIKV2Modifier` and read those members by name. The per-frame pass lives in `FootIKV2CoreNative` (`native/planet_crust/src/foot_ik_core_native.{h,cpp}`, a line-by-line port of
`_process_modification_with_delta` and everything under it: snapshot, pelvis drop, body lag, stance plan, place foot, solve, align, toe clearance, flatten, sink, step limit, ease correction, ground/ray sampling). The core reads the
shell's settings with `owner.get(...)` once per pass and SHARES the shell's Dictionaries (a Dictionary is a reference), so the lab, the traces and the checks read what the native pass wrote; it writes the few scalars back with
`owner.set(...)` (`debug_pelvis_drop`, `debug_body_lag`, `debug_last_frame`, `debug_passes`, `final_frame`, `final_basis`, `_is_moving`).
- The shell runs the core when `FootIKV2CoreNative` exists and `PLANET_NO_NATIVE` / `FOOT_IK_V2_GDSCRIPT` are unset (`FOOT_IK_V2_GDSCRIPT=1` forces the GDScript reference path: use it for A/B runs).
- Result (headless lab, 900 frames): total 0.695 -> 0.435 ms/frame; from the original 1.01 ms that is -57 %.
- Full suite with the core: SAME PASS/FAIL set as the baseline (red: project checks, floor-walk jerk 0.209, ramp strafe, stairs turn dz=0); the measured numbers differ only in the last digit of float noise (6 of ~60
  rows: reversals 11 -> 10, foot_max 0.113 -> 0.115, knee_max 14.2 -> 14.0): C++ does the vector maths in float32 where GDScript did scalar maths in double between the vector steps.
- Still GDScript at runtime: the leg set-up (`_build_legs`, once), the sole object (`foot_ik_v2_sole.gd` wraps the native sole; the core calls its `level_points` / `lowest_world_y`), the ledge (called only when a foot is over a drop), the shell
  properties. Next: stage D/E: A/B trace comparison, run the fuzz with both, delete the GDScript pass when equal, then 037 in C++.

## Progress 2026-10-25 (stage D/E done): A/B check, GDScript pass deleted

- Fuzz `scripts/fuzz_foot_ik_v2.sh 12 7` with the native core: IDENTICAL to the GDScript run (the same 8 poses fail, the same 4 pass).
- Per-frame trace comparison of the lab check (`--foot-ik-v2-check`, 666 trace frames, `FOOT_IK_V2_GDSCRIPT=1` vs native): the largest difference of any hip / knee / foot / toe joint position over all frames is 2.0 mm
  (right foot, idle, frame 596; knees 1.9 mm at the landing), one sole-tilt value differs (0.25 deg vs 0 at one frame): float32 vs double rounding, no logic difference. Target was < 1 mm: not reached by a hair, judged noise.
- DELETED the GDScript pass: `foot_ik_v2_modifier.gd` is now the 180-line shell (exports, debug_* / final_* members, `_build_legs`, the ledge, `_ray` for the ledge, `ledge_push`); `_process_modification_with_delta` calls the core.
  The GDScript helper classes it used are removed (stepper, lock, joint limiter, reach blend, body smoother, ground filter, knee hint, stretch hold, sole gap, the native switch): they live in git history (last commit with them: 8e07f4c).
  CONSEQUENCE (decision, user asked for everything in C++): Foot IK v2 now REQUIRES the native library (`scripts/build_native.sh`, which the git hooks run after a pull). Without it the shell logs one error and the foot IK is off.
  `PLANET_NO_NATIVE=1` therefore also turns the foot IK off; `FOOT_IK_V2_GDSCRIPT` no longer exists. `foot_ik_v2_sole.gd` and `foot_ik_v2_solver.gd` keep their GDScript maths as fallbacks (the solver check uses them).
- Suite after the deletion: SAME PASS/FAIL set and numerically identical rows to the previous core run. Frame time 0.46-0.50 ms (machine noise; the shell's `owner.get` of 30 settings per pass is the small remainder).
- Next: 037 stage 1 (plant once) in `foot_ik_core_native.cpp`.

## 037 stage 1 attempt on the native code (2026-10-25): measured, NOT adopted

Fuzz metric script `/e/Temp/tx/fuzz_score.py` (sums the idle-check lines of a `scripts/fuzz_foot_ik_v2.sh 12 7` log). Baseline (GDScript = native): 4 ok / 8 fail, tip clip frames 2, float frames 2, 7 pop faults, max foot step 0.209 m.
- The existing `foot_lock` (hold a resting foot's world xz, the nearest thing to "plant once") switched on in the native pass (temporary env switch, removed again): `dz=0` stairs turn: the clip is gone (0 frames) but a float of 0.046 (limit 0.040) and a
  "foot moved 0.227 m" fault appear. That fault is partly the CHECK'S artefact: the lab measures the IK correction as final foot minus `debug_animated_ankle`, and with the lock the latter is the held anchor, which jumps 0.21 m at a re-plant while the foot itself
  walks there at 2.5 cm/frame. The fuzz with the lock: 0 ok / 12 fail, clip frames 5, float frames 8, 10 pop faults, max step 0.311: clearly worse (same verdict as the old notes).
- What the dz=0 failure really is (traced frame by frame, left foot, frames 284-297, yaw 127-129 deg): at a turn step the foot is `stretched` and hovers 0.17-0.19 m above its tread for ~10 frames (the resting reach needs a 0.2 m pelvis drop and the
  pelvis only sinks at `pelvis_attack_speed` 1.5 m/s = 2.5 cm/frame: 0.079 -> 0.179), the toe clearance adds 0.07 m for 6 frames and then drops to 0 in one frame, and while the foot comes down the heel passes through the tread edge (heel clearance
  -0.049 at frame 294). So the two float/clip frames are the end of a ~10 frame reach transient after a tread flip under the animated foot, not a single-frame bug. A real fix is the 037 stage 3 idea (solve the pelvis once from the final foot targets, no rate-limited
  chase) together with stage 1 (decide the tread once); neither is a quick patch, and each trial costs a 1-4 minute headless run.
- Not started: stages 1-4 of 037. Since the port is done and verified, they can now be done in `foot_ik_core_native.cpp` only (no second implementation to keep in sync). Suggested order: (a) pelvis solved from the planned targets in one step with the
  attack rate only applied while MOVING; check dz=0 and the fuzz; (b) plant-once footprint sampling; (c) inertialization.

## 037 pelvis-attack experiment (2026-10-25, later): a faster pelvis sink does NOT fix the dz=0 turn failure

`pelvis_attack_speed` 1.5 (today) / 4 / 12 m/s on `--stairs-turn=0`: clip 0.049 / 0.026 / 0.026 m, float 0.068 / 0.068 / 0.068, foot_step_max 0.060 / 0.093 / 0.180 (limit 0.060): the float stays and a sharper sink only adds one-frame foot motion. So the
hover is not caused by the sink RATE alone; the earlier reading (a rate-limited chase) was wrong or incomplete. The target tread decision (which tread the foot is aimed at while the foot is half over an edge) is the remaining suspect: stage 1 (decide
the tread once) is the next experiment, not stage 3. The experiment switch was removed again (no code change committed).

## 037 stage 1 footprint experiment (2026-10-25, later): no effect on the dz=0 failure
A resting foot took the HIGHEST walkable tread among 4 extra rays (+-10 cm along the foot, +-5 cm across, within 25 cm) instead of the single ankle ray (temporary env switch, removed again).
`--stairs-turn=0`: identical numbers to the baseline (clip 0.049, float 0.068, step 0.060), so the target tread is not what differs: the hover/clip comes from the reach/pelvis/toe-clearance path,
not from which tread is sampled. Both cheap theories (pelvis rate, tread choice) are now ruled out. Next, only if wanted: trace frames 284-297 for `debug_reach_check` + `debug_toe_lift`
and make the pelvis drop use the post-clearance target (a real 037 stage 3 change, not a patch). No code change committed.
