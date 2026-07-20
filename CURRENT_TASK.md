# Current Task: One unified character + animation system

**Branch:** `player-swappable-skin`
**Status:** Phase 0 complete (catalog module + 3-character proof set migrated).
Phase 1 (extend `HumanoidRetargeter`) not started.

## End goal (in plain terms)

1. **One onboarding pipeline.** Any humanoid asset — rigged or a bare mesh —
   goes through the character editor once: import, auto-map or generate a
   rig. That's already mostly built.
2. **One shared catalog.** The result becomes a list of ready-to-use
   characters, not tool-only preview subjects.
3. **Any character, any role, anywhere.** Pull one from that catalog and use
   it as the player *or* as an NPC in any scene, and animation just works,
   because both roles are driven by the same underlying retargeting system
   instead of two independent ones.
4. **Converge over time.** Other existing character/animation assets
   (UAL1, UAL2, the Mixamo action-pack NPCs use, MotusMan's native clips)
   get folded into the unified system too, where practical — not a hard
   deadline, an ongoing direction.

## Reality check: there are three systems today, not one

- **`PlayerBody`** bakes its own rich UAL1/UAL2 locomotion+action set onto
  MotusMan's skeleton at load, via `_humanoid_retarget_local_pose` (FABRIK +
  swing retargeting, full finger chains, root motion, contact-timed combat).
  The most capable of the three, and the most gameplay-critical/fragile.
- **`HumanoidActor`** (NPCs) uses a simpler, separate system for
  locomotion (a plain Mixamo-family bone-*prefix* strip via
  `character_bone_prefix`, no full role-based mapping) - but its one
  retargeted clip (the UAL2 attack, via `components/unreal_mixamo_animation.gd`)
  already goes through `HumanoidRetargeter.retarget_clip`. So
  `HumanoidRetargeter` is *not* tool-only today, despite living under
  `tools/character_editor/` - it's already a real, if narrow, gameplay
  dependency.
- **The character editor tool** already has a third layer of abstraction —
  per-character-type adapters (`player_body_adapter.gd`,
  `mixamo_character_adapter.gd`, `retargeted_mixamo_adapter.gd`,
  `mapped_humanoid_adapter.gd`) that normalize all of the above into one
  common interface — but only for the tool's own posing/preview UI. None of
  it feeds real gameplay today.

Notably, `tools/character_editor/humanoid_retargeter.gd`'s own doc comment
says it's a **"Generic version of PlayerBody's UAL retarget engine...
extracted as a standalone utility instead of shared code, deliberately, so
nothing here can ever regress the already-hardened, gameplay-critical
player rig. Duplicated on purpose; do not merge back into player_body.gd."**
That boundary was drawn deliberately, to keep tool churn from ever risking
the hardened gameplay copy. This task's end goal directly reverses that
decision for `PlayerBody` specifically. That's fine — goals evolve — but
the risk the old boundary was protecting against doesn't go away, so the
migration needs its own safeguard: **build/extend the shared core as code
proven equivalent side-by-side, and only ever cut a consumer over once its
replacement is live-verified. Never edit the gameplay copy of the
retargeting math in place.**

**This resolves Phase 1's "which module to consolidate into" question:**
`HumanoidRetargeter` wins. It already has exactly the right shape - a
`BoneMapConfig` describing both rigs via data instead of hardcoded bone-name
constants (`bone_map`, `hips_source`/`hips_target`,
`head_source`/`head_target`, `shoulder_l/r_source`/`target`, `arm_chains`)
- and it's already proven safe in real gameplay via `HumanoidActor`'s
attack clip. `player_body_pose_math.gd` is the outlier that should
eventually retire, not the target. Phase 1's real work becomes: (a) confirm
`HumanoidRetargeter`'s `use_humanoid_retarget` path covers everything
`PlayerBody`'s own inline math does (root motion, hand/finger detail,
contact-timed combat baking - `HumanoidRetargeter` doesn't obviously handle
these yet, needs verification), and (b) write a translation from the
catalog's `humanoid_map: {role: bone_name}` shape into `BoneMapConfig`.

## The shared catalog module

Today the catalog only exists as `CharacterEditor.gd`'s own
`_custom_characters` dictionary, populated by walking disk when the tool
scene runs — inaccessible from `player.tscn`/`ui/hud.gd`, a different scene
entirely. This project already solved an identical problem for a different
asset type: `objects/object_catalog.gd` + `objects/object_definition.gd`
("Object catalogs are authoring data... collects explicit definitions and
provides filtering", per `AGENTS.md`). Follow the same shape:

- New `characters/character_catalog.gd` + `character_definition.gd`
  (stateless/static, no autoload needed) - the single place that scans
  `imported_characters/`/`generated_characters/`, lists entries, and loads
  a given entry's scene + `humanoid_map` + rest-facing offset. Called from
  the character editor tool, `PlayerBody`, `HumanoidActor`, and the debug
  menu alike - none of them own catalog logic themselves.
- `CharacterEditorRigHandler` becomes a *consumer* of this module instead
  of owning catalog scanning/persistence itself (`tools/object_library/`
  has the same relationship to `ObjectCatalog` already). Also relieves
  `rig_handler.gd`, which is already at the 1000-line lint ceiling.
- **Built-ins get migrated in, not kept separate.** `player`/MotusMan,
  `shambler`, `ch10`, `zombiegirl`, `x_bot`, `y_bot`, and the rest of
  `CHARACTER_KINDS` each get run through the rig tool once to produce a
  real, persisted `humanoid_map`, becoming ordinary catalog entries -
  exactly how `ObjectCatalog`'s "initial catalog is the CC0 KayKit weapon
  pack" is just pre-registered data, not special-cased code. One list, not
  "is this built-in or custom" branching in every consumer forever.
- **Rest-facing becomes catalog metadata, not per-instance tuning.** Each
  entry stores an auto-computed yaw offset (reusing `_skeleton_rest_facing`,
  already implemented for the tool's comparison harness), with an optional
  manual-override field for cases the automatic derivation gets wrong -
  mirroring how auto-map already coexists with manual joint overrides.
  Removes `HumanoidActor.character_yaw_offset_deg`'s current requirement to
  hand-tune yaw every time a character gets placed in a new scene.

This module is a prerequisite for Phase 2 onward, not just Phase 5 - even
"cut PlayerBody over to the shared core" implies PlayerBody can look up a
character's `humanoid_map` on its own, outside the tool.

## Migration philosophy

- **Non-destructive and incremental.** All three existing systems keep
  running throughout. Nothing gets deleted until whatever replaces it has
  been live-tested and confirmed equivalent (or better).
- **Content variety can stay.** NPCs and the player don't need to play the
  *same* clips — they can keep their own appropriate animation sets
  forever. What unifies is the retargeting *machinery* underneath (one
  `humanoid_map`-driven core), not the content choices on top of it.
- **Cut over system-by-system**, each with its own explicit "old output vs.
  new output" verification step. No big-bang rewrite.
- **Live-test every phase before committing** — no exceptions, and this
  now includes NPC combat-critical code (attack contact timing, damage
  windows) which is just as easy to silently break as player code.

## Phased plan

### Phase 0 — Inventory, catalog module, and built-in migration
- [x] List every current animation source precisely. Done - see "Reality
      check" above; also surfaced that `HumanoidRetargeter` is already a
      real (if narrow) gameplay dependency via `HumanoidActor`'s attack
      clip, which resolved Phase 1's consolidation-target question.
- [x] Build the shared catalog module: `characters/character_catalog.gd`
      now exists (`list_all`, `persist_character`, `generate_uuid_v4`,
      `ensure_id`, `delete_character_assets`, and friends), extracted out
      of `character_editor_rig_handler.gd` (which dropped from 1000 to 833
      lines as a result) and `character_editor_import_handler.gd`, both of
      which now consume it instead of owning disk I/O. Verified via
      `scripts/check.sh`, a headless scene boot, and a live
      `CharacterCatalog.list_all()` call confirming it correctly reads the
      real (currently empty - see below) on-disk state.
      Deliberately scoped down from the original plan: kept plain
      `Dictionary` entries (matching how `_custom_characters` already
      works) rather than introducing a typed `character_definition.gd`
      Resource class yet, and left `REQUIRED_ROLES`/`auto_map`/
      `full_map_from_prefix` (rig-mapping *computation*, not storage) in
      `rig_handler.gd` - narrower, lower-risk first cut.
- [x] Migrated the 3 needed for the proof set (not all 12 - see below):
      `builtin_motusman`, `builtin_x_bot`, `builtin_y_bot`. Each got a
      manifest written next to its existing source model (
      `pistol_starter/MotusMan/MotusMan_v55.character.json`,
      `mixamo_characters/X Bot.character.json`,
      `mixamo_characters/Y Bot.character.json`), with a full bone-level
      `humanoid_map` (`full_map_from_prefix` maps every bone sharing the
      prefix, not just the 19 `REQUIRED_ROLES` - 80 bones for MotusMan, 65
      for each Mixamo bot, fingers included) and a computed
      `rest_yaw_offset_deg` (via `PlayerBodyPoseMath.skeleton_rest_facing`
      + `signed_angle_to` against Godot's canonical `-Z`). All three came
      out ~0° - a genuinely useful, non-obvious finding: `x_bot`/`y_bot`
      (Mixamo's own generic reference rigs) are *not* subject to the
      "authored facing +Z, needs 180°" convention `AGENTS.md` documents for
      the actual zombie/action-pack FBXs already in use - don't assume
      that convention generalizes to every Mixamo-family asset without
      computing it per-rig, which is exactly why this is computed, not
      hardcoded.
      **Deliberately used distinct `kind_id`s** (`builtin_x_bot`, not
      `x_bot`) rather than reusing `CHARACTER_KINDS`' own strings -
      `character_editor.gd`'s `_load_character()` checks
      `_custom_characters.has(kind)` *before* falling back to the plain
      `MIXAMO_CHARACTERS` adapter it uses today, so a same-named catalog
      entry would have silently switched which adapter loads `x_bot`/`y_bot`
      in the tool - an unverified, out-of-scope behavior change. Confirmed
      via a live scan that `CharacterCatalog.list_all()` returns zero
      entries under the literal `"player"`/`"x_bot"`/`"y_bot"` keys.
      Remaining 9 (`shambler`, `brute`, `vanguard`, `parasite`,
      `copzombie`, `zombiegirl`, `ch08`, `ch10`, `ch15`): explicitly
      deferred to whenever they're actually needed, not migrated on spec.
- [x] Decide the first two-or-three-character proof set for later phases:
      MotusMan + `x_bot` + `y_bot`, as recommended.
- [x] Confirmed live (via the running editor's MCP bridge,
      `dump_live_bone_poses`): both `x_bot` and `y_bot` use the plain
      `mixamorig_<Role>` convention with no gaps (`mixamorig_Hips`,
      `mixamorig_Spine1`, `mixamorig_Spine2` all present) - `
      full_map_from_prefix` will produce a complete `REQUIRED_ROLES`
      mapping for both with zero manual mapping needed.

**Note on current catalog state:** while verifying the extraction, found
that the catalog is presently *empty* - `zombie2` (the character used to
test the Delete Permanently feature earlier this session) was actually
deleted during that live testing, and no other character has a persisted
manifest (`Ch28_nonPBR` predates the manifest convention entirely). Not a
bug - confirmed via `git log`/`git status` that this matches the already-
committed state. Worth knowing before Phase 0's remaining item (built-in
migration): there's currently nothing in the catalog to migrate *to*
alongside, it'll be the first real content in it.

**End-to-end live import test (via the real `test_import_character`/
`test_button_click` MCP tools, added to `server.py` specifically because
this project's own principle is that the tool must be agent-testable, not
just human-testable) surfaced and fixed two real, pre-existing bugs, both
now fixed and verified:**
1. `EditorFileSystem.reimport_files()` fails outright ("Can't find file...
   during file reimport") on any path inside a directory it has never
   scanned - true of every character's brand-new per-id folder now, never
   true of the old shared flat directory. Fixed in
   `addons/mcp_bridge/pose_debugger_plugin.gd`'s `_import_asset`: call
   `EditorFileSystem.scan_sources()` and await `is_scanning()` clearing
   before `update_file()`/`reimport_files()`.
2. `reload_editor_bridge` has been silently non-functional for actual code
   changes since it was built: `plugin.gd`'s `_register_pose_debugger()`
   was missing the `update_file()` cache-bust call that its sibling reload
   path (`commands.gd`'s, in `_handle_command()`) already documents as
   required - GDScript keeps its own compiled-script cache independent of
   `ResourceLoader`'s `CACHE_MODE_REPLACE`. Fixed by adding the same call.
   (This bug is why the fix for #1 above needed a full editor restart to
   verify, not just `reload_editor_bridge` - confirmed by observing the
   error log still cite pre-edit line numbers after a "successful" reload.)

Verified via a real live import of `x_bot`'s FBX: correct UUID folder,
correct manifest location inside it, fully auto-mapped `humanoid_map` (63
roles incl. fingers), `id` matching the folder name.

**Full import -> delete round trip then verified live end-to-end**, using
the actual `zombie2.glb` from Downloads: imported via `test_import_character`
(correct UUID folder + manifest), selected via `set_live_character` (through
the new `send_editor_bridge_command` passthrough, which accepts custom
kind_ids the Python tool's enum-typed wrapper doesn't), the real
"Delete Permanently..." popup menu item clicked via a new
`test_popup_item_click` diagnostic (menus fire `id_pressed(id)`, not the
zero-argument `pressed` `test_button_click` handles), confirmed visually via
a live screenshot that the modal opened correctly with the full-window
backdrop, then the real Confirm button clicked via `test_button_click` -
`"Deleted zombie2 and its asset files"`, folder gone from disk, `Ch28_nonPBR`
untouched. Two new permanent MCP diagnostics added as a result
(`test_popup_item_click`, and `send_editor_bridge_command` - a generic
passthrough onto any `commands.gd`/`character_editor_mcp_handler.gd` `cmd`,
added so future diagnostic additions never need a new dedicated Python tool
+ MCP reconnect again, since only the Godot-side files need to change).

### Phase 1 — Extend HumanoidRetargeter to cover PlayerBody's full feature set
Consolidation target decided (see above): `HumanoidRetargeter`, not
`player_body_pose_math.gd` - it's already data-driven via `BoneMapConfig`
and already proven in real gameplay (`HumanoidActor`'s attack clip).
- [ ] Audit `HumanoidRetargeter.retarget_clip`/`use_humanoid_retarget`
      against everything `player_body.gd`'s inline retargeting does that it
      might not yet: root motion track handling, full finger-chain detail,
      hand retarget modes, contact-timed combat baking. List gaps
      precisely before writing anything.
- [ ] Close those gaps inside `HumanoidRetargeter` (still consumed by
      nobody real yet except `HumanoidActor`'s narrower attack-clip case,
      which must keep working unchanged throughout).
- [ ] Write the translation from a catalog entry's `humanoid_map: {role:
      bone_name}` into a `BoneMapConfig` instance.
- [ ] Prove the result bit-for-bit (or visually, via Compare mode)
      equivalent to `PlayerBody`'s current MotusMan output before anything
      real consumes it. This phase changes nothing a player or NPC can see
      yet.

### Phase 2 — Cut PlayerBody over to the shared core
- [ ] Swap `player_body.gd`'s internal retargeting calls to the new shared
      core, keeping MotusMan as the only real skin still. Behavior must be
      provably unchanged (Compare mode, live playback of every gameplay
      clip category).
- [ ] Generalize the body/skeleton/mesh wiring itself: `player.tscn`'s
      `Body` node currently *is* a direct instance of the MotusMan FBX
      (`W1_Stand_Aim_Idle_IPC.fbx`) with `skeleton`/`mesh` found via fixed
      `@onready` paths (`$Skeleton3D`, `$Skeleton3D/MotusMan_v55`, a single
      mesh, not a list). Change this to instantiate an `@export var
      character_scene: PackedScene` at runtime and find `Skeleton3D` /
      mesh parts dynamically — mirroring `HumanoidActor._setup_character()`
      (`actors/npcs/humanoid_actor/humanoid_actor.gd:72`), the pattern that
      already works for NPCs. Default `character_scene` to today's MotusMan
      FBX so nothing changes with zero config.
- [ ] Re-verify the documented Godot 4.6.2 `AnimationMixer` segfault gotcha
      (mutating an `AnimationLibrary` mid-crossfade) under the new
      instantiation timing — don't just assume the old mitigation still
      applies unchanged.

### Phase 3 — Cut HumanoidActor over to the shared core
- [ ] Replace its bone-*prefix* mapping with the same `humanoid_map`
      lookup the player now uses, keeping its existing (smaller) clip set.
      NPC behavior must stay identical or improve — not regress.
- [ ] Live-test patrol/chase/attack contact timing specifically, since
      that's the NPC-side equivalent of the player's fragile action-contact
      system.

### Phase 4 — Prove "any character, any role" on a second skin
- [ ] Take one catalog character (e.g. `x_bot`) and use the *same* imported/
      rigged entry as both a player skin and an NPC skin, end-to-end.
- [ ] Accept a known-imperfect held-item grip if not separately tuned yet —
      call it out explicitly rather than silently shipping a bad-looking
      grip. `flashlight_grip_pose.json`'s finger rotations and the
      flashlight's `0.12` scale were hand-tuned to MotusMan's specific hand
      size; a different skin needs its own tuning or a documented
      "close enough" default.

### Phase 5 — In-game character swap (the real acceptance test)
Resolved: not a scene export, not save-file state — the **in-game debug
menu**. `ui/hud.gd`'s existing `DebugOverlay` already has this exact shape
for other catalogs: `ObjectListButton`/`ObjectPanel` lists spawnable
objects, `AnimClipsButton`/`AnimPanel` lists animation clips. A
`CharacterListButton`/`CharacterPanel` belongs right alongside them.
- [ ] Add a Character page to the debug menu listing the shared catalog
      (the same list the character editor tool already builds/persists).
- [ ] Selecting an entry swaps the *live* player's `character_scene` during
      an actual play session — not a restart, not the editor tool.
- [ ] Baking a full clip library onto an arbitrary skeleton isn't instant
      (import already warns "may take a few seconds" for one asset) - show
      a brief loading message on the panel while the bake runs, mirroring
      the character editor's own "Importing... this may take a few
      seconds" status pattern, rather than let the game hitch silently.
- [ ] This is the concrete proof the whole task succeeded: **stand in a
      real level, open the debug menu, pick any imported character from the
      list, watch the player become that character with animation already
      working.** If that doesn't hold for an arbitrary catalog entry, the
      unification isn't done yet, regardless of what Phases 1-4 claim.

### Phase 6 — Ongoing convergence (opportunistic, not a hard finish line)
- [ ] Fold other existing animation-asset variations into the unified
      system as opportunities come up, per "any other asset with variation,
      if possible, we will convert it."

## Explicit non-goals (for now)

- **Not** supporting fully arbitrary imported models as playable/NPC skins
  in the near term — only the curated proof set from Phase 0, until Phase 4
  demonstrates the pattern holds.
- **Not** a single big rewrite — see migration philosophy above.

## Open questions

- Does `x_bot`/`y_bot` need finger-chain mapping for held-object grip to
  look right, or is "roughly the same hand size" good enough for Phase 4's
  bar?
- Should `humanoid_retargeter.gd` physically move out of
  `tools/character_editor/` (e.g. to `components/`, alongside
  `unreal_mixamo_animation.gd`) once `PlayerBody` also depends on it? Its
  current location is a misnomer once it's a real gameplay dependency for
  two systems, not one — cosmetic, not blocking, worth doing whenever it's
  convenient during Phase 1.
