# Survival Horror FPS — Project Plan

**Engine:** Godot 4.6 (Forward+, Jolt Physics)
**Language:** GDScript
**Genre:** First-person survival horror, scarcity-driven (Resident Evil-style resource pressure)
**Setting:** Abandoned research facility
**Goal:** Learning sandbox — build each system properly to learn Godot FPS/horror development. No shipping pressure, but every system should be built as if it could ship.

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

### Project structure
```
res://
  actors/            # player/, enemies/<name>/ — scene + scripts + assets together
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
| 3 | enemies |
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
- [x] FPS controller: walk/sprint/crouch, stamina, mouse look (no jump — see decisions)
- [x] Interaction ray + first interactables (door, pickup, readable note)
- [x] Flashlight toggle (no battery yet)

### M2 — Inventory & items
- [ ] Item resource definitions, pickup → inventory flow
- [ ] Inventory UI (limited slots), use/drop/examine
- [ ] Key item unlocks a locked door

### M3 — Combat
- [ ] Pistol: aim, fire, reload from inventory ammo, feedback (sfx/flash/decals)
- [ ] Health component + damage, player hurt/death, healing item
- [ ] Target dummies to shoot

### M4 — First enemy
- [ ] Shambler with patrol/investigate/chase/attack state machine
- [ ] Navigation mesh in test level, hearing + vision perception
- [ ] Full loop test: sneak past OR spend scarce ammo

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
| 2026-07-15 | GDScript over C# | Fastest iteration for learning; best docs/examples for Godot 4 |
| 2026-07-15 | Scarcity survival over hide-only or action | Richest system mix to learn (inventory, combat, AI, economy) |
| 2026-07-15 | Abandoned facility setting | Contained scope, interior lighting control, classic puzzle-box layout |
| 2026-07-15 | One enemy type first | Depth over breadth; AI state machine is the learning goal |
| 2026-07-15 | Saves only in safe rooms | Core to the tension model; simpler serialization scope |
| 2026-07-15 | No jumping | Classic survival horror; keeps level design and animation scope tight |
| 2026-07-15 | Crouch = toggle, sprint = hold; crouch on C (not Ctrl) | Comfort defaults; Ctrl collides with macOS shortcuts |
| 2026-07-15 | Reading a note pauses the game | Safe reading, RE-style; HUD runs with PROCESS_MODE_ALWAYS to close it |

Add new rows as we make calls (e.g., grid vs slot inventory, hitscan vs projectile).

---

## 7. Open Questions

- Inventory style: RE-style grid with item sizes, or simple N slots? (decide at M2)
- Player death: reload last save only, or checkpoint mercy? (decide at M5)
- Story delivery: notes only, or add audio logs? (decide at M6)
- Should the flashlight occupy a "hand" (RE1-style tradeoff) or be free? (decide at M5)
