# 025 archive: walking hypothesis before exact event matching

The recurring point below was subsequently matched to startup idle frame 17, not walking.
See `../025_stair_walk_toe_riser_clip.md` for current evidence and status.

## Status and scope

**Open, unfixed.** Confirmed real via two independent tools (a quick box-check and the
project's precise per-vertex mesh check), not a false positive. Two targeted fixes made today
did not resolve the specific recurring case the user hit live. Distinct from `019` (clipping
while turning in place, not walking) and `020` (ramp-corner contact loss).

## How this was found

Built a new always-on live diagnostic for the manual preview scene, requested by the user after
019/020 review: `tools/foot_ik/foot_ik_live_penetration_monitor.gd` (generic "which nearby box
collider(s) does this point overlap, and by how much" check, reusing
`FootClearanceEvaluator.evaluate_box` - same math `foot_ik_idle_plant_stability_check.gd`'s own
turn-sweep already used) plus `tests/manual/foot_ik/foot_ik_clip_indicator.gd` (spawns a large red
marker at the clip point and prints one throttled `[FOOT_IK_CLIP] side=... depth_m=... point=...`
log line per clipping episode - not spammed every frame). Wired into `foot_ik_debug_overlay.gd`,
checking each foot's ankle and toe-tip position every physics frame.

Also discovered, while investigating this, an existing but unused precise checker already in the
codebase: `tests/manual/foot_ik/foot_ik_live_penetration_check.gd` - raycasts every skinned mesh
vertex against the real floor collider (not a box approximation), opt-in via a
`user://foot_ik_penetration_check_marker` file since it's expensive (a raycast per vertex per
physics frame - **caused a severe FPS drop when enabled during ordinary play; do not leave this
marker file in place outside a short, isolated headless test**). Used it once, briefly, in a
headless run to cross-check the new indicator's finding - see "Confirmed real" below.

## The concrete symptom

Live-captured via the new indicator during the user's own play: dozens of clip events per
session, most small (5-10mm, likely negligible noise), but several genuinely large - up to
**15.9cm** on one foot, recurring at the *exact same world point* (`(15.37852, 1.117114,
1.958677)`, depth `0.1587` to four decimal places) across at least three separate live sessions,
unchanged by either fix attempt below.

Correlating that exact point against the live `foot_ik_controlled.jsonl` trace: animation
`moves/unarmed_walk`, target owner `live_contact`, and `root_yaw_deg` changing by ~3.7 degrees
every frame for several consecutive frames right at that point - **the character is walking and
turning at the same time**, going down/across the stairs.

## Confirmed real, not a diagnostic false positive

Enabled `foot_ik_live_penetration_check.gd` (the precise per-vertex mesh checker) for one short
headless run of the same automated stair-walk scenario (`foot_ik_preview.tscn -- --foot-ik-check`,
360 frames): `FOOT_IK_LIVE_PENETRATION_CHECK FAIL samples=358 attempts=358 penetrating_samples=286
penetrating_vertices=13884 max_depth_m=0.134882` with the penetrating vertices concentrated almost
entirely in `foot_l`/`foot_r`/`ball_l`/`ball_r` bones - real mesh-into-geometry penetration on the
feet, not a box-shape approximation artifact.

## Two fix attempts today, neither resolved the recurring case

The general (non-idle) foot-target smoothing in `foot_ik_ground_sampler.gd` had no collision
awareness at all, unlike the idle-only paths (`_move_toward_held`, already existing from an
earlier session). Extracted a shared `_hold_short_of_collision(space, previous, intended)` helper
(clamps an already-computed move short of any blocking geometry between the two points) and:

1. Applied it inside `move_target_smoothed()` (the main `live_contact`/`locomotion_stance` lerp
   path, and `foot_ik_stair_predictor.gd`'s support-foot transfer-blend path - both needed `space`
   threaded through their call chains, see `ensure_support`/`_apply_support_contact`). Verified via
   the fast suite: no regressions, `FOOT_IK_STAIR_LOCOMOTION_CHECK` (92 steps) still passes clean.
2. The recurring 15.9cm clip persisted identically after (1). Traced it to `body_turning == true`
   at that exact moment (walking *and* turning together) routing through a **different**,
   sibling branch in `sample()` that used a plain `move_toward` with no collision awareness at
   all. Applied the same `_hold_short_of_collision` helper there too.

**Result: the exact same 15.9cm clip at the exact same point recurred a third time, completely
unchanged**, after both fixes were live and verified present in the working tree. This means the
actual trigger is neither of the two branches fixed today - something else is producing this
specific target, or the collision-hold's own geometry probe isn't detecting whatever it's
clipping into at this spot (possibly a thin riser edge/nosing the horizontal-ray-at-fixed-height
probe in `_hold_short_of_collision` steps over, since it only checks a single height slightly
above both endpoints, not the whole vertical span the foot sweeps through).

## What to try next (not attempted)

- Get the *character root* position/rotation near the recurring point (not just the clip point
  itself) and reproduce headlessly, the same way `024` did for its own repro - then add temporary
  print instrumentation at each `smoothed_target[side]` write site active during
  `owner=live_contact` walking-while-turning, to find which one actually produces the clipped
  value (mirroring `024`'s successful "stop guessing, instrument every write site" approach after
  its own first few fix attempts failed).
- Check whether `_hold_short_of_collision`'s single fixed-height horizontal probe
  (`HOLD_PROBE_UP := 0.05` above the higher of the two endpoints) can miss a riser edge that both
  endpoints already sit above/below - a foot sweeping diagonally down-and-across a step during a
  turn could pass through a corner the flat probe height never crosses.
- Check `foot_ik_stair_predictor.gd`'s gait-coupled `update_swing_lift`/`_desired_swing_lift`
  (untouched today) - the swinging (non-support) leg's vertical lift arc has never been given a
  horizontal collision check either, unlike the two paths fixed today.
- Re-verify with the precise mesh checker (marker file, **headless/short session only, never
  during ordinary play** - it visibly tanks FPS) after any future fix attempt, not only the
  quick box-based indicator, since it caught real penetration the box check would also have
  caught here but is the more authoritative source for a final confirmation.

## Third investigation pass: the horizontal-probe hypothesis above was ruled out

Built a temporary exact-trajectory replay (hardcoded array of the real session's recorded
position/yaw per frame, played back directly into `$Player.global_position`/`.rotation`,
bypassing normal input - reverted after use, never committed) to reproduce the specific
recurring clip deterministically, plus a temporary print inside `_hold_short_of_collision`
logging every probe ray it casts near the known clip point.

**Every single probe during the replay returned an empty hit** - the horizontal ray genuinely
finds no geometry at any of the sampled positions/heights. This rules out "the flat probe height
misses a raised riser corner" as the cause: the collision-hold logic isn't failing to see a wall
it should - the wall (if the clip is even in this leg's ankle-target path at all) isn't where
this raycast looks. Also found that correlating the logged clip point against the trace by
*nearest root position* (used throughout this investigation) is too imprecise for foot-level
diagnosis - at the specific frame that root-distance search picked, neither the recorded ankle
(`foot_pos`) nor toe joint position was within 0.3m of the actual clip point, meaning the
matched frame was several strides off from the real event. Any future attempt needs a tighter
match (nearest by ankle/toe position, not root) or the exact-trajectory-replay technique above
(kept out of the repo, but the technique - hardcode the trace's per-frame root/yaw into a
temporary `$Player` override - is reusable) run long enough to capture the clip within the
replay itself, not just the surrounding area.

This also raises a real, undecided question for whoever picks this up next: the clip may not be
an *ankle-target path* problem at all (what both of today's fixes and this whole investigation
assumed) - it could be a toe/mesh-orientation issue structurally like `019`'s already-confirmed
`LANDING_UPPER`/toe-envelope gap, just triggered by walking instead of stationary rotation.
Confirming which joint (ankle vs. toe) is actually penetrating at the real clip moment, precisely
matched, is the necessary next step before attempting another fix.

## References

- `tools/foot_ik/foot_ik_live_penetration_monitor.gd`,
  `tests/manual/foot_ik/foot_ik_clip_indicator.gd` - the new always-on live indicator.
- `tests/manual/foot_ik/foot_ik_live_penetration_check.gd` - the pre-existing, precise, opt-in
  per-vertex checker (marker file `user://foot_ik_penetration_check_marker`) - already existed,
  just never wired to any of this session's investigations before now.
- `actors/player/foot_ik/foot_ik_ground_sampler.gd::_hold_short_of_collision` - the new shared
  collision-hold helper, extracted from the idle-only `_move_toward_held`, now also used by
  `move_target_smoothed()` and the `body_turning` branch in `sample()`.
- `AGENT_TASKS/019_foot_ik_toe_riser_clip_during_rotation.md` - the sibling turning-in-place
  clip bug (three earlier fix attempts, also still open) - same visible symptom family, confirmed
  structurally different mechanism (that one is stationary rotation with no walking).
- `AGENTS.md`'s Foot IK section - notes on the new live indicator and the precise checker's
  performance cost, so neither gets rebuilt or left on by accident again.
