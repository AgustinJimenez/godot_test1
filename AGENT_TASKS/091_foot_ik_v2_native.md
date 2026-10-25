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
