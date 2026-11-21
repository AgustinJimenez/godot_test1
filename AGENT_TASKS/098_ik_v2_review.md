# 098 - Foot IK v2 review (independent, by a Fable 5.2 agent)

Status (2026-11-14): LAUNCHED. Request (user): "launch a fable 5.2 agent to review the ik implementation, to see what to improve, what's wrong, investigate online if we must".
Review only: no code changes, no commits. Findings go in the Findings section below and the agent's report.

## Scope
Foot IK v2 as it runs now: the native port (`native/planet_crust/src/foot_ik_*_native.{h,cpp}`: core, helpers, ledge, modifier, native), the GDScript glue
(`actors/player/foot_ik_v2/foot_ik_v2_install.gd`, `actors/player/foot_ik/foot_ik_recorder.gd`, `actors/player/climb/hand_hold_ik_modifier.gd`), the tests and probes in
`tests/manual/foot_ik_v2/`, and the history in `AGENT_TASKS/035*`, `036`, `037`, `091`, `093`, `docs/foot_ik_industry_review.md`, `docs/procedural_walk_experiment.md`.
Background: v2 is the reduced rewrite of v1 (preferred by the user: "looks so much better"); v1 is legacy and out of scope except as comparison.

## Questions
1. What is wrong: bugs, wrong maths, edge cases (stairs, slopes, ledges, turns, landings, steep or unstable ground, planet curvature / non-Y up), state that can fight itself,
   frame-rate or timestep dependence, double-precision issues, thread safety, memory or allocation per frame.
2. What to improve, ranked by how much smoother the animation would look (the user judges only by whether it looks smooth), then by cost.
3. How it compares with the state of the art: UE5 Control Rig / Full Body IK / Foot Placement, Unity Animation Rigging, Godot's own SkeletonIK/LookAtModifier, Motion
   Matching foot locking, inertialization, ground-reaction and pelvis-offset work, GDC talks (search online where useful: cite sources with links).
4. Whether the 037 "plant once" design is still the right next step, and what the cheapest path to it is.
5. Test coverage gaps: which scenarios have no check, and which checks pass trivially.

## Rules for the reviewer
- Read the code and tests; run the existing native check and solver check only if quick (`foot_ik_v2_native_check.gd`, `foot_ik_v2_solver_check.gd`); one game instance at a time;
  the user's editor (PID 20944, same exe name) must never be killed. Do not edit source files; write only to this file (the Findings section).
- Lead each finding with the outcome in plain words (smooth / not smooth, fast / slow, buggy / not), then the technical detail with file:line.
- Mark each finding CONFIRMED (reproduced or proven from the code), PLAUSIBLE, or SPECULATION.

## Findings (2026-11-14, review only: no source file changed)

Short paths: `core` = `native/planet_crust/src/foot_ik_core_native.cpp`, `helpers` = `foot_ik_helpers_native.cpp`, `solver` = `foot_ik_native.cpp`, `suite` = `scripts/check_foot_ik_v2.sh`,
`UE` = `E:/repo/UnrealEngine/Engine/Plugins/Animation/AnimationWarping/Source/Runtime/Public/BoneControllers/AnimNode_FootPlacement.h` (Epic's own foot placement, on this machine).
What was run: `foot_ik_v2_solver_check.gd` PASS (9/9), `foot_ik_v2_native_check.gd` PASS (solve 6e-7 m), `foot_ik_v2_comparison.tscn` twice (UAL walks and `--temp-walk`), all headless on the
single-precision 4.7.2 console build (`/e/Temp/bin/godot`). Nothing was run on the double engine, and no stairs / planet scene was run: those findings are from the code and the task logs.

### The one-paragraph answer
v2 does not look smooth in four situations, and they share one cause: a foot's correction (how far the IK moves it from the animation) is allowed to change by any amount in one frame whenever
the change is "up, away from the ground", and the foot's tilt has no smoothing at all. So every tread edge, ramp foot, toe-off and ground-triangle edge shows as a hop or a twitch. The checks
confirm it rather than forbid it (their limits are today's numbers: up to 29 cm of IK change in one frame passes). The industry answer is not more rules but a spring on the correction itself
(UE does exactly that, per foot, for height, tilt and pelvis). That is stage 4 of 037, and it should be done FIRST, not last.

### 1. What is wrong (ranked by how visible it is)

1. **Feet hop on stairs, ramp starts and edges: an upward correction is never smoothed.** CONFIRMED (code + the project's own numbers).
   The ground height under a foot snaps up at once (`helpers:152`, `p_raw > current`), the easing lets the "away from the ground" part of any change through whole (`core:1057`), and the toe
   clearance adds its lift in the same frame (`core:704`). Logged results: toe lift 0.008 -> 0.20 m in one frame at a ramp base (091), 8-23 cm hops at each tread while strafing (037), and the
   suite accepts IK jerk up to 0.29 m in a frame (`suite:102`). This is the main thing the eye reads as "not smooth".
2. **Foot tilt twitches on natural ground: the tilt comes from one ray's surface normal and is applied unsmoothed.** CONFIRMED in code, visible size PLAUSIBLE (not run on the planet).
   `align_foot` (`core:620-654`) turns the sole to the normal of the single ankle ray (`core:487-499`, again after the resample `core:847-866`) with weight `plant`, and nothing limits how fast the
   foot bone turns (the joint limiter only covers hip and knee, and is off while moving: `core:1006`). A height-map or voxel collider has one normal per triangle, so the foot turns a few degrees
   each time the ankle crosses a triangle edge.
3. **On almost-flat ground the foot switches between two different behaviours in one frame.** CONFIRMED in code, visible size PLAUSIBLE.
   "Flat mode" (keep the animation's foot pitch, no planting) needs `normal.y >= 0.999` (2.5 degrees), ground within 3 cm of the body and a flat toe (`core:525-527`); otherwise the sole is forced
   flat onto the ground. At a heel strike the animated foot is pitched 10-30 degrees, so crossing that threshold (gentle planet terrain does it constantly) flips the foot pitch by that much.
   Cause: the tilt is "make the sole match the normal" instead of "add the ground's slope to the animated foot". With the second form flat ground is automatically no change and the mode is not needed.
4. **Toe-off pops of 6-10 cm when jogging or sprinting on slopes.** CONFIRMED (093 soak: 1-37 per 150 s, left as a "trade-off").
   The plant weight fades at a fixed 0.13 per frame (`core:540`, `PLANT_RATE / 60`) while the animated ankle is 0.5-0.7 m from the ground target, so the correction changes by rate x distance.
   A fade on a weight is the wrong tool: the thing to bound is the correction's speed (a spring), which does not grow with distance.
5. **Still present: about a dozen one-frame switches on "moving / not moving".** CONFIRMED (`core:482, 525-527, 566, 611, 681, 737, 760, 1006, 1042`, pelvis rates `core:302-306`).
   037 named this on 2026-10-04; only the knee hint got an eased value (`blend_walk`). Each is a place a pop appears 0.3 s after stopping or on the first walking frame.
   Also a hard knee-pole switch at rest when any foot's ground crosses 3 cm from the body level (`core:951-955`), guarded only by the 60 degrees-per-frame limiter.
6. **A resting foot can jump up to 6 cm in one frame.** CONFIRMED in code. The stepper only starts a step for a move over 6 cm (`helpers:56-73`); smaller moves pass whole. The stance shift moves in
   5 cm steps (`core:368-389`), so each change is exactly such a jump. 036's own acceptance says 3 cm is the ceiling for a non-step frame.
7. **The pelvis still ratchets from last frame's result.** CONFIRMED in code, visible size PLAUSIBLE. `core:284-301`: a foot marked "stretched" at rest raises the hold by `pelvis_drop + residual`
   every frame, and "stretched" is any foot more than 2 cm from its FULL ground target (`core:597-603`), which includes a foot that is only part-way planted (plant weight under 1), not just an
   out-of-reach one. A foot the clip holds 3-14 cm up at rest (the stop step, a weight shift) can therefore pull the pelvis down at the 2.5 cm/frame cap. The planet soak's worst pelvis change is
   exactly 2.5 cm in a frame (093), i.e. the cap is being hit in normal play.
8. **On flat floor the IK is not neutral.** CONFIRMED (run today). Flat pad, the player's real walk: pelvis lowered up to 3.1 cm, ankle moved 3.1 cm, knee 5.4 cm; UAL walk: pelvis 4.9 cm (limit 5.0),
   knee 10.9 cm; crouch idle: right foot moved 17 cm (limit 18). The IK's idea of ankle height (from the shoe mesh) and the clips' own planted height differ by about 3 cm, so it pulls feet down and
   the pelvis after them on every stride. Whether the pelvis bobs with each stride or sits steady was not measured (the check prints only the maximum).
9. **A foot can be placed on top of anything up to hip height.** CONFIRMED in code, PLAUSIBLE in play. The ground ray starts at hip height (`core:893`) and a hit is only rejected for being too far
   BELOW (`core:878-880`); there is no "too high to step on" limit. A foot swung next to a knee-high rock, log or wall takes its top as ground, and that rise is applied at once (finding 1).
10. **Leaving the ground gives the correction up in one frame.** CONFIRMED in code. `no_ground` and `not_walkable` (`core:488-497, 514-523`) skip the eased release that `mid_swing` and
    `out_of_reach` got in 093; so does every release while standing (`ease_release` returns at once when not moving, `core:458`).
11. **Smaller correctness items.** All CONFIRMED in code, low visibility:
    - Frame-rate: every rate is "per physics frame" with 60 written in (`core:540, 744`, `helpers:56, 139, 167`, `CORRECTION_STEP`, the joint limiter). Correct only at 60 ticks; halves or doubles otherwise.
    - The knee hint's smoothing advances once per solve, not once per frame (`helpers:189-197`, called from `core:948`), and a foot is solved 4-15 times a frame, so its rate varies frame to frame.
    - `ease_release` (`core:455-472`) is not frame-gated: a second pass in the same tick eases twice.
    - Hip swing cap: the solver moves the knee but returns the old ankle (`solver:150-159`), so the foot misses, reads "stretched" and feeds finding 7 (the old crouch-idle 0.40 m sink; hidden by raising the cap to 140).
    - `aim` rebuilds the bone basis from a quaternion (`core:1004-1007`): any scale on a thigh or shin bone is lost. Fine for today's rigs, a trap for a new one.
    - The ray query keeps the mask and the excluded body from its first use (`core:883-892`): a later `ground_mask` change does nothing.
    - A released leg leaves last frame's `debug_solve` in place, and the pelvis release reads it as that leg's slack (`core:297-300`).
12. **Not a problem (checked).** Non-Y up: every "up" is world +Y, but `PlanetWorld` turns the planet under the player so +Y stays up (`planet_world_native.h:4-5`). Double precision: no float/double
    mix that matters; the only gap is that nothing is tested on the double build (section 5). Threads: all on the main thread; `FootIKV2Debug`'s static maps are fine there. Memory: no leak; about
    45 property reads by name per pass (`core:74-139`), the legs rebuilt from a Dictionary every pass (`core:141-164`), all state in Dictionaries keyed by side (`core` header line 85) and one
    Dictionary per ray. 0.43-0.50 ms a frame in total (091): untidy, not a cause of anything visible.

### 2. What to improve (ranked by smoothness gained, then cost)

1. **One spring per foot on the correction (height first), replacing the caps.** Biggest gain, medium cost (one file). Keep `offset = IK foot - animated foot` as state and move it with a critically
   damped spring: fast up (half-life about 0.05 s), slower down. Deletes `CORRECTION_STEP`, `ease_release`, the ground filter's rate and the plant-weight fade's job of hiding jumps. Fixes findings 1, 4, 6, 10.
   The cost is honest: for 2-4 frames a toe may be a few cm inside a riser. UE accepts exactly this ("MaxGroundPenetration 10 cm ... recommended to allow some to account for interpolation", `UE:303-306`).
   The earlier "easing clips or floats" verdict (AGENTS.md) was for a speed cap on the foot, which lags without limit; a spring on the offset settles in a fixed time.
2. **Tilt as "ground slope added to the animated foot", through its own spring.** Large gain on natural ground, small cost. Rotate the animated foot by the rotation from up to the ground normal, eased
   (UE: `GroundRotationSpringState`, `UE:118-120`). Removes the flat-mode switch (finding 3) and the triangle twitches (finding 2), and keeps the clip's heel-toe roll. Take the slope from heel and toe
   hits instead of one ray's normal.
3. **A thicker ground probe.** Medium gain, small cost. A sphere sweep of about 5 cm (UE's default, `UE:291-294`) instead of a ray rounds every tread edge and triangle edge, so the height rises over
   several frames before the foot arrives; add a top limit of about 0.35-0.45 m above the body's floor (finding 9).
4. **Pelvis from this frame's targets, through a spring.** Medium gain, medium cost. Needed drop = the most any planted foot's final target needs, then a spring (UE: stiffness 350, critically damped,
   `UE:361-376`); delete the stretch hold and its ratchet (finding 7). This is 037 stage 3, and the 091 "dz=0" fix already proved the idea (the pelvis must follow the final target).
5. **One eased "walk" value instead of the moving flag everywhere.** Medium gain, small cost: `blend_walk` exists; use it for the limiter, the pelvis cap and rates, the reach rules and the sink passes (finding 5).
6. **Agree the planted height with the clips.** Small-medium gain, small cost: measure each clip's own planted ankle height once at load and use it as that clip's `ankle_height`, so flat floor is a true
   no-op (finding 8). Check the crouch idle by eye: the IK re-poses its right foot by 17 cm.
7. **Later, larger:** bake each clip's contact times at load (foot height and speed: UE drives planting from a per-foot speed curve, `UE:435-437, 460-466`), then lock a planted foot in the world and let
   it go through the same spring (section 4). Turn-in-place: with no lock the feet ride round with the body like a turntable.
8. **Worth one look, PLAUSIBLE:** the animation and the IK run on the physics tick (`player_body.gd:348, 354`), with `max_fps=60` and no physics interpolation (`project.godot:16`). Whenever a drawn
   frame gets 0 or 2 ticks (any dip under 60, and the planet is GPU-bound) the whole character repeats or skips a pose. If the body stutters while the camera stays smooth, this is it, and no IK change will fix it.

### 3. Against the state of the art

| Topic | Industry (source) | v2 today |
|---|---|---|
| Smoothing | Springs on ground height, ground tilt, plant offset and pelvis (`UE:108-121, 230-274`); inertialization = decay the pose difference after a change (Bollo, GDC 2018) | Per-frame step caps, a weight fade, hard switches; upward changes unsmoothed |
| Ground probe | Sphere sweep 5 cm, from 75 cm above to 100 cm below the foot, some penetration allowed (`UE:276-316`) | One ray from hip height, zero penetration, up to 8 re-solves to clear a toe |
| Contact | Plant / unplant / replant state with a release radius of 35 cm and angle of 45 degrees, driven by foot speed (`UE:27-32, 453-519`) | Decided again every frame from ankle height; lock exists but is off |
| Pelvis | Lowest needed offset, spring, modes for uphill / downhill, horizontal rebalance, heel lift before hip drop (`UE:334-412`) | Drop only, rate caps, 6 cm cap while moving, feedback ratchet at rest |
| Foot tilt | Slope added to the animated foot, blended by foot speed, ankle twist reduced (`UE:72-74, 506-508`) | Sole forced onto the normal, or untouched in flat mode |
| Solver | Analytic two-bone with a pole (UE, Unity `TwoBoneIKConstraint`, Godot 4.6 `TwoBoneIK3D`) | The same; v2's solver is sound (checks pass, knee never bends backward) |

v2's solver, sole-from-the-mesh and ledge "safe zone" are as good as or better than the references. What it lacks is the layer between "where the ground is" and "what the bone does": the interpolation.
Godot's own IK (returned in 4.6: `TwoBoneIK3D` and friends) is only a solver, with no ground logic, so there is nothing to adopt there; `SkeletonIK3D` stays a dead end (AGENTS.md).
Links: [UE FootPlacement pelvis settings](https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/AnimationWarpingRuntime/FFootPlacementPelvisSettings),
[UE leg interpolation data](https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/AnimationWarpingRuntime/FLegRuntimeData/FInterpolationData),
[UE pose warping](https://dev.epicgames.com/documentation/unreal-engine/pose-warping-in-unreal-engine),
[Bollo, Inertialization, GDC 2018](https://gdcvault.com/play/1025165/Inertialization-High-Performance-Animation-Transitions),
[Holden, IK and foot locking](https://theorangeduck.com/page/inverse-kinematics-foot-locking) (already read for 037),
[Holden, dead blending](https://theorangeduck.com/page/dead-blending-node-unreal-engine),
[Godot 4.6 IK](https://godotengine.org/article/inverse-kinematics-returns-to-godot-4-6/), [TwoBoneIK3D](https://docs.godotengine.org/en/4.6/classes/class_twoboneik3d.html).
The UE header was read line by line; the web pages were found by search and only their summaries read, so treat them as pointers, not as checked claims.

### 4. Is 037 "plant once" still the right next step?

**Right idea, wrong order.** Deciding a foot's ground once per contact is what UE does, and it is the only real cure for a foot re-deciding its tread every frame. But the experiments since 037 was
written say it is not what the eye is waiting for: the lock (the nearest thing to plant once) made the fuzz worse, the footprint sample changed nothing, tread hysteresis changed nothing (all 091), and
the one thing that fixed a real failure was the pelvis following the final target. Plant once also cannot work while walking as 037 states it: a walking foot is not locked in XZ and slides under the
clip, so a held height is wrong the moment the foot slides over an edge. It needs a true world lock, and a lock needs a smooth release, which v2 does not have.

Recommended order (each stage gated on the suite, the fuzz and a live look):
- **A. Springs on the correction** (improvements 1, 2, 5): 037's stage 4, moved to the front. It is what the user sees, it needs no contact decision, and it makes every later release smooth by construction.
- **B. Pelvis from final targets through a spring** (improvement 4): 037 stage 3. Delete the stretch hold.
- **C. Plant once = lock + latch**: on planting, hold the world position, height and normal; release on distance (UE: 35 cm), angle, reach or foot speed; the offset left over decays through stage A's spring.
- **D. Only if stairs still hop:** the swing foot's height follows a curve from the lift-off ground to the landing ground. The flat-walk clip's swing foot goes through the riser (037's own conclusion),
  and only a planned swing or real stair clips fix that; no sampling rule can.

Cheapest path: do not design C from scratch. `AnimNode_FootPlacement.cpp` is on this machine next to the header cited above; port its plant / unplant / replant test and its spring calls into
`core`, in place of `ease_correction`, the stepper, the ground filter and the plant fade. Stage A alone is small and can be judged in 2-3 idle loops plus one walk up the lab stairs.

### 5. Test coverage gaps

Checks that pass without testing anything (all CONFIRMED):
- **Idle knee sway** (`suite:291-300`): the trace is looked for only under macOS and Linux paths. On Windows it finds none, `awk` prints 0 for empty input (tried: prints `0`), and `0 <= 0.04` passes.
- **Every "stairs walk ... (run)" line** (`suite:78-80, 84-86, 91-93, 107-110`) greps for `FOOT_IK_V2_IDLE_CHECK`, which matches the FAIL line too. Only the vibration numbers are graded; clip and float are not.
- **Limits are today's values, not quality bars**: IK jerk up to 0.29 m a frame, reversals 15 %, knee 36 degrees a frame (`suite:98-103`); flat-floor difference 17-18 cm (`suite:120-122`);
  pelvis drop on flat floor 5.0 cm against a measured 4.9. They catch "worse than today", never "bad".
- **Solver check `hip_swing_is_capped`** grades the thigh angle only, not that the foot then misses its target (finding 11).
- **Native check** compares the solver and the sole with a GDScript oracle. The 1,081-line decision pass has no reference any more (the GDScript was deleted in 091), so the suite numbers are its only guard.

Scenarios with no check:
- The double-precision engine and library (the build the game runs on in this branch): the suite's `godot` is the single-precision 4.7.2 console build.
- Natural terrain: the planet soak grades floating only while standing (`planet_ik_soak.gd:167-168`), so a foot that does not reach the ground on a downhill stride is never counted; nothing measures foot tilt change per frame anywhere.
- Smooth turning in place (suite: "KNOWN OPEN", fuzz only), `--stairs-turn=0.24`, the 0.35 m stairs.
- Stop and start transitions as such (the 0.3 s after stopping, where finding 5's switches fire), landings on slopes, walking off a ledge, a waist-high obstacle beside a foot (finding 9).
- Any tick rate other than 60, any frame rate under 60 (improvement 8), a second modifier pass in one tick.
- A rig with scaled leg bones; a character swap during play.

Stale text to fix when next in these files: `foot_ik_core_native.h:3-7` and `foot_ik_helpers_native.h:3-6` still say the GDScript stays as the reference (deleted in 091); 037's title says "nothing built yet".

## Status of the follow-up (2026-11-15)

Done (uncommitted; judged by eye by the user: "i don't see anything wrong"):
- Improvement 1, height: a spring on the upward ("away from the ground") part of the correction, half-life 0.05 s (`UP_HALF_LIFE`, `ease_correction`). Cost, measured on the double engine: at a ramp base the toe sinks up to 11.3 cm for 3 frames
  (spring off: no clip, but the foot floats 16 cm for 9 frames); the lab's all-surfaces walk now allows 12 cm (`SURFACE_TIP_CLIP_LIMIT`, idle checks keep 2 cm). The stairs sidedown IK jerk p95 rose 0.034 -> 0.060 (the hop is spread over frames) while the worst frame fell 0.107 -> 0.079; its limit is 0.065.
- Improvement 2, tilt: the ground normal given to `align_foot` goes through a spring, half-life 0.06 s (`TILT_HALF_LIFE`, `smooth_tilt`). Not shown visibly on gentle dunes (the normal hardly changes); on the all-surfaces check it cut the float frames 7 -> 4.
- Test gaps fixed in `scripts/check_foot_ik_v2.sh`: the stairs "(run)" lines require `FOOT_IK_V2_IDLE_CHECK PASS`; the knee-sway check finds its trace on Windows and fails when there is none. The suite was run on the double engine (a `godot` wrapper first on PATH): 58 PASS, 0 FAIL.

Not started, and why: improvement 4 in full (pelvis from this frame's final targets; only the pelvis SPEED easing below was done): the soak's worst pelvis change is 4 mm a frame on the walk script (`PELVIS_POP`), so there is no measured pop to fix yet; its stretch-hold logic carries several earlier bug fixes. Also not started: 3 (thicker ground probe), 5 (one eased walking value), 6 (clip ankle height), 7 (plant lock).
Start any of these from a measured failure (a soak or live-log number), not from the review's reading of the code.

Pelvis (2026-11-15, uncommitted, NOT yet judged by eye): measured first, on the lab's replays (strafe on ramp15/30, uphill, jump45, stairs up/down/sidedown/sideup; per-frame `body.pelvis_drop`
from `foot_ik_v2_check.jsonl`): the pelvis starts every dip at the full 2.5 cm/frame (1.5 m/s) on one frame and hit that rate for 18-20 frames on a 30-45 degree ramp (a 20+ cm dip); on stairs it bobs 0 -> 6 -> 2 -> 6 cm every
stride. Change: the pelvis speed now builds at `PELVIS_ACCEL` = 20 m/s^2 (`update_pelvis_drop`), still limited by the same attack / release / moving rates and slowed to stop at the needed value. Dip onset on ramp30 went
2.5, 2.5, ... -> 1.0, 1.5, 2.1, 2.5 cm a frame. Suite on the double engine: 58 PASS, 0 FAIL; idle checks' float stays <= 1.6 cm. The needed-drop logic (stretch hold and its ratchet) is untouched.

Left from the review's list (2026-11-15), none started: 2.3 thicker ground probe (about 5 cm sphere sweep + a ~0.4 m "too high to step on" limit); 2.5 one eased walk value in place of the moving flag (~12 switches);
2.6 the clips' own planted ankle height (flat floor is not a no-op: pelvis 3-5 cm); 2.7/4.C plant lock + latch; 2.8 the physics-tick / 60 fps stutter question; findings 1.5-1.7, 1.9-1.11 (pelvis ratchet at rest, resting foot jumps up to 6 cm,
leaving the ground gives up the correction at once, frame-rate "60" written in, knee-hint smoothing per solve); the stale header text in `foot_ik_core_native.h` / `foot_ik_helpers_native.h`; test gaps: natural-terrain tilt per frame, turning in place,
stop/start transitions, ticks other than 60. Caveat: the earlier "before / after" planet-walk clips used the lab's temporary spawn (the user's last logged position, mid-flight) and are not valid; record with `--no-temp-spawn`.

### Eased walk value (improvement 5) and stop/start test gap: measured, no failure found (2026-11-15)

The idle-check replay already walks, stops, walks and stops again on flat floor (walk to idle at frames 149 and 258, idle to walk at 78 and 220). In the per-frame trace
(`foot_ik_v2_check.jsonl`, double engine) the change of what the IK adds to the animated ankle stays at or below 4.5 cm per frame for 25 frames after each switch
(median over the whole run 0.1 mm), and the pelvis moves at most 1.5 cm per frame. The only large steps (up to 28 cm) are the jump landing at the start, which is the
animation itself changing. So there is no pop to fix at the stop/start switches on flat floor, and the ~12 on/off `moving` switches are NOT being replaced for now:
re-open only from a recorded pop (a stop on a slope or stairs is the likely place; the replay has no such segment yet).
Also done: the stale headers of `foot_ik_core_native.h` and `foot_ik_helpers_native.h` (they still described a GDScript reference copy that no longer exists).

### Thicker ground probe (improvement 3): looked at, deliberately not started (2026-11-15)

`ground_hit` (foot_ik_core_native.cpp) is a single `intersect_ray` plus five inward re-tries; every placement, the resample and the ledge logic read that one hit, so a sphere
sweep changes the hit position AND normal for all of them. There is no recorded case where a foot lands wrongly on a tread edge or a rock (the stairs and 45 degree ramp
checks all pass), so the change would be speculative and could move the 58 suite numbers. Start it only from a recorded failure: a natural-terrain clip of a foot
resting on a rock/kerb edge, or a tread-edge case in the stairs lab.

### Walk speed on slopes (2026-11-15, `actors/player/player.gd`)

The walk now slows progressively with the uphill gradient along the walking direction (rise over run from `get_floor_normal`): speed x (1 - 0.6 x gradient), floor 0.45, eased at 2/s, and the clip's
playback scale follows it, so the feet keep matching the ground. Downhill and flat are untouched. The stair slowdown stays an on/off switch: an eased version (tried at 8/3, 20/0.8 and
instant-in/0.8-out per second) doubled the stairs IK jerk (diagl 0.035 -> 0.060, backward 0.030 -> 0.060) because the stair clip's pace and the ground speed disagree half-way. Suite 58 PASS.
NOT done: why the stair slowdown triggers on natural terrain; the live log of 2026-11-14 holds no slowed sample to read the condition from. Needs a play-test with `planet_live_lab.jsonl` kept.

### Clip ankle height (improvement 6): measured, not an ankle-height mismatch (2026-11-15)

Flat floor, double engine, per-animation `pelvis_drop` from the idle-check trace: idle 7.8 cm (constant), walk median 3.2 cm (max 7.3), jump landing up to 12 cm (the landing itself).
In the last idle frame the planted feet both end 9.1-9.2 cm above the ground (= `ankle_height`), so the placement is right; the left leg needs 0.873 m of a 0.887 m reach and the
clip's two ankles stand 11.6 cm apart in height, so the pelvis goes down to keep the left leg from being fully stretched (the stretch hold), not because the clip's ankle height
differs from `ankle_height`. A fix would be a different idle pose (an animation change) or a per-clip pelvis offset; neither is an IK bug, so nothing was changed.

### Pelvis from final targets / stretch-hold ratchet (rest of improvement 4): measured at rest, no drift (2026-11-15)

The two idle stretches after a walk (frames 149-219 and 258-702 of the idle-check trace) both settle at 7.7-7.8 cm whatever the entry value (6.0 cm and 0.2 cm at the first idle frame), and stay
constant for the 445 frames of the last one. A ratchet that kept the pelvis lower than needed would show as a history-dependent rest value; it does not here. Not changed. Re-open from a
case where the rest height differs between two ways of arriving at the same spot (slope, stairs), which this replay does not cover.

### Tick rate other than 60 (improvement 8, test gap): measured, passes (2026-11-15)

New lab flag `--ticks=N` (sets `Engine.physics_ticks_per_second`; `--fixed-fps` alone does NOT change the physics rate, the numbers came out identical to 60 with it). The idle replay at 30 and 120 Hz
passes the idle check (clip 0.000, foot step 0.001 at 30, 0.008 at 120). At 120 Hz the settling after a walk shows two frames with the right toe 4-7 cm up (frames 301-302, a foot coming down over about 10
ticks = 0.08 s, no pop). Both rates are now two lines in `scripts/check_foot_ik_v2.sh`. Not covered: the whole character skipping poses when a render frame gets 0 or 2 physics ticks (that is outside the IK code).

### "60" written into rates (finding 1.10, part): plant-fade and support-shift rates now per second (2026-11-15)

`PLANT_RATE / 60.0` and `SUPPORT_RATE / 60.0` (foot_ik_core_native.cpp) were per-frame steps, so at 120 Hz those fades ran at half the speed and at 30 Hz at double; they are now `* delta_physics`
(identical at 60 Hz; the suite is unchanged: 58 PASS, 22 idle checks incl. 30/120 Hz). Left: the ground filter's `RATE / 60.0` in foot_ik_helpers_native.cpp (the step after HOLD_FRAMES held frames; the
hold itself counts frames, so it needs a delta passed in and a time-based hold: not changed).

### Correction easing (finding 1.11 `ease_release` not frame-gated, and the per-frame step): fixed (2026-11-15)

`ease_release` stepped the held correction once per CALL, and `CORRECTION_STEP` (3 cm) was a per-frame step in it and in the correction easing below (`ease_correction`). Now a second call in the same frame re-solves at the
already eased value without stepping again, and the step is `CORRECTION_STEP * delta_physics * 60` (3 cm at 60 Hz, 1.5 cm at 120, 6 cm at 30: the same speed in m/s). Identical at 60 Hz: suite 58 PASS, 22 idle checks.
No measured double step was seen (the paths only call it once per frame today); this is a guard plus the rate fix. Still open: the ground filter's `RATE / 60.0` (needs a delta passed in), the knee-hint smoothing once per solve,
the resting foot's one-frame jumps (idle foot step at rest measured 0.001 m at 30 and 60 Hz, 0.008 at 120: nothing to fix there).

### Ground filter rate and hold (finding 1.10, rest): now in time (2026-11-15)

`FootIKV2GroundFilterNative::height` stepped `RATE / 60.0` after `HOLD_FRAMES = 3`: now `RATE / physics_ticks_per_second` and `ceil(0.05 * ticks)` frames (3 at 60 Hz, so unchanged there). Suite 58 PASS.
The "60" items of finding 1.10 are done. Open from the small items: knee-hint smoothing once per solve, leaving the ground giving the correction up at once, natural-terrain tilt-per-frame test, scaled leg bones.

### Knee-hint smoothing once per frame (finding 1.7): fixed (2026-11-15)

`FootIKV2KneeHintNative::steady` advanced its slerp on every `solve()` call, so a leg solved twice in a frame (resample, re-solve) smoothed twice as fast. It now keeps where the frame started
(`frame_start`/`frame_of`, physics frame) and recomputes from there on a repeated call. Same at one solve per frame: suite 58 PASS.
Open from the small items: leaving the ground giving the correction up at once, the natural-terrain tilt-per-frame test, scaled leg bones.

### Leaving / reaching the ground (findings 1.6, 1.9): measured, a one-frame landing snap exists, not changed (2026-11-15)

Idle-check replay, left foot, frames around the first jump landing (60 Hz): frame 7 foot 0.324 m above the ground (the leg reaching down in the air), frame 8 (the physics landing, clip switches to `jump_land`)
foot 0.032 m: a 29 cm drop in one frame, the IK's addition to the animated ankle going -0.082 -> -0.358 m; the foot then follows the clip up again (0.046, 0.077, 0.139 m). The takeoff side is small
(8.7 cm in the air). A cap on how fast the downward correction may grow at the landing (like the 3 cm/frame release easing) would turn the snap into a few frames of foot hang above the ground while the body is already down:
a look/trade-off to judge by eye on a recorded landing, so it is NOT changed without that. Record: the lab jump replay (`--jump45` or the idle replay's `jump` segment) with a close side camera.

**Correction to the landing note above (2026-11-15):** the 29 cm one-frame drop (trace frames 7-8) is the lab's SPAWN drop (the character starts in the air, `_from_floor` false), not a landing from a jump.
The replay's own jump lands at trace frame 84 (`jump` -> `walk`, velocity 0): there the left foot goes 1.165 (released) -> 1.088 -> 1.023 -> 0.955 -> 0.889 -> 0.840 m while the clip's ankle goes 1.117 -> 1.081 -> 1.043,
so the IK's addition grows by about 3 cm per frame at most and the foot follows smoothly (right foot: 0.843 -> 0.842, no change). No landing snap in the jump itself, nothing to cap. Landing clip: the 4x slow clip
sent to the user covers it at about 1.8 s of real time. Item closed unless a live jump shows otherwise.

### Landing absorb, the suite in one session, and the walk the suite does not test (2026-11-15)

- **Landing absorb** (foot_ik_core_native.cpp, `update_pelvis_drop`): the capsule stopped dead from the fall speed (hips 5.1 cm/frame -> 0). On a landing faster than 1.5 m/s the pelvis now keeps going down at 60% of that
  speed (cap 2 m/s, from the NEXT frame) and stops at PELVIS_ACCEL; dip at most 10 cm, fading out over 0.35 s. Hip steps now 5.4, 5.1, 5.5, 3.5, 2.6, 1.7, 0.6 cm. Suite 58 PASS.
- **One session:** `tests/manual/foot_ik_v2/foot_ik_v2_session.tscn` runs the 28 lab scenarios of the suite in one process (one window, one movie); the lab asks `foot_ik_v2_session.gd` for its args and no longer quits in a
  session. `--only=text`, `--from=N`. Recording script: scratchpad `suite_rec/session_rec.sh` (temporary override.cfg with display/window/size/no_focus, `--screen 1`).
- **BLIND SPOT FOUND by that recording:** `PlayerTempWalk` (ENABLED, CHOICE 4 = the Mixamo walk at 0.575 playback) replaces `unarmed_walk` in a window, but a HEADLESS run keeps UAL1's Walk (`_skip_headless`). The suite is headless, so it
  has never tested the walk the player sees (the walk clip time advances 0.018/frame windowed vs 0.033 headless). New lab flag `--temp-walk` makes a headless run use the real walk. With it, "flat floor, every surface" FAILS
  (clip 0.0388 m at stair010, limit 0.010) and so does the ramp strafe in a window (float 0.112 m, 17 frames, limit 0.080): same numbers as the windowed recording. NOT fixed, NOT yet in the suite (it would turn it red).
- The "left leg shaking" the user saw at second 5 of part 1 is the lab's spawn drop (the character starts in the air): left foot y 0.306 -> 0.121 -> 0.041 -> 0.130 -> 0.139 -> 0.118 -> 0.097 at frames 14-20, knee turns 17/9/19/3/14/33 deg per frame.
  Tried a faster foot hand-off during the landing window (8 cm/frame through `ease_correction`): the foot dipped below the planted height (0.041) and did not calm, so it was reverted.

### Stair controller converted to native (2026-11-15)

`actors/player/player_stair_controller.gd` (418 lines) is now `PlayerStairControllerNative` (native/planet_crust/src/player_stair_controller_native.cpp/.h, registered in register_types.cpp); the GDScript file is deleted
(git history has it). Same API and properties (hover_offset_y, balance_offset_y, camera_snap_y, consumed_horizontal_motion, continuous_traversal_active, setup, begin_frame, apply_step_up/down, is_short_step_down,
record_presentation_delta, update_presentation, reset, is_climbing, has_recent_transition, is_near_stairs, get_debug_state, get_body_rest_y). player.gd creates it with
`ClassDB.instantiate(&"PlayerStairControllerNative")` and types the results it uses. Suite: 58 PASS. Still GDScript: the speed/slowdown block of player.gd (next), the clip choice (player_body.gd, player_stair_clips.gd, player_temp_walk.gd).

### Walk pace converted to native (2026-11-15)

The speed block of player.gd (uphill slowdown 0.6/0.45 eased 2 per second, the on/off stair slowdown, the clip playback scale) is `PlayerWalkPaceNative::pace` (native/planet_crust/src/player_walk_pace_native.cpp/.h):
`pace(speed, walking_pace, on_stairs, on_floor, floor_normal, wish, delta, stair_scale) -> [ground speed, playback scale]`. The UPHILL_*/STAIR_STEP_SPEED constants moved with it. Suite 58 PASS.
Still GDScript in the player's walk: the clip choice and rate (player_body.gd, player_stair_clips.gd, player_temp_walk.gd, an experiment file: "delete this file" is in its header), the ledge/steep-slope helpers.

Lab ramps (2026-11-15): the lab's ramps stood with their low end 0.2 * cos(angle) above the floor (19 cm vertical face at ramp15), and the character stopped dead at it (also with the old GDScript player, so not the native conversion); the all-surface check "passed" with the character stuck. The ramps are now sunk by that lip (`RAMP_LIP`) and painted light blue (stairs too); ramp15 now climbs (suite 58 PASS). Still open: stair020 stops at its first 0.2 m riser (step-up finds no tread), `--spot=N` / `--spot-loop` walk/loop one surface of the check.

Stair clips (2026-11-16, uncommitted): the authored stair clips (`assets/models/stair_clips/*.res`) are named for Mixamo bones (`Hips`, `LeftUpLeg`); this character's skeleton is UAL (`pelvis`, `spine_02`), so not one track matched and the clip animated NOTHING (legs frozen while `animation_time` cycled; found by the animated ankle staying a fixed offset from the body on lab ramp45, which is put on the stair collision layer so the game's own `on_staircase` picks the stair clip). Fixes: `PlayerStairClips._retargeted` retargets the stair FBX onto the character like the temp Mixamo walk (in place along the ground, the climb kept; the .res is the fallback / Mixamo-named characters); the clip plays against its own measured ground speed (`PlayerStairClips.ref_speed`, was the strafe speed); `player.gd` takes the stair pace on any stair-layer surface and caps the stair speed so the clip never plays faster than `STAIR_CLIP_MAX_RATE` 1.7 (only while the stair clip plays: capping the lab's flat-walk stairs failed the suite, clip 0.0277 and jerk 0.060); `PlayerWalkPaceNative` no longer stacks the uphill slowdown on the stair pace (0.375 x 0.45 = 0.54 m/s dropped the animation to idle). Measured on ramp45 (headless, Mixamo walk): flat 2.75 steps/s at 2.7 m/s, ramp 2.9 steps/s at 0.68 m/s. Suite 58 PASS. Open: the ramp45 per-frame foot step is 0.262 m (`foot_step=0.262@right_ramp45`, not graded), and 7 right-toe TIP_CLIPs of 3+ cm appear on it with the stair clip.
Loop viewer (lab): `--spot=N` walks one surface of the all-surface check, `--spot-loop` repeats it (longer walk, starts standing on the floor, `FootIKV2Modifier.reset_state()` between passes: a scene reload froze the window 9 s because the player scene loads again, a bare teleport kept the held feet and the pelvis crouched 17 cm). Ramps now start flush with the floor (`RAMP_LIP`); they stood 19 cm up at their low end and the character stopped at that face. Left-toe floats of 6-11 cm for ~9 frames at the first step from idle with the Mixamo walk: every pass, not yet judged (real float or heel-strike pitch).

Real-walk checks (2026-11-16): the suite now also runs the all-surface lab with `--temp-walk` (the Mixamo walk a window plays; headless uses the UAL one) and requires PASS, with `REAL_WALK_CLIP_TOLERANCE` 0.05 for the sole clip (measured 0.032-0.046 on stair010/ramp30: the foot's rise is a spring, `UP_HALF_LIFE`, so the toe sinks up to 8 cm into a riser for 1-2 frames, which `SURFACE_TIP_CLIP_LIMIT` 0.12 already allows). Per-lane INFO lines print the real-walk numbers. Left-toe "floats" at the first step from idle are the clip's own heel rock-back (heel on the floor 0.4-2 cm, sole pitched 18-27 deg, `align reason animated`): not counted, and no longer printed. Stair020 stops at its first 0.2 m riser (measures nothing). Suite 58 PASS.

Landing check (2026-11-16): `scripts/check_foot_ik_v2.sh` runs its own 60 Hz idle replay and requires the IK pelvis drop to stay under 0.13 m (measured 0.124; MAX_LANDING_DIP 0.10 + the usual drop) with no one-frame change over 0.035 m (measured 0.028). It first read whatever trace the previous run left (0.159 from another replay), which made it fragile. The pelvis drop peak depends on the tick rate (30 Hz 0.112, 60 Hz 0.124, 120 Hz 0.135; one-frame change 0.048 / 0.028 / 0.015): 30 Hz is the rate at which one frame is large, not a snap.

Release snap (2026-11-16): the largest per-frame foot movement of the lab was 0.228 m (right foot, step onto ramp45 with the stair clip, `skip no_ground`, plant 0.6): a foot a correction had lifted 0.2-0.3 m off the ground (a swing foot over a ramp) was released onto the animated pose in ONE frame when its ground ray found nothing. `place_foot` now eases that release like the out-of-reach one (`ease_release`, 3 cm a frame, only while moving and with a held correction). ramp45 foot step 0.228 -> 0.117 m; ramp15/30 unchanged (0.090 / 0.102); suite 59 PASS. Open: stair010 run ALONE with the default walk fails the sole clip limit (0.029 vs 0.010; the all-surface run passes because it starts that lane with the previous lane's foot state): the same spring as the real-walk case (0.032-0.046), so a fresh character on the stairs may clip ~3 cm for a few frames; the suite grades only the all-surface runs.

### stair020 stuck at its first riser: found and fixed; the real-walk run now fails there (honest)

Measured (headless `--foot-ik-v2-check --spot=5 --spot-loop`, root z/velocity in the trace): the player walked to z 2.697, stopped, velocity 0 for good. `PlayerStairControllerNative::apply_step_up` was never reached with any motion: it got `motion = 0`. Cause: `PlayerSteepSlope.block_uphill` (runs just before it). The capsule's rounded bottom touching the top EDGE of the 0.2 m riser reads a 63 degree normal (past the lab's 60, and the game's default 45), so the whole walk velocity was taken away. 0.1 m risers read a shallower normal and passed. (Ruled out first: the step-up headroom test lifting by `step_height` 0.4 against the second 0.4 m tread: reverted, it was not the cause.)

Fix (`actors/player/player_steep_slope.gd`): `_is_step_edge` - not a slope when a flat tread (normal.y >= 0.7) is just beyond the contact, 0.01..step_height+0.05 above the feet. A really steep slope has no such tread, still blocks.

Consequence: stair020 used to "pass" the real-walk graded run by standing still at the riser. Now it climbs, and that run FAILS at stair020 (suite 58 PASS / 1 FAIL): clip 0.081 (limit 0.05), tip_clip_max 0.184, foot_step 0.150, 3 pose faults; the default (UAL walk) run passes. The 0.2 m staircase is walked with the flat Mixamo walk (only Ramp45 has the stair collision layer), so the swing foot goes into the 0.2 m risers. Next: measure which frames/foot, then decide between the stair layer on stair boxes (stair clip) and IK riser clearance for the flat walk. Limits NOT loosened.
