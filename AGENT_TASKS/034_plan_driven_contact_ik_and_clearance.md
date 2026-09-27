# 034 - Plan-driven contact IK and environmental clearance

Status: in progress. Flat contact and the revised Stair Up clearance are headless-clean; the new
stair result still needs a live visual verdict. Real collision and general environmental clearance
remain.
Depends on task 033's portable plan and character-attached debug view. Work stays in the isolated
locomotion lab before gameplay Player integration.

## Current handoff

**Status on 2026-09-22: all four moving flat gaits are automation-clean; live visual review is
pending.** UAL Walk, Aim Walk, Crouch, and Sprint consume the same persistent six-contact plan.
Their planted ankles hold a horizontal world target while retaining source shoe roll and upper-body
motion. Sprint's root travel comes from its source stance (2.412 m/cycle, 3.62 m/s at native
cadence); contact fades in on descent and out before takeoff, with zero IK weight in true flight.
The Contact IK slider now turns these corrections off. Both the private source sampler and live
comparison skeleton reset at clip switches, preventing unkeyed bones from retaining the prior gait.

Focused 120-frame pose and 1209-vertex shoe checks pass all eight in-place/moving flat cases.
Worst moving plant error is <= 0.0003 m; worst leg step is Walk 9.19, Aim Walk 15.17, Crouch 8.20,
and Sprint 25.69 degrees/frame (source Sprint 27.10). Every moving shoe clears the flat plane by
>= 0.006 m. The 60-frame Crouch -> Walk Contact IK off regression matches the source within
0.056 degrees and zero positional difference. All five moving modes retain a stable six-contact
plan over 15.2 cycles; the existing Stair Up check and `scripts/check.sh` pass. The detailed
failure/correction trail is in [the archived iteration](archive/034_flat_gait_contact_iteration.md).

Next: compare each moving gait live for 2-3 loops, especially Sprint's landing and takeoff.
The moving root is still scripted, and the staircase is still visual-only. Remaining task 034 work
includes a controllable physics body, colliding stairs, and swept/final shoe clearance there.
Animation and visual changes remain uncommitted until the user confirms them live.

The lab now has a **Reset parameters** button for its six gait sliders. Their UI values and runtime
properties reset together; Steps / second uses the selected source clip's native cadence (1.0 for
Original). This button resets tuning only, leaving the current playback position and step plan
intact. The controls helper applies the slider's actual step-quantized value to both the display and
runtime field. The project parse check passed; a focused movement check is pending.

The 15.2-cycle movement check passes all five modes with the new button present; the control panel
remains stable in size while values update. The scene still needs the user's live UI/visual verdict,
and `scripts/check.sh` passes. Gameplay/animation changes remain uncommitted.

The 2026-09-22 live test found visibly floating feet after the first stair-edge clip correction.
The old regression only asserted *minimum* shoe clearance, so it passed a shoe arbitrarily high
above its tread. The new planted-shoe maximum-gap assertion reproduced a 0.126 m hover. The cause
was feeding the previous frame's raised stance target into `maxf()`: clearance could rise but never
settle. Re-evaluating each planted ankle from its accepted tread height before applying the current
phase's shoe-depth clearance eliminates that accumulation. This exposed a later swing toe reaching
~0.233 m forward, so the forward probe/reserved tread envelope is now 0.24 m. Before the first
toe correction the measured final shoe entered a neighboring tread by 0.302 m;
the ankle-only stair check still passed. A planned ankle now stays inside the same 0.35 m tread's
usable interval (0.24 m toe reach, 0.10 m heel/marker clearance). The source rig sampler records
each phase's true skinned-shoe depth below the ankle; the moving stair target lifts only enough to
clear that shoe envelope over the current/next tread. The read-only marker depicts a smaller
0.18 m contact patch, while the regression checks the complete skinned shoe, not the decal.

Focused 480-frame Stair Up replay (nearly the full 12-tread climb): **PASS**, 1,209 shoe vertices,
worst clearance **+0.006 m** and highest planted-shoe gap **+0.006 m**, zero unsafe planned-contact
frames, 0.000 m plant error, and 21.1 deg/frame worst joint change (below the 30-degree limit).
The expanded replay caught a later -0.010 m swing-toe clip that the first 240 frames missed; the
new maximum-gap check caught the 0.126 m hover that the prior minimum-only regression missed.
`--flat-mesh-check` passes all eight flat cases;
`--infinite-check` passes all five modes over 15.2 cycles; `scripts/check.sh` passes. Do not call
the broader task complete: stair boxes remain visual-only, only the authored 0.35 m Stair Up
geometry is covered, and body/shin collision and arbitrary heights still need implementation.
Next: user live-tests 2-3 stair loops for a smooth toe, no visible floating/slide, and markers
fully on treads. Do not commit until that verdict.

The lab now has a **Spawn up + down stairs (3 m ahead)** button. It places twelve 0.35 m/0.18 m
ascending treads three metres ahead of the current character, a 0.70 m top landing, and twelve
descending treads. It keeps the selected gait and walks forward through the whole route, stopping
on flat ground at the end. The route is visual-only; no physics body or colliders were added.
`--course-check` presses the real UI button and replays every selectable gait, asserting the 3 m
placement, climb, descent, and completion, plus per-frame skinned-shoe clearance/contact. The
sampled shoe-shape envelope distinguishes toe from heel heights, and body descent begins smoothly
on the top landing. **Route PASS for all six modes. Shoe PASS for Walk, Sprint, and Crouch** in the
latest full-frame run: Walk minimum +0.003 m and planted maximum gap +0.012 m; Sprint +0.005/+0.028;
Crouch -0.003/+0.013. The regular Walk needed a reach-aware pelvis drop on the narrow ascent
treads plus validation against both neighboring source shoe-profile frames: its previous worst
toe clip was -0.155 m despite a safe planned target. Walk and Sprint need a 0.26 m toe reserve;
the shorter-foot modes retain 0.245 m to avoid needless edge-induced hover. The focused existing
Stair Up climb check still passes (+0.006 m minimum, +0.006 m gap, 21.1 deg/frame maximum).

**Still red:** Aim Walk clips only -0.007 m but floats +0.169 m at one ascent boundary (the
nearest sampled shoe envelope incorrectly anticipates a taller tread by ~0.18 m); Stair Up
reuses its ascent-only clip on the descent because no down-stair clip exists and has -0.044 m
toe clip/+0.068 m gap; Original clears the mesh but floats +0.226 m on descent. The course
checker exits nonzero for these pose-quality defects, despite every route completing. The next
design step is final-pose shoe/terrain validation or a better phase-specific profile, rather
than widening one global clearance margin. Need live visual verdict on the button, Walk/Sprint/
Crouch gait smoothness, and the known red cases. No gameplay/animation commit until the user's
live approval.

**Stair-step snap investigation (2026-09-23):** The course now automatically writes a bounded
per-physics-frame `user://procedural_walk_course.jsonl` capture (root/phase, hips correction,
both foot targets/contact/ankle/toe/knee, shoe-correction count, per-joint quaternion deltas,
named transitions). `scripts/procedural_walk_trace.py TRACE summary|worst|window|events` emits
compact findings without dumping JSONL. A headless Walk course captured 975 frames with zero
physics-tick gaps; three repeated right-leg spikes were 112-117 deg at contact onset before a
stable anatomical knee pole reduced them to <35 deg. A separate ~43 deg loop-boundary spike was
not a source animation seam: the pelvis reach-drop incorrectly checked the *full* remote plant
even when the current contact weight was ~0.07, then released a 0.25 m correction in one frame.
Checking reach to the same weight-blended target actually used by the leg solve removed that spike.
Using the solver's preferred knee-flex reach in the pelvis calculation reduced the remaining
joint maximum to ~29 deg while preserving full skinned-shoe clearance. **The visible ankle snap is
not yet fixed:** near toe-off, the skinned toe approaches the next riser while the ankle drifts
~3-4 cm ahead of its safe plant; the reactive clearance path raises it ~0.18 m in one frame.
The course checker now explicitly fails Walk on >8 cm single-frame ankle motion or >30 deg joint
motion; do not mistake its shoe PASS for a smooth-pose PASS. Next fix should shape the base
step/leg trajectory before the riser, not rate-limit the emergency clearance and leave a clip.
Live confirmation is required because the user saw the snap in the interactive scene.
The six-mode rerun still completes every route. Its new continuity measurements are diagnostic,
not yet graded for other modes: Aim Walk has a 112 deg joint step, Crouch 42 deg, and Stair Up
21 deg; each needs mode-specific trajectory assessment before declaring it smooth. The trace
writer records the modifier's final pass for each physics tick, buffers/replaces additional
same-tick passes, and the Walk replay had 975 records with zero missing ticks.

## Goal

Make every moving gait consume the shared footstep plan, then prevent the controlled character's
body, shoes, and leg swing paths from passing through stairs or other solid geometry.

The desired pipeline is:

```text
desired movement + source pose
             -> persistent validated footstep plan
             -> contact-weighted leg/pelvis solve
             -> final shoe/body clearance validation
             -> rendered pose
```

Imported animation remains the preferred full-body style. The plan becomes authoritative for root
travel and foot contacts; IK refines the leg chains without replacing the clip's upper body or
distinct walk/sprint/crouch character.

## Current baseline

- Original Walk and Stair Up already use the custom analytic two-bone solve and world-space plants.
- Moving UAL Walk, Aim Walk, Sprint, and Crouch publish three future contacts per foot and blend
  their leg chains toward accepted world plants during source-defined contact.
- Flat reference modes preserve all 73 sampled source bones in-place. Moving variants preserve the
  source upper body and shoe roll, with a small pelvis clearance offset and contact-corrected legs.
- The lab's staircase is visual-only geometry. Its known height function can position an ankle on a
  tread but cannot physically prevent a root, shoe, shin, or swing path from crossing a riser.
- The project must not use deprecated `SkeletonIK3D`; reuse the direct analytic solve.

## Architecture boundaries

- `ProceduralFootstepPlan`: accepted immutable world-space contacts only; no drawing or bone edits.
- Gait/contact controller: contact timing, swing phase, plan consumption, and root travel.
- Leg/pelvis solver: transforms a source pose toward the accepted contacts; no terrain queries.
- Clearance validator: terrain queries plus foot/body proxy tests; validates both destinations and
  swept paths before a target reaches the solver.
- `ProceduralStepPlanDebug3D`: read-only view of accepted, adjusted, and rejected proposals.
- Physics body: prevents root/body penetration. Do not use the deforming skinned mesh as a collider.

## Phase 1 - Make every flat gait consume its plan

1. Add explicit per-foot contact intervals to the sampled gait profile. A single forward-most ankle
   frame is enough to seed the current markers but not enough for smooth blend-in/out.
2. During stance, lock the ankle to the accepted world target with a smooth contact-weight curve.
3. During swing, follow a planned start-to-destination arc; preserve the source leg pose as the
   preferred bend/style rather than replacing it with one generic gait.
4. Blend shoe orientation toward the support plane and retain source heel/toe roll where clearance
   permits.
5. Coordinate pelvis height/translation so both legs remain reachable without moving a planted foot.
6. Derive root travel from the same gait/plan data, so changing speed cannot reintroduce shoe slide.
7. Release contact continuously at toe-off and acquire continuously before/at touchdown; never snap
   from exact source pose to full IK in one frame.

Initial modes: UAL Walk, MotusMan Aim Walk, UAL Sprint, and UAL Crouch. Treat Sprint's airborne phase
explicitly; do not force either foot onto the floor when the source gait has no contact.

## Phase 2 - Add real character and environment collision

1. Make a dedicated controllable prototype scene with `CharacterBody3D` plus a capsule (or similarly
   simple body proxy). Add real `StaticBody3D` + `BoxShape3D` collision for the authored stairs.
2. Keep visual meshes non-colliding. A deforming skinned mesh must not be used as the gameplay body
   collider.
3. Stop or slide the root against stairs/walls through normal body movement before pose generation.
4. Keep authored stair dimensions available to both rendering and collision from one source of truth.

## Phase 3 - Validate feet and swept swing paths

Use a small oriented foot proxy or explicit heel/sole/toe points. Validate:

- support exists under the intended sole;
- the complete shoe volume does not overlap a tread or riser;
- the target remains reachable and on the correct side of the body;
- the line/arc from swing start to touchdown stays clear at intermediate samples;
- the knee/shin do not cross the riser when a practical leg proxy is required;
- final post-solve shoe samples remain outside solid geometry.

If a proposal is invalid, try bounded corrections in this order: raise the swing arc, shorten the
step, shift it within the stance lane, delay the step, then reject/stop movement. Never silently pass
an invalid target to IK or invent unsupported ground.

## Debug presentation

- Accepted fixed contacts: existing left/right colors.
- Adjusted proposal: yellow, with the original optionally outlined.
- Rejected proposal or final penetration: red.
- Optional foot proxy and sampled swing arc.
- Display the reason (`unsupported`, `riser overlap`, `sweep blocked`, `unreachable`, `body blocked`)
  without making logging unbounded.

The debug component remains optional and read-only. Disabling it must not alter planning, movement,
IK, or collision.

## Regression coverage

Add focused checks as each phase lands:

- Every moving gait publishes six alternating targets and consumes exactly one per contact.
- Five retained queue entries remain bitwise/approximately unchanged after a contact.
- Planted ankle world drift, contact blend step, and per-joint angular change stay bounded.
- Walk/sprint/crouch retain their source upper-body pose and Sprint retains airborne frames.
- Root speed agrees with plan cadence and accepted step distance.
- Target and every sampled point on the swing arc clear tread/riser proxies.
- Final skinned shoe vertices (or the established mesh sampler) do not enter stair boxes.
- The capsule cannot translate through the staircase.
- Debug on/off produces identical locomotion metrics.
- Stop, restart, gait switch, stair-loop reset, and direction change clear/reseed the correct state.

Do not accept endpoint-only checks: a valid start and landing can still produce a shoe that cuts
through a riser between them.

## Live acceptance

- Feet remain visibly planted without horizontal skating during stance.
- No snap when contact IK engages/releases or when switching gait.
- Sprint still reads as Sprint rather than a grounded walk played quickly.
- The character, shoes, toes, shins, and knees do not visibly pass through the staircase.
- Invalid terrain causes an understandable shortened/raised/delayed step or movement stop.
- Markers remain stable and accurately predict the contacts the character actually uses.

## Non-goals for the first implementation

- Do not integrate with the gameplay Player or its existing Foot IK stack.
- Do not solve turning, strafing, jumping, and arbitrary moving platforms in the same patch.
- Do not add full skinned-mesh physics collision.
- Do not hide penetration by rendering the character offset from its physical body.
- Do not commit visual/animation behavior until the user tests it live and confirms the result.

## Flat-gait slice result

The four moving flat gaits use the shared contact plan and pass focused headless pose, mesh, and
sustained-plan checks. This covers the stance lock and source-preserving leg solve. The planned swing
arc, support-plane shoe orientation, shared pelvis reach, and terrain validation remain design work;
flat-ground success does not prove them. After live visual review, add the colliding stair prototype
and swept shoe/body validation in the isolated lab.
