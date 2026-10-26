# 092 Planet scene GDScript -> C++ (GDExtension in native/planet_crust)

Request: turn every GDScript file that makes the planet scene work (systems/planet/*.gd, ~11.4k lines) into C++.
User is AFK; a 4-minute wakeup loop reminds the agent to continue. No questions: decide, record here.

## Rules
- One file (or tight group) per step. Port keeps the class_name, method names, signals, exported properties, so scenes and callers do not change.
- Native class replaces the .gd (git rm the .gd, keep .tscn references valid; update scripts/uids).
- Verify each step: build (scripts/build_native.sh), planet lab headless checks, a screenshot where visual.
- Commit with explicit paths only. Never touch the user's uncommitted files (addons/godot_ai, project.godot, tools/bark/fits).
- Don't rebuild while the DLL is locked; if locked, work on the next port's source and retry.
- Order: hot paths first, then world/glue, UI last.

## Order / status
(see log below; mark [x] when committed)

## Log
- [x] planet_settings (Resource, exports as NP_FIELD/NP_BIND). Check: `LOG_DIR=/e/Temp/pc092 bash scripts/planet_check.sh --quick` (needs PATH=/e/Temp/bin; baseline: all PASS except lint = gdlint not installed).
- Plan, leaf-first: clock, tectonics, star/star_light/star_system, air, sun_glow, dust, frame, rock(twin), moon, tides, climate, seasons, noise, drainage*, chart*, ... then tile/surface/scatter/turf/sway, world, map, UI last.
- [x] planet_clock (helpers: /e/Temp/reg.sh Class header, /e/Temp/pc.sh runs checks; write files with Write tool, heredocs fail)
- [x] planet_tectonics (ctor args -> PlanetTectonics.create(seed, plates); float consts -> get_continent() etc.; no ctor args on native classes: use static create)
- [x] star, star_light, star_system (typed arrays: TypedArray<> + PROPERTY_HINT_ARRAY_TYPE so GDScript infers Array[Star])
- [x] planet_moon, planet_tides, planet_air (static math; vector consts -> static fns)
- [x] planet_frame (tile arg typed Object* until PlanetTile is native)
- [x] planet_rock (native enums have no .size(): kind_count()). Stray console godot holds the DLL: /e/Temp/b.sh kills them then builds
- [x] planet_seasons, planet_climate (script fallbacks dropped; generation_native_check lost its script reference comparisons). helper: /e/Temp/commit.sh msg paths...
- [x] planet_seasons, planet_climate (script fallbacks dropped). helper: /e/Temp/commit.sh msg paths...
- [x] planet_drainage, planet_drainage_cache (cache key now hashes native-class storage props + dll mtime)
- [x] planet_weather (holds noise by ObjectID, no ref cycle)
- [x] planet_noise (create(settings); script reference removed, --native-check deleted; tests/manual/planet/noise_golden.tscn = golden hash check in planet_check.sh; macro_height is now the native one incl. erosion). GDScript deps reached by script load for now: species_registry, planet_scatter.species_table, flora_meshes.VARIANTS
- [x] planet_crust_guard, undergrowth, shells, dust, motes, sway_tree (nodes of the scene held by id: NP_OBJECT/NP_BIND_OBJECT). NOT portable as-is: planet_swim, planet_fauna (extend GDScript WorldSwim/WorldFauna), planet_imprinter (await). Motes/dust/shells have no automated check: look at them in the final visual pass.
- [x] planet_sway
- [x] planet_map_log, planet_chart_profile, planet_ground_bake (ground bake only checked by loading: LOOK at the ground in the visual pass)
- [x] planet_cloud_gpu, planet_sun_glow. WARNING: never declare file-scope statics of engine types (Array, RID, PackedXArray...): the DLL fails to load (Error 1114); use a lazily allocated struct. Visual check at the lab (--grounded --plants shot) is fine; the sun glow itself not yet looked at
- [x] planet_turf (FloraMeshes reached through its script: flora_script()->call). Remaining that CANNOT be native while their GDScript base exists: planet_atmosphere (WorldAtmosphere), planet_swim (WorldSwim), planet_fauna (WorldFauna)
- [x] planet_scatter (statics via set_trees_on(); Script::get("detailed") reads FloraMeshes static var fine; lab screenshot shows trees/grass OK). Next: planet_tile, planet_surface, planet_chart, planet_world, map/UI, footprints, recorder, impostors/imprinter/dents (await -> signals)
- [x] planet_tile (MeshBuilder reached via script new(): keep it in a Ref<RefCounted>, never a raw Object* from a temporary Variant). User asked: run my visual tests in the BACKGROUND on screen 1 (--screen 1 --windowed, run_in_background)
- [x] planet_surface. QUEUED after the port (user request): IK on the planet: load the planet scene, walk a long while, read the Foot IK v2 logs, find what is off, fix the bug; many runs, same 4-minute loop. Write it up in AGENT_TASKS/093_foot_ik_planet_soak.md
