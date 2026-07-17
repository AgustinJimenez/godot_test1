# Tooling Research

Ongoing notes on open-source Godot 4 libraries/addons/tools that could help
this project — general development, UI, visuals, animation retargeting,
storage, editor tooling, etc. Pure research log, not a commitment to use
anything here; check back before reaching for a hand-rolled solution to a
problem one of these already solves. Append new findings under a dated
section rather than editing old entries, so the log stays a history of what
was looked at and when.

## Open TODOs

Unlike the rest of this log (informational, no action implied), these are
explicit follow-ups pulled out of the research below because they need a
decision, not just awareness.

- **[ ] Decide on Git LFS.** No LFS configured currently; several
  multi-MB binaries (`UAL1_Standard.glb` 7.4MB, `The Boss.fbx` 6.1MB,
  `MotusMan_v55.fbx` 4.9MB, more) are already committed as plain git blobs.
  Adopting LFS now means rewriting history (`git lfs migrate`) for
  everything already committed, not just a `.gitattributes` change - an
  explicit, history-altering call for the user to make, not something to
  do unprompted. Not urgent for a solo project; becomes worth revisiting
  if the repo gets unwieldy to clone or a second contributor hits a binary
  merge conflict. Full detail in the "2026-07-17, fifth pass" section
  below.

- **[~] MCP for the character editor — superseded by a build-our-own plan.**
  Originally framed as "decide between GDAI MCP and Godot MCP Pro" (full
  comparison still below, in the "2026-07-17, eighth pass" section - kept
  for reference). After further discussion, decided a custom MCP server is
  the better fit: `character_editor.gd` already exposes an agent-shaped
  CLI-args automation interface, so a purpose-built server can be a thin
  wrapper around it instead of a generic Godot-manipulation tool re-deriving
  that from scratch. Full investigation (architecture options, SDK choice,
  tool list, open questions) written up in
  **`docs/character_editor_mcp_plan.md`** - not yet implemented, that doc
  is itself the "investigate before coding" step, still needs review/
  agreement before any code gets written.

## 2026-07-17

### Retargeting (relevant to the UAL retargeting saga — see `docs/task_history/ual_animation_retargeting.md`)

- **[Mixamo Animation Retargeter](https://github.com/RaidTheory/Godot-Mixamo-Animation-Retargeter)**
  (Godot Asset Library #3429) — adds a right-click "Retarget Mixamo
  Animation" option in the FileSystem dock; automates the
  `BoneMap`/`SkeletonProfileHumanoid` Advanced Import Settings workflow that
  this project eventually hand-rolled as `_humanoid_retarget_local_pose()`.
  Bone map is Mixamo-naming-specific by default but stored as an editable
  `mixamo_bone_map.tres` — could plausibly be adapted to UAL's Unreal
  Mannequin naming (`thigh_r`, `upperarm_r`, `clavicle_r`, ...) instead of
  writing retarget math by hand for any *future* animation pack. Requires a
  `Skeleton3D` node named exactly `"Skeleton"`. Does not explicitly document
  T-pose vs A-pose handling — that's still on us to get right, same lesson
  as this session. Godot 4.3+, untested on older versions per its own docs.
- **[Mixamo Animation Batcher](https://godotengine.org/asset-library/asset/5079)**
  — same idea, batch-oriented, exports `.res` files with automatic
  `SkeletonProfileHumanoid` retargeting and bone renaming.

### AI / behavior (relevant to the shambler enemy's state machine)

- **[LimboAI](https://github.com/limbonaut/limboai)** — de-facto Godot 4
  behavior-tree framework, GDExtension (native speed), visual tree editor
  in the Godot editor itself.
- **[Beehave](https://github.com/bitbrain/beehave)** — alternative
  behavior-tree addon, pure GDScript (no native compile step).
- Either would give `actors/enemies/shambler/` a more standard, debuggable
  structure than hand-rolled state logic if the enemy roster grows beyond
  one type.

### Visuals / horror atmosphere ("Resident Evil-style" per the project pitch)

- **Volumetric Fog + FogVolumes** — built into Godot 4 core, no addon
  needed. Froxel-based (frustum-aligned voxel buffer), reacts to lights and
  shadows in real time. Recipe found for horror specifically: dark red
  albedo, black emission, density ~0.1, then push contrast to ~1.2 and
  saturation to ~1.5 in the Environment's Adjustments section.
- **[HorrorScreenFX](https://asago.itch.io/horrorscreenfx)** — post-process
  addon built specifically for horror games: VHS/CRT, digital glitch,
  chromatic aberration, animated film grain, screen flicker/distortion, 8
  curated presets, one-node setup, 2D+3D. Directly on-genre for this
  project — worth a proper look before building a custom post-process stack.
- **[Godot Post Process Plugin](https://github.com/GodotPostProcess/addon)**
  — more general-purpose alternative: vignette, blur, screen shake, analog
  monitor, CRT/VHS, animated grain, with a `PostProcessPreset` resource
  system for saving/reusing effect combinations. Less horror-opinionated
  than HorrorScreenFX, more building blocks.

### Storage / saves

No single dominant library — 2026 consensus from research: JSON for save
data + a dedicated autoload `SaveManager` singleton + custom `Resource`
subclasses for structured data (this project already has this pattern via
`items/item.gd`) + always save to `user://`, never `res://` (the latter is
read-only in exported builds) + stamp every save with a version + timestamp
for future migration. Two safety-relevant addons worth knowing about if
notes/pickups/saves are ever loaded from untrusted sources (Godot resources
can execute code on load): **Godot Safe Resource Loader** and
**WCSafeResourceFormat**.

### UI

- Godot 4.6 ships a new default "Modern" editor theme (the former community
  "Minimal Theme," now built into core) — nothing to install, already the
  default.
- **[Dialogue Manager](https://github.com/nathanhoad/godot_dialogue_manager)**
  — the standard Godot 4 branching-dialogue tool (script-like authoring
  language, in-editor syntax checking, `DialogueManager` global at
  runtime). No dedicated "journal" feature built in, but the project's
  existing note/HUD system (`ui/hud.gd`'s `show_note()`) could layer on top
  of it if notes ever need branching logic or in-game NPC dialogue.
- **ThemeGen** / **Reactive UI** — code-first theme generation / React-style
  component framework for Godot UI. Probably overkill for the current
  toast/note/inventory HUD, worth revisiting if the UI grows significantly
  more complex.

### General tooling

- **[Debug Draw 3D](https://github.com/DmitriySalnikov/godot_debug_draw_3d)**
  — draw lines/spheres/boxes/text in the running game with a one-liner
  GDScript call, zero cost in release builds (strips via build flags). Would
  have made some of this session's bone/skeleton debugging visualization
  (the hand-built `ImmediateMesh` tube gizmos in the animation comparison
  tooling) trivial instead of custom geometry code — worth reaching for
  first next time a "draw a debug shape in 3D space" need comes up.
- **[GUT (Godot Unit Test)](https://github.com/bitwes/Gut)** — GDScript unit
  testing framework. `AGENTS.md` currently states "there are no unit tests;
  verification is done by exercising scenes" — worth reconsidering for
  logic-heavy, non-visual systems (inventory rules, save/load, damage
  calculations) where a scene-exercise test is overkill and a fast unit
  test would catch regressions cheaply. Visual/animation correctness should
  stay manual per the project's standing rule either way.

### Broader ecosystem notes (not immediately actionable, logged for context)

- **Terrain3D**, **ProtonScatter** — large-outdoor-scene tooling (heightmap
  terrain, prop scattering). Not relevant to an indoor facility setting
  unless the design changes.
- **Phantom Camera** — Cinemachine-style camera behavior plugin. Possibly
  relevant later if cutscene or dynamic camera framing needs grow beyond
  the current first/third-person toggle.
- **GodotSteam** — Steam platform integration (achievements, lobbies,
  networking). Only relevant at ship time, not now.

## 2026-07-17, continued

### Audio / sound design (horror leans hard on this)

- **[Resonate](https://github.com/hugemenace/resonate)** — all-in-one sound
  and music management addon, officially maintained (Widgit Gaming, active
  Jan 2026). Two systems: `SoundManager` (auto-pools/orchestrates
  `AudioStreamPlayer`s, automatic 2D/3D detection, polyphonic playback) and
  `MusicManager` (stemmed tracks, built-in crossfading). Probably the best
  general-purpose starting point if the project wants a real audio manager
  instead of ad hoc `AudioStreamPlayer` nodes.
- **[gd-dynamic-sound](https://github.com/funfirerabbit/gd-dynamic-sound)**
  — intensity-layered dynamic music (up to 3 simultaneous layers blended at
  runtime, e.g. calm/tense/danger stems for the same track) + seamless
  playlist transitions + overlapping one-shot SFX. Requires Godot 4.6+
  (matches this project's engine version exactly). This is the classic
  Resident-Evil-style "danger stinger" pattern - worth checking first for
  the encounter-tension music the design pillars call for.
- **[Godot Dynamic Music Framework](https://github.com/R3X-G1L6AME5H/godot-dynamic-music-framework)**
  — similar adaptive-music idea, explicitly cites a horror use case
  (dissonant layer fades in as a monster approaches) plus randomized
  "oneshot" musical motifs (the technique Mick Gordon used on the DOOM
  OST) for less repetitive ambience.
- **Godot Mixing Desk** — older (Godot 3.3.x-era) procedural
  audio/adaptive-music plugin; likely needs a compatibility check before
  use on 4.6, logged for completeness rather than as a strong recommendation.
- General tip from research, not addon-specific: use an Audio Bus layout
  (Master/Music/SFX/UI groups) so per-category volume and effects
  (e.g. a muffled bus for underwater/behind-doors) are trivial to add later.

### Level design / greyboxing (relevant to the "interconnected facility" design pillar)

- **Built-in CSG tools** (`CSGCombiner` + shape nodes) — already in Godot 4
  core, good for rapid room blockout without leaving the editor or touching
  Blender. Explicitly a prototyping tool, not final-geometry-performant per
  Godot's own docs - export/replace with real meshes once a layout is locked.
- **CSG Mesh Exporter (.OBJ)** — exports CSG blockouts to OBJ, a clean
  bridge from greybox to final art pass.
- **[Dioptra Level Editor](https://godotengine.org/asset-library/asset/5115)**
  — Hammer/TrenchBroom-style in-editor level tool (node-free, streamlined
  texturing workflow). Worth a look if room-by-room greyboxing in CSG
  starts feeling slow once the facility's room count grows past what's in
  `test_room.tscn` today.

### Inventory (comparison against the project's existing hand-rolled system)

The project already has a working Resource-based inventory
(`items/item.gd` + `components/inventory.gd`) matching the exact pattern
these addons also use (items as `Resource`s, not scene nodes; a Node
component wrapping an array of references; UI reacts to a `changed`
signal) - so this is "compare notes," not "replace what works." Logged in
case scarcity-mechanic needs (weight limits, stacking, item boxes) outgrow
the hand-rolled version:

- **[Inventory System (expressobits)](https://github.com/expressobits/inventory-system)**
  — modular, multiplayer-compatible, logic/UI separated, items as separate
  resources, MIT, actively updated (Feb 2026).
  - **[GLoot (peter-kish)](https://github.com/peter-kish/gloot)** — item
  prototypes defined in a JSON prototype tree, with per-item property
  overrides. Godot 4.4+.
- **[Modular Inventory System (Andrei)](https://andreicl.itch.io/modular-inventory-system/)**
  — most actively updated (Jul 2026, Godot 4.7), adds persistent
  `ItemInstance`s with durability/custom properties and versioned
  save-format migration - closest addon-world equivalent to the
  scarcity/durability mechanics the design doc calls for, if the hand-rolled
  system ever needs that level of complexity.

## 2026-07-17, graphics realism pass

### Lighting / global illumination — the single highest-impact item for this project

- **SDFGI (Signed Distance Field Global Illumination)** — built into Godot 4
  core, no addon. Real-time, dynamic indirect lighting/bounce that follows
  the camera automatically (no baking, no extents to configure, unlike
  VoxelGI). Runs on modest hardware (developed/tested on a GTX 1060 @ 60
  FPS) since it doesn't require ray tracing. Supports dynamic lights and
  specular reflections. **This is the single highest-impact thing to look
  at for this project specifically**: a flashlight-driven horror game in a
  mostly-dark facility lives or dies on how convincingly light bounces off
  walls/floors around the beam - that's exactly SDFGI's use case. Enable
  via `WorldEnvironment` → Environment → SDFGI section; mesh instances need
  their *Global Illumination > Mode* set to Static. Forward+ only (already
  the project's renderer per `AGENTS.md`). Key tuning knobs: `Bounce
  Feedback` (0.3-1.0 for more realistic multi-bounce light at a small
  perf cost), `Cascades` (lower if the camera moves fast), `Min Cell Size`
  (lower = more accurate, more expensive), `Max Distance` (keep below the
  Camera's Far value).
- **SSIL (Screen Space Indirect Lighting)** — cheaper complement to SDFGI,
  similar to SSAO but for bounced *color* rather than just occlusion (makes
  shadowed areas pick up nearby wall/floor color instead of going flat
  black) - worth enabling alongside SDFGI, not instead of it.
- **Baked GI (LightmapGI/VoxelGI)** — the alternative for scenes that don't
  change at runtime. Less relevant here since flashlight + dynamic lights
  are core to the gameplay loop (per `docs/PLANNING.md`'s "darkness is a
  resource" pillar) - SDFGI is the better fit than baking.

### Materials / decals (grime, bullet holes, blood — fits the "abandoned facility" setting)

- **`StandardMaterial3D`** already gives full PBR (albedo/normal/roughness/
  metallic/emission) - concrete ≈ 0.8-0.95 roughness, worn/polished metal
  ≈ low roughness + metallic 1.0, wood ≈ 0.4-0.6 roughness, useful reference
  numbers for dressing the facility.
  One easy-to-miss import setting: texture **Repeat must be manually
  enabled** in the Import dock (defaults to Disabled in Godot 4) or tiling
  textures render as a single stretched image.
- **Godot 4's built-in `Decal` node** — projects albedo/normal/PBR-mask
  textures onto arbitrary geometry, good for static grime/bullet-hole
  dressing. Known limitation: no way to supply a *whole material* (so no
  animated decals like fresh blood spreading) - fine for static grime,
  not for dynamic blood pooling.
- **[Decal with PBR shader (Godot Shaders, updated for 4.6)](https://godotshaders.com/shader/decal-with-pbr-godot-4-4/)**
  — community shader adding full PBR (heightmap/roughness/metallic) to
  decals, using `DEPTH_TEXTURE`/`NORMAL_TEXTURE` for proper surface
  integration - upgrade path if the built-in Decal node's albedo-only
  projection isn't enough.
  - For genuinely dynamic blood spatter/pooling that reacts and spreads
  across surfaces: the pattern found (no ready-made addon, hand-built by a
  community dev working in 4.4) is writing blood textures into a
  `SubViewport`, then running a shader on that viewport to animate/blend
  the decals - a real project if pursued, not a drop-in.

### Particles / atmosphere

- **[GODOT-VFX-LIBRARY](https://github.com/haowg/GODOT-VFX-LIBRARY)** — 35+
  scene-based (`.tscn`) particle effects + 17+ shaders, action-game
  oriented but includes directly relevant atmosphere pieces: torch fire,
  fireflies, steam, an "EnvVFX Manager" for ambient/environmental effects.
- **[Waving Particles shader](https://godotshaders.com/shader/waving-particles/)**
  — configurable floating-particle shader (soft circles/crosses/custom
  texture) explicitly suited to dust motes catching flashlight beams in a
  dark room - a classic horror-atmosphere detail, cheap to add.

### Character/skin shading (relevant since the player's own body is visible - `PlayerBody`)

- Godot 4's `BaseMaterial3D`/spatial shaders have **built-in subsurface
  scattering and transmission support** (`SSS_STRENGTH` and related render
  modes) - no addon needed for believable skin on any visible
  character/enemy geometry, just enabling and tuning the existing material
  properties.

### Overall takeaway

Of everything researched today, **SDFGI is the standout recommendation** -
it's zero-addon, matches the project's Forward+/4.6 setup exactly, and
directly serves the "darkness is a resource" design pillar better than
anything else surfaced. Decals and particle atmosphere are good
second-priority polish once core lighting is dialed in.

**Status: research only, nothing implemented yet. To try later:** SDFGI +
SSIL first (highest impact, zero-addon), then decals/particle atmosphere
as polish once lighting is dialed in.

## 2026-07-17, 3D animation / IK libraries

### Godot 4.6 ships a built-in IK framework (January 2026) — directly relevant to the unfinished wrist/grip work

This project is already on Godot 4.6 (per `AGENTS.md`), and 4.6 reintroduced
Inverse Kinematics as a proper built-in system after `SkeletonIK3D` was
removed in the 4.0 rewrite and never replaced through 4.0-4.5. This lands
squarely on the still-open problem from
`docs/task_history/ual_animation_retargeting.md`'s Bug 3 update 5: the
`Pistol_Shoot` hand-silhouette mismatch, and the abandoned
"three-link FABRIK chain (Shoulder -> Arm -> ForeArm -> Hand)" that was
hand-rolled and left as an explicitly unfinished checkpoint. **A native
FABRIK solver now exists and is designed specifically to compose with
`RetargetModifier3D`** (the same class whose formula the successor agent
already extracted and reimplemented as `_humanoid_retarget_local_pose()`) -
worth checking whether the *actual* `RetargetModifier3D` node plus the new
IK modifiers can replace both the hand-rolled retarget formula and the
abandoned hand-rolled FABRIK chain with the engine's own tested
implementation, same lesson as
[[feedback-check-engine-source-before-hand-deriving]].

**Node hierarchy** (all extend `SkeletonModifier3D`, so they run *after*
animation is applied, composing with baked/retargeted poses rather than
fighting them):

- `IKModifier3D` (base)
  - `TwoBoneIK3D` — analytic, single-pass, no iteration. Use for simple
    arm/leg limb chains; always pair with a pole target so elbow/knee bend
    direction is controlled.
  - `ChainIK3D`
    - `SplineIK3D` — tails, tentacles, cables.
    - `IterateIK3D`
      - `FABRIK3D` — the solver relevant to the wrist/grip problem. Has a
        deterministic toggle (off = state carries frame-to-frame for
        faster convergence; on = fresh solve each frame, useful for
        networked/synchronized poses).
      - `CCDIK3D` — alternative iterative solver for long chains.
      - `JacobianIK3D`

- Supporting modifiers meant to be composed alongside IK (twist/aim
  correction is deliberately NOT baked into the solvers themselves):
  `BoneConstraint3D` (+ `AimModifier3D`, `ConvertTransformModifier3D`,
  `CopyTransformModifier3D`), `BoneTwistDisperser3D`,
  `LimitAngularVelocityModifier3D`, `LookAtModifier3D`,
  `SpringBoneSimulator3D`, and **`RetargetModifier3D`** itself.

**Setup**: chain root/end bone define the joint array (auto-constructed,
same pattern as `SpringBoneSimulator3D`). Targets are `Node3D` references
(via `BoneConstraint3D`), not bone-only. All classes are ordinary
`Node`-based types extending `SkeletonModifier3D`, so should be scriptable
via GDScript, not editor-only - the official announcement's screenshots
show inspector setup but nothing suggests the API is closed off from code.

**Gotchas found:**
- Documentation is explicitly incomplete as of the announcement - "detailed
  tutorials are planned but expected to be quite large."
- Deterministic IK can produce large angular velocities by design;
  `LimitAngularVelocityModifier3D` is the documented mitigation.
- Iterative solvers (FABRIK/CCDIK) cost more per frame than analytic
  Two-Bone IK - fine for a single player-character wrist correction, worth
  profiling before using on multiple simultaneous enemies.
- 19 new modifier types shipped across 4.4-4.6 with many combinations -
  real learning curve, start with the single FABRIK3D + RetargetModifier3D
  combination relevant to the wrist problem rather than the whole modifier
  stack at once.

### Third-party alternative (predates the built-in system, now largely superseded)

- **[Twisted IK 2](https://twistedtwigleg.itch.io/twistedik2)** — older
  addon offering FABRIK/CCDIK modifier nodes plus rigidbody-physics
  skeleton interaction and 2D IK. **No longer in active development** per
  its own listing - stable but frozen. Given Godot 4.6 now ships an
  equivalent (and better-integrated-with-retargeting) system natively, this
  is logged for completeness rather than recommended over the built-in
  framework.

**Status: research only, nothing implemented yet.** This is the most
actionable finding of today's research given the known, explicitly-still-open
`Pistol_Shoot` hand mismatch - next concrete step if picked up: read the
actual `RetargetModifier3D`/`FABRIK3D` engine source (same technique that
resolved the earlier retargeting bug) before attempting any hand-rolled IK
chain again.

**Cross-verified locally, same day:** ran `godot --doctool <path> --headless`
(dumps the full engine API reference straight from the installed 4.6.2
binary - see `AGENTS.md`). `FABRIK3D.xml`, `IKModifier3D.xml`,
`RetargetModifier3D.xml`, `TwoBoneIK3D.xml`, `ChainIK3D.xml`, `CCDIK3D.xml`
all exist locally with real, complete method/property signatures (e.g.
`ChainIK3D.get_end_bone_name(index)`, `RetargetModifier3D.set_position_enabled(enabled)`)
and confirmed the exact inheritance chain
`FABRIK3D -> IterateIK3D -> ChainIK3D -> IKModifier3D -> SkeletonModifier3D`.
Prose descriptions are still empty (expected - brand new feature, not yet
written up by Godot's docs team), but the API surface itself is exact and
ready to use for implementation, no more web-research needed before
attempting this.

## 2026-07-17, gap-filling pass — tied to concrete existing project state, not generic categories

Prompted by "what are we missing" rather than another broad sweep. Picked
four areas specifically because each maps to something already present or
already on the roadmap, not a hypothetical need.

### Real-time mirrors — could replace the `debug_mirror.gd` puppeted-double hack

`levels/debug_mirror.gd`'s own comment already explains why it exists:
"SubViewport textures are unreliable in Godot 4.6 once this scene is
instanced inside another one - see godotengine/godot#115402" - so a second
animated `PlayerBody` is puppeted every frame to fake the reflection
instead. That workaround is also the source of the still-open, unrelated
lazy-bake bug logged in `docs/task_history/ual_animation_retargeting.md`
(the mirror double never receives lazily-baked debug clips). A proper
reflection technique could remove the puppeted double - and the bug -
entirely.

- **Screen Space Reflections (built-in, Environment setting)** — cheapest,
  but screen-only: reflects nothing off-screen, so a mirror the player can
  see edge-on or from an angle will show gaps. Weak fit for an actual mirror
  prop.
- **Reflection Probes (built-in)** — ambient/specular light source, low
  update frequency by design. Good for a shiny floor, not a true mirror.
- **[PlanarReflector-CPP](https://godotengine.org/asset-library/asset/4102)**
  — the most robust option found: real-time planar reflections with
  geometric accuracy, GDExtension (C++, fast), SubViewport downscaling,
  dual render for game/editor, layer-based filtering (control what's
  visible in the reflection), distance LOD, update-frequency and
  movement-threshold controls to cap cost. **Caveat to check before
  adopting**: it explicitly uses SubViewport internally, which is the exact
  mechanism `debug_mirror.gd`'s own comment says was unreliable when
  nested inside another instanced scene (godotengine/godot#115402) - verify
  whether that specific bug still reproduces with this addon's setup (or
  in the currently-installed 4.6.2) before relying on it, don't assume it's
  fixed.
- **[V-Sekai Godot Planar Reflection](https://github.com/V-Sekai/godot_planar_reflection)**
  — alternative, offers a "screenspace mode" specifically to avoid
  non-square-pixel distortion up close; worth a fallback comparison against
  PlanarReflector-CPP.

### Save-room / checkpoint system — directly on the roadmap (M5)

`docs/PLANNING.md`'s status line names this explicitly as next:
"M5 — Survival pressure (flashlight battery, scarcity tuning, safe-room
save/load)." Research finding: **there is no dedicated "RE-style typewriter
save" addon** - this is universally hand-built on top of the same
JSON + autoload-`SaveManager` + `user://` pattern already logged under
Storage/saves above, nothing new to add there. The concrete implementation
path once M5 is picked up: a save-room prop follows the exact same
`Interactable` pattern already used for doors/pickups/notes/animation
stations (per `AGENTS.md`'s Architecture section) - its `interacted` signal
calls into the `SaveManager` autoload, no new architectural pattern needed,
just a new `Interactable` owner type.

### Ragdoll / physics-driven death — alternative to precisely retargeting death poses

Motivated by how much difficulty the `Death01` clip caused in the
retargeting saga (`docs/task_history/ual_animation_retargeting.md`). Godot
4 has this **built in**, no addon: `PhysicalBoneSimulator3D` (parent,
controls the simulation) + one `PhysicalBone3D` per simulated bone. Call
`physical_bones_start_simulation()` to hand a skeleton over to physics;
can be scoped to specific bone names for partial ragdoll (e.g. only
legs/arms react physically while the torso stays animated). Has a built-in
**`Influence` property (0.0-1.0)** for blending animation and physics
smoothly instead of a hard cut - relevant because a physics-driven collapse
doesn't need to precisely match a retargeted animation's silhouette at all,
it just needs correct mass/joint limits, sidestepping the whole class of
retargeting-fidelity problem this session hit repeatedly.
- **[Active Ragdoll (cberry22)](https://github.com/cberry22/active-ragdoll---physics-animations-in-godot-4.0)**
  — goes further: physics-driven character that continuously tries to
  match a *target animated pose* (Unreal-style "Physical Animations"),
  so a character can be knocked around by forces while still visibly
  trying to hold its animated pose. Overkill for a simple death collapse,
  but the underlying `PhysicalBoneSimulator3D` technique is the same -
  logged in case hit-reaction physics ever go beyond a canned animation.

### CI / automated headless testing

Motivated by how much of this session was manual `--headless`/
`--write-movie` invocation, repeated by hand every time. Godot 4's
standard binary already supports `--headless` with no separate build and
no virtual display needed in CI (confirmed - this project already does
exactly this locally). Two testing-framework options if this project ever
wants actual CI rather than manual scene-exercise (per `AGENTS.md`: "there
are no unit tests; verification is done by exercising scenes"):

- **GUT** (already logged above) — has a CLI runner
  (`addons/gut/gut_cmdln.gd`), returns a real exit code GitHub Actions can
  read directly.
- **[GdUnit4](https://github.com/godot-gdunit-labs/gdUnit4)** — alternative
  embedded testing framework (GDScript + C#), has an **official GitHub
  Action** (`godot-gdunit-labs/gdUnit4-action`) that wraps setup for you.
- Gotcha found worth remembering either way: a naive one-step CI job can
  false-negative because Godot prints scary `ERROR` lines (leak warnings
  etc.) on exit and can return non-zero even when tests genuinely passed.
  The documented fix is a **two-step job**: (1) `godot --headless --import
  --quit` first so all resources/`class_name` scripts are registered, then
  (2) run the actual test suite in a separate, fully-headless step. Cache
  the downloaded Godot binary by version to avoid a 30-60s redownload every
  run.
- Given the project's current testing convention (`tests/manual/<domain>/`
  persistent acceptance harnesses, no automated tests), this is
  lowest-priority of today's four findings - logged for if/when the
  project decides manual scene-exercise stops scaling.

## 2026-07-17, second gap-filling pass

### Weapon/combat "game feel" — relevant to the existing M3 hitscan pistol

- **[Sparkle](https://forum.godotengine.org/t/sparkle-game-feel-plugin-for-godot-4/137508)**
  — bundles camera shake, screen flash, particle bursts, and hit-pause into
  one node/call.
- **[Game Feel Pack: Hitstop + Shake](https://streamline-creations.itch.io/game-feel-pack-hitstopscreenshake-juice-for-godot-4/)**
  — one-line hitstop (`Hitstop.freeze(0.08)`) plus camera shake utilities.
- **[Simple FPS Weapon System](https://github.com/Jeh3no/Godot-simple-FPS-weapon-system)**
  — full resource-based FPS weapon asset: switching, hitscan + projectile
  types, procedural camera recoil/bobbing/tilting, muzzle flash, bullet
  hole decals, explosion effects. Godot 4.4-4.7. Worth comparing against
  the hand-rolled pistol before adding a second weapon type, not
  necessarily to replace what's already working.
- No addon needed for the core technique if building by hand instead: a
  **trauma-based camera shake** (accumulate a `trauma` float per hit,
  capped at 1.0, `shake_magnitude = trauma^2` so repeated hits compound
  non-linearly instead of just repeating) sampled from `FastNoiseLite` at
  a bumped 4.0-6.0 frequency (the default is too low and reads as floaty
  rather than snappy) was the most concretely useful technique surfaced,
  addon or not.

### Interactable highlight/outline — relevant to the core `Interactable` pattern

No dominant addon here - it's overwhelmingly a DIY spatial-shader technique
(a second render pass / fresnel-rim shader), not a drop-in plugin. Given
this project's entire interaction model is centered on one raycast-driven
`Interactable` pattern used by every door/pickup/note (per `AGENTS.md`
Architecture), a highlight-on-look shader would be a small, high-leverage
addition - toggle a shader param or `visible` outline mesh from the same
place `set_prompt()` is already called on `hud.gd`, no new architecture
needed. [Community outline/glow shaders](https://godotshaders.com/shader-tag/outline/)
are CC0 and copy-paste-able starting points.

### Occlusion culling / indoor performance — relevant to the "interconnected facility" design pillar

- Godot 4 has **built-in raster occlusion culling** (`Rendering >
  Occlusion Culling` project setting + baked `OccluderInstance3D`
  geometry). Most effective in indoor scenes with **many smaller rooms**
  rather than fewer large ones - directly matches the "Metroidvania-lite"
  interconnected-facility design pillar in `docs/PLANNING.md`.
- **Real gap, not just under-explored**: the Godot 3.x Rooms & Portals
  system (which also provided *gameplay* culling - disabling AI/physics/
  processing in occluded areas, not just rendering) was never ported to
  Godot 4. An open proposal exists; not implemented. No addon fills this
  gap either.
- **Concrete limitation to plan around**: baked occlusion can't be toggled
  per-object at runtime, so **doors specifically don't occlude** - looking
  down a corridor lined with several open doorways causes overdraw as
  everything behind every doorway renders regardless of whether those
  doors are shut in-fiction. Practical mitigation is a level-design one,
  not a code one: place opaque walls/turns to break sightlines at regular
  intervals rather than relying on doors to block view.
- Performance follows an **L-shaped curve** - most of the benefit comes
  from just a *few* rooms worth of setup, not exhaustive per-room tuning.

### Cutscene / scripted-event tooling — relevant to the "readable dread over jump scares" design pillar

- **[Godot Event Sequencer](https://github.com/Amethyst-szs/godot-event-sequencer)**
  — visual Event Node/Editor for scripted sequences (camera moves, audio,
  dialogue beats), extensible via config + GDScript.
  - **[Godot Sequencer](https://github.com/jimmybeer/godot-sequencer)** —
  timeline-based orchestration across cameras/animation/audio/VFX/gameplay
  events for multiple actors at once - closer to a traditional cutscene
  timeline tool.
- **CutsceneDirector pattern** (script-based, no addon) — a custom
  director class using `await` + signals to sequence cutscene actions
  (`await director.move_camera(...)`, etc.) reads as sequential code
  instead of a timeline; the source article's argument is this scales
  better than `AnimationPlayer`/`Tween` timelines once a scripted moment
  needs branching logic (e.g. a scripted "something moves in the dark, then
  reacts to whether the player has the flashlight on") rather than just
  playing back fixed motion - a stronger fit for the project's "readable
  dread" pillar than a pure timeline tool would be, given the design leans
  on player choice/reaction to environmental cues rather than fixed set
  pieces.
- **[GDrama](https://godotengine.org/asset-library/asset/2378)** —
  cutscene framework closer to a visual-novel toolkit (dialogue boxes,
  choices, character animation triggers); more relevant if NPC dialogue
  scenes end up being a real feature than for pure environmental-horror
  beats.

**Status: research only, nothing implemented from this pass either.**

## 2026-07-17, third gap-filling pass

### Flashlight battery — directly on the roadmap (M5, same milestone as save-room)

Same conclusion as the save-room research: **no dedicated addon exists** -
universally hand-built (a `battery_life` float that drains while the light
is on, pauses/recharges while off, driving a UI meter). One tutorial
surfaced specifically for Godot 4.3 ("Flashlight With Battery") with
source on GitHub if a starting reference is useful, but there's no
off-the-shelf system to evaluate here - this is straightforward custom
GDScript work when M5 is picked up, same as the save-room half of that
milestone.

### AI perception / stealth detection — comparison against the shambler's existing vision cone + hearing

This surfaced genuinely actionable design critique, not just addons, worth
weighing against `actors/enemies/shambler/`'s existing perception system
regardless of whether any addon gets adopted:

- **Never sample player visibility from a single point.** Sample multiple
  body parts (head/torso/feet) - crouching behind low cover should hide
  the torso while still exposing the head, which a single raycast-to-center
  can't represent.
- **A single vision cone is unrealistic.** Real peripheral vision is
  wide-but-weak (~180°) plus a narrower focused cone (~60°) - composite
  shapes (the "Splinter Cell method") read as fairer to the player than
  one hard-edged cone.
- **Hearing should propagate along navigation paths, not straight-line
  distance.** A sound on the other side of a wall shouldn't be "heard"
  just because it's geometrically close - route it through
  `NavigationServer3D` path distance instead. Worth checking whether the
  shambler's existing hearing check already does this or uses raw
  distance - if the latter, this is a concrete, scoped improvement.
- **Never hide detection reasons from the player.** Surface *why* the
  enemy noticed (too bright, too loud, in direct sightline) rather than a
  silent "gotcha" - a UX principle, not a code one, but relevant to
  `docs/PLANNING.md`'s "readable dread" pillar specifically.
- **Performance**: run detection/visibility checks on a ~0.1-0.2s Timer
  rather than every `_physics_process` tick - negligible responsiveness
  cost, meaningfully cheaper with multiple enemies active.
- **[godot-perception](https://github.com/kylecorry31/godot-perception)**
  — a more generalized Godot 4 sensory-system plugin, worth a look if the
  project ever wants perception logic reusable across multiple enemy types
  rather than bespoke per-enemy.
- **[Godot 4 Stealth Skeleton](https://obscura-tempura-studios.itch.io/godot-4-stealth-skeleton)**
  (itch.io, MIT) — a template project with patrol/vision-cone/noise-radius/
  trap/alert-state (patrol → investigate → alert → chase) already wired up
  - notably the **same state names** the shambler already implements per
  `AGENTS.md`/commit history, so this is a good reference to diff design
  decisions against even without importing any of its code.

### Asset import / performance (Godot 4.6 built-ins, no addons needed)

Relevant given the project already imports several large FBX/glTF packs
(MotusMan, `pistol_starter` animations, UAL1, UAL2). All of the following
are built into 4.6 already, nothing to install:

- **Betsy GPU texture compression is ~2x faster in 4.6** specifically for
  3D texture imports (RGB converted to RGBA on GPU, used directly).
- **Basis Universal** VRAM compression (`Project Settings > Rendering >
  Textures > VRAM Compression`) is the recommended default for 2026 -
  small on-disk size (JPEG-like) that transcodes to whatever the GPU
  needs at runtime.
- If imports feel slow: `Project Settings > Importer Defaults > Texture`,
  set `Detect 3D = Disabled` and `Compress Mode` explicitly (`VRAM
  Compressed` for 3D, `Lossless` for any pixel-art UI textures) rather
  than leaving it on auto-detect.
- **Mesh LOD generation improved in 4.6** - better preserves the original
  silhouette for meshes built from multiple separate parts (relevant to
  multi-part character rigs like MotusMan) rather than degrading oddly at
  distance.
- Godot 4's built-in occlusion culling (already logged in the previous
  pass) and mesh LOD are described as the two highest-leverage rendering
  optimizations together, not alternatives to each other.

**Status: research only, nothing implemented from this pass.**

## 2026-07-17, fourth gap-filling pass

### Foot IK / foot-sliding — direct follow-on from the built-in IK framework finding

Motivated by finishing the thought from the earlier IK research entry, and
relevant to any retargeted locomotion (the project already does
speed-based animation-rate matching for this exact problem - see
`WALK_REF_SPEED`/`JOG_REF_SPEED`/`CROUCH_REF_SPEED` in `player_body.gd`,
"Rough forward speeds the clips were authored at, for foot matching").
**No dedicated addon found** - confirms this is built-in-tools territory,
same conclusion as the wrist/grip IK research:

- The recommended technique is a **foot lock target**: a secondary IK
  target placed directly under the foot's last grounded position, which
  the actual foot is pinned to via IK (FABRIK/TwoBoneIK from the framework
  already found) until the next step begins - stops the foot sliding
  across the floor between keyframes, especially visible on stairs/uneven
  ground or when animation playback speed doesn't perfectly match
  movement speed (relevant given the project already tunes playback rate
  rather than relying on exact 1:1 speed matching).
- **Root motion** (letting the animation clip's own translation drive the
  `CharacterBody3D` instead of scripted velocity) is the other classic
  answer to foot sliding, described as essential for locomotion fidelity
  by design - but the project's own source clips are explicitly
  **"in-place" with no baked root motion** (`UAL_PATH`'s doc comment in
  `player_body.gd`), so this specific technique doesn't apply here; foot
  IK is the relevant one of the two, not root motion.
- Simple mitigation with no IK at all, worth remembering: slowing the
  movement speed (or, equivalently, tuning `*_REF_SPEED` more precisely)
  gives the IK/animation more time to keep up and reduces the appearance
  of sliding on its own.

### Melee combat — hitbox/hurtbox pattern (relevant given the `melee` input action already bound in `project.godot`)

No dedicated addon found - this is DIY-pattern territory, same as
save/battery/flashlight. Consistent, well-documented technique across
every source found:

- **Hitbox** (the weapon/fist's damage-dealing volume) and **hurtbox**
  (what can be damaged) are separated `Area3D` nodes specifically so an
  attacker can't damage itself.
- Keep the hitbox's `CollisionShape3D` **disabled by default**, and enable
  it only during the actual swing frames **by keying the `disabled`
  property directly from the `AnimationPlayer` track** - this fits the
  project's existing pattern closely, since gameplay one-shot animations
  already run through `PlayerBody.play_action_animation()` with an
  `action_finished` signal boundary (per `AGENTS.md`) - a punch/melee
  hitbox window is a natural fit for that same animation-driven
  activation window rather than a new timing mechanism.
- If Godot warns about changing collision state mid-physics-step,
  `set_deferred("disabled", ...)` is the documented fix.
- Beyond the basic hit/hurt pair, sources flagged **combo timing windows**,
  **brief invincibility frames after being hit**, and **queuing an attack
  through a state machine rather than firing it directly from `_input`**
  (to prevent overlapping attacks) as the next layer of polish once basic
  hit detection works - relevant if melee grows beyond a single punch.

### Puzzle / lock / key / code mechanics — relevant to the "keys/fuses/codes" design pillar

**No free/open-source addon found that fits a first-person 3D horror
game** - the one dedicated toolkit found (RetroPixel Labs' "Point & Click
Adventure Toolkit," $14.99) is built for 2D point-and-click adventures
(Monkey Island/Maniac Mansion style), not a first-person 3D game, so it's
a poor structural fit even setting cost aside. **This confirms the
project's existing pattern already covers the need**: doors already have a
`required_item` check against the same `Resource`-identity comparison used
throughout the inventory system (per `AGENTS.md` Architecture section).
Fuses and code-entry puzzles are the same `Interactable` pattern again -
a fuse-box `Interactable` that checks "has fuse item," a keypad
`Interactable` that checks an entered code against a stored value - no new
architecture needed, this is naturally covered by decisions already made
rather than a gap to fill with a library.

**Status: research only, nothing implemented from this pass. This pass's
main conclusion is negative-but-useful**: flashlight battery, melee
hitboxes, and lock/code puzzles all confirmed as "no addon fits, and the
project's existing patterns already cover it" - useful to know *before*
searching for a library next time one of these comes up, rather than
re-researching the same negative result.

## 2026-07-17, fifth pass

### Accessibility (colorblind, subtitles, input remapping)

- **[ColorBlind Accessibility Tool](https://godotengine.org/asset-library/asset/3460)**
  (Asset Library, MIT) — colorblind post-process filter + a color-replace
  shader + adjustable glow, editor-integrated.
- **[paulloz/godot-colorblindness](https://github.com/paulloz/godot-colorblindness)**
  — simpler alternative: a `Colorblindness` `CanvasLayer` control, set a
  `Type` property (deuteranopia/protanopia/tritanopia/etc.) and everything
  rendered under it gets tinted accordingly.
- **[Maaack's Input Remapping](https://github.com/Maaack/Godot-Input-Remapping)**
  — described as the fastest path to a working remap menu (~5 minutes),
  installable via AssetLib, game-agnostic (2D/3D), scales from game-jam to
  commercial use.
- **[KoBeWi's Godot-Input-Remap](https://github.com/KoBeWi/Godot-Input-Remap)**
  — more programmatic/resource-based alternative, includes
  `find_duplicates()` for detecting conflicting bindings and
  clone/restore helpers for a cancel-safe settings menu.
- Subtitles specifically: no dedicated subtitle-system addon surfaced;
  Godot's own accessibility proposal (godot-proposals#983) lists
  comprehensive subtitles with speaker identification as a still-open
  engine-level goal, not something to expect a mature addon for yet.
- None of this is implemented or currently planned in `docs/PLANNING.md` -
  logged as available groundwork, not a recommendation to prioritize over
  the actual roadmap.

### Version control — checked against this project's actual repo state, not generic

Confirmed directly (`git lfs ls-files`, `.gitattributes`, `git ls-files`
+ `du`): **this repo has no Git LFS configured**, and already has several
multi-megabyte binary assets committed as ordinary git blobs -
`assets/models/universal_animation_library/UAL1_Standard.glb` (7.4MB),
`assets/models/action_adventure_pack/The Boss.fbx` (6.1MB),
`assets/models/pistol_starter/MotusMan/MotusMan_v55.fbx` (4.9MB), plus
several more MotusMan textures in the 1.5-2.7MB range.

Godot's own docs are clear on the two things that matter most here:
1. **Set up Git LFS *before* the first commit of a binary file** - adding
   it retroactively for files already in history requires `git lfs
   migrate` (a history rewrite), not a simple `.gitattributes` addition.
   Since this repo's large binaries are already committed as plain blobs
   across many past commits, adopting LFS now would mean rewriting
   published history - **a decision for the user to make explicitly, not
   something to do unprompted** (matches this project's own git safety
   rules around destructive/history-altering operations).
2. **Never put `*.tscn` under LFS** - only binary formats (`*.scn`,
   `*.res`, `*.fbx`, `*.glb`, images, audio). `.tscn` files are Godot's
   plain-text, git-mergeable format specifically so merge conflicts stay
   resolvable - LFS-tracking them turns a normal text merge conflict into
   an unresolvable SHA256 pointer conflict.

Given the repo already works fine and this is a solo learning-sandbox
project (not a multi-contributor team hitting clone-time or merge-conflict
pain yet), **this is logged as "worth knowing," not "worth doing"** - the
practical trigger for actually adopting LFS would be either the repo
becoming unwieldy to clone, or a second contributor joining and hitting
binary merge conflicts, neither of which is the current situation.

**Status: research only. This pass's version-control finding is the one
item across all research passes so far that would require an explicit,
history-altering user decision rather than just adding a new addon -
flagging that distinction clearly rather than treating it the same as
everything else on this list.**

## 2026-07-17, sixth pass — can Godot itself generate/model 3D content?

Prompted directly: is 3D modeling/generation possible *inside* Godot,
not just importing assets made elsewhere. Short answer: **yes, at three
different levels**, none of which replace a full sculpting tool like
Blender for organic/detailed character work, but all genuinely usable for
this project's actual needs (blockout geometry, simple props, procedural
variation).

### Level 1: fully built-in, no addon - programmatic mesh generation

Verified directly via `--doctool` (see `AGENTS.md`), not just web search -
`SurfaceTool` (33 methods confirmed present: `add_vertex`,
`add_triangle_fan`, `generate_normals`, `generate_tangents`,
`generate_lod`, `commit`/`commit_to_arrays`, etc.), `ArrayMesh`, and
`MeshDataTool` are all real, mature, fully-featured classes for building
or editing mesh geometry entirely from GDScript - vertex by vertex or
triangle by triangle, with automatic normal/tangent/LOD generation. This
is genuinely how you'd procedurally generate 3D shapes at runtime or from
an editor script, no external tool needed. Also built-in: primitive meshes
(`BoxMesh`, `CylinderMesh`, `SphereMesh`, etc.) directly assignable to a
`MeshInstance3D`'s Mesh property for simple parametric shapes with zero
code.

### Level 2: in-editor modeling addons (grayboxing/blockout, not sculpting)

- **[Godot-Ply](https://github.com/jarneson/godot-ply)** — genuine
  in-editor **box modeling** (not just CSG primitives): Shift+Click to
  add/subtract selections, edge/face loop select, gizmos for translate/
  rotate/scale aligned to selected-geometry normals. Closer to a
  lightweight Hammer/TrenchBroom-style workflow than Godot's built-in CSG
  nodes (already logged under Level design, 2026-07-17 first pass) -
  worth comparing directly against Dioptra (also already logged) for
  facility blockout work.
- **[Godot-Sculptor](https://codeberg.org/dbat/godot-sculptor)** —
  different approach: procedural sculpting via 3D paths/curves rather than
  push-pull vertex sculpting, generates meshes at runtime, much smaller
  file sizes than heightmap-based approaches. Godot 4.4+.
- **[Goshapes](https://godotassetlibrary.com)** — curve-based level
  creation built on `Path3D`: generates block meshes, path meshes (fences/
  roads/corridors), and scattered instances along a drawn curve. Possibly
  relevant for corridor-heavy facility geometry specifically.
- **[Godot 3D Cursor Plugin](https://godotassetlibrary.com)** — editor-only
  QoL, adds a Blender-style 3D cursor so new nodes spawn at a chosen point
  rather than the origin.
- Terrain3D/GDExtension Terrain Heightmap Editor (already logged under the
  very first research pass) also count here for outdoor sculpting, not
  relevant to this project's indoor setting.
- **Consistent community consensus across every source found**: for actual
  organic/detailed sculpting (character work, ZBrush-style deformation),
  everyone still recommends Blender externally + `.glb`/`.gltf` import -
  Godot's in-editor sculpting ecosystem is described as "still maturing,"
  not a Blender replacement. The addons above are real and useful for
  blockout/procedural/parametric work specifically, not a substitute for
  what MotusMan/UAL/pistol_starter-style character assets need.

### Level 3: AI-based generation (text-to-3D / image-to-3D), 2026 state

- **[Meshy](https://www.meshy.ai/)** — text-to-3D and image-to-3D, has a
  **native Godot plugin**, low-poly mode for real-time engines, 2K-4K PBR
  texture export, generous free tier. Probably the most direct/lowest-friction
  option if this gets tried.
- **3D AI Studio** — similar text/image-to-3D pipeline, emphasizes clean
  GLB export with automatic remesh-to-low-poly, no native Godot plugin
  found but GLB is Godot's own recommended import format so friction is
  low regardless.
- **Ziva** / **Summer Engine** — broader in-editor AI *agents* (not just
  asset generators) that can also generate meshes/sprites as one capability
  among many (scene manipulation, GDScript generation, etc.) - already
  touched on briefly in the very first research pass's "AI-Assisted
  Development" section; logged here again specifically for their 3D-asset
  angle.
- Worth being clear-eyed about for a "learning sandbox" project
  specifically (per `AGENTS.md`'s stated purpose - "build each system
  properly to learn Godot"): AI-generated assets solve an *asset*
  production bottleneck, not a *learning* one - using them for props/set
  dressing doesn't undercut the project's learning goals the way using
  them to skip understanding a system (like the retargeting math) would.

**Status: research only.** No conclusion pushed either way on adopting any
of this - logged because it directly answers a question asked, not because
it's flagged as needed.

## 2026-07-17, seventh pass — can we generate a new *rigged, animatable* 3D character?

Direct follow-on from the previous pass. Yes, and the 2026 pipeline is
real: AI mesh generation (text or image prompt) → **auto-rigging**
(places a full bipedal skeleton on the mesh automatically, reading
shoulder/hip/spine geometry) → export as FBX/GLB with the rig and skin
weights intact, into Godot.

- **[Meshy](https://www.meshy.ai/tutorials/character-auto-rigging-workflow)**
  — auto-rigs a "production-ready skeleton" in under 30 seconds from an
  uploaded or generated humanoid/biped/quadruped mesh, no manual weight
  painting. Also ships **600+ preset animation clips** (walk/combat/idle/
  emote/jump/dance) designed to blend cleanly. Free tier: 100 credits/month,
  rigging itself is free. Exports FBX/GLB/USDZ - FBX is the tutorial's own
  recommendation for "preserving skeletons and skinning across game
  engines."
- **[Mixamo](https://www.mixamo.com/)** (Adobe, free) — the long-established
  alternative: upload a T/A-pose humanoid mesh, get a free auto-rig back,
  paired with Mixamo's own large animation library. Its own documented
  limitation: **biped/humanoid only**, not viable for creatures or
  non-humanoid shapes. Directly relevant because the
  **[Mixamo Animation Retargeter](https://github.com/RaidTheory/Godot-Mixamo-Animation-Retargeter)**
  addon (logged in the very first research pass) already exists
  specifically for bringing Mixamo-rigged content into Godot.
- **Tripo AI**, **Rodin AI**, **Uthana (on Scenario)** — comparable
  auto-rigging pipelines, logged as alternatives without a deep
  comparison; Tripo is cited as fastest end-to-end (modeling + texturing +
  retopology + rigging in one pass).

### The honest caveat - this doesn't bypass what this session actually learned

Checked directly (not assumed): Meshy's own tutorial does **not** claim its
output skeleton matches any specific standard (Mixamo, UE5 Mannequin, or
otherwise) out of the box - it explicitly documents that you may need to
**"rename or re-parent joints to match your target game engine's bone
naming convention"**, and that for engines with humanoid-retargeting
systems (their example: Unity's Humanoid rig type), you still set up
retargeting rather than getting drop-in compatibility for free. **This is
exactly the same class of problem this project spent an entire session on**
(`docs/task_history/ual_animation_retargeting.md`) - a new AI-generated
character does not arrive pre-matched to this project's existing UAL
animation library any more than UAL arrived pre-matched to MotusMan.

What's genuinely different now versus at the start of that saga: this
project has a **working, verified retargeting formula**
(`_humanoid_retarget_local_pose()`, the actual `RetargetModifier3D` math)
and, as of the sixth research pass, a confirmed-present built-in IK
framework for any remaining contact/grip corrections - so bringing in a
new AI-generated character and retargeting the existing animation set onto
it is now a *repeatable, understood* process rather than the open-ended
unknown it was originally. The realistic pipeline, if this is ever
attempted: generate + auto-rig the character → import to Godot → build a
`BONE_MAP` for its skeleton's names (same pattern as UAL's) → reuse
`_humanoid_retarget_local_pose()` unchanged. The alternative path - using
the generator's *own* bundled animations (e.g. Meshy's 600 presets)
instead of the existing UAL library - trades away everything already
invested in UAL/UAL2 integration for a different, untested animation
source, so isn't obviously better even if initially less friction.

**Status: research only.**

## 2026-07-17, eighth pass — Godot MCP for driving the in-development character editor

Prompted by a specific need: an agent needs to visually inspect and
interact with `tools/character_editor/character_editor.tscn` (per
`AGENTS.md` - a running 3D tool with gizmos, joint selection, camera
Orbit/Move, drag-to-rotate rings) at runtime, not just edit its scene
files at rest. Note this project's character editor already has a
CLI-args deterministic-inspection mode built in (`--` args like
`bone=`, `pick=`, `capture=`, `dump_bones=`) specifically for
non-interactive agent use - an MCP server would be for *interactive*,
visual, real-time manipulation on top of that, not a replacement for it.

### A real contradiction found and resolved - methodology note

A comparison article (summerengine.com, a competing commercial product)
claimed flatly that **no** Godot MCP server can screenshot a running game
or simulate input - "What it cannot do is interact with the running
engine." This directly contradicted GDAI MCP's own marketing claims.
**Did not take either secondary source at face value** - went to GDAI
MCP's own GitHub README, then its docs/changelog pages, and found
concrete, named, dated tool additions
(`get_editor_screenshot`, `get_running_scene_screenshot`,
"Now AI can simulate inputs in your game!" per the changelog) that
directly refute the comparison article's claim. **The competing vendor's
comparison article was wrong or outdated about a competitor's product** -
same lesson as [[feedback-check-engine-source-before-hand-deriving]]:
verify a specific, checkable claim against the primary source instead of
trusting a summary, especially one written by an interested party.

### Comparison of the two real contenders

Both genuinely support running-game screenshots and input simulation, not
just editor/file-level scene manipulation - the two live options for this
project's specific need:

| | **[GDAI MCP](https://gdaimcp.com/)** | **[Godot MCP Pro](https://github.com/youichi-uda/godot-mcp-pro)** |
|---|---|---|
| Price | Paid, via buymeacoffee.com (specific tier not published on the docs page checked) | **$15 one-time, lifetime updates** |
| Godot version | 4.1+ | 4.x |
| Screenshot tools | `get_editor_screenshot`, `get_running_scene_screenshot` | `get_game_screenshot`, `get_editor_screenshot`, **`capture_frames`** (multi-frame) |
| Input simulation | Keyboard + Input Actions ("AI can simulate inputs in your game") - **no explicit mouse-position/drag tool confirmed** in the docs checked | `simulate_key`, **`simulate_mouse_click`**, **`simulate_mouse_move`**, `simulate_action`, `simulate_sequence` (frame-delayed sequences) |
| Runtime introspection | Not detailed in docs checked | `get_game_scene_tree`, `set_game_node_property`, `navigate_to`, `move_to` - live property get/set while running |
| Tool count / scope | Not enumerated | **175 tools total**, selectable modes (Full 175 / 3D 103 / Lite 84 / Minimal 35) via CLI flag - avoids loading everything if not needed |
| Install (Claude Code) | One CLI command (`claude mcp add ...`) after copying the addon folder in; requires `uv` pre-installed | Copy addon folder in, `npm install && npm run build` (server code only included in the paid package), point client config at built `index.js` |

**Recommendation for this specific use case, with reasoning, not just the
higher tool count:** **Godot MCP Pro** is the better fit specifically
*because* the character editor is gizmo-drag-heavy - "drag the selected
joint's red/green/blue rings to rotate," "single-click drag... to Orbit or
Move the camera" (both quoted from `AGENTS.md`'s own description of the
tool). That interaction pattern needs actual mouse position + click/drag
simulation, not just keyboard/action input - which is exactly the gap
between the two servers found in the docs actually checked (GDAI MCP's
docs mention keyboard/action simulation but never explicitly confirm
mouse position control; Godot MCP Pro explicitly lists
`simulate_mouse_move` alongside `simulate_mouse_click`). The bounded
one-time price and selectable tool-scope (no need to load all 175 tools
if only screenshot + mouse + a handful of runtime-inspection tools are
actually needed) are secondary reasons, not the main one.

**Not installed. This needs the user's explicit go-ahead before setup** -
both options mean running a third-party server (Node.js for Godot MCP
Pro, Python/`uv` for GDAI MCP) with editor and filesystem access, which is
a real environment/trust decision, same category as the Git LFS TODO
above, not something to do unprompted. Added as a new Open TODO.

**Superseded, see above**: decided to build a custom MCP server instead of
installing either third-party option - see the "MCP for the character
editor" Open TODO entry and `docs/character_editor_mcp_plan.md`.

## 2026-07-17, ninth pass — a third way to read a pose besides screenshot or raw numbers

Prompted directly: besides a screenshot (vision) or a raw dump of bone
quaternions/Euler angles (precise but hard to spatially reason about
without mentally rendering it), is there another way for an agent to
understand a humanoid pose? Yes - **posecodes**, from pose-to-text
research: **[PoseScript](https://europe.naverlabs.com/research/publications/posescript-3d-human-poses-from-natural-language/)**
and **[MotionScript](https://arxiv.org/html/2312.12634)**. Checked
directly (fetched the paper, didn't just trust a summary) whether this
needs a trained model - **it doesn't**: posecode extraction is confirmed
rule-based geometry (angle between joint direction vectors, L2 distance
between joint pairs, axis-aligned coordinate comparison, then if/elif
bucketing into named categories). Three types: **angle posecodes**
(`straight`/`slightly bent`/`partially bent`/`bent at a right angle`/
`almost completely bent`/`completely bent`), **distance posecodes**
(`close`/`shoulder width`/`spread`/`wide apart`), **relative-position
posecodes** (`left of`/`right of`, `above`/`below`, `in front of`/`behind`,
pure sign comparison, no trig). The angle computation is literally the
same primitive (`angle_to()` between two bone direction vectors) already
proven working this session for the knee-bend retargeting diagnosis - not
new territory, just a new packaging of a technique already in hand.
Exact degree/distance thresholds aren't published in the paper text
(would need the linked codebase or to pick reasonable ones ourselves).

Proposed as a new `describe_pose()` tool for the character editor MCP
(full design in `docs/character_editor_mcp_plan.md`) - a genuinely third
distinct modality alongside vision and raw numbers: a compact categorical
summary like `{"right_elbow": "bent at a right angle", "hands_distance":
"close"}`, complementing rather than replacing the raw bone dump.

**Status: adopted into the character editor MCP plan, not yet built.**
