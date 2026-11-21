# 100 - More plant species and a fuller population

SUMMARY of the first session (2026-11-18, all UNCOMMITTED, built into the double DLL; details in the Log below):
- New tree kinds: poplar, olive, beech, linden (on), pine (on, bottle-brush pads), bristlecone (off). Broadleaf quota 4 -> 6 (CHANGES the species of every seed: revert `QUOTA` to keep saves).
- Realistic mushrooms were white (the stone rule for sway < 0.1 and no UV): fixed; new mushroom shape; moss mats; rounded flowers with natural colours; fern rosettes with fiddleheads.
- Fuller forest floor (cover layer 1.7 m / 0.7 chance, +0.4 ms GPU on the forest walk); densities of fern, mushroom, flower and shrub up.
- Cost of everything on the forest walk: gpu 2.9 -> about 3.0-3.5 ms (noise between runs), draw calls 710 -> 740-752.
- Tree quality fixes (task 099): conifer bottle-brush needles and bare lower trunks, far needle fill, per-leaf colour, log shader and bark, limbs that no longer lie flat on the ground.

## DECISION TO EVALUATE WHILE TESTING: broadleaf quota 6 (was 4)
- Where: `QUOTA` in `native/planet_crust/src/species_generator_native.cpp` (~line 56), `{ 3, 6, 1, 1, 6, 2, 4, 2, 2, 6, 3, 2 }` = conifer, broadleaf, palm, bare tree, shrub, cactus, grass, tall grass, reed, flower, fern, mushroom.
  The shares are scaled to the species count (the planet's default is 120): broadleaf is about 19 species instead of 13. Rebuild with `scripts/build_native.sh --double` after any change.
- The user's current leaning (2026-11-18): **6 looks better** (more kinds of leafy tree per world). Not yet tested across many seeds: only seed 8 and seed 1337 by eye.
- Known cost: the species mix of EVERY seed changes, so saved worlds load with different plants. If saves matter, go back to 4: `{ 3, 4, 1, 1, ... }`.
- What to check when testing it: (1) variety: count tree species by kind on 4-5 seeds (a headless script like `tests/manual/world/forest_density.gd` / the `archetype` count used in tick 24 of this log); (2) no form is starved
  (conifers, shrubs, flowers still have species at a land spot of each biome); (3) forests still read as forests, not a zoo (no single spot with 8 different broadleaf looks); (4) the forest walk cost (`scripts/gpu_breakdown.sh`);
  (5) if going higher than 6, re-check that conifers and shrubs keep enough of the shares.
- Same kind of "decide by looking" item: leaf size (task 099 tick 51: card factor 1.1, the old value is 1.7 in `grow_stem()`).

Status (2026-11-18): **OPEN, started while the user was away.** The user's words: "add more tree species, more plant species, grass, mushroom, etc, use the open
google image as ref, don't close the google images tab, open new tabs from this tab so you don't lose it, use the images as references, we need more population
of plants, how many you can add on this session?"

## How species work now (read before changing)
- A world makes `species_count` species (default 36, `systems/world_gen/world_settings.gd`, native `PlanetSettings`) from the seed in `native/planet_crust/src/species_generator_native.cpp`.
  Shares per form are `QUOTA` (3 conifer, 4 broadleaf, 1 palm, 1 bare tree, 6 shrub, 2 cactus, 4 grass, 2 tall grass, 2 reed, 6 flower, 3 fern, 2 mushroom); other totals scale them.
- Names come from `nouns_of(form)` and `kind_noun` (named tree archetypes: umbrella, dragon, raintree, buttress, willow, cherry, blossom, ancient, oak, cypress, giant, birch, maple,
  spruce, juniper, baobab, elm, eucalyptus). Tree shapes: `tree_archetypes_native.cpp`; meshes: `plant_mesh_native.cpp`.
- Reference tabs: Chrome (chrome-devtools MCP) page "trees - Google" (Google Images). NEVER close or navigate it: open new tabs from it (`new_page`) and use `take_screenshot`.
  Also see memory `tree-species-reference-chrome`.

## Plan
1. More species per world: raise the default `species_count` and re-balance `QUOTA` (more grasses, flowers, mushrooms, shrubs, ferns; keep forests believable). Check cost (mesh cache,
   `species_check`, native check) and that existing seeds stay valid.
2. More names and looks per form (nouns, colours, shapes), checked against photos from the Google tab.
3. New forms only if cheap: candidates bamboo, succulents / agave, ground cover (moss, clover mats), lily pads. Each needs a builder.
4. Every step: pictures (gallery `species_gallery.tscn` page 1-4 and planet lab), `species_check.tscn`, `--native-check`.

## Log
- 2026-11-18: created.
- 2026-11-18: four new tree kinds added in `tree_archetypes_native.cpp` (+ names and climate weights in `species_generator_native.cpp`): `pine` (tall bare orange trunk, tufts at limb tips),
  `poplar` (slim column), `olive` (gnarled, silver narrow leaves), `bristlecone` (small twisted). Conifer weights: pine added; broadleaf: poplar (cool, wet), olive (hot, not wet).
  First pictures (scratchpad `kinds/sheet.png`, tree_builder_lab, white trunks because the lab has no bark): olive and poplar read well; pine was too sparse (5 tufts), set limbs 8, crown 5.5,
  needle_size 1.4; bristlecone not yet judged (clipped frame). `tree_builder_lab.gd` now takes `--kind=NAME --dist=X --yaw= --pitch= --focus=FRACTION --shot=PATH` and its
  "Copy properties" no longer fails (enum names through `ClassDB.class_get_enum_constants`). Default `species_count` of the planet is 120 (native `PlanetSettings`), the 36 is the old script.
  Still to do: planet-lab closeups of the bark and leaves of the new kinds (the lab shows white trunks), more shrub / flower / mushroom / grass looks, species_check + native check.
- 2026-11-18 (later): pine and bristlecone retried (not tips_only, not frosted): the needle tufts are still small and sparse on a tall bare trunk (needle length is capped near 1.1 m x trunk
  stoutness in `plant_mesh_native.cpp`), so both kinds are switched OFF in `archetype_of` (weight 0.0) until the spray is fixed (same cause as task 099's conifer finding). Poplar and olive are on.
- 2026-11-18 (loop tick 1): MUSHROOMS. Found why realistic mushrooms were pure white (also in the planet): `flora_wind.gdshader` line ~807 shades any vertex with `sway < 0.1` and no UV
  as STONE (rock photo) in the realistic look, and mushrooms were built with sway 0 and no UV. Fix: the native mushroom builder (`PlantMeshNative::mushroom`) paints with sway 0.105 (`soft`).
  Same builder now also has a bulbous foot, a tapering stalk, a cap in three rounded rings with a pale gill underside, and white flecks on red caps. Pictures: scratchpad `kinds/mushJ.png`
  (seeds 2, 3, 5, gallery `--page=4 --form=mushroom --detailed`): caps now cream / brown / orange; flecks not yet seen (no red-capped species in those seeds). The gallery got `--form=NAME`.
  Rule for any new ground plant built without UVs: give it a sway of at least 0.105 or the realistic shader turns it into rock. `SPECIES_CHECK PASS`, `GENERATION_NATIVE_CHECK PASS`.
  Reference tab: Chrome page 5 (opened from the Google tab) "forest floor mushrooms ferns moss": moss mats, shelf fungi, clustered small mushrooms, fiddlehead ferns: ideas for next ticks.
- 2026-11-18 (loop tick 3): no new species this tick; shader leaf-colour variation recorded in task 099. Next: ferns (fiddleheads), moss mats, shelf fungus, more flowers; the Google tab is untouched.
- 2026-11-18 (loop tick 4): FERNS. Before (scratchpad `close/fern0.png`, gallery `--page=4 --form=fern --detailed --seed=8`): each plant read as one or two lone arching sprigs with
  big oval leaflets (low plants skipped the fine pinnate strip and drew a full leaf shape per leaflet). Change: `plant_mesh_native.cpp` `frond()`: `strip = cards && g->leaflet >= 0.02` (the
  `!low_plant` is gone), so ferns and bracken use the shader's strip. After (`close/fern1.png`): a rosette of many fronds with fine pointed leaflets, reads as a fern / bamboo-like clump,
  fewer triangles. Not yet compared with the fiddlehead photos (Chrome page 5 first search) in the planet lab; fiddleheads (curled young fronds) are the next fern idea. `SPECIES_CHECK PASS`.
- 2026-11-18 (loop tick 5): FOREST FLOOR. Planet-lab pictures (scratchpad `close/floorg.png`, `close/dens_a.png`, `close/floor20.png`; seed 8 forest site): the floor is almost all grass (golden / lime),
  with a few big flat star-shaped purple flowers and almost no ferns or mushrooms; from above the forest reads well (dark conifers, white frosted ones, rust and lime broadleaf).
  Real forest floors (Google tab, "forest floor mushrooms ferns moss") are dense with ferns, moss, litter and mushroom groups. Change: niche densities in `species_generator_native.cpp`
  (fern 0.25-0.42 -> 0.4-0.68, mushroom 0.1-0.2 -> 0.2-0.36, flower 0.5-0.75 -> 0.65-0.95, shrub 0.14-0.4 -> 0.2-0.55). Result in the lab: no visible difference (31 FPS as before), so the
  limit is not the species density but how a layer's chance is shared: grasses (density up to 0.95) win nearly every grid point of their layer. Next: look at `_scatter` / the per-layer
  cap in `planet_scatter_native.cpp` so understory plants (ferns, mushrooms, moss) get their own layer or a guaranteed share under trees; then moss mats and litter. `SPECIES_CHECK PASS`.
- 2026-11-18 (loop tick 6): the limit was the COVER layer (ferns, mushrooms, tall grass): `planet_scatter_native.cpp` `SPACING` 2.6 m and `MAX_CHANCE` 0.5. Now 1.7 m and 0.7 (grass layer
  untouched). Lab picture `close/dens_c.png` (same view as `dens_a.png`): tan mushroom caps (the realistic colour fix from tick 1 now shows in the planet), a fern clump and more small
  plants on the floor, 29 FPS against 31 before (about -2 FPS in this view; measure with `--fps` / `scripts/gpu_breakdown.sh` before keeping). Still sparse next to the Google photos:
  needs moss mats and litter, and groups of mushrooms. Checks: SPECIES_CHECK PASS, GENERATION_NATIVE_CHECK see tick note below if it did not print PASS.
- 2026-11-18 (loop tick 7): COST of the denser cover layer, same forest walk (`planet_lab -- --plants --grounded --forest-walk=25 --weather=clear --hour=11 --fixed-fps 60`, Vulkan):
  old (2.6 m / 0.5): gpu 2.9 ms avg, p95 5.1, 710 draw calls, 787,854 primitives; new (1.7 m / 0.7): gpu 3.3 ms avg, p95 5.6, 732 draw calls, 800,832 primitives; frame rate 59.7 vs 59.9 (fixed 60).
  So about +0.4 ms GPU (+14 %), +22 draw calls, +1.6 % primitives: kept. Constants are back at the new values (the library was rebuilt twice for the comparison).
- 2026-11-18 (loop tick 8): MOSS MATS. New look inside the MUSHROOM form (no new enum): `archetype_of` gives mushroom species "mushroom" (3) or "moss" (2 if wet, else 0.5); name noun "Moss";
  `PlantMeshes::build` passes the archetype; `PlantMeshNative::mushroom()` builds a moss mat when it is "moss": 10-15 low rounded cushions, two greens, clustered within about 0.3-0.5 m, sway 0.105
  (the realistic stone rule). Gallery picture `close/moss.png` (seed 11, `--page=4 --form=mushroom --detailed`): a clump of green cushions beside purple caps; bright in the gallery's flat light,
  not yet seen in the planet (seed 8 forest site: none drawn there yet; check at a wet spot). Checks: SPECIES_CHECK / GENERATION_NATIVE_CHECK run after this change (see the lines printed in the tick report).
- 2026-11-18 (loop tick 9): moss species exist in the seed-8 planet (ids 117 Common Moss, 119 Silver Moss, 120 Woodland Moss; wet 0.77-0.95) but none was visible at three forest sites: the
  tall grass hides them (the grass layer is 0.95 chance every 1.7 m). Tried grass shade tolerance 0.3 -> 0.1 in `planet_scatter_script_native.cpp`: no visible change at the wet site (the crowns
  are high and open, so there is little shade to react to); reverted. Idea left: let the grass thin out near a moss or fern cover plant, or cap grass height under canopy.
- 2026-11-18 (loop tick 11): two more broadleaf kinds: `beech` (grey smooth trunk, wide flare, broad dense dome, wavy oval leaves) and `linden` (short trunk, rounded dense crown, large serrated heart
  leaves) in `tree_archetypes_native.cpp`, names and weights (cool, wet: beech 2.0 above moisture 0.45, linden 1.5 above 0.35) in `species_generator_native.cpp`. Lab picture `kinds/sheet_bl.png`
  (tree_builder_lab `--kind=beech|linden`): both read as believable broadleaf trees, the beech crown a little sparse; not yet seen in the planet. Tree kinds now: leafy, oak, ancient, umbrella,
  dragon, raintree, buttress, willow, cherry, blossom, birch, maple, elm, baobab, eucalyptus, poplar, olive, beech, linden (+ conifer, giant, cypress, spruce, juniper; pine and bristlecone off).
  SPECIES_CHECK and GENERATION_NATIVE_CHECK run after the change.
- 2026-11-18 (loop tick 12): `QUOTA` broadleaf 4 -> 6 (`species_generator_native.cpp`): a 120-species planet (seed 8) now has 28 tree species (was 25): juniper, 8 conifer, spruce, umbrella, eucalyptus,
  3 birch, 5 leafy, beech, maple, elm, ancient, linden, 2 oak, willow, buttress, 3 palm, 3 dead. (Seed 8 happened not to draw poplar or olive.) SPECIES_CHECK and GENERATION_NATIVE_CHECK PASS.
  Planet picture `close/mix40.png` (`--dir=-0.13406,0.66250,0.73697 --view-alt=40 --view-pitch=-12`): a broadleaf canopy of greens, lime and yellow patches (the per-leaf tone variation helps):
  the best overview so far. The 8 generic "conifer" species are still the weakest look (see task 099).
- 2026-11-18 (loop tick 13): NOTE: the tick-12 quota change (broadleaf 4 -> 6) reshuffles which species a seed makes (the planet picture at the seed-8 forest site now shows a different mix). If saved
  worlds must look the same, set `QUOTA` back to `{ 3, 4, 1, 1, ...}` in `species_generator_native.cpp`. Conifer blocks softened in the shader (see task 099, tick 13).
- 2026-11-18 (loop tick 15): FLOWERS. Gallery (`--page=4 --form=flower --detailed --seed=8`, `close/flowers0.png`): every flower was neon (cyan, magenta, saturated orange) and the colours did not
  match the names ("Red Lupine" was orange). `bright()` in `species_generator_native.cpp` picked any hue but green at saturation 0.55-0.95. Now it picks from a table of real meadow colours
  (white 2.0, yellow 2.5, orange 1.0, red 1.0, pink 1.5, violet 1.5, blue 1.0, each a narrow hue band and muted saturation / value; berries use it too). Picture `close/flowers1.png`: white, yellow
  and blue flowers, no neon. The flower SHAPE is still the same spiky star / tulip for every species (4-10 petals, `bloom()`); next: separate looks (daisy: many thin petals round a yellow disc,
  lupine: a tall spike of small florets, poppy: four wide cupped petals, bell: hanging cups). Google blocked the reference tab with a bot check this tick (page 5 now shows Wikimedia Commons
  search results instead; page 4, the "trees" Google tab, is untouched); use Commons for further references. SPECIES_CHECK and GENERATION_NATIVE_CHECK run after this change.
- 2026-11-18 (loop tick 16): flower SHAPES per kind in `tree_archetypes_native.cpp`: daisy 14 flat petals (cup 0) round a yellow disc, poppy 4 wide cupped petals (cup 0.75) round a dark centre, lavender 7 petals cup 0.9.
  Gallery pictures (`close/fl_sheet.png`, seeds 8, 21, 33): the colours are natural (white, yellow, pink, blue, orange) and the daisy kind is visibly flatter, but most flowers still read as small spiky
  stars on tufts of stems: the `bloom()` petal is one triangle, the cup is a lift, and a flower sits at the end of each stem with no leaves on the stalk. Real next steps: rounded petals (two-
  triangle petals with a width bulge), a visible centre disc for every kind, a leafy stalk, and a spike-of-florets look for lupine. SPECIES_CHECK PASS.
- 2026-11-18 (loop tick 17): ROUNDED PETALS. `bloom()` in `plant_mesh_native.cpp`: a petal is now three triangles (narrow foot, widest at 60 % of its length, then a point) instead of one, and the
  centre disc is drawn for every flower, not only in the realistic look. Gallery pictures `close/fp_sheet.png` (seeds 21, 33): flowers now read as pink cosmos, white anemones, yellow
  buttercups, blue and orange blooms with yellow centres: clearly flowers, not stars. Cost: +2 triangles per petal (a flower of 5 petals: 10 -> 15 triangles, +centre). SPECIES_CHECK PASS.
  Still to do for flowers: a leafy stalk, a lupine spike of florets, bell flowers (hanging cups).
- 2026-11-18 (loop tick 22): PINE and BRISTLECONE retried with big tufts: `plant_mesh_native.cpp` needle cap is now 2.2 (not 1.1) when `needle_size > 2.0`, pine and bristlecone use `needle_size 2.6` and
  `tips_only`. Lab picture `kinds/sheet4.png`: the tufts are bigger, but each is a comb of a few long fern-like strips, so the tree reads as a palm-topped tree, not a pine. Both kinds stay OFF
  (weight 0 in `archetype_of`). A real pine pad needs many short needle strips round a twig (a bottle-brush: 6-8 strips turned round the axis) and dense twigs at the limb ends; the present spray is
  three strips in a fan (`spray()`), which only suits a spruce-like frond. Next: a `bottle_brush` spray (strips turned 360 degrees) for pine, then switch the kinds on.
- 2026-11-18 (loop tick 23): PINE ON. `spray()` in `plant_mesh_native.cpp` has a bottle-brush branch (used when `needle_size > 2.0`, i.e. the pine kinds): 8 short strips turned all the way round the
  twig, reach 0.75-1.0 of the spray length, instead of the three-strip fan. Lab picture `kinds/pine6c.png`: a tall bare trunk with a flat-topped crown of dark green brush pads: a stone-pine /
  umbrella-pine silhouette, believable and far better than before (the tufts are still on the small side for a 24 m tree). Pine is back in `archetype_of` (weight 2.0 when moisture < 0.75, 0.3
  otherwise); bristlecone stays off (its tufts are fewer, on a twisted trunk: not judged again). SPECIES_CHECK and GENERATION_NATIVE_CHECK run after.
- 2026-11-18 (loop tick 24): PINE FULLER. Seed 8 now has 2 pine species (seed 1337: 2, seed 5: 2, seed 77: 3); in the planet picture (`close/pine_forest.png`, 30 m up) they stood out as bare spokes of
  limbs with a few small white-tipped pads. `branch()` now also puts a pad at 0.6 of every non-last limb of a pine (the `needle_size > 2.0` kinds): lab picture `kinds/pine8c.png`: a much fuller
  umbrella-pine crown. Open: the pads of the seed-8 pines are frosted white (the species' cold niche sets `frosted`), which looks odd on a pine; check `for_species` and turn frosted off for
  the pine kind unless the species is truly cold. SPECIES_CHECK PASS.
- 2026-11-18 (loop tick 24, follow-up): the white pads are by design: `for_species` (`tree_archetypes_native.cpp` line ~1088) copies `frosted` from the species, and `species_generator_native.cpp` line 366 sets
  `frosted = heat < 0.3`, i.e. a cold-niche conifer is drawn snow-covered (the snowy conifers of every forest). A pine in a cold niche is therefore frosted too; nothing to fix.
- 2026-11-18 (loop tick 28): pine at the smaller pad size, in the planet (`close/pine_d.png`, seed 8 forest, 30 m up): the pines are umbrella-pine shapes (bare spoked limbs carrying dark green pads;
  the frosted ones show white), clearly different from the surrounding broadleaf and bottle-brush conifers, and they blend into the forest without standing out. Accepted for now. Left: bristlecone,
  fern fiddleheads, lupine spike and bell flowers, leafy flower stalks, shelf fungus, a bark relief for logs.
- 2026-11-18 (loop tick 30): FIDDLEHEADS. `fronds()` in `plant_mesh_native.cpp`: ferns (low plants with leaflets, realistic look) get 2-4 rolled young fronds rising from the crown: a 12-step curl
  (up, then a 4.2 rad spiral) drawn as a thin leaf-green ribbon of triangles. First try used `tube()`, whose surface is marked as bark, and came out grey-white: the ribbon avoids that
  (rule: anything that is not bark must not use `tube`). Gallery picture `close/fern3.png`: green croziers among the fronds, the right-hand fern shows a clear one. Cost: 2 x 12 x 2 triangles
  per fern (about 50) in the realistic version only. SPECIES_CHECK and GENERATION_NATIVE_CHECK PASS.
- 2026-11-18 (loop tick 43): LUPINE. New flower kind `lupine` (`tree_archetypes_native.cpp` NAME_LIST / PLANT_LIST / genome; name noun "Lupine"; weight 1.5 in the flower `archetype_of`): a tuft of narrow
  leaves and tall stalks that end in a spike of 9 small florets, each turned a different way round the stalk and shrinking toward the tip (`frond()`: `g->petals == 3` is the marker for the
  spike look). Lab picture `kinds/lupine_c.png`: violet spikes on tall stems, reads as lupine / delphinium. The `Range` table had `petals` from 4, which `nudge()` used to pull the marker 3
  back to 4: now 3-10 (same trap as the pine's `needle_size`). SPECIES_CHECK and GENERATION_NATIVE_CHECK run above.
- 2026-11-18 (loop tick 45): shelf fungus on logs, see task 099 tick 45 (unverified after enlarging).
- 2026-11-18 (loop tick 49): FLOWER KINDS NOW SHOW IN A WORLD. `nudge()` (called by `for_species`) runs `vary_flowers()` which re-draws petals (4-10), cup and centre of EVERY flowering genome, so the daisy
  (14 petals), the poppy (4 wide cupped) and the lupine spike marker (petals == 3) set in `make()` were overwritten in every planet and gallery (only the tree lab, which skips the nudge, showed them);
  this is why all flowers looked alike. `for_species` now remembers petals, cup and centre before the nudge and restores them for daisy, poppy, lupine, lavender and bell (wildflower keeps its
  random variety). Gallery pictures (`close/fq_sheet.png`, seeds 3, 8, 21, 33, 40, `--page=4 --form=flower --detailed`): spikes of florets down tall stalks (lupine) in pink, yellow, white and
  violet, flat daisies, wide red poppies, pink cosmos, blue and white blooms: a believable meadow of different plants. SPECIES_CHECK and GENERATION_NATIVE_CHECK PASS.
- 2026-11-18 (loop tick 52): MUSHROOM SIZE. The planet picture (`close/leafcap3.png`) showed orange caps about 0.5-0.6 m wide on 0.2 m stems. `species_generator_native.cpp` mushroom `shape_forms`: stalk height
  0.1-0.3 -> 0.08-0.22 m, cap radius per stalk height 0.9-1.3 -> 0.5-0.85 (so a cap is about as wide as the stalk is tall, 1.0-1.7 x). SPECIES_CHECK and GENERATION_NATIVE_CHECK run after.
- 2026-11-18 (loop tick 54): checkpoint pictures of the current build, ground level (`close/final_sheet.png`: wet broadleaf forest and the conifer / broadleaf forest, seed 8): mushrooms are no longer
  oversized, lupine spikes stand in the grass, the forests read as photos taken under a canopy. Open list: bell flowers, leafy flower stalks, bristlecone, moss mats at a wet spot in a picture,
  the broadleaf quota decision (saves), leaf size taste (see task 099 tick 51).
- 2026-11-18 (loop tick 55): BELLFLOWER. New flower kind `bell` (`tree_archetypes_native.cpp` lists + genome, name noun "Bellflower", weight 1.2 in the flower `archetype_of`, shape kept through the species nudge like
  daisy / poppy / lupine): 8 arching stalks (length 0.65, arch 0.5, droop 0.3), each ending in a nodding cup: `frond()` draws the bloom with the normal DOWN for `petals == 6 && flower_cup > 0.9`.
  Lab picture `kinds/bell2_c.png`: violet bells hanging at different heights from fine arching stalks; the first try (droop 0.55) dropped them to the ground. SPECIES_CHECK and
  GENERATION_NATIVE_CHECK PASS. Flower kinds now: wildflower, daisy, poppy, lavender, lupine, bell.
- 2026-11-18 (loop tick 57): BRISTLECONE looked at again with the bottle-brush pads (`kinds/bris_c.png`): a stubby bottle trunk with a few long palm-like tufts: not a bristlecone (a real one is a twisted,
  weathered trunk with short bottle-brush foxtails along the twigs). It stays OFF (weight 0). Needs a thinner, twisting, mostly dead trunk (`trunk_bend` / `trunk_lumps` / `bare` dead limbs) and many short pads
  along the twigs: left for later, low value.
