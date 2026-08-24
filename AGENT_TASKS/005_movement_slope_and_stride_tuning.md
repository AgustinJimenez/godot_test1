# 005: Movement Slope and Stride Adaptation

## Overview
Implement slope speed scaling, slope angle detection, and dynamic animation playback matching on steep staircases and uneven ground surfaces to prevent foot sliding and unnatural uphill/downhill pacing.

## Concept & Reference
- **Reference**: `stride_warping` and `slope_warping` in AMSG's `addons/PoseWarping/`.
- **Approach**:
  1. Sample surface ground normal under the player capsule to compute slope grade.
  2. Scale movement velocity and animation playback rate based on ascending / descending angle.
  3. Couple slope inclination with our `PlayerLookPoseModifier` stair-balance and `PlayerFootIKModifier` sole pitch alignment.

## Planned Deliverables
1. Slope detection and velocity factor calculation in `actors/player/player.gd`.
2. Locomotion rate adjustment in `actors/player/player_body.gd`.
3. Verification across flat, $15^\circ$, $30^\circ$, and $45^\circ$ test ramps and stairs.
