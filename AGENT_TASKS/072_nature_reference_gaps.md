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

## Side by side with our own pictures (2026-10-19)

Compared the references (a lit lake valley at sunset with a flower meadow, a misty path through a forest,
a mossy boulder in a dark glade, a grassy lake edge, a mountain with a lit cabin) with our latest pictures:
the snow forest with plants (Ultra), the desert start of a game-size planet, the open sea, the clear-day
horizon. What separates them, in the order the eye catches it:

A. **Everything in front is simple.** References: the first 5 m are full of different small things (ferns,
   flowers, stones, leaves, roots, moss), each a different colour. Ours: a dozen grass clumps and a few
   pebbles on a flat colour. Needs: more kinds of ground cover (flowers in patches, ferns, moss and leaf
   litter by moisture), clumped not evenly spread, with colour variety.
B. **Light has direction and mood.** References: a low sun with long shadows, rim light on leaves, warm
   light against cool shade, dark foreground against bright distance. Ours: flat even daylight, shadows
   the same blue everywhere. Needs: warm sun / cool shadow split, a lower default sun hour or a golden
   hour on start, stronger contrast in the grade, rim light (sun through leaves: translucent leaves).
C. **Depth haze.** References: 4-5 clear planes of mountains, each paler and bluer; light mist in the
   valleys. Ours (after the thinner fog): good but the colour of the haze is green-teal in the middle
   distance, where it should go blue-grey and warm toward the sun. Needs: fog colour from the sky colour
   in that direction (sun side warm, far side blue), valley mist in low wet ground at dawn.
D. **Water reflects the world.** References: the lake mirrors trees, mountains and the sunset glow. Ours:
   reflects the sky only. Needs: planar reflection or SSR on water (SSR is a setting: check it on water),
   a visible shore line with reeds and wet sand.
E. **Terrain has strong large forms with texture variety.** References: cliffs with strata, scree,
   boulders on slopes, ground that changes colour in patches (rock, grass, soil, flowers). Ours: smooth hills,
   one or two ground colours per region. Needs: slope-based rock outcrops (thermal erosion), patchy
   ground colour by noise inside a biome.
F. **Trees are varied and leafy.** References: broad canopies, branches, different species and ages,
   fallen trunks. Ours: low-poly spiky conifers, same silhouette. Needs: more tree shapes (broadleaf,
   dead trees, saplings), leaf cards with translucency, wind motion (exists in the shader).
G. **Sky and clouds.** References: tall cumulus with dark bases and bright edges, sunset gradients. Ours:
   flat layers, white. Needs: taller billows, darker undersides, a sunset sky colour check.
H. **Atmosphere particles.** References: pollen, dust and small insects in the sunbeams, falling leaves.
   Ours: none. Needs: a particle system near the player (GPUParticles) for dust and pollen in shafts.

Not a gap but worth keeping: our haze, sun glare, sea sheen, ground texture detail and footprints are
already in the same family as the references at this distance; what is missing is mostly *quantity and
variety of near things* (A, E, F) and *light mood* (B, C).

### Order proposed
1. B+C first (cheap, shows everywhere): sun/shade colour split, golden-hour default, haze colour toward the
   sun and blue-grey far; contrast in the default grade.
2. A: ground cover variety + plants on by default (measure cost).
3. D: water reflection and shoreline.
4. E, F, G, H as separate items.

## Loop log (overnight 2026-10-19)

1. **Ozone** in the air model (sky shader + `PlanetAir`): the horizon and the far hills go blue instead
   of green-teal; the sunset has a warm band. Seen at noon and 17:54 on seed 8.
2. **Plant cover colour** on the ground (`PlanetRock.colour` and the native twin, native check passes,
   colour gap 0.0105): dry grass, grass and the dark of forest floor by rain and warmth, none on steep
   rock, desert or cold. Before this the land of seed 8 was grey-beige everywhere (0 of ~3800 land
   samples green); now 839 are and the wettest places read as meadows with darker patches and blue-green
   hills in the haze (`-0.60402,-0.07923,0.79302` and `-0.79710,-0.54198,0.26625` on seed 8).
3. **Meadow variety in the ground shader** (`planet_ground.gdshader`, near the player, Fine detail and up):
   patches of yellowing grass, darker clumps, and flowers (white, yellow, purple) as round dots in
   drifts (3D cells, so they stay round on slopes). Flowers are still small and sparse at a distance:
   real flower meshes belong to task 3 (plants).
4. **Warm / cool haze split** (`environment.fog_sun_scatter`, 0.55 on a clear day): toward a low sun the
   haze takes the sun's colour and gives long warm layers; away from it it stays blue-green. Noon looks
   as before (checked at 12:30). Seen on the green hills of seed 8 at 8:00.
5. **Water mirrors the land** (`mirror_of_the_land` in `planet_water.gdshader`: a 28-step screen-space
   march along the reflected ray, blended by a Fresnel term; only within 6 km, only in realistic mode).
   It compiles and the open sea is unchanged; NOT yet seen working: no view of land across water was
   found (the lab's coast of seed 8 is a flat mud plain, and scans for an island timed out). Check it
   on a lake or fjord when one is found (`--sea --water` and a camera 3-10 m over the water).
6. **Morning mist** (`PlanetAtmosphere.mist_wanted`, set by the world from the humidity, the local hour
   3.5-10 and the height under 250 m): adds up to 0.0028 of fog in wet low ground at dawn, eased in. Noon
   is unchanged. Not yet looked at in a wet lowland at dawn (the greenest test place is 330 m up).
7. **Dawn fill light**: the ambient light lifts by up to 1.6 when the sun is low, so the shadowed side
   of the land is dark green and not black. Seen at 6:12 on seed 8.
8. **Dust and pollen** (`PlanetMotes`, setting `particles`, High and Ultra): 700 tiny warm specks in a box of
   air that follows the camera, in world space, drifting on a noise; only in daylight, fair weather and
   under 2.5 km, not underwater. Seen as a few faint specks in a still at 8:20; their motion and amount
   need a look in play (the lab's `--view-alt` views have no player, so they do not show there).
