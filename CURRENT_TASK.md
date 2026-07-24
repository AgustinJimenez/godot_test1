# Current Task: Modular outfit composition - reset to plain baseline

**Date:** 2026-07-23
**Branch:** `main`
**Status:** In progress, uncommitted. Reset back to a clean baseline after the clearance-adjustment
pipeline (`tools/outfit_pipeline/fit_outfit_to_body.py`) produced a run of confusing, hard-to-verify
results. The tool itself is left on disk but is not currently used anywhere - both
`ui/character_creator.gd` and `tests/manual/outfits/outfit_coverage_comparison.gd` now point directly
at the original, unmodified pack files.

## Current baseline

`ui/character_creator.tscn` renders:

1. the complete selected Universal Base Character body, without vertex or fragment masking;
2. the selected Quaternius outfit's original, unmodified clothing surfaces layered over that body;
3. no outfit-authored duplicate skin surfaces (`Regular_Male`/`Regular_Female` outfit primitives are
   discarded with `shaders/discard_surface.gdshader`, leaving the base body as the only skin source).

Diagnostic colors remain enabled by default: complete base body red, clothing blue.
`P` switches between face and full-body framing; left-drag orbits and the mouse wheel zooms.

No clearance adjustment is applied. Body and clothing meshes will overlap/clip wherever the pack's
own geometry doesn't already clear the base body - that's expected right now, not a bug to chase.

## Asset structure

The male Peasant glTF includes:

- a complete humanoid skeleton;
- `Male_Peasant_Arms`, with clothing and a separate `MI_Regular_Male` skin primitive;
- `Male_Peasant_Body`, clothing only;
- `Male_Peasant_Legs`, clothing only;
- `Male_Peasant_Feet`, clothing only;
- no head/face/neck mesh.

## Comparison harness

`tests/manual/outfits/outfit_coverage_comparison.tscn` shows three columns side by side:

1. full red base body;
2. blue clothes only;
3. full red body plus blue clothes.

Left-drag orbits all three around a shared target and the mouse wheel zooms. `OUTFIT_SCENE` at the
top of `outfit_coverage_comparison.gd` currently points at the plain, unmodified
`Male_Peasant.gltf`.

Yaw angles near 90/270 with this harness's column layout put all three columns on nearly the same
camera ray and make them occlude each other - use other angles to keep them visually separated.

Use the clothes-only column to tell an authored opening (skin visible because the garment simply has
no geometry there - e.g. an open collar, a ragged sleeve/boot edge) from an actual clearance problem
(skin visible through a region the clothes-only column shows as fully covered).

## Removed approach (do not restore without a materially different model)

An earlier automatic body-coverage mask system (UV-space proximity/ray mask baking, per-body/per-outfit
PNG visibility masks, a runtime body-mask shader, Head/Neck ownership exceptions, runtime UV
erosion/dilation) was removed at the user's request: broad masks hid the body but erased visible skin
near open collars, narrow masks preserved junctions but exposed body through clothing, dilation
suppressed pinholes by eating more junction skin, and results were inconsistent between viewing angles.

## Set-aside approach: per-vertex clearance push

`tools/outfit_pipeline/fit_outfit_to_body.py` pushes clothing-material vertices outward from the body
until they clear it by a configurable margin, with a Laplacian smoothing pass to keep the result
visually coherent. It works for some cases but produced enough confusing, hard-to-verify results
(see git history / prior session transcripts for the detailed attempts if picking this back up) that
we're setting it aside for now rather than continuing to patch it blind. Not deleted - just not wired
into anything currently. Revisit once the plain baseline above is well understood.

## Next work

1. With the plain baseline above, visually catalog where body/clothing actually overlap or clip,
   per body/outfit combination, using the comparison harness and the clothes-only-column method
   described above to separate authored openings from real overlap.
2. Decide, from that clean picture, whether the per-vertex clearance push is worth revisiting, and if
   so, verify each change against a fresh render at good zoom before calling it fixed - not from
   memory or a lower-resolution glance.
3. This whole outfit system is still debug-only: no `PlayerProfile` field, no
   `player_body_cosmetics.gd` wiring, `ui/character_creator.gd`'s Outfit dropdown is explicitly
   marked temporary.

## Verification

Run:

```sh
scripts/check.sh
git diff --check
```

No commit has been requested.
