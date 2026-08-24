# 003: Physical Bone Ragdoll Simulation and Knockdown

## Overview
Implement physics-driven ragdoll simulation using Godot's `PhysicalBone3D` hierarchy on the MotusMan / character skeleton for fatal hits, heavy enemy impact knockdowns, and smooth get-up blending.

## Concept & Reference
- **Reference**: `ragdoll` state and `physical_bones_start_simulation()` in AMSG's `CharacterMovementComponent`.
- **Approach**:
  1. Build and tune physical bone collision shapes and 6DOF/cone constraints on the MotusMan skeleton.
  2. Switch collision layers and trigger physical simulation on severe damage or death.
  3. Snapshot pelvis/spine transform upon coming to rest to blend seamlessly into get-up animations.

## Planned Deliverables
1. `PhysicalBone3D` ragdoll rig configuration on the player and enemy character skeletons.
2. Ragdoll trigger and recovery state management in `actors/player/player.gd` and enemy AI.
3. Test harness verifying ragdoll activation, impact momentum transfer, and reset.
