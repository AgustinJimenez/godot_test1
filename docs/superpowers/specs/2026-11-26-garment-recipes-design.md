# Garment recipes: every garment from one builder

Date: 2026-11-26. Task: `AGENT_TASKS/103_cloth_simulation.md` (section "Next: every garment"). Status: design, not built.

## Intent

The villager shirt and trousers work: they are built from the body, simulated with the vendored GPU cloth add-on, and a long round of fixes
(clipping at the waist and calves, the neckline, the shirt's inside, folds, lopsided capsules, normals) made them look right. Most of those fixes
are written for "shirt" and "pants" by name. The user: *"those are basic shirt and pants, we can't have the same amount of work on every type of
cloth, it must work on every cloth."* Later they want leather and steel armour too.

The goal is that a new garment is a short description, not new code and not a new round of fixes: describe it, build it, and it hangs, layers and
collides correctly in both labs.

## Decisions (user)

- Garments stay **built from the body**, as the shirt and trousers are ("the same way you did both shirt and pants"). How far that reaches is
  open; **Blender is the fallback** for shapes the builder cannot make.
- Approach: **garment recipes and one general builder** (chosen over per-garment code with shared helpers, and over adding a Blender import now).
- The fit-to-body stage stays separate so a hand-modelled mesh can enter there later without rework.

## Goals

1. A garment is a **recipe** (data). Adding one needs no edit to the builder, the shader or the labs.
2. One **builder** makes any recipe, for both bodies, with the body's blend shapes carried over (as now).
3. **Layering**: an outfit is built from the inside out; each garment is kept outside every garment under it where they overlap (generalising
   "the shirt stays 12 mm outside the trousers"), and its freedom is capped where it lies over another layer (generalising the shirt-over-trousers
   freedom cap).
4. **Derived, not hand-painted**: the freedom map (vertex colour B), the hem band (G), the belt mask (R) and the inside mask (A) come from the
   recipe, its material and the body's regions; the solver settings and the collision setup come from the recipe too.
5. **Materials**: cloth (linen, wool) simulated as now; leather simulated but stiff and held close; steel plates rigid, on the bones, not
   simulated. The material sets the defaults (freedom, stiffness, ease, render look), a recipe may override them.
6. The labs load **any list of garments** (an outfit), not exactly a shirt and trousers.
7. The shirt and trousers become the first two recipes and come out **as good as today**: the current visual checks and probes still pass
   (waist overlap 0, calves 0 inside, no folds under the hem, neckline as now, `humans_check.sh --render` green apart from the known elbow motion
   checks, which must not get worse).

## Non-goals (for now)

- A Blender import of hand-made meshes (kept possible, not built).
- Pockets, collars that stand, ruffles, buttons, seams as geometry.
- Self-collision of one garment, a cloth LOD for crowds (task 103 already lists LOD separately).
- An in-game wardrobe or UI; the body lab's Clothes dropdown lists outfits.

## Anti-goals

- Per-garment special cases in the builder ("if garment == 'shirt'"). The rules that exist for the shirt and trousers today must become general
  rules or recipe fields.
- A recipe so detailed that writing one is as much work as the code it replaces.
- Losing what the current garments already do right.

## Constraints and facts the design rests on

- **Offset shells cannot bridge the legs.** `make_clothes.py` offsets the body's own surface; a shell cannot hang across the gap between the legs
  (note at `SHIRT_HEM_BELOW_HIPS`). Skirts, dresses, robes and long coats below the hips need a second shape kind.
- The body's regions come from the rigged body's skin weights (`bone_labels`, `part_of`: arm / leg / torso with a position along the limb).
- Coordinates in the builder are Blender's (Z up, front is -Y); joints come from `<gender>_rig.json`.
- The solver reads one vertex-colour channel as freedom; our shader reads the others (R belt, G hem, A draw the inside). Four channels in all.
- The collision that works: small torso capsules (pelvis and upper-spine capsules shrunk: they are lopsided), full-size shin capsules, exact
  arm-surface contact for sleeves (native `HumanRig.prepare_cloth_arms`), a 4 mm render offset (1 mm for sleeves with exact contact), garments as
  each other's peers. Exact contact costs ~1.5-2 ms a character a body region; capsules ~0.5 ms.
- Rebuilding garments is offline (Blender, background); the labs bake body-slider shapes at run time (`_baked_mesh`).

## The recipe

A recipe is a small data file per garment (proposal: JSON under `assets/models/humans/garments/`, one per garment, gender-neutral; the builder
writes `<gender>_<garment>.glb`). Fields, with what today's shirt and trousers would put in them:

| Field | Meaning | Shirt | Trousers |
|---|---|---|---|
| `layer` | 0 = against the skin, higher = over | 1 | 0 |
| `shape` | `shell` (offset from the body) or `drape` (lofted round the body, crosses the legs' gap) | shell | shell |
| `covers` | body regions: torso, upper_arm, forearm, thigh, shin (and later hand, foot, head) | torso, upper_arm, forearm | torso (below the waist), thigh, shin |
| `top` | where it starts: `neck` (with a neckline), or a height (waist) | neck | waist, 3.5 cm above the hips |
| `neckline` | round ease, V depth and width (if `top` is neck) | round 1 cm, V 8.5 cm deep, 7 cm wide | - |
| `bottom` | where the torso part ends (a height from the hips) | at the hips | - |
| `sleeve_end`, `leg_end` | share of the forearm / shin covered | 0.9 | 0.9 |
| `ease` | how far it stands off what is under it (skin or the layer below), and how it grows toward the hems | 16 mm, +12 mm to the hem; sleeves 19 mm | 12 mm, +10 mm to the cuffs |
| `openings` | per opening: `open` or `bound` (closes in to the skin) | neck bound, sleeves open, hem open | waist bound, cuffs bound |
| `material` | linen, wool, leather, steel (defaults below) | linen | wool |
| `belt` | a belt at the top (a band the shader draws) | - | yes |
| overrides | optional: freedom per region, stiffness | - | - |

Everything else in `make_clothes.py` today (hip placement direction, the round neckline cut, the unfold pass, the rolled rim, the sleeve
refinement, the smoothing and its floors, the armpit inside mask) becomes a general rule the builder applies to any recipe.

## Materials

| Material | Simulated | Freedom | Other |
|---|---|---|---|
| linen | yes | hangs free from where the body stops supporting it (shoulders glued, sleeves free past the upper arm, the torso freer toward the hem) | today's shirt |
| wool | yes | a little less | today's trousers |
| leather | yes | low everywhere, stiffer bending | thicker rim |
| steel | no | - | rigid pieces, each on one bone, kept outside the layers below; no solver |

The freedom rules today (glued at the shoulders and the neck band, freer down a hanging sleeve, freer toward a hem, a bound opening glued, capped
where it lies over another layer, lower legs held close enough not to swing into the calves) become one function of: the region, how far along it,
whether it hangs, the opening type, and the material.

## The builder (fit to body)

1. **Cut** the body's surface to the recipe's coverage (regions, top, bottom, ends, neckline), with clean edges (split exactly on the cut, as the
   round neckline does now).
2. **Shape**: `shell` offsets from the body; `drape` lofts round the body from the hips down (a cone / tube that crosses the legs' gap), joined to
   the shell above it.
3. **Place over the layers below**: built from the inside out; where a garment covers a lower layer it is kept outside that finished layer by its
   ease (the spread push used for the shirt now), and placed out from the body's middle where the skin's normals face each other (the hip rule).
4. **Smooth, unfold, refine** (sleeve-style refinement wherever exact contact is used), **rim** every opening.
5. **Masks**: freedom (B), hem band (G), belt (R), inside (A: everywhere but where two of its own pieces overlap, the armpits).
6. Write the glb with the body's blend shapes, as now.

## In the labs (run time)

- An **outfit** is a list of recipes. The body lab and the rig lab load any outfit (the Clothes dropdown lists outfits; "Villager" = shirt +
  trousers, "Underwear" as now).
- One solver per simulated garment, all garments each other's peers; steel pieces are attached rigidly (`HumanRig.attach_rigid`-style), no solver.
- Collision per garment from its coverage: exact surface contact for the regions it hangs loose over and swings against (sleeves over the arms
  today), capsules elsewhere (small on the torso, full on the shins, the lopsided pelvis and upper-spine capsules shrunk); render offset from that
  choice.
- The body-slider baking and restart, the debug probes (`--cloth-overlap`, `--cloth-legs`, `--wiggle`) work for any outfit.

## Collision budget (user, after the builder check: option C)

Exact surface contact (the sleeves' arm contact, ~1.5-2 ms a character per body region) only for **characters close to the camera**; farther
characters use capsules with stiffer cloth (freedom capped where a garment would otherwise swing into the body). Close characters may get exact
contact on any region a garment hangs loose over and swings against (arms, legs under a dress or long coat, torso under a jerkin): the native
contact preparer (`HumanRig.prepare_cloth_arms`, arm bones hard-coded today) is generalised to any set of bones. This ties in with the distance
LOD already on task 103's list: near = exact contact, middle = capsules, far = static skinned clothes. **Fix first (user):** the exact contact is
made reliable before it is extended: task 104's proposed stage (find which step of the solver lets the elbow particles end inside the arm in the
walk, give the final contact one owner, gate on the walking vertex / edge / face checks for both bodies) is done first, and only then is the
preparer generalised to the legs and torso. Garments that need only capsules (the shirt, the trousers, vests, leather) do not wait on it; drapes
(dresses, long coats) get exact contact once it is fixed. The near / middle / far distances are left to the builder
(measured: a whole frame within budget with a crowd in the body lab's `--crowd` mode).

## Calls made in the write-up (the author's, after the builder check; the user may change them)

- **The unit of building is the outfit.** Layering depends on what is under a garment, so an outfit file lists its garments and the builder builds
  them inside out, writing `<gender>_<outfit>_<garment>.glb`. A garment worn in two outfits is built twice (cheap: offline, about a minute).
- **"As good as today" means the same probe results, not identical files.** The general rules may simplify today's tuned constants. The bar for
  the shirt and trousers: waist overlap 0 (`--cloth-overlap`), calves 0 inside (`--cloth-legs`), no inward-facing folds under the hem beyond the
  rolled lip, the neckline and the inside as now, `humans_check.sh --render` green apart from the elbow motion checks. Those swing with unrelated
  changes (male frame 90 faces went 4, 8, 14, 7 across this task), so the bar for them is "within the range seen in task 103": male f90 at most
  14 faces inside, male f150 at most 8 vertices / 10 faces, female f90 and f150 passing.
- **Steel is a later stage.** The first build covers cloth (linen, wool) and leather. Steel pieces (rigid, one bone each, split at the joints so a
  pauldron does not shear across the shoulder) come after, and the cloth under a plate gets its freedom capped rather than a new collider type.
- **New garments get the same proof as the shirt and trousers**: the overlap probe between any two layers, the legs probe for anything covering
  the legs, the walk and the wiggle, both bodies, the slider extremes. The probes become general (any pair of layers, any covered region).

## Approaches considered

1. **Recipes and one general builder** (chosen): new garments are data; general rules replace per-garment code. More work now, little per garment
   later.
2. Shared helpers with one function per garment: less work now, but every garment is still code, the thing the user wants to avoid.
3. Recipes plus a Blender import from the start: any shape, but rougher automatic fitting and more work before anything new is wearable. Kept
   possible by the separate fit stage.

## Left to the builder

- The recipe file format and where it lives; how the builder is split into files.
- The `drape` loft's exact construction, as long as it crosses the legs' gap, starts where the shell above it ends and follows the body's slider
  shapes.
- The freedom function's exact curves, as long as the shirt and trousers come out as they are now.
- Which first new garments prove it (proposal: a long tunic or dress (drape), a vest over the shirt (a third layer), leather bracers or a jerkin
  (leather), one steel piece such as a pauldron (rigid)).
