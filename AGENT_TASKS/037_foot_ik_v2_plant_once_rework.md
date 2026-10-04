# 037 - Foot IK v2: plant once from the footprint (design note, nothing built yet)

## Why

Seven live-log bugs in a row (2026-10-04) had one shape: the foot target comes from ONE ray under the
ANIMATED ankle, re-decided EVERY frame, and each symptom got its own rule on top. Rules now stacked:
stretch-hold ratchet + release (`foot_ik_v2_stretch_hold.gd`), pelvis drop cap + landing bypass,
correction easing, moving/resting mode switch, `max_surface_drop`. They interact: a faster landing rate
(2.5x instead of 2x) turned the stair-turn check red. Per AGENTS.md ("repeated failures"), stop patching
and move the decision, not add another guard.

Evidence (live logs, stairs):
- Right foot on a nosing: ray flips tread (y 0.40) <-> floor below the stairs (y 0.00); foot jumped 0.3 m
  in 16 frames, heel 28 cm inside the tread. `_plausible` compares with the ankle ALREADY lowered by the
  0.40 m squat, so a floor 0.40 m under the body looks only 9 cm away.
- Squat stuck at the 0.40 cap: the ratchet (`_stretch_hold`) only ever went up while idle.
- Landing at a stair edge: right foot touches -> land clip counts as "moving" -> pelvis capped at 6 cm ->
  left foot hangs 10-30 cm up for the whole clip, reaches the floor only when idle starts.

## Plan (each stage ends with the suite + fuzz green; keep the checks, they encode real bugs)

1. **Plant once.** A foot gets a contact state (planted / swinging) from the clip's foot height + speed
   (already: `PLANT_FADE_*`, `_is_swinging`). On entering planted it picks its world position + surface
   ONCE and holds it (`foot_ik_v2_lock.gd` already holds the XZ while resting; extend to y/surface and to
   walking). No per-frame re-sampling while planted, so no nosing flip by construction.
2. **Footprint ground.** At the moment of planting sample heel, toe and ankle (+ the inward probes that
   exist) and take the HIGHEST plausible hit; `_plausible` measures from the capsule floor (root y), not
   from the squatted ankle. Needs a helper file (modifier is at the 1000-line cap).
3. **Pelvis solved once from the final targets.** Needed drop = what the planted targets need (per foot,
   max), no feedback from last frame's `stretched` state, so no ratchet; delete `_stretch_hold`, the
   release helper and the landing bypass. Landing = planted feet on the floor, the same rule as idle.
4. **Smoothing = inertialization** (blend the pose offset to zero over ~0.1-0.2 s, per bone) instead of
   per-frame speed caps (`CORRECTION_STEP`, joint speed limits). Do last; it only replaces caps.

Order: 1+2 first (expected to fix the flip, the far-floor plant and the stuck squat together, and to
delete code), then 3, then 4. Gate every stage on the suite, the fuzz run and the user's live check.

## Open questions

- Walking: does a planted walking foot need the same hold? (clip contact timing vs 0.2 m stair rises).
- Landing on a ledge: the user wants the leg to go down to a floor ~0.3 m below at once; with plant-once
  the swinging foot has no target until it lands, so define "landing" = plant immediately on the floor.
- Floor 0.4 m below the body at a stair edge: plant there (squat) or on the tread? Needs a rule the user
  agrees with by watching it.

## Sources read

Holden, "Inverse Kinematics and Foot Locking" (theorangeduck.com/page/inverse-kinematics-foot-locking);
"Feet on the world" (aether-lang-dev/ae3d #577). No Uncharted 4 foot-IK talk found; the code cannot be read.
