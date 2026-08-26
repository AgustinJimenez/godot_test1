# 008: Foot IK platform-edge safety

## Status

Implemented and under final verification as of 2026-08-26. Do not commit gameplay changes until the
user confirms the live result.

## Problem

When the character keeps pushing diagonally near a platform or stair-landing edge, normal walking
velocity stops but the body can still move slightly. After input release, one foot can remain beyond
the authored platform surface with no contact and zero IK weight, visibly floating over the void.

## Confirmed live evidence

Source: `user://foot_ik_controlled.jsonl`, latest user reproduction ending at frame 1265.

- Frames 566–965 retain edge-directed input and report zero horizontal velocity, but the root still
  accumulates 0.079m of horizontal movement.
- When input reaches zero, `_nudge_to_ledge_safe_zone()` moves the root another 0.225m diagonally.
- The final 40 idle frames have left `contact_hit=true`, `ground_weight=1.0`; right
  `contact_hit=false`, `ground_weight=0.0`.
- The right foot remains beyond the authored surface in its animation pose.

This shows two connected defects: blocked motion can still accumulate collision-recovery movement,
and edge recovery proves only a body-center support point rather than support for both stance-foot
areas. Around the stair gym, traversal collision must not be mistaken for authored foot support.

A later live capture ending at frame 625 exposed a separate transient failure hidden by the final
settled pose. Frames 456–504 place the left solved foot outside its colored safe rectangle while a
blocked lateral input is held and the body turns from about 110 to 86 degrees. At frames 499–504 the
left foot crosses the center line, reaching 0.110m onto the right side, loses contact, and fades from
full weight. By the final 40 frames it has recovered, so the trace analyzer's default `--last-n 40`
originally reported no anomaly.

A jump capture ending at frame 1305 exposed a third edge state. The capsule landed at root
`(14.326, 2.080, 4.221)` facing 89 degrees, balanced on the back lip of the top landing. From frame
1130 through the end, the left foot had no authored contact and zero weight; its deep fallback target
settled on the floor about 2.1m below. The left colored zone was entirely beyond the landing, so no
same-side foot-only target existed. The capsule's lip contact reported a tilted floor normal and the
old slope guard disabled body recovery.

## Required regression

Extend the persistent ledge check with a long-held diagonal edge/corner push, then release input and
observe stable idle. It must fail if:

1. the root creeps after the movement request has been blocked;
2. recovery moves farther toward any unsupported edge; or
3. either final foot lacks authored-surface contact or remains below full planted weight.

The existing short 20-frame movement-only cases are insufficient because they finish before slow
collision recovery or the final idle foot state can be observed.

## Work order

1. Add the failing long-hold and post-release regression using the same split authored/traversal
   surfaces as the live stair landing.
2. Make blocked ledge movement preserve the last safe horizontal root position without breaking
   gravity, floor snap, stairs, ramps, or genuine edge-parallel movement.
3. Make idle recovery validate the authored contact surface for both stance zones; do not accept an
   invisible traversal-only hit as proof that a foot is safe.
4. Ensure an unsupported idle foot retracts to reachable support on its own side of the character.
5. Run ledge, randomized edge stance, walk-to-idle stance, ramps including the 360-degree sweep,
   stair repeat/idle-freeze, `scripts/check.sh`, and the full Foot IK runner.

## Implemented

- Blocked ledge input now restores the frame's starting horizontal position after collision recovery,
  while preserving vertical movement and floor state.
- Unsupported-foot recovery checks a small authored-surface patch around a proposed target and aims
  toward a same-side stance point near the body.
- Cached recovery targets are revalidated against the complete body-relative colored rectangle when
  recovery tries to reuse them. A supported world-space target is discarded when rotation moves it
  outside lateral or longitudinal zone bounds.
- Retraction runs only during idle animation; applying the same correction during active stair
  walking pulled a planted foot sideways through a riser.
- The per-foot retraction flag is reset every frame, so an old successful recovery cannot make a later
  unsupported foot look planted.
- The recovery side guard now follows MotusMan's actual skeleton-local convention: left is positive X
  and right is negative X.
- The ledge regression reproduces the exact long diagonal stair-landing push from the live trace and
  observes the released idle state. Its runner timeout was raised so this longer case can finish.
- A second stair-landing regression holds lateral input, rotates from 109.69 to 68.43 degrees in small
  steps, and checks every intermediate solved pose against the colored zones rather than checking only
  the final recovered stance.
- `scripts/trace.sh --anomalies` now reports `FOOT_SAFE_ZONE` events. Use `--last-n 0` to analyze the
  whole current capture rather than its default final 40 frames.
- Grounded idle recovery now runs after every ordinary movement update, including a zero-input jump
  landing. Its slope guard uses a direct center ray instead of the capsule's potentially tilted lip
  normal, allowing the body to move inward from a flat edge without pulling characters up real ramps.
- The ledge harness includes the exact airborne position, downward velocity, yaw, and landing-edge
  geometry from the frame-1305 reproduction. It requires both feet to regain authored contact and
  full weight after landing.

## Verification so far

- Ledge safety: PASS, including the held diagonal case and the new gradual blocked-turn case.
- Jump-to-landing-edge recovery: PASS; body moved 0.496m inward and both feet finished planted.
- Random edge stance: PASS, 100 positions and rotations.
- Walk-to-idle stance: PASS, 24 cases and 2184 sampled frames.
- Ramp locomotion: PASS, uphill/downhill on 15, 30, and 45 degrees with 360-degree turns.
- Stair repeat and idle-freeze clearance: PASS.
- Project lint, import, and GDScript parsing (`scripts/check.sh`): PASS.
- Full Foot IK runner: all edge, ramp, stair, planting, penetration, and stance checks pass. The
  runner later stops at the pre-existing `walk_fwd_left` A/B continuity expectation, outside this
  platform-edge task.

The full Foot IK suite is intentionally expensive because it simulates thousands of animation and
physics frames. A later independent task can split fast and exhaustive tiers and run isolated scenes
in two or three parallel Godot processes; trace-writing scenes must remain serial unless each receives
a unique output path.

## Related history

Earlier Foot IK work is preserved in
[`007_foot_ik_stair_contact_and_locomotion.md`](007_foot_ik_stair_contact_and_locomotion.md).
