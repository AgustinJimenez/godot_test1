# 017: Foot IK - balanced, weight-bearing stance pose

## Status and scope

**Minimal fix applied; further steps (torso counter-lean, support-polygon verification) still
open.** The both-feet-grounded branch of `_apply_support_pelvis_and_legs`'s `target_shift` now
weights the pelvis midpoint by `ground_weight`, matching the edge-asymmetric branch's own
existing formula (see "Research" section below) - verified against the full suite (`Passed: 41`,
no new failures). Not yet confirmed live against the specific stair-stance symptom that opened
this task (no manual playtest since applying it). The rest of this doc's investigation (torso
counter-lean as a separate layer, a real support-polygon check, whether a large foot-height
difference needs its own handling) remains open. Opened from a live user observation (playing
`foot_ik_preview.tscn`, standing on stairs): even after 014's pelvis-drop fix (unreachable
targets no longer float) and the `minimum_knee_pole_alignment` tightening (less sideways knee
drift), a two-footed stair stance with a large height difference between feet can still look
"weird" in the hip/legs specifically - not floating, not crossed, not twisted, but not reading as
a natural, balanced, weight-bearing stance either. This task is about diagnosing *why* a
geometrically-valid pose (correct joint order, good knee-pole alignment, both feet solidly
grounded per `sole_clearance`) can still fail to *look* balanced, and what to do about it.

## The concrete symptom that prompted this

A live trace frame (`foot_ik_controlled.jsonl`, captured mid-session): both feet grounded
cleanly (`sole_clearance` ~0 for both), right foot on a much higher tread (`target_owner=
landing_upper`). Decomposing the right foot's offset from its hip relative to the body's facing
direction showed roughly **equal parts forward and sideways** (~0.34m each) rather than a
mostly-forward step-up, with the thigh swung 63.7 degrees from vertical to reach it. Nothing here
is numerically invalid (reachable, correctly ordered, well-aligned pole) - the joint chain is a
technically-correct solution to "put the ankle at this target," but the *resulting silhouette*
doesn't obviously read as "a person supporting their weight while climbing," because nothing in
the solve was ever asked to care about that.

## What already exists (audit before building anything new)

`player_foot_ik_modifier.gd::_apply_support_pelvis_and_legs` already has a real, but limited,
weight-distribution mechanism - `target_shift`, applied as a lateral-only (XZ) pelvis nudge:

- **Edge-asymmetric case** (`is_edge_asym`: one foot hit, the other didn't): `com` is a
  `ground_weight`-weighted average of the two targets, and the pelvis shifts toward it (capped at
  0.35m via `limit_length`).
- **Both-feet-grounded case** (`elif not is_flat_idle and l_hit and r_hit`): the pelvis instead
  shifts toward the plain **unweighted midpoint** `(l_tgt + r_tgt) * 0.5` - no `ground_weight`
  factored in here at all, inconsistent with the edge-asymmetric branch right above it. This is
  the branch that governs the observed stair-stance symptom (both feet do have `hit=true`).

That's the entire "balance" mechanism today. It is horizontal-only, pelvis-only, and - in the
branch that matters for this symptom - not even weighted by how much each foot is actually
carrying. There is no:

- Torso/spine counter-lean (a real person reaching one leg far to a side or up typically leans
  the trunk to keep their actual center of mass over the support base - see `AGENTS.md`'s Foot IK
  section on the existing spine-twist precedent set by task 016's prototype work, a different
  mechanism but the same "counterbalance via the torso" idea).
- Any check that a computed pelvis position keeps the body's true center of mass within the
  polygon formed by the two foot contact points (the actual definition of "balanced" in
  biomechanics/animation) - `target_shift`'s midpoint is a cheap proxy, not a real containment
  check.
- Any special-casing for a *large* height difference between the two feet specifically (a shallow
  step and a steep stair currently go through the identical shift logic) - real weight shifting
  behavior is not linear in tread-height difference.

## Where to look for real reference material, not hand-derive

Per this repo's own established practice (`AGENTS.md`'s "Check engine source before
hand-deriving" precedent from earlier work): before inventing a balance heuristic from scratch,
check what a real, shipped system already does. Concrete candidates already touched by this
project's own history:

- **Real ALS** (already deeply read for `AGENT_TASKS/016`): `ALSCharacterAnimInstance.cpp`'s
  `SetPelvisIKOffset`/foot-IK pelvis handling was explicitly *not* ported in 016 ("this project
  deliberately replaces with this project's existing PlayerFootIKModifier") - but it was read
  once already, and may have a real, portable pelvis/weight-offset formula worth a second look
  now that this project's own pelvis system has grown independently.
- Standard game-animation foot-IK write-ups (Unreal's own two-bone IK + pelvis adjustment
  documentation, Unity's Final IK "AimIK"/"BipedIK" weight-distribution notes) generally frame
  this as: project the hip-to-ankle line for each leg onto the ground, weight each foot's
  contribution by its actual load (not just "is it touching"), and bias the pelvis toward the
  loaded side rather than a geometric midpoint of targets.

## Research: how real shipped systems solve this (no full physics/ragdoll)

None of these run a real physics center-of-mass solve per frame - every real, shipped two-bone-IK
system uses cheap proxies. Concrete, citable findings, cheapest-first:

- **COM proxy: just use the pelvis bone position.** No shipped foot-IK system computes a true
  mass-weighted COM. Unreal's IK Rig literally names the pelvis bone the "Character Root"/"Center
  of Gravity (COG)" bone ([IK Rig docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/ik-rig-in-unreal-engine)).
  Robotics' Linear Inverted Pendulum Model makes the same simplification for the same reason: hip
  lateral motion dominates true COM motion during biped stance/gait. This project already has the
  pelvis bone transform on hand every frame - free.
- **Pelvis weighting by "load": nobody uses real contact force.** Unity FinalIK's `BipedIK` pelvis
  solver exposes `Pos Weight`/`Rot Weight` driven mainly by leg-length error (pelvis drops to avoid
  over-stretch past `Min Leg Length`), not force
  ([FinalIK BipedIK](http://www.root-motion.com/finalikdox/html/page4.html),
  [Leg IK](http://www.root-motion.com/finalikdox/html/page11.html)). Unreal's own Control Rig
  pattern: `pelvis_target_z = min(left_foot_offset_z, right_foot_offset_z)`, then each foot's
  remaining local offset is `foot_target_z - pelvis_target_z`
  ([StraySpark procedural-IK writeup](https://www.strayspark.studio/blog/procedural-animation-ik-ue57-guide)).
  The practical substitute for "load" here is this project's own existing `ground_weight`
  (contact/settle confidence over time) - already computed, already the exact quantity the
  edge-asymmetric branch uses; the both-feet branch just needs to start using it too.
- **Torso/spine counter-lean is a separate layer, not solved jointly with leg IK.** Real
  contrapposto: the pelvis tilts toward the loaded hip, spine/shoulders counter-tilt the opposite
  way in an S-curve so COM stays over the support foot
  ([contrapposto](https://en.wikipedia.org/wiki/Contrapposto)). Game implementation
  (StraySpark, same source as above): a manual proportional counter-lean budget spread across
  spine bones (~5-25 degrees each), with the neck given an explicit opposite correction to keep
  the head/gaze level - applied as its own layer *after* leg IK resolves the pelvis, not inside it.
- **Support polygon, cheaply, for exactly two feet.** The real criterion (simplified from
  robotics' Zero Moment Point: "stable iff the ZMP/center-of-pressure falls inside the support
  polygon", [Wikipedia](https://en.wikipedia.org/wiki/Zero_moment_point)) collapses for a
  two-foot stance to "does the COM proxy's XZ projection fall between the two foot XZ positions,
  inflated by foot size" - no convex-hull math needed. Games use this only as a soft steering
  signal (lerp the pelvis toward that segment, load-weighted), never a hard solved constraint.
- **Nothing found using explicit mass-percentage tables** (e.g. "60% of mass above the hips") in
  any shipped two-bone-IK system - that level of detail belongs to full ragdoll/ZMP controllers,
  out of scope here.

Minimal concrete pseudocode synthesized from the above, directly applicable to this project's own
`target_shift` computation:

```gdscript
# both-feet-grounded branch: replace the plain midpoint with a ground_weight-weighted one,
# matching the edge-asymmetric branch's own existing formula (smallest, most defensible fix).
var com := (l_tgt * l_gw + r_tgt * r_gw) / maxf(l_gw + r_gw, 0.001)
target_shift = Vector3(com.x - pelvis_pos.x, 0.0, com.z - pelvis_pos.z).limit_length(0.35)
```

That single change directly closes the audit gap above (the both-feet branch not using
`ground_weight` at all) and is the cheapest, most conservative first step - before any new torso
counter-lean layer or support-polygon check, which are real but separate additions.

## Open questions to resolve before implementing anything

- **Answered by research, cheap and low-risk**: use the pelvis bone as the COM proxy (free,
  already available) and weight the both-feet-grounded branch's midpoint by `ground_weight`
  (already computed elsewhere in this file) - no expensive per-frame search needed, unlike the
  class of bug `014` already found and fixed twice in this exact file.
- **Still open**: does a torso/spine counter-lean belong in Foot IK at all, or is it a separate
  system? Research confirms real systems treat it as its own layer *after* leg/pelvis IK, which
  matches this project's own existing precedent (`prototype_spine_twist_modifier.gd` lives
  outside the real Foot IK stack, only in the ALS prototype) - suggests any counter-lean here
  should also be a separate modifier, not folded into `_apply_support_pelvis_and_legs`.
- **Still open**: is the "both feet grounded, large height difference" case common enough in real
  gameplay (versus only this synthetic stair-testing scenario) to justify going further than the
  minimal weighted-midpoint fix (e.g. a real support-polygon-segment lerp)?
- **Still open, and now more concretely answerable**: verification. Research gives a real,
  cheap, numeric definition to check against - "pelvis-proxy COM's XZ projection falls within the
  segment between the two foot targets, inflated by foot radius, load-weighted toward the more-
  loaded foot" - a new automated check could assert exactly that after any fix, the same way
  existing checks assert reachability/penetration/joint limits today.

## References

- `actors/player/player_foot_ik_modifier.gd::_apply_support_pelvis_and_legs` - the existing
  `target_shift`/`com` mechanism (both branches), lines ~889-928.
- `014_foot_ik_preview_scene_fps_collapse.md` - the pelvis-drop fix this symptom was found
  alongside; confirms the float/reach class of bug is separate from this balance question.
- `AGENTS.md`'s Foot IK section - the established caution around this file's history of
  regressions on seemingly-safe changes; any fix here should follow the same one-owner-at-a-time,
  full-suite-verify discipline already documented there.
- Research sources (see "Research" section above for what each contributed): [Unreal IK Rig
  docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/ik-rig-in-unreal-engine),
  [FinalIK BipedIK](http://www.root-motion.com/finalikdox/html/page4.html),
  [FinalIK Leg IK](http://www.root-motion.com/finalikdox/html/page11.html),
  [StraySpark procedural animation/IK UE5.7 guide](https://www.strayspark.studio/blog/procedural-animation-ik-ue57-guide),
  [Wikipedia: Zero moment point](https://en.wikipedia.org/wiki/Zero_moment_point),
  [Wikipedia: Contrapposto](https://en.wikipedia.org/wiki/Contrapposto).
