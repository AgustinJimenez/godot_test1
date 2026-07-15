# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

First-person survival horror game (Resident Evil-style scarcity) in **Godot 4.6** (Forward+, Jolt physics), written in **GDScript**. This is a learning sandbox: when building systems, briefly explain the Godot concepts involved rather than delivering code silently.

**`docs/PLANNING.md` is the design source of truth.** It holds the milestone roadmap (work in M-order), the Decisions Log (append a row when a design call is made), and open questions with the milestone where each gets decided. Check off roadmap items as they land.

## Commands

The `godot` binary is on PATH (Godot 4.6 mono build).

```sh
godot --headless --import          # reimport assets + register class_name scripts; run after adding files outside the editor
godot --headless --quit-after 10   # boot the main scene for N frames; smoke test for runtime errors
godot --path . res://levels/<scene>.tscn   # run a specific scene
```

There are no unit tests; verification is done by exercising scenes. The established pattern: write a throwaway `levels/_<name>_demo.tscn` + script that drives the player via `Input.action_press()` and direct rotation, record it with Movie Maker mode, inspect frames, then **delete the demo files before committing**:

```sh
godot --path . --write-movie /tmp/out/frame.png --fixed-fps 24 --resolution 1280x720 res://levels/_demo.tscn --quit-after 180
ffmpeg -y -framerate 24 -i /tmp/out/frame%08d.png -c:v libx264 -pix_fmt yuv420p out.mp4
```

Demo scripts that must keep running while the tree is paused (e.g. while an overlay is open) need `process_mode = 3` (ALWAYS) on their root.

Headless import of the FBX packs prints `Can't open file ... Clients/JohnGalt/...` errors — these are broken absolute texture paths baked into the MotusMan FBXs; ignore them (fix at runtime is a material override with `assets/models/pistol_starter/MotusMan/sourceimages/MCG_diff.jpg`).

## Architecture

Scene composition flows: `playground.tscn` (main scene) = `test_room.tscn` (pure environment, no player) + `player.tscn`. Environment scenes stay player-agnostic; game scenes compose them. `animation_preview.tscn` similarly wraps the test room to preview the FBX animation packs.

**Interaction pattern (used for everything the player touches):** an `Interactable` (plain Node, `components/interactable.gd`) is added as a child *named exactly "Interactable"* of any CollisionObject3D. The player's `RayCast3D` hits the collider, calls `get_node_or_null(^"Interactable")`, shows its `prompt`, and calls `interact(player)` on E; the owner (door, pickup, note) connects to its `interacted` signal. New interactables follow this recipe — do not subclass the player or hardcode types.

**Items are `Resource`s:** `items/item.gd` (`class_name Item`) defines the schema; concrete items are `.tres` files in `items/`. World pickups (`levels/props/item_pickup.tscn`) and inventory slots reference the same resource, so identity comparison (`slot["item"] == item`) is how ownership checks work (e.g. door `required_item`). The inventory (`components/inventory.gd`, Node child of Player) emits `changed`; UI refreshes reactively from that signal only.

**HUD contract:** `ui/hud.gd` lives inside `player.tscn`, registers in group `"hud"`, and runs with `PROCESS_MODE_ALWAYS`. World objects reach it via `get_tree().get_first_node_in_group(&"hud")` and call `toast()`, `show_note()`, `set_prompt()`. Overlays (note, inventory) pause the tree; the HUD closes them itself because it still processes while paused. The player is left `PAUSABLE` on purpose — pausing is what freezes gameplay.

**Player rig:** yaw rotates the `CharacterBody3D`, pitch rotates `HeadPivot`; camera, flashlight, and interact ray hang off the camera. Discrete input in `_unhandled_input`, continuous state polled in `_physics_process`. No jump, by design.

**Physics layers** (named in project settings): 1 world, 2 player, 3 enemies, 4 interactables, 5 projectiles, 6 ai_perception. Conventions: player collides with mask 1 only; pickups/notes are Area3D on layer 4 with mask 0; the interact ray uses mask 9 (world + interactables) with `collide_with_areas`; a solid interactable door is layer 9 so it both blocks and is hittable.

## Conventions

- Static typing everywhere in GDScript; `&"action"` StringNames for input actions; input actions only (never key checks) — the map lives in `project.godot`.
- Composition over inheritance: reusable behaviors are child Nodes (`components/`), not base classes. Signals up, calls down.
- snake_case files/functions, PascalCase nodes/scenes; scene + its script live side by side (`actors/player/`, `levels/props/`).
- `.tscn`/`.tres` files are hand-editable text; when writing them, `load_steps` = total ext+sub resources + 1.
- Commit at milestone boundaries with a summary of what the milestone added.
