# 002: Locomotion Camera Tilt and Inertia

## Overview
Implement subtle first-person camera and body banking/tilt when strafing laterally or turning rapidly, adding physical weight and momentum to survival horror movement.

## Concept & Reference
- **Reference**: `tilt` and camera roll interpolation in AMSG's `CharacterMovementComponent` / `CameraComponent`.
- **Approach**:
  1. Calculate lateral velocity relative to player heading.
  2. Smoothly rotate camera roll ($Z$-axis) proportionally to lateral speed and angular turn rate (e.g. max $\pm 1.5^\circ\text{--}2.5^\circ$).
  3. Apply subtle landing compression dip on jump/fall impact.

## Planned Deliverables
1. Camera tilt parameter configuration in `actors/player/player.gd` / camera rig.
2. Smooth critically-damped spring or exponential decay for tilt recovery.
3. Verification that mouse aim precision remains unaffected during subtle tilt.
