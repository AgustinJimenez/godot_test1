# Crotch drop and sleeve taper: two builder rules for every garment (design)

Approved by the user on 2026-11-27 ("yes"). A small change to the garment builder (`tools/blender/garments/fit.py`, recipes in
`assets/models/humans/garments/`), see `docs/blender_workflow.md` "Garments".

## Why

The user, looking at the villager: the trousers' groin is "too adjusted" (real trousers are fuller there), and the shirt is "a little bit too big"
at the elbow. Both come from how the builder makes every garment: the body's surface pushed out by a fixed ease. Trousers follow the skin into the
groin 12 mm out (real trousers have a crotch seam that bridges across below the body); a sleeve is the same tube from the shoulder to the wrist (a
real sleeve is cut narrower toward the wrist). The user wants a small change that fixes this for every garment, not per garment.

## Goals

- Every garment covering both thighs (trousers, later breeches, hose, a skirted mail's legs) bridges the groin: between the legs it spans straight
  across from one inner thigh to the other, its lowest line `crotch_drop` below the body's crotch, blended into the normal fit over a few cm.
- Every sleeve (shirt, mail, later coats) tapers: the room over the arm (the limb ease) narrows smoothly from the upper arm to the wrist, to
  `sleeve_taper` of the upper arm's room at the wrist. The cuff (bound or open) keeps its own rule at its end.
- Defaults in the builder, an optional per-recipe value to override (0 drop = skin-tight hose; taper 1 = a straight tube).
- Every outfit rebuilt; the existing checks keep passing; one new check per rule.

## Non-goals

- Flat cutting patterns (the "pattern sheet" debug view of each garment's pieces): discussed, deferred until these two rules are judged.
- Pattern-first garments (pieces sewn round the body): not this change.

## Approaches

1. General builder rules with recipe overrides (chosen: the user asked for a small change that affects every garment).
2. Per-recipe tuning (more ease in the trousers, less in the shirt's limb): rejected, it fixes two garments and not the shape (a bigger tube is
   still a tube, a looser crotch still follows the groin).
3. Pattern-first builder: rejected for now (replaces the builder's core; see Non-goals).

## Design

- Recipe fields (optional, validated in `recipe.py`): `crotch_drop` (metres, >= 0, only for garments covering both thighs) and `sleeve_taper`
  (0..1, only for garments covering the forearm). Builder defaults: crotch drop ~0.035 m, sleeve taper ~0.7 (builder's call; tuned on renders).
- Crotch: in the zone between the thighs below the hips (the body's crotch point from the hips joint, a few cm round it), each garment point's
  target height is raised toward / lowered to a flat bridge: points facing the other leg move toward the middle plane, and the lowest line sits
  `crotch_drop` below the body's crotch; blended out over a few cm toward the thighs, the seat and the front. Applied before the layer pushes, so
  layered garments still stay outside each other.
- Sleeve: the limb ease (and its flare) scaled along the arm by a smooth factor from 1 at the shoulder to `sleeve_taper` at the wrist (on the
  forearm share `part[2]`), before the cuff's bound-opening rule.
- Checks (`garment_check.py`): for a garment covering both thighs, its lowest point between the legs lies at least ~2 cm below the body's crotch;
  for a sleeved garment, the mean room round the forearm near the sleeve's end is less than round the upper arm. Plus the existing layer, opening,
  inward-area and neckline checks for every outfit (`tools/blender/garments/test_build.sh`) and the GPU cloth checks (`scripts/cloth_check.sh`).

## Left to the builder

The exact defaults, the blend widths, how the bridge is shaped (flat or a shallow curve), and whether the drop is measured from the body's
crotch point or the hips joint; judged on before/after renders of the groin and the elbow on both bodies.

## Documentation

`docs/blender_workflow.md` "Garments" gets the two rules and their recipe fields; `AGENTS.md` points anyone working on clothes to that section and
to this design.
