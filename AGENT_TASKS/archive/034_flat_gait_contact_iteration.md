# 034 - Flat gait contact iteration, 2026-09-22

Historical measurements and corrections moved from task 034's current handoff. The active task
keeps only the current result and next action.

## Current handoff (update this section after every implementation step)

**Phase 1, slice 1 is implemented and automation-clean; live approval is next.** Moving UAL Walk now
derives touchdown/toe-off intervals from the source clip, consumes the persistent six-contact plan,
smoothly blends an analytic two-bone solve to each world plant, preserves source knee direction and
shoe roll, and leaves all non-leg bones untouched. Mid-stance startup captures the rendered ankle to
avoid a snap. Plan targets include the source mesh-clearance lift, and the pose target follows only
the source clip's floor-safe vertical heel/toe-roll offset while its horizontal plant stays fixed.
Aim Walk, Sprint, and Crouch still publish plans but intentionally do not consume them yet.

Automated evidence on 2026-09-22: the 120-frame pose check reports 0.0000 m planted error, 9.19
degrees/frame worst leg change, and <= 0.069 degrees/effectively zero positional upper-body change.
The moving Walk shoe remains at least +0.006 m above the plane (previous first attempt: -0.028 m).
All five plan queues remain stable across 15.2 cycles; moving and existing stair checks pass; and
`scripts/check.sh` passes. The next action is a 2-3-loop live comparison of moving **Walk (UAL)**.
If approved, apply the same contact-profile contract one mode at a time: Aim Walk, Crouch, then Sprint
(whose airborne interval must remain unplanted). Do not commit this visual behavior before approval.

**2026-09-22 continuation:** The user asked to continue. Slice 2 is MotusMan Aim Walk, which already
publishes a six-contact plan but has no rendered contact solve. Apply the existing Walk contact
pipeline to Aim Walk, check that a real planted interval is sampled for both feet, then measure the
same final shoe, upper-body, and joint-continuity metrics. The previous Walk result remains the
baseline. Update this handoff after each implementation/validation step; leave the visual change
uncommitted pending live review.

**Slice 2 step 1 implemented; validation pending.** Moving Aim Walk now uses the same plan-driven
contact solve as UAL Walk. Its source upper body is still copied directly; shoe orientation and
vertical heel/toe roll remain source-driven. The pose regression now requires at least 60 fully
weighted foot-frame samples across its 120-frame loop, so an empty contact interval cannot pass on
zero reported target error. The moving-mode UI identifies Aim Walk as contact-locked.

**Slice 2 step 2 pose check passes.** Across 120 frames, moving Aim Walk has 105 fully weighted
foot-frame samples, worst ankle-to-effective-target error 0.0001 m, worst leg rotation change 15.17
degrees/frame, and non-leg difference <= 0.079 degrees/0.0004 m versus the reference. UAL Walk and
all in-place/source-only modes also pass. Next check: actual skinned-shoe floor clearance.

**Slice 2 step 3 mesh check fails.** Moving Aim Walk's lowest skinned shoe vertex is -0.008 m
against the flat plane; its unmodified in-place pose remains +0.006 m. The planted ankle metric alone
missed this. Investigate the frame/side and whether midstance initialization is being treated as a
touchdown-anchored vertical plant before changing the solver or clearance budget.

**Slice 2 step 4 cause confirmed and correction in progress.** The worst penetration is left shoe
frame 15 at full contact weight. The safe source low point is +0.006 m, but the solved shoe is
-0.008 m. The active plant was captured when starting midstance; the roll-offset code subtracts
the clip's touchdown ankle height anyway. Record the source ankle height when each plant is
acquired, using the rendered ankle on midstance startup and the planned touchdown height for a
normal touchdown. Then offset subsequent source ankle motion from that plant-specific anchor.

**Slice 2 step 5 mesh check passes after plant-specific anchor.** Each active plant now stores the
source ankle height at acquisition; the current source heel/toe roll is relative to that height.
Moving Aim Walk's lowest skinned vertex is +0.006 m (was -0.008 m); UAL Walk and all untouched modes
also pass. Next action is to rerun pose continuity and long-run queue/movement checks, then the
canonical project check. Live visual review remains outstanding.

**Slice 2 step 6 pose continuity passes.** After the anchor correction, moving Aim Walk has 0.0001 m
worst full-contact error, 15.17 degrees/frame worst leg rotation, and 105 fully planted foot-frame
samples. Its non-leg source difference remains <= 0.079 degrees/0.0004 m. Walk, all in-place cases,
Sprint, and Crouch source-only cases also pass. Next run the long-cycle queue check, then proceed to
Crouch with the same focused pose and final mesh gates.

**Slice 2 step 7 long-cycle plan passes.** All five moving modes retained stable six-contact queues
over 15.2 cycles; Aim Walk traveled 17.94 m at its measured cadence. Slice 2 is automation-clean.
The next implementation enables contact IK for Crouch using the same plant-specific vertical anchor.
Aim Walk and UAL Walk remain available for live visual review and are still uncommitted.

**Slice 3 step 1 Crouch contact solve and pose check pass.** Moving Crouch consumes its plan through
the shared solve. In 120 frames, it has 114 fully weighted foot-frame samples, 0.0003 m worst
plant error, and 8.20 degrees/frame worst leg rotation; non-leg differences remain <= 0.373
degrees/0.0030 m versus the source. All other pose cases still pass. Next check: final skinned-shoe
floor clearance, then sustained plan stability.

**Slice 3 step 2 Crouch final shoe check passes.** Its moving skinned shoe stays at or above
+0.006 m, with 120/120 frames having a near-floor contact. Walk and Aim Walk remain clear.
Sprint is next. Before enabling its contact solve, measure whether the current source-derived
touchdown/toe-off interval assigns any contact weight during the clip's real airborne frames; if so,
the Sprint profile needs a ground-contact gate.

**Slice 4 step 1 airborne profile mismatch measured.** The existing Sprint interval weights an
airborne source foot in 36-38 of 174 airborne foot-frame samples per 120-frame cycle. It would
visibly pull a flying foot down. Add a Sprint-only source-shoe-height fade so weight reaches zero by
4 cm above the floor. Keep an accepted touchdown target valid through the zero-weight airborne
part; a temporary zero contact weight must not discard the plant before the same step touches.
The source sprint itself reaches 27.10 degrees/frame at this playback rate, so compare the contact
solve's step against that source baseline rather than applying Walk's 20-degree ceiling.

**Slice 4 step 2 first Sprint solve fails.** The height gate removes all 36-38 false airborne
contact samples, and 54 fully weighted samples remain. However, moving Sprint spikes to 64.85
degrees/frame against the unmodified source's 27.10, and its worst planted target error is 0.1824 m.
This is a real reach/plan mismatch, not merely a threshold issue. Keep the failure visible while
tracing the worst frame's target, current root/hip, and plant timing; do not ship the Sprint solve
until it meets the same final pose and shoe checks.

**Slice 4 step 3 reach evidence.** Worst full-contact error occurs at frame 87 on the left:
root Z -7.891 m, fixed plant Z -7.123 m (0.768 m behind the root), target Y 0.328 m.
The sampled Sprint touchdown/toe-off interval spans 0.45 cycle for each side
(left 0.85->0.30, right 0.40->0.85), while the current estimated root travel is
3.587 m/cycle. Next measure how far the source ankle actually travels between those endpoints;
that is the appropriate speed contract for a locked foot over this interval.

**Slice 4 step 4 source stance travel measured.** Left ankle moves 1.082 m and right 1.089 m
between touchdown and toe-off, each over 0.45 cycle. A planted Sprint foot therefore supports
about 2.41 m root travel/cycle, not the existing near-floor derivative estimate of 3.587 m/cycle.
The old estimate advances the body roughly 0.53 m too far during one locked stance and explains the
reach failure. Use the sampled contact endpoint displacement/duration for Sprint's root speed and
future-step spacing; keep the already accepted Walk/Aim/Crouch speeds unchanged.

**Slice 4 step 5 speed correction resolves reach but reveals knee-plane flip.** At 2.412 m/cycle,
Sprint's worst fully weighted target error falls from 0.1824 m to 0.0003 m, and 54 planted samples
remain. The worst leg frame is still 78.25 degrees against the source's 27.10, at left shin frame 6.
The shared source-knee pole can reverse near a straight leg when Sprint's contact solve changes the
ankle direction quickly. Try the same fixed native-forward anatomical knee plane already used by the
lab's Original gait, scoped to Sprint, then measure joint continuity and shoe clearance. Do not
weaken the joint budget.

**Slice 4 step 6 fixed Sprint knee plane helps but does not finish the handoff.** Worst leg change
falls from 78.25 to 39.10 degrees/frame while the target remains accurate (0.0003 m). The next
suspect is the source-height gate's rapid 0->1 contact acquisition during Sprint's fast vertical
landing. Inspect the first landing's weight and per-frame leg change before choosing a bounded
time/phase transition.

**Slice 4 step 7 release discontinuity identified.** The worst 39.10-degree step is frame 10,
when left contact falls from weight 0.68 to zero as the source shoe rises from 0.016 m to
0.073 m in one frame. The source clip is already about to lift at frame 8. Use a bounded forward
sample of its sole height to release the plant over the last few grounded frames, with zero contact
weight whenever the source sole is above 0.04 m. Keep the speed and stable knee-plane fixes.

**Slice 4 step 8 predictive release improves but remains slightly over budget.** An 0.08-cycle
lookahead drops the worst Sprint leg step from 39.10 to 32.43 degrees/frame, with 48 fully weighted
samples and no false airborne contact. The source step is 27.10, so the regression's source+5-degree
budget is 32.10; this still fails by 0.33 degrees. Extend the release interval modestly and record
the exact worst frame/bone before accepting the result.

**Slice 4 step 9 release timing is no longer the limiting frame.** With a 0.12-cycle release, the
early takeoff changes stay near 20.5 degrees/frame, but the worst remains 32.43 degrees at
left shin frame 118, on the next contact acquisition. The original source is 27.10 degrees/frame.
Inspect that landing's source sole height and contact weights; smooth acquisition separately from
the already controlled release. Full-weighted samples remain 39 and airborne contacts remain zero.

**Slice 4 step 10 acquisition discontinuity identified.** At frame 117 the descending left sole
is 0.041 m above the plane and receives zero contact; at frame 118 it is 0.017 m above the plane and
receives full weight, producing the 32.43-degree shin step. Add a Sprint-only partial acquisition as
the descending source sole enters the last 0.12 m above ground. The true airborne interval above
0.12 m must retain zero IK weight; release on ascent remains predictive and reaches zero by 0.04 m.

**Slice 4 step 11 Sprint pose check passes with near-ground acquisition.** A descending sole blends
into the plant over its last 0.12 m before contact; true flight above 0.12 m has zero IK weight.
Worst leg change is now 25.69 degrees/frame, below the unmodified source's 27.10 at this same
playback rate. Worst fully planted target error is below printed 0.0001 m, 39 fully weighted
foot-frame samples remain, and zero of 144 true-airborne samples have weight. Next validate the
final skinned shoe; contact error alone does not prove sole clearance.

**Slice 4 step 12 final shoe clearance passes.** Across the 120-frame final skinned-mesh check,
moving Sprint's lowest shoe vertex is +0.006 m, with 66/120 frames having a near-floor sole;
the source/in-place Sprint has 64/120. All Walk, Aim Walk, and Crouch variants also pass.
Temporary per-frame Sprint diagnostics can now be removed. Next validate sustained six-contact
plan stability and the revised Sprint root speed, then run the canonical project check.

## Final review follow-up

The existing Contact IK slider only affected the older procedural path. The flat reference
contact solve now multiplies its weight by the slider so 0 actually disables the correction.
The first 60-frame off-state check after Crouch -> Walk still differed by 5.76 degrees / 0.0285 m,
despite zero IK weight. The worst forearm's sampled Walk local pose and raw comparison rig differed
by 4.703 degrees: the comparison AnimationPlayer retained bones unkeyed by Walk from Crouch.
Resetting both the live comparison skeleton on clip switch and the private sampler before each
clip made the off-state check pass (0.056 degrees, effectively zero position, zero IK weight).
All flat pose and skinned-shoe checks, 15.2-cycle plans, the existing stair check, and
`scripts/check.sh` passed afterward. A first canonical check exceeded the lab's 1000-line limit
by one line; removing an obsolete header comment restored the limit before the passing rerun.
