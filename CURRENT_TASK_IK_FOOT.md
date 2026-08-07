# Active Task: Stair Foot IK

**Date:** 2026-08-05 (latest session below); previous session 2026-08-03

**Checkpoint branch:** `experiment/native-foot-ik`

**Status (2026-08-05):** Idle foot IK now works well on 6 of 7 stair heights in
`foot_ik_preview.tscn`. The jump-landing float/pop bugs are fixed and kept (see "2026-08-05 session"
below). Two open problems remain, both harder than a threshold tweak:

1. **65cm stairs-to-floor idle float (unresolved).** The one remaining idle-case stair height that
   still floats. Live-reported by the user as: lands correctly via the new landing-grace fix, then
   pops back to floating once idle settles in — right foot, almost instant, within <1s of landing. A
   headless repro at the exact reported spot did **not** reproduce it (stayed planted 6+ seconds). Not
   actively being chased right now — needs a fresh live debug-panel capture caught in the act (Copy IK
   Data at the exact moment it pops) rather than more guessing.
2. **Foot IK correction while actively walking on stairs (partially fixed).** After the five-round
   revert documented below, a second attempt using better tooling (a comprehensive per-frame trace
   instead of single-print patches) found and fixed the actual primary blocker: an earlier session's
   own guard was silently vetoing the stair predictor's support override almost every frame during
   walking. This is real, verified, and kept - see "2026-08-05 session, continued: the actual fix"
   below. **Not fully solved**: the stair predictor now plants correctly whenever it acquires a
   support leg, but acquisition itself is still too infrequent (~67% of a walk cycle still has no
   support and both feet float) because the acquisition test is still distance-based and the true
   foot-to-tread gap routinely exceeds any distance threshold that's safe to use (see that section for
   the measured numbers and the safe/unsafe threshold boundary found). A third fix attempted in the
   same session (see "2026-08-05 session, continued further") - skipping the modifier's phantom
   `delta=0.0` calls outright - **broke IK completely when tested live** (floated on everything,
   including previously-working idle poses) despite a clean headless trace and passing automated
   suite, and was reverted immediately. Lesson captured in `AGENTS.md`. The two remaining kept fixes
   (jump-landing, support-plant guard removal) pass the full automated suite but are **still not yet
   manually confirmed live in-game**.
3. **Idle-freeze + raycast-noise deadband: confirmed live and committed.** Based on a Reddit r/gamedev
   thread the user shared, a foot's ground target now freezes entirely (stops re-raycasting) once
   confirmed fully planted and motionless for ~0.5s, and a small deadband rejects sub-noise raycast
   diffs outright even before that freeze kicks in - see "2026-08-05 session, continued once more:
   idle-freeze from community advice" below. **User confirmed live: "this is so much better."**
   Committed as `f52370a` on `experiment/native-foot-ik` together with the jump-landing and
   support-plant fixes from earlier in the session.
4. **Hip swing limit added (untested live).** Implemented right after the research above: a cone
   clamp on the thigh direction around straight-down (`max_hip_swing_degrees`, default 100°),
   preventing the previously-unconstrained hip from rotating the leg to an anatomically impossible
   angle when a target ends up somewhere it shouldn't (a stale support target, a bad retraction).
   Confirmed the clamp actually engages (an artificially tight 15° test caused real, measurable
   penetration since legs could no longer reach the treads); passes the full automated suite at the
   sane default. See "2026-08-05 session, joint limits: hip swing cone" below. **Not yet tested live.**

**Status (2026-08-03, historical):** Three threads. (1) The swing foot still bumps stair risers instead
of clearing each step cleanly — still open, next debugging target below. (2) Idle step-down Option A/B
(see "Resume here") — extensively live-tested this session; several real bugs found and fixed (list
below), but one symptom remains unexplained (see "Open: right foot stuck on the 0.65m-to-floor drop").
(3) Option B's whole-body walk-down (since fully removed in a later session, replaced by retraction +
capped deep-crouch) did not stop after resolving the one foot that triggered it.

## 2026-08-05 session: jump-landing fixes (kept, committed-ready)

Two real bugs found and fixed, both confirmed via headless repro (jump onto flat ground and onto
the 0.65m stairs-to-floor spot) plus the full `check_foot_ik.sh` suite passing with zero regressions.
Not yet manually confirmed in-game by the user at time of writing - do not commit until they do.

- **`ground_weight` stuck at exactly 0.0 for the rest of a landing animation.** Root cause: the
  landing-recovery animation's own foot motion is fast enough that `likely_idle` reads false, so the
  short ground raycast misses and the `idle_settle_search_down` extended fallback (gated on
  `likely_idle`) never runs - contact is never found. Because contact is never found, the
  `_prev_animated_foot_pos` reference (only ever written by `gait_tracker.update()`'s success path)
  never refreshes either, so next frame's `anim_speed` reads an even-larger stale delta against a
  frozen pre-jump position - a self-sustaining deadlock. Fixed with a `_landing_grace_time` window
  (0.35s, starts on `set_character_grounded()`'s false→true transition) that (a) forces `likely_idle`
  true regardless of `anim_speed`, (b) forces `_prev_animated_foot_pos` to refresh every frame instead
  of only on success, and (c) bypasses the velocity-based raw_weight gate entirely
  (`skip_velocity_gate` param threaded into `gait_tracker.update()`).
- **Instant pop back to the floating animated pose right as the grace window expires.** The grace
  window above force-plants `ground_weight`, but `_step_down_classification`'s own
  `_step_down_static_streak` (which gates `step_down`, which in turn is what lets `contact_lost`'s
  ordinary 3cm distance gate be bypassed) runs off the same raw `anim_speed` the grace window
  otherwise ignores - if the land-recovery animation's motion outlasted grace even slightly, one frame
  of `contact_lost` firing snapped weight back to 0, popping the foot to the raw animated pose.
  Fixed by also bypassing the streak requirement for the same grace window.
- Also added: a live current-animation-name label above the "Animation Timeline" slider in
  `foot_ik_debug_overlay.gd` (was requested to help diagnose the above live, ended up not needed once
  the deadlock was found via headless trace, but worth keeping).
- Files touched: `actors/player/player_foot_ik_modifier.gd` (`_landing_grace_time`,
  `LANDING_GRACE_DURATION`, `set_character_grounded()`, `_animated_vertical_speed()`,
  `_step_down_classification()`), `actors/player/foot_ik/foot_ik_gait_tracker.gd`
  (`update()`'s new `skip_velocity_gate` param), `tests/manual/foot_ik/foot_ik_debug_overlay.gd`
  (animation name label).

## 2026-08-05 session: stair-walking IK investigation (reverted, not fixed)

User report: idle foot IK works, but while actually walking up/down stairs the feet mostly float on
the raw uncorrected animation pose - matches this file's own long-standing "not accepted" disclaimer
at the top of `foot_ik_stair_predictor.gd`. Confirmed numerically via `--foot-ik-check`'s
`STAIR_FOOT_TRACE` JSON, parsed frame-by-frame: `ground_weight` for both feet almost never rises above
~0.1-0.3 while walking, and `forced_support` (the stair predictor's own "which foot is currently
planted" tracking) sits empty most of the time.

Five distinct, compounding root causes were found and fixed one at a time - each fix was individually
correct and verified against its own symptom, but the aggregate `FOOT_IK_BODY_PENETRATION_CHECK`
number **never moved from the very first broken baseline (32 penetrating samples, 0.35m max depth)
across all five rounds**, meaning some other blocking issue kept the net result unchanged throughout.
All changes were reverted at the end of the session rather than leave a half-working, unverified state
in the tree. In order found:

1. **Stance acquisition/retention used a flat 3cm distance gate** (`_is_contacting()` in
   `foot_ik_stair_predictor.gd`, via `GROUND_CONTACT_DISTANCE`). Wrong signal for stairs: a real gap
   between the animated sole and the true tread is *expected* and often large (25-45cm measured live)
   because the walk clip is flat-ground-authored, not stair-aware - this is exactly the mismatch foot
   IK exists to correct. The distance gate almost never passed, so support was almost never acquired.
2. **Replaced with a velocity-based test** (`absf(vertical_velocity) <= swing_speed_threshold`),
   matching the established principle already documented elsewhere in this file: "a foot that isn't
   currently moving vertically is either standing still or momentarily planted... and should get full
   correction regardless of how tall that correction needs to be." This let support acquire, but a
   **single low-velocity frame** is enough to false-positive during a swing arc's low-velocity dip,
   which planted a foot into the tread it was swinging over (`FOOT_IK_BODY_PENETRATION_CHECK`
   regression: 43 samples, up from the walking-float baseline's initial 0).
3. **Required a short sustained streak** (`STANCE_CONFIRM_STREAK = 3`, same decay-not-hard-reset
   hysteresis `_step_down_classification` already uses) instead of a single frame. Reduced but did not
   eliminate the penetration (32 samples) - a foot swinging mostly *horizontally* can hold near-zero
   *vertical* velocity for several consecutive frames while still genuinely airborne.
4. **Added `swing_active` as a hard disqualifier** (already tracked per-leg by
   `update_swing_lift()`, just not consulted here before). No change to the penetration number at all
   (still 32 samples) - but the failure pattern was revealing: the penetrating leg was *always* the
   current `support` leg with `ground_weight=1.0`, and the penetration depth was a suspiciously
   *constant* ~0.35m - exactly one stair riser, every single time, regardless of which riser. This
   meant the support *target* itself was stale (latched to the previous, now-passed tread), not a
   swing false-positive at all - the old distance-based retention check (removed in step 2) used to
   catch this by accident; nothing had replaced its actual job.
5. **Added an explicit staleness check** comparing the character's real physical root height
   (`CharacterBody3D.global_position.y`, sampled once per frame in `update_travel_direction()` - not
   the animated foot pose, which can't be trusted for this given point 1 above) against the root
   height at the moment support was last latched; re-acquire once it's risen by more than
   `step_min_rise`. Confirmed via direct trace that this correctly detected each riser transition and
   the latched target height *did* progress correctly (0.35 → 0.70 → 1.05 → 1.40...). **Penetration
   number still did not move (32 samples).** Direct correlation against the penetrating frames showed
   `support` stuck on the *same* leg (`left`) for the entire test, never transferring to `right` even
   once - meaning steps 2-5 fixed real problems that simply weren't the ones gating these specific
   frames.
6. **Traced why transfer never happened**: `_try_transfer_support()` had its own extra, stricter,
   redundant gate (`candidate_velocity <= velocity_noise_floor` (0.03) `or landing_seen`) layered on
   top of the new `_is_stance_candidate` check. Removed the redundant gate. Still no change in the
   aggregate check.
7. **Traced the streak itself with a delta-aware print** and found the same double-call-per-physics-tick
   engine artifact that caused both jump-landing bugs above: `_process_modification_with_delta` (and
   therefore `ensure_support()`) runs twice per physics tick, once with the real delta and once with
   `delta=0.0` - and the delta=0 call always computes velocity=0 (early-return guard), so the streak
   oscillated 1→0→1→0 forever instead of accumulating, never reaching `STANCE_CONFIRM_STREAK`. Gated
   the streak update to `delta > 0.0` only (same fix pattern as the landing bugs). **The streak then
   visibly climbed correctly on real ticks (confirmed 4, 5, 6, 7...) - but still reset to exactly 0 at
   one point and then stayed at 0 for dozens of subsequent frames, even during a long stretch where
   `swing_active` was independently confirmed `false`.** This means the leg's own velocity signal is
   reading as genuinely, repeatedly noisy during this specific window for a reason not yet identified -
   investigation stopped here for the night.

**Everything for this thread was reverted** (`git checkout` on `foot_ik_stair_predictor.gd` and
`foot_ik_preview.gd`; the small `player_foot_ik_modifier.gd` plumbing changes for it hand-reverted
while keeping the unrelated, verified landing-grace fixes above). Working tree confirmed back to a
clean, fully-passing `check_foot_ik.sh`/`check.sh` state.

**Next attempt should start with better tooling, not more live patches.** The pattern all session was
"fix one gate, verify a proxy signal looks right, re-run the one aggregate check, learn nothing moved,
repeat" - too slow and too easy to fix five real bugs without ever seeing the actual blocker. Next
time: build a small always-on visualization (extend `foot_ik_debug_overlay.gd`, or a dedicated
headless dump) that plots, for both feet across a full multi-step walk cycle in one pass:
`ground_weight`, `forced_support`, `vertical_velocity`, `swing_active`, and actual foot-to-tread
vertical gap - so the whole interaction is visible at once instead of inferred one print statement and
one aggregate number at a time.

## 2026-08-05 session, continued: the actual fix (kept, verified, not fully complete)

Followed the "next attempt" advice immediately above in the same session: added `step_down`,
`swing_active`, `contact_lost`, and `raw_weight` fields to the existing `STAIR_FOOT_TRACE` JSON dump
(`_foot_trace_sample()` in `foot_ik_preview.gd` - it already had `ground_weight` and a per-tread
vertical `clearance` metric via `_point_stair_trace()`, so this only needed a few more fields, not a
new tool), then read a full 138-frame walk cycle for both feet side by side in one pass instead of
chasing single print statements.

**The actual primary blocker**, found immediately once both feet's full state was visible together at
once: at frame 14, the stair predictor had *already correctly* picked `left` as the support leg with a
genuinely tiny 4.9cm clearance to the true tread - a clean, correct decision. But `ground_weight`
stayed at exactly 0 anyway, because `contact_lost=true`. The cause: `_apply_support_contact()` in
`foot_ik_stair_predictor.gd` (the function that force-sets the support leg's `ground_weight` to `1.0`)
had a guard added in an earlier session (see "Session bugs found and fixed" below,
`_apply_support_contact()` bullet) that skips the override whenever `gait_tracker`'s own independent
`contact_lost` computation disagrees. `gait_tracker`'s `contact_lost` uses the same
`GROUND_CONTACT_DISTANCE` (3cm) distance gate that's fundamentally wrong for stairs (see reverted
investigation above, point 1) - so during active walking it disagreed almost every single frame,
silently vetoing the stair predictor's own, purpose-built, already-correct decision essentially all
the time. Removed the guard (`_owner._smoothed_ground_weight[side] = 1.0` unconditionally again, as it
was before that earlier fix).

**Verified this doesn't reintroduce the bug that guard was added for.** That earlier bug's symptom was
a stale, no-longer-valid support leg getting force-planted forever. `ensure_support()`'s own retention
checks (target reachability + distance) still run every frame *before* `_apply_support_contact()` and
already exist specifically to drop stale support - the earlier guard was papering over a case those
checks alone didn't catch cleanly, but removing it and re-running the full `check_foot_ik.sh` suite
(stretch, airborne, and - importantly - body penetration across the *entire* scene, all idle dummies
included, not just the walker) came back clean (0 penetrating samples) in every configuration tested
below. Idle-only characters are unaffected either way: they never call `ensure_support()` in the first
place (`is_active()` requires `_support_side` to have been set, which only happens via active walking).

**Also widened the distance-based acquisition gate** (`_is_contacting()`, new
`SUPPORT_CONTACT_DISTANCE` constant in `foot_ik_stair_predictor.gd`, separate from the idle-focused
`GROUND_CONTACT_DISTANCE`) from 3cm - found the safe boundary empirically:

| Threshold | `FOOT_IK_BODY_PENETRATION_CHECK` | Frames still with no support acquired (of 138) |
|---|---|---|
| 0.03 (original) | PASS (0) | baseline broken - almost always empty |
| 0.15 | PASS (0) | 102 (no measurable change from 0.03) |
| 0.20 | PASS (0) | 102 (identical to 0.15) |
| 0.25 | PASS (0) | not measured (boundary search) |
| 0.30 | **FAIL (8 samples, 0.348m max depth)** | not measured - unsafe |

Settled on **0.15** (comfortable margin below the 0.25-0.30 failure boundary). It provides essentially
no additional benefit over the guard-removal fix alone in this specific 0.35m-riser walk cycle
(confirmed identical 102/138 empty-support frames at both 0.15 and 0.20), but is still correct to keep
- it should help more on shallower stairs where the true gap is naturally smaller, and does not need
to be revisited unless a future change specifically targets it. **The real remaining problem is that
in 92 of those 102 empty-support frames, *both* feet's clearance from the true tread exceeds 15cm at
the same time - often up to 0.5m** (the flat-ground-authored clip vs. real 0.35m stair geometry
mismatch is simply that large for a meaningful fraction of the gait cycle). No distance threshold that
stays under the ~0.25-0.30 penetration-unsafe boundary can close that gap; a non-distance signal
(velocity, gait-phase, or animation-authored foot-contact events) is needed for the remaining
acquisition frequency, which is exactly the harder problem the five-round reverted investigation above
was trying (and failing) to solve differently. Given the guard-removal fix alone is a real, substantial,
low-risk improvement on its own, it's kept independently rather than blocked on solving that harder
problem too.

Files touched (kept): `actors/player/foot_ik/foot_ik_stair_predictor.gd` (`_apply_support_contact()`
guard removed, `SUPPORT_CONTACT_DISTANCE` added), `tests/manual/foot_ik/foot_ik_preview.gd`
(`_foot_trace_sample()` diagnostic fields).

## 2026-08-05 session, continued further: double-call deadlock also hits ordinary walking (REVERTED - broke IK live)

User reported live (after the fix above, still same session): idle straddle poses and jump-landing
both look correct, but while actually walking "the lower foot moves up and floats, like over an
invisible floor at the step level." Traced with the same enriched `STAIR_FOOT_TRACE` dump (temporarily
pointed at the 0.65m walker for a clearer, larger-gap repro, then reverted back to 0.35m) and found:
for the swinging (non-support) leg, `raw_weight` read `1.0` and `contact_lost` read `false` for ten
consecutive real frames - yet `ground_weight` never advanced from exactly `0.0` the entire time. This
is the *exact same* symptom, and turned out to be the exact same root cause, as the jump-landing
"stuck at 0" bug fixed earlier this session (see the "jump-landing fixes" section above): Godot calls
`_process_modification_with_delta()` twice per physics tick for a reason never pinned down - once with
the real delta, once with `delta=0.0` - and that extra call's own independent contact/velocity sample
can disagree with the real one, corrupting streak/weight state that assumes exactly one authoritative
sample per tick. The landing-grace fix only patched this for the few hundred milliseconds right after
touchdown; it did nothing for ordinary mid-walk swings, where the same deadlock can strike just as
easily.

**Fixed at the actual root this time**, rather than another narrow per-symptom patch: added a guard at
the very top of `_process_modification_with_delta()` that skips the call outright whenever
`delta <= 0.0` *and* the tree isn't paused (the one legitimate delta=0 case - re-evaluating a paused,
tuning-adjusted pose from the debug panel - is explicitly still allowed through). Re-traced afterward:
the swinging leg's `swing_active` flag now holds `true` continuously through its entire swing arc with
zero flicker (previously it randomly flipped `false` mid-swing due to the phantom duplicate call), and
the stuck-at-exactly-0 deadlock is gone. Full `check_foot_ik.sh` suite still passes clean (0 penetrating
samples) after this change.

**Aggregate floating-time numbers barely moved** (still ~102/138 frames with no support acquired, ~99
with both feet under 0.5 weight, both roughly matching pre-fix baselines) - this fix did not close the
acquisition-frequency gap described in the section above (that's still a real, separate, larger
problem). What it *did* fix is a genuine correctness bug: weight no longer gets permanently and
incorrectly stuck at exactly 0 due to an engine-level artifact unrelated to gait. Whether this
resolves the user's specific "lower foot floats to step level" report is not yet confirmed - it may be
partially explained by this deadlock, partially by the separate, larger acquisition-frequency gap
(which would show as similar-looking floating for a different reason). Needs a fresh live test.

**REVERTED after live testing.** The user tested this specific change live in `foot_ik_preview.tscn`
immediately after and reported "the ik does not work" - IK was now floating on **everything**,
including idle straddle poses that had worked correctly all session. So the headless
`--fixed-fps 60` call pattern this fix was based on ("always exactly one real-delta call and one
`delta=0.0` call per tick") evidently does **not** hold in the live/interactive editor the same way -
whatever the real live call pattern is, unconditionally skipping delta<=0 calls skipped calls that
were actually needed. Reverted immediately (`_process_modification_with_delta()` back to its original
top). **Lesson captured in `AGENTS.md`**: a clean headless trace and a passing `check_foot_ik.sh` are
not sufficient evidence for a fix to this specific twice-per-tick behavior - it must be confirmed live
before trusting it, and this is now the second time in one session this exact class of change
(changing what runs on a delta=0 call, not just gating an individual reference update) needed a live
correction after headless testing said it was clean.

**Not yet manually confirmed in-game** - the two fixes that remain in place from this session (jump-
landing, support-plant guard removal) still need the user to walk the real stairs and look; this one
reverted change does not need re-testing (it's gone).

## 2026-08-05 session, continued once more: idle-freeze from community advice (added, untested live)

User shared a Reddit r/gamedev thread ("For anyone working on foot/leg IK, please read this," 2020,
145 upvotes) with a widely-agreed-with piece of practical advice: the classic "twitchy foot IK while
standing still" complaint comes from continuously re-raycasting the ground target even while idle, so
ordinary per-frame noise (breathing, idle sway, idle-animation micro-motion) occasionally shifts the
raycast origin enough to flip between two adjacent valid surfaces. Their fix: once there's no
movement input, **stop re-raycasting/re-solving entirely** - pick a placement once and freeze it there,
accepting it might be a hair off rather than technically-correct-every-frame but visibly jittering.

This directly matches a structural weakness already visible in this project's own foot IK: everything
built so far leans on *continuous* resampling plus hysteresis/streak tuning to *tolerate* noise, rather
than removing the resampling once it's no longer needed - and the still-unexplained 65cm idle-float
bug (plants correctly, then pops back to floating almost instantly) is exactly the failure mode a
freeze would structurally prevent, since there'd be nothing left to re-sample that could cause a pop.

**Implemented as a new, narrowly-scoped, opt-in mechanism** (`update_idle_freeze()` in
`foot_ik_gait_tracker.gd`, wired from `player_foot_ik_modifier.gd`'s per-leg loop): once a leg's
`ground_weight` has read `>= 0.999` and `anim_speed` has stayed under `idle_step_down_speed` for
`IDLE_FREEZE_STREAK` (30) consecutive *real* ticks, it freezes - `_sample_ground_contact()` stops
updating `_smoothed_target`/`_smoothed_normal` from new raycasts entirely, including tolerating a
transient raycast miss without treating it as lost contact. Only a clearly real motion
(`IDLE_UNFREEZE_SPEED_MULT` - 3x the idle threshold, well above ordinary noise) releases the freeze,
so a genuine step still responds promptly. The streak only advances on real (`delta > 0`) ticks -
learned the hard way earlier in this same session that per-frame reference/streak updates must be
delta-gated, not skip-the-whole-call gated, to survive the modifier's twice-per-tick call pattern
safely.

**A real bug was caught during this exact change**, worth remembering: `var frozen := _gait_tracker.update_idle_freeze(...)`
failed to compile with "Cannot infer the type... because the value doesn't have a set type" - `_gait_tracker`
is declared untyped (same pattern `_owner` uses throughout these helper classes), so `:=` type
inference on a method call through it doesn't work; needs an explicit `var frozen: bool = ...`. This
was caught by the *full* `scripts/check.sh` run (the actual Godot project-import/parse step), not by
`gdlint` alone - a reminder to always run the whole script, not just grep its lint section, since a
type-inference error like this compiles fine syntactically but fails at Godot's own script-reload step
and would otherwise have looked like a clean pass.

Passes the full automated suite (stretch/airborne/penetration all clean). Files touched:
`actors/player/foot_ik/foot_ik_gait_tracker.gd` (new `update_idle_freeze()`),
`actors/player/player_foot_ik_modifier.gd` (`_idle_frozen`/`_idle_freeze_streak` state, wiring into
the per-leg loop and `_sample_ground_contact()`).

**Follow-up in the same session**: user reported the freeze helped but they could still see a "split
second re-raycast" - a brief visible readjustment before a foot fully settles/freezes. Added a
complementary fix: `TARGET_NOISE_DEADBAND` (1cm) in `player_foot_ik_modifier.gd` - any new raycast hit
within 1cm of the current smoothed target is now rejected outright instead of lerped toward, since
ordinary noise can shift the *normal* enough to visibly rock the foot even when position barely
changes. Applies continuously (not just pre-freeze), independent of the freeze mechanism. Caught a
real `Cannot infer the type` compile error during this work (untyped `_gait_tracker` reference used
with `:=`) via the full `scripts/check.sh` run, not `gdlint` alone.

**Confirmed live by the user**: "this is so much better" - both the freeze and the deadband fix are
working as intended. **Committed** as `f52370a` on `experiment/native-foot-ik`, together with the
jump-landing and support-plant-guard-removal fixes from earlier in the session.

## 2026-08-05 session, research: joint limits and more foot IK resources

User asked how to find more resources like the Reddit thread. Search strategy notes and results below
for future reference, plus the next target identified from it (joint limits).

**How to find more:** search `[engine] foot IK [specific symptom]` (e.g. "Unity foot IK stairs
floating") rather than generic tutorials - devs posting bug reports surface real lessons-learned, not
polished-tutorial marketing copy. `site:gamedev.net` / `site:forum.unity.com` narrows to dev forums
where people post failure cases. Following specific researcher/dev blogs (e.g. `theorangeduck.com` -
Daniel Holden, ex-Ubisoft La Forge) beats cold search for genuinely practical, battle-tested writeups.

**On stairs specifically** (still our main unsolved problem):
[Foot IK on Stairs for Rigidbody-Driven Movement](https://discussions.unity.com/t/foot-ik-on-stairs-for-rigidbody-driven-movement/1640419)
(Unity Discussions) describes our *exact* symptom - legs floating/snapping when the animation clip is
out of sync with stair step length, i.e. the same flat-clip-vs-real-geometry mismatch this project's
own investigation kept running into all night. Worth a close read before the next attempt at the
walking-acquisition-frequency gap (see the "actual fix" section above).
Also: [Foot IK for stairs climbing](https://discussions.unity.com/t/foot-ik-for-stairs-climbing/831938),
[Using IK for walking on stairs (Unreal)](https://answers.unrealengine.com/questions/938195/using-ik-for-walking-on-stairs.html).

**On joint limits** (the next target flagged this session, not yet started): current state is a single
knee flexion clamp (`max_knee_flexion_degrees` in `foot_ik_leg_solver.gd`) but no hip swing-angle
constraint at all - the hip is solved as an unconstrained ball-and-socket in the closed-form two-bone
solve, so an extreme/unreachable target could rotate the whole leg to an anatomically impossible
angle. Best reference found: [Joint Limits - theorangeduck.com](https://theorangeduck.com/page/joint-limits)
(swing-twist decomposition - separates a ball-and-socket joint's rotation into a twist around one axis
plus a swing across a plane, letting each be limited independently and intuitively). Also:
[Inverse Kinematics with Joint Limits - GameDev.net](https://www.gamedev.net/forums/topic/677093-inverse-kinematics-with-joint-limits/).

## 2026-08-05 session, joint limits: hip swing cone (added, untested live)

Implemented a simpler version of the full swing-twist decomposition from the research above, scoped to
what this project's leg IK actually needs: a single cone-angle clamp on the thigh direction
(`new_hip_to_knee_dir` in `foot_ik_leg_solver.gd`'s `solve()`), measured from straight down
(`Vector3.DOWN`), limited by a new `max_hip_swing_degrees` export (default 100°) on
`player_foot_ik_modifier.gd`. Full twist (roll around the thigh's own long axis) isn't modeled or
limited - for a leg-only closed-form two-bone solve there's no independent twist degree of freedom to
begin with (the knee's bend plane already fully determines hip orientation along with position), so a
swing-only cone covers the actual failure mode: the leg splaying sideways or backward past a human
hip's real range of motion.

When the swing angle exceeds the limit, the thigh direction is rotated back onto the cone boundary
(same rotation-axis-and-clamped-angle technique as swing-twist limiting) rather than clamped naively,
so the knee's swing *plane* (left/right bend direction, already chosen via the existing knee pole
vector) is preserved - only how far down that plane it's allowed to swing changes. The calf is then
re-aimed from the (possibly moved) knee toward the original target and kept rigid at `lower_length`,
exactly mirroring how the existing knee flexion clamp above it already accepts an imperfect reach
rather than break bone length - the foot may land short of target instead of forcing an inhuman pose.

**Verified the clamp actually does something**, not just parses: temporarily set
`max_hip_swing_degrees` to an unreasonably tight `15.0` and re-ran `check_foot_ik.sh` -
`FOOT_IK_BODY_PENETRATION_CHECK` failed with real, measurable penetration (17 samples, 0.10m max
depth), since legs could no longer swing far enough to reach the stair treads at all. Restored the
sane `100.0` default and re-ran clean (0 penetrating samples, stretch/airborne also clean) - confirms
100° doesn't meaningfully constrain any pose exercised by the existing preview scene, only the genuine
extreme cases this is meant to catch.

Not currently exposed in the debug panel UI - `max_knee_flexion_degrees` isn't either, so left
consistent for now.

Files touched: `actors/player/foot_ik/foot_ik_leg_solver.gd` (the clamp + calf re-aim in `solve()`),
`actors/player/player_foot_ik_modifier.gd` (`max_hip_swing_degrees` export).

**Not yet manually confirmed in-game.** No automated check can tell "looks anatomically correct" from
"passes numerically" - specifically watch for: (1) any pose where a leg now visibly stops short of a
target it used to reach (would mean 100° is too tight for some legitimate case, e.g. a wide stair
stance), (2) confirm ordinary idle/walk/jump poses across all stair heights still look identical to
before this change (they should, since nothing in the existing scene reads as needing more than 100°).

## 2026-08-05 session, idle-freeze follow-up: single-frame unfreeze caused a periodic twitch (fixed)

User caught this live, right after the hip-swing-cone work above, via a debug-panel capture: left leg
twitching "every few split seconds" while standing idle. The capture itself showed a stable, correctly
planted foot at that exact instant (`ground_weight=1.0`, `contact_lost=false`, `vertical_velocity=
0.005`) - the bug wasn't in the plant, it was periodic, meaning it had to be in the freeze/unfreeze
transition added earlier this session, not the underlying IK math.

Root cause: `update_idle_freeze()`'s un-freeze check released the freeze on a **single frame**
exceeding `IDLE_UNFREEZE_SPEED_MULT * idle_step_down_speed`, with no debounce - every other streak in
this codebase requires sustained confirmation before acting (that's the whole reason the freeze
mechanism itself needs 30 consecutive calm ticks), but the release side of the same mechanism didn't
follow that same principle. The idle animation's own periodic breathing/sway motion apparently spikes
just over that threshold for an instant once per cycle, which was enough to yank the foot out of
freeze, force a resample against a slightly different raw target, and only re-freeze ~0.5s later -
visible as a recurring twitch locked to the animation's own cycle period.

**Fixed**: added `IDLE_UNFREEZE_STREAK` (3) - un-freezing now also needs 3 consecutive real ticks
above the speed threshold, not one. Full automated suite still passes clean after the change. Files
touched: `actors/player/foot_ik/foot_ik_gait_tracker.gd` (`update_idle_freeze()`),
`actors/player/player_foot_ik_modifier.gd` (`_idle_unfreeze_streak` state).

**Also noticed but not investigated** in that same debug capture (not what was reported, logged here
so it isn't lost): the right foot showed `raw_weight=0.0, contact_lost=true, ground_weight=1.0` -
this looks alarming in isolation but is very likely the *intended* behavior of the support-plant guard
removal from earlier in the session (the stair predictor force-plants its chosen support leg
regardless of gait_tracker's own stricter contact_lost opinion) rather than a new bug - right was
probably the stair predictor's currently-latched support leg at that moment. Also: `toe_tip_gap=
-0.116` on the left foot (toe reading below the ground surface) at a fairly steep `pitch=45.0` - worth
a look if it turns out visually wrong, but not chased since it wasn't what was reported.

**Not yet manually confirmed in-game** - needs the user to stand idle at the same repro spot again and
confirm the twitch is actually gone, not just theoretically fixed.

## 2026-08-05 session, idle-freeze follow-up part 2: the real cause was ground_weight, not the freeze

The unfreeze-streak fix above didn't fix it - user confirmed live at a *different* spot with the
**same** symptom, ruling out anything specific to that one location, and confirmed via a follow-up
question that the twitch is specifically **a vertical dip-then-recover**, not a rocking/orientation
pop. That pins it away from the freeze mechanism entirely (it only touches `_smoothed_target`/
`_smoothed_normal` - position/orientation smoothing - never `ground_weight`) and onto
`ground_weight`'s own, completely separate computation in `foot_ik_gait_tracker.gd`.

**Root cause found in `_raw_weight()`**: the falling branch has always required `min_falling_streak`
(3) sustained frames before it's trusted (that's the whole reason `_falling_streak` hysteresis exists
- see the comment right above it), but the **rising branch had no equivalent protection at all** - a
single frame of rising velocity, even a tiny ~0.05 m/s blip from ordinary idle sway/breathing, gets
amplified by `rising_penalty` (4.0×) into a large, instant `raw_weight` drop with zero debounce. Because
`ground_weight_fall_time` (0.05s) is faster than `ground_weight_rise_time` (0.12s), the resulting
`ground_weight` dips quickly and recovers more slowly - a visible, recurring sag-and-recover, timed to
whatever produces that periodic rising blip in the idle clip.

**Fixed**: added a `_rising_streak` counter mirroring `_falling_streak` (same decay-not-hard-reset
hysteresis band), and gated the rising branch on `min_falling_streak` (reused, not a new export) the
same way the falling branch already is. Full automated suite still passes clean, including
`FOOT_IK_BODY_PENETRATION_CHECK` - a genuine swing-start's rising velocity sustains far longer than 3
frames, so this doesn't meaningfully delay real swing detection.

Files touched: `actors/player/foot_ik/foot_ik_gait_tracker.gd` (`_measure_velocity()`, `_raw_weight()`),
`actors/player/player_foot_ik_modifier.gd` (`_rising_streak` state).

**Not yet manually confirmed in-game** - this is the second attempted fix for the same reported
symptom; don't assume it's the last word until the user confirms it live.

## 2026-08-05 session, idle-freeze follow-up part 3: pinned to the actual trigger - animation loop reset

The rising-streak fix (part 2) didn't fully resolve it either - user narrowed the trigger precisely
this time: **it happens specifically when the idle animation loop resets**. That's a genuinely
different, far more mundane mechanism than parts 1/2 chased: `AnimationPlayer` with
`Animation.LOOP_LINEAR` doesn't blend across the loop point, it hard-resets
`current_animation_position` from the clip's end straight back to its start - a real, instantaneous
position discontinuity, not motion. `_measure_velocity()` was diffing straight across that jump every
single loop (`(pose_at_time_0 - pose_at_time_2.5) / delta`) as if it were one ordinary frame's worth of
real movement, producing a large spurious velocity spike exactly once per loop - which explains why
parts 1 and 2's streak-based fixes only ever partially helped: a big enough single-frame spike can
still push a 3-frame streak/threshold in one or two ticks even with debouncing, especially right as the
new loop's own opening motion (often a settle/breath-intake with genuinely higher velocity) continues
in the same direction for a frame or two after.

**Fixed at the actual source this time**: added `update_animation_discontinuity()` in
`foot_ik_gait_tracker.gd`, called once per frame (not per-leg, to avoid yet another double-detection
pitfall) from `_process_modification_with_delta()`. Compares `AnimationPlayer.current_animation_position`
against last frame's value; if it dropped by more than 0.05s (real playback only moves forward, so any
backward jump this large is a loop reset or an animation switch, never normal progress), the frame is
flagged discontinuous. `_measure_velocity()` then suppresses just that one frame's velocity reading
(reads as motionless) while still refreshing `_prev_animated_foot_pos` to the fresh post-loop pose, so
the *next* frame's diff is correct again - same "don't diff across a teleport" principle already
applied elsewhere this session (physical stair snaps, jump landings).

**Verified the mechanism actually fires** (not just parses) via a temporary trace: confirmed 27 firings
across the scene's idle characters over a ~7s headless run, with `prev=2.5 new=0.0167` matching the
idle clip's exact 2.5s length wrapping to its start - and it also caught animation *transitions* (e.g.
`prev=1.33 new=0.0167`, mid-clip position reset when switching to a different animation), not just
same-clip loops, which is a useful bonus this same mechanism gets for free. Full automated suite still
passes clean. Also fixed a repeat of the same `Cannot infer the type` compile error from earlier in the
session (untyped `_owner.player_body.anim_player.current_animation_position` used with `:=`) - same
lesson, same fix (explicit `: float` type), caught again by the full `scripts/check.sh` run.

Files touched: `actors/player/foot_ik/foot_ik_gait_tracker.gd` (`update_animation_discontinuity()`,
`_measure_velocity()`), `actors/player/player_foot_ik_modifier.gd` (`_prev_animation_position`,
`_animation_discontinuous` state, call site in `_process_modification_with_delta()`).

**Not yet manually confirmed in-game** - third attempt at the same reported symptom. This one has the
most direct causal chain and the most precise user-reported trigger of the three, but the previous two
also looked solid on paper before falling short live - confirm before trusting it.

## 2026-08-05 session, new open item: leg overreaches into empty space on a ramp (not investigated)

User screenshot (controllable `$Player`, turning in place on/near a 30-45° ramp): one leg fully
extends, nearly straight, reaching down and away past the ramp's edge into open space below - visibly
the kind of pose that would make a real person slip and fall, not just "weird." Explicitly **not** the
same bug as the freeze/weight/loop-reset chain above - different root system.

**Working hypothesis (not verified live or headlessly)**: this is the existing idle step-down "deep
crouch fallback" (`_retract_to_reachable()` / `step_down_max_crouch` in `player_foot_ik_modifier.gd`,
from a much earlier session) - when a foot's target isn't reachable even after retracting the search
toward the hip, the leg is deliberately left extended toward the original (unreachable) target rather
than snap back, per an explicit earlier user request: *"let's make the leg foot to lower what's human
possible, and leave it hang... let's leave it looks weird but not wrong"* - accepted specifically for
the **stairs** case, where a hanging leg reads as "reaching for a real step below." On a **ramp**, the
same fallback reads as clearly wrong instead, most likely because the retraction search - which walks
the target back toward the hip's own XZ, re-raycasting at each step - is failing to find the ramp's own
nearby surface even directly under the hip. Suspect a raycast/collision-geometry quirk specific to how
ramps are modeled near their edges (e.g. collision not matching the visual mesh's extent, or a straight
vertical raycast missing a steeply-angled thin slab past its physical boundary) rather than a genuine
"nothing is reachable" case like a real stair drop.

**Not investigated further this session** - user explicitly chose to log this for a fresh session
rather than open a fourth concurrent investigation thread. Next time: reproduce headlessly by placing
`$Player` (or a ramp reference character) near a ramp edge and rotating yaw in place across several
angles, capturing `_step_down_classification`'s plant/settle verdict and `_retract_to_reachable()`'s
per-step raycast results for the affected leg, to confirm or refute the retraction-search-fails
hypothesis before touching any code. The hip-swing cone added earlier this session (`max_hip_swing_degrees`)
constrains *angle* but not *distance*, so it alone does not prevent this - a max horizontal reach
relative to the hip/pelvis, or tightening what counts as a trustworthy retraction result on non-stair
surfaces, are both worth considering once the actual cause is confirmed.

## 2026-08-05 session, idle-freeze follow-up part 4: the actual root cause - retraction bypasses freeze entirely

Fourth report of the same reported twitch, at yet another spot, and after three separate real fixes
(unfreeze debounce, rising-velocity streak, animation-loop-discontinuity suppression) that all passed
their own verification but didn't stop it. The debug captures kept showing the twitching leg
(consistently `left`, across every report) with `step_down=true` and a large `lower_distance`
(0.319-0.444m across captures) - i.e. always classified as **settle**, going through
`_retract_to_reachable()`, not the ordinary plant path any of the first three fixes touched.

**Root cause**: `_retract_to_reachable()` runs its full 8-step raycast search **every single frame**
while classification stays "settle" - completely unconditionally, with no gate at all - and on success
it **directly overwrites** `_smoothed_target[side]`/`_smoothed_normal[side]`, bypassing the
`smooth_rate`-based lerp the ordinary path uses entirely. The idle-freeze mechanism from earlier this
session only guards `_sample_ground_contact()`'s own internal lerp (the ordinary plant path) - it was
never wired into this separate, always-rerunning, zero-smoothing settle/retraction code path at all.
Any frame-to-frame raycast noise here (from the same idle-sway motion implicated in parts 1-3) was
fully visible with no damping whatsoever, on every single frame, regardless of any of the previous
three fixes - they were all correct fixes for real, different bugs, just not *this* one.

**Fixed**: gated the retraction search itself on `not frozen` - once frozen, the settle path now
reuses the already-settled `_smoothed_target`/`_smoothed_normal` exactly like the ordinary path already
does, instead of re-running the search from scratch every frame. `step_down` itself (which drives the
weight/contact-lost bypass, unrelated to target smoothing) is set unconditionally either way, so
freezing only stops the *search*, not the plant.

**Verified the search actually stops running**, not just that the target happens to look stable: a
temporary per-call trace confirmed `_retract_to_reachable()` fires every frame through frame 38, then
stops entirely the moment freeze engages at frame 40 - direct proof the gate works, not an inference
from a coincidentally-static number. Full automated suite still passes clean.

Files touched: `actors/player/player_foot_ik_modifier.gd` only (the settle block in
`_process_modification_with_delta()`).

**Not yet manually confirmed in-game** - fourth attempt at the same symptom. Given the previous three
also had verified mechanisms and still didn't fully resolve it live, this is a *stronger* candidate
(it's the only one of the four that actually touches the exact code path the twitching leg was
consistently going through in every single capture) but still needs live confirmation, not just a
headless trace, before treating it as done.

## Session bugs found and fixed (live-testing marathon)

None of these were caught by the automated `check_foot_ik.sh` suite - all found by the user testing
live in the editor and pushed back on "should be fixed" claims until proven with contradictory data,
not just a plausible-sounding theory. Read this before touching idle step-down code again.

- **`PlayerIdleSettleStep.compute_direction()`'s `ARRIVED_DISTANCE` guard** returned `Vector3.ZERO`
  whenever the target was within 5cm of the root - but `idle_settle_target` is the dangling foot's own
  ground-contact XZ, which sits only a small stance-width offset from the root, well under 5cm in some
  animation poses. Character never moved from a pure standstill; only a manual nudge (which displaced
  the root far enough) unblocked it. Fix: removed the guard - `idle_settle_needed` flipping `false` is
  already the authoritative "done" signal.
- **Streak-flicker killing `ground_weight` before it could ramp**, found twice, same root pattern: a
  "must sustain N consecutive frames" counter fed by ordinary per-frame animation-velocity noise, with
  a **hard reset to 0** on any single frame that ticks over threshold. Idle-animation jitter crosses a
  small threshold (`idle_step_down_speed`/`velocity_noise_floor` are both ~0.03-0.06) often enough that
  the counter could almost never sustain 4 frames, so `step_down`/the falling branch flickered
  true/false continuously, and every `false` frame force-reset `ground_weight` to `0.0` via
  `contact_lost` before it could finish climbing. Hit in two places:
  `_step_down_classification`'s `_step_down_static_streak` (`player_foot_ik_modifier.gd`) and
  `_measure_velocity`'s `_falling_streak` (`foot_ik_gait_tracker.gd`). Fix in both: decay by 1 on
  marginal noise (up to 2x threshold) instead of resetting to 0; only a clear, large reversal still
  resets immediately (confirmed via `FOOT_IK_BODY_PENETRATION_CHECK` that a too-lenient first attempt
  at the first one let a foot start planting mid-swing and sink into the tread it was swinging over -
  tighten the tolerance band before trusting a hysteresis fix here, don't just widen it).
- **`_apply_support_contact()` (`foot_ik_stair_predictor.gd`) unconditionally overwrote
  `_smoothed_ground_weight[side] = 1.0`** for whichever leg the stair predictor's active-walking
  support-transfer logic currently considers the "support" foot, completely bypassing
  `gait_tracker.update()`'s own fresh computation for that same frame. If `_support_side` stays latched
  (e.g. left over from the settle-walk's real stair-climbing movement) well past the point the
  character has gone idle, it force-resets that leg's weight back to `1.0` every single frame even on
  frames where `gait_tracker` had just determined contact was genuinely lost. Caught via a live readout
  showing an internally-impossible combination: `raw_weight=0.0, contact_lost=true` yet displayed
  `ground_weight=1.0`. Fixed: only force the override when `gait_tracker`'s own `contact_lost` for that
  leg agrees contact is present.
- **`ui/hud.gd`'s Esc/P debug menu pauses the whole tree** (`get_tree().paused = true`), which stops
  `player.gd`'s `_physics_process` entirely - the only place the settle-walk and weight ramp run. Every
  "still broken" report early in the session traced back to a paused/frozen read. Fixed several ways:
  `foot_ik_debug_overlay.gd` re-evaluates the modifier every frame while paused
  (`_refresh_paused_ik_pose()`) so readouts stay honest; the "IK Active" checkbox now syncs to the real
  `active` state every frame instead of only at construction/last click (was showing "IK DISABLED"
  forever after one bad frame at spawn, even after `active` self-corrected); added a "Keep Playing"
  toggle (**on by default**) that force-unpauses every frame the Esc/P menu would otherwise freeze, so
  the character keeps moving in real time while the panel is open.
- **A real editor crash, not a gameplay bug**: the 0.35m stair walker's `STAIR_FOOT_TRACE` per-frame
  JSON debug logging was ungated and re-fired on every one of its repeating walk-up-idle-reset cycles
  during ordinary interactive play (it was only ever meant for the one-shot `--foot-ik-check` capture).
  Over a long editor session this overflows Godot's own console buffer and **silently kills the whole
  debug process** (`ERROR: [output overflow, print less text!]` / `--- Debugging process stopped ---`
  in the Output panel) - every reading taken after that point is from a dead process and will never
  update no matter what code changes are made. Gated the logging behind `_automated_stretch_check`.
  **If a future "nothing reacts, definitely tested live" report resists every plausible fix, check the
  Output panel for this exact message before spending more time on the code.**
- Added permanent diagnostics worth keeping: `is_floating`/`RawWeight`/`CtcLost`/`StuckSec` readout
  columns, a live `player_pos`/`ik_active`/`settle: needed=.../target=...` line in the always-visible
  panel (no pause or button press needed), and `player_pos` in the Copy IK Data text - these were what
  actually let each of the bugs above get pinned down instead of guessed at.
- Split `_spawn_marker`/`_spawn_ray`/`update_ray_visual`/`_spawn_angle_label` out of
  `foot_ik_debug_overlay.gd` into a new `foot_ik_debug_markers.gd` (`FootIkDebugMarkers`, static
  helpers) purely to stay under the 1000-line lint cap while adding the ray-visualization gizmo (a
  visible green/red line for the actual decisive ground probe, not just its endpoints).
- `$Player` now spawns directly at the confirmed repro spot (bottom riser of the 0.65m stairs,
  straddling the final drop to true ground level) instead of the scene's original default, so manual
  testing doesn't require walking there first.

## Open: right foot stuck on the 0.65m-to-floor drop (unresolved)

Despite all of the above, the right foot still gets permanently stuck floating specifically at
`$Player`'s spawn point (bottom riser of the 0.65m stairs → true ground, classified `step_down=true`/
Option A skeleton-only-sink, **not** Option B whole-body walk - `settle_needed` stays `false` here).
`RawWeight` and `CtcLost` read correctly (`1.0`/`false`) but `ground_weight` stays at exactly `0.0`
indefinitely in live play - confirmed by the user watching it for several real seconds with no pause
and no interaction. A watchdog was added (`_weight_stuck_time` in `foot_ik_gait_tracker.gd`'s
`_smooth_weight`, self-heals if `raw_weight - weight > 0.05` persists past `~0.5-0.6s`) but the last
live reading showed `stuck_time=0.00` the entire time despite the stuck symptom being visibly present
in the same reading - meaning the accumulation condition isn't even triggering as written, or isn't
running with the code the user is actually testing. **Exhaustively reproduced headlessly and could not
reproduce the stuck state even once**: jump-in-place, jump-with-horizontal-repositioning, and 60 real
seconds of just standing still at the exact same spawn transform all recovered correctly within under
a second and stayed stable for the rest of each run. Whatever the real trigger is, it requires live
play in the actual editor and has not been isolated. Manually toggling the "IK Active" checkbox
reliably fixes it (forces `set_debug_enabled()`'s unconditional `reset_runtime_state()`, unlike
`set_character_grounded()`'s reset, which only fires on an actual airborne↔grounded transition - a
no-op if `active` never changes value). Next step if resumed: instrument `_smooth_weight()` itself
directly (not just its inputs/outputs) with an always-on throttled print, since the readout-based
diagnosis has been exhausted without finding the trigger.

## Open: Option B walks the character down an entire staircase unprompted (not yet investigated)

Discovered while manually testing the other stair heights (which otherwise work correctly per the
fixes above): standing idle partway up a tall staircase and just looking around causes the character
to auto-walk itself down every remaining riser to the bottom, one step at a time, with no player input.
Option B is meant to resolve the *one* foot that can't reach with a pelvis sink alone and then stop -
not treat every riser transition as a fresh trigger and cascade all the way down. This was not
scoped/tested for multi-riser staircases before now (all verification this session used a single
riser). Likely more disruptive to actual gameplay feel than the stuck-foot bug above; not yet
diagnosed at all - start here next.

## Resume here (uncommitted work, mid-verification)

All of the following is uncommitted and represents the current session's work. Do not assume any of
it is finished or committed:

- Option B (auto settle-step) in `player_foot_ik_modifier.gd`: `_step_down_eligible()` became
  `_step_down_classification()`, returning `{"plant": bool, "settle": bool}` instead of one bool —
  `plant` is the old Option A envelope-sink case, `settle` is a drop that's a real step
  (within `step_down_max_drop`) but needs more pelvis sink than `step_down_pelvis_drop` allows. New
  `idle_settle_needed`/`idle_settle_target` (world position of the lowest pending foot) let
  `player.gd` react.
- New `actors/player/player_idle_settle_step.gd` (`PlayerIdleSettleStep`, stateless/static — several
  `Player` instances are live at once in the stair harness, so nothing here may be cached per-class):
  `compute_direction(player)` returns a normalized world-space direction toward `idle_settle_target`,
  or `Vector3.ZERO` once within `ARRIVED_DISTANCE`.
- `player.gd` (already at the 1000-line lint cap, hence the new file instead of inline code): when idle
  (`direction` zero, on floor, not mid-roll) substitutes that direction right where real movement input
  would go (`_physics_process`, right after `direction` is computed), so it rides the *exact* existing
  `_apply_step_up()`/`_apply_step_down()`/`move_and_slide()` path a real walk down these stairs already
  uses. **First attempt called `_apply_step_down()` directly with a tiny per-frame motion vector and
  did nothing** — verified via a temporary `--idle-settle-check` headless run (see below) that showed
  `y` frozen for 300 frames straight while `idle_settle_needed` stayed true: `_apply_step_down()` only
  detects a tread transition by comparing the floor height at the current position against the
  position shifted by *that one frame's* motion, so an idle-speed nudge (~8mm/frame) never reached far
  enough to see the edge. Routing through ordinary walking input instead — proven correct by the same
  harness successfully climbing these stairs — fixed it; a rerun showed `y` descending step by step
  (1.4008 → 1.3969 → 1.3906 → 1.3637 → 1.3051 → 1.0507, landing exactly on `0.35×3`) with
  `idle_settle_needed` toggling off on arrival as expected.
- Reproduction method for future regressions: temporarily add a CLI flag (`OS.get_cmdline_user_args()`)
  to `foot_ik_preview.gd` that teleports `$Player` to the 0.35m stairs, walks it up
  (`movement_input_override`), stops after ~90 frames, and prints `idle_settle_needed`/
  `idle_settle_target`/per-leg `debug_*` fields every 15 frames; temporarily lower
  `step_down_pelvis_drop` (e.g. to 0.15) so the existing 0.35m case reliably classifies as "settle"
  instead of "plant". Run via `godot --headless --fixed-fps 60 --quit-after 300 --path <project> ...
  -- --idle-settle-check` (no `--write-movie` — that mode crashed in this environment with a null
  texture in `MovieWriter::add_frame()`, unrelated to this feature). Revert the scratch edit
  (`git checkout -- tests/manual/foot_ik/foot_ik_preview.gd`) afterward; nothing from this workflow
  should be committed.
- **Removed `step_down_max_drop` entirely.** It used to reject any drop deeper than 0.4m outright
  (float, no matter what). Once the whole-body walk-down exists, that cap no longer serves a purpose —
  it's real collision-swept movement, not a skeleton stretch, so it has no reach limit of its own. The
  only remaining cap, `step_down_pelvis_drop`, now solely decides cheap skeleton-only plant vs.
  whole-body walk.
- **Extended the ground probe for genuinely idle feet.** `_sample_ground_contact()` has two rays: a
  primary one at the raw ankle position (drives orientation/smoothing) and a secondary one at the
  toe-tip-predicted lowest point (drives step-down classification). Both stayed capped at `ray_down`
  (0.6m) even for a stationary foot, so anything below that depth simply floated forever with no
  target to walk toward, regardless of the settle-walk mechanism above. Both now retry once at
  `idle_settle_search_down` (4.0m) when the short-range probe finds nothing **and** the foot is
  currently near-motionless (`anim_speed <= idle_step_down_speed` on that single frame - the sustained
  multi-frame streak in `_step_down_classification` still gates whether settle actually engages, this
  is only about not giving up on the probe itself too early). Mid-swing keeps the short range
  unchanged, so gait timing is unaffected - a swinging foot legitimately having nothing below within
  0.6m is normal and must not suddenly "see" a distant floor.
- Verified via the same `--idle-settle-check` scratch-flag method (teleport `$Player` onto the 0.65m
  stairs case - a single riser deeper than the old `ray_down`): right foot's secondary ray hit
  `lower_dist=0.643` immediately (only findable via the extended probe), `idle_settle_needed` triggered
  right away, and the capsule genuinely walked itself down over ~2s of headless simulation
  (`y`: 2.598 → 2.587 → 2.580 → 2.524 → 2.522 → 2.335 → 1.951, landing exactly on `0.65×3`), ending
  fully planted (`ground_weight=1.0`, `step_down=true`). Confirms both the extended-primary-ray fix and
  the max_drop removal work together correctly, not just in isolation.
- **What is left:** see the "Open" sections below - this is no longer a simple "confirm and commit",
  two real problems were found during that manual verification.

## Native IK experiment decision

The current custom implementation is being preserved as the first checkpoint on
`experiment/native-foot-ik`. The next attempt will compare it with Godot 4.6.2's native
`TwoBoneIK3D`, configured with two settings: one target and anatomical knee pole per leg.

- Do not run custom and native solvers on the same bones simultaneously.
- Keep collision, ray/contact sampling, gait classification, stair prediction, support transfer,
  target trajectory, the debug overlay, and the acceptance harness independent of the solver.
- Initially expose an explicit Custom/Native backend switch in the manual harness. Gameplay stays on
  the custom checkpoint until the native path passes basic comparison.
- Use `TwoBoneIK3D`, not `FABRIK3D`: each leg is an analytic hip → knee → ankle chain. FABRIK adds
  iteration without solving the actual lift/cross/land target-timing problem.
- Timebox the comparison to idle, flat walking, the normal-speed 0.35 m stairs, jumping/airborne
  release, and anatomical knee direction.
- Adopt native IK only if it is visibly at least as stable, preserves the animation better, and lets
  us delete meaningful custom bone-solving code. Otherwise retain the checkpoint and continue fixing
  the explicit stair target trajectory.

Native IK is a solver replacement, not a complete stair solution. Regardless of backend, the target
must still lift above the riser, cross its plane, and then descend onto the tread.

Current prototype status:

- `foot_ik_native_backend.gd` configures one native `TwoBoneIK3D` with two settings, separate
  target nodes, and separate anatomical knee poles.
- The Foot IK modifier retains target generation and switches exclusively between the custom and
  native output backends.
- The Foot IK debug panel has a `Solver Backend` dropdown for immediate Custom/Native comparison.
- Interactive launches default the focused 0.35 m stair character to Native TwoBone while leaving
  the general controllable player and other references on Custom. Automated checks stay Custom by
  default; add `--native-foot-ik` to force the native focused run.
- The automated custom and native runs currently produce effectively identical ankle endpoints and
  the same penetration metrics. This confirms the native backend is wired to the shared targets; it
  does **not** demonstrate a visible improvement, so the normal-speed manual comparison is decisive.
- The native prototype has anatomical pole targets, but it does not yet apply the custom solver's
  `max_knee_flexion_degrees` limit. Before adopting it for gameplay, verify knee direction throughout
  idle, walking, stair contact, and landing, then add a native `BoneConstraint3D` if the pole alone is
  insufficient.

## Current user-visible result

- The controllable player and the focused 0.35 m reference character use the same shared stair
  collision and Foot IK implementation.
- The earlier whole-body penetration is no longer visible in manual testing.
- The remaining obvious problem is during the swing phase: a foot travels toward the next tread and
  contacts the vertical step edge before it has lifted above that edge. The gait therefore reads as
  bumping or catching the foot rather than taking a deliberate step.
- Do not mark the task complete until normal-speed manual traversal shows the foot lifting above the
  predicted riser, moving across it, and then descending onto the tread without a knee inversion,
  body stretch, floating plant, or visible collision.

## Architecture to preserve

The former 1,000-line modifier was split by responsibility. Do not collapse these phases back into
one function:

- `actors/player/player_foot_ik_modifier.gd`: orchestration, ground-contact sampling, shared pelvis
  application, and public/debug state.
- `actors/player/foot_ik/foot_ik_gait_tracker.gd`: animated vertical velocity, contact weight,
  falling streak, and landing events.
- `actors/player/foot_ik/foot_ik_stair_predictor.gd`: travel direction, predicted tread, swing lift,
  and single-support-foot ownership/transfer.
- `actors/player/foot_ik/foot_ik_leg_solver.gd`: the final closed-form anatomical leg solve and bone
  angle limits. It must not perform raycasts or choose gait state.
- `actors/player/player.gd`: authoritative `CharacterBody3D` stair ascent/descent and collision-root
  movement. This is shared gameplay code, not test-only behavior.

Godot evaluates `SkeletonModifier3D` after animation and restores the base pose afterward. Continue
applying recurring IK there; direct persistent bone writes from an ordinary node can feed a corrected
pose into the next frame.

## Fixes already retained

- Stair collision probes the horizontal tread beyond the blocking riser instead of treating a
  rounded capsule/riser-corner collision as the tread.
- Upward collision moves the capsule and complete rendered body to the tread immediately. Only the
  third-person camera retains inverse-height easing on ascent; leaving the body below the collision
  root caused the complete mesh to pass through the riser.
- Short descent presentation may ease above the destination tread.
- Forced support is retained only while its rendered sole/toe probe remains within real contact
  distance and its latched target remains anatomically reachable. A stale ray hit alone is not
  support; it previously pulled the pelvis through several steps.
- A fixed anatomical knee pole and flexion limits prevent the procedural solve from bending knees
  through the front of the leg.
- IK releases while airborne so jumps do not remain attracted to stair targets.
- The static split-tread inspection pose freezes only `Player`'s physics callback. Animation and
  `SkeletonModifier3D` processing continue, avoiding capsule depenetration that moves the hips while
  the feet remain planted.
- Stair reference characters run at normal gameplay speed. Slow motion hid timing failures.

## Harness and diagnostics

Persistent scene:

```text
tests/manual/foot_ik/foot_ik_preview.tscn
```

The scene includes multiple stair heights. The 0.35 m character is the focused traversable case and
uses the real `Player` physics callback. The 0.50 m and 0.65 m stairs are pose-limit references only;
gameplay `Player.step_height` remains 0.40 m.

The debug panel provides animation pause/scrubbing, IK tunables, a close foot camera, step/riser
colors, contact rays and impact points, predicted landing markers, foot/bone overlays, and copied
frame data. The focused trace logs animation time, root/tread state, support owner, animated vertical
velocity, contact distance, ground weight, predicted target, and swing lift.

Run both checks after every stair movement or Foot IK change:

```sh
scripts/check_foot_ik.sh
scripts/check.sh
```

Current automated result (as of the uncommitted provenance fix):

```text
FOOT_IK_STRETCH_CHECK PASS samples=138 max_error_m=0.0 limit_m=0.005
FOOT_IK_AIRBORNE_CHECK PASS samples=62
FOOT_IK_BODY_PENETRATION_CHECK PASS samples=138 attempts=138 unavailable=0
missing_mesh=0 penetrating_samples=0 penetrating_vertices=0 max_depth_m=0.0
tolerance_m=0.005
```

The mesh check CPU-skins every current `MeshInstance3D` from mesh weights, live `Skin` bind poses,
and final skeleton transforms. `bake_mesh_from_current_skeleton_pose()` does not work with this
gameplay import. The penetration check used to report XFAIL with 39 penetrating samples (2202
vertices, 0.051 m max depth) purely because the harness was skinning the *pre-IK animated pose*: at
the harness's idle/deferred sample time the skeleton still held the last animation pose, not the
modifier's output. Reading the modifier's post-solve `_final_bone_poses` snapshot instead (the
provenance fix) made it PASS with zero penetrations.

## Next debugging target: clear the riser before advancing

Work on the remaining foot bump as a swing-path problem, not by globally enlarging the ankle offset
or blindly increasing the toe margin. A larger toe margin was tested and worsened the numerical
penetration result.

Recommended next pass:

1. For the swing foot, identify the next vertical riser plane and its top height from the already
   predicted tread.
2. Log the rendered toe/sole's signed horizontal distance to that riser and vertical clearance above
   its top on every normal-speed frame.
3. Divide the predicted step into explicit clearance phases:
   lift above `riser_top + step_clearance_margin`, then allow forward crossing, then release lift and
   descend toward the tread.
4. Do not consider the predicted foot ready to descend merely because its downward ground ray sees
   the higher tread; require the rendered toe/sole to have crossed the riser plane with positive
   clearance first.
5. If the collision root reaches successive treads faster than the animation can produce valid
   alternating contacts, synchronize stair traversal speed/advance with the step phase rather than
   stretching a planted leg or retaining an old support target.
6. Compare the same animation frame with IK enabled and disabled after each change. Idle poses should
   remain equivalent, and the authored swing arc should not collapse.

## Approaches that were insufficient or harmful

- Applying full plant IK on every frame flattened the authored walk swing.
- Height-only gait classification confused a high static correction with an active swing.
- A hard rising/falling velocity sign gate twitched around zero; the current dead zone and continuous
  weighting are intentional.
- Allowing both legs to make independent support decisions produced frames with no reliable support.
- Retaining support from any ray hit, even when the rendered contact was far away, pulled the pelvis
  and body through the staircase.
- Smoothing the complete body below an upward collision snap created guaranteed mesh penetration.
- Manually translating the focused test character through risers created a harness-only penetration
  failure and did not validate the controllable player.
- Increasing `toe_tip_margin` from 0.035 m to 0.09 m worsened the measured maximum penetration and was
  reverted.
- Slow motion made the behavior appear better while the normal-speed timing remained broken.

## Idle step-down envelope (big-drop policy) — three options to try

The idle step-down feature plants a stationary foot that hovers over a lower surface by sinking the
shared pelvis. The standing leg has only ~4cm of reach slack (hip-to-foot ≈ 0.84 of the 0.887 max
reach), so planting a foot one riser below costs the pelvis roughly the full step height minus that
slack. The two exported caps in `player_foot_ik_modifier.gd` define the "step" envelope:

| Step drop | Pelvis must sink | Verdict |
|---|---|---|
| 0.20 | ~0.18 | natural settle (user-approved) |
| 0.35 | ~0.33 | borderline crouch |
| 0.50 | ~0.46 | obvious crouch |
| 0.65 | ~0.61 | basically sitting |

**Option A — envelope + accept float (currently implemented).** `step_down_max_drop = 0.4`,
`step_down_pelvis_drop = 0.35`. Anything within the envelope plants and never floats; drops beyond it
are ledges the standing leg physically cannot reach, so the foot stays at its animated pose (floats)
instead of bending the body into a squat. Gameplay stairs stay ≤ 0.40m and the focused 0.35m harness
case fits with a ~0.33 sink; the 0.50/0.65m pose-limit references are ledges. Note that middle-riser
straddles on tall stairs still plant, because the hip sits high up the staircase and the needed sink
is only ~0.5·step − 0.02; only a low hip straddling the bottom riser needs the full-step sink.

**Option B — envelope + auto settle-step.** Keep the same caps, but when the dangling foot's needed
pelvis drop exceeds `step_down_pelvis_drop`, the idle character eases the whole body down to the lower
surface so both feet plant there (upright, never floats, never crouches). Requires a new eased capsule
descent with collision and input-cancel handling; reuse the stair predictor's step-down support
transfer rather than writing a second descent path.

**Option C — envelope + partial reach.** Keep the sink capped but still ramp the ground weight so the
foot is pulled to its lowest reachable point (max extension) even when it cannot touch, shrinking the
visible gap while leaving it hovering above the lower surface — a half-measure that may still read as
floating.

How to toggle: A only changes the two exports. B and C change `_step_down_eligible()` /
`_apply_support_pelvis_and_legs()`. After any switch, re-run `scripts/check_foot_ik.sh` +
`scripts/check.sh` and manually straddle the bottom riser of the 0.35/0.50/0.65 rows with the
controllable player.

## Manual acceptance checklist

- Walk the controllable player up and down the 0.35 m stairs at normal speed.
- Confirm each swing foot clears the vertical riser before crossing it.
- Inspect front, side, rear, and close foot-camera views.
- Confirm feet land on tread tops without floating or penetrating.
- Confirm the body and pants do not stretch below the steps.
- Jump and land on/near stairs; knees must not invert and airborne IK must release.
- Compare idle and walk poses with IK on/off for unrelated deformation.
- After any automated scene run, leave the Godot scene stopped; the user starts manual tests.

## 2026-08-07 session, new open item: right foot's toe/ball sits ~1.2cm below the Ramp 45 surface (confirmed, not yet fixed)

Reported by the user as "leg clipping" while idle-standing on the Ramp 45 platform. Confirmed and
pinpointed via a new live diagnostic (`tests/manual/foot_ik/foot_ik_live_penetration_check.gd`,
marker-file toggle `user://foot_ik_penetration_check_marker`, folded into the existing
`user://foot_ik_controlled.jsonl` trace as a per-frame `"penetration"` field): once past the ordinary
spawn-settle transient (~frame 40), a **stable, unchanging** set of 23 mesh vertices reads ~1.24cm
below the ramp's actual collision surface every single frame while standing still - not noise, not a
one-off spike. Bone attribution (`penetrating_bones`) confirms it's the right foot specifically:
`ball_r` (16 vertices) and `foot_r` (7 vertices). 1.24cm is well above the check's 5mm tolerance
(matches `FOOT_IK_BODY_PENETRATION_CHECK`'s own tolerance).

**Update, same session, investigated further:**

- `target_max_speed` ruled out first (per the plan above): disabled it entirely (raised to 1000) and
  the clip persisted unchanged (smaller, on the other foot that particular run, but still present) -
  not the cause.
- **The "tilt under-measures clearance" hypothesis was wrong, and disproven with a concrete reason,
  not just more testing.** `_compute_new_foot_basis_world()` rotates the *whole foot* so its local
  down-axis always exactly matches the current ground normal - by construction, re-projecting any
  local-frame point onto that same (now-aligned) direction is mathematically identical to just
  reading the point's local Y-component, regardless of tilt. Built a "direction-aware" version
  (stored the full sole-mesh point cloud in local space, re-projected onto the live ground direction
  every frame) specifically to test this, and confirmed via live debug prints across normals of
  1.0, 0.97, 0.87, 0.71 (flat through 45°) that it returned the *exact same number* as the original
  flat-pose scalar every time - proof the two are equivalent, not just similar. Reverted the
  direction-aware version back to the plain scalar (`_sole_depth_below_foot`) to keep the code
  simple, since it added real complexity for zero behavioral difference.
- **Two genuine bugs found and fixed in the process, unrelated to tilt:** two of the *three*
  `effective_offset` consumers were silently using a lesser value instead of the real one -
  `_retract_to_reachable()` used bare `ankle_offset` alone (no toe/sole clearance at all), and
  `foot_ik_stair_predictor.gd`'s `_apply_support_contact()` cached the offset once at
  `_latch_support_target()` time and never refreshed it during ordinary retention (so a support foot
  latched before the character fully settled could keep an offset computed from transient state for
  its entire retention). Both now correctly use `_sole_depth_below_foot`/`leg["effective_offset"]`
  live. Real fixes, verified via `check_foot_ik.sh` (no regression) - but confirmed via live capture
  that neither fully explains the observed clip either (numbers barely moved).
- **What's actually left**: a small (~0.8-1.2cm), *tilt-independent* clip that persists regardless of
  which of the above is active - meaning the flat-pose `_measure_leg_sole_depth()` scalar itself is
  probably just measuring a few mm-1cm too shallow, a plain magnitude issue, not a
  direction/orientation one. Worth checking next: whether the "chain-dominant, non-chain-influences
  keep rest pose" split in that function (see its own comment about biasing "only the top edge")
  is actually excluding some blend-region vertices that are the true deepest point in the rendered
  mesh, or whether a flat small safety margin (a few mm) on `_sole_depth_below_foot` is the
  pragmatic fix given the magnitude involved.

To reproduce/re-verify: play `foot_ik_preview.tscn` with the marker file present (`touch
user://foot_ik_penetration_check_marker` before `play_scene_in_editor()`, matching the auto-spin
marker pattern already used for the turn-snap investigation), stand idle on Ramp 45 for a few seconds,
stop, and read `"penetration"` from the JSONL trace past frame ~40 - the `bones` breakdown will show
which bone/foot and roughly how deep.
