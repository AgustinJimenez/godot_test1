# Survival Horror FPS — Project Plan

**Engine:** Godot 4.6 (Forward+, Jolt Physics)
**Language:** GDScript
**Genre:** First-person survival horror, scarcity-driven (Resident Evil-style resource pressure)
**Setting:** Abandoned research facility
**Goal:** Learning sandbox — build each system properly to learn Godot FPS/horror development. No shipping pressure, but every system should be built as if it could ship.

> **Status (2026-07-18):** M0–M4 done. Player locomotion uses the retargeted UAL unarmed set, including jump, roll, alternating punches, interaction/pickup actions, and an experimental right-hand flashlight pose copied from UAL2 `Idle_Lantern`. The test room includes labeled action-preview stations and the P/Esc menu includes a controls guide. The shambler (patrol/investigate/chase/attack/search, `NavigationAgent3D` + vision cone + hearing) is live in `test_room.tscn` and `nature_playground.tscn` on runtime-baked navmeshes. The nature sandbox also exercises model-backed inventory pickups, right-hand equipment, and melee damage. Next up: **M5 — Survival pressure** (flashlight battery, scarcity tuning, safe-room save/load). Main scene is `levels/playground.tscn`; controls: WASD / Shift sprint / Space jump / X roll / Q punch or melee / C crouch / F flashlight / E interact / Tab inventory / LMB fire / RMB aim / R reload / V camera / P or Esc menu.

---

## 1. Vision

You wake up in a decommissioned underground research facility. Power is failing, sections are locked down, and something is loose in the dark. Ammo, healing items, and light sources are scarce — every encounter is a decision: fight, sneak, or run.

**Design pillars:**

1. **Scarcity creates tension** — the player should always feel one bad fight away from trouble. Combat is a *costly choice*, not the default answer.
2. **The facility is a puzzle box** — interconnected areas, locked doors, keys/fuses/codes, shortcuts that loop back. Metroidvania-lite navigation.
3. **Darkness is a resource** — flashlight with limited battery, sparse working lights, enemies react to light and sound.
4. **Readable dread over jump scares** — audio cues, environmental storytelling, and anticipation do the heavy lifting.

**Reference games:** Resident Evil (resource loop, item boxes), Alien: Isolation (facility atmosphere), Amnesia (light/darkness), Signalis (scarcity tuning).

---

## 2. Core Gameplay Loop

```
Explore area → find items/notes/keys → manage inventory
     ↑                                        ↓
unlock shortcut ← solve obstacle ← encounter enemy (fight / evade / flee)
```

Session-level loop: push into unknown territory low on resources → find a safe room → bank progress → push further.

---

## 3. Systems Breakdown

Each system is a self-contained learning unit. Rough build order in §5.

### 3.1 Player Controller (FPS)
- `CharacterBody3D` + capsule, camera on a neck/head pivot
- Walk, sprint (limited stamina), crouch, lean (optional, later)
- Head-bob and camera tilt kept subtle — horror pacing is slow
- Interaction ray (`RayCast3D`) with "look at → prompt → press E" flow
- **Learn:** input handling, physics movement, camera rigs

### 3.2 Interaction System
- `Interactable` component (Area3D or interface-style script) — doors, pickups, switches, notes, save points
- Doors: openable, locked (key item), jammed (one-way until opened from other side)
- **Learn:** composition with nodes, signals, groups

### 3.3 Inventory & Items
- Grid or slot-limited inventory (limited slots = scarcity pressure)
- Item resources defined as `Resource` (.tres) — name, icon, stack size, use effect
- Item types: weapons, ammo, healing, key items, readables (notes/documents)
- Combine items (e.g., herb + herb) — optional, later
- **Learn:** custom Resources, UI (Control nodes), drag & drop

### 3.4 Weapons & Combat
- Hitscan pistol first; shotgun later; melee fallback (weak, last resort)
- Ammo pulled from inventory; deliberate reload; no crosshair sway spam — slow, heavy gunfeel
- Damage system via a `Health` component reused by player and enemies
- **Learn:** raycasting damage, animation players, recoil/feedback (sound, muzzle flash, hitstop)

### 3.5 Enemy AI
- Start with ONE enemy type done well: a shambler (slow, tanky, relentless)
- States: idle/patrol → investigate (heard sound) → chase (seen player) → attack → search (lost player)
- `NavigationAgent3D` for pathfinding; vision cone + hearing radius for perception
- Later: a second, faster enemy to force different tactics
- **Learn:** state machines, NavigationServer, perception systems

### 3.6 Light & Darkness
- Flashlight (SpotLight3D) with battery drain; batteries are inventory items
- Facility mostly dark; a few flickering/emergency lights for navigation landmarks
- Enemy perception influenced by player's light (flashlight on = easier to spot)
- **Learn:** Godot 4 lighting, shadows, environment/fog, performance budgeting

### 3.7 Sound & Atmosphere
- Ambient bed per zone (hums, drips, distant clangs) via `AudioStreamPlayer3D`
- Sound propagation matters for AI (running is loud, crouch-walk is quiet)
- Dynamic tension layer: music/stinger when enemy is hunting
- **Learn:** audio buses, 3D audio, occlusion tricks

### 3.8 Save System & Safe Rooms
- Manual saves at safe-room terminals only (classic survival horror pressure)
- Serialize: player state, inventory, world flags (doors unlocked, items taken, enemies dead)
- Safe rooms: distinct calm ambience, guaranteed no enemies
- **Learn:** serialization (JSON or ConfigFile), autoloads, world-state flags

### 3.9 UI/UX
- Diegetic-leaning HUD: minimal — health indicator, ammo only when aiming, interaction prompts
- Inventory screen (pauses or slows game — decide during build)
- Note/document reader; pause menu; settings (sensitivity, volume, brightness)
- **Learn:** Control nodes, themes, focus handling

### 3.10 Level / World
- One facility hub with 3 wings (e.g., Atrium → Labs, Maintenance, Medical)
- Greybox everything first; art pass much later (or never — sandbox!)
- Locked-door progression: fuse for elevator in Labs, keycard in Medical, etc.
- **Learn:** GridMap or CSG for greyboxing, scene organization, occlusion culling

---

## 4. Technical Conventions

### Imported asset packs (in `assets/models/`)

| Pack | Contents | Earmarked for |
|---|---|---|
| `action_adventure_pack` | Mixamo-skeleton clips (idle, walk, run, sneak, cover…) + "The Boss" skinned character | **M4 enemy** — clips share one skeleton, so they load into any Mixamo character's AnimationPlayer at runtime (see `tests/manual/animation/animation_preview.gd`) |
| `pistol_starter` | MoCap Online MotusMan character, 1911 pistol model, pistol aim/walk/fire animation set | **M3 reference** for weapon handling; the 1911 could become the viewmodel weapon |
| `kaykit_fantasy_weapons` | KayKit Fantasy Weapons Bits free pack, CC0; 31 glTF weapon and shield models with one shared texture | Initial content for the generic object catalog/browser and later pickup/equip experiments |
| `rusty_knife` | User-generated GLB; 19,080 triangles, two embedded 1024 WebP textures; distribution license still needs confirmation | First realistic knife used to exercise generated-asset inspection, object categorization, pickup, inventory, right-hand calibration, and melee |
| `stylized_nature_megakit` | Curated 21-model subset of Quaternius Stylized Nature MegaKit Standard, CC0; glTF geometry plus only referenced textures | `nature_playground.tscn` exploration sandbox and future exterior prototypes |
| `universal_animation_library` | Quaternius UAL1 in-place animation library and mannequin, CC0 | Current unarmed player locomotion/actions and raw comparison source |
| `universal_animation_library_2` | Quaternius UAL2 in-place animation library and mannequin, CC0; 42 non-conflicting clips exposed in Character Editor | Candidate held-object poses, especially `Idle_Lantern` and `Walk_Carry`; debug-only until manually accepted |

Notes: MotusMan FBXs reference textures by absolute paths from the author's machine — reapply `MotusMan/sourceimages/MCG_diff.jpg` as a material override. `tests/manual/animation/animation_preview.tscn` previews the older FBX packs inside the test room; Character Editor's Compare mode previews UAL1/UAL2 beside their retargeted MotusMan result. The UAL packs include their CC0 license files. ⚠️ If this repo ever goes public, check the non-UAL pack licenses first (game use OK, raw FBX redistribution generally not).

### Project structure
```
res://
  actors/            # player/, npcs/<body-type>/ — scene + scripts together
  components/        # reusable nodes: health.gd, interactable.gd, hurtbox.gd
  items/             # item .tres resources + item scene(s)
  levels/            # facility scenes, greybox assets
  systems/           # autoloads: game_state.gd, save_manager.gd, audio_manager.gd
  ui/                # HUD, inventory, menus
  assets/            # shared art/audio/fonts (sfx/, music/, models/, textures/)
  docs/              # this file & design notes
```

### Conventions
- **Scenes-as-components:** favor composition (a `Health` node, an `Interactable` node) over deep inheritance.
- **Signals up, calls down:** children emit signals, parents call child methods. Cross-system communication through a small set of autoload event buses only when necessary.
- **Static typing everywhere** in GDScript (`var speed: float = 4.0`, typed arrays) — better errors and autocomplete.
- **snake_case** files/functions/variables, **PascalCase** nodes/classes/scenes.
- One scene = one responsibility; instance, don't copy-paste.
- Input actions defined in the Input Map (never hardcode keys): `move_*`, `sprint`, `crouch`, `interact`, `fire`, `aim`, `reload`, `flashlight`, `inventory`, `pause`.

### Physics layers (plan now, avoid pain later)
| Layer | Name |
|---|---|
| 1 | world |
| 2 | player |
| 3 | damageables |
| 4 | interactables |
| 5 | projectiles/hitscan |
| 6 | ai_perception |

---

## 5. Roadmap (Milestones)

Ordered so each milestone produces something playable and teaches new ground. Tick them off here as we go.

### M0 — Project setup ✅
- [x] Folder structure, input map, physics layers, .gitignore/git init
- [x] Greybox test room with lighting (placeholder camera until the M1 player exists)

### M1 — Walking simulator ✅
- [x] FPS controller: walk/sprint/crouch/jump, stamina, mouse look
- [x] Interaction ray + first interactables (door, pickup, readable note)
- [x] Flashlight toggle (no battery yet)

### M2 — Inventory & items ✅
- [x] Item resource definitions (.tres), pickup → inventory flow
- [x] Inventory UI (8 slots, stacking), use/drop/examine
- [x] Key item unlocks a locked door (keycard, consumed on use)

### M3 — Combat ✅
- [x] Pistol: aim, fire, reload from inventory ammo, feedback (sfx/flash/decals)
- [x] Health component + damage, player hurt/death, healing item
- [x] Target dummies to shoot

### M4 — First enemy ✅
- [x] Shambler with patrol/investigate/chase/attack/search state machine
- [x] Navigation mesh in test level, hearing + vision perception
- [x] Full loop test: sneak past OR spend scarce ammo (verified via scripted demo: heard → investigated → lost interest → seen → chased → attacked/damaged player)

### M5 — Survival pressure
- [ ] Flashlight battery drain + battery items
- [ ] Ammo/health scarcity tuning pass in a dedicated test map
- [ ] Safe room + terminal save/load (full serialization)

### M6 — The facility (vertical slice territory)
- [ ] Greybox hub + one wing with locked-door progression
- [ ] Ambient audio zones + tension music layer
- [ ] Notes/documents telling a first story fragment
- [ ] Playable 15-min slice: wake up → explore → survive → reach safe room

### M7+ — Stretch (pick whatever is most fun to learn)
- Second enemy type (fast/fragile) · shotgun · item combining
- Lean/peek, door-crack peeking · enemy that stalks between rooms
- Post-processing horror pass (film grain, vignette, fog volumes)
- Art pass on one room to learn the full asset pipeline

---

## 6. Decisions Log

| Date | Decision | Why |
|---|---|---|
| 2026-07-23 | Fit modular garments as generated asset copies by pushing nearby clothing vertices outside the base body to a small rest-pose clearance; preserve source assets and exclude outfit-authored skin primitives. Start with Male Peasant and validate deformation before applying the pipeline to every outfit. | Altering the garment fixes the actual geometry while keeping the complete body intact. The rejected UV/proximity maps could neither classify open garment shells reliably nor prevent intersections. Rest-pose clearance is only a first step because skin weights still determine whether that spacing survives animation. |
| 2026-07-23 | Restart modular-outfit composition from an unmasked baseline: render the complete base body plus clothing, and discard only the outfit's duplicate skin primitives. The attempted automatic proximity/UV-mask implementation is removed. | The mask alternated between erasing visible body geometry at collars/cuffs and exposing body through clothing, with results changing by viewing angle. The baseline makes source intersections explicit before choosing an authored modular-body or topology-aware replacement strategy. |
| 2026-07-20 | Native humanoid generation derives pelvis height from a horizontal mesh profile: center-plane occupancy locates the leg-to-pelvis merge, upper-body width locates the waist, and their midpoint is blended with a conservative prior after plausibility checks. The result and whether geometry or fallback was used are persisted as rig landmarks. | The former cross-section fitting adjusted only X/Z, leaving Hips and upper-leg Y fixed at 37% of height; on Zombie1 this put the hip line at the crotch even while other joints looked plausible. Numeric geometry landmarks make this class of error detectable without relying on an unregistered reference image or user observation, while the prior/fallback limits clothing-induced outliers. |
| 2026-07-20 | Native autorig skinning now retains extra candidate influences, smooths them for two conservative passes over actual triangle adjacency, and only then prunes and normalizes the four exported Godot weights. Learned mesh-to-rig projects remain optional external-provider research rather than embedded editor dependencies. | Neighbor smoothing reduces rigid deformation boundaries while topology prevents weights from crossing disconnected surfaces. UniRig's inference stack requires Python/PyTorch/CUDA, RigAnything's released code is noncommercial research-only, and control-rig frameworks such as Rigify/CloudRig/mGear do not solve mesh landmark inference or skin binding. |
| 2026-07-19 | Character Editor character selection is a persistent catalog: Import creates/registers an entry, the selector reads it, the adjacent menu renames it, `Reset Generated Rig` deletes only derived rig/profile data and restores the source model, and `Remove from Editor` deletes only the registration. Source model files are preserved by both destructive-looking actions. | Rigging is iterative and users need to retry generation without manually deleting project files. Separating catalog identity, immutable source, and regenerable derived assets makes the destructive boundary explicit and prevents an editor-management action from losing the original model. |
| 2026-07-19 | Character Editor inserts Rig between Character and Animation. It diagnoses skeleton and skin bindings, auto-maps common humanoid names, exposes manual core/toe/finger mapping, persists imported-character profiles beside the model, and blocks Animation until the required body chain is mapped. For a static neutral T/A-pose humanoid, the editor can generate a Godot-native `Skeleton3D`, anatomical-region vertex weights, `Skin`, and reusable rigged `.tscn`; external riggers remain fallbacks for complex topology and weight cleanup. | Retargeting requires both a semantic bone map and a deformable mesh. Keeping the first-pass generator inside the editor makes the experiment reproducible and inspectable without hiding a Blender round trip, while labeling its neutral-pose/weighting limits avoids presenting a heuristic as production-quality autorigging. |
| 2026-07-19 | Character Editor distinguishes read-only built-in animation packs from persistent user-managed `CharacterAnimationPackage` resources. The package menu supports create, rename, and delete; imports copy sources into a package-specific project folder, and opening a package lazily retargets its sources for the current character. Deleting a package preserves its copied source files. | Package metadata must survive editor and character changes, but retargeted `Animation` objects are target-skeleton-specific and should be rebuilt for the selected rig. Keeping deletion non-destructive prevents a metadata action from silently destroying imported source assets or shared dependencies. |
| 2026-07-19 | Character Editor uses a five-stage workflow: Character, Animation, Attachments, Pose, and Review. Interactive launches begin with no character, preset, animation, or attachment loaded; selecting a character exposes a static base pose before animation selection. Automation arguments continue to auto-load a character for deterministic CLI/MCP use. | Progressive disclosure keeps unrelated controls out of the way and makes the dependency order explicit. An empty initial session also prevents old flashlight state from appearing to be part of every new character or pose. |
| 2026-07-19 | Character Editor pose schema v3 stores an ordered collection of independently visible attachment slots; the panel edits one selected slot at a time and supports adding/removing down to zero. The primary slot is mirrored into legacy single-object fields, and schema-v2 presets remain loadable. Two-handed props remain one attachment plus a future off-hand contact/IK constraint. | Props can belong to either hand, belts, backs, or arbitrary skeleton bones, and a pose may require several at once. Keeping selection as an alias preserves the existing transform, camera, gizmo, and MCP workflows. Duplicating one two-handed weapon onto both hands would create two models and cannot enforce hand contact, so that problem needs a constraint rather than another prop slot. |
| 2026-07-19 | Character Editor's preset `Open` action uses a searchable visual pose library. Missing object-only thumbnails render once into a cache; selecting a card drives one manually rotatable/zoomable live 3D preview, and `Load Selected` applies the pose. The modal retains native-OS JSON Browse and the Object row retains raw 3D-file Browse. | The reusable unit is the complete saved contact pose, not only a model path: object, attachment, transforms, animation, and bone corrections must reopen together. Cached grid images keep browsing cheap, while one live viewport provides real model inspection without multiplying render cost per card. |
| 2026-07-19 | Debug item access uses an explicit `ItemCatalog` resource and grants through the normal `Inventory` API; the grouped Object List equips weapons through the player's existing equipment API. | An authored resource catalog remains deterministic in exported builds and gives tooling a reusable list without coupling gameplay UI to directory scanning. Reusing inventory/equipment paths keeps capacity, ownership signals, and held visuals consistent with world pickups. |
| 2026-07-19 | Confirmed player damage spawns a brief world-space contact burst; vivid-red NPC health bars appear only within 7 m while attacking or for 3 seconds after taking damage. NPC scratch damage fires once when playback crosses the clip's normalized 0.48 contact point, with range checked at that instant. Added a session-only `Show FPS` toggle to the Debug page. | Feedback is emitted only after `Health` accepts damage, so misses, dead targets, and refused damage cannot produce false hit confirmation. Contact position belongs to the weapon query, while health display reacts to `Health`/`NPCController` signals and stays unobtrusive outside close combat. Normalized animation timing remains aligned when clip length or playback speed changes; a fixed seconds-based windup did not. FPS is diagnostic rather than a persisted graphics quality setting. |
| 2026-07-19 | Replaced the model/archetype-named `Shambler` with a composed `HumanoidActor` + body-independent `NPCController`. The controller stores runtime-switchable disposition (friendly/neutral/suspicious/hostile) separately from behavior state (idle/patrol/investigate/chase/attack/search/flee); every controlled actor joins `npcs`, while only hostile actors join `enemies`. | “Enemy” is a relationship to the player, not an actor identity, and events such as damage can change it. Body shape still determines how intentions are executed: the current actor owns biped Mixamo animation and ground navigation, while a future wolf or flying creature can reuse the controller/state contract and stable components without inheriting humanoid skeleton assumptions. |
| 2026-07-19 | Added a project-wide `GraphicsSettings` autoload with persisted Low/Medium/High/Ultra/Custom presets and a Graphics tab in the pause menu. Runtime controls cover render scale, AA, directional shadows, SSAO, SSIL, fog, glow, VSync, and frame limit; SDFGI is deliberately excluded. | A persistent service keeps renderer state across current and future scenes while the HUD remains a presentation/navigation layer. Godot 4.6 Forward+ exposes these controls directly, so no addon is needed. SDFGI is not a safe generic toggle because scenes and meshes require GI-specific authoring and tuning. |
| 2026-07-19 | Mixamo zombie visuals receive a configurable 180-degree yaw offset under the `HumanoidActor` body; AI/perception/collision continue using Godot's parent-level `-Z` forward. | The live body-forward arrow exposed that the FBX meshes face authored `+Z` even while the authoritative actor faced its target. Their original walk/run hip tracks also travel in `+Z`, providing a sign-bearing diagnostic that the shoulder-cross facing axis could not. Separating visual correction from actor yaw supports future assets with different forward conventions. |
| 2026-07-19 | Added an exported shambler body-forward debug arrow, enabled in the current sandbox while enemy visual-facing is diagnosed. | The arrow inherits the authoritative `CharacterBody3D` transform and points along local `-Z`, separating an AI yaw problem from an imported model/skeleton forward-axis mismatch during live inspection. |
| 2026-07-19 | During chase, shambler velocity follows the navigation path while body facing tracks the player directly; the temporary player footstep-marker debug system and its menu control were removed. | Facing a path waypoint made an aggro enemy appear disengaged from its target, especially around path corners. Separating look direction from path velocity keeps attention readable. Footstep spheres had served their animation-diagnostic purpose and cluttered normal scene runs. |
| 2026-07-19 | Humanoid enemy strikes require facing within 12 degrees and lock body yaw through wind-up/contact/recovery. | Continuously steering toward a strafing player during a committed strike produces an unnatural rotating swivel and removes the player's ability to evade laterally. |
| 2026-07-19 | Game and scene runs start in a maximized desktop window rather than fullscreen. | Maximized mode uses the available display area for first/third-person inspection while retaining normal OS window controls and easier switching back to the editor. |
| 2026-07-19 | Removed proximity-only world pickup labels; the ray-driven HUD prompt is the single interaction indicator, and overlays clear it while gameplay is paused. | The world label appeared based only on distance even when the interaction ray could not pick up the item, producing two conflicting prompts. A key prompt should guarantee that pressing its key can perform the advertised action. |
| 2026-07-19 | Corrected shambler actor-facing yaw to `atan2(-direction.x, -direction.z)` for Godot's local `-Z` forward convention. | The previous positive-X formula rotated the authoritative body exactly away from its target: a player due east produced a west-facing body-forward vector. Imported visual forward is configured independently because the current Mixamo meshes use authored `+Z`. |
| 2026-07-19 | Enemy walk/run copies are converted to in-place clips by subtracting accumulated horizontal hip displacement over their timelines; navigation remains the only owner of world translation. | The imported Mixamo walk and run advance their hips roughly 1.75 m and 3.16 m per cycle. Playing those translating clips while also moving the `CharacterBody3D` made the visible character advance independently and snap to the animation origin on every loop. Removing only accumulated X/Z travel preserves vertical bob and cyclic stride motion. |
| 2026-07-19 | Melee damage lands at an explicit animation contact point rather than immediately on input. Hostile `HumanoidActor` NPCs use wind-up, contact-time range validation, recovery, and a retargeted UAL2 `Zombie_Scratch` one-shot; `Health.apply_damage()` returns and signals actual applied damage, including capped overkill. | Separating input, animation timing, hit discovery, and health arithmetic makes interrupted or escaped attacks miss correctly, guarantees one hit per swing, and keeps authored visual motion independent from damage rules. |
| 2026-07-18 | Added three initially hostile NPCs with Ch10/zombie-girl visuals to the nature sandbox on a runtime-baked navmesh and added item-defined melee damage/range through a composed `MeleeWeapon` capsule query; Q uses `Sword_Attack` for equipped KayKit weapons and remains a weak punch when unarmed. `HumanoidActor.character_scene` selects any compatible Mixamo visual, and `character_bone_prefix` rewrites its small action-pack animation set for numbered-prefix rigs such as Ch10's `mixamorig5_`. | This reuses the established `Health` discovery contract for both player and NPC damage, keeps combat behavior out of `Item` resources, and makes one query work for first/third-person because aim remains camera-driven while the held model remains skeleton-driven. A capsule covering the complete reach is more forgiving and avoids the close-range dead zone produced by a sphere placed only at maximum reach. Separating the visual scene from the archetype avoids duplicating navigation/perception/state logic for each zombie skin. |
| 2026-07-18 | Reusable 3D assets are described by `ObjectDefinition` resources collected in explicit `ObjectCatalog` resources; the first catalog contains the CC0 KayKit fantasy weapon pack and is browsable in `tools/object_library/object_library.tscn`. Gameplay `Item` resources independently carry an optional world scene with separate pickup and held transforms. `WEAPON` items equip visually through a right-hand `BoneAttachment3D`; attack behavior remains a separate component. | A searchable authoring catalog answers which assets exist and how to preview them without coupling asset discovery to the player's eight-slot ownership inventory. Items opt into gameplay and ownership explicitly, one model-backed path handles placed/dropped/held visuals, and separating visual equipment from combat avoids forcing swords, shields, firearms, and future tools into one behavior class. |
| 2026-07-19 | Weapon inventory entries keep the broad `Item.Kind.WEAPON`, while the authoring catalog uses concrete families such as `Knives`, `Swords`, and `Axes` plus searchable behavior tags such as `melee`. The catalog was renamed from the source-specific KayKit catalog to the general `weapon_models` catalog when the rusty knife was added. | Inventory behavior should not require a new enum value for every weapon silhouette. Concrete categories remain useful for asset browsing, and a source-neutral catalog can contain models from multiple licensed packs without misrepresenting their origin. |
| 2026-07-18 | Added `nature_playground.tscn` as a composition of the existing player and a player-agnostic `nature/nature_environment.tscn`; imported a curated glTF subset of the CC0 Stylized Nature MegaKit rather than the full OBJ/FBX/glTF download | The sandbox exercises the real first/third-person controller in an exterior environment while preserving the established scene-composition boundary. glTF retains material/texture references cleanly in Godot, and selecting only the trees, rocks, path, and ground-cover assets used by the scene avoids three duplicate source formats and unnecessary repository weight. |
| 2026-07-18 | Project checks use pinned `gdtoolkit`/`pre-commit` dependencies and one `scripts/check.sh` entrypoint, enforced by both a local pre-commit hook and GitHub Actions; the 1000-line limit stays in place and `class-definitions-order` stays disabled | Reproducible, automatic lint/import/parse validation prevents tool-version drift and forgotten manual checks. The current size threshold guards against renewed file growth without forcing another arbitrary split, while declaration reordering would add churn rather than correctness coverage. |
| 2026-07-15 | GDScript over C# | Fastest iteration for learning; best docs/examples for Godot 4 |
| 2026-07-15 | Scarcity survival over hide-only or action | Richest system mix to learn (inventory, combat, AI, economy) |
| 2026-07-15 | Abandoned facility setting | Contained scope, interior lighting control, classic puzzle-box layout |
| 2026-07-15 | One enemy type first | Depth over breadth; AI state machine is the learning goal |
| 2026-07-15 | Saves only in safe rooms | Core to the tension model; simpler serialization scope |
| 2026-07-15 | No jumping | Classic survival horror; keeps level design and animation scope tight |
| 2026-07-16 | Reversed the no-jump constraint for experimentation: Space now applies vertical velocity and plays UAL `Jump_Start` → `Jump` → `Jump_Land` phases | This project is primarily a Godot learning sandbox, so testing a complete airborne animation/physics state is more valuable than preserving the earlier genre restriction. Level design still does not require jumping. |
| 2026-07-16 | Added an action-animation priority layer: X rolls with a short directional impulse, Q alternates jab/cross, E interactables request interact/pickup clips, and flashlight-on idle uses `Idle_Torch`; labeled test spheres and a menu controls guide expose the experiments | One-shot clips must temporarily outrank the locomotion selector or they are replaced on the next physics tick. Keeping the request as a semantic animation name on `Interactable` preserves the existing generic interaction contract. |
| 2026-07-16 | Flashlight visual is a scaled GLB attached to MotusMan's `LeftHand`; the functional spotlight remains camera-owned and offset left | `Idle_Torch` authors a forward left-hand grip, and `BoneAttachment3D` keeps the prop synchronized with it. Separating the beam from the animated wrist preserves predictable view-aligned illumination while still rendering the held object correctly in first and third person. |
| 2026-07-17 | Added CC0 UAL2 to the grouped animation viewer and copied `Idle_Lantern` into the local looping `unarmed_torch_idle` gameplay state; moved the experimental prop attachment and beam offset to the right side | UAL2 shares UAL1's complete mannequin/finger skeleton, and `Idle_Lantern` supplies a purpose-authored right-hand held-object pose. Keep source assets immutable and tune only the local retargeted state/additive arm layer. |
| 2026-07-15 | Crouch = toggle, sprint = hold; crouch on C (not Ctrl) | Comfort defaults; Ctrl collides with macOS shortcuts |
| 2026-07-15 | Reading a note pauses the game | Safe reading, RE-style; HUD runs with PROCESS_MODE_ALWAYS to close it |
| 2026-07-15 | Slot inventory (8 slots + stacks), not RE grid | Same learning value, third of the UI code; can evolve later |
| 2026-07-15 | Keys are consumed on unlock | Scarcity flavor; one key = one door |
| 2026-07-15 | Hitscan pistol via direct space-state ray query | Planned in §3.4; instant feedback, no projectile bookkeeping to learn yet |
| 2026-07-15 | Weapon auto-equips while its item is in inventory (single weapon slot) | Simplest ownership model; weapon-switch UI can come with the shotgun |
| 2026-07-15 | Magazine lives on the weapon, reserve ammo lives in inventory stacks | Reload = inventory transaction, keeps ammo scarcity visible in the UI |
| 2026-07-15 | Consumable effects are data on Item (`heal_amount`), not item subclasses | One resource schema; using at full health refuses to consume the item |
| 2026-07-15 | Player death pauses tree + YOU DIED overlay, E reloads the scene | Placeholder until M5 save/load decides real death flow |
| 2026-07-15 | First-person body: MotusMan mesh under the player, head bones collapsed into the chest each frame, camera 0.25m ahead of the face | Body awareness (see legs/shadow); MotusMan IPC clips cover idle/walk/jog/crouch with no retargeting |
| 2026-07-15 | Mirror prop is a puppeted body double (position/yaw/animation mirrored each frame), not a live SubViewport reflection | Godot 4.6 SubViewport/ViewportTexture rendering breaks once its scene is instanced inside another (godotengine/godot#115402); the double sidesteps the engine bug entirely — same trick classic RE mirrors use |
| 2026-07-15 | Eye camera position is solved (angle clamp + binary-searched chest clearance), not just following raw look pitch | Full-head debug view let the camera's near clip end up inside the hood/collar past ~40° down; a fixed angle clamp stopped the chin-into-chest visual but not the camera itself, so eye position now also enforces a minimum distance from the chest bone |
| 2026-07-15 | Debug tooling: P opens a menu to edit `eye_offset` live, V shows an external camera with a red eye marker + FOV wireframe gizmo | Iterating on camera placement previously required re-recording Movie Maker clips; this makes it self-service in-game |
| 2026-07-16 | Independent head look: mouse yaw turns the head up to `head_yaw_limit_deg` (75°) before the body starts rotating; the body also auto-turns to catch up while actively moving | Real necks don't swivel a full 180 — RE-style body-awareness games (and real anatomy) turn the head first, body follows. Head and body yaw are stored as plain floats and only ever written into `head.rotation`, never read back out of it — Godot's Euler decomposition is unstable near the pitch extremes (gimbal lock), and reading it back to accumulate the next frame's value compounded that instability into a visible spin under sustained diagonal mouse input |
| 2026-07-16 | Movement direction follows combined body+head yaw, not just body yaw | Otherwise glancing sideways while holding W would strafe instead of walking that way, once head and body could differ |
| 2026-07-16 | Eye-clearance solve extended to per-bone radii (chest/shoulders/arms) and to yaw, not just pitch | The chest-only, pitch-only version (previous row) missed two things: turning the head to the side brings the shoulder/arm into range even before any downward pitch, and the shoulder/arm joints sit too close to the head bone for one shared clearance radius to be achievable — each bone now has its own minimum distance tuned to what's geometrically reachable |
| 2026-07-16 | Debug eye marker has shadow casting explicitly disabled | It's invisible from the FP camera itself (inside the near-clip distance) but shadows ignore camera visibility, so it was showing up as a sphere-shaped blob in the player's own shadow where the (collapsed, low-shadow) head should be |
| 2026-07-16 | Head is always visible now — removed the collapse-into-chest trick entirely, `_bend_head_bones()` runs unconditionally | The earlier rejection of full-head mode ("MotusMan wears a hood wrapping the eye point") predates the per-bone yaw+pitch eye-clearance solve; verified clean at neutral look, moderate glances, and hard extremes (left+down) with the solve in place, so the fallback is no longer needed. Own shadow now shows a proper head silhouette too |
| 2026-07-16 | `head_yaw_limit_deg` tuned down from 75° to 60° | Playtest feel — narrower head-alone turn range before the body catches up |
| 2026-07-16 | Neck/head mesh bend: lowered `MAX_BEND_UP_DEG` 75°→60°, and added a small forward torso lean (Spine/Spine1/Spine2, 4%/5%/6% of the clamped pitch) on look-down | This rig's linear-blend skin stretches visibly ("candy wrapper" artifact) on the Neck-Head joint past ~72-75° of bend; 60° leaves real margin. Torso lean is deliberately subtle - a stronger version (tried live, reverted) pushed the cumulative spine→neck→head rotation back past the same stretch threshold |
| 2026-07-16 | Head bend's pitch and yaw are radially clamped together (as one 2D vector, magnitude ≤ `MAX_BEND_UP_DEG`), not just independently per axis | Each axis clamped on its own still let combined near-limit pitch+yaw compose into a larger rotation than either alone, re-triggering the same skin-stretch artifact; only affects the visible bend, the camera's actual look direction is untouched |
| 2026-07-16 | Unarmed walk clip sourced from Universal Animation Library (Godot-native-retargeting-labeled, CC0), not the Mixamo action_adventure_pack or "Human Basic Motions FREE" | Needed a plain walk with no gun-aim pose; UAL was the pack that actually retargeted cleanly onto MotusMan (see next row) |
| 2026-07-16 | Retargeting formula is `target_rest.basis * (src_rest.basis.inverse() * src_pose_quat)` per bone (delta-from-own-rest, reapplied to target's own rest), and the whole spine chain (not just arms) is excluded and held at the relaxed-idle pose instead of retargeted | Copying raw local rotations is wrong when source/target rest orientations differ (MotusMan's bone-forward axis differs from UAL/Mixamo's). The delta formula works for spine/legs but the arms still came out T-pose-like even when individually held — root cause was their *parent* (Spine2) still being animated by the retargeted clip and cascading a wrong orientation into otherwise-correct child bones; holding the full spine chain fixed it |
| 2026-07-16 | AnimationPlayer crossfades need an explicit constant-value track for any bone that should stay put, not just "leave it untracked" | A bone with no track in the new clip doesn't freeze at its last pose after the blend completes — it settles back toward the skeleton's rest pose. `_bake_held_track()` bakes a real 2-keyframe constant track instead |
| 2026-07-16 | Shambler patrol/investigate/chase/attack/search state machine, built as a plain `CharacterBody3D` + `NavigationAgent3D`, reusing the animation_preview.gd clip-borrowing trick (idle/walking/running/hard-landing-as-death from action_adventure_pack, no retargeting needed since it's the native Mixamo rig) | Matches §3.5; "The Boss" shares a skeleton with the pack's standalone clip files, so unlike the player's MotusMan work, no retargeting math is needed here |
| 2026-07-16 | Room navmesh is baked at runtime in `nav_bake.gd` (`NavigationRegion3D.bake_navigation_mesh(false)`), not pre-baked and checked in | No editor-driven baking step in this headless-first workflow; the room is small and static so a runtime bake at load is cheap enough |
| 2026-07-16 | Navmesh source geometry uses `parsed_geometry_type = STATIC_COLLIDERS` + `geometry_source_geometry_mode = GROUPS_WITH_CHILDREN` (group joined via code in `nav_bake.gd`, not via a hand-authored `groups=[...]` line in the .tscn), baked after a 0.5s real-time wait | The room's CSGBox3D geometry lives under a sibling "Geometry" node, not under the NavigationRegion3D itself, so the default ROOT_NODE_CHILDREN source mode found nothing (0 polygons). Hand-authoring `groups=["navmesh_source"]` directly in the .tscn was silently ignored by Godot 4.6 (`get_nodes_in_group()` came back empty) — joining the group from code in `_ready()` is what actually works. CSGShape3D's collision body is built via a deferred call, so the bake also needs to wait for that; a real-time wait proved more reliable than a fixed physics-frame count, which raced under load |
| 2026-07-16 | Shambler death plays the pack's "hard landing" clip once (`LOOP_NONE`) instead of a procedural topple tween | The generic `rotation:x` topple tween (reused from `target_dummy.gd`) visually sank the humanoid mesh into the floor when rotated 90° around its own origin — the target dummy's simple prop shape hid this, the Boss rig didn't. There's no dedicated death clip in the pack, but "hard landing" reads as a believable collapse and reuses the existing clip-borrowing pattern instead of new tween math |
| 2026-07-16 | AI vision cone + hearing check extracted into `components/perception.gd` (a plain Node, added as a child and used directly via `@onready`, not looked up by name like Health/Interactable) | Movement and animation stay per-entity (player is camera/input-driven with independent head-look, the shambler is nav-agent/AI-driven with no camera - genuinely different control models, not worth forcing into one shared piece), but vision+hearing is identical logic any future AI entity will want with just different tuning. Matches the project's composition-over-inheritance convention; extracted now, before a second enemy duplicates it, rather than after |
| 2026-07-16 | `NavigationAgent3D.path_desired_distance`/`target_desired_distance` bumped from the 0.5 default to 1.0 on the shambler | The runtime-baked navmesh's walkable surface sits at Y=0.5 (voxel-quantized by `cell_height`) while the actual floor is Y=0.0, so the 3D distance from the agent to its first path waypoint was ≈0.5 - exactly on the default threshold, and the "close enough, advance to the next waypoint" check never fired. The agent looked completely stuck (correct path computed via `NavigationServer3D.map_get_path()`, but `get_next_path_position()` never advanced past waypoint 0, even across many seconds and re-set target values) until the threshold was pushed safely past that gap |
| 2026-07-16 | Reverted the UAL-retargeted `walk_relaxed` clip; unarmed and armed movement both use the single native MotusMan aim-pose walk again, same as before that work started | Looked fine in recorded frames but read as stiff/mannequin-like in actual play - the HELD_BONES workaround (whole spine+arm chain frozen, since directly retargeting them lands in a T-pose-like result every time) is too visible over animated legs at interactive framerates and viewing angles. A procedural arm-swing patch on top of the held pose was tried as a quick fix and also rejected on sight. Reverted `actors/player/player_body.gd` to its pre-retarget state (`git checkout main --`) rather than keep patching; the UAL asset (`assets/models/universal_animation_library/`) is left in the repo for a future attempt. Properly fixing this needs a real retargeting approach for the arms specifically - most likely Godot's built-in humanoid retargeting (BoneMap + SkeletonProfileHumanoid) instead of the hand-rolled delta-from-rest math, deferred because it needs editor-driven setup this headless-first workflow has avoided so far |
| 2026-07-16 | `walk_relaxed` reinstated; retargeting rebuilt around two techniques instead of the single delta-from-rest formula: (1) rotation deltas for spine/legs/hips are now computed and reapplied in GLOBAL (skeleton-root) space rather than each bone's parent-relative local space, and (2) the arm chain (shoulders/upper arms/forearms) retargets via a position-based "swing" - matching where the bone points (parent-to-child direction in world space) instead of transferring its rotation at all | Measuring both rigs' actual rest poses (dumped bone-by-bone) showed they're both genuine T-poses related by one consistent 180° rotation, not a T-pose/A-pose mismatch as suspected - so the old local-space formula's failure mode was hop-count compounding: each parent hop in a chain re-introduces the same small convention mismatch, and arms sit 6-7 hops deep (through the whole spine) versus 3-4 for legs, exactly matching which bones worked and which didn't. Global-space deltas remove the compounding, which alone fixed spine/legs cleanly, but arms *still* spread into a T-pose - confirmed by re-testing with a proper 3rd-person capture (the original attempts likely only ever checked a narrow viewing angle that hid it). Position-based swing sidesteps rotation-transfer entirely for the specific bones that kept failing: positions carry no "which local axis means forward" ambiguity, so there's nothing left to get backwards. Hands are still held (no further mapped child to derive a swing direction from, and not very visible on this rig at typical camera distance) |
| 2026-07-16 | `_retarget_clip` composes the source skeleton's GLOBAL pose by hand (`_manual_global_pose`, walking the parent chain via the plain `get_bone_pose()` getter) instead of calling `Skeleton3D.get_bone_global_pose()` | The commit above still shipped a real, separate bug the recorded/screenshot verification missed entirely: `get_bone_global_pose()` reads from a cache that only refreshes on the engine's own per-frame update - baking runs synchronously inside `_ready()` with no such frame ever happening, so it kept returning one stale snapshot for the *entire* clip regardless of how many times `set_bone_pose_rotation`/`position` were called first (confirmed by dumping actual baked keyframe values: every bone was bit-identical across all 41 samples, both the global-space delta bones and the swing bones alike). `force_update_all_bone_transforms()` didn't help either - apparently still deferred rather than synchronous. In-game this looked like the character sliding forward with the whole body locked in one frozen pose ("floating"), which is a materially different failure mode from the T-pose-spread bug fixed in the same commit - overall movement and camera tracking were enough to make screenshots look plausible at a glance, which is exactly why it slipped through recorded-frame verification and needed an actual playtest to surface. Numeric checks (dumping real keyframe values, printing a bone's position over time) are catching what visual spot-checks alone have now missed twice on this feature |
| 2026-07-16 | Player locomotion in both first- and third-person views uses the retargeted UAL unarmed set (`Idle`, `Walk`, `Sprint`, `Crouch_Idle`, `Crouch_Fwd`) even while the pistol viewmodel is equipped; native MotusMan aim clips remain debug references only | The MotusMan pack's default locomotion is authored as a persistent gun-aim pose, which made ordinary exploration read as armed aiming. Camera mode does not need a separate animation state because both views inspect the same body skeleton. Weapon-specific full-body animation can be added later alongside an actual third-person held weapon/contact setup. |

Add new rows as we make calls (e.g., grid vs slot inventory, hitscan vs projectile).

---

## 7. Open Questions

- ~~Inventory style~~ → decided: simple slots (see Decisions Log)
- Player death: reload last save only, or checkpoint mercy? (decide at M5)
- Story delivery: notes only, or add audio logs? (decide at M6)
- Should the flashlight occupy a "hand" (RE1-style tradeoff) or be free? (decide at M5)
