# 033 - Portable procedural locomotion controller

Status: in progress. Phase 1 extraction implemented in the isolated gait lab; awaiting live review.
No gameplay Player integration until the portable prototype is controllable and visually accepted.

## Goal

Evolve `tests/manual/procedural_walk/procedural_walk_lab.tscn` into a controllable locomotion
prototype whose planning, pose generation, contact correction, and debug views are reusable character
components. Imported clips remain motion references; desired movement and the accepted footstep plan
become the locomotion authority.

```text
input -> desired movement -> gait/footstep planner -> root + full-body pose -> contact IK
                                      `-> optional character-attached debug view
```

## Boundaries

- Work in the isolated procedural-walk harness first; do not couple this experiment to gameplay Foot
  IK or replace `Player` movement incrementally behind its back.
- Extract one boundary at a time and keep the lab visually equivalent after every extraction.
- A planned step is immutable until consumed or explicitly invalidated by a future terrain/safety
  policy. Rendering, leg placement, and validation must read the same plan object.
- Debug rendering is optional and must never own or mutate locomotion decisions.
- Preserve whole-body reference comparison and final skinned-foot clearance checks.

## Milestones

1. **Portable plan and debug view** - shared `ProceduralFootstepPlan`; character-attached
   `ProceduralStepPlanDebug3D`; six persistent alternating targets; queue stability regression.
2. **Desired-motion input** - camera-relative direction, acceleration/braking, walk/crouch/sprint,
   stop and restart, with root speed derived from gait rather than independent translation.
3. **Directional gait** - turning and lateral/diagonal movement, committed-foot preservation, stable
   replanning of only uncommitted steps.
4. **Whole body** - pelvis/weight transfer, spine counter-motion, arms, acceleration lean, smooth gait
   and stop transitions.
5. **Terrain planning** - query flat/sloped/stair/uneven support before accepting a step; final IK
   refines contact rather than inventing locomotion.
6. **Controllable character scene** - reusable composition and input bindings, still isolated until
   live-tested against the gameplay character's required behavior.

## Phase 1 current result

The queue was extracted from `ProceduralWalkLabModifier` into
`procedural_footstep_plan.gd`. The modifier remains the gait-policy owner but consumes the same plan
object exposed to other components. `procedural_walk_step_predictor.gd` is now a `Node3D` attached to
the MotusMan character, bound only to the plan plus a surface-height callable; it processes and draws
itself and can be attached to another compatible character without the lab or raw-comparison helper.

All moving flat reference modes now populate that plan too. The reference bank samples each source
foot's forward-most ankle point as touchdown, combines its phase with that clip's measured cadence
and root travel, and seeds three immutable future contacts per foot. Crossing the corresponding
source contact consumes one entry and appends the same foot's next-cycle placement. This is
animation-derived anticipation, not the Original/stair procedural leg solve, but it predicts the
actual root-translated source pose rather than drawing a generic stride.

The stair acceptance check requires queue stability: between frames the six targets must be identical
or shift left exactly once with five accepted entries unchanged. Existing moving, infinite-travel,
pose-match, flat-mesh, stair, and project checks must remain green. Live acceptance: markers stay fixed
until consumed, one new far marker appears per landing, and disabling their display does not affect the
gait.

## Next

After live approval, add a separate desired-motion component and a controllable prototype scene. The
flat imported modes now consume their plan for touchdown events and moving foot contact through task
034's isolated analytic solve. Verify marker/contact alignment live before using those plans for
terrain decisions.
