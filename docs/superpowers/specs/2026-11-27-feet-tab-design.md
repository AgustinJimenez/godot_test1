# Feet tab: realistic foot size in the body lab (design)

Approved by the user on 2026-11-27 ("yes").

## Why

The user wants a tab about the feet in the body lab, "at least to modify realistically the feet size", with the camera on the feet while the tab is
open.

## Approaches

1. Blend shapes from MakeHuman's foot targets (chosen): `feet/l|r-foot-scale-incr|decr` (size), `-depth-` (length), `-horiz-` (width), made in
   `tools/blender/make_bodies.py` like the proportion shapes (shoulders, waist, ...); the garment builder copies every body shape onto the
   garments, so shoes follow. The bones do not move (foot IK keeps the base foot's length): fine for a few cm.
2. Scaling the foot bones at runtime: rejected (the ankle swells with the foot, animations can overwrite it, shoes stretch like rubber).

## Design

- Shapes `feet_small` / `feet_big`, `feet_short` / `feet_long`, `feet_narrow` / `feet_wide` (both feet's targets together).
- Lab: a "Feet" tab with Size, Length and Width sliders (the proportion sliders' mechanism, `_add_shape_sliders`), and a readout of the foot's
  length (heel to toe tip, measured from the mesh with the shapes applied) in cm and the EU shoe size (Paris points: 1.5 x (length + 1.5 cm) in cm,
  rounded). Slider limits so adult feet stay within ~22-30 cm.
- Camera: opening the tab frames both feet from a little above and in front (like the Beard tab's view); leaving it returns to the full body.
- Saved with the other body values (the character settings).
- Shoes rebuilt so they carry the shapes; the shoe-coverage probe checked at the slider extremes.

## Left to the builder

Slider strengths (the MakeHuman targets at full weight may be extreme), the camera's exact framing, and the readout's place in the tab.
