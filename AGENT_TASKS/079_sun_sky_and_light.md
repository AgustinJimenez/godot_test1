# 079 - Sun, sky and light (what the desert photo needs, and the planet as a whole)

Status (2026-10-21): **planned.** Written after the user's reference photo for the desert (task 078): a low golden sun, a
teal-to-warm sky, shadowed slip faces that stay warm, long dune shadows, hazy far dunes. The engine's own sky and one
directional light do none of this by themselves. Work and judge in `tests/manual/planet/planet_lab.tscn` (`--bare --weather=clear
--hour=17.5 --seed=1 --dir=-0.7687,0.6392,-0.0225`, a desert) and compare with the photo
(`E:\Temp\claude\E--repo-godot-projects-godot-test1\f4ab9921-f9a8-49c4-9eea-ca7a459a2434\images\26.png`).

Check first what `planet_atmosphere.gd` and the cloud code already do (the star's colour from its mass, the sun disc, cloud
shadows, volumetric fog): several of these may be half there.

## Steps, in this order

1. **Warm light in the shadows (quick). DONE 2026-10-21** (`shade_bounce` 0.55 in `planet_ground.gdshader`: `col * paint * shaded * sun height` as emission; the slip faces of the dunes are warm, not blue; no extra pass). Shadowed ground is lit by the bright ground round it: add a bounce term from the
   ground's own colour (sand: warm) to the ambient on ground facing away from the sun, scaled by the sun's height (none at
   night). Today the slip faces are cold blue. Measure: one more term in the ground shader; no extra pass.
2. **Sky and sun colour from physics.** Rayleigh and Mie scattering from the star's colour and the sun's height: blue at noon, gold
   and orange near the horizon, the warm glow along the horizon; the sun a little flatter and redder when low (refraction).
   Follows the star mass setting and the atmosphere thickness of the planet. Replaces the grey-blue sky of the desert render.
3. **Far shadows from the terrain.** At a low sun the long dune and mountain shadows make the picture, and the shadow map only
   reaches a few hundred metres. March the planet's height field toward the sun (a few steps, coarse far away) in the ground
   shader and the haze, so far slopes facing away from the sun are dark. Budget: a few ALU per pixel, measured.
4. **Distance haze (aerial perspective).** Far dunes and mountains fade into a warm haze with distance and sun direction.
5. **Light shafts and the sun's glow** near the horizon (the sun disc, a halo, shafts through dust; volumetric fog exists).
6. **Cloud lighting:** bright edges and golden undersides at sunset, matched shadows.
7. **Night and sky:** moonlight by phase, a real star field, twilight, the planet's own shadow at dusk.
8. **Eclipses:** the moon shadowing the ground (the orbit geometry is real already).

## Rules

Each step: lab picture next to the photo, the frame cost measured (before and after, planet look-down render), `planet_check
--quick` passes, commit and push. A step that changes the whole look (2, 3) is shown to the user before it becomes the default.
