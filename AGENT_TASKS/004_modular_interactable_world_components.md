# 004: Modular Interactable World Components

## Overview
Implement a reusable, component-based world interaction framework for interactive survival horror facility props (light switches, power breakers, valve wheels, keycard readers, electronic keypads, and barricade latches).

## Concept & Reference
- **Reference**: `Interactable` and `InteractableLight` architecture in AMSG's `addons/AMSG/Interactable/`.
- **Approach**:
  1. Base `InteractableComponent` (`Node3D` / `Area3D`) exposing prompt text, required key/item, state signals, and interaction verb.
  2. Specialized child components (`InteractableSwitch`, `InteractableLight`, `InteractableDoorLock`, `InteractableContainer`).
  3. Seamless integration with player raycast interaction and HUD prompt display.

## Planned Deliverables
1. `core/interaction/interactable_component.gd` and specialized interactable subclasses.
2. Signal-driven light switch and power breaker sample props for the facility greybox.
3. Test map verifying player interaction, state persistence, and UI prompt response.
