# 041 - Procedural flora species

Status: **implemented, uncommitted, waiting for the user's live look** (2026-10-15). Brainstormed with
the user, then built end to end while they were away (they asked for exactly that: design, build,
test, review at the end). Builds on [040](040_procedural_world.md). Branch: `godot-4.7-upgrade`
(the whole project was moved to Godot 4.7.2 the same day to install the Godot AI MCP plugin; the
plugin and the upgrade are separate from this task).

## Goal

Vegetation that looks like real life: many categories and visible variety, not 19 hand-written kinds
with 2-6 variants each. Instead of hand-coding each plant, the world generates **species** when it is
built: a species is a set of properties (height, trunk, branching, crown, leaves, colours, wind sway,
environment preferences) that decides what its plants look like and where they grow.

## Decisions (user answers, in order)

1. **When are species created?** Each time a world is generated, from the seed (not a fixed
   hand-made library). Later, as the world expands while the player explores, more species may be added
   in the background with some probability (NOT built yet, see "Growth over time").
2. **Scope: all plants** - trees, shrubs, grasses, flowers, ferns, cacti, reeds, mushrooms.
3. **Where a species grows: environment preferences** (moisture, heat, height above water, slope),
   not biome lists. New species need no biome-table edit; forests thin out and change gradually.
4. **Species count: about 36 per world** (a setting, `WorldSettings.species_count`).
5. **Approach: parametric growth forms.** One builder per growth form, driven by the species'
   numbers. Rejected: full L-systems (too heavy and hard to keep low-poly, poor fit for grass and
   flowers). Possible later upgrade for trees only: a light real-branching step.

## What was built (`systems/world_gen/flora/`)

| File | Job |
|---|---|
| `plant_species.gd` | `PlantSpecies`: one species. `Form` (12 growth forms), `Layer` (5 scatter layers), shape numbers, colours, niche (moisture/heat/above-water/slope + density + clump settings), `fitness()`, `footprint()` (trunk collider) |
| `species_generator.gd` | `SpeciesGenerator.generate(seed, count)`: quota per form (36 = 3 conifer, 4 broadleaf, 1 palm, 1 bare tree, 6 shrub, 2 cactus, 4 grass, 2 tall grass, 2 reed, 6 flower, 3 fern, 2 mushroom), species of one form spread over the climate (stratified), shape and colour draws, names ("Snow Fir", "Meadow Birch", a willow is a broadleaf that droops) |
| `species_registry.gd` | `SpeciesRegistry.for_settings(settings)`: the species of a seed (cached, last two seeds), per-layer lists, mesh cache behind a mutex (tile worker thread + main thread both read it) |
| `plant_meshes.gd` | dispatch: species + variant + detailed -> mesh; `build_far` for horizon trees |
| `plant_tree_builders.gd` | conifer, broadleaf (forking trunk, lumps, weeping, birch bark patches, leaf cards in the realistic look), palm, bare tree, far proxies |
| `plant_ground_builders.gd` | shrub (berries/blossom), cactus (columnar with arms or barrel), grass and tall grass (seed heads), reed (cattails), flower (stems in a clump), fern (leaflets when realistic), mushroom |

Changed: `world_scatter.gd` (rewritten around species: `_scatter(layer)`, `_pick()`, per layer grid
spacing, chance = sum of the species' fit x density up to a per-layer cap that equals the old biome
maximum; rocks, logs, spires and the new stumps stay biome-driven), `flora_meshes.gd` (now only rocks,
stumps, logs, spires; enum values kept so rocks keep their shapes), `procedural_world.gd` (detail swap
handles species meshes), `world_settings.gd` (`species_count`), `.gdlintrc` (excludes `godot_ai`, the
third-party plugin, otherwise `scripts/check.sh` lint fails on 1000+ of its lines).

How it behaves: every grid point on a tile scores each species of the layer by `fitness x density`
(x a clump noise for patchy species), the plant is chosen in proportion, and a species that does not
fit the spot is simply not there. Per-instance size spread, yaw, mesh variant (2-3 per species) and a
small tint difference. Colliders only for trunks and cacti. Far tiles use cheap cone/ball proxies.
Frosted (snowy) conifers are the cold-niche species. Autumn, wind, snow and the realistic look work
unchanged (same shader, same vertex-colour conventions).

## Verification (all green on 2026-10-15, Godot 4.7.2)

- `godot --headless --path . res://tests/manual/world/species_check.tscn` -> `SPECIES_CHECK PASS`:
  36 species, unique names, every form and layer present, deterministic per seed, different seeds
  differ, ordinary land is covered by trees and grasses (45/45 spots), 174 meshes in 450 ms, none over
  12000 triangles (largest 5120, detailed broadleaf).
- `godot --headless --path . res://tests/manual/world/world_lab.tscn -- --world-check --flora` ->
  `WORLD_CHECK PASS` and `FLORA_CHECK PASS species=36 of 36 layers=5/5` (the check is part of
  `--world-check` now).
- Lint: `gdlint .` clean (gdtoolkit 4.5.0).
- Look: `tests/manual/world/species_gallery.tscn` (keys: 1-4 pages, R new seed, D realistic, A autumn)
  and the live `levels/procedural_world.tscn` in low-poly and realistic, several seeds, F4 re-roll.
- Performance versus the old flora, same lab walk (`-- --perf`, headless, three runs each):
  frame avg 8.7 -> 8.8 ms, p99 9.0 -> 10.0 ms, worst frame 206 -> 235 ms, world build 2.75 -> 3.0 s.
  Cause: 21 percent more plant instances (20.2k vs 16.6k in 325 tiles) and 12 percent more batches,
  101 distinct meshes instead of 59. Cheaper species scoring changed nothing (scoring is not the cost).

## Not done / next

- **Growth over time** (user's later idea): species appearing as the world expands. Keep it
  deterministic ("same seed = same world" must not depend on exploration order): derive extra species
  per region from (seed, region) and let a tile use the base list plus the species of the regions
  around it. Ids stay stable, the registry only ever appends. Not built (YAGNI until asked).
- Tune after the user's look: grass is the bulk of the instances (the two broad grasses are ~10k of
  20k); species names pick generic adjectives ("Meadow Fern"); conifers are all the same cone-stack
  silhouette apart from size and tier count; no real branching yet; flowers are flat petal discs.
- Per-species size spread, colour jitter and the density caps are the knobs to turn first.
- Ideas: more growth forms (vines, bamboo, agave, tree ferns), seasonal flowering per species,
  species-specific wind sway, the World menu page could list the seed's species.
- The Godot editor does not pick up new `class_name` scripts until a headless `--import` has rewritten
  `.godot/global_script_class_cache.cfg` (a `filesystem_manage scan` did not). Run it once after adding
  a new global class, then the next play works.

## Even forks and tiers (2026-10-15)

The user saw trees "divided" with uneven divisions. Broadleaf crowns had forks at random angles and
lengths and lumps scattered at random, so the canopy broke into detached blobs. Now
`PlantTreeBuilders.broadleaf` places the forks at equal angles (phase random per mesh, +-0.1 rad)
with equal reach, one lump of leaves at each fork tip, one on the axis and the rest on a ring
between the forks; a single fork is dropped (it only looked like a crooked branch). Conifer tier
radius jitter went from +-10% to +-3% so the tiers shrink evenly. Looked at in the species gallery
(low-poly and realistic, two seeds). If the user meant something else by "divided" (e.g. the
trunk pieces of palms), ask which species.

### The "divided" trees were the trunks (same day, found from a user screenshot)

The user still saw divided trees after the crown change: the trunk of a broadleaf tree was three
separate stacked cones, each straight and each with its own random rim wobble and its own dark to
light colour ramp. On a leaning tree the pieces were shifted sideways by `tilt * t^2` per piece, so
they did not meet (visible steps), and the colour banded at every joint. Palm trunks (5 stacked
pieces) had the same fault. Now `PlantTreeBuilders._tube` builds one continuous tube through shared
rings (`_trunk` 5 rings, palm 9 rings with a slight bulge on every other ring for the ringed look);
`_trunk_centre` is the single formula for the lean, also used by the birch bark marks (which now
follow the taper too). Lesson: the gallery framed whole trees from far away and hid this. The
gallery now has a close-up mode: C toggles it (eye level, close to one species), Left / Right pick
the species.

### Plant lab and the cactus arms (same day)

User screenshot of a cactus: the arms were plain cylinders crossing the trunk and floating cylinders
beside it. The arm's rotation had the wrong sign (`Basis(BACK, side * PI/2)` points a piece along
+Y into -side), so each horizontal piece went INTO the trunk while its upward piece stood at the
correct outer end, detached. Now the arm is placed with `Basis.looking_at(dir) * Basis(RIGHT, -PI/2)`
(the same way the broadleaf forks are), arms leave in opposite directions (the third at a right
angle) at different heights, and each upward piece starts where its horizontal piece ends.

New lab `tests/manual/world/plant_lab.tscn` (the user asked for "a lab where we can generate
randomly and see the results"): one growth form at a time, a row per species, a column per random
individual. F / Shift+F form, G new random species (new seed), V new random individuals, D realistic,
A autumn, C close-up of one row (Left / Right individual, Up / Down species). Command line:
`--form=CACTUS --seed=N --detailed`. Individuals are `PlantMeshes.build(species, random_variant,
detailed)`. Use it after any change to a plant builder: look at several G / V rerolls in both looks,
and in close-up, not only at the gallery's overview.

### Mushroom clumps clipping (same day)

A clump of 2-4 mushrooms put each one at a random spot within +-20 cm, while a cap is as wide as its
stalk is tall times `crown` (up to 1.3), so neighbouring caps cut into each other.
`PlantGroundBuilders.mushroom_layout` now places every next mushroom beside an earlier one at least
the two cap radii plus 3 cm away, retrying 24 times (no free spot: that mushroom is left out).
`species_check` tests it: 900 random clumps over three seeds, the least room between two caps is
3.7 cm. The plant lab's close-up now frames the plant by its size (a mushroom was a speck).

## Branches and single leaves instead of the leaf-ball crown (2026-10-15, step 1, NOT committed)

The user asked for tree crowns made of branches and actual leaves with unique shapes, built one kind
at a time. Design agreed in chat: limbs -> branches -> twigs (tubes, `PlantTreeBuilders.tube`),
single leaves on the twigs in the species' pattern, a leaf outline per species, both looks
(low-poly: fewer bigger flat leaves; realistic: more, smaller, curled), near trees keep the full
crown out to the distance where the far stand-ins start, measure the cost.

Built so far (only OVAL leaves, i.e. beech and elm; every other species still has the old crown
until its leaf shape is done: `PlantCrownBuilders.supports()` is the switch):
- `plant_species.gd`: `LeafShape` (OVAL, LOBED, PALMATE, HEART, LANCEOLATE, DIAMOND), `LeafPattern`,
  `leaf_shape/pattern/aspect/size/lobes`, `limb_count`, `limb_angle`.
- `species_generator.gd` `_leaves()`: leaf traits from the NOUN of the name (oak lobed, maple
  palmate, beech and elm oval, ash narrow, linden heart, poplar and birch diamond, willow very
  narrow), on their own dice (`seed ^ 0x1EAF`) so nothing else of the species or the world changes.
- `plant_leaf_shapes.gd`: leaf outline in leaf space and `add_leaf` (a fan of triangles around a
  centre lifted along the normal = folded midrib; tip curl in the realistic look).
- `plant_crown_builders.gd`: the branching (golden-angle limbs, 4 branches per limb, 4 twigs per
  branch, 5 / 8 leaves per twig low-poly / realistic, alternate / opposite / spiral).
- Lab: `plant_lab` C cycles the view (all / trunk / crown); labels now say the leaf shape and limbs.
  X toggles a free camera: W A S D fly (Q down, E up, Shift fast, wheel = speed) and holding the
  right mouse button looks around; in free mode A and D fly the camera, so L (realistic) and U
  (autumn) do what D and A do; R puts the camera back on the framed view.
- `world_render_stats.tscn`: real-window render cost (triangles, draw calls, CPU frame, FPS); run it
  with `-- --realistic` for the realistic look (the headless `--perf` cannot see triangles).

Measured, seed 1337, standing in a forest and turning once (baseline = old crowns everywhere):
low-poly 1.08M triangles/frame (worst 1.58M) -> 1.32M (worst 2.02M), CPU frame 5.76 -> 6.34 ms;
realistic 3.35M (worst 5.31M) -> 3.69M (worst 5.93M), 5.60 -> 6.24 ms; draw calls unchanged; 120 FPS
in both. That is with only the two oval-leaf species converted; expect about twice the increase when
all broadleaf species have it. Largest tree mesh: 6160 triangles (budget 12000).
Next kinds, one at a time: lobed (oak), palmate (maple), heart (linden), diamond (birch, poplar),
narrow (ash; willow with hanging branches).

### Branch joints (user screenshot, same day)

"Branches not well connected": two faults in my first crown. (1) `PlantTreeBuilders.tube` drew its
rings flat on the horizontal plane, which is right for an upright trunk and turns a sideways branch
into a flat ribbon; the rings now stand at right angles to the path (a frame carried along it
without twisting). (2) The tubes were open at both ends and a branch started on its parent's axis
with the trunk top uncapped: tips and the trunk top are now capped (`caps` argument), a child
starts a little inside its parent (parent radius there * 1.1) and the limbs start well inside the
trunk top. Checked in the plant lab crown view and with the free camera at the joints.

### Wind sync and the chain look (user report, same day)

Two faults in the crown. (1) Wind: every ring of a branch carried one fixed sway weight (alpha) per
depth, so a twig, which sways more, started away from the point of its branch it grows from (that
point sways less): the joints moved apart. The weight is now continuous: it starts at 0 at the top of
the trunk, grows along each tube (`SWAY_GAIN`), a child starts with the value its parent has at that
spot, a leaf's stalk has the twig's value and its tip adds `LEAF_SWAY_GAIN`. (2) A child had half its
parent's BASE radius, as thick as the parent's end, and left at a shallow angle, so thick pieces ran
on in a row and overlapped like a chain: children now have `CHILD_RADIUS` (0.6) of the parent's radius
where they leave and a wider angle (tangent 0.4, outward 0.9, up 0.25). The plant lab got T (calm,
breeze, gale) to look at the sway.

### Cylinders poking out of the parent, blunt twig tips (user report, same day)

(1) A child started `1.1 x` the parent's radius behind the parent's centre line, i.e. past the far
side of the parent, so its first ring and the cylinder after it came out of the back of the parent.
It now starts `BURY` (0.4) of the parent's radius behind the attach point, which keeps the whole
ring inside the parent (the limbs likewise start 0.5 limb radii inside the trunk top). (2) Every
tube ended at half its radius with a flat cap, so twigs ended as short cylinders: tubes now end at
`TIP_RADIUS` (limb 0.4, branch 0.25, twig 0.05 of its start radius), twigs end in a point, and the
child radius follows the tapered parent. The plant lab got a fourth view, C: branches (close-up of
the trunk top where the limbs leave and split).

### Curved branches (user remark, same day)

Branches were a few straight segments with random kinks (stiff, and the thin ends that move most in
wind were the most rigid). Each branch is now one smooth arc: `CURVE` (limb 0.5, branch 0.8, twig 1.2
rad at most, random 35-100% of it, to either side, in a random plane through the branch), more rings
(`RINGS` 6 / 5 / 3), a little `WANDER`, `LIFT` for the limbs reaching up and `SAG` so thin twigs droop
under their leaves. Cost: largest tree mesh 6638 -> 7982 triangles (budget 12000); render stats,
seed 1337: low-poly 1.42M triangles/frame (old crowns 1.08M), realistic 3.83M (3.35M), CPU frame
6.3 ms in both, 120 FPS, with only beech and elm converted.

### Plant lab: one plant at a time, the mouse turns around it (user request, same day)

`plant_lab.tscn` now opens on ONE plant. Left / Right step through every plant of every row (the
next individual, 6 per species), Up / Down the species; the mouse (captured) turns the camera around
the plant at a constant distance, the wheel zooms, M (or Esc) gives the mouse back (then hold the
left button to turn). C cycles the view: individual, trunk, crown, branches (all orbit the plant,
each with its own target height, distance and pitch scaled by the plant's size) and overview (all
the plants of the form, as before). R puts the angle and zoom back; X is still the free camera (W A S D
fly, right mouse looks); L / U / T as before. Only the focused plant is shown in the orbit views.
The orbit was tested by injecting mouse-motion and wheel events (the camera stays at the same distance
from the plant while it goes round; the wheel zooms).

### Flat trunk top, planks for branches (user screenshot, same day)

The trunk ended in a flat cut (a disc) with the limbs coming out of it, and the tubes had so few
sides (limbs 6, trunk 7) that they read as planks. Now the top of the trunk narrows into a rounded
dome (two more rings: 0.8 and 0.3 of the top radius, capped) and the limbs start well down inside
that dome (2 limb radii below the top, 0.7 of the trunk-top radius thick instead of 0.55); the trunk
has 9 sides, limbs 8, branches 6, twigs 4 (the realistic look doubles them). The lab's branches view
now looks from just under the join.

### Branches that ended bare (user report, same day)

Children were placed along 30-85% of a parent, so the last stretch of every limb and branch was a
bare tapered cone. In a real tree a branch never ends bare: it keeps dividing, and only the last
twigs end, each in a leaf or bud. The last child (the "leader") now starts at the very tip and grows
straight on (direction mostly the tangent, half the parent's length), the other three spread along
30-85% as before; so limbs and branches end in twigs, and twigs end in a pointed tip with a leaf.

### Lab key H: leaves hidden (user request, same day)

`MeshBuilder.leafless` (a debug look): `PlantMeshes.build(species, variant, detailed, leafless)` builds
a tree without its leaves (the new crown skips its leaves, the old crown skips its lumps and leaf
cards); the branches are identical to the leafy mesh. The plant lab's H toggles it. Nothing in the
game sets it.

### Round trunks (user remark, same day)

Trunks were 6-9 sided prisms (12-18 in the realistic look) and low-poly shading shows every side.
Sides now: broadleaf trunk 14, conifer trunk 12, palm trunk 10 (dead tree 16), crown limbs 11,
branches 8, twigs 5 low-poly (12 / 10 / 6 realistic: the crown chooses its own, `tube(...,
refine=false)`); the radial wobble of the conifer and dead trunks went from 0.07-0.12 to 0.03 / 0.04,
so a trunk is round and not lumpy. `add_frustum` and `tube` stop doubling the sides for the
realistic look at 12 or more (already round). Cost, seed 1337: low-poly 1.54M triangles/frame, CPU 5.3
ms; realistic 3.91M, CPU 5.9 ms (before the sides rise: 1.42M / 3.83M, 6.3 ms); largest tree mesh
8678 triangles (budget 12000).

### Steps where a branch carries on (user screenshot, same day)

Where a limb or branch ends and the next one carries on (the "leader" child at its tip), the parent
was closed with a cap at 0.4 / 0.25 of its radius and the leader started at 0.6 x that, buried 0.4
radii back: a visible ring and a step in diameter. The leader now starts exactly at the parent's tip
with the parent's tip radius (no burying), uses the parent's number of sides (`sides_depth`), and the
parent is not capped when something continues it (only twigs are capped); the leader's kink is
smaller (direction 0.95 tangent). `_branch(..., continues)`. Checked in the lab (H, branches view).

### Which trees have the new crown (user could not find it, same day)

Only species whose leaf shape is OVAL: Beech and Elm (`PlantCrownBuilders.supports()`); Linden,
Birch, Oak, Maple, Ash, Poplar, Willow keep the old ball crown until their leaf shape is done. In the
lab at seed 1337 plant 1 is a Linden (old crown), the Beech is plant 7, the Elm plant 13. The lab now
opens on the first new-crown tree of the form and the label says "(new crown)" or "(old crown)". A
procedural world only has the species its seed drew, so a world may have no beech or elm at all.

## Every leafy species has the branch crown, one leaf kind at a time (same day, NOT committed)

Built and looked at in the plant lab (new key K: sets what kind of tree the leafy species are, so a
shape can be seen without a seed that draws it), in this order: lobed (oak: notch, lobe, notch...
three lobes a side), palmate (maple: five lobes fanning from a point, leaf size 0.17 and shallow
notches because the first try buried the branches), heart (linden), diamond (birch, poplar), narrow
(ash, willow). `PlantCrownBuilders.IMPLEMENTED` lists the kinds that get the crown: now all six, so
every broadleaf species has branches and single leaves; the old ball crown code is still in
`PlantTreeBuilders.broadleaf` below `supports()` (unused now: delete it when the user is happy).
Willow: its branches hang (`DROOP_SAG` x the species' droop; `apply_leaf_traits` gives a willow
droop >= 0.7).

Per-leaf variation: every leaf has its own asymmetry (one side up to 18% wider) and its tip bent
sideways (up to 12% of its length, more on narrow leaves) next to the length (80-120%) and colour
spread it already had. Species edge (`leaf_edge`): serrated (elm, birch, poplar, linden) and wavy
(beech, willow); drawn only in the realistic look (every other outline point pulled in 20% / 8%),
the low-poly look keeps clean edges.

Cost (lesson): the first version with teeth doubled the leaf points and the realistic meshes reached
13-20k triangles (SPECIES_CHECK limit 12000). Now: teeth add 2 points a side instead of the extra
roundness, diamond leaves use the same few points as oval, 5 leaves per twig (4 low-poly). Largest
tree mesh 11982 triangles. Render stats, seed 1337, forest, all broadleaf converted: low-poly 2.09M
triangles/frame (old crowns 1.08M), realistic 4.74M (3.35M); CPU frame 6.3 ms, 120 FPS, draw calls
unchanged. The realistic look is the one near the limit: if more is added, take leaves off first.
Not done: sun and shade leaves, leaves that differ by position, veins, a lab view of one leaf alone.

## Conifers: whorled branches and needle sprays (same day, NOT committed, first pass)

The user pointed out that only the leafy trees had the new crown. `plant_conifer_builders.gd`
(`PlantConiferBuilders.build`, used by `PlantMeshes` for `Form.CONIFER`; the old stacked-cone builder
`PlantTreeBuilders.conifer` is unused now, `far()` still draws the horizon version): a straight trunk
narrowing to a leader, whorls of 5-6 branches every 0.5-0.9 m (turned against the whorl below),
drooping by the species' `droop` with their tips lifting, 2 branchlets each, and sprays of single
needles (fan of thin triangles, 9 low-poly / 11 realistic) at every branch and branchlet tip and half
way along a branch, plus four at the leader. Same rules as the leafy crown: tubes start inside their
parent, taper under a spray, wind weight grows continuously from the trunk to the needle tips;
frosted species get white needle tips. Largest tree mesh 11982 triangles (first try with 1.4 m whorl
spacing was bare, with 13 needles and 3 branchlets realistic it was 13.7k). Looked at in the lab
(Snow Fir) low-poly only. Not measured yet: render cost with conifers converted. Next: palm (a ring of
pinnate fronds: a curved rachis with leaflets), shrub (stems from the ground with the leafy-crown
builder at small scale).

Open design question from the user (answered in chat): broadleaf and conifer need not be separate
forms; one tree builder driven by traits (leader strength, branch arrangement whorled / spiral,
droop, leaf kind blade / needle / frond) would also give mixed species. Not done.
