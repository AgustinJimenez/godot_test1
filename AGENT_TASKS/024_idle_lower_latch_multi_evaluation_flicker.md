# 024: Split-height idle-foot feedback loops

## Status

**Fix implemented; exact headless replay passes; broader validation in progress. Awaiting user
live confirmation.** No scene autoplay and no commit until that confirmation. Original five rejected
experiments are preserved in [the archive](archive/024_rejected_latch_investigation.md).

## Confirmed causes (2026-09-13)

The previous right-latch-only hypotheses missed two coupled mechanisms:

1. `straighten_compressed_upper_target()` can request an optional body nudge when upper-foot
   clearance fails. `Player._nudge_to_ledge_safe_zone()` rejects it when both feet already have
   support, calling `reject_split_safe_root()` **even with no active split recovery**. That function
   erased both lower-foot owners and reset both smoothed targets to raw animation probes.
   Filtered instrumentation matched the visible resets exactly: ticks 96/116/137/... had
   `split=(inf, inf, inf)`, `nudge=(-1,0,0)`. Right target jumped about 14 cm.
2. Independently, upper-foot extension fed its own output into pelvis centering. The pelvis moved
   toward the extended foot, reducing hip-to-target reach until the retained-flexion check failed;
   the target then returned inward and reacquired. With unrelated resets fixed, this still cycled
   every ~27 frames. Instrumentation measured cached-target reach decreasing 0.744 -> 0.676 m
   against a 0.675 m retention threshold while geometry/stance checks remained valid.

Fixes:

- Declining a nudge clears that request but only cancels foot ownership if an actual split-recovery
  target/held transaction exists. Real split rejection retains its existing release behavior.
- The upper-foot producer explicitly reports when its policy is active, including failed-search
  frames. During that stationary policy, pelvis uses independent `raw_ground_target`, not the
  extension output. `brace_upper` is NOT an equivalent gate: it was false in this exact repro.
- Generic target smoothing cannot pull against an active compressed-upper target. During existing
  animation-seam holds, the coordinator also retains the prior independent pelvis basis. Without
  these seam provisions, the new regression correctly caught a residual 3.9 cm once-per-loop twitch.
- Trace stance-zone checks now use recorded body yaw, matching the runtime rectangle. Animated hip
  axes falsely flagged the fixed stationary pose; old traces without yaw retain the old fallback.

This is not a broad pelvis migration: locomotion, slopes, spacing and non-upper policies retain
their existing reference choices. Existing unrelated dirty work was preserved.

## Repro and regression

Live/replay spawn: `Vector3(15.52282, 1.422718, 1.734463)`, yaw `100.977250312091` degrees.

```sh
godot --headless --fixed-fps 60 --path . \
  res://tests/manual/foot_ik/foot_ik_split_idle_feedback_check.tscn --quit-after 620
```

New persistent acceptance scene replays 600 frames with no input; after 120 settle frames it
measures every rendered ankle across 480 frames, checking drift, frame steps, support clearance,
body drift, body-relative stance bounds, weights and uninterrupted right lower-foot ownership.
It also checks that optional nudge rejection preserves holds while real split rejection releases.
Registered in the shared exhaustive check list and fast allowlist.

Current exact result: **PASS**, drift `0.000001 m`, step `0.000002 m`, clearance `0.000001 m`,
root drift `0`, invalid frames `0`, rejection isolation `true`.

Evidence directory: `/tmp/foot-ik-024.3JFLad/` (original live capture and inherited diff preserved
before tests, baseline, isolated fixes, targeted diagnostic logs and final trace).

## Remaining work / acceptance

- Finish fast/full regression map and mutation-check that this new test fails without the fixes.
- User: play the preview when convenient; watch 2-3 idle loops at this spawn. Neither foot should
  repeatedly slide out/back or twitch at the loop seam.
- Tasks 019 (toe/riser penetration) and 020 (ramp-corner burial) remain separate, unresolved cases;
  do not mark them fixed from this one stable stance.
