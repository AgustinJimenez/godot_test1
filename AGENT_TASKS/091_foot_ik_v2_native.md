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
