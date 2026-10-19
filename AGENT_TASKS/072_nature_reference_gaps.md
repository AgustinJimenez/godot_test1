# 072 - What the "realistic 3D nature" references have that the planet lacks

Seen 2026-10-19 on a Google Images search for "realistic 3d nature" (four views kept privately in
`E:\Temp\claude\refs\`, not in the repo: they are stock and marketplace renders, not ours to ship).
Plan by what they all share, in the order it would show most. Planet only (the flat world is retired,
see the memory note).

1. **Density of plants.** Every picture is layered: ground cover and ferns in front, shrubs and trunks in
   the middle, canopy and far trees behind, with fallen logs and mossy rocks. Ours has plants off by
   default. Do first: plants ON by default, the cost measured (they were "for later").
2. **Light through the air.** Low warm sun, soft shafts between trunks, a pale haze that thickens with
   distance and lifts the dark forest floor. Done in part (shafts, haze, thinner base fog); missing: shafts
   that react to the canopy (needs the trees), a lift of the shadows by the sky (more ambient bounce, maybe
   SDFGI once it stops resetting the GPU).
3. **Surfaces.** Moss on the north side and on stones, leaf litter, wet dark soil, pebbles at the edges of
   water. Done: generated rock/soil/sand normals, pebbles. Missing: moss and leaf-litter layers by
   moisture and slope; a wet band at the shore.
4. **Water edges.** Calm lakes mirroring trees and sky, a clear shoreline with reeds and grass leaning
   into the water, rocks at the edge, a soft transition from shallow to deep. Ours: sea and river
   shaders exist, no shoreline plants, no reflection of the land (only the sky).
5. **Rocks.** Big mossy boulders, layered cliffs, stones in streams. Ours: six low-poly rock shapes and
   spires; no moss, no variety of scale, no stones in water.
6. **Sky mood.** Layered clouds with lit edges, warm sunsets. Ours has the volume clouds; the sunset
   colours need a look at low sun with clouds.
7. **Colour grade.** Slight warm-green grade, strong depth contrast. Ours has natural/vivid/filmic grades.

First step proposed: plants on by default, measure the frame cost on a game-size planet, then ground
cover (moss and litter by moisture) and the shoreline.
